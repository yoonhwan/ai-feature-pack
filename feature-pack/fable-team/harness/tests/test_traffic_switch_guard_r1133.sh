#!/usr/bin/env bash
# test_traffic_switch_guard_r1133.sh — r1133: ft-traffic-switch.sh(의존 대조 · 전환 뒤 health · 자동 원복) + ft-hil lint(날 update-traffic REJECT)
#   카드 반례 R1~R8 · 변이 3 · bin·kit 같은 내용 · 줄 상한
# 격리: gcloud 대역(응답 파일 · 호출 기록 calls.log · update-traffic rc 차례 upd.rc) + curl 대역(응답 차례 health.seq) + 임시 HIL_DIR
#   실 gcloud·실 서비스·실 /tmp/h* 0 · 자기 재호출 0(변이는 bin 사본을 함수로 돌린다) · 고정 sleep 0(TS_HEALTH_INTERVAL=0)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 RSG_ACTIVE)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
sec() { echo "== $1 (누적 $((SECONDS - T0))s)"; }

FX="$T/fx"; mkdir -p "$FX" "$T/home" "$T/comm"
cat > "$T/gcloud" <<'EOS'
#!/bin/bash
F="${FX:?}"; echo "$*" >> "$F/calls.log"
case "$*" in
  "run services describe "*) cat "$F/svc.json" ;;
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
rev() {  # <이름> <Ready> <env 이름…> — B 는 secret 참조
  local n="$1" rd="$2" e js=""; shift 2
  for e in "$@"; do
    [ "$e" = B ] && js="$js{\"name\":\"B\",\"valueFrom\":{\"secretKeyRef\":{\"name\":\"s-b\",\"key\":\"latest\"}}}," || js="$js{\"name\":\"$e\",\"value\":\"v\"},"
  done
  printf '{"spec":{"containers":[{"env":[%s]}]},"status":{"conditions":[{"type":"Ready","status":"%s"}]}}\n' "${js%,}" "$rd" > "$FX/rev-$n.json"
}
printf '{"status":{"latestReadyRevisionName":"cur-1","traffic":[{"revisionName":"cur-1","percent":100,"latestRevision":true}]}}\n' > "$FX/svc.json"
rev cur-1 True A B; rev old-1 True A B C; rev old-2 True A; rev nr-1 False A B
OK200='200|{"status":"ok","consumer_ready":true}'; FALSE200='200|{"status":"ok","consumer_ready":false}'
E503='503|{"consumer_ready":false,"reason":"worker_unreachable"}'
fx() { : > "$FX/calls.log"; rm -f "$FX/cn"; printf '%s\n' "$1" > "$FX/upd.rc"; shift; printf '%s\n' "$@" > "$FX/health.seq"; }
sw() { local b="$1"; shift; env -i HOME="$T/home" PATH="/usr/bin:/bin" FX="$FX" TS_GCLOUD="$T/gcloud" TS_CURL="$T/curl" TS_HEALTH_INTERVAL=0 \
  bash "$b/ft-traffic-switch.sh" --service svc --region r1 --health-url https://gw.test/health "$@" 2>&1; }
nupd() { grep -c 'update-traffic' "$FX/calls.log"; }
last() { printf '%s\n' "$1" | tail -n 1; }

check_r1() { local o rc; fx 0 "$E503" "$E503" "$OK200"; o="$(sw "$1" --to old-1=100)"; rc=$?
  [ "$rc" = 0 ] && [ "$(nupd)" = 1 ] && has "$(last "$o")" "health=200 consumer_ready=true · 성공" "R1 503→503→200 = 성공 rc0 · 원복 0" || bad "R1 rc=$rc upd=$(nupd) ← $o"; }
check_r2() { local o rc; fx "0" "$E503"; o="$(sw "$1" --to old-1=100)"; rc=$?
  [ "$rc" = 3 ] && [ "$(nupd)" = 2 ] && grep -q 'update-traffic svc --region=r1 --to-revisions=cur-1=100' "$FX/calls.log" \
    && has "$(last "$o")" "health=503 consumer_ready=false · 원복 rc=3" "R2 끝까지 503 = 직전 표(LATEST 행 → cur-1=100 고정 · r1140)로 원복 1회 · rc3" || bad "R2 rc=$rc upd=$(nupd) ← $o"; }
check_r3() { local o rc; fx "0" "$FALSE200"; o="$(sw "$1" --to old-1=100)"; rc=$?
  [ "$rc" = 3 ] && [ "$(nupd)" = 2 ] && has "$(last "$o")" "원복 rc=3" "R3 200 ∧ consumer_ready=false = 성공 아님 · 원복 rc3" || bad "R3 rc=$rc upd=$(nupd) ← $o"; }

sec "R1~R3 전환 뒤 health · 자동 원복"
check_r1 "$BIN0"; check_r2 "$BIN0"; check_r3 "$BIN0"
o="$(sw "$BIN0" --to old-1=100)"; has "$o" "의존 대조 — 대상 old-1 ↔ 지금 cur-1: 어긋남 0" "R1 사전 확인 줄(의존 대조)"
sec "R4·R5 의존 대조"
fx 0 "$OK200"; o="$(sw "$BIN0" --to old-2=100)"; rc=$?
[ "$rc" = 1 ] && [ "$(nupd)" = 0 ] && has "$o" "REJECT 의존 어긋남 — 대상 old-2 에 없는 키: env:B secret:s-b" "R4 대상에 env·secret 없음 = rc1 · update-traffic 0" || bad "R4 rc=$rc upd=$(nupd) ← $o"
fx 0 "$OK200"; o="$(sw "$BIN0" --to old-2=100 --allow-env-drift "B 는 옛 코드가 안 읽음")"; rc=$?
[ "$rc" = 0 ] && [ "$(nupd)" = 1 ] && has "$o" "의존 어긋남 허용(--allow-env-drift): B 는 옛 코드가 안 읽음 — 대상 old-2 에 없는 키: env:B secret:s-b" "R5 이유 주면 전환 + 이유 1줄" || bad "R5 rc=$rc upd=$(nupd) ← $o"
fx 0 "$OK200"; o="$(sw "$BIN0" --to nr-1=100)"; rc=$?
[ "$rc" = 1 ] && [ "$(nupd)" = 0 ] && has "$o" "REJECT 대상 nr-1 준비 안 됨(Ready=False)" "대상 Ready 아님 = rc1 · 전환 0" || bad "Ready rc=$rc ← $o"
sec "R8 원복도 실패"
fx "$(printf '0\n1')" "$E503"; o="$(sw "$BIN0" --to old-1=100)"; rc=$?
[ "$rc" = 4 ] && has "$o" "원복 실패 — 손 원복: gcloud run services update-traffic svc --region=r1 --to-revisions=cur-1=100" "R8 rc4 + 손 원복 명령 1줄(이름 고정 표 · r1140)" || bad "R8 rc=$rc ← $o"
has "$(last "$o")" "원복 실패 rc=4" "R8 결과 줄이 마지막 줄"

sec "R6·R7 ft-hil --add 등록 거절"
HD="$T/hil"; mkdir -p "$HD"
hil() { env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$T/comm" bash "$1/ft-hil.sh" --add "$2" 2>&1; }
nh() { find "$HD" -maxdepth 1 -name 'h[0-9]*' ! -name '*.*' | wc -l | tr -d ' '; }
plan() { printf '#!/usr/bin/env bash\n# ft-hil-request seat=byz-harness-master-claude#1\n# 되돌림: gcloud run services update-traffic svc --region=r1 --to-revisions=x=100\n%s\n' "$2" > "$T/$1.sh.hil"; }
plan raw 'S=svc; G=r1; timeout 60 gcloud run services \
  update-traffic "$S" --region="$G" --to-revisions="old=100"'
plan nourl 'bash ft-traffic-switch.sh --service svc --region r1 --to old-1=100'
plan good 'bash ft-traffic-switch.sh --service svc --region r1 --to old-1=100 --health-url https://gw.test/health'
check_r6() { local o rc n0; n0="$(nh)"; o="$(hil "$1" "$T/raw.sh.hil")"; rc=$?
  [ "$rc" = 1 ] && [ "$(nh)" = "$n0" ] && has "$o" "REJECT 트래픽 전환은 ft-traffic-switch.sh 로(전환 뒤 health·자동 원복) — 날 update-traffic 줄 4" "R6 날 update-traffic(이어 쓰기) = REJECT · 등록 0 · 주석 줄은 통과" || bad "R6 rc=$rc h=$(nh) ← $o"; }
check_r6 "$BIN0"
o="$(hil "$BIN0" "$T/nourl.sh.hil")"; rc=$?
[ "$rc" = 1 ] && [ "$(nh)" = 0 ] && has "$o" "REJECT ft-traffic-switch.sh 호출에 --health-url 이 없다" "R7 --health-url 없음 = REJECT · 등록 0" || bad "R7 rc=$rc ← $o"
o="$(hil "$BIN0" "$T/good.sh.hil")"; rc=$?
[ "$rc" = 0 ] && [ "$(nh)" = 1 ] && ok "대조: 도구 + --health-url 계획 = 등록 h1" || bad "대조 등록 rc=$rc h=$(nh) ← $o"

sec "ⓔ bin·kit 같은 내용 · 줄 상한"
for f in ft-traffic-switch.sh ft_traffic_plan_judge.py ft-hil.sh; do
  cmp -s "$BIN0/$f" "$KIT/$f" && ok "bin=kit $f" || bad "bin≠kit $f"
  n="$(wc -l < "$BIN0/$f" | tr -d ' ')"; [ "$n" -le 200 ] && ok "$f ${n}줄 ≤200" || bad "$f ${n}줄 > 200"
done

mutant() {  # <이름> <파일> <sed 식> → 변이 bin 경로(원본과 다르면)
  local m="$T/mut-$1"; cp -R "$BIN0" "$m" && sed "$3" "$BIN0/$2" > "$m/$2"
  cmp -s "$BIN0/$2" "$m/$2" && { bad "변이 $1 사본 = 원본"; return 1; }; echo "$m"
}
sec "변이 3 — 각 변이가 대응 칸을 FAIL 시킨다(검출)"
mutv() { local f0=$fail; "$@" > /dev/null 2>&1; local d=$((fail - f0)); fail=$f0; [ "$d" -gt 0 ]; }   # 같은 셸에서 돌려 FAIL 수를 센다
m="$(mutant cr ft-traffic-switch.sh 's/\[ "\$HC" = 200 \] && \[ "\$HR" = true \]/[ "$HC" = 200 ]/')" && { mutv check_r3 "$m" && ok "변이 1(consumer_ready 검사 삭제) → R3 FAIL 검출" || bad "변이 1 을 못 잡음"; }
m="$(mutant rb ft-traffic-switch.sh 's/^watch_health || restore .*/watch_health || :/')" && { mutv check_r2 "$m" && ok "변이 2(원복 삭제) → R2 FAIL 검출" || bad "변이 2 를 못 잡음"; }
m="$(mutant judge ft-hil.sh 's/ && lint "\$f" "\${FT_TRAFFIC_JUDGE[^}]*}" "트래픽 전환" ""//')" && { rm -rf "$HD"; mkdir -p "$HD"; mutv check_r6 "$m" && ok "변이 3(판정 호출 삭제) → R6 FAIL 검출" || bad "변이 3 을 못 잡음"; }

sec "끝"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
