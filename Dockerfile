ARG ARCH=arm64
# The Ubuntu release that the packages are built for: 22.04 or 24.04. Each
# release needs its own build, as the packages link against its libraries.
ARG UBUNTU_VERSION=22.04
FROM --platform=linux/${ARCH} ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive
ENV WORKDIR=/root
ENV SOC=j722s

# The build installs Python packages and its own wheels into the system Python.
# Ubuntu 24.04's pip refuses that unless told to (PEP 668); the pip of 22.04
# ignores the variable.
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# When this arm64 image runs on an x86 host, every process runs under
# qemu-user, which gives the guest a fixed 8 MiB stack and ignores setrlimit().
# GCC raises its own stack limit to 64 MiB on native hosts; under QEMU it
# cannot, so cc1plus dies with "internal compiler error: Segmentation fault"
# on deeply nested C++. Give QEMU a 64 MiB stack. Ignored on native arm64.
ENV QEMU_STACK_SIZE=67108864

ARG ARCH=arm64

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        automake \
        bash \
        bash-completion \
        binfmt-support \
        bison \
        build-essential \
        ca-certificates \
        ccache \
        chrpath \
        cpio \
        curl \
        debianutils \
        debootstrap \
        diffstat \
        dosfstools \
        file \
        flex \ 
        gawk \
        gcc \
        git \
        iputils-ping \
        libacl1 \
        libdrm-dev \
        libegl-dev \
        libelf-dev \
        libgbm-dev \
        libgles2-mesa-dev \
        libglm-dev \
        liblz4-tool \
        libncurses-dev \
        libopencv-dev \
        libsdl2-2.0-0 \
        libsdl2-dev \
        libssl-dev \
        libtool \
        libyaml-cpp-dev \
        libgstreamer1.0-dev \
        libgstreamer-plugins-base1.0-dev \
        locales \
        nano \
        ninja-build \
        openssl \
        parted \
        pkg-config \
        pybind11-dev \
        python3 \
        python3-git \
        python3-jinja2 \
        python3-pexpect \
        python3-pip \
        python3-subunit \
        sed \
        socat \
        software-properties-common \
        sudo \
        tar \
        texinfo \
        udev \
        unzip \
        vim \
        wget \
        x11-xserver-utils \
        xterm \
        xz-utils \
        zstd \
    && locale-gen en_US.UTF-8

RUN . /etc/os-release && \
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | \
    gpg --dearmor -o /usr/share/keyrings/kitware-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ ${VERSION_CODENAME} main" \
    > /etc/apt/sources.list.d/kitware.list && \
    apt-get update

# The same CMake on every release.
RUN . /etc/os-release && \
    apt-get install -y \
    cmake=3.29.6-0kitware1ubuntu${VERSION_ID}.1 \
    cmake-data=3.29.6-0kitware1ubuntu${VERSION_ID}.1

RUN git clone https://git.ti.com/git/rpmsg/ti-rpmsg-char.git \
    --branch 0.6.7 --depth 1 --single-branch && \
    cd ti-rpmsg-char && \
    autoreconf -i && ./configure --host=aarch64-none-linux-gnu --prefix=/usr && \
    make && make install && \
    rm -rf ti-rpmsg-char

# Allow minimum password length of image in Distrobox to be 1 character
RUN sed -i 's/pam_unix\.so obscure/pam_unix.so minlen=1 obscure/' /etc/pam.d/common-password
RUN echo gemstone > /etc/hostname

# Taskfile Installation
# Pinned to 3.44.1 (Go 1.24). Under qemu-user, i.e. on x86 hosts, 3.50.0
# (Go 1.26) randomly segfaults, panics or deadlocks; 3.44.1 does not.
RUN curl -fsSL https://github.com/go-task/task/releases/download/v3.44.1/task_linux_arm64.deb \
        --output /tmp/task_linux_arm64.deb && \
    apt-get install -y /tmp/task_linux_arm64.deb && \
    rm /tmp/task_linux_arm64.deb && \
    task --completion bash > /etc/bash_completion.d/task

# VCS Repotool
# Its dependencies include the latest setuptools, which no longer has
# pkg_resources. --ignore-installed puts it in /usr/local next to the
# distribution's setuptools, whose pkg_resources python3-pbr still imports
# whenever a setup.py runs. --force-reinstall did the same on Ubuntu 22.04,
# but on 24.04 it removes the distribution's setuptools.
RUN pip install vcstool --ignore-installed && \
    cp /usr/local/share/vcstool-completion/vcs.bash /etc/bash_completion.d/vcs

# -------------------------------------------------------------------------
# yq
# -------------------------------------------------------------------------
RUN wget https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_${ARCH} \
    -O /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

RUN pip3 install meson pybind11 numpy packaging

RUN curl https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo \
    && chmod a+x /usr/local/bin/repo

COPY .bash_completion.d/* /etc/bash_completion.d/
RUN echo "source /etc/bash_completion" >> /etc/bash.bashrc

CMD ["bash"]
