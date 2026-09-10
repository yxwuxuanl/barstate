# BarState 产品上下文

<!-- impeccable:product-schema 1 -->

## Platform

macos

原生 macOS 菜单栏应用，使用 Swift 6、SwiftUI 和 AppKit，最低支持 macOS 15。当前工具的产品模板未枚举 macOS，此处按项目实际平台记录。

## Users

使用 Mac 查看自定义 HTTP API 数值、Prometheus 指标或本机 Codex 额度的用户。

当前迭代优先服务日常监控场景。用户已确认关注异常提醒、数据新鲜度与恢复；没有选择以 Codex 专用能力或创建引导作为本次主线。

## Product Purpose

将周期性取得的数值直接显示在 macOS 菜单栏，用户可以从弹窗检查全部监控项，并进入设置调整请求、解析和显示方式。

## Operating Context

支持每个监控项独立显示，或合并为一个菜单栏入口。应用在本机轮询用户配置的接口；Codex 数据源在请求时读取本机认证文件。

新建监控以及相关请求/解析配置变更需先测试成功再保存。监控启用和菜单栏显示开关即时生效。已有首次启动引导、示例、克隆、排序、配置备份和只读恢复流程。

## Capabilities and Constraints

- 当前工作区在 HTTP API 能力上加入 DeepSeek、OpenRouter、SiliconFlow 中国站预设；Prometheus 提供四种模板与自定义查询；Codex 读取主周期。结果仍为单个数值，以上能力纳入 1.0.0。
- HTTP API 目前仅支持 HTTPS GET；Prometheus 允许本机环回地址使用 HTTP。
- 界面支持简体中文和英文；Apple Silicon 和 Intel 均为项目支持平台。
- 应用不含遥测、分析、广告或开发者运营的后端，配置和运行数据保存在本机。
- Basic 认证与请求头目前保存在本机配置；Codex 凭据不复制到 BarState 配置。
- 已实现按数据年龄统一判断新鲜度，以及默认关闭的单条异常提醒规则（数值或连续失败、可选恢复通知）。独立打包版通知投递和点击定位已验收；OpenRouter / SiliconFlow 真实账户、部分系统流程和 VoiceOver 导航按用户决定本轮跳过，仍未验证。

## Evidence on Hand

- `README.md`、`README_ZH.md`、`docs/USER_GUIDE.md`：现有功能和使用说明。
- `Sources/`、`Tests/`：实现及现有测试。
- `docs/images/`、`design-qa.md`：已有界面与设计检查记录；截图可能早于最新功能，以源码为准。
- `PRIVACY.md`、`SECURITY.md`、`CONTRIBUTING.md`：隐私、数据处理和贡献约束。
- 当前规划没有真实用户访谈或使用统计，不应编造用户量、留存率或效果数据。

## Confirmed Planning Decisions

- 下一次迭代主线：日常监控的异常提醒、数据新鲜度与恢复。
- 当前交付形式：优先级路线图，暂不估算工期。
- Settings 已确认原生 macOS 侧栏与任务分区，以及 Apple 表单样式、Raycast 信息密度、Proxyman 局部连接调试区域的组合；具体参考见 `docs/SETTINGS_STYLE_REFERENCES.md`，布局见 `docs/SETTINGS_REDESIGN.md`。
- 本版 DataSource 按已接受建议纳入 DeepSeek、OpenRouter、SiliconFlow 与 Prometheus 常用指标模板；Codex 多周期/重置时间验证通过后纳入。接口资料见 `docs/DATASOURCE_PRESETS.md`。
- `docs/NEXT_ITERATION.md` 是整合 UI、DataSource 与日常监控的迭代主计划，统一范围、依赖和验收；专题文档为补充资料。阈值和交互细节中的默认建议可在验证后调整，不作为永久产品约束。
- 2026-09-07 用户明确要求暂时跳过剩余验收项。本轮迭代实现据此收尾，跳过项保留为后续补验；2026-09-10 用户要求提交、推送并发布 1.0.0。
