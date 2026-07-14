# Security Policy

## Supported Version

Only the latest tagged release is supported with security fixes.

## Reporting A Vulnerability

Use GitHub's private vulnerability reporting feature for this repository. Do
not open a public issue containing an exploit, credential, token, or affected
host information.

## Installation Trust

The bootstrap requires HTTPS and verifies the version-pinned runner with an
embedded SHA-256 digest before execution. Product installers are downloaded
only after the operator selects a provider.

Review `install.sh`, `runner.sh`, and `SHA256SUMS` before use in a sensitive
environment. A pinned release URL is preferable to `main` when immutable input
is required.
