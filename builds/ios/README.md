# builds/ios

`ERA_Ascension_iOS_unsigned.ipa` — сборка 0.12.0 (15) из итогового кода, собрана в GitHub Actions на macOS
(Xcode 26.6, запуск №6) из официального Xcode-проекта Godot 4.7.1. SHA-256 — в `SHA256SUMS.txt`, проверка структуры —
`reports/ios_ci/IPA_VERIFICATION.md`.

**Файл не подписан.** Установить его на произвольный iPhone нельзя. Варианты:
- переподписать своим Apple ID (AltStore, Sideloadly) или открыть Xcode-проект на своём Mac и запустить на своём iPhone;
- добавить секреты подписи в GitHub (см. `reports/IOS_BUILD_REPORT.md`, раздел 4) — тогда workflow соберёт подписанный `ERA_Ascension_iOS.ipa`.

Смоук-тест в iOS Simulator (iPhone 17 Pro / iOS 26.5) пройден: меню, мир, бой, сохранение, загрузка —
`reports/ios_ci/SIMULATOR_SMOKE.md`. Это проверка в симуляторе; на физическом iPhone игра не проверялась.
