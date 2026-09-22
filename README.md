# Lumina Lock

[![Release](https://img.shields.io/github/v/release/mhduiy/lumina-lock?style=flat-square)](https://github.com/mhduiy/lumina-lock/releases)
[![License](https://img.shields.io/badge/license-MIT-97CA00?style=flat-square)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/mhduiy/lumina-lock?style=flat-square)](https://github.com/mhduiy/lumina-lock/commits/master)
[![Contributors](https://img.shields.io/github/contributors/mhduiy/lumina-lock?style=flat-square)](https://github.com/mhduiy/lumina-lock/graphs/contributors)
[![Issues](https://img.shields.io/github/issues/mhduiy/lumina-lock?style=flat-square)](https://github.com/mhduiy/lumina-lock/issues)
[![Stars](https://img.shields.io/github/stars/mhduiy/lumina-lock?style=flat-square)](https://github.com/mhduiy/lumina-lock/stargazers)
![Platform](https://img.shields.io/badge/platform-Deepin%2023%2B%20%7C%20UOS%2025-4B8BBE?style=flat-square)
![Qt](https://img.shields.io/badge/Qt-6%20%7C%20QML-41CD52?style=flat-square)
![C%2B%2B](https://img.shields.io/badge/C%2B%2B-17-00599C?style=flat-square)

一个视觉优先、界面极简、动画精致的 Linux 锁屏，支持静态与动态壁纸，并附带一个可以把
DDE 的 dde-lock 换掉的 DEB。

> **它不是安全级锁屏。** 不拦截系统级快捷键、不做 input routing / VT 切换，Wayland 下
> 没有 lock surface。真正的安全锁屏需要 compositor / session manager 集成，见文末
> [安全边界](#安全边界)。

## 特性

**锁屏**

- 极简场景：壁纸 + 大号时间 + 日期，没有控制中心 / 通知 / 天气
- 磨砂玻璃：时间日期是半透明玻璃字（字形作遮罩，笔画里透出模糊后的壁纸），密码框是圆角毛玻璃面板；只采样各自覆盖的那一小块壁纸，不做整屏模糊
- 任意按键 / 点击 / 上滑进入认证态，时间上移、背景 dim + 模糊、密码区淡入；**唤醒的那次按键直接成为密码的第一个字符**
- 密码框：圆点居中，每输入一个字符轻微弹动；错误时横向抖动 + 弹性下沉，正确时描边闪 accent 并向外脉冲
- 入场 / 转场共用一条缓动曲线，不做整屏缩放（那是此前卡顿的主因）

**壁纸**

- 静态图片与视频动态壁纸（循环、静音），整摞用「淡出上层遮挡物」揭示，进入无黑屏闪烁
- 多个动态视频可随机抽播：每次上锁抽一个、不连续重复，列表为空或文件都不在时回退内置壁纸，多屏共享同一次抽签
- N 卡机器上视频走 **GStreamer 后端**以启用 NVDEC 硬解（Qt 6.8 默认的 FFmpeg 后端按线程数分配解码 surface，4K 片源会超过驱动的 32 个上限而静默回退软解）；`QT_MEDIA_BACKEND` 可覆盖
- 锁屏退出后释放视频解码资源

**控制中心**

- 随包一个 dde-control-center 插件（顶级模块「锁屏壁纸」）：壁纸类型 / 静态图 / 动态视频与封面 / 时间与日期的字重、字号、位置
- 写入 `org.lumina.lock` DConfig，锁屏启动时读取、驻留期间实时生效；CLI 参数优先

**系统集成**

- **PAM 认证**：C++ 层、worker 线程、异步，密码不落日志、用完立即擦除
- **多屏**：每屏一个全屏窗口跑同一份 surface，同一时刻只有一块「活跃屏」收起时钟并显示密码框；点击归被点的屏，按键归指针所在的屏；热插拔不会留下没有密码框、也丢了输入抓取的锁屏
- **输入独占（X11）**：上锁时对认证屏的窗口做键盘抓取，Alt+Tab / Super 不再切走锁屏；**不抓取指针**（多屏下那会让「点哪块屏哪块屏进认证」失效）
- **常驻**：解锁只隐藏窗口并释放视频资源，进程不退出；D-Bus 可重新上锁
- **dde-lock D-Bus 兼容**：以 `org.deepin.dde.LockFront1` 注册，DDE 各组件的调用方式不变
- **锁屏状态上报**：上锁 / 解锁时调用 `org.deepin.dde.SessionManager1.SetLocked`，logind、电源管理与
  `dde-quick-login` 看到的锁屏状态与画面一致；`-lq`（快速登录）因此能正常走完，而不是等超时被登出
- 挂起恢复遵循电源守护进程的 `SleepLock` 设置；HiDPI 友好，尺寸全部基于窗口高度等比缩放

**电源菜单**

- 持有 dde-lock 的 `org.deepin.dde.ShutdownFront1`：dock 的电源按钮、启动器的电源项、会话发起的请求都打到它
- 关机是**滑条**：拖到底松手，背景随行程压暗到最暗
- 其余动作是圆形图标按钮；不可撤销的重启与更新变体需要**按住**（圆环进度），松手即取消
- 只有机器真能做的动作才出现；更新文案取自 lastore 的 `UpgradableApps`
- 锁屏右下角另有**切换用户**与**电源**两个控件，只在密码界面出现，带错峰入场

## 安装（替换 dde-lock）

```bash
sudo dpkg -i lumina-lock_1.0.0_amd64.deb
systemctl --user daemon-reload
systemctl --user restart dde-lock.service   # 或直接重新登录
```

验证接管，以及卸载回退：

```bash
dpkg -S /usr/bin/dde-lock                 # 应为 lumina-lock
ls -l /usr/bin/dde-lock.dde-session-shell # 原包装脚本仍在（dde-session-shell 的文件）
sudo dpkg -r lumina-lock                  # 自动还原 dde-lock
```

**替换机制**：只接管 `/usr/bin/dde-lock` 一个路径——`preinst` 用 `dpkg-divert` 把
dde-session-shell 的包装脚本挪走，`postrm` 卸载时自动还原。**不用 `Conflicts`**：那会把
dde-session-shell 整个卸掉，连 lightdm 登录界面一起消失。其余胶水文件（D-Bus service、
`/etc/pam.d/dde-lock`、desktop 入口、systemd 单元）的 `Exec` 本来就指向 `/usr/bin/dde-lock`，
接管后自然生效；另加一个 systemd drop-in 把 `Type=forking` 改为 `simple`（本程序不 fork）。

**与 dde-lock 的已知差异**

- 仅密码认证：不接 deepin-authenticate，因此没有指纹 / 人脸 / UADP 密码弹窗
- 锁屏内没有用户列表，`ShowUserList()` 交给 greeter
- Wayland 下不做替换、也没有锁屏语义（与 dde-lock 现状一致）

## 构建与运行

依赖：Qt 6（Core / Gui / Qml / Quick / Multimedia / DBus）、libpam、libxcb、CMake ≥ 3.21。

```bash
cmake -B build && cmake --build build

./build/lumina-lock                      # 立即上锁并常驻
./build/lumina-lock --daemon             # 后台常驻，等 D-Bus Show() 再上锁
./build/lumina-lock -lq                  # dde-quick-login 的启动方式（快速登录，隐含 -l）
./build/lumina-lock --wallpaper a.jpg    # 静态壁纸
./build/lumina-lock --video a.mp4 --poster cover.jpg
./build/lumina-lock --pam-service dde-lock --user $USER
```

打包（产物在上级目录）：

```bash
sudo apt install qt6-base-dev qt6-declarative-dev qt6-multimedia-dev libpam0g-dev \
    libxcb1-dev libdtk6core-dev dde-control-center-dev debhelper cmake
dpkg-buildpackage -b -us -uc
```

## 配置

控制中心里改完即可直接上锁验证。也可以用 CLI：

```bash
dde-dconfig set -a org.lumina.lock -r org.lumina.lock -k wallpaperType -v video
dde-dconfig set -a org.lumina.lock -r org.lumina.lock -k videoPath -v /path/to/a.mp4
dde-dconfig set -a org.lumina.lock -r org.lumina.lock -k clockWeight -v bold
```

键：`wallpaperType` / `wallpaperPath` / `videoPath` / `videoPaths` / `posterPath` /
`clockWeight` / `dateWeight` / `clockFontSize` / `dateFontSize` / `clockPositionX` /
`clockPositionY`。非法值会被夹到范围或回退默认，手改配置不会让锁屏异常。

## D-Bus

会话总线上，与 dde-lock 同名同路径：

| 服务 | 用途 |
|---|---|
| `org.deepin.dde.LockFront1` | 上锁面：`Show` / `ShowUserList` / `ShowAuth` / `Suspend` / `Hibernate`，属性 `Visible` |
| `org.deepin.dde.ShutdownFront1` | 电源菜单：`Show` / `Shutdown` / `Restart` / `Logout` / `Suspend` / `Hibernate` / `SwitchUser` / `Lock` / `UpdateAndShutdown` / `UpdateAndReboot`，属性 `Visible` |
| `org.lumina.Lock` | 自有控制口：`lock` / `quit`，属性 `locked` |

```bash
dbus-send --session --dest=org.deepin.dde.LockFront1 \
    /org/deepin/dde/LockFront1 org.deepin.dde.LockFront1.Show
```

命名代际（`org.deepin.dde.*1` vs `com.deepin.dde.*`）由 `-DDSS_SNIPE=ON/OFF` 选择，默认 ON，
与 Deepin 23+ / UOS 25 一致；DEB 固定以 ON 构建。

开发时可设 `LUMINA_POWER_DRY_RUN=1`：只打印将要执行的动作、不真的执行。

## 架构

```
src/
├── auth/PamAuthenticator      # PAM：worker 线程 + conversation + 结果回传 GUI 线程
├── session/LockSession        # 会话门面：用户身份、认证编排、锁定状态
├── session/LockService        # dde-lock lockFront D-Bus 适配器
├── power/PowerSession         # 电源菜单：可用性、动作、ShutdownFront1 行为
├── wallpaper/WallpaperManager # 壁纸「是什么」（类型 + 源），不含渲染
├── wallpaper/WallpaperConfig  # 从 org.lumina.lock DConfig 读取并应用
├── appearance/AppearanceConfig# 时间 / 日期字重、字号、位置
├── screen/ScreenManager       # 每屏一个窗口、活跃认证屏、X11 属性与键盘抓取、热插拔
└── main.cpp                   # 组装 + CLI + D-Bus 注册

dcc-plugin/                    # dde-control-center 插件（「锁屏壁纸」模块）
qml/
├── LockScreen.qml             # 统一 Scene（Idle / Authenticating），每屏一个实例
├── ClockView.qml  AuthView.qml  WallpaperHost.qml  PowerScreen.qml  Theme.qml
└── components/                # PasswordField / GlassText / GlassPanel / PowerIcon / MotionBehavior
```

C++ 负责系统能力、认证、状态与资源；QML 负责 UI 与动画。壁纸内容与认证数据完全隔离——
第三方壁纸不会接触到密码或认证数据。

## 安全边界

- Lock UI 与壁纸内容**都不是可信安全边界**，认证数据只经由 `LockSession` / `PamAuthenticator`
- 默认 PAM 服务为 `login`；dde-lock 部署路径使用 `--pam-service dde-lock`。以普通用户运行时，`pam_unix` 依赖 setuid 的 `unix_chkpwd` 校验密码
- **输入独占只在 X11 生效**：Wayland 下键盘抓取返回 `false`（合成器掌管快捷键），不做替代方案
- **磨砂玻璃需要 shader 后端**：software 后端下玻璃字退化为普通白字、面板退化为半透明纯色，其余功能不受影响
- 真正的系统锁屏还需要：compositor / session manager 集成、Wayland lock surface、input routing、全局快捷键屏蔽、VT / session 切换。本阶段均未实现

## 测试

```bash
QT_QPA_PLATFORM=offscreen ./build/lumina-lock --test-exit-ms 2000   # 启动与 QML 加载
echo "wrong-password" | ./build/lumina-pam-test $(whoami)           # PAM 后端
bash tests/lock-state-report/run.sh                                 # 锁屏状态上报（快速登录依赖）
tests/*/run.sh                                                      # 其余各功能沙箱脚本
```

## 贡献者

<a href="https://github.com/mhduiy/lumina-lock/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=mhduiy/lumina-lock" alt="Contributors" />
</a>

## 许可证

[MIT](LICENSE) © 2026 mhduiy
