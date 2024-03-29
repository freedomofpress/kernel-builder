# debian:buster 2021-12-20
FROM debian@sha256:94ccfd1c5115a6903cbb415f043a0b04e307be3f37b768cf6d6d3edff0021da3

ARG UID=1000
ARG GID=1000
ARG USERNAME=securedrop
ENV KBUILD_BUILD_USER "$USERNAME"
ENV KBUILD_BUILD_HOST "freedom.press"
ENV DEBFULLNAME "SecureDrop Team"

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
COPY scripts/mkdebian /usr/local/bin/mkdebian

COPY securedrop-grsec /securedrop-grsec
COPY securedrop-workstation-grsec /securedrop-workstation-grsec

RUN mkdir -p -m 0755 /kernel /patches-grsec /output
RUN chown ${USERNAME}:${USERNAME} /kernel /patches-grsec /output
WORKDIR /kernel

# VOLUME ["/kernel"]

USER ${USERNAME}
COPY pubkeys/ /pubkeys

CMD ["/usr/local/bin/build-kernel.sh"]
