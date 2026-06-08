#!/bin/bash

if [ $# -ne 2 ]
then
    echo "Error: Two arguments required"
    exit 1
fi

writefile=$1
writestr=$2

dir=$(dirname "$writefile")

mkdir -p "$dir"

echo "$writestr" > "$writefile"

if [ $? -ne 0 ]
then
    echo "Error: Could not create file"
    exit 1
fi
