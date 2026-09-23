// SPDX-License-Identifier: GPL-3.0-or-later
import org.deepin.dcc 1.0

// 插件元数据：顶级模块入口。name 与插件名一致，用于配置隐藏/禁用与定位。
DccObject {
    name: "luminalock"
    parentName: "root"
    displayName: qsTr("锁屏壁纸")
    // 模块图标用插件自己的名字（qml/luminalock.svg → :/dsg/icons/luminalock.dci）。
    // 不能借系统壁纸的图标名 dcc_wallpaper：那会把系统自己的壁纸模块图标一起顶掉。
    // 上一版自造图标在侧边栏显得又小又偏，原因是画布没按图形范围框定——图形只占原
    // 1024 画布的 662x1024 且偏左，放进方形格子自然缩成一小块。画布已在 svg 里重新
    // 框定并居中，见该文件顶部的注释。
    icon: "luminalock"
    weight: 130
}
