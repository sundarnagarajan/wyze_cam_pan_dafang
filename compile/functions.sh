#!/bin/bash
if [ -n "$BASH_SOURCE" ]; then
    PROG_PATH=${PROG_PATH:-$(readlink -e $BASH_SOURCE)}
else
    PROG_PATH=${PROG_PATH:-$(readlink -e $0)}
fi
PROG_DIR=${PROG_DIR:-$(dirname ${PROG_PATH})}
PROG_NAME=${PROG_NAME:-$(basename ${PROG_PATH})}

DAFANG_DIR=$(readlink -e ${PROG_DIR}/..)
DAFANG_TOOLCHAIN_DIR=${DAFANG_DIR}/toolchain
WYZECAM_KCONFIG_DIR=${DAFANG_DIR}/wyze_cam_pan_kernel_config
OPENFANG_KCONFIG_DIR=${DAFANG_DIR}/openfang_kernel_config
KERNEL_DIR=${DAFANG_DIR}/kernel
DRIVERS_DIR=${DAFANG_DIR}/drivers
DAFANG_NEW_DIR=${DAFANG_DIR}/new
DEPMOD_DIR=${DAFANG_NEW_DIR}/depmod
DEPMOD_MODULES_DIR=${DEPMOD_DIR}/lib/modules/$(uname -r)
BUILT_MODULES_DIR=${DAFANG_NEW_DIR}/modules
BUILT_KERNEL_DIR=${DAFANG_NEW_DIR}/kernel
BUILT_KERNEL_FILENAME=${KERNEL_DIR}/arch/mips/boot/uImage.lzma
NEW_KERNEL_FILENAME=kernel-t20.bin

export ARCH=mips
export CROSS_COMPILE=${DAFANG_TOOLCHAIN_DIR}/bin/mips-linux-gnu-
export CC=${CROSS_COMPILE}gcc
export KSRC=$KERNEL_DIR
MAKE_THREADED="make -j$(nproc)"


# Print diagnostic output only once - even if sourced multiple times
if [ -z "$__DEFS_PRINTED__" ]; then
    export __DEFS_PRINTED__=yes
    
    for v in DAFANG_DIR DAFANG_NEW_DIR DAFANG_TOOLCHAIN_DIR KERNEL_DIR DRIVERS_DIR BUILT_MODULES_DIR DEPMOD_DIR DEPMOD_MODULES_DIR BUILT_KERNEL_DIR NEW_KERNEL_FILENAME WYZECAM_KCONFIG_DIR OPENFANG_KCONFIG_DIR
    do
        printf '%-32s : %s\n' "$v" "${!v}"
    done
    ls -l $CC
fi

function patch_kernel() {
    ls -1 ${KERNEL_DIR}/.patch_completed 1>/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo '---------- Already patched ----------'
        return 0
    fi
    cd ${KERNEL_DIR}
    for f in $(ls -1 ${KERNEL_DIR}/../patches/*.patch 2>/dev/null)
    do
        patch --forward -r - -p1 < $f || exit 1
    done
}

function reverse_kernel_patches() {
    ls -1 ${KERNEL_DIR}/.patch_completed 1>/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo '---------- Not patched ----------'
        return 0
    fi
    cd ${KERNEL_DIR}
    for f in $(ls -1 ${KERNEL_DIR}/../patches/*.patch 2>/dev/null)
    do
        patch --reverse -r - -p1 < $f || exit 1
    done
}

function clean_kernel() {
    cd ${KERNEL_DIR}
    if [ -f .config ]; then 
        mv .config .config.keep
    fi
    $MAKE_THREADED distclean
    if [ -f .config.keep ]; then
        mv .config.keep .config
    else
        \cp -f ${WYZECAM_KCONFIG_DIR}/.config ${KERNEL_DIR}/
    fi
}

function build_kernel() {
    cd ${KERNEL_DIR}
    ( $MAKE_THREADED oldconfig && $MAKE_THREADED uImage && $MAKE_THREADED modules && $MAKE_THREADED ) || exit 1
}

function clean_drivers() {
    cd ${DRIVERS_DIR}
    find . -name '*.ko' -exec rm -f {} \;
    for d in $(find -type d)
    do
        if [ -f "${d}/Makefile" ]; then
            echo "Executing make clean in $d"
            cd $d
            $MAKE_THREADED clean 1>/dev/null 2>&1
            cd - 1>/dev/null
        fi
    done
}

function build_drivers() {
    cd ${DRIVERS_DIR}
    for d in audio/alsa isp/tx-isp misc/sample_motor misc/sensor_info sensors/jxf22 sensors/jxh62;
    do
        cd $d
        $MAKE_THREADED
        cd - 1>/dev/null
    done
}

function run_depmod() {
    # Assemble all built modules and generate modules.dep
    # Note: depmod ASSUMES kernel version == running (HOST) kernel version
    rm -rf ${DAFANG_NEW_DIR}

    mkdir -p ${DEPMOD_MODULES_DIR}

    find ${KERNEL_DIR} -name '*.ko' -exec cp {} ${DEPMOD_MODULES_DIR}/ \;
    find ${DRIVERS_DIR} -name '*.ko' -exec cp {} ${DEPMOD_MODULES_DIR}/ \;
    for f in modules.builtin modules.order
    do
        cp ${KERNEL_DIR}/$f ${DEPMOD_MODULES_DIR}/
    done

    depmod -b ${DAFANG_NEW_DIR}/depmod -a
}

function copy_built_files() {
    mkdir -p ${BUILT_MODULES_DIR}
    cp -v ${DEPMOD_MODULES_DIR}/* ${BUILT_MODULES_DIR}/
    rm -rf ${DEPMOD_DIR}

    # Copy kernel
    mkdir -p ${BUILT_KERNEL_DIR}
    cp ${BUILT_KERNEL_FILENAME} ${BUILT_KERNEL_DIR}/${NEW_KERNEL_FILENAME}
    mkimage -l ${BUILT_KERNEL_DIR}/${NEW_KERNEL_FILENAME}
}

