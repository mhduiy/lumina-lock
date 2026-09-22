cmake_minimum_required(VERSION 3.21)

project(lumina-lock
    VERSION 0.1.0
    DESCRIPTION "A minimal, modern Linux lock screen (UI & authentication prototype)"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# dde-lock compatibility: deepin 6.x uses the org.deepin.dde.*1 D-Bus naming
# ("snipe"), classic DDE used com.deepin.dde.*. Default matches deployed 6.x.
option(DSS_SNIPE "Use org.deepin.dde.*1 D-Bus naming for the lock front" ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick Multimedia DBus)

# --- PAM ---
find_library(PAM_LIBRARY NAMES pam REQUIRED)
find_path(PAM_INCLUDE_DIR NAMES security/pam_appl.h REQUIRED)

# --- X11 (lock-screen window integration, see ScreenManager) ---
find_library(XCB_LIBRARY NAMES xcb REQUIRED)

# --- DConfig (control-center wallpaper settings) ---
find_package(Dtk6Core REQUIRED)
find_package(Dtk6DConfig REQUIRED)

qt_add_executable(lumina-lock
    src/main.cpp
    src/appearance/AppearanceConfig.cpp
    src/appearance/AppearanceConfig.h
    src/auth/PamAuthenticator.cpp
    src/auth/PamAuthenticator.h
    src/session/LockService.cpp
    src/session/LockService.h
    src/session/LockSession.cpp
    src/session/LockSession.h
    src/session/dbusnames.h
    src/power/PowerService.cpp
    src/power/PowerService.h
    src/power/PowerSession.cpp
    src/power/PowerSession.h
    src/wallpaper/WallpaperConfig.cpp
    src/wallpaper/WallpaperConfig.h
    src/wallpaper/WallpaperManager.cpp
    src/wallpaper/WallpaperManager.h
    src/screen/ScreenManager.cpp
    src/screen/ScreenManager.h
    resources.qrc
)

if(DSS_SNIPE)
    target_compile_definitions(lumina-lock PRIVATE DSS_SNIPE=1)
endif()

target_include_directories(lumina-lock PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${PAM_INCLUDE_DIR}
)

target_link_libraries(lumina-lock PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::Multimedia
    Qt6::DBus
    ${PAM_LIBRARY}
    ${XCB_LIBRARY}
    Dtk6::Core
)

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(lumina-lock PRIVATE -Wall -Wextra)
endif()

# Standalone PAM backend test (no GUI).
qt_add_executable(lumina-pam-test
    tests/pam_test.cpp
    src/auth/PamAuthenticator.cpp
    src/auth/PamAuthenticator.h
)
target_include_directories(lumina-pam-test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${PAM_INCLUDE_DIR}
)
target_link_libraries(lumina-pam-test PRIVATE Qt6::Core ${PAM_LIBRARY})

# The lock-state report dde-quick-login depends on (LockSession::reportLockState).
# Needs a session bus of its own, so run it under dbus-run-session.
qt_add_executable(lumina-lock-state-test
    tests/lock-state-report/main.cpp
    src/auth/PamAuthenticator.cpp
    src/auth/PamAuthenticator.h
    src/session/LockSession.cpp
    src/session/LockSession.h
    src/session/dbusnames.h
)
if(DSS_SNIPE)
    target_compile_definitions(lumina-lock-state-test PRIVATE DSS_SNIPE=1)
endif()
target_include_directories(lumina-lock-state-test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${PAM_INCLUDE_DIR}
)
target_link_libraries(lumina-lock-state-test PRIVATE Qt6::Core Qt6::DBus ${PAM_LIBRARY})

install(TARGETS lumina-lock RUNTIME DESTINATION bin)

# DConfig schema for the wallpaper settings (control-center integration).
dtk_add_config_meta_files(APPID org.lumina.lock
    FILES data/dsg/configs/org.lumina.lock/org.lumina.lock.json)

# Optional dde-control-center plugin (skipped when its dev package is absent).
option(BUILD_DCC_PLUGIN "Build the dde-control-center wallpaper plugin" ON)
if(BUILD_DCC_PLUGIN)
    find_package(DdeControlCenter QUIET)
    if(DdeControlCenter_FOUND)
        add_subdirectory(dcc-plugin)
    else()
        message(STATUS "dde-control-center dev files not found; skipping control-center plugin")
    endif()
endif()

# The dde-lock replacement deliberately ships *no* D-Bus/PAM/desktop/systemd
# glue: those files already exist on a DDE system (owned by dde-session-shell
# and dde-session) and their Exec lines all point at /usr/bin/dde-lock, which
# this package takes over via dpkg-divert. Shipping our own copies would
# conflict with the packages we coexist with (see debian/ and README).
