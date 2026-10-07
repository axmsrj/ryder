#!/bin/sh

#
#  build-librw.sh
#  Ryder
#
#  Created by Alex Marcelle on 07/10/26.
#

set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
source_dir="$project_dir/Vendor/librw"
build_dir="$project_dir/Vendor/build/librw-null"

cmake \
    -S "$source_dir" \
    -B "$build_dir" \
    -DLIBRW_PLATFORM=NULL \
    -DLIBRW_TOOLS=OFF \
    -DLIBRW_INSTALL=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0

cmake --build "$build_dir" --target librw --parallel
