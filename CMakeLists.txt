cmake_minimum_required(VERSION 3.24)

project(Hesh
    VERSION 0.1.4
    DESCRIPTION "A lightweight device development and emulation environment"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Test WebEngineQuick)

qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

qt_add_library(hesh_core STATIC
    src/app/Application.cpp
    src/app/Application.hpp
    src/app/Settings.cpp
    src/app/Settings.hpp
    src/devices/Device.cpp
    src/devices/Device.hpp
    src/devices/DeviceManager.cpp
    src/devices/DeviceManager.hpp
    src/devices/DeviceProfile.cpp
    src/devices/DeviceProfile.hpp
    src/devices/DeviceStorage.cpp
    src/devices/DeviceStorage.hpp
    src/web/WebDevice.cpp
    src/web/WebDevice.hpp
)

target_include_directories(hesh_core
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(hesh_core
    PUBLIC
        Qt6::Core
        Qt6::Gui
)

qt_add_executable(hesh
    src/main.cpp
)

target_link_libraries(hesh
    PRIVATE
        hesh_core
        Qt6::Gui
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::WebEngineQuick
)

set_source_files_properties(qml/theme/Theme.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(hesh
    URI Hesh
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/components/AppButton.qml
        qml/components/DeviceFrame.qml
        qml/components/StandaloneDeviceWindow.qml
        qml/components/StandaloneContextMenu.qml
        qml/components/DeviceContextMenu.qml
        qml/components/DeviceListItem.qml
        qml/components/DeviceToolbarMenu.qml
        qml/components/EmptyState.qml
        qml/components/IconButton.qml
        qml/components/Sidebar.qml
        qml/components/StatusBadge.qml
        qml/dialogs/ClearDeviceDataDialog.qml
        qml/dialogs/CreateDeviceDialog.qml
        qml/pages/DeviceWorkspace.qml
        qml/theme/Theme.qml
    RESOURCES
        qml/theme/qmldir
        assets/icons/hesh.png
)

qt_add_executable(hesh_tests
    tests/device_tests.cpp
)

target_link_libraries(hesh_tests
    PRIVATE
        hesh_core
        Qt6::Test
)

enable_testing()
add_test(NAME hesh_core_tests COMMAND hesh_tests)

install(TARGETS hesh
    RUNTIME DESTINATION bin
)
