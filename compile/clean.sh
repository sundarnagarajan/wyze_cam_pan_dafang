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
echo "Extracting kernel from source tar file"
clean_extract_kernel 2>&1 | show_1_line
echo "Cleaning drivers"
clean_drivers
echo ""
echo "Time taken in seconds: $SECONDS"
