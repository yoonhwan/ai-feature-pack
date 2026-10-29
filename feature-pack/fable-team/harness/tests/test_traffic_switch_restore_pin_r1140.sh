#!/usr/bin/env bash
# test_traffic_switch_restore_pin_r1140.sh — r1140: ft-traffic-switch.sh 직전 표의 LATEST 행 = 그 순간 revisionName 고정 · 원복은 이름 박힌 표로
#   카드 반례 R1~R4 · 변이 1 · bin·kit 같은 내용 · 줄 상한
# 격리: gcloud 대역(services describe 응답 차례 svc.seq · revisions describe 응답 파일 · 호출 기록 calls.log) + curl 대역(끝까지 503)
#   실 gcloud·실 서비스 0 · 자기 재호출 0(변이는 bin 사본을 함수로 돌린다) · 고정 sleep 0(TS_HEALTH_INTERVAL=0)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 RSG_ACTIVE)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:500}";; *) ok "$3";; esac; }
sec() { echo "== $1 (누적 $((SECONDS - T0))s)"; }

FX="$T/fx"; mkdir -p "$FX" "$T/home"
cat > "$T/gcloud" <<'EOS'
#!/bin/bash
F="${FX:?}"; echo "$*" >> "$F/calls.log"
case "$*" in
  "run services describe "*) n="$(grep -c 'services describe' "$F/calls.log")"; s="$(sed -n "${n}p" "$F/svc.seq")"; [ -n "$s" ] || s="$(tail -n 1 "$F/svc.seq")"; cat "$F/$s.json" ;;
  "run revisions describe "*) cat "$F/rev-$4.json" 2>/dev/null || { echo "not found $4" >&2; exit 1; } ;;
  "run services update-traffic "*) echo "update-traffic 대역 rc=0" ;;
  *) exit 9 ;;
esac
EOS
cat > "$T/curl" <<'EOS'
#!/bin/bash
out=/dev/null
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac; done
printf '%s' '{"consumer_ready":false,"reason":"worker_unreachable"}' > "$out"; printf 503
EOS
chmod +x "$T/gcloud" "$T/curl"
for r in w-00662 w-00663 w-00664; do
  printf '{"spec":{"containers":[{"env":[{"name":"A","value":"v"}]}]},"status":{"conditions":[{"type":"Ready","status":"True"}]}}\n' > "$FX/rev-$r.json"
done
svc() {  # <파일 이름> <traffic JSON 배열> — latestCreated = latestReady = w-00664
  printf '{"status":{"latestCreatedRevisionName":"w-00664","latestReadyRevisionName":"w-00664","traffic":%s}}\n' "$2" > "$FX/$1.json"
}
svc r1 '[{"latestRevision":true,"percent":100,"revisionName":"w-00663"}]'
svc r2 '[{"percent":100,"revisionName":"w-00662"}]'
svc r3 '[{"latestRevision":true,"percent":50,"revisionName":"w-00663"},{"percent":50,"revisionName":"w-00662"}]'
svc r4 '[{"latestRevision":true,"percent":100}]'
svc on64 '[{"percent":100,"revisionName":"w-00664"}]'
fx() { : > "$FX/calls.log"; printf '%s\n' "$@" > "$FX/svc.seq"; }
sw() { local b="$1"; shift; env -i HOME="$T/home" PATH="/usr/bin:/bin" FX="$FX" TS_GCLOUD="$T/gcloud" TS_CURL="$T/curl" TS_HEALTH_INTERVAL=0 TS_HEALTH_TRIES=2 \
  bash "$b/ft-traffic-switch.sh" --service svc --region r1 --health-url https://gw.test/health "$@" 2>&1; }
nupd() { grep -c 'update-traffic' "$FX/calls.log"; }
restore_to() { grep 'update-traffic' "$FX/calls.log" | sed -n '2p' | sed 's/.*--to-revisions=//'; }

check_r1() { local o rc; fx r1 on64; o="$(sw "$1" --to w-00664=100)"; rc=$?
  [ "$rc" = 3 ] && [ "$(nupd)" = 2 ] && [ "$(restore_to)" = "w-00663=100" ] && ok "R1 ⓐ LATEST(w-00663)=100 → 원복 --to-revisions=w-00663=100 · rc3" \
    || bad "R1 rc=$rc upd=$(nupd) 원복=$(restore_to) ← ${o:0:500}"
  has "$o" "직전 표: w-00663=100 (LATEST 고정 · 원복은 이 표로)" "R1 직전 표 줄 = 이름 + LATEST 고정 꼬리"
  hasnt "$o" "LATEST=100" "R1 LATEST=100 표 0"; }

sec "R1 LATEST 행 = 이름 고정"
check_r1 "$BIN0"
sec "R2 이름 박힌 표 = 그대로"
fx r2 on64; o="$(sw "$BIN0" --to w-00664=100)"; rc=$?
[ "$rc" = 3 ] && [ "$(restore_to)" = "w-00662=100" ] && ok "R2 ⓑ 원복 --to-revisions=w-00662=100 · rc3" || bad "R2 rc=$rc 원복=$(restore_to) ← ${o:0:500}"
has "$o" "직전 표: w-00662=100 (원복은 이 표로)" "R2 직전 표 줄 = 고정 꼬리 0(지금 그대로)"
sec "R3 LATEST 50 + 이름 50"
fx r3 on64; o="$(sw "$BIN0" --to w-00664=100)"; rc=$?
[ "$rc" = 3 ] && [ "$(restore_to)" = "w-00663=50,w-00662=50" ] && ok "R3 ⓐ 원복 --to-revisions=w-00663=50,w-00662=50 · rc3" || bad "R3 rc=$rc 원복=$(restore_to) ← ${o:0:500}"
sec "R4 LATEST 행 이름 없음 = 판정 불가"
fx r4 on64; o="$(sw "$BIN0" --to w-00664=100)"; rc=$?
[ "$rc" = 5 ] && [ "$(nupd)" = 0 ] && has "$o" "판정 불가 — 직전 LATEST 행에 리비전 이름 없음 — 원복 표를 못 만든다(svc)" "R4 ⓒ rc5 · update-traffic 0" \
  || bad "R4 rc=$rc upd=$(nupd) ← ${o:0:500}"
has "$(printf '%s\n' "$o" | tail -n 1)" "판정 불가 rc=5" "R4 결과 줄이 마지막 줄"

sec "ⓓ bin·kit 같은 내용 · 줄 상한"
cmp -s "$BIN0/ft-traffic-switch.sh" "$KIT/ft-traffic-switch.sh" && ok "bin=kit ft-traffic-switch.sh" || bad "bin≠kit ft-traffic-switch.sh"
n="$(wc -l < "$BIN0/ft-traffic-switch.sh" | tr -d ' ')"; [ "$n" -le 200 ] && ok "ft-traffic-switch.sh ${n}줄 ≤200" || bad "ft-traffic-switch.sh ${n}줄 > 200"

sec "변이 1 — 고정 삭제(LATEST 행 = LATEST 그대로)가 R1 을 FAIL 시킨다(검출)"
m="$T/mut-pin"; cp -R "$BIN0" "$m"
sed 's/n = t.get("revisionName") or ("LATEST" if t.get("latestRevision") else "?")/n = "LATEST" if t.get("latestRevision") else t.get("revisionName", "?")/' "$BIN0/ft-traffic-switch.sh" > "$m/ft-traffic-switch.sh"
if cmp -s "$BIN0/ft-traffic-switch.sh" "$m/ft-traffic-switch.sh"; then bad "변이 사본 = 원본"
else f0=$fail; check_r1 "$m" > /dev/null 2>&1; d=$((fail - f0)); fail=$f0
  [ "$d" -gt 0 ] && ok "변이 1(LATEST 고정 삭제) → R1 FAIL 검출" || bad "변이 1 을 못 잡음"; fi

sec "끝"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
