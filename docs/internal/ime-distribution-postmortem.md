# IME 分发与设置入口问题复盘

日期：2026-06-01

这份文档记录超强两笔 IME 分发化过程中遇到的几个关键问题、最终根因和
后续维护注意事项。相关修复主要在：

- `f4e3969 Make cqlb IME distributable`
- `b208e80 Fix IME settings menu command`
- `323a412 Fix distributable IME settings flow`

## 结论摘要

这些问题不是同一个 bug，而是 macOS 输入法分发链路上的几个不同缓存和
运行时约束叠加：

1. IME 必须是 Developer ID 签名、公证并 stapled 的 app bundle。pkg
   本身是否签名不是按键无响应的直接原因。
2. pkg payload 必须固定安装到 `/Library/Input Methods`，不能让 Installer
   bundle relocation 改路径。
3. 打包流程不能为了公证临时安装一份同 bundle id 的 IME 到
   `~/Library/Input Methods`。这会污染 TIS/LaunchServices 缓存，后续 pkg
   删除该副本后，系统仍可能尝试拉起已不存在或旧版本的用户目录副本。
4. TextInput 相关进程缓存很重。安装后需要清理旧 `cqlb-ime`、重启
   `TextInputMenuAgent` / `TextInputSwitcher` 等，并确保系统目录下的 app
   已注册。
5. IMK 菜单命令派发不是普通稳定的 AppKit 菜单路径。需要同时兼容 IMK
   `doCommand(by:command:)` 和普通 target/action。
6. 不要在 IME 进程里用 `NSWindow(contentViewController:)` 创建设置窗口。
   macOS 26 上它会走 AppKit 私有 title binding 路径，在 IME 进程内抛
   ObjC exception 并导致整个输入法崩溃。

## 问题一：安装后输入法列表找不到 cqlb

### 现象

pkg 安装成功，但系统设置里的输入源列表找不到“超强两笔”，或者列表状态
刷新不稳定。

### 根因

macOS 对第三方 IME 的发现有硬性过滤：

- bundle identifier 需要符合类似 `com.xxx.inputmethod.yyy` 的形态。
- app bundle 需要 Developer ID Application 签名。
- macOS 15+ 上还需要公证并 stapled ticket。
- Info.plist、`ComponentInputModeDict`、本地化名、`PkgInfo` 等字段必须完整。

pkg 是否用 Developer ID Installer 签名不是 IME 是否能被加载的核心条件。
pkg 签名主要影响安装包展示和分发信任提示；真正被系统加载的是
`cqlb-ime.app`。

### 修复

- 使用 Developer ID Application 给 `cqlb-ime.app` 签名。
- `notarytool submit --wait` 后 `stapler staple` 到 app bundle。
- 在构建阶段校验：

```bash
codesign --verify --strict -R="notarized" dist/cqlb-ime.app
xcrun stapler validate dist/cqlb-ime.app
```

## 问题二：能看到图标，但键盘按键没反应

### 现象

菜单栏能看到“超强两笔”图标，输入源也能切过去，但按键没有进入 IME，
`/tmp/cqlb-ime.log` 没有新的启动或 `activateServer` 记录。

### 根因

最终确认有两个容易触发该现象的路径缓存问题：

1. pkg bundle relocation：
   macOS Installer 默认会按 bundle id 查找旧 app，并可能把 payload 重定位到
   旧位置。IME 必须固定安装在 `/Library/Input Methods` 或
   `~/Library/Input Methods`，路径错了会导致 TextInput 系统注册错误 app。

2. 打包流程污染 `~/Library/Input Methods`：
   旧的 `make package-installer` 先运行 `install-ime`，把同 bundle id 的
   `cqlb-ime.app` 临时装到 `~/Library/Input Methods`，然后 pkg 又安装到
   `/Library/Input Methods`，postinstall 再删除用户目录副本。

   这会让 TIS/LaunchServices/TextInputMenuAgent 缓存短时间内看到两份
   相同 bundle id 的 IME。用户目录副本被删除后，系统仍可能尝试拉起旧路径，
   结果表现为“输入源存在但按键没反应”。

### 修复

- `scripts/pkg-components.plist` 设置：

```xml
<key>BundleIsRelocatable</key>
<false/>
```

- `make package-ime` 改为只生成和公证 `dist/cqlb-ime.app`，不再安装到
  `~/Library/Input Methods`。
- `make pkg-ime` 只从 `dist/cqlb-ime.app` staging payload。
- `scripts/pkg/postinstall`：
  - 删除当前 console user 的旧 `~/Library/Input Methods/cqlb-ime.app`。
  - `lsregister -f` 注册 `/Library/Input Methods/cqlb-ime.app`。
  - 终止旧 `cqlb-ime`。
  - 重启 `TextInputMenuAgent`、`TextInputSwitcher`、`ControlCenter`、
    `SystemUIServer`。
  - `TextInputSwitcher` 对 TERM 不敏感，因此对它使用 `killall -KILL`。
  - 安装完成后用 `launchctl asuser ... open -g` 拉起 `/Library` 下的新 IME。

## 问题三：菜单里的“设置…”点击没反应

### 现象

输入法能正常打字，菜单里有“设置…”，点击后没有任何可见效果。

### 根因

这类菜单不是完全普通的 AppKit 菜单。IMK 文档里说明输入法菜单项可能通过
`doCommandBySelector:commandDictionary:` 派发，sender 是 command dictionary。
macOS 26 上又会出现普通 target/action 路径和 IMK command 路径混用的情况。

只依赖一种路径时，菜单项可能显示但点击没有进入设置逻辑。

### 修复

- 给菜单项显式设置 `target = self` 和 `isEnabled = true`。
- 菜单 action 使用无参数 selector：

```swift
#selector(openSettingsMenuItem)
```

- 同时保留 `doCommand(by:command:)` 兜底，兼容 IMK command dispatch：

```swift
if selector == #selector(openSettingsMenuItem) || selector == #selector(openSettings(_:)) {
    openSettings(info)
}
```

### 验证信号

点击菜单后，`/tmp/cqlb-ime.log` 应该看到：

```text
[imk] open settings requested
```

如果只看到大量：

```text
[imk] menu requested
```

说明系统只是反复请求菜单内容，点击 action 还没有进入设置逻辑。

## 问题四：设置菜单 action 收到了，但窗口不显示

### 现象

日志已经出现：

```text
[imk] open settings requested
```

但用户看不到设置窗口。

### 根因

IME 进程是 `LSUIElement` / accessory app。它适合后台处理输入，但不是一个
稳定的前台窗口宿主。菜单点击发生时 `TextInputMenuAgent` 仍在 tracking
输入法菜单，立即创建普通设置窗口可能被当前文本客户端盖住或无法成为 key
window。

### 修复

- 点击菜单后延迟一个 run-loop turn：

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { ... }
```

- 展示设置窗口前临时把 activation policy 提升为 `.regular`。
- 关闭设置窗口时恢复 `.accessory`。
- `orderFrontRegardless()` 仍保留，用来处理 IME 窗口被文本客户端压住的情况。

## 问题五：点击设置导致“超强两笔”意外退出

### 现象

点击“设置…”后，系统弹出：

```text
“超强两笔”意外退出。
```

crash report 中 fault stack 在：

```text
SettingsWindowPresenter.show(onSave:)
NSWindow.__allocating_init(contentViewController:)
_bindTitleToContentViewController
NSBinder addBinding
```

### 根因

`NSWindow(contentViewController:)` 是 AppKit convenience initializer。
在 macOS 26 的 IME 进程里，它会进入 AppKit 私有的
`_bindTitleToContentViewController` 路径，并抛 ObjC exception。Swift 无法
正常 catch 这个 ObjC exception，最终整个 IME 进程 abort。

这个 crash 与输入引擎无关，发生在设置窗口创建阶段。

### 修复

不要用：

```swift
NSWindow(contentViewController: hostingController)
```

改成先创建普通 `NSWindow`，再设置 `contentViewController`：

```swift
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
    backing: .buffered,
    defer: false
)
window.contentViewController = hostingController
window.title = "超强两笔 · 设置"
```

这样绕开 AppKit 的 title binding convenience path，设置窗口可以正常显示。

## 后续维护原则

- 打包、公证、pkg staging 只操作 `dist/cqlb-ime.app`，不要在分发流程中写入
  `~/Library/Input Methods`。
- 本机开发安装可以继续用 `make install`，但这只服务本机调试，不参与 pkg
  分发。
- 每次修改 Info.plist、图标、菜单、安装路径相关内容，都 bump
  `CFBundleVersion`，否则 macOS TIS 缓存可能继续使用旧元数据。
- 遇到“图标存在但按键没反应”，优先查：

```bash
tail -n 200 /tmp/cqlb-ime.log
ps -axo pid,lstart,command | rg 'cqlb-ime|TextInputMenuAgent|TextInputSwitcher'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "/Library/Input Methods/cqlb-ime.app/Contents/Info.plist"
codesign --verify --strict -R="notarized" \
  "/Library/Input Methods/cqlb-ime.app"
```

- 遇到“菜单设置没反应”，优先看 `/tmp/cqlb-ime.log` 中是否有：
  - `menu requested`
  - `open settings requested`
  - `present settings window`
- 遇到设置 crash，先看 `~/Library/Logs/DiagnosticReports/cqlb-ime-*.ips`，
  不要只看输入法逻辑。
