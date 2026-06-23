# Vendor 说明

## OpenCV2

### 版本
OpenCV 4.10.0

### 产物
`OpenCV2/opencv2.xcframework` — 编译好的 Mac Catalyst xcframework，包含：
- `ios-arm64_x86_64-maccatalyst/libopencv_world_maccatalyst.a`

### 编译脚本

```bash
#!/bin/bash
# 下载源码
cd Vendor/OpenCVBuild
curl -L https://github.com/opencv/opencv/archive/4.10.0.zip -o opencv-4.10.0.zip
unzip opencv-4.10.0.zip

# 编译 arm64 maccatalyst
cmake opencv-4.10.0 \
  -B build-arm64-maccatalyst \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=macosx \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_CXX_FLAGS="-target arm64-apple-ios14.0-macabi" \
  -DCMAKE_C_FLAGS="-target arm64-apple-ios14.0-macabi" \
  -DCMAKE_INSTALL_PREFIX=install-arm64-maccatalyst \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_PERF_TESTS=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_opencv_apps=OFF \
  -DWITH_CUDA=OFF \
  -DWITH_OPENCL=OFF
cmake --build build-arm64-maccatalyst --target install -j$(sysctl -n hw.logicalcpu)

# 编译 x86_64 maccatalyst
cmake opencv-4.10.0 \
  -B build-x86_64-maccatalyst \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=macosx \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_CXX_FLAGS="-target x86_64-apple-ios14.0-macabi" \
  -DCMAKE_C_FLAGS="-target x86_64-apple-ios14.0-macabi" \
  -DCMAKE_INSTALL_PREFIX=install-x86_64-maccatalyst \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_PERF_TESTS=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_opencv_apps=OFF \
  -DWITH_CUDA=OFF \
  -DWITH_OPENCL=OFF
cmake --build build-x86_64-maccatalyst --target install -j$(sysctl -n hw.logicalcpu)

# 合并为 fat library
lipo -create \
  install-arm64-maccatalyst/lib/libopencv_world.a \
  install-x86_64-maccatalyst/lib/libopencv_world.a \
  -output libopencv_world_maccatalyst.a

# 打包成 xcframework
xcodebuild -create-xcframework \
  -library libopencv_world_maccatalyst.a \
  -headers install-arm64-maccatalyst/include \
  -output ../OpenCV2/opencv2.xcframework
```

### 重新编译
需要重新编译时，按上述脚本执行。中间产物（build-*/、install-*/、*.zip、*.a）不入仓库。
