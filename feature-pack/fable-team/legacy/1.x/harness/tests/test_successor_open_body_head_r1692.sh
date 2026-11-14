#!/usr/bin/env bash
# test_successor_open_body_head_r1692.sh — r1692: 후계 «개설 쪽지» 가 [인계] 묶음에 세어져 ready·close 가 영구 막히던 자리.
#   ⓐ 개설 본문 첫 줄 머리 «[인계]»·«[레디]»(앞 공백 포함) → ft-successor-open REJECT rc1 · 좌석 열기·송신 0
#   ⓑ «[승계 발주] …» 머리 = 지금 그대로 통과(스텁 송신 1)
#   ⓒ 도달 파일 seq 의 개설 쪽지는 묶음 밖 → ready «[인계] #<기계 seq> 받음 · 항목 2» · close-check CLOSE-OK
#   ⓓ 도달 파일 없음 = 지금 그대로(형식 불명 REJECT rc3)   ⓔ 도달 파일 깨짐 = 넘기지 않음(rc3 · 예외 0)
#   ⓕ 손 [인계](도달 파일 seq 와 다른 seq) = 지금 그대로 형식 불명 REJECT rc3(r1116b ④ 보존)
#   변이(사본에서만): M1 머리 검사 삭제 → ⓐ FAIL · M2 seq 빼기 삭제 → ⓒ FAIL · M3 «도달 파일 무관하게 형식 불명 빼기» → ⓕ FAIL
# 격리: 가짜 tmux·tmuxc·pgrep·send·mbox·reach(PATH 앞 스텁) + 임시 리포·임시 우편함(FT_MBOX_DIR·FT_MBOX_STATE_DIR) · 실 세션·실 명부·실 우편함 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."; SRC="$REPO/harness/comm"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:0:400}"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SO="$REPO/harness/kit/fable-team/bin/ft-successor-open.sh"
F="$T/fakebin"; lg="$T/calls.log"; R="$T/repo"; OLD="byz-t-old-claude#1"; NEW="byz-t-new-claude#2"
mkdir -p "$F" "$R"; git -C "$R" init -q
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$F/$1"; chmod +x "$F/$1"; }
mkstub tmux 'case "$1" in has-session) [ -f "$OPENED" ] && exit 0; exit 1;; list-panes) echo 4242;; send-keys) :;; display-message) echo "$PANE_CWD";; esac; exit 0'
mkstub tmuxc 'echo "tmuxc $*" >> "$LOG"; : > "$OPENED"; exit 0'
mkstub pgrep 'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo pgrep >> "$LOG"; echo 5555; exit 0'
mkstub send 'echo send >> "$LOG"; printf "%s" "$2" > "$SENT"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit 0'
mkstub mbox 'echo "mbox $1" >> "$LOG"; exit 0'; : > "$F/mbox_doorbell.sh"; mkstub reach 'exit 0'
mkstub ft-hil.sh '[ "$1 $2" = "--pending --each" ] && { echo "h62 3"; exit 0; }
exit 2'
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok; RES="$FT_RES_ROOT"; SENSORS="$T/sensors/fake-sensors"
mkdir -p "$RES/design" "$R/.fable-team" "$T/live"
printf '# TEAMS\n\n| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| t | `design/t/` | byz-t-master-claude | 현역 |\n' > "$RES/design/TEAMS.md"
printf '{"byz-t-master-claude":{"role":"master","model":"m"},"%s":{"role":"master","model":"m"},"%s":{"role":"master","model":"m"}}\n' "$OLD" "$NEW" > "$RES/.fable-team/seats-t.json"
printf '| 팀 | 오케 | arch 상시 |\n|---|---|---|\n| t | byz-t-master-claude | — |\n' > "$T/teamset.md"
printf '<!-- S17-BOOT-BEGIN -->\n목적 0 = 진행 카드를 완성하고 닫는다.\n<!-- S17-BOOT-END -->\n' > "$T/gov.md"
printf '%s\n' "$T/live" > "$R/.fable-team/LIVE_ROOT"
GOL='골 원문 1줄\n골 원문 2줄\n골 원문 3줄'
so_run() {  # so_run [개설도구] — 개설 1회(로그·도달 파일 초기화 · 본문 = $T/b.txt)
  rm -f "$lg" "$T/opened"; rm -rf "$R/.fable-team/state"; : > "$lg"
  env HOME="$T/home" PANE_CWD="$T/pane" PATH="$F:$PATH" LOG="$lg" OPENED="$T/opened" SENT="$T/sent.txt" \
      SENSORS="$SENSORS" FT_RES_ROOT="$RES" FT_TEAMSET_MD="$T/teamset.md" FT_GOV_MD="$T/gov.md" \
      FT_SO_POLL=0 FT_SO_WAIT_MAX=3 FT_SEND_VERIFIED="$F/send" FT_MBOX_SH="$F/mbox" FT_REACH_CHECK="$F/reach" \
      bash "${1:-$SO}" "$OLD" "$R" --name "$NEW" --agent claude --model 'claude-opus-5-5[1m]' --ctx 1m --effort high --body-file "$T/b.txt" > "$T/out" 2>&1
  RC=$?
}
cnt() { grep -c "^$1" "$lg"; }
# ── ⓐ 본문 머리 검사(개설 도구)
for hh in '[인계] byz-t-old-claude#1 -> byz-t-new-claude#2 (ctx 1m)' '[레디] byz-t-new-claude#2 <- byz-t-old-claude#1' '   [인계] 앞 공백'; do
  printf '%s\n골 원문 2줄\n골 원문 3줄\n본문 나머지\n열린 칸 감시: 없음\n' "$hh" > "$T/b.txt"; so_run "$SO"
  { [ "$RC" = 1 ] && grep -q '본문 첫 줄 머리' "$T/out" && [ "$(cnt tmuxc)" = 0 ] && [ "$(cnt send)" = 0 ]; } \
    && ok "ⓐ «${hh:0:14}» → REJECT rc1 · 열기·송신 0" || bad "ⓐ «${hh}»" "rc=$RC log=$(tr '\n' ' ' < "$lg") out=$(cat "$T/out")"
done
printf '[승계 발주] byz-t-old-claude#1 -> byz-t-new-claude#2\n골 원문 2줄\n골 원문 3줄\n본문 나머지\n열린 칸 감시: 없음\n' > "$T/b.txt"; so_run "$SO"
{ [ "$RC" = 0 ] && [ "$(cnt send)" = 1 ] && grep -q '\[승계 발주\]' "$T/sent.txt"; } \
  && ok "ⓑ «[승계 발주]» 머리 → 통과 · 스텁 송신 1" || bad "ⓑ" "rc=$RC log=$(tr '\n' ' ' < "$lg") out=$(cat "$T/out")"

# ── ⓒ~ⓕ 우편함 쪽: 정본 사본 + 임시 CANON/state
C="$T/env/.fable-team/comm"; Q="$C/mailbox.jsonl"; ST="$T/env/.fable-team/state"
mkdir -p "$C" "$ST" "$T/env/seats" "$ST/successor"; git -C "$T/env" init -q; : > "$Q"
cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"
printf '{"_master":"%s","%s":{"role":"master"},"%s":{"role":"master"}}\n' "$NEW" "$OLD" "$NEW" > "$T/env/seats/seats-t.json"
xe() { ( cd "$T/env" && env FT_SEATS_JSON="$T/env/seats/seats-t.json" FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$ST" FT_MBOX_RATE_N=999 \
  FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/harness/bin/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py" FT_HIL_BIN="$F/ft-hil.sh" PATH="$F:$PATH" "$@" ); }
sh_() { OUT="$(xe timeout 20 bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
py() { OUT="$(xe timeout 20 python3 "$C/mbox.py" "$@" 2>&1)"; RC=$?; }
seqof() { printf '%s\n' "$OUT" | sed -n 's/^QUEUED seq=\([0-9]*\).*/\1/p' | head -1; }
lastbody() { python3 -c 'import json,sys;print([json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()][-1]["body"])' "$C/mailbox.log.jsonl" 2>/dev/null; }
openmsg() { printf '{"successor":"%s","seq":%s,"reached_at":"t","rc":0,"model":"m"}\n' "$NEW" "$1" > "$ST/successor/$OLD.json"; }
roster1() { python3 - "$T/env/seats/seats-t.json" "$OLD" "$NEW" <<'PY'
import json,sys
p,o,n=sys.argv[1:4]; d=json.load(open(p,encoding="utf-8")); d[o]={"role":"stop-ready","_replaced_by":n}
json.dump(d,open(p,"w",encoding="utf-8"))
PY
}
setup() {  # setup — 옛 좌석 [HIL] 2통 recv → 개설 쪽지([인계] 머리·항목 없음) → 기계 [인계](항목 2) → retire → 후계 recv
  OUT="$(printf '{"seq": 1, "ts": "t", "to": "%s", "from": "%s", "body": "[HIL] q1"}\n{"seq": 2, "ts": "t", "to": "%s", "from": "%s", "body": "[HIL] q2"}\n' "$OLD" "$OLD" "$OLD" "$OLD")"
  printf '%s\n' "$OUT" >> "$Q"; sh_ recv "$OLD"
  sh_ send "$NEW" "$OLD" "[인계] $OLD -> $NEW (ctx 1m) · 19:12 개설 발주"; OSEQ="$(seqof)"
  sh_ send "$NEW" "$OLD" "[인계] $OLD -> $NEW · 항목 2 · [레디] 는 항목마다 «<id> 받음»"$'\n'"- #1 [slack-oppa] x"$'\n'"- #2 [slack-oppa] y"; HSEQ="$(seqof)"
  roster1; sh_ recv "$NEW"
}
run_ready() { sh_ ready "$NEW" "$OLD"; RB="$OUT"; RRC="$RC"; py close-check "$OLD"; CB="$OUT"; CRC="$RC"; }
setup; openmsg "$OSEQ"; run_ready
{ [ "$RRC" = 0 ] && case "$(lastbody)" in "[레디] $NEW <- $OLD · [인계] #$HSEQ 받음 · 항목 2"*) true;; *) false;; esac && [ "$CRC" = 0 ] && case "$CB" in CLOSE-OK*) true;; *) false;; esac; } \
  && ok "ⓒ 개설 쪽지 #$OSEQ = 묶음 밖 → [레디] 항목 2 · close-check CLOSE-OK" || bad "ⓒ" "ready rc=$RRC :: $RB :: close rc=$CRC :: $CB"
rm -f "$ST/successor/$OLD.json"; run_ready
{ [ "$RRC" = 3 ] && case "$RB" in *"형식 불명"*) true;; *) false;; esac; } \
  && ok "ⓓ 도달 파일 없음 = 지금 그대로(형식 불명 REJECT rc3)" || bad "ⓓ" "rc=$RRC :: $RB"
printf 'not-json\n' > "$ST/successor/$OLD.json"; run_ready
{ [ "$RRC" = 3 ] && case "$RB" in *"형식 불명"*) true;; *) false;; esac && ! grep -q Traceback <<<"$RB"; } \
  && ok "ⓔ 도달 파일 깨짐 = 넘기지 않음(rc3 · 예외 0)" || bad "ⓔ" "rc=$RRC :: $RB"
openmsg "$OSEQ"; sh_ send "$NEW" "$OLD" "[인계] $OLD -> $NEW · 손으로 쓴 꼴(항목 머리 없음)"; sh_ recv "$NEW"; run_ready
{ [ "$RRC" = 3 ] && case "$RB" in *"형식 불명"*) true;; *) false;; esac; } \
  && ok "ⓕ 손 [인계](도달 seq 와 다름) = 지금 그대로 REJECT rc3(r1116b ④)" || bad "ⓕ" "rc=$RRC :: $RB"

# ── 변이 M1·M2·M3 (사본에서만 · 원본 되돌림)
MX="$T/mx"; mkdir -p "$MX"; cp -R "$(dirname -- "$SO")/." "$MX/"
python3 - "$MX/$(basename -- "$SO")" "$T/mx-ok" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); s=p.read_text(); i=s.find('# ⓐ-2 (r1692)')
if i<0: sys.exit(1)
j=s.find('esac',i); j=s.find('\n',j); p.write_text(s[:i]+s[j+1:]); open(sys.argv[2],'w').write('ok')
PY
printf '[인계] byz-t-old-claude#1 -> byz-t-new-claude#2\n골 원문 2줄\n골 원문 3줄\n본문 나머지\n열린 칸 감시: 없음\n' > "$T/b.txt"; so_run "$MX/$(basename -- "$SO")"
{ grep -q '본문 첫 줄 머리' "$T/out"; } && bad "M1 머리 검사 삭제가 ⓐ 에 안 잡힘" "rc=$RC :: $(cat "$T/out")" || ok "M1 머리 검사 삭제 → ⓐ 의 거절 줄이 사라짐(변이 잡힘 · rc=$RC)"
python3 - "$C/mbox_handover.py" "$T/m2-ok" <<'PY'
import pathlib,sys,re
p=pathlib.Path(sys.argv[1]); s=p.read_text()
m=re.search(r'\n(\s*)and r\.get\("seq"\) != _successor_open_seq\(old\)', s)
if not m: sys.exit(1)
p.write_text(s[:m.start()]+s[m.end():]); open(sys.argv[2],'w').write('ok')
PY
rm -f "$ST/successor/$OLD.json"; openmsg "$OSEQ"; run_ready
{ [ "$RRC" = 0 ]; } && bad "M2 seq 빼기 삭제가 ⓒ 에 안 잡힘" "rc=$RRC :: $RB" || ok "M2 seq 빼기 삭제 → ⓒ FAIL 확인(rc=$RRC)"
cp "$SRC/mbox_handover.py" "$C/mbox_handover.py"
rm -f "$ST/successor/$OLD.json"; printf '\ndef _handovers(old, new):\n    return [r for r in _sent() if r.get("from") == old and r.get("to") == new\n            and _head(r.get("body")) == "[인계]" and items(r) is not None]\n' >> "$C/mbox_handover.py"
run_ready
case "$RB" in *"형식 불명"*) bad "M3 형식 불명 무조건 빼기가 ⓕ 에 안 잡힘" "rc=$RRC :: $RB";; *) ok "M3 «도달 파일 무관하게 형식 불명 빼기» → ⓕ 의 «형식 불명» 거절 사라짐(변이 잡힘 · rc=$RRC)";; esac
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
