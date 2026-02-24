#!/bin/bash
if [[ "$1" == "state" && "$2" == "pull" ]]; then
    cat terraform.tfstate
    exit 0
fi
exit 1
