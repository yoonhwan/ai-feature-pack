#!/usr/bin/env bash
# test_autonomy_card_delete_d2_r1778.sh — r1778 ⑧ standing-approve D2 길: 카드 대상 안 삭제 PR 통과 · 대상 밖 거절 · 변이 M3(--card 전달 삭제)
#   격리: 임시 BYZ 리포(명부)·임시 팩 리포(origin = ssh 스텁 → 로컬 bare)·가짜 tmux·gh·슬랙 · 실 상태 0 · press 0(나노는 쏘지 않는다)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/stub" "$T/fakebin" "$T/da" "$T/pdir"
T0=1800000000; OD=1794302162.301939; PL='byz-planner-master-claude#105'; HM='byz-harness-master-claude#115'
# ── BYZ 리포 = 명부 루트 · 판정문 리포 · 실제 좌석 = 가짜 tmux 세션명
mkrepo "$T/byz"; B="$W"; mkdir -p "$B/.fable-team"; printf '.fable-team/\n' >> "$B/.git/info/exclude"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$PL" "$B/.fable-team/seats-planner.json"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$HM" "$B/.fable-team/seats-harness.json"
SEATFILE="$T/seatname"; export SEATFILE; printf '%s' "$PL" > "$SEATFILE"
printf '#!/bin/bash\n[ "$1" = display-message ] && { cat "$SEATFILE"; exit 0; }\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$2" >> "%s"\necho "SLACK-TS 1800000000.000100"\n' "$T/slack.log" > "$T/stub/post.sh"
printf '#!/usr/bin/env bash\ncat "$REPLIES"\n' > "$T/stub/replies"; chmod +x "$T/stub/"*
printf '{"ok":true,"messages":[{"ts":"1794302162.300000","user":"UBOT","text":"질문"},{"ts":"%s","user":"U0AC2JF0M7D","thread_ts":"1794302162.300000","text":"승인"}]}' "$OD" > "$T/replies.json"
S="$T/state"; LOG="$S/autonomy.log"
export FT_ROOT="$B" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/pdir" FT_SEAT="$PL" TMUX_PANE=%9 PATH="$T/fakebin:$PATH"
export FT_SCOPE_SLACK_POST="$T/stub/post.sh" FT_SLACK_REPLIES_CMD="$T/stub/replies" REPLIES="$T/replies.json"
# ── 팩 리포(하네스 루트 = <리포>/feature-pack/fable-team/harness) · origin = git@github.com:fake/pack.git(ssh 스텁 → 로컬 bare)
mkrepo "$T/pack"; P="$W"; export PACK_ORIGIN="$ORIGIN"
HB="$P/feature-pack/fable-team/harness"; EV="$P/feature-pack/fable-team/legacy/1.x/harness/evidence/r1"
mkdir -p "$HB/bin" "$HB/kit/fable-team/templates" "$EV"; echo keep > "$EV/a.md"; echo keep > "$EV/b.md"
cm "$P" harness; git -C "$P" push -q origin main; git -C "$P" remote set-url origin git@github.com:fake/pack.git
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
grant() { as_seat "$PL"; run a approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD"; }
mkdel() {  # mkdel <N> <지울 경로> — 팩 origin/main 에서 PR head 1커밋(파일 삭제) → PRSHA · STUB_JSON · PRF
  git -C "$P" fetch -q origin; git -C "$P" checkout -q -B "pr$1" origin/main
  rm -f "$P/$2"; cm "$P" "pr $1"; git -C "$P" push -q -f origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$P" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":"pr"+sys.argv[2],"title":"del "+sys.argv[3],"body":"카드 r1778","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" "$2" > "$STUB_JSON"
  git -C "$P" checkout -q main; }
mkda() { DAO="$T/da/$1.out"; printf 'codex\n판정: %s\n\n근거\n\n판정: %s\n' "$2" "$2" > "$DAO"; printf 'head=%s model=gpt-6.1-sol effort=high rc=0 start=1 end=2\n' "$3" > "$DAO.meta"; }
sum256() { shasum -a 256 "$1" | awk '{print $1}'; }
mkv() {  # mkv <이름> <A> <원문> — DA 판정 가지(refs/heads/docs/da-278062)에 판정문 커밋
  VF="$B/design/harness/da/VERDICT-$1.md"; mkdir -p "$(dirname "$VF")"
  printf '# 판정 %s\n\n- 승인 sha: %s\n- DA 원문: %s\n- DA 원문 sha256: %s\n- 격리: 세트 %s · rc=0\n' "$1" "$2" "$3" "$(sum256 "$3")" "$2" > "$VF"
  git -C "$B" checkout -q main; cm "$B" "verdict $1" && git -C "$B" push -q origin main && git -C "$B" push -q origin main:refs/heads/docs/da-278062 && git -C "$B" fetch -q origin; }
cardw() { CARD="$T/card.md"; printf '# 카드\n\n- 대상: `%s`\n\n## 구현 범위\n\n- `%s`\n\n## 상태\n- 2026\n' "$1" "$1" > "$CARD"; }
sa() { as_seat "$HM"; L0="$(nlog)"; run a standing-approve D2 "$1" --pr "$2" --repo pack --verdict "$3" --card "$CARD"; }
rej() { local sh="$2"; [ "$rc" = 2 ] && has "$3" && { [ -z "$sh" ] || [ ! -e "$S/autonomy-merge-approved/$sh" ]; }; ck "$1" $?; }

bash -n "$BIN/ft-autonomy-standing-d2.sh"; ck "bash -n d2" $?
python3 -c "import ast;ast.parse(open('$BIN/autonomy_scope_rules.py').read());ast.parse(open('$BIN/autonomy_scope_classify.py').read())"; ck "python ast 2종" $?
IN_SCOPE="feature-pack/fable-team/legacy/1.x/harness/evidence/r1/a.md"; OUT_SCOPE="feature-pack/fable-team/legacy/1.x/harness/evidence/r1/b.md"

# ══ ⑧ 대상 안 삭제 → ② 분류 통과(docs) → STANDING-OK · 대상 밖 삭제 → ② 거절
fresh; grant; [ "$rc" = 0 ]; ck "D2 켜기(planner master)" $?
mkdel 61 "$IN_SCOPE"; A61="$PRSHA"; mkda ok61 APPROVE "$A61"; mkv ok61 "$A61" "$DAO"; V61="$VF"
cardw "$P/$IN_SCOPE"; sa "$A61" 61 "$V61"
[ "$rc" = 0 ] && has "^STANDING-OK $A61 pr=61 repo=pack da=$A61 "; ck "⑧1 카드 대상 안 파일 삭제 PR(절대 경로 카드) → STANDING-OK" $?
grep -qx "standing-use D2 $A61 $T0 pr=61 repo=pack da=$A61" "$LOG" && [ -e "$S/autonomy-merge-approved/$A61" ]; ck "⑧2 승인 기록·승인 파일 있음" $?
mkdel 62 "$OUT_SCOPE"; A62="$PRSHA"; mkda ok62 APPROVE "$A62"; mkv ok62 "$A62" "$DAO"
cardw "$P/$IN_SCOPE"; L0="$(nlog)"; sa "$A62" 62 "$VF"
rej "⑧3 카드 대상 밖 파일 삭제 PR → ② 거절(kind=delete · 쓰기 0)" "$A62" '② 분류기 거절 rc=3: FORBID kind=delete'
fresh; grant; cardw "$T/없는카드.md"; sa "$A61" 61 "$V61"
rej "⑧4 카드 파일이 없음 → ② 거절(닫힌 쪽)" "$A61" '② 분류기 거절 rc=3: FORBID kind=delete'

# ══ 변이 M3 — d2_classify 의 --card 전달을 지우면 ⑧1 이 «거절» 로 뒤집힌다(그 칸이 전달을 실제로 잡는다)
mb="$T/mut-m3"; mkdir -p "$mb"; for f in "$BIN"/*; do ln -s "$f" "$mb/$(basename "$f")"; done; rm -f "$mb/ft-autonomy-standing-d2.sh"
python3 - "$BIN/ft-autonomy-standing-d2.sh" "$mb/ft-autonomy-standing-d2.sh" '[ -z "${D2_CARD:-}" ] || a+=(--card "$D2_CARD")' ':' <<'PY' || { echo "FAIL 변이 M3 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1, sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
fresh; as_seat "$PL"; FT_NOW="$T0" "$BASH" "$mb/ft-autonomy.sh" approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD" >/dev/null 2>&1; ck "변이 판 D2 켜기" $?
cardw "$P/$IN_SCOPE"; as_seat "$HM"
out="$(FT_NOW="$T0" "$BASH" "$mb/ft-autonomy.sh" standing-approve D2 "$A61" --pr 61 --repo pack --verdict "$V61" --card "$CARD" 2>&1)"; rc=$?
[ "$rc" = 2 ] && has '② 분류기 거절 rc=3: FORBID kind=delete'; ck "M3 --card 전달 삭제 → ⑧1 칸이 거절로 뒤집힌다(빨강)" $?
as_seat "$HM"; out="$(FT_NOW="$T0" "$BASH" "$BIN/ft-autonomy.sh" standing-approve D2 "$A62" --pr 62 --repo pack --verdict "$VF" --card "$CARD" 2>&1)"; rc=$?
[ "$rc" = 2 ]; ck "M3 뒤 같은 상태 판(정상)에서도 대상 안·밖 구분은 유지" $?

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
