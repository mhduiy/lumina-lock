#!/bin/bash
# 沙箱里真跑一遍 org.lumina.lock 的 DConfig 读写，验证「控制中心加视频 → 锁屏抽签读得到」
# 这条链路的存储环节。全部在临时目录里跑：不写系统目录、不碰用户真实配置。
#
# 写和读分成两个进程，和真机上「控制中心写、锁屏读」一致（DConfig 的值是退出时才落盘的）。
#
# 用法：
#   bash tests/dconfig-roundtrip/run.sh                  # 用仓库里的 schema
#   bash tests/dconfig-roundtrip/run.sh /usr/share/dsg/configs/org.lumina.lock/org.lumina.lock.json
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCHEMA="${1:-$REPO/data/dsg/configs/org.lumina.lock/org.lumina.lock.json}"
SANDBOX="$(mktemp -d /tmp/lumina-dconfig-XXXXXX)"
mkdir -p "$SANDBOX/usr/share/dsg/configs/org.lumina.lock" "$SANDBOX/home"
cp "$SCHEMA" "$SANDBOX/usr/share/dsg/configs/org.lumina.lock/org.lumina.lock.json"

BIN="$SANDBOX/dcfg-roundtrip"
echo "schema: $SCHEMA"
if ! g++ -std=c++17 -fPIC -o "$BIN" "$REPO/tests/dconfig-roundtrip/main.cpp" \
        $(pkg-config --cflags --libs dtk6core) 2>"$SANDBOX/build.log"; then
    echo "编译失败："; head -20 "$SANDBOX/build.log"; exit 1
fi

# meta 查找路径 = <localPrefix>/<DSG_DATA_DIRS 项>/configs/<appid>/<name>.json（字符串拼接），
# 所以 DSG_DATA_DIRS 填绝对形式、localPrefix 指到沙箱；值存储跟着 HOME 走。
# 必须锁成 FileBackend：否则会去问真机上跑着的 dde-dconfig-daemon，读到的就是真实配置。
run_step() {
    local mode="$1"
    echo "--- $mode"
    env HOME="$SANDBOX/home" \
        DSG_DATA_DIRS=/usr/share/dsg \
        DSG_DCONFIG_BACKEND_TYPE=FileBackend \
        DSG_DCONFIG_FILE_BACKEND_LOCAL_PREFIX="$SANDBOX" \
        "$BIN" "$mode" 2>&1
    return $?
}

rc=0
run_step defaults || rc=1
run_step write || rc=1
run_step read || rc=1
run_step clear || rc=1
run_step read-clear || rc=1

echo "--- exit $rc   沙箱: $SANDBOX"
exit $rc
