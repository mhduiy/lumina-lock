#!/bin/bash
# 探针：加载真的 VideoListDialog.qml（桩 dccData，2 条视频），看列表是否渲染出来。
# 用法：bash tests/videolist-dialog/run.sh
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SB="$(mktemp -d /tmp/lumina-dialog-XXXXXX)"
MOC=/usr/lib/qt6/libexec/moc
[ -x "$MOC" ] || MOC="$(command -v moc6 || command -v moc)"

"$MOC" "$REPO/tests/videolist-dialog/main.cpp" -o "$SB/main.moc" || exit 1
if ! g++ -std=c++17 -fPIC -I"$SB" -o "$SB/probe" "$REPO/tests/videolist-dialog/main.cpp" \
        $(pkg-config --cflags --libs Qt6Qml Qt6Quick) 2>"$SB/build.log"; then
    echo "编译失败："; head -20 "$SB/build.log"; exit 1
fi

echo "sandbox: $SB"
env QT_QPA_PLATFORM=offscreen "$SB/probe" "$REPO/dcc-plugin/qml/VideoListDialog.qml" 2>&1 \
    | grep -viE "^This plugin does not support|qt.qpa|libpng" | sed 's/^/  /'
rc=${PIPESTATUS[0]}
echo "--- exit $rc   沙箱: $SB"
exit $rc
