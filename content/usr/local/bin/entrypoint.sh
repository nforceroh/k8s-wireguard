#!/bin/bash

set -u

pod_subnet=$(ip -4 -o addr show eth0 | awk '{print $4}'|awk -F\. '{print $1"."$2".0.0/16"}')

PING_IP=${PING_IP:-1.1.1.1}
DNS_IP=${DNS_IP:-1.1.1.1}
CHECK_INTERVAL=${CHECK_INTERVAL:-10}
IP_CHECK_INTERVAL=${IP_CHECK_INTERVAL:-60}
ALLOWED_SUBNETS=${ALLOWED_SUBNETS:-${pod_subnet}}
CLUSTER_SUBNET=${CLUSTER_SUBNET:-10.244.0.0/16}

set_dns () {
  cp /etc/resolv.conf /etc/resolv.conf.bak
  printf 'nameserver %s\n' "${DNS_IP}" > /etc/resolv.conf
}

finish () {
  wg-quick down "${interface}" 2>/dev/null || true
    exit 0
}

config_file=/etc/wireguard/wg0.conf
if [[ ! -f "$config_file" ]]; then
  echo "Configuration file not found: ${config_file}" >&2
    exit 1
fi

interface=$(basename "${config_file%.*}")
endpoint=$(awk -F= '/^[[:space:]]*Endpoint[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$config_file" | cut -f1 -d:)
if [[ -z "$endpoint" ]]; then
  echo "Unable to parse endpoint from ${config_file}" >&2
  exit 1
fi

echo "Using interface: ${interface}"
echo "Using endpoint host: ${endpoint}"

if [[ "$endpoint" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  endpoint_ip="$endpoint"
else
  endpoint_ip=$(getent ahostsv4 "$endpoint" | awk '{print $1; exit}')
  if [[ -z "$endpoint_ip" ]]; then
    echo "Unable to resolve endpoint host ${endpoint}" >&2
    exit 1
  fi
fi

echo "Resolved endpoint IP: ${endpoint_ip}"

#sysctl -p

trap finish SIGTERM SIGINT SIGQUIT

echo "Getting external address pre VPN enabled"
MYISP=$(curl -s ifconfig.me)
echo "My ISP IP is ${MYISP}"
echo "${MYISP}" > /tmp/myisp.ip

echo "All IP"
ip a
echo "IP Routes"
ip r

route -n
echo "Setting up routing"
default_gateway=$(ip -4 route | awk '$1 == "default" { print $3 }')
if [[ -z "$default_gateway" ]]; then
  echo "Unable to determine default gateway" >&2
  exit 1
fi
ip route replace "${endpoint_ip}/32" via "${default_gateway}" dev eth0
route -n

echo "Resetting resolvconf state"
resolvconf -u 2>/dev/null || true

echo "Initiating VPN connection"
if ! wg-quick up "$config_file"; then
  echo "wg-quick failed to bring up ${interface}" >&2
  exit 1
fi
set_dns
ip route replace default dev "$interface"

# Create static routes for any ALLOWED_SUBNETS and punch holes in the firewall
echo "Allowing traffic to local subnet ${pod_subnet}" >&2
for subnet in ${ALLOWED_SUBNETS//,/ }; do
    echo "Add local subnet ${subnet} via ${default_gateway} dev eth0"
  ip route add "$subnet" via "$default_gateway" dev eth0
#    iptables --insert OUTPUT --destination "$subnet" --jump ACCEPT
done
echo "Allowing traffic to local cluster ${CLUSTER_SUBNET}" >&2
for subnet in ${CLUSTER_SUBNET//,/ }; do
    echo "Add cluster subnet ${subnet} via ${default_gateway} dev eth0"
    ip route add "$subnet" via "$default_gateway" dev eth0
#    iptables --insert OUTPUT --destination "$subnet" --jump ACCEPT
done


echo "Getting external address while on VPN"
MYVPN=$(curl -s ifconfig.me)
echo "My VPN IP is ${MYVPN}" 

if [ "${MYISP}" == "${MYVPN}" ]; then
  echo "Not connected, check configuration"
  exit 1
fi

# Infinite sleep
sleep infinity &

wait $!
