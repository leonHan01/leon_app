# Leon

[简体中文](README.md) · English

Leon is a native messaging app for macOS, Android, and iOS. Sync chats across devices, message AI Agents directly, or @mention an Agent in a group chat. The separate `leon_lite_workflow` backend manages conversations and message history.

## Features

- **Chat and sync.** Use the shared device chat, create groups and named Agent conversations, load older messages, and retry pending sends.
- **Organize conversations.** Search across chats or within one conversation, jump to the original message, reply with a quote, save favorites, and start a separate branch from a sent message.
- **Send and read attachments.** Attach images, PDFs, Word and Excel files, plain text, Markdown, and CSV files. Messages can render Markdown, code blocks, math, and Mermaid diagrams.
- **Manage Agent context and usage.** View conversation summaries, start a new topic, export or restore chat backups, and review token usage and estimated costs.
- **Archive on macOS.** Use the `leonbook` CLI to save a conversation summary, the complete Markdown transcript, and attachments as a LeonBook draft.

Document analysis, conversation branching, structured memory, and notifications require backend support. Web search and image generation also require a compatible model and the corresponding settings in the Agent Workbench.

## Install and connect

1. Build the client for your platform using the table below, or use an existing package for that platform.
2. In Settings, enter the HTTPS address and access token from your service administrator. On macOS, enter a device name in Connection (「连接」) and select Verify and Connect (「验证并连接」). On Android and iOS, enter your `UserName` under Register or Sign In (「注册或登录」).
3. Open the Agents list to start a direct chat, or open a group chat to send a message. Type `@` in a group chat to choose which Agent should respond.

Configure models and Agents in the backend’s Agent Workbench (「Agent 工作台」) at `/workspace/agents.html`.

## Build from source

Run the appropriate command from the repository root. Build outputs go to the local `dist/` directory.

| Platform | Minimum OS | Build requirements | Command | Output |
| --- | --- | --- | --- | --- |
| macOS | macOS 13 | macOS Swift toolchain, Apple-issued signing certificate | `bash scripts/build-macos.sh` | `dist/Leon.app`, `dist/Leon-macOS.zip` |
| Android | Android 8.0 (API 26) | JDK 17+, Android SDK Platform 35, Build Tools 35 | `bash scripts/build-android.sh` | `dist/Leon-android-debug.apk` |
| iOS | iOS 16 | Full Xcode installation, Node.js 22.12+ with npm, Python 3 | `bash scripts/build-ios.sh device` | `dist/Leon-iOS-device-unsigned.zip` |

- **macOS.** Set `LEON_CODESIGN_IDENTITY` and `LEON_CODESIGN_TEAM_ID` to use your own certificate and team. Unzip the archive and move `Leon.app` to Applications.
- **Android.** Set `ANDROID_HOME` or configure the SDK in `android/local.properties`. The script also runs unit tests and lint. After building, install the debug APK on a development device.
- **iOS.** Run `bash scripts/build-ios.sh simulator` for a simulator build. To install on a device, configure signing for the `Leon` scheme in `ios/Leon.xcodeproj` in Xcode. See the [iOS development guide](ios/README.md) for project setup and signing.

## Development checks

```bash
bash scripts/test-macos.sh
bash scripts/test-ios-core.sh
```

After changing the shared Markdown renderer, run `npm ci`, `npm run build`, and `npm test` in `shared/markdown`. The renderer tests use a local Chrome installation. Set `LEON_CHROME` to specify the executable.

## Repository layout

| Directory | Contents |
| --- | --- |
| [`macos/`](macos/) | SwiftUI client and Swift package |
| [`android/`](android/) | Native Java client and Gradle project |
| [`ios/`](ios/) | SwiftUI / UIKit client and Xcode project |
| [`shared/markdown/`](shared/markdown/) | Source and offline assets for Markdown, KaTeX, and Mermaid |
| [`scripts/`](scripts/) | Build, packaging, and verification scripts |

## Related documentation

- [Document attachments and message notifications (Chinese)](docs/documents-and-notifications.md)
- [Agent web search setup and limits (Chinese)](docs/agent-web-search.md)
- [Backend compatibility patches](ios/ServerCompatibility/)
- [Development and release history (Chinese)](docs/project-history.md)
