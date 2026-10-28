#!/bin/bash
# Real QML/input test in temporary HOME + FileBackend + named offscreen screen.
# Run with: bash tests/wake-password/run.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$REPO/build"
SB="$(mktemp -d "$REPO/build/wake-password-XXXXXX")"
mkdir -p "$SB/usr/share/dsg/configs/org.lumina.lock" "$SB/home"
cp "$REPO/data/dsg/configs/org.lumina.lock/org.lumina.lock.json" \
   "$SB/usr/share/dsg/configs/org.lumina.lock/org.lumina.lock.json"

sources=("$REPO/tests/wake-password/main.cpp")
for unit in appearance/AppearanceConfig auth/PamAuthenticator power/PowerSession \
            screen/ScreenManager session/LockSession wallpaper/WallpaperManager; do
    moc="$SB/moc_${unit##*/}.cpp"
    /usr/lib/qt6/libexec/moc "$REPO/src/$unit.h" -o "$moc"
    sources+=("$REPO/src/$unit.cpp" "$moc")
done
flags="$(pkg-config --cflags --libs Qt6Quick Qt6Multimedia Qt6DBus Qt6Test dtk6core)"
read -r -a flags <<<"$flags"
"${CXX:-/usr/bin/g++}" -std=c++17 -fPIC -DDSS_SNIPE=1 -I"$REPO/src" \
    "${sources[@]}" "${flags[@]}" -lpam -lxcb -o "$SB/wake-password"
mkdir -p "$SB/stub" "$SB/legacy/usr/share/dsg/configs/org.lumina.lock" "$SB/legacy/home"
printf '#pragma once\n#define DCC_FACTORY_CLASS(classname)\n' > "$SB/stub/dccfactory.h"
/usr/lib/qt6/libexec/moc "$REPO/dcc-plugin/src/luminalock.h" -o "$SB/luminalock.moc"
"${CXX:-/usr/bin/g++}" -std=c++17 -fPIC -I"$REPO/dcc-plugin/src" -I"$SB" -I"$SB/stub" \
    "$REPO/tests/wake-password/settings.cpp" "$REPO/dcc-plugin/src/luminalock.cpp" \
    "${flags[@]}" -o "$SB/wake-settings"
python3 - "$REPO/data/dsg/configs/org.lumina.lock/org.lumina.lock.json" \
    "$SB/legacy/usr/share/dsg/configs/org.lumina.lock/org.lumina.lock.json" <<'PY'
import json, sys
with open(sys.argv[1]) as source:
    schema = json.load(source)
schema["contents"].pop("wakeFillPassword")
with open(sys.argv[2], "w") as target:
    json.dump(schema, target)
PY
printf '%s\n' '{"screens":[{"name":"WakeTestScreen","x":0,"y":0,"width":1280,"height":720,"logicalDpi":96,"logicalBaseDpi":96,"dpr":1}]}' > "$SB/offscreen.json"
echo "sandbox: $SB"
run() {
    local prefix="$1"; shift
    timeout 20 env HOME="$prefix/home" DSG_DATA_DIRS=/usr/share/dsg \
        DSG_DCONFIG_BACKEND_TYPE=FileBackend DSG_DCONFIG_FILE_BACKEND_LOCAL_PREFIX="$prefix" \
        QT_QPA_PLATFORM="offscreen:configfile=$SB/offscreen.json" QT_QPA_OFFSCREEN_NO_GLX=1 \
        QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software LUMINA_POWER_DRY_RUN=1 \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$SB/no-session-bus" \
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=$SB/no-system-bus" "$@"
}
rc=0
run "$SB" "$SB/wake-password" "$REPO" || rc=1
run "$SB" "$SB/wake-settings" "$REPO" || rc=1
run "$SB/legacy" "$SB/wake-settings" "$REPO" missing || rc=1
exit "$rc"
