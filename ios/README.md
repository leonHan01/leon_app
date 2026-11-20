# Leon iOS 原生版

独立 SwiftUI / UIKit 应用，最低 iOS 16，面向 iPhone 与 iPad。Android 原生工程、Mac 原生工程和已有安装包继续保留。本目录不依赖 Dart、Flutter、CocoaPods 或第三方 Swift 包。

当前状态：已安装并初始化 Xcode 27.2，iPhoneOS Release 整包编译通过（arm64、最低 iOS 16）；SwiftUI / UIKit 源码已完成 SDK 类型检查。20 项核心与 HTTP 协议场景、11 项正文检查通过。已为连接的 iPhone 16 Pro 完成免费个人签名、生成 IPA 并成功安装。用户完成开发者信任后，**真机启动验证已通过**；完整功能尚未真机验收。

## 已实现的范围

| 范围 | 原生实现 |
| --- | --- |
| 账号 | 服务地址、访问令牌、UserName 注册 / 登录、Keychain 保存会话、退出与失效处理 |
| 导航 | Agents / 群聊 / 设置、Agent 主页、固定私聊、命名独立对话、创建群聊和添加用户 |
| 聊天 | 前台轮询、增量同步、更早历史、回复 / 压缩状态、失败回复重试与本机忽略、消息原文复制 |
| 输入 | UIKit 输入框、中文组词、@候选与键盘补全、Enter 发送、Shift+Enter 换行 |
| 图片 | 原生相册选择与图片粘贴、方向校正、压缩、多图草稿、预览和重试；每条最多 4 张 |
| 可靠发送 | 先持久化后上传，重试保留消息 / 图片 UUID；账号与服务器隔离；清理记录时同步删除本地待发附件 |
| 上下文 | 查看及刷新摘要、调整保留轮数、手动压缩、清理前预览 / 备份 / 确认 |
| 备份 | 系统文件导出 ZIP、有限大小的本地预览、校验后确认恢复到独立对话 |
| 用量 | 输入 / 输出 / 总 Token、调用统计、沿用已有日期版本的价格估算、失败保留上次结果 |

上述为代码实现范围，并不代表每项已完成 iOS 真机验证。草稿及最近会话缓存在内存中，待发队列与失败忽略状态保存到磁盘；应用进入后台暂停轮询，回到前台再同步。Mac 专属的 LeonBook CLI 归档没有移入 iOS。

页面、导航、输入、相册、文件选择、凭据及网络均使用系统框架。消息正文使用系统 WKWebView 加载打包在本地的 Markdown / KaTeX / Mermaid 组件，复用现有 Android、Mac 的排版资源和许可证；并非整个应用使用网页页面。文本桥接中不传访问令牌，外链图片不携带服务凭据。

## 打开与构建

在仓库根目录准备离线正文资源：

```bash
npm ci --prefix shared/markdown
node ios/Tools/prepare-assets.mjs
python3 ios/Tools/generate-project.py
```

然后用完整 Xcode 打开 `ios/Leon.xcodeproj`，选择 `Leon` scheme。真机运行需要在 Signing & Capabilities 中设置自己的开发团队和可用 Bundle ID。首次运行前确保服务端已支持下述 iOS 平台字段。

可用脚本只编译，不启动 App 或模拟器：

```bash
bash scripts/build-ios.sh simulator
bash scripts/build-ios.sh device
```

脚本检查完整 Xcode、运行核心与正文检查、准备资源并构建。输出分别是 `dist/Leon-iOS-simulator-unsigned.zip` / `dist/Leon-iOS-device-unsigned.zip`，包含未签名的 `.app`。设备 ZIP 不是可直接安装的 IPA；签名、归档、TestFlight / App Store 分发须在 Xcode 中完成。

本机另外已生成 `dist/Leon-iOS-personal.ipa`（约 3 MB），通过 `codesign --verify --deep --strict` 及 ZIP 内容完整性检查。描述文件已确认包含当前 iPhone，个人签名有效期至 **2026-11-27 21:42（北京时间）**。此包仅供已登记设备使用，不能在手机上点开当作 APK 安装；有效期届满需要重新签名安装。个人签名构建使用 Xcode 中选定的 Personal Team，普通构建脚本仍输出未签名版本。

`Resources/Markdown` 是被忽略的生成目录；正文补丁只作用于该 iOS 副本，不修改现有两端使用的资源。直接从干净检出打开工程前须执行资源准备步骤。

## 检查与待验收项

无需完整 Xcode 的核心检查：

```bash
bash scripts/test-ios-core.sh
node ios/Tools/test-renderer.mjs
```

核心检查覆盖真实磁盘隔离及损坏队列、先保存再发送、图片断网重试、历史修订与 LRU 淘汰、跨会话图片批次、清空后的延迟图片、草稿、失败提示、用量、登录失效、禁止重定向，以及拦截 URLSession 的 HTTP 协议用例。ZIP 检查覆盖 stored / deflate、CRC、损坏与超限文件。HTTP 测试使用进程内响应，不访问生产服务或调用模型。正文的 11 项检查覆盖中文标点粗体、标题、扩展语法、自动链接、转义与代码。

同一脚本还检查 UI 源码语法和工程 plist；**语法解析不等于 iOS SDK 类型检查或运行测试**。iPhoneOS 整包另已通过 Xcode 编译。后续真机验收必须包含：Keychain 重开登录、中文输入与外接键盘、相册 / 粘贴、文件导入导出、富文本高度和滚动、弱网重试、切会话时的迟到响应，以及 Android / iOS 跨端消息与清理同步。当前未启动游戏或模拟器；已在 iPhone 16 Pro 上安装并启动 Leon，用户确认能打开，`devicectl` 再次启动成功。

2026-11-20 本机结果：20 项核心 / HTTP 协议场景、11 项正文检查和 Xcode 27.2 的 iPhoneOS Release 构建通过；产物的 `CFBundleSupportedPlatforms` 为 `iPhoneOS`，离线正文资源完整。个人签名及绑定手机的描述文件已验证，`devicectl` 确认 `com.leon.ios` 安装成功；完成手机开发者信任后，用户确认能打开，命令行再次核验启动成功。原有 Android、Mac 与共享正文的 177 个受保护文件曾在迁移清理阶段核对一致。

## 服务端兼容

客户端发送真实的 `platform: ios`。`ServerCompatibility/ios-platform.patch` 保留原迁移阶段必要的兼容改动：允许 iOS 发送消息、设备心跳和备份消息，并在在线设备列表显示 iOS。`IosClientCompatibilityTest.java` 是对应的服务端回归用例。

同级服务端项目中的这些兼容改动继续保留，**没有部署到公网**。若目标服务器仍只允许 `macos` / `android`，需要先合入并部署平台兼容改动；不要把 iOS 伪装为 Android。群聊、UserName、上下文、独立对话及 ZIP 备份还需要现有对应版本接口和 32 MB 反向代理配置。

## Flutter 清理记录

已删除 `mobile/`、三个 mobile 构建 / 检查 / 准备脚本及 Flutter Android 调试包。已移除本次迁移安装的临时 Flutter SDK、Pub / Dart 缓存、Gradle 9.5.0 与 Flutter 插件专用缓存，并通过 SDK Manager 卸载专门新增的 NDK 28.2、CMake 3.22.1、Android 34 / 36 平台和 Build Tools 36。合计约 12 GB。

保留原生 Android 使用的 SDK 35、Build Tools 35、Gradle 8.11.1、JDK，以及 Mac / iOS 使用的 Swift 工具链和已有共享正文资源。共享缓存未作全盘清空，避免影响原有项目。

## 目录

- `Sources/LeonCore`：协议模型、URLSession、持久化、聊天状态、ZIP 预览、补全与用量估算。
- `Sources/LeonIOS`：SwiftUI 页面、UIKit 输入 / 相册、Security Keychain、WKWebView 正文。
- `Tests`：可用 Command Line Tools 编译执行的核心和协议测试。
- `Tools`：确定性 Xcode 工程生成、离线资源准备、图标转换与测试夹具。
