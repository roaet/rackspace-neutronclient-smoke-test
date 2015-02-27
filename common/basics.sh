#!/bin/bash

has_prog() {
    local prog=`which "$1"`
    if [ ${#prog} -eq 0 ]; then
        echo 0
    else
        echo 1
    fi
}

in_venv() {
    in_venv=`python -c 'import sys; print hasattr(sys, "real_prefix")'`
    if [ "$in_venv" == "True" ]; then
        echo 1
    else
        echo 0
    fi
}
