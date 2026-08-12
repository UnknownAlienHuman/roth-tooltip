# RothTooltip TODO

Текущий инцидент на 2026-03-13: refresh path для unit tooltip заходил в Blizzard `RebuildFromTooltipInfo()` с secret unit payload и валился в `GameTooltip_UnitColor -> UnitPlayerControlled`.

## Источник проблемы

- `RothTooltip/Core.lua` вызывал `tip.RebuildFromTooltipInfo()` раньше, чем пытался безопасно восстановить tooltip через `SetUnit()` / `SetHyperlink()`.
- Для unit tooltips в Midnight это unsafe: Blizzard line rules снова читают `lineData.unitToken`, и при secret token `GameTooltip_UnitColor(unit)` падает на `UnitPlayerControlled(unit)`.
- Ошибка воспроизводилась из `Unit.lua` на `MODIFIER_STATE_CHANGED`, но тот же refresh path использовался и из других мест (`INSPECT_READY`, options apply, profile reapply).

## Задачи

- [x] Сверить stack trace с `TooltipDataRules.lua`, `GameTooltip.lua` и `lookup_api("UnitPlayerControlled")`
- [x] Переставить `RefreshTooltipSafe()` на безопасный приоритет `SetUnit()` / `SetHyperlink()`
- [x] Заблокировать fallback в `RebuildFromTooltipInfo()` для unit tooltip, если safe refresh не сработал
- [x] Прогнать статическую проверку Lua и diff только по `RothTooltip`

## Проверка после правки

- [ ] `/reload` без ошибок `UnitPlayerControlled` / `GameTooltip_UnitColor`
- [ ] `MODIFIER_STATE_CHANGED` не роняет открытый unit tooltip
- [ ] `INSPECT_READY` не роняет открытый unit tooltip
- [ ] Применение настроек / profile reapply не роняет открытый unit tooltip

## Локально подтверждено

- `RefreshTooltipSafe()` теперь сначала пытается безопасно переоткрыть tooltip через `SetUnit()` / `SetHyperlink()`.
- Для `Enum.TooltipDataType.Unit` код больше не проваливается обратно в `RebuildFromTooltipInfo()` после неудачного safe refresh.
- `lookup_api("UnitPlayerControlled")` подтверждает, что API ждёт `UnitToken`, а не secret value в tainted execution.
- `npx -y luaparse _Addons/RothTooltip/Core.lua` прошёл успешно.
- `git diff --check -- _Addons/RothTooltip` прошёл без ошибок.
