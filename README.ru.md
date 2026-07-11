# Codex Auth Bar

Нативное macOS-приложение в menu bar для управления аккаунтами Codex и запуска
конфигурационных профилей Codex CLI.

Проект вдохновлён
[Loongphy/codex-auth](https://github.com/Loongphy/codex-auth) и совместим с его
форматом registry v4. Это независимый Swift-порт, не связанный с OpenAI или
Loongphy.

Основные возможности: безопасное переключение с перезапуском Codex App,
изолированный login, import/export/CPA, aliases, previous account, usage,
локальный fallback, `<name>.config.toml` profiles, opt-in auto-switch,
проверяемый по SHA-256 experimental codext и read-only виджеты macOS малого,
среднего и большого размера.

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

## Виджеты

Перед добавлением малого, среднего или большого виджета один раз запустите
Codex Auth Bar. Виджет доступен только для чтения: нажатие открывает экран
аккаунтов приложения по deep link `codexauthbar://accounts`; он не переключает
аккаунты и не выполняет сетевых запросов.

Приложение публикует в App Group только безопасный производный snapshot для
отрисовки: отображаемые данные аккаунта и usage limits. В нём явно нет access
token, refresh token, API key, ChatGPT account/user ID, email или auth mode.
Для signed build контрибьюторам нужен Apple provisioning, включающий
`group.com.mesteriis.CodexAuthBar` одновременно для приложения и widget
extension.

Автоматические запросы WidgetKit reload coalescing-ятся не чаще одного раза за
15 минут, а обычный timeline виджета обновляется через 30 минут. Устаревший или
недоступный snapshot остаётся помеченным как stale/offline и не запускает
обновление. При отключённом в Settings Usage API виджет показывает только
последний безопасный локальный snapshot и сам Usage API не вызывает.

Выбранный визуальный референс — Precision Ledger. QA-заметки и артефакты малого,
среднего и большого виджетов: [`docs/qa/widget-design-qa.md`](docs/qa/widget-design-qa.md),
[`widget-small.png`](docs/qa/widget-small.png),
[`widget-medium.png`](docs/qa/widget-medium.png) и
[`widget-large.png`](docs/qa/widget-large.png).
