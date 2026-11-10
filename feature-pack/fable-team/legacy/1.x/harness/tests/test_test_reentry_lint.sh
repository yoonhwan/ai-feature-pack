#!/usr/bin/env bash
# test_test_reentry_lint.sh — r1041 ft-test-reentry-lint.sh: «시험이 자기 파일을 가드 없이 다시 부르는 줄» 을 rc3 으로 막는다.
#   r1132 ⓜ: «기준판을 떠다니는 이름(HEAD·origin/…·main)으로 꺼내는 줄» 도 FLOATBASE rc3 (반례 R1~R4·R7 + 변이 1 · R5·R6 = test_merge_land_baseline_paths_r1132.sh)
#   계기: 10-28 나노 r1038 시험의 변이 칸이 자기 파일(BASH_SOURCE)을 다시 불러 무한 재귀 → 사용자 프로세스 상한 도달, 전 좌석 셸 fork 실패.
# 시험은 표본 «파일 글자» 만 본다 — 표본을 실행하지 않고(그러면 이 카드의 사고를 재현한다) 실제 프로세스 증가 0 · tmux·네트워크 0.
# 상한: 이 시험 자신은 70초 안에 끝나고 자기 자신을 다시 부르지 않는다(하드 룰 22 · r1041).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
LINT="$BIN/ft-test-reentry-lint.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:200}";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT

bash -n "$LINT" && ok "bash -n lint" || bad "bash -n lint"
cmp -s "$LINT" "$KIT/ft-test-reentry-lint.sh" && ok "키트 사본 cmp 0 lint" || bad "키트 사본 어긋남 lint"
[ -x "$LINT" ] && ok "실행 비트" || bad "실행 비트 없음"

# 표본 — R1 가드 없음 · R2 한 줄 가드 · R2b 여러 줄 가드 · R3 자기 호출 없음 · R4 남의 시험 호출 · R1b 주석 속 자기 호출
cat > "$T/s1_noguard.sh" <<'EOF'
#!/usr/bin/env bash
# 변이 칸 — 자기 파일을 다시 부른다(가드 없음)
bash "$(dirname "${BASH_SOURCE[0]:-$0}")/s1_noguard.sh" --mutate
EOF
cat > "$T/s2_guard.sh" <<'EOF'
#!/usr/bin/env bash
[ -n "${FT_NO_MUTATE:-}" ] && exit 0
bash "$(dirname "${BASH_SOURCE[0]:-$0}")/s2_guard.sh" --mutate
EOF
cat > "$T/s3_multiline_guard.sh" <<'EOF'
#!/usr/bin/env bash
if [ -n "${FT_NO_MUTATE:-}" ]; then
  exit 0
fi
bash "$0" --mutate
EOF
cat > "$T/s4_selfcall_none.sh" <<'EOF'
#!/usr/bin/env bash
bash "$(dirname "${BASH_SOURCE[0]:-$0}")/_helper.sh"
EOF
cat > "$T/s5_other_test.sh" <<'EOF'
#!/usr/bin/env bash
bash "$(dirname "${BASH_SOURCE[0]:-$0}")/test_other.sh"
EOF
cat > "$T/s6_comment_only.sh" <<'EOF'
#!/usr/bin/env bash
# bash "$0" --mutate  ← 주석이면 판정 대상 아님
echo hi
EOF
# bash -c 의 $0 은 «넘긴 인자» 다 — 대상 파일이 아니므로 판정 밖(실사례 tests/test_tmm_group.sh:23)
cat > "$T/s7_bash_c.sh" <<'EOF'
#!/usr/bin/env bash
run() { bash -c 'source "$0" __lib; cat_of "$1"' "$HELPER" "$2"; }
run x
EOF

# ⓐ R1 — 가드 없는 자기 호출 = rc3 · 첫 줄 REENTRY
out="$("$LINT" "$T/s1_noguard.sh" 2>/dev/null)"; rc=$?
eq "$rc" 3 "ⓐ R1 가드 없는 자기 호출 rc3"
eq "$(printf '%s' "$out" | head -1)" "REENTRY $T/s1_noguard.sh:3" "ⓐ 첫 줄 = REENTRY <파일>:<줄>"
# ⓑ R2 — 한 줄 가드 = rc0
out="$("$LINT" "$T/s2_guard.sh" 2>/dev/null)"; rc=$?
eq "$rc" 0 "ⓑ R2 한 줄 가드 rc0"
eq "$out" "OK $T/s2_guard.sh" "ⓑ rc0 출력 = OK <파일>"
# ⓒ R2b — 여러 줄 가드(검사문 + 다음 줄 exit) = rc0
"$LINT" "$T/s3_multiline_guard.sh" >/dev/null 2>&1 && ok "ⓒ R2b 여러 줄 가드 rc0" || bad "ⓒ 여러 줄 가드인데 rc≠0"
# ⓓ R3 — 자기 호출 없음(남을 부름) = rc0
"$LINT" "$T/s4_selfcall_none.sh" >/dev/null 2>&1 && ok "ⓓ R3 자기 호출 없음 rc0" || bad "ⓓ R3 인데 rc≠0"
# ⓔ R4 — 다른 시험 파일을 부르는 줄 = rc0
"$LINT" "$T/s5_other_test.sh" >/dev/null 2>&1 && ok "ⓔ R4 다른 시험 호출 rc0" || bad "ⓔ R4 인데 rc≠0"
# ⓕ 주석 속 자기 호출 = rc0(글자만 있는 줄은 호출이 아니다)
"$LINT" "$T/s6_comment_only.sh" >/dev/null 2>&1 && ok "ⓕ 주석 속 자기 호출 rc0" || bad "ⓕ 주석인데 rc≠0"
# ⓕ-2 bash -c 안의 $0 = 넘긴 인자(대상 파일 아님) → rc0
"$LINT" "$T/s7_bash_c.sh" >/dev/null 2>&1 && ok "ⓕ-2 bash -c 의 \$0 은 판정 밖 rc0" || bad "ⓕ-2 bash -c 인데 rc≠0"
# ⓖ 여러 파일 — 위반 줄이 OK 줄보다 «앞» 에 온다(첫 줄 규칙)
out="$("$LINT" "$T/s2_guard.sh" "$T/s1_noguard.sh" 2>/dev/null)"
eq "$(printf '%s' "$out" | head -1)" "REENTRY $T/s1_noguard.sh:3" "ⓖ 여러 파일일 때 첫 줄이 REENTRY"
has "$out" "OK $T/s2_guard.sh" "ⓖ 통과 파일도 OK 줄로 남는다"
# ⓗ usage rc2 · 없는 파일 rc2 «판정 불가»
"$LINT" >/dev/null 2>&1; eq "$?" 2 "ⓗ 인자 없음 rc2"
out="$("$LINT" "$T/없다.sh" 2>&1)"; rc=$?
eq "$rc" 2 "ⓗ 없는 파일 rc2"
has "$out" "판정 불가" "ⓗ 없는 파일 = «판정 불가» 1줄"
# ⓘ 변이 — 가드 줄만 지운 사본은 rc3 이어야 한다(가드가 판정을 흔든다는 증거) · 같은 «파일 이름» 을 다른 폴더에 둔다(이름이 바뀌면 자기 호출 판정이 달라진다)
mkdir -p "$T/mut"
grep -v '^\[ -n "${FT_NO_MUTATE:-}" \] && exit 0$' "$T/s2_guard.sh" > "$T/mut/s2_guard.sh"
cmp -s "$T/s2_guard.sh" "$T/mut/s2_guard.sh" && bad "ⓘ 변이: 가드 줄이 지워지지 않음"
out="$("$LINT" "$T/mut/s2_guard.sh" 2>/dev/null)"; rc=$?
eq "$rc" 3 "ⓘ 변이(가드 삭제) rc3"
eq "$(printf '%s' "$out" | head -1)" "REENTRY $T/mut/s2_guard.sh:2" "ⓘ 변이 REENTRY 줄 번호"
# ⓙ 실사건 대조 — 이 카드의 사고 시험 꼴(자기 호출 + 가드 0)은 막히고, 팩에 이미 있는 시험은 통과한다
cat > "$T/test_da_rounds_three_r1038.sh" <<'EOF'
#!/usr/bin/env bash
bash "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/test_da_rounds_three_r1038.sh" --mutate
EOF
"$LINT" "$T/test_da_rounds_three_r1038.sh" >/dev/null 2>&1; eq "$?" 3 "ⓙ 실사건 꼴(가드 0 자기 호출) rc3"

# ⓜ r1132 FLOATBASE — 기준판을 떠다니는 이름으로 꺼내면 rc3 · 고정 40hex 통과 · 면제 꼬리는 «면제» 1줄
#   표본 줄은 GIT 로 써 두고 sed 로 git 으로 바꾼다(이 시험 파일 자신이 FLOATBASE 로 걸리지 않게 · ⓛ)
fb() { sed 's/GIT/git/' > "$T/$1"; }
fb f1_origin.sh <<'EOF'
#!/usr/bin/env bash
GIT -C "$TOP" show "origin/main:x/ft-merge-land.sh" > "$T/red.sh"
EOF
fb f2_head.sh <<'EOF'
#!/usr/bin/env bash
BASE="$(GIT show HEAD:./x.sh)"
EOF
fb f3_pinned.sh <<'EOF'
#!/usr/bin/env bash
GIT show "948ae223ae5bc1f9bb871775b9e80158943b7d6b:./x.sh" > "$T/base.sh"
EOF
fb f4_fixture.sh <<'EOF'
#!/usr/bin/env bash
v="$(GIT -C "$ORIGIN" show "main:$1")"   # baseline-ref: ok 픽스처 원격
EOF
fb f7_default.sh <<'EOF'
#!/usr/bin/env bash
TOP=x; BASEREF="${FT_R648_BASE:-origin/main}"
for f in a b; do
  GIT -C "$TOP" show "$BASEREF:${BIN#"$TOP"/}/$f" > "$T/base/$f"
done
EOF
out="$("$LINT" "$T/f1_origin.sh" 2>/dev/null)"; rc=$?
eq "$rc" 3 "ⓜ R1 show origin/main:… > 파일 rc3"
eq "$(printf '%s' "$out" | head -1)" "FLOATBASE $T/f1_origin.sh:2" "ⓜ R1 첫 줄 = FLOATBASE <파일>:<줄>"
out="$("$LINT" "$T/f2_head.sh" 2>/dev/null)"; rc=$?
eq "$rc" 3 "ⓜ R2 HEAD 판을 \$(…) 로 받음 rc3"
eq "$(printf '%s' "$out" | head -1)" "FLOATBASE $T/f2_head.sh:2" "ⓜ R2 FLOATBASE 줄"
out="$("$LINT" "$T/f3_pinned.sh" 2>/dev/null)"; rc=$?
eq "$rc" 0 "ⓜ R3 고정 40hex rc0"; eq "$out" "OK $T/f3_pinned.sh" "ⓜ R3 OK 줄"
out="$("$LINT" "$T/f4_fixture.sh" 2>/dev/null)"; rc=$?
eq "$rc" 0 "ⓜ R4 면제 꼬리 rc0"
has "$out" "면제 FLOATBASE $T/f4_fixture.sh:2 — 픽스처 원격" "ⓜ R4 «면제» 1줄 + 이유"
has "$out" "OK $T/f4_fixture.sh" "ⓜ R4 OK 줄"
out="$("$LINT" "$T/f7_default.sh" 2>/dev/null)"; rc=$?
eq "$rc" 3 "ⓜ R7 기본값에 숨은 이름(\${X:-origin/main}) rc3"
eq "$(printf '%s' "$out" | head -1)" "FLOATBASE $T/f7_default.sh:4" "ⓜ R7 FLOATBASE 줄"
out="$("$LINT" "$T/f3_pinned.sh" "$T/s1_noguard.sh" "$T/f1_origin.sh" 2>&1)"; rc=$?
eq "$rc" 3 "ⓜ 여러 파일 · REENTRY+FLOATBASE 섞임 rc3"
eq "$(printf '%s\n' "$out" | head -2 | tr '\n' '|')" "REENTRY $T/s1_noguard.sh:3|FLOATBASE $T/f1_origin.sh:2|" "ⓜ 위반 줄이 OK 줄보다 앞"
has "$out" "고정 40hex sha" "ⓜ stderr 처방 1줄"
# ⓜ 변이 — FLOATBASE 출력 줄을 지운 사본은 R1 을 통과시킨다(= 검사가 판정을 흔든다는 증거)
python3 - "$LINT" "$T/mut/lint.sh" <<'PY' || bad "ⓜ 변이 대상 없음"
import sys
s = open(sys.argv[1], encoding="utf-8").read(); old = '  printf "FLOATBASE %s:%d\\n", FILENAME, FNR\n'
assert old in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, "", 1))
PY
bash "$T/mut/lint.sh" "$T/f1_origin.sh" >/dev/null 2>&1; eq "$?" 0 "ⓜ 변이(FLOATBASE 검사 삭제) → R1 rc0 = 시험이 잡음"

# ⓚ 정적 — 발주문(_RLX · 두 사본)과 정본(governance §15)에 «ulimit -u · timeout 70 · lint rc0» 줄이 있다
rlx_of() { grep '^_RLX="' "$1"; }
body_of() { grep '^BODY=' "$1"; }
for pair in "추적본:$BIN/ft-nano-spawn.sh" "키트:$KIT/ft-nano-spawn.sh"; do
  lbl="${pair%%:*}"; f="${pair#*:}"
  g="$(rlx_of "$f")"
  [ -n "$g" ] && ok "ⓚ $lbl _RLX 줄 있음" || bad "ⓚ $lbl _RLX 줄 없음"
  has "$g" "ulimit -u" "ⓚ $lbl ulimit -u"
  has "$g" "timeout 70" "ⓚ $lbl timeout 70"
  has "$g" "ft-test-reentry-lint.sh" "ⓚ $lbl lint 도구 이름"
  has "$g" "재진입 표지" "ⓚ $lbl 재진입 표지 요구"
  case "$(body_of "$f")" in *'${_RLX}'*) ok "ⓚ $lbl BODY 에 _RLX 반영";; *) bad "ⓚ $lbl BODY 에 \${_RLX} 없음(발주문에 안 붙는다)";; esac
done
GOV="$REPO/skill/references/main-team-governance.md"
has "$(cat "$GOV")" "arch 격리 보고 = «시험을 직접 돌린 증거»" "ⓚ 정본 §15 제목"
has "$(cat "$GOV")" "ft-test-reentry-lint.sh" "ⓚ 정본에 lint 도구"
has "$(cat "$GOV")" "단계별 초" "ⓚ 정본에 단계별 초"
has "$(cat "$GOV")" "단독 70초" "ⓚ 정본에 시험 상한"
[ "$(grep -c '^_RLX="' "$BIN/ft-nano-spawn.sh")" = 1 ] && ok "ⓚ _RLX 정의 1개" || bad "ⓚ _RLX 정의 중복"
# ⓛ 자기 시험 — 이 두 시험은 자기 자신을 다시 부르지 않는다(lint rc0 = 시험 스스로 위반 0)
"$LINT" "$HERE/test_test_reentry_lint.sh" >/dev/null 2>&1 && ok "ⓛ 이 시험 자신 lint rc0" || bad "ⓛ 이 시험 자신이 자기 호출 위반"
"$LINT" "$HERE/test_resource_watch_proc_count.sh" >/dev/null 2>&1 && ok "ⓛ proc 시험 lint rc0" || bad "ⓛ proc 시험이 자기 호출 위반"

echo "---- fail=$fail"; [ "$fail" -eq 0 ]
