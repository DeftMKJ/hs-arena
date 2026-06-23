#!/usr/bin/env bash
set -euo pipefail

OPENCV_VERSION="${OPENCV_VERSION:-4.10.0}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-15.0}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$ROOT_DIR/Vendor/OpenCVBuild"
VENDOR_DIR="$ROOT_DIR/Vendor/OpenCV2"
SRC_DIR="$WORK_DIR/opencv-$OPENCV_VERSION"
XCFRAMEWORK_PATH="$VENDOR_DIR/opencv2.xcframework"

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake not found. Install it first:"
  echo "  brew install cmake ninja"
  exit 1
fi

if command -v ninja >/dev/null 2>&1; then
  GENERATOR="Ninja"
  BUILD_PARALLEL_ARGS=()
else
  GENERATOR="Unix Makefiles"
  BUILD_PARALLEL_ARGS=(--parallel "$(sysctl -n hw.ncpu)")
fi

mkdir -p "$WORK_DIR" "$VENDOR_DIR"

if [ ! -d "$SRC_DIR" ]; then
  ZIP_PATH="$WORK_DIR/opencv-$OPENCV_VERSION.zip"
  echo "Downloading OpenCV $OPENCV_VERSION..."
  curl -L "https://github.com/opencv/opencv/archive/refs/tags/$OPENCV_VERSION.zip" -o "$ZIP_PATH"
  /usr/bin/ditto -x -k "$ZIP_PATH" "$WORK_DIR"
fi

IMGCODECS_CMAKE="$SRC_DIR/modules/imgcodecs/CMakeLists.txt"
if ! grep -q "CMAKE_CXX_COMPILER_TARGET MATCHES \"macabi\"" "$IMGCODECS_CMAKE"; then
  echo "Patching OpenCV imgcodecs AppKit sources for Mac Catalyst..."
  /usr/bin/python3 - "$IMGCODECS_CMAKE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = "if(APPLE AND (NOT IOS) AND (NOT XROS))"
new = "if(APPLE AND (NOT IOS) AND (NOT XROS) AND NOT CMAKE_CXX_COMPILER_TARGET MATCHES \"macabi\")"
if old not in text:
    raise SystemExit(f"Expected CMake condition not found in {path}")
path.write_text(text.replace(old, new))
PY
fi

build_arch() {
  local arch="$1"
  local target="$arch-apple-ios$DEPLOYMENT_TARGET-macabi"
  local build_dir="$WORK_DIR/build-$arch-maccatalyst"
  local install_dir="$WORK_DIR/install-$arch-maccatalyst"
  local sdk_path
  sdk_path="$(xcrun --sdk macosx --show-sdk-path)"

  echo "Building OpenCV for $target..."
  rm -rf "$build_dir" "$install_dir"
  cmake -S "$SRC_DIR" -B "$build_dir" -G "$GENERATOR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_dir" \
    -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_OSX_SYSROOT="$sdk_path" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_C_COMPILER_TARGET="$target" \
    -DCMAKE_CXX_COMPILER_TARGET="$target" \
    -DCMAKE_C_FLAGS="-target $target" \
    -DCMAKE_CXX_FLAGS="-target $target" \
    -DCMAKE_EXE_LINKER_FLAGS="-target $target" \
    -DCMAKE_SHARED_LINKER_FLAGS="-target $target" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_opencv_world=ON \
    -DBUILD_LIST=core,imgproc,imgcodecs,features2d,flann,calib3d \
    -DBUILD_opencv_highgui=OFF \
    -DBUILD_opencv_videoio=OFF \
    -DBUILD_opencv_objdetect=OFF \
    -DBUILD_opencv_photo=OFF \
    -DBUILD_opencv_video=OFF \
    -DBUILD_opencv_dnn=OFF \
    -DBUILD_opencv_ml=OFF \
    -DBUILD_opencv_gapi=OFF \
    -DBUILD_TESTS=OFF \
    -DBUILD_PERF_TESTS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_opencv_apps=OFF \
    -DBUILD_JAVA=OFF \
    -DBUILD_opencv_python2=OFF \
    -DBUILD_opencv_python3=OFF \
    -DWITH_OPENCL=OFF \
    -DWITH_IPP=OFF \
    -DWITH_ITT=OFF

  if [ "${#BUILD_PARALLEL_ARGS[@]}" -gt 0 ]; then
    cmake --build "$build_dir" --config Release "${BUILD_PARALLEL_ARGS[@]}"
  else
    cmake --build "$build_dir" --config Release
  fi
  cmake --install "$build_dir" --config Release
}

build_arch arm64
build_arch x86_64

rm -rf "$XCFRAMEWORK_PATH"

UNIVERSAL_LIB="$WORK_DIR/libopencv_world_maccatalyst.a"
rm -f "$UNIVERSAL_LIB"
lipo -create \
  "$WORK_DIR/install-arm64-maccatalyst/lib/libopencv_world.a" \
  "$WORK_DIR/install-x86_64-maccatalyst/lib/libopencv_world.a" \
  -output "$UNIVERSAL_LIB"

xcodebuild -create-xcframework \
  -library "$UNIVERSAL_LIB" \
  -headers "$WORK_DIR/install-arm64-maccatalyst/include/opencv4" \
  -output "$XCFRAMEWORK_PATH"

echo "Done: $XCFRAMEWORK_PATH"
