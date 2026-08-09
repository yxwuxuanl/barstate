# Changelog

All notable changes to BarState are documented here.

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

[0.5.0]: https://github.com/yxwuxuanl/barstate/releases/tag/v0.5.0
[0.4.0]: https://github.com/yxwuxuanl/barstate/releases/tag/v0.4.0
[0.3.0]: https://github.com/yxwuxuanl/barstate/releases/tag/v0.3.0
[0.2.1]: https://github.com/yxwuxuanl/barstate/releases/tag/v0.2.1
[0.2.0]: https://github.com/yxwuxuanl/barstate/releases/tag/v0.2.0
[0.1.0]: https://github.com/yxwuxuanl/barstate/releases/tag/v0.1.0
