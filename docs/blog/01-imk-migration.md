# 把我的开源中文输入法从"外挂"改造成系统级 IME，踩的所有坑

> 主角：[cqlb（超强两笔）](https://github.com/cch123/cqlb)，我自己写的 macOS 开源中文输入法。
> 起点：基于 `CGEventTap` 的"外挂"方案。
> 目标：改成 `InputMethodKit` 的系统级标准输入法。
> 总耗时：从规划到真正能用，断断续续两天，其中大半天在和 macOS 的各种沉默过滤斗智斗勇。
> macOS 版本：Tahoe 26 beta（Darwin 25.4）。

---

## 0. 起点：cqlb 原本是怎么工作的

cqlb 是一个 macOS 菜单栏常驻应用，核心是：

- `CGEventTap` 注册全局键盘监听
- 收到 keyDown → 查超强两笔码表 → 在独立候选窗口展示
- 用户选择候选词 → `CGEvent.keyboardSetUnicodeString` + `CGEvent.post` 把文本"注入"当前 app

它**不是**系统标准 IME，所以不需要在"键盘设置 → 输入法"里添加，只要授予"辅助功能"权限就能用。好处是实现简单、不受 Apple 的 IME 限制；坏处是几个固有的：

1. **无内嵌预编辑**：编码只能显示在独立候选窗口，没法在当前文本框里 inline 显示
2. **Electron 兼容性差**：某些 Electron app 不接收注入的文本
3. **每次更新都要重新授权辅助功能**（cdhash 变了 TCC 就失效）
4. **跟系统的输入法切换机制割裂**：密码框不会自动切英文

我一直想把它改成标准 IME 模式，拖到最近终于动手了。

---

## 1. 技术上要改什么

macOS 的标准输入法走 `InputMethodKit`（IMK），架构是：

- 你的 bundle 装到 `~/Library/Input Methods/` 或 `/Library/Input Methods/`
- 系统进程 `TextInputMenuAgent` / `imklaunchagent` 按需拉起你的进程
- 你的进程里跑 `IMKServer`，每连接一个客户端（app），系统自动实例化一个 `IMKInputController`
- controller 响应各种回调：`handle(_:client:)`、`activateServer`、`commitComposition`...

替换映射大致是：

| 外挂模式（CGEventTap） | IMK 模式 |
|---|---|
| `CGEvent.tapCreate` 全局监听 | `IMKInputController.handle(_:client:)` |
| `CGEventPost` 注入 | `client.insertText(_:replacementRange:)` |
| 独立候选窗 + AX 光标查询 | 候选窗 + `client.attributes(forCharacterIndex:lineHeightRectangle:)` |
| 辅助功能权限 | 无需特殊权限 |
| 无内嵌预编辑 | `client.setMarkedText(_:selectionRange:replacementRange:)` 原生支持 |

核心引擎（码表加载、候选匹配、配置读写）完全不用动——我把它放在独立的 `CqlbCore` 纯 Swift 模块里，两种模式共用。

## 2. 高层架构

```
┌──────────────────────────┐      ┌──────────────────────────┐
│ CqlbApp (外挂)           │      │ CqlbIME (IMK)            │
│  ~/Applications/         │      │  ~/Library/Input Methods │
│  CGEventTap              │      │  IMKServer +             │
│  TextInjector            │      │   IMKInputController     │
└────────────┬─────────────┘      └────────────┬─────────────┘
             │                                  │
             └──────────┐          ┌────────────┘
                        ▼          ▼
              ┌─────────────────────────────┐
              │ CqlbCore (unchanged)        │
              │  Engine / Dict / Config     │
              └──────────────┬──────────────┘
                             ▲
                             │ shares config.json
                             │
              ┌──────────────┴──────────────┐
              │ CqlbSettings (SwiftUI)      │
              └─────────────────────────────┘
```

代码没什么花活，基本对着 Apple 的 `InputMethodKit` 文档照抄加上我自己的引擎调用就行。几个小时就写完了。

然后开始折磨人的部分。

---

## 3. 坑一：macOS 15+/26 对自签 IME 的**静默**过滤

写完代码、打包成 bundle、装到 `~/Library/Input Methods/cqlb-ime.app`、ad-hoc 签名，兴冲冲打开"键盘设置 → 文本输入 → 输入法 → +"。

**没有我的输入法。**

在"简体中文"分类下只有 Apple 自带的那几个和已经装过的鼠须管。没有 cqlb。

排查路径：

```bash
# LaunchServices 知道我的 bundle 吗？
lsregister -dump | grep com.cqlb.inputmethod
# 知道，已注册

# TIS 能枚举到吗？
TISCreateInputSourceList(nil, true) | filter
# 不能，321 个输入源里没我的

# 手动调 TISRegisterInputSource 呢？
let r = TISRegisterInputSource(url as CFURL)
# r == 0 (noErr)，但依然不出现
```

系统日志也没有任何说明为什么我被拒绝——**静默过滤**。

对比鼠须管（Squirrel）：它在 `/Library/Input Methods/` 下（系统级），属主 `root:wheel`。我 `sudo ditto` 过去，`chown` 到 `root:wheel`，改属主、重新签。**还是不出现**。

最后我拿鼠须管的 `codesign -dvvv` 输出一看：

```
Authority=Developer ID Application: Yuncao Liu (28HU5A7B46)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
```

**证书链 anchor 到 Apple Root CA。** 我的是：

```
Authority=cqlb-dev       ← 自签
```

我写了个脚本把 `cqlb-dev` 证书导入 System 钥匙串，设成 "Always Trust / Code Signing"，重新签。**还是不出现**。

做了一个对照实验：写一个最小化的 IMK sample（就几十行代码，啥都不做），同样流程装上去。**也不出现**。

到这里基本确定：**macOS 15+/26 要求第三方输入法必须用 Apple 签发的 Developer ID 证书。** 本地信任的自签不算。

这个"限制"在 Apple 官方文档里**找不到**。Hacker News 和 Apple Developer Forums 上有零星讨论提到类似现象，但没一个说得清楚。我是用排除法一步步验证出来的。

结论：掏钱吧。$99/年。

## 4. 坑二：Apple Developer 的"新团队首次公证"

付完钱、Xcode 里生成 `Developer ID Application` 证书、改 Makefile 的 CERT_NAME、重新签——

```bash
codesign -dvvv cqlb-ime.app
# Authority=Developer ID Application: CHUNHUI CAO (WW9TMJ499X)
# Authority=Apple Root CA
```

合规了。去 picker 里看——**还是没有**。

再查：

```bash
spctl -a -vvv --type execute cqlb-ime.app
# rejected
# source=Unnotarized Developer ID
```

啊对，macOS 15+ 要求**公证**。Developer ID 签名 ≠ 公证。Gatekeeper 要两样都有。

公证就是把 bundle 上传给 Apple 的服务器扫一遍恶意代码，返回一个 ticket 贴回 bundle。流程：

```bash
xcrun notarytool store-credentials cqlb-notary \
    --apple-id "xxx@xxx.com" \
    --team-id "WW9TMJ499X" \
    --password "app-specific-password"   # appleid.apple.com 生成

xcrun notarytool submit cqlb-ime.zip \
    --keychain-profile cqlb-notary \
    --wait
```

Apple 文档说"most uploads within 5 minutes"。

我的**第一次**提交：**3 小时 20 分钟**才 Accepted。

Apple DTS 有个回帖解释：

> "Occasionally, some uploads are held for **in-depth analysis** and may take longer to complete. As you notarise your apps, the system will learn how to recognise them, and you should see fewer delays."

翻译：新 Developer 团队的第一次提交会进 Apple 的"深度分析"队列。论坛报告里有人等了 24~72 小时。

好消息是：同一 Team ID 的**后续提交**基本 2-5 分钟。我后来又连着公证了 5 次调试，每次都几分钟。

## 5. 坑三（真正的根因）：bundle ID 必须含 `.inputmethod.` 作为中间组件

签名通过了、公证通过了、Gatekeeper 接受了、`syspolicy_check distribution` 全绿——**还是不出现在 picker 里**。

我又花了几个小时对齐鼠须管的所有可见配置：

- `LSBackgroundOnly=false` + `LSUIElement=true`（两个都要有）
- `Contents/PkgInfo` 文件（8 字节 `APPL????`）
- `InputMethodServerControllerClass` 用 `Module.ClassName` 形式（Swift module-qualified）
- 删掉 `@objc(CustomName)` 注解，靠 Swift 自动的 `CqlbIME.CqlbInputController` 注册

还是不出现。

我都快要开 Apple DTS 的 support ticket 了。最后在 Google 搜了半天，找到一个中文博客 [R0uter's Blog](https://www.logcg.com/en/archives/2078.html)，里面一句话：

> The bundle identifier **must contain the keyword "inputmethod" and place it before the final dot separator**.

对照一下：

| IME | Bundle ID | `.inputmethod.` 在中间？ |
|---|---|---|
| 鼠须管 | `im.rime.inputmethod.Squirrel` | ✅ |
| Apple 简体拼音 | `com.apple.inputmethod.SCIM` | ✅ |
| Apple 韩文 | `com.apple.inputmethod.Korean` | ✅ |
| **我** | `com.cqlb.inputmethod` | ❌ `inputmethod` 是最后一段 |

我用的 `com.cqlb.inputmethod`，**`inputmethod` 是最后一段**，没有后续。macOS 的 IME 发现代码按 `.inputmethod.<suffix>` pattern 过滤 bundle，不符合的直接不列出来。**没有日志、没有错误、没有任何提示**。

改成 `com.cqlb.inputmethod.cqlb`，重新签、重新公证。

**这一次，出来了。**

---

## 6. 其他收尾的小坑

### 6.1 名字本地化必须把 TISInputSourceID 作为 key

第一次出现时，picker 里显示的不是"超强两笔"，而是原始的 `com.cqlb.inputmethod.cqlb.Hans`。

标准的 `InfoPlist.strings` 里我写了：

```
"CFBundleName" = "超强两笔";
"CFBundleDisplayName" = "超强两笔";
```

但 picker 显示的是**模式 ID**，不是 bundle name。Squirrel 的做法是把 mode ID 本身作为 key：

```
"CFBundleName"                       = "鼠须管";
"im.rime.inputmethod.Squirrel"       = "鼠须管";
"im.rime.inputmethod.Squirrel.Hans"  = "鼠须管";
"im.rime.inputmethod.Squirrel.Hant"  = "鼠鬚管";
```

### 6.2 候选窗口定位

外挂模式用 Accessibility API 获取光标位置。IMK 模式要用 IMK 自己的：

```swift
// 优先
var rect = NSRect.zero
_ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)

// 备选（一些 app 只支持这个）
let rect = client.firstRect(forCharacterRange: range, actualRange: &actual)
```

一开始我只用了第二种，TextEdit 里窗口总是跑到屏幕左下角。加上第一种 fallback 之后正常了。

### 6.3 图标样式

我一开始做的是黑底 + 白字的 rounded rect PDF，picker 里 16×16 小尺寸下显示成**纯白方块**——系统对 IME 图标做了 template rendering（可能把黑色当成"前景色"反色了）。

后来又踩了 Fn HUD 的坑：如果给"浅底深字"的彩色图设置 `TISIconIsTemplate=true`，系统会把浅底和黑字压成同一个单色 mask，选中态里就变成一个空白色块。最终方案是学 Squirrel 的非 template 路线：不设置 `TISIconIsTemplate`，`tsInputModeMenuIconFileKey`、`tsInputModeAlternateMenuIconFileKey`、`tsInputMethodIconFileKey` 都指向同一张完整的 `cqlb-label.tiff`。

这张 TIFF 还有几个细节：

- 尺寸只放 `22×16` 和 `44×32 @2x`，避免 Fn HUD 拿到大 app icon rep 后乱缩放。
- 白色 badge 占满完整 `22×16` 画布；一旦留透明 inset，就会比 Apple / Squirrel 的输入法图标小一圈。
- "两"字不是用字体 metrics 居中，而是先离屏渲染，扫描真实可见墨迹 bbox，再把 bbox 居中。小尺寸中文 glyph 的 side bearing 和抗锯齿会让 metrics 居中看起来偏；最终还要加 1px 的 optical y-offset，把视觉重心偏上的“两”略微下移。
- 改图标时要 bump `CFBundleVersion`，必要时重启 `TextInputMenuAgent` / `TextInputSwitcher` / `ControlCenter` / `SystemUIServer`，否则系统会继续吃旧缓存。

### 6.4 IME 菜单入口

外挂模式有菜单栏 icon，点击出"设置…"。IMK 模式要在 `IMKInputController.menu()` 里返回一个 `NSMenu`，系统会把它挂到菜单栏输入法切换器里的当前 IME 条目下。

```swift
override func menu() -> NSMenu! {
    let menu = NSMenu()
    let settings = NSMenuItem(title: "设置…", action: #selector(openSettings(_:)), keyEquivalent: "")
    settings.target = self
    menu.addItem(settings)
    return menu
}

@objc private func openSettings(_ sender: Any?) {
    if let url = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.cqlb.settings"
    ) {
        NSWorkspace.shared.open(url)
    }
}
```

---

## 7. 总结：一份完整的 IME bundle checklist

给从头做 macOS 输入法的自己或别人一份清单，按顺序检查：

**代码层面**

- [ ] 继承 `IMKInputController`，实现 `handle(_:client:)`、`activateServer`、`commitComposition`
- [ ] `main.swift` 里启动 `IMKServer(name: connectionName, bundleIdentifier: bundleId)`
- [ ] `NSApplication.shared.setActivationPolicy(.accessory)`
- [ ] Swift 类**不要**加 `@objc(custom_name)` 注解，让 Swift 自动注册为 `Module.ClassName`

**Bundle 结构**

- [ ] 装到 `~/Library/Input Methods/` 或 `/Library/Input Methods/`
- [ ] 属主 `root:wheel`（系统级必需；用户级可以是普通用户）
- [ ] `Contents/PkgInfo`（8 字节 `APPL????`）
- [ ] `Contents/Resources/<name>.icns`（多分辨率，透明背景 + 黑色单字符）
- [ ] `Contents/Resources/{zh-Hans,en}.lproj/InfoPlist.strings`

**Info.plist 必需键**

- [ ] `CFBundleIdentifier` 必须形如 `com.xxx.inputmethod.yyy`（**`inputmethod` 在中间，不能是最后一段**）
- [ ] `LSBackgroundOnly = false` + `LSUIElement = true`（两个都要）
- [ ] `NSPrincipalClass = NSApplication`
- [ ] `InputMethodServerControllerClass = "YourModule.YourController"`
- [ ] `InputMethodServerDelegateClass`（同上）
- [ ] `InputMethodConnectionName = "$(PRODUCT_BUNDLE_IDENTIFIER)_Connection"`
- [ ] `ComponentInputModeDict` 含 `tsInputModeListKey` 和 `tsVisibleInputModeOrderedArrayKey`
- [ ] 每个 mode dict 里有 `TISInputSourceID` / `TISIntendedLanguage` / `tsInputMode*IconFileKey` / `tsInputModePrimaryInScriptKey: true` / `tsInputModeScriptKey: "smUnicodeScript"`

**InfoPlist.strings 本地化**

- [ ] `"CFBundleName" = "显示名";`
- [ ] `"com.xxx.inputmethod.yyy" = "显示名";`（bundle ID 作为 key）
- [ ] `"com.xxx.inputmethod.yyy.<Mode>" = "显示名";`（**每个 mode ID 作为 key**，不然 picker 显示原始 ID）

**签名与公证（macOS 15+/26 必需）**

- [ ] 用 **Apple Developer ID Application** 证书签名（$99/年 Developer Program 会员才能申请）
- [ ] 签名时 `--options runtime --timestamp`
- [ ] 上传 Apple notary service：`xcrun notarytool submit ... --wait`
  - 新团队首次可能 24-72 小时
  - 后续提交通常 2-5 分钟
- [ ] `xcrun stapler staple bundle.app` 把 ticket 贴回
- [ ] `spctl -a -vvv --type execute bundle.app` 应该返回 `source=Notarized Developer ID`

**发现与激活**

- [ ] 装完之后 `killall TextInputMenuAgent` 刷新系统扫描
- [ ] 首次添加需要用户在"键盘设置 → 文本输入 → 输入法 → +"里手动添加

---

## 8. 感想

macOS 的输入法开发生态在苹果官方文档里的覆盖度**非常低**。`InputMethodKit` 的 API 文档是 2006 年 WWDC 那一批的，大量关键要求（bundle ID 格式、公证强制、mode ID 本地化方式）都要靠：

- 读 Squirrel 的源码
- 对比 Apple 内置 IME 的 Info.plist
- 在 Apple Developer Forums 海底捞针
- 中文开发者博客里的老文章
- 自己反复踩坑

如果 Apple 能把这份 checklist 正经写成一份"IME developer guide"，能省掉无数开发者的周末。

但也正因为这样——做出来是有成就感的。

---

## 9. 如果你也想做 macOS 输入法

- 源码参考：[cqlb](https://github.com/cch123/cqlb)（MIT 协议）
- Rime 项目 Squirrel：[rime/squirrel](https://github.com/rime/squirrel)（最成熟的开源 IMK 参考实现）
- Apple 官方（陈旧但还是要看）：[InputMethodKit documentation](https://developer.apple.com/documentation/inputmethodkit)
- 社区笔记：[Let's talk about what InputMethodKit needs to improve](https://gist.github.com/ShikiSuen/73b7a55526c9fadd2da2a16d94ec5b49)

欢迎 star / PR / 提 issue。
