FROM ghcr.io/nforceroh/k8s-alpine-baseimage:3.23

ARG \
  BUILD_DATE=now \
  VERSION=unknown

LABEL \
  org.label-schema.maintainer="Sylvain Martin (sylvain@nforcer.com)" \
  org.label-schema.build-date="${BUILD_DATE}" \
  org.label-schema.version="${VERSION}" \
  org.label-schema.vcs-url="https://github.com/nforcer/k8s-wireguard" \
  org.label-schema.schema-version="1.0"

RUN apk add --no-cache bc grep iproute2 iptables iptables-legacy ip6tables \
    iputils ipcalc kmod libcap-utils libqrencode-tools net-tools \
    wireguard-tools libnatpmp openresolv moreutils python3 \
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
ADD --chmod=755 /content/usr/local/bin /usr/local/bin

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD ["python3", "-c", "import urllib.request,sys;\ntry:\n r=urllib.request.urlopen('http://127.0.0.1:8080', timeout=3);\n sys.exit(0 if r.getcode()==200 else 1)\nexcept Exception:\n sys.exit(1)"]

#ENTRYPOINT ["bash", "/usr/local/bin/entrypoint.sh"]