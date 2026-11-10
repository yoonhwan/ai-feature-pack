#!/usr/bin/env bash
# test_hil_route_team.sh — r578: ft-hil-ask.sh 의 명부 = «보내는 좌석의 팀 명부» (mbox_guard tfile 규칙)
# 임시 루트(git init)·가짜 명부 3벌·가짜 mbox 만 쓴다 — 실제 우편함·실 명부·실 좌석은 건드리지 않는다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
ASK="${FT_HIL_ASK_BIN:-$SRC/ft-hil-ask.sh}"   # FT_HIL_ASK_BIN = base 사본으로 «전 FAIL» 대조할 때만
LINT="$SRC/ft-seats-lint.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:250}";; esac; }
not() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:250}";; *) ok "$3";; esac; }

bash -n "$SRC/ft-hil-ask.sh" && ok "bash -n ft-hil-ask.sh" || bad "bash -n ft-hil-ask.sh"
cmp -s "$SRC/ft-hil-ask.sh" "$HERE/../../harness/bin/ft-hil-ask.sh" && ok "킷 두 벌 cmp 동일" || bad "킷 두 벌이 다르다"

R="$T/root"; mkdir -p "$R/.fable-team"
git -C "$R" init -q 2>/dev/null || bad "임시 루트 git init"
printf '#!/usr/bin/env bash\necho "to=$2 from=$3" >> "%s/routes.log"\necho "QUEUED seq=555 to=$1 pending=1 doorbell=absent"\n' "$T" > "$T/mbox.sh"
printf '#!/usr/bin/env bash\ncat "%s/alive"\n' "$T" > "$T/tmux.sh"
: > "$T/alive"
row='"_version":"t"'
printf '{%s,"_master":"byz-planner-master-claude#86","_hil_route":"byz-planner-master-claude#86","byz-planner-master-claude#86":{"role":"master","agent":"claude"},"byz-planner-desk-claude#5":{"role":"master","agent":"claude"}}\n' "$row" > "$R/.fable-team/seats-planner.json"
printf '{%s,"_master":"byz-harness-master-claude#87","_hil_route":"byz-planner-master-claude#86","byz-harness-master-claude#87":{"role":"master","agent":"claude"}}\n' "$row" > "$R/.fable-team/seats-harness.json"
printf '{%s,"_master":"byz-ops-master-claude#1","_hil_route":"byz-planner-desk-claude#5","byz-ops-master-claude#1":{"role":"master","agent":"claude"}}\n' "$row" > "$R/.fable-team/seats-ops.json"
printf '{%s,"_master":"byz-feature-master-claude#2","_hil_route":"byz-planner-master-claude#86","byz-feature-master-claude#2":{"role":"master","agent":"claude"}}\n' "$row" > "$R/.fable-team/seats-feature.json"
printf '{%s,"_master":"byz-cfo-master-codex#1","byz-cfo-master-codex#1":{"role":"master","agent":"codex"}}\n' "$row" > "$R/.fable-team/seats-cfo.json"

# ask <좌석> [env ...] — FT_ROOT=임시 루트 · FT_ME=좌석 · 가짜 mbox · 원장 임시
ask() { local seat="$1"; shift; env -u FT_SEATS -u FT_HIL_ROUTE -u FT_SEND_DRY HOME="$T" PYTHONDONTWRITEBYTECODE=1 \
  FT_ROOT="$R" HIL_LEDGER="$T/HIL-LEDGER.md" FT_MBOX_CMD="$T/mbox.sh" FT_ME="$seat" ${@+"$@"} \
  bash "$ASK" "질문 $seat" 2>&1; }
last_route() { sed -n '$s/^to=\([^ ]*\).*/\1/p' "$T/routes.log" 2>/dev/null; }
nroute() { [ -f "$T/routes.log" ] && wc -l < "$T/routes.log" | tr -d ' ' || echo 0; }

echo "== ⓐ ops 좌석 · ops 명부 _hil_route=desk · 하네스 명부=planner → desk (고치기 전 = planner FAIL)"
out="$(ask byz-ops-master-claude#1)"; rc=$?
[ $rc -eq 0 ] && ok "ⓐ ask rc=0" || bad "ⓐ rc=$rc $out"
[ "$(last_route)" = "byz-planner-desk-claude#5" ] && ok "ⓐ 수신 = ops 명부의 desk(팀 명부 우선)" || bad "ⓐ 수신 = $(last_route) (하네스 명부 planner 로 갔나)"
has "$out" "route=byz-planner-desk-claude#5" "ⓐ ASKED 줄 route = desk"

echo "== ⓑ feature 좌석 · feature 명부 _hil_route=planner → planner"
out="$(ask byz-feature-master-claude#2)"; rc=$?
[ $rc -eq 0 ] && ok "ⓑ ask rc=0" || bad "ⓑ rc=$rc $out"
[ "$(last_route)" = "byz-planner-master-claude#86" ] && ok "ⓑ 수신 = feature 명부의 planner" || bad "ⓑ 수신 = $(last_route)"

echo "== ⓒ 팀 명부에 _hil_route 없음(cfo 꼴) → REJECT · 다른 팀 대체 0"
n0="$(nroute)"
out="$(ask byz-cfo-master-codex#1)"; rc=$?
[ $rc -ne 0 ] && ok "ⓒ rc≠0 ($rc)" || bad "ⓒ rc=0 — 조용히 대체됨"
has "$out" "_hil_route 없음" "ⓒ 사유 = 그 명부에 _hil_route 없음"
has "$out" "seats-cfo.json" "ⓒ 사유에 읽은 명부 경로(cfo)"
[ "$(nroute)" = "$n0" ] && ok "ⓒ 송신 0" || bad "ⓒ 송신이 나갔다"

echo "== ⓒ2 팀 명부 파일 자체가 없음 → REJECT «팀 명부 없음 <경로>»"
printf '{"_master":"byz-ghost-master-claude#9","byz-ghost-master-claude#9":{"role":"master"}}\n' > "$R/.fable-team/seats-ghost.json"
mv "$R/.fable-team/seats-ghost.json" "$T/ghost.away"
out="$(ask byz-ghost-master-claude#9)"; rc=$?
[ $rc -ne 0 ] && has "$out" "팀 명부 없음" "ⓒ2 파일 없음 → «팀 명부 없음» REJECT" || bad "ⓒ2 rc=$rc $out"

echo "== ⓓ FT_SEATS·FT_HIL_ROUTE 명시 = 그대로 우선"
out="$(ask byz-ops-master-claude#1 FT_SEATS="$R/.fable-team/seats-planner.json")"; rc=$?
[ $rc -eq 0 ] && [ "$(last_route)" = "byz-planner-master-claude#86" ] && ok "ⓓ FT_SEATS 명시 우선" || bad "ⓓ rc=$rc 수신=$(last_route)"
out="$(ask byz-ops-master-claude#1 FT_HIL_ROUTE=byz-explicit-route-claude#0)"; rc=$?
[ $rc -eq 0 ] && [ "$(last_route)" = "byz-explicit-route-claude#0" ] && ok "ⓓ FT_HIL_ROUTE 명시 우선" || bad "ⓓ rc=$rc 수신=$(last_route)"

echo "== ⓔ 명부 lint: _hil_route = 다른 명부(planner)에만 행이 있는 살아 있는 desk 좌석 → 경보 0 · 죽으면 경보"
printf 'byz-planner-master-claude#86\nbyz-planner-desk-claude#5\nbyz-harness-master-claude#87\nbyz-ops-master-claude#1\nbyz-feature-master-claude#2\nbyz-cfo-master-codex#1\n' >> "$T/alive"
lx() { env FT_ROOT="$R" FT_TMUX_LS_CMD="bash $T/tmux.sh" FT_BOARD_NOW="2026-10-21T02:00:00" bash "$LINT" "$@" 2>&1; }
out="$(lx --team "$R/.fable-team/seats-ops.json")"; rc=$?
not "$out" "_hil_route" "ⓔ 살아 있는 다른 명부 좌석 = _hil_route 경보 0"
has "$out" "불일치 0" "ⓔ rc=0 불일치 0"
printf 'byz-planner-master-claude#86\nbyz-harness-master-claude#87\nbyz-ops-master-claude#1\nbyz-feature-master-claude#2\nbyz-cfo-master-codex#1\n' > "$T/alive"
out="$(lx --team "$R/.fable-team/seats-ops.json")"; rc=$?
has "$out" "_hil_route byz-planner-desk-claude#5 세션 없음" "ⓔ 죽은 좌석 → ⓑ 경보"
[ $rc -ne 0 ] && ok "ⓔ 경보 시 rc≠0" || bad "ⓔ 경보인데 rc=0"

echo "== 기존 시험 회귀 (test_hil_ledger.sh)"
FT_MBOX_CMD=/bin/true bash "$HERE/test_hil_ledger.sh" >/dev/null 2>&1 && ok "test_hil_ledger.sh PASS" || bad "test_hil_ledger.sh FAIL"

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
