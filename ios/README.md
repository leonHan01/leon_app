# Leon iOS 原生版

独立 SwiftUI / UIKit 应用，最低 iOS 16，面向 iPhone 与 iPad。Android 原生工程、Mac 原生工程和已有安装包继续保留。本目录不依赖 Dart、Flutter、CocoaPods 或第三方 Swift 包。

当前状态（2026-11-20）：**0.12.3（build 4）** 已通过 Xcode 27.2 的 iPhoneOS Release 编译、个人签名与 IPA 完整性检查。28 项核心 / HTTP 场景和新增的 18 项原生输入框布局场景通过；0.12.2 的 11 项正文解析检查、7 组正文浏览器交互检查和 2 项服务端 iOS 兼容检查亦通过。最近一次核验安装并启动的是 **0.12.1（build 2）**；按用户要求暂时保留新版安装包，完整功能仍需双端实机验收。

0.12.3 修复逐字输入长文本时输入框横向撑宽、挤占发送按钮空间的问题。短文本关闭滚动后，`UITextView` 的固有宽度会随输入增长；现在通过 `UIViewRepresentable.sizeThatFits` 明确接受父布局分配的宽度。输入自动换行，最多显示四行，之后在框内滚动。修复前 393 点宽页面逐字输入至第 17 字即超出预留空间；修复后三种手机宽度的布局回归检查通过，尚未安装到 iPhone 验证。

## 已实现的范围

| 范围 | 原生实现 |
| --- | --- |
| 账号 | 服务地址、访问令牌、UserName 注册 / 登录、Keychain 保存会话、退出与失效处理 |
| 导航 | Agents / 群聊 / 设置、Agent 主页、固定私聊、命名独立对话、创建群聊和添加用户 |
| 聊天 | 前台轮询、增量同步、更早历史、回复 / 压缩状态、失败回复重试与本机忽略、消息原文复制 |
| 输入 | UIKit 输入框、中文组词、@候选与键盘补全、Enter 发送、Shift+Enter 换行 |
| 图片 | 原生相册 / 文件选择与图片粘贴、方向校正、压缩、多图草稿、预览和重试；每条最多 4 张 |
| 可靠发送 | 先持久化后上传，重试保留消息 / 图片 UUID；账号与服务器隔离；清理记录时同步删除本地待发附件 |
| 上下文 | 查看及刷新摘要、调整保留轮数、手动压缩、清理前预览 / 备份 / 确认 |
| 备份 | 系统文件导出 ZIP、有限大小的本地预览、校验后确认恢复到独立对话 |
| 用量 | 输入 / 输出 / 总 Token、调用统计、沿用已有日期版本的价格估算、失败保留上次结果 |

上述为代码实现范围，并不代表每项已完成 iOS 真机验证。草稿及最近会话缓存在内存中，待发队列与失败忽略状态保存到磁盘；应用进入后台暂停轮询，回到前台再同步。Mac 专属的 LeonBook CLI 归档没有移入 iOS。

页面、导航、输入、相册、文件选择、凭据及网络均使用系统框架。消息正文使用系统 WKWebView 加载打包在本地的 Markdown / KaTeX / Mermaid 组件，复用现有 Android、Mac 的排版资源和许可证；并非整个应用使用网页页面。文本桥接中不传访问令牌，外链图片不携带服务凭据。

## Android 功能对齐记录（0.12.2）

以下以仓库中的 Android 原生客户端为基准。表中“已实现”指源码和接口已对应，不代表完整的双端实机验收。

| 功能 | iOS 对应情况与本次补齐 |
| --- | --- |
| 登录与连接 | 已实现 UserName 注册 / 登录、服务地址与令牌、失效退出、连接隔离；iOS 使用 Keychain 保存凭据 |
| Agents 与会话 | 已实现整行点击进入聊天、头像进入主页、介绍 / 模型、历史独立对话、固定私聊与命名新对话；补齐默认新对话时间名称 |
| 群聊 | 已实现创建、成员查看和邀请；补齐旧群聊 ownerId 为空字符串时的管理权限，与 Android 保持一致 |
| 消息与历史 | 已实现发送、增量 / 更早历史、前台轮询、在线设备、8 个会话各 300 条缓存、草稿、持久化待发队列与手动重试 |
| 输入与提及 | 已实现中文组词、@候选、Enter 发送、Shift+Enter 换行；补齐外接键盘候选处理优先级与组词状态检查 |
| 图片 | 已实现相册、粘贴、预览和重试；本次增加从文件选择。每条最多 4 张，输入限 20 MB / 48 MP / 单边 16000，压缩为最长边 1600、每张不超过 1 MB 的 JPEG |
| 富文本 | 已实现 Markdown、扩展语法、HTML 清理、代码复制、公式和 Mermaid；实际 iOS 打包资源通过 11 项解析及 7 组浏览器交互检查 |
| Agent 回复状态 | 已实现等待 / 进行 / 失败状态、回复重试、本机忽略与持久化；不与用户消息重发混用 |
| 上下文 | 已实现摘要查看 / 刷新、保留 1–20 轮、手动压缩；补齐操作完成反馈 |
| 清理与备份 | 已实现修订校验、清理前预览 / 备份 / 确认、ZIP 导出与校验、恢复到独立对话；导入限制 32 MB / 10000 条，取消选择不报错 |
| Token 用量 | 已实现输入 / 输出 / 总量、调用统计、模型费用估算；失败保留上次结果，切换连接清空 |
| 反馈与数据隔离 | 补齐复制、同步、建群、新对话、邀请、备份等提示；图片与头像迟到响应不再跨账号返回，图片以缩略图加载并按需释放 |

iOS 的相册、文件、键盘与凭据界面采用系统原生实现，系统弹窗外观随平台而异。Mac 专属 LeonBook CLI 归档不属于 Android 功能对齐范围。服务端兼容检查使用本地测试，未替代生产环境跨端联调，本次工作没有部署服务端。

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

本机已生成 `dist/Leon-iOS-personal-0.12.3.ipa`（约 3 MB），并更新 `dist/Leon-iOS-personal.ipa`；0.12.2 的版本化 IPA 继续保留。新包通过 `codesign --verify --deep --strict` 及 ZIP 内容完整性检查。描述文件已确认包含当前 iPhone，个人签名有效期至 **2026-11-27 21:42（北京时间）**。此包仅供已登记设备使用，不能在手机上点开当作 APK 安装；有效期届满需要重新签名安装。个人签名构建使用 Xcode 中选定的 Personal Team，普通构建脚本仍输出未签名版本。

`Resources/Markdown` 是被忽略的生成目录；正文补丁只作用于该 iOS 副本，不修改现有两端使用的资源。直接从干净检出打开工程前须执行资源准备步骤。

## 检查与待验收项

无需完整 Xcode 的核心检查：

```bash
bash scripts/test-ios-core.sh
node ios/Tools/test-renderer.mjs
node ios/Tools/test-browser.mjs
```

28 项核心 / HTTP 检查覆盖真实磁盘隔离及损坏队列、先保存再发送、图片断网重试、历史修订与 LRU 淘汰、跨会话图片批次、清空 / 退出后的延迟图片、旧群聊权限、草稿、失败提示、用量、登录失效、禁止重定向，以及拦截 URLSession 的 HTTP 协议用例。ZIP 检查覆盖 stored / deflate、CRC、损坏与超限文件。HTTP 测试使用进程内响应，不访问生产服务或调用模型。正文的 11 项检查覆盖中文标点粗体、标题、扩展语法、自动链接、转义与代码。

浏览器检查复用已有共享资源的 Playwright 依赖，在无界面 Chrome 中加载实际 iOS 资源并模拟 WK 消息桥，检查任务列表 / 脚注 / 站内跳转、HTML 折叠 / 表格、代码复制、公式、Mermaid、外链图片隔离及移动宽度 / 深色。7 组均通过；这不是 iPhone 上的 WKWebView 运行测试。

原生输入框布局回归检查（需要完整 Xcode 和可用的 Mac Catalyst 运行环境）：

```bash
bash scripts/test-ios-composer-layout.sh
```

该检查仅启动独立的本地测试宿主，加载真实 `NativeChatView` / `NativeComposer`，不修改现有 Mac 应用，不登录真实账号或访问网络，不启动游戏或模拟器。在 320 / 393 / 430 点宽度下，逐字输入、粘贴中文、连续英文、长 URL、多行文本及清空恢复共 18 项场景检查编辑区边界、换行、四行上限与滚动。它验证原生 UIKit / SwiftUI 布局，但不替代手机键盘与中文输入法的实机验收。

核心脚本还检查 UI 源码语法和工程 plist；**语法解析不等于 iOS SDK 类型检查或运行测试**。iPhoneOS 整包另已通过 Xcode 编译。后续真机验收必须包含：Keychain 重开登录、中文输入与外接键盘、相册 / 文件 / 粘贴、文件导入导出、富文本高度和滚动、弱网重试、切会话时的迟到响应，以及 Android / iOS 跨端消息与清理同步。当前未启动游戏或模拟器；0.12.1 已在 iPhone 16 Pro 安装并启动，用户确认能打开，`devicectl` 再次启动成功；0.12.3 保留安装包，待用户准备好后更新。

0.12.3 产物的 `CFBundleSupportedPlatforms` 为 `iPhoneOS`，离线正文资源完整，个人签名及绑定手机的描述文件已验证。原有 Android、Mac 与共享正文的 177 个受保护文件曾在迁移清理阶段核对一致；本次功能对齐及输入修复没有修改这两端源码。

## 服务端兼容

客户端发送真实的 `platform: ios`。`ServerCompatibility/ios-platform.patch` 保留原迁移阶段必要的兼容改动：允许 iOS 发送消息、设备心跳和备份消息，并在在线设备列表显示 iOS。`IosClientCompatibilityTest.java` 是对应的服务端回归用例。

同级服务端项目中的这些兼容改动继续保留，`IosClientCompatibilityTest` 的 2 项检查通过（JDK 21、H2 内存数据库）。**本次工作没有部署服务端，未核验公网部署版本**。若目标服务器仍只允许 `macos` / `android`，需要先合入并部署平台兼容改动；不要把 iOS 伪装为 Android。群聊、UserName、上下文、独立对话及 ZIP 备份还需要现有对应版本接口和 32 MB 反向代理配置。

## Flutter 清理记录

已删除 `mobile/`、三个 mobile 构建 / 检查 / 准备脚本及 Flutter Android 调试包。已移除本次迁移安装的临时 Flutter SDK、Pub / Dart 缓存、Gradle 9.5.0 与 Flutter 插件专用缓存，并通过 SDK Manager 卸载专门新增的 NDK 28.2、CMake 3.22.1、Android 34 / 36 平台和 Build Tools 36。合计约 12 GB。

保留原生 Android 使用的 SDK 35、Build Tools 35、Gradle 8.11.1、JDK，以及 Mac / iOS 使用的 Swift 工具链和已有共享正文资源。共享缓存未作全盘清空，避免影响原有项目。

## 目录

- `Sources/LeonCore`：协议模型、URLSession、持久化、聊天状态、ZIP 预览、补全与用量估算。
- `Sources/LeonIOS`：SwiftUI 页面、UIKit 输入 / 相册、Security Keychain、WKWebView 正文。
- `Tests`：可用 Command Line Tools 编译执行的核心和协议测试。
- `Tools`：确定性 Xcode 工程生成、离线资源准备、图标转换与测试夹具。
