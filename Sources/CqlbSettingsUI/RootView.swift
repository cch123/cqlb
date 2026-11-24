import SwiftUI
import AppKit
import CqlbCore

/// Settings root.
///
/// Visual structure, back to front:
///
///     Backdrop        window-sized soft glow tinted by the accent color
///     glass surfaces  floating sidebar panel + content cards (Liquid Glass
///                     on macOS 26+, material fallback before that)
///     controls        stock AppKit/SwiftUI controls, tinted with the accent
///
/// The backdrop exists to give the glass something to refract; glass over a
/// flat window background reads as a plain gray card.
struct RootView: View {
    @Bindable var model: SettingsModel
    /// `CQLB_SETTINGS_PANE` selects the initial pane; used by the
    /// `cqlb-settings-preview` dev tool to snapshot a specific pane.
    @State private var selection: Pane =
        Pane(rawValue: ProcessInfo.processInfo.environment["CQLB_SETTINGS_PANE"] ?? "") ?? .appearance
    @Namespace private var sidebarSelection

    enum Pane: String, CaseIterable, Identifiable, Hashable {
        case appearance = "外观"
        case functions  = "功能"
        case shortcuts  = "快捷键"
        case about      = "关于"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .appearance: return "paintbrush.pointed.fill"
            case .functions:  return "wand.and.stars"
            case .shortcuts:  return "command"
            case .about:      return "info"
            }
        }

        var tile: Color {
            switch self {
            case .appearance: return .pink
            case .functions:  return .indigo
            case .shortcuts:  return .orange
            case .about:      return .gray
            }
        }

        var subtitle: String {
            switch self {
            case .appearance: return "候选窗口的字体、布局和配色"
            case .functions:  return "输入辅助、候选词过滤和用户词库"
            case .shortcuts:  return "切换中英文和操作候选词的按键"
            case .about:      return "版本信息与致谢"
            }
        }
    }

    private var accent: Color { model.config.appearance.accentColor.color }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 208)
                .padding(10)
            detail
        }
        .background(Backdrop(accent: accent))
        .tint(accent)
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.45), value: model.config.appearance.accentColor)
        // Settings apply immediately; writes are debounced inside the model.
        .onChange(of: model.config) { _, _ in
            model.scheduleSave()
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Clearance for the window's traffic-light buttons.
            Color.clear.frame(height: 40)

            HStack(spacing: 10) {
                Text("两")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(accent.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: accent.opacity(0.45), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("超强两笔")
                        .font(.system(size: 14, weight: .semibold))
                    Text("输入法设置")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)

            ForEach(Pane.allCases) { pane in
                sidebarItem(pane)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassSurface(cornerRadius: 18)
    }

    private func sidebarItem(_ pane: Pane) -> some View {
        let selected = pane == selection
        return Button {
            withAnimation(.snappy(duration: 0.28)) { selection = pane }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: pane.icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(pane.tile.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(pane.rawValue)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.primary.opacity(0.14))
                        .matchedGeometryEffect(id: "selection", in: sidebarSelection)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Detail

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection.rawValue)
                        .font(.system(size: 28, weight: .bold))
                    Text(selection.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)

                switch selection {
                case .appearance: AppearanceView(model: model)
                case .functions:  FunctionsView(model: model)
                case .shortcuts:  ShortcutsView(model: model)
                case .about:      AboutView(accent: accent)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 28)
            .padding(.top, 46)
            .padding(.bottom, 28)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .id(selection)
        .transition(.opacity.combined(with: .offset(y: 8)))
    }
}

// MARK: - Backdrop

/// Window-sized ambient glow in the accent color and two neighbouring hues.
private struct Backdrop: View {
    let accent: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Group {
                    Circle()
                        .fill(accent)
                        .frame(width: w * 0.75)
                        .offset(x: -w * 0.32, y: -h * 0.38)
                    Circle()
                        .fill(accent)
                        .hueRotation(.degrees(48))
                        .frame(width: w * 0.6)
                        .offset(x: w * 0.38, y: h * 0.42)
                    Circle()
                        .fill(accent)
                        .hueRotation(.degrees(-42))
                        .frame(width: w * 0.42)
                        .offset(x: w * 0.30, y: -h * 0.45)
                }
                .blur(radius: 110)
                .opacity(scheme == .dark ? 0.34 : 0.26)
            }
            .frame(width: w, height: h)
            .clipped()
        }
    }
}

// MARK: - Glass

private struct GlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}

extension View {
    /// Liquid Glass on macOS 26+, a bordered material before that.
    func glassSurface(cornerRadius: CGFloat) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}

// MARK: - Shared building blocks

/// A titled glass card holding setting rows.
struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            VStack(spacing: 0) { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .glassSurface(cornerRadius: 16)
        }
    }
}

/// A row with a title, an optional secondary description, and a trailing
/// control.
struct SettingRow<Content: View>: View {
    let title: String
    let hint: String?
    @ViewBuilder let content: Content

    init(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5))
                if let hint {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) { content }
        }
        .padding(.vertical, 11)
    }
}

struct SettingToggle: View {
    let title: String
    let hint: String?
    @Binding var isOn: Bool

    init(_ title: String, hint: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.hint = hint
        self._isOn = isOn
    }

    var body: some View {
        SettingRow(title, hint: hint) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct RowDivider: View {
    var body: some View {
        Divider().opacity(0.6)
    }
}

/// Keycap for a fixed (non-configurable) key.
struct KeyBadge: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 8)
            .frame(minWidth: 26, minHeight: 24)
            .background(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(.primary.opacity(0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .strokeBorder(.primary.opacity(0.14), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
    }
}
