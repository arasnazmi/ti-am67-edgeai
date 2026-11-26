<p align="center">
    <picture>
        <source media="(prefers-color-scheme: dark)" srcset=".meta/logo-dark.png" width="40%" />
        <source media="(prefers-color-scheme: light)" srcset=".meta/logo-light.png" width="40%" />
        <img alt="T3 Foundation" src=".meta/logo-light.png" width="40%" />
    </picture>
</p>

# TI AM67A EdgeAI

 [![T3 Foundation](./.meta/t3-foundation.svg)](https://www.t3vakfi.org/en) [![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![Built with Devbox](https://www.jetify.com/img/devbox/shield_galaxy.svg)](https://www.jetify.com/devbox/docs/contributor-quickstart/) [![Documentation](https://img.shields.io/badge/Documentation-gray?style=flat&logo=Mintlify)](https://docs.t3gemstone.org)

## What is it?

This repository contains the build system and packaging scripts for the **TI AM67A EdgeAI**. It automates the end-to-end process of compiling, patching, and packaging all software components required to run AI inference workloads on T3 Gemstone boards.

The scripts handle the full pipeline for the following components:

- **TensorFlow Lite** — static library and Python wheel for aarch64
- **ONNXRuntime** — shared library and Python wheel with TIDL execution provider
- **TI TIDL Runtime** — TIDL-RT, TFLite-RT delegate, and ONNX-RT EP libraries
- **GStreamer** — multimedia framework with TI-specific downstream patches
- **DLR (Deep Learning Runtime)** — Neo-AI DLR library and Python wheel
- **v4l2-utils** — V4L2 camera utilities
- **ti-rpmsg-char** — RPMsg character device library for heterogeneous core communication
- **EdgeAI App Stack** — demo applications, test data, model zoo, and environment setup

All components are packaged as `.deb` files and/or Python `.whl` files, ready to be deployed on the target device.

This repository is intended for developers who want to build the SDK from source, customize individual components, or integrate new versions of upstream libraries into the T3 Gemstone software stack.

For pre-built binaries and full documentation, visit [https://docs.t3gemstone.org/en/boards/o1/ai/introduction](https://docs.t3gemstone.org/en/boards/o1/ai/introduction).

##### 1. Install Docker and jetify-devbox on the host computer.

```bash
user@host:$ ./setup.sh
```

<a name="section-ii"></a>
##### 2. After the installation is successful, activate the jetify-devbox shell to automatically install tools such as Docker, taskfile, etc.

```bash
user@host:$ devbox shell
```

##### 3. Create a Docker image, and enter it.

The packages are built for the Ubuntu release of the image: 22.04 (jammy) by default, or 24.04 (noble).

```bash
root@host:~ task box                        # Ubuntu 22.04
root@host:~ task box UBUNTU_VERSION=24.04   # Ubuntu 24.04
```

The image mounts the repository, so `workarea/` and `out/` are shared between the two. Use a separate
checkout for each release, or empty both directories before building for the other one.

On Ubuntu 24.04, t3-gstreamer is GStreamer 1.24.13 instead of 1.22.12: it is installed to `/usr/local`, ahead of the
distribution's GStreamer 1.24.2, and must not be older. TI does not publish its gst-plugins-good patches for 1.24, so
`patches/gstreamer/1.24.13` has them rebased, plus a patch that keeps the Bayer format names (`rggb10`, ...) of TI's
1.22 patches, which the TI GStreamer plugins and applications use.

##### 4. Build the Deb and WHL packages

```bash
# Show all available tasks and environment variables
root@host:~ task default

# Builds all .deb and .whl packages
root@host:~ ./build-all.sh
```

### Screencast

[![asciicast](https://asciinema.org/a/KDwPPlCV2wxzpwDB4sLseW2X9.svg)](https://asciinema.org/a/KDwPPlCV2wxzpwDB4sLseW2X9)

# Troubleshooting

#### 1. First Installation of Docker

Docker is installed on your system via the `./setup.sh` command. If you are installing Docker for the first time,
you must log out and log in again after the installation is complete.

#### 2. Removal of Docker Image

To remove a Docker image, execute the destroy command.

```bash
root@host:~ task destroy
```

#### 3. Segmentation Faults on x86 Hosts

On an x86 host the arm64 build container runs under QEMU, which causes two kinds of crashes:

- QEMU gives every process a fixed 8 MiB stack. GCC needs more for some C++ files and fails with
  `internal compiler error: Segmentation fault`. The Dockerfile raises the limit with `QEMU_STACK_SIZE`.
- `task` 3.50.0 (built with Go 1.26) randomly segfaults or hangs under QEMU. The Dockerfile pins `task` 3.44.1, which does not.

Rebuild the image (`task box`) after updating. Builds on native arm64 machines, such as CI, are not affected.

Builds use one compile job per CPU, capped at one per 2 GiB of free RAM. To use fewer, start the container with `NPROC=<n> task box`.

# Continuous Integration

`.github/workflows/build.yml` builds all packages for Ubuntu 22.04 and 24.04 on native arm64 GitHub runners, one runner
per component and release, with ccache. The packages are uploaded as the `ti-am67-edgeai-packages-ubuntu-<release>`
artifacts. Pushing a tag also publishes both sets as one GitHub release; the file names say which release a file is for.
The release also has one zip per Ubuntu release, `ti-am67-edgeai-<tag>-ubuntu-<release>-arm64.zip`, with all of its
`.deb` packages: unzip it and run `sudo apt install ./*.deb`.
