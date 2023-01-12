#!/bin/bash
LLVM_VERSION=${1:-15}

debian=$(grep VERSION_CODENAME /etc/os-release | awk -F"=" '{ print $2 }')
wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -
add-apt-repository -y "deb http://apt.llvm.org/${debian}/ llvm-toolchain-${debian}-${LLVM_VERSION} main"
apt-get update -y
apt-get install -y clang-${LLVM_VERSION} clang-tools-${LLVM_VERSION} clang-tidy-${LLVM_VERSION}
apt-get clean
