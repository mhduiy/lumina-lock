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

    function saveFile(kind, url) {
        selectionError = dccData.setFile(kind, url) ? ""
            : qsTr("无法保存壁纸，请检查文件是否可读，以及壁纸配置是否已正确安装。")
    }

    DccObject {
        name: "type"
        parentName: "luminalock"
        displayName: qsTr("壁纸类型")
        description: qsTr("锁屏背景使用内置壁纸、静态图片还是动态视频")
        weight: 10
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.ComboBox {
            flat: true
            model: [qsTr("默认壁纸"), qsTr("静态图片"), qsTr("动态视频")]
            currentIndex: dccData.wallpaperType === "video" ? 2
                        : (dccData.wallpaperType === "static" ? 1 : 0)
            onActivated: index => dccData.setType(index === 2 ? "video"
                                                    : (index === 1 ? "static" : "none"))
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
        description: qsTr("清空壁纸设置并回到默认字号与字重")
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
