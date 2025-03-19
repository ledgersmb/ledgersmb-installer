FROM debian:bookworm-slim

ARG VERSION=1.12.4

RUN echo -n "APT::Install-Recommends \"0\";\nAPT::Install-Suggests \"0\";\n" >> /etc/apt/apt.conf && \
    DEBIAN_FRONTEND=noninteractive apt-get -q -y update && \
    DEBIAN_FRONTEND=noninteractive apt-get -q -y upgrade && \
    DEBIAN_FRONTEND=noninteractive apt-get -q -y install \
      perl libio-socket-ssl-perl

# apt-file dh-make-perl

COPY ledgersmb-installer /usr/bin/ledgersmb-installer
RUN ledgersmb-installer install --prepare-env --no-verify-sig --log-level=trace --version=$VERSION && \
    DEBIAN_FRONTEND="noninteractive" apt-get clean -q && \
    rm -rf ~/.cpanm/ /var/lib/apt/lists/* /usr/share/man/*

