// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import luminalock 1.0

// 插件 QML 探针：模块图标（qrc 里的 luminalock.svg）能否解析并解码。
//
// 图标走的是 DTK IconLabel 的 name → fallback source 路径，name 是主题图标名
// （找得到才用），真正的图是 iconSource（模块 qrc 内的相对路径）。这里直接按
// qrc 路径加载一遍，确认它存在且可解码。
//
// 退出码：0 = Ready；7 = 解不到（路径/格式/资源没编进去）。
Window {
    width: 10
    height: 10
    visible: false

    Image {
        id: icon
        source: "qrc:/qt/qml/luminalock/luminalock.svg"
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: Qt.exit(icon.status === Image.Ready ? 0 : 7)
    }
}
