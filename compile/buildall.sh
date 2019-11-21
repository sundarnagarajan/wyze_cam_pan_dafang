#!/bin/bash
if [ -n "$BASH_SOURCE" ]; then
    PROG_PATH=${PROG_PATH:-$(readlink -e $BASH_SOURCE)}
else
    PROG_PATH=${PROG_PATH:-$(readlink -e $0)}
fi
PROG_DIR=${PROG_DIR:-$(dirname ${PROG_PATH})}
PROG_NAME=${PROG_NAME:-$(basename ${PROG_PATH})}
source ${PROG_DIR}/functions.sh || exit 1

SECONDS=0
echo "Cleaning kernel"
clean_kernel
echo "Cleaning drivers"
clean_drivers
patch_kernel
build_kernel | show_dots_per_file
build_drivers
run_depmod
copy_built_files
echo ""
echo "Time taken in seconds: $SECONDS"
