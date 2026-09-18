// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import org.deepin.dtk 1.0 as D

// 随机视频列表的管理弹窗：添加 / 删除多个动态壁纸视频。
//
// 列表本身就是 DConfig 里的 dccData.videoPaths，这里只负责维护它——"这次上锁放
// 哪一个"由锁屏在每次上锁时抽签决定（见 WallpaperConfig），插件不参与。
D.DialogWindow {
    id: dialog
    width: 460
    minimumWidth: width
    maximumWidth: width
    icon: "preferences-system"
    modality: Qt.WindowModal
    visible: true
    title: qsTr("随机视频列表")

    property string errorMessage: ""

    // 注意：DialogWindow 的内容区高度 = childrenRect.height（由内容自己撑起来），
    // 所以这里既不能用 anchors.fill: parent，也不能给子项用 Layout.fillHeight ——
    // 那样算出来的内容高度是 0，列表会被压成 0 高，表现就是「加进去了却看不见」。
    // 正确写法：内容纵向尺寸都给死（列表用 Layout.preferredHeight）。
    ColumnLayout {
        width: parent.width
        spacing: 10

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: D.DTK.fontManager.t6
            text: qsTr("每次上锁从下面的视频里随机挑一个播放，不会连续两次放同一个。")
        }

        Item {
            Layout.fillWidth: true
            // 固定高度：内容区高度靠 childrenRect 算，fillHeight 在这里算不出值。
            Layout.preferredHeight: 280

            ListView {
                id: videoList
                anchors.fill: parent
                clip: true
                spacing: 4
                model: dccData.videoPaths

                delegate: Item {
                    id: row
                    required property string modelData
                    readonly property string fileName: modelData.replace(/^.*\//, "")

                    width: videoList.width
                    height: 44

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: removeButton.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            font: D.DTK.fontManager.t6
                            text: row.fileName
                        }

                        // 同名视频可能来自不同目录，路径也一并给出，便于分辨。
                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            opacity: 0.6
                            font: D.DTK.fontManager.t7
                            text: row.modelData.substring(0, row.modelData.length - row.fileName.length)
                        }
                    }

                    Button {
                        id: removeButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        font: D.DTK.fontManager.t6
                        text: qsTr("删除")
                        onClicked: dccData.removeVideo(row.modelData)
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                visible: videoList.count === 0
                font: D.DTK.fontManager.t6
                text: qsTr("还没有添加视频")
            }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: dialog.errorMessage.length > 0
            font: D.DTK.fontManager.t6
            text: dialog.errorMessage
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Button {
                id: addButton
                font: D.DTK.fontManager.t6
                text: qsTr("添加视频")
                onClicked: addDialog.open()

                // 文件对话框必须挂在 Item 下面：D.DialogWindow 的默认属性是
                // `content`（list<Item>），Window 塞不进去——放成它的直接子级会让
                // 整个 VideoListDialog 实例化失败，连带整个模块都建不出来。
                // 挂在按钮里也和控制中心其他插件里的写法一致。
                FileDialog {
                    id: addDialog
                    title: qsTr("选择锁屏动态壁纸视频")
                    fileMode: FileDialog.OpenFile
                    nameFilters: ["Videos (*.mp4 *.mov *.webm *.mkv *.m4v *.avi)"]
                    onAccepted: {
                        if (dccData.addVideo(selectedFile)) {
                            dialog.errorMessage = ""
                        } else {
                            // 后端知道原因（文件读不了 / schema 里没有 videoPaths），
                            // 直接显示它，别让用户去猜。
                            dialog.errorMessage = dccData.lastError.length > 0
                                ? dccData.lastError
                                : qsTr("无法添加该视频。")
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Button {
                font: D.DTK.fontManager.t6
                text: qsTr("完成")
                onClicked: dialog.close()
            }
        }
    }
}
