# Contributing to BarState

Thanks for taking the time to improve BarState.

## Before opening a change

- Search existing issues and pull requests to avoid duplicate work.
- Open an issue before starting a large feature or behavior change.
- Never include real credentials, private endpoints, or response data in issues, tests, screenshots, or commits.
- Keep user-facing text available in both English and Simplified Chinese.

For suspected vulnerabilities, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Development requirements

- macOS 15 or later
- Swift 6
- Xcode or the matching macOS command-line developer tools

Build the app from the repository root:

```sh
./scripts/build-app.sh
open .build/BarState.app
```

## Required checks

Run all checks before submitting a pull request:

```sh
swift test
./scripts/check-localizations.sh
./scripts/test-app-smoke.sh
```

Please add or update tests when changing parsing, requests, persistence, polling, or menu bar formatting.

## Pull requests

Keep each pull request focused. Explain the problem, the chosen approach, user-visible changes, and how you verified the result. Include screenshots for UI changes.

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
