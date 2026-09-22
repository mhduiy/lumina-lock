#!/bin/bash
# 回归测试：锁屏必须把上锁/解锁状态报给会话管理器。
#
# 为什么要它：dde-quick-login 用 `-lq` 拉起锁屏后，只等
# org.deepin.dde.SessionManager1 的 LockedChanged(true)——收到才给 systemd 发
# READY=1 并停掉「60 秒还没锁上就把用户登出」的定时器。锁屏如果不报，会话在 DDE
# 眼里一直是未锁，快速登录就被白白登出。这条跨进程契约编译期和离屏冒烟都看不出来，
# 所以在这里钉住：让一个 stub 顶替会话管理器，看它到底收到什么。
#
# stub 必须是独立进程：LockSession 走 QDBusInterface，introspection 是同步调用，
# 自己调自己会死锁。所以这里跑同一个二进制的两个角色。
#
# 用法：bash tests/lock-state-report/run.sh [测试二进制路径]
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${1:-$REPO/build/lumina-lock-state-test}"
SB="$(mktemp -d /tmp/lumina-lockstate-XXXXXX)"

[ -x "$BIN" ] || { echo "找不到测试二进制 $BIN（先构建 lumina-lock-state-test）"; exit 1; }

cat >"$SB/expected.txt" <<'EOF'
SetLocked(true)
SetLocked(false)
SetLocked(true)
SetLocked(false)
EOF

echo "sandbox: $SB"
echo "binary:  $BIN"

timeout 40 dbus-run-session -- bash -c "
    '$BIN' --stub >'$SB/stub.log' 2>&1 &
    STUB=\$!
    for _ in \$(seq 1 50); do
        grep -q 'stub ready' '$SB/stub.log' && break
        sleep 0.1
    done
    if ! grep -q 'stub ready' '$SB/stub.log'; then
        echo 'stub 没起来：' >&2
        cat '$SB/stub.log' >&2
        kill \$STUB 2>/dev/null
        exit 1
    fi
    '$BIN' >'$SB/driver.log' 2>&1
    echo \"driver exit=\$?\" >>'$SB/driver.log'
    kill \$STUB 2>/dev/null
    wait \$STUB 2>/dev/null
" >/dev/null 2>&1

grep '^SetLocked' "$SB/stub.log" >"$SB/actual.txt" 2>/dev/null

if grep -q 'driver done' "$SB/driver.log" 2>/dev/null \
   && diff -u "$SB/expected.txt" "$SB/actual.txt"; then
    echo "PASS：会话管理器按顺序收到 4 次上报（启动 true、解锁 false、上锁 true、解锁 false）"
    exit 0
fi

echo "FAIL：上报序列不对" >&2
echo "--- stub.log" >&2
cat "$SB/stub.log" >&2
echo "--- driver.log" >&2
cat "$SB/driver.log" >&2
exit 1
