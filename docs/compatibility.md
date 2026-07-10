# Compatibility

The initial behavior baseline is `Loongphy/codex-auth` commit
`22d87d1531420102fa2f3d51d134f29344dda27c` and registry schema 4.

Supported reads: legacy version 2, schema/version 3, and schema 4. Newer schemas
fail closed without writing. Auth snapshots are copied byte-for-byte so unknown
Codex fields survive switching and export.

Intentional safety differences from upstream:

- optimistic concurrent-write detection and an advisory lock;
- a crash-recovery journal without secrets;
- `clean` preserves `accounts/backup/`;
- codext downloads require pinned SHA-256 verification.
