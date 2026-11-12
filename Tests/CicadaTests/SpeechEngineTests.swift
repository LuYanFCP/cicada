import CryptoKit
import Foundation
import Testing
@testable import Cicada

/// Serves a model's files as Hugging Face would, honouring `Range`, from `files`.
final class FakeHub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var files: [String: Data] = [:]
    nonisolated(unsafe) static var ranges: [String] = []
    nonisolated(unsafe) static var hosts: [String] = []
    /// Hosts that can't be reached from here.
    nonisolated(unsafe) static var down: Set<String> = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        Self.hosts.append(url.host ?? "")
        if Self.down.contains(url.host ?? "") {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        guard let whole = Self.files[url.lastPathComponent] else {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        var body = whole
        var code = 200
        if let range = request.value(forHTTPHeaderField: "Range"), let from = Int(range.dropFirst(6).dropLast()) {
            Self.ranges.append(range)
            body = whole.dropFirst(from)
            code = 206
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor @Suite(.serialized) struct SpeechEngineTests {
    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// A small model with the same shape as the real ones.
    private func tiny(_ contents: [String: Data]) -> EngineModel {
        EngineModel(id: "tiny", name: "Tiny", repo: "someone/Tiny-ASR", revision: String(repeating: "a", count: 40),
                    files: contents.keys.sorted().map { .init(path: $0, size: Int64(contents[$0]!.count), sha256: sha(contents[$0]!)) })
    }

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func download(_ model: EngineModel, into folder: URL) -> ModelDownload {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeHub.self]
        return ModelDownload(model: model, into: folder, session: config) { _ in }
    }

    @Test func modelsArePinnedToACommitAndEveryFileToItsHash() {
        #expect(EngineModel.all.count == 2 && EngineModel.named("nothing").id == EngineModel.all[0].id)
        for model in EngineModel.all {
            #expect(model.revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil)
            #expect(model.files.count == 9 && Set(model.files.map(\.path)).count == 9)
            for file in model.files {
                #expect(file.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil && file.size > 0)
            }
        }
        let big = EngineModel.all[0]
        #expect(big.served == "Qwen3-ASR-1.7B-8bit" && big.bytes > 2_400_000_000 && big.bytes < 2_600_000_000)
        #expect(big.url(big.files[0], host: "huggingface.co").absoluteString
                == "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/\(big.revision)/chat_template.json")
    }

    /// Cicada's own download first; else the same commit in Hugging Face's cache, where
    /// mlx-audio's server left it (its files are links into `blobs`).
    @Test func aModelIsFoundInCicadasFolderOrHuggingFacesCache() throws {
        let model = tiny(["config.json": Data("{}".utf8), "model.safetensors": Data(repeating: 7, count: 300)])
        let own = try scratch(), home = try scratch()
        #expect(model.folder(own: own, home: home) == nil)

        let cache = home.appendingPathComponent(".cache/huggingface/hub/models--someone--Tiny-ASR")
        let snapshot = cache.appendingPathComponent("snapshots/\(model.revision)")
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache.appendingPathComponent("blobs"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: snapshot.appendingPathComponent("config.json"))
        let blob = cache.appendingPathComponent("blobs/weights")
        try Data(repeating: 7, count: 200).write(to: blob)
        try FileManager.default.createSymbolicLink(at: snapshot.appendingPathComponent("model.safetensors"), withDestinationURL: blob)
        // Cut short: not a model yet.
        #expect(model.folder(own: own, home: home) == nil)
        try Data(repeating: 7, count: 300).write(to: blob)
        #expect(model.folder(own: own, home: home)?.path == snapshot.path)

        let mine = own.appendingPathComponent("Tiny-ASR")
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        for file in model.files { try Data(repeating: 7, count: Int(file.size)).write(to: mine.appendingPathComponent(file.path)) }
        #expect(model.folder(own: own, home: home)?.path == mine.path)
    }

    @Test func theServersFirstLineSaysReadyOrWhyNot() {
        let ready = SpeechEngine.event(fromLine: #"{"event":"ready","host":"127.0.0.1","port":50123,"model_name":"m","server_pid":9}"#)
        #expect(ready?.name == "ready" && ready?.reason == nil)
        let failed = SpeechEngine.event(fromLine: #"{"event":"failed","reason":"cannot listen on 127.0.0.1:50123"}"#)
        #expect(failed?.name == "failed" && failed?.reason?.contains("cannot listen") == true)
        #expect(SpeechEngine.event(fromLine: "loading weights") == nil && SpeechEngine.event(fromLine: "{}") == nil)
        let port = SpeechEngine.freePort()
        #expect(port > 1024 && port < 65536)
    }

    /// Without the model nothing is asked of the engine: this Mac's own recognition hears the meeting.
    @Test func theEnginesAddressIsLoopbackAndNeedsTheModelOnDisk() {
        let engine = SpeechEngine()
        let missing = tiny(["config.json": Data("{}".utf8)])
        let c = engine.config(missing)
        #expect(c.builtIn && c.hearBase?.absoluteString == "http://127.0.0.1:\(engine.port)/v1/" && c.hearModel == nil && !c.transcribes)
        #expect(!engine.installed(missing) && !engine.owns(missing) && !engine.running)
    }

    @Test func aDownloadIsCheckedAgainstItsHashAndGoesOnWhereItStopped() async throws {
        let weights = Data((0..<5000).map { UInt8($0 % 251) })
        let contents = ["config.json": Data(#"{"a":1}"#.utf8), "model.safetensors": weights]
        let model = tiny(contents)
        let folder = try scratch()
        FakeHub.files = contents
        FakeHub.ranges = []
        FakeHub.hosts = []
        FakeHub.down = []

        // Cut off after 2000 bytes last time: only the rest is asked for.
        let part = folder.appendingPathComponent("Tiny-ASR.part")
        try FileManager.default.createDirectory(at: part, withIntermediateDirectories: true)
        try weights.prefix(2000).write(to: part.appendingPathComponent("model.safetensors"))
        try await download(model, into: folder).run()
        #expect(FakeHub.ranges == ["bytes=2000-"])
        let final = folder.appendingPathComponent("Tiny-ASR")
        #expect(model.complete(in: final) && !FileManager.default.fileExists(atPath: part.path))
        #expect(try Data(contentsOf: final.appendingPathComponent("model.safetensors")) == weights)
        #expect(FakeHub.hosts.allSatisfy { $0 == "huggingface.co" })

        // Something else under that name: not kept, and not installed.
        try FileManager.default.removeItem(at: final)
        FakeHub.files["model.safetensors"] = Data(repeating: 1, count: 5000)
        await #expect(throws: ModelDownload.Failure.corrupt) { try await self.download(model, into: folder).run() }
        #expect(!FileManager.default.fileExists(atPath: final.path))
        #expect(!FileManager.default.fileExists(atPath: part.appendingPathComponent("model.safetensors").path))

        // Hugging Face out of reach: the mirror, held to the same hashes.
        FakeHub.files = contents
        FakeHub.hosts = []
        FakeHub.down = ["huggingface.co"]
        try await download(model, into: folder).run()
        #expect(model.complete(in: final) && FakeHub.hosts.contains("hf-mirror.com"))
        FakeHub.down = []
    }
}
