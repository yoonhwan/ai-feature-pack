#!/usr/bin/env bash
# test_card_assign_record_clear_r1988.sh — r1988 record <카드> clear <사유> | clear seat --seat <옛 이름> = 원장이 그 사유·그 좌석일 때만 none(since 유지 · released_at 지금 · 거울 «없음») ·
#   다른 사유·state·원장 없음 = REJECT rc1 쓰기 0. 반례 ①~⑦ + 변이 M1~M4(임시 사본 · 실파일 0) + bin·kit 같음.
# 임시 git 리포 · 실 원장·실 좌석·실 쪽지 0 · 네트워크 0 · 고정 sleep 0. 돌리기: timeout 70 bash harness/tests/test_card_assign_record_clear_r1988.sh
set -uo pipefail
export TZ=Asia/Seoul FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CARD_ASSIGN_NOW
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
TOOL="$BIN/ft_card_assign_watch.py"; NOW=$(date +%s); H=design/harness/indices; S0=$((NOW - 9000))
gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t.com commit -q --allow-empty -m "$3"; }
new_root() {  # 임시 루트 R(git main) + 카드 루트 표 + 카드 k · 원장 = R/.fable-team/state/card-assign/k.json
  R="$(mktemp -d "$T/r.XXXXXX")"; mkdir -p "$R/.fable-team/state/card-assign" "$R/$H/대기"
  git -C "$R" init -q -b main; printf '.fable-team/\n' > "$R/.gitignore"
  printf 'harness\t.\tmain\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '%s\n' "# 카드 k" "- 상태: 대기" "- 배정: 대기(DA · 2026-11-14T10:00:00)" "## 상태" "- 시험" > "$R/$H/대기/k.md"
  git -C "$R" add -A; gc "$R" "$((NOW - 90000)) +0900" card
  [ -z "${1:-}" ] || printf '%s\n' "$1" > "$R/.fable-team/state/card-assign/k.json"
}
rec() { OUT="$(cd "$R" && env FT_ROOT="$R" FT_CARD_ASSIGN_NOW="$NOW" python3 "${TOOL_RUN:-$TOOL}" record "$R/$H/대기/k.md" "$@" 2>&1)"; RC=$?; }
jget() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]))' "$R/.fable-team/state/card-assign/k.json" "$2"; }
snap() { cat "$R/.fable-team/state/card-assign/k.json" "$R/$H/대기/k.md" 2>/dev/null | shasum | cut -c1-12; }
same() { local b; b="$(snap)"; rec "$@"; [ "$RC" = 1 ] && [ "$(snap)" = "$b" ] && case "$OUT" in REJECT*) true;; *) false;; esac; }

c1() { new_root '{"state":"waiting","reason":"DA","since":'$S0',"pause":{"kind":"hold","key":"1"},"urgent":false}'; rec clear DA
  [ "$RC" = 0 ] && [ "$(jget k state)" = none ] && [ "$(jget k reason)" = None ] && [ "$(jget k pause)" = None ] && [ "$(jget k since)" = "$S0.0" ] \
    && [ "$(jget k released_at)" = "$NOW.0" ] && grep -qx -- '- 배정: 없음' "$R/$H/대기/k.md"; }
c2() { new_root '{"state":"waiting","reason":"선행","since":'$S0'}'; same clear DA; }
c3() { new_root '{"state":"seat","seat":"byz-harness-nano-k#0"}'; same clear DA; }
c4() { new_root; same clear DA && [ ! -e "$R/.fable-team/state/card-assign/k.json" ]; }
c5() { new_root '{"state":"waiting","reason":"사람","since":'$S0',"verdict":"7"}'; local b; b="$(snap)"; rec clear 사람
  [ "$RC" = 2 ] && [ "$(snap)" = "$b" ] && case "$OUT" in *"판정 번호 필수"*) true;; *) false;; esac || return 1
  rec clear 사람 verdict 7; [ "$RC" = 0 ] && [ "$(jget k state)" = none ] && [ "$(jget k verdict)" = None ]; }
c6() { new_root '{"state":"seat","seat":"byz-harness-nano-k#0"}'; rec clear seat --seat byz-harness-nano-k#0
  [ "$RC" = 0 ] && [ "$(jget k state)" = none ] && [ "$(jget k seat)" = None ] && [ "$(jget k released_at)" = "$NOW.0" ] && grep -qx -- '- 배정: 없음' "$R/$H/대기/k.md"; }
c7() { new_root '{"state":"seat","seat":"byz-harness-nano-k#0"}'; same clear seat --seat byz-harness-nano-x#1 && { new_root '{"state":"waiting","reason":"DA","since":'$S0'}'; same clear seat --seat byz-harness-nano-k#0; }; }

for c in 1 2 3 4 5 6 7; do
  n=$(printf '①②③④⑤⑥⑦' | python3 -c "import sys;print(sys.stdin.read()[$c-1])")
  if c$c; then ok "$n clear 반례 $c"; else bad "$n clear 반례 $c :: rc=$RC $OUT"; fi
done
lap cases
cmp -s "$TOOL" "$KIT/ft_card_assign_watch.py" && ok "bin·kit 같음" || bad "bin·kit 다름"

mutant() {  # <이름> <옛 글> <새 글> <잡혀야 할 반례> — 임시 폴더(형제 모듈은 심링크)에서만 바꾼다
  local d="$T/m$1"; mkdir -p "$d"; for f in "$BIN"/*.py; do ln -s "$f" "$d/"; done; rm "$d/ft_card_assign_watch.py"
  python3 - "$TOOL" "$d/ft_card_assign_watch.py" "$2" "$3" <<'PY' || { bad "$1 변이 적용 실패"; return; }
import sys; s = open(sys.argv[1], encoding="utf-8").read(); assert s.count(sys.argv[3]) == 1, "옛 글 1곳 아님"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
  if TOOL_RUN="$d/ft_card_assign_watch.py" c$4; then bad "$1 변이가 살아남음(반례 $4 통과)"; else ok "$1 변이 → 반례 $4 FAIL"; fi
}
mutant M1 'else old.get("reason") == arg' 'else True' 2
mutant M2 '"since": float(old.get("since") or now)' '"since": now' 1
mutant M3 'if old.get("state") != want or not hit:' 'if old.get("state") != "seat" and (old.get("state") != want or not hit):' 3
mutant M4 'old.get("seat") == seat if' 'True if' 7
lap mutants
echo "단계:$STEP · FAIL $fail"
[ "$fail" = 0 ]
