import AppKit
import SwiftUI
import CqlbCore

extension Config.Appearance.AccentColor {
    var color: Color {
        switch self {
        case .red:    return .red
        case .orange: return .orange
        case .green:  return .green
        case .blue:   return .blue
        case .purple: return .purple
        case .teal:   return .teal
        }
    }

    var label: String {
        switch self {
        case .red:    return "红色"
        case .orange: return "橙色"
        case .green:  return "绿色"
        case .blue:   return "蓝色"
        case .purple: return "紫色"
        case .teal:   return "青色"
        }
    }
}

struct AppearanceView: View {
    @Bindable var model: SettingsModel

    /// Installed families, CJK-capable ones first. A free-text field let
    /// users save misspelled names that silently fell back to the system font.
    static let fontFamilies: (cjk: [String], other: [String]) = {
        let all = NSFontManager.shared.availableFontFamilies
        let probe = "两笔" as NSString
        func coversCJK(_ family: String) -> Bool {
            guard let font = NSFont(name: family, size: 13) else { return false }
            let set = font.coveredCharacterSet
            return (0..<probe.length).allSatisfy {
                guard let scalar = Unicode.Scalar(probe.character(at: $0)) else { return false }
                return set.contains(scalar)
            }
        }
        let cjk = all.filter(coversCJK)
        let cjkSet = Set(cjk)
        return (cjk, all.filter { !cjkSet.contains($0) })
    }()

    private var fontInstalled: Bool {
        Self.fontFamilies.cjk.contains(model.config.appearance.font)
            || Self.fontFamilies.other.contains(model.config.appearance.font)
    }

    /// Slider without tick marks: bind to a rounded value instead of using
    /// `step:`, which draws one tick per step.
    private var fontSize: Binding<Double> {
        Binding(
            get: { model.config.appearance.fontSize },
            set: { model.config.appearance.fontSize = $0.rounded() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PreviewStage(
                appearance: model.config.appearance,
                showAnnotation: model.config.functions.reverseLookupDisplay != .none
            )

            Card("颜色") {
                SettingRow("外观") {
                    Picker("", selection: $model.config.appearance.colorScheme) {
                        Text("跟随系统").tag(Config.Appearance.ColorScheme.system)
                        Text("浅色").tag(Config.Appearance.ColorScheme.light)
                        Text("深色").tag(Config.Appearance.ColorScheme.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 230)
                }
                RowDivider()
                SettingRow("强调色", hint: "同时用于候选窗口和本窗口") {
                    HStack(spacing: 9) {
                        ForEach(Config.Appearance.AccentColor.allCases, id: \.self) { accent in
                            AccentSwatch(
                                accent: accent,
                                selected: model.config.appearance.accentColor == accent
                            ) {
                                model.config.appearance.accentColor = accent
                            }
                        }
                    }
                }
            }

            Card("候选窗口") {
                SettingRow("布局") {
                    Picker("", selection: $model.config.appearance.layout) {
                        Text("横排").tag(Config.Appearance.Layout.horizontal)
                        Text("竖排").tag(Config.Appearance.Layout.vertical)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }
                RowDivider()
                SettingRow("光效", hint: "流光描边、高亮光晕和染色玻璃") {
                    Toggle("", isOn: $model.config.appearance.glow)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                RowDivider()
                SettingRow("显示编码行", hint: "在候选词上方再显示一遍已输入的编码") {
                    Toggle("", isOn: $model.config.appearance.showPreedit)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                RowDivider()
                SettingRow("每页候选数") {
                    Picker("", selection: $model.config.appearance.candidateCount) {
                        ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            Card("字体") {
                SettingRow("字体", hint: fontInstalled ? nil : "未安装该字体，将使用系统字体") {
                    Picker("", selection: $model.config.appearance.font) {
                        if !fontInstalled {
                            Text(model.config.appearance.font).tag(model.config.appearance.font)
                            Divider()
                        }
                        ForEach(Self.fontFamilies.cjk, id: \.self) { Text($0).tag($0) }
                        Divider()
                        ForEach(Self.fontFamilies.other, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                RowDivider()
                SettingRow("字号") {
                    HStack(spacing: 10) {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(.secondary)
                        Slider(value: fontSize, in: 10...32)
                            .frame(width: 170)
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(.secondary)
                        Text("\(Int(model.config.appearance.fontSize)) pt")
                            .font(.system(size: 12.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// Accent swatch: a gradient disc; the selected one gains an outer ring.
private struct AccentSwatch: View {
    let accent: Config.Appearance.AccentColor
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(accent.color.gradient)
                .frame(width: 20, height: 20)
                .shadow(color: accent.color.opacity(selected ? 0.55 : 0), radius: 5)
                .padding(3)
                .overlay(
                    Circle().strokeBorder(accent.color, lineWidth: 2).opacity(selected ? 1 : 0)
                )
                .scaleEffect(hovering && !selected ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: selected)
        .animation(.snappy(duration: 0.15), value: hovering)
        .accessibilityLabel(accent.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(accent.label)
    }
}

/// Hero area: the candidate-window preview floating over a gradient in the
/// accent color, the way the real window floats over a document.
private struct PreviewStage: View {
    let appearance: Config.Appearance
    let showAnnotation: Bool

    private var accent: Color { appearance.accentColor.color }

    var body: some View {
        ZStack {
            // Gradient stage.
            ZStack {
                Rectangle().fill(accent.gradient)
                Circle()
                    .fill(accent)
                    .hueRotation(.degrees(55))
                    .frame(width: 320)
                    .blur(radius: 70)
                    .offset(x: 190, y: 70)
                Circle()
                    .fill(accent)
                    .hueRotation(.degrees(-50))
                    .frame(width: 260)
                    .blur(radius: 70)
                    .offset(x: -220, y: -80)
                Circle()
                    .fill(.white.opacity(0.22))
                    .frame(width: 200)
                    .blur(radius: 60)
                    .offset(x: -60, y: -110)
            }
            .saturation(1.15)

            CandidatePreview(appearance: appearance, showAnnotation: showAnnotation)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 216)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: accent.opacity(0.35), radius: 22, y: 10)
    }
}

/// Live mock of the candidate window. Mirrors `CandidateView` in the IME:
/// accent pill behind the highlighted candidate, next-key hints, optional
/// code row, capsule panel in horizontal layout.
private struct CandidatePreview: View {
    let appearance: Config.Appearance
    let showAnnotation: Bool

    /// (text, keys still to type after the sample preedit "ld")
    private static let samples: [(text: String, hint: String)] = [
        ("两", ""), ("笔", "b"), ("输入", "c"), ("法", "gk"), ("超强", "h"),
    ]

    private var size: CGFloat { CGFloat(min(max(appearance.fontSize, 10), 32)) }
    private var small: CGFloat { max(10, (size * 0.68).rounded()) }
    private var accent: Color { appearance.accentColor.color }
    private var horizontal: Bool { appearance.layout == .horizontal }
    /// The preview illustrates style, not page size: cap the rows so a
    /// vertical 9-candidate page still fits the stage.
    private var items: [(text: String, hint: String)] {
        let cap = horizontal ? 4 : 3
        return Array(Self.samples.prefix(min(max(appearance.candidateCount, 1), cap)))
    }
    private var candidateFont: Font {
        NSFont(name: appearance.font, size: size) != nil
            ? .custom(appearance.font, fixedSize: size)
            : .system(size: size, weight: .medium)
    }
    private var forcedScheme: SwiftUI.ColorScheme? {
        switch appearance.colorScheme {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
    private var rowHeight: CGFloat { max(28, size + 14) }
    private var panelRadius: CGFloat {
        if horizontal { return appearance.showPreedit ? 16 : (rowHeight + 12) / 2 }
        return min(10, rowHeight / 2) + 6
    }

    var body: some View {
        let panel = VStack(alignment: .leading, spacing: 2) {
            if appearance.showPreedit {
                Text("ld")
                    .font(.system(size: max(11, size - 4), weight: .medium, design: .monospaced))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 9)
                    .frame(height: max(22, size + 6))
            }
            if horizontal {
                HStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        candidate(i, item)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        candidate(i, item)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(6)
        // Near-opaque: the stage behind is saturated, and a thin material
        // would tint the panel with it and wash out the accent-colored text.
        .background(
            Color(nsColor: .windowBackgroundColor).opacity(0.86),
            in: RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
        )
        .overlay {
            if appearance.glow {
                // Static stand-in for the IME's flowing border light.
                RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                    .strokeBorder(
                        AngularGradient(
                            colors: [.clear, accent, .white, accent, .clear, .clear, accent.opacity(0.8), .clear, .clear],
                            center: .center,
                            angle: .degrees(200)
                        ),
                        lineWidth: 1.5
                    )
            }
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
        .fixedSize()
        .animation(.snappy(duration: 0.22), value: appearance)

        if let forcedScheme {
            panel.environment(\.colorScheme, forcedScheme)
        } else {
            panel
        }
    }

    private func candidate(_ index: Int, _ item: (text: String, hint: String)) -> some View {
        let on = index == 0
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(index + 1)")
                .font(.system(size: small, weight: .medium).monospacedDigit())
                .foregroundStyle(on ? AnyShapeStyle(.white.opacity(0.72)) : AnyShapeStyle(.secondary))
            Text(item.text)
                .font(candidateFont)
                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            if showAnnotation && !item.hint.isEmpty {
                Text(item.hint)
                    .font(.system(size: small, weight: .semibold, design: .monospaced))
                    .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(accent))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 11)
        .frame(height: rowHeight)
        .frame(maxWidth: horizontal ? nil : .infinity, alignment: .leading)
        .background {
            if on {
                let shape = RoundedRectangle(
                    cornerRadius: horizontal ? rowHeight / 2 : min(10, rowHeight / 2),
                    style: .continuous
                )
                if appearance.glow {
                    // Two-hue sweep with a glow, as in the IME.
                    shape.fill(accent)
                        .overlay(
                            shape.fill(accent)
                                .hueRotation(.degrees(38))
                                .mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing))
                        )
                        .shadow(color: accent.opacity(0.65), radius: 7)
                } else {
                    shape.fill(accent.gradient)
                }
            }
        }
    }
}
