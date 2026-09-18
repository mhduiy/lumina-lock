#!/bin/bash
# 控制中心插件 QML 探针：装包之前先验证插件的 QML 结构真的能建起来。
#
# 为什么需要它：插件 QML 里的结构错误不会只报一行——主对象建不出来时，控制中心里
# **整个模块连图标一起消失**，日志里只有一句 MainObjErr。等装完再从日志里翻，代价
# 太大；这个脚本直接拿 qml 工具把插件的 QML 模块加载起来跑一遍。
#
# 用法（参数是 plugins_v1.1 目录：里面按插件名分子目录）：
#   bash tests/plugin-qml-probe/run.sh obj-x86_64-linux-gnu/lib/plugins_v1.1
#   bash tests/plugin-qml-probe/run.sh /usr/lib/x86_64-linux-gnu/dde-control-center/plugins_v1.1
#   # 也有直接跑包里那份的时候：
#   dpkg-deb -x lumina-lock_*.deb /tmp/newdeb && \
#     bash tests/plugin-qml-probe/run.sh /tmp/newdeb/usr/lib/x86_64-linux-gnu/dde-control-center/plugins_v1.1
#
# 退出码：0 = 全过；1 = 有探针失败。
set -u

DIR="${1:-}"
if [ -z "$DIR" ]; then
    echo "用法: bash $0 <plugins_v1.1 目录>" >&2
    exit 2
fi
if [ ! -d "$DIR/luminalock" ]; then
    echo "在 $DIR 下找不到 luminalock 插件目录" >&2
    exit 2
fi

QML=/usr/lib/qt6/bin/qml   # /usr/bin/qml 是 qtchooser 包装，找不到 Qt 安装
HERE="$(cd "$(dirname "$0")" && pwd)"
PROBES="dialog_probe icon_probe"
rc=0

for probe in $PROBES; do
    log="/tmp/dcc-qml-probe-$probe.log"
    QML2_IMPORT_PATH="$DIR" QT_QPA_PLATFORM=offscreen timeout 30 \
        "$QML" "$HERE/$probe.qml" >"$log" 2>&1
    code=$?
    if [ $code -eq 0 ]; then
        echo "PASS  $probe"
    else
        echo "FAIL  $probe (exit=$code, 日志 $log)"
        # 只挑出能说明问题的行，其余留在日志里
        grep -E "unavailable|Cannot assign|not defined|Cannot|error" "$log" | head -5 | sed 's/^/        /'
        rc=1
    fi
done

echo "--- $([ $rc -eq 0 ] && echo 全部通过 || echo 有失败) ---"
exit $rc
