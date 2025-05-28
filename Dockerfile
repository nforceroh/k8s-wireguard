FROM docker.io/nforceroh/k8s-alpine-baseimage:latest

ARG BUILD_DATE=now
ARG VERSION=unknown
ARG WIREGUARD_RELEASE

LABEL \
  maintainer="Sylvain Martin (sylvain@nforcer.com)"

RUN apk update && \
  if [ -z ${WIREGUARD_RELEASE+x} ]; then \
    WIREGUARD_RELEASE=$(curl -sL "http://dl-cdn.alpinelinux.org/alpine/v3.21/main/x86_64/APKINDEX.tar.gz" | tar -xz -C /tmp \
    && awk '/^P:wireguard-tools$/,/V:/' /tmp/APKINDEX | sed -n 2p | sed 's/^V://'); \
  fi && \
  echo "**** install dependencies ****" && \
  apk add --no-cache bc coredns grep iproute2 iptables iptables-legacy \
    ip6tables iputils kmod libcap-utils libqrencode-tools net-tools openresolv \
    wireguard-tools==${WIREGUARD_RELEASE} && \
  echo "wireguard" >> /etc/modules && \
  cd /usr/sbin && \
  for i in ! !-save !-restore; do \
    rm -rf iptables$(echo "${i}" | cut -c2-) && \
    rm -rf ip6tables$(echo "${i}" | cut -c2-) && \
    ln -s iptables-legacy$(echo "${i}" | cut -c2-) iptables$(echo "${i}" | cut -c2-) && \
    ln -s ip6tables-legacy$(echo "${i}" | cut -c2-) ip6tables$(echo "${i}" | cut -c2-); \
  done && \
  sed -i 's|\[\[ $proto == -4 \]\] && cmd sysctl -q net\.ipv4\.conf\.all\.src_valid_mark=1|[[ $proto == -4 ]] \&\& [[ $(sysctl -n net.ipv4.conf.all.src_valid_mark) != 1 ]] \&\& cmd sysctl -q net.ipv4.conf.all.src_valid_mark=1|' /usr/bin/wg-quick && \
  rm -rf /etc/wireguard && \
  ln -s /config/wg_confs /etc/wireguard && \
  printf "Linuxserver.io version: ${VERSION}\nBuild-date: ${BUILD_DATE}" > /build_version && \
  echo "**** clean up ****" && \
  rm -rf /tmp/*
#  chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/wg_healthcheck.py

#RUN \
#    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && \
#    echo "net.ipv4.conf.all.forwarding=1" >> /etc/sysctl.conf && \
#    echo "net.ipv4.conf.all.src_valid_mark=1" >> /etc/sysctl.conf && \
#    echo "##Force IPv6 off" >> /etc/sysctl.conf && \
#    echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf && \
#    echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf && \
#    echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf && \
#    echo "net.ipv6.conf.eth0.disable_ipv6 = 1" >> /etc/sysctl.conf
COPY /rootfs /
#ENTRYPOINT ["bash", "/usr/local/bin/entrypoint.sh"]