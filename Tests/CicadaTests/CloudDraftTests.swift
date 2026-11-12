@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import Cicada

/// `CloudStream`'s drafts: the stretch being said, heard as it grows by the user's own speech
/// server, shown until the line's final takes its place.
@MainActor struct CloudDraftTests {
    private static let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

    private func tone(_ seconds: Double) -> [Int16] {
        (0..<Int(seconds * 16000)).map { i in
            let env = 0.55 + 0.45 * sin(2 * .pi * 4 * Double(i) / 16000)
            return Int16(sin(2 * .pi * 300 * Double(i) / 16000) * env * 0.3 * 32767)
        }
    }

    private func silence(_ seconds: Double) -> [Int16] { Array(repeating: 0, count: Int(seconds * 16000)) }

    /// The app's sample meeting at 16 kHz: speech that `SoundKind` lets through.
    private func sample() throws -> [Int16] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/sample/sample.m4a")
        let file = try AVAudioFile(forReading: url)
        let source = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: source)
        let converter = try #require(AVAudioConverter(from: file.processingFormat, to: Self.format))
        let frames = AVAudioFrameCount(Double(file.length) * 16000 / file.processingFormat.sampleRate) + 1600
        let out = try #require(AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: frames))
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return source
        }
        try #require(error == nil && out.frameLength > 16000)
        return Array(UnsafeBufferPointer(start: out.int16ChannelData![0], count: Int(out.frameLength)))
    }

    /// In 0.1 s buffers, as the audio router hands them over.
    private func feed(_ stream: CloudStream, _ samples: [Int16]) {
        var i = 0
        while i < samples.count {
            let n = min(1600, samples.count - i)
            let buffer = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: AVAudioFrameCount(n))!
            buffer.frameLength = AVAudioFrameCount(n)
            samples.withUnsafeBufferPointer { buffer.int16ChannelData![0].update(from: $0.baseAddress! + i, count: n) }
            stream.append(buffer)
            i += n
        }
    }

    /// What the stream gave out, as it comes.
    private final class Seen {
        var pieces: [Recognition.Piece] = []
        var drafts: [Double] = []
    }

    private func collect(_ stream: CloudStream, into seen: Seen) -> Task<Void, Never> {
        Task { @MainActor in
            do { for try await piece in stream.results { seen.pieces.append(piece) } } catch {}
        }
    }

    private func wait(_ what: @MainActor () -> Bool) async {
        for _ in 0..<300 where !what() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func theLineBeingSaidShowsAsADraftThatGrows() async {
        let seen = Seen()
        let stream = CloudStream(draft: { _, seconds in
            seen.drafts.append(seconds)
            return "draft \(seen.drafts.count)"
        }) { _, _ in nil }
        let reading = collect(stream, into: seen)
        // Nothing while nobody speaks, nor in the first moments of a line.
        feed(stream, silence(0.5) + tone(0.6))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(seen.drafts.isEmpty && seen.pieces.isEmpty)
        // A second in: the first draft, of everything said so far.
        feed(stream, tone(0.6))
        await wait { seen.pieces.count == 1 }
        #expect(seen.pieces.first?.text == "draft 1" && seen.pieces.first?.isFinal == false)
        #expect((1.0...1.5).contains(seen.drafts.first ?? 0))
        // One more second of the same line: the next draft hears the whole line again.
        feed(stream, tone(1.0))
        await wait { seen.pieces.count == 2 }
        #expect(seen.pieces.last?.text == "draft 2" && seen.drafts.count == 2)
        #expect((seen.drafts.last ?? 0) - (seen.drafts.first ?? 0) >= 0.9)
        // The line ends without words (a tone is no speech; the service heard nothing either):
        // the draft is taken down, since no final will replace it.
        feed(stream, silence(1.0))
        await wait { seen.pieces.count == 3 }
        #expect(seen.pieces.last?.text == "" && seen.pieces.last?.isFinal == false)
        #expect(seen.drafts.count == 2)
        await stream.cancel()
        reading.cancel()
    }

    @Test func theFinalTakesTheDraftsPlace() async throws {
        let seen = Seen()
        let speech = try sample()
        let stream = CloudStream(draft: { _, seconds in
            seen.drafts.append(seconds)
            return "so far"
        }) { _, _ in CloudHeard(lang: "en", original: "The whole line.", translation: nil) }
        let reading = collect(stream, into: seen)
        feed(stream, Array(speech.prefix(20800)))
        await wait { !seen.pieces.isEmpty }
        #expect(seen.pieces.first?.text == "so far" && seen.pieces.first?.isFinal == false)
        feed(stream, Array(speech.dropFirst(20800)) + silence(1.0))
        await stream.finish()
        await reading.value
        let finals = seen.pieces.filter(\.isFinal)
        #expect(!finals.isEmpty && finals.allSatisfy { $0.text == "The whole line." })
        // A final clears its own draft: nothing is taken down by an empty one, and nothing follows it.
        #expect(!seen.pieces.contains { $0.text.isEmpty })
        #expect(seen.pieces.last?.isFinal == true)
    }

    @Test func aDraftThatComesBackAfterTheLineEndedIsDropped() async throws {
        let seen = Seen()
        let speech = try sample()
        let stream = CloudStream(draft: { _, seconds in
            seen.drafts.append(seconds)
            // Slower than the rest of the line takes to arrive.
            try? await Task.sleep(for: .milliseconds(300))
            return "late"
        }) { _, _ in CloudHeard(lang: "en", original: "The whole line.", translation: nil) }
        let reading = collect(stream, into: seen)
        feed(stream, speech + silence(1.0))
        await stream.finish()
        await reading.value
        #expect(!seen.drafts.isEmpty)
        #expect(!seen.pieces.isEmpty && seen.pieces.allSatisfy(\.isFinal))
    }

    @Test func withoutASpeechServerThereAreNoDrafts() async {
        let seen = Seen()
        let stream = CloudStream { _, _ in nil }
        let reading = collect(stream, into: seen)
        feed(stream, silence(0.5) + tone(2.5))
        try? await Task.sleep(for: .milliseconds(150))
        #expect(seen.pieces.isEmpty)
        await stream.cancel()
        reading.cancel()
    }

    @Test func theOpenStretchIsNumberedAndMeasured() {
        var seg = CloudSegmenter()
        #expect(seg.open == nil && seg.serial == 0)
        seg.feed(silence(0.5) + tone(1.5)) { _ in }
        let open = seg.open
        #expect(open?.serial == 0 && (1.5...1.7).contains(open?.seconds ?? 0))
        #expect((1.4...1.6).contains(open?.spoken ?? 0) && open?.quiet == 0 && open?.steady == false)
        #expect(seg.openSamples.count == Int((open?.seconds ?? 0) * 16000))
        seg.feed(silence(0.3)) { _ in }
        #expect((0.27...0.33).contains(seg.open?.quiet ?? 0))
        var pieces: [CloudSegmenter.Piece] = []
        seg.feed(silence(0.5)) { pieces.append($0) }
        #expect(pieces.map(\.serial) == [0] && seg.open == nil && seg.serial == 1)
        seg.feed(tone(1.0)) { _ in }
        #expect(seg.open?.serial == 1)
    }
}
