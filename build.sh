#!/bin/bash

set -e

# Default values
BUILD_TYPE="Release"
BUILD_SYSTEM="cmake"
ENABLE_HIKARI="OFF"
TARGET_OS="mac"

# ./build.sh -s xcode -t Debug -h OFF -o ios
usage() {
  echo "Usage: $0 [-s cmake|xcode] [-t Debug|Release] [-h ON|OFF] [-o mac|ios]"
  echo "  -s  Build system: cmake (default) or xcode"
  echo "  -t  Build type: Debug or Release (default: Release)"
  echo "  -h  Enable Hikari: ON or OFF (default: OFF)"
  echo "  -o  Target OS: mac (default) or ios"
  exit 1
}

# Parse arguments
while getopts "s:t:h:o:" opt; do
  case $opt in
    s) BUILD_SYSTEM="$OPTARG" ;;
    t) BUILD_TYPE="$OPTARG" ;;
    h) ENABLE_HIKARI="$OPTARG" ;;
    o) TARGET_OS="$OPTARG" ;;
    *) usage ;;
  esac
done

PROJECT_ROOT=$(pwd)
if [ "$TARGET_OS" = "mac" ]; then
  SDK_NAME="macosx"
  ARCM_PARAM="-arch arm64 -arch x86_64"
elif [ "$TARGET_OS" = "ios" ]; then
  ARCM_PARAM="-arch arm64 -arch arm64e"
  SDK_NAME="iphoneos"
else
  echo "Unsupported TARGET_OS: $TARGET_OS (must be 'mac' or 'ios')"
  exit 1
fi


# xcodebuild -showsdks
# xcrun --sdk iphoneos --show-sdk-path

# ---- Hikari 工具链解析（cmake / xcode 共用）----
# Hikari 工具链只含 clang，不含 swiftc，因此 Swift 必须始终使用 Xcode 自带编译器。
HIKARI_CC=""
HIKARI_CXX=""
if [ "$ENABLE_HIKARI" = "ON" ]; then
  PATH_Hikari_XCODE="/Applications/Xcode.app/Contents/Developer/Toolchains/Hikari_LLVM20.1.5.xctoolchain/usr/bin"
  PATH_Hikari_USER_LIBRARY="$HOME/Library/Developer/Toolchains/Hikari_LLVM20.1.5.xctoolchain/usr/bin"
  if [ -d "$PATH_Hikari_XCODE" ]; then
    hikari_llvm_bin="$PATH_Hikari_XCODE"
    echo "Using Hikari LLVM from Xcode path: $hikari_llvm_bin"
  elif [ -d "$PATH_Hikari_USER_LIBRARY" ]; then
    hikari_llvm_bin="$PATH_Hikari_USER_LIBRARY"
    echo "Using Hikari LLVM from user Library path: $hikari_llvm_bin"
  else
    echo "Error: No valid path found for Hikari LLVM toolchain."
    echo "Please ensure Hikari_LLVM20.1.5.xctoolchain exists in one of the following directories:"
    echo "  - /Applications/Xcode.app/Contents/Developer/Toolchains/"
    echo "  - ~/Library/Developer/Toolchains/"
    exit 1
  fi
  HIKARI_CC="$hikari_llvm_bin/clang"
  HIKARI_CXX="$hikari_llvm_bin/clang++"
  if [ ! -x "$HIKARI_CC" ]; then
    echo "❌ Hikari clang not found or not executable: $HIKARI_CC"
    exit 1
  fi
  echo "✅ Hikari enabled: using $HIKARI_CC"
else
  echo "ℹ️ Hikari disabled: using default system compiler"
fi
# Apple Swift 编译器（始终来自 XcodeDefault，Hikari 工具链没有 swiftc）
SWIFT_COMPILER="$(xcrun --sdk "$SDK_NAME" -f swiftc 2>/dev/null || xcrun -f swiftc)"

# SDK 路径（cmake / xcode 分支都会用到）
SDK_PATH=$(xcrun --sdk "$SDK_NAME" --show-sdk-path)
if [ -z "$SDK_PATH" ]; then
  echo "Error: Could not determine $SDK_NAME SDK path. Is Xcode or Command Line Tools installed correctly?"
  echo "Please ensure Xcode is installed or run 'xcode-select --install'."
  exit 1
fi
export CMAKE_OSX_SYSROOT="$SDK_PATH"

# Hikari 构建时关闭 Clang modules 会丢失 @import 的“自动链接”，需手动补 -framework。
# 清单与 CMakeLists.txt 中 target_link_libraries 保持一致（mac / ios 分别列出）。
if [ "$TARGET_OS" = "mac" ]; then
  FRAMEWORK_LIST="Foundation CoreFoundation AppKit Cocoa IOKit CloudKit Security CoreWLAN"
else
  FRAMEWORK_LIST="Foundation CoreFoundation UIKit IOKit CloudKit CoreGraphics Security"
fi
FRAMEWORK_LDFLAGS=""
for _fw in $FRAMEWORK_LIST; do
  FRAMEWORK_LDFLAGS="$FRAMEWORK_LDFLAGS -framework $_fw"
done
FRAMEWORK_LDFLAGS="${FRAMEWORK_LDFLAGS# }"

if [ "$BUILD_SYSTEM" = "xcode" ]; then
  echo "🔨 Building with Xcode ($BUILD_TYPE) for $TARGET_OS..."
  DERIVED_DATA_PATH="$PROJECT_ROOT/xcode-build"
  XCODE_ARGS=(
    # -scheme "dylib_dobby_hook_$TARGET_OS"
    -quiet
    -target "dylib_dobby_hook_$TARGET_OS"
    -configuration "$BUILD_TYPE"
    $ARCM_PARAM
    # -derivedDataPath "$DERIVED_DATA_PATH"  
    SYMROOT="$DERIVED_DATA_PATH"
    ONLY_ACTIVE_ARCH=NO
    CODE_SIGN_IDENTITY=""
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGNING_ALLOWED=NO
    COMPILER_INDEX_STORE_ENABLE=NO
    ENABLE_BITCODE=NO
    GCC_OPTIMIZATION_LEVEL=0
  )
  if [ "$ENABLE_HIKARI" = "ON" ]; then
    XCODE_ARGS+=(
      OTHER_CFLAGS="\
        -mllvm -hikari \
        -mllvm -enable-strcry \
        -mllvm -enable-cffobf \
        -mllvm -enable-subobf \
        -mllvm -enable-fco \
        -mllvm -ah_objcruntime \
        -mllvm -ah_inline \
        -mllvm -enable-indibran \
        -mllvm -indibran-enc-jump-target \
        -mllvm -ah_antirebind"
      # Hikari 工具链只含 clang，不含 swiftc，所以只覆盖 C/C++/ObjC 的编译器，
      # Swift 仍使用 Xcode 自带 swiftc（见 SWIFT_COMPILER），避免 TOOLCHAINS 整体切换导致 swift 找不到。
      CC="$HIKARI_CC"
      CXX="$HIKARI_CXX"
      SWIFT_COMPILER="$SWIFT_COMPILER"
      # Hikari clang 版本较旧，无法构建 Xcode 26 SDK 的 Clang 模块（could not build module 'CoreFoundation'），
      # 关闭 modules，C/ObjC 改用文本 #import；Swift 侧由 Xcode swiftc 自行处理，不受影响。
      CLANG_ENABLE_MODULES=NO
      # 关闭 modules 会丢失 @import 的自动链接，这里手动补上源码里引用到的框架。
      OTHER_LDFLAGS="$FRAMEWORK_LDFLAGS"
    )
    echo "✅ Hikari enabled for Xcode (C/ObjC -> Hikari clang, Swift -> Xcode swiftc)."
  else
    echo "ℹ️ Hikari disabled for Xcode."
  fi
  rm -rf "$DERIVED_DATA_PATH"
  xcodebuild -quiet clean -target "dylib_dobby_hook_$TARGET_OS" -configuration "$BUILD_TYPE" SYMROOT="$DERIVED_DATA_PATH"
  xcodebuild "${XCODE_ARGS[@]}"
  PRODUCT_DYLIB="$DERIVED_DATA_PATH/Build/Products/$BUILD_TYPE/libdylib_dobby_hook.dylib"
  echo "✅ Build completed. Product located at: $PRODUCT_DYLIB"

else
  echo "🔨 Building with CMake ($BUILD_TYPE) for $TARGET_OS..."
  BUILD_DIR="$PROJECT_ROOT/cmake-build-$BUILD_TYPE"  
  SDK_PATH=$(xcrun --sdk "$SDK_NAME" --show-sdk-path)
  if [ -z "$SDK_PATH" ]; then
      echo "Error: Could not determine $SDK_NAME SDK path. Is Xcode or Command Line Tools installed correctly?"
      echo "Please ensure Xcode is installed or run 'xcode-select --install'."
      exit 1
  fi
  export CMAKE_OSX_SYSROOT="$SDK_PATH"

  if [ "$ENABLE_HIKARI" = "ON" ]; then
    # cmake 配置期也用 Hikari clang 探测编译器，与真正编译保持一致
    export CC="$HIKARI_CC"
    export CXX="$HIKARI_CXX"
    echo "✅ Hikari enabled: using $CC"
  else
    echo "ℹ️ Hikari disabled: using default system compiler"
  fi

  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"
  # Swift 需要 Xcode 生成器 (CMake 原生 Swift 多架构 + 优雅支持)
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "❌ Error: xcodebuild not found. Xcode is required for Swift support (CMake -G Xcode)."
    exit 1
  fi
  echo "ℹ️ Using Xcode generator (Swift support, multi-arch)"
  if [ "$TARGET_OS" = "mac" ]; then
    ARCH_PARAM="-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64"
    ARCHS_VALUE="x86_64 arm64"
    CONFIG_DIR="$BUILD_TYPE"
  else
    ARCH_PARAM="-DCMAKE_OSX_ARCHITECTURES=arm64;arm64e"
    ARCHS_VALUE="arm64 arm64e"
    # Xcode 生成器: iOS 配置目录带 -iphoneos 后缀 (EFFECTIVE_PLATFORM_NAME)
    CONFIG_DIR="$BUILD_TYPE-iphoneos"
  fi
  cmake -G Xcode -DTARGET_OS="$TARGET_OS" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DENABLE_HIKARI="$ENABLE_HIKARI" -DCMAKE_OSX_SYSROOT="${CMAKE_OSX_SYSROOT}" $ARCH_PARAM "$PROJECT_ROOT"
  XCODE_BUILD_ARGS=(
    -quiet
    -project dylib_dobby_hook.xcodeproj
    -target dylib_dobby_hook
    -configuration "$BUILD_TYPE"
    build
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO ARCHS="$ARCHS_VALUE"
  )
  if [ "$ENABLE_HIKARI" = "ON" ]; then
    # 关键：-G Xcode 生成器会忽略 CC/CXX 环境变量，必须在 xcodebuild 阶段用 build setting 覆盖，
    # 让 C/ObjC 真正走 Hikari clang，同时把 Swift 锁定到 Xcode 自带 swiftc（Hikari 工具链无 swiftc）。
    XCODE_BUILD_ARGS+=( CC="$HIKARI_CC" CXX="$HIKARI_CXX" SWIFT_COMPILER="$SWIFT_COMPILER" CLANG_ENABLE_MODULES=NO )
  fi
  xcodebuild "${XCODE_BUILD_ARGS[@]}"
  DYLIB_PATH="$BUILD_DIR/$CONFIG_DIR/libdylib_dobby_hook.dylib"
  if [ -f "$DYLIB_PATH" ]; then
    mkdir -p "$PROJECT_ROOT/release/$TARGET_OS"
    cp "$DYLIB_PATH" "$PROJECT_ROOT/release/$TARGET_OS/libdylib_dobby_hook.dylib"
  else
    echo "❌ Error: built dylib not found at $DYLIB_PATH"
    exit 1
  fi
  cd "$PROJECT_ROOT"
fi

echo "✅ Project build and installation completed."

FILES=(
  "release"
  "script"
  "tools"
)
EXCLUDE_FILES=(
  "local_apps.json"
  "Organismo-mac.framework"
  "script/apps/IDA/plugins/" # Too Big
)

ARCHIVE_NAME="dylib_dobby_hook.tar.gz"


EXCLUDE_PARAMS=()
for exclude in "${EXCLUDE_FILES[@]}"; do
  EXCLUDE_PARAMS+=(--exclude="$exclude")
done


tar -czf "$ARCHIVE_NAME" "${EXCLUDE_PARAMS[@]}" "${FILES[@]}"

echo "✅ The following files have been packed into $ARCHIVE_NAME:"
for file in "${FILES[@]}"; do
  echo "- $file"
done

file release/$TARGET_OS/libdylib_dobby_hook.dylib
