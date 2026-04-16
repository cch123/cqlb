import SwiftUI
import CqlbCore

struct ShortcutsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 20) {
            GlassPanel("激活 / 切换") {
                VStack(spacing: 14) {
                    GlassRow("中英文切换", hint: "按一次进入中文,再按一次退出") {
                        KeyBadge("⌥ Space")
                    }
                    GlassDivider()
                    GlassRow("清空输入", hint: "按退格或 Esc 清空当前输入") {
                        KeyBadge("Esc")
                    }
                }
            }

            GlassPanel("候选窗口") {
                VStack(spacing: 14) {
                    GlassRow("选择候选词") { KeyBadge("1 – 9") }
                    GlassDivider()
                    GlassRow("上屏首候选") { KeyBadge("Space") }
                    GlassDivider()
                    GlassRow("上屏原始输入") { KeyBadge("Enter") }
                    GlassDivider()
                    GlassRow("翻页") { KeyBadge("↑ / ↓") }
                }
            }
        }
    }
}

struct KeyBadge: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(.callout, design: .monospaced).weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            )
    }
}
