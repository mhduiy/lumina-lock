#!/bin/bash
# 随机动态壁纸进程级 e2e：真跑锁屏二进制，验证「从配置读池 → 抽签 → 池过滤 → 回退」。
# 抽签规则本身（不连续重复、单条池、空池）由 tests/draw-rule 直接单测覆盖。
#
# 全部在临时目录里跑：schema 和值存储都在沙箱，不碰用户真实配置，也不装任何东西。
#
# 注意：抽签日志是 qInfo，dtk6 默认丢弃，必须 QT_LOGGING_RULES="default.info=true" 才可见。
# 另注：文件后端不会为外部写入发 valueChanged（真机上那条 live-reload 路径靠 DBus 守护
# 进程发信号），所以这里不做「改配置立刻重抽」的断言。
#
# 用法：bash tests/random-draw-e2e/run.sh [锁屏二进制路径]
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${1:-$REPO/obj-x86_64-linux-gnu/lumina-lock}"
SCHEMA="$REPO/data/dsg/configs/org.lumina.lock/org.lumina.lock.json"
SB="$(mktemp -d /tmp/lumina-draw-XXXXXX)"

V1=/usr/share/wallpapers/deepin-livewallpapers/default.mp4
V2=/usr/share/dde-introduction/professional.mp4
V3=/usr/share/dde-introduction/demo.mp4
GONE=/tmp/lumina-not-a-real-video.mp4
for f in "$V1" "$V2" "$V3"; do
    [ -r "$f" ] || { echo "缺少测试视频 $f，跳过"; exit 0; }
done
[ -x "$BIN" ] || { echo "找不到锁屏二进制 $BIN（先构建）"; exit 1; }

mkdir -p "$SB/usr/share/dsg/configs/org.lumina.lock"
cp "$SCHEMA" "$SB/usr/share/dsg/configs/org.lumina.lock/org.lumina.lock.json"

# 用 DConfig 库本身写配置（就是控制中心的写法）；手工构造缓存 JSON 不行，列表键读不出来。
PROBE="$SB/probe"
if ! g++ -std=c++17 -fPIC -o "$PROBE" "$REPO/tests/dconfig-roundtrip/main.cpp" \
        $(pkg-config --cflags --libs dtk6core) 2>"$SB/probe-build.log"; then
    echo "探针编译失败："; head -20 "$SB/probe-build.log"; exit 1
fi

cfg_env() {
    env HOME="$SB/home" DSG_DATA_DIRS=/usr/share/dsg \
        DSG_DCONFIG_BACKEND_TYPE=FileBackend \
        DSG_DCONFIG_FILE_BACKEND_LOCAL_PREFIX="$SB" "$@"
}

write_config() { # $1 = type, $2... = pool paths
    local type="$1"; shift
    cfg_env "$PROBE" write-args "$type" "$@" >/dev/null 2>&1
}

run_lock() { # $1 = 日志文件
    # 必须跑在独立的 dbus session 里：直接跑会去抢真机的
    # org.deepin.dde.LockFront1，抢不到时它会向正在运行的锁屏转发 Show()——
    # 那会把用户的屏幕锁上，而且这一轮不会有抽签日志（测试会莫名其妙少几条）。
    timeout 30 dbus-run-session -- bash -c "
        env HOME='$SB/home' DSG_DATA_DIRS=/usr/share/dsg \
            DSG_DCONFIG_BACKEND_TYPE=FileBackend \
            DSG_DCONFIG_FILE_BACKEND_LOCAL_PREFIX='$SB' \
            QT_QPA_PLATFORM=offscreen QT_LOGGING_RULES='default.info=true' \
            '$BIN' --test-exit-ms 3000 >'$1' 2>&1
    "
    return 0
}

echo "sandbox: $SB"

echo
echo "########## 1) 池 = 3 个真实视频 + 1 个失效路径（连跑 5 次）##########"
write_config video-random "$V1" "$V2" "$V3" "$GONE"
for i in 1 2 3 4 5; do
    run_lock "$SB/run$i.log"
    echo "  --- 第 $i 次: $(grep -oE 'random draw \S+' "$SB/run$i.log" | sed 's|.*/||' | tr '\n' ' ')"
done

echo
echo "########## 2) 池里全是失效路径（期望回退内置壁纸、不抽签）##########"
write_config video-random "$GONE" /tmp/also-missing.mp4
run_lock "$SB/run4.log"
echo "    抽签次数: $(grep -cE 'random draw' "$SB/run4.log")"

echo
echo "########## 3) 固定视频类型 video（期望不抽签）##########"
write_config video "$V1" "$V2" "$V3"
run_lock "$SB/run5.log"
echo "    抽签次数: $(grep -cE 'random draw' "$SB/run5.log")"

echo
echo "########## 4) 空池（期望回退内置壁纸、不抽签）##########"
write_config video-random
run_lock "$SB/run6.log"
echo "    抽签次数: $(grep -cE 'random draw' "$SB/run6.log")"

echo
echo "########## 5) 池里只有 1 个视频（边界：应始终是它且不崩）##########"
write_config video-random "$V2"
run_lock "$SB/run7.log"
echo "  --- $(grep -oE 'random draw \S+' "$SB/run7.log" | sed 's|.*/||' | tr '\n' ' ')"

echo
python3 - "$SB" "$V1" "$V2" "$V3" "$GONE" <<'PY'
import os, re, sys
sb, v1, v2, v3, gone = sys.argv[1:6]
good = {v1, v2, v3}
fails = []
def say(ok, what, detail=""):
    print(("  PASS " if ok else "  FAIL ") + what + (" " + detail if detail else ""))
    if not ok: fails.append(what)
def draws(name):
    p = os.path.join(sb, name)
    return re.findall(r"Wallpaper: random draw (\S+)", open(p, errors="replace").read()) if os.path.exists(p) else []

d = sum((draws(f"run{i}.log") for i in range(1, 6)), [])
say(len(d) >= 5, "每次上锁都抽一次签（5 次运行）", f"-> {len(d)} 次")
say(all(x in good for x in d), "抽中的都是真实存在的文件（失效路径从未被抽中）",
    f"-> {sorted({os.path.basename(x) for x in d})}")
# 5 次里至少出现 2 个不同结果；单次抽签本来就是随机的，样本太少会偶发误报
say(len(set(d)) > 1, "跨运行确实是随机的（5 次里不止一个结果）", f"-> {len(set(d))} 个不同")

d7 = draws("run7.log")
say(d7 and all(x == v2 for x in d7), "单条池：始终抽它、不崩",
    f"-> {sorted({os.path.basename(x) for x in d7})}")

say(draws("run4.log") == [], "池全失效时不抽签（回退内置壁纸）")
say(draws("run5.log") == [], "固定视频类型不抽签")
say(draws("run6.log") == [], "空池不抽签（回退内置壁纸）")

print("全部通过" if not fails else f"有 {len(fails)} 项失败")
sys.exit(0 if not fails else 1)
PY
rc=$?
echo "--- exit $rc   沙箱: $SB"
exit $rc
