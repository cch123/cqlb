import SwiftUI
import CqlbCore

struct ShortcutsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Card("中英文切换") {
                SettingRow("组合键") {
                    Picker("", selection: $model.config.shortcuts.toggleChineseEnglish) {
                        Text("⌥ 空格").tag(Config.Shortcuts.ToggleKey.optionSpace)
                        Text("⇧ 空格").tag(Config.Shortcuts.ToggleKey.shiftSpace)
                        Text("关闭").tag(Config.Shortcuts.ToggleKey.none)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                RowDivider()
                SettingRow("单击 Shift", hint: "快速按下并松开，期间不按其他键") {
                    Picker("", selection: $model.config.shortcuts.shiftTap) {
                        Text("任意 Shift").tag(Config.Shortcuts.ShiftTap.both)
                        Text("左 Shift").tag(Config.Shortcuts.ShiftTap.left)
                        Text("右 Shift").tag(Config.Shortcuts.ShiftTap.right)
                        Text("关闭").tag(Config.Shortcuts.ShiftTap.none)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            Card("候选词") {
                SettingRow("选择候选词") { KeyBadge("1 – 9"); KeyBadge("鼠标点击") }
                RowDivider()
                SettingRow("上屏高亮的候选词") { KeyBadge("空格") }
                RowDivider()
                SettingRow("移动高亮") {
                    KeyBadge("↑"); KeyBadge("↓"); KeyBadge("←"); KeyBadge("→"); KeyBadge("Tab")
                }
                RowDivider()
                SettingRow("翻页") {
                    KeyBadge("-"); KeyBadge("="); KeyBadge("PgUp"); KeyBadge("PgDn")
                }
            }

            Card("编码") {
                SettingRow("上屏原始输入", hint: "拼音和英文模式会去掉 i / ' 前缀") { KeyBadge("回车") }
                RowDivider()
                SettingRow("删除一个编码") { KeyBadge("退格") }
                RowDivider()
                SettingRow("清空输入") { KeyBadge("Esc") }
            }
        }
    }
}
