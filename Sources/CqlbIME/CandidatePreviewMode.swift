import AppKit
import CqlbCore

/// Development-only harness for the candidate window (see `main.swift`).
/// It never touches `EngineHost`, so no dictionaries are loaded.
enum CandidatePreviewMode {
    static func run(arguments: [String]) -> Never {
        var appearance = Config().appearance
        appearance.layout = arguments.contains("vertical") ? .vertical : .horizontal
        appearance.showPreedit = arguments.contains("header")
        appearance.glow = !arguments.contains("noglow")
        appearance.colorScheme = arguments.contains("light") ? .light
            : arguments.contains("dark") ? .dark : .system
        for accent in Config.Appearance.AccentColor.allCases where arguments.contains(accent.rawValue) {
            appearance.accentColor = accent
        }
        let pinyin = arguments.contains("pinyin")

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // Backdrop with text, so translucency has something behind it.
        let frame = NSRect(x: 200, y: 300, width: 640, height: 300)
        let backdrop = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.level = .floating
        let text = NSTextField(wrappingLabelWithString:
            "超强两笔输入法，最多四键上屏，重码少。The quick brown fox jumps over the lazy dog. "
            + "候选窗口浮在文档上方，这里是一段用来衬托半透明效果的示例文字。两笔两笔两笔。")
        text.font = .systemFont(ofSize: 20)
        text.frame = NSRect(x: 24, y: 24, width: 592, height: 252)
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.frame = container.bounds
        let dark = appearance.colorScheme == .dark
        gradient.colors = dark
            ? [NSColor(calibratedWhite: 0.16, alpha: 1).cgColor, NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.26, alpha: 1).cgColor]
            : [NSColor.white.cgColor, NSColor(calibratedRed: 0.86, green: 0.91, blue: 1, alpha: 1).cgColor]
        container.layer?.addSublayer(gradient)
        container.addSubview(text)
        backdrop.contentView = container
        backdrop.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        backdrop.orderFrontRegardless()

        func candidate(_ text: String, _ code: String, _ source: Candidate.Source = .main) -> DisplayCandidate {
            DisplayCandidate(text: text, code: code, annotation: code, source: source)
        }
        var state = EngineState.empty
        if pinyin {
            state.preedit = "zhong"
            state.isPinyinMode = true
            state.candidates = [
                candidate("中", "zg", .pinyin), candidate("种", "hzg", .pinyin),
                candidate("重", "tgj", .pinyin), candidate("钟", "qzg", .pinyin),
            ]
        } else {
            state.preedit = "ld"
            state.candidates = [
                candidate("两", "ld"), candidate("笔", "ldb"), candidate("输入", "ldc"),
                DisplayCandidate(text: "✌️", code: "ld", annotation: "两", source: .emoji),
                candidate("法", "ldgk"), candidate("超强", "ldh"),
            ]
        }
        state.hasNextPage = true
        state.highlightedIndex = arguments.contains("second") ? 1 : 0

        let caret = NSRect(x: frame.minX + 60, y: frame.maxY - 90, width: 2, height: 24)
        CandidateWindowController.shared.show(state: state, near: caret, appearance: appearance)
        print("preview frame \(Int(frame.minX)),\(Int(NSScreen.main!.frame.height - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))")
        fflush(stdout)
        app.run()
        exit(0)
    }
}
