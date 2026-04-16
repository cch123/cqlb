import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            GlassPanel {
                HStack(spacing: 16) {
                    Text("两")
                        .font(.system(size: 48, weight: .bold))
                        .frame(width: 76, height: 76)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.tint)
                        )
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("超强两笔")
                            .font(.title.bold())
                        Text("cqlb · 版本 0.1.0")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            GlassPanel("关于") {
                Text("基于 Rime 的超强两笔码表,使用 Option+Space 切换中英文的外挂式 macOS 输入法。通过 CGEventTap 捕获键盘事件、Accessibility 权限注入文本。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            GlassPanel("致谢") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("付东升 — 超强两笔码表 (8.1.3)", systemImage: "person.fill")
                    Label("Rime Input Method Engine", systemImage: "character.textbox")
                    Label("OpenCC — Emoji 数据", systemImage: "face.smiling")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}
