cmake_minimum_required(VERSION 3.28)

# Define Project and Application name
set(BIN_NAME "vlm_edge_studio")

# Define version info
set(APP_VERSION_MAJOR 1)
set(APP_VERSION_MINOR 0)
set(APP_VERSION_PATCH 0)

# Project definition with version
project(${BIN_NAME}
    VERSION ${APP_VERSION_MAJOR}.${APP_VERSION_MINOR}.${APP_VERSION_PATCH}
    DESCRIPTION "Next-Gen Vision Language Models for Image & Video Analysis"
    LANGUAGES CXX
)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Enable automatic Qt tools
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# Build configuration
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# Compiler-specific options
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(-Wall -Wextra -Wpedantic)
endif()

# Find Qt6 components
find_package(Qt6 6.2 REQUIRED COMPONENTS 
    Concurrent
    Core 
    Quick 
    OpenGL
    Network
)

qt_standard_project_setup(REQUIRES 6.2)

# Find Python and set up dependencies
find_package(Python3 REQUIRED COMPONENTS Interpreter Development)

# Verify Qt6 OpenGL support
if(NOT TARGET Qt6::OpenGL)
    message(FATAL_ERROR "Qt6 OpenGL component is required but not found")
endif()

# Find PkgConfig
find_package(PkgConfig REQUIRED)
if(NOT PKG_CONFIG_FOUND)
    message(FATAL_ERROR "pkg-config is required but not found")
endif()


# Find GStreamer components with proper error handling
pkg_check_modules(GSTREAMER REQUIRED IMPORTED_TARGET gstreamer-1.0>=1.16)
pkg_check_modules(GST_VIDEO REQUIRED IMPORTED_TARGET gstreamer-video-1.0>=1.16)

# Optional GStreamer GL support
pkg_check_modules(GST_GL IMPORTED_TARGET gstreamer-gl-1.0>=1.16)
if(GST_GL_FOUND)
    message(STATUS "GStreamer GL support found: ${GST_GL_VERSION}")
    add_compile_definitions(HAVE_GST_GL)
else()
    message(WARNING "GStreamer GL support not found - some features may be limited")
endif()

# Check for required GStreamer plugins at configure time
find_program(GST_INSPECT gst-inspect-1.0)
if(GST_INSPECT)
    execute_process(
        COMMAND ${GST_INSPECT} videotestsrc
        RESULT_VARIABLE GST_VIDEOTESTSRC_RESULT
        OUTPUT_QUIET ERROR_QUIET
    )
    if(NOT GST_VIDEOTESTSRC_RESULT EQUAL 0)
        message(WARNING "videotestsrc plugin not found - basic functionality may not work")
    endif()
    
    execute_process(
        COMMAND ${GST_INSPECT} appsink
        RESULT_VARIABLE GST_APPSINK_RESULT
        OUTPUT_QUIET ERROR_QUIET
    )
    if(NOT GST_APPSINK_RESULT EQUAL 0)
        message(FATAL_ERROR "appsink plugin not found - this is required for the application")
    endif()
else()
    message(WARNING "gst-inspect-1.0 not found - cannot verify GStreamer plugin availability")
endif()

# Define source files
set(SOURCES
    src/main.cpp
    src/aafconnector.cpp
    src/cameradetector.cpp
    src/gstqmlglsink.cpp
    src/gsttestglsink.cpp
    src/submitprompt.cpp
)

set(HEADERS
    include/aafconnector.h
    include/cameradetector.h
    include/gstqmlglsink.h
    include/gsttestglsink.h
    include/submitprompt.h
)

set(QML_RESOURCES
    qml/resources.qrc
)

# Verify source files exist
foreach(source_file ${SOURCES} ${HEADERS})
    if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${source_file}")
        message(FATAL_ERROR "Source file not found: ${source_file}")
    endif()
endforeach()

# Create executable
add_executable(${PROJECT_NAME}
    ${SOURCES}
    ${HEADERS}
    ${QML_RESOURCES}
)

target_compile_definitions(${BIN_NAME} PRIVATE QT_NO_KEYWORDS)

# Set target properties
set_target_properties(${PROJECT_NAME} PROPERTIES
    OUTPUT_NAME ${BIN_NAME}
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# Target-specific include directories
target_include_directories(${PROJECT_NAME} PRIVATE
    ${Python3_INCLUDE_DIRS}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# Link libraries using modern target-based approach
target_link_libraries(${PROJECT_NAME} PRIVATE
    Qt6::Concurrent
    Qt6::Core
    Qt6::Quick
    Qt6::OpenGL
    Qt6::Network
    PkgConfig::GSTREAMER
    PkgConfig::GST_VIDEO
    ${Python3_LIBRARIES}
)

# Conditionally link GStreamer GL if available
if(GST_GL_FOUND)
    target_link_libraries(${PROJECT_NAME} PRIVATE PkgConfig::GST_GL)
endif()

# Linux-specific settings
target_link_libraries(${PROJECT_NAME} PRIVATE
    ${CMAKE_DL_LIBS}  # For dynamic loading
)

# Handle different OpenGL implementations
find_package(OpenGL REQUIRED)
if(TARGET OpenGL::EGL)
    target_link_libraries(${PROJECT_NAME} PRIVATE OpenGL::EGL)
    add_compile_definitions(HAVE_EGL)
endif()

# Debug/Release specific settings
target_compile_definitions(${PROJECT_NAME} PRIVATE
    $<$<CONFIG:Debug>:DEBUG_BUILD>
    $<$<CONFIG:Release>:NDEBUG>
    APP_VERSION="${PROJECT_VERSION}"
)

# Compiler-specific optimizations
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(${PROJECT_NAME} PRIVATE -O3)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        target_compile_options(${PROJECT_NAME} PRIVATE /O2)
    endif()
endif()

# Print configuration summary
message(STATUS "")
message(STATUS "Configuration Summary:")
message(STATUS "  Project: ${PROJECT_NAME} ${PROJECT_VERSION}")
message(STATUS "  Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  C++ standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "  Qt6 version: ${Qt6_VERSION}")
message(STATUS "  GStreamer version: ${GSTREAMER_VERSION}")
if(GST_GL_FOUND)
    message(STATUS "  GStreamer GL version: ${GST_GL_VERSION}")
else()
    message(STATUS "  GStreamer GL: NOT FOUND")
endif()
message(STATUS "")
