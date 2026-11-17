#!/usr/bin/env bash
# test_disk_reclaim_split_r2199.sh — r2199 ft-disk-reclaim.sh squash 길 떼기 반례 ②~④(① = r2107 · r2196 시험 재실행).
# ② 줄 수 < 200 두 파일 · ③ bin = kit 같은 바이트 두 파일 · ④ 모듈 뺀 사본 → plan · apply rc 3 · stderr 1줄 · 쓰기/지우기 0.
# 입력은 mktemp 안 · 실 gh · lsof · tmux 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_DISK_RECLAIM_DIR:-$HERE/../bin}"; KIT="$HERE/../kit/fable-team/bin"
TOOL="$BIN/ft-disk-reclaim.sh"; MOD="$BIN/_disk_reclaim_squash.py"
W="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$W"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }
[ -f "$TOOL" ] && [ -f "$MOD" ] || { echo "FAIL 도구 없음: $TOOL $MOD"; exit 1; }
T0=$SECONDS

# ② 줄 수
chk "② ft-disk-reclaim.sh < 200줄" "$([ "$(wc -l < "$TOOL")" -lt 200 ] && echo y)" "y"
chk "② _disk_reclaim_squash.py < 200줄" "$([ "$(wc -l < "$MOD")" -lt 200 ] && echo y)" "y"
# ③ bin = kit
for f in ft-disk-reclaim.sh _disk_reclaim_squash.py; do
  chk "③ bin = kit $f" "$(cmp -s "$BIN/$f" "$KIT/$f" && echo same)" "same"
done
T1=$SECONDS

# ④ 모듈 뺀 사본(설치가 새 파일을 빠뜨린 꼴)
mkdir -p "$W/b" "$W/tmp/old" "$W/cache" "$W/out" "$W/a"; cp "$TOOL" "$W/b/"
export FT_RECLAIM_TMP_ROOT="$W/tmp" FT_RECLAIM_CACHE_ROOT="$W/cache" FT_RECLAIM_REPOS="$W/none" FT_RECLAIM_INFO="" FT_RECLAIM_GH=/bin/false
bash "$W/b/ft-disk-reclaim.sh" plan "$W/out" > "$W/p.out" 2> "$W/p.err"; rc=$?
chk "④ plan rc 3 · stdout 0 · stderr 1줄 · candidates.tsv 0" \
  "$rc|$(wc -c < "$W/p.out" | tr -d ' ')|$(cat "$W/p.err")|$(ls "$W/out" | wc -l | tr -d ' ')" "3|0|판정 불가 squash 모듈|0"
printf 'tmp\t1\t%s\t조건 전부\n' "$W/tmp/old" > "$W/a/c.tsv"
bash "$W/b/ft-disk-reclaim.sh" apply "$W/a/c.tsv" > "$W/a.out" 2> "$W/a.err"; rc=$?
chk "④ apply rc 3 · stderr 1줄 · ABORT 줄 · 지우기 0" \
  "$rc|$(cat "$W/a.err")|$(cat "$W/a/deleted.log")|$([ -d "$W/tmp/old" ] && echo kept)" \
  "3|판정 불가 squash 모듈|ABORT 판정 불가 squash 모듈 deleted=0 skipped=0|kept"
chk "④ __pycache__ 0" "$(ls -d "$BIN/__pycache__" "$W/b/__pycache__" 2>/dev/null | wc -l | tr -d ' ')" "0"
T2=$SECONDS
echo "TIME ②③=$((T1-T0))s ④=$((T2-T1))s"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL count=$fail"
exit $(( fail > 0 ))
