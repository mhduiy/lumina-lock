// SPDX-License-Identifier: GPL-3.0-or-later
import org.deepin.dcc 1.0

// 插件元数据：顶级模块入口。name 与插件名一致，用于配置隐藏/禁用与定位。
DccObject {
    name: "luminalock"
    parentName: "root"
    displayName: qsTr("锁屏壁纸")
    // 模块图标用控制中心自带的名字：插件自造的图标（DCI）在侧边栏渲染成格子的
    // 三分之一，试过资源前缀 /dsg/icons、24px 明暗图层、无内边距都不行，未解决。
    icon: "dcc_wallpaper"
    weight: 130
}
