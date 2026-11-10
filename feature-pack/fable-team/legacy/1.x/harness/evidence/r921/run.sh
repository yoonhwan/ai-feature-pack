#!/usr/bin/env bash
# r921 전/후 — «base(origin/main) 코드 + 새 시험» = 빨강 · «이 브랜치 코드 + 새 시험» = 초록.
# 임시 사본에서 돈다 — 실 bin·실 kit·실 상태 파일 수정 0 (사본만 바꾼다).
# 사용: bash run.sh [<outdir>]   (기본 = 이 폴더 · red-base.txt · green.txt · files.txt 를 쓴다)
set -uo pipefail
H="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"   # = fable-team/harness
R="$(cd -- "$H/../../.." && pwd)"                               # = 팩 리포 루트
PKG="$R/feature-pack/fable-team/harness"                        # git 경로 접두
OUT="${1:-$H/evidence/r921}"; mkdir -p "$OUT"
BASE="${BASE_REF:-origin/main}"
# 이 카드가 바꾼 파일 — base 모드에서만 이 8개를 origin/main 판으로 되돌린다(나머지는 그대로)
CHANGED="ft-resource-gate.sh ft-nano-spawn.sh ft-role-spawn.sh ft-tick.sh ft-research-seat-lib.sh ft-resource-reclaim.sh ft-successor-open.sh ft_spawn_queue.py ft-reclaim-capped.sh"   # r2: ft-reclaim-capped.sh 신규 = base 에 없다(되돌리면 «없음» REJECT 로 빨강)
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

stage() { # stage <dst> <base|branch>
  local dst="$1/harness" mode="$2" f   # 시험이 REPO=$HERE/../.. 에서 bin·kit·tests 를 찾는다 — <dst>/harness 꼴로 놓는다
  mkdir -p "$dst"
  cp -R "$H/bin" "$dst/" && cp -R "$H/kit" "$dst/" && cp -R "$H/tests" "$dst/" || return 1
  [ "$mode" = base ] || return 0
  for f in $CHANGED; do
    git -C "$R" cat-file -e "$BASE:feature-pack/fable-team/harness/bin/$f" 2>/dev/null || { rm -f "$dst/bin/$f" "$dst/kit/fable-team/bin/$f"; continue; }   # base 에 없던 신규 파일 = 전 상태에선 «없음»
    git -C "$R" show "$BASE:feature-pack/fable-team/harness/bin/$f" > "$dst/bin/$f" || { echo "STAGE ERR base $f"; return 1; }
    if [ -f "$dst/kit/fable-team/bin/$f" ]; then git -C "$R" show "$BASE:feature-pack/fable-team/harness/kit/fable-team/bin/$f" > "$dst/kit/fable-team/bin/$f" || return 1; fi
  done
}

{ echo "# base(${BASE}) 코드 + 이 브랜치의 새 시험 — «멈춤» 코드에서는 새 시험이 빨강이어야 한다"
  echo "# 명령: bash tests/test_resource_warn_proceed_r921.sh (임시 사본 $T/base)"
  stage "$T/base" base || exit 1
  bash "$T/base/harness/tests/test_resource_warn_proceed_r921.sh" 2>&1; echo "---- base rc=$?"
} > "$OUT/red-base.txt"

{ echo "# 이 브랜치 코드 + 이 브랜치 시험 — 초록(카드 ⓐ~ⓖ + 변이 4종)"
  echo "# 명령: bash tests/test_resource_warn_proceed_r921.sh (임시 사본 $T/branch)"
  stage "$T/branch" branch || exit 1
  bash "$T/branch/harness/tests/test_resource_warn_proceed_r921.sh" 2>&1; echo "---- branch rc=$?"
} > "$OUT/green.txt"

{ echo "# 이 카드가 바꾼 코드 파일(base↔branch)"; for f in $CHANGED; do echo "bin/$f"; echo "kit/fable-team/bin/$f"; done
  echo "# 이 카드가 바꾼·추가한 시험"; echo "tests/test_resource_warn_proceed_r921.sh (신규 ⓐ~ⓖ + 변이 4종)"
  echo "tests/test_resource_gate.sh · tests/test_resource_gate_pressure.sh · tests/test_resource_freeze_exempt.sh (기대값을 WARN+진행으로 갱신)"
  echo "tests/test_resource_reclaim.sh · tests/test_nano_spawn_teamset_cap.sh (회수·AT-CAP 갈래 갱신)"
  echo "tests/test_role_spawn_team.sh · tests/test_raised_seat.sh (임시 bin 짝 누락 = 사전 결함 보충)"
  echo "tests/lib/fake_reclaim_world.sh (NOW 재앵커 = 사전 시간 flake 제거)"
} > "$OUT/files.txt"
[ "$OUT" = "$H/evidence/r921" ] && { chmod +x "$H/evidence/r921/run.sh" 2>/dev/null; true; }
echo "wrote $OUT/{red-base.txt,green.txt,files.txt}"
