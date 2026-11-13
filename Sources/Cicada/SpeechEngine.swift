import CryptoKit
import Foundation

/// A speech model the built-in engine runs: a Hugging Face checkpoint pinned to one commit, every
/// file by its size and SHA-256 (the pins are SGLang-Omni's, whose server reads these models).
struct EngineModel: Equatable, Identifiable, Sendable {
    struct File: Equatable, Sendable {
        let path: String
        let size: Int64
        let sha256: String
    }

    let id: String
    /// Not translated: the name people know the model by.
    let name: String
    let repo: String
    let revision: String
    let files: [File]

    var bytes: Int64 { files.reduce(0) { $0 + $1.size } }
    /// What the server calls it, and the folder it is kept in: the repo's last part.
    var served: String { repo.split(separator: "/").last.map(String.init) ?? repo }

    func url(_ file: File, host: String) -> URL {
        URL(string: "https://\(host)/\(repo)/resolve/\(revision)/\(file.path)")!
    }

    /// Every file is in `folder` at its size (a download in progress has not all of them yet).
    func complete(in folder: URL) -> Bool {
        files.allSatisfy { file in
            let values = try? folder.appendingPathComponent(file.path).resolvingSymlinksInPath()
                .resourceValues(forKeys: [.fileSizeKey])
            return values?.fileSize.map(Int64.init) == file.size
        }
    }

    /// Where the model is: Cicada's own download, else the same commit already fetched by
    /// Hugging Face's tools (mlx-audio's server keeps it there), so nobody downloads it twice.
    func folder(own: URL = SpeechEngine.modelsFolder, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let mine = own.appendingPathComponent(served)
        if complete(in: mine) { return mine }
        let cached = home.appendingPathComponent(".cache/huggingface/hub/models--\(repo.replacingOccurrences(of: "/", with: "--"))/snapshots/\(revision)")
        return complete(in: cached) ? cached : nil
    }

    private static let shared = [
        File(path: "chat_template.json", size: 1161, sha256: "75a8cfca24f00de72d796fbfed6858fc9614ef3dabd8696684cc3bc03a9c58ff"),
        File(path: "generation_config.json", size: 142, sha256: "1da527824d81e07118facff437e03f2e24a23311e3bdeb2368973fe77e5f275c"),
        File(path: "merges.txt", size: 1_671_853, sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
        File(path: "preprocessor_config.json", size: 330, sha256: "45e120a4eda2c20c5d7f2ea9354e63536bf35e27aa573fb7cdf78017b378770d"),
        File(path: "tokenizer_config.json", size: 12487, sha256: "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"),
        File(path: "vocab.json", size: 2_776_833, sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"),
    ]

    /// 1.7B first: clearly better Chinese and mixed speech, and an M-series Mac answers a sentence
    /// in a fraction of a second. 0.6B for a Mac short of memory.
    static let all = [
        EngineModel(id: "qwen3-asr-1.7b", name: "Qwen3-ASR 1.7B", repo: "mlx-community/Qwen3-ASR-1.7B-8bit",
                    revision: "a8379a2e2f9e313c9292cdf1af4055ab56d50d55", files: shared + [
            File(path: "config.json", size: 7188, sha256: "1b76b3b6c655fc54595da025f7a96474ad9fa86363303fbdd61a7d8483ccfaf7"),
            File(path: "model.safetensors.index.json", size: 78968, sha256: "0a5d0ec11188602242ff81a9969883d0fdeb98cd5d85cd1413089d897c201af5"),
            File(path: "model.safetensors", size: 2_463_307_541, sha256: "bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c"),
        ]),
        EngineModel(id: "qwen3-asr-0.6b", name: "Qwen3-ASR 0.6B", repo: "mlx-community/Qwen3-ASR-0.6B-4bit",
                    revision: "313d850181767edf09f00a9c289becca70e58cd0", files: shared + [
            File(path: "config.json", size: 7187, sha256: "923618cf5ca452fda0253a6be5c1a17f94a2e4851d3b98beb45848565587bd72"),
            File(path: "model.safetensors.index.json", size: 71814, sha256: "e3bb80ef0fd42a5be07b04e90c97d60460bbde8af3531e0bfe9100a61404d81a"),
            File(path: "model.safetensors", size: 708_236_945, sha256: "70c7e67e588062adce4f10796e47ad42ead51c6671eda61a0987eae38ca95ddf"),
        ]),
    ]

    static func named(_ id: String) -> EngineModel { all.first { $0.id == id } ?? all[0] }
}

/// 语音识别 › 内置: SGLang-Omni's native Qwen3-ASR server (`scripts/build-engine.sh`), kept in the
/// app and run as a child process on a loopback port. To the rest of the app it is one more
/// `/audio/transcriptions` address, so the meeting goes through the same path as 自建服务; this
/// class starts it when a meeting needs it, restarts it if it dies, and stops it two minutes after
/// the meeting (or a check, or an import) to give its memory back: the 1.7B model holds 2.4 GB,
/// and loads again in about a second.
@MainActor
final class SpeechEngine: ObservableObject {
    enum Failure: Error, Equatable { case noRuntime, noModel, start(String) }

    struct Progress: Equatable {
        let model: String
        var received: Int64
        let total: Int64
        var fraction: Double { total > 0 ? min(1, Double(received) / Double(total)) : 0 }
    }

    /// The server in the app bundle; nil on an Intel Mac, before macOS 15 (MLX's floor), and in a
    /// build made without it. `CICADA_ENGINE` points a dev run at build/engine.
    nonisolated static let runtime: URL? = {
        #if arch(arm64)
        guard #available(macOS 15, *) else { return nil }
        let folder = ProcessInfo.processInfo.environment["CICADA_ENGINE"].map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.resourceURL?.appendingPathComponent("engine")
        guard let server = folder?.appendingPathComponent("qwen3_asr_server"),
              FileManager.default.isExecutableFile(atPath: server.path) else { return nil }
        return server
        #else
        return nil
        #endif
    }()
    nonisolated static var available: Bool { runtime != nil }

    /// One folder for the dev and release builds: nobody wants 2.5 GB twice.
    nonisolated static var modelsFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveSubs/models")
    }

    static let idle: TimeInterval = 120

    /// The download under way, and why the last one stopped.
    @Published private(set) var progress: Progress?
    @Published private(set) var problem: String?
    /// Bumped when a model arrives or goes, for views that ask `installed`.
    @Published private(set) var changes = 0

    /// Still wanted with nothing asked of it lately: a meeting is on (long silences included).
    var inUse: () -> Bool = { false }
    /// A model arrived or went: the speech client's settings changed with it.
    var onChange: () -> Void = {}

    private(set) var port = SpeechEngine.freePort()
    private var process: Process?
    private var control: FileHandle?
    private var serving: String?
    private var starting: (model: String, task: Task<Void, Error>)?
    private var lastUsed = Date()
    private var idleTimer: Timer?
    private var download: Task<Void, Never>?

    var running: Bool { process?.isRunning == true && serving != nil }

    func installed(_ model: EngineModel) -> Bool { model.folder() != nil }
    /// Cicada downloaded it (and may delete it), rather than Hugging Face's tools.
    func owns(_ model: EngineModel) -> Bool { model.complete(in: Self.modelsFolder.appendingPathComponent(model.served)) }

    /// The speech client's address for `model`; without the model on disk nothing is recognized
    /// by it (this Mac's own recognition hears the meeting).
    func config(_ model: EngineModel) -> AIConfig {
        let base = URL(string: "http://127.0.0.1:\(port)/v1/")
        return AIConfig(provider: .custom, base: base, textModel: "", hearModel: Self.available && installed(model) ? model.served : nil,
                        hearBase: base, builtIn: true)
    }

    // MARK: The server

    /// The server is up with `model` loaded; starts it (or swaps the model) first if not.
    func ensure(_ model: EngineModel) async throws {
        lastUsed = Date()
        if running, serving == model.id { return }
        if let starting, starting.model == model.id { return try await starting.task.value }
        let task = Task { try await self.start(model) }
        starting = (model.id, task)
        defer { if starting?.model == model.id { starting = nil } }
        try await task.value
    }

    private func start(_ model: EngineModel) async throws {
        guard let runtime = Self.runtime else { throw Failure.noRuntime }
        guard let folder = model.folder() else { throw Failure.noModel }
        stop()
        let began = Date()
        for attempt in 0..<2 {
            do {
                try await launch(runtime, model: model, folder: folder)
                debugLog(String(format: "engine: %@ ready on port %d in %.1f s", model.served, port, Date().timeIntervalSince(began)))
                scheduleIdleCheck()
                return
            } catch Failure.start(let reason) where attempt == 0 && reason.contains("cannot listen") {
                // Someone took the port since it was picked: another one, and the address with it.
                port = Self.freePort()
            }
        }
        throw Failure.start("cannot listen")
    }

    private func launch(_ runtime: URL, model: EngineModel, folder: URL) async throws {
        let p = Process()
        p.executableURL = runtime
        // --supervised: it says "ready" on stdout, and leaves when its stdin closes, so it never
        // outlives the app. The cache limit keeps MLX's freed buffers from piling up beside the weights.
        p.arguments = ["--supervised", "--host", "127.0.0.1", "--port", String(port), "--model-directory", folder.path,
                       "--model-name", model.served, "--cache-limit-mb", "512"]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr
        let first = FirstEvent()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; first.finish(nil) } else { first.feed(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where !line.isEmpty {
                debugLog("engine: \(line)")
            }
        }
        p.terminationHandler = { [weak self] ended in
            first.finish(nil)
            Task { @MainActor in
                guard let self, self.process === ended else { return }
                debugLog("engine: exited (\(ended.terminationStatus))")
                self.process = nil
                self.serving = nil
            }
        }
        do { try p.run() } catch { throw Failure.start(error.localizedDescription) }
        process = p
        control = stdin.fileHandleForWriting
        // Loading 2.4 GB from a cold disk took 15 s; a Mac short of memory takes longer.
        let timeout = Task { try? await Task.sleep(for: .seconds(180)); first.finish(nil) }
        let event = await first.value()
        timeout.cancel()
        guard let event, event.name == "ready" else {
            if process === p { stop() }
            throw Failure.start(event?.reason ?? "no answer")
        }
        serving = model.id
    }

    func stop() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard let p = process else { return }
        process = nil
        serving = nil
        try? control?.write(contentsOf: Data("{\"command\":\"shutdown\"}\n".utf8))
        try? control?.close()
        control = nil
        if p.isRunning { p.terminate() }
    }

    private func scheduleIdleCheck() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.running, !self.inUse(), Date().timeIntervalSince(self.lastUsed) >= Self.idle else { return }
                debugLog("engine: idle, stopped")
                self.stop()
            }
        }
    }

    /// The first event line of the server's stdout: `{"event":"ready",…}` or `{"event":"failed","reason":…}`.
    nonisolated static func event(fromLine line: String) -> (name: String, reason: String?)? {
        guard let root = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let name = root["event"] as? String, !name.isEmpty else { return nil }
        return (name, root["reason"] as? String)
    }

    /// A port nobody listens on right now.
    nonisolated static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 47113 }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) == 0 && getsockname(fd, $0, &len) == 0 }
        }
        return bound ? Int(UInt16(bigEndian: addr.sin_port)) : 47113
    }

    // MARK: Models

    func fetch(_ model: EngineModel) {
        guard download == nil, !installed(model) else { return }
        problem = nil
        progress = Progress(model: model.id, received: 0, total: model.bytes)
        download = Task { [weak self] in
            let result: String?
            do {
                try await ModelDownload(model: model, into: Self.modelsFolder) { received in
                    Task { @MainActor in
                        guard let self, self.progress?.model == model.id else { return }
                        self.progress?.received = received
                    }
                }.run()
                result = nil
            } catch is CancellationError {
                // Cancelled by the user: what arrived is not wanted either.
                try? FileManager.default.removeItem(at: Self.modelsFolder.appendingPathComponent(model.served + ".part"))
                result = nil
            } catch ModelDownload.Failure.corrupt {
                result = L("下载的文件不完整，请再试一次")
            } catch ModelDownload.Failure.noSpace(let needed) {
                result = L("磁盘空间不够，还需要 \(String(format: "%.1f", Double(needed) / 1e9)) GB")
            } catch {
                debugLog("engine: download failed: \(error)")
                result = L("下载没有完成，请检查网络后再试；已下载的部分会接着下")
            }
            guard let self else { return }
            self.download = nil
            self.progress = nil
            self.problem = result
            self.changes += 1
            self.onChange()
        }
    }

    /// Stops the download and removes what arrived; one that failed keeps it, to go on from.
    func cancelFetch() {
        download?.cancel()
    }

    /// Removes Cicada's own download (never Hugging Face's cache, which other tools use).
    func delete(_ model: EngineModel) {
        if serving == model.id || starting?.model == model.id { stop() }
        try? FileManager.default.removeItem(at: Self.modelsFolder.appendingPathComponent(model.served))
        changes += 1
        onChange()
    }
}

/// The first event the server prints, wherever the line breaks fall; answered once.
private final class FirstEvent: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var done = false
    private var result: (name: String, reason: String?)?
    private var waiter: CheckedContinuation<(name: String, reason: String?)?, Never>?

    func feed(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var found: (name: String, reason: String?)?
        while found == nil, let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            found = SpeechEngine.event(fromLine: line)
        }
        lock.unlock()
        if let found { finish(found) }
    }

    func finish(_ event: (name: String, reason: String?)?) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        result = event
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume(returning: event)
    }

    func value() async -> (name: String, reason: String?)? {
        await withCheckedContinuation { c in
            lock.lock()
            if done { lock.unlock(); c.resume(returning: result) } else { waiter = c; lock.unlock() }
        }
    }
}

/// Downloads a model's files into `<folder>/<name>.part`, each checked against its SHA-256, and
/// moves the folder into place once all are there. A file cut off half way is continued (HTTP
/// Range) on the next try. Hugging Face first; where it can't be reached, its mirror: the pinned
/// hashes are what make either trustworthy.
final class ModelDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Failure: Error, Equatable { case http(Int), corrupt, noSpace(Int64) }

    static let hosts = ["huggingface.co", "hf-mirror.com"]

    private let model: EngineModel
    private let folder: URL
    private let onBytes: @Sendable (Int64) -> Void
    private var session: URLSession!

    // One file at a time; touched only on the session's serial delegate queue.
    private var handle: FileHandle?
    private var part: URL?
    private var finished: CheckedContinuation<Void, Error>?
    private var failure: Error?
    private var before: Int64 = 0
    private var written: Int64 = 0
    private var reported = Date.distantPast

    init(model: EngineModel, into folder: URL, session configuration: URLSessionConfiguration = .default,
         onBytes: @escaping @Sendable (Int64) -> Void) {
        self.model = model
        self.folder = folder
        self.onBytes = onBytes
        super.init()
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 24 * 3600
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    func run() async throws {
        defer { session.finishTasksAndInvalidate() }
        let fm = FileManager.default
        let partial = folder.appendingPathComponent(model.served + ".part")
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        let have = model.files.reduce(Int64(0)) { $0 + min(Self.size(partial.appendingPathComponent($1.path)), $1.size) }
        let free = (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? .max
        let needed = model.bytes - have + 200_000_000
        if free < needed { throw Failure.noSpace(needed - free) }

        var host = 0
        var done: Int64 = 0
        for file in model.files {
            let target = partial.appendingPathComponent(file.path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if Self.size(target) > file.size { try? fm.removeItem(at: target) }
            if Self.size(target) < file.size {
                while true {
                    try Task.checkCancellation()
                    do {
                        try await get(model.url(file, host: Self.hosts[host]), to: target, done: done)
                        break
                    } catch let error as URLError where error.code != .cancelled && host + 1 < Self.hosts.count {
                        // Unreachable from here (not a refusal, which the mirror would repeat): the mirror.
                        debugLog("engine: \(Self.hosts[host]) unreachable (\(error.code.rawValue)), trying \(Self.hosts[host + 1])")
                        host += 1
                    }
                }
            }
            guard Self.size(target) == file.size, Self.sha256(target) == file.sha256 else {
                try? fm.removeItem(at: target)
                throw Failure.corrupt
            }
            done += file.size
            onBytes(done)
        }
        let final = folder.appendingPathComponent(model.served)
        try? fm.removeItem(at: final)
        try fm.moveItem(at: partial, to: final)
    }

    private func get(_ url: URL, to target: URL, done: Int64) async throws {
        let offset = Self.size(target)
        var request = URLRequest(url: url)
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        let task = session.dataTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                session.delegateQueue.addOperation {
                    self.part = target
                    self.handle = nil
                    self.failure = nil
                    self.before = done
                    self.written = offset
                    self.finished = c
                    task.resume()
                }
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let part, code == 200 || code == 206 else {
            failure = Failure.http(code)
            return completionHandler(.cancel)
        }
        // 200 to a Range request: the server sent the whole file again.
        if code == 200 { written = 0 }
        if !FileManager.default.fileExists(atPath: part.path) || code == 200 {
            FileManager.default.createFile(atPath: part.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: part)
        _ = try? handle?.seekToEnd()
        if handle == nil { failure = CocoaError(.fileWriteUnknown) }
        completionHandler(handle == nil ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do { try handle?.write(contentsOf: data) } catch {
            failure = error
            return dataTask.cancel()
        }
        written += Int64(data.count)
        if Date().timeIntervalSince(reported) > 0.2 {
            reported = Date()
            onBytes(before + written)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        let c = finished
        finished = nil
        if let failure { c?.resume(throwing: failure) }
        else if let error { c?.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error) }
        else { c?.resume() }
    }

    static func size(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func sha256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
