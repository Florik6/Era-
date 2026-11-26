# Xcode-проект iOS (официальный экспорт Godot 4.7.1)

Создан командой `tools/export_ios.sh release` (пресет «iOS» в `export_presets.cfg`).

В репозитории лежат сам проект (`ERA_Ascension.xcodeproj`, папка `ERA_Ascension/` с Info.plist,
иконками, экраном запуска) и данные игры `ERA_Ascension.pck`. Библиотеки движка
(`ERA_Ascension.xcframework`, `MoltenVK.xcframework` и др., ~370 МБ) берутся без изменений из
официального шаблона Godot iOS и в git не хранятся — `tools/export_ios.sh` создаёт их заново.

Собрать IPA можно только на macOS с Xcode. Это делает workflow `.github/workflows/ios.yml`
на облачном macOS-сборщике GitHub Actions. Подробности и статус — в `reports/IOS_BUILD_REPORT.md`.

`DEVELOPMENT_TEAM = UNSIGNED00` — заглушка: настоящий Team ID подставляется только в CI
из секрета `IOS_TEAM_ID`.
