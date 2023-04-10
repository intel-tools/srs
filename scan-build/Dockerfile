ARG DISTRO=debian:testing-slim
FROM $DISTRO

ARG USER=root
ARG USER_ID=0
ARG GROUP_ID=0

ENV DEBIAN_FRONTEND noninteractive
ENV FINAL_USER $USER
ENV FINAL_GROUP_ID $GROUP_ID

COPY scan-build.sh /scan-build.sh

RUN apt-get update && apt-get install -y \
    build-essential pkg-config coreutils binutils \
    autoconf autoconf-archive automake autopoint \
    meson ninja-build nasm yasm \
    cmake cmake-data cmake-extras \
    gettext bison flex libtool libssl-dev \
    wget curl libz3-dev time jq tar sudo \
    python3 libpython3-dev libboost-all-dev \
    gnupg lsb-release software-properties-common git \
    clang-15 clang-tools-15 clang-tidy-15 \
    && apt-get clean \
    && chmod +x /scan-build.sh \
    && git config --global --add safe.directory '*'

RUN if [ $USER != "root" ] ; then groupadd -g ${GROUP_ID} ${USER} && useradd -m ${USER} --uid ${USER_ID} -g ${GROUP_ID}; fi

ENV USER root
ENTRYPOINT ["/scan-build.sh"]
