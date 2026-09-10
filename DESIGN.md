---
name: BarState
description: 原生 macOS 监控设置；紧凑表单、清晰状态与局部响应检查。
rounded:
  badge: "4pt"
  compact: "6pt"
  panel: "8pt"
  group: "10pt"
spacing:
  compact: "6pt"
  tight: "8pt"
  accessory: "12pt"
  section-title: "14pt"
  row: "16pt"
  region: "24pt"
components:
  settings-group:
    rounded: "{rounded.group}"
    padding: "{spacing.row}"
  response-panel:
    rounded: "{rounded.panel}"
---

# Design System: BarState

## Overview

**Creative North Star: "原生 macOS 设置：Apple 表单、Raycast 密度、Proxyman 局部响应组织"**

BarState 的设置界面以日常操作为中心。沿用用户确认的原生 macOS canon：低对比分组、紧凑控件和明确的文字层级；需要理解请求与响应时，再展开技术内容。视觉重点是当前监控名称、当前任务及其反馈。

此文记录BarState 1.0.0 Settings 的已实现系统，适用于 SwiftUI / AppKit、macOS 15+。依据实际代码与原生窗口截图，不把未来计划当成规范；产品事实以 [PRODUCT.md](PRODUCT.md) 为准，界面方向与官方参考见 [Settings 样式参考](docs/SETTINGS_STYLE_REFERENCES.md)。不为已确认方向另创名称。

前置令牌中的 `pt` 表示 SwiftUI 逻辑点，不是网页 CSS 点数。语义颜色、系统文字样式与平台控件无法由 CSS 令牌如实表达，因此保留在下文及 本机忽略的 `.impeccable/design.json` 的 `extensions.nativeMacOS` 中。该文件的 HTML/CSS 组件仅供面板示意预览，不是原生实现或视觉验收依据。

**Key Characteristics:**

- 系统语义表面与文字颜色，深浅色由 macOS 解析。
- 固定身份、任务导航和保存操作；当前任务内容独立滚动。
- 对齐的紧凑表单，技术内容在局部区域展开。
- 状态、测试与验证反馈使用文字和原生符号共同表达。

## Colors

颜色服务于选择、层级和运行状态；没有独立的品牌色盘或固定主题色值。

### Primary

- **系统强调色**（`Color.accentColor`）：原生选择及主要操作；通用设置的选中背景和变量复制按钮使用局部透明度。具体呈现随系统设置和控件状态变化，不以截图中的蓝色或灰色取代语义值。

### Neutral

- **窗口表面**（`Color(nsColor: .windowBackgroundColor)`）：编辑区和通用设置底层。
- **控件分组表面**（`Color(nsColor: .controlBackgroundColor)`）：主题设置组；与窗口表面形成克制的明度关系。
- **文本表面**（`Color(nsColor: .textBackgroundColor)`）：响应 Body 阅读区域。
- **主次文字**（`.primary`、`.secondary`、`.tertiary`）：内容、说明和低优先级辅助信息。来源标签使用 `.quaternary` 背景。
- **边界与操作栏**（`Divider()`、`.separator`、`.bar`）：分区边界、局部检查器轮廓和固定页脚；由平台解析材质。

### Named Rules

**The Semantic Color Rule.** 保留原生语义颜色与材质；不把某次截图采样的 hex、玻璃效果或合成色阶作为主题真值。

**The Health Meaning Rule.** 红色用于失败和无效输入；橙色用于重试、过期、离线及需要处理的提示；绿色用于明确的测试成功反馈。侧栏与标题使用同一个 `MonitorHealth` 判断状态，并以文字说明，不把正常运行普遍染成绿色。侧栏的刷新中状态可使用强调色。

## Typography

**Body Font:** macOS 系统字体，通过 SwiftUI 文字样式调用；不指定网页回退字体栈。界面没有独立展示字体。

**Label/Mono Font:** 技术表达式和响应内容使用 `.system(..., design: .monospaced)`；时间和耗时使用 `.monospacedDigit()`。菜单栏效果预览沿用系统圆体正文，以对应预览对象。

### Hierarchy

| 角色 | 实际调用 | 用途 |
| --- | --- | --- |
| 标题 | `.title2.weight(.semibold)` | 当前监控名称、通用设置和来源列表标题 |
| 组标题 | `.headline` | 设置组与侧栏标题 |
| 正文 | 默认正文；来源列表名称为 `.body.weight(.medium)` | 字段、控件和来源名称 |
| 状态与辅助标题 | `.subheadline`；响应标题增加 `.semibold` | 运行摘要、响应和 HTTP 详情标题 |
| 说明 | `.callout`、`.caption` | 来源说明、帮助、测试和保存反馈 |
| 来源标签 | `.caption2.weight(.medium)` | 侧栏名称旁的短来源标签 |
| 技术文字 | 系统等宽正文 / caption | JSONPath、脚本、变量、结果与类型 |

系统语义文字样式的实际字号、行高和字形由 macOS 决定，未采样为固定数值。响应查看器另有局部字号和行距，见组件说明；它们不是通用字号阶梯。

**The Native Type Rule.** 用语义文字样式区分操作层级；等宽字体留给技术内容，普通表单继续使用系统正文。

## Layout

窗口采用 `HSplitView`。默认内容尺寸为 1120 × 760 点，根视图最低尺寸为 860 × 620 点；窗口控制器也设置对应最小尺寸。侧栏最小 / 理想 / 最大宽度为 210 / 220 / 270 点，右侧最小宽度为 620 点。理想宽度不是固定侧栏宽度，实际分割由窗口布局决定。

编辑器的标题、运行摘要、分区选择器在滚动区域外；底部保存区也独立固定。分区选择器最大宽度为 460 点。`region` 是编辑器标题和内容的共同边距与组间距；`section-title` 分隔组标题和分组；`row` 用于组内边距及表单横纵间距。

表单使用两列 `Grid` / `GridRow`：标签宽 128 点、靠右，输入列向左对齐并获得余下宽度。短数字与菜单使用内容适合的宽度，URL、凭据、表达式获得较宽输入空间。提醒的条件与阈值各占一个真实 `GridRow`，阈值编辑器宽 120 点，单位紧邻字段。

通用设置采用独立标题和滚动区域，内容最大宽度 660 点。来源选择采用原生 sheet 与分组列表，固定 500 × 560 点。没有网页断点或移动端布局；较小窗口继续保留桌面分栏，表单纵向滚动，响应内容可在自身区域双向滚动。

**The Persistent Context Rule.** 编辑内容滚动时，当前监控、任务分区与保存操作仍留在窗口中；切换同一监控的分区共享草稿。

## Elevation & Depth

这些 Settings 组件没有自定义阴影或自定义动效曲线。层级来自语义表面、分隔线、细轮廓及间距；窗口、sheet、菜单、按钮和焦点的系统效果由 macOS 提供。不要将操作系统自身的窗口阴影解释成项目的阴影令牌。

**The Local Depth Rule.** 常规设置保持低对比分组；较强的边界用于响应、脚本和请求头等局部技术区域。

## Shapes

小来源标签和变量按钮复用 `badge` 圆角；通用设置入口和脚本编辑框复用 `compact`；响应与请求头区域复用 `panel`；设置主题组复用 `group`。来源标签使用连续圆角。平台按钮、菜单、开关、选择器和文本输入框保持各自原生形状，不套用同一个自定义圆角。

响应和请求头区域使用细的语义分隔色轮廓（1 点）；设置主题组主要依赖背景，不给每个普通字段再包一层卡片。

## Components

### Buttons

主要保存操作采用 `.borderedProminent`，绑定默认键盘操作；撤销 / 取消保留原生次要按钮与取消快捷键。请求测试和解析测试使用原生默认按钮，进度指示与结果就近排列。新增等紧凑图标操作使用无边框按钮并提供辅助功能标签；来源列表的示例入口采用 `.link`。

按钮悬停、按下、焦点与禁用外观交由原生控件处理。保存按钮根据草稿、测试和进行中的请求 / 解析状态启用；不要通过 CSS 风格的手绘状态覆盖这些语义。

### Chips

侧栏来源标签是次级信息，不是筛选器：固定短文本、次级文字、四级背景、`badge` 圆角。变量复制按钮是实际操作：等宽 caption、轻强调色背景，复制后显示勾选与绿色反馈。HTTP 状态标签属于响应组件，成功与失败色保持响应语义。

### Cards / Containers

`settingsSection` 把一个标题与一组相关控件组合起来；采用 `settings-group` 令牌。通用设置也使用同类分组表面，但保留自身内容排布。避免将所有局部间距升级成全局令牌。

### Inputs / Fields

文本、密码、菜单、步进器与开关使用 SwiftUI 原生控件。常规标签使用次级文字和统一标签列；帮助文字紧随所属输入。标题名称是 `.plain` 文本字段，仍有明确的辅助功能名称。

验证失败时，页脚保留原因，并切换到相应任务分区、滚动到相关区域；已有焦点映射的字段获得焦点。分区内显示可选择的红色错误文字。不要将该行为描述为所有字段都已有完整焦点映射。已保存监控的启用和菜单栏显示开关即时生效，其他编辑通过保存提交，相关说明保持清楚。

### Navigation

监控列表采用 `.sidebar` 原生选择态。每项两行：名称与短来源在上，当前值或状态在下；长名称尾部截断，来源标签保留宽度，完整信息通过帮助文本补充。过期或重试时，副标题把状态与旧数值放在一起，避免旧数值单独看起来像刚刷新。

应用级偏好从底部“通用设置”进入；添加来源使用分组 sheet。同一监控内使用原生分段选择器在连接、显示、提醒间切换。跨监控、进入通用设置或关闭窗口的未保存保护继续使用原生确认界面。

### Runtime Summary & Response Inspector

运行摘要采用 `DisclosureGroup`：默认精简，详情为次级 caption；失败、重试或离线的状态变化会展开详情。状态符号来自 SF Symbols，并配合文字，不以 Unicode 字形替代图标。

响应检查器把最新请求失败、元数据、Body 与 HTTP 详情分层显示。Body 使用系统等宽（13 点，附加行距 3 点），可选择文本，阅读区域高度为 132–210 点；HTTP 详情使用系统等宽（12 点）并可展开。浅深色均使用文本语义背景。代码与响应的阅读尺寸只适用于这些局部组件，未推广为全局正文规范。

## Do's and Don'ts

### Do:

- **Do** 优先复用原生控件、语义颜色与现有设置组，保留系统焦点和键盘操作。
- **Do** 在默认与最小窗口检查中英文标签、状态文字、阈值输入和固定保存区。
- **Do** 把测试反馈、显示预览和可修正的错误放在所属任务附近。
- **Do** 将真实原生窗口截图及其来源用于验证；实现细节以 Swift 源码为准。

### Don't:

- **Don't** 把固定 hex、网页 CSS 预览或特定 macOS 版本的材质当成原生设计真值。
- **Don't** 用颜色单独表达健康状态，或将旧数值呈现为没有状态说明的新结果。
- **Don't** 把完整响应检查器的密度与边界推广到普通设置表单。
- **Don't** 把计划功能、样例数值或尚未验收的场景记成已完成的系统能力。

证据范围：主要实现见 [SettingsView](Sources/BarState/Views/SettingsView.swift)、[MonitorEditorViewV2](Sources/BarState/Views/MonitorEditorViewV2.swift)、[MonitorEditorSupportViews](Sources/BarState/Views/MonitorEditorSupportViews.swift)、[MonitorEditorState](Sources/BarState/Views/MonitorEditorState.swift)、[SourceCatalogView](Sources/BarState/Views/SourceCatalogView.swift) 与 [SettingsWindowController](Sources/BarState/App/SettingsWindowController.swift)。当前实窗图及来源见 [截图说明](docs/images/README.md)。本次 finish review 对阈值、侧栏状态、产品事实与保存错误定位四项修复给出 `ship`；此结论仅覆盖相关修复及提供视窗，不代表整个 UI、所有辅助功能或发布验收。

未规范化：响应查看器的局部字号 / 透明度、个别控件宽度、单次截图材质与预览数据均未提炼成全局令牌；没有发现需要作为家族样式继承的展示装饰。系统字体与 SF Symbols 属于已确认的原生语言，不按网页装饰规则误判为禁用项。
