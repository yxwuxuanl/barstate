# Security Policy

## Supported versions

Security fixes are provided for the latest BarState release. Before reporting a problem, confirm that it is reproducible with the newest version from the repository's Releases page.

## Reporting a vulnerability

Please do not disclose suspected vulnerabilities, credentials, private endpoint URLs, or response data in a public issue.

Use GitHub's **Report a vulnerability** action in the Security tab to send the maintainer a private report. If that action is unavailable, open a public issue containing no sensitive details and ask the maintainer to establish a private contact channel.

Include, when possible:

- the affected BarState version and Mac model/macOS version;
- clear reproduction steps;
- the security impact you observed or anticipate; and
- any suggested mitigation.

You should receive an acknowledgment within seven days. Please allow time to investigate and prepare a fix before publishing details.

## Credential guidance

BarState stores Basic Authentication credentials and custom header values locally with monitor configuration. Prefer dedicated, revocable, least-privilege credentials and avoid production-wide or long-lived secrets.

Codex Quota monitors read `~/.codex/auth.json` with read-only access at request time. The token is not copied into BarState settings, and persisted Codex responses are limited to rate-limit data.

The downloadable app is currently ad hoc signed, not signed with an Apple Developer ID, and not notarized by Apple. Download builds only from this repository's Releases page, or build the app from source.
