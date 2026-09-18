// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs

import org.deepin.dcc 1.0
import org.deepin.dtk 1.0 as D

// 锁屏设置页：dccData 为 C++ 导出的 Luminalock 对象。
//
// 每行都带 backgroundType: DccObject.Normal，下拉用 D.ComboBox（flat），
// 按钮用控制中心其他地方一样的宽度算法——这样才和其他设置页渲染成一致的卡片。
DccObject {
    id: root

    property string selectionError: ""

    // 字重选项：label 用于显示，value 是 DConfig 里的拼写。
    readonly property var weightOptions: [
        { label: qsTr("细体"), value: "light" },
        { label: qsTr("常规"), value: "normal" },
        { label: qsTr("中等"), value: "medium" },
        { label: qsTr("半粗"), value: "demibold" },
        { label: qsTr("粗体"), value: "bold" }
    ]
    readonly property var weightLabels: weightOptions.map(option => option.label)
    readonly property var weightValues: weightOptions.map(option => option.value)

    // 壁纸类型：显示文案与 DConfig 取值一一对应。
    readonly property var typeValues: ["none", "static", "video", "video-random"]
    readonly property var typeLabels: [qsTr("默认壁纸"), qsTr("静态图片"), qsTr("动态视频"),
                                       qsTr("动态视频（随机）")]

    function typeIndex(value) {
        const index = typeValues.indexOf(value)
        return index < 0 ? 0 : index
    }

    function saveFile(kind, url) {
        selectionError = dccData.setFile(kind, url) ? ""
            : qsTr("无法保存壁纸，请检查文件是否可读，以及壁纸配置是否已正确安装。")
    }

    DccObject {
        name: "type"
        parentName: "luminalock"
        displayName: qsTr("壁纸类型")
        description: qsTr("锁屏背景使用内置壁纸、静态图片、单个动态视频，还是每次上锁从视频列表里随机播放一个")
        weight: 10
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.ComboBox {
            id: typeCombo
            flat: true
            model: root.typeLabels
            currentIndex: root.typeIndex(dccData.wallpaperType)
            onActivated: index => dccData.setType(root.typeValues[index])

            // 下拉自己写入 currentIndex 时会打断上面的绑定，而"随机视频列表"里加
            // 视频同样会把类型切成 video-random——不重新同步的话，下拉会显示一个
            // 和锁屏实际行为不一致的旧值。
            Connections {
                target: dccData
                function onWallpaperTypeChanged() {
                    typeCombo.currentIndex = root.typeIndex(dccData.wallpaperType)
                }
            }
        }
    }

    DccObject {
        name: "image"
        parentName: "luminalock"
        displayName: qsTr("静态图片")
        description: dccData.wallpaperPath === "" ? qsTr("未设置")
                                                  : dccData.wallpaperPath
        weight: 20
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Button {
            text: qsTr("选择图片")
            onClicked: imageDialog.open()

            // 原生文件对话框（走系统文件管理器），不用 Qt Quick 自带实现。
            FileDialog {
                id: imageDialog
                title: qsTr("选择锁屏壁纸图片")
                fileMode: FileDialog.OpenFile
                nameFilters: ["Images (*.jpg *.jpeg *.png *.bmp *.gif *.webp)"]
                onAccepted: root.saveFile("static", selectedFile)
            }
        }
    }

    DccObject {
        name: "video"
        parentName: "luminalock"
        displayName: qsTr("动态视频")
        description: dccData.videoPath === "" ? qsTr("未设置") : dccData.videoPath
        weight: 30
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Button {
            text: qsTr("选择视频")
            onClicked: videoDialog.open()

            FileDialog {
                id: videoDialog
                title: qsTr("选择锁屏动态壁纸视频")
                fileMode: FileDialog.OpenFile
                nameFilters: ["Videos (*.mp4 *.mov *.webm *.mkv *.m4v *.avi)"]
                onAccepted: root.saveFile("video", selectedFile)
            }
        }
    }

    DccObject {
        name: "videoPool"
        parentName: "luminalock"
        displayName: qsTr("随机视频列表")
        description: dccData.videoPaths.length === 0
                     ? qsTr("未设置")
                     : qsTr("%1 个视频").arg(dccData.videoPaths.length)
        weight: 35
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Button {
            text: qsTr("管理")
            onClicked: videoListLoader.active = true

            // 弹窗按需创建、关掉即销毁，和别的插件的对话框一致。
            Loader {
                id: videoListLoader
                active: false
                sourceComponent: VideoListDialog {
                    onClosing: videoListLoader.active = false
                }
            }
        }
    }

    DccObject {
        name: "poster"
        parentName: "luminalock"
        displayName: qsTr("视频封面")
        description: dccData.posterPath === "" ? qsTr("未设置") : dccData.posterPath
        weight: 40
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Button {
            text: qsTr("选择封面")
            onClicked: posterDialog.open()

            FileDialog {
                id: posterDialog
                title: qsTr("选择动态壁纸封面图片")
                fileMode: FileDialog.OpenFile
                nameFilters: ["Images (*.jpg *.jpeg *.png *.bmp *.gif *.webp)"]
                onAccepted: root.saveFile("poster", selectedFile)
            }
        }
    }

    DccObject {
        name: "clockPositionX"
        parentName: "luminalock"
        displayName: qsTr("时间日期横向位置")
        description: qsTr("0 = 贴左边缘，50 = 居中（默认），100 = 贴右边缘")
        weight: 52
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.SpinBox {
            from: 0
            to: 100
            editable: true
            value: dccData.clockPositionX
            onValueChanged: dccData.setClockPositionX(value)
        }
    }

    DccObject {
        name: "clockPositionY"
        parentName: "luminalock"
        displayName: qsTr("时间日期纵向位置")
        description: qsTr("0 = 贴上边缘，50 = 居中（默认），100 = 贴下边缘")
        weight: 54
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.SpinBox {
            from: 0
            to: 100
            editable: true
            value: dccData.clockPositionY
            onValueChanged: dccData.setClockPositionY(value)
        }
    }

    DccTitleObject {
        name: "clockTitle"
        parentName: "luminalock"
        displayName: qsTr("时钟样式")
        weight: 50
    }

    DccObject {
        name: "clockFontSize"
        parentName: "luminalock"
        displayName: qsTr("时间字号")
        description: qsTr("以 1080p 高度为基准，按屏幕分辨率等比缩放")
        weight: 60
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.SpinBox {
            from: 80
            to: 240
            editable: true
            value: dccData.clockFontSize
            onValueChanged: dccData.setClockFontSize(value)
        }
    }

    DccObject {
        name: "clockWeight"
        parentName: "luminalock"
        displayName: qsTr("时间字体粗细")
        weight: 62
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.ComboBox {
            flat: true
            model: root.weightLabels
            currentIndex: Math.max(0, root.weightValues.indexOf(dccData.clockWeight))
            onActivated: index => dccData.setClockWeight(root.weightValues[index])
        }
    }

    DccObject {
        name: "dateFontSize"
        parentName: "luminalock"
        displayName: qsTr("日期字号")
        description: qsTr("以 1080p 高度为基准，按屏幕分辨率等比缩放")
        weight: 64
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.SpinBox {
            from: 14
            to: 48
            editable: true
            value: dccData.dateFontSize
            onValueChanged: dccData.setDateFontSize(value)
        }
    }

    DccObject {
        name: "dateWeight"
        parentName: "luminalock"
        displayName: qsTr("日期字体粗细")
        weight: 66
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.ComboBox {
            flat: true
            model: root.weightLabels
            currentIndex: Math.max(0, root.weightValues.indexOf(dccData.dateWeight))
            onActivated: index => dccData.setDateWeight(root.weightValues[index])
        }
    }

    DccObject {
        name: "reset"
        parentName: "luminalock"
        displayName: qsTr("恢复默认")
        description: qsTr("清空壁纸设置（含随机视频列表）并回到默认字号、字重与时间日期位置")
        weight: 80
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Button {
            text: qsTr("恢复默认")
            onClicked: dccData.resetToDefault()
        }
    }

    DccObject {
        name: "selectionError"
        parentName: "luminalock"
        visible: root.selectionError.length > 0
        weight: 90
        backgroundType: DccObject.Normal
        pageType: DccObject.Item
        page: D.Label {
            text: root.selectionError
            wrapMode: Text.Wrap
        }
    }
}
