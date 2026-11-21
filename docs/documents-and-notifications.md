# 文档附件与消息通知

本轮版本：Mac 0.14.0、Android 0.15.0、iOS 0.16.0。保留引用、收藏、聊天搜索、图片保存和会话分支。

## 文档附件

- 手机聊天「＋ → 文件」，Mac 输入区「添加文件」。支持 PDF、TXT、DOC、DOCX、XLS、XLSX、MD、Markdown、CSV。
- 一条消息最多 4 个文档，每个不超过 10 MB。可只发文件，也可输入具体分析问题；群聊沿用已有的 @ Agent 规则。
- 原文件在本地待发队列中独立保存，先保存再上传；重试保留文件与消息标识。切换会话保留草稿，清理聊天会移除相关待发文件。
- 服务端保存原文件，并提取正文、工作表名称、行号与表格内容送入模型上下文。不会计算公式、执行宏或获取外部链接。TXT、Markdown、CSV 支持 UTF-8、带 BOM 的 UTF-16 和 GB18030 中文编码。
- 文件卡片可打开原文件；Android 还可保存到文件。文档消息支持引用、收藏和从原消息创建会话分支。收藏保存独立原件，清理原会话后仍可读取。
- 含文档的聊天备份使用格式版本 2，仍受 32 MB 总大小限制；恢复时重新解析文件并重映射附件、引用标识。旧版纯文字 / 图片备份仍可读取。

解析范围：PDF 最多 300 页；扫描件没有可提取的文字时会提示先 OCR 或发送页面图片。加密、损坏或扩展名不符的文件会拒绝。每个文档最多提取 60,000 字符，模型输入另受上下文额度限制；多文档分享额度，截取时向模型明确标记，不能据此推断未读取部分。当前不提供 OCR、全文检索增强或附件内嵌图片分析。

服务端采用 [Apache PDFBox](https://pdfbox.apache.org/3.0/getting-started.html) 和 [Apache POI](https://poi.apache.org/download.cgi)。原文件读取、上传、引用均验证当前会话权限；文档收藏按账号独立验证。

## 消息通知

三端设置中有「新消息通知」与「通知显示消息预览」。初始关闭，开启时申请系统权限。默认通知只显示新消息提示，不展示正文。正在查看的会话不弹出提醒；点击通知先核验账号和原消息权限，再进入会话。首次开启以服务器当前进度为起点，不重放旧聊天记录。

Mac 在 App 进程运行期间接收系统通知；iOS 与 Android 在前台使用账号隔离的全局通知收件箱。手机切到后台后，真正的远程送达分别依赖 APNs 和 vivo 平台，不依赖持续后台轮询。

服务端保存设备与送达游标，重启后继续处理新消息；临时失败按退避重试，无效 token 停用。每次发送前再次检查会话权限、token 归属与登录会话有效性，退出账号或设备重新绑定会停止旧账号通知。消息不经过客户端提供的任意回调地址。

### vivo

已接入官方 SDK 4.1.0.0（510），包括授权后初始化、设备注册、当前账号 profileId 绑定、前台展示控制与通知点击。仅在设备同时支持账号校验和前台不展示能力时启用远程通道；不满足时保留应用运行期间的通知。SDK 来源与隐私说明见 `android/app/libs/VIVO-SDK-NOTICE.md`。

本机的服务端配置保存在项目外 `~/.config/leon/vivo-push.env`，权限 0600；客户端只读 `~/.config/leon/vivo-client.properties` 中的 AppID / AppKey，完全不读取 AppSecret。平台鉴权已验证成功；AppSecret 不写入源码、文档、日志或安装包。

启用 vivo 配置的客户端构建：

```bash
cd android
LEON_VIVO_CONFIG="$HOME/.config/leon/vivo-client.properties" \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew --no-daemon assembleDebug lintDebug
```

默认不读取私有配置，因此本地 JVM / Robolectric 回归不会初始化真实厂商 SDK。SDK 的 Android 字节码不直接适用于 JVM 的验证器；无配置的测试清单不注册厂商 receiver，启用配置的实际 APK 会包含 receiver。真实注册、系统权限和后台送达仍须在 vivo 手机上验收。

vivo 应用必须使用匹配的包名 `com.leon.app` 和安装包签名，并完成平台所需的应用审核；当前 Android 包沿用本机开发签名。服务端模式默认 `0`（正式即时消息），若应用尚在审核或需要测试白名单，使用 `LEON_PUSH_VIVO_MODE=1`。

平台说明：[SDK 集成](https://developers.vivo.com/doc/d/1e090cf8718245e4846e7dbc0135cd07)、[客户端 API](https://developers.vivo.com/doc/d/4e5dd6c6295d4e668e533084c5b8d381)、[服务端 API](https://developers.vivo.com/doc/d/b904b86d68254ab5a4e3b439e1ec997d)。

### iOS / APNs

当前仍使用个人免费签名，系统通知及 APNs 注册 / 服务端框架已完成，尚未启用 APNs 后台送达。启用前需要支持推送的开发者团队、应用描述文件与 APNs 密钥；参见 [Apple 能力支持](https://developer.apple.com/help/account/reference/supported-capabilities-ios)。

具备相应团队和描述文件后：

```bash
LEON_IOS_TEAM=你的团队ID LEON_IOS_APNS_ENVIRONMENT=development \
python3 ios/Tools/generate-project.py
```

生成器会启用 `aps-environment`，并保存 `development` 或 `production` 环境。未设置该变量时不启用 APNs entitlement，免费个人签名构建保持可用。服务端通过 HTTP/2、ES256 token 鉴权访问 APNs；`.p8` 只保留在服务端。

## 服务端配置与交付状态

新增接口均位于已有认证保护的 `/api/device-messages`：

- `POST /documents` 上传原件并解析；`GET /documents/{id}` 下载原件。
- `GET /favorites/{id}/documents/{documentId}` 读取私有收藏原件。
- `GET /notifications/status` 查看通道配置；`GET /notifications` 读取全局新消息收件箱。
- `POST /notifications/devices` 注册 / 更新设备；`POST /notifications/devices/{deviceId}/remove` 停用设备。

服务端环境变量包括 `LEON_PUSH_ENABLED`、`LEON_PUSH_VIVO_APP_ID`、`LEON_PUSH_VIVO_APP_KEY`、`LEON_PUSH_VIVO_APP_SECRET`、`LEON_PUSH_VIVO_MODE`；APNs 使用 `LEON_PUSH_APNS_KEY_FILE`、`LEON_PUSH_APNS_KEY_ID`、`LEON_PUSH_APNS_TEAM_ID`、`LEON_PUSH_APNS_TOPIC`。默认远程下发关闭，生产服务不会自动加载本机私有文件。

代码已同步到同级 `leon_lite_workflow`，并做本地构建与测试。兼容补丁为 `ios/ServerCompatibility/document-attachments.patch`、`ios/ServerCompatibility/message-notifications.patch`，按此前引用 / 收藏补丁、文档、通知的顺序使用；会话分支补丁由原分支功能单独提供。

本轮不部署或重启服务端、不安装手机客户端，也不启动 App、游戏或模拟器。新接口需升级服务端；平台端到端验收需使用新版客户端和实际设备。


## 后续安装交付

2026-11-21 交付记录：Android 0.15.0（build 30）已重新打包并验证签名与 vivo 配置；iOS 0.16.0（build 16）已覆盖安装到已连接的 iPhone 16 Pro，设备读回版本一致。手机当时锁屏，尚未完成启动核验。本次未部署或重启服务端。
