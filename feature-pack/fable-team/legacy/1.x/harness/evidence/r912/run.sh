#!/usr/bin/env bash
# r912 전/후 — base(origin/main) 파일로는 새 시험이 빨강 · 이 브랜치 파일로는 초록(임시 사본에서 돈다 · 실 파일·실 큐 수정 0).
# 사용: bash run.sh <outdir>   (outdir 에 red-base.txt · green.txt · files.txt 를 쓴다)
set -uo pipefail
H="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"   # = fable-team/harness
R="$(cd "$H/../../.." && pwd)"                                   # = 팩 리포 루트
OUT="${1:-$H/evidence/r912}"; mkdir -p "$OUT"
PY="${PYTHON:-python3.11}"
BASE="${BASE_REF:-origin/main}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

stage() {   # stage <dir> — 하네스 사본(bin·comm·tests·kit) + skill 사본(자르는 곳 셋 대조용)
  mkdir -p "$1/fable-team/harness"
  cp -R "$H/bin" "$H/comm" "$H/tests" "$H/kit" "$1/fable-team/harness/"
  cp -R "$H/../skill" "$1/fable-team/"   # ★r3★ skill/scripts/ft-mbox.py 도 같은 규칙으로 자른다(시험 ⓕ·ⓘ)
  find "$1" -name __pycache__ -type d -prune -exec rm -rf {} +
  # 시험 하네스(real_state_guard)가 «git 저장소» 를 전제한다 — 사본을 저장소로 만든다(실 저장소와 무관).
  git -C "$1" init -q && git -C "$1" add -A && git -C "$1" -c user.name=m -c user.email=m@m commit -qm base >/dev/null
}

run_all() {   # run_all <dir> — 격리 사본에서 두 시험을 돌려 stdout+rc 를 찍는다
  local d="$1/fable-team/harness" rc=0
  echo "## shell: bash tests/test_mbox_keep_human_mail.sh"
  (cd "$d" && PYTHONDONTWRITEBYTECODE=1 bash tests/test_mbox_keep_human_mail.sh 2>&1); echo "rc=$?"
  echo "## py: pytest tests/scripts/test_model_swap_notify_coalesce.py"
  (cd "$d" && PYTHONDONTWRITEBYTECODE=1 "$PY" -m pytest -q -p no:cacheprovider tests/scripts/test_model_swap_notify_coalesce.py 2>&1 | grep -E "^(FAILED|ERROR|[0-9]+ (passed|failed))" | head -20); echo "rc=${PIPESTATUS[0]}"
}

# ── 전(red): base 의 mbox_ops·ft_model_swap·ft_model_swap_account·kit/skill ft-mbox.py 로 되돌리고 mbox_keep.py 는 지운다
S="$T/red"; stage "$S"
for f in comm/mbox_ops.py bin/ft_model_swap.py bin/ft_model_swap_account.py kit/fable-team/bin/ft-mbox.py; do
  git -C "$R" show "$BASE:feature-pack/fable-team/harness/$f" > "$S/fable-team/harness/$f" || { echo "ERROR $BASE:$f 못 읽음"; exit 1; }
done
git -C "$R" show "$BASE:feature-pack/fable-team/skill/scripts/ft-mbox.py" > "$S/fable-team/skill/scripts/ft-mbox.py" || { echo "ERROR $BASE:skill/scripts/ft-mbox.py 못 읽음"; exit 1; }
rm -f "$S/fable-team/harness/comm/mbox_keep.py"
{ echo "# 전(red) — base=$BASE ($(git -C "$R" rev-parse --short "$BASE")) 의 comm/mbox_ops.py · bin/ft_model_swap*.py · kit/skill ft-mbox.py + mbox_keep.py 없음"
  echo "# 새 시험이 «실패»해야 정상(고치기 전 결함을 시험이 실제로 잡는지)."
  run_all "$S"; } > "$OUT/red-base.txt" 2>&1

# ── 후(green): 이 브랜치 파일 그대로
S2="$T/green"; stage "$S2"
{ echo "# 후(green) — 이 브랜치 파일 그대로"
  run_all "$S2"; } > "$OUT/green.txt" 2>&1

# ── 변경 파일 + kit 짝 cmp
{ echo "# 변경·추가 파일 (git status · diff --stat vs $BASE)"
  git -C "$R" -c core.quotepath=false status --porcelain -- feature-pack/fable-team/harness | sed 's/^/  /'
  git -C "$R" diff --stat "$BASE" -- feature-pack/fable-team/harness | sed 's/^/  /'
  echo "# 짝 사본 kit cmp0"
  for f in ft_model_swap.py ft_model_swap_account.py; do
    if cmp -s "$H/bin/$f" "$H/kit/fable-team/bin/$f"; then echo "  cmp0 bin/$f = kit/fable-team/bin/$f"; else echo "  DRIFT bin/$f vs kit"; fi
  done
  echo "# 줄 수(≤200 규칙)"
  wc -l "$H/comm/mbox_ops.py" "$H/comm/mbox_keep.py" "$H/bin/ft_model_swap.py" "$H/bin/ft_model_swap_account.py" | sed 's/^/  /'
  echo "# 자르는 곳 셋 공유 블록 바이트 동일(r3 · 시험 ⓘ)"
  python3 - "$H/comm/mbox_keep.py" "$H/kit/fable-team/bin/ft-mbox.py" "$H/../skill/scripts/ft-mbox.py" <<'PY' | sed 's/^/  /'
import re, sys, hashlib
pat = re.compile(r"^# >>> r912 mbox_keep shared begin.*?^# <<< r912 mbox_keep shared end\n", re.S | re.M)
hs = [hashlib.sha256((pat.search(open(p, encoding="utf-8").read()) or [""]).group(0).encode()).hexdigest()[:16] for p in sys.argv[1:]]
print("identical" if len(set(hs)) == 1 else "DRIFT", hs)
PY
} > "$OUT/files.txt" 2>&1

grep -c FAIL "$OUT/red-base.txt" >/dev/null
echo "== red-base (앞 25줄)"; head -25 "$OUT/red-base.txt"
echo "== green"; tail -6 "$OUT/green.txt"
echo "== files"; cat "$OUT/files.txt"
