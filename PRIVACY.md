# Privacy

Last updated: August 9, 2026

BarState is a local macOS application. The project does not operate a backend service, collect analytics, include advertising, or transmit telemetry to the developer.

## Data stored on your Mac

BarState stores the information required to run your monitors in `~/Library/Application Support/BarState/`. Depending on your configuration, this can include:

- monitor names, endpoint URLs, PromQL queries, parser expressions, display templates, and refresh settings;
- Basic Authentication credentials and custom request header contents;
- the most recent complete response received from a configured endpoint, except that Codex Quota retains only the `rate_limit` object; and
- monitor state such as the latest value, status, and update time.

This data is stored locally and is not sent to the BarState developer. Credentials and header values are currently stored with the rest of the local monitor configuration, not in Keychain. Use dedicated, revocable credentials with the minimum permissions required.

When a Codex Quota monitor is enabled, BarState reads the access token and account ID from `~/.codex/auth.json` at request time. BarState has read-only access to that file and does not copy its contents into monitor settings.

## Network access

BarState makes network requests to API or Prometheus endpoints that you configure. When you configure a Codex Quota monitor, it also calls `https://chatgpt.com/backend-api/wham/usage`. Those requests are governed by the privacy practices of the endpoint operators. BarState does not proxy requests through a BarState-owned server.

## JavaScript parsing

Custom JavaScript parsers run in a bundled, sandboxed XPC service on your Mac. Parser execution does not send code or response data to the developer.

## Removing your data

Quit BarState, move `BarState.app` to the Trash, and delete `~/Library/Application Support/BarState/` to remove all locally stored BarState data. Deletion is permanent.

## Changes

Material changes to this notice will be documented in the repository and reflected by the date above.
