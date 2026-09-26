#!/usr/bin/env bash

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <config1> <config2>"
    exit 1
fi

grep -E '^CONFIG_[A-Za-z0-9_]+=' "$1" \
    | cut -d= -f1 \
    | sort -u > /tmp/config1.keys

grep -E '^CONFIG_[A-Za-z0-9_]+=' "$2" \
    | cut -d= -f1 \
    | sort -u > /tmp/config2.keys

comm -12 /tmp/config1.keys /tmp/config2.keys

