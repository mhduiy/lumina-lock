#!/bin/bash
# 插件后端「添加视频」回归测试：单独编译 dcc-plugin/src/luminalock.cpp（用 dccfactory.h 替身），
# 在沙箱里跑两种 schema：
#   * 新 schema（含 videoPaths）  -> 添加成功、落盘、类型切到 video-random、删空回退
#   * 旧 schema（去掉 videoPaths）-> 必须明确失败并给出原因（用户机器上的真实状态）
# 不装东西、不碰用户真实配置。
#
# 用法：bash tests/plugin-add/run.sh
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCHEMA="$REPO/data/dsg/configs/org.lumina.lock/org.lumina.lock.json"
SB="$(mktemp -d /tmp/lumina-pluginadd-XXXXXX)"

V1=/usr/share/wallpapers/deepin-livewallpapers/default.mp4
[ -r "$V1" ] || { echo "缺少测试视频 $V1，跳过"; exit 0; }

# 沙箱骨架：新 schema 与"去掉新键"的旧 schema 各一份
mkdir -p "$SB/new/usr/share/dsg/configs/org.lumina.lock" "$SB/old/usr/share/dsg/configs/org.lumina.lock"
cp "$SCHEMA" "$SB/new/usr/share/dsg/configs/org.lumina.lock/org.lumina.lock.json"
python3 - "$SCHEMA" "$SB/old/usr/share/dsg/configs/org.lumina.lock/org.lumina.lock.json" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
j = json.load(open(src))
for k in ("videoPaths", "clockPositionX", "clockPositionY"):
    j["contents"].pop(k, None)
json.dump(j, open(dst, "w"), ensure_ascii=False, indent=4)
print("旧 schema 的键:", sorted(j["contents"]))
PY

# dccfactory.h 替身（真货来自 dde-control-center-dev，会把类注册成插件；单测不需要注册）
mkdir -p "$SB/stub"
cat > "$SB/stub/dccfactory.h" <<'EOF'
#pragma once
// 单测替身：真货由 dde-control-center-dev 提供，DCC_FACTORY_CLASS 会生成插件注册类。
// 这里不需要注册，展开成空即可。
#define DCC_FACTORY_CLASS(classname)
EOF

MOC=/usr/lib/qt6/libexec/moc
[ -x "$MOC" ] || MOC="$(command -v moc6 || command -v moc)"
"$MOC" "$REPO/dcc-plugin/src/luminalock.h" -o "$SB/luminalock.moc" || exit 1

CFLAGS="$(pkg-config --cflags --libs Qt6Core dtk6core)"
BIN="$SB/plugin-add"
echo "sandbox: $SB"
if ! g++ -std=c++17 -fPIC -I"$SB/stub" -I"$REPO/dcc-plugin/src" -I"$SB" \
        -o "$BIN" "$REPO/tests/plugin-add/main.cpp" "$REPO/dcc-plugin/src/luminalock.cpp" \
        $CFLAGS 2>"$SB/build.log"; then
    echo "编译失败："; head -25 "$SB/build.log"; exit 1
fi

run() { # $1 = schema 目录名(new/old), 其余 = 参数
    local which="$1"; shift
    env HOME="$SB/$which/home" DSG_DATA_DIRS=/usr/share/dsg \
        DSG_DCONFIG_BACKEND_TYPE=FileBackend \
        DSG_DCONFIG_FILE_BACKEND_LOCAL_PREFIX="$SB/$which" \
        "$BIN" "$@" 2>&1
}

rc=0
echo
echo "########## 1) 新 schema：添加 -> 另一个进程读回 -> 删空回退 ##########"
run new add-ok "$V1" || rc=1
run new read-back "$V1" || rc=1
run new add-then-remove "$V1" || rc=1

echo
echo "########## 2) 旧 schema（没有 videoPaths）：必须明确失败 ##########"
run old add-nokey "$V1" || rc=1

echo
echo "########## 3) 读不了的文件：必须失败并说明 ##########"
run new add-badfile /tmp/lumina-no-such-file.mp4 || rc=1

echo
echo "--- exit $rc   沙箱: $SB"
exit $rc
