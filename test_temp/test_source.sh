#!/bin/bash
source ../get_preserving_file_name.sh
if declare -f get_preserving_file_names > /dev/null; then
    echo "SUCCESS: Function available"
    exit 0
else
    echo "FAIL: Function not available"
    exit 1
fi
