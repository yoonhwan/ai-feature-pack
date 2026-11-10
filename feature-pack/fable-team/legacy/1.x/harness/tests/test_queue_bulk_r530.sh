#!/usr/bin/env bash
# test_queue_bulk_r530.sh — r530: 일괄 보류 판정기 ft_queue_bulk.py bulk-check + 홈 훅 harness-freeze-gate.sh 규칙 1.
#   픽스처 = 임시 git 리포(큐 md + 카드 md 2장) · 훅엔 PreToolUse JSON · 외부 호출 0 · GIT_* env 0 · 실 리포·실 HOME 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
QB="$HERE/../kit/fable-team/bin/ft_queue_bulk.py"
GATE="$HERE/../kit/hooks/harness-freeze-gate.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
# chk <기대 rc> <이름> <bulk-check 인자…> — stdout+stderr → $T/out
chk() { local want=$1 name=$2; shift 2; python3 "$QB" bulk-check "$@" --repo "$R" >"$T/out" 2>&1; local rc=$?
  [ "$rc" = "$want" ] && ok "$name rc=$rc" || bad "$name — rc=$rc 기대 $want · $(head -c 300 "$T/out")"; }
has() { grep -qF -- "$2" "$T/$1" && ok "$3" || bad "$3 — '$2' 없음 · $(head -c 300 "$T/$1")"; }
# gate <command> [env…] → rc · stderr → $T/err
gate() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$R" "$1" \
  | FT_QUEUE_BULK="${QBX:-$QB}" bash "$GATE" 2>"$T/err"; }
gexp() { gate "$2"; local rc=$?; [ "$rc" = "$1" ] && ok "$3 rc=$rc" || bad "$3 — rc=$rc 기대 $1 · $(head -c 300 "$T/err")"; }

R="$T/byz"; Q="$R/design/teams/planner/AUTONOMY-QUEUE.md"; C="$R/design/harness/indices/대기"
mkdir -p "$(dirname "$Q")" "$C"
git -C "$R" init -q -b main && git -C "$R" config user.email t@t && git -C "$R" config user.name t
{ echo '# 큐'; echo; echo '| 자율 | 시각 | 질문 | 처리됨 |'; echo '|---|---|---|---|'
  for i in 1 2 3 4 5 6 7 8 9 10; do echo "| A2 | 2026-10-14 16:3$((i%10)) | q$i | 대기 |"; done; } > "$Q"
for c in c1 c2; do printf '# 인덱스: %s\n- 상태: 대기\n\n## 상태\n- base_sha: x\n' "$c" > "$C/$c.md"; done
git -C "$R" add -A && git -C "$R" commit -qm init
H='보류 — X 막힘 · 재확인 2026-10-21 09:00'
setq() { python3 - "$Q" "$@" <<'PY'
import sys
p, pairs = sys.argv[1], sys.argv[2:]
lines = open(p, encoding="utf-8").read().splitlines()
for q, v in zip(pairs[::2], pairs[1::2]):
    lines = [(l.rsplit("|", 2)[0] + f"| {v} |") if f"| {q} |" in l else l for l in lines]
open(p, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
}
reset() { git -C "$R" reset -q --hard; }

[ -f "$QB" ] && ok "판정기 파일 있음" || bad "판정기 파일 없음: $QB"

# ⓐ 큐 2줄 → 보류(스테이징) = REJECT
setq q3 "$H" q9 "$H"; git -C "$R" add -A
chk 1 "ⓐ 큐 2줄 보류 --staged" --staged
has out 'REJECT 일괄 보류 2줄(' "ⓐ REJECT 머리"
has out 'AUTONOMY-QUEUE.md:7' "ⓐ q3 줄 번호(7)"
has out 'AUTONOMY-QUEUE.md:13' "ⓐ q9 줄 번호(13)"
has out '보류는 한 번에 한 줄 · 줄마다 사유·재확인 시각' "ⓐ 사유 문구"
reset

# ⓑ 1줄만 = 통과
setq q3 "$H"; git -C "$R" add -A
chk 0 "ⓑ 큐 1줄 보류" --staged
has out 'OK 일괄 보류 1줄' "ⓑ OK 줄"
reset

# ⓒ 새 줄 2개가 처음부터 보류 = REJECT
printf '| A9 | 2026-10-20 10:00 | n1 | %s |\n| A9 | 2026-10-20 10:01 | n2 | %s |\n' "$H" "$H" >> "$Q"; git -C "$R" add -A
chk 1 "ⓒ 새 줄 2개 처음부터 보류" --staged
reset

# ⓓ 카드 2장 «- 상태:» → 보류 = REJECT · 1장 = 통과
sed -i '' "s/^- 상태: 대기$/- 상태: $H/" "$C/c1.md" "$C/c2.md"; git -C "$R" add -A
chk 1 "ⓓ 카드 2장 보류" --staged
has out 'c1.md' "ⓓ 카드 이름 c1"
has out 'c2.md' "ⓓ 카드 이름 c2"
reset
sed -i '' "s/^- 상태: 대기$/- 상태: $H/" "$C/c1.md"; git -C "$R" add -A
chk 0 "ⓓ 카드 1장 보류" --staged
reset
# ⓓ' 큐 1줄 + 카드 1장 = 합계 2 = REJECT
setq q3 "$H"; sed -i '' "s/^- 상태: 대기$/- 상태: $H/" "$C/c1.md"; git -C "$R" add -A
chk 1 "ⓓ' 큐 1줄 + 카드 1장 합계 2" --staged
reset

# ⓔ 풀기(보류 → 대기·진행·완료) 여러 줄 = 통과 · 이미 보류인 줄 그대로 + 다른 칸 손봄 = 통과
setq q1 "$H"; git -C "$R" commit -qam h1; setq q2 "$H"; git -C "$R" commit -qam h2; setq q4 "$H"; git -C "$R" commit -qam h4
sed -i '' "s/^- 상태: 대기$/- 상태: $H/" "$C/c1.md"; git -C "$R" commit -qam c1h
sed -i '' "s/^- 상태: 대기$/- 상태: $H/" "$C/c2.md"; git -C "$R" commit -qam c2h
setq q1 '대기' q2 '진행 — v65 master' q4 '완료 — 판정 2501'
sed -i '' "s/^- 상태: 보류.*$/- 상태: 진행/" "$C/c1.md" "$C/c2.md"; git -C "$R" add -A
chk 0 "ⓔ 보류 3줄·카드 2장 풀기" --staged
has out 'OK 일괄 보류 0줄' "ⓔ OK 0줄"
reset
git -C "$R" mv "$C/c1.md" "$R/design/harness/indices/c1.md"; git -C "$R" mv "$C/c2.md" "$R/design/harness/indices/c2.md"
chk 0 "ⓔ 이미 보류인 카드 2장 폴더 이동(git mv) = 새 보류 아님" --staged
reset

# ⓖ --range A..B (착지 게이트) — 같은 판정
B0=$(git -C "$R" rev-parse HEAD)
setq q5 "$H" q6 "$H"; git -C "$R" commit -qam two
chk 1 "ⓖ --range 2줄 보류 커밋" --range "$B0..HEAD"
has out 'REJECT 일괄 보류 2줄(' "ⓖ range REJECT 머리"
B1=$(git -C "$R" rev-parse HEAD); setq q7 "$H"; git -C "$R" commit -qam one
chk 0 "ⓖ --range 1줄 보류 커밋" --range "$B1..HEAD"
chk 2 "ⓖ 없는 rev = git 실패 rc2" --range "nope..HEAD"
chk 2 "ⓖ 인자 없음 rc2"

# ⓕ 훅(harness-freeze-gate · freeze 표식 없음)
setq q8 "$H" q10 "$H"; git -C "$R" add -A
gexp 2 'git commit -m x' "ⓕ git commit + 큐 2줄 보류 = exit 2"
has err 'REJECT 일괄 보류 2줄(' "ⓕ stderr REJECT"
[ "$(grep -c 'REJECT 일괄 보류' "$T/err")" = 1 ] && ok "ⓕ REJECT 1줄" || bad "ⓕ REJECT 줄 수 $(grep -c 'REJECT 일괄 보류' "$T/err")"
gexp 2 "cd $R && git commit -m x" "ⓕ cd 따라감 = exit 2"
gexp 0 'git status --short' "ⓕ git commit 아닌 명령 = 통과"
gexp 0 'echo "git commit -m x"' "ⓕ 따옴표 안 글자 = 통과"
QBX="$T/none.py" gexp 0 'git commit -m x' "ⓕ 판정기 없음 = 통과(fail-open)"
has err 'WARN' "ⓕ 판정기 없음 WARN"
printf '{bad json' | FT_QUEUE_BULK="$QB" bash "$GATE" 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && ok "ⓕ JSON 깨짐 = 통과 rc=0" || bad "ⓕ JSON 깨짐 rc=$rc"
has err 'WARN' "ⓕ JSON 깨짐 WARN"
git -C "$R" reset -q; setq q8 "$H" q10 "$H"
gexp 2 'git commit -am x' "ⓕ -a(작업 트리만 2줄 보류) = exit 2"
gexp 0 'git commit -m x' "ⓕ 스테이징 0 + 평범한 커밋 = 통과"
reset; setq q8 "$H"; git -C "$R" add -A
gexp 0 'git commit -m x' "ⓕ 1줄 보류 커밋 = 통과"
reset

# ⓖ 기존 harness-freeze-gate 시험 그대로(freeze 규칙)
bash "$HERE/test_harness_freeze_gate.sh" >"$T/freeze" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "ⓖ 기존 test_harness_freeze_gate.sh rc=0" || bad "ⓖ 기존 freeze 시험 rc=$rc · $(grep FAIL "$T/freeze" | head -3)"

echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "FAIL $fail" ) =="
[ $fail = 0 ]
