# DataSource 预设与接口资料

已并入 [完整迭代计划](NEXT_ITERATION.md)，本页保留接口依据与后续候选，实施范围以主计划为准。首批 DeepSeek、OpenRouter、SiliconFlow 与 Prometheus 模板已实现；Codex 保留主周期，有条件扩展延后。2026-09-07 本轮迭代实现已完成，证据见 [实施记录](ITERATION_PROGRESS.md)：DeepSeek 与现有 Codex 主周期已通过真实账户检查，OpenRouter / SiliconFlow 账户检查按用户决定本轮跳过，仍未验证；不估工期。

## 首批服务

| 顺序 | 来源 | 建议指标 | 选择理由与边界 |
| --- | --- | --- | --- |
| 1 | DeepSeek | 账户总余额 | 直接适配低余额提醒；按返回币种选余额，不假定数组首项永远是人民币 |
| 2 | OpenRouter | 默认 Key 今日用量，可选月用量、剩余预算 | 普通 Key 即可查询自身信息；未设预算时显示“未设置限额”，不能当作剩余 0。账户余额另需 Management Key，留待后续独立提供 |
| 3 | SiliconFlow | 总余额 | 同样能直接结合低余额提醒；接入时确认目标站点、单位与余额口径，不能把赠送余额当成总余额 |

这三项均有公开 GET 接口，适合复用现有 HTTP 能力。产品交付应包含来源专属配置表单、默认显示与错误说明，而不只是填好 URL 的示例。

## 同时补齐已有来源

- **Prometheus 常用指标模板**：优先 CPU 使用率、内存使用率、磁盘使用率、目标是否在线。属于已有来源的易用性增强。按指标所需 exporter 提示前提；用户选择实例与磁盘挂载点，避免多个时间序列误聚合成单个值。没有匹配指标时明确说明，不返回 0。
- **Codex 更多周期与重置时间（有条件扩展）**：当前只读主周期，验证通过后增加可用周期选择，把重置时间作为弹窗辅助信息。现有实现使用的接口需单独核对真实响应与兼容性，不能保证每种账户都有相同周期；时间不是另一个数值监控项。不阻塞本版核心交付。

## 后续值得加的来源

- **Claude Code 订阅额度**：价值较高。官方状态栏输入已有 5 小时与 7 天用量及重置时间，但只在 Pro/Max 会话产生响应后提供，字段可能缺失。建议研究将状态栏数据写入本机小型快照再由 BarState 读取的方式；这属于待验证的接入设计。需要保留已有 statusLine 设置、记录来源更新时间；Claude Code 没有活动时，BarState 不能通过轮询旧快照把额度当作刚刚更新。
- **HTTP 服务健康/响应时间**：适合个人服务与服务器日常监控。属于新增探测能力，当前通用 HTTP 路径只提取响应中的数值，不能直接等价为状态码与耗时监控。先明确成功状态范围、超时和重定向，再接入提醒。
- **OpenAI / Anthropic API 花费**：适合组织费用监控，但需相应管理员权限和时间区间聚合。与 ChatGPT / Claude 订阅额度分开命名；首批面向简单配置时，建议排在余额预设之后。

## 设置流程

“添加监控”打开来源列表：AI 额度与余额、服务器指标、自定义。选择供应商后显示凭据、指标与刷新周期，测试通过再保存；默认隐藏供应商固定的 URL 与解析方式。通用 HTTP / Prometheus 继续提供完整配置。

每个预设应定义来源标识与版本、指标名称、单位、默认模板、刷新建议、缺失值行为和错误说明。建议提供低余额提醒入口，但默认关闭，遵循本版统一通知规则。对同一账户多个指标的请求合并需保留认证变更隔离；不能让旧账户结果覆盖新配置。

验收关注：有效响应、401/403、429、字段缺失、数字字符串、预算未设、币种差异，以及远端或本地快照过期。SiliconFlow 用户信息响应含邮箱等无关账户信息，预设应只保留必要指标与诊断信息。本文所列文档核对不替代真实账户兼容验证。

## 官方接口依据

- [DeepSeek：Get User Balance](https://api-docs.deepseek.com/api/get-user-balance/)：`GET /user/balance`，`balance_infos` 提供币种、总余额、赠送和充值余额。
- [OpenRouter：Get current API key](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-api-key)：`GET /api/v1/key`，Bearer Key；提供 `usage_daily`、`usage_monthly`、`limit_remaining` 等。
- [OpenRouter：Get remaining credits](https://openrouter.ai/docs/api/api-reference/credits/get-remaining-credits)：`GET /api/v1/credits`，明确要求 Management Key；账户剩余可按 `total_credits - total_usage` 计算。
- [SiliconFlow：获取用户账户信息](https://docs.siliconflow.com/cn/api-reference/userinfo/get-user-info)：响应区分 `balance`、`chargeBalance` 与 `totalBalance`。中国站端点以 [官方 OpenAPI](https://github.com/siliconflow/siliconcloud/blob/main/openapi.yaml) 的 `https://api.siliconflow.cn/v1/user/info` 为准；[中国站充值条款](https://docs.siliconflow.com/cn/legals/recharge-policy) 明确人民币。当前实现仅提供中国站与 CNY，国际站不在已支持范围；真实账户尚未验证。
- [Claude Code：Customize your status line](https://code.claude.com/docs/en/statusline)：`rate_limits.five_hour` / `seven_day` 包含已用百分比与重置时间，文档明确说明订阅条件与字段缺失情形。
- [Prometheus：Node Exporter 指南](https://prometheus.io/docs/guides/node-exporter/)、[Jobs and instances](https://prometheus.io/docs/concepts/jobs_instances/)：主机指标采集前提与 `up` 状态；`up=0` 表示抓取失败，不等同于断言整台主机离线。
- [OpenAI：Reviewing API usage and costs](https://help.openai.com/en/articles/10478918-reviewing-api-usage-and-costs)、[Admin API Keys](https://platform.openai.com/docs/api-reference/admin-api-keys)：组织用量/成本与管理员权限。
- [Anthropic：Admin API](https://platform.claude.com/docs/en/manage-claude/admin-api)：组织管理员凭据与权限要求。
