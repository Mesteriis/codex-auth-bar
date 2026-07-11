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
не отправляет данные на собственный сервер. Подробности — в английском README и
[SECURITY.md](SECURITY.md).
