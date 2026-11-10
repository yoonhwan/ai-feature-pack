#!/usr/bin/env bash
# test_distill_failopen_r1554.sh — r1554: 증류 훅의 «판정 불가» 를 좌석/하위 세션/그 밖 3갈래로 가른다.
#   사례 ⓐ(3갈래) ⓑ(첫 통과 → 연속 N회 막음) ⓒ(팀장 1통) ⓓ(닫는 사건) ⓔ(판정 가능 동작 그대로) ⓕ(감사 표)
#   변이 M1~M4 = 그 갈래를 하나씩 없애면 해당 사례가 무너지는지(변이는 그 사례만 돌린다 = 시간 상한).
#   실좌석·실홈·실우편함 쓰기 0(전부 $TMP). 인자: 없음. /bin/bash(macOS 3.2) 로 실행.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${R1554_SUT:-$HERE/../../harness/kit/fable-team/templates/hooks/context-distill-gate.sh}"
AUDIT="${R1554_AUDIT:-$HERE/../../harness/kit/fable-team/bin/ft-distill-audit.sh}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
want() { [ -z "${R1554_ONLY:-}" ] && return 0; case " $R1554_ONLY " in *" $1 "*) return 0;; *) return 1;; esac; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; HOMED="$TMP/home"; SEAT="byz-t-seat#0"; SESS="sess-1554"; MBOX="$TMP/mbox.sh"
LOG="$HOMED/.claude/logs/context-distill-gate.log"; STREAK="$HOMED/.claude/state/distill-gate-failopen/$SESS.json"
mkdir -p "$REPO/.fable-team/comm" "$HOMED" "$REPO/.fable-team/state/inbox-haiku-cwd/sub"; git -C "$REPO" init -q
printf '{"_master":"byz-harness-master-pi#172","%s":{"role":"nano","agent":"claude"}}\n' "$SEAT" > "$REPO/.fable-team/seats-harness.json"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %s\n' "$TMP/mbox.log" > "$MBOX"

run() { # run <훅> <모드> <cwd> <transcript|-> <좌석|-> → $RC · 로그 = $LOG
  local h="$1" mode="$2" cwd="$3" tr="$4" seat="$5"; [ "$tr" = "-" ] && tr="$TMP/nope.jsonl"
  local json; json="$(python3 -c 'import json,sys
print(json.dumps({"transcript_path":sys.argv[1],"cwd":sys.argv[2],"session_id":sys.argv[3],"tool_name":"Bash","tool_input":{"command":"ls"}}))' "$tr" "$cwd" "$SESS")"
  local se=""; [ "$seat" != "-" ] && se="$seat"
  printf '%s' "$json" | env HOME="$HOMED" FT_MBOX="$MBOX" FT_SEAT="$se" TMUX_PANE= /bin/bash "$h" "$mode" >"$TMP/out" 2>"$TMP/err"
  RC=$?
}
tx() { printf '{"type":"assistant","message":{"model":"claude-opus-5-5","usage":{"input_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$1" > "$TMP/t.jsonl"; echo "$TMP/t.jsonl"; }
lines() { [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }
undecided() { awk '/undecidable/{n++} END{print n+0}' "$LOG" 2>/dev/null; }
reset_all() { rm -rf "$HOMED/.claude" "$TMP/mbox.log"; }
sends() { awk '/send byz-harness-master-pi#172/{n++} END{print n+0}' "$TMP/mbox.log" 2>/dev/null; }

cases() { # cases <이름> <훅>
  local n="$1" h="$2"
  /bin/bash -n "$h" && ok "$n /bin/bash -n" || bad "$n /bin/bash -n"

  if want ⓐ1; then reset_all
    run "$h" hard "$REPO/.fable-team/state/inbox-haiku-cwd/sub" - "$SEAT"
    { [ "$RC" -eq 0 ] && [ "$(lines)" -eq 0 ] && [ ! -s "$TMP/err" ]; } && ok "$n ⓐ1 하위 세션 → 면제(로그 0 · stderr 0)" || bad "$n ⓐ1 rc=$RC log=$(lines)"; fi

  if want ⓐ2; then reset_all
    run "$h" hard "$REPO" - "$SEAT"
    { [ "$RC" -eq 0 ] && [ "$(lines)" -eq 1 ] && grep -q "undecidable branch=seat seat=$SEAT session=$SESS reason=transcript-missing n=1/3" "$LOG"; } \
      && ok "$n ⓐ2 좌석 → 기록 1줄 + 통과(n=1/3)" || bad "$n ⓐ2 rc=$RC log=$(cat "$LOG" 2>/dev/null)"; fi

  if want ⓐ3; then reset_all
    run "$h" hard "$REPO" - "-"
    { [ "$RC" -eq 1 ] && [ "$(lines)" -eq 1 ] && grep -q 'error mode=hard branch=other' "$LOG" && grep -q 'fail-open' "$TMP/err"; } \
      && ok "$n ⓐ3 명부 밖 → 경고 통과(rc 1, branch=other)" || bad "$n ⓐ3 rc=$RC log=$(cat "$LOG" 2>/dev/null)"; fi

  if want ⓑ; then reset_all
    run "$h" hard "$REPO" - "$SEAT"; r1="$RC"
    run "$h" hard "$REPO" - "$SEAT"; r2="$RC"
    run "$h" hard "$REPO" - "$SEAT"; r3="$RC"
    { [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$r3" -eq 2 ] && grep -q 'n=3/3' "$LOG"; } \
      && ok "$n ⓑ 연속 3회 = 막음(rc 2) · 1~2회는 통과" || bad "$n ⓑ rc=$r1/$r2/$r3"
    { [ "$(sends)" -eq 1 ] && grep -q '증류 판정 불가 byz-t-seat#0 transcript-missing' "$TMP/mbox.log"; } \
      && ok "$n ⓒ 팀장 1줄 «[긴급] 증류 판정 불가 <좌석> <이유>»" || bad "$n ⓒ mbox=$(cat "$TMP/mbox.log" 2>/dev/null)"
    run "$h" hard "$REPO" - "$SEAT"
    [ "$(sends)" -eq 1 ] && ok "$n ⓒ2 4회째에도 1통(중복 0)" || bad "$n ⓒ2 중복 발송 $(sends)"; fi

  if want ⓓ; then reset_all
    run "$h" hard "$REPO" - "$SEAT"   # n=1
    run "$h" hard "$REPO" - "$SEAT"   # n=2
    run "$h" warn "$REPO" "$(tx 100000)" "$SEAT"; r4="$RC"
    { [ "$r4" -eq 0 ] && [ ! -f "$STREAK" ]; } && ok "$n ⓓ 닫는 사건 — 판정 가능해지면 연속 횟수 0" || bad "$n ⓓ streak 남음 rc=$r4 $(cat "$STREAK" 2>/dev/null)"
    run "$h" hard "$REPO" - "$SEAT"; r5="$RC"
    { [ "$r5" -eq 0 ] && grep -q 'n=1/3' "$LOG"; } && ok "$n ⓓ2 닫힌 뒤 다시 1회부터(막힘 0)" || bad "$n ⓓ2 rc=$r5 $(tail -1 "$LOG")"; fi

  if want ⓔ; then reset_all
    run "$h" warn "$REPO" "$(tx 100000)" "$SEAT"; e1="$RC"; o1="$(cat "$TMP/out")"
    run "$h" warn "$REPO" "$(tx 260000)" "$SEAT"; e2="$RC"; o2="$(cat "$TMP/out")"
    run "$h" hard "$REPO" "$(tx 310000)" "$SEAT"; e3="$RC"
    { [ "$e1" -eq 0 ] && [ -z "$o1" ] && [ "$e2" -eq 0 ] && printf '%s' "$o2" | grep -q '260k' && [ "$e3" -eq 2 ] \
      && [ "$(undecided)" -eq 0 ] && [ ! -f "$STREAK" ]; } \
      && ok "$n ⓔ 판정 가능 = 경고·차단 그대로(판정 불가 줄·상태 0)" || bad "$n ⓔ rc=$e1/$e2/$e3 undecided=$(undecided)"; fi

  if want ⓕ; then
    local now; now="$(date +%FT%T)"
    { printf '%s undecidable branch=seat seat=a#0 session=s1 reason=transcript-missing n=1/3\n' "$now"
      printf '%s undecidable branch=seat seat=a#0 session=s1 reason=transcript-missing n=2/3\n' "$now"
      printf '%s undecidable-block branch=seat seat=a#0 session=s1 reason=transcript-missing n=3/3 notified=sent:m\n' "$now"
      printf '%s error mode=hard branch=other reason=scan-failed detail="x"\n' "$now"
      printf '%s error mode=warn transcript missing: %s\n' "$now" "''"
      printf '%s undecidable branch=seat seat=b#0 session=s2 reason=no-usage n=1/3\n' "$now"
    } > "$TMP/audit.log"
    bash "$AUDIT" --log "$TMP/audit.log" --hours 24 > "$TMP/audit.out" 2>"$TMP/audit.err"; local arc=$?
    { [ "$arc" -eq 0 ] && grep -qE '^seat-record +3 ' "$TMP/audit.out" && grep -qE '^seat-block +1 ' "$TMP/audit.out" \
      && grep -qE '^other +1 ' "$TMP/audit.out" && grep -qE '^other-legacy +1 ' "$TMP/audit.out" \
      && grep -qE '^subsession +0 ' "$TMP/audit.out" && grep -qE '^a#0 +3$' "$TMP/audit.out" && grep -qE '^b#0 +1$' "$TMP/audit.out"; } \
      && ok "$n ⓕ 감사 표(갈래별 4줄 · 좌석별 a#0 3 / b#0 1)" || bad "$n ⓕ rc=$arc $(cat "$TMP/audit.out" "$TMP/audit.err" 2>/dev/null | tr '\n' ' ')"; fi
}

cases 진본 "$KIT"
i=0
for spec in \
  'if cwd_n and SUBSESSION_RE.search(cwd_n):|if False:|ⓐ1|ⓐ1' \
  'escalated = st["n"] >= FAILOPEN_MAX|escalated = False|ⓑ|ⓑ' \
  'if escalated and reason not in st["notified"]:|if escalated:|ⓑ|ⓒ' \
  'streak_reset()  # r1554|pass  # r1554|ⓓ|ⓓ'; do
  i=$((i+1)); IFS='|' read -r o nw ro ef <<<"$spec"
  M="$TMP/mut$i.sh"
  if OLD="$o" NEW="$nw" python3 - "$KIT" "$M" <<'PYEOF'
import os, sys
src = open(sys.argv[1], encoding="utf-8").read()
if os.environ["OLD"] not in src: sys.exit("변이 대상 없음: " + os.environ["OLD"][:60])
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(os.environ["OLD"], os.environ["NEW"], 1))
PYEOF
  then R1554_SUT="$M" R1554_ONLY="$ro" bash "${BASH_SOURCE[0]}" > "$TMP/mut$i.out" 2>&1; RC=$?
    { [ "$RC" -ne 0 ] && grep -q "^FAIL 진본 $ef" "$TMP/mut$i.out"; } && ok "M$i $ef 없어지면 무너진다" || bad "M$i $ef 변이가 안 잡힌다(rc=$RC)"
  else bad "M$i 변이 생성"; fi
done
echo "$([ "$fail" -eq 0 ] && echo ALL PASS || echo FAIL=$fail)"
[ "$fail" -eq 0 ] || exit 1
