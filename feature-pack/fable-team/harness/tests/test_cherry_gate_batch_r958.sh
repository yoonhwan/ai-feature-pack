#!/usr/bin/env bash
# test_cherry_gate_batch_r958.sh — r958: ⑤ cherry 게이트의 커밋·경로별 외부 호출을 «묶음 호출» 로 바꾼다.
#   ⓐ(빨강 먼저) «+» 커밋 300개에서 지금 판은 커밋마다 git 을 3회 부른다(외부 호출 수 ∝ 커밋 수 = 70초 초과 REJECT 의 원인) — 새 판은 묶음 상수 회.
#   ⓑ 같은 입력에서 판정 결과(차단·WARN 목록·사유 토큰·stdout 전문)가 지금 판과 같다.  ⓒ 1회가 상한을 넘으면 반으로 쪼개 재시도 1, 그래도 넘으면 사유 있는 REJECT.
#   ⓓ 진행 파일로 다시 부르면 끝난 묶음은 건너뛴다(같은 결과).  ⓔ 기존 시험 ALL PASS · /bin/bash 3.2.  ⓕ 변이 2종이 각각 ⓑ·ⓒ 단언을 깨뜨린다.
# mktemp 리포만 쓴다 — 실 브랜치·루트 .fable-team/·원장 쓰기 0. press(라이브 오디오) 없음.
set -uo pipefail
export FT_TEAMSET=0 FT_ALLOW_TRACKED_BIN=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../harness/bin"
G="$KIT/ft-nano-cherry-gate.sh"
OLD="${FT_TEST_OLD_GATE:-}"          # 지금 판(옛 게이트) 경로 — 없으면 origin/main 사본을 뜬다
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

[ -n "$OLD" ] && [ -f "$OLD" ] || OLD="$T/old-gate.sh"
if [ ! -s "$OLD" ]; then
  git -C "$KIT" show origin/main:feature-pack/fable-team/harness/bin/ft-nano-cherry-gate.sh > "$OLD" 2>/dev/null \
    || git -C "$KIT" show HEAD:feature-pack/fable-team/harness/bin/ft-nano-cherry-gate.sh > "$OLD" 2>/dev/null
fi
[ -s "$OLD" ] || { echo "FAIL 옛 게이트 사본을 못 떴다(origin/main·HEAD)"; exit 1; }

# ── 가짜 git(호출 기록 + 느린 git) ────────────────────────────────────────────────
REAL_GIT="$(command -v git)"
mkdir -p "$T/bin"
cat > "$T/bin/git" <<'SH'
#!/bin/bash
[ -z "${FT_GIT_LOG:-}" ] || printf '%s\n' "$*" >> "$FT_GIT_LOG"
if [ -n "${FT_SLOW_WHEN:-}" ]; then case "$*" in *"$FT_SLOW_WHEN"*) sleep "${FT_SLOW_SLEEP:-2}";; esac; fi
exec "$REAL_GIT" "$@"
SH
chmod 755 "$T/bin/git"
gitc() { PATH="$T/bin:$PATH" REAL_GIT="$REAL_GIT" "$@"; }

# ── 픽스처 ─────────────────────────────────────────────────────────────────────
w()  { mkdir -p "$(dirname "$R/$1")"; printf '%s\n' "$2" > "$R/$1"; }
cm() { git -C "$R" add -A && git -C "$R" commit -qm "$1"; }
# small: 옛 시험과 같은 5가지 판정 상황을 한 파일에 담는다(ⓑ 대조용)
mksmall() {  # <이름> → $R
  R="$T/$1"; git init -q -b main "$R"
  w app/a.py a0; w design/card.md c0; cm base
  git -C "$R" checkout -q -b nano/x
  w app/b.py b1; w design/card.md nano1; cm "nano code+card"
  w design/d.md dn; cm "nano doc only"
  w app/b.py b0; cm "nano revert code"
  git -C "$R" checkout -q main; w design/card.md feat; cm "feat card"; w app/m.py m; cm "feat moved"
}
# big: «+» 커밋 N개 · 경로 M개(한 커밋이 M개 전부를 건드린다 = 경로 수천 혼합 커밋) — ⓐ·ⓓ
mkbig() {  # <이름> <커밋 수> <경로 수> <design 만?>
  local i m="$3"
  R="$T/$1"; git init -q -b main "$R"
  for i in $(seq 1 "$m"); do mkdir -p "$R/d$(($i % 40))/p"; printf 'f%s\n' "$i" > "$R/d$(($i % 40))/p/f$i.txt"; done
  mkdir -p "$R/app" "$R/design"; printf 'x\n' > "$R/app/main.py"; printf 'd0\n' > "$R/design/base.md"   # feat·design 커밋이 쓸 자리
  cm base
  git -C "$R" checkout -q -b nano/x
  for i in $(seq 1 "$2"); do
    if [ "${4:-0}" = 1 ]; then printf 'd%s\n' "$i" > "$R/design/c$i.md"; else printf 'c%s\n' "$i" > "$R/app/c$i.py"; fi
    git -C "$R" add -A; git -C "$R" commit -qm "nano $i"
  done
  if [ "${4:-0}" = 0 ]; then   # 경로 수천 혼합 커밋 1개(위 커밋들 + M개 경로 전부)
    for i in $(seq 1 "$m"); do printf 'g%s\n' "$i" > "$R/d$(($i % 40))/p/f$i.txt"; done
    git -C "$R" add -A; git -C "$R" commit -qm "nano mega"
  fi
  git -C "$R" checkout -q main; printf 'feat\n' > "$R/app/main.py"
  git -C "$R" add -A; git -C "$R" commit -qm "feat touch"
}
run() { OUT="$(bash "$1" main nano/x --repo "$R" 2>&1)"; RC=$?; }

# ⓐ 빨강 먼저 — 옛 판은 커밋마다 git 3회(호출 수 = 3×커밋 수), 새 판은 묶음 상수 회
mkbig biga 300 4 1
: > "$T/calls-old"
FT_GIT_LOG="$T/calls-old" gitc bash "$OLD" main nano/x --repo "$R" >/dev/null 2>&1; n_old="$(wc -l < "$T/calls-old" | tr -d ' ')"
: > "$T/calls-new"
FT_GIT_LOG="$T/calls-new" gitc bash "$G" main nano/x --repo "$R" >/dev/null 2>&1; n_new="$(wc -l < "$T/calls-new" | tr -d ' ')"
[ "$n_old" -ge 900 ] && ok "ⓐ옛 판 외부 호출 ${n_old}회 ≥ 3×300(커밋 수 비례)" || bad "ⓐ옛 판 외부 호출이 커밋 수 비례가 아니다(${n_old}회) — 픽스처 확인"
[ "$n_new" -le 20 ] && ok "ⓐ새 판 외부 호출 ${n_new}회 ≤ 20(묶음 상수 회)" || bad "ⓐ새 판 외부 호출 ${n_new}회 > 20 — 묶음 호출이 아니다"

# ⓑ 같은 입력 → 같은 판정(차단·WARN 목록·사유 토큰·stdout 전문 대조)
mksmall s1
run "$OLD"; old_out="$OUT" old_rc="$RC"
run "$G";   new_out="$OUT" new_rc="$RC"
[ "$old_rc" = "$new_rc" ] && [ "$old_out" = "$new_out" ] && ok "ⓑsmall 판정 전문 동일(rc=${RC})" \
  || bad "ⓑsmall 판정이 다르다(rc ${old_rc}≠${new_rc}) :: old=${old_out:0:400} new=${new_out:0:400}"
mkbig bigb 12 300 0     # 경로 수천 혼합 커밋 + 코드 커밋 → REJECT(차단 목록·경로 사유)
: > "$T/calls-b"
FT_GIT_LOG="$T/calls-b" gitc bash "$G" main nano/x --repo "$R" > "$T/newb" 2>&1; new_rc=$?
old_out="$(bash "$OLD" main nano/x --repo "$R" 2>&1)"; old_rc=$?
same_block() { diff <(printf '%s\n' "$1" | grep -E '^  \+ |^REJECT|^WARN' ) <(printf '%s\n' "$2" | grep -E '^  \+ |^REJECT|^WARN') >/dev/null; }
[ "$old_rc" = "$new_rc" ] && same_block "$old_out" "$(cat "$T/newb")" && ok "ⓑbig 판정 동일(rc=${new_rc} · 차단·WARN 목록 같음)" \
  || bad "ⓑbig 판정이 다르다(rc ${old_rc}≠${new_rc}) :: $(diff <(printf '%s\n' "$old_out") "$T/newb" | head -8 | tr '\n' ' ')"
n_b="$(wc -l < "$T/calls-b" | tr -d ' ')"
[ "$n_b" -le 30 ] && ok "ⓑbig(경로 300개) 묶음 호출 ${n_b}회 ≤ 30" || bad "ⓑbig 묶음 호출 ${n_b}회 > 30 — 경로마다 부르고 있다"

# ⓒ 1회 상한 초과 → 반 쪼개기 재시도 1 → 그래도 넘으면 사유 있는 REJECT (항목 1개까지 쪼갠다 = «묶음 1»)
mksmall s2
OUT="$(FT_CHERRY_LIM_S=1 PATH="$T/bin:$PATH" REAL_GIT="$REAL_GIT" FT_SLOW_WHEN="--no-walk" FT_SLOW_SLEEP=2 bash "$G" main nano/x --repo "$R" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'REJECT cherry 게이트 — 커밋 1초 초과(묶음 1 · 마지막 ' && ok "ⓒ상한 초과 = 사유 있는 REJECT(쪼개도 넘음)" \
  || bad "ⓒ시간 초과 REJECT 가 아니다(rc=$RC) :: ${OUT:0:400}"

# ⓓ 진행 파일 — 끝난 묶음은 다시 묻지 않는다(같은 결과 · 그 묶음 git 호출 0)
prog="$T/prog.txt"
OUT="$(FT_CHERRY_PROGRESS="$prog" bash "$G" main nano/x --repo "$R" 2>&1)"; RC1=$?; out1="$OUT"
: > "$T/calls-d"
OUT="$(FT_CHERRY_PROGRESS="$prog" PATH="$T/bin:$PATH" REAL_GIT="$REAL_GIT" FT_GIT_LOG="$T/calls-d" FT_SLOW_WHEN="--no-walk" FT_SLOW_SLEEP=0 bash "$G" main nano/x --repo "$R" 2>&1)"; RC2=$?
[ "$RC1" = "$RC2" ] && [ "$out1" = "$OUT" ] && ok "ⓓ진행 파일 재호출 → 같은 결과(rc=${RC2})" || bad "ⓓ진행 파일 재호출 결과가 다르다(rc ${RC1}≠${RC2})"
grep -q -- '--no-walk' "$T/calls-d" && bad "ⓓ끝난 묶음을 다시 물었다(--no-walk 재호출)" || ok "ⓓ끝난 묶음은 다시 묻지 않는다(--no-walk 호출 0)"

# ⓔ 기존 시험 · 문법 · /bin/bash 3.2
bash -n "$G" && ok "ⓔbash -n" || bad "ⓔbash -n"
for t in test_cherry_gate_identical_head.sh test_cherry_gate_squash.sh; do
  bash "$HERE/$t" >"$T/$t.out" 2>&1 && ok "ⓔ$t rc=0" || bad "ⓔ$t 실패 :: $(tail -3 "$T/$t.out" | tr '\n' ' ')"
done
/bin/bash "$HERE/test_cherry_gate_identical_head.sh" >"$T/b32.out" 2>&1 && ok "ⓔ/bin/bash 3.2 에서 기존 시험 rc=0" || bad "ⓔ/bin/bash 3.2 실패 :: $(tail -3 "$T/b32.out" | tr '\n' ' ')"

# ⓕ 변이 2종 — 각각 ⓑ·ⓒ 단언을 깨뜨린다
R="$T/biga"   # 커밋 300개 픽스처(§ⓐ 와 같은 것)
: > "$T/calls-m"
FT_CHERRY_BATCH=1 FT_GIT_LOG="$T/calls-m" gitc bash "$G" main nano/x --repo "$R" >/dev/null 2>&1
n_m="$(wc -l < "$T/calls-m" | tr -d ' ')"
[ "$n_m" -gt 20 ] && ok "ⓕ변이(묶음 대신 커밋마다 호출 = FT_CHERRY_BATCH=1) → 호출 ${n_m}회로 ⓑ 단언(≤20) FAIL" \
  || bad "ⓕ변이가 ⓑ 단언을 못 깨뜨린다(${n_m}회 ≤ 20)"
sed 's/\[ "\$d" -lt 1 \]/[ "$d" -lt 0 ]/' "$G" > "$T/gate-nosplit.sh"
grep -q '"\$d" -lt 0' "$T/gate-nosplit.sh" && ok "ⓕ변이본 생성(쪼개기 끔)" || bad "ⓕ변이본 생성 실패"
OUT="$(FT_CHERRY_LIM_S=1 PATH="$T/bin:$PATH" REAL_GIT="$REAL_GIT" FT_SLOW_WHEN="--no-walk" FT_SLOW_SLEEP=2 bash "$T/gate-nosplit.sh" main nano/x --repo "$R" 2>&1)"; RC=$?
printf '%s' "$OUT" | grep -q '묶음 1 ·' && bad "ⓕ쪼개기 끈 변이가 ⓒ 단언을 못 깨뜨린다 :: ${OUT:0:200}" \
  || ok "ⓕ쪼개기 끈 변이 → «묶음 1» 이 아니라 ⓒ 단언 FAIL(rc=$RC)"

echo "---"; [ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED=$fail"; exit 1; }
