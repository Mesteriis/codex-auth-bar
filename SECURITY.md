# Security policy

Please report vulnerabilities privately through GitHub Security Advisories.
Do not include real Codex tokens, JWTs, API keys, or auth files in reports.

Supported releases are the latest published stable version and the latest
release candidate. The project never logs raw auth JSON and uses only synthetic
credentials in tests.

The optional usage API and codext features are explicitly documented trust
boundaries. Codext archives must match the pinned SHA-256 before extraction.
