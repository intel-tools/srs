ARG DISTRO=debian:testing-slim
FROM $DISTRO

ENV DEBIAN_FRONTEND noninteractive
ENV USER root

COPY scan-build.sh /scan-build.sh

RUN apt-get update && apt-get install -y \
    build-essential pkg-config coreutils binutils \
    autoconf autoconf-archive automake autopoint \
    meson ninja-build nasm yasm \
    cmake cmake-data cmake-extras \
    gettext bison flex libtool libssl-dev \
    wget curl libz3-dev time jq tar sudo bc \
    python3 libpython3-dev libboost-all-dev \
    gnupg lsb-release software-properties-common git \
    clang-15 clang-tools-15 clang-tidy-15 \
    && apt-get clean \
    && chmod +x /scan-build.sh \
    && git config --global --add safe.directory '*'

ENTRYPOINT ["/scan-build.sh"]
