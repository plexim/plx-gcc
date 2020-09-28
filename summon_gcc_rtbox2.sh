#!/bin/bash

# Written by Uwe Hermann <uwe@hermann-uwe.de>, released as public domain.
# Modified by Piotr Esden-Tempski <piotr@esden.net>, released as public domain.

#
# Requirements (example is for Debian, replace package names as needed):
#
# sudo apt-get install build-essential git flex bison libgmp3-dev libmpfr-dev libncurses5-dev libmpc-dev autoconf texinfo libtool libftdi-dev libusb-1.0-0-dev
# sudo apt-get build-dep gcc-4.5
#

# Stop if any command fails
set -e

##############################################################################
# Default settings section
# You probably want to customize those
# You can also pass them as parameters to the script
##############################################################################
TARGET=aarch64-none-elf		# Or: TARGET=arm-elf
PREFIX=/opt/a53/${TARGET}	# Install location of your final toolchain
LOCALLIB=`pwd`/locallib
DARWIN_OPT_PATH=/sw	# Path in which MacPorts or Fink is installed
# Set to 'sudo' if you need superuser privileges while installing
SUDO=
# Set to 1 to be quieter while running
QUIET=0
# Set to 1 to use linaro gcc instead of the FSF gcc
USE_LINARO=1
# Set to 1 to enable building of OpenOCD
OOCD_EN=0
# Set to 1 to enable building of GDB
GDB_EN=0
# Set to 'master' or a git revision number to use instead of stable version
OOCD_GIT=master
# ${MAKE} the gcc default to Cortex-M3
DEFAULT_TO_CORTEX_M3=0
# Override automatic detection of cpus to compile on
#CPUS=4

MAKE=make

##############################################################################
# Parsing command line parameters
##############################################################################

while [ $# -gt 0 ]; do
	case $1 in
		TARGET=*)
		TARGET=$(echo $1 | sed 's,^TARGET=,,')
		;;
		PREFIX=*)
		PREFIX=$(echo $1 | sed 's,^PREFIX=,,')
		;;
		DARWIN_OPT_PATH=*)
		DARWIN_OPT_PATH=$(echo $1 | sed 's,^DARWIN_OPT_PATH=,,')
		;;
		SUDO=*)
		SUDO=$(echo $1 | sed 's,^SUDO=,,')
		;;
		QUIET=*)
		QUIET=$(echo $1 | sed 's,^QUIET=,,')
		;;
		USE_LINARO=*)
		USE_LINARO=$(echo $1 | sed 's,^USE_LINARO=,,')
		;;
		OOCD_EN=*)
		OOCD_EN=$(echo $1 | sed 's,^OOCD_EN=,,')
		;;
		OOCD_GIT=*)
		OOCD_GIT=$(echo $1 | sed 's,^OOCD_GIT=,,')
		;;
		DEFAULT_TO_CORTEX_M3=*)
		DEFAULT_TO_CORTEX_M3=$(echo $1 | sed 's,^DEFAULT_TO_CORTEX_M3=,,')
		;;
		CPUS=*)
		CPUS=$(echo $1 | sed 's,^CPUS=,,')
		;;
		*)
		echo "Unknown parameter: $1"
		exit 1
		;;
	esac

	shift # shifting parameter list to access the next one
done

echo "Settings used for this build are:"
echo "TARGET=$TARGET"
echo "PREFIX=$PREFIX"
echo "DARWIN_OPT_PATH=$DARWIN_OPT_PATH"
echo "SUDO=$SUDO"
echo "QUIET=$QUIET"
echo "USE_LINARO=$USE_LINARO"
echo "OOCD_EN=$OOCD_EN"
echo "OOCD_GIT=$OOCD_GIT"
echo "DEFAULT_TO_CORTEX_M3=$DEFAULT_TO_CORTEX_M3"
echo "CPUS=$CPUS"

##############################################################################
# Version and download url settings section
##############################################################################
if [ ${USE_LINARO} == 0 ] ; then
	# For FSF GCC:
	GCCVERSION=4.5.2
	GCC=gcc-${GCCVERSION}
	GCCURL=http://ftp.gnu.org/gnu/gcc/${GCC}/${GCC}.tar.gz

	# For FSF GDB:
	GDBVERSION=7.3.1
	GDB=gdb-${GDBVERSION}
	GDBURL=http://ftp.gnu.org/gnu/gdb/${GDB}.tar.bz2
else
	# For Linaro GCC:
	GCCRELEASE=8.3-2019.03
	GCCVERSION=8.3-2019.03
	GCC=gcc-arm-src-snapshot-${GCCVERSION}
	GCCURL=https://developer.arm.com/-/media/Files/downloads/gnu-a/${GCCRELEASE}/srcrel/${GCC}.tar.xz

	# For Linaro GDB:
	GDBRELEASE=7.6-2013.05
	GDBVERSION=7.6-2013.05
	GDB=gdb-linaro-${GDBVERSION}
	GDBURL=http://launchpad.net/gdb-linaro/7.6/${GDBRELEASE}/+download/${GDB}.tar.bz2
fi

BINUTILS=binutils-2.31.1
NEWLIB=newlib-3.1.0.20181231
OOCD=openocd-0.6.0
LIBCMSIS=
LIBCMSIS_GIT=v1.10-3
LIBGMP=gmp-6.1.2
LIBMPFR=mpfr-4.0.2
LIBMPC=mpc-1.1.0
LIBISL=isl-0.19
CONFFLAGS=

##############################################################################
# Flags section
##############################################################################

if [ "x${CPUS}" == "x" ]; then
	if which getconf > /dev/null; then
		CPUS=$(getconf _NPROCESSORS_ONLN)
	else
		CPUS=1
	fi

	PARALLEL=-j$((CPUS + 1))
else
	PARALLEL=-j${CPUS}
fi

echo "${CPUS} cpu's detected running ${MAKE} with '${PARALLEL}' flag"

GDBFLAGS=
BINUTILFLAGS=

if [ ${DEFAULT_TO_CORTEX_M3} == 0 ] ; then
	GCCFLAGS=
else
	# To default to the Cortex-M3:
	GCCFLAGS="--with-arch=armv7-m --with-mode=thumb --with-float=soft"
fi

# Pull in the local configuration, if any
if [ -f local.sh ]; then
    . ./local.sh
fi

MAKEFLAGS=${PARALLEL}
TARFLAGS=v

if [ ${QUIET} != 0 ]; then
    TARFLAGS=
    MAKEFLAGS="${MAKEFLAGS} -s"
fi

export PATH="${PREFIX}/bin:${PATH}"

SUMMON_DIR=$(pwd)
SOURCES=${SUMMON_DIR}/sources
STAMPS=${SUMMON_DIR}/stamps


##############################################################################
# Tool section
##############################################################################
TAR=tar

##############################################################################
# OS and Tooldetection section
# Detects which tools and flags to use
##############################################################################

case "$(uname)" in
	Linux)
	echo "Found Linux OS."
	GCCFLAGS="${GCCFLAGS} \
                  --with-gmp=${LOCALLIB} \
	          --with-mpfr=${LOCALLIB} \
	          --with-mpc=${LOCALLIB} \
                  --with-system-zlib"
        CONFFLAGS="--build=x86_64-pc-linux-gnu \
                   --host=x86_64-pc-linux-gnu"
        LOCAL_CFLAGS="-O2"
	CPUS=4
	FETCH="wget -c --no-check-certificate"
	;;
	Darwin)
	echo "Found Darwin OS."
	GCCFLAGS="${GCCFLAGS} \
                  --with-gmp=${LOCALLIB} \
	          --with-mpfr=${LOCALLIB} \
	          --with-mpc=${LOCALLIB} \
              --with-system-zlib"
    CONFFLAGS="--build=x86_64-apple-darwin \
               --host=x86_64-apple-darwin"
    LOCAL_CFLAGS="-O2 -fbracket-depth=1024"
	OOCD_CFLAGS="-I/opt/mine/include -I${DARWIN_OPT_PATH}/include"
	OOCD_LDFLAGS="-L/opt/mine/lib -L${DARWIN_OPT_PATH}/lib"
	CPUS=7
	if gcc --version | grep llvm-gcc > /dev/null ; then
		echo "Found you are using llvm gcc, switching to clang for gcc compile."
		GCC_CC=clang
	fi
	FETCH="curl -LO"
	;;
	CYGWIN*)
	echo "Found CygWin that means Windows most likely."
	;;
	MINGW32*)
	echo "Found MinGW that means Windows most likely."
	GCCFLAGS="${GCCFLAGS} \
                  --with-gmp=${LOCALLIB} \
	          --with-mpfr=${LOCALLIB} \
	          --with-mpc=${LOCALLIB}"
    CONFFLAGS="--build=i686-pc-mingw32 \
               --host=i686-pc-mingw32"
    LOCAL_CFLAGS="-O2"
	LOCAL_LDFLAGS_GCC=-Wl,-Bstatic,-liconv
	LOCAL_LDFLAGS_GDB=-Wl,-Bstatic,-liconv,-lintl
	CPUS=0
    MAKEFLAGS=
	FETCH="curl -LO"
    GCC_CC="gcc -static-libgcc"
    GCC_CXX="c++ -static-libgcc"
	;;
	*)
	echo "Found unknown OS. Aborting!"
	exit 1
	;;
esac

##############################################################################
# Building section
# You probably don't have to touch anything after this
##############################################################################

# Fetch a versioned file from a URL
function fetch {
    if [ ! -e ${STAMPS}/$1.fetch ]; then
        log "Downloading $1 sources..."
        ${FETCH} $2 && touch ${STAMPS}/$1.fetch
    fi
}

function clone {
    local NAME=$1
    local GIT_REF=$2
    local GIT_URL=$3
    local POST_CLONE=$4
    local GIT_SHA=$(git ls-remote ${GIT_URL} ${GIT_REF} | cut -f 1)

    # It seems that the ref is actually a SHA as it could not be found through ls-remote
    if [ "x${GIT_SHA}" == "x" ]; then
        local GIT_SHA=${GIT_REF}
    fi

    # Setting uppercase NAME variable for future use to the source file name
    eval $(echo ${NAME} | tr "[:lower:]" "[:upper:]")=${NAME}-${GIT_SHA}

    # Clone the repository and do all necessary operations until we get an archive
    if [ ! -e ${STAMPS}/${NAME}-${GIT_SHA}.fetch ]; then
        # Making sure there is nothing in our way
        if [ -e ${NAME}-${GIT_SHA} ]; then
            log "The clone directory ${NAME}-${GIT_SHA} already exists, removing..."
            rm -rf ${NAME}-${GIT_SHA}
        fi
        log "Cloning ${NAME}-${GIT_SHA} ..."
        git clone ${GIT_URL} ${NAME}-${GIT_SHA}
        cd ${NAME}-${GIT_SHA}
        log "Checking out the revision ${GIT_REF} with the SHA ${GIT_SHA} ..."
        git checkout -b sat-branch ${GIT_SHA}
	if [ "x${POST_CLONE}" != "x" ]; then
		log "Running post clone code for ${NAME}-${GIT_SHA} ..."
		${POST_CLONE}
	fi
        log "Removing .git directory from ${NAME}-${GIT_SHA} ..."
        rm -rf .git
        cd ..
        log "Generating source archive for ${NAME}-${GIT_SHA} ..."
        tar cfj ${SOURCES}/${NAME}-${GIT_SHA}.tar.bz2 ${NAME}-${GIT_SHA}
        rm -rf ${NAME}-${GIT_SHA}
        touch ${STAMPS}/${NAME}-${GIT_SHA}.fetch
    fi
}

# Log a message out to the console
function log {
    echo "******************************************************************"
    echo "* $*"
    echo "******************************************************************"
}

# Unpack an archive
function unpack {
    log Unpacking $*
    # Use 'auto' mode decompression.  Replace with a switch if tar doesn't support -a
    ARCHIVE=$(ls ${SOURCES}/$1.tar.*)
    case ${ARCHIVE} in
	*.bz2)
	    echo "archive type bz2"
	    TYPE=j
	    ;;
	*.xz)
	    echo "archive type xz"
	    TYPE=J
	    ;;
	*.gz)
	    echo "archive type gz"
	    TYPE=z
	    ;;
	*)
	    echo "Unknown archive type of $1"
	    echo ${ARCHIVE}
	    exit 1
	    ;;
    esac
    "${TAR}" xf${TYPE}${TARFLAGS} ${SOURCES}/$1.tar.* --no-same-owner
}

# Install a build
function install {
    log $1
    ${SUDO} ${MAKE} $2 $3 $4 $5 $6 $7 $8
}


mkdir -p ${STAMPS} ${SOURCES}

cd ${SOURCES}

fetch ${BINUTILS} http://ftp.gnu.org/gnu/binutils/${BINUTILS}.tar.bz2
fetch ${GCC} ${GCCURL}
fetch ${NEWLIB} ftp://sourceware.org/pub/newlib/${NEWLIB}.tar.gz
fetch ${GDB} ${GDBURL}
fetch ${LIBGMP} https://gmplib.org/download/gmp/${LIBGMP}.tar.xz
fetch ${LIBMPFR} https://www.mpfr.org/mpfr-current/${LIBMPFR}.tar.bz2
fetch ${LIBMPC} ftp://ftp.gnu.org/gnu/mpc/${LIBMPC}.tar.gz
fetch ${LIBISL} http://isl.gforge.inria.fr/${LIBISL}.tar.bz2

if [ ${OOCD_EN} != 0 ]; then
	if [ "x${OOCD_GIT}" == "x" ]; then
		fetch ${OOCD} http://sourceforge.net/projects/openocd/files/openocd/0.5.0/${OOCD}.tar.bz2
	else
		clone oocd ${OOCD_GIT} git://openocd.git.sourceforge.net/gitroot/openocd/openocd ./bootstrap
	fi
fi

cd ${SUMMON_DIR}

if [ ! -e build ]; then
    mkdir build
fi

if [ ! -e ${STAMPS}/${BINUTILS}.build ]; then
    unpack ${BINUTILS}
    # http://trac.cross-lfs.org/ticket/926
    # Fix a couple of syntax errors that prevent the documentation from building with Texinfo-5.1:
    #sed -i -e 's/@colophon/@@colophon/' -e 's/doc@cygnus.com/doc@@cygnus.com/' \
	#${BINUTILS}/bfd/doc/bfd.texinfo
    if [[ "$(uname)" == MINGW32* ]]
    then
        cd ${BINUTILS}
        patch -p0 < ../patches/libiberty.patch
        cd ..
    fi

    cd build
    log "Configuring ${BINUTILS}"
    ../${BINUTILS}/configure ${CONFFLAGS} \
                             --target=${TARGET} \
                             --prefix=${PREFIX} \
                             --disable-multilib \
                             --with-gnu-as \
                             --with-gnu-ld \
                             --disable-nls \
                             --disable-werror \
                             ${BINUTILFLAGS}
    log "Building ${BINUTILS}"
    ${MAKE} ${MAKEFLAGS}
    install ${BINUTILS} install
    cd ..
    log "Cleaning up ${BINUTILS}"
    touch ${STAMPS}/${BINUTILS}.build
    rm -rf build/* ${BINUTILS}
fi

if [ ! -e ${LOCALLIB} ]; then
    mkdir ${LOCALLIB}
fi

if [ ! -e ${STAMPS}/${LIBGMP}.build ]; then
    unpack ${LIBGMP}
    cd build
    log "Configuring ${LIBGMP}"
    ../${LIBGMP}/configure ${CONFFLAGS} \
                           --prefix=${LOCALLIB} \
                           --disable-shared \
                           --enable-cxx
    log "Building ${LIBGMP}"
    ${MAKE} ${MAKEFLAGS}
    install ${LIBGMP} install
    cd ..
    log "Cleaning up ${LIBGMP}"
    touch ${STAMPS}/${LIBGMP}.build
    rm -rf build/* ${LIBGMP}
fi

if [ ! -e ${STAMPS}/${LIBMPFR}.build ]; then
    unpack ${LIBMPFR}
    cd build
    log "Configuring ${LIBMPFR}"
    ../${LIBMPFR}/configure ${CONFFLAGS} \
                            --prefix=${LOCALLIB} \
    					    --with-gmp=${LOCALLIB} \
                            --disable-shared 
    log "Building ${LIBMPFR}"
    ${MAKE} ${MAKEFLAGS}
    install ${LIBMPFR} install
    cd ..
    log "Cleaning up ${LIBMPFR}"
    touch ${STAMPS}/${LIBMPFR}.build
    rm -rf build/* ${LIBMPFR}
fi

if [ ! -e ${STAMPS}/${LIBMPC}.build ]; then
    unpack ${LIBMPC}
    cd build
    log "Configuring ${LIBMPC}"
    ../${LIBMPC}/configure ${CONFFLAGS} \
                           --prefix=${LOCALLIB} \
    					   --with-gmp=${LOCALLIB} \
    					   --with-mpfr=${LOCALLIB} \
                           --disable-shared 
    log "Building ${LIBMPC}"
    ${MAKE} ${MAKEFLAGS}
    install ${LIBMPC} install
    cd ..
    log "Cleaning up ${LIBMPC}"
    touch ${STAMPS}/${LIBMPC}.build
    rm -rf build/* ${LIBMPC}
fi

if [ ! -e ${STAMPS}/${LIBISL}.build ]; then
    unpack ${LIBISL}
    cd build
    log "Configuring ${LIBISL}"
    ../${LIBISL}/configure ${CONFFLAGS} \
                           --prefix=${LOCALLIB} \
    					   --with-gmp-prefix=${LOCALLIB} \
                           --disable-shared 
    log "Building ${LIBISL}"
    ${MAKE} ${MAKEFLAGS}
    install ${LIBISL} install
    cd ..
    log "Cleaning up ${LIBISL}"
    touch ${STAMPS}/${LIBISL}.build
    rm -rf build/* ${LIBISL}
fi


if [ ! -e ${STAMPS}/${GCC}-${NEWLIB}.build ]; then
    unpack ${GCC}
    unpack ${NEWLIB}

    log "Adding newlib symlink to gcc"
    ln -f -s `pwd`/${NEWLIB}/newlib ${GCC}
    log "Adding libgloss symlink to gcc"
    ln -f -s `pwd`/${NEWLIB}/libgloss ${GCC}
    
		log "Patching gcc to stop linking against crt0.o"
		cd ${GCC}
		patch -p1 -i ../patches/nocrt0.patch
		cd ..

    if [[ "$(uname)" == MINGW32* ]]
    then
        patch -p0 < patches/gcc-mingw.patch
    fi
    cd build
    if [ "X${GCC_CC}" != "X" ] ; then
	    export GLOBAL_CC=${CC}
	    log "Overriding the default compiler with: \"${GCC_CC}\""
	    export CC=${GCC_CC}
    fi
    if [ "X${GCC_CXX}" != "X" ] ; then
	    export GLOBAL_CXX=${CXX}
	    log "Overriding the default compiler with: \"${GCC_CC}\""
	    export CXX=${GCC_CXX}
    fi

    log "Configuring ${GCC} and ${NEWLIB}"
    CFLAGS=$LOCAL_CFLAGS CXXFLAGS=$LOCAL_CFLAGS LDFLAGS=$LOCAL_LDFLAGS_GCC \
    READELF_FOR_TARGET=${PREFIX}/bin/${TARGET}-readelf \
       ../${GCC}/configure ${CONFFLAGS} \
                           --target=${TARGET} \
                      --prefix=${PREFIX} \
                      --disable-multilib \
                      --enable-languages="c,lto" \
                      --with-isl=${LOCALLIB} \
                      --with-newlib CFLAGS=-O3 CXXFLAGS=-O3 \
                      --disable-newlib-supplied-syscalls \
                      --with-gnu-as \
                      --with-gnu-ld \
                      --disable-nls \
                      --disable-shared \
                      --enable-threads \
                      --enable-lto \
                      --with-headers=newlib/libc/include \
                      --disable-libssp \
                      --disable-libstdcxx-pch \
                      --disable-libmudflap \
                      --disable-libgomp \
                      --disable-werror \
                      --disable-nls \
                      ${GCCFLAGS}
    log "Building ${GCC} and ${NEWLIB}"
    ${MAKE} ${MAKEFLAGS}
    install ${GCC} install
    cd ..
    log "Cleaning up ${GCC} and ${NEWLIB}"

    if [ "X${GCC_CC}" != "X" ] ; then
	    unset CC
	    CC=${GLOBAL_CC}
	    unset GLOBAL_CC
    fi
    if [ "X${GCC_CXX}" != "X" ] ; then
	    unset CXX
	    CXX=${GLOBAL_CXX}
	    unset GLOBAL_CXX
    fi


    touch ${STAMPS}/${GCC}-${NEWLIB}.build
    rm -rf build/* ${GCC} ${NEWLIB}
fi

if [ ${GDB_EN} != 0 ]; then
if [ ! -e ${STAMPS}/${GDB}.build ]; then
    unpack ${GDB}
    cd build
    log "Configuring ${GDB}"
    CFLAGS=$LOCAL_CFLAGS CXXFLAGS=$LOCAL_CFLAGS LDFLAGS=$LOCAL_LDFLAGS_GDB \
       ../${GDB}/configure ${CONFFLAGS} \
                        --target=${TARGET} \
                        --prefix=${PREFIX} \
                        --disable-multilib \
                        --disable-werror \
		      ${GDBFLAGS}
    log "Building ${GDB}"
    ${MAKE} ${MAKEFLAGS}
    install ${GDB} install
    cd ..
    log "Cleaning up ${GDB}"
    touch ${STAMPS}/${GDB}.build
    rm -rf build/* ${GDB}
fi
fi

if [ ${OOCD_EN} != 0 ]; then
if [ ! -e ${STAMPS}/${OOCD}.build ]; then
    unpack ${OOCD}
    
    cd build 
    log "Configuring openocd-${OOCD}"
    CFLAGS="${CFLAGS} ${OOCD_CFLAGS}" \
    LDFLAGS="${LDFLAGS} ${OOCD_LDFLAGS}" \
    ../${OOCD}/configure --enable-maintainer-mode \
				 --disable-option-checking \
				 --disable-werror \
				 --prefix=${PREFIX} \
				 --enable-dummy \
				 --enable-ft2232_libftdi \
				 --enable-usb_blaster_libftdi \
				 --enable-ep93xx \
				 --enable-at91rm9200 \
				 --enable-presto_libftdi \
				 --enable-usbprog \
				 --enable-jlink \
				 --enable-vsllink \
				 --enable-rlink \
				 --enable-stlink \
				 --enable-arm-jtag-ew
    log "Building ${OOCD}"
    ${MAKE} ${MAKEFLAGS}
    install ${OOCD} install
    cd ..
    log "Cleaning up ${OOCD}"
    touch ${STAMPS}/${OOCD}.build
    rm -rf build/* ${OOCD}
fi
fi
