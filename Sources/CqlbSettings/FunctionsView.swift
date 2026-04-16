import SwiftUI
import CqlbCore

struct FunctionsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 20) {
            GlassPanel("系统") {
                GlassRow("开机自动启动", hint: "登录时自动运行超强两笔") {
                    Toggle("", isOn: $model.config.functions.launchAtLogin)
                        .labelsHidden().toggleStyle(.switch)
                }
            }

            GlassPanel("输入辅助") {
                VStack(spacing: 14) {
                    GlassRow("临时拼音反查", hint: "输入 3+ 字符且以 i 开头时使用拼音反查") {
                        Toggle("", isOn: $model.config.functions.tempPinyin)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    GlassDivider()
                    GlassRow("临时英文", hint: "以 ' 引导临时输入英文") {
                        Toggle("", isOn: $model.config.functions.tempEnglish)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    GlassDivider()
                    GlassRow("Emoji 建议", hint: "候选列表中插入对应 emoji") {
                        Toggle("", isOn: $model.config.functions.emojiSuggestion)
                            .labelsHidden().toggleStyle(.switch)
                    }
                }
            }

            GlassPanel("过滤与显示") {
                VStack(spacing: 14) {
                    GlassRow("GB2312 过滤", hint: "只显示 GB2312 字符集内的候选") {
                        Toggle("", isOn: $model.config.functions.gb2312Filter)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    GlassDivider()
                    GlassRow("候选注释", hint: "候选词旁边显示编码或拼音") {
                        Picker("", selection: $model.config.functions.reverseLookupDisplay) {
                            Text("不显示").tag(Config.Functions.ReverseLookup.none)
                            Text("编码").tag(Config.Functions.ReverseLookup.code)
                            Text("拼音").tag(Config.Functions.ReverseLookup.pinyin)
                            Text("全部").tag(Config.Functions.ReverseLookup.both)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                        .labelsHidden()
                    }
                }
            }
        }
    }
}
