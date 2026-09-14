// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Dialogs
import org.deepin.dcc 1.0

// 锁屏壁纸设置页：dccData 为 C++ 导出的 Luminalock 对象。
DccObject {
    id: root
    property string selectionError: ""

    // Font weights offered for the clock. `value` is the DConfig spelling.
    readonly property var weightModel: [
        { text: qsTr("细体"), value: "light" },
        { text: qsTr("常规"), value: "normal" },
        { text: qsTr("中等"), value: "medium" },
        { text: qsTr("半粗"), value: "demibold" },
        { text: qsTr("粗体"), value: "bold" }
    ]

    function saveFile(kind, url) {
        selectionError = dccData.setFile(kind, url) ? ""
            : qsTr("无法保存壁纸，请检查文件是否可读，以及壁纸配置是否已正确安装。")
    }

    DccObject {
        name: "type"
        parentName: "luminalock"
        displayName: qsTr("壁纸类型")
        weight: 10
        pageType: DccObject.Editor
        page: ComboBox {
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
        weight: 20
        pageType: DccObject.Editor
        page: RowLayout {
            spacing: 10
            Label {
                Layout.fillWidth: true
                text: dccData.wallpaperPath === "" ? qsTr("未设置") : dccData.wallpaperPath
                elide: Text.ElideMiddle
            }
            Button {
                id: imageButton
                text: qsTr("选择图片")
                onClicked: imageDialog.open()
                FileDialog {
                    id: imageDialog
                    parentWindow: imageButton.Window.window
                    title: qsTr("选择锁屏壁纸图片")
                    fileMode: FileDialog.OpenFile
                    // Keep the picker in Qt Quick, independent of file-manager D-Bus services.
                    options: FileDialog.DontUseNativeDialog
                    nameFilters: ["Images (*.jpg *.jpeg *.png *.bmp *.gif *.webp)"]
                    onAccepted: root.saveFile("static", selectedFile)
                }
            }
        }
    }

    DccObject {
        name: "video"
        parentName: "luminalock"
        displayName: qsTr("动态视频")
        weight: 30
        pageType: DccObject.Editor
        page: RowLayout {
            spacing: 10
            Label {
                Layout.fillWidth: true
                text: dccData.videoPath === "" ? qsTr("未设置") : dccData.videoPath
                elide: Text.ElideMiddle
            }
            Button {
                id: videoButton
                text: qsTr("选择视频")
                onClicked: videoDialog.open()
                FileDialog {
                    id: videoDialog
                    parentWindow: videoButton.Window.window
                    title: qsTr("选择锁屏动态壁纸视频")
                    fileMode: FileDialog.OpenFile
                    options: FileDialog.DontUseNativeDialog
                    nameFilters: ["Videos (*.mp4 *.mov *.webm *.mkv *.m4v *.avi)"]
                    onAccepted: root.saveFile("video", selectedFile)
                }
            }
        }
    }

    DccObject {
        name: "poster"
        parentName: "luminalock"
        displayName: qsTr("视频封面")
        weight: 40
        pageType: DccObject.Editor
        page: RowLayout {
            spacing: 10
            Label {
                Layout.fillWidth: true
                text: dccData.posterPath === "" ? qsTr("未设置") : dccData.posterPath
                elide: Text.ElideMiddle
            }
            Button {
                id: posterButton
                text: qsTr("选择封面")
                onClicked: posterDialog.open()
                FileDialog {
                    id: posterDialog
                    parentWindow: posterButton.Window.window
                    title: qsTr("选择动态壁纸封面图片")
                    fileMode: FileDialog.OpenFile
                    options: FileDialog.DontUseNativeDialog
                    nameFilters: ["Images (*.jpg *.jpeg *.png *.bmp *.gif *.webp)"]
                    onAccepted: root.saveFile("poster", selectedFile)
                }
            }
        }
    }

    DccObject {
        name: "clockWeight"
        parentName: "luminalock"
        displayName: qsTr("时间字体粗细")
        weight: 50
        pageType: DccObject.Editor
        page: ComboBox {
            textRole: "text"
            valueRole: "value"
            model: root.weightModel
            Component.onCompleted: currentIndex = indexOfValue(dccData.clockWeight)
            onActivated: dccData.setClockWeight(currentValue)
        }
    }

    DccObject {
        name: "dateWeight"
        parentName: "luminalock"
        displayName: qsTr("日期字体粗细")
        weight: 60
        pageType: DccObject.Editor
        page: ComboBox {
            textRole: "text"
            valueRole: "value"
            model: root.weightModel
            Component.onCompleted: currentIndex = indexOfValue(dccData.dateWeight)
            onActivated: dccData.setDateWeight(currentValue)
        }
    }

    DccObject {
        name: "reset"
        parentName: "luminalock"
        displayName: qsTr("恢复默认")
        weight: 70
        pageType: DccObject.Editor
        page: Button {
            text: qsTr("恢复默认壁纸")
            onClicked: dccData.resetToDefault()
        }
    }

    DccObject {
        name: "selectionError"
        parentName: "luminalock"
        visible: root.selectionError.length > 0
        weight: 80
        pageType: DccObject.Item
        page: Label {
            text: root.selectionError
            wrapMode: Text.Wrap
        }
    }
}
