# BarState

[English](README.md) | [简体中文](README_ZH.md)

BarState is a macOS menu bar monitoring app for service balances, HTTP API values, Prometheus metrics, and local Codex quota.

[User Guide](docs/USER_GUIDE_EN.md) · [Releases](../../releases) · [Privacy](PRIVACY.md) · [Security](SECURITY.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

## What’s new in 1.0.0

BarState 1.0.0 adds native Settings sections, DeepSeek / OpenRouter / SiliconFlow China presets, four Prometheus templates, freshness indicators, and optional local alerts. The transient menu bar refresh icon has been removed to reduce flicker.

Read the [iteration plan](docs/NEXT_ITERATION.md), [validation record](docs/ITERATION_PROGRESS.md), or [user guide](docs/USER_GUIDE_EN.md). DeepSeek and existing Codex quota have real-account checks; packaged notification delivery and click navigation also passed. OpenRouter and SiliconFlow account checks, real login/wake/network recovery, and VoiceOver navigation were explicitly deferred for this release and remain unverified.

![Settings, sample data, dark minimum window](docs/images/iteration-settings-en-dark.jpg)

## Earlier App Preview

<p align="center">
  <img src="docs/images/barstate-menubar-popover.png" alt="BarState menu bar and monitor popover" width="540">
</p>

![BarState monitor settings](docs/images/barstate-settings.png)

## System Requirements

- macOS 15 or later
- Apple Silicon Macs (M1 or later) and Intel Macs are both first-class supported platforms

## Download and Install

> [!WARNING]
> The current release is ad hoc signed, not signed with an Apple Developer ID, and has not been notarized by Apple. Install only from the official Homebrew tap or this repository's Releases page.

### Homebrew

Install BarState from the official tap. Homebrew automatically selects the correct build for Apple Silicon or Intel Macs:

```bash
brew install --cask yxwuxuanl/tap/barstate
```

Upgrade or uninstall it with:

```bash
brew upgrade --cask barstate
brew uninstall --cask barstate
```

### Manual Installation

1. Download the installer for your Mac architecture from [Releases](../../releases):
   - Apple Silicon: `BarState-macos-arm64.dmg`
   - Intel: `BarState-macos-x86_64.dmg`
2. Open the downloaded DMG and drag `BarState.app` into the Applications folder.
3. Double-click `BarState.app` to launch it.
4. If macOS blocks the app, open System Settings → Privacy & Security.
5. Find BarState in the Security section, click Open Anyway, and confirm with your login password or Touch ID.

Alternatively, after confirming that the app came from this repository's Releases page, remove BarState's download quarantine attribute in Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/BarState.app"
```

This command affects BarState only and does not disable Gatekeeper globally.

You do not need to disable Gatekeeper globally, and doing so is not recommended.

## HTTP Request Monitoring

HTTP request monitoring is designed for extracting numeric values from standard API responses. BarState sends requests on a schedule, then parses each response with JSONPath or JavaScript.

### Create an HTTP Request Monitor

1. Launch BarState, click `BarState` in the menu bar, and select Settings.
2. Click Add in the sidebar and choose Custom HTTP API.
3. Enter a name and an HTTPS endpoint URL.
4. Configure Basic Authentication or add request headers if the endpoint requires them.
5. Click Test Request and confirm that the endpoint returns the expected response.
6. Choose JSONPath or JavaScript and enter a parser expression.
7. Click Test Parser and confirm that it returns a numeric value.
8. Set the refresh interval, choose a template in Menu Bar, then save the monitor.
9. Turn on Enable Monitor. To show the result directly in the menu bar, also turn on Show in Menu Bar.

A new HTTP request monitor must pass both the request and parser tests before it can be saved.

### Configure the HTTP Request

The API data source currently supports HTTPS `GET` requests only. HTTP endpoints, other request methods, and request bodies are not supported.

For HTTP Basic Authentication, choose `Basic Authentication` under Authentication and enter the username and password. BarState generates the `Authorization` header automatically.

For Bearer tokens, API keys, and other authentication schemes, add one or more headers in the Request Headers section. For example:

```text
Authorization: Bearer your-token
```

You can use `${TIMESTAMP}` in the URL, header names, and header values. BarState replaces it with the current Unix timestamp in seconds when sending the request.

You cannot add a custom `Authorization` header while Basic Authentication is enabled.

After configuring the request, click Test Request. The response preview shows the body, status code, Content-Type, request time, and response headers.

### Parse the HTTP Response

#### JSONPath

For JSON responses, BarState supports a simplified JSONPath syntax with the `$` root, property access, and array indexes.

For example, given this response:

```json
{
  "data": {
    "temperatures": [23.6]
  }
}
```

Use the following expression to extract `23.6`:

```text
$.data.temperatures[0]
```

#### JavaScript

Use JavaScript when you need custom processing or when the endpoint returns non-JSON text. The function receives a `response` parameter and must return a number or a numeric string.

```javascript
function(response) {
    return response.data.temperatures[0]
}
```

For a plain-text response, process the string directly:

```javascript
function(response) {
    return Number(response.trim())
}
```

After changing the parser type or expression, run Test Parser successfully before saving the new configuration.

### Three Common Use Cases

The parser expressions below match the example responses. Adjust them to fit the structure returned by your API.

1. Show the remaining API quota:

   ```json
   {"data":{"remaining":842}}
   ```

   Use the JSONPath `$.data.remaining` and a display template such as `Quota ${value}`.

2. Show a live exchange rate:

   ```json
   {"rates":{"CNY":7.23}}
   ```

   Use the JSONPath `$.rates.CNY` and a display template such as `USD/CNY ${value}`.

3. Show a temperature sensor that returns plain text:

   ```text
   23.6
   ```

   Use JavaScript to convert the text to a number:

   ```javascript
   function(response) {
       return Number(response.trim())
   }
   ```

   Use a display template such as `Temperature ${value}°C`.

## Codex Quota Monitoring

Codex Quota monitoring reads the primary rate-limit window for the Codex account currently signed in on this Mac and displays the remaining percentage.

1. Sign in to Codex so that `~/.codex/auth.json` exists.
2. In BarState, choose Add → Codex.
3. Click Test Quota, then set the display template and refresh interval.
4. Save and enable the monitor.

BarState calls `https://chatgpt.com/backend-api/wham/usage` and calculates the displayed value as `100 - used_percent`. Credentials are read from `~/.codex/auth.json` for each request and are not copied into BarState settings. Stored response previews retain only the `rate_limit` object, excluding the account ID, user ID, and email address.

## PromQL Query Monitoring

PromQL query monitoring reads Prometheus metrics directly and does not use JSONPath or JavaScript. BarState runs Prometheus instant queries on a schedule and displays the resulting single numeric value in the menu bar.

### Create a PromQL Query Monitor

1. Choose Add → Prometheus.
2. Enter the Prometheus address. Choose a template and target, or a custom PromQL query.
3. Configure Basic Authentication or add authentication headers if required.
4. Click Test Query and confirm that the query returns a single numeric value.
5. Set the display template and refresh interval, then save and enable the monitor.

BarState automatically appends `/api/v1/query` to the Prometheus address. Remote addresses must use HTTPS; local loopback addresses such as `localhost`, `127.x.x.x`, and `::1` may use HTTP.

The PromQL query must return either a scalar or an instant vector containing exactly one series. If it returns multiple series, refine target labels. Aggregate only when those series belong to the measurement you intend to summarize. After creating a monitor or changing its query settings, Test Query must succeed before the monitor can be saved.

### Three Common Use Cases

1. Show API requests per second:

   ```promql
   sum(rate(http_requests_total[5m]))
   ```

2. Show the API 5xx error rate as a percentage:

   ```promql
   100 * sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
   ```

3. Show the percentage of monitored targets that are currently up:

   ```promql
   100 * avg(up)
   ```

## Display and Refresh

The display template must contain `${value}`, which BarState replaces with the parsed result. For example:

```text
Temperature ${value}°C
```

The refresh interval can use seconds, minutes, or hours and must be between 30 seconds and 365 days.

Click any BarState menu bar item to view all monitors, their current status, and their latest update time. You can refresh one monitor or all enabled monitors. The menu bar can show separate monitor items or one consolidated BarState item; separate items support a maximum title length. Hold Command while dragging a menu bar item to change its position.

## Other Settings

Open General at the bottom of the sidebar for application preferences. Monitor-specific display and alert rules live in their own sections.

- Launch at Login: opens BarState automatically when you sign in to macOS.
- Language: choose Follow System, 简体中文, or English. Restart BarState to apply the change.
- Menu Bar: choose separate items or a single consolidated entry.
- The sidebar supports drag reordering and context-menu clone, move, and delete actions.

## Local Data and Uninstalling

BarState stores monitor settings in:

```text
~/Library/Containers/com.barstate.BarState/Data/Library/Application Support/BarState/
```

A build outside the app sandbox may instead use `~/Library/Application Support/BarState/`. Basic Authentication credentials, preset API keys, custom headers, and recent response data are stored locally. Service presets retain selected metric fields and diagnostics; custom HTTP and Prometheus retain the recent response. Codex credentials are not copied into BarState, and Codex response storage is limited to rate-limit data. Avoid long-lived or highly privileged credentials, and prefer dedicated credentials that can be revoked.

If configuration files cannot be read, BarState enters a read-only recovery mode so later edits cannot overwrite them. Starting fresh archives the old files with `.corrupt-timestamp.json` names first.

To uninstall BarState:

1. Quit BarState.
2. Move `BarState.app` to the Trash.
3. To remove all monitor settings as well, delete `~/Library/Containers/com.barstate.BarState/Data/Library/Application Support/BarState/`.

Deleting the settings directory permanently removes its data.

## Run from Source

From the project root, run:

```sh
./scripts/build-app.sh
open .build/BarState.app
```

To run the full set of checks:

```sh
swift test
./scripts/check-localizations.sh
./scripts/test-app-smoke.sh
```

The built app is available at `.build/BarState.app`. If this Mac has the mixed Command Line Tools / SDK issue recorded in validation progress, use `./scripts/test-local-toolchain.sh` for the same test suite. `BARSTATE_BUILD_ARCH=arm64` or `x86_64` selects the architecture for the app build and smoke scripts; `BARSTATE_BUILD_DIR` selects an output directory.

## Privacy and Security

BarState has no analytics, advertising, developer-operated backend, or telemetry. It connects to endpoints you configure and, when enabled, the Codex quota endpoint described above. Monitor data is stored locally on your Mac. Read the [Privacy Notice](PRIVACY.md) and [Security Policy](SECURITY.md) before using sensitive endpoints.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for development requirements and required checks. Release history is recorded in [CHANGELOG.md](CHANGELOG.md).

## License

BarState is free and open-source software released under the [MIT License](LICENSE).
