#!/usr/bin/env bash
# test_autonomy_standing_d3_r1794.sh — r1794 «상시 승인 D3» 위험 낮은 병합(docs·ff·시험 파일만) 반례 ①~⑥b + 변이 M1~M8(사본에서만 · 원본 대조)
#   격리: 임시 BYZ 리포(명부 planner+desk·harness)·임시 팩 리포(origin = github ssh 꼴 → ssh 스텁이 로컬 bare 로) · 가짜 tmux·gh·슬랙 게시 · FT_NOW 고정
#   실 gh·실 슬랙·실 원격·실 상태 0 · GIT_* env 0 — press 0 · 기준판(origin/main bin) = ABIN=<그 판 bin> 으로 같은 시험(①②⑤ Red)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/stub" "$T/fakebin" "$T/da" "$T/pdir"
T0=1800000000; OD=1794302162.301939; PL='byz-planner-master-claude#105'; HM='byz-harness-master-claude#115'; NANO='byz-harness-nano-r1794-x#0'; DESK='byz-planner-desk-pi#134'
mkrepo "$T/byz"; B="$W"; mkdir -p "$B/.fable-team"; printf '.fable-team/\n' >> "$B/.git/info/exclude"
mkdir -p "$B/design"; printf '| 팀 | 폴더 | 상태 | 명부 |\n|---|---|---|---|\n| planner | `design/planner/` | 현역 | |\n| harness | `design/harness/` | 현역 | |\n' > "$B/design/TEAMS.md"   # r1907: 명부 이름 = TEAMS.md «명부» 칸(빈 칸 = seats-<팀>.json)
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1],"_desk":sys.argv[2]},open(sys.argv[3]+"/seats-planner.json","w"));json.dump({"_master":sys.argv[4]},open(sys.argv[3]+"/seats-harness.json","w"))' "$PL" "$DESK" "$B/.fable-team" "$HM"
SEATFILE="$T/seatname"; export SEATFILE; printf '%s' "$PL" > "$SEATFILE"
printf '#!/bin/bash\n[ "$1" = display-message ] && { cat "$SEATFILE"; exit 0; }\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$2" >> "%s"\necho "SLACK-TS 1800000000.000100"\n' "$T/slack.log" > "$T/stub/post.sh"
printf '#!/usr/bin/env bash\ncat "$REPLIES"\n' > "$T/stub/replies"
printf '{"ok":true,"messages":[{"ts":"1794302162.300000","user":"UBOT","text":"질문"},{"ts":"%s","user":"U0AC2JF0M7D","thread_ts":"1794302162.300000","text":"승인"}]}' "$OD" > "$T/replies.json"
S="$T/state"; LOG="$S/autonomy.log"
export FT_ROOT="$B" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/pdir" FT_SEAT="$PL" TMUX_PANE=%9 PATH="$T/fakebin:$PATH"
export FT_SCOPE_SLACK_POST="$T/stub/post.sh" FT_SLACK_REPLIES_CMD="$T/stub/replies" REPLIES="$T/replies.json"
mkrepo "$T/pack"; P="$W"; export PACK_ORIGIN="$ORIGIN"
HB="$P/feature-pack/fable-team/harness"; ELB="$P/feature-pack/fable-team/legacy/1.x/harness/bin"; mkdir -p "$HB/bin" "$HB/kit/fable-team/templates" "$ELB"
echo base > "$HB/bin/ft-x.sh"; echo x > "$HB/kit/fable-team/templates/.keep"; cm "$P" harness; git -C "$P" push -q origin main
git -C "$P" remote set-url origin git@github.com:fake/pack.git
printf '#!/bin/bash\nexec bash -c "$(printf %%s "${!#}" | sed -E "s|'"'"'[^'"'"']*'"'"'|'"'"'$PACK_ORIGIN'"'"'|")"\n' > "$T/stub/ssh"
printf '#!/bin/bash\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\necho "$*" >> "$STUB_LOG"\nexit 0\n' > "$T/stub/gh"
printf '#!/bin/bash\nexit 0\n' > "$T/stub/noop"; chmod +x "$T/stub"/*
export GIT_SSH_COMMAND="$T/stub/ssh" FT_HARNESS_ROOT="$HB" FT_SCOPE_PACK_TABLE="$BIN/../kit/fable-team/templates/scope-classes-pack.tsv"
export FT_GH="$T/stub/gh" FT_GH_WRITE="$T/stub/gh" STUB_JSON="$T/pr.json" STUB_LOG="$T/gh.log" FT_INSTALL_CHECK="$T/stub/noop"
git -C "$P" fetch -q origin || { echo "FAIL 팩 픽스처 fetch"; exit 1; }
a() { FT_NOW="$T0" "$BASH" "${ABIN:-$BIN}/ft-autonomy.sh" "$@"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
nlog() { grep -c . "$LOG" 2>/dev/null || true; }
fresh() { rm -rf "$S"; mkdir -p "$S"; }
as_seat() { printf '%s' "$1" > "$SEATFILE"; export FT_SEAT="$1"; }
grant() { as_seat "${GSEAT:-$PL}"; L0="$(nlog)"; run a approve-standing D3 --repos "${2:-byz,pack}" --classes "${1:-docs,ff,test}"; }
nld() { cat "$S/autonomy-standing/D3.ledger.tsv" 2>/dev/null | grep -c . || true; }
sa() { as_seat "${SA_SEAT:-$HM}"; L0="$(nlog)"; LD0="$(nld)"; run a standing-approve D3 "$1" --pr "$2" --repo "${3:-pack}"; }
rej() { [ "$rc" = 2 ] && has "$3" && has '다시: scope-approve 또는 D2' && [ ! -e "$S/autonomy-merge-approved/$2" ] && [ "$(nlog)" = "$L0" ] && [ "$(nld)" = "$LD0" ]; ck "$1" $?; }
mkpr() {  # mkpr <N> <파일…> — 팩 origin/main 에서 PR head 1커밋(파일마다 줄 1개 덧붙임 · 내용 = ADD) → refs/pull/N/head · PRSHA · STUB_JSON
  local n="$1" f; shift; git -C "$P" fetch -q origin; git -C "$P" checkout -q -B "pr$n" origin/main
  for f in "$@"; do mkdir -p "$P/$(dirname "$f")"; printf 'pr%s %s\n%s' "$n" "$RANDOM" "${ADD:-}" >> "$P/$f"; done; cm "$P" "pr $n"
  git -C "$P" push -q -f origin "pr$n:refs/pull/$n/head"; PRSHA="$(sha "$P" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":"pr"+sys.argv[2],"title":"docs r1794 PR "+sys.argv[2],"body":"카드 r1794","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$n" > "$STUB_JSON"; }
L="feature-pack/fable-team/legacy/1.x"; DOC="$L/notes-r1794.md"; TA="$L/harness/tests/test_a_r1794.sh"; TB="$L/harness/tests/lib/test_b_r1794.py"; PRF="$L/harness/bin/ft-x.sh"
bash -n "$BIN/ft-autonomy-standing-d3.sh" && bash -n "$BIN/ft-autonomy.sh" && bash -n "$BIN/ft-merge-land.sh" && bash -n "$BIN/ft-merge-lib.sh"; ck "bash -n 4종" $?

# ══ ① 켜기 — 오빠 `!` 꼴(planner master pane · D1 과 같은 좌석 판정)만 · 팀 master·나노 = 거절 · 켜짐 Slack 1글 먼저 · grants.audit
fresh; rm -f "$T/slack.log"
GSEAT="$HM" grant; [ "$rc" = 2 ] && has 'STANDING-REJECT approve-standing D3 — 호출 좌석' && [ ! -e "$S/autonomy-standing" ] && [ "$(nlog)" = "$L0" ]; ck "①0 팀 master 좌석 켜기 → 거절 · 쓰기 0(M1 근거)" $?
GSEAT="$NANO" grant; [ "$rc" = 2 ] && has '호출 좌석' && [ "$(nlog)" = "$L0" ]; ck "①0b 나노 좌석 켜기 → 거절" $?
grant code; [ "$rc" = 2 ] && has '--classes 는 docs·ff·test' && [ "$(nlog)" = "$L0" ]; ck "①0c --classes code → 거절(코드 = D2)" $?
grant; [ "$rc" = 0 ] && has '^STANDING-GRANTED D3 repos=byz,pack classes=docs,ff,test slack_ts=1800000000.000100$'; ck "①1 오빠 \`!\` 꼴 → GRANTED" $?
grep -qx "approve-standing D3 $T0 repos=byz,pack classes=docs,ff,test" "$LOG" && [ "$(grep -c '^approve-standing D3 ' "$S/autonomy-standing/grants.audit")" = 1 ] && grep -q 'slack_ts=1800000000.000100$' "$S/autonomy-standing/grants.audit"; ck "①2 log 1줄 · grants.audit 1줄(+slack_ts)" $?
[ "$(grep -c '상시 승인 D3 켜짐' "$T/slack.log")" = 1 ]; ck "①3 켜짐 Slack 가짜 1글" $?
grant; [ "$rc" = 0 ] && has '^STANDING-NOOP D3 이미 켜짐' && [ "$(nlog)" = "$L0" ]; ck "①4 두 번 켜기 = NOOP(쓰기 0)" $?

# ══ ② ff PR → 통과 · approve-merge D3 · 승인 파일 · scope 셈 그대로(자율 ON A16 + 범위 S45 살아 있음)
fresh; printf '%s\ton\tA16\n' "$T0" > "$LOG"; printf '{"mode":"on","since":%s,"event":"A16","until":null,"level":"full"}\n' "$T0" > "$S/autonomy.json"
printf 'approve-scope S45 A16 %s until=%s max=20 daily=20 classes=docs,ff,code codemax=5 repos=byz,pack\n' "$T0" "$((T0 + 3600))" >> "$LOG"
grant; SC0="$(a scope-status 2>&1)"; mkpr 11 "$DOC"; A11="$PRSHA"; sa "$A11" 11
[ "$rc" = 0 ] && has "^STANDING-OK $A11 pr=11 repo=pack class=ff by=$HM$"; ck "②1 ff PR → STANDING-OK class=ff(팀 master · DA 판정문 0)" $?
grep -qx "standing-use D3 $A11 $T0 pr=11 repo=pack class=ff" "$LOG" && grep -qx "approve-merge $A11 D3 $T0" "$LOG" && [ "$(cat "$S/autonomy-merge-approved/$A11")" = "approve-merge $A11 D3 $T0" ]; ck "②2 log standing-use D3 → approve-merge D3 · 승인 파일 같은 줄" $?
[ "$(awk -F'\t' -v a="$A11" '$2==a {print NF "|" $3 "|" $4}' "$S/autonomy-standing/D3.ledger.tsv")" = "7|11|class=ff" ]; ck "②3 D3 원장 1행(7칸)" $?
! grep -q '^scope-use ' "$LOG" && [ "$(a scope-status 2>&1)" = "$SC0" ]; ck "②4 scope-use 0 · scope-status(used·today·code) 그대로(M2 근거)" $?
[ "$(a mode)" = on ]; ck "②5 D3 줄이 든 log → 위변조 0(mode=on)" $?
L0="$(nlog)"; sa "$A11" 11; [ "$rc" = 0 ] && has "^STANDING-NOOP $A11" && [ "$(nlog)" = "$L0" ]; ck "②6 같은 head 두 번 = NOOP" $?

# ══ ③ 시험 파일만 → class=test · 시험+제품 bin → 거절 · docs+시험 → 거절
fresh; grant; mkpr 21 "$TA" "$TB"; A21="$PRSHA"; sa "$A21" 21
[ "$rc" = 0 ] && has "^STANDING-OK $A21 pr=21 repo=pack class=test "; ck "③1 tests/ 아래 2파일 → class=test 통과" $?
fresh; grant; mkpr 22 "$TA" "$PRF"; A22="$PRSHA"; sa "$A22" 22; rej "③2 시험 1 + 제품 bin 1 → 거절(M3 근거)" "$A22" '전부 시험 파일은 아님'
mkpr 23 "$DOC" "$TA"; A23="$PRSHA"; sa "$A23" 23; rej "③3 docs + 시험 → 거절" "$A23" '전부 시험 파일은 아님'

# ══ ④ 종류 범위 · FORBID · CRITICAL · repo 범위
fresh; grant ff,test; git -C "$P" fetch -q origin; git -C "$P" checkout -q -B mv origin/main; echo m >> "$P/b.txt"; cm "$P" mv; git -C "$P" push -q origin mv:main
mkpr 31 "$DOC"; A31="$PRSHA"; git -C "$P" checkout -q -B mv2 origin/main; echo n >> "$P/a.txt"; cm "$P" mv2; git -C "$P" push -q origin mv2:main; git -C "$P" fetch -q origin
sa "$A31" 31; rej "④1 docs(ff 아님) PR · classes=ff,test → 거절" "$A31" '② 종류 docs 는 상시 승인 범위'
fresh; grant; mkpr 32 "feature-pack/fable-team/ft2/contracts/x.md"; A32="$PRSHA"; sa "$A32" 32; rej "④2 FORBID 종류 → 거절" "$A32" '② 분류기 거절'
ADD='git push -f origin main' mkpr 33 "$TA"; A33="$PRSHA"; sa "$A33" 33; rej "④3 CRITICAL(destroy · 시험 파일 안) → 거절(M4 근거)" "$A33" '③ 크리티컬: destroy'
fresh; grant docs,ff,test byz; mkpr 34 "$DOC"; A34="$PRSHA"; sa "$A34" 34 pack; rej "④4 --repo pack · repos=byz → 거절" "$A34" '② 저장소 pack 은 승인 범위'

# ══ ⑤ ② 승인 줄로 ft-merge-land 착지 → 위변조 0 · D3 원장 착지 sha · Slack 1줄
fresh; grant; mkpr 41 "$DOC"; A41="$PRSHA"; sa "$A41" 41; rm -f "$T/slack.log"
out="$(cd "$B" && bash "${ABIN:-$BIN}/ft-merge-land.sh" 41 --approve-sha "$A41" --repo "$P" 2>&1)"; rc=$?; Q41="${out#*sha=}"; Q41="${Q41%% *}"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(git -C "$PACK_ORIGIN" rev-parse refs/heads/main)" = "$Q41" ]; ck "⑤1 D3 승인 줄로 착지 LANDED(M5 근거)" $?
[ "$(awk -F'\t' -v a="$A41" '$2==a {print $6 "|" $7}' "$S/autonomy-standing/D3.ledger.tsv")" = "$Q41|git revert --no-edit $Q41" ]; ck "⑤2 D3 원장 착지 sha·되돌림 칸" $?
[ "$(grep -c "병합함: PR #41 · 카드 r1794 · 상시 승인 D3(위험 낮은 병합) · 되돌림: git revert --no-edit $Q41" "$T/slack.log")" = 1 ]; ck "⑤3 병합 뒤 Slack 1줄(D3 표기)" $?

# ══ ⑥ 정상 모드 → D3 켜기 → use → approve-merge → standing-stop D3 log 에서 위변조 0 · 다음 D3 거절 · D2 길 보존
fresh; printf '%s\ton\tA16\n' "$T0" > "$LOG"; printf '{"mode":"on","since":%s,"event":"A16","until":null,"level":"full"}\n' "$T0" > "$S/autonomy.json"
grant; mkpr 51 "$DOC"; A51="$PRSHA"; sa "$A51" 51; run a standing-stop D3 "시험 멈춤"
[ "$rc" = 0 ] && grep -qx "standing-stop D3 $T0 시험 멈춤" "$LOG" && [ "$(a mode)" = on ] && a status | grep -q '^\[자율 ON A16'; ck "⑥1 stop 까지 든 log → log_last_mode rc0 · 위변조 0(M7 근거)" $?
mkpr 52 "$DOC"; A52="$PRSHA"; sa "$A52" 52; rej "⑥2 stop 뒤 standing-approve D3 → 거절(M6 근거)" "$A52" '① 상시 승인 D3 꺼짐'
mkda() { DAO="$T/da/$1.out"; printf 'codex\n판정: APPROVE\n\n근거\n\n판정: APPROVE\n' > "$DAO"; printf 'head=%s model=gpt-6.1-sol effort=high rc=0 start=1 end=2\n' "$2" > "$DAO.meta"; }
mkv() { VF="$B/design/harness/da/VERDICT-$1.md"; mkdir -p "$(dirname "$VF")"
  printf '# 판정\n\n- 승인 sha: %s\n- DA 원문: %s\n- DA 원문 sha256: %s\n- 격리: 세트 %s · rc=0\n' "$2" "$DAO" "$(shasum -a 256 "$DAO" | awk '{print $1}')" "$2" > "$VF"
  git -C "$B" checkout -q main; cm "$B" "verdict $1" && git -C "$B" push -q origin main main:refs/heads/docs/da-278062 && git -C "$B" fetch -q origin; }
. "$HERE/lib/card_ref_fixture.sh"; CARD="$(fx_card_path "$B" card.md)"
as_seat "$PL"; run a approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD"; mkpr 53 "$PRF"; A53="$PRSHA"; mkda d53 "$A53"; mkv d53 "$A53"
printf '# 카드\n\n## 상태\n- 세트: %s · 시험: bash tests/x.sh rc=0 · 이슈: 0\n' "$A53" > "$CARD"; fx_card_pub "$B" "$CARD"
as_seat "$HM"; run a standing-approve D2 "$A53" --pr 53 --repo pack --verdict "$VF" --card "$CARD"
[ "$rc" = 0 ] && has "^STANDING-OK $A53 pr=53 repo=pack da=$A53 " && [ "$(a mode)" = on ]; ck "⑥3 같은 log 에서 D2 standing-approve 통과(D2 보존)" $?

# ══ ⑥b 좌석 — desk(자율 ON·full) → 거절 · 쓰기 0 / 같은 조건 팀 master → 통과
fresh; printf '%s\ton\tA16\n' "$T0" > "$LOG"; printf '{"mode":"on","since":%s,"event":"A16","until":null,"level":"full"}\n' "$T0" > "$S/autonomy.json"
grant; mkpr 61 "$DOC"; A61="$PRSHA"; SA_SEAT="$DESK" sa "$A61" 61; rej "⑥b1 desk 좌석(자율 ON·full) → 거절 · 쓰기 0(M8 근거)" "$A61" 'ⓑ 팀 master 좌석만'
sa "$A61" 61; [ "$rc" = 0 ] && has "^STANDING-OK $A61 "; ck "⑥b2 같은 조건 팀 master → 통과" $?

# ══ 변이 M1~M8 — 사본에서만 · 변이마다 원본으로 같은 사례 1회 더(원본 = 위 칸) · 변이 판에서 빨강이어야 할 칸이 통과하면 그 칸이 검사를 잡는다
mut() {  # mut <이름> <파일> <원문> <바꿀 글> → $T/mut-<이름>/
  local mb="$T/mut-$1"; mkdir -p "$mb"; for f in "$BIN"/*; do ln -s "$f" "$mb/$(basename "$f")"; done; rm -f "$mb/$2"
  python3 - "$BIN/$2" "$mb/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1, sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
}
D3F=ft-autonomy-standing-d3.sh; AU=ft-autonomy.sh
mut m1 "$D3F" '  std_seat_probe || {' '  true || {'; fresh; GSEAT="$HM" ABIN="$T/mut-m1" grant
[ "$rc" = 0 ] && has 'STANDING-GRANTED D3'; ck "M1 켜기 좌석 판정 뺌 → ①0 칸이 켜진다(빨강)" $?
mut m2 "$D3F" '  printf '"'"'%s\n'"'"' "$line" >> "$LOG" || std_wfail log
  { printf' '  printf '"'"'scope-use S45 %s ff %s\n'"'"' "$1" "$now" >> "$LOG"; printf '"'"'%s\n'"'"' "$line" >> "$LOG" || std_wfail log
  { printf'
fresh; printf '%s\ton\tA16\n' "$T0" > "$LOG"; printf '{"mode":"on","since":%s,"event":"A16","until":null,"level":"full"}\n' "$T0" > "$S/autonomy.json"
printf 'approve-scope S45 A16 %s until=%s max=20 daily=20 classes=docs,ff,code codemax=5 repos=byz,pack\n' "$T0" "$((T0 + 3600))" >> "$LOG"
grant; SC0="$(a scope-status 2>&1)"; ABIN="$T/mut-m2" sa "$A11" 11
[ "$rc" = 0 ] && { grep -q '^scope-use ' "$LOG" || [ "$(a scope-status 2>&1)" != "$SC0" ]; }; ck "M2 standing-use 뒤 scope-use 도 씀 → ②4 칸이 빨강" $?
mut m3 "$D3F" 'd3_is_test "$p" || return 1; done <<<"$OUT"
  [ "$n" -gt 0 ]' 'd3_is_test "$p" && return 0; done <<<"$OUT"
  return 1'; fresh; grant; ABIN="$T/mut-m3" sa "$A22" 22
[ "$rc" = 0 ] && has '^STANDING-OK'; ck "M3 «전부 시험» → «하나라도 시험» → ③2 칸이 통과(빨강)" $?
mut m4 "$D3F" 'd3_classify "$head"; d3_critical "$head"' 'd3_classify "$head"'; fresh; grant; ABIN="$T/mut-m4" sa "$A33" 33
[ "$rc" = 0 ] && has '^STANDING-OK'; ck "M4 --critical 생략 → ④3 칸이 통과(빨강)" $?
mut m5 "$AU" '(A[0-9]+|OFF|D1|D2|D3) [0-9]+$' '(A[0-9]+|OFF|D1|D2) [0-9]+$'; fresh; printf '%s\ton\tA16\n' "$T0" > "$LOG"; printf '{"mode":"on","since":%s,"event":"A16","until":null}\n' "$T0" > "$S/autonomy.json"
grant; mkpr 71 "$DOC"; A71="$PRSHA"; sa "$A71" 71; [ "$(ABIN="$T/mut-m5" a mode)" = tamper ] && [ "$(a mode)" = on ]; ck "M5 APPROVE_RE 에 D3 안 더함 → 같은 log 가 위변조(원본 on · 빨강)" $?
mut m6 "$D3F" '  d3_on || std_err "① 상시 승인 D3 꺼짐' '  d3_on; [ -n "${D3_REPOS:-}" ] || std_err "① 상시 승인 D3 꺼짐'
fresh; grant; run a standing-stop D3 "멈춤"; ABIN="$T/mut-m6" sa "$A71" 71
[ "$rc" = 0 ] && has '^STANDING-OK'; ck "M6 stop 무시 → ⑥2 칸이 통과(빨강)" $?
mut m7 "$AU" "^standing-stop (D1|D2|D3) [0-9]+" "^standing-stop (D1|D2) [0-9]+"; fresh; printf '%s\ton\tA16\n' "$T0" > "$LOG"; printf '{"mode":"on","since":%s,"event":"A16","until":null}\n' "$T0" > "$S/autonomy.json"; grant; run a standing-stop D3 "멈춤"
[ "$(ABIN="$T/mut-m7" a mode)" = tamper ] && [ "$(a mode)" = on ]; ck "M7 STANDING_STOP_RE 에 D3 안 더함 → ⑥1 log_last_mode rc1(위변조 · 빨강)" $?
mut m8 "$D3F" '  d3_seat
' '  d2_seat; D3_BY="$D2_BY"
'; fresh; printf '%s\ton\tA16\n' "$T0" > "$LOG"; printf '{"mode":"on","since":%s,"event":"A16","until":null,"level":"full"}\n' "$T0" > "$S/autonomy.json"
grant; SA_SEAT="$DESK" ABIN="$T/mut-m8" sa "$A61" 61
[ "$rc" = 0 ] && has "^STANDING-OK $A61 .*by=$DESK"; ck "M8 D3 좌석을 d2_seat 그대로 → ⑥b1 칸이 desk 로 통과(빨강)" $?

# ══ 키트 사본 · 크기
for f in ft-autonomy.sh "$D3F" ft-merge-land.sh ft-merge-lib.sh; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f"; ck "키트 사본 cmp0 $f" $?; done
[ "$(wc -l < "$BIN/ft-autonomy.sh")" -le 200 ] && [ "$(wc -l < "$BIN/$D3F")" -le 150 ] && [ "$(wc -l < "$BIN/ft-merge-land.sh")" -le 120 ]; ck "줄 수 상한(autonomy 200 · d3 150 · merge-land 120)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
