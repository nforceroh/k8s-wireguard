FROM docker.io/nforceroh/k8s-alpine-baseimage:latest

ARG BUILD_DATE=now
ARG VERSION=unknown
ARG WIREGUARD_RELEASE

LABEL \
  maintainer="Sylvain Martin (sylvain@nforcer.com)"

RUN apk add --no-cache bc grep iproute2 iptables iptables-legacy ip6tables \
    iputils ipcalc kmod libcap-utils libqrencode-tools net-tools \
    wireguard-tools libnatpmp openresolv moreutils \
  && echo "wireguard" >> /etc/modules \
  && echo "**** clean up ****" \
  && rm -rf /tmp/*
#  chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/wg_healthcheck.py

RUN \
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && \
    echo "net.ipv4.conf.all.forwarding=1" >> /etc/sysctl.conf && \
    echo "net.ipv4.conf.all.src_valid_mark=1" >> /etc/sysctl.conf && \
    echo "##Force IPv6 off" >> /etc/sysctl.conf && \
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf && \
    echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf && \
    echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf && \
    echo "net.ipv6.conf.eth0.disable_ipv6 = 1" >> /etc/sysctl.conf

ADD --chmod=755 /content/etc/s6-overlay /etc/s6-overlay

#ENTRYPOINT ["bash", "/usr/local/bin/entrypoint.sh"]