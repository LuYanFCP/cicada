import SwiftUI

/// One text endpoint for subtitles and notes; the audio service keeps its route.
struct SentenceTranslationSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var client: LingClient
    var serviceTitle: String? = nil
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var base = ""
    @State private var textModel = ""
    @State private var key = ""
    @State private var error: String?
    @State private var fetchedModels: [String] = []
    @State private var fetching = false

    var body: some View {
        SettingsCard {
            SettingsRow(title: L("翻译和纪要"), divider: settings.sentenceTranslation) {
                PillMenu(value: settings.sentenceTranslation ? L("OpenAI 兼容接口") : serviceTitle ?? L("跟随 AI 服务"),
                         options: [("service", serviceTitle ?? L("跟随 AI 服务")), ("custom", L("OpenAI 兼容接口"))]) { choice in
                    settings.sentenceTranslation = choice == "custom"
                    error = nil
                    model.applySentenceTranslation()
                }
            }
            if settings.sentenceTranslation {
                fields.padding(16)
            }
        }
        .onAppear { sync(); onEditingChanged(hasEdits) }
        .onChange(of: hasEdits) { _, editing in onEditingChanged(editing) }
        .onDisappear { onEditingChanged(false) }
        .onChange(of: settings.sentenceBase) { _, value in base = value }
        .onChange(of: settings.sentenceModel) { _, value in textModel = value }
    }

    private var hasStoredKey: Bool { !(client.key ?? "").isEmpty }
    private var availableModels: [String] {
        if !fetchedModels.isEmpty { return fetchedModels }
        return base == settings.sentenceBase && key.isEmpty ? client.catalog : []
    }
    private var hasEdits: Bool {
        base != settings.sentenceBase || textModel != settings.sentenceModel || !key.isEmpty
    }

    private var keyPlaceholder: String {
        if hasStoredKey { return L("已保存 key；留空保留") }
        return AIProvider.isNearby(base) ? L("本机和局域网服务可不填") : L("填写 API key")
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("纪要和文字记录的逐句翻译共用此接口")
                .font(.system(size: 11)).foregroundStyle(Palette.tertiary).lineLimit(1)
            field(L("地址")) {
                TextField("https://api.example.com/v1", text: $base)
            }
            HStack(spacing: 10) {
                Text("模型").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .frame(width: 54, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    ServiceModelField(value: $textModel, catalog: availableModels, placeholder: L("填写模型名称"))
                        .onSubmit(save)
                    readModelsButton
                }
            }
            field("API key") {
                SecureField(keyPlaceholder, text: $key)
            }
            HStack(spacing: 10) {
                SoftButton(client.aiCheck.running ? L("正在检查…") : L("保存并检查"), dark: true, action: save)
                    .disabled(client.aiCheck.running)
                if hasStoredKey {
                    Button("移除 key") { client.removeKey(); key = ""; error = nil }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
            }
            status
        }
        .onChange(of: base) { _, _ in error = nil; fetchedModels = [] }
        .onChange(of: textModel) { _, _ in error = nil }
        .onChange(of: key) { _, _ in error = nil; fetchedModels = [] }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                .frame(width: 54, alignment: .leading)
            content()
                .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.ground))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
                .onSubmit(save)
        }
    }

    @ViewBuilder private var status: some View {
        if let error {
            statusLine(error, color: Palette.error)
        } else if !hasEdits {
            if client.aiCheck.running {
                statusLine(L("正在检查…"), color: Palette.secondary)
            } else if let failure = client.aiCheck.failure {
                statusLine(failureText(failure.reason, code: failure.code), color: Palette.error)
                if client.aiCheck.needsLocalNetwork {
                    SoftButton(L("打开系统设置")) { model.openLocalNetworkSettings() }
                }
            } else if client.aiCheck.busy {
                statusLine(L("接口繁忙，请稍后再试"), color: Palette.warn)
            } else if let slow = client.aiCheck.slowLine() {
                statusLine(slow, color: Palette.warn)
            } else if client.aiCheck.passed {
                statusLine(L("检查通过，翻译和纪要将使用此接口"), color: Palette.ok)
            }
        }
    }

    private func statusLine(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }

    private func failureText(_ reason: AICheck.Reason, code: Int?) -> String {
        switch reason {
        case .badAddress: L("地址要用 https；这台 Mac 和局域网里的服务可以用 http。")
        case .unreachable: client.aiCheck.needsLocalNetwork ? L("知了没有本地网络权限") : L("连不上翻译接口，请检查地址或网络")
        case .invalidKey: L("翻译接口的 key 无效，请重新填写")
        case .mgmtKey: L("这个 key 不能调用模型，请更换 API key")
        case .noCredit: L("翻译接口的账户余额不足")
        case .noModel: L("找不到这个模型，请检查模型名称")
        case .noJSON: L("这个服务不支持 JSON，纪要写不了；翻译照常。")
        case .busy: L("接口繁忙，请稍后再试")
        case .serverError: code.map { L("接口暂时出错（HTTP \($0)）") } ?? L("翻译接口暂时出错，请稍后再试")
        }
    }

    private var readModelsButton: some View {
        SoftButton(fetching ? L("正在读取…") : L("读取模型"), action: readModels)
            .disabled(fetching)
    }

    private func readModels() {
        guard !fetching else { return }
        let address = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = AIProvider.customBase(address) else {
            error = L("请填写有效地址；公网用 https，本机或局域网可用 http")
            return
        }
        guard !secret.contains(where: \.isWhitespace) else { error = L("key 不能含空格或换行"); return }
        let configuration = AIConfig.sentence(base: address, model: "")
        guard !secret.isEmpty || client.hasStoredKey(for: configuration) || AIProvider.isNearby(url.absoluteString) else {
            error = L("请填写 API key")
            return
        }
        error = nil
        fetching = true
        Task {
            defer { fetching = false }
            do {
                let ids = try await client.availableTextModels(for: configuration, key: secret)
                guard address == base.trimmingCharacters(in: .whitespacesAndNewlines),
                      secret == key.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                fetchedModels = ids
                if ids.isEmpty { error = L("读不到模型列表，请手动填写") }
            } catch {
                guard address == base.trimmingCharacters(in: .whitespacesAndNewlines),
                      secret == key.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                self.error = L("读不到模型列表，请手动填写")
            }
        }
    }

    private func save() {
        guard !client.aiCheck.running else { return }
        let address = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = textModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = AIProvider.customBase(address) else {
            error = L("请填写有效地址；公网用 https，本机或局域网可用 http")
            return
        }
        guard !name.isEmpty else { error = L("请填写模型名称"); return }
        guard !name.contains(where: \.isWhitespace) else { error = L("模型名称不能含空格或换行"); return }
        guard !secret.contains(where: \.isWhitespace) else { error = L("key 不能含空格或换行"); return }
        let configuration = AIConfig.sentence(base: address, model: name)
        guard !secret.isEmpty || client.hasStoredKey(for: configuration) || AIProvider.isNearby(url.absoluteString) else {
            error = L("请填写 API key")
            return
        }
        if !secret.isEmpty, !client.saveKey(secret, for: configuration) {
            error = L("key 没有保存，请重试")
            return
        }
        settings.sentenceBase = address
        settings.sentenceModel = name
        error = nil
        key = ""
        model.applySentenceTranslation()
    }

    private func sync() {
        base = settings.sentenceBase
        textModel = settings.sentenceModel
    }
}
