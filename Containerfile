# Builds a 32-bit wineasio for Proton 10 (Wine 10), independent of the host distro:
# many distros no longer ship the 32-bit Wine libraries wineasio's build needs.
FROM docker.io/library/debian:bookworm
ENV DEBIAN_FRONTEND=noninteractive
ARG WINE_VERSION=10.0.0.0~bookworm-1
ARG WINEASIO_VERSION=1.3.0
ARG WINEASIO_SHA256=f8bf74c871233f65e5befecc7b4f2629f2566f84e951e363af0ad51eae516a4c

RUN dpkg --add-architecture i386 && apt-get update -qq && \
    apt-get install -qqy --no-install-recommends ca-certificates wget gnupg gcc-multilib make patch && \
    mkdir -pm755 /etc/apt/keyrings && \
    wget -qO /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -qNP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources && \
    apt-get update -qq && \
    apt-get install -qqy --no-install-recommends \
        winehq-stable=$WINE_VERSION wine-stable=$WINE_VERSION wine-stable-amd64=$WINE_VERSION \
        wine-stable-i386=$WINE_VERSION wine-stable-dev=$WINE_VERSION

WORKDIR /build
RUN wget -q https://github.com/wineasio/wineasio/releases/download/v$WINEASIO_VERSION/wineasio-$WINEASIO_VERSION.tar.gz && \
    echo "$WINEASIO_SHA256  wineasio-$WINEASIO_VERSION.tar.gz" | sha256sum -c - && \
    tar xzf wineasio-$WINEASIO_VERSION.tar.gz
COPY patches/ /build/patches/
WORKDIR /build/wineasio-$WINEASIO_VERSION
RUN for p in /build/patches/*.patch; do patch -p1 < "$p"; done && make 32 && \
    mkdir /out && cp build32/wineasio32.dll build32/wineasio32.dll.so /out/
