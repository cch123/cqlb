import SwiftUI
import CqlbCore

private func swiftUIColor(for c: Config.Appearance.AccentColor) -> Color {
    switch c {
    case .red:    return .red
    case .orange: return .orange
    case .green:  return .green
    case .blue:   return .blue
    case .purple: return .purple
    case .teal:   return .teal
    }
}

struct AppearanceView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 20) {
            GlassPanel("字体") {
                VStack(spacing: 14) {
                    GlassRow("字体") {
                        TextField("PingFang SC", text: $model.config.appearance.font)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                    }
                    GlassDivider()
                    GlassRow("字号") {
                        HStack(spacing: 10) {
                            Slider(
                                value: $model.config.appearance.fontSize,
                                in: 10...32,
                                step: 1
                            )
                            .frame(width: 180)
                            Text("\(Int(model.config.appearance.fontSize)) pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }

            GlassPanel("候选窗口") {
                VStack(spacing: 14) {
                    GlassRow("每页候选数") {
                        Stepper(
                            value: $model.config.appearance.candidateCount,
                            in: 1...9
                        ) {
                            Text("\(model.config.appearance.candidateCount)")
                                .monospacedDigit()
                        }
                        .frame(width: 110)
                    }
                    GlassDivider()
                    GlassRow("布局") {
                        Picker("", selection: $model.config.appearance.layout) {
                            Text("横向").tag(Config.Appearance.Layout.horizontal)
                            Text("纵向").tag(Config.Appearance.Layout.vertical)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .labelsHidden()
                    }
                    GlassDivider()
                    GlassRow("颜色方案") {
                        Picker("", selection: $model.config.appearance.colorScheme) {
                            Text("跟随系统").tag(Config.Appearance.ColorScheme.system)
                            Text("浅色").tag(Config.Appearance.ColorScheme.light)
                            Text("深色").tag(Config.Appearance.ColorScheme.dark)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                        .labelsHidden()
                    }
                    GlassDivider()
                    GlassRow("强调色") {
                        HStack(spacing: 8) {
                            ForEach(Config.Appearance.AccentColor.allCases, id: \.self) { color in
                                Circle()
                                    .fill(swiftUIColor(for: color))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle().strokeBorder(.white.opacity(
                                            model.config.appearance.accentColor == color ? 0.9 : 0
                                        ), lineWidth: 2)
                                    )
                                    .shadow(color: swiftUIColor(for: color).opacity(
                                        model.config.appearance.accentColor == color ? 0.5 : 0
                                    ), radius: 4)
                                    .onTapGesture {
                                        model.config.appearance.accentColor = color
                                    }
                            }
                        }
                    }
                }
            }
        }
    }
}
