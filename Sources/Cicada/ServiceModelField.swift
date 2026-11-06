import SwiftUI

/// Typing and choosing a fetched model both update the same draft immediately.
struct ServiceModelField: View {
    @Binding var value: String
    let catalog: [String]
    let placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $value)
                .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.ground))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
            if !catalog.isEmpty {
                Menu {
                    ForEach(catalog, id: \.self) { id in Button(id) { value = id } }
                } label: {
                    HStack(spacing: 6) {
                        Text(L("选一个")).font(.system(size: 12))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Palette.ink).padding(.horizontal, 10).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Palette.ground))
                    .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel(L("模型"))
            }
        }
    }
}
