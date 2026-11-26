#!/usr/bin/env bash
# Exports the official Godot iOS Xcode project into exports/ios_xcode/.
#
# Godot refuses to write the Xcode project without an App Store Team ID, but
# the repository must not carry account data. The Team ID is therefore taken
# from the environment (CI secret IOS_TEAM_ID) and injected into a temporary
# copy of export_presets.cfg; the original file is always restored.
#
# Without IOS_TEAM_ID the placeholder "UNSIGNED00" is used: the project is
# complete and builds with code signing disabled, but nothing signed with it
# can be installed on an arbitrary iPhone.
#
# Usage: tools/export_ios.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-release}"
TEAM="${IOS_TEAM_ID:-UNSIGNED00}"
GODOT="${GODOT:-godot}"
OUT="exports/ios_xcode"

BACKUP="$(mktemp)"
cp export_presets.cfg "$BACKUP"
restore() { cp "$BACKUP" export_presets.cfg; rm -f "$BACKUP"; }
trap restore EXIT

python3 - "$TEAM" "${IOS_PROFILE_UUID:-}" "${IOS_PROFILE_NAME:-}" "${IOS_EXPORT_METHOD:-}" "${IOS_SIGN_IDENTITY:-}" "${IOS_BUNDLE_ID:-}" <<'EOF'
import sys
team, uuid, name, method, ident, bundle = sys.argv[1:7]
p = 'export_presets.cfg'
s = open(p).read()
head, sep, ios = s.partition('[preset.2]')
assert sep, 'iOS preset missing'
def put(key, val):
    global ios
    old = next(l for l in ios.splitlines() if l.startswith(key + '='))
    ios = ios.replace(old, '%s=%s' % (key, val), 1)
put('application/app_store_team_id', '"%s"' % team)
methods = {'app-store': 0, 'development': 1, 'ad-hoc': 2, 'enterprise': 3}
if method:
    put('application/export_method_release', str(methods[method]))
if uuid:
    put('application/provisioning_profile_uuid_release', '"%s"' % uuid)
if name:
    put('application/provisioning_profile_specifier_release', '"%s"' % name)
if ident:
    put('application/code_sign_identity_release', '"%s"' % ident)
if bundle:
    put('application/bundle_identifier', '"%s"' % bundle)
open(p, 'w').write(head + sep + ios)
EOF

rm -rf "$OUT"
mkdir -p "$OUT"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . "--export-$MODE" "iOS" "$OUT/ERA_Ascension.ipa"
test -d "$OUT/ERA_Ascension.xcodeproj" || { echo "Xcode project was not produced" >&2; exit 1; }
echo "Xcode project: $OUT/ERA_Ascension.xcodeproj (team: $TEAM)"
