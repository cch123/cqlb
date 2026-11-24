import SwiftUI

struct AboutView: View {
    let accent: Color

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        if let build = info?["CFBundleVersion"] as? String, build != short {
            return "\(short) (\(build))"
        }
        return short
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                Text("两")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(accent.gradient, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                    )
                    .shadow(color: accent.opacity(0.5), radius: 18, y: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text("超强两笔")
                        .font(.system(size: 24, weight: .bold))
                    Text("版本 \(appVersion)")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("基于超强两笔码表的 macOS 输入法，最多四键上屏。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .glassSurface(cornerRadius: 20)

            Card {
                if let url = URL(string: "https://github.com/cch123/cqlb") {
                    Link(destination: url) {
                        SettingRow("项目主页", hint: "github.com/cch123/cqlb") {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Card("致谢") {
                credit("超强两笔码表 8.1.3", "付东升")
                RowDivider()
                credit("码表格式", "Rime")
                RowDivider()
                credit("Emoji 数据", "OpenCC")
            }
        }
    }

    private func credit(_ title: String, _ name: String) -> some View {
        SettingRow(title) {
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}
