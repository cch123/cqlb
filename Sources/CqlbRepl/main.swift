import Foundation
import CqlbCore

// Interactive engine driver.
//
// Feeds a whole input line into the engine one Character at a time, prints
// the engine state after each keystroke, and commits on `<CR>`. Meant to
// exercise the Engine module end-to-end without a GUI.
//
// Usage:
//   cqlb-repl
//
// At the `input>` prompt, type a composition string. Special tokens:
//   \b     backspace (one per token)
//   \s     space (select top)
//   \n     enter (commit raw)
//   \e     escape (clear)
//   \=     page down
//   \-     page up
//   \1..\6 select candidate at that slot on the current page
//   \q     quit

let rimeDir = ("~/Library/Rime" as NSString).expandingTildeInPath
let cacheDir = ("~/Library/Caches/cqlb" as NSString).expandingTildeInPath
let fm = FileManager.default
try? fm.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)

func load(_ name: String, cap: Int? = nil) throws -> CodeTable {
    let src = URL(fileURLWithPath: "\(rimeDir)/\(name)")
    let cache = URL(fileURLWithPath: "\(cacheDir)/\(name).bin")
    let opts = DictLoadOptions(maxEntries: cap, minWeight: 0, skipStemColumn: true)
    let result = try DictLoader.loadCached(source: src, cache: cache, options: opts)
    print("  loaded \(name) [\(result.fromCache ? "cache" : "yaml")] count=\(result.table.count)")
    return result.table
}

print("loading dictionaries…")
let loadStart = Date()
let main: CodeTable
let pinyin: CodeTable?
let english: CodeTable?
let emoji: EmojiDict

do {
    main = try load("cqlb.dict.yaml")
    pinyin = try? load("ipinyin.dict.yaml")
    english = try? load("english.dict.yaml")
    let emojiUrls = ["\(rimeDir)/opencc/emoji_word.txt", "\(rimeDir)/opencc/emoji_category.txt"]
        .map { URL(fileURLWithPath: $0) }
    emoji = try EmojiDict.load(from: emojiUrls)
    print("  loaded emoji dict keys=\(emoji.count)")
} catch {
    FileHandle.standardError.write(Data("dictionary load failed: \(error)\n".utf8))
    exit(1)
}
let totalMs = Date().timeIntervalSince(loadStart) * 1000
print("ready in \(String(format: "%.0f", totalMs)) ms\n")

let resources = EngineResources(main: main, pinyin: pinyin, english: english, emoji: emoji)
var engine = Engine(resources: resources, config: .default)

func printState(_ state: EngineState) {
    let line = "  preedit=[\(state.preedit)] page=\(state.pageIndex) "
              + (state.hasPrevPage ? "< " : "  ")
              + (state.hasNextPage ? "> " : "  ")
    print(line)
    if state.candidates.isEmpty {
        print("    (no candidates)")
        return
    }
    for (i, c) in state.candidates.enumerated() {
        let tag: String
        switch c.source {
        case .main:    tag = "  "
        case .pinyin:  tag = "py"
        case .english: tag = "en"
        case .emoji:   tag = "em"
        case .punct:   tag = "pu"
        }
        let ann = c.annotation.isEmpty ? "" : "  (\(c.annotation))"
        print("    \(i + 1). [\(tag)] \(c.text)\(ann)")
    }
}

func processResult(_ r: EngineResult) {
    switch r {
    case .passthrough:
        print("  <passthrough>")
    case .update(let s):
        printState(s)
    case .commit(let text, let s):
        print("  >>> commit: \"\(text)\"")
        printState(s)
    }
}

print("type composition. tokens: \\b \\s \\n \\e \\= \\- \\1..\\6 \\q")
print("example: anj\\s   (types 'anj' then space to select top)\n")

while let line = readLine() {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed == "\\q" { break }
    if trimmed.isEmpty { continue }

    var idx = trimmed.startIndex
    while idx < trimmed.endIndex {
        let c = trimmed[idx]
        if c == "\\" {
            let next = trimmed.index(after: idx)
            if next >= trimmed.endIndex { break }
            let t = trimmed[next]
            idx = trimmed.index(after: next)
            switch t {
            case "b":
                print("[\\b]")
                processResult(engine.processKey(KeyEvent(char: nil, special: .backspace)))
            case "s":
                print("[\\s]")
                processResult(engine.processKey(KeyEvent(char: nil, special: .space)))
            case "n":
                print("[\\n]")
                processResult(engine.processKey(KeyEvent(char: nil, special: .enter)))
            case "e":
                print("[\\e]")
                processResult(engine.processKey(KeyEvent(char: nil, special: .escape)))
            case "=":
                print("[\\=]")
                processResult(engine.processKey(KeyEvent(char: nil, special: .pageDown)))
            case "-":
                print("[\\-]")
                processResult(engine.processKey(KeyEvent(char: nil, special: .pageUp)))
            case "1", "2", "3", "4", "5", "6":
                let i = Int(String(t))! - 1
                print("[\\\(t)]")
                processResult(engine.selectCandidate(at: i))
            default:
                print("unknown token \\\(t)")
            }
        } else {
            print("[\(c)]")
            processResult(engine.processKey(KeyEvent(char: c)))
            idx = trimmed.index(after: idx)
        }
    }
}
