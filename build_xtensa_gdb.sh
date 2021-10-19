#!/bin/bash
set -e

TARGET_HOST=$1
BUILD_PYTHON_VERSION=$2
DESTDIR=$3
GDB_REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
GDB_BUILD_DIR="${GDB_REPO_ROOT}/_build"

if [[ -z $TARGET_HOST  || -z $BUILD_PYTHON_VERSION ]]; then
  echo "Target host and python version must be specified (set python version \"without_python\" to build without python), eg:"
  echo "  ./build_xtensa_gdb.sh i686-w64-mingw32 3.6.0"
  exit 1
fi

if [ -z $DESTDIR ]; then
  DESTDIR="${GDB_REPO_ROOT}/dist"
fi

PLATFORM=
if [[ ${TARGET_HOST} == *"mingw32" ]] ; then
  PLATFORM="windows"
elif  [[ ${TARGET_HOST} == *"apple-darwin"* ]] ; then
  PLATFORM="macos"
else # linux
  PLATFORM="linux"
fi

# Clean build and dist directories
rm -fr $GDB_BUILD_DIR $DESTDIR

# Build xtensa-config libs
cd xtensaconfig
make clean
AR="$TARGET_HOST-ar" CC="$TARGET_HOST-gcc" make install DESTDIR=$DESTDIR PLATFORM=$PLATFORM
cd ..

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

CONFIG_OPTS=" \
--host=$TARGET_HOST \
--target=xtensa-esp-elf \
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
--with-static-standard-libraries \
"

# Makes configure happy if native build
export LD_LIBRARY_PATH="$PYTHON_CROSS_DIR_LIB:$LD_LIBRARY_PATH"

mkdir $GDB_BUILD_DIR && cd $GDB_BUILD_DIR
eval "$GDB_REPO_ROOT/configure $CONFIG_OPTS"

# Build GDB

make
make install DESTDIR=$DESTDIR

#strip binaries. Save user's disc space
${TARGET_HOST}-strip $DESTDIR/bin/xtensa-esp-elf-gdb${EXE}
${TARGET_HOST}-strip $DESTDIR/bin/xtensa-esp-elf-gprof${EXE}

# rename gdb to have python version in filename
if [ $BUILD_PYTHON_VERSION != "without_python" ]; then
	mv $DESTDIR/bin/xtensa-esp-elf-gdb${EXE} $DESTDIR/bin/xtensa-esp-elf-gdb-${BUILD_PYTHON_VERSION%.*}${EXE}
fi
