#!/usr/bin/env bash
# test_skill_mbox_env_first_r2050.sh — r2050 반례 ② 래퍼 고정: 스킬 ft-mbox.py 사본을 팩 꼴 워크트리 cwd 에서 send
#  ⓐ FT_MBOX_DIR=<임시 루트>/.fable-team/comm(ft2 좌석 열기 칸의 꼴) → 임시 루트 comm 1줄 · 워크트리 공용 루트 comm 0줄
#  ⓑ 같은 일을 그 env 없이 → 공용 루트 comm 1줄(= 결함 재현) · 래퍼 변경 0 이라 기준판에서도 PASS
# 임시 git 리포·임시 우편함만 · 실 우편함·실 tmux 0 · sleep 0.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROOT FT_MBOX_DIR; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../skill/scripts/ft-mbox.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
eq() { [ "$2" = "$3" ] && echo "PASS $1" || { echo "FAIL $1 (기대 '$3' 실제 '$2')"; fail=$((fail+1)); }; }
lines() { [ -f "$1/mailbox.jsonl" ] && grep -c . "$1/mailbox.jsonl" || echo 0; }

world() {  # <이름> → $T/<이름>/{root,pack,pack-wt,tool}
  local W="$T/$1"
  mkdir -p "$W/root/.fable-team/comm" "$W/pack/.fable-team/comm" "$W/tool"
  cp "$SRC" "$W/tool/ft-mbox.py"
  git -C "$W/pack" init -q && echo 1 > "$W/pack/f" && git -C "$W/pack" add f \
    && git -C "$W/pack" -c user.email=t@t -c user.name=t commit -qm i && git -C "$W/pack" worktree add -q --detach "$W/pack-wt" || { echo "FAIL 준비 $1"; exit 1; }
  echo "$W"
}

W="$(world a)"
out="$(cd "$W/pack-wt" && FT_MBOX_DIR="$W/root/.fable-team/comm" timeout 25 python3 "$W/tool/ft-mbox.py" send byz-x-da byz-x-nano "r2050 a" --force 2>&1)"; rc=$?
eq "ⓐ rc" "$rc" 0
eq "ⓐ 루트 comm 1줄 · 공용 루트 0줄" "$(lines "$W/root/.fable-team/comm") $(lines "$W/pack/.fable-team/comm")" "1 0"

W="$(world b)"
out="$(cd "$W/pack-wt" && timeout 25 python3 "$W/tool/ft-mbox.py" send byz-x-da byz-x-nano "r2050 b" --force 2>&1)"; rc=$?
eq "ⓑ rc" "$rc" 0
eq "ⓑ env 없음 = 공용 루트 1줄(결함 재현)" "$(lines "$W/root/.fable-team/comm") $(lines "$W/pack/.fable-team/comm")" "0 1"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
