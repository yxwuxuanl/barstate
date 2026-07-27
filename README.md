# BarState

[简体中文](README.md) | [English](README_EN.md)

BarState 是一款 macOS 菜单栏监控工具，提供两种独立的使用方式：发送 HTTP 请求并解析 API 响应，或执行 PromQL 查询读取 Prometheus 指标。两种方式取得的数值都可以直接显示在菜单栏中。

需要完整的操作说明时，请参阅 [BarState 使用指南](docs/USER_GUIDE.md)。

## 界面预览

![BarState 设置面板、菜单栏状态与监控列表](docs/images/barstate-app-overview-zh.png)

## 系统要求

- macOS 15 或更高版本
- Apple Silicon（M1 或更新的 Mac）和 Intel Mac 均为首要支持平台

## 下载与安装

> [!WARNING]
> 当前 Release 未使用 Apple Developer ID 签名，也未经过 Apple 公证。请只从本仓库的 Releases 页面下载安装包。

1. 在 [Releases](../../releases) 页面下载与 Mac 架构对应的安装包：
   - Apple Silicon：`BarState-macos-arm64.dmg`
   - Intel：`BarState-macos-x86_64.dmg`
2. 打开下载的 DMG，将 `BarState.app` 拖入“应用程序”文件夹。
3. 双击 `BarState.app` 尝试启动。
4. 如果 macOS 阻止打开，请进入“系统设置” → “隐私与安全性”。
5. 在“安全性”区域找到 BarState，点击“仍要打开”，然后使用登录密码或 Touch ID 确认。

也可以在确认应用来自本仓库 Releases 后，通过终端移除 BarState 的下载隔离标记：

```sh
xattr -dr com.apple.quarantine "/Applications/BarState.app"
```

此命令只作用于 BarState，不会全局关闭 Gatekeeper。

不需要也不建议为了运行 BarState 而全局关闭 Gatekeeper。

## HTTP 请求监控

HTTP 请求监控适合从普通 API 响应中提取数值。BarState 定时发送请求，再通过 JSONPath 或 JavaScript 解析响应。

### 创建 HTTP 请求监控

1. 启动 BarState，点击菜单栏中的 `BarState`，选择“设置…”。
2. 点击左侧的“新增”，将“数据源”保持为 `API`。
3. 填写监控项名称和 HTTPS 接口地址。
4. 如有需要，配置 Basic Authentication 或添加请求头。
5. 点击“测试请求”，确认接口返回了预期内容。
6. 选择 JSONPath 或 JavaScript 解析方式，填写解析表达式。
7. 点击“测试解析”，确认能够得到数值。
8. 设置显示模板和刷新周期，然后保存。
9. 开启“启用监控”；需要在菜单栏直接显示结果时，再开启“显示在菜单栏”。

新建 HTTP 请求监控必须先完成请求测试并成功解析，之后才能保存。

### 配置 HTTP 请求

API 数据源目前只支持 HTTPS `GET` 请求，不支持 HTTP、其他请求方法或请求体。

接口使用 HTTP Basic Authentication 时，在“认证方式”中选择 `Basic Authentication`，然后填写用户名和密码。BarState 会自动生成 `Authorization` 请求头。

Bearer Token、API Key 等其他认证方式可以在“请求头”区域添加多组 Header，例如：

```text
Authorization: Bearer your-token
```

URL、请求头名称和请求头值都可以使用 `${TIMESTAMP}`。发送请求时，它会被替换为当前 Unix 秒级时间戳。

启用 Basic Authentication 时，不能再手动添加 `Authorization` 请求头。

配置完成后点击“测试请求”。响应预览会显示 Body、状态码、Content-Type、请求时间和响应头等信息。

### 解析 HTTP 响应

#### JSONPath

JSON 响应可以使用简化 JSONPath，支持根节点 `$`、属性访问和数组下标。

例如，接口返回：

```json
{
  "data": {
    "temperatures": [23.6]
  }
}
```

使用以下表达式可取得 `23.6`：

```text
$.data.temperatures[0]
```

#### JavaScript

需要自定义处理逻辑，或接口返回的不是 JSON 时，请使用 JavaScript。函数接收 `response` 参数，并返回数字或数字字符串。

```javascript
function(response) {
    return response.data.temperatures[0]
}
```

如果响应是普通文本，可以直接处理字符串：

```javascript
function(response) {
    return Number(response.trim())
}
```

修改解析方式或表达式后，需要再次点击“测试解析”并成功，才能保存新配置。

### 三个常用场景

以下解析表达式基于示例响应，实际使用时需要按照接口返回的数据结构调整。

1. 查看 API 剩余额度：

   ```json
   {"data":{"remaining":842}}
   ```

   使用 JSONPath `$.data.remaining`，显示模板可设置为 `额度 ${value}`。

2. 查看实时汇率：

   ```json
   {"rates":{"CNY":7.23}}
   ```

   使用 JSONPath `$.rates.CNY`，显示模板可设置为 `USD/CNY ${value}`。

3. 查看返回纯文本的温度传感器：

   ```text
   23.6
   ```

   使用 JavaScript 将文本转换为数字：

   ```javascript
   function(response) {
       return Number(response.trim())
   }
   ```

   显示模板可设置为 `温度 ${value}℃`。

## PromQL 查询监控

PromQL 查询监控用于直接读取 Prometheus 指标，不需要配置 JSONPath 或 JavaScript。BarState 会定时调用 Prometheus 即时查询接口，并将查询得到的单个数值显示在菜单栏中。

### 创建 PromQL 查询监控

1. 新建监控项，将“数据源”切换为 `Prometheus`。
2. 填写 Prometheus 地址和 PromQL。
3. 如有需要，配置 Basic Authentication 或添加认证请求头。
4. 点击“测试查询”，确认查询能够得到单个数值。
5. 设置显示模板和刷新周期，保存并启用监控。

BarState 会在 Prometheus 地址后自动补全 `/api/v1/query`。远程地址必须使用 HTTPS；`localhost`、`127.x.x.x` 和 `::1` 等本机环回地址可以使用 HTTP。

PromQL 必须返回一个标量或仅包含一条时间序列的即时向量。如果查询返回多条时间序列，请使用 `sum()`、`avg()`、`max()` 等聚合函数，或添加更精确的标签筛选。新建监控项或修改查询配置后，需要先点击“测试查询”并成功，才能保存。

### 三个常用场景

1. 查看 API 每秒请求量：

   ```promql
   sum(rate(http_requests_total[5m]))
   ```

2. 查看 API 的 5xx 错误率（百分比）：

   ```promql
   100 * sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
   ```

3. 查看所有监控目标的当前在线率（百分比）：

   ```promql
   100 * avg(up)
   ```

## 显示与刷新

显示模板必须包含 `${value}`，它会被替换为解析结果。例如：

```text
气温 ${value}℃
```

刷新周期可以使用秒、分或时，允许范围为 30 秒至 365 天。

点击任意 BarState 菜单栏项目可以查看全部监控项、当前状态和最近更新时间，也可以手动刷新所有已启用的监控项。按住 Command 键拖动菜单栏项目，可以调整它们的位置。

## 其他设置

- “登录时启动”：登录 macOS 后自动打开 BarState。
- “语言”：支持跟随系统、简体中文和 English；更改后重新启动 BarState 生效。
- 左侧监控项列表可以调整顺序或删除不再需要的监控项。

## 本地数据与卸载

监控配置保存在：

```text
~/Library/Application Support/BarState/
```

Basic Authentication 凭据、请求头内容和最近一次完整响应会保存在本机。请避免使用长期有效或权限过高的凭据，并尽量使用可随时撤销的专用凭据。

卸载步骤：

1. 退出 BarState。
2. 将 `BarState.app` 移到废纸篓。
3. 如需同时删除全部监控配置，再删除 `~/Library/Application Support/BarState/`。

删除配置目录后无法恢复其中的数据。

## 从源码运行

在项目根目录执行：

```sh
./scripts/build-app.sh
open .build/BarState.app
```

运行完整检查：

```sh
swift test
./scripts/check-localizations.sh
./scripts/test-app-smoke.sh
```

构建完成后的应用位于 `.build/BarState.app`。
