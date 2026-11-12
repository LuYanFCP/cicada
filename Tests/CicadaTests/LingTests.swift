import Foundation
import Testing
@testable import Cicada

/// Answers Ling requests from the test, and keeps what was asked. Requests reach a URLProtocol
/// with the body as a stream, not `httpBody`.
final class LingStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var reply: (Int, String) = (200, "")
    nonisolated(unsafe) static var seen: [(at: Date, body: [String: Any], url: URL?, authorization: String?, method: String?)] = []
    /// Each request's body as sent (a multipart upload isn't JSON).
    nonisolated(unsafe) static var raw: [Data] = []
    /// Answers each request by what it asked, instead of `reply`.
    nonisolated(unsafe) static var respond: (([String: Any]) -> (Int, String))?
    private static let lock = NSLock()

    static func reset(_ status: Int = 200, _ body: String) {
        lock.withLock { reply = (status, body); seen = []; raw = []; respond = nil }
    }

    static func chatReply(_ text: String, finish: String? = "stop") -> String {
        var choice: [String: Any] = ["message": ["content": text]]
        if let finish { choice["finish_reason"] = finish }
        return String(data: try! JSONSerialization.data(withJSONObject: ["choices": [choice]]), encoding: .utf8)!
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var data = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            stream.close()
        }
        let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let (status, text) = Self.lock.withLock {
            Self.seen.append((Date(), body, request.url, request.value(forHTTPHeaderField: "Authorization"), request.httpMethod))
            Self.raw.append(data)
            return Self.respond?(body) ?? Self.reply
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// The key file and the Ling client share `AIKey`'s state, so these run one at a time in a temp folder.
@MainActor @Suite(.serialized) struct LingTests {
    let folder: URL

    init() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-key-\(UUID().uuidString)")
        AIKey.folderOverride = folder
    }

    private func client() -> LingClient {
        AIKey.save("sk-test-0000000000")
        let ling = LingClient()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LingStub.self]
        ling.session = URLSession(configuration: config)
        return ling
    }

    // MARK: Custom service

    private func customClient() -> LingClient {
        let ling = client()
        ling.config = { AIConfig(provider: .custom, base: URL(string: "http://localhost:9/v1/"), textModel: "m") }
        return ling
    }

    private func sentenceClient(checksJSON: Bool = false) -> LingClient {
        let sentence = LingClient(keyNamespace: "sentence", checksJSON: checksJSON)
        sentence.config = {
            AIConfig(provider: .custom, base: URL(string: "https://translation.example.com/v1/"), textModel: "sentence-model")
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LingStub.self]
        sentence.session = URLSession(configuration: config)
        return sentence
    }

    private func audioClient(format: AudioInputFormat = .openai) -> LingClient {
        let audio = LingClient(keyNamespace: "audio", checksJSON: false, checksAudio: true)
        audio.config = { AIConfig.audio(base: "https://audio.example.com/v1", model: "omni-model", format: format) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LingStub.self]
        audio.session = URLSession(configuration: config)
        return audio
    }

    @Test func audioUnderstandingKeepsItsKeySeparateFromTextAndMing() async throws {
        let ming = client()
        AIKey.save("sk-text-service", "sentence-custom")
        AIKey.save("sk-other-custom", "custom")
        let audio = audioClient()
        #expect(audio.key == nil)
        LingStub.reset(200, LingStub.chatReply("OK"))
        await audio.setKey("  sk-audio-only\n")
        #expect(audio.key == "sk-audio-only")
        #expect(ming.key == "sk-test-0000000000")
        #expect(AIKey.read("sentence-custom") == "sk-text-service" && AIKey.read("custom") == "sk-other-custom")
        let file = folder.appendingPathComponent("ai-key-audio-custom")
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
        audio.config = { AIConfig.audio(base: "https://api.openai.com/v1", model: "gpt-audio", format: .openai) }
        #expect(audio.key == nil)
        await audio.setKey("sk-openai-audio")
        #expect(AIKey.read("audio-openai") == "sk-openai-audio" && AIKey.read("audio-custom") == "sk-audio-only")
        audio.removeKey()
        #expect(audio.key == nil && AIKey.read("audio-custom") == "sk-audio-only")
        #expect(ming.key == "sk-test-0000000000" && AIKey.read("sentence-custom") == "sk-text-service")
    }

    @Test(arguments: [AudioInputFormat.openai, .ming])
    func audioMessagesUseTheSelectedWireFormat(_ format: AudioInputFormat) async throws {
        let audio = audioClient(format: format)
        AIKey.save("sk-audio-only", "audio-custom")
        let wav = CloudHearing.wav(Array(repeating: 0, count: 16000))
        LingStub.reset(200, LingStub.chatReply("Heard."))
        _ = try await audio.chat(content: "Interpret the audio.", instruction: "Reply.", priority: .speak, audio: wav)
        let request = try #require(LingStub.seen.first)
        #expect(request.body["model"] as? String == "omni-model")
        #expect(request.url?.absoluteString == "https://audio.example.com/v1/chat/completions")
        #expect(request.authorization == "Bearer sk-audio-only")
        let messages = try #require(request.body["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "system")
        #expect(messages.first?["content"] as? String == "Interpret the audio.")
        let content = try #require(messages.last?["content"] as? [[String: Any]])
        #expect(content.contains { $0["type"] as? String == "text" && $0["text"] as? String == "Reply." })
        switch format {
        case .openai:
            let part = try #require(content.first { $0["type"] as? String == "input_audio" })
            let input = try #require(part["input_audio"] as? [String: String])
            #expect(input["data"] == wav.base64EncodedString() && input["format"] == "wav")
            #expect(!content.contains { $0["type"] as? String == "audio_url" })
        case .ming:
            let part = try #require(content.first { $0["type"] as? String == "audio_url" })
            let input = try #require(part["audio_url"] as? [String: String])
            #expect(input["url"] == "data:audio/wav;base64," + wav.base64EncodedString())
            #expect(!content.contains { $0["type"] as? String == "input_audio" })
        }
    }

    @Test func checkingAnAudioModelActuallySendsOneSecondOfAudio() async throws {
        let audio = audioClient()
        AIKey.save("sk-audio-only", "audio-custom")
        LingStub.reset(200, LingStub.chatReply("OK"))
        await audio.check()
        #expect(audio.aiCheck.passed && !audio.aiCheck.running)
        let request = try #require(LingStub.seen.first { $0.body["model"] as? String == "omni-model" })
        let messages = try #require(request.body["messages"] as? [[String: Any]])
        let content = try #require(messages.last?["content"] as? [[String: Any]])
        let part = try #require(content.first { $0["type"] as? String == "input_audio" })
        let input = try #require(part["input_audio"] as? [String: String])
        let wav = try #require(input["data"].flatMap { Data(base64Encoded: $0) })
        #expect(input["format"] == "wav" && wav.count == 32044)
        #expect(wav.prefix(4) == Data("RIFF".utf8))
        #expect(request.url?.host == "audio.example.com" && request.authorization == "Bearer sk-audio-only")
        #expect(request.body["response_format"] == nil)
    }

    @Test func aRejectedAudioReplyEndsTheCheckAndCanBeRetried() async {
        let audio = audioClient()
        AIKey.save("sk-audio-only", "audio-custom")
        LingStub.reset(200, LingStub.chatReply("根据现有检索证据，未找到相关结果。"))
        await audio.check()
        #expect(!audio.aiCheck.running && audio.aiCheck.failure?.reason == .noJSON)
        #expect(audio.aiCheck.hear?.ok == false && audio.keyState != .checking)

        LingStub.reset(200, LingStub.chatReply("OK"))
        await audio.check()
        #expect(!audio.aiCheck.running && audio.aiCheck.passed && audio.aiCheck.hear?.ok == true)
    }

    @Test func browsingAnUnsavedAudioEndpointKeepsTheActiveRouteAndCredentials() async throws {
        let audio = audioClient()
        AIKey.save("sk-active-audio", "audio-custom")
        LingStub.reset(200, LingStub.chatReply("OK"))
        await audio.check()
        LingStub.reset(200, #"{"data":[{"id":"active-omni","input_modalities":["audio"],"output_modalities":["text"]}]}"#)
        await audio.fetchCatalog()
        let active = audio.config()
        let state = audio.keyState
        let check = audio.aiCheck
        let catalog = audio.catalog
        #expect(check.passed && catalog == ["active-omni"])
        let keyFile = folder.appendingPathComponent("ai-key-audio-custom")
        let persistedKey = try Data(contentsOf: keyFile)
        let draft = AIConfig.audio(base: "https://draft.example.com/v1", model: "", format: .openai)

        LingStub.reset(200, #"{"data":[{"id":"draft-omni","input_modalities":["audio"],"output_modalities":["text"]},{"id":"draft-tts"}]}"#)
        #expect(try await audio.availableAudioModels(for: draft, key: "  sk-unsaved-draft\n") == ["draft-omni"])
        let request = try #require(LingStub.seen.first)
        #expect(request.method == "GET" && request.url?.absoluteString == "https://draft.example.com/v1/models")
        #expect(request.authorization == "Bearer sk-unsaved-draft" && request.body.isEmpty)
        #expect(audio.config() == active && audio.catalog == catalog && audio.keyState == state && audio.aiCheck == check)
        #expect(try Data(contentsOf: keyFile) == persistedKey)

        // Even a draft request using the active key must not invalidate the working service.
        LingStub.reset(401, "{}")
        await #expect(throws: LingClient.Failure.invalidKey) {
            try await audio.availableAudioModels(for: draft, key: "sk-active-audio")
        }
        #expect(LingStub.seen.last?.url?.host == "draft.example.com")
        #expect(audio.config() == active && audio.catalog == catalog && audio.keyState == state && audio.aiCheck == check)
        #expect(audio.key == "sk-active-audio")
        #expect(try Data(contentsOf: keyFile) == persistedKey)
    }

    @Test func browsingAnUnsavedTextEndpointFindsChatModelsWithoutSavingTheDraft() async throws {
        let text = sentenceClient(checksJSON: true)
        AIKey.save("sk-active-text", "sentence-custom")
        let active = text.config()
        let state = text.keyState
        let keyFile = folder.appendingPathComponent("ai-key-sentence-custom")
        let persistedKey = try Data(contentsOf: keyFile)
        let draft = AIConfig.sentence(base: "https://draft-text.example.com/v1", model: "")
        LingStub.reset(200, #"{"data":[{"id":"chat-model","output_modalities":["text"]},{"id":"voice-tts","output_modalities":["audio"]},{"id":"text-embedding-3-small"}]}"#)
        #expect(try await text.availableTextModels(for: draft, key: "  sk-unsaved-text\n") == ["chat-model"])
        let request = try #require(LingStub.seen.first)
        #expect(request.method == "GET" && request.url?.absoluteString == "https://draft-text.example.com/v1/models")
        #expect(request.authorization == "Bearer sk-unsaved-text" && request.body.isEmpty)
        #expect(text.config() == active && text.key == "sk-active-text" && text.keyState == state)
        #expect(text.catalog.isEmpty)
        #expect(try Data(contentsOf: keyFile) == persistedKey)
    }

    @Test func configuredAudioHearsAndInterpretsWhileMingStillGeneratesTheVoice() async throws {
        let ming = client()
        let audio = audioClient()
        AIKey.save("sk-audio-only", "audio-custom")
        let transcript = "LANG: zh-CN\nORIGINAL: 我们周五发布。\nTRANSLATION: We ship on Friday."
        LingStub.reset(200, "")
        LingStub.respond = { body in
            body["model"] as? String == "Ming-3.0-tts-0.5B" ? (200, "0123456789") : (200, LingStub.chatReply(transcript))
        }
        let translator = TranslationService(ling: ming)
        translator.audioClient = { audio }
        let wav = CloudHearing.wav(Array(repeating: 0, count: 16000))
        let interpretation = await translator.interpret(wav: wav, source: "zh-CN", target: "en", trace: TranslateTrace())
        #expect(interpretation?.original == "我们周五发布。" && interpretation?.translation == "We ship on Friday.")
        let heard = try await translator.hear(wav: wav, seconds: 1, target: "en", hint: "zh-CN")
        #expect(heard?.lang == "zh-CN" && heard?.translation == "We ship on Friday.")
        var chunks = 0
        for try await _ in ming.speech("We ship on Friday.") { chunks += 1 }
        #expect(chunks == 1)
        translator.audioClient = { nil }
        _ = await translator.interpret(wav: wav, source: "zh-CN", target: "en", trace: TranslateTrace())
        #expect(LingStub.seen.compactMap { $0.body["model"] as? String } == ["omni-model", "omni-model", "Ming-3.0-tts-0.5B", "Ming-3.0-audio-flash"])
        #expect(LingStub.seen.compactMap { $0.url?.host } == ["audio.example.com", "audio.example.com", "api.ant-ling.com", "api.ant-ling.com"])
        #expect(LingStub.seen.compactMap(\.authorization) == ["Bearer sk-audio-only", "Bearer sk-audio-only", "Bearer sk-test-0000000000", "Bearer sk-test-0000000000"])
    }

    @Test func sentenceKeysStaySeparateFromLingAndOtherCustomServices() async throws {
        AIKey.save("sk-original-ling")
        AIKey.save("sk-original-custom", "custom")
        LingStub.reset(200, LingStub.chatReply("我们周五发布。"))
        let sentence = sentenceClient()
        #expect(sentence.key == nil)
        await sentence.setKey("  sk-sentence-only\n")
        #expect(sentence.key == "sk-sentence-only")
        #expect(AIKey.read() == "sk-original-ling")
        #expect(AIKey.read("custom") == "sk-original-custom")
        let file = folder.appendingPathComponent("ai-key-sentence-custom")
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
        #expect(try String(contentsOf: file, encoding: .utf8) == "sk-sentence-only")
        sentence.config = { AIConfig.sentence(base: "https://api.openai.com/v1", model: "gpt-5.4-nano") }
        #expect(sentence.key == nil)
        await sentence.setKey("sk-openai-sentence")
        #expect(AIKey.read("sentence-openai") == "sk-openai-sentence")
        #expect(AIKey.read("sentence-custom") == "sk-sentence-only")
        sentence.config = {
            AIConfig(provider: .custom, base: URL(string: "https://translation.example.com/v1/"), textModel: "sentence-model")
        }
        sentence.removeKey()
        #expect(sentence.key == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(AIKey.read("sentence-openai") == "sk-openai-sentence")
        #expect(AIKey.read() == "sk-original-ling" && AIKey.read("custom") == "sk-original-custom")
    }

    /// "用翻译和纪要的地址和 key": the audio row reads the text row's key for the same address and
    /// saves its own copy; neither row ever sees the other's key on its own.
    @Test func audioCanTakeTheTextKeyForTheSameAddressOnlyWhenAsked() async throws {
        let sentence = sentenceClient()
        AIKey.save("sk-shared-gateway", "sentence-custom")
        let audio = audioClient()
        let same = AIConfig.audio(base: "https://translation.example.com/v1", model: "omni-model", format: .openai)
        #expect(audio.storedKey(for: same) == nil && !audio.hasStoredKey(for: same))
        let text = AIConfig.sentence(base: "https://translation.example.com/v1", model: "sentence-model")
        let copied = try #require(sentence.storedKey(for: text))
        #expect(audio.saveKey(copied, for: same))
        #expect(audio.storedKey(for: same) == "sk-shared-gateway" && AIKey.read("audio-custom") == "sk-shared-gateway")
        // Each keeps its own file: removing one leaves the other.
        audio.removeKey()
        #expect(AIKey.read("audio-custom") == nil && sentence.key == "sk-shared-gateway")
        sentence.hideKey = true
        #expect(sentence.storedKey(for: text) == nil)
    }

    private func speechClient(base: String = "http://localhost:8000/v1") -> LingClient {
        let speech = LingClient(keyNamespace: "asr", checksJSON: false, checksTranscription: true)
        speech.config = { AIConfig.speech(base: base, model: "mlx-community/Qwen3-ASR-1.7B-8bit") }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LingStub.self]
        speech.session = URLSession(configuration: config)
        return speech
    }

    /// Qwen3-ASR through mlx-audio on this Mac: the check is one second of audio to
    /// `/audio/transcriptions`, asking for JSON with the language (mlx-audio streams NDJSON
    /// otherwise), with no key.
    @Test func speechServerIsCheckedWithOneTranscriptionAskingForJSON() async throws {
        LingStub.reset(200, #"{"text":""}"#)
        let speech = speechClient()
        #expect(speech.key == "" && !speech.hearsAudio)
        await speech.check()
        let first = try #require(LingStub.seen.first)
        #expect(first.url?.absoluteString == "http://localhost:8000/v1/audio/transcriptions" && first.authorization == nil)
        let body = String(decoding: try #require(LingStub.raw.first), as: UTF8.self)
        #expect(body.contains("name=\"response_format\"\r\n\r\nverbose_json\r\n"))
        #expect(body.contains("mlx-community/Qwen3-ASR-1.7B-8bit"))
        #expect(speech.aiCheck.passed && speech.aiCheck.hear?.ok == true && speech.transcribes)
        // Meetings call it the same way and read the text back.
        LingStub.reset(200, #"{"text":" 大家好 "}"#)
        let heard = try await speech.transcribe(CloudHearing.wav(Array(repeating: 0, count: 1600)), language: nil)
        #expect(heard.text == "大家好" && heard.language == nil)
    }

    /// The language comes from the server (mlx-audio lists it, Whisper servers name it), so a
    /// French line is not taken for English; a server that takes only plain JSON still works.
    @Test func speechServerNamesTheLanguageAndFallsBackToPlainJSON() async throws {
        let speech = speechClient()
        let wav = CloudHearing.wav(Array(repeating: 0, count: 1600))
        LingStub.reset(200, #"{"text":"Bonjour à tous.","language":["French"],"segments":[]}"#)
        #expect(try await speech.transcribe(wav, language: nil).language == "French")
        LingStub.reset(200, #"{"text":"Hello.","language":"english"}"#)
        #expect(try await speech.transcribe(wav, language: nil).language == "english")
        let line = CloudHearing.transcript("Bonjour à tous.", reported: "French", hint: "en", target: "zh-CN", seconds: 2)
        #expect(line?.lang == "fr")

        // gpt-4o-transcribe answers 400 to verbose_json: asked again as json, and json from then on.
        LingStub.reset(200, "")
        LingStub.respond = { _ in
            let asked = String(decoding: LingStub.raw.last ?? Data(), as: UTF8.self)
            return asked.contains("\r\n\r\nverbose_json\r\n") ? (400, "{}") : (200, #"{"text":"Hello."}"#)
        }
        #expect(try await speech.transcribe(wav, language: nil).text == "Hello.")
        #expect(try await speech.transcribe(wav, language: nil).text == "Hello.")
        let formats = LingStub.raw.map { String(decoding: $0, as: UTF8.self).contains("verbose_json") }
        #expect(formats == [true, false, false])
        // A 400 that plain JSON gets too is the server's answer, not a format it refused.
        speech.reconfigure(check: false)
        LingStub.reset(400, "{}")
        await #expect(throws: LingClient.Failure.http(400)) { _ = try await speech.transcribe(wav, language: nil) }
        LingStub.reset(200, #"{"text":"Hello."}"#)
        _ = try await speech.transcribe(wav, language: nil)
        #expect(String(decoding: LingStub.raw.last ?? Data(), as: UTF8.self).contains("verbose_json"))
    }

    /// 语音识别 › 内置: the engine in the app is brought up first, asked for a streamed answer (the
    /// only one that names the language), and never sent the key saved for a server.
    @Test func theBuiltInEngineIsStartedFirstAndNamesTheLanguage() async throws {
        let speech = speechClient()
        #expect(speech.saveKey("sk-for-my-server", for: speech.config()))
        let base = URL(string: "http://127.0.0.1:50123/v1/")
        speech.config = { AIConfig(provider: .custom, base: base, textModel: "", hearModel: "Qwen3-ASR-1.7B-8bit", hearBase: base, builtIn: true) }
        var starts = 0
        speech.startEngine = { starts += 1 }
        #expect(speech.key == "" && speech.transcribes)
        let done = #"{"type":"transcript.text.done","text":" Bonjour à tous. ","generation_metadata":{"generated_token_count":7,"language":"French","finish_reason":"stop"}}"#
        LingStub.reset(200, ":\n\ndata: \(done)\n\ndata: [DONE]\n\n")
        let heard = try await speech.transcribe(CloudHearing.wav(Array(repeating: 0, count: 1600)), language: nil)
        #expect(heard.text == "Bonjour à tous." && heard.language == "French" && starts == 1)
        let first = try #require(LingStub.seen.first)
        #expect(first.url?.absoluteString == "http://127.0.0.1:50123/v1/audio/transcriptions" && first.authorization == nil)
        let body = String(decoding: try #require(LingStub.raw.first), as: UTF8.self)
        #expect(body.contains("name=\"stream\"\r\n\r\ntrue\r\n") && body.contains("name=\"include_generation_metadata\"\r\n\r\ntrue\r\n"))
        #expect(!body.contains("response_format"))

        // It ended on an error instead of a transcript.
        LingStub.reset(200, #"data: {"type":"error","error":{"code":"transcription_failed"}}"# + "\n\n")
        await #expect(throws: LingClient.Failure.parse) { _ = try await speech.transcribe(Data(), language: nil) }
        // It would not start: nothing is sent, and it reads as a server on this Mac that isn't running.
        LingStub.reset(200, "")
        speech.startEngine = { throw SpeechEngine.Failure.noModel }
        await #expect(throws: LingClient.Failure.network) { _ = try await speech.transcribe(Data(), language: nil) }
        #expect(LingStub.seen.isEmpty)
        speech.removeKey()
    }

    @Test func aSpeechServerWithoutTheModelOrAnsweringNDJSONSaysWhy() async throws {
        LingStub.reset(404, #"{"detail":"Model not found"}"#)
        let speech = speechClient()
        await speech.check()
        #expect(speech.aiCheck.failure?.reason == .noModel && speech.aiCheck.hear == .fail(code: 404))
        // NDJSON (a server not asked for JSON) can't be read as a transcription.
        LingStub.reset(200, "{\"text\":\"a\"}\n{\"text\":\"b\"}\n")
        await speech.check()
        #expect(speech.aiCheck.failure?.reason == .noJSON)
    }

    @Test func sentenceInterfaceDoesNotNeedTheNotesJSONMode() async throws {
        LingStub.reset(200, "")
        LingStub.respond = { body in
            body["response_format"] != nil ? (400, "{}") : (200, LingStub.chatReply("我们周五发布。"))
        }
        let sentence = sentenceClient()
        AIKey.save("sk-sentence-only", "sentence-custom")
        await sentence.check()
        #expect(sentence.aiCheck.passed && sentence.aiCheck.failure == nil)
        #expect(LingStub.seen.allSatisfy { $0.body["response_format"] == nil })
        #expect(try await sentence.chat(content: "We ship on Friday.", instruction: "Translate.", priority: .translate) == "我们周五发布。")

        // The original service still needs JSON for meeting notes.
        let original = customClient()
        await original.check()
        #expect(original.aiCheck.failure?.reason == .noJSON)
    }

    @Test func anInvalidSentenceReplyEndsTheCheckAndCanBeRetried() async {
        let sentence = sentenceClient()
        AIKey.save("sk-sentence-only", "sentence-custom")
        LingStub.reset(200, "{}")
        await sentence.check()
        #expect(!sentence.aiCheck.running)
        #expect(sentence.aiCheck.failure?.reason == .noJSON)

        LingStub.reset(200, LingStub.chatReply("我们周五发布。"))
        await sentence.check()
        #expect(!sentence.aiCheck.running && sentence.aiCheck.passed)
        #expect(sentence.aiCheck.failure == nil)
    }

    @Test func removingASentenceKeyInvalidatesAnInFlightCheck() async {
        let sentence = sentenceClient()
        AIKey.save("sk-sentence-only", "sentence-custom")
        let started = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        defer { started.continuation.finish(); release.signal() }
        LingStub.reset(200, "")
        LingStub.respond = { body in
            if body["model"] != nil {
                started.continuation.yield(())
                release.wait()
            }
            return (200, LingStub.chatReply("我们周五发布。"))
        }
        let check = Task { await sentence.check() }
        var events = started.stream.makeAsyncIterator()
        _ = await events.next()
        sentence.removeKey()
        #expect(sentence.key == nil)
        release.signal()
        await check.value
        #expect(!sentence.aiCheck.running && !sentence.aiCheck.passed)
        #expect(sentence.keyState == .none)
    }

    @Test func sentencesAndImportedLinesUseTheirOwnInterfaceWhileSpeakingKeepsLing() async {
        let ling = client()
        let sentence = sentenceClient()
        AIKey.save("sk-sentence-only", "sentence-custom")
        LingStub.reset(200, "")
        LingStub.respond = { body in
            (200, LingStub.chatReply(body["model"] as? String == "sentence-model" ? "整句译文。" : "同传译文。"))
        }
        let translator = TranslationService(ling: ling)
        translator.sentenceClient = { sentence }
        #expect(await translator.translate("A complete sentence.", source: "en", target: "zh-CN", kind: .sentence) == "整句译文。")
        #expect(await translator.translate("An imported line.", source: "en", target: "zh-CN", kind: .file) == "整句译文。")
        #expect(await translator.translate("What I said.", source: "en", target: "zh-CN", kind: .speak) == "同传译文。")
        #expect(LingStub.seen.compactMap { $0.body["model"] as? String } == ["sentence-model", "sentence-model", "Ling-3.1-flash"])
        #expect(LingStub.seen.map { $0.url?.host } == ["translation.example.com", "translation.example.com", "api.ant-ling.com"])
        #expect(LingStub.seen.map(\.authorization) == ["Bearer sk-sentence-only", "Bearer sk-sentence-only", "Bearer sk-test-0000000000"])

        translator.sentenceClient = { nil }
        #expect(await translator.translate("Follow the original service.", source: "en", target: "zh-CN", kind: .sentence) == "同传译文。")
        #expect(LingStub.seen.last?.url?.host == "api.ant-ling.com")
    }

    private func meeting(_ store: SessionStore) -> String {
        let id = store.begin().id
        store.append(TranscriptLine(id: "l1", t: 0, speaker: "them", src: "We ship on Friday.", dst: nil,
                                    srcLang: "en", dstLang: "zh-CN"))
        return id
    }

    @Test func configuredTextServiceWritesNotesWithoutALingKeyAndTranslatesTheTranscript() async {
        let original = client()
        AIKey.remove()
        let text = sentenceClient(checksJSON: true)
        AIKey.save("sk-text-service", "sentence-custom")
        LingStub.reset(200, "")
        LingStub.respond = { body in
            let reply = body["response_format"] != nil
                ? #"{"title":"发布计划","summary":"我们确认周五发布。","topics":[],"conclusions":[],"todos":[],"terms":[]}"#
                : "我们周五发布。"
            return (200, LingStub.chatReply(reply))
        }
        let store = SessionStore(root: folder.appendingPathComponent("records"))
        let id = meeting(store)
        let notes = NotesEngine(ling: original, store: store)
        notes.client = { text }
        await notes.replay(id, step: 1)
        #expect(!original.hasKey)
        #expect(notes.state == .idle && notes.notes.final && notes.notes.covered == 1)
        #expect(store.session(id)?.notes?.summary == "我们确认周五发布。")
        #expect(LingStub.seen.count == 2)
        #expect(LingStub.seen.allSatisfy { ($0.body["response_format"] as? [String: String])?["type"] == "json_object" })

        let translator = TranslationService(ling: original)
        translator.sentenceClient = { text }
        #expect(await translator.translate("We ship on Friday.", source: "en", target: "zh-CN", kind: .sentence) == "我们周五发布。")
        #expect(await translator.translate("We ship on Friday.", source: "en", target: "zh-CN", kind: .file) == "我们周五发布。")
        #expect(LingStub.seen.allSatisfy { $0.body["model"] as? String == "sentence-model" && $0.url?.host == "translation.example.com" })
        #expect(LingStub.seen.allSatisfy { $0.authorization == "Bearer sk-text-service" })
    }

    @Test func laterNotesFollowTheNewlySelectedTextService() async {
        let original = client()
        AIKey.remove()
        let first = sentenceClient(checksJSON: true)
        let second = sentenceClient(checksJSON: true)
        second.config = {
            AIConfig(provider: .custom, base: URL(string: "https://second.example.com/v1/"), textModel: "second-model")
        }
        AIKey.save("sk-text-service", "sentence-custom")
        LingStub.reset(200, "")
        LingStub.respond = { body in
            let summary = body["model"] as? String == "second-model" ? "第二个服务整理的纪要。" : "第一个服务整理的纪要。"
            return (200, LingStub.chatReply("{\"summary\":\"\(summary)\",\"topics\":[]}"))
        }
        let store = SessionStore(root: folder.appendingPathComponent("records"))
        let id = meeting(store)
        let notes = NotesEngine(ling: original, store: store)
        var selected = first
        notes.client = { selected }
        await notes.replay(id, step: 1)
        #expect(notes.notes.summary == "第一个服务整理的纪要。")
        selected = second
        await notes.replay(id, step: 1)
        #expect(notes.notes.summary == "第二个服务整理的纪要。")
        #expect(store.session(id)?.notes?.summary == "第二个服务整理的纪要。")
        #expect(LingStub.seen.compactMap { $0.body["model"] as? String } == ["sentence-model", "sentence-model", "second-model", "second-model"])
        #expect(LingStub.seen.compactMap { $0.url?.host } == ["translation.example.com", "translation.example.com", "second.example.com", "second.example.com"])
        notes.client = nil
        await notes.replay(id, step: 1)
        #expect(notes.state == .noKey && LingStub.seen.count == 4)
    }

    @Test func aTextServiceWithoutJSONCanTranslateButCannotWriteNotes() async {
        let original = client()
        AIKey.remove()
        let text = sentenceClient(checksJSON: true)
        AIKey.save("sk-text-service", "sentence-custom")
        LingStub.reset(200, "")
        LingStub.respond = { body in
            body["response_format"] != nil ? (400, "{}") : (200, LingStub.chatReply("我们周五发布。"))
        }
        await text.check()
        #expect(text.aiCheck.failure?.reason == .noJSON && !text.aiCheck.running)
        let store = SessionStore(root: folder.appendingPathComponent("records"))
        let id = meeting(store)
        let notes = NotesEngine(ling: original, store: store)
        notes.client = { text }
        await notes.replay(id, step: 1)
        #expect(notes.notes.isEmpty && store.session(id)?.notes == nil)
        #expect(notes.state == .failed)
        let translator = TranslationService(ling: original)
        translator.sentenceClient = { text }
        #expect(await translator.translate("We ship on Friday.", source: "en", target: "zh-CN", kind: .sentence) == "我们周五发布。")
        #expect(LingStub.seen.last?.body["response_format"] == nil)
        #expect(LingStub.seen.last?.url?.host == "translation.example.com")
    }

    @Test func anAddressChangedAfterQueuingCannotReceiveThePreviousServersKey() async throws {
        let sentence = sentenceClient()
        AIKey.save("sk-old-server", "sentence-custom")
        var base = URL(string: "https://old.example.com/v1/")!
        sentence.config = { AIConfig(provider: .custom, base: base, textModel: "sentence-model") }
        LingStub.reset(200, LingStub.chatReply("我们周五发布。"))
        _ = try await sentence.chat(content: "First.", instruction: "Translate.", priority: .translate)
        _ = try await sentence.chat(content: "Queued.", instruction: "Translate.", priority: .translate, onQueued: { _ in
            base = URL(string: "https://new.example.com/v1/")!
            AIKey.save("sk-new-server", "sentence-custom")
        })
        let queued = try #require(LingStub.seen.last)
        #expect(queued.url?.host == "old.example.com")
        #expect(queued.authorization == "Bearer sk-old-server")
    }

    @Test func aServerThatRefusesTemplateKwargsIsAskedWithoutThem() async throws {
        LingStub.reset(200, "")
        LingStub.respond = { body in body["chat_template_kwargs"] != nil ? (400, "{}") : (200, LingStub.chatReply("好")) }
        let ling = customClient()
        #expect(try await ling.chat(content: "x", instruction: "Translate.", priority: .translate) == "好")
        _ = try await ling.chat(content: "y", instruction: "Translate.", priority: .translate)
        let bodies = LingStub.seen.map(\.body)
        #expect(bodies.count == 3 && bodies[0]["chat_template_kwargs"] != nil && bodies[1]["chat_template_kwargs"] == nil)
        // Not sent again once refused.
        #expect(bodies[2]["chat_template_kwargs"] == nil)
    }

    @Test func aRefusalForSomethingElseKeepsThinkingOff() async throws {
        LingStub.reset(200, "")
        // No JSON mode on this server: 400 with or without the kwargs. Asked again without JSON mode.
        LingStub.respond = { body in body["response_format"] != nil ? (400, "{}") : (200, LingStub.chatReply("好")) }
        let ling = customClient()
        #expect(try await ling.chat(content: "x", instruction: "Notes.", priority: .translate, json: true) == "好")
        #expect(LingStub.seen.last?.body["response_format"] == nil && LingStub.seen.last?.body["chat_template_kwargs"] != nil)
        _ = try await ling.chat(content: "y", instruction: "Translate.", priority: .translate)
        #expect(LingStub.seen.last?.body["chat_template_kwargs"] != nil)
    }

    // MARK: Retries

    @Test func finalNotesKeepRetryingForAboutAMinute() {
        #expect(LingClient.retryWaits(.translate).isEmpty)
        #expect(LingClient.retryWaits(.speak, patient: true).isEmpty)
        #expect(LingClient.retryWaits(.notes) == [1, 2, 4])
        let patient = LingClient.retryWaits(.notes, patient: true)
        #expect(patient.count == 6)
        #expect((50...70).contains(patient.reduce(0, +)))
    }

    @Test func heardAudioRetriesAndTextFailsFast() {
        #expect(LingClient.retryWaits(.translate, audio: true) == [1, 2, 4, 8])
        #expect(LingClient.retryWaits(.speak, audio: true) == [1])
        #expect(LingClient.retryWaits(.translate, audio: false).isEmpty)
    }

    @Test func retryAfterIsSecondsOrADate() {
        #expect(LingClient.retryAfterSeconds("5") == 5)
        #expect(LingClient.retryAfterSeconds(nil) == nil)
        #expect(LingClient.retryAfterSeconds("soon") == nil)
        let now = Date(timeIntervalSince1970: 1_700_000_000)  // Tue, 14 Nov 2023 22:13:20 GMT
        #expect(LingClient.retryAfterSeconds("Tue, 14 Nov 2023 22:13:30 GMT", now: now) == 10)
    }

    @Test func heardAudioOutlastsA429AndTextFallsBackMeanwhile() async throws {
        LingStub.reset(200, "")
        var first = true
        LingStub.respond = { _ in
            if first { first = false; return (429, "{}") }
            return (200, LingStub.chatReply("ORIGINAL: hi\nTRANSLATION: 你好"))
        }
        let ling = client()
        async let heard = ling.chat(content: "x", instruction: "Hear.", priority: .translate, audio: Data([0, 1]))
        // The 429 pauses the gate: a text translation now fails at once (its caller uses Google)
        // instead of spending the pause in the queue.
        try await Task.sleep(for: .milliseconds(300))
        await #expect(throws: LingClient.Failure.rateLimited) {
            try await ling.chat(content: "y", instruction: "Translate.", priority: .translate)
        }
        let reply = try await heard
        #expect(reply.hasPrefix("ORIGINAL"))
        #expect(LingStub.seen.count == 2)
        let gap = LingStub.seen[1].at.timeIntervalSince(LingStub.seen[0].at)
        #expect(gap >= 1 && gap < 2)
        #expect(ling.rateLimitedAt == nil)
    }

    // MARK: Key file

    @Test func keyFileIsOnlyForThisUser() throws {
        #expect(AIKey.save("sk-abc1234567890"))
        let file = folder.appendingPathComponent("ling-api-key")
        let fm = FileManager.default
        #expect(try fm.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
        #expect(try fm.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int == 0o700)
        #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try String(contentsOf: file, encoding: .utf8) == "sk-abc1234567890")
    }

    @Test func keyIsNotInUserDefaults() {
        let key = "sk-not-in-defaults-\(UUID().uuidString)"
        AIKey.save(key)
        let values = UserDefaults.standard.dictionaryRepresentation().values.map { "\($0)" }
        #expect(!values.contains(where: { $0.contains(key) }))
    }

    @Test func keyReadsTrimmedAndRemoves() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "  sk-spaced-key \n".write(to: folder.appendingPathComponent("ling-api-key"), atomically: true, encoding: .utf8)
        AIKey.folderOverride = folder // forget the cached value
        #expect(AIKey.read() == "sk-spaced-key")
        AIKey.remove()
        #expect(AIKey.read() == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("ling-api-key").path))
    }

    @Test func emptyKeyFileIsNoKey() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try " \n".write(to: folder.appendingPathComponent("ling-api-key"), atomically: true, encoding: .utf8)
        AIKey.folderOverride = folder
        #expect(AIKey.read() == nil)
    }

    @Test func eachServiceHasItsOwnKeyFile() throws {
        #expect(AIKey.save("sk-ling-111", "ling"))
        #expect(AIKey.save("sk-zen-222", "zenmux"))
        let file = folder.appendingPathComponent("ai-key-zenmux")
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
        #expect(AIKey.read("ling") == "sk-ling-111" && AIKey.read("zenmux") == "sk-zen-222" && AIKey.read("openai") == nil)
        AIKey.remove("zenmux")
        #expect(AIKey.read("zenmux") == nil && AIKey.read() == "sk-ling-111")
    }

    @Test func maskedShowsOnlyTheEnds() {
        #expect(AIKey.masked("sk-abcdefghij3f9a") == "sk-" + String(repeating: "•", count: 12) + "3f9a")
        #expect(AIKey.masked("short") == "sk-…")
    }

    // MARK: Client

    @Test func contentGoesInTheSystemMessageAndThinkingIsOff() async throws {
        let ling = client()
        LingStub.reset(200, LingStub.chatReply(" Hello. "))
        let out = try await ling.chat(content: "你好。", instruction: "Translate the system message.", priority: .translate)
        #expect(out == "Hello.")
        let body = try #require(LingStub.seen.first?.body)
        #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
        #expect(body["stream"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == "你好。")
        #expect(messages[1]["role"] as? String == "user")
        #expect(messages[1]["content"] as? String == "Translate the system message.")
    }

    @Test func eachRequestIsReportedWithServiceModelAndUse() async throws {
        let ling = client()
        var calls: [AICall] = []
        ling.onCall = { calls.append($0) }
        LingStub.reset(200, LingStub.chatReply("ok"))
        _ = try await ling.chat(content: "x", instruction: "y", priority: .translate)
        _ = try await ling.chat(content: "x", instruction: "y", priority: .notes)
        _ = try await ling.chat(content: "x", instruction: "y", priority: .notes, model: "Ling-3.0-tiny", role: "speakers")
        #expect(calls.map(\.provider) == ["ling", "ling", "ling"])
        #expect(calls.map(\.role) == ["translate", "notes", "speakers"])
        #expect(calls.map(\.model) == ["Ling-3.1-flash", "Ling-3.1-flash", "Ling-3.0-tiny"])
        #expect(calls.allSatisfy { $0.outcome == "ok" })
    }

    @Test func voiceRequestsAreReportedWithFirstAudio() async throws {
        let ling = client()
        var calls: [AICall] = []
        ling.onCall = { calls.append($0) }
        LingStub.reset(200, "0123456789")   // no Content-Type: raw PCM, one chunk
        var chunks = 0
        for try await _ in ling.speech("你好世界") { chunks += 1 }
        #expect(chunks == 1)
        let c = try #require(calls.first)
        #expect(c.role == "voice" && c.provider == "ling" && c.model == "Ming-3.0-tts-0.5B")
        #expect(c.outcome == "ok" && c.chars == 4 && c.firstAudio != nil && c.promptTokens == 0)
    }

    @Test func aJSONObjectInPlainTextCountsAsJSON() {
        func reply(_ t: String) -> [String: Any] { ["choices": [["message": ["content": t]]]] }
        #expect(LingClient.answersJSON(reply("{\"ok\": true}")))
        #expect(LingClient.answersJSON(reply("```json\n{\"ok\": true}\n```")))
        #expect(!LingClient.answersJSON(reply("ok")))
        #expect(!LingClient.answersJSON(nil))
    }

    @Test func rejectedKeyIsMarkedInvalid() async {
        let ling = client()
        LingStub.reset(401, "{}")
        await #expect(throws: LingClient.Failure.invalidKey) {
            try await ling.chat(content: "x", instruction: "y", priority: .translate)
        }
        #expect(ling.keyState == .invalid)
        #expect(!ling.usable)
    }

    @Test func searchStyleRepliesAreDropped() async {
        let ling = client()
        LingStub.reset(200, LingStub.chatReply("根据现有检索证据，……"))
        await #expect(throws: LingClient.Failure.hijacked) {
            try await ling.chat(content: "x", instruction: "y", priority: .translate)
        }
        LingStub.reset(200, LingStub.chatReply("Hello.", finish: nil))
        await #expect(throws: LingClient.Failure.hijacked) {
            try await ling.chat(content: "x", instruction: "y", priority: .translate)
        }
    }

    @Test func noKeyMeansNoRequest() async {
        let ling = client()
        AIKey.remove()
        LingStub.reset(200, LingStub.chatReply("Hello."))
        await #expect(throws: LingClient.Failure.noKey) {
            try await ling.chat(content: "x", instruction: "y", priority: .translate)
        }
        #expect(LingStub.seen.isEmpty)
    }

    @Test func startsAreSpacedAndGoInPriorityOrder() async throws {
        let ling = client()
        LingStub.reset(200, LingStub.chatReply("ok"))
        // The first call takes the gate; the next three queue behind it, asked in reverse priority.
        _ = try await ling.chat(content: "first", instruction: "i", priority: .notes)
        async let notes = ling.chat(content: "notes", instruction: "i", priority: .notes)
        async let translate = ling.chat(content: "translate", instruction: "i", priority: .translate)
        async let speak = ling.chat(content: "speak", instruction: "i", priority: .speak)
        _ = try await (notes, translate, speak)
        let order = LingStub.seen.map { (($0.body["messages"] as? [[String: Any]])?.first?["content"] as? String) ?? "" }
        #expect(order == ["first", "speak", "translate", "notes"])
        let times = LingStub.seen.map(\.at)
        for (a, b) in zip(times, times.dropFirst()) {
            #expect(b.timeIntervalSince(a) >= 0.55)
        }
    }
}
