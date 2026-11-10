#!/usr/bin/env bash
# ft-anchor-a-request-log.sh — 앵커 A(계정별 요청 기록) 잊지 않는 장치 (r1571 카드 ⓒⓓⓕⓖⓗ · Issue byz#8209)
#   run(기본) = launchd 1개가 1시간 간격으로 부른다. cliproxy 를 재기동하지 않고(launchctl·kill 호출 0) config 를 쓰지 않는다.
#     ② 끝 시각(아래 상수 1줄) 뒤 첫 실행에 «끄기·지우기 h 실행 요청» 1통 · 완료 표식이 없으면 24시간마다 1통
#     ③ 끄기 h 완료 표식이 생기면 그 뒤 알림·경보 0 + 해제 안내 1줄(그 1줄이 마지막 발신)
#     ③' logs/main*.log 합계 ≥ 상한의 80% 면 1통 — 같은 구간 반복 0(합계가 80% 아래로 내려가야 다시 켜진다)
#     ④ 하루 1회 전환 추출 — 계정이 바뀐 첫 줄만 «시각<TAB>이전<TAB>다음» 1행 · 로그는 읽기만(수정 0)
#   수신자 = seats-planner.json `_desk`(desk) + `_hil_route`(planner master) — 없으면 ERROR rc3(다른 좌석으로 대신 보내지 않는다)
#   비밀 0: 계정은 이메일 그대로, API key 이름은 «(api-key-id)» 로 가린다 · 요청 본문을 읽지 않는다.
#   env(시험용): FT_ANCHOR_NOW·FT_ANCHOR_MBOX·FT_ANCHOR_SEATS·FT_ANCHOR_LOGS·FT_ANCHOR_STATE_DIR·FT_ANCHOR_DONE·FT_ANCHOR_CAP_MB·FT_ANCHOR_END_TS·FT_ANCHOR_ME
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
END_TS="${FT_ANCHOR_END_TS:-1794888000}"   # ⓓ 끝 시각 1곳 = 2026-11-17 13:00 KST(=04:00Z) — h 문서 §0 과 같은 값
CAP_MB="${FT_ANCHOR_CAP_MB:-1024}"         # ⓐ logs-max-total-size-mb 제안값(상한) — 80% 가 경보선
D="${FT_ANCHOR_STATE_DIR:-$HOME/.claude/fable-team/state/capacity}"
ST="$D/anchor-a-alert.state"; OUT="$D/anchor-a-transitions.tsv"; DONE="${FT_ANCHOR_DONE:-$D/anchor-a-done}"
LOGS="${FT_ANCHOR_LOGS:-$HOME/.cli-proxy-api/logs}"; ME="${FT_ANCHOR_ME:-ft-anchor-a-request-log}"
mkdir -p "$D" 2>/dev/null || { echo "ERROR 상태 폴더 생성 실패: $D" >&2; exit 4; }
n(){ case "${1:-}" in ''|*[!0-9]*) echo 0;; *) echo "$1";; esac; }
kv(){ sed -n "s/^$1=//p" "$ST" 2>/dev/null | tail -1; }
save(){ ( umask 022; printf 'released=%s\nreq_sent=%s\nsize_armed=%s\nextract_last=%s\n' "$REL" "$REQ" "$ARMED" "$EXT" > "$ST" ); }
mbox="${FT_ANCHOR_MBOX:-}"
if [ -z "$mbox" ]; then . "$HERE/ft-harness-root.sh"; C="$(ft_comm_dir "$HERE")" || exit 3; mbox="$C/mbox.sh"; fi
SEATS="${FT_ANCHOR_SEATS:-}"
if [ -z "$SEATS" ]; then . "$HERE/ft-harness-root.sh"; R="$(ft_repo_root "$HERE")" || exit 3; SEATS="$R/.fable-team/seats-planner.json"; fi
route(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get(sys.argv[2],"") or "")' "$SEATS" "$1" 2>/dev/null; }
DESK="$(route _desk)"; PLAN="$(route _hil_route)"
[ -n "$DESK" ] && [ -n "$PLAN" ] || { echo "ERROR 받는이 없음 — $SEATS 의 _desk·_hil_route" >&2; exit 3; }
send(){ bash "$mbox" send "$1" "$ME" "$2" >/dev/null 2>&1 || { echo "ERROR mbox send 실패 to=$1" >&2; return 3; }; }
now="${FT_ANCHOR_NOW:-$(date +%s)}"; rc=0; REL="$(n "$(kv released)")"; REQ="$(n "$(kv req_sent)")"
ARMED="$(kv size_armed)"; [ -n "$ARMED" ] || ARMED=1; EXT="$(n "$(kv extract_last)")"

if [ -e "$DONE" ]; then   # ③ 해제 안내 1줄 뒤 알림·경보 0 (M10)
  [ "$REL" = 1 ] && exit 0
  send "$DESK" "[앵커 A 해제] 끄기·지우기 완료 표식 확인($DONE) — 이 시각부터 알림·경보를 멈춘다. launchd 는 끄기 h 마지막 단계에서 아직 해제하지 않았다면 bootout 1회." || exit 3
  REL=1; save; exit 0
fi
bytes=0; for f in "$LOGS"/main*.log; do [ -f "$f" ] || continue; bytes=$((bytes + $(stat -f%z "$f" 2>/dev/null || echo 0))); done
thr=$(( CAP_MB * 1048576 * 8 / 10 ))
if [ "$bytes" -ge "$thr" ] && [ "$ARMED" = 1 ]; then   # ⓖ 크기 경보 — 같은 구간 반복 0 (M5)
  body="[앵커 A 크기 경보] logs/main*.log 합계 $((bytes/1048576))MB ≥ 상한의 80%($((thr/1048576))MB · 상한 ${CAP_MB}MB · 경로 $LOGS). 끄기·지우기 h 로 정리하고 추출 결과를 aifp#3 에 넘겼는지 확인."
  if send "$DESK" "$body" && send "$PLAN" "$body"; then ARMED=0; else rc=3; fi
fi
[ "$bytes" -ge "$thr" ] || ARMED=1
if [ "$now" -ge "$END_TS" ] && { [ "$REQ" = 0 ] || [ $((now-REQ)) -ge 86400 ]; }; then   # ② 끝 시각 뒤 요청 · 24시간 반복 (M1)
  body="[앵커 A 끄기·지우기 h 실행 요청] 끝 시각(2026-11-17 13:00 KST)이 지났다. h 문서 §끄기·지우기 순서: 3키 복구→설정 재적재 확인(debug=false 줄)→관측기 종료→삭제(logs/main*.log 와 state/capacity/anchor-sampler.log 만 · 보존 anchor-t0.json·anchor-watch.py·anchor-snapshots.jsonl)→완료 표식→plist 해제."
  send "$DESK" "$body" && send "$PLAN" "$body" && REQ="$now" || rc=3
fi
if [ $((now-EXT)) -ge 86400 ]; then   # ④ 전환 추출 하루 1회 (M4) — 로그 폴더·파일 없음 = 정상 경로(추출 0행 · rc0)
  if [ ! -d "$LOGS" ]; then EXT="$now"
  elif find "$LOGS" -maxdepth 1 -name 'main*.log' -type f -exec cat {} + 2>/dev/null | awk '
    { if (match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ T][0-9][0-9]:[0-9][0-9]:[0-9][0-9]/)) ts=substr($0,RSTART,RLENGTH)
      acct=""
      if (match($0, /Use OAuth [^ ].* for model/)) {   # 실제 형식 = «Use OAuth provider=<p> auth_file=<계정> for model» (DA #279622) · 옛 형식 «Use OAuth <계정> for model» 도 받는다
        s=substr($0,RSTART,RLENGTH); sub(/^Use OAuth /,"",s); sub(/ for model$/,"",s)
        if (match(s, /auth_file=[^ ]+/)) acct=substr(s,RSTART+10,RLENGTH-10)
        else { split(s,f," "); acct=f[1] } }
      else if (match($0, /Use API key [^ ]+ for model/)) acct="(api-key-id)"
      if (acct=="") next
      if (prev!="" && acct!=prev) print ts "\t" prev "\t" acct
      prev=acct }' > "$OUT.new"; then
    { [ -f "$OUT" ] && cat "$OUT"; cat "$OUT.new"; } | awk '!seen[$0]++' > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
    rm -f "$OUT.new"; EXT="$now"
  else echo "ERROR 전환 추출 실패 — 다음 회 재시도(${LOGS})" >&2; rc=3; fi
fi
save; exit $rc
