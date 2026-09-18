// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import luminalock 1.0

// 插件 QML 探针：只验证 VideoListDialog 这个 Window 能不能被创建。
//
// 它踩过的坑：FileDialog（Window）曾被放在 D.DialogWindow 的直接子级，而
// D.DialogWindow 的默认属性是 `content`（list<Item>），Window 塞不进去 —— 结果是
// 这个文件实例化失败、类型不可用，进而让 LuminalockMain 建不出主对象，控制中心里
// 整个模块连图标一起消失（日志只有一句 MainObjErr）。
//
// 退出码：0 = 建起来了；2 = 类型加载失败（结构错误）。
Window {
    width: 100
    height: 100
    visible: false

    VideoListDialog {
        id: probe
        visible: false
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: Qt.exit(probe.title.length > 0 ? 0 : 3)
    }
}
