#!/usr/bin/env bash
# Checks an iOS .ipa and writes a Markdown report (stdout).
#   - structure: Payload/<App>.app
#   - Info.plist: bundle id, versions, executable, minimum iOS, orientations
#   - executable architectures (must contain arm64)
#   - game data (.pck) and compiled assets (icons) inside the bundle
#   - code signature, team, entitlements, embedded provisioning profile
# Runs on macOS (plutil, lipo, codesign, security). Exit code 0 when the
# structure is valid; the signature state is reported, never assumed.
#
# Usage: tools/verify_ipa.sh path/to/app.ipa [expected.bundle.id]
set -uo pipefail
IPA="$1"
EXPECT_ID="${2:-}"
FAIL=0
ok()   { echo "| $1 | ✅ $2 |"; }
bad()  { echo "| $1 | ❌ $2 |"; FAIL=1; }
note() { echo "| $1 | ⚠️ $2 |"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "## Проверка IPA: \`$(basename "$IPA")\`"
echo
echo "| Проверка | Результат |"
echo "|---|---|"
if [ ! -f "$IPA" ]; then bad "Файл" "не найден"; exit 1; fi
ok "Размер" "$(du -h "$IPA" | cut -f1) ($(stat -f%z "$IPA" 2>/dev/null || stat -c%s "$IPA") байт)"
ok "SHA-256" "\`$(shasum -a 256 "$IPA" 2>/dev/null | cut -d' ' -f1 || sha256sum "$IPA" | cut -d' ' -f1)\`"
if ! unzip -q "$IPA" -d "$TMP"; then bad "ZIP" "архив не распаковывается"; exit 1; fi
APP="$(ls -d "$TMP"/Payload/*.app 2>/dev/null | head -1)"
if [ -z "$APP" ]; then bad "Структура" "нет Payload/*.app"; exit 1; fi
ok "Структура" "Payload/$(basename "$APP")"
PL="$APP/Info.plist"
get() { plutil -extract "$1" raw -o - "$PL" 2>/dev/null; }
BID="$(get CFBundleIdentifier)"
if [ -n "$EXPECT_ID" ] && [ "$BID" != "$EXPECT_ID" ]; then bad "Bundle ID" "$BID (ожидался $EXPECT_ID)"; else ok "Bundle ID" "$BID"; fi
ok "Имя" "$(get CFBundleDisplayName) / $(get CFBundleName)"
ok "Версия" "$(get CFBundleShortVersionString) (сборка $(get CFBundleVersion))"
ok "Минимальная iOS" "$(get MinimumOSVersion)"
ORI="$(plutil -extract UISupportedInterfaceOrientations json -o - "$PL" 2>/dev/null)"
ok "Ориентации" "\`$ORI\`"
FAM="$(plutil -extract UIDeviceFamily json -o - "$PL" 2>/dev/null)"
ok "Семейство устройств" "\`$FAM\` (1 = iPhone, 2 = iPad)"
EXE="$APP/$(get CFBundleExecutable)"
if [ -f "$EXE" ]; then
  ARCHS="$(lipo -archs "$EXE" 2>/dev/null)"
  case " $ARCHS " in *" arm64 "*) ok "Архитектура" "$ARCHS";; *) bad "Архитектура" "${ARCHS:-не определена} (нужна arm64)";; esac
  ok "Исполняемый файл" "$(du -h "$EXE" | cut -f1)"
else
  bad "Исполняемый файл" "не найден"
fi
PCK="$(ls "$APP"/*.pck 2>/dev/null | head -1)"
if [ -n "$PCK" ]; then ok "Данные игры (.pck)" "$(basename "$PCK"), $(du -h "$PCK" | cut -f1)"; else bad "Данные игры (.pck)" "отсутствуют"; fi
if [ -f "$APP/Assets.car" ]; then ok "Иконки (Assets.car)" "есть"; else note "Иконки (Assets.car)" "нет"; fi
if [ -f "$APP/Launch Screen.storyboardc/Info.plist" ] || ls "$APP"/*.storyboardc >/dev/null 2>&1; then ok "Экран запуска" "есть"; else note "Экран запуска" "не найден"; fi

SIG="$(codesign -dv --verbose=4 "$APP" 2>&1)"
if echo "$SIG" | grep -q "not signed at all"; then
  note "Подпись" "**не подписан** — установить на произвольный iPhone нельзя"
  SIGNED=0
else
  SIGNED=1
  AUTH="$(echo "$SIG" | grep '^Authority=' | head -1 | cut -d= -f2-)"
  TEAM="$(echo "$SIG" | grep '^TeamIdentifier=' | cut -d= -f2-)"
  if codesign --verify --deep --strict "$APP" 2>"$TMP/verify.txt"; then
    ok "Подпись" "действительна: ${AUTH:-?}, команда ${TEAM:-?}"
  else
    bad "Подпись" "не проходит проверку: $(tr '\n' ' ' < "$TMP/verify.txt")"
  fi
  ENT="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert json -o - - 2>/dev/null)"
  ok "Entitlements" "\`${ENT:-нет}\`"
fi
PROF="$APP/embedded.mobileprovision"
if [ -f "$PROF" ]; then
  security cms -D -i "$PROF" > "$TMP/prof.plist" 2>/dev/null
  pget() { /usr/libexec/PlistBuddy -c "Print $1" "$TMP/prof.plist" 2>/dev/null; }
  NDEV="$(pget ProvisionedDevices | grep -c '^ ' || true)"
  ALL="$(pget ProvisionsAllDevices)"
  GTA="$(pget Entitlements:get-task-allow)"
  KIND="App Store / TestFlight"
  if [ "$ALL" = "true" ]; then KIND="Enterprise"; elif [ "$NDEV" -gt 0 ] && [ "$GTA" = "true" ]; then KIND="Development"; elif [ "$NDEV" -gt 0 ]; then KIND="Ad Hoc"; fi
  ok "Профиль" "«$(pget Name)», тип $KIND, команда $(pget TeamIdentifier:0), до $(pget ExpirationDate), устройств: $NDEV"
  PAPP="$(pget Entitlements:application-identifier)"
  case "$PAPP" in *".$BID"|*".*") ok "Профиль ↔ Bundle ID" "$PAPP";; *) bad "Профиль ↔ Bundle ID" "$PAPP не совпадает с $BID";; esac
else
  if [ "$SIGNED" = "1" ]; then bad "Профиль" "embedded.mobileprovision отсутствует"; else note "Профиль" "нет (сборка без подписи)"; fi
fi
echo
if [ "$FAIL" = "0" ]; then echo "Итог: структура IPA корректна."; else echo "Итог: **есть ошибки**."; fi
exit $FAIL
