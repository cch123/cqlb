import AppKit
import SwiftUI
import CqlbCore

struct FunctionsView: View {
    @Bindable var model: SettingsModel

    private var schemeHint: String {
        switch model.config.scheme {
        case .cqlb: return "编码用 26 个字母加 ; , . / 四个键"
        case .cqyx: return "编码只用 26 个字母，; , . / 直接出标点"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Card("编码方案") {
                SettingRow("方案", hint: schemeHint) {
                    Picker("", selection: $model.config.scheme) {
                        ForEach(Scheme.allCases, id: \.self) { scheme in
                            Text(scheme.displayName).tag(scheme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)
                }
            }

            Card("输入辅助") {
                SettingToggle(
                    "拼音反查",
                    hint: "以 i 开头输入拼音，查看不会拆的字怎么打",
                    isOn: $model.config.functions.tempPinyin
                )
                RowDivider()
                SettingToggle(
                    "临时英文",
                    hint: "以 \(String(model.config.scheme.englishPrefix)) 开头输入英文，空格连词，回车上屏",
                    isOn: $model.config.functions.tempEnglish
                )
                RowDivider()
                SettingToggle(
                    "Emoji 建议",
                    hint: "在首选词后面插入对应的 emoji",
                    isOn: $model.config.functions.emojiSuggestion
                )
            }

            Card("候选词") {
                SettingToggle(
                    "仅常用字（GB2312）",
                    hint: "隐藏含生僻汉字的候选，符号不受影响",
                    isOn: $model.config.functions.gb2312Filter
                )
                RowDivider()
                SettingRow("候选注释", hint: "「编码」只显示还没打的键；拼音反查时显示完整两笔码") {
                    Picker("", selection: $model.config.functions.reverseLookupDisplay) {
                        Text("不显示").tag(Config.Functions.ReverseLookup.none)
                        Text("编码").tag(Config.Functions.ReverseLookup.code)
                        Text("拼音").tag(Config.Functions.ReverseLookup.pinyin)
                        Text("编码和拼音").tag(Config.Functions.ReverseLookup.both)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            Card("用户词库") {
                SettingRow("自定义词条", hint: "\(model.config.scheme.displayName)的词库。每行「词组 Tab 编码」，不写编码则自动编码，保存后立即生效") {
                    Button("打开词库文件…") {
                        let scheme = model.config.scheme
                        UserDict.createTemplateIfMissing(for: scheme)
                        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
                        NSWorkspace.shared.open(
                            [UserDict.url(for: scheme)],
                            withApplicationAt: textEdit,
                            configuration: NSWorkspace.OpenConfiguration()
                        )
                    }
                }
            }
        }
    }
}
