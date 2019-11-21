#!/bin/bash
if [ -n "$BASH_SOURCE" ]; then
    PROG_PATH=${PROG_PATH:-$(readlink -e $BASH_SOURCE)}
else
    PROG_PATH=${PROG_PATH:-$(readlink -e $0)}
fi
PROG_DIR=${PROG_DIR:-$(dirname ${PROG_PATH})}
PROG_NAME=${PROG_NAME:-$(basename ${PROG_PATH})}
source ${PROG_DIR}/defs.sh || exit 1

if [ -f $KERNEL_DIR}/.patch_completed ]; then
    exit 0
fi
cd ${KERNEL_DIR}
for f in $(ls -1 ${KERNEL_DIR}/../patches/*.patch 2>/dev/null)
do
    patch --forward -r - -p1 < $f || exit 1
done
