import SwiftUI
import AppKit
import CqlbCore

struct RootView: View {
    @Bindable var model: SettingsModel
    @State private var selection: Section = .appearance

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case appearance = "外观"
        case functions  = "功能"
        case shortcuts  = "快捷键"
        case about      = "关于"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .appearance: return "paintbrush.fill"
            case .functions:  return "slider.horizontal.3"
            case .shortcuts:  return "keyboard.fill"
            case .about:      return "info.circle.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
                    .padding(.vertical, 3)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(selection.rawValue)
                            .font(.system(size: 28, weight: .bold))
                            .padding(.top, 8)

                        Group {
                            switch selection {
                            case .appearance: AppearanceView(model: model)
                            case .functions:  FunctionsView(model: model)
                            case .shortcuts:  ShortcutsView(model: model)
                            case .about:      AboutView()
                            }
                        }
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)

                // ── Save / Revert bar ──
                if selection != .about {
                    Divider()
                    HStack {
                        if model.isDirty {
                            Text("有未保存的更改")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("还原") {
                            model.revert()
                        }
                        .disabled(!model.isDirty)

                        Button("保存") {
                            model.save()
                        }
                        .disabled(!model.isDirty)
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 12)
                }
            }
            .background(Color.clear)
        }
        .background(Color.clear)
        .background(FrostedWindowInstaller())
        .onChange(of: model.config) { _, _ in
            model.markDirty()
        }
    }
}

// MARK: - Window-level frosted glass (NSVisualEffectView, blurs desktop)

struct FrostedWindowInstaller: NSViewRepresentable {
    class Coordinator { var installed = false }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let coord = context.coordinator
        return WindowHook { window in
            guard !coord.installed else { return }
            coord.installed = true

            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true

            guard let originalContent = window.contentView else { return }

            // VFX as root → blurs desktop. SwiftUI hosting view on top.
            let vfx = NSVisualEffectView(frame: originalContent.frame)
            vfx.material = .popover
            vfx.blendingMode = .behindWindow
            vfx.state = .active
            vfx.autoresizingMask = [.width, .height]

            window.contentView = vfx

            originalContent.translatesAutoresizingMaskIntoConstraints = false
            vfx.addSubview(originalContent)
            NSLayoutConstraint.activate([
                originalContent.topAnchor.constraint(equalTo: vfx.topAnchor),
                originalContent.bottomAnchor.constraint(equalTo: vfx.bottomAnchor),
                originalContent.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
                originalContent.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
            ])
        }
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class WindowHook: NSView {
    let handler: (NSWindow) -> Void
    init(handler: @escaping (NSWindow) -> Void) {
        self.handler = handler
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let w = window { handler(w) }
    }
}

// MARK: - Card-level Liquid Glass (macOS 26 native .glassEffect on top of the frosted window)

struct GlassPanel<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LiquidGlassCard())
    }
}

private struct LiquidGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        } else {
            content
                .background(.thinMaterial, in: .rect(cornerRadius: 20))
        }
    }
}

// MARK: - Row helpers

struct GlassRow<Content: View>: View {
    let label: String
    let hint: String?
    @ViewBuilder let content: Content

    init(_ label: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 14))
                if let hint = hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            content
        }
    }
}

struct GlassDivider: View {
    var body: some View {
        Divider().opacity(0.4)
    }
}
