#!/bin/bash
# 回归测试：锁屏 surface 必须能真正加载出来。
#
# 为什么要它：Surfaces 是「上锁时」才建的（ScreenManager::showAll → 加载
# qrc:/qml/LockScreen.qml）。所以离屏冒烟（只启动、不上锁）跑得再绿，也发现不了
# LockScreen.qml 里的 QML 错误——而那种错误的表现是「锁屏根本不出现」，也就是
# 屏幕实际没锁住。这个脚本真触发一次上锁（D-Bus Show），然后检查有没有加载错误。
#
# 用法：bash tests/lock-surface-load/run.sh [锁屏二进制路径]
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${1:-/usr/bin/lumina-lock}"
SCHEMA="$REPO/data/dsg/configs/org.lumina.lock/org.lumina.lock.json"
SB="$(mktemp -d /tmp/lumina-surface-XXXXXX)"
SVC=org.deepin.dde.LockFront1
OBJ=/org/deepin/dde/LockFront1

[ -x "$BIN" ] || { echo "没有锁屏二进制 $BIN"; exit 1; }
mkdir -p "$SB/usr/share/dsg/configs/org.lumina.lock" "$SB/home" "$SB/log"
cp "$SCHEMA" "$SB/usr/share/dsg/configs/org.lumina.lock/org.lumina.lock.json"

echo "sandbox: $SB"
echo "binary:  $BIN"
timeout 40 dbus-run-session -- bash -c "
    env HOME='$SB/home' DSG_DATA_DIRS=/usr/share/dsg \
        DSG_DCONFIG_BACKEND_TYPE=FileBackend \
        DSG_DCONFIG_FILE_BACKEND_LOCAL_PREFIX='$SB' \
        QT_QPA_PLATFORM=offscreen $BIN --daemon --test-exit-ms 9000 >'$SB/log/out.log' 2>&1 &
    APP=\$!
    sleep 3
    # 触发上锁：这才是会建 surface 的那条路径
    dbus-send --session --print-reply --dest=$SVC $OBJ ${SVC}.Show >/dev/null 2>&1
    sleep 4
    kill \$APP 2>/dev/null
    wait \$APP 2>/dev/null
" >/dev/null 2>&1

python3 - "$SB/log/out.log" <<'PY'
import re, sys, os
log = sys.argv[1]
txt = open(log, errors="replace").read() if os.path.exists(log) else ""
fails = []
def say(ok, what, detail=""):
    print(("  PASS " if ok else "  FAIL ") + what + (" " + detail if detail else ""))
    if not ok: fails.append(what)

# surface 加载失败会打这两类：加载失败本身，或具体 QML 错误
bad = re.findall(r"ScreenManager: failed to load[^\n]*\n(?:[^\n]*\n)?", txt)
if bad:
    print("  --- 加载错误原文 ---")
    for b in bad[:4]:
        print("   ", b.strip().replace("\n", " | "))

say(not bad, "LockScreen.qml 能加载（没有 ScreenManager: failed to load）")
say("Property value set multiple times" not in txt, "没有「同一属性赋值多次」这类 QML 错误")
say("Cannot assign" not in txt and "Type .* unavailable" not in txt, "没有类型/属性不可用的 QML 错误")
# 反面证据：确实走到过 surface（否则上面的"没错误"毫无意义）
say("ScreenManager" in txt, "确实触发了 surface 相关路径（否则断言不算数）")

print("全部通过" if not fails else f"有 {len(fails)} 项失败")
sys.exit(0 if not fails else 1)
PY
rc=$?
echo "--- exit $rc   日志: $SB/log/out.log"
exit $rc
