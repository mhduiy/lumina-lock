# Lumina Lock

一个视觉体验优先、界面极简、动画精致、支持动态壁纸的现代 Linux 锁屏原型。

**重要说明**：当前实现是 *UI 与认证原型*，还不是真正安全的系统锁屏。它是一个普通全屏窗口，不拦截系统级快捷键、不做 input routing / VT 切换，也不实现 Wayland lock surface 或 compositor 集成。真正的系统锁屏需要与 session manager / compositor 集成（见文末“安全边界”）。

## 特性（第一阶段）

- 极简展示界面：壁纸 + 大号时间 + 日期，无控制中心 / 通知 / 天气等无关内容
- 任意按键 / 点击 / 上滑进入认证态，时间上移、背景 dim + 适度模糊、密码区 fade + slide 出现
- 静态图片壁纸（`Image`，aspect-crop 填充）与视频动态壁纸（`MediaPlayer` + `VideoOutput`，循环、静音）
- 视频带 poster 占位，进入时无黑屏闪烁；锁屏退出后释放视频资源
- PAM 密码认证（C++ 层、异步、密码不落日志、生命周期尽量短）
- 认证失败内联错误提示 + 密码框轻微 shake；成功则播放退出动画后通知解锁
- 基础多屏：主屏显示认证 UI，副屏只显示壁纸 + 时钟，且副屏不重复启动视频解码
- HiDPI 友好：所有尺寸基于窗口高度等比缩放，无 1920×1080 写死

## 构建

依赖：Qt 6（Core / Gui / Qml / Quick / Multimedia）、libpam 开发头文件、CMake ≥ 3.21。

```bash
cmake -B build
cmake --build build
```

## 运行

```bash
# 默认内置静态壁纸
./build/lumina-lock

# 自定义静态图片
./build/lumina-lock --wallpaper /path/to/wallpaper.jpg

# 视频动态壁纸（建议同时给出 poster 以避免首帧黑屏）
./build/lumina-lock --video /path/to/wallpaper.mp4 --poster /path/to/cover.jpg

# 指定 PAM 服务名 / 认证用户
./build/lumina-lock --pam-service login --user $USER
```

内置资源 `assets/wallpapers/default.jpg` 与 `default-video.mp4` 由 ffmpeg 生成，可自由替换。

## 架构

```
src/
├── auth/PamAuthenticator   # PAM：worker 线程 + conversation + 结果回传 GUI 线程
├── session/LockSession     # 会话门面：用户身份、认证编排、unlock 信号
├── wallpaper/WallpaperManager  # 壁纸“是什么”（类型 + 源），不含渲染
├── screen/ScreenManager    # 每屏一个全屏窗口，处理热插拔
└── main.cpp                # 组装 + CLI

qml/
├── LockScreen.qml          # 主屏统一 Scene（Idle / Authenticating 状态）
├── SecondaryScreen.qml     # 副屏（壁纸 + 时钟）
├── ClockView.qml           # 时间 / 日期
├── AuthView.qml            # 头像 / 用户名 / 密码 / 内联错误
├── WallpaperHost.qml       # 壁纸渲染（静态 / 视频）
├── Theme.qml               # 视觉令牌（颜色 / 字体 / 缩放）
└── components/PasswordField.qml
```

职责边界：

- **C++** 负责系统能力、认证、状态与资源管理
- **QML** 负责 UI、动画与视觉表现
- 壁纸内容（`WallpaperManager` / `WallpaperHost`）与认证数据（`LockSession` / `PamAuthenticator`）完全隔离——后续第三方壁纸插件不会接触到密码或认证数据

### 壁纸抽象

`WallpaperManager`（C++，数据）↔ `WallpaperHost`（QML，渲染）是统一抽象：

```
Wallpaper
├── StaticImage   (type = "static")
└── Video         (type = "video")
```

后续可自然扩展 `Shader` 等类型，无需改动 `LockScreen.qml`。第一阶段不做完整插件系统。

### 认证流程

```
QML AuthView.submit(password)
   → LockSession.authenticate(password)
   → PamAuthenticator.authenticate(user, password)   [worker 线程]
       pam_start → pam_authenticate → pam_end
   → finished(success, message)                       [queued 回 GUI 线程]
   → LockSession.authenticationFinished
   → QML：成功 → 退出动画 → LockSession.unlock() → app.quit()
          失败 → 内联错误 + shake
```

密码只在 `PamAuthenticator::Job`（worker 线程持有）中出现，`pam_authenticate` 返回后立即用 `volatile` 写零擦除；`LockSession` 的临时副本同样清零。密码不会被打印到日志。

## 安全边界（重要）

- Lock UI、壁纸内容**都不是可信安全边界**；认证数据只经由 `LockSession` / `PamAuthenticator`。
- 默认 PAM 服务为 `login`。以普通用户运行时，`pam_unix` 依赖 setuid 的 `unix_chkpwd` 校验密码；正式部署时请配置专用的 PAM 服务文件并按需设置权限（如 i3lock/swaylock 的做法）。
- 真正系统锁屏后续需考虑：compositor / session manager 集成、Wayland lock surface、input routing、全局快捷键屏蔽、VT/session 切换等。本原型均未实现。

## Wayland / X11

代码不依赖任一窗口系统特有的 UI 逻辑，仅使用 `QScreen` + `showFullScreen()`。在 X11 与 Wayland 下均可作为全屏窗口运行（安全语义不同，见上）。

## 冒烟测试

```bash
# 离屏渲染，2 秒后自动退出（验证启动与 QML 加载无致命错误）
QT_QPA_PLATFORM=offscreen ./build/lumina-lock --test-exit-ms 2000

# 真实显示环境短暂运行
./build/lumina-lock --test-exit-ms 3000
```

## 已知问题

- 在部分系统上，fcitx5 的 Qt6 平台输入上下文插件会打印
  `QObject::startTimer: Timers can only be used with threads started with QThread`
  警告。它来自 `libfcitx5platforminputcontextplugin.so` 自身，与本项目无关且无害。
  锁屏的密码框已通过 `TextInput.Password` 隐藏回显，正式部署时应进一步禁用输入法。
- PAM 认证需要在有真实 PAM 配置的环境下验证（默认服务 `login`）。本仓库以
  UI/认证原型为交付目标，未做 setuid 或专用服务文件的部署集成。
