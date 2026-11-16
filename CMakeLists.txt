cmake_minimum_required(VERSION 3.22)
project(Tandav_GCS VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    QuickControls2
    Network
    Multimedia
    Positioning
)

add_executable(Tandav_GCS
    src/main.cpp
    src/models/VesselState.h
    src/models/VesselState.cpp
    src/models/MissionPlan.h
    src/models/MissionPlan.cpp
    src/backend/TelemetryManager.h
    src/backend/TelemetryManager.cpp
    src/backend/GamepadInput.h
    src/backend/GamepadInput.cpp
    src/backend/VideoPipeline.h
    src/backend/VideoPipeline.cpp
    src/backend/FailsafeMonitor.h
    src/backend/FailsafeMonitor.cpp
    resources/qml.qrc
)

target_include_directories(Tandav_GCS PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/models
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend
)

target_link_libraries(Tandav_GCS PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Network
    Qt6::Multimedia
    Qt6::Positioning
)
