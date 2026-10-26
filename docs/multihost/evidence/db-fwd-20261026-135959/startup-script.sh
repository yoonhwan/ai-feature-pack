#!/bin/bash
# byz-db-fwd startup-script — VM:38309 → 10.2.0.10:5432 (iptables DNAT · COS 내장 · 외부 pull 0)
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -C PREROUTING -p tcp --dport 38309 -j DNAT --to-destination 10.2.0.10:5432 2>/dev/null || iptables -t nat -A PREROUTING -p tcp --dport 38309 -j DNAT --to-destination 10.2.0.10:5432
iptables -t nat -C POSTROUTING -d 10.2.0.10 -p tcp --dport 5432 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -d 10.2.0.10 -p tcp --dport 5432 -j MASQUERADE
iptables -C FORWARD -d 10.2.0.10 -p tcp --dport 5432 -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -d 10.2.0.10 -p tcp --dport 5432 -j ACCEPT
iptables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -C INPUT -p tcp --dport 38309 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 38309 -j ACCEPT
logger -t byz-db-fwd "forward 38309 -> 10.2.0.10:5432 applied"
