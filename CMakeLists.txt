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

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick Multimedia)

# --- PAM ---
find_library(PAM_LIBRARY NAMES pam REQUIRED)
find_path(PAM_INCLUDE_DIR NAMES security/pam_appl.h REQUIRED)

qt_add_executable(lumina-lock
    src/main.cpp
    src/auth/PamAuthenticator.cpp
    src/auth/PamAuthenticator.h
    src/session/LockSession.cpp
    src/session/LockSession.h
    src/wallpaper/WallpaperManager.cpp
    src/wallpaper/WallpaperManager.h
    src/screen/ScreenManager.cpp
    src/screen/ScreenManager.h
    resources.qrc
)

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
    ${PAM_LIBRARY}
)

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(lumina-lock PRIVATE -Wall -Wextra)
endif()

install(TARGETS lumina-lock RUNTIME DESTINATION bin)
