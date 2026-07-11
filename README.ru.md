# Codex Auth Bar

Нативное macOS-приложение в menu bar для управления аккаунтами Codex и запуска
конфигурационных профилей Codex CLI.

Проект вдохновлён
[Loongphy/codex-auth](https://github.com/Loongphy/codex-auth) и совместим с его
форматом registry v4. Это независимый Swift-порт, не связанный с OpenAI или
Loongphy.

Основные возможности: безопасное переключение с перезапуском Codex App,
изолированный login, import/export/CPA, aliases, previous account, usage,
локальный fallback, `<name>.config.toml` profiles, opt-in auto-switch и
проверяемый по SHA-256 experimental codext.

```bash
swift test --package-path src/Packages/CodexAuthCore
./script/build_and_run.sh --verify
```

Весь Swift-код приложения, пакета и тестов хранится в `src/`.

Токены хранятся в локальных auth-файлах Codex. Приложение не имеет аналитики и
не отправляет данные на собственный сервер. Удалённое обновление usage включено
по умолчанию и отправляет токен обновляемого аккаунта только на неофициальные
endpoint-ы `chatgpt.com/backend-api/wham/usage` и
`chatgpt.com/backend-api/accounts`; для проверки API-ключа используется
`api.openai.com/v1/me`. Удалённое обновление можно выключить в Settings.

Snapshots и backups также содержат plaintext credentials и защищаются правами
`0600`; каталог `accounts/` создаётся с `0700`. Experimental codext загружается
только по закреплённому manifest и проверяется по SHA-256. Подробности — в
английском README и [SECURITY.md](SECURITY.md).
