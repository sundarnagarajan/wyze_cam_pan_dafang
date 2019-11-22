#!/bin/bash
if [ -n "$BASH_SOURCE" ]; then
    PROG_PATH=${PROG_PATH:-$(readlink -e $BASH_SOURCE)}
else
    PROG_PATH=${PROG_PATH:-$(readlink -e $0)}
fi
PROG_DIR=${PROG_DIR:-$(dirname ${PROG_PATH})}
PROG_NAME=${PROG_NAME:-$(basename ${PROG_PATH})}

DAFANG_DIR=$(readlink -e ${PROG_DIR}/..)
BAK_DIR=${DAFANG_DIR}/bak
DAFANG_TOOLCHAIN_DIR=${DAFANG_DIR}/toolchain
WYZECAM_KCONFIG_DIR=${DAFANG_DIR}/kernel_config/camera/wyze_cam_pan/
OPENFANG_KCONFIG_DIR=${DAFANG_DIR}/kernel_config/upstream/openfang/
KERNEL_SRC_DIR=${DAFANG_DIR}/kernel_src_tar
KERNEL_SRC_TAR_FILENAME=${KERNEL_SRC_DIR}/kernel-3.10.14.tar.xz
KERNEL_DIR=${DAFANG_DIR}/kernel
DRIVERS_DIR=${DAFANG_DIR}/drivers
DAFANG_NEW_DIR=${DAFANG_DIR}/new
DEPMOD_DIR=${DAFANG_NEW_DIR}/depmod
DEPMOD_MODULES_DIR=${DEPMOD_DIR}/lib/modules/$(uname -r)
BUILT_MODULES_DIR=${DAFANG_NEW_DIR}/modules
BUILT_KERNEL_DIR=${DAFANG_NEW_DIR}/kernel
BUILT_KERNEL_FILENAME=${KERNEL_DIR}/arch/mips/boot/uImage.lzma
NEW_KERNEL_FILENAME=kernel-t20.bin
LOG_FILE=${DAFANG_DIR}/compile.log

export ARCH=mips
export CROSS_COMPILE=${DAFANG_TOOLCHAIN_DIR}/bin/mips-linux-gnu-
export CC=${CROSS_COMPILE}gcc
export KSRC=$KERNEL_DIR
MAKE_THREADED="make -j$(nproc)"

mkdir -p ${BAK_DIR}

# Print diagnostic output only once - even if sourced multiple times
if [ -z "$__DEFS_PRINTED__" ]; then
    export __DEFS_PRINTED__=yes
    
    for v in DAFANG_DIR DAFANG_NEW_DIR DAFANG_TOOLCHAIN_DIR KERNEL_DIR DRIVERS_DIR BUILT_MODULES_DIR DEPMOD_DIR DEPMOD_MODULES_DIR BUILT_KERNEL_DIR NEW_KERNEL_FILENAME WYZECAM_KCONFIG_DIR OPENFANG_KCONFIG_DIR KERNEL_SRC_DIR KERNEL_SRC_TAR_FILENAME BAK_DIR
    do
        printf '%-32s : %s\n' "$v" "${!v}"
    done
    ls -l $CC
fi

function show_dots_per_file() {
    echo -en "\033s"
    tee -a $LOG_FILE | while read -r a;
    do
        echo -en "\033u"
        echo -en "\r\033[0J"
        echo -n "$a"
    done
    echo "done"
}

function tar_top_dir() {
    # $1: tar file path
    # Outputs top dir (assumes only one top dir)
    tar tvf "$1" | head -1 | awk '{print $NF}' | sed -e 's/\/$//'
}

function backup_config() {
    # $1: SOURCE dir to backup .config FROM
    local KTOP_DIR=$1
    \rm -f "${BAK_DIR}/.config.keep"
    if [ -f "${KTOP_DIR}/.config" ]; then
        cp "${KTOP_DIR}/.config" "${BAK_DIR}/.config.keep"
    fi
}

function restore_config() {
    # $1: TARGET dir to backup .config TO
    local KTOP_DIR=$1
    if [ -f "${BAK_DIR}/.config.keep" ]; then
        \cp -f "${BAK_DIR}/.config.keep" "${KTOP_DIR}/.config"
    else
        echo "Restoring default config from ${WYZECAM_KCONFIG_DIR}"
        \cp -f ${WYZECAM_KCONFIG_DIR}/.config ${KTOP_DIR}/.config
    fi
}

function patch_kernel() {
    >&2 echo "Patching kernel"
    ls -1 ${KERNEL_DIR}/.patch_completed 1>/dev/null 2>&1
    if [ $? -eq 0 ]; then
        >&2 echo '---------- Already patched ----------'
        return 0
    fi
    cd ${KERNEL_DIR}
    for f in $(ls -1 ${KERNEL_DIR}/../patches/*.patch 2>/dev/null)
    do
        patch --forward -r - -p1 < $f || exit 1
    done
}

function reverse_kernel_patches() {
    >&2 echo "Reversing kernel patches"
    ls -1 ${KERNEL_DIR}/.patch_completed 1>/dev/null 2>&1
    if [ $? -ne 0 ]; then
        >&2 echo '---------- Not patched ----------'
        return 0
    fi
    cd ${KERNEL_DIR}
    for f in $(ls -1 ${KERNEL_DIR}/../patches/*.patch 2>/dev/null)
    do
        patch --reverse -r - -p1 < $f || exit 1
    done
}

function clean_extract_kernel() {
    cd $DAFANG_DIR
    local KTOP_DIR=${DAFANG_DIR}/$(tar_top_dir $KERNEL_SRC_TAR_FILENAME)
    if [ -d "$KTOP_DIR" ]; then
        backup_config "$KTOP_DIR"
        rm -rf $KTOP_DIR
    fi
    tar xf "$KERNEL_SRC_TAR_FILENAME"
    patch_kernel
    restore_config "$KTOP_DIR"
}

function clean_kernel() {
    cd ${KERNEL_DIR}
    backup_config "$KERNEL_DIR"
    $MAKE_THREADED distclean
    $MAKE_THREADED mrproper
    restore_config "$KERNEL_DIR"
    patch_kernel
}

function build_kernel() {
    ln -sf ${DAFANG_DIR}/$(tar_top_dir $KERNEL_SRC_TAR_FILENAME) ${KERNEL_DIR}
    cd ${KERNEL_DIR}
    ( $MAKE_THREADED silentoldconfig && $MAKE_THREADED uImage && $MAKE_THREADED modules && $MAKE_THREADED ) || exit 1
}

function clean_drivers() {
    cd ${DRIVERS_DIR}
    find . -name '*.ko' -exec rm -f {} \;
    for d in $(find -type d)
    do
        if [ -f "${d}/Makefile" ]; then
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
    echo "Running depmod"
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
    echo "Copying files"
    mkdir -p ${BUILT_MODULES_DIR}
    cp ${DEPMOD_MODULES_DIR}/* ${BUILT_MODULES_DIR}/
    rm -rf ${DEPMOD_DIR}

    # Copy kernel
    mkdir -p ${BUILT_KERNEL_DIR}
    cp ${BUILT_KERNEL_FILENAME} ${BUILT_KERNEL_DIR}/${NEW_KERNEL_FILENAME}
    mkimage -l ${BUILT_KERNEL_DIR}/${NEW_KERNEL_FILENAME}
}

