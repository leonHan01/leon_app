# Leon

简体中文 · [English](README.en.md)

Leon 是面向 macOS、Android 和 iOS 的原生消息应用。你可以在设备之间同步聊天，与 AI Agent 私聊，或在群聊中 @ 指定 Agent。会话和消息历史由独立的 `leon_lite_workflow` 服务端管理。

## 主要功能

- **聊天与同步**。支持设备群聊、自建群聊、命名的 Agent 会话、历史分页和待发消息重试。
- **整理对话**。可以搜索全部会话或当前会话、定位原消息、引用回复、收藏消息，以及从已发送的消息创建独立分支。
- **发送与阅读**。支持图片和 PDF、Word、Excel、文本、Markdown、CSV 附件。聊天正文可显示 Markdown、代码块、数学公式和 Mermaid 图表。
- **Agent 上下文与用量**。查看会话摘要，开启新话题，导出或恢复聊天备份，并查看 Token 用量及费用估算。
- **macOS 归档**。通过 `leonbook` CLI 将对话总结、完整 Markdown 原文和附件保存为 LeonBook 草稿。

文档分析、会话分支、结构化记忆和通知需要支持对应功能的服务端版本。联网搜索和图片生成还需要在 Agent 工作台启用，并选择兼容的模型。

## 安装与连接

1. 从下表选择平台并构建客户端，或使用已有的对应平台安装包。
2. 在设置中填写服务管理员提供的 HTTPS 地址和访问令牌。macOS 在「连接」中填写设备名称并选择「验证并连接」。Android 和 iOS 在「注册或登录」中填写 `UserName`。
3. 打开 Agents 列表开始私聊，或进入群聊发送消息。在群聊中输入 `@` 选择需要回复的 Agent。

模型和 Agent 在服务端的「Agent 工作台」（`/workspace/agents.html`）配置。

## 从源码构建

在仓库根目录执行对应命令，产物写入本地 `dist/`。

| 平台 | 最低系统 | 构建环境 | 命令 | 构建产物 |
| --- | --- | --- | --- | --- |
| macOS | macOS 13 | macOS Swift 工具链、Apple 签发的签名证书 | `bash scripts/build-macos.sh` | `dist/Leon.app`、`dist/Leon-macOS.zip` |
| Android | Android 8.0（API 26） | JDK 17+、Android SDK Platform 35、Build Tools 35 | `bash scripts/build-android.sh` | `dist/Leon-android-debug.apk` |
| iOS | iOS 16 | 完整的 Xcode、Node.js 22.12+（含 npm）、Python 3 | `bash scripts/build-ios.sh device` | `dist/Leon-iOS-device-unsigned.zip` |

- **macOS**。用 `LEON_CODESIGN_IDENTITY` 和 `LEON_CODESIGN_TEAM_ID` 指定自己的证书和团队。解压 ZIP 后将 `Leon.app` 移到「应用程序」。
- **Android**。通过 `ANDROID_HOME` 或 `android/local.properties` 指定 SDK。脚本同时运行单元测试和 lint。构建后可将调试 APK 安装到开发设备。
- **iOS**。`bash scripts/build-ios.sh simulator` 可构建模拟器版本。真机安装需要在 Xcode 中为 `ios/Leon.xcodeproj` 的 `Leon` scheme 配置签名。工程准备与签名步骤见 [iOS 开发说明](ios/README.md)。

## 开发检查

```bash
bash scripts/test-macos.sh
bash scripts/test-ios-core.sh
```

修改共享 Markdown 渲染器后，在 `shared/markdown` 中运行 `npm ci`、`npm run build` 和 `npm test`。渲染测试使用本机 Chrome，可用 `LEON_CHROME` 指定可执行文件。

## 仓库结构

| 目录 | 内容 |
| --- | --- |
| [`macos/`](macos/) | SwiftUI 客户端和 Swift Package |
| [`android/`](android/) | Java 原生客户端和 Gradle 工程 |
| [`ios/`](ios/) | SwiftUI / UIKit 客户端和 Xcode 工程 |
| [`shared/markdown/`](shared/markdown/) | Markdown、KaTeX、Mermaid 的源码和离线资源 |
| [`scripts/`](scripts/) | 构建、打包与检查脚本 |

## 相关文档

- [文档附件与消息通知](docs/documents-and-notifications.md)
- [Agent 联网搜索的配置与限制](docs/agent-web-search.md)
- [服务端兼容补丁](ios/ServerCompatibility/)
- [开发与发布记录](docs/project-history.md)
