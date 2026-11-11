#!/bin/sh
# Build cctools-port (Apple's ld for i386-apple-darwin8) into env/root/opt/cross.
# atv-linux-loader needs it to link mach_kernel.
set -eu

ENV=$(cd "$(dirname "$0")" && pwd)
REF=986-ld64-711

"$ENV/run" sh -eu -c "
    rm -rf /tmp/cctools-port
    git clone -q --depth 1 -b $REF https://github.com/tpoechtrager/cctools-port.git /tmp/cctools-port
    cd /tmp/cctools-port/cctools
    CC=clang CXX=clang++ ./configure --prefix=/opt/cross --target=i386-apple-darwin8 >/dev/null
    make -j\$(nproc) >/dev/null
    make install >/dev/null
    test -x /opt/cross/bin/i386-apple-darwin8-ld
"
