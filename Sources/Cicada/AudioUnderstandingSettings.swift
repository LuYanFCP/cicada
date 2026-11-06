import SwiftUI

/// The audio input model is independent of text generation and the voice spoken into the room.
struct AudioUnderstandingSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var client: LingClient
    @State private var base = ""
    @State private var audioModel = ""
    @State private var format = "openai"
    @State private var key = ""
    @State private var error: String?
    @State private var fetchedModels: [String] = []
    @State private var fetching = false

    var body: some View {
        SettingsCard {
            SettingsRow(title: L("语音理解"), divider: settings.audioUnderstanding) {
                PillMenu(value: settings.audioUnderstanding ? L("OpenAI 兼容接口") : defaultTitle,
                         options: [("default", defaultTitle), ("custom", L("OpenAI 兼容接口"))]) { choice in
                    settings.audioUnderstanding = choice == "custom"
                    error = nil
                    model.applyAudioUnderstanding()
                }
            }
            if settings.audioUnderstanding { fields.padding(16) }
        }
        .onAppear { sync() }
        .onChange(of: settings.audioBase) { _, value in base = value }
        .onChange(of: settings.audioModel) { _, value in audioModel = value }
        .onChange(of: settings.audioFormat) { _, value in format = value }
    }

    private var hasStoredKey: Bool { !(client.key ?? "").isEmpty }
    private var availableModels: [String] {
        if !fetchedModels.isEmpty { return fetchedModels }
        return base == settings.audioBase && format == settings.audioFormat && key.isEmpty ? client.catalog : []
    }
    private var defaultTitle: String { settings.provider.id == .ling ? L("默认服务（Ming）") : L("跟随 AI 服务") }
    private var hasEdits: Bool {
        base != settings.audioBase || audioModel != settings.audioModel || format != settings.audioFormat || !key.isEmpty
    }
    private var keyPlaceholder: String {
        if hasStoredKey { return L("已保存 key；留空保留") }
        return AIProvider.isNearby(base) ? L("本机和局域网服务可不填") : L("填写 API key")
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("接收音频并返回原文和译文，发声仍用原来的声音")
                .font(.system(size: 11)).foregroundStyle(Palette.tertiary).lineLimit(1)
            field(L("地址")) {
                TextField("https://api.example.com/v1", text: $base)
                    .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.ground))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
                    .onSubmit(save)
            }
            field(L("模型")) {
                VStack(alignment: .leading, spacing: 6) {
                    ServiceModelField(value: $audioModel, catalog: availableModels, placeholder: L("填写音频模型名称"))
                        .onSubmit(save)
                    readModelsButton
                }
            }
            field(L("接口格式")) {
                PillMenu(value: format == "ming" ? L("Ming 兼容") : "OpenAI",
                         options: [("openai", "OpenAI"), ("ming", L("Ming 兼容"))]) { format = $0 }
                Spacer(minLength: 0)
            }
            field("API key") {
                SecureField(keyPlaceholder, text: $key)
                    .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.ground))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
                    .onSubmit(save)
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
        .onChange(of: audioModel) { _, _ in error = nil }
        .onChange(of: format) { _, _ in error = nil; fetchedModels = [] }
        .onChange(of: key) { _, _ in error = nil; fetchedModels = [] }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12)).foregroundStyle(Palette.secondary).frame(width: 68, alignment: .leading)
            content()
        }
    }

    @ViewBuilder private var status: some View {
        if let error {
            statusLine(error, color: Palette.error)
        } else if !hasEdits {
            if client.aiCheck.running {
                statusLine(L("正在检查…"), color: Palette.secondary)
            } else if let failure = client.aiCheck.failure {
                if failure.reason == .noJSON {
                    statusLine(L("音频模型的返回格式不正确，请检查模型和接口格式"), color: Palette.error)
                } else if let message = client.aiCheck.message(service: client.serviceName, host: client.serviceHost, model: client.config().textModel) {
                    statusLine(message, color: Palette.error)
                }
                if client.aiCheck.needsLocalNetwork {
                    SoftButton(L("打开系统设置")) { model.openLocalNetworkSettings() }
                }
            } else if client.aiCheck.busy {
                statusLine(L("接口繁忙，请稍后再试"), color: Palette.warn)
            } else if client.aiCheck.passed {
                statusLine(L("检查通过，可接收音频并返回原文和译文"), color: Palette.ok)
            }
        }
    }

    private func statusLine(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }

    private var readModelsButton: some View {
        SoftButton(fetching ? L("正在读取…") : L("读取模型"), action: readModels)
            .disabled(fetching)
    }

    private func readModels() {
        guard !fetching else { return }
        let address = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedFormat = format
        guard let url = AIProvider.customBase(address) else {
            error = L("请填写有效地址；公网用 https，本机或局域网可用 http")
            return
        }
        guard !secret.contains(where: \.isWhitespace) else { error = L("key 不能含空格或换行"); return }
        let configuration = AIConfig.audio(base: address, model: "", format: AudioInputFormat(rawValue: selectedFormat) ?? .openai)
        guard !secret.isEmpty || client.hasStoredKey(for: configuration) || AIProvider.isNearby(url.absoluteString) else {
            error = L("请填写 API key")
            return
        }
        error = nil
        fetching = true
        Task {
            defer { fetching = false }
            do {
                let ids = try await client.availableAudioModels(for: configuration, key: secret)
                guard address == base.trimmingCharacters(in: .whitespacesAndNewlines), selectedFormat == format,
                      secret == key.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                fetchedModels = ids
                if ids.isEmpty { error = L("读不到模型列表，请手动填写") }
            } catch {
                guard address == base.trimmingCharacters(in: .whitespacesAndNewlines), selectedFormat == format,
                      secret == key.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                self.error = L("读不到模型列表，请手动填写")
            }
        }
    }

    private func save() {
        guard !client.aiCheck.running else { return }
        let address = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = audioModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = AIProvider.customBase(address) else {
            error = L("请填写有效地址；公网用 https，本机或局域网可用 http")
            return
        }
        guard !name.isEmpty else { error = L("请填写音频模型名称"); return }
        guard !name.contains(where: \.isWhitespace) else { error = L("模型名称不能含空格或换行"); return }
        guard !secret.contains(where: \.isWhitespace) else { error = L("key 不能含空格或换行"); return }
        let configuration = AIConfig.audio(base: address, model: name, format: AudioInputFormat(rawValue: format) ?? .openai)
        guard !secret.isEmpty || client.hasStoredKey(for: configuration) || AIProvider.isNearby(url.absoluteString) else {
            error = L("请填写 API key")
            return
        }
        if !secret.isEmpty, !client.saveKey(secret, for: configuration) {
            error = L("key 没有保存，请重试")
            return
        }
        settings.audioBase = address
        settings.audioModel = name
        settings.audioFormat = format
        error = nil
        key = ""
        model.applyAudioUnderstanding()
    }

    private func sync() {
        base = settings.audioBase
        audioModel = settings.audioModel
        format = settings.audioFormat
    }
}
