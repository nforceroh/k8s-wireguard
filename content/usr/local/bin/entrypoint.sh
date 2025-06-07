#!/bin/bash

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
    wg-quick down wg0
    exit 0
}

config_file=$(find /etc/wireguard -type f -name '*.conf' | shuf -n 1)
if [[ -z "$config_file" ]]; then
    echo "No configuration files found in /etc/wireguard" >&2
    exit 1
fi

interface=$(basename "${config_file%.*}")
endpoint=$(grep -i Endpoint $config_file |awk '{print $3}'|cut -f1 -d:)

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
ip route del default
ip route add ${endpoint}/32 via ${default_gateway} dev eth0
route -n


echo "Initiating VPN connection"
wg-quick up /etc/wireguard/wg0.conf
set_dns
ip route add default dev wg0

# Create static routes for any ALLOWED_SUBNETS and punch holes in the firewall
echo "Allowing traffic to local subnet ${pod_subnet}" >&2
for subnet in ${ALLOWED_SUBNETS//,/ }; do
    echo "Add local subnet ${subnet} via ${default_gateway} dev eth0"
    ip route add "$subnet" via "$default_gateway"
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
