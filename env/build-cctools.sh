#!/bin/sh
# Build cctools-port (Apple's ld for i386-apple-darwin8) into env/root/opt/cross.
# atv-linux-loader needs it to link mach_kernel.
set -eu

ENV=$(cd "$(dirname "$0")" && pwd)
# A commit, not the branch: the branch moves, and what it builds links the
# kernel. This is the head of branch 986-ld64-711 as of 2026-11-11.
REF=9fc3e04656050ddc33d24c036ab822249af4ceee

"$ENV/run" sh -eu -c "
    rm -rf /tmp/cctools-port
    git init -q /tmp/cctools-port
    cd /tmp/cctools-port
    git fetch -q --depth 1 https://github.com/tpoechtrager/cctools-port.git $REF
    git -c advice.detachedHead=false checkout -q FETCH_HEAD
    test \"\$(git rev-parse HEAD)\" = $REF
    cd cctools
    CC=clang CXX=clang++ ./configure --prefix=/opt/cross --target=i386-apple-darwin8 >/dev/null
    make -j\$(nproc) >/dev/null
    make install >/dev/null
    test -x /opt/cross/bin/i386-apple-darwin8-ld
"
