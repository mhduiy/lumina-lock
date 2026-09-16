# Lumina Lock

一个视觉体验优先、界面极简、动画精致、支持动态壁纸的现代 Linux 锁屏。

**重要说明**：本项目既是 *UI 与认证原型*，也提供了 **dde-lock 的 drop-in 替换 DEB**（见「DEB 打包与 dde-lock 替换」）。替换后的锁屏通过 dde-lock 同名 D-Bus 接口与 DDE 协作；但它不是安全级的系统锁屏：不拦截系统级快捷键、不做 input routing / VT 切换，Wayland 下的 lock surface 也未实现。真正的安全锁屏需要 compositor / session manager 集成（见文末「安全边界」）。

## 特性

- 极简展示界面：壁纸 + 大号时间 + 日期，无控制中心 / 通知 / 天气等无关内容
- **磨砂玻璃质感**：时间 / 日期本身是半透明玻璃字——字形作为遮罩，笔画里透出模糊后的壁纸（iOS 锁屏那种观感），并带一层字形投影保证任意壁纸下都可读；密码框则是圆角毛玻璃面板。两者都只采样自身覆盖的那一小块壁纸并裁剪成对应形状，不做整屏模糊；静态壁纸按需采样（静止时不重算），视频壁纸逐帧采样
- 任意按键 / 点击 / 上滑进入认证态，时间上移、背景 dim + 适度模糊、密码区 fade + slide 出现；**唤醒的那次按键会直接成为密码的第一个字符**，底部提示文字淡入上浮后缓慢呼吸
- 密码框：圆点居中显示，每输入一个字符有一次轻微弹动；密码错误时横向抖动 + 弹性下沉的弹跳反馈，正确时描边闪 accent 色并向外脉冲一下
- 静态图片壁纸（`Image`，aspect-crop 填充）与视频动态壁纸（`MediaPlayer` + `VideoOutput`，循环、静音）
- 壁纸整摞采用「**淡出上层遮挡物**」揭示：底色层在最上面盖住整摞，就绪后交叉淡出（500ms），poster 同理盖在视频之上。不用「淡入内容」是因为 `VideoOutput` 的 item opacity 不参与混合，而 `Rectangle`/`Image` 的会。进入时无黑屏闪烁；锁屏退出后释放视频资源
- **时间 / 日期字体粗细可调**（细体 / 常规 / 中等 / 半粗 / 粗体），控制中心里改完即时生效
- **控制中心集成**：随包附带 dde-control-center 插件（顶级模块「锁屏壁纸」），可设置静态图片 / 动态视频壁纸及封面、时间与日期字重，写入 `org.lumina.lock` DConfig；锁屏启动时读取、驻留时实时生效（CLI `--wallpaper`/`--video` 优先）
- PAM 密码认证（C++ 层、异步、密码不落日志、生命周期尽量短）
- 认证失败内联错误提示 + 密码框轻微 shake；成功则播放退出动画后解锁
- **入场**：时钟/日期以固定字号单次淡入（480ms），不做尺寸动画；**再次上锁时同样只淡入一次**（`resetForLock()` 关闭 `animating` 让场景吸附回 Idle，入场淡入必须同样受它约束，否则会把上次遗留的满不透明度先淡出再淡入）——`unit` 取自窗口高度，窗口定尺寸前为 0，若此时动画尺寸会呈现"从无到有地长大"
- **转场**：退出时淡出内容、再淡出窗口；不做内容缩放（缩放整屏大号文字是此前卡顿的主因），视频壁纸全程继续播放。所有淡入淡出共用 `qml/components/MotionBehavior.qml`（一条 `cubic-bezier(0.4, 0, 0.2, 1)`，时长按用途覆盖），避免各处曲线漂移。全屏壁纸模糊在启动的头几帧预热（以 0 模糊量绘制一次），避免它第一次渲染时编译 level-3 模糊 shader、分配多级 FBO 链而卡住过渡
- **上锁期间独占输入**（X11）：锁屏时抓取键盘，Alt+Tab / Super 等窗口管理器快捷键不再切走窗口；解锁时释放。抓取只挂在「当前认证屏」的窗口上并随认证 UI 迁移（**不抓取指针**：多屏下每个屏都有自己的全屏窗口，抓指针会把所有点击都灌进一个窗口，导致"点哪块屏哪块屏进认证"失效）
- **常驻进程**：解锁只隐藏窗口、释放视频资源，进程不退出；可通过 D-Bus 重新上锁
- **dde-lock D-Bus 兼容**：以 `org.deepin.dde.LockFront1` 注册 `Show / ShowUserList / ShowAuth / Suspend / Hibernate` 方法与 `Visible` 属性，DDE 组件（dde-daemon、dock、快捷键、挂起/恢复）调用方式与 dde-lock 完全一致
- **X11 窗口集成**：锁屏窗口带 `_DEEPIN_LOCK_SCREEN` / `_DEEPIN_NET_STARTUP` 属性、使用 dde-lock 相同的窗口标志，deepin-wm 会将其置顶并保持聚焦
- 挂起恢复时遵循电源守护进程的 `SleepLock` 设置（关闭时恢复桌面不锁屏）
- **多屏**：每个屏跑同一个 surface，同一时刻只有一块屏是「活跃屏」——它收起时钟并显示密码框，其余屏保持壁纸 + 时钟 + 提示。活跃屏跟随交互：**点击**哪块屏就归哪块屏；**按键**归「指针所在」的那块屏（X11 键盘抓取只会把按键送到一个窗口，指针位置是唯一可靠的"用户在看哪块屏"信号），唤醒的那次按键会成为该屏密码的第一个字符。副屏同样播放动态壁纸（每屏一个解码器，锁屏隐藏时释放）
- HiDPI 友好：所有尺寸基于窗口高度等比缩放，无 1920×1080 写死

## 构建

依赖：Qt 6（Core / Gui / Qml / Quick / Multimedia / DBus）、libpam 开发头文件、libxcb 开发头文件、CMake ≥ 3.21。

```bash
cmake -B build
cmake --build build
```

## 运行

```bash
# 默认内置静态壁纸，立即上锁并常驻（解锁只隐藏窗口，进程不退出）
./build/lumina-lock

# 后台常驻，等待 D-Bus Show() 再上锁（dde-lock 部署方式）
./build/lumina-lock --daemon

# 自定义静态图片
./build/lumina-lock --wallpaper /path/to/wallpaper.jpg

# 视频动态壁纸（建议同时给出 poster 以避免首帧黑屏）
./build/lumina-lock --video /path/to/wallpaper.mp4 --poster /path/to/cover.jpg

# 指定 PAM 服务名 / 认证用户
./build/lumina-lock --pam-service dde-lock --user $USER
```

壁纸也可以在控制中心设置（见「在控制中心设置壁纸」），无需命令行参数。

内置资源 `assets/wallpapers/default.jpg` 与 `default-video.mp4` 由 ffmpeg 生成，可自由替换。

## 架构

```
src/
├── auth/PamAuthenticator   # PAM：worker 线程 + conversation + 结果回传 GUI 线程
├── session/LockSession     # 会话门面：用户身份、认证编排、锁定状态
├── session/LockService     # dde-lock lockFront D-Bus 适配器（QDBusAbstractAdaptor）
├── wallpaper/WallpaperManager  # 壁纸“是什么”（类型 + 源），不含渲染
├── wallpaper/WallpaperConfig   # 从 org.lumina.lock DConfig 读取壁纸设置并应用
├── appearance/AppearanceConfig # 从同一 DConfig 读取时间 / 日期字重
├── screen/ScreenManager    # 每屏一个全屏窗口、活跃认证屏的选择、X11 锁屏属性与键盘抓取、热插拔
└── main.cpp                # 组装 + CLI + D-Bus 服务注册

dcc-plugin/                 # dde-control-center 插件（控制中心「锁屏壁纸」模块）
├── src/luminalock.{h,cpp}  # dccData：DConfig 读写 + 文件选择器
└── qml/Luminalock*.qml     # 模块入口 + 设置页

qml/
├── LockScreen.qml          # 统一 Scene（Idle / Authenticating 状态；每个屏各一个实例）
├── ClockView.qml           # 时间 / 日期（磨砂玻璃字 + 可调字重）
├── AuthView.qml            # 头像 / 用户名 / 密码 / 内联错误
├── WallpaperHost.qml       # 壁纸渲染（静态 / 视频）
├── Theme.qml               # 视觉令牌（颜色 / 字体 / 缩放）
└── components/
    ├── PasswordField.qml   # 毛玻璃密码框 + 环形 busy 弧
    ├── GlassText.qml       # 磨砂玻璃字：字形作遮罩 + 模糊壁纸填充 + 字形投影
    └── GlassPanel.qml      # 毛玻璃面板（局部采样 + 模糊 + 圆角遮罩）
```

职责边界：

- **C++** 负责系统能力、认证、状态与资源管理
- **QML** 负责 UI、动画与视觉表现
- 壁纸内容（`WallpaperManager` / `WallpaperHost`）与认证数据（`LockSession` / `PamAuthenticator`）完全隔离——后续第三方壁纸插件不会接触到密码或认证数据

### 认证流程

```
QML AuthView.submit(password)
   → LockSession.authenticate(password)
   → PamAuthenticator.authenticate(user, password)   [worker 线程]
       pam_start → pam_authenticate → pam_end
   → finished(success, message)                       [queued 回 GUI 线程]
   → LockSession.authenticationFinished
   → QML：成功 → 退出动画 → LockSession.unlock() → 隐藏窗口（进程常驻）
          失败 → 内联错误 + shake
```

密码只在 `PamAuthenticator::Job`（worker 线程持有）中出现，`pam_authenticate` 返回后立即用 `volatile` 写零擦除；`LockSession` 的临时副本同样清零。密码不会被打印到日志（失败时只记录错误类别，例如 "Wrong password"）。

## 在控制中心设置锁屏

随包安装一个 dde-control-center 插件，控制中心会多出一个顶级模块「锁屏壁纸」。页面按控制中心自己的约定写：每行 `backgroundType: DccObject.Normal`、值放在行描述里、下拉用 `D.ComboBox { flat: true }`；行高、按钮尺寸与内边距**全部沿用控制中心默认值**，插件里不做任何写死，因此和其他设置页保持一致。可设置：

- **壁纸类型**：默认壁纸 / 静态图片 / 动态视频
- **静态图片**：文件选择器选择一张图片
- **动态视频**：选择一段视频；**视频封面**：可选一张封面图（避免首帧黑屏）
- **时间字号** / **日期字号**：以 1080p 高度为基准的像素值（时间 80–240、日期 14–48），按屏幕分辨率等比缩放
- **时间字体粗细** / **日期字体粗细**：细体 / 常规 / 中等 / 半粗 / 粗体
- **恢复默认**：清空配置，回到内置壁纸与默认字重

插件写入 `org.lumina.lock` DConfig（键 `wallpaperType` / `wallpaperPath` / `videoPath` / `posterPath` / `clockWeight` / `dateWeight` / `clockFontSize` / `dateFontSize`，schema 随包装在 `/usr/share/dsg/configs/org.lumina.lock/`）。锁屏进程读取同一份配置：启动时应用，驻留期间实时生效（DConfig 变更通知），因此**在控制中心改完即可直接上锁验证**。字重取值为 `thin` / `extralight` / `light` / `normal` / `medium` / `demibold` / `bold`，无法识别的值回退到默认（时间 `light`、日期 `medium`）；字号超出范围会被夹到边界（时间 80–240、日期 14–48）。因此手改配置不会导致锁屏异常。

命令行参数 `--wallpaper` / `--video` 优先级高于 DConfig；不带这些参数时才读取控制中心的设置。文件选择用**系统文件对话框**（`FileDialog` 不加 `DontUseNativeDialog`，与其余控制中心插件一致，由文件管理器提供界面），系统上没有该服务时 Qt 会自动回退到自带实现。也可用 CLI 直接读写该配置：

```bash
dde-dconfig set -a org.lumina.lock -r org.lumina.lock -k wallpaperType -v video
dde-dconfig set -a org.lumina.lock -r org.lumina.lock -k videoPath -v /path/to/wallpaper.mp4
dde-dconfig set -a org.lumina.lock -r org.lumina.lock -k posterPath -v /path/to/cover.jpg
dde-dconfig set -a org.lumina.lock -r org.lumina.lock -k clockWeight -v bold
dde-dconfig set -a org.lumina.lock -r org.lumina.lock -k dateWeight -v demibold
dde-dconfig set -a org.lumina.lock -r org.lumina.lock -k clockFontSize -v 180
dde-dconfig set -a org.lumina.lock -r org.lumina.lock -k dateFontSize -v 32
```

开发期调试插件（未安装到系统时）：

```bash
# --list 只加载模块树并打印（需绕过 stdout 会被安全加载器吞掉的 /usr/bin 包装脚本）
/usr/libexec/deepin/dde-control-center --spec /abs/path/build/lib/plugins_v1.1/ --list
```

## DEB 打包与 dde-lock 替换

目标是：`sudo dpkg -i` 一个 DEB 即可让 DDE 的锁屏换成 Lumina Lock，且不破坏 DDE 其他组件。

### 替换机制（手术式，不碰登录界面）

dde-lock 并不是独立包：可执行文件、D-Bus service 文件、PAM 配置、desktop 入口分别属于 `dde-session-shell` 与 `dde-session` 两个包。因此：

1. **只接管 `/usr/bin/dde-lock` 一个路径**。DEB 的 `preinst` 用 `dpkg-divert` 把 dde-session-shell 的包装脚本挪到 `/usr/bin/dde-lock.dde-session-shell`，再把本项目的二进制（经 `usr/bin/dde-lock → lumina-lock` 符号链接）放到原位；`postrm` 在卸载时自动还原。**不用 `Conflicts`**——那会把 dde-session-shell 整个卸掉，连 lightdm 登录界面一起消失，装完无法登录。
2. **其余胶水文件复用系统现有的**：`/usr/share/dbus-1/services/org.deepin.dde.LockFront1.service`、`/etc/pam.d/dde-lock`、`/usr/share/applications/dde-lock.desktop`、`/usr/lib/systemd/user/dde-lock.service` 的 `Exec` 都指向 `/usr/bin/dde-lock`——接管后自然指向 Lumina Lock。所以本包 `Depends: dde-session-shell (>= 6.0.0)`，不重复安装这些文件（避免文件冲突）。
3. **一个 systemd user drop-in**：`/etc/systemd/user/dde-lock.service.d/lumina-lock.conf`，把 dde-session 单元的 `Type=forking` 改为 `simple`（本程序不 fork，原配置会把会话初始化挂死），并显式传 `--daemon --pam-service dde-lock`。
4. **新增（无冲突）**：控制中心插件装到 `/usr/lib/*/dde-control-center/plugins_v1.1/luminalock/`，壁纸 DConfig schema 装到 `/usr/share/dsg/configs/org.lumina.lock/`。这两类文件是全新路径，不与任何现有包冲突；故本包另 `Depends: dde-control-center`（插件需在控制中心里加载）。

三条上锁路径都汇聚到 `/usr/bin/dde-lock`，因此全部被接管：

- **会话初始化**：`dde-lock.service` 随会话启动常驻（隐藏等待）
- **D-Bus 激活**：dde-daemon / dock / 快捷键调用 `org.deepin.dde.LockFront1.Show()`；若常驻进程还在，调用直接送达；不在则由 dbus-daemon 经 `SystemdService=dde-lock.service` 拉起
- **挂起/恢复**：`Suspend(true/false)` / `Hibernate(true/false)` 由会话电源守护进程调用

### 构建 DEB

```bash
# 需安装构建依赖：qt6-base-dev qt6-declarative-dev qt6-multimedia-dev libpam0g-dev libxcb1-dev \
#   libdtkcore-dev dde-control-center-dev debhelper cmake
dpkg-buildpackage -b -us -uc     # 产物在上级目录 lumina-lock_0.4.11-1_amd64.deb
```

### 安装 / 卸载 / 回退

```bash
# 安装（替换 dde-lock）
sudo dpkg -i lumina-lock_0.4.11-1_amd64.deb
systemctl --user daemon-reload
systemctl --user restart dde-lock.service   # 让新锁屏接管；或直接重新登录

# 验证接管
dpkg -S /usr/bin/dde-lock                    # 应为 lumina-lock
ls -l /usr/bin/dde-lock.dde-session-shell    # 原包装脚本仍在（dde-session-shell 的文件）
dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.GetNameOwner string:org.deepin.dde.LockFront1
# 控制中心里应出现「锁屏壁纸」模块（重开控制中心即可见）

# 卸载（自动还原 dde-lock，DDE 恢复原锁屏）
sudo dpkg -r lumina-lock
```

### 已知差异（相对 dde-lock）

- **认证走 PAM**（`/etc/pam.d/dde-lock`，与 dde-lock 的 PAM 配置同源），不接 deepin-authenticate，因此指纹 / 人脸等生物认证、密码弹窗（UADP）不可用；仅密码认证
- **无多用户切换**：`ShowUserList()` 映射为直接上锁，锁屏界面不显示用户列表
- **Wayland 不支持**：dde-session 的单元在 Wayland 会话直接跳过（`ExecCondition`），与 dde-lock 现状一致；Wayland 锁屏仍需 compositor 集成
- 上锁后仍依赖 deepin-wm 对 `_DEEPIN_LOCK_SCREEN` 窗口的特殊处理来置顶/聚焦；不拦截全局快捷键（同 dde-lock 的窗口机制）

## 常驻与 D-Bus

程序是常驻服务：解锁只隐藏窗口（并释放视频解码资源），进程保持运行。

D-Bus 接口（会话总线，与 dde-lock 同名同路径，供 DDE 组件调用）：

```bash
# 上锁（DDE 各组件即以此方式驱动）
dbus-send --session --print-reply --dest=org.deepin.dde.LockFront1 \
    /org/deepin/dde/LockFront1 org.deepin.dde.LockFront1.Show

# 查询 Visible 属性
dbus-send --session --print-reply --dest=org.deepin.dde.LockFront1 \
    /org/deepin/dde/LockFront1 org.freedesktop.DBus.Properties.Get \
    string:org.deepin.dde.LockFront1 string:Visible
```

另有本项目自有的控制接口 `org.lumina.Lock`（对象路径 `/org/lumina/Lock`，方法 `lock` / `quit`，属性 `locked`），用于测试与手动控制：

```bash
dbus-send --session --dest=org.lumina.Lock --type=method_call \
    /org/lumina/Lock org.lumina.Lock.lock
dbus-send --session --dest=org.lumina.Lock --type=method_call \
    /org/lumina/Lock org.lumina.Lock.quit
```

D-Bus 命名（`org.deepin.dde.*1` snipe 世代 vs 旧版 `com.deepin.dde.*`）在配置期由 `-DDSS_SNIPE=ON/OFF` 选择，默认 ON，与 Deepin 23+ / UOS 25 部署一致。DEB 固定以 `-DDSS_SNIPE=ON` 构建。

## 安全边界（重要）

- Lock UI、壁纸内容**都不是可信安全边界**；认证数据只经由 `LockSession` / `PamAuthenticator`。
- 默认 PAM 服务为 `login`；dde-lock 部署路径使用 `--pam-service dde-lock`（与 dde-lock 相同的 `/etc/pam.d/dde-lock`）。以普通用户运行时，`pam_unix` 依赖 setuid 的 `unix_chkpwd` 校验密码。
- 真正系统锁屏后续需考虑：compositor / session manager 集成、Wayland lock surface、input routing、全局快捷键屏蔽、VT/session 切换等。本原型均未实现。

## Wayland / X11

代码不依赖任一窗口系统特有的 UI 逻辑，仅使用 `QScreen` + `showFullScreen()`。在 X11 下窗口附加 `_DEEPIN_LOCK_SCREEN` / `_DEEPIN_NET_STARTUP` 属性并使用 `WindowStaysOnTopHint | X11BypassWindowManagerHint`（与 dde-lock 一致），由 deepin-wm 置顶并聚焦；Wayland 下可作为普通全屏窗口运行（安全语义不同，见上），且 dde-lock 替换路径在 Wayland 会话不生效（与 dde-lock 现状一致）。

**输入独占只在 X11 生效**：上锁时对「当前认证屏」的窗口做键盘抓取（`QWindow::setKeyboardGrabEnabled`），窗口管理器收不到 Alt+Tab、Super 等快捷键，因此无法切走锁屏；解锁时释放，认证 UI 换屏时抓取跟着换到那个窗口。抓取失败会打印 `ScreenManager: keyboard grab refused` 警告（窗口还不可见时最多重试 10 次）。**不抓取指针**：多屏下每个屏都有自己的全屏窗口，点击本来就落在锁屏上，而抓指针会把所有点击灌进同一个窗口、使「点哪块屏哪块屏进认证」失效。Wayland 下键盘抓取返回 `false`（合成器掌管快捷键），不做替代方案——锁屏窗口与普通全屏窗口语义相同。

**磨砂玻璃需要 shader 渲染后端**：`GlassText` / `GlassPanel` 依赖 `MultiEffect`（`ShaderEffect`）。当场景图运行在 software 后端（`QT_QUICK_BACKEND=software`、`QQuickWindow::GraphicsInfo.Software`）时无法执行 shader，此时玻璃字退化为普通白字、面板退化为半透明纯色表面，其余功能不受影响。

## 多屏

每个物理屏都会得到一个自己的全屏窗口，跑同一个 surface（`qml/LockScreen.qml`）。任意时刻只有一块屏是**活跃屏**：它把时钟收起、背景 dim + 模糊、显示密码框；其余屏停在 Idle（壁纸 + 时钟 + 底部提示），随时可以被唤醒接管。

活跃屏由交互决定，QML 侧不参与这个判断：

- **点击**：点击落在哪块屏，认证 UI 就归哪块屏（每块屏的窗口只处理自己的点击）；
- **按键**：X11 的键盘抓取只会把按键送到「持抓取的那个窗口」，所以 `ScreenManager::eventFilter()` 全局监听按键，用**指针所在屏**作为「用户在看哪块屏」的判据——若按键不属于当前活跃屏，就把认证 UI 搬过去，并让这次按键成为该屏密码的第一个字符（不会误敲进用户看不见的那个密码框）；若按键本来就属于活跃屏，直接放行给密码框；
- 键盘抓取跟着密码框走（抓取窗口才是收按键的窗口）；
- **Escape** 会清掉活跃屏（所有屏回到 Idle）；D-Bus `ShowAuth(true)` 默认把认证 UI 放在主屏；
- **热插拔**：新增屏直接建窗口、可被唤醒；活跃屏被拔掉时退回「无活跃屏」，剩下的屏随时可以接管（旧实现下主屏被拔会留下一个没有密码框、也丢了输入抓取的锁屏，只能杀进程）。

`qml` 侧只通过 `Screens` 单例（`Screens.authScreenName` / `activateAuthForScreen()` / `clearAuth()` / `takePendingText()`）与这套拓扑打交道，surface 本身不含任何屏幕数/主副屏逻辑。

## 冒烟测试

```bash
# 离屏渲染，2 秒后自动退出（验证启动与 QML 加载无致命错误）
QT_QPA_PLATFORM=offscreen ./build/lumina-lock --test-exit-ms 2000

# 隔离会话内验证 dde-lock D-Bus 兼容面（不触碰真实会话）
dbus-run-session -- bash -c '
  QT_QPA_PLATFORM=offscreen ./build/lumina-lock --daemon --test-exit-ms 30000 &
  sleep 2
  dbus-send --session --print-reply --dest=org.deepin.dde.LockFront1 \
    /org/deepin/dde/LockFront1 org.freedesktop.DBus.Properties.Get \
    string:org.deepin.dde.LockFront1 string:Visible   # 期望 false
  dbus-send --session --print-reply --dest=org.deepin.dde.LockFront1 \
    /org/deepin/dde/LockFront1 org.deepin.dde.LockFront1.Show
  dbus-send --session --print-reply --dest=org.deepin.dde.LockFront1 \
    /org/deepin/dde/LockFront1 org.freedesktop.DBus.Properties.Get \
    string:org.deepin.dde.LockFront1 string:Visible   # 期望 true
  dbus-send --session --print-reply --dest=org.lumina.Lock \
    /org/lumina/Lock org.lumina.Lock.quit
'

# 多屏（无头）：Xvfb 起两块屏，每块屏应各有一个锁屏窗口，且只有指针所在屏进认证态
Xvfb :99 -screen 0 1920x1080x24 -screen 1 1920x1080x24 &
DISPLAY=:99 ./build/lumina-lock --test-exit-ms 8000 &
sleep 2
DISPLAY=:99.0 xwininfo -root -children | grep -c "Lumina Lock"   # 期望 1
DISPLAY=:99.1 xwininfo -root -children | grep -c "Lumina Lock"   # 期望 1
DISPLAY=:99 xdotool mousemove 2500 500 click 1                   # 点第二块屏
DISPLAY=:99 xdotool type --delay 80 "abc"                        # 应进入第二块屏的密码框

# 真实显示环境短暂运行
./build/lumina-lock --test-exit-ms 3000

# PAM 后端单测（密码从 stdin 读入，不出现在进程列表中）
echo "wrong-password" | ./build/lumina-pam-test $(whoami)
```

## 已知问题

- 在部分系统上，fcitx5 的 Qt6 平台输入上下文插件会打印
  `QObject::startTimer: Timers can only be used with threads started with QThread`
  警告。它来自 `libfcitx5platforminputcontextplugin.so` 自身，与本项目无关且无害。
  锁屏的密码框已通过 `TextInput.Password` 隐藏回显，正式部署时应进一步禁用输入法。
- PAM 认证需要在有真实 PAM 配置的环境下验证（默认服务 `login` / 部署时 `dde-lock`）。
- 替换 dde-lock 的 DEB 以 Deepin 23+ / UOS 25 的 snipe D-Bus 命名为目标；经典命名（`com.deepin.dde.*`）可自行以 `-DDSS_SNIPE=OFF` 构建。
