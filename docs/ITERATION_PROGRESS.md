# 迭代实施记录

目标：完成 [完整迭代计划](NEXT_ITERATION.md) 的核心范围。更新：2026-09-10。**本轮迭代实现已完成**：核心代码、自动化、原生窗口检查和文档已交付；用户明确要求暂时跳过剩余验收项，这些项目保留为后续补验，不再阻塞本轮完成。跳过不代表验收通过。用户于 2026-09-10 要求提交、推送并发布 1.0.0；应用及脚本服务均已更新为 1.0.0（构建号 6），发布结果以仓库的 [v1.0.0 Release](https://github.com/yxwuxuanl/barstate/releases/tag/v1.0.0) 为准。无工期估算。

## 工作包状态

| 工作包 | 当前状态 | 证据与边界 |
| --- | --- | --- |
| 请求与配置隔离 | 已实现并测试 | Basic 认证方式、用户名、密码变化先复现失败再修复；调度和主线程落地两处隔离；换指标清除旧值 |
| 预设与解析 | 已实现并测试 | DeepSeek / OpenRouter / SiliconFlow 中国站；币种、预算缺失、负余额、有限数校验与响应裁剪；旧 HTTP 不自动变成预设 |
| Prometheus 模板 | 已实现并验证计算 | CPU、内存、磁盘、目标采集状态；实际 Swift 查询由官方 promtool 3.14.0 执行，四种数值及四种空结果检查通过 |
| Settings 与来源表单 | 已实现，限定复核通过 | 固定标题/三个分区/保存区、独立 General、来源目录、专属表单；阈值 AX 与连续错误定位通过；全界面验收范围见下文 |
| 新鲜度与恢复状态 | 已实现并通过核心测试 | 菜单栏、弹窗、设置及侧栏共用健康状态；过期/时钟回拨、保留旧值、离线与环回例外；计时仅在状态变化时更新 UI |
| 本地提醒 | 已实现，投递与点击验收通过 | 连续样本、异常去重/冷却持久化、恢复、克隆关闭；独立打包版已观察拒绝/授权状态、系统投递及用户点击后选中指定监控 |
| 在途请求合并 | 已实现并测试 | 完全相同请求共享在途响应；凭据/超时差异不合并；独立取消与底层取消；完成后无缓存 |
| 服务账户 | DeepSeek、现有 Codex 主周期已验证 | DeepSeek 同一已配置官方接口的一次只读请求通过；Codex 实窗测试额度和保存通过；OpenRouter / SiliconFlow 尚无账户验收证据 |
| Codex 多周期 | 延后，属于有条件扩展 | 当前真实账户只有主周期，次周期为空；保留现有主周期，没有据单账户样本推断所有账户形态 |
| 文档与截图 | 已完成交接 | 中英文指南、三个 README、隐私、1.0.0 变更记录、真实截图与 [DESIGN.md](../DESIGN.md)；设计 sidecar 在本机 `.impeccable/design.json`（遵循现有 gitignore，未暂存） |

## 最终自动化证据

以下日志位于忽略的 `.build/`，是本机验证证据。

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| 核心与应用测试 | 130 项 / 22 组通过 | `.build/final-acceptance-tests.log` |
| Apple Silicon 打包 | 通过 | `.build/notification-diagnostic-build.log` |
| Intel 交叉构建 | 通过 | `.build/final-acceptance-intel-build.log` |
| Apple Silicon 中英文冒烟 | 两种语言通过 | `.build/final-acceptance-arm64-smoke.log` |
| Intel 中英文冒烟 | 两种语言通过，本机运行 | `.build/final-acceptance-intel-smoke.log` |
| 本地化一致性 | 通过 | `./scripts/check-localizations.sh` |
| 本地文档链接和图片路径 | 通过 | 检查 README、指南、计划和隐私文档 |
| 图片来源元数据 | 13 张，0 缺失 | `impeccable embed-prompt --scan docs/images docs/references` |

适用的测试涵盖预设字段缺失、业务错误、数值类型、真实 0、负数、预算未设、币种选择、配置变更、请求取消、并发共享、时间边界、离线隔离、提醒判定、先落盘再通知及重启去重。最初 `.build/p0-before.log` 中三种认证变化共 9 个断言失败，修复后通过。

实窗发现原有排序操作会被旧顺序字段撤销，保存旧草稿也可能覆盖新顺序。新增 3 项测试在修复前产生 6 个失败断言（`.build/ordering-before.log`），修复后通过；原生窗口已验证上移、草稿保留和保存后顺序不变，见 `.build/qa/ordering-after.ax.txt`。

本机普通 `swift test` 遇到混装 CLT/SDK 组件问题。可重复运行 `./scripts/test-local-toolchain.sh`：使用项目内公开 manifest 接口副本、native 构建后端、SDK 26.5 和显式 Testing 路径运行同一套测试，没有修改系统工具链。正常 Xcode 环境仍使用 `swift test`。构建与冒烟脚本支持 `BARSTATE_BUILD_ARCH` 和 `BARSTATE_BUILD_DIR`。

## 真实窗口与设计复核

使用独立测试标识 `com.barstate.BarState.IterationPreview`、内存示例数据及虚拟 Key。正式版进程与监控配置保留。通过 `scripts/prepare-preview-app.sh` 生成该测试包。

已检查默认 1120×760 与最小 860×620 内容尺寸、中文/英文、浅色/深色、分区保留草稿、未保存导航与取消、保存同步、来源目录及无 Key 阻止保存。阈值可通过 AX 设置，非法值不能保存，修正后成功保存。连续触发阈值和显示模板错误时，界面会返回模板分区并聚焦字段，行内与底部 AX 均更新为当前错误。

独立 Impeccable 复核最终 `disposition: ship`，仅针对四项 material fixes：阈值可访问性/对齐、保存错误定位、侧栏统一健康状态、产品事实同步；四项均为 `resolved`。此结论**不是全界面或发布验收通过**。

后续已补齐以下原生窗口检查，证据位于 `.build/qa/`：

- HTTP 完整响应：展开 Body 与响应头、测试解析、切换分区后保留展开和测试结果（`http-response-en-light.*`）。
- Codex：真实账户测试额度、查看仅保留限额的响应、保存、克隆需重新测试且提醒默认关闭、取消克隆及删除本次测试项（`codex-connection-en-light.jpg`，含真实额度，仅留本机）。
- 空列表与只读恢复：独立测试容器的损坏主文件从备份进入只读，确认只读期间文件未变；恢复后可编辑。主文件和备份均损坏时，确认归档后进入可新增的空列表；测试后逐字节恢复原有两份配置（`recovery-readonly-en-light.*`、`empty-settings-en-light.*`）。
- 菜单弹窗：正常、上次值与持续失败的状态及刷新入口；点击 Server Load 行后设置选中同名监控（`popover-en-light.*`、`popover-row-navigation.ax.txt`）。

八张复核截图及最终错误定位 AX 在 `.build/qa/`；对外文档使用 `docs/images/iteration-*.jpg`，来源见 [截图说明](images/README.md)。截图来自实际系统合成窗口；旧的视图离屏缓存捕获未作为有效视觉证据。

## 外部服务与系统集成

**DeepSeek：**读取已配置的同一官方余额接口一次，新预设按 CNY 取得有效有限数值，保留真实负余额，裁剪后与原响应的预设解析结果一致。未输出或保存 Key、具体余额或原始服务响应。

**Codex：**在独立打包版通过“测试额度”读取现有本机登录，取得有效主周期剩余百分比并成功保存。当前返回 `primary_window`，`secondary_window` 为 `null`；快照仅包含 `rate_limit`。本次观察支持继续保留主周期，不足以交付多周期扩展；没有复制认证到监控配置。

**Prometheus：**从官方发布下载 [3.14.0 Darwin arm64 工具](https://github.com/prometheus/prometheus/releases/tag/v3.14.0)，归档 SHA-256 为 `a9623f7f4fe65b1b171b423c1a72bbf23dfdf41a171dcb33e7dd302af80dc01c`，匹配官方值；仅提取到 `.build/prometheus-tools/`。用当前 Swift 代码导出的四个查询，对固定样本运行 `promtool test rules`：CPU 25%、内存 75%、磁盘 80%、抓取失败 0，另加其他主机/挂载点/tmpfs 干扰及无目标结果。8 项预期全部通过，见 `.build/prometheus-template-evaluation.log`。这是实际查询引擎的可控序列验证，未冒充用户生产 node_exporter 的实连验收。

**通知：**独立打包版已验证拒绝与授权后的状态显示，并观察连续三次失败后进入持续异常。通过系统已投递列表确认通知送达；用户点击“BarState notification check”后确认选中同名监控，应用点击回执及 AX 也独立确证。此前选中的是第一项“Unrelated notification check”，因此覆盖了切换到指定监控的路径。证据为 `.build/notification-delivery-receipt.json`（`started → authorized → incident-submitted → system-delivered → clicked`）及 `.build/qa/notification-clicked.ax.txt`。测试版通知权限已恢复关闭，提醒样式恢复临时；正式版权限未修改。

**登录启动：**独立预览包初次显示无法注册的说明，但实际开启后注册成功，系统状态返回启用且错误消失；随后关闭成功并恢复原状态。见 `.build/qa/login-enabled.ax.txt`、`login-restored.ax.txt`。真实注销/重登尚未执行，注册成功不替代登录后自动启动的验收。

## 本轮跳过的验收与后续补验

用户于 2026-09-07 明确要求“暂时跳过剩余验收项”。以下五项本轮均标记为**跳过，未验证**，取代此前等待配合的状态；保留场景以便后续补验。独立测试版已退出；测试版通知权限、提醒样式、登录启动开关及临时替换的配置均已恢复，正式版未受改动。

- **OpenRouter 账户（跳过）：**在 App 填入可用 Key，分别测试今日用量、本月用量和 Key 剩余预算；有预算时显示正确数值，无预算时显示说明并可切换到用量指标继续保存。
- **SiliconFlow 中国站账户（跳过）：**在 App 填入中国站 Key，测试和保存总余额，核对 CNY 及菜单栏显示。两家凭据均直接输入 App，无需发到对话里。
- **登录启动（跳过重新登录实测）：**开启独立测试版登录启动，用户手动重新登录后确认自动启动，再关闭测试版登录启动。注册与移除已验证。
- **睡眠与网络恢复（跳过实际系统流程）：**用户安排睡眠唤醒、断网和联网，检查旧值与过期标记、离线状态、恢复后新请求及提醒去重；本机环回 Prometheus 在外网不可用时仍可监控。相关自动化已通过。
- **VoiceOver（跳过真实语音导航）：**完成选择监控、切换分区、修改阈值及定位保存错误；现有 AX 检查不能替代这一验收。

用户已另行授权 1.0.0 发布；版本号、变更记录、截图与中英文指南已准备。本轮完成依据为已交付的实现与现有验证，以及用户明确跳过上述验收的决定，未将跳过项记为通过。

## 1.0.0 发布记录

2026-09-10：用户授权提交、推送并发布 1.0.0。版本号统一为 1.0.0，构建号递增为 6；保留已跳过的账户、系统和 VoiceOver 实测边界。GitHub Actions 对发布提交执行双架构测试、构建及冒烟检查，成功后附加 Apple Silicon / Intel DMG。版本与资产以 [Release 页面](https://github.com/yxwuxuanl/barstate/releases/tag/v1.0.0) 为准。
