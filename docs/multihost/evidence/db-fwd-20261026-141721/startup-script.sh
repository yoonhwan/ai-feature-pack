#!/bin/bash
# byz-db-fwd startup-script — VM:38309 → 10.2.0.10:5432 (iptables DNAT · COS 내장 · 외부 pull 0)
# 한 줄이라도 실패하면 즉시 끝나고 «applied» 를 남기지 않는다(journal: byz-db-fwd FAIL <단계>).
set -u
fail() { logger -t byz-db-fwd "FAIL $1"; exit 1; }
sysctl -w net.ipv4.ip_forward=1 >/dev/null || fail sysctl
IPT="iptables -w 10"
$IPT -t nat -C PREROUTING -p tcp --dport 38309 -j DNAT --to-destination 10.2.0.10:5432 2>/dev/null || $IPT -t nat -A PREROUTING -p tcp --dport 38309 -j DNAT --to-destination 10.2.0.10:5432 || fail dnat
$IPT -t nat -C POSTROUTING -d 10.2.0.10 -p tcp --dport 5432 -j MASQUERADE 2>/dev/null || $IPT -t nat -A POSTROUTING -d 10.2.0.10 -p tcp --dport 5432 -j MASQUERADE || fail masq
$IPT -C FORWARD -d 10.2.0.10 -p tcp --dport 5432 -j ACCEPT 2>/dev/null || $IPT -I FORWARD 1 -d 10.2.0.10 -p tcp --dport 5432 -j ACCEPT || fail fwd-out
$IPT -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || $IPT -I FORWARD 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || fail fwd-est
# 재검사 4+1(DNAT 된 패킷은 INPUT 이 아니라 FORWARD 를 탄다 — INPUT 규칙은 두지 않는다)
[ "$(sysctl -n net.ipv4.ip_forward)" = 1 ] || fail verify-sysctl
$IPT -t nat -C PREROUTING -p tcp --dport 38309 -j DNAT --to-destination 10.2.0.10:5432 || fail verify-dnat
$IPT -t nat -C POSTROUTING -d 10.2.0.10 -p tcp --dport 5432 -j MASQUERADE || fail verify-masq
$IPT -C FORWARD -d 10.2.0.10 -p tcp --dport 5432 -j ACCEPT || fail verify-fwd
$IPT -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || fail verify-fwd-est
logger -t byz-db-fwd "applied 38309 -> 10.2.0.10:5432"
