# cqlb (超强两笔)

macOS 超强两笔输入法。最多四键上屏，重码极少。

cqlb 提供两种运行模式，共用同一套引擎、码表与设置应用：

- **IME 模式（推荐）** — 基于 `InputMethodKit` 的系统级输入法。支持**内嵌预编辑**（编码直接显示在文本框内），兼容性最好，不需要辅助功能权限。需要 Apple Developer ID 证书签名 + 公证。
- **外挂模式** — 常驻菜单栏的普通 macOS 应用，通过 `CGEventTap` 全局监听键盘事件，`CGEventPost` 注入文本。不需要签名和公证，只需授予辅助功能权限即可使用。

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
```

### IME 模式（推荐）

```bash
# 1. 在 Makefile 里把 IME_CERT_NAME 改成你自己的 Developer ID
#    "Developer ID Application: Your Name (TEAMID)"
# 2. 首次配置公证凭证（一次性）：
xcrun notarytool store-credentials cqlb-notary \
    --apple-id "your@apple-id" \
    --team-id "YOURTEAMID" \
    --password "xxxx-xxxx-xxxx-xxxx"   # 来自 appleid.apple.com 的 App 专用密码

# 3. 装 IME + 设置应用
make install          # 同时把设置 app 装到 ~/Applications
make install-ime      # 装 IME bundle 到 ~/Library/Input Methods
make notarize-ime     # 提交 Apple 公证 + staple（2-5 分钟，首次可能更久）

# 4. 在 系统设置 → 键盘 → 文本输入 → 输入法 里添加"超强两笔"
```

### 外挂模式（无需 Developer ID）

```bash
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

两种模式的差异只在输入层，引擎和码表完全共用。

**IME 模式**（`Sources/CqlbIME/`）：

1. **IMKServer 启动** — 系统 `TextInputMenuAgent` 按需拉起 IME 进程
2. **事件处理** — `IMKInputController.handle(_:client:)` 接收 NSEvent
3. **编码匹配** — 击键送入引擎，查询超强两笔码表，匹配候选词
4. **内嵌预编辑** — `client.setMarkedText(_:selectionRange:replacementRange:)` 把编码显示在文本框内
5. **文本上屏** — `client.insertText(_:replacementRange:)` 提交最终文本
6. **候选窗口** — 通过 `client.attributes(forCharacterIndex:lineHeightRectangle:)` 拿光标位置，绘制候选窗口

**外挂模式**（`Sources/CqlbApp/`）：

1. **事件监听** — 注册 `cgSessionEventTap`，监听 `.keyDown` 和 `.flagsChanged` 事件
2. **编码匹配** — 击键送入引擎，查询超强两笔码表，匹配候选词
3. **文本注入** — 选中候选词后，通过 `CGEventPost` 将文本注入当前应用
4. **候选窗口** — 通过 Accessibility API 获取光标位置，绘制候选窗口

## 配置

**IME 模式**：菜单栏输入法图标 → **超强两笔 → 设置…**
**外挂模式**：菜单栏图标 → **设置…**

两种模式的设置都打开同一个 `cqlb Settings.app`，读写同一份配置。

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
│   ├── CqlbApp/          # 外挂模式主应用：菜单栏、CGEventTap、候选窗口
│   ├── CqlbIME/          # IME 模式主应用：IMKServer、IMKInputController
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
- **CqlbApp** — 外挂模式主应用，链接 AppKit / ApplicationServices / ServiceManagement。包含 `EventTap`（全局键盘监听）、`TextInjector`（文本注入）、`CandidateWindow`（候选窗口）等。
- **CqlbIME** — IME 模式主应用，链接 InputMethodKit。包含 `CqlbInputController`（IMK 事件处理）和同款候选窗口。与 CqlbApp 共用 CqlbCore 和 config.json。
- **CqlbSettings** — 独立的设置应用，使用 SwiftUI 构建，读写与主应用相同的 `config.json`。两种模式都能实时接收配置变更。
- **CqlbQuery** / **CqlbRepl** — 开发调试工具，用于在终端测试引擎查询。

## 从源码构建

```bash
# 构建（debug）
make build          # 外挂模式 + 设置 app
make build-ime      # IME 模式
make build CONFIG=release   # release

# 安装
make install        # 外挂模式 → ~/Applications/cqlb.app + cqlb Settings.app
make install-ime    # IME 模式 → ~/Library/Input Methods/cqlb-ime.app
make notarize-ime   # 提交 Apple 公证 + staple（IME 模式必需）

# 清理
make clean
make uninstall       # 外挂
make uninstall-ime   # IME
```

码表文件位于 `Dicts/` 目录，构建时会自动复制到应用 bundle 的 `Resources/Dicts/` 中。

## IME 模式坑点记录

以下是从实装过程中踩过的坑，记下来给未来自己和 fork 这个仓库的人：

### Bundle Identifier 必须含 `.inputmethod.` 作为中间组件

- ✅ `com.cqlb.inputmethod.cqlb`（我们的）
- ✅ `im.rime.inputmethod.Squirrel`（鼠须管）
- ✅ `com.apple.inputmethod.SCIM`（Apple 内置）
- ❌ `com.cqlb.inputmethod`（`inputmethod` 是**最后一段**，被 TextInputMenuAgent 静默过滤）

macOS IME 发现路径按这个 pattern 过滤 bundle——不符合的直接不出现在"键盘设置 → 添加输入法"列表，**没有任何日志提示**。

### 必须 Developer ID 签名 + 公证 + staple

macOS 15+ 上：
- 自签证书不行（即便导入 System 钥匙串设为 trustRoot+codeSign）
- ad-hoc 签名不行
- 只签不公证的 Developer ID bundle 不行（`syspolicy_check` 会直接报 `Notary Ticket Missing Fatal`）
- 必须走完整的 `codesign + xcrun notarytool submit + xcrun stapler staple` 链路

我们的 Makefile 把这些都串起来了，`make install-ime && make notarize-ime` 一气呵成。

### 名字本地化必须把 TISInputSourceID 作为 key

`Resources/zh-Hans.lproj/InfoPlist.strings` 里除了 `CFBundleName` 还必须加 mode ID 的映射：

```
"CFBundleName"                       = "超强两笔";
"com.cqlb.inputmethod.cqlb"          = "超强两笔";
"com.cqlb.inputmethod.cqlb.Hans"     = "超强两笔";   ← 关键
```

否则 picker 里会直接显示原始的 `com.cqlb.inputmethod.cqlb.Hans` 字符串。

### InputMethodServerControllerClass 用 Swift module 形式

Info.plist 里：

```xml
<key>InputMethodServerControllerClass</key>
<string>CqlbIME.CqlbInputController</string>   ← Module.Class，不加 @objc(name)
```

Swift 类不标 `@objc(custom_name)`、直接继承 `IMKInputController`，Swift runtime 自动以 `Module.Class` 形式注册到 ObjC runtime。鼠须管、Apple 内置样例都是这个写法。

### Info.plist 其它必要键

- `LSBackgroundOnly=false` + `LSUIElement=true`（两个都要有，前者显式声明"不是纯后台 app，有 UI"）
- `Contents/PkgInfo` 文件（8 字节 `APPL????`，老式 LaunchServices 探测路径需要）
- `ComponentInputModeDict`（mode 列表 + visible order）
- `InputMethodConnectionName = $(PRODUCT_BUNDLE_IDENTIFIER)_Connection`

完整对照参见 [Resources/IME-Info.plist](Resources/IME-Info.plist)。

### IME 菜单 / Fn HUD 图标用 Apple-style TIFF

picker 和按 Fn 弹出的输入法 HUD 都走 TIS 的小图标路径。这里不要复用 app icon。当前采用鼠须管更稳的做法：不设置 `TISIconIsTemplate`，直接提供一张完整的浅色 badge + 深色 glyph。mode 级 `tsInputModeAlternateMenuIconFileKey` 和顶层 `tsInputMethodAlternateIconFileKey` 都指向同一张 `cqlb-label.tiff`；如果给彩色 badge 设置 `TISIconIsTemplate=true`，系统会把浅底和深字压成同一张单色 mask，Fn HUD 里字会被一起染没。

`scripts/gen-tiff.sh` 保留 Apple 内置 IME 的 TIFF 编码形态：RGB+unassociated alpha、LZW、多 rep。`cqlb-label.tiff` 使用鼠须管 `rime.pdf` 同款 22×16 / 44×32 @2x 横向比例。TIS 图标文件名刻意和 app icon 的 `cqlb.icns` 分开，避免 LaunchServices/TextInput UI 按旧 icon URL 缓存。

这次图标问题的定位结论：

- **Fn HUD 空白块**：`TISIconIsTemplate=true` 只能配纯 mask。把“浅底深字”的彩色图声明成 template 后，系统会把浅底和黑字压成同一个单色 mask，选中态里字就一起消失。
- **白框比系统/鼠须管小**：TIS 不会替第三方 IME 自动扩 badge；`22×16` 画布里留透明 inset，就会直接显示成更小的白框。现在 badge 占满完整画布。
- **字看起来不居中**：按字体 metrics 居中不等于视觉居中，中文字在小尺寸下有 side bearing 和抗锯齿边缘。生成脚本会先离屏渲染 glyph，扫描真实可见墨迹 bbox，再把 bbox 居中到 badge；最后再给“两”一个 1px optical y-offset，因为它的视觉重心偏上。
- **系统缓存很粘**：修改图标时需要同时换清晰的 TIS icon 文件路径、bump `CFBundleVersion`，并重启 `TextInputMenuAgent` / `TextInputSwitcher` / `ControlCenter` / `SystemUIServer` 才能避免旧图继续显示。

### 首次公证可能要几小时

新 Developer 团队的**第一次**公证提交会进 Apple 的 "in-depth analysis" 队列，最慢可能 24-72 小时（[见 Apple Developer Forums](https://developer.apple.com/forums/thread/811968)）。之后同一 Team ID 提交通常 2-5 分钟。

## 已知限制

**外挂模式**：

- **无内嵌预编辑** — 编码显示在独立的候选窗口中。
- **需要辅助功能权限** — 每次更新应用后可能需要重新授权。
- **部分应用不兼容** — 某些使用自定义文本引擎的应用（如部分 Electron 应用）可能无法正确接收注入的文本。
- **远程桌面兼容性** — 使用远程桌面软件时，modifier key 可能触发意外行为。

**IME 模式**：

- 需要 Apple Developer ID（$99/年）做签名和公证。
- 光标定位依赖 client 实现——少数 Carbon/Terminal 应用不提供 `attributes(forCharacterIndex:)`，候选窗口会回退到屏幕中下方。

## 致谢

- **付东升** — 超强两笔编码方案及码表
- **Rime** — 码表格式参考
- **OpenCC** — 简繁转换

## 许可证

MIT
