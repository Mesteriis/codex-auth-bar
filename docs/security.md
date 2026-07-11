# Security and privacy

Codex Auth Bar has no analytics, telemetry backend, or user account service of
its own. It manages the files that the Codex CLI already uses.

## Plaintext credentials

Codex `auth.json` contains credentials in plaintext. Managed account snapshots
and rotation backups therefore also contain plaintext credentials. The app
creates `accounts/` with mode `0700`, sensitive files with mode `0600`, rejects
symlinked managed files, writes through a same-directory temporary file, calls
`fsync`, and replaces files atomically. Do not sync `CODEX_HOME` to an
untrusted or shared location.

## Remote APIs

Remote refresh is enabled by default and can be disabled in Settings. Access
tokens are sent only to the following HTTPS endpoints:

- `https://chatgpt.com/backend-api/wham/usage`
- `https://chatgpt.com/backend-api/accounts`
- `https://api.openai.com/v1/me` for API-key identity

The ChatGPT backend endpoints are unofficial and may change. Sessions are
ephemeral, have no cookies or URL cache, and reject redirects to unexpected
hosts. Local-only refresh reads Codex rollout JSONL and sends nothing.

## Recovery

Switch transactions use a journal containing account keys and hashes, never
tokens. On startup, known old or new file hashes are reconciled. If `auth.json`
was changed to unknown bytes by another process, recovery stops and leaves it
untouched. Registry rebuild is available in the management window and selects
the newest valid snapshot for each account.

## Experimental codext

Managed codext downloads are pinned to a reviewed version and SHA-256 for each
architecture. The installer checks HTTPS origin, final redirect host, exact
size, checksum, expected archive entries, and path traversal before extraction.
A custom executable path is explicitly user-trusted and is not covered by the
manifest verification.

## Custom CODEX_HOME

A custom home can be selected in Settings and takes effect after restarting
Codex Auth Bar. The app does not request Full Disk Access. Choosing a location
with broader permissions weakens the protection provided by `~/.codex`.
