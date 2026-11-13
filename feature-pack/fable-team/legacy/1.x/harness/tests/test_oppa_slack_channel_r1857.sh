#!/usr/bin/env bash
# test_oppa_slack_channel_r1857.sh — 끝: --oppa-slack <채널>:<ts> 면 그 채널에서 오빠 답글을 읽고, 채널 없는 옛 꼴은 byz-desk 그대로 (카드 r1857-oppa-slack-channel)
#   반례 ①~⑤ + 변이 M1~M3 · 기준판 Red(① 둘 다 rc2) · 격리: 임시 폴더 · 가짜 replies(FT_SLACK_CHANNEL·FT_SLACK_TS 로 응답) · 가짜 mbox · 실 Slack 0 · sleep 0 · timeout 70
set -uo pipefail
TO=70; HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; fail=0; mkdir -p "$T/root/.fable-team/state" "$T/hil" "$T/fake"
ck() { if [ "$2" = 0 ]; then echo "  OK   $1"; else echo "  FAIL $1"; fail=1; fi; }
X=C0CGUDJ9NTS; DESK=C0C9GRFHJE5; P=1794558197.484359; R=1794536251.464119; A=1794558973.827969; SHA=b9338cce840fbf7628dbd343d1ece638e865e8ac
OPPA=U0AC2JF0M7D; export RJ="$T/replies.json" WANT="$X" CALLS="$T/calls.log" SENT="$T/sent.tsv"
mk() { printf '{"ok":true,"messages":[{"ts":"%s","user":"UBOT","text":"루트"},{"ts":"%s","thread_ts":"%s","user":"UBOT","text":"승인 요청 %s"},{"ts":"%s","thread_ts":"%s","user":"%s","text":"네"}]}' "$R" "$P" "$R" "$SHA" "$A" "$R" "$1" > "$RJ"; }
cat > "$T/fake/replies.sh" <<'SH'
#!/usr/bin/env bash
printf '%s:%s\n' "${FT_SLACK_CHANNEL:-}" "${FT_SLACK_TS:-}" >> "$CALLS"
[ "${FT_SLACK_CHANNEL:-}" = "$WANT" ] && { cat "$RJ"; exit 0; }
echo '{"ok":false,"error":"thread_not_found"}'
SH
printf '#!/usr/bin/env bash\nprintf "%%s\\t%%s\\n" "$2" "$4" >> "$SENT"\n' > "$T/fake/mbox.sh"
export FT_SLACK_REPLIES_CMD="bash $T/fake/replies.sh"; unset FT_SCOPE_SLACK_CHANNEL
run() { out="$(timeout $TO python3 "$@" 2>&1)"; rc=$?; }

c1() {  # ① 채널 X 에만 있는 질문 — X:<ts> = SLACK-OK · <ts> 만 = REJECT
  mk "$OPPA"; run "$1/ft_oppa_slack_check.py" "$X:$P" "$SHA"; [ $rc = 0 ] && grep -q "^SLACK-OK $SHA parent=$P reply=$A$" <<<"$out" || return 1
  run "$1/ft_oppa_slack_check.py" "$P" "$SHA"; [ $rc = 2 ] && grep -q '^REJECT' <<<"$out"; }
c2() { mk UNOTOPPA; run "$1/ft_oppa_slack_check.py" "$X:$P" "$SHA"; [ $rc = 2 ] && grep -q '^REJECT' <<<"$out" && ! grep -q SLACK-OK <<<"$out"; }
c3() {  # ③ 계획 → plan_judge 통과 · register-plan 채널 저장 · scan 이 X:<ts> 로 넘김
  local L="$T/led-$RANDOM.jsonl" plan="$T/plan.sh"; : > "$L"; : > "$SENT"; mk "$OPPA"
  printf 'bash ft-autonomy.sh approve-merge %s --oppa-slack %s:%s\n' "$SHA" "$X" "$P" > "$plan"
  FT_SCOPE_STATUS_CMD="echo '[범위 승인 S3 · 살아 있음]'" run "$1/ft_scope_plan_judge.py" --plan "$plan"; [ $rc = 0 ] && [ "$out" = ok ] || return 1
  export FT_ROOT="$T/root" FT_DESK_REPLY_LEDGER="$L" FT_NOW=1794559000 HIL_DIR="$T/hil" FT_MBOX_SH="$T/fake/mbox.sh" FT_SEATS_PLANNER="$T/seats.json"
  printf '{"_desk":"byz-planner-desk-pi#1","_master":"byz-planner-master-pi#2"}' > "$FT_SEATS_PLANNER"
  run "$1/ft_desk_reply_wake.py" --register-plan "$plan" h9; [ $rc = 0 ] && [ "$(wc -l < "$L" | tr -d ' ')" = 1 ] && grep -q "\"channel\": *\"$X\"" "$L" || return 1
  : > "$CALLS"; run "$1/ft_desk_reply_wake.py"; [ $rc = 0 ] && grep -q "^$X:" "$CALLS" && grep -q "\[오빠 답글\] h9 ts=$A" "$SENT"; }
c4() {  # ④ 꼴 틀림 = oppa_parse·검사기 모두 rc2 usage
  local v; for v in "x:$P" "C1:$P" "C1:" ":$P" "$X:$X:$P"; do
    ( . "$1/ft-autonomy-oppa.sh"; oppa_parse --oppa-slack "$v" "$SHA" ) 2>/dev/null; [ $? = 2 ] || { echo "    oppa_parse 통과: $v"; return 1; }
    run "$1/ft_oppa_slack_check.py" "$v" "$SHA"; [ $rc = 2 ] && grep -q usage <<<"$out" || { echo "    검사기 usage 아님: $v rc=$rc"; return 1; }; done
  ( . "$1/ft-autonomy-oppa.sh"; oppa_parse --oppa-slack "$X:$P" "$SHA"; [ "$OPPA" = "$X:$P" ] ); }
c5() {  # ⑤ 옛 꼴 = byz-desk(env 없으면) · env 채널이면 그 채널 · 장부 옛 줄(채널 칸 없음) = <ts> 로 넘김
  mk "$OPPA"; WANT=$DESK run "$1/ft_oppa_slack_check.py" "$P" "$SHA"; [ $rc = 0 ] && grep -q "^SLACK-OK $SHA parent=$P reply=$A$" <<<"$out" || return 1
  FT_SCOPE_SLACK_CHANNEL=$X run "$1/ft_oppa_slack_check.py" "$P" "$SHA"; [ $rc = 0 ] || return 1
  local L="$T/led-old.jsonl"; printf '{"q_ts":"%s","h":"h8","sha":"%s","at":1,"deadline":1894559000,"state":"open"}\n' "$P" "$SHA" > "$L"; : > "$CALLS"; : > "$SENT"
  WANT=$DESK FT_DESK_REPLY_LEDGER="$L" run "$1/ft_desk_reply_wake.py"; [ $rc = 0 ] && grep -q "^$DESK:" "$CALLS" && grep -q '\[오빠 답글\] h8' "$SENT"; }

echo "== 기준판 Red (origin/main 83b067e8) =="
mkdir -p "$T/base"; git -C "$HERE" show 83b067e8da87bb548c0b836d5cdb606b0ff07df9:feature-pack/fable-team/legacy/1.x/harness/bin/ft_oppa_slack_check.py > "$T/base/ft_oppa_slack_check.py"
mk "$OPPA"; run "$T/base/ft_oppa_slack_check.py" "$X:$P" "$SHA"; a=$rc; run "$T/base/ft_oppa_slack_check.py" "$P" "$SHA"
[ $a = 2 ] && [ $rc = 2 ]; ck "기준판 ① X:<ts> rc=$a · <ts> rc=$rc (둘 다 rc2 = Red)" $?
echo "== 반례 =="
c1 "$BIN"; ck "① 채널 X 질문: X:<ts> SLACK-OK rc0 · <ts> 만 REJECT rc2" $?
c2 "$BIN"; ck "② 채널 X 답글 작성자 ≠ 오빠 → X:<ts> 도 REJECT rc2" $?
c3 "$BIN"; ck "③ plan_judge 통과 · register-plan 1줄(채널 저장) · scan 이 X:<ts> 로 넘김" $?
c4 "$BIN"; ck "④ 꼴 틀림(x: · C1: · :ts · 채널 2개) oppa_parse·검사기 rc2" $?
c5 "$BIN"; ck "⑤ 옛 꼴 = byz-desk · env 채널 · 장부 옛 줄 그대로" $?
echo "== 변이 (FAIL 이어야 한다) =="
mut() { local d="$T/$1"; mkdir -p "$d"; cp "$BIN"/{ft_oppa_slack_check.py,ft-autonomy-oppa.sh,ft_scope_plan_judge.py,ft_traffic_plan_judge.py,ft_desk_reply_wake.py,ft_desk_reply_thread.py} "$d/"; python3 - "$d/$2" "$3" "$4" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8"); assert sys.argv[2] in t, "변이 자리 없음"
p.write_text(t.replace(sys.argv[2], sys.argv[3]), encoding="utf-8")
PY
  [ $? = 0 ] || { echo "  FAIL $1 변이 자리 없음"; fail=1; return; }
  if "$5" "$d" >/dev/null 2>&1; then echo "  FAIL $1 살아남음"; fail=1; else echo "  OK   $1 → ${5} FAIL"; fi; }
mut M1 ft_oppa_slack_check.py 'CHANNEL or os.environ' 'os.environ' c1
mut M2 ft_oppa_slack_check.py '(C[A-Z0-9]{8,12})' '([^:]*)' c4
mut M3 ft_desk_reply_wake.py '**({"channel": chan} if chan else {})' '' c3
echo "== bin = kit =="
for f in ft_oppa_slack_check.py ft-autonomy-oppa.sh ft_scope_plan_judge.py ft_desk_reply_wake.py; do cmp -s "$BIN/$f" "$HERE/../kit/fable-team/bin/$f" || { echo "  FAIL kit 다름 $f"; fail=1; }; done
[ $fail = 0 ] && echo "PASS test_oppa_slack_channel_r1857" || echo "FAIL test_oppa_slack_channel_r1857"
exit $fail
