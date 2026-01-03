cmake_minimum_required(VERSION 3.15)
project(coreaudio)

# macOS-only project
if(NOT APPLE)
    message(FATAL_ERROR "coreaudio-node only supports macOS")
endif()

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# macOS deployment target
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.2" CACHE STRING "Minimum macOS version")

# Build universal binary
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "Build architectures")

# Swift source files
set(SWIFT_SOURCES
    ${CMAKE_SOURCE_DIR}/native/swift/CoreAudioBridge.swift
    ${CMAKE_SOURCE_DIR}/native/swift/NativeAudioRecorder.swift
    ${CMAKE_SOURCE_DIR}/native/swift/AudioTapManager.swift
    ${CMAKE_SOURCE_DIR}/native/swift/AudioBuffer.swift
    ${CMAKE_SOURCE_DIR}/native/swift/AudioPacket.swift
    ${CMAKE_SOURCE_DIR}/native/swift/AudioFormatConverter.swift
    ${CMAKE_SOURCE_DIR}/native/swift/AudioFormatManager.swift
    ${CMAKE_SOURCE_DIR}/native/swift/TapConfiguration.swift
    ${CMAKE_SOURCE_DIR}/native/swift/TapMuteBehavior.swift
    ${CMAKE_SOURCE_DIR}/native/swift/AudioTeeErrors.swift
    ${CMAKE_SOURCE_DIR}/native/swift/AudioPermission.swift
    ${CMAKE_SOURCE_DIR}/native/swift/AudioDeviceManager.swift
    ${CMAKE_SOURCE_DIR}/native/swift/MicrophoneCapture.swift
    ${CMAKE_SOURCE_DIR}/native/swift/Utils.swift
)

# Output directory for Swift library
set(SWIFT_LIB_DIR ${CMAKE_BINARY_DIR}/swift_lib)
file(MAKE_DIRECTORY ${SWIFT_LIB_DIR})

# Build Swift static library using custom command
add_custom_command(
    OUTPUT ${SWIFT_LIB_DIR}/libcoreaudio_swift.a
    COMMAND swiftc
        -emit-library
        -static
        -module-name CoreAudioSwift
        -parse-as-library
        -O
        -target arm64-apple-macosx14.2
        -o ${SWIFT_LIB_DIR}/libcoreaudio_swift_arm64.a
        ${SWIFT_SOURCES}
    COMMAND swiftc
        -emit-library
        -static
        -module-name CoreAudioSwift
        -parse-as-library
        -O
        -target x86_64-apple-macosx14.2
        -o ${SWIFT_LIB_DIR}/libcoreaudio_swift_x86_64.a
        ${SWIFT_SOURCES}
    COMMAND lipo
        -create
        ${SWIFT_LIB_DIR}/libcoreaudio_swift_arm64.a
        ${SWIFT_LIB_DIR}/libcoreaudio_swift_x86_64.a
        -output ${SWIFT_LIB_DIR}/libcoreaudio_swift.a
    DEPENDS ${SWIFT_SOURCES}
    COMMENT "Building Swift static library (universal binary)"
    VERBATIM
)

# Create a custom target for the Swift library
add_custom_target(swift_lib DEPENDS ${SWIFT_LIB_DIR}/libcoreaudio_swift.a)

# Required for cmake-js
include_directories(${CMAKE_JS_INC})

# C++ N-API addon
add_library(${PROJECT_NAME} SHARED
    native/cpp/coreaudio_napi.cpp
)

# Ensure Swift is built first
add_dependencies(${PROJECT_NAME} swift_lib)

# Set the output name without 'lib' prefix
set_target_properties(${PROJECT_NAME} PROPERTIES
    PREFIX ""
    SUFFIX ".node"
)

# Include directories
target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_SOURCE_DIR}/native/cpp
    ${CMAKE_JS_INC}
)

# Get Swift library path
execute_process(
    COMMAND xcrun --show-sdk-path
    OUTPUT_VARIABLE MACOS_SDK_PATH
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

execute_process(
    COMMAND swiftc -print-target-info
    OUTPUT_VARIABLE SWIFT_TARGET_INFO
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Find Swift runtime library path
execute_process(
    COMMAND xcrun --toolchain default --find swiftc
    OUTPUT_VARIABLE SWIFTC_PATH
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
get_filename_component(SWIFT_BIN_DIR ${SWIFTC_PATH} DIRECTORY)
get_filename_component(SWIFT_TOOLCHAIN_DIR ${SWIFT_BIN_DIR} DIRECTORY)
set(SWIFT_LIB_PATH "${SWIFT_TOOLCHAIN_DIR}/lib/swift/macosx")

# Link with our Swift library and required frameworks
target_link_libraries(${PROJECT_NAME}
    ${CMAKE_JS_LIB}
    ${SWIFT_LIB_DIR}/libcoreaudio_swift.a
    "-L${SWIFT_LIB_PATH}"
    "-lswiftCore"
    "-lswiftFoundation"
    "-lswiftDarwin"
    "-lswiftDispatch"
    "-lswiftCoreFoundation"
    "-lswiftObjectiveC"
    "-framework CoreAudio"
    "-framework AudioToolbox"
    "-framework AVFoundation"
    "-framework Foundation"
    "-framework CoreFoundation"
    "-framework AppKit"
)

# Add node-addon-api
execute_process(
    COMMAND node -p "require('node-addon-api').include"
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    OUTPUT_VARIABLE NODE_ADDON_API_DIR
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
string(REGEX REPLACE "[\"\n]" "" NODE_ADDON_API_DIR ${NODE_ADDON_API_DIR})
target_include_directories(${PROJECT_NAME} PRIVATE ${NODE_ADDON_API_DIR})

# Define NAPI_VERSION
target_compile_definitions(${PROJECT_NAME} PRIVATE NAPI_VERSION=8)
