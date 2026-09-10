# Privacy

Last updated: September 10, 2026 (BarState 1.0.0).

BarState is a local macOS application. The project does not operate a backend service, collect analytics, include advertising, or transmit telemetry to the developer.

## Data stored on your Mac

The sandboxed app stores monitor data in `~/Library/Containers/com.barstate.BarState/Data/Library/Application Support/BarState/`. A source build running outside the app sandbox may use `~/Library/Application Support/BarState/`. Depending on your configuration, this can include:

- monitor names, endpoint URLs, PromQL queries, parser expressions, display templates, and refresh settings;
- Basic Authentication credentials, preset API keys, and custom request header contents;
- the most recent complete response from a custom HTTP or Prometheus endpoint; service presets retain only necessary metric fields and selected diagnostic headers, while Codex Quota retains only the `rate_limit` object; and
- monitor state such as the latest value, status, update time, alert rule, and incident deduplication state.

This data is stored locally and is not sent to the BarState developer. Credentials and header values are currently stored with the rest of the local monitor configuration, not in Keychain. Use dedicated, revocable credentials with the minimum permissions required.

When a Codex Quota monitor is enabled, BarState reads the access token and account ID from `~/.codex/auth.json` at request time. BarState has read-only access to that file and does not copy its contents into monitor settings.

## Network access

BarState makes network requests to API or Prometheus endpoints that you configure. Service presets call the selected provider directly: `api.deepseek.com/user/balance`, `openrouter.ai/api/v1/key`, or `api.siliconflow.cn/v1/user/info`. A Codex Quota monitor calls `https://chatgpt.com/backend-api/wham/usage`. Those requests are governed by the privacy practices of the endpoint operators. BarState does not proxy requests through a BarState-owned server.

## Local notifications

Alerts are optional. With your permission, macOS may display a monitor's name, numeric condition or generic request failure, and recovery information. Notification content does not include endpoint URLs, credentials, request headers, or full responses. Rule evaluation and incident deduplication happen on your Mac.

## JavaScript parsing

Custom JavaScript parsers run in a bundled, sandboxed XPC service on your Mac. Parser execution does not send code or response data to the developer.

## Removing your data

Quit BarState, move `BarState.app` to the Trash, and remove its data directory listed above. If you also used a build outside the sandbox, check that separate directory too. Deletion is permanent.

## Changes

Material changes to this notice will be documented in the repository and reflected by the date above.
