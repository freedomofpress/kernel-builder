FROM debian:stable

ARG UID=1000
ARG GID=1000
ARG USERNAME=kernel-builder

ENV LINUX_VERSION 5.6.9

RUN apt-get update && \
    apt-get install -y \
    git fakeroot build-essential ncurses-dev xz-utils libssl-dev bc wget \
    flex curl bison rsync kmod cpio libelf-dev

RUN groupadd -g ${GID} ${USERNAME} && useradd -m -d /home/${USERNAME} -g ${GID} -u ${UID} ${USERNAME}

COPY build-kernel.sh /usr/local/bin/build-kernel.sh

RUN mkdir -p /kernel
RUN chown ${USERNAME}:${USERNAME} /kernel
WORKDIR /kernel

VOLUME ["/kernel"]

USER ${USERNAME}

CMD ["/usr/local/bin/build-kernel.sh"]
