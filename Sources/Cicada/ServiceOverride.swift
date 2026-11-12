import AppKit
import SwiftUI

/// Settings › AI 服务 › 按功能换服务: translation and notes, the meeting's speech recognition, or
/// audio understanding, on an OpenAI-compatible service of their own instead of the default.
/// Following, a row is one line that says what it uses. On its own service it opens to the address,
/// model and key, and folds back to that line (address, model, how the check went) once it works.
/// Speech recognition starts from Qwen3-ASR on this Mac (mlx-audio's server): nothing leaves the Mac.
/// It has a third choice where the build carries the engine, 内置: no address, model or key, only
/// which model and its download (`EngineForm`).
struct ServiceOverrideRow: View {
    enum Kind { case text, speech, audio }

    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var client: LingClient
    let kind: Kind
    var divider = true

    @State private var open = false
    @State private var base = ""
    @State private var modelName = ""
    @State private var format = AudioInputFormat.openai.rawValue
    @State private var key = ""
    /// A key is saved: it shows masked until 更换.
    @State private var replacingKey = false
    /// Audio only: the address came from 翻译和纪要, and its key goes with it when saved (never shown).
    @State private var reuseTextKey = false
    @State private var error: String?
    @State private var fetched: [String] = []
    @State private var fetching = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if builtIn && open {
                EngineForm(model: model, settings: settings, engine: model.engine, client: client)
                    .padding(.leading, 34).padding(.trailing, 16).padding(.bottom, 14)
            } else if on && open { form }
            if divider { Divider().padding(.leading, 16) }
        }
        .onAppear {
            sync()
            // Not set up, or not working: open where it needs filling in.
            open = needsAttention
        }
        .onChange(of: savedBase) { _, _ in sync() }
        .onChange(of: savedModel) { _, _ in sync() }
    }

    // MARK: Settings, by kind

    private var on: Bool {
        switch kind {
        case .text: settings.sentenceTranslation
        case .speech: settings.speechServer
        case .audio: settings.audioUnderstanding
        }
    }
    /// 语音识别 › 内置: the engine inside the app hears the meeting.
    private var builtIn: Bool { kind == .speech && settings.speechBuiltIn }
    private var engineModel: EngineModel { EngineModel.named(settings.speechEngineModel) }
    /// Everything it needs is filled in (or, for the engine, downloaded).
    private var ready: Bool { builtIn ? model.engine.installed(engineModel) : on && configured && client.hasKey }
    private var needsAttention: Bool { (on || builtIn) && (!ready || client.aiCheck.failure != nil) }
    private var choice: String { builtIn ? "engine" : on ? "custom" : "follow" }
    private var choices3: [(id: String, title: String)] {
        var options = [("follow", followTitle)]
        if kind == .speech, SpeechEngine.available { options.append(("engine", L("内置"))) }
        return options + [("custom", ownTitle)]
    }

    private var savedBase: String {
        switch kind {
        case .text: settings.sentenceBase
        case .speech: settings.speechBase
        case .audio: settings.audioBase
        }
    }
    private var savedModel: String {
        switch kind {
        case .text: settings.sentenceModel
        case .speech: settings.speechModel
        case .audio: settings.audioModel
        }
    }
    private var savedFormat: String { kind == .audio ? settings.audioFormat : AudioInputFormat.openai.rawValue }
    private var title: String {
        switch kind {
        case .text: L("翻译和纪要")
        case .speech: L("语音识别")
        case .audio: L("语音理解")
        }
    }
    private var configured: Bool { AIProvider.customBase(savedBase) != nil && !savedModel.isEmpty }

    private func configuration(base: String, model: String) -> AIConfig {
        switch kind {
        case .text: .sentence(base: base, model: model)
        case .speech: .speech(base: base, model: model)
        case .audio: .audio(base: base, model: model, format: AudioInputFormat(rawValue: format) ?? .openai)
        }
    }

    private func setOn(_ value: Bool) {
        switch kind {
        case .text: settings.sentenceTranslation = value
        case .speech: settings.speechServer = value
        case .audio: settings.audioUnderstanding = value
        }
    }

    private func apply() {
        switch kind {
        case .text: model.applySentenceTranslation()
        case .speech: model.applySpeechServer()
        case .audio: model.applyAudioUnderstanding()
        }
    }

    /// Following, for speech: this Mac's own engines on Apple silicon (an Intel Mac has none).
    private var followTitle: String { kind == .speech && !Recognition.cloudOnly ? L("本机") : L("同上") }
    private var ownTitle: String { kind == .speech ? L("自建服务") : L("兼容接口") }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            // Following, there is nothing to open: the line is just text.
            if on || builtIn {
                Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: { headerLabel }
                    .buttonStyle(.plain)
            } else {
                headerLabel
            }
            Segments(options: choices3, value: choice) { pick($0) }
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
    }

    private var headerLabel: some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 13)).foregroundStyle(Palette.ink)
                    if on || builtIn {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.secondary).rotationEffect(.degrees(open ? 90 : 0))
                    }
                }
                HStack(spacing: 6) {
                    // Three choices leave the engine's line room for one thing: the model, or what is wrong.
                    if !builtIn { Text(detail).foregroundStyle(Palette.tertiary).lineLimit(1).truncationMode(.middle) }
                    else if state == nil { EngineLine(engine: model.engine, model: engineModel) }
                    if let s = state { Text(s.text).foregroundStyle(s.color).lineLimit(1).fixedSize() }
                }
                .font(.system(size: 11))
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }

    /// What following means with the service above.
    private var followed: String {
        let p = settings.provider
        switch kind {
        case .text:
            return p.id == .custom ? L("用上面填的服务") : L("用 \(p.name)")
        case .speech:
            // Three choices leave the line less room (English runs wider).
            if !Recognition.cloudOnly { return SpeechEngine.available ? L("更快，不花钱") : L("更快，不花钱，声音不出这台 Mac") }
            if settings.audioUnderstanding { return L("用语音理解的模型") }
            return p.hearsAudio ? L("用 Ling 的 Ming") : L("还没有能听的服务")
        case .audio:
            if p.hearsAudio { return L("用 Ling 的 Ming") }
            return Recognition.cloudOnly ? L("还没有能听的服务") : L("本机识别后再翻译")
        }
    }

    private var detail: String {
        guard on else { return followed }
        guard configured, let host = AIProvider.customBase(savedBase)?.host else { return L("填上地址和模型") }
        // "mlx-community/Qwen3-ASR-1.7B-8bit" reads as its last part in one line.
        return "\(host) · \(savedModel.split(separator: "/").last.map(String.init) ?? savedModel)"
    }

    private var dot: Color {
        let check = client.aiCheck
        guard ready else { return Color(white: 0.75) }
        if check.running { return Palette.accent }
        if check.failure != nil { return Palette.error }
        if check.slow || check.busy { return Palette.warn }
        return check.passed ? Palette.ok : Color(white: 0.75)
    }

    /// How the last check went, after the address in the folded line.
    private var state: (text: String, color: Color)? {
        guard ready else { return nil }
        let check = client.aiCheck
        if check.running { return (L("正在检查…"), Palette.tertiary) }
        if let f = check.failure { return (shortProblem(f.reason), Palette.error) }
        if check.busy { return (L("很忙"), Palette.warn) }
        switch kind {
        case .text:
            guard let t = check.translate else { return check.passed ? (L("能用"), Palette.ok) : nil }
            return (L("翻一句 \(String(format: "%.1f", t.seconds)) 秒"), t.slow ? Palette.warn : Palette.tertiary)
        case .speech where builtIn: return nil
        case .speech, .audio:
            if case .ok(let s)? = check.hear { return (L("听一秒音频 \(String(format: "%.1f", s)) 秒"), Palette.tertiary) }
            return check.passed ? (L("能用"), Palette.ok) : nil
        }
    }

    private func shortProblem(_ reason: AICheck.Reason) -> String {
        switch reason {
        case .unreachable: builtIn ? L("没能启动") : client.aiCheck.localNetworkDenied ? L("没有本地网络权限") : L("暂时连不上")
        case .badAddress: L("地址不对")
        case .invalidKey, .mgmtKey: L("这个 key 用不了")
        case .noCredit: L("余额不足")
        case .noModel: L("模型用不了")
        case .noJSON: kind == .text ? L("不支持 JSON") : L("返回格式不对")
        case .busy: L("很忙")
        case .serverError: L("暂时出错")
        }
    }

    private func pick(_ picked: String) {
        guard picked != choice else { return }
        let custom = picked == "custom"
        if kind == .speech { settings.speechEngine = picked == "engine" }
        setOn(custom)
        error = nil
        if custom { sync() }
        apply()
        withAnimation(.easeOut(duration: 0.15)) { open = needsAttention }
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            if kind == .speech { speechHint }
            if canReuseText {
                Button(L("用翻译和纪要的地址和 key")) { reuseText() }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary).underline()
                    .padding(.leading, labelWidth + 8)
            }
            row(L("地址")) {
                TextField("https://api.example.com/v1", text: $base).modifier(FieldStyle()).onSubmit(save)
            }
            if !base.trimmingCharacters(in: .whitespaces).isEmpty, AIProvider.customBase(base) == nil {
                note(L("地址要用 https；这台 Mac 和局域网里的服务可以用 http。"), Palette.error)
            } else if let host = AIProvider.customBase(base)?.host, AIProvider.isNearby(host), !AIProvider.isLocal(host),
                      !client.aiCheck.needsLocalNetwork {
                note(L("局域网里的服务器：macOS 会问一次能否访问本地网络，点“允许”。"), Palette.tertiary)
            }
            row(L("模型")) {
                ModelNameField(value: $modelName, placeholder: kind == .audio ? L("填写音频模型名称") : L("填写模型名称"),
                               choices: choices, fetching: fetching, onFetch: readModels, onSubmit: save)
            }
            if kind == .audio {
                row(L("接口格式")) {
                    Segments(options: [("openai", "OpenAI"), ("ming", L("Ming 兼容"))], value: format) { format = $0 }
                    Spacer(minLength: 0)
                }
            }
            row("key") { keyField }
            HStack(spacing: 8) {
                SoftButton(client.aiCheck.running && !hasEdits ? L("正在检查…") : L("保存并检查"), dark: true, action: save)
                    .disabled(client.aiCheck.running && !hasEdits)
                if hasEdits && configured { SoftButton(L("取消"), action: revert) }
                Spacer(minLength: 0)
            }
            .padding(.leading, labelWidth + 8)
            status.padding(.leading, labelWidth + 8)
            lockLine
        }
        .padding(.leading, 34).padding(.trailing, 16).padding(.bottom, 14)
        .onChange(of: base) { old, new in
            error = nil
            fetched = []
            if reuseTextKey, new != settings.sentenceBase { reuseTextKey = false }
            // Ling's address takes Ming's format; leaving it goes back to OpenAI's. Only while typing:
            // the saved address coming back keeps the format saved with it.
            if kind == .audio, new != savedBase {
                let ling = AIProvider.ling.base?.host
                if AIProvider.customBase(new)?.host == ling { format = AudioInputFormat.ming.rawValue }
                else if AIProvider.customBase(old)?.host == ling { format = AudioInputFormat.openai.rawValue }
            }
        }
        .onChange(of: modelName) { _, _ in error = nil }
        .onChange(of: format) { _, _ in error = nil; fetched = [] }
        .onChange(of: key) { _, _ in error = nil; fetched = [] }
    }

    private let labelWidth: CGFloat = 64

    /// The recommended way, one line and where to read how to start it.
    private var speechHint: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Recognition.cloudOnly ? L("推荐 Qwen3-ASR，用 mlx-audio 跑在一台 Apple 芯片的 Mac 上。")
                                       : L("推荐在这台 Mac 上用 mlx-audio 跑 Qwen3-ASR，会议的声音不出这台 Mac。"))
                .font(.system(size: 11)).foregroundStyle(Palette.tertiary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(L("怎么启动 ↗")) { NSWorkspace.shared.open(Self.speechGuide) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize()
        }
    }

    /// The website's steps for running Qwen3-ASR with mlx-audio, in the UI language.
    static var speechGuide: URL {
        let lang = Bundle.main.preferredLocalizations.first ?? "zh"
        let prefix = ["en", "ja", "ko"].first { lang.hasPrefix($0) }.map { "/\($0)" } ?? ""
        return URL(string: "https://cicada.indaloop.app\(prefix)/start/#local-asr")!
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                .frame(width: labelWidth, alignment: .leading)
            content()
        }
    }

    private func note(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true).padding(.leading, labelWidth + 8)
    }

    /// The key saved for this kind of address, masked; else a field. Copied from 翻译和纪要, it
    /// says so instead.
    @ViewBuilder private var keyField: some View {
        if reuseTextKey && key.isEmpty {
            Text("同翻译和纪要的 key").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(Palette.ground))
            SoftButton(L("更换")) { reuseTextKey = false; replacingKey = true }
        } else if let saved = draftKey, !saved.isEmpty, !replacingKey {
            Text(AIKey.masked(saved)).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line, lineWidth: 1))
            SoftButton(L("更换")) { key = ""; replacingKey = true }
        } else {
            SecureField(keyPlaceholder, text: $key).modifier(FieldStyle()).onSubmit(save)
        }
    }

    private var lockLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
            Text(L("key 只存在这台 Mac 上（只有你的账户能读），只发给 \(AIProvider.customBase(base)?.host ?? L("你填的地址"))"))
                .font(.system(size: 11)).foregroundStyle(Palette.tertiary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let saved = client.key, !saved.isEmpty {
                Button("移除 key") { client.removeKey(); key = ""; replacingKey = false; error = nil }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder private var status: some View {
        if let error {
            line(error, Palette.error)
        } else if hasEdits {
            line(L("改动还没保存"), Palette.tertiary)
        } else if client.hasKey {
            let check = client.aiCheck
            if check.running {
                line(kind == .speech && AIProvider.isNearby(savedBase) ? L("正在检查…第一次要加载模型，可能要几分钟")
                                                                         : L("正在检查…"), Palette.secondary)
            } else if let failure = check.failure {
                line(problem(failure.reason, code: failure.code), Palette.error)
                if check.needsLocalNetwork {
                    HStack(spacing: 8) {
                        SoftButton(L("打开系统设置"), dark: true) { model.openLocalNetworkSettings() }
                        SoftButton(L("重新检查")) { Task { await client.check() } }
                    }
                } else if failure.reason == .unreachable || failure.reason == .busy || failure.reason == .serverError {
                    SoftButton(L("重新检查")) { Task { await client.check() } }
                }
            } else if check.busy {
                line(L("接口繁忙，请稍后再试"), Palette.warn)
            } else if let slow = check.slowLine() {
                line(slow, Palette.warn)
            } else if check.passed {
                line(passedLine, Palette.ok)
            }
        }
    }

    private var passedLine: String {
        switch kind {
        case .text: L("检查通过，翻译和纪要将使用此接口")
        case .speech: Recognition.cloudOnly ? L("检查通过，下一场会议起用它识别")
            : L("检查通过，下一场会议起用它识别；连不上时自动换回本机")
        case .audio: L("检查通过，可接收音频并返回原文和译文")
        }
    }

    private func line(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }

    private func problem(_ reason: AICheck.Reason, code: Int?) -> String {
        switch reason {
        case .badAddress: return L("地址要用 https；这台 Mac 和局域网里的服务可以用 http。")
        case .unreachable:
            if client.aiCheck.needsLocalNetwork { return L("知了没有本地网络权限") }
            if kind == .speech, AIProvider.isLocal(savedBase) {
                // It took the request and said nothing for 20 minutes: the model is still on its way.
                if client.aiCheck.timedOut { return L("服务还没听完一秒音频：模型可能还在下载或加载，等启动服务的终端窗口里加载完，再点重新检查。") }
                // A server on this Mac that refuses the connection isn't running.
                return L("这台 Mac 上的识别服务没在运行：先启动它，再点重新检查。")
            }
            return L("连不上这个地址，请检查地址或网络")
        case .invalidKey: return L("这个 key 无效，请重新填写")
        case .mgmtKey: return L("这个 key 不能调用模型，请更换 API key")
        case .noCredit: return L("这个账户余额不足")
        case .noModel:
            // mlx-audio answers 404 when the model's download failed too (an expired Hugging Face
            // token, a proxy that drops it), not only for a wrong name.
            if kind == .speech, AIProvider.isLocal(savedBase) {
                return L("服务找不到这个模型。名称没错的话，多半是第一次下载没成功，看看启动服务的终端窗口里的报错。")
            }
            return L("找不到这个模型，请检查模型名称")
        case .noJSON:
            switch kind {
            case .text: return L("这个服务不支持 JSON，纪要写不了；翻译照常。")
            case .speech: return L("返回的不是识别结果，请确认地址是语音识别服务（/audio/transcriptions）")
            case .audio: return L("音频模型的返回格式不正确，请检查模型和接口格式")
            }
        case .busy: return L("接口繁忙，请稍后再试")
        case .serverError: return code.map { L("接口暂时出错（HTTP \($0)）") } ?? L("接口暂时出错，请稍后再试")
        }
    }

    // MARK: Drafts

    private var hasEdits: Bool {
        base != savedBase || modelName != savedModel || format != savedFormat || !key.isEmpty || reuseTextKey
    }

    /// The key that would go with the address being typed (saved keys are per kind of service).
    private var draftKey: String? {
        guard AIProvider.customBase(base) != nil else { return nil }
        return client.storedKey(for: configuration(base: base, model: modelName))
    }

    private var keyPlaceholder: String {
        AIProvider.isNearby(base) ? L("本机和局域网服务可不填") : L("填写 API key")
    }

    /// The list read just now; else, for the saved address, the one the last check read.
    private var choices: [String] {
        if !fetched.isEmpty { return fetched }
        return base == savedBase && format == savedFormat && key.isEmpty ? client.catalog : []
    }

    private var textConfig: AIConfig? { settings.sentenceTranslation ? settings.sentenceConfig : nil }
    private var textKey: String? { textConfig.flatMap { model.sentenceAI.storedKey(for: $0) } }

    private var canReuseText: Bool {
        kind == .audio && base.trimmingCharacters(in: .whitespaces).isEmpty && textConfig?.base != nil
    }

    private func reuseText() {
        base = settings.sentenceBase
        reuseTextKey = textKey != nil
        key = ""
        replacingKey = false
        readModels()
    }

    /// The saved fields; speech recognition with nothing saved starts from the recommended
    /// server, to save and check as it is.
    private func sync() {
        let fresh = kind == .speech && savedBase.isEmpty && savedModel.isEmpty
        base = fresh ? AIConfig.recommendedSpeech.base : savedBase
        modelName = fresh ? AIConfig.recommendedSpeech.model : savedModel
        format = savedFormat
    }

    private func revert() {
        sync()
        key = ""
        replacingKey = false
        reuseTextKey = false
        error = nil
        fetched = []
    }

    /// What was typed, or the key it would use: the typed one, 翻译和纪要's, then the saved one.
    private var typedKey: String {
        let typed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty, reuseTextKey, let textKey { return textKey }
        return typed
    }

    private func readModels() {
        guard !fetching else { return }
        let address = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = typedKey
        guard let url = AIProvider.customBase(address) else {
            error = L("请填写有效地址；公网用 https，本机或局域网可用 http")
            return
        }
        guard !secret.contains(where: \.isWhitespace) else { error = L("key 不能含空格或换行"); return }
        let c = configuration(base: address, model: "")
        guard !secret.isEmpty || client.hasStoredKey(for: c) || AIProvider.isNearby(url.absoluteString) else {
            error = L("先填 key 再读取模型")
            return
        }
        error = nil
        fetching = true
        let asked = (address, format, key)
        Task {
            defer { fetching = false }
            let ids: [String]?
            switch kind {
            case .text: ids = try? await client.availableTextModels(for: c, key: secret)
            case .speech: ids = try? await client.availableSpeechModels(for: c, key: secret)
            case .audio: ids = try? await client.availableAudioModels(for: c, key: secret)
            }
            // Typed over while it was reading: the answer belongs to another address or key.
            guard asked == (base.trimmingCharacters(in: .whitespacesAndNewlines), format, key) else { return }
            fetched = ids ?? []
            if fetched.isEmpty { error = L("读不到模型列表，请手动填写") }
        }
    }

    private func save() {
        let address = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = typedKey
        guard let url = AIProvider.customBase(address) else {
            error = L("请填写有效地址；公网用 https，本机或局域网可用 http")
            return
        }
        guard !name.isEmpty else { error = kind == .audio ? L("请填写音频模型名称") : L("请填写模型名称"); return }
        guard !name.contains(where: \.isWhitespace) else { error = L("模型名称不能含空格或换行"); return }
        guard !secret.contains(where: \.isWhitespace) else { error = L("key 不能含空格或换行"); return }
        let c = configuration(base: address, model: name)
        guard !secret.isEmpty || client.hasStoredKey(for: c) || AIProvider.isNearby(url.absoluteString) else {
            error = L("请填写 API key")
            return
        }
        // Saved before the address changes: a request starting right after must not take the old key.
        if !secret.isEmpty, !client.saveKey(secret, for: c) {
            error = L("key 没有保存，请重试")
            return
        }
        switch kind {
        case .text:
            settings.sentenceBase = address
            settings.sentenceModel = name
        case .speech:
            settings.speechBase = address
            settings.speechModel = name
        case .audio:
            settings.audioBase = address
            settings.audioModel = name
            settings.audioFormat = format
        }
        sync()
        error = nil
        key = ""
        replacingKey = false
        reuseTextKey = false
        fetched = []
        apply()
    }
}

/// A model name typed by hand, with the service's list beside it: "读取模型" asks for it, then a
/// menu offers it (long lists by maker). Picking one only fills the field.
struct ModelNameField: View {
    @Binding var value: String
    let placeholder: String
    let choices: [String]
    let fetching: Bool
    let onFetch: () -> Void
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $value).modifier(FieldStyle()).onSubmit(onSubmit)
            if choices.isEmpty {
                SoftButton(fetching ? L("正在读取…") : L("读取模型"), action: onFetch).disabled(fetching)
            } else {
                Menu {
                    if choices.count > 20 {
                        ForEach(ModelMenu.groups(choices), id: \.0) { maker, ids in
                            Menu(maker) { ForEach(ids, id: \.self) { id in Button(id) { value = id } } }
                        }
                    } else {
                        ForEach(choices, id: \.self) { id in Button(id) { value = id } }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(L("选一个")).font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Palette.ink).padding(.horizontal, 12).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.925)))
                    .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help(L("\(choices.count) 个模型"))
            }
        }
    }
}

/// The white, outlined text field of the AI settings.
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
            .padding(.horizontal, 12).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line, lineWidth: 1))
    }
}

/// 语音识别 › 内置, folded: the model and where it stands.
private struct EngineLine: View {
    @ObservedObject var engine: SpeechEngine
    let model: EngineModel

    var body: some View {
        Text(text).foregroundStyle(Palette.tertiary).lineLimit(1)
    }

    private var text: String {
        if let p = engine.progress, p.model == model.id { return L("正在下载 \(Int(p.fraction * 100))%") }
        return engine.installed(model) ? model.name : L("要先下载模型")
    }
}

/// 语音识别 › 内置, open: which model, its download, and how the check of it went. Nothing to
/// type: the engine is in the app, and the model comes from Hugging Face checked against its hash.
private struct EngineForm: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: SpeechEngine
    @ObservedObject var client: LingClient

    private var picked: EngineModel { EngineModel.named(settings.speechEngineModel) }
    private var fetching: SpeechEngine.Progress? { engine.progress.flatMap { $0.model == picked.id ? $0 : nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("知了自带的 Qwen3-ASR 引擎：不用装别的，会议的声音不出这台 Mac。")
                .font(.system(size: 11)).foregroundStyle(Palette.tertiary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("模型").font(.system(size: 12)).foregroundStyle(Palette.secondary).frame(width: 64, alignment: .leading)
                Segments(options: EngineModel.all.map { ($0.id, "\($0.name) · \(Self.size($0.bytes))") }, value: picked.id) { id in
                    guard id != picked.id, engine.progress == nil else { return }
                    settings.speechEngineModel = id
                    model.applySpeechServer()
                }
                Spacer(minLength: 0)
            }
            Group {
                if let p = fetching {
                    HStack(spacing: 10) {
                        ProgressView(value: p.fraction).frame(maxWidth: 220)
                        Text("\(Self.size(p.received)) / \(Self.size(p.total))").font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Palette.secondary)
                        SoftButton(L("取消")) { engine.cancelFetch() }
                    }
                } else if !engine.installed(picked) {
                    HStack(spacing: 10) {
                        SoftButton(L("下载模型（\(Self.size(picked.bytes))）"), dark: true) { engine.fetch(picked) }
                            .disabled(engine.progress != nil)
                        if let problem = engine.problem { line(problem, Palette.error) }
                    }
                } else {
                    status
                }
            }
            .padding(.leading, 72)
        }
    }

    @ViewBuilder private var status: some View {
        let check = client.aiCheck
        HStack(spacing: 10) {
            if check.running {
                line(L("正在检查…第一次要加载模型，可能要几分钟"), Palette.secondary)
            } else if let failure = check.failure {
                line(failure.reason == .unreachable ? L("内置引擎没能启动，会议先用本机识别。")
                     : failure.code.map { L("内置引擎出错了（HTTP \($0)），会议先用本机识别。") } ?? L("内置引擎出错了，会议先用本机识别。"),
                     Palette.error)
                SoftButton(L("重新检查")) { Task { await client.check() } }
            } else if check.passed {
                line(L("检查通过，下一场会议起用它识别；启动不了时自动换回本机"), Palette.ok)
            }
            Spacer(minLength: 0)
            if engine.owns(picked), !check.running {
                Button("删除模型") { engine.delete(picked) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
        }
    }

    private func line(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }

    /// "2.5 GB", "713 MB": decimal, as download sizes are quoted.
    static func size(_ bytes: Int64) -> String {
        bytes >= 1_000_000_000 ? String(format: "%.1f GB", Double(bytes) / 1e9) : String(format: "%.0f MB", Double(bytes) / 1e6)
    }
}
