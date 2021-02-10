# debian:buster 2021-02-10
FROM debian@sha256:1092695e843ad975267131f27a2b523128c4e03d2d96574bbdd7cf949ed51475

ARG UID=1000
ARG GID=1000
ARG USERNAME=user
ENV KBUILD_BUILD_USER "$USERNAME"
ENV KBUILD_BUILD_HOST "kernel-builder"

RUN apt-get update && \
    apt-get install -y \
    bc \
    bison \
    build-essential \
    cpio \
    curl \
    fakeroot \
    flex \
    gcc-8-plugin-dev \
    git \
    gnupg \
    kmod \
    libelf-dev \
    liblz4-tool \
    libssl-dev \
    lsb-release \
    ncurses-dev \
    python3 \
    python3-requests \
    rsync \
    wget \
    xz-utils

RUN groupadd -g ${GID} ${USERNAME} && useradd -m -d /home/${USERNAME} -g ${GID} -u ${UID} ${USERNAME}

COPY build-kernel.sh /usr/local/bin/build-kernel.sh
COPY grsecurity-urls.py /usr/local/bin/grsecurity-urls.py

RUN mkdir -p -m 0755 /kernel /patches-grsec /output
RUN chown ${USERNAME}:${USERNAME} /kernel /patches-grsec /output
WORKDIR /kernel

# VOLUME ["/kernel"]

USER ${USERNAME}
COPY pubkeys/ /tmp/pubkeys
RUN gpg --import --quiet /tmp/pubkeys/*

CMD ["/usr/local/bin/build-kernel.sh"]
