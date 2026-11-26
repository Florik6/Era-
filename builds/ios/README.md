# builds/ios

Здесь должен лежать `ERA_Ascension_iOS.ipa`. **Сейчас файла нет.**

IPA собирается только на macOS. Workflow `.github/workflows/ios.yml` положит сюда файл и отчёты проверки,
когда его macOS-задача сможет запуститься. До сих пор аккаунту GitHub не выдавалась macOS-машина.
Без секретов подписи появится `ERA_Ascension_iOS_unsigned.ipa`: такой файл нельзя установить на произвольный iPhone.

Статус, причины и варианты — в `reports/IOS_BUILD_REPORT.md`.
