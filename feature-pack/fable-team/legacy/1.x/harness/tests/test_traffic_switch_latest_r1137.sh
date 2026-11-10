#!/usr/bin/env bash
# test_traffic_switch_latest_r1137.sh — r1137: ft-traffic-switch.sh LATEST = latestCreated · 준비 전 = 판정 불가 rc5 · 전환 뒤 켜진 리비전 대조(대조 안 한 것 = 원복)
#   카드 반례 R1~R6 · 변이 2 · bin·kit 같은 내용 · 줄 상한
# 격리: gcloud 대역(services describe 응답 차례 svc.seq · revisions describe 응답 파일 · 호출 기록 calls.log · update-traffic rc 차례 upd.rc) + curl 대역
#   실 gcloud·실 서비스 0 · 자기 재호출 0(변이는 bin 사본을 함수로 돌린다) · 고정 sleep 0(TS_HEALTH_INTERVAL=0)
#   실 JSON 칸(10-30 실측 byz-agents-worker-dev): status.latestCreatedRevisionName · latestReadyRevisionName · traffic[].{revisionName,percent,latestRevision}
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
  "run services describe "*) n="$(grep -c 'services describe' "$F/calls.log")"; s="$(sed -n "${n}p" "$F/svc.seq")"; [ -n "$s" ] || s="$(tail -n 1 "$F/svc.seq")"
    [ "$s" = FAIL ] && { echo "describe 대역 실패" >&2; exit 1; }; cat "$F/$s.json" ;;
  "run revisions describe "*) cat "$F/rev-$4.json" 2>/dev/null || { echo "not found $4" >&2; exit 1; } ;;
  "run services update-traffic "*) n="$(grep -c update-traffic "$F/calls.log")"; r="$(sed -n "${n}p" "$F/upd.rc" 2>/dev/null)"; echo "update-traffic 대역 rc=${r:-0}"; exit "${r:-0}" ;;
  *) exit 9 ;;
esac
EOS
cat > "$T/curl" <<'EOS'
#!/bin/bash
F="${FX:?}"; out=/dev/null
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac; done
n=$(( $(cat "$F/cn" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$F/cn"
l="$(sed -n "${n}p" "$F/health.seq")"; [ -n "$l" ] || l="$(tail -n 1 "$F/health.seq")"
printf '%s' "${l#*|}" > "$out"; printf '%s' "${l%%|*}"
EOS
chmod +x "$T/gcloud" "$T/curl"
rev() {  # <이름> <Ready> — env A · secret 참조 B(같은 의존)
  printf '{"spec":{"containers":[{"env":[{"name":"A","value":"v"},{"name":"B","valueFrom":{"secretKeyRef":{"name":"s-b","key":"latest"}}}]}]},"status":{"conditions":[{"type":"Ready","status":"%s"}]}}\n' "$2" > "$FX/rev-$1.json"
}
svc() {  # <파일 이름> <latestReady> <latestCreated> <켜진 리비전(LATEST 행)>
  printf '{"status":{"latestCreatedRevisionName":"%s","latestReadyRevisionName":"%s","traffic":[{"latestRevision":true,"percent":100,"revisionName":"%s"}]}}\n' "$3" "$2" "$4" > "$FX/$1.json"
}
rev w-00662 True; rev w-00663 True; rev w-00664 True; rev w-00665 True; rev w-00666 False
svc h254 w-00663 w-00664 w-00663      # R1: describe 순간 latestReady = 지금 · latestCreated = 막 준비된 새 리비전
svc mk w-00663 w-00666 w-00663        # R2: latestCreated 만드는 중(Ready=False)
svc same w-00663 w-00663 w-00663      # R6: latestCreated = 지금
svc on64 w-00664 w-00664 w-00664; svc on65 w-00665 w-00665 w-00665; svc on62 w-00663 w-00663 w-00662
OK200='200|{"status":"ok","consumer_ready":true}'; E503='503|{"consumer_ready":false,"reason":"worker_unreachable"}'
fx() { : > "$FX/calls.log"; rm -f "$FX/cn"; printf '%s\n' $1 > "$FX/svc.seq"; printf '%s\n' "$2" > "$FX/upd.rc"; shift 2; printf '%s\n' "$@" > "$FX/health.seq"; }
sw() { local b="$1"; shift; env -i HOME="$T/home" PATH="/usr/bin:/bin" FX="$FX" TS_GCLOUD="$T/gcloud" TS_CURL="$T/curl" TS_HEALTH_INTERVAL=0 \
  bash "$b/ft-traffic-switch.sh" --service svc --region r1 --health-url https://gw.test/health "$@" 2>&1; }
nupd() { grep -c 'update-traffic' "$FX/calls.log"; }
last() { printf '%s\n' "$1" | tail -n 1; }

check_r1() { local o rc; fx "h254 on64" 0 "$OK200"; o="$(sw "$1" --to LATEST=100)"; rc=$?
  [ "$rc" = 0 ] && [ "$(nupd)" = 1 ] || bad "R1 rc=$rc upd=$(nupd) ← ${o:0:500}"
  has "$o" "LATEST = w-00664(latestCreated)" "R1 ⓐ LATEST 를 latestCreated 로 풂"
  has "$o" "의존 대조 — 대상 w-00664 ↔ 지금 w-00663: 어긋남 0" "R1 ⓐ 푼 이름의 의존 대조 줄"
  hasnt "$o" "대조 생략" "R1 ⓐ 대조 생략 0"
  has "$o" "켜진 리비전 = w-00664" "R1 켜진 리비전 = 대조한 리비전"; }
check_r4() { local o rc; fx "h254 on65" 0 "$OK200"; o="$(sw "$1" --to LATEST=100)"; rc=$?
  [ "$rc" = 3 ] && [ "$(nupd)" = 2 ] && [ "$(cat "$FX/cn")" = 1 ] && has "$o" "원복 — 켜진 리비전 w-00665 가 대조 안 한 리비전" "R4 ⓒ 켜진 리비전 대조 안 함 = 원복 rc3 · health 창 전(원복 뒤 1회만)" \
    || bad "R4 rc=$rc upd=$(nupd) ← ${o:0:500}"; }

sec "R1·R6 LATEST 풀기"
check_r1 "$BIN0"
fx "same same" 0 "$OK200"; o="$(sw "$BIN0" --to LATEST=100)"; rc=$?
[ "$rc" = 0 ] && [ "$(nupd)" = 1 ] || bad "R6 rc=$rc upd=$(nupd) ← ${o:0:500}"
has "$o" "LATEST = w-00663(latestCreated) = 지금 리비전(대조 생략)" "R6 latestCreated = 지금 → 푼 이름과 함께 대조 생략 1줄"
sec "R2 준비 전 = 판정 불가"
fx "mk" 0 "$OK200"; o="$(sw "$BIN0" --to LATEST=100)"; rc=$?
[ "$rc" = 5 ] && [ "$(nupd)" = 0 ] && has "$o" "판정 불가 — 최신 리비전 준비 안 됨(created w-00666 Ready=False · ready w-00663) · 준비 뒤 다시" "R2 ⓑ rc5 · update-traffic 0" || bad "R2 rc=$rc upd=$(nupd) ← ${o:0:500}"
has "$(last "$o")" "판정 불가 rc=5" "R2 결과 줄이 마지막 줄"
sec "R3·R4 전환 뒤 켜진 리비전 대조"
fx "h254 on64" 0 "$E503" "$OK200"; o="$(sw "$BIN0" --to LATEST=100)"; rc=$?
[ "$rc" = 0 ] && [ "$(nupd)" = 1 ] && has "$o" "health 2: 200 consumer_ready=true" "R3 켜진 = 대조한 리비전 → health 창 진행(503→200 성공)" || bad "R3 rc=$rc ← ${o:0:500}"
check_r4 "$BIN0"
fx "h254 FAIL" 0 "$OK200"; o="$(sw "$BIN0" --to LATEST=100)"; rc=$?
[ "$rc" = 3 ] && [ "$(nupd)" = 2 ] && has "$o" "원복 — 전환 뒤 켜진 리비전 조회 실패" "전환 뒤 조회 실패 = 원복 rc3(전환 뒤라 원복 쪽)" || bad "조회 실패 rc=$rc ← ${o:0:500}"
sec "R5 이름 직접 = r1133 그대로"
fx "same on62" 0 "$OK200"; o="$(sw "$BIN0" --to w-00662=100)"; rc=$?
[ "$rc" = 0 ] && has "$o" "의존 대조 — 대상 w-00662 ↔ 지금 w-00663: 어긋남 0" "R5 이름 직접 = 대조 후 전환 rc0" || bad "R5 rc=$rc ← ${o:0:500}"
hasnt "$o" "latestCreated" "R5 LATEST 풀이 줄 0"

sec "ⓔ bin·kit 같은 내용 · 줄 상한"
cmp -s "$BIN0/ft-traffic-switch.sh" "$KIT/ft-traffic-switch.sh" && ok "bin=kit ft-traffic-switch.sh" || bad "bin≠kit ft-traffic-switch.sh"
n="$(wc -l < "$BIN0/ft-traffic-switch.sh" | tr -d ' ')"; [ "$n" -le 200 ] && ok "ft-traffic-switch.sh ${n}줄 ≤200" || bad "ft-traffic-switch.sh ${n}줄 > 200"

mutant() {  # <이름> <sed 식> → 변이 bin 경로(원본과 다르면)
  local m="$T/mut-$1"; cp -R "$BIN0" "$m" && sed "$2" "$BIN0/ft-traffic-switch.sh" > "$m/ft-traffic-switch.sh"
  cmp -s "$BIN0/ft-traffic-switch.sh" "$m/ft-traffic-switch.sh" && { bad "변이 $1 사본 = 원본"; return 1; }; echo "$m"
}
sec "변이 2 — 각 변이가 대응 칸을 FAIL 시킨다(검출)"
mutv() { local f0=$fail; "$@" > /dev/null 2>&1; local d=$((fail - f0)); fail=$f0; [ "$d" -gt 0 ]; }   # 같은 셸에서 돌려 FAIL 수를 센다
m="$(mutant ready 's/n="\${LCREATED:-}"/n="${LREADY:-}"/')" && { mutv check_r1 "$m" && ok "변이 1(LATEST = latestReady 로 되돌림) → R1 FAIL 검출" || bad "변이 1 을 못 잡음"; }
m="$(mutant after '/^for r in \$ON; do/d')" && { mutv check_r4 "$m" && ok "변이 2(전환 뒤 켜진 리비전 대조 삭제) → R4 FAIL 검출" || bad "변이 2 를 못 잡음"; }

sec "끝"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
