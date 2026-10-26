#!/usr/bin/env bash
# test_cherry_gate_batch_r958.sh — r958: ⑤ cherry 게이트의 커밋·경로별 외부 호출을 «묶음 호출» 로 바꾼다.
#   ⓐ(빨강 먼저) «+» 커밋 300개에서 지금 판은 커밋마다 git 을 3회 부른다(외부 호출 수 ∝ 커밋 수 = 70초 초과 REJECT 의 원인) — 새 판은 묶음 상수 회.
#   ⓑ 같은 입력에서 판정 결과(차단·WARN 목록·사유 토큰·stdout 전문)가 지금 판과 같다.  ⓒ 1회가 상한을 넘으면 반으로 쪼개 재시도 1, 그래도 넘으면 사유 있는 REJECT.
#   ⓓ 진행 파일로 다시 부르면 끝난 묶음은 건너뛴다(같은 결과).  ⓔ 기존 시험 ALL PASS · /bin/bash 3.2.  ⓕ 변이 2종이 각각 ⓑ·ⓒ 단언을 깨뜨린다.
#   ⓖ(r2) rename 무변경 이동 = base 판과 같은 REJECT(+ 변이 «rename 검출 켬» → FAIL) · ⓗ(r2) cherry 1회 상한 초과 = 단계 이름 «cherry» 있는 REJECT(+ 변이 «cherry 도우미 밖» → FAIL).
#   ⓘ~ⓚ(r3 · DA⑥ r2 HOLD 2 재설계): ⓘ따옴표·공백·탭·한글·rename 경로 = base 판과 stdout 전문 동일 · ⓙ동사 5종(rev-parse·merge-base·cherry·diff-tree·log) 각각 상한 초과 = 그 동사 이름 REJECT ·
#   ⓚ안전망(통로 밖 맨 호출 0 · 경로 출력 -z 빠짐 0) · 변이 2종(rev-parse 통로 밖 → ⓙ·ⓚ FAIL · -z 뺌 → ⓘ FAIL).
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
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'REJECT cherry 게이트 — 커밋(log) 1초 초과(묶음 1 · 마지막 ' && ok "ⓒ상한 초과 = 사유 있는 REJECT(쪼개도 넘음)" \
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

# ── ⓖ rename 무변경 이동 → REJECT (r958 r2 · DA⑥ r1 반례 1: base 판과 같은 차단 목록) ──────────────
#   rename 을 켜면 원시 줄이 `:…R100\t옛경로\t새경로` = «두 경로가 한 칸» → 없는 이름 하나가 «sup» 로 통과했다(HEAD b948b3a4 실측).
mkrename() {  # <이름> → $R : feat=main 에서 app/a.py 만 있고, 나노는 내용 그대로 app/b.py 로 옮긴 커밋 1개
  R="$T/$1"; git init -q -b main "$R"
  mkdir -p "$R/app"; printf 'A0\n' > "$R/app/a.py"; git -C "$R" add -A; git -C "$R" commit -qm base
  git -C "$R" checkout -q -b nano/x; git -C "$R" mv app/a.py app/b.py; git -C "$R" commit -qm "rename no content"
  git -C "$R" checkout -q main; printf 'x\n' > "$R/app/m.py"; git -C "$R" add -A; git -C "$R" commit -qm "feat moved"
}
mkrename ren1
run "$OLD"; old_out="$OUT" old_rc="$RC"
run "$G";   new_out="$OUT" new_rc="$RC"
[ "$old_rc" -eq 1 ] && ok "ⓖbase 판은 rename 무변경 이동을 REJECT 한다(rc=1)" || bad "ⓖbase 판 기준값이 REJECT 가 아니다(rc=${old_rc}) — 픽스처 확인"
[ "$new_rc" -eq 1 ] && same_block "$old_out" "$new_out" && ok "ⓖrename 무변경 이동 = base 와 같이 REJECT(rc=1 · 차단·WARN 목록 같음)" \
  || bad "ⓖrename 무변경 이동을 통과시켰다(rc=${new_rc} · base rc=${old_rc}) :: ${new_out:0:400}"
#   r3: 경로가 NUL 프레임이라 rename 을 켜도 «없는 이름» 이 안 생긴다(구조가 닫음 — 그게 r3 의 요점). 그래서 변이는 «경로 대조를 끄는» 쪽으로 둔다
#   = need(미반영) 를 sup(반영됨) 로 바꿔 치면 미랜딩 이동이 통과한다 → ⓖ 단언이 깨진다(판정 규칙이 실제로 값을 잡는지의 증거).
cp "$KIT/ft_git_capped.py" "$T/" 2>/dev/null   # 변이본은 $T 에 살아 도우미를 못 찾는다 — 변이 1개만 다르게 둔다
sed -e 's/emit("need", p, t\[0\], t\[1\])/emit("sup", p)/' -e 's/emit("miss", p, "(tip 삭제/emit("sup", p, "(tip 삭제/' "$G" > "$T/gate-needoff.sh"
grep -q 'emit("sup", p)$' "$T/gate-needoff.sh" && ok "ⓖ변이본 생성(경로 대조 끔 = need·miss 를 sup 로)" || bad "ⓖ변이본 생성 실패"
OUT="$(bash "$T/gate-needoff.sh" main nano/x --repo "$R" 2>&1)"; MRC=$?
[ "$MRC" -eq 1 ] && bad "ⓖ경로 대조를 끈 변이가 ⓖ 단언을 못 깨뜨린다(rc=1)" \
  || ok "ⓖ경로 대조를 끈 변이 → rc=${MRC} 통과로 ⓖ 단언 FAIL(미반영 경로가 sup 로 새는 자리)"

# ── ⓗ cherry 1회 상한 초과 → 단계 이름 있는 REJECT (r958 r2 · DA⑥ r1 반례 2) ──────────────────
#   `git cherry` 만 상한 도우미 밖이면 «cherry 1회가 8초» 인 입력에서 9.22초 뒤 rc0 OK(+ 0) = 조용한 통과(계약 ② 위반).
mksmall s3
OUT="$(FT_CHERRY_LIM_S=1 PATH="$T/bin:$PATH" REAL_GIT="$REAL_GIT" FT_SLOW_WHEN="cherry" FT_SLOW_SLEEP=2 bash "$G" main nano/x --repo "$R" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'REJECT cherry 게이트 — cherry 1초 초과(묶음 1 · 마지막 ' \
  && ok "ⓗcherry 1회 상한 초과 = 단계 이름 «cherry» 있는 REJECT(조용한 통과 0)" \
  || bad "ⓗcherry 상한 초과가 사유 있는 REJECT 가 아니다(rc=$RC) :: ${OUT:0:400}"
sed 's/G cherry "\$CG_TMPV" cherry/git -C "\$REPO" cherry/' "$G" > "$T/gate-nocherrycap.sh"
grep -q 'git -C "\$REPO" cherry' "$T/gate-nocherrycap.sh" && ok "ⓗ변이본 생성(cherry 를 통로 밖으로)" || bad "ⓗ변이본 생성 실패"
OUT="$(FT_CHERRY_LIM_S=1 PATH="$T/bin:$PATH" REAL_GIT="$REAL_GIT" FT_SLOW_WHEN="cherry" FT_SLOW_SLEEP=2 bash "$T/gate-nocherrycap.sh" main nano/x --repo "$R" 2>&1)"; MRC=$?
printf '%s' "$OUT" | grep -q 'cherry 1초 초과' && bad "ⓗcherry 도우미 밖 변이가 ⓗ 단언을 못 깨뜨린다 :: ${OUT:0:200}" \
  || ok "ⓗcherry 도우미 밖 변이 → «cherry 초과» REJECT 없음 = ⓗ 단언 FAIL(rc=${MRC})"

# ── ⓘ(r3) DA⑥ r2 반례 1 + 꼴 묶음 — 따옴표·공백·탭·한글·rename 경로가 base 판과 «stdout 전문» 같다 ────────────
#   r2 판은 경로를 줄 단위로 파싱해 `a"b.py` 가 git 의 따옴표 표기(`"a\"b.py"`)로 들어와 트리의 실제 이름과 안 맞았고, 그래서 미랜딩 코드가 `sup` 로 통과했다.
mkweird() {  # <이름> → $R : 코드 경로 5종(따옴표·공백·탭·한글·rename 따옴표) → base 판도 REJECT
  R="$T/$1"; git init -q -b main "$R"
  w app/a.py a0; w design/card.md c0; cm base
  git -C "$R" checkout -q -b nano/x
  w 'app/a"b.py' q1; w 'app/c d.py' sp; w "app/e	f.py" tab; w 'app/g한글.py' kr; w 'app/r"q.py' rq
  cm "weird add"
  git -C "$R" mv 'app/r"q.py' 'app/s"q.py'; git -C "$R" commit -qm "weird rename"
  git -C "$R" checkout -q main; w app/m.py m; cm "feat moved"
}
mkweirdpass() {  # 통과 쪽 꼴 — nano 가 넣은 따옴표 경로 내용이 feat 에 이미 같은 채로 들어가 있음
  R="$T/$1"; git init -q -b main "$R"
  w app/a.py a0; cm base
  git -C "$R" checkout -q -b nano/x; w 'app/x"y.py' C1; w 'design/d"oc.md' D1; cm "nano weird"
  git -C "$R" checkout -q main; w 'app/x"y.py' C1; cm "feat same"; w 'design/z"z.md' z; cm "feat doc"
}
for f in mkweird mkweirdpass; do
  "$f" "${f}1"
  run "$OLD"; old_out="$OUT" old_rc="$RC"
  run "$G";   new_out="$OUT" new_rc="$RC"
  [ "$old_rc" = "$new_rc" ] && [ "$old_out" = "$new_out" ] && ok "ⓘ${f} 판정 전문 동일(rc=${new_rc})" \
    || bad "ⓘ${f} 판정이 다르다(rc ${old_rc}≠${new_rc}) :: $(diff <(printf '%s\n' "$old_out") <(printf '%s\n' "$new_out") | head -6 | tr '\n' ' ')"
done
printf '%s' "$new_out" >/dev/null
run "$G" 2>/dev/null   # 마지막 픽스처(mkweirdpass) 기준
mkweird mkweirdchk; run "$G"
printf '%s' "$OUT" | grep -qF 'app/a"b.py' && ok "ⓘ따옴표 경로가 목록에 «원문 그대로» 나온다" || bad "ⓘ따옴표 경로가 목록에 없다 :: ${OUT:0:300}"

# ── ⓙ(r3) 동사마다 상한 초과 → 그 동사 이름 있는 REJECT (계약 ②: 조용한 통과 0) ───────────────────────
#   r1 은 cherry, r2 는 rev-parse 만 상한 밖이었다. r3 는 «전부 한 통로» 라 동사 5종이 각각 잡혀야 한다(상한은 시험용으로 1초로 줄인다).
mkplain() {  # 충돌 없이 merge-tree delta 가 생기는 최소 꼴 — diff-tree·merge-base 까지 닿는다
  R="$T/$1"; git init -q -b main "$R"
  w app/a.py a0; w design/card.md c0; cm base
  git -C "$R" checkout -q -b nano/x; w app/n.py n; cm "nano code"
  git -C "$R" checkout -q main; w app/f.py f; cm "feat code"
}
#   ★픽스처 폴더 이름에 동사 이름을 넣지 않는다★ — 가짜 git 이 «명령줄 전체» 를 패턴 대조하므로 경로에 그 글자가 있으면 모든 호출이 느려진다(실측).
_n=0
for v in rev-parse merge-base cherry diff-tree log; do
  _n=$((_n + 1)); mkplain "slow$_n"
  OUT="$(FT_CHERRY_LIM_S=1 PATH="$T/bin:$PATH" REAL_GIT="$REAL_GIT" FT_SLOW_WHEN="$v" FT_SLOW_SLEEP=2 bash "$G" main nano/x --repo "$R" 2>&1)"; RC=$?
  [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -qE "^REJECT cherry 게이트 — .*${v}.*1초 초과" \
    && ok "ⓙ${v} 상한 초과 = «${v}» 이름 있는 REJECT" \
    || bad "ⓙ${v} 상한 초과가 «${v}» 이름 있는 REJECT 가 아니다(rc=$RC) :: ${OUT:0:300}"
done

# ── ⓚ(r3) 안전망 — 본문(주석 제외 · 따옴표 글자 제외)에서 «통로 밖 맨 호출 0 · 경로 호출 -z 빠짐 0» ─────────
netsafe() {  # <파일> → 위반 줄들 + 마지막 줄 «N=<위반 수>» · 허용 = cg_git 정의 안의 전달 1줄뿐
  python3 - "$1" <<'PY'
import re, sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")
def strip_q(s):
    out, q, i = [], None, 0
    while i < len(s):
        c = s[i]
        if q:
            if c == q: q = None
            out.append(" ")
        elif c in "\"'":
            q = c; out.append(" ")
        else:
            out.append(c)
        i += 1
    return "".join(out)
wrap = end = -1
for i, l in enumerate(lines):
    if wrap < 0 and re.match(r"\s*cg_git\(\)\s*\{", l): wrap = i
    elif wrap >= 0 and end < 0 and re.match(r"\}\s*$", l): end = i
bad = allowed = 0
for no, raw in enumerate(lines, 1):
    if raw.lstrip().startswith("#"):
        continue
    s = strip_q(raw)
    if re.search(r"(?<![A-Za-z0-9_./-])git[ \t]", s):
        if wrap < no <= end:
            allowed += 1
        else:
            print("BARE %d: %s" % (no, raw.strip())); bad += 1
    if re.search(r"--raw|--name-only|\bdiff-tree\b|\bls-tree\b", s) and " -z" not in s:
        print("NOZ %d: %s" % (no, raw.strip())); bad += 1
if allowed != 1:
    print("WRAP 허용된 전달 줄이 %d개(정확히 1 이어야 한다)" % allowed); bad += 1
print("N=%d" % bad)
PY
}
outn="$(netsafe "$G")"; [ "$(printf '%s\n' "$outn" | tail -1)" = "N=0" ] && ok "ⓚ통로 밖 맨 호출 0 · 경로 호출 -z 빠짐 0 · 통로 정의 안 전달 1" \
  || bad "ⓚ안전망 위반 :: $(printf '%s\n' "$outn" | grep -v '^N=' | head -4 | tr '\n' ' ')"

# ── 변이(r3) — ①rev-parse 하나를 통로 밖으로 → ⓙrev-parse · ⓚ FAIL ②경로 출력 -z 빼기 → ⓘ FAIL ──────────────
sed 's|G rev-parse /dev/null rev-parse|git -C "$REPO" rev-parse|g' "$G" > "$T/gate-baregit.sh"
grep -q 'git -C "$REPO" rev-parse' "$T/gate-baregit.sh" && ok "변이본 생성(rev-parse 를 통로 밖으로)" || bad "변이본 생성 실패(rev-parse)"
outn="$(netsafe "$T/gate-baregit.sh")"; [ "$(printf '%s\n' "$outn" | tail -1)" = "N=0" ] \
  && bad "변이 «rev-parse 통로 밖» 이 ⓚ 를 못 깨뜨린다" || ok "변이 «rev-parse 통로 밖» → ⓚ 위반 검출(ⓚ 단언 FAIL)"
mkplain s_mut; R="$T/s_mut"
OUT="$(FT_CHERRY_LIM_S=1 PATH="$T/bin:$PATH" REAL_GIT="$REAL_GIT" FT_SLOW_WHEN=rev-parse FT_SLOW_SLEEP=2 bash "$T/gate-baregit.sh" main nano/x --repo "$R" 2>&1)"; MRC=$?
printf '%s' "$OUT" | grep -qE 'rev-parse.*1초 초과' && bad "변이 «rev-parse 통로 밖» 이 ⓙrev-parse 를 못 깨뜨린다" \
  || ok "변이 «rev-parse 통로 밖» → ⓙrev-parse 단언 FAIL(rc=${MRC} · 상한 초과 REJECT 없음)"
sed 's/ -z "\$@"; }/ "\$@"; }/' "$G" > "$T/gate-noz.sh"
grep -q -- '-z "\$@"' "$T/gate-noz.sh" && bad "변이본 생성 실패(-z 가 그대로)" || ok "변이본 생성(커밋 묶음 -z 뺌)"
mkweird nz1; R="$T/nz1"
OUT="$(bash "$T/gate-noz.sh" main nano/x --repo "$R" 2>&1)"; MRC=$?
$( bash "$OLD" main nano/x --repo "$R" >/dev/null 2>&1 ); ORC=$?
[ "$MRC" = "$ORC" ] && bad "변이 «-z 뺌» 이 ⓘ 단언을 못 깨뜨린다(둘 다 rc=$MRC)" \
  || ok "변이 «-z 뺌» → rc=${MRC}(base rc=${ORC}) 로 ⓘ 단언 FAIL(따옴표 경로가 새는 자리)"

echo "---"; [ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED=$fail"; exit 1; }
