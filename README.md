# cqlb (超强两笔)

macOS 外挂输入法，使用超强两笔编码方案。最多四键上屏，重码极少。

cqlb 是一个常驻菜单栏的普通 macOS 应用，通过 `CGEventTap` 全局监听键盘事件，并用 `CGEventPost` 注入文本。它**不是**系统输入法（IME），不需要在"键盘设置"中添加，只需授予辅助功能权限即可使用。

## 功能特性

**输入**
- 超强两笔编码，最多四键上屏，重码极少
- 自动四码上屏
- 支持临时拼音输入（编码前加 `i`）
- 支持临时英文输入
- Emoji 联想输入

**界面**
- 横排/竖排候选窗口，跟随光标显示
- 浅色/深色/跟随系统外观
- 候选词数量、字体、字号均可配置

**辅助**
- 反查编码/拼音显示
- GB2312 字符过滤（可选）
- 开机自启动
- 首次启动自动检测辅助功能权限
- 独立设置应用，菜单栏一键打开

## 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- 构建需要 Swift 工具链（Xcode 15+ 或对应版本的 Swift toolchain）

## 快速开始

```bash
git clone https://github.com/cch123/cqlb.git && cd cqlb
make install && make run
```

首次启动时，应用会自动检测辅助功能权限状态。如未授权，请前往 **系统设置 → 隐私与安全性 → 辅助功能**，勾选 cqlb，然后重新启动应用。

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Option` + `Space` | 切换中/英文模式 |
| `Shift` 单击 | 快速切换中/英（<300ms，中间不按其他键） |
| `i` + 拼音 | 临时拼音输入 |
| 数字键 `1`-`9` | 选择对应候选词 |
| `Space` | 选择第一个候选词 |
| `Escape` | 清空当前输入 |

## 工作原理

cqlb 使用 macOS 的 `CGEventTap` API 在全局层面拦截键盘事件：

1. **事件监听** — 注册 `cgSessionEventTap`，监听 `.keyDown` 和 `.flagsChanged` 事件
2. **输入切换** — Option+Space 或 Shift 快速单击切换中/英文模式
3. **编码匹配** — 击键送入引擎，查询超强两笔码表，匹配候选词
4. **文本注入** — 选中候选词后，通过 `CGEventPost` 将文本注入当前应用
5. **候选窗口** — 使用 AppKit 绘制候选窗口，跟随当前光标位置显示

## 配置

从菜单栏图标点击 **设置...** 打开设置应用，或直接打开 `cqlb Settings.app`。

配置文件存储在：

```
~/Library/Application Support/cqlb/config.json
```

可配置项：

| 类别 | 选项 |
|------|------|
| 外观 | 字体、字号、候选词数量、横排/竖排、配色方案、强调色 |
| 功能 | Emoji 联想、GB2312 过滤、临时英文、临时拼音、反查显示 |
| 快捷键 | 中英切换键、清空缓冲区键 |

## 项目结构

```
cqlb/
├── Sources/
│   ├── CqlbCore/         # 核心库：引擎、码表、配置、OpenCC
│   │   ├── Engine/       #   输入引擎，候选词匹配
│   │   ├── Config/       #   配置读写 (config.json)
│   │   └── Dict/         #   码表加载与查询
│   ├── CqlbApp/          # 主应用：菜单栏、事件监听、候选窗口
│   ├── CqlbSettings/     # 设置应用 (SwiftUI)
│   ├── CqlbQuery/        # 命令行查询工具 (开发用)
│   └── CqlbRepl/         # 交互式 REPL (开发用)
├── Dicts/                # 码表文件
├── Resources/            # Info.plist、应用图标
├── scripts/              # 构建辅助脚本
├── Tests/                # 单元测试
├── Package.swift
├── Makefile
└── dev.sh
```

### 模块说明

- **CqlbCore** — 纯 Swift 库，包含输入引擎、码表解析、配置管理。不依赖 AppKit，可独立测试。
- **CqlbApp** — 主应用，链接 AppKit / ApplicationServices / Carbon。包含 `EventTap`（全局键盘监听）、`TextInjector`（文本注入）、`CandidateWindow`（候选窗口）等。
- **CqlbSettings** — 独立的设置应用，使用 SwiftUI 构建，读写与主应用相同的 `config.json`。
- **CqlbQuery** / **CqlbRepl** — 开发调试工具，用于在终端测试引擎查询。

## 从源码构建

```bash
# 构建（debug 模式）
make build

# 构建 release 版本
make build CONFIG=release

# 安装到 ~/Applications/ 并启动
make install
make run

# 清理构建产物
make clean

# 卸载
make uninstall
```

码表文件位于 `Dicts/` 目录，构建时会自动复制到应用 bundle 的 `Resources/Dicts/` 中。

## 已知限制

- **无内嵌预编辑** — 编码显示在独立的候选窗口中，而非应用的文本输入框内。这是外挂输入法方案的固有限制。
- **需要辅助功能权限** — `CGEventTap` 要求辅助功能权限才能工作。每次更新应用后可能需要重新授权。
- **部分应用不兼容** — 某些使用自定义文本引擎的应用（如部分 Electron 应用）可能无法正确接收注入的文本。
- **远程桌面兼容性** — 使用远程桌面软件时，modifier key 可能触发意外行为。

## 致谢

- **付东升** — 超强两笔编码方案及码表
- **Rime** — 码表格式参考
- **OpenCC** — 简繁转换

## 许可证

MIT
