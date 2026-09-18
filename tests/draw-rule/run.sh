#!/bin/bash
# 抽签规则单测：直接编译 WallpaperConfig + WallpaperManager，在沙箱里抽多次，
# 验证「池过滤 / 不连续重复 / 单条池 / 空池回退」。不装东西、不碰用户配置。
#
# 用法：bash tests/draw-rule/run.sh
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCHEMA="$REPO/data/dsg/configs/org.lumina.lock/org.lumina.lock.json"
SB="$(mktemp -d /tmp/lumina-drawrule-XXXXXX)"

V1=/usr/share/wallpapers/deepin-livewallpapers/default.mp4
V2=/usr/share/dde-introduction/professional.mp4
V3=/usr/share/dde-introduction/demo.mp4
GONE=/tmp/lumina-not-a-real-video.mp4
for f in "$V1" "$V2" "$V3"; do
    [ -r "$f" ] || { echo "缺少测试视频 $f，跳过"; exit 0; }
done

mkdir -p "$SB/usr/share/dsg/configs/org.lumina.lock"
cp "$SCHEMA" "$SB/usr/share/dsg/configs/org.lumina.lock/org.lumina.lock.json"

PROBE="$SB/probe"
BIN="$SB/draw-rule"
CFLAGS="$(pkg-config --cflags --libs Qt6Core dtk6core)"
MOC=/usr/lib/qt6/libexec/moc   # 不要用 /usr/bin/moc，那是 qtchooser 包装（找不到 Qt）
[ -x "$MOC" ] || MOC="$(command -v moc6 || command -v moc)"
echo "sandbox: $SB"
# Q_OBJECT 类要 moc：单独编译这两个类就得自己生成 moc 源。
"$MOC" "$REPO/src/wallpaper/WallpaperConfig.h" -o "$SB/moc_WallpaperConfig.cpp" || exit 1
"$MOC" "$REPO/src/wallpaper/WallpaperManager.h" -o "$SB/moc_WallpaperManager.cpp" || exit 1
if ! g++ -std=c++17 -fPIC -I"$REPO/src/wallpaper" -I"$SB" -o "$BIN" "$REPO/tests/draw-rule/main.cpp" \
        "$REPO/src/wallpaper/WallpaperConfig.cpp" "$REPO/src/wallpaper/WallpaperManager.cpp" \
        "$SB/moc_WallpaperConfig.cpp" "$SB/moc_WallpaperManager.cpp" \
        $CFLAGS 2>"$SB/build.log"; then
    echo "编译失败："; head -25 "$SB/build.log"; exit 1
fi
if ! g++ -std=c++17 -fPIC -o "$PROBE" "$REPO/tests/dconfig-roundtrip/main.cpp" $CFLAGS \
        2>"$SB/probe-build.log"; then
    echo "探针编译失败："; head -20 "$SB/probe-build.log"; exit 1
fi

cfg_env() {
    env HOME="$SB/home" DSG_DATA_DIRS=/usr/share/dsg \
        DSG_DCONFIG_BACKEND_TYPE=FileBackend \
        DSG_DCONFIG_FILE_BACKEND_LOCAL_PREFIX="$SB" "$@"
}
set_pool() { cfg_env "$PROBE" write-args "$@" >/dev/null 2>&1; }

rc=0
echo "########## 1) 池 = 3 个真实视频 + 1 个失效路径 ##########"
set_pool video-random "$V1" "$V2" "$V3" "$GONE"
cfg_env "$BIN" multi || rc=1

echo
echo "########## 2) 池里只有 1 个视频 ##########"
set_pool video-random "$V2"
cfg_env "$BIN" single || rc=1

echo
echo "########## 3) 空池 ##########"
set_pool video-random
cfg_env "$BIN" empty || rc=1

echo
echo "########## 4) 池里全是失效路径 ##########"
set_pool video-random "$GONE" /tmp/also-missing.mp4
cfg_env "$BIN" allgone || rc=1

echo
echo "########## 5) 旧 schema（没有 videoPaths / clockPosition*）：必须回退不崩 ##########"
mkdir -p "$SB/old/usr/share/dsg/configs/org.lumina.lock"
python3 - "$SCHEMA" "$SB/old/usr/share/dsg/configs/org.lumina.lock/org.lumina.lock.json" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
for k in ("videoPaths", "clockPositionX", "clockPositionY"):
    j["contents"].pop(k, None)
json.dump(j, open(sys.argv[2], "w"), ensure_ascii=False, indent=4)
PY
env HOME="$SB/old/home" DSG_DATA_DIRS=/usr/share/dsg \
    DSG_DCONFIG_BACKEND_TYPE=FileBackend \
    DSG_DCONFIG_FILE_BACKEND_LOCAL_PREFIX="$SB/old" \
    "$BIN" oldschema || rc=1

echo
echo "--- exit $rc   沙箱: $SB"
exit $rc
