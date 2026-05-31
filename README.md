# cqlb (超强两笔)

macOS 标准输入法版本的超强两笔。最多四键上屏，重码少，基于
`InputMethodKit` 接入系统输入源。

## 功能特性

**输入**
- 超强两笔编码，最多四键上屏
- 自动四码上屏
- 支持临时拼音输入（编码前加 `i`）
- 支持临时英文输入
- Emoji 联想输入

**界面**
- 内嵌预编辑，编码直接显示在当前文本框内
- 横排/竖排候选窗口，跟随光标显示
- 浅色/深色/跟随系统外观
- 候选词数量、字体、字号均可配置
- 输入法菜单内置设置窗口，不需要额外安装设置 App

**辅助**
- 反查编码/拼音显示
- GB2312 字符过滤（可选）
- 由 macOS 按需加载，无需辅助功能权限或登录项

## 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- 构建需要 Swift 工具链（Xcode 15+ 或对应版本 Swift toolchain）
- 分发需要 Apple Developer ID Application 证书和公证凭证

## 快速开始

```bash
git clone https://github.com/cch123/cqlb.git && cd cqlb
```

```bash
# 1. 在 Makefile 里把 IME_CERT_NAME 改成你自己的 Developer ID
#    "Developer ID Application: Your Name (TEAMID)"

# 2. 首次配置公证凭证（一次性）：
xcrun notarytool store-credentials cqlb-notary \
    --apple-id "your@apple-id" \
    --team-id "YOURTEAMID" \
    --password "xxxx-xxxx-xxxx-xxxx"

# 3. 本机安装调试版 IME
make install

# 4. 生成可分发 release zip
make package-ime

# 5. 生成 macOS 安装包 pkg（安装到 /Library/Input Methods）
make pkg-ime
```

`make package-ime` 会执行 release 构建、Developer ID 签名、提交 Apple
公证、staple、验证，并生成：

```
dist/cqlb-ime-notarized.zip
```

`make pkg-ime` 会把 `dist/cqlb-ime.app` 里当前已公证并 staple 的 IME
打成安装包：

```
dist/cqlb-ime-installer.pkg
```

pkg 组件被标记为不可重定位，会固定安装到 `/Library/Input Methods`。
安装脚本会清理当前登录用户下旧的
`~/Library/Input Methods/cqlb-ime.app`，避免同一个 bundle identifier
同时存在两份时系统拉起旧副本。

默认会生成未签名 pkg。它内部的 `cqlb-ime.app` 已签名并公证，但 pkg
本身要完全无警告分发还需要 Developer ID Installer 证书：

```bash
make pkg-ime PKG_CERT_NAME="Developer ID Installer: Your Name (TEAMID)"
```

首次安装后，到 **系统设置 → 键盘 → 文本输入 → 输入法 → +** 添加
“超强两笔”。

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

1. **IMKServer 启动** — 系统 `TextInputMenuAgent` 按需拉起 IME 进程
2. **事件处理** — `IMKInputController.handle(_:client:)` 接收 NSEvent
3. **编码匹配** — 击键送入引擎，查询超强两笔码表，匹配候选词
4. **内嵌预编辑** — `client.setMarkedText` 把编码显示在文本框内
5. **文本上屏** — `client.insertText` 提交最终文本
6. **候选窗口** — 通过 IMK client API 获取光标位置并绘制候选窗口

## 配置

菜单栏输入法图标 → **超强两笔 → 设置…**

设置窗口在 `cqlb-ime.app` 进程内打开，读写：

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
│   ├── CqlbCore/         # 核心库：引擎、码表、配置
│   ├── CqlbIME/          # IME：IMKServer、IMKInputController、候选窗口
│   ├── CqlbSettingsUI/   # 输入法内置 SwiftUI 设置界面
│   ├── CqlbQuery/        # 命令行查询工具（开发用）
│   └── CqlbRepl/         # 交互式 REPL（开发用）
├── Dicts/                # 码表文件
├── Resources/            # IME Info.plist、本地化、图标
├── scripts/              # IME 图标生成脚本
├── Package.swift
├── Makefile
└── dev.sh
```

## 构建命令

```bash
make build                 # debug 构建 cqlb-ime
make install               # debug 构建并安装到 ~/Library/Input Methods
make install CONFIG=release
make package-ime           # release + notarize + zip，不写入 ~/Library
make pkg-ime               # 从 dist 中已公证的 IME 生成 pkg 安装包
make package-installer     # release + notarize + zip + pkg
make clean
make uninstall             # 删除 ~/Library/Input Methods/cqlb-ime.app
```

码表文件位于 `Dicts/`，构建时会自动复制到
`cqlb-ime.app/Contents/Resources/Dicts/`。

## IME 分发要点

### Bundle Identifier 必须含 `.inputmethod.` 作为中间组件

- ✅ `com.cqlb.inputmethod.cqlb`
- ✅ `im.rime.inputmethod.Squirrel`
- ✅ `com.apple.inputmethod.SCIM`
- ❌ `com.cqlb.inputmethod`

macOS IME 发现路径会过滤不符合 `.inputmethod.<suffix>` 形态的 bundle。

### 必须 Developer ID 签名 + 公证 + staple

macOS 15+ 上，第三方 IME 需要完整的 Developer ID 签名、公证和 stapled
ticket。Makefile 会在 `bundle-ime` 阶段做签名校验，在 `notarize-ime`
阶段做：

```bash
xcrun stapler validate dist/cqlb-ime.app
codesign --verify --strict -R="notarized" dist/cqlb-ime.app
```

### 名字本地化必须把 TISInputSourceID 作为 key

`Resources/zh-Hans.lproj/InfoPlist.strings` 里除了 `CFBundleName`，还必须
映射 mode ID：

```
"CFBundleName"                       = "超强两笔";
"com.cqlb.inputmethod.cqlb"          = "超强两笔";
"com.cqlb.inputmethod.cqlb.Hans"     = "超强两笔";
```

否则输入法列表里可能直接显示原始 identifier。

### Info.plist 必要键

- `LSBackgroundOnly=false` + `LSUIElement=true`
- `Contents/PkgInfo` 文件（8 字节 `APPL????`）
- `ComponentInputModeDict`
- `InputMethodConnectionName = $(PRODUCT_BUNDLE_IDENTIFIER)_Connection`

完整对照见 `Resources/IME-Info.plist`。

### pkg 必须禁用 bundle relocation

macOS Installer 默认会尝试按 bundle identifier 查找旧 app 并重定位安装目标。
输入法不能接受这个行为：如果 `cqlb-ime.app` 被重定位到构建目录或下载目录，
`TextInputMenuAgent` 可能注册错误路径，表现为切到输入法后按键没有反应。

`scripts/pkg-components.plist` 将 `BundleIsRelocatable` 设为 `false`，
`make pkg-ime` 必须带上这个 component plist。

### IME 菜单 / Fn HUD 图标用 Apple-style TIFF

输入法列表、菜单栏切换器和 Fn HUD 都走 TIS 小图标路径。当前使用
`cqlb-label.tiff`，不设置 `TISIconIsTemplate`，避免浅底深字被系统压成
单色 mask 后在选中态消失。

修改图标时需要 bump `CFBundleVersion`，并重启
`TextInputMenuAgent` / `TextInputSwitcher` / `ControlCenter` /
`SystemUIServer`，否则系统可能继续使用旧缓存。

### 首次公证可能要更久

新 Developer Team 的第一次公证可能进入 Apple 的 in-depth analysis 队列。
之后同一 Team ID 的提交通常几分钟完成。

## 已知限制

- 需要 Apple Developer ID（$99/年）做签名和公证。
- 光标定位依赖 client 实现；少数 Carbon/Terminal 应用不提供完整 IMK
  caret rect，候选窗口会回退到屏幕中下方。

## 致谢

- **付东升** — 超强两笔编码方案及码表
- **Rime** — 码表格式参考
- **OpenCC** — Emoji 数据

## 许可证

MIT
