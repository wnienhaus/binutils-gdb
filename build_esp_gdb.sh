#!/bin/bash
set -e

TARGET_HOST=$1
ESP_CHIP_ARCHITECTURE=$2
BUILD_PYTHON_VERSION=$3
GDB_DIST=$4
GDB_REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
GDB_BUILD_DIR="${GDB_REPO_ROOT}/_build"

if [[ -z $TARGET_HOST  || -z $BUILD_PYTHON_VERSION || -z $ESP_CHIP_ARCHITECTURE ]]; then
  echo "Target host, chip arch and python version must be specified (set python version \"without_python\" to build without python), eg:"
  echo "  ./build_esp_gdb.sh i686-w64-mingw32 xtensa 3.6.0"
  exit 1
fi

if [ -z $GDB_DIST ]; then
  GDB_DIST="${GDB_REPO_ROOT}/dist"
fi

PLATFORM=
if [[ ${TARGET_HOST} == *"mingw32" ]] ; then
  PLATFORM="windows"
elif  [[ ${TARGET_HOST} == *"apple-darwin"* ]] ; then
  PLATFORM="macos"
else # linux
  PLATFORM="linux"
fi

# Prepare build configure variables
if [ $BUILD_PYTHON_VERSION != "without_python" ]; then
	PYTHON_CROSS_DIR=/opt/python-$TARGET_HOST-$BUILD_PYTHON_VERSION
	PYTHON_CROSS_DIR_INCLUDE=`find $PYTHON_CROSS_DIR -name Python.h | xargs -n1 dirname`
fi
PYTHON_CROSS_DIR_LIB=
PYTHON_CROSS_LINK_FLAG=
PYTHON_LIB_POINT=
PYTHON_LIB_SUFFIX=
PYTHON_LIB_PREFIX=
EXE=
if [[ ${PLATFORM} == "windows" ]] ; then
  PYTHON_LIB_SUFFIX=".dll"
  EXE=".exe"
elif  [[ ${PLATFORM} == "macos" ]] ; then
  PYTHON_LIB_POINT="."
  PYTHON_LIB_SUFFIX=".dylib"
  PYTHON_LIB_PREFIX="lib"
else # linux
  PYTHON_LIB_POINT="."
  PYTHON_LIB_SUFFIX=".so"
  PYTHON_LIB_PREFIX="lib"
fi

# Clean build and dist directories
rm -fr $GDB_BUILD_DIR $GDB_DIST

# Build xtensa-config libs
pushd xtensaconfig
make clean
CROSS_COMPILE="$TARGET_HOST-" TARGET_ESP_ARCH=${ESP_CHIP_ARCHITECTURE} DESTDIR=$GDB_DIST PLATFORM=$PLATFORM make install
popd

# Temporary rename wrapper
mv $GDB_DIST/bin/${ESP_CHIP_ARCHITECTURE}-esp-elf-gdb${EXE} ${GDB_DIST}/bin/${ESP_CHIP_ARCHITECTURE}-esp-elf-gdb-wrapper${EXE} 2> /dev/null || true

PYTHON_CONFIG_OPTS=
if [ $BUILD_PYTHON_VERSION != "without_python" ]; then
	PYTHON_CROSS_LIB_PATH=$(find $PYTHON_CROSS_DIR -name ${PYTHON_LIB_PREFIX}python3${PYTHON_LIB_POINT}[0-9]*${PYTHON_LIB_SUFFIX} | head -1)
	PYTHON_CROSS_LINK_FLAG=$(basename $PYTHON_CROSS_LIB_PATH)
	PYTHON_CROSS_LINK_FLAG="${PYTHON_CROSS_LINK_FLAG%$PYTHON_LIB_SUFFIX}"
	PYTHON_CROSS_LINK_FLAG="-l${PYTHON_CROSS_LINK_FLAG#$PYTHON_LIB_PREFIX}"
	PYTHON_CROSS_DIR_LIB=$(dirname $PYTHON_CROSS_LIB_PATH)
	PYTHON_LDFLAGS="-L$PYTHON_CROSS_DIR_LIB $PYTHON_CROSS_LINK_FLAG -Wno-unused-result -Wsign-compare -DNDEBUG -g -fwrapv -O3 -Wall -Wstrict-prototypes"
	PYTHON_CONFIG_OPTS="--with-python \
--with-python-libdir=$PYTHON_CROSS_DIR/lib \
--with-python-includes=-I$PYTHON_CROSS_DIR_INCLUDE \
--with-python-ldflags=\"$PYTHON_LDFLAGS\""
else
	PYTHON_CONFIG_OPTS="--without-python"
fi

WITH_XTENSACONFIG_OPTS=
if [ $ESP_CHIP_ARCHITECTURE == "xtensa" ]; then
  WITH_XTENSACONFIG_OPTS="--with-xtensaconfig"
fi

CONFIG_OPTS=" \
--host=$TARGET_HOST \
--target=${ESP_CHIP_ARCHITECTURE}-esp-elf \
--build=`gcc -dumpmachine` \
--disable-werror \
--with-expat \
--with-libexpat-prefix=/opt/expat-$TARGET_HOST \
--disable-threads \
--disable-sim \
--disable-nls \
--disable-binutils \
--disable-ld \
--disable-gas \
--disable-source-highlight \
--prefix=/ \
--with-gmp=/opt/gmp-$TARGET_HOST \
--with-libgmp-prefix=/opt/gmp-$TARGET_HOST \
--with-mpc=/opt/mpc-$TARGET_HOST \
--without-mpfr \
${PYTHON_CONFIG_OPTS} \
${WITH_XTENSACONFIG_OPTS} \
--with-libexpat-type=static \
--with-liblzma-type=static \
--with-libgmp-type=static \
--with-static-standard-libraries \
--with-pkgversion="esp-gdb" \
--with-curses \
--enable-tui \
"

# Makes configure happy if native build
export LD_LIBRARY_PATH="$PYTHON_CROSS_DIR_LIB:$LD_LIBRARY_PATH"

# Link with static libncurses
export CFLAGS="-I/opt/ncurses-$TARGET_HOST/include"
export CXXFLAGS="-I/opt/ncurses-$TARGET_HOST/include"
export LDFLAGS="-L/opt/ncurses-$TARGET_HOST/lib"

if [[ ${PLATFORM} == "linux" ]] ; then
  export CFLAGS="$CFLAGS -Wno-psabi"
  export CXXFLAGS="$CXXFLAGS -Wno-psabi"
fi

mkdir $GDB_BUILD_DIR && cd $GDB_BUILD_DIR
eval "$GDB_REPO_ROOT/configure $CONFIG_OPTS"

# Build GDB

make
make install DESTDIR=$GDB_DIST

#strip binaries. Save user's disc space
${TARGET_HOST}-strip $GDB_DIST/bin/${ESP_CHIP_ARCHITECTURE}-esp-elf-gdb${EXE}
${TARGET_HOST}-strip $GDB_DIST/bin/${ESP_CHIP_ARCHITECTURE}-esp-elf-gprof${EXE}

GDB_PROGRAM_SUFFIX=
if [ $BUILD_PYTHON_VERSION == "without_python" ]; then
  GDB_PROGRAM_SUFFIX="no-python"
else
  GDB_PROGRAM_SUFFIX=${BUILD_PYTHON_VERSION%.*}
fi

# rename gdb to have python version in filename
mv $GDB_DIST/bin/${ESP_CHIP_ARCHITECTURE}-esp-elf-gdb${EXE} $GDB_DIST/bin/${ESP_CHIP_ARCHITECTURE}-esp-elf-gdb-${GDB_PROGRAM_SUFFIX}${EXE}

# rename wrapper to original gdb name
mv $GDB_DIST/bin/${ESP_CHIP_ARCHITECTURE}-esp-elf-gdb-wrapper${EXE} $GDB_DIST/bin/${ESP_CHIP_ARCHITECTURE}-esp-elf-gdb${EXE} 2> /dev/null || true
