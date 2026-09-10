# Changelog

All notable changes to BarState are documented here.

## [1.0.0] - 2026-09-10

Native Settings, service presets, and daily monitoring improvements. OpenRouter / SiliconFlow real-account checks, real login/wake/network recovery, and VoiceOver navigation were explicitly deferred for this release. See the [validation record](docs/ITERATION_PROGRESS.md) for evidence and unverified scenarios.

- Reorganized Settings into a native sidebar, shared Connection & Parsing / Menu Bar / Alerts draft, independent General settings, and a fixed save area with error routing.
- Added a source catalog and DeepSeek, OpenRouter, and SiliconFlow China presets with explicit metrics, currency handling, and limited response snapshots.
- Added CPU, memory, disk, and target scrape-status Prometheus templates with explicit target selection.
- Unified freshness, previous-value, failure, and offline status across monitor surfaces.
- Removed the transient menu bar refresh icon to reduce flicker during frequent or slow requests.
- Added opt-in local alert rules, consecutive-sample confirmation, persisted incident deduplication, and optional recovery notifications.
- Isolated results after authentication or metric changes and shared identical in-flight requests without caching completed responses.
- Fixed sidebar move and drag ordering being undone by old order numbers; saving an already-open draft preserves the current order.
- Added bilingual development guides, repeatable local toolchain validation, and architecture-specific build options.

## [0.5.0] - 2026-08-09

- Added a Codex Quota data source that displays the remaining primary-window quota.
- Read Codex credentials at request time from `~/.codex/auth.json` without copying tokens into BarState settings.
- Limited persisted Codex responses to rate-limit data so account identity is not retained.
- Added privacy, security, license, contribution, and release-history documentation.

## [0.4.0] - 2026-07-31

- Added configurable value-to-color status indicators for menu bar monitors.
- Improved monitor status details and menu bar presentation.
- Expanded compatibility and formatter test coverage.

## [0.3.0] - 2026-07-28

- Improved the first-launch and monitor-creation experience.
- Strengthened persistence and recovery behavior for unreadable configuration files.
- Refined the settings, monitor editor, and menu bar status presentation.
- Expanded smoke and unit test coverage.

## [0.2.1] - 2026-07-27

- Fixed the app icon background so it renders transparently.

## [0.2.0] - 2026-07-27

- Added Prometheus instant-query monitoring with PromQL.
- Added Basic Authentication and multiple custom request headers.
- Added native installers for both Apple Silicon and Intel Macs.
- Added English localization and expanded user documentation.
- Added monitor cloning, reordering, and improved request/response inspection.

## [0.1.0] - 2026-07-26

- Initial public release.
- Added scheduled HTTPS `GET` monitoring.
- Added numeric response extraction with JSONPath or JavaScript.
- Added configurable menu bar value display and refresh intervals.

[1.0.0]: https://github.com/yxwuxuanl/barstate/releases/tag/v1.0.0
[0.5.0]: https://github.com/yxwuxuanl/barstate/releases/tag/v0.5.0
[0.4.0]: https://github.com/yxwuxuanl/barstate/releases/tag/v0.4.0
[0.3.0]: https://github.com/yxwuxuanl/barstate/releases/tag/v0.3.0
[0.2.1]: https://github.com/yxwuxuanl/barstate/releases/tag/v0.2.1
[0.2.0]: https://github.com/yxwuxuanl/barstate/releases/tag/v0.2.0
[0.1.0]: https://github.com/yxwuxuanl/barstate/releases/tag/v0.1.0
