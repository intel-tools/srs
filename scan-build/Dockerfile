FROM debian:testing-slim

ENV DEBIAN_FRONTEND noninteractive
ENV USER root
 
COPY scan-build/scan-build.sh /scan-build.sh
COPY scan-build/.gitconfig /root

RUN apt-get update && apt-get install -y \
    build-essential pkg-config coreutils binutils \
    autoconf autoconf-archive automake autopoint \
    meson ninja-build nasm yasm \
    cmake cmake-data cmake-extras \
    gettext bison flex libtool \
    wget curl libz3-dev time jq tar \
    python3 libpython3-dev libboost-all-dev \
    gnupg lsb-release software-properties-common git \
    clang-15 clang-tools-15 clang-tidy-15
RUN apt-get clean
RUN chmod +x /scan-build.sh

ENTRYPOINT /scan-build.sh
