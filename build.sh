#!/usr/bin/env bash

# Copyright 2025-2026 NXP

# NXP Proprietary. This software is owned or controlled by NXP and may only be
# used strictly in accordance with the applicable license terms.  By expressly
# accepting such terms or by downloading, installing, activating and/or
# otherwise using the software, you are agreeing that you have read, and that
# you agree to comply with and are bound by, such license terms.  If you do
# not agree to be bound by the applicable license terms, then you may not
# retain, install, activate or otherwise use the software.

set -e # Exit on any error

TOOLCHAIN_PATH="$1"
BUILD_DIR="build"
PACKAGE_DIR="vlm-edge-studio"
GUI_PACKAGE_DIR="vlm-edge-studio"
BIN_NAME="vlm_edge_studio"

# Extract sysroot path from toolchain path
# Remove the filename (environment-setup-armv8a-poky-linux) and append sysroots
SYSROOT_BASE=$(dirname "$TOOLCHAIN_PATH")/sysroots

# Python3 configuration variables using extracted sysroot path
PYTHON3_INCLUDE_DIR="$SYSROOT_BASE/armv8a-poky-linux/usr/include/python3.13"
PYTHON3_LIBRARY="$SYSROOT_BASE/armv8a-poky-linux/usr/lib/libpython3.13.so"
PYTHON3_EXECUTABLE="$SYSROOT_BASE/x86_64-pokysdk-linux/usr/bin/python3.13"

RED='\033[1;31m'
NC='\033[0m' # No Color

PACKAGE="📦"
WRENCH="🔧"
DRINK="🍺"

if [ -z "$TOOLCHAIN_PATH" ]; then
	echo "Usage: $0 <toolchain_path>"
	exit 1
fi
if [ ! -e "$TOOLCHAIN_PATH" ]; then
	echo "Error: Path '$TOOLCHAIN_PATH' does not exist."
	echo -e "${RED}ERROR:${NC} Path '$TOOLCHAIN_PATH' does not exist."
	exit 1
fi

echo "Toolchain path '$TOOLCHAIN_PATH' exists. Sourcing for cross-compilation."
echo "Using sysroot base: $SYSROOT_BASE"

# Source your toolchain
source "$TOOLCHAIN_PATH"

# Create build directory
if [ ! -d "$BUILD_DIR" ]; then
	echo "Creating build directory..."
	echo "Creating build directory for $PACKAGE_DIR..."
	mkdir "$BUILD_DIR"
else
	echo "Reusing existing build directory..."
	echo "Reusing existing build directory for $PACKAGE_DIR..."
fi

# Navigate into build
cd "$BUILD_DIR"

# Run CMake with Python3 configuration
echo " $WRENCH Running CMake..."
cmake -DCMAKE_BUILD_TYPE=Release \
	-DPython3_INCLUDE_DIR="$PYTHON3_INCLUDE_DIR" \
	-DPython3_LIBRARY="$PYTHON3_LIBRARY" \
	-DPython3_EXECUTABLE="$PYTHON3_EXECUTABLE" \
	.. || {
	echo -e "${RED}ERROR:${NC} CMake failed for $PACKAGE_DIR"
	exit 1
}

# Compile with make
echo "$WRENCH Compiling..."
make -j$(nproc) || {
	echo -e "${RED}ERROR:${NC} Compilation failed for $PACKAGE_DIR"
	exit 1
}

echo "Build $BIN_NAME completed successfully."

# Move to root path of repository
cd ../

# Move the binary to GUI package directory
echo "Moving binary to package directory..."
if [ ! -d "$PACKAGE_DIR/usr/share/$PACKAGE_DIR/" ]; then
	echo "Creating directory structure for package..."
	mkdir -p "$PACKAGE_DIR/usr/share/$PACKAGE_DIR/"
fi

if [ -f "$BUILD_DIR/bin/$BIN_NAME" ]; then
	cp "$BUILD_DIR/bin/$BIN_NAME" "$PACKAGE_DIR/usr/share/$PACKAGE_DIR/"
	echo "Binary moved to $PACKAGE_DIR/usr/share/$PACKAGE_DIR/$BIN_NAME"
else
	echo -e "${RED}ERROR:${NC} Binary $BUILD_DIR/bin/$BIN_NAME not found."
	exit 1
fi

# Build deb package
if [ ! -d "$PACKAGE_DIR" ]; then
	echo -e "${RED}ERROR:${NC} Package directory '$PACKAGE_DIR' not found."
	exit 1
fi

echo "$PACKAGE Creating DEB package..."
echo "$DRINK Grab a drink..."
dpkg-deb --build "$PACKAGE_DIR" || {
	echo "DEB package creation failed"
	exit 1
}
echo "Build and packaging completed successfully."
