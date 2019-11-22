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
rm -f $LOG_FILE

echo "Cleaning kernel"
clean_kernel 2>&1 | show_1_line
echo "Cleaning drivers"
clean_drivers
patch_kernel 2>&1 | show_1_line
echo "Building kernel"
build_kernel 2>&1 | show_1_line
echo "Building drivers"
build_drivers 2>&1 | show_1_line
run_depmod
copy_built_files
echo ""
echo "Time taken in seconds: $SECONDS"
