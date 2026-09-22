#!/bin/bash
# 回归测试：屏幕分辨率变化后，锁屏和电源页必须跟着变。
#
# 为什么要它：这两个页面的窗口是按屏幕尺寸摆的，而且是 override-redirect（无边框、
# 不受窗口管理器管），所以窗口管理器不会替它们改尺寸。屏幕一变，surface 就继续画在
# 旧尺寸里 —— 看上去就是「页面没跟着变」。这条路径只在真的发生屏幕变化时才走，
# 离屏冒烟（只启动、不上锁）永远碰不到。
#
# 做法：Xvfb 里再嵌一个 Xephyr，得到一台能切分辨率的 X server，用 xrandr 切模式
# （就是用户改分辨率时发生的那件事），再用 xwininfo 量窗口在 X server 里的真实大小。
# 全程不碰当前桌面。
#
# 用法：bash tests/screen-geometry/run.sh [锁屏二进制路径]
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${1:-$REPO/build/lumina-lock}"
WALL="$REPO/assets/wallpapers/default.jpg"
XVFB_DISPLAY=:91
NESTED_DISPLAY=:92
OUTPUT=default
SB="$(mktemp -d /tmp/lumina-geometry-XXXXXX)"

for tool in Xvfb Xephyr xrandr xwininfo xdpyinfo dbus-run-session; do
    command -v "$tool" >/dev/null || { echo "缺少 $tool，跳过"; exit 0; }
done
[ -x "$BIN" ] || { echo "找不到锁屏二进制 $BIN（先构建）"; exit 1; }
[ -r "$WALL" ] || { echo "缺少测试壁纸 $WALL"; exit 1; }

echo "sandbox: $SB"
echo "binary:  $BIN"

cleanup() {
    [ -n "${XVFB_PID:-}" ] && kill "$XVFB_PID" 2>/dev/null
    [ -n "${XEPHYR_PID:-}" ] && kill "$XEPHYR_PID" 2>/dev/null
    wait 2>/dev/null
}
trap cleanup EXIT

Xvfb "$XVFB_DISPLAY" -screen 0 1600x1200x24 >"$SB/xvfb.log" 2>&1 &
XVFB_PID=$!
for _ in $(seq 1 50); do
    DISPLAY="$XVFB_DISPLAY" xdpyinfo >/dev/null 2>&1 && break
    sleep 0.2
done
DISPLAY="$XVFB_DISPLAY" xdpyinfo >/dev/null 2>&1 \
    || { echo "Xvfb 没起来（$XVFB_DISPLAY 被占用？）"; exit 1; }

DISPLAY="$XVFB_DISPLAY" Xephyr "$NESTED_DISPLAY" -screen 1600x1200 -resizeable -noreset \
    >"$SB/xephyr.log" 2>&1 &
XEPHYR_PID=$!
for _ in $(seq 1 50); do
    DISPLAY="$NESTED_DISPLAY" xdpyinfo >/dev/null 2>&1 && break
    sleep 0.2
done
DISPLAY="$NESTED_DISPLAY" xdpyinfo >/dev/null 2>&1 \
    || { echo "Xephyr 没起来（$NESTED_DISPLAY 被占用？）"; exit 1; }

for size in 1024x768 1400x1050; do
    DISPLAY="$NESTED_DISPLAY" xrandr --output "$OUTPUT" --mode "$size" >/dev/null 2>&1 || true
done
DISPLAY="$NESTED_DISPLAY" xrandr --output "$OUTPUT" --mode 1024x768 >/dev/null 2>&1 \
    || { echo "Xephyr 的 $OUTPUT 输出不支持 1024x768，跳过"; exit 0; }
DISPLAY="$NESTED_DISPLAY" xrandr --output "$OUTPUT" --mode 1600x1200 >/dev/null 2>&1 || true

cat >"$SB/inner.sh" <<'INNER'
#!/bin/bash
export DISPLAY="$NESTED_DISPLAY"
geom() { xwininfo -root -tree | grep -i "Lumina $1" | awk '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+x[0-9]+\+/) print $i}'; }
setmode() { xrandr --output "$OUTPUT" --mode "$1" >/dev/null 2>&1; sleep 3; }

"$BIN" --wallpaper "$WALL" --test-exit-ms 60000 >"$OUT/app.log" 2>&1 &
APP=$!
sleep 6

failed=0
check() { # $1 = what, $2 = expected geometry
    local got; got="$(geom "$1")"
    echo "  ${1}: ${got:-<无窗口>}（期望 ${2}）"
    [ "$got" = "$2" ] || { echo "    FAIL：${1} 没有跟着变"; failed=1; }
}

echo "模式 1024x768（锁屏）"
setmode 1024x768
check Lock 1024x768+0+0

echo "模式 1024x768（电源页，开着的情况下改分辨率）"
echo "  Show: $(dbus-send --session --print-reply --dest=org.deepin.dde.ShutdownFront1 \
    /org/deepin/dde/ShutdownFront1 org.deepin.dde.ShutdownFront1.Show 2>&1 | head -1)"
sleep 3
check Power 1024x768+0+0

echo "模式 1400x1050（锁屏 + 电源页）"
setmode 1400x1050
check Lock 1400x1050+0+0
check Power 1400x1050+0+0

kill "$APP" 2>/dev/null
wait "$APP" 2>/dev/null
exit "$failed"
INNER
chmod +x "$SB/inner.sh"

NESTED_DISPLAY="$NESTED_DISPLAY" OUTPUT="$OUTPUT" BIN="$BIN" WALL="$WALL" OUT="$SB" \
    timeout 120 dbus-run-session -- bash "$SB/inner.sh"
status=$?

if [ "$status" -eq 0 ]; then
    echo "PASS：分辨率变化后锁屏与电源页都跟得上"
else
    echo "FAIL：见上面的尺寸对比" >&2
    echo "--- app.log（ScreenManager 部分）" >&2
    grep ScreenManager "$SB/app.log" >&2
fi
exit "$status"
