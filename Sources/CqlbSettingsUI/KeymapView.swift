import SwiftUI
import CqlbCore

// MARK: - Key map data
//
// Transcribed from the official key charts of 超强两笔 (30 keys) and
// 超强音形 (26 keys), and cross-checked against the shipped code tables: the
// second code of a character agrees with the stroke pair / radical assigned
// here. The two schemes differ only in where the 折 combinations live:
// 两笔 puts them on `; , . /`, 音形 folds them onto `M C V B`.

/// The five basic strokes.
enum Stroke: String {
    case heng = "横", shu = "竖", pie = "撇", dian = "点", zhe = "折"
}

/// Keyboard zones, named after the first stroke of the pairs they hold.
enum KeyZone: String, CaseIterable {
    case pie = "撇区", dian = "点区", shu = "竖区", heng = "横区", single = "单笔画区", zhe = "折区"

    var color: Color {
        switch self {
        case .pie:    return .purple
        case .dian:   return .green
        case .shu:    return .orange
        case .heng:   return .teal
        case .single: return .pink
        case .zhe:    return .blue
        }
    }
}

struct KeySpec: Identifiable {
    let key: String
    let zone: KeyZone
    /// One or two stroke combinations (a single stroke counts as one).
    let combos: [[Stroke]]
    let radical: String?

    var id: String { key }
    var isActive: Bool { !combos.isEmpty }

    init(_ key: String, _ zone: KeyZone, _ combos: [[Stroke]] = [], radical: String? = nil) {
        self.key = key
        self.zone = zone
        self.combos = combos
        self.radical = radical
    }
}

enum Keymap {
    /// Rows 1 and 2 are identical in both schemes except for `;`.
    private static func upperRows(semicolon: [[Stroke]]) -> [[KeySpec]] {
        [
            [
                KeySpec("Q", .pie, [[.pie, .heng]]),
                KeySpec("W", .pie, [[.pie, .shu]]),
                KeySpec("E", .pie, [[.pie, .pie]]),
                KeySpec("R", .pie, [[.pie, .dian]]),
                KeySpec("T", .pie, [[.pie, .zhe]]),
                KeySpec("Y", .dian, [[.dian, .heng]]),
                KeySpec("U", .dian, [[.dian, .shu]], radical: "扌"),
                KeySpec("I", .dian, [[.dian, .pie]]),
                KeySpec("O", .dian, [[.dian, .dian]]),
                KeySpec("P", .dian, [[.dian, .zhe]]),
            ],
            [
                KeySpec("A", .shu, [[.shu, .heng]]),
                KeySpec("S", .shu, [[.shu, .shu]], radical: "日"),
                KeySpec("D", .shu, [[.shu, .pie]], radical: "月"),
                KeySpec("F", .shu, [[.shu, .dian]], radical: "亻"),
                KeySpec("G", .shu, [[.shu, .zhe]]),
                KeySpec("H", .heng, [[.heng, .heng]]),
                KeySpec("J", .heng, [[.heng, .shu]]),
                KeySpec("K", .heng, [[.heng, .pie]]),
                KeySpec("L", .heng, [[.heng, .dian]], radical: "口"),
                KeySpec(";", .heng, semicolon),
            ],
        ]
    }

    static func rows(for scheme: Scheme) -> [[KeySpec]] {
        switch scheme {
        case .cqlb:
            return upperRows(semicolon: [[.heng, .zhe]]) + [[
                KeySpec("Z", .single, [[.heng]], radical: "钅"),
                KeySpec("X", .single, [[.shu]], radical: "木"),
                KeySpec("C", .single, [[.pie]], radical: "氵"),
                KeySpec("V", .single, [[.dian]], radical: "土"),
                KeySpec("B", .single, [[.zhe]], radical: "艹"),
                KeySpec("N", .zhe, [[.zhe, .heng]]),
                KeySpec("M", .zhe, [[.zhe, .shu]]),
                KeySpec(",", .zhe, [[.zhe, .pie]]),
                KeySpec(".", .zhe, [[.zhe, .dian]]),
                KeySpec("/", .zhe, [[.zhe, .zhe]]),
            ]]
        case .cqyx:
            return upperRows(semicolon: []) + [[
                KeySpec("Z", .single, [[.heng]], radical: "钅"),
                KeySpec("X", .single, [[.shu]], radical: "木"),
                KeySpec("C", .single, [[.pie], [.zhe, .pie]], radical: "氵"),
                KeySpec("V", .single, [[.dian], [.zhe, .dian]], radical: "土"),
                KeySpec("B", .single, [[.zhe], [.zhe, .zhe]], radical: "艹"),
                KeySpec("N", .zhe, [[.zhe, .heng]]),
                KeySpec("M", .zhe, [[.zhe, .shu], [.heng, .zhe]]),
                KeySpec(",", .zhe),
                KeySpec(".", .zhe),
                KeySpec("/", .zhe),
            ]]
        }
    }

    /// Key holding a stroke pair or single stroke in `scheme`, for the
    /// worked examples.
    static func key(for combo: [Stroke], in scheme: Scheme) -> String {
        rows(for: scheme).joined().first { $0.combos.contains(combo) }?.key.lowercased() ?? "?"
    }
}

// MARK: - Stroke drawing

/// One stroke drawn as a vector path in a unit box, so stroke weight and
/// shape are identical at every size and do not depend on an installed font.
struct StrokeShape: Shape {
    let stroke: Stroke

    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
        }
        var path = Path()
        switch stroke {
        case .heng:
            path.move(to: p(0.10, 0.52))
            path.addLine(to: p(0.90, 0.48))
        case .shu:
            path.move(to: p(0.50, 0.08))
            path.addLine(to: p(0.50, 0.92))
        case .pie:
            path.move(to: p(0.74, 0.10))
            path.addQuadCurve(to: p(0.20, 0.90), control: p(0.66, 0.62))
        case .dian:
            path.move(to: p(0.34, 0.26))
            path.addQuadCurve(to: p(0.68, 0.70), control: p(0.58, 0.40))
        case .zhe:
            path.move(to: p(0.16, 0.24))
            path.addLine(to: p(0.80, 0.20))
            path.addQuadCurve(to: p(0.62, 0.90), control: p(0.80, 0.62))
        }
        return path
    }
}

/// A stroke combination drawn side by side.
struct StrokeCombo: View {
    let strokes: [Stroke]
    let size: CGFloat
    var color: Color = .primary

    var body: some View {
        HStack(spacing: size * 0.10) {
            ForEach(Array(strokes.enumerated()), id: \.offset) { _, stroke in
                StrokeShape(stroke: stroke)
                    .stroke(color, style: StrokeStyle(lineWidth: max(1.4, size * 0.13), lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.78, height: size)
            }
        }
        .accessibilityLabel(strokes.map(\.rawValue).joined())
    }
}

// MARK: - Keyboard

private struct KeyCap: View {
    let spec: KeySpec
    let side: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
        ZStack {
            if spec.isActive {
                shape.fill(spec.zone.color.opacity(0.16))
                shape.strokeBorder(spec.zone.color.opacity(0.55), lineWidth: 1)
            } else {
                // Present on the keyboard but unused by this scheme.
                shape.strokeBorder(
                    Color.primary.opacity(0.18),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
            }

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    Text(spec.key)
                        .font(.system(size: side * 0.24, weight: .bold, design: .rounded))
                        .foregroundStyle(spec.isActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    Spacer(minLength: 0)
                    if let radical = spec.radical {
                        Text(radical)
                            .font(.system(size: side * 0.30, weight: .bold))
                            .foregroundStyle(spec.zone.color)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: side * 0.05) {
                    ForEach(Array(spec.combos.enumerated()), id: \.offset) { _, combo in
                        StrokeCombo(strokes: combo, size: side * (spec.combos.count > 1 ? 0.23 : 0.32))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(side * 0.11)
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .combine)
    }
}

/// Three staggered rows scaled to the available width.
private struct KeyboardDiagram: View {
    let scheme: Scheme

    private static let offsets: [CGFloat] = [0, 0.32, 0.78]   // in key widths
    private static let gapRatio: CGFloat = 0.10               // gap / key width

    var body: some View {
        let rows = Keymap.rows(for: scheme)
        // total width = 10 keys + 9 gaps + largest row offset
        let unitsWide = 10 + 9 * Self.gapRatio + (Self.offsets.last ?? 0)
        let unitsHigh = 3 + 2 * Self.gapRatio
        GeometryReader { geo in
            let side = geo.size.width / unitsWide
            let gap = side * Self.gapRatio
            VStack(alignment: .leading, spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: gap) {
                        ForEach(row) { KeyCap(spec: $0, side: side) }
                    }
                    .padding(.leading, side * Self.offsets[index])
                }
            }
        }
        .aspectRatio(unitsWide / unitsHigh, contentMode: .fit)
    }
}

// MARK: - Pane

struct KeymapView: View {
    @Bindable var model: SettingsModel
    /// Which scheme's chart is shown. Starts at the scheme in use; changing
    /// it here only changes the chart, not the setting.
    @State private var shown: Scheme

    init(model: SettingsModel) {
        self.model = model
        // `CQLB_SETTINGS_SCHEME` lets the preview tool snapshot either chart.
        let override = ProcessInfo.processInfo.environment["CQLB_SETTINGS_SCHEME"].flatMap(Scheme.init(rawValue:))
        _shown = State(initialValue: override ?? model.config.scheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Picker("", selection: $shown) {
                            ForEach(Scheme.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 190)
                        Spacer()
                        Text(shown == model.config.scheme ? "当前使用的方案" : "仅查看，未切换方案")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    KeyboardDiagram(scheme: shown)
                        .animation(.snappy(duration: 0.25), value: shown)

                    HStack(spacing: 12) {
                        ForEach(KeyZone.allCases, id: \.self) { zone in
                            HStack(spacing: 5) {
                                Circle().fill(zone.color).frame(width: 7, height: 7)
                                Text(zone.rawValue)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 13)
            }

            Card("怎么取码") {
                rule("第一码", "字的读音首字母。「好」读 hǎo，第一码是 h。")
                RowDivider()
                rule("后面的码", "按书写顺序看字的部件，每个部件取头两笔，按这两笔所在的键。")
                RowDivider()
                rule("彩色偏旁", "键上标了偏旁的（扌 日 月 亻 口 钅 木 氵 土 艹），遇到这个偏旁直接按该键。")
                RowDivider()
                rule("最后一个部件", "继续两笔两笔地取；只剩一笔时按单笔画键。全字最多四码。")
            }

            Card("例字") {
                example("明", [("m", "读音 míng"), ("s", "日"), ("d", "月")])
                RowDivider()
                example("打", [("d", "读音 dǎ"), ("u", "扌"), (key([.heng, .shu]), "丁：横竖")])
                RowDivider()
                example("好", [
                    ("h", "读音 hǎo"),
                    (key([.zhe, .pie]), "女：折撇"),
                    (key([.zhe, .shu]), "子：折竖"),
                    (key([.heng]), "末笔：横"),
                ])
            }

            Card("词组") {
                rule("两个字", "每个字取前两码。「输入」= \(shown == .cqlb ? "s; rr" : "sm rr")。")
                RowDivider()
                rule("三个字", "第一个字取前两码，后两个字各取第一码。")
                RowDivider()
                rule("四字及以上", "取第一、二、三和最后一个字的第一码。「中华人民共和国」= zhrg。")
            }

            Card("特殊引导键") {
                rule("i", "后面接拼音，反查不会拆的字；候选旁边会给出它的编码。")
                RowDivider()
                rule(String(shown.englishPrefix), "临时输入英文。")
                RowDivider()
                rule("v", "引导符号输入，例如 vv 是问号。")
            }
        }
        .onChange(of: model.config.scheme) { _, scheme in
            shown = scheme
        }
    }

    private func key(_ combo: [Stroke]) -> String {
        Keymap.key(for: combo, in: shown)
    }

    private func rule(_ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .frame(width: 92, alignment: .leading)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }

    private func example(_ character: String, _ steps: [(key: String, note: String)]) -> some View {
        HStack(spacing: 14) {
            Text(character)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 92, alignment: .leading)
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    VStack(spacing: 5) {
                        KeyBadge(step.key)
                        Text(step.note)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 56)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }
}
