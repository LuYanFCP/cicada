import Foundation
import Security

// MARK: - API key (local file)

/// The user's AI keys, one file per service (`ling-api-key`, `ai-key-<service>`) only this user
/// can read (0600, folder 0700) under Application Support, left out of backups. Never written to
/// UserDefaults, logs or exports.
///
/// Not the Keychain for now: the app is signed ad hoc, so the Keychain only trusts one exact build
/// (its cdhash) and asks for the login password after every rebuild or update. Back to the Keychain
/// once builds are signed with a Developer ID (a stable team id). Keys saved there by earlier
/// builds are moved over once.
enum AIKey {
    private static var cached: [String: String?] = [:]

    /// Tests only: keep the key in this folder instead, and leave the Keychain alone, so a test
    /// run never touches the user's real key.
    static var folderOverride: URL? { didSet { cached = [:] } }

    private static var folder: URL {
        folderOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(DevBuild.supportFolder)
    }
    private static func file(_ service: String) -> URL {
        folder.appendingPathComponent(service == "ling" ? "ling-api-key" : "ai-key-\(service)")
    }

    static func read(_ service: String = "ling") -> String? {
        if let hit = cached[service] { return hit }
        var value = (try? String(contentsOf: file(service), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        if value?.isEmpty ?? true { value = nil }
        if value == nil, service == "ling", folderOverride == nil, let old = LegacyKeychain.take() {
            // One last Keychain prompt, then the key lives in the file.
            value = old
            write(old, service)
        }
        cached[service] = .some(value)
        return value
    }

    @discardableResult
    static func save(_ key: String, _ service: String = "ling") -> Bool {
        let ok = write(key, service)
        cached[service] = .some(ok ? key : nil)
        return ok
    }

    static func remove(_ service: String = "ling") {
        try? FileManager.default.removeItem(at: file(service))
        if service == "ling", folderOverride == nil { LegacyKeychain.delete() }
        cached[service] = .some(nil)
    }

    @discardableResult
    private static func write(_ key: String, _ service: String) -> Bool {
        let file = file(service)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            // Create it 0600 before the key goes in, so it is never readable by others.
            if !fm.fileExists(atPath: file.path) {
                guard fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                    debugLog("ai key: could not create the key file")
                    return false
                }
            }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            #if os(iOS)
            // Readable after the first unlock: listening goes on on the lock screen, and a meeting
            // started from the Action Button while locked still needs the key for the notes.
            try Data(key.utf8).write(to: file, options: .completeFileProtectionUntilFirstUserAuthentication)
            #else
            try Data(key.utf8).write(to: file)
            #endif
            var url = file
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
            return true
        } catch {
            debugLog("ai key: save failed \(error.localizedDescription)")
            return false
        }
    }

    /// Where builds before the file kept the key: login Keychain, service = bundle id + ".ai".
    private enum LegacyKeychain {
        private static var query: [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "com.wquguru.cicada.swiftrun") + ".ai",
             kSecAttrAccount as String: "ling"]
        }

        /// The old key, removed from the Keychain once read.
        static func take() -> String? {
            // Skip the Keychain entirely when there was never an item (no prompt for new users).
            var exists = query
            exists[kSecReturnAttributes as String] = true
            guard SecItemCopyMatching(exists as CFDictionary, nil) == errSecSuccess else { return nil }
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
                  let key = (out as? Data).flatMap({ String(data: $0, encoding: .utf8) }), !key.isEmpty else { return nil }
            delete()
            debugLog("ai key: moved from the Keychain to the key file")
            return key
        }

        static func delete() { SecItemDelete(query as CFDictionary) }
    }

    /// "sk-…3f9a" for display.
    static func masked(_ key: String) -> String {
        guard key.count > 8 else { return "sk-…" }
        return String(key.prefix(3)) + String(repeating: "•", count: 12) + String(key.suffix(4))
    }
}

// MARK: - Ling client

/// The one AI client for the whole app: Ling (ant-ling.com) or another OpenAI-compatible service
/// (`AIProvider`), whichever settings name. Request *starts* go through one gate in priority order
/// (speak-back, translation, notes), spaced for the service: Ling's account allows about 2
/// requests per second across every model.
///
/// Two Ling quirks found in testing shape every call (`AIConfig.shape` turns thinking off for the
/// others too, each its own way):
/// - `thinking` is on by default: always disable it (otherwise +2.6 s and billed reasoning).
/// - When the user message reads like a factual question, the gateway answers it with a search
///   essay instead of following the prompt. So the content always goes in the system message and
///   the user message is a fixed instruction; a search-style reply is detected and dropped.
@MainActor
final class LingClient: ObservableObject {
    enum Priority: Int, Comparable {
        case speak = 0, translate = 1, notes = 2
        static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    }

    enum KeyState: Equatable {
        case none
        case unchecked
        case checking
        case ok(seconds: Double)
        case invalid
        case unreachable(String)
    }

    enum Failure: Error, Equatable {
        case noKey, invalidKey, rateLimited, hijacked, timeout, http(Int), network, parse
    }

    static let models = AIProvider.ling.textModels.map(\.id)
    private static let hijackPrefixes = ["根据现有检索证据", "暂未找到足够可靠的信息", "根据检索"]

    @Published private(set) var keyState: KeyState
    @Published private(set) var rateLimitedAt: Date?
    /// Step by step, where the service stands (`keyState` is its short form for older callers).
    @Published private(set) var aiCheck = AICheck()
    /// The last time the room voice spoke (or failed to) through this service.
    @Published private(set) var lastVoice: (ok: Bool, at: Date)?
    /// The service's text models from its `/models`, recommended first (empty until fetched).
    @Published private(set) var catalog: [String] = []
    /// Every model id the service lists, to tell whether the chosen one still exists.
    private var listed: Set<String>?
    /// Reads this device's proxy settings to word the "can't reach" hint (never used to connect).
    var proxyHint: (() async -> AICheck.ProxyHint)?
    /// Whether the local network permission holds back a connection to this address (Mac only;
    /// asked only after a request to a local network server failed).
    var localNetworkProbe: ((URL) async -> Bool)?

    /// Debug control only: the next checks end this way (for screenshots of every state).
    var simulateCheck: AICheck.Reason?
    /// Debug control only: report this OpenRouter balance instead of the real one.
    var simulateBalance: Double?
    /// Debug control only: a server that can't be reached is held back by the local network permission.
    var simulateLocalNetwork = false
    /// The service in use, its address and models. Set by the app from settings.
    var config: () -> AIConfig = { AIConfig(provider: .ling, base: AIProvider.ling.base, textModel: "Ling-3.1-flash",
                                            voiceModel: "Ming-3.0-tts-0.5B", voiceBase: AIProvider.ling.base) }
    var provider: AIProvider { config().provider }
    private let keyNamespace: String?
    private let checksJSON: Bool
    private let checksAudio: Bool
    /// The meeting's speech server: only `/audio/transcriptions` is asked of it.
    private let checksTranscription: Bool
    private var keyService: String { keyService(for: provider) }
    private func keyService(for provider: AIProvider) -> String {
        keyNamespace.map { "\($0)-\(provider.id.rawValue)" } ?? provider.id.rawValue
    }

    func hasStoredKey(for configuration: AIConfig) -> Bool { AIKey.read(keyService(for: configuration.provider)) != nil }
    /// The key saved for that kind of service, to show masked or to hand to another setting that
    /// shares its address (never displayed or logged).
    func storedKey(for configuration: AIConfig) -> String? {
        hideKey ? nil : AIKey.read(keyService(for: configuration.provider))
    }

    /// Debug control only: make every chat call fail this way.
    var simulate: Failure?

    /// Debug control only: act as if there were no key, without touching the key file.
    var hideKey = false

    /// Tests swap in a session with a stub protocol.
    var session: URLSession = .shared

    var hasKey: Bool { key != nil }
    /// The key for the service in use. A custom service on this Mac or the local network may need none: "".
    var key: String? {
        if hideKey { return nil }
        let c = config()
        if c.provider.id == .custom {
            guard let base = c.base else { return nil }
            return AIKey.read(keyService) ?? (AIProvider.isNearby(base.absoluteString) ? "" : nil)
        }
        return AIKey.read(keyService)
    }
    /// The key is known to work (or at least not known to be bad): notes and translation.
    var usable: Bool { hasKey && keyState != .invalid }
    /// Voices in the room from this service (else the Mac's).
    var speaks: Bool { usable && config().hasVoices }
    /// The user's own voice: only Ling clones.
    var clones: Bool { usable && provider.clones }
    /// Speak-back heard by the service's audio model (Ming) instead of on this Mac.
    var hearsAudio: Bool {
        let c = config()
        return usable && c.acceptsAudio && (c.audioInputFormat == nil || !c.textModel.isEmpty)
    }
    var audioModel: String { config().audioInputFormat == nil ? "Ming-3.0-audio-flash" : config().textModel }
    /// The meeting recognized by the custom service's speech model instead of on this Mac.
    var transcribes: Bool { usable && config().transcribes }
    /// The custom service refused `chat_template_kwargs` once: leave it out until settings change.
    private var noTemplateKwargs = false

    init(keyNamespace: String? = nil, checksJSON: Bool = true, checksAudio: Bool = false, checksTranscription: Bool = false) {
        self.keyNamespace = keyNamespace
        self.checksJSON = checksJSON
        self.checksAudio = checksAudio
        self.checksTranscription = checksTranscription
        keyState = AIKey.read(keyNamespace.map { "\($0)-ling" } ?? "ling") == nil ? .none : .unchecked
    }

    /// Settings switched service, address or model: forget the old state and check again.
    func reconfigure(check: Bool = true) {
        settingsGeneration += 1
        noTemplateKwargs = false
        recheck?.cancel()
        catalog = []
        listed = nil
        aiCheck = AICheck()
        lastVoice = nil
        keyState = hasKey ? .unchecked : .none
        // A custom service's check is two real requests (and a hear one): fields saved one after
        // another check once, not once each.
        if check, hasKey {
            let wait = config().provider.id == .custom ? 0.8 : 0
            recheck = Task { [weak self] in
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
                await self?.check()
            }
        }
    }
    private var recheck: Task<Void, Never>?
    /// Bumped when settings change: a request sent to the service before says nothing about the new one.
    private var settingsGeneration = 0

    // MARK: Key

    /// Save before switching addresses, so requests starting after a configuration change never
    /// take the previous server's key while an asynchronous save is still waiting to run.
    @discardableResult
    func saveKey(_ raw: String, for configuration: AIConfig) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !hideKey else { return false }
        return AIKey.save(key, keyService(for: configuration.provider))
    }

    /// Saves the key and checks it with the cheapest possible request.
    func setKey(_ raw: String) async {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        if hideKey { debugLog("ai key: not saved while hidden (debug)"); keyState = .invalid; return }
        guard saveKey(k, for: config()) else { return }
        await check()
    }

    func removeKey() {
        settingsGeneration += 1
        checkGeneration += 1
        recheck?.cancel()
        recheck = nil
        AIKey.remove(keyService)
        catalog = []
        listed = nil
        aiCheck = AICheck()
        keyState = hasKey ? .unchecked : .none
    }

    /// The service's name for messages ("这个服务" for a custom address) and its host.
    var serviceName: String { provider.id == .custom ? L("这个服务") : provider.name }
    var serviceHost: String { config().base?.host ?? provider.base?.host ?? "" }

    /// The cheapest requests that prove each step: Ling's tiny model; OpenRouter's key info (plus
    /// its credits, for the balance); OpenAI's model list; else one token from the chosen model. A
    /// custom service must also return JSON (the notes need it). The model list then tells whether
    /// the chosen text model still exists.
    func check() async {
        // Counted before anything else: a slower check still running (a custom service that thinks
        // for seconds) must not land on top of what this one finds, even "no key".
        checkGeneration += 1
        let generation = checkGeneration
        guard let key else { keyState = .none; aiCheck = AICheck(); return }
        keyState = .checking
        let c = config()
        var r = AICheck()
        r[.reach] = .running
        aiCheck = r
        let started = Date()
        if let reason = simulateCheck {
            await finishCheck(Self.simulated(reason), c, generation)
            return
        }
        if c.provider.id == .custom, c.base == nil {
            r.fail(.reach, .badAddress, reached: false)
            await finishCheck(r, c, generation)
            return
        }
        if AICheck.owner(ofKey: key)?.management == true {
            r.fail(.key, .mgmtKey, reached: false)
            await finishCheck(r, c, generation)
            return
        }
        do {
            if checksTranscription {
                guard c.transcribes else { throw Failure.http(404) }
                // A server on this Mac loads the model on its first request, downloading it the first
                // time (Qwen3-ASR 1.7B is 2.4 GB: 5 minutes at 8 MB/s, measured): give that time here
                // rather than in a meeting. Loading it from disk took 15 s, a warm request 0.5 s.
                let nearby = c.base.map { AIProvider.isNearby($0.absoluteString) } ?? false
                _ = try await transcribe(CloudHearing.wav(Array(repeating: 0, count: 16000)), language: nil,
                                         timeout: nearby ? 1200 : 30, role: "speech-check")
                let seconds = Date().timeIntervalSince(started)
                r.pass(upTo: .text, seconds: seconds)
                r.hear = .ok(seconds: seconds)
            } else if checksAudio {
                guard !c.textModel.isEmpty else { throw Failure.http(404) }
                let reply = try await chat(content: "This is an audio connection test. Reply with OK only.", instruction: "Reply OK.",
                                           priority: .speak, maxTokens: 20, timeout: 20,
                                           audio: CloudHearing.wav(Array(repeating: 0, count: 16000)), role: "audio-check")
                guard !reply.isEmpty else { throw Failure.parse }
                r.pass(upTo: .text, seconds: Date().timeIntervalSince(started))
                r.hear = .ok(seconds: Date().timeIntervalSince(started))
            } else if !checksJSON {
                r.translate = try await checkTranslation(c, key: key)
                r.pass(upTo: .text, seconds: Date().timeIntervalSince(started))
            } else {
                switch c.provider.id {
                case .ling:
                    _ = try await post("chat/completions", body: ["model": "Ling-3.0-tiny", "messages": [["role": "user", "content": "hi"]],
                                                                 "max_tokens": 1, "thinking": ["type": "disabled"]], key: key, timeout: 15)
                    r.pass(upTo: .text, seconds: Date().timeIntervalSince(started))
                case .openrouter:
                    let info = try await get("key", key: key)
                    r.pass(upTo: .key, seconds: Date().timeIntervalSince(started))
                    let credits = try? await get("credits", key: key)
                    r.balance = AICheck.balance(key: info, credits: credits)
                case .openai:
                    _ = try await get("models", key: key)
                    r.pass(upTo: .key, seconds: Date().timeIntervalSince(started))
                case .zenmux:
                    var body: [String: Any] = ["model": c.textModel, "messages": [["role": "user", "content": "hi"]]]
                    c.shape(&body, maxTokens: 1)
                    _ = try await post("chat/completions", body: body, key: key, timeout: 20)
                    r.pass(upTo: .text, seconds: Date().timeIntervalSince(started))
                case .custom:
                    // A real sentence, the way a meeting translates: one token says nothing about a
                    // model that thinks for six seconds before every answer.
                    r.translate = try await checkTranslation(c, key: key)
                    r.pass(upTo: .text, seconds: Date().timeIntervalSince(started))
                    var json: [String: Any] = ["model": c.textModel, "response_format": ["type": "json_object"],
                                               "messages": [["role": "system", "content": "Reply with the JSON object {\"ok\": true}."],
                                                            ["role": "user", "content": "Reply."]]]
                    c.shape(&json, maxTokens: 20, templateKwargs: !noTemplateKwargs)
                    do { _ = try await postChat(json, key: key, timeout: 30, base: c.base) } catch Failure.http(let code) {
                        r.fail(.text, .noJSON, code: code)
                    }
                }
            }
        } catch let failure as Failure {
            if checksAudio || checksTranscription {
                if case .http(let code) = failure { r.hear = .fail(code: code) }
                else { r.hear = failure == .network || failure == .timeout ? .unreachable : .fail(code: nil) }
                r.timedOut = checksTranscription && failure == .timeout
            }
            if failure == .parse || failure == .hijacked {
                r.fail(.text, .noJSON)
            } else if let (step, reason, code) = AICheck.classify(failure, at: AICheck.firstStep(c.provider.id)) {
                if reason == .busy { r.pass(upTo: step, seconds: nil); r[step] = .busy } else { r.fail(step, reason, code: code) }
            }
        } catch {
            if checksAudio || checksTranscription { r.hear = .unreachable }
            r.fail(.reach, .unreachable)
        }
        if r.failure == nil, c.provider.id != .ling {
            await fetchCatalog()
            // A model the service no longer lists fails here, before a meeting finds out.
            if let listed, !c.textModel.isEmpty, !checksAudio {
                if !listed.contains(c.textModel) { r.fail(.text, .noModel) } else if r[.text] == .untested { r[.text] = .ok(seconds: nil) }
            }
        }
        await finishCheck(r, c, generation)
    }

    private func checkTranslation(_ c: AIConfig, key: String) async throws -> AICheck.Speed {
        var body: [String: Any] = ["model": c.textModel, "messages": [
            ["role": "system", "content": "Translate the text into Simplified Chinese. Reply with the translation only.\n\nWe will ship the new version on Friday after the design review."],
            ["role": "user", "content": "Translate."]]]
        c.shape(&body, maxTokens: 120, templateKwargs: !noTemplateKwargs)
        let asked = Date()
        let root = try await postChat(body, key: key, timeout: 30, base: c.base)
        guard let choice = (root["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any],
              let text = message["content"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.parse }
        return AICheck.Speed(seconds: Date().timeIntervalSince(asked), thinks: AIConfig.thought(root))
    }

    /// Bumped by every check: a slower, older check (a model changed twice quickly) must not
    /// land after the newer one and overwrite it.
    private var checkGeneration = 0

    private func finishCheck(_ result: AICheck, _ c: AIConfig, _ generation: Int) async {
        var r = result
        if r.failure?.reason == .unreachable, !r.localNetworkDenied { r.localNetworkDenied = await localNetworkDenied(c.base) }
        if r.failure?.reason == .unreachable, r.proxy == nil, !r.localNetworkDenied { r.proxy = await proxyHint?() }
        guard generation == checkGeneration, c == config() else {
            debugLog("ai \(c.provider.id.rawValue): an older check finished late, dropped")
            return
        }
        // Cancelled because a setting changed (the next check is on its way): its requests failed
        // as "unreachable", which would show a service that can't be reached until that check lands.
        guard !Task.isCancelled else {
            debugLog("ai \(c.provider.id.rawValue): a cancelled check dropped")
            return
        }
        if let simulateBalance { r.balance = simulateBalance }
        r.at = Date()
        aiCheck = r
        syncKeyState()
        debugLog("ai \(c.provider.id.rawValue): check → \(r.summary)")
    }

    /// A made-up result for `reason` (debug screenshots of every state).
    private static func simulated(_ reason: AICheck.Reason) -> AICheck {
        var r = AICheck()
        switch reason {
        case .busy:
            r.pass(upTo: .text, seconds: 1.2)
            r[.text] = .busy
        case .unreachable, .badAddress: r.fail(.reach, reason, reached: false)
        case .invalidKey, .noCredit: r.fail(.key, reason, code: reason == .noCredit ? 402 : nil)
        case .mgmtKey: r.fail(.key, reason, reached: false)
        case .noModel, .noJSON: r.fail(.text, reason, code: 404)
        case .serverError: r.fail(.text, reason, code: 503)
        }
        return r
    }

    /// The short form older callers read: invalid stops every request, another failure says why.
    private func syncKeyState() {
        guard hasKey else { keyState = .none; return }
        let c = aiCheck
        if let f = c.failure, f.reason != .busy {
            keyState = f.reason == .invalidKey || f.reason == .mgmtKey ? .invalid
                : .unreachable(c.message(service: serviceName, host: serviceHost, model: config().textModel) ?? "")
        } else if c.passed {
            var seconds = 0.0
            for s in c.steps { if case .ok(let sec?) = s.state { seconds = sec } }
            keyState = .ok(seconds: seconds)
        }
    }

    /// A real request (notes, translation) came back: keep the steps current without a check.
    /// One server error in a meeting isn't worth repainting the settings for.
    private func observe(_ failure: Failure?, seconds: Double = 0, audio: Bool = false, generation: Int) {
        // Sent before the service, address or model changed (a meeting's last notes, say): not this one's.
        guard hasKey, !aiCheck.running, simulateCheck == nil, generation == settingsGeneration else { return }
        var r = aiCheck
        if let failure {
            guard let (step, reason, code) = AICheck.classify(failure, at: .text), reason != .serverError else { return }
            // An audio request (Ming hearing speak-back) says nothing about the text model.
            if audio, step == .text { return }
            if reason == .busy { r.pass(upTo: .key, seconds: nil); r[step] = .busy } else { r.fail(step, reason, code: code) }
        } else {
            r.pass(upTo: audio ? .key : .text, seconds: seconds)
        }
        let wasUnreachable = aiCheck.failure?.reason == .unreachable
        r.at = Date()
        r.passive = true
        if r.failure?.reason != .unreachable { r.proxy = nil; r.localNetworkDenied = false }
        if r.steps == aiCheck.steps, aiCheck.passive { aiCheck.at = r.at; return }
        aiCheck = r
        syncKeyState()
        debugLog("ai: from a real request → \(r.summary)")
        if r.failure?.reason == .unreachable, !wasUnreachable {
            let base = config().base
            Task {
                let denied = await localNetworkDenied(base)
                let hint = denied ? nil : await proxyHint?()
                guard aiCheck.failure?.reason == .unreachable else { return }
                aiCheck.localNetworkDenied = denied
                aiCheck.proxy = hint
                syncKeyState()
            }
        }
    }

    /// A server on the local network (not this Mac) that failed: is it the permission?
    private func localNetworkDenied(_ url: URL?) async -> Bool {
        if simulateLocalNetwork { return true }
        guard let url, let host = url.host, AIProvider.isNearby(host), !AIProvider.isLocal(host),
              let localNetworkProbe else { return false }
        return await localNetworkProbe(url)
    }

    /// Back from System Settings (or from the permission prompt): look again if the local network
    /// permission was what stopped it; turning it on doesn't change the network path.
    func recheckLocalNetwork() {
        guard hasKey, aiCheck.needsLocalNetwork, !aiCheck.running else { return }
        debugLog("ai: back while the local network was denied, checking again")
        Task { await check() }
    }

    /// The network came back (or changed) while the service was unreachable: look again.
    func networkChanged() {
        guard hasKey, aiCheck.failure?.reason == .unreachable, !aiCheck.running else { return }
        debugLog("ai: network changed while unreachable, checking again")
        Task { await check() }
    }

    /// The service's text models, for the model menu. Quietly empty when it has no `/models`.
    func fetchCatalog() async {
        let c = config()
        let generation = settingsGeneration
        guard let key, c.provider.id != .ling, let data = try? await getData("models", key: key) else { return }
        guard generation == settingsGeneration, c == config(), key == self.key else { return }
        catalog = checksAudio ? AIConfig.audioModels(fromCatalog: data)
            : checksTranscription ? AIConfig.speechModels(fromCatalog: data)
            : AIConfig.textModels(fromCatalog: data, recommended: c.provider.textModels.map(\.id))
        listed = AICheck.listedModels(data)
        debugLog("ai \(c.provider.id.rawValue): \(catalog.count) models")
    }

    // MARK: Chat

    /// Read choices for an unsaved endpoint without changing its active route or key.
    func availableTextModels(for configuration: AIConfig, key raw: String) async throws -> [String] {
        let data = try await availableModels(for: configuration, key: raw)
        return AIConfig.textModels(fromCatalog: data, recommended: [])
    }

    func availableSpeechModels(for configuration: AIConfig, key raw: String) async throws -> [String] {
        let data = try await availableModels(for: configuration, key: raw)
        return AIConfig.speechModels(fromCatalog: data)
    }

    func availableAudioModels(for configuration: AIConfig, key raw: String) async throws -> [String] {
        let data = try await availableModels(for: configuration, key: raw)
        return AIConfig.audioModels(fromCatalog: data)
    }

    private func availableModels(for configuration: AIConfig, key raw: String) async throws -> Data {
        guard !hideKey else { throw Failure.noKey }
        guard let base = configuration.base else { throw Failure.noKey }
        let typed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = typed.isEmpty
            ? AIKey.read(keyService(for: configuration.provider)) ?? (AIProvider.isNearby(base.absoluteString) ? "" : nil)
            : typed else { throw Failure.noKey }
        guard !key.contains(where: \.isWhitespace) else { throw Failure.invalidKey }
        return try await getData("models", key: key, base: base, markKeyInvalid: false)
    }

    /// One chat completion. `content` goes in the system message, `instruction` is the fixed user
    /// message. Notes retry 429s with backoff; translation and speak-back fail fast so the caller
    /// can fall back to another translator. `audio` (a WAV) goes in the user message before the
    /// instruction, for Ming's audio model (Ling only: `hearsAudio`).
    func chat(content: String, instruction: String, priority: Priority, json: Bool = false,
              maxTokens: Int = 1024, timeout: TimeInterval = 30, model: String? = nil, audio: Data? = nil,
              role: String? = nil, patient: Bool = false, onQueued: ((Double) -> Void)? = nil) async throws -> String {
        guard let key else { throw Failure.noKey }
        guard keyState != .invalid else { throw Failure.invalidKey }
        if let simulate {
            if simulate == .rateLimited { rateLimitedAt = Date() }
            throw simulate
        }
        let c = config()
        let generation = settingsGeneration
        let call = CallLabel(provider: c.provider.id.rawValue, model: model ?? c.textModel,
                             role: role ?? (priority == .notes ? "notes" : "translate"))
        var body: [String: Any] = [
            "model": call.model,
            "messages": [
                ["role": "system", "content": content],
                ["role": "user", "content": audio.map { wav -> Any in
                    let input: [String: Any] = c.audioInputFormat == .openai
                        ? ["type": "input_audio", "input_audio": ["data": wav.base64EncodedString(), "format": "wav"]]
                        : ["type": "audio_url", "audio_url": ["url": "data:audio/wav;base64," + wav.base64EncodedString()]]
                    return [input, ["type": "text", "text": instruction]]
                } ?? instruction],
            ],
            "stream": false,
        ]
        c.shape(&body, maxTokens: maxTokens, templateKwargs: !noTemplateKwargs)
        if audio != nil {
            if c.audioInputFormat == .openai { body["modalities"] = ["text"] }
            // Audio chat models do not take text reasoning controls.
            if c.provider.id == .openai { body["reasoning_effort"] = nil }
        }
        if json { body["response_format"] = ["type": "json_object"] }
        let waits = Self.retryWaits(priority, patient: patient)
        for attempt in 1...(waits.count + 1) {
            let asked = Date()
            await acquire(priority)
            guard generation == settingsGeneration else { throw CancellationError() }
            let queued = Date().timeIntervalSince(asked)
            onQueued?(queued)
            let started = Date()
            do {
                let root = try await postChat(body, key: key, timeout: timeout, base: c.base)
                guard let choice = (root["choices"] as? [[String: Any]])?.first,
                      let message = choice["message"] as? [String: Any],
                      let text = message["content"] as? String else { throw Failure.parse }
                let finish = choice["finish_reason"] as? String
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if (finish == nil && c.provider.id == .ling) || Self.hijackPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
                    debugLog("ling: \(priority) search-style reply dropped (finish=\(finish ?? "nil"))")
                    throw Failure.hijacked
                }
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                let usage = root["usage"] as? [String: Any]
                // A reply cut at max_tokens is usually half a JSON object: say so, or it reads as a bad reply.
                debugLog("ling: \(priority) ok \(ms) ms tokens=\(usage?["prompt_tokens"] ?? "?")/\(usage?["completion_tokens"] ?? "?")\(finish == "length" ? " cut at max_tokens" : "")")
                report(call, priority, at: started, queued: queued, outcome: "ok",
                       tokens: (usage?["prompt_tokens"] as? Int ?? 0, usage?["completion_tokens"] as? Int ?? 0))
                if rateLimitedAt != nil { rateLimitedAt = nil }
                observe(nil, seconds: Double(ms) / 1000, audio: audio != nil, generation: generation)
                return trimmed
            } catch let failure as Failure {
                report(call, priority, at: started, queued: queued, outcome: Self.name(failure))
                observe(failure, audio: audio != nil, generation: generation)
                guard failure == .rateLimited else { throw failure }
                guard attempt <= waits.count else {
                    rateLimitedAt = Date()
                    throw failure
                }
                let wait = waits[attempt - 1] + Double.random(in: 0...0.5)
                debugLog("ling: \(priority) 429, retry in \(String(format: "%.1f", wait)) s")
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        throw Failure.rateLimited
    }

    /// Seconds to wait before each retry of a 429. Notes retry a few times; translation and
    /// speak-back fail fast so the caller can fall back. `patient` (the final notes) keeps at it for
    /// about a minute: a model limited upstream (OpenRouter's Ling 3.1 by DeepInfra, 2026-11) came
    /// back after ~15 s, and a meeting left without its notes is worse than notes a little late.
    nonisolated static func retryWaits(_ priority: Priority, patient: Bool = false) -> [Double] {
        guard priority == .notes else { return [] }
        return patient ? [1, 2, 4, 8, 16, 30] : [1, 2, 4]
    }

    /// Every request, for diagnostics (timings and token counts only).
    var onCall: ((AICall) -> Void)?

    /// Which service, model and use a request is for: the diagnostics page groups by these.
    struct CallLabel { let provider, model, role: String }

    private func report(_ call: CallLabel, _ priority: Priority, at started: Date, queued: Double, outcome: String,
                        tokens: (Int, Int) = (0, 0), chars: Int = 0, firstAudio: Double? = nil) {
        onCall?(AICall(at: started, provider: call.provider, model: call.model, role: call.role, priority: "\(priority)",
                       queue: queued, seconds: Date().timeIntervalSince(started), outcome: outcome,
                       promptTokens: tokens.0, completionTokens: tokens.1, chars: chars, firstAudio: firstAudio))
    }

    static func name(_ failure: Failure) -> String {
        switch failure {
        case .http(let code): "http\(code)"
        default: "\(failure)"
        }
    }

    // MARK: Speech

    /// Streams the voice for `text` as raw 24 kHz mono 16-bit PCM chunks. Ling (Ming): a built-in
    /// `voice`, or a voice cloned from `reference` (a WAV data URI and what it says); `language` is
    /// Ming's `language_id`, needed for Japanese, Korean, German, French and Spanish. Others: the
    /// configured speech model and `voice`.
    ///
    /// Replies come three ways and all are read: SSE with base64 chunks (Ling, ZenMux), raw PCM
    /// bytes (OpenRouter), or one JSON `{"audio": <WAV>}`. Gemini TTS and Kokoro speak 24 kHz too.
    func speech(_ text: String, voice: String? = "UK_Charlotte", reference: (audio: String, text: String)? = nil,
                language: String? = nil) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { cont in
            let task = Task { @MainActor [weak self] in
                guard let self, let key = self.key else { cont.finish(throwing: Failure.noKey); return }
                let c = self.config()
                guard let base = c.voiceBase, let voiceModel = c.voiceModel else { cont.finish(throwing: Failure.noKey); return }
                let asked = Date()
                await self.acquire(.speak)
                let queued = Date().timeIntervalSince(asked)
                let started = Date()
                var firstAudio: Double?
                let call = CallLabel(provider: c.provider.id.rawValue, model: voiceModel, role: "voice")
                func yield(_ pcm: Data) {
                    if firstAudio == nil { firstAudio = Date().timeIntervalSince(started) }
                    cont.yield(pcm)
                }
                var req = URLRequest(url: base.appendingPathComponent("audio/speech"))
                req.httpMethod = "POST"
                req.timeoutInterval = 20
                if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                var body: [String: Any] = ["model": voiceModel, "input": text, "response_format": "pcm"]
                if c.provider.id == .ling {
                    body["sample_rate"] = 24000
                    body["stream"] = true
                    body["stream_format"] = "sse"
                    if let reference {
                        body["references"] = [["audio": reference.audio, "text": reference.text]]
                        req.timeoutInterval = 30
                    } else if let voice {
                        body["voice"] = voice
                    }
                    if let language { body["language_id"] = language }
                } else {
                    // OpenRouter documents no `stream` (it streams the bytes anyway); ZenMux needs it.
                    if c.provider.id != .openrouter { body["stream"] = true }
                    body["voice"] = voice ?? c.voices.first?.id ?? "Kore"
                }
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                do {
                    let (bytes, response) = try await self.session.bytes(for: req)
                    let http = response as? HTTPURLResponse
                    switch http?.statusCode ?? 0 {
                    case 200: break
                    case 401, 403:
                        self.keyState = .invalid
                        throw Failure.invalidKey
                    case 429: throw Failure.rateLimited
                    case let code: throw Failure.http(code)
                    }
                    let type = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
                    if type.contains("event-stream") {
                        for try await line in bytes.lines {
                            guard line.hasPrefix("data:"),
                                  let obj = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any]
                            else { continue }
                            if obj["type"] as? String == "speech.audio.done" { break }
                            if let b64 = obj["audio"] as? String, let pcm = Data(base64Encoded: b64) { yield(pcm) }
                        }
                    } else if type.contains("json") {
                        var data = Data()
                        for try await b in bytes { data.append(b) }
                        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let b64 = obj["audio"] as? String, let wav = Data(base64Encoded: b64) else { throw Failure.parse }
                        yield(Self.pcm(fromWAV: wav))
                    } else {
                        // Raw PCM: hand it on in 0.1 s pieces so playback starts early.
                        var chunk = Data()
                        chunk.reserveCapacity(4800)
                        for try await b in bytes {
                            chunk.append(b)
                            if chunk.count >= 4800 { yield(chunk); chunk.removeAll(keepingCapacity: true) }
                        }
                        if !chunk.isEmpty { yield(chunk) }
                    }
                    self.report(call, .speak, at: started, queued: queued, outcome: "ok", chars: text.count, firstAudio: firstAudio)
                    self.lastVoice = (true, Date())
                    cont.finish()
                } catch {
                    // Cancelled: the voice was cut short on purpose (stop, a new press), not a failure.
                    let outcome = Task.isCancelled ? "cancelled" : (error as? Failure).map(Self.name) ?? "network"
                    self.report(call, .speak, at: started, queued: queued, outcome: outcome, chars: text.count, firstAudio: firstAudio)
                    if !Task.isCancelled { self.lastVoice = (false, Date()) }
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    /// The samples of a WAV (its `data` chunk); the bytes as they are when there is no header.
    nonisolated static func pcm(fromWAV wav: Data) -> Data {
        guard wav.count > 12, wav.prefix(4) == Data("RIFF".utf8) else { return wav }
        var i = 12
        while i + 8 <= wav.count {
            let id = wav.subdata(in: i..<i + 4)
            let size = wav.subdata(in: i + 4..<i + 8).withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self).littleEndian) }
            if id == Data("data".utf8) { return wav.subdata(in: i + 8..<min(wav.count, i + 8 + size)) }
            i += 8 + size + (size & 1)
        }
        return wav
    }

    // MARK: Recognition

    /// What the custom service's speech model heard in `wav` (a 16 kHz mono WAV): standard
    /// `/audio/transcriptions` (Qwen3-ASR, Whisper servers, Fun-ASR). `language` (a BCP-47 code) is
    /// the hint, for servers that take one. Throws like a chat call, so listening can tell a
    /// service that is down from a quiet meeting.
    func transcribe(_ wav: Data, language: String?, timeout: TimeInterval = 12,
                    role: String = "heard-them") async throws -> (text: String, language: String?) {
        guard let key else { throw Failure.noKey }
        let c = config()
        guard let base = c.hearBase, let model = c.hearModel else { throw Failure.noKey }
        let asked = Date()
        await acquire(.translate)
        let queued = Date().timeIntervalSince(asked)
        let started = Date()
        let call = CallLabel(provider: c.provider.id.rawValue, model: model, role: role)
        var req = URLRequest(url: base.appendingPathComponent("audio/transcriptions"))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        let boundary = "cicada-" + UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // `response_format` spelled out: mlx-audio's server streams NDJSON unless asked for JSON.
        var fields = [("model", model), ("temperature", "0"), ("response_format", "json")]
        if let language { fields.append(("language", String(language.prefix { $0 != "-" }))) }
        req.httpBody = Self.multipart(fields: fields, file: wav, boundary: boundary)
        do {
            let data = try await send(req, key: key, contentType: nil)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = root["text"] as? String else { throw Failure.parse }
            report(call, .translate, at: started, queued: queued, outcome: "ok", chars: text.count)
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), root["language"] as? String)
        } catch let failure as Failure {
            report(call, .translate, at: started, queued: queued, outcome: Self.name(failure))
            throw failure
        } catch {
            report(call, .translate, at: started, queued: queued, outcome: "parse")
            throw Failure.parse
        }
    }

    nonisolated static func multipart(fields: [(String, String)], file: Data, boundary: String) -> Data {
        var d = Data()
        for (name, value) in fields {
            d.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        d.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        d.append(file)
        d.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return d
    }

    // MARK: Transport

    /// A chat completion. A custom server that refuses `chat_template_kwargs` (a strict gateway
    /// answers 400 or 422 to fields it doesn't know) is asked again without it, and isn't sent it
    /// again until settings change.
    private func postChat(_ body: [String: Any], key: String, timeout: TimeInterval, base: URL? = nil) async throws -> [String: Any] {
        guard let base = base ?? config().base else { throw Failure.noKey }
        do {
            return try await post("chat/completions", body: body, key: key, timeout: timeout, base: base)
        } catch Failure.http(let code) where (code == 400 || code == 422) && body["chat_template_kwargs"] != nil {
            // Only when the same request goes through without it: a 400 for something else (no
            // JSON mode) must not turn thinking back on for every translation.
            var plain = body
            plain["chat_template_kwargs"] = nil
            do {
                let root = try await post("chat/completions", body: plain, key: key, timeout: timeout, base: base)
                debugLog("ai custom: chat_template_kwargs refused (HTTP \(code)), sent without it from now on")
                if config().base == base { noTemplateKwargs = true }
                return root
            } catch {
                throw Failure.http(code)
            }
        }
    }

    private func post(_ path: String, body: [String: Any], key: String, timeout: TimeInterval, base: URL? = nil) async throws -> [String: Any] {
        guard let base = base ?? config().base else { throw Failure.noKey }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(req, key: key)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.parse }
        return root
    }

    private func get(_ path: String, key: String) async throws -> [String: Any] {
        let data = try await getData(path, key: key)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func getData(_ path: String, key: String, base: URL? = nil, markKeyInvalid: Bool = true) async throws -> Data {
        guard let base = base ?? config().base else { throw Failure.noKey }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.timeoutInterval = 15
        return try await send(req, key: key, markKeyInvalid: markKeyInvalid)
    }

    private func send(_ request: URLRequest, key: String, contentType: String? = "application/json", markKeyInvalid: Bool = true) async throws -> Data {
        let generation = settingsGeneration
        var req = request
        if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError where e.code == .timedOut {
            throw Failure.timeout
        } catch {
            debugLog("ling: network error \(error.localizedDescription)")
            throw Failure.network
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: return data
        case 401, 403:
            if markKeyInvalid, generation == settingsGeneration, key == self.key { keyState = .invalid }
            throw Failure.invalidKey
        case 429: throw Failure.rateLimited
        default:
            debugLog("ling: HTTP \(code)")
            throw Failure.http(code)
        }
    }

    // MARK: Start gate

    private var lastStart = Date.distantPast
    private var waiting: [(priority: Priority, seq: Int, resume: CheckedContinuation<Void, Never>)] = []
    private var seq = 0
    private var pumping = false

    private func acquire(_ priority: Priority) async {
        if waiting.isEmpty && Date().timeIntervalSince(lastStart) >= provider.spacing {
            lastStart = Date()
            return
        }
        seq += 1
        let n = seq
        await withCheckedContinuation { cont in
            waiting.append((priority, n, cont))
            pump()
        }
    }

    private func pump() {
        guard !pumping, !waiting.isEmpty else { return }
        pumping = true
        let wait = max(0, provider.spacing - Date().timeIntervalSince(lastStart))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pumping = false
                guard let i = self.waiting.indices.min(by: {
                    (self.waiting[$0].priority, self.waiting[$0].seq) < (self.waiting[$1].priority, self.waiting[$1].seq)
                }) else { return }
                let next = self.waiting.remove(at: i)
                self.lastStart = Date()
                next.resume.resume()
                self.pump()
            }
        }
    }
}
