# Leon

macOS 0.14.0 / Android 0.15.0 / iOS 0.16.0 新增文档附件与消息通知：支持 PDF、TXT、Word、Excel、Markdown、CSV 发送给 AI 分析，接入 vivo 实际应用配置与 APNs 框架。详见 [功能、限制与配置说明](docs/documents-and-notifications.md)。服务端已本地更新，尚未部署。

## 对话分支（macOS 0.14.0 / Android 0.15.0 / iOS 0.16.0）

Mac 右键、Android / iOS 长按已发送成功的消息，选择「从这里创建分支」，填写名称后创建并进入独立会话。文字、富文本、图片和文档消息均提供入口；Android 图片长按先选择「消息操作」。创建窗口展示分支点说明，失败可用同一请求重试；旧服务端提示升级。分支可在对应 Agent 的历史会话或群聊列表继续打开。

服务端复制该会话从第一条到所选消息（含）的全部已保存历史，不限于本机已加载页面。文字、发送者、原时间、图片、文档、回复关联与引用快照一并保留；为消息和附件分配新标识，引用与回复关联重映射到分支内。创建过程原子提交、按账号与请求标识去重，不复制待发草稿、Agent 任务或触发模型调用。原会话的草稿按现有机制保留；两份历史和附件独立，清理其中一个会话不影响另一个。

分支保留原会话的 Agent；群聊分支默认仅创建者可见，不自动邀请原群其他用户，后续可使用既有邀请入口添加。只有有权读取源会话的账号能创建，分支点必须属于该会话。每个分支最多复制 10,000 条消息、128 MB 附件，超限不留下半成品。

分支上下文从复制的原文重新构建，不沿用可能包含分支点之后内容的摘要、事实或请求快照。当前话题边界若在所选位置之前，则映射到新消息；若当前话题在分支点之后才开启，分支从复制的历史开始重新组织上下文。后续压缩和检索仅在分支自身记录内进行。

新增 `POST /api/conversations/{id}/branches`，请求为 `{"messageId":123,"requestId":"UUID","name":"方案 B"}`，返回普通会话对象；服务端保存 `chat_conversation_branch` 来源与请求记录。沿用账号权限、Bearer / 管理 Cookie 写入来源校验和 `no-store`；仅为分支控制器加入现有聊天会话认证白名单。兼容补丁为 `ios/ServerCompatibility/conversation-branches.patch`，已同步到同级服务端工程。

验证：服务端 35 项分支 / 备份 / 搜索 / 收藏 / 文档 / 账号回归（含 8 项分支测试）、Android 61 项测试与 lint、iOS 53 项核心 / HTTP 场景、Mac 会话状态与 HTTP 协议检查通过；三端 Release / APK 构建通过。未启动 App、游戏或模拟器，未进行实机交互验收。**服务端已本地打包，尚未部署；实际使用需先升级服务端。**

最新安装包：`dist/Leon-macOS-0.14.0.zip`、`dist/Leon-android-debug-0.15.0.apk`、`dist/Leon-iOS-personal-0.16.0.ipa`；本次不自动安装。

## 上下文与结构化记忆（本地实现，待部署）

移除按 N 轮自动压缩与三端的轮数设置，改为按 Token 压力管理上下文。短聊天保留完整原文；常规模型接近输入预算 80%、Luna 接近 60% 时尝试压缩，压缩失败且原始完整请求仍放得下时回退原文继续回复，超过预算则明确提示并保留历史。


Luna 的输入预算进一步从 4,000 降至 3,000 个估算 Token，约 1,800 时尝试压缩。新摘要最多 500 Token，事实提示最多 500；历史检索最多带回 1 轮且整段参考不超过 350 Token，保留数据库中的原始聊天与事实。Sol、Terra 的独立预算见下文。旧失败请求的快照在重试时也会核对当前预算。此调整仍需部署服务端后生效，增量补丁为 `ios/ServerCompatibility/luna-context.patch`。


Sol 和 Terra 的应用输入预算统一设为 20,000 个估算 Token，约 16,000 时尝试压缩，压缩后优先保留约 10,000 Token 范围内的最新完整轮次。Luna 继续使用 3,000。此调整需部署服务端后生效，增量补丁为 `ios/ServerCompatibility/sol-terra-context.patch`。

压缩时分别生成阶段摘要和有用户原文依据的结构化事实，记录发言者、来源消息与更正 / 撤销关系。普通回复会按问题检索当前会话、当前话题中的相关旧原文，最多带回 3 轮；不跨会话或话题检索。客户端上下文页展示事实及来源、检索轮数与回退状态。事实随聊天备份保存，恢复时重映射来源；旧客户端、旧备份保持兼容。旧版服务端显示升级提示。

服务端改动位于同级 `leon_lite_workflow`，兼容补丁为 `ios/ServerCompatibility/context-memory.patch`。`recentRounds` 仅为旧接口和备份保留，不再控制原文窗口或压缩时机。事实提取与现有压缩同一次模型调用完成，本轮未增加每次回复后的后台记忆任务。此改动不自动部署服务端或安装客户端。

验证入口：`bash scripts/test-context-memory-models.sh` 检查 Mac / iOS 新旧响应兼容；服务端 `ContextMemoryIntegrationTest` 覆盖按 Token 压缩、完整原文回退、事实来源和更正、同话题检索、重试快照及备份恢复。


macOS 0.12.0 / Android 0.13.0 / iOS 0.14.0 新增引用回复与账号私有收藏，支持文字和图片、原消息定位及收藏搜索。服务端已本地更新和打包，尚未部署。

Android 0.12.4 / iOS 0.13.4 的聊天快捷按钮使用纯黑常规字重文字和细线图标，不加粗；保持单行横向排列和「会话列表」入口。

macOS 0.11.0 / Android 0.12.0 / iOS 0.13.0 新增全局与会话内聊天记录搜索，支持关键字高亮、完整历史分页和原消息定位；服务端已完成本地更新，尚未部署。

新增独立的 [iOS 原生工程与 Android 功能对齐记录](ios/README.md)，使用 SwiftUI / UIKit，最低 iOS 16。Android 与 Mac 原生版本保留；Flutter 代码及本次迁移安装的专用环境已移除。Android 0.11.2 / iOS 0.12.5 在自建群聊聊天页提供「添加用户 / 添加 Agent」入口，并保留 Agent 详情跳转和 iOS 长文本换行修复。两端新版安装包已生成，iOS 已签名；新增群聊 Agent 接口已完成本地服务端测试与打包，尚未部署。2026-11-21 已按用户要求将 iOS 升级安装到 iPhone 16 Pro，设备端读回版本为 0.13.4（build 11），并成功启动；未进行完整功能实机验收。

macOS 与 Android 原生消息应用。0.5.0 增加在线设备心跳，支持输入 @快捷选择、Agent 头像配置与上传、设备文字互发、Agent 私聊，以及在群聊中 @指定 Agent。两端填写相同的服务地址和现有访问令牌，同步同一所有者下的会话。

应用提供文字发送、消息历史、增量同步、更早历史分页、网络状态、失败手动重试、待发消息恢复、消息复制及设备名称。服务器确认接收后显示正式消息，不把服务器接收称为对方已读。每条最多 8,000 个 UTF-16 单元（部分 emoji 占两个）。

Mac 和 Android 聊天气泡支持 Markdown：标题、粗体、斜体、删除线、行内代码、代码块、有序 / 无序及嵌套列表、引用、分隔线、链接和表格。普通换行保留，自己发送、Agent 回复、历史及待发消息使用相同渲染。代码块和扩展内容中的宽表格可横向滚动，代码块可单独复制；Mac 右键「复制原文」、Android 长按气泡保留整条 Markdown。仅 HTTP / HTTPS / mailto 链接可打开。消息发送、保存和同步均保留原始正文，输入框仍编辑原文。

两端还支持任务列表 `- [ ]` / `- [x]`、脚注 `[^1]` 与返回跳转、定义列表、`==高亮==`、`H~2~O` 下标、`x^2^` 上标、`:smile:` 等 emoji 简码，以及 NOTE / TIP / IMPORTANT / WARNING / CAUTION 提示块。复选框可在当前显示中勾选，聊天原文和服务器记录不因此更改。`[[标题]]`、`[[#标题|显示文字]]` 跳转到当前消息中的同名标题，也可用 `[[https://example.com|显示文字]]` 打开网站；应用没有跨文档笔记库，不创建其他文档或反向引用索引。

Markdown 图片与 HTML 图片可直接显示 HTTPS 地址或 PNG / JPEG / GIF / WebP 的 base64 data 图片，等比适配气泡，加载失败显示说明文字。外链图片不携带消息服务的访问令牌或来源页。支持常用 HTML 排版、`<details><summary>…</summary>…</details>` 折叠内容，以及 HTML 表格的 `colspan` / `rowspan` 合并单元格；内容经过清理，不执行消息中的脚本或嵌入网页。折叠内容内写 Markdown 时，在 HTML 标签与 Markdown 段落间保留空行。

标注语言的围栏代码块使用 Highlight.js 着色，未知语言保留代码原文，复制按钮保留空白与换行。`mermaid` 围栏支持流程图、时序图、状态图、类图等 Mermaid 图表；语法有误时保留源码。扩展消息共用 `shared/markdown/runtime` 中的本地排版组件，包括 KaTeX 公式和字体、代码高亮与按需加载的 Mermaid；普通消息继续使用原生渲染。富内容容器按可见范围加载和释放，折叠、图片及图表的高度变化会同步到气泡。

更新排版组件：在 `shared/markdown` 执行 `npm ci && npm run build`，将更新的 `runtime` 一并提交。两端原生构建直接打包该目录，不依赖在线 CDN 或构建时下载 npm 包。共用渲染与交互检查为 `cd shared/markdown && npm test`（使用本机 Chrome，可通过 `LEON_CHROME` 指定路径）；Mac 原生 WKWebView 离屏检查包含在 `scripts/test-macos.sh`，Android 的资源、路由和桥接检查包含在 `scripts/build-android.sh`。

Mac 和 Android 聊天气泡还支持本地 LaTeX 数学公式：`\(…\)`、`$…$` 为行内公式，`\[…\]`、`$$…$$` 为块级公式，块级分隔符可与公式同一行或独占一行。支持分数、根号、上下标、求和与矩阵等，过宽公式等比缩放。公式可与列表、引用、表格和粗体混排；行内代码、代码块中的公式写法保持原文，常见美元金额不转换。未闭合的块级公式和无法渲染的 LaTeX 保留可读文本。Mac 使用原生 SwiftMath 排版，字体随安装包提供，适配浅色 / 深色及自己发送的气泡；两端渲染都不依赖网络，复制原文、发送与同步仍保留原始正文。

Android 兼容 `**一句话总结：**Transformer`、`这是**“注意力”**机制` 等粗体边界紧邻中文标点的写法。兼容层仅参与显示解析，保留原始消息、代码、转义、实体及链接目标；不会为正文插入空格。回归测试覆盖接收与发送气泡、中文引号、未闭合标记、行内 / 块级代码和引用链接。

## 引用回复与收藏（macOS 0.12.0 / Android 0.13.0 / iOS 0.14.0）

三端参考微信的操作路径：Mac 右键、Android / iOS 长按已发送成功的消息，选择「引用」或「收藏」。普通文字、富文本和图片消息均支持，原有复制、代码复制、图片保存和大图预览保留。

引用后，输入框上方显示发送者和原文片段，图片以「[图片]」标识，点击 × 只取消引用，保留已输入内容。引用草稿随会话分别保存；发送失败后与同一待发消息标识一起恢复和重试。正式消息显示引用卡片，可点击定位原消息及前后文。清理原会话后引用定位会提示原消息不可用。引用仅限当前有权访问的会话，服务器生成原文快照，不接受客户端伪造的引用正文；沿用独立的 `quoteMessageId` / `quote` 字段，不改变原有 Agent `replyTo` 关联或群聊 @ 规则。模型上下文会携带所引用的文字和图片，供 Agent 理解当前提问。

Mac 侧栏、手机「设置 → 收藏」及聊天更多菜单提供收藏入口。收藏列表展示发送者、原消息时间、正文 / 图片和来源会话，支持搜索、更多分页、查看详情、定位原消息与确认取消收藏。收藏按账号存储在服务器，三端可读取；收藏本身不调用模型。重复收藏同一条消息不会产生重复记录。文字和图片附件保存独立快照，清理原聊天后仍可查看收藏；原消息定位则要求原记录仍存在。取消收藏只删除该账号的收藏及其图片副本，不影响聊天原文。

新增 `GET /api/device-messages/features`、`GET /api/device-messages/favorites`、`POST /api/device-messages/{messageId}/favorite`、`POST /api/device-messages/favorites/{id}/remove`、`GET /api/device-messages/favorites/{id}/images/{imageId}`。查询和图片读取均校验账号，沿用 Bearer / Cookie 和 `no-store`；不能读取或删除其他账号的收藏。引用发送前检查服务端能力，旧服务端会提示升级并保留待发内容，不会默默降级为普通文字。服务端新增引用快照列、收藏表和收藏图片表，保留旧消息、原图、会话和上下文；备份导入导出保留并重映射引用关系。兼容补丁为 `ios/ServerCompatibility/quote-favorites.patch`。

验证：服务端 64 项相关集成回归、iOS 41 项核心 / HTTP 场景、Mac 独立 HTTP / 状态检查通过；Android 56 项测试、lint、APK 构建通过。Mac / iOS Release 构建、Android 调试安装包构建和 Mac / iOS 签名校验通过，已检查 Android 引用预览的离屏截图。未启动 App、游戏或模拟器，未进行新功能实机交互验收。服务端仅本地构建，**尚未部署，使用引用和收藏需先升级服务端**。

最新安装包：`dist/Leon-macOS-0.12.0.zip`、`dist/Leon-android-debug-0.13.0.apk`、`dist/Leon-iOS-personal-0.14.0.ipa`；按约定仅保留每个平台最新版，不自动安装。

## 手机聊天快捷面板（Android 0.12.4 / iOS 0.13.4）

Android、iOS 同步采用纯黑图标、黑色常规字重文字、1.7 单位细线和白色圆角方块；尺寸、边框与留白一致。快捷按钮不再使用灰色文字或灰色图标。相册、压缩上下文、查看上下文、新建对话、会话列表均在同一行；群聊额外提供「@ Agent」。按钮宽度随可用空间分配，窄屏保持最小点击宽度并允许左右滑动，不折成第二行。移除面板中的「加载备份」「清理记录」按钮，既有服务端协议与数据不受影响。

点击「会话列表」进入当前 Agent 详情页查看历史独立对话；群聊先选择当前会话的 Agent。查看详情不会新建会话或发送消息，返回保留原会话、文字 / 图片草稿，并收起快捷面板。原有聊天菜单「查看 Agent 信息」共用相同跳转。

Android 49 项单元 / 页面测试、lint、APK 构建通过，包含小屏布局、两个旧按钮移除、私聊 / 群聊跳转及草稿保留；已检查原生界面离屏预览。iOS 36 项核心检查和 iPhoneOS Release 编译 / 个人签名通过。安装包为 `dist/Leon-android-debug-0.12.4.apk`、`dist/Leon-iOS-personal-0.13.4.ipa`。本次仅更新两个手机客户端，不改 Mac 或服务端，不安装或启动 App、游戏、模拟器。

## 聊天记录搜索（macOS 0.11.0 / Android 0.12.0 / iOS 0.13.0）

三端新增参考微信查找路径的聊天记录搜索。Mac 侧栏、Android / iOS 的 Agents 和群聊列表提供全局搜索入口；Mac 聊天标题栏的放大镜、手机聊天「… → 查找聊天记录」只查当前会话。Mac 使用 ⌘F 查当前会话、⇧⌘F 查全部会话。

输入关键字后稍候 350 毫秒自动搜索，也可直接按搜索 / 回车。结果按最新消息优先显示会话、发送者、时间和命中片段，关键字以绿色突出；支持清除、取消、无结果提示、失败重试与加载更多。搜索覆盖服务器保存的完整文字历史，不限于本机缓存或最近 100 条；按连续字符串匹配，忽略英文字母大小写，`%` / `_` 等字符按原文处理，每次最多 50 条，关键字最多 100 个 UTF-16 单元。图片 OCR、附件内容与未发送草稿不参与搜索，不调用模型。

点结果进入原消息的只读历史定位页，命中消息高亮，可继续查看更早 / 更新消息，Markdown、公式、图表和图片沿用已有渲染。返回保留搜索词、结果和列表位置；「进入会话」返回该会话的正常聊天。搜索使用独立游标，不改变实时聊天缓存、上下文、待发队列或草稿。连续输入、清空和切换连接时丢弃迟到结果；账号失效后手机端退出并关闭搜索。原消息已删除、会话无权访问或历史修订变化时显示错误，避免混合清理前后的历史。

新增只读接口 `GET /api/device-messages/search?q=...&conversationId=...&before=...&limit=50`；省略 `conversationId` 为当前账号有权访问的全部会话。返回 `results`（每项含 `message` / `conversationName`）、`hasMore`、`nextBefore`。原消息定位为 `GET /api/device-messages/context?conversationId=...&messageId=...&direction=around|before|after&limit=20`，返回消息、双向分页状态和 `historyRevision`。沿用现有 Bearer / Cookie 认证、所有者 / 群成员权限及 `Cache-Control: no-store`；不新增数据库表或修改历史。兼容补丁保存在 `ios/ServerCompatibility/chat-search.patch`，已同步到同级服务端源码。

本地验证：服务端 21 项相关集成测试通过（含新增的 5 项搜索测试）；iOS 36 项核心 / HTTP 场景通过，iPhoneOS Release 构建及个人签名通过；Mac Release 构建、签名和独立搜索协议 / 状态检查通过；Android 48 项测试、lint 和 APK 构建通过。未启动 App、游戏或模拟器，未进行实机交互验收。

安装包：`dist/Leon-macOS-0.11.0.zip`、`dist/Leon-android-debug-0.12.0.apk`、`dist/Leon-iOS-personal-0.13.0.ipa`。**服务端仅完成本地测试和打包，尚未部署；实际使用搜索需先升级服务端。** 本次不自动安装客户端。

## 群聊添加用户与 Agent（Android 0.11.2 / iOS 0.12.5）

自建群聊的群主可在聊天页「… → 添加用户 / 添加 Agent」直接邀请；「群成员」中也保留入口，并同时展示用户和 Agent。添加用户使用已注册的 UserName，支持逗号分隔，每批最多 32 位；添加 Agent 支持多选，仅列出启用且尚未入群的 Agent，群内 Agent 总数最多 32。成功后可在原群聊继续 @ 新 Agent，原成员、草稿及聊天记录保留。

沿用群主管理权限，普通成员可查看群成员。默认「设备群聊」是个人收件箱，继续保持账号隔离，不开放邀请；多人交流使用自建群聊。

新增 `POST /api/conversations/{id}/agents`，请求 `{"agentIds":["UUID"]}`，返回更新后的会话。沿用聊天会话认证和群主权限；原子追加、去重、幂等，拒绝无效 / 停用 Agent、私聊 / 默认设备群聊及超过 32 个 Agent 的操作，不修改会话所有者、历史或原有成员。不需要数据库迁移。现有添加用户接口仍为 `POST /api/conversations/{id}/members`。

服务端代码已同步到同级 `leon_lite_workflow` 并完成本地测试 / 打包，兼容补丁保留在 `ios/ServerCompatibility/group-agents.patch`。本次未部署或重启线上服务；旧服务端需升级后才能使用添加 Agent。两端安装包为 `dist/Leon-android-debug-0.11.2.apk` / `dist/Leon-iOS-personal-0.12.5.ipa`，尚未安装手机。

## 聊天菜单 Agent 信息（Android 0.11.1 / iOS 0.12.4）

聊天右上角「… → 查看 Agent 信息」进入 Agent 详情：私聊直接查看当前 Agent，群聊先从当前会话可用的 Agent 中选择。页面展示介绍、服务商 / 模型和仅属于该 Agent 的历史独立对话，可以点击历史继续聊天。返回保留原会话及草稿；查看详情本身不会创建私聊或发送消息。原有会话信息、群成员、Token 用量等菜单继续保留。

Android 42 项单元 / 页面测试、lint 与 APK 构建通过；iOS Release 编译、个人签名及 IPA 完整性检查通过。安装包为 `dist/Leon-android-debug-0.11.1.apk` / `dist/Leon-iOS-personal-0.12.4.ipa`，本次未安装手机。

## Android 手机导航（0.8.0）

底部「Agents / 群聊 / 设置」分开显示。Agents 列表展示头像、名称与标识，点整行进入独立聊天；群聊页只显示群聊，右上角「＋」新建群。返回键先收起附件面板，再返回原列表。连接地址、设备名称、连接状态和同步入口位于设置页。

聊天页使用紧凑标题栏、灰色背景、左右头像和白色 / 浅绿色气泡。输入有内容才显示发送按钮；相册和群聊提及入口收进「＋」，更多菜单提供会话信息与同步。保留 Markdown、图片选择 / 粘贴 / 预览、@补全、历史分页和失败重试。Enter 发送，Shift+Enter 换行，组词和 @候选仍优先处理。

Android 的 Agent 回复原文超过 500 个 Unicode 字符时，头像与名字显示在正文上方，正文铺满聊天区域的可用宽度，利用原头像列的左侧空白。恰好 500 字及更短的回复保持原有气泡布局。

已有私聊立即打开；首次私聊在后台创建并显示加载状态，发送前等待创建成功。文字、图片草稿和最多 8 个会话的最近 300 条历史保存在内存中；目录与心跳更新独立执行，避免阻塞页面切换。

## Token 费用估算（0.10.1）

Mac 与 Android 的 Token 用量页增加按服务商 / 模型的美元估算区间与已匹配模型合计。价格依据 2026-11-19 查询的 [OpenAI 官网](https://developers.openai.com/api/docs/pricing)和 [DeepSeek 官网](https://api-docs.deepseek.com/quick_start/pricing/)，按每百万文本 Token 计价；不认识的模型不参与合计并显示「暂无可匹配价格」，不会猜测别名或把未知费用当零。价格表需随官网调整更新。

现有服务端只存各模型输入 / 输出累计量，不记录缓存细分或每次调用时间，因此以全部命中缓存及全部未命中分别计算低 / 高估算；DeepSeek 同时取非高峰和高峰价格。累计数据不区分历史价格、未报告用量、折扣和其他费用，金额仅为按当前短上下文标准文本价格的参考范围，不能视为账单或真实费用上下界。

## Token 用量（0.9.0）

Mac 侧栏点击「Token 用量」，Android 在「设置 → Token 用量」或聊天页「更多 → Token 用量」查看。打开时读取最新数据，也可手动刷新；显示累计输入、输出、总 Token、已报告 / 未报告用量的调用次数，以及按服务商与模型划分的明细。读取失败保留上次结果和读取时间；切换连接时清空旧连接统计。

统计覆盖当前服务的所有会话、工作流、上下文压缩和归档总结，来源为模型实际返回的用量，从服务端启用记录时开始累计。多个配置或 Agent 共用同一服务商与模型只统计一次，已停用或不再配置的历史模型仍可查看。未返回有效用量的调用只增加「未报告」次数，不将其估算为零消耗；缓存与推理 Token 已包含在返回的总量中。此处为全局累计，不是当前会话的单独用量，也不是账单金额。

需要升级服务端。新增 `GET /api/agents/usage`，沿用现有 Bearer / Cookie 认证，返回 `Cache-Control: no-store` 和数组，每项包含 `provider`、`model`、`inputTokens`、`outputTokens`、`totalTokens`、`reportedCalls`、`unreportedCalls`、`firstRecordedAt`、`lastRecordedAt`；不返回模型凭据或管理配置。沿用现有用量表与代理路径，无数据库迁移。旧服务端返回 404 时客户端提示升级。本次本地构建不自动部署正式服务。

## 图片消息与 AI 看图

### 保存聊天图片（macOS 0.11.2 / Android 0.12.6 / iOS 0.13.6）

打开图片后，三端预览区右下角均提供常驻的圆形下载图标，点一下直接保存；iOS 保存时显示进度并禁止重复点击。Android / iOS 仍可在聊天缩略图和大图预览中长按选择「保存图片」，Mac 保留右键「保存图片…」。搜索记录中的图片复用同一入口。

iOS 仅在点击保存时请求向系统相册添加照片的权限，拒绝后显示前往系统设置的入口。Android 10 及以上将图片保存到系统相册的 `Pictures/Leon`，不申请读取相册或全部存储权限；Android 8 / 9 使用系统文件保存窗口。保存的是服务器消息附件或本地待发附件的完整 JPEG 数据，保留现有附件尺寸，不截取屏幕或保存缩略图。保存操作不调用模型。

保存成功后才提示成功；Android 写入或发布失败会清理未完成的相册条目，重复点击保存时避免同时写入同一张图。保存功能已通过 iPhoneOS Release 个人签名构建、36 项 iOS 核心检查、Android 图片保存写入检查和完整测试 / lint，以及 Mac Release 编译与签名；下载图标更新重新完成三端构建。安装包见 `dist/Leon-iOS-personal-0.13.6.ipa`、`dist/Leon-android-debug-0.12.6.apk`、`dist/Leon-macOS-0.11.2.zip`；本次不自动安装或启动客户端，实际系统相册授权和保存仍需手机验收，无需服务端改动。

### 同一 Agent 聊天与绘图（2026-11-21，本地实现，尚未部署）

OpenAI Agent 配置新增「允许此 Agent 绘图」和独立的「绘图模型」字段，默认关闭以保留现有行为。开启后，聊天仍使用原对话模型，通过 Responses API 的 `image_generation` 工具按用户请求生成或修改图片；无需另外创建绘图 Agent。对话模型必须支持图片生成工具，通常为 GPT-5 及更新模型，具体以 OpenAI 模型权限为准。默认绘图模型为 `gpt-image-2.5-flare`，可在 Agent 管理页修改，复用该 Agent 的 OpenAI 凭据。

生成图作为有会话权限的消息附件保存，Mac / Android / iOS 复用现有缩略图、大图和历史同步；继续发送「把刚才那张图的月亮改大」时，会把最近上下文中的图片作为参考。摘要压缩、会话标题和其他后台文字调用不启用绘图工具。每次请求最多调用一次工具；普通聊天由模型直接回复文字。

本版沿用现有图片规则：生成图压缩为最长边 1600 像素、每张不超过 1 MB 的 JPEG，不保留透明背景或高清原文件。图片和回复原子保存，失败不留下半条消息；不自动重复调用付费接口，失败后可手动重试。绘图会产生额外 OpenAI API 费用；没有返回图片工具用量时标记为未报告，不推算为零。

使用前需部署同级服务端、更新 Mac AI 执行器，并运行新版 `scripts/install_ai_executor_proxy.py` 升级受限执行器回传路径的大小上限；客户端展示协议保持兼容。兼容补丁位于 `ios/ServerCompatibility/image-generation.patch`。本次不自动部署、重启线上服务或替换正在运行的执行器。

### 图片上传与看图

Mac 执行器安装副本可用 `python3 scripts/check-mac-ai-executor.py` 检查。该命令直接加载本机已安装的 `worker.py`，用模拟任务核验文字和 Responses 绘图协议，不读取真实凭据、不访问网络。2026-11-21 排查「OpenAI 返回无效响应」时确认：仓库执行器已支持绘图，但运行中的安装副本仍为旧版，在请求发给 OpenAI 之前就把 Responses 的 `input` 格式判为无效。已备份并更新本机副本、重启本地执行器，原失败用例及安装副本自检通过；服务器未部署或重启。

Mac 点击输入区「选择图片」，或直接在输入框按 ⌘V 粘贴截图 / 图片，也支持粘贴 Finder 中复制的图片文件。Android 点击聊天输入栏「＋ → 相册」，或使用输入框的粘贴菜单 / 支持图片的键盘输入。每条最多 4 张，可发送纯图片或图文；发送前显示可移除的预览。切换会话时分别保留图片草稿，切换服务器连接时清空当前图片草稿。客户端会校正照片方向、将透明背景合成白色，等比压缩为最长边 1600 像素、每张不超过 1 MB 的 JPEG；GIF 取第一帧。Mac 原文件 / 剪贴板最多 64 MB，Android 最多 20 MB，两端均限制原始像素总量。

历史记录和待发消息显示图片缩略图，点击查看大图；加载失败可点击重新加载。发送前先将待发图片写入按服务器与令牌隔离的本地私有目录，再上传并发送消息，网络失败后手动重试复用相同图片与消息标识。上传不会由仅选择 / 粘贴触发。整条消息被服务器确认后清除本地待发图片；正式图片持久化在服务端 H2 数据库中，随数据库备份，重开 App 仍可加载。

AI 看图需要支持图片输入的 OpenAI 模型。DeepSeek Agent 的图片请求会明确提示不支持，不把图片伪装成文字发送。服务端将附件转换为 Chat Completions 的 `text` / `image_url` 内容块，以 Base64 数据传给模型，不提供公开图片链接。历史上下文最多重新附带最近 8 张图片，较早图片仍保留在聊天记录；摘要压缩时也保留附件引用供视觉模型读取。Markdown 外链图片按上述扩展渲染规则展示，但仅用于客户端显示，不会自动转换成发送给模型的图片附件。

接口：`POST /api/device-messages/images?id=<UUID>&conversationId=<会话>` 上传原始图片字节（最大 5 MB，实际解码及尺寸检查后重新编码）；`GET /api/device-messages/images/{id}` 返回 JPEG。两者沿用现有 Bearer / Cookie 认证和 Cookie 写入来源校验。发送消息增加可选 `imageIds` 数组，历史消息增加 `images` 元数据数组；附件只能绑定上传时的会话，老版本纯文字请求保持兼容。

启用需要同时升级客户端、服务端，以及已安装的 Mac AI 执行器（`scripts/mac_ai_executor.py`）。执行器图像任务读取与服务端请求上限已扩至 16 MB，其他响应仍保留原大小限制。原有消息代理路径包含图片接口，单次上传保持在既有 6 MB 限额内。本次源码与安装包更新不自动部署正式服务或重启正在运行的执行器。

## 自动生成会话标题

服务端每 30 秒检查一次私聊：每新增 10 轮用户消息，使用该 Agent 的模型在后台更新简短标题，包括用户创建时指定名称的私聊；群聊不参与。默认名称的私聊仍会在已有文字消息且安静 2 分钟后首次生成标题，之后从该次生成的消息位置重新计算 10 轮。历史私聊也会逐步处理；每次最多处理 3 个，正在回复或压缩上下文的会话会等待。生成期间若有新消息、历史被清空或名称被修改，旧结果不会覆盖会话；失败后至少等待 1 小时再尝试。空会话和没有文字内容的会话不会调用模型。

生成标题会将最近最多 24 条文字消息（每条最多 240 字，合计最多约 6,000 字符）发送给该 Agent 配置的模型服务，并产生模型调用和 Token 用量。生成的标题保存于服务端，Mac、Android、iOS 通过现有目录同步显示。设置 `leon.chat.auto-title-enabled=false` 可关闭后台生成。启用需要升级服务端；本次不自动部署或重启服务。

## Agent 配置与聊天

Mac 侧栏和 Android 的 Agents 首页列表点击 Agent 后直接进入聊天。点击聊天中的 Agent 头像打开详情页，展示头像、名字、@标识、介绍、服务商与模型，以及仅属于该 Agent 的历史独立对话。点击历史条目继续聊天，或从详情页开始聊天 / 新建命名对话。详情页返回原聊天，保留当前会话与草稿；进入详情本身不会创建会话或调用模型。

介绍需要升级服务端后在「Agent 工作台 → Agent 介绍」中填写，最多 2,000 字符，保存于新增的 `chat_agent.description` 列，并随已认证的 `/api/agents` 摘要返回。介绍独立于角色提示词；旧客户端未提交该字段时保留原介绍，显式提交空字符串可清除。未填写或旧服务端不提供时显示「暂无介绍」。历史会话及现有 Agent 配置保留。本次本地更新不自动部署正式服务。

升级服务端后，从工作空间侧栏进入「Agent 工作台」，或访问 `/workspace/agents.html`。

1. 在「高级设置 → 模型配置」保存模型及对应凭据；新建 Agent 时填写显示名称、唯一的 `@标识`、角色提示词，并从已保存模型中选择。
2. Agent 保存模型引用，每次回复复用模型的最新配置与凭据。停用模型会阻止调用；旧 Agent 可以沿用原独立配置，也可以切换到统一模型。停用 Agent 保留历史消息。
3. Mac 左侧「AGENTS · 私聊」、Android 底部「Agents」列表或页面「聊天测试」均可打开私聊；私聊中的每条用户消息会触发该 Agent。
4. 在默认设备群聊或新建群聊里，通过 `@ Agent` 菜单 / 页面 Agent 按钮插入 `@标识`，例如 `@writer 帮我润色这段文字`。只有被 @ 的群成员回复，普通群消息不调用模型。每条最多 @4 个 Agent，自建群最多加入 32 个 Agent。
5. 回复显示「等待回复」「正在回复」或脱敏后的失败原因；失败可点击「重试回复」。消息发送重试和模型回复重试分别处理，不会重复保存用户消息。

模型请求完全由服务端执行。API Key 使用 AES-GCM 加密存储在 H2，并复用服务器已有 `LEON_WORKFLOW_CREDENTIAL_KEY`；未配置此加密主密钥时，页面会提示并禁止新建凭据。主密钥必须保留原值，不能为启用本功能重新生成或轮换已有工作流密钥。

工作流的「消息通知 → Agent 发送 App 消息」节点可选择 Agent 和私聊 / 群聊，正文支持上游模板；使用 Agent 名称和头像发送，不调用模型。单节点测试会发送真实消息。

控制台「Agent 工作台」显示在线设备数、名称、平台和最近活跃时间。0.5.0 客户端打开并连接后约每 10 秒上报心跳，45 秒未响应即离线；网页聊天不计入设备。退出 App 后消息仍在服务器保存，下次打开同步，当前不提供系统级离线推送。

每个私聊 / 群聊拥有独立历史和上下文。模型使用当前会话至本次提问的最近至多 30 条消息、约 32,000 字符，以及该 Agent 的提示词；这些内容会发送至所选模型服务商。回复仅使用官方 HTTPS 接口，不支持自定义转发地址，不提供工具执行能力。Agent 回复不会自动触发其他 Agent。

后台队列最多积压 256 个任务，至多同时处理 4 个会话，同一会话按顺序回复。未开始的任务可在重启后继续；正在执行的任务在重启后标记失败，避免自动重复付费调用。网络超时或服务重启后的手动重试可能产生新的模型费用。当前回复一次性完成后展示，未实现逐字流式输出。

## Agent 头像（0.3.0）

在「Agent 工作台」选择一个 Agent，可使用「选择头像」或「上传头像」。选定后点击「保存 Agent」生效。

- 内置你提供的 30 张 PNG：海绵宝宝、章鱼哥、Abigail / Alfred 等人物和 Avatar 系列。预设原文件不改动，透明背景和宽高比保留；旧 Agent 默认使用 Alfred。
- 自定义上传支持 PNG / JPG，文件最多 5 MB，宽高均不超过 4096 像素。服务端根据真实图片格式校验，等比缩放并居中生成 512×512 PNG，保留透明背景，不拉伸图片。
- 上传文件持久化到 H2 的 `chat_agent_avatar` 表，随既有数据库一起备份；重复图片去重，不依赖临时目录或原始下载文件。Agent 的 `avatar_id` 保存当前选择。
- 上传仅允许管理页 Cookie 和原有写入来源校验；头像读取也需要现有 Cookie 或 Bearer。Mac、Android 使用已认证请求加载头像，并在内存缓存，避免在 URL 中暴露令牌。
- 后台卡片、网页聊天、Mac Agent 列表 / 聊天气泡、Android Agent 选择列表 / 聊天身份栏显示头像。改变头像不会改动既有消息正文或模型凭据。

新增接口：`GET /api/agent-avatars` 返回预设和已上传的头像元数据；`GET /api/agent-avatars/{id}` 返回 PNG；`POST /api/agent-admin/avatars` 使用 multipart 字段 `file` 上传。Agent 创建 / 更新接收 `avatarId`，省略时新 Agent 使用默认值，旧 Agent 保留当前值。`/api/agents` 摘要包含 `avatarId`。

## 输入 @快捷选择（0.4.0）

Mac、Android 和网页群聊输入框中键入 `@` 或全角 `＠`，会自动显示当前群内已启用的 Agent，候选显示头像、名称与 `@标识`。继续输入中文名称或标识可筛选，每次最多显示 8 个匹配项。

可点击候选，或使用上下方向键选择、Enter / Tab 确认、Esc 关闭。补全只替换光标所在的 `@` 片段，保留前后正文，并把光标放在分隔空白之后，便于继续输入。输入邮箱、选择了一段文字或中文输入法仍在组词时，不会自动匹配；私聊不展示其他 Agent 的候选。Shift+Enter 保持换行。

Mac 输入框按 Enter 直接发送，Shift+Enter 换行，⌘Enter 仍可发送。@候选打开时，Enter 优先确认候选；中文输入法组词时，Enter 保持确认文字，不触发发送。

Mac 侧栏中，已有私聊统一显示在对应的 Agent 入口，不再同时出现在上方会话列表；停用 Agent 的历史和找不到对应 Agent 的旧会话仍可访问。点击 Agent 后，聊天旁会显示该 Agent 的历史对话列表，可切换对话或新建命名对话。切换已有 Agent 直接使用已知会话，不重复创建私聊或等待目录刷新。首次打开私聊也会立即选中 Agent 并显示加载提示，在后台创建会话；重复点击合并为同一个请求，创建失败可点击重试，尚未创建成功前禁止发送消息。已加载的历史在内存缓存中立即恢复，再后台同步增量；群聊与私聊分别保留文字 / 图片草稿。缓存最多保留 12 个会话、每个会话最近 300 条消息，较早消息仍可分页加载，切换服务器连接时清空历史缓存。Agent 目录与在线心跳独立在后台更新，慢请求不会阻塞当前会话，旧的私聊创建响应也不会覆盖之后的点击选择。

网页逻辑检查：`node --test src/test/js/agent-mentions.test.cjs`（在服务端项目执行）。Mac 检查包含 `scripts/test-macos.sh` 的光标 / Unicode / 文本保留用例；Android 构建脚本包含 `MentionCompletionTest`。

## 安装与连接

安装包按平台仅保留最新的一份版本化文件。2026-11-21 已清理旧版、重复副本及过时的 iOS 未签名 ZIP；下文旧版本章节中的安装包名称为历史记录，当前可用包以此处列出的最新版本为准。后续打包完成后继续按此规则整理，避免累积重复安装包。

- macOS：解压 `dist/Leon-macOS-0.14.0.zip`，把 `Leon.app` 拖入「应用程序」。当前构建为 Apple Silicon，最低 macOS 13。本机使用固定的 `Leon Local Signing` 证书签名，以便更新后保留钥匙串授权；首次从旧签名切换时可能需要重新授权。该本地签名未使用 Developer ID 公证，不适合分发给其他 Mac。构建可通过 `LEON_CODESIGN_IDENTITY` 指定其他持久签名身份。
- Android：将 `dist/Leon-android-debug-0.15.0.apk` 传入手机安装，最低 Android 8.0（API 26）。这是开发签名安装包，发布商店前需配置长期发布密钥。
- 打开「连接设置」，填写服务器地址（默认 `https://121.40.254.112`）、现有访问令牌和设备名称，点击「验证并连接」。两端令牌必须一致。
- 服务端需要先运行下文新增消息接口的版本。仅构建客户端不会升级公网服务。

应用处于前台时约每 2 秒拉取增量，失败后逐步延长至 30 秒；返回前台或点击「同步」会立即重连。退出或后台不接收系统推送，重新打开后读取服务器消息。首次显示最近 100 条，点击「加载更早的消息」继续读取。历史保存在服务器；待发消息保存在设备内，重新打开后可手动重试，重试不会重复落库。

macOS 将令牌存入系统钥匙串；Android 使用 Android Keystore 的 AES-GCM 加密后保存。令牌不会出现在 URL 或日志，HTTP 重定向不会携带认证继续跳转。Android 禁用备份和设备迁移，避免复制设备标识及不可解密的凭据。切换服务地址或令牌会切换待发队列，不把旧消息发送到新连接。

## 服务端

直接扩展现有 `/Users/leon/Documents/ChatGPT/leon_lite_workflow` Spring Boot 项目，没有引入第二个服务器。

新增文件：

- `src/main/java/com/leon/workflow/messaging/DeviceMessageController.java`
- `src/main/java/com/leon/workflow/messaging/DeviceMessageStore.java`
- `src/test/java/com/leon/workflow/messaging/DeviceMessageIntegrationTest.java`
- `src/test/java/com/leon/workflow/messaging/DeviceMessagePersistenceTest.java`

沿用现有 `/api/**` 的 Bearer 认证及 Cookie 写入来源限制。为 `device_message` 增加会话、角色和回复引用字段，旧消息自动归入 `shared` 设备群聊。新增 `chat_agent`、`chat_conversation` 和 `chat_agent_job` 表，启动时迁移并保留既有消息 ID 和内容。部署继续使用该项目的 `scripts/deploy.py`，不需要修改公网端口。已有反向代理需要把 `/api/device-messages`、`/api/agents`、`/api/conversations` 和 `/api/agent-admin` 交给 Spring 服务，保留 Authorization / Cookie；`/workspace/agents.*` 沿用现有 workspace 页面登录保护。配置接口还会强制校验管理页 Cookie；客户端 Bearer 令牌只能读取 Agent 摘要及聊天，不能读取角色提示词或管理模型凭据。

沿用现有单所有者认证域，没有新增用户注册或联系人系统。这里的 Agent 私聊在同一所有者的设备间同步；所有持有该服务有效令牌的客户端都能访问其会话。未提供多用户权限隔离或端到端加密。令牌轮换不会删除服务器历史。

### HTTP 协议

所有响应为直接 JSON，不使用现有其他接口的 `success/data` 包装。携带 `Authorization: Bearer <token>`，返回 `Cache-Control: no-store`。

`GET /api/device-messages?conversationId=shared&limit=100` 返回指定会话的最新一页，消息按 ID 升序排列。`hasMore` 表示还有更早历史。

`GET /api/device-messages?after=123&limit=100` 返回 ID 大于 123 的最早一页。`hasMore` 为真时继续使用该页最后 ID 拉取，直到追平。`after=0` 从最早历史开始。

`GET /api/device-messages?before=123&limit=100` 返回该 ID 之前的最近一页。`after` 与 `before` 互斥，limit 为 1–100。

```json
{"messages":[{"id":124,"clientMessageId":"UUID","deviceId":"UUID","sender":"我的 Mac","platform":"macos","text":"你好","createdAt":1700000000000}],"hasMore":false}
```

`POST /api/device-messages`：

```json
{"clientMessageId":"生成一次并在重试时复用的 UUID","deviceId":"设备的持久 UUID","sender":"我的 Mac","platform":"macos","text":"你好"}
```

返回保存后的单条消息。platform 只能为 `macos` 或 `android`。同一 `(deviceId, clientMessageId)` 相同内容重试返回同一 ID；不同内容返回 409。可附带 `conversationId`（缺省为 `shared`）和 `mentionAgentIds` UUID 数组。群聊也会识别正文中独立的 `@标识`。设备名称长度 1–60，文本非空且长度不超过 8,000。时间为服务器 Unix 毫秒，消息顺序以 ID 为准。输入无效返回 400，认证失败返回 401/403。

新增接口：

- `GET /api/agents`：不含提示词和 Key 的 Agent 摘要。
- `GET /api/conversations`：会话目录；`POST /api/conversations/direct/{agentId}` 创建或打开固定的 Agent 私聊。
- `POST /api/conversations/groups`：提交 `{ "name": "讨论组", "agentIds": ["UUID"] }` 创建群聊。
- `GET/POST /api/agent-admin`、`PUT /api/agent-admin/{id}`：管理页 Cookie 专用；更新提交读取到的 `version`，防止并发覆盖。
- `POST /api/device-messages/{messageId}/agents/{agentId}/retry`：仅将失败回复任务重新排队。

消息新增 `conversationId`、`role`、`agentId`、`replyTo` 字段；Agent 回复的 platform 为 `agent`。分页响应另含 `jobs` 数组（未完成 / 失败任务），客户端应持续轮询，即使本页没有新消息也要刷新任务状态。旧客户端省略会话字段时继续使用设备群聊。

客户端发送确认不会跳过接收游标，防止同时收发时漏掉其他设备插入的消息。服务端在单实例进程内串行化提交和分页读取，避免增量游标越过未提交 ID；不支持把同一数据库扩展成多个应用写入实例。

## 构建与验证

macOS 使用 SwiftUI + URLSession，Android 使用原生 Java 界面 + HttpURLConnection。没有 Flutter、Electron 或 WebView 运行时依赖。

```bash
bash scripts/build-macos.sh
bash scripts/build-android.sh
```

Mac 构建需要 macOS Command Line Tools（Swift 5.9+）。Android 需要 JDK 17+、SDK Platform 35、Build Tools 35；配置 `ANDROID_HOME` 或 `android/local.properties`。Gradle Wrapper 固定为 8.11.1，Android Gradle Plugin 固定为 8.7.2；首次构建需要下载依赖。

```bash
bash scripts/test-macos.sh
```

Android 构建脚本包含 `testDebugUnitTest` 和 `lintDebug`。服务端使用 Java 21：

```bash
cd /Users/leon/Documents/ChatGPT/leon_lite_workflow
JAVA_HOME=$(/usr/libexec/java_home -v 21) mvn -Dtest=AgentChatIntegrationTest,OfficialAgentModelClientTest,DeviceMessageIntegrationTest,DeviceMessagePersistenceTest,ApiAuthenticationIntegrationTest test
```

Mac 测试直接编译实际的模型和网络源文件，兼容只有 Command Line Tools 的环境。客户端真实 HTTP 测试只对隔离测试服务执行，指定 `LEONAPP_TEST_SERVER` 和 `LEONAPP_TEST_TOKEN` 后运行 `bash scripts/test-macos.sh`。该测试会实际创建 Mac / Android 平台的测试消息，不应指向正式数据库。

本机开发仅允许 HTTP 环回地址；Android 模拟器可使用 `http://10.0.2.2:8080`。手机真机连接电脑时应配置可验证证书的 HTTPS 地址，或使用 `adb reverse tcp:8080 tcp:8080` 后连接 `http://127.0.0.1:8080`。不提供跳过证书验证开关。

## 0.1.0 验证（2026-11-18）

- 服务端 10 项测试通过：API 收发、认证拦截、输入校验、历史分页、并发重试去重、H2 磁盘库关闭重开及现有认证回归。
- Mac Release 构建、本机签名校验通过；实际打开检查主窗口、连接设置及无效地址提示。
- Mac 实际 URLSession 对隔离 Spring Boot 服务的 HTTP 收发、中文换行、重试去重及第二设备回复测试通过；未连接正式数据库。
- Android APK 构建、2 项单元测试、Lint 通过（无问题）。本机没有连接 Android 设备，尚未进行真机界面与跨设备实机联调。
- 本次任务未部署公网服务；服务端源码已在指定项目内添加。

## 0.2.0 验证（2026-11-18）

- 服务端共 22 项测试通过；验证了私聊隔离、群成员限制、普通消息不调用模型、@指定 Agent、回复不递归触发、并发幂等、失败脱敏、手动重试、凭据不回显、provider 请求参数及旧版消息表迁移保留 ID 和正文。
- Mac 实际网络源代码对本地隔离服务验证了 Agent 目录、私聊、群聊、@回复任务与历史隔离。`LEONAPP_TEST_AGENT` 可指定隔离服务中的 Agent ID，启用这部分协议检查。
- 服务端页面实际打开检查配置回显、会话选择和 @按钮；检查时只使用临时数据库和虚构 API Key，未发出真实模型调用。
- macOS / Android 0.2.0 安装包已生成。Android 未连接真机；模型适配器使用模拟 HTTP 响应验证，未使用真实 API Key 联调。
- 本次任务未部署公网服务。

模型协议参考：[OpenAI Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)、[DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)。

## 0.3.0 验证（2026-11-18）

- 服务端 28 项测试通过，新增覆盖 30 张预设原图、头像读取认证、上传 Cookie / Origin 校验、图片尺寸与格式限制、透明背景和等比缩放、去重、选择保留及数据库关闭重开。
- 在本机临时数据库实际验证预设选择、上传文件、保存、刷新后的头像回显；未修改正式数据。
- Mac 网络检查增加头像下载与缓存验证；Android 构建和 Lint 检查通过。Android 真机尚未连接。
- 两端安装包更新至 0.3.0。本次任务未部署公网服务。

## 0.4.0 验证（2026-11-18）

- 网页 3 组单元测试通过；实际检查 @自动出现、中文筛选、箭头 + Enter、Tab、Esc、邮箱边界、群成员限制、私聊关闭候选及正文中间替换。
- Mac 实际原生输入组件检查通过：@候选、方向键 + Enter、Tab 补全、中文筛选、Esc、邮箱及光标后正文保留。检查使用单独测试应用和虚构 Agent，没有读取连接凭据或发送消息。
- Android 匹配与光标替换单元测试及 Lint 检查通过，尚未连接真机。两端安装包更新至 0.4.0。
- 本次只修改客户端及网页交互，无服务端数据库或模型协议变更；未部署公网服务。


## Mac 失败提示忽略（0.5.1）

失败回复右侧提供「×」忽略按钮，只在当前 Mac 隐藏该条失败提示，按服务器连接与访问令牌隔离保存，重开 App 仍保持隐藏。原消息和服务端任务记录保留，不触发重试，也不改变其他设备。当前会话底部可用「恢复已忽略的失败提示」重新显示。新消息的失败正常显示；已忽略任务若被观察到重新排队或执行，会恢复后续失败提示。

### 对话上下文（macOS 0.6.0）

会话右上角「上下文」可查看各 Agent 的阶段摘要、已确认事实及来源、最近请求的估算输入 Token 和携带轮数，或开启新话题。开启新话题保留聊天记录，后续回复不再携带旧记忆或检索旧话题。新版按 Token 压力压缩，不按轮数触发；压缩失败时仅在完整原文仍放得下的情况下回退继续回复，否则保留原始记录并明确提示。摘要与请求上下文持久化在服务端，OpenAI 继续由 Mac 执行端调用，DeepSeek 继续在服务器调用；压缩调用同样计入模型累计用量。

### 聊天命令与 LeonBook 归档（macOS 0.7.0）

输入 `/` 呼出命令，方向键选择、Enter/Tab 执行、Esc 关闭。`/compact` 主动压缩较早上下文并保留最近一轮；`/context` 查看摘要；`/new` 结束本轮，可先归档再开启全新上下文，也可仅开启新对话；`/export` 导出当前轮次而不重置上下文。群聊明确选择总结使用的 Agent。

导出通过已安装的 `leonbook` CLI 执行，固定当前 root/user，文章保存为草稿，总结在前、原文和图片在后，并附完整 Markdown 原文。长对话的原文完整保存在附件中。同一归档重试复用固定 slug 并读回校验，只有确认文章保存后才开启新上下文；若服务器发现归档期间有新消息，则保留文章并拒绝重置。未完成的导出可以重新执行命令继续，CLI 不可用或磁盘离线时保留当前上下文。不会自动发布到互联网。

### /clear 清空记录（macOS 0.7.1）

输入 `/clear` 先展示当前会话的消息数量和永久删除确认，确认后清空服务端消息、图片和上下文，并清理当前设备该会话的缓存和未发送内容。其他会话、Agent 配置及已导出的 LeonBook 文章保留；需要备份时先执行 `/export`。正在回复/压缩/总结时不能清空，确认后有新消息则须刷新并重新确认。新版 Mac 会接收服务端历史修订，丢弃其他设备清空前的旧缓存。服务端未升级时清空按钮不可用并明确提示部署更新。


### Android 失败提示忽略（0.9.2）

聊天中每条失败回复右侧提供「×」，点击后仅在本机隐藏该条提示，保留原消息与服务端任务，不触发模型重试。忽略状态按服务器和访问令牌隔离保存，切换会话或重开 App 后仍生效；会话底部的「恢复已忽略的失败提示」可重新显示并手动重试。进行中或排队任务不能忽略；新的失败和失败原因变化仍会显示，观察到任务重新排队或执行后会解除旧的忽略状态。无需升级服务端。


### Android 快捷命令、聊天备份与独立对话（0.10.0）

聊天输入栏「＋」提供两行快捷入口：相册、压缩上下文、查看上下文、新建对话、加载备份和清理记录。新建对话直接为当前 Agent 创建独立会话（群聊中先选择 Agent），创建后进入空白聊天，不携带原对话的消息、图片草稿或上下文。聊天页不再提供「对话列表」和「备份记录」快捷入口；清理记录前仍可选择「先备份」。压缩在群聊先选择 Agent；上下文弹窗展示各 Agent 阶段摘要、已确认事实及来源、最近请求估算 Token 和检索 / 回退状态。后台压缩状态在聊天中自动同步。清理先显示服务器消息数量并要求明确确认；若有未完成任务或确认后出现新消息，服务端拒绝操作。

点击聊天中 Agent 的头像进入 Agent 主页，查看该 Agent 的独立对话；可切换已有对话或新建命名对话，每个对话分别保存上下文和草稿。原来的固定私聊继续保留。

备份通过系统文件选择器保存 ZIP，包含服务器已保存的完整消息、时间、回复关联、图片与当前压缩摘要、结构化事实及更正 / 撤销记录、话题边界和旧版兼容轮数字段；不包含 API Key、访问令牌或模型配置。加载时先显示备份会话名与消息数量并确认，再恢复成独立对话，保留已有记录，不自动调用模型。私聊备份可加载给当前 Agent；群聊备份从群聊入口加载，并要求原成员 Agent 仍存在。文件最多 32 MB、10,000 条消息，未发送草稿不包含在备份中。

需要部署服务端项目本次新增的独立对话与备份接口；32 MB 上传还需安装更新后的 `scripts/install_messaging_proxy.py`。旧服务端提示升级。Android 同步历史修订，其他设备清理后会丢弃旧会话缓存与待发消息。本次仅本地构建安装包，不自动部署正式服务。
