#!/bin/bash
if [ -n "$BASH_SOURCE" ]; then
    PROG_PATH=${PROG_PATH:-$(readlink -e $BASH_SOURCE)}
else
    PROG_PATH=${PROG_PATH:-$(readlink -e $0)}
fi
PROG_DIR=${PROG_DIR:-$(dirname ${PROG_PATH})}
PROG_NAME=${PROG_NAME:-$(basename ${PROG_PATH})}
source ${PROG_DIR}/defs.sh || exit 1

SECONDS=0

cd ${KERNEL_DIR}
if [ -f .config ]; then 
    mv .config .config.keep
fi
$MAKE_THREADED clean
if [ -f .config.keep ]; then
    mv .config.keep .config
else
    \cp -f ${WYZECAM_KCONFIG_DIR}/.config ${KERNEL_DIR}/
fi
( $MAKE_THREADED oldconfig && $MAKE_THREADED uImage && $MAKE_THREADED modules && $MAKE_THREADED ) || exit 1

cd ${DRIVERS_DIR}
for d in $(find -type d)
do
    if [ -f "${d}/Makefile" ]; then
        echo "Executing make clean in $d"
        cd $d
        $MAKE_THREADED clean 1>/dev/null 2>&1
        cd - 1>/dev/null
    fi
done
find . -name '*.ko' -exec rm -f {} \;
for d in audio/alsa isp/tx-isp misc/sample_motor misc/sensor_info sensors/jxf22 sensors/jxh62;
do
    cd $d
    $MAKE_THREADED
    cd - 1>/dev/null
done

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

mkdir -p ${BUILT_MODULES_DIR}
cp -v ${DEPMOD_MODULES_DIR}/* ${BUILT_MODULES_DIR}/
rm -rf ${DEPMOD_DIR}

# Copy kernel
mkdir -p ${BUILT_KERNEL_DIR}
find ${KERNEL_DIR} -name 'uImage.lzma' -exec cp {} ${BUILT_KERNEL_DIR}/ \;
cp ${BUILT_KERNEL_DIR}/uImage.lzma ${BUILT_KERNEL_DIR}/${NEW_KERNEL_FILENAME}
mkimage -l ${BUILT_KERNEL_DIR}/${NEW_KERNEL_FILENAME}

echo "Time taken in seconds: $SECONDS"
