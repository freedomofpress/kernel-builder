FROM debian:stable

ARG UID=1000
ARG GID=1000
ARG USERNAME=kernel-builder

RUN apt-get update && \
    apt-get install -y \
    git fakeroot build-essential ncurses-dev xz-utils libssl-dev bc wget \
    flex curl bison rsync kmod cpio libelf-dev

RUN apt-get install -y python3 python3-requests
RUN apt-get install -y gnupg
RUN apt-get install -y gcc-8-plugin-dev

RUN groupadd -g ${GID} ${USERNAME} && useradd -m -d /home/${USERNAME} -g ${GID} -u ${UID} ${USERNAME}

COPY build-kernel.sh /usr/local/bin/build-kernel.sh
COPY grsecurity-urls.py /usr/local/bin/grsecurity-urls.py

RUN mkdir -p /kernel /patches
RUN chown ${USERNAME}:${USERNAME} /kernel /patches
WORKDIR /kernel

VOLUME ["/kernel"]

USER ${USERNAME}
COPY pubkeys/ /tmp/pubkeys
RUN gpg --import --quiet /tmp/pubkeys/*

CMD ["/usr/local/bin/build-kernel.sh"]
