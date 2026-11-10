#!/usr/bin/env bash
# test_scratch_reg_rows_r1032.sh — r1032: ft-scratch-repo.sh reg_rows() = «등록부 전체 1회 세기»(줄마다 grep 2회 → awk 1회)
#   골: 쌓인 사본을 지우는 --sweep 1회가 70초 예산에 후보 7개만 보고 삭제 0 이던 것 — G5(지우기 직전 확인)가 후보마다 부르는 reg_rows 가
#       등록부 약 640줄 × 2 grep(외부 명령 1270회 · 1회 약 7초)이었다. 한 번만 세게 바꾼다.
#   ⓐ 새 reg_rows = 옛 reg_rows 와 «같은 줄 집합·같은 개수»(R1 한 등록부 중복 · R2 양쪽 1줄 · 한쪽만 · 빈 줄·공백 줄)
#   ⓑ 못 읽은 등록부(폴더) = REG_BAD=1 = 모름 — 함수 수준 · 실 SUT --sweep 수준(ERROR 1줄 · 삭제 0 · 후보 생존) 둘 다(R3)
#   ⓒ 600줄 등록부에서 reg_rows 1회 ≤ 1초 ∧ 외부 명령 수가 줄 수에 비례하지 않는다(60줄과 600줄의 cat·awk·grep 호출 수가 같다 · R5)
#   M  변이 «옛 판(줄마다 grep 2회) 복원» = ⓒ 만 빨강(기대 칸만 FAIL 일 때 검출)
# 임시 폴더·임시 등록부만 쓴다 — 실 하네스 상태·실 사본 삭제 0(임시 폴더 안만).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
SUT="${FT_SUT:-$REPO/bin/ft-scratch-repo.sh}"
CASES="${FT_CASES:-all}"; MUT="${FT_MUT:-new}"   # FT_MUT=old = 변이(옛 판 몸통으로 같은 시험을 돌린다)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
want() { case "$CASES" in all) return 0;; *"$1"*) return 0;; esac; return 1; }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/state" "$T/reg" "$T/cbin"
TAB=$'\t'

# ── 공통 하네스: SUT(또는 옛 판)의 reg_rows 몸통만 꺼내 cap·reg_list 스텁과 함께 eval ───────────────────
body() { awk -v f="$1" '$0 ~ "^"f"\\(\\) \\{" {on=1} on{print} on && /^}/ {exit}' "$SUT"; }   # SUT 의 함수 몸통(닫는 줄 «}» 이 1열)
cat > "$T/old_rows.sh" <<'OLD'
reg_rows() {   # 옛 판(r996) — 기준판 대조용. 뜻: 등록부별 등장 횟수의 최대만 · 한 등록부 안 중복은 그대로 · 빈 줄 0
  local f rows line n1 n2 t="$STATE/.regrows.$$"
  ROWS=""; REG_BAD=0
  reg_list
  : > "$t" 2>/dev/null || { ROWS=""; REG_BAD=1; return 0; }
  for f in $REGS; do
    [ -e "$f" ] || continue
    cap rows cat -- "$f" || { REG_BAD=1; continue; }
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      cap n1 grep -c -x -F -e "$line" -- "$f"; n1="${n1:-0}"
      cap n2 grep -c -x -F -e "$line" -- "$t"; n2="${n2:-0}"
      isnum "$n1" && isnum "$n2" || { REG_BAD=1; continue; }
      [ "$n1" -gt "$n2" ] || continue
      printf '%s\n' "$line" >> "$t"
    done <<EOF
$rows
EOF
  done
  cap ROWS cat -- "$t"; rm -f -- "$t" 2>/dev/null
  return 0
}
OLD
if [ "$MUT" = old ]; then cp "$T/old_rows.sh" "$T/impl.sh"   # 변이 = 옛 판(줄마다 grep 2회) 복원
else
  { body reg_rows || true; } > "$T/impl.sh"
  [ -s "$T/impl.sh" ] && grep -q '^}' "$T/impl.sh" || { bad "SUT 에서 reg_rows 몸통을 못 꺼냄"; echo "(1 failed)"; exit 1; }
fi
cap() { local __cap_v="$1" __cap_o __cap_r; shift; __cap_o="$("$@")"; __cap_r=$?; printf -v "$__cap_v" '%s' "$__cap_o"; return "$__cap_r"; }
isnum() { case "$1" in ''|*[!0-9]*) return 1;; esac; }
reg_list() { :; }   # REGS 는 부르는 쪽이 정한다(등록부 찾기 = reg_list 는 이 카드 범위 밖 · 0.3초)
run_rows() { # <몸통 파일> <REGS> → "BAD=<n>" + ROWS 한 줄씩 · 실패 rc 는 그대로
  ( set +u
    REGS="$2"; ROWS=""; REG_BAD=0; STATE="$T/state"
    eval "$(cat "$1")" || exit 3
    reg_rows
    printf 'BAD=%s\n' "$REG_BAD"
    [ -z "$ROWS" ] || printf '%s\n' "$ROWS" )
}
rows_of() { run_rows "$1" "$2" | awk 'NR>1' | sort; }

# ── 등록부 3꼴: r1 = 한 등록부 안 중복(R1) · r2·r3 = 양쪽에 같은 줄(R2) · r4 = 한쪽만 · r5 = 빈 줄·공백 줄 섞임 ──
P="$T/scratch/repo-aaaaaaaa-1-1"; Q="$T/scratch/repo-bbbbbbbb-2-2"; R="$T/scratch/repo-cccccccc-3-3"
printf '%s\town-a\t100\t%s\n%s\town-a\t100\t%s\n' "$P" "$T/scratch" "$P" "$T/scratch" > "$T/reg/r1.tsv"
printf '%s\town-b\t200\t%s\n' "$Q" "$T/scratch" > "$T/reg/r2.tsv"
printf '%s\town-b\t200\t%s\n' "$Q" "$T/scratch" > "$T/reg/r3.tsv"
printf '%s\town-c\t300\t%s\n' "$R" "$T/scratch" > "$T/reg/r4.tsv"
printf '\n%s\town-d\t400\t%s\n   \n' "$R" "$T/scratch" > "$T/reg/r5.tsv"
mkdir -p "$T/reg/unreadable"   # R3 꼴: «폴더» = 읽기 실패(권한 조작 0 · 하드 룰 19)

# ── ⓐ 새 = 옛 (같은 줄 집합·같은 개수) ──────────────────────────────────────────────────
if want ⓐ; then
  a_i=0
  for spec in "R1 한 등록부 중복|$T/reg/r1.tsv" "R2 장부 둘 같은 줄|$T/reg/r2.tsv $T/reg/r3.tsv" \
              "한쪽만|$T/reg/r4.tsv" "섞임(중복+양쪽+한쪽)|$T/reg/r1.tsv $T/reg/r2.tsv $T/reg/r3.tsv $T/reg/r4.tsv" \
              "빈 줄·공백 줄|$T/reg/r5.tsv"; do
    a_i=$((a_i+1)); name="${spec%%|*}"; regs="${spec#*|}"
    OLD="$(rows_of "$T/old_rows.sh" "$regs")"; NEW="$(rows_of "$T/impl.sh" "$regs")"
    [ "$OLD" = "$NEW" ] && ok "ⓐ$a_i $name = 옛 판과 같은 줄 집합·개수($(printf '%s\n' "$NEW" | grep -c .)줄)" \
      || bad "ⓐ$a_i $name 옛≠새 [옛=$(printf '%s' "$OLD" | tr '\n' ';') 새=$(printf '%s' "$NEW" | tr '\n' ';')]"
  done
  # R1 = 2줄 그대로(중복이 남아 G5 «정확히 1줄 아님» 거절 유지) · R2 = 1줄
  [ "$(run_rows "$T/impl.sh" "$T/reg/r1.tsv" | grep -c "^$P$TAB")" = 2 ] && ok "ⓐ R1 한 등록부 안 중복 = ROWS 2줄(G5 거절 유지)" || bad "ⓐ R1 중복 개수 틀림"
  [ "$(run_rows "$T/impl.sh" "$T/reg/r2.tsv $T/reg/r3.tsv" | grep -c "^$Q$TAB")" = 1 ] && ok "ⓐ R2 장부 둘에 같은 줄 = ROWS 1줄(G5 통과 가능)" || bad "ⓐ R2 양쪽 개수 틀림"
fi

# ── ⓑ 못 읽은 등록부 = REG_BAD=1(모름 · 함수 수준) ──────────────────────────────────────
if want ⓑ; then
  OUTB="$(run_rows "$T/impl.sh" "$T/reg/r2.tsv $T/reg/unreadable")"; RCB=$?
  { [ "$RCB" = 0 ] && printf '%s\n' "$OUTB" | grep -qx 'BAD=1' && printf '%s\n' "$OUTB" | grep -q "^$Q$TAB"; } \
    && ok "ⓑ 못 읽은 등록부 = REG_BAD=1(읽힌 등록부 줄은 그대로)" || bad "ⓑ rc=$RCB [$OUTB]"
  [ "$(rows_of "$T/impl.sh" "$T/reg/r2.tsv $T/reg/unreadable")" = "$(rows_of "$T/impl.sh" "$T/reg/r2.tsv")" ] && ok "ⓑ 못 읽은 등록부는 셈에서 빠질 뿐 다른 줄을 흔들지 않는다" || bad "ⓑ 부분 읽기 결과 틀림"
  # 실 SUT --sweep 수준: ROOT 등록부 자리가 «폴더» = 못 읽음 → ERROR 1줄 · 삭제 0 · 후보 생존
  G="$T/src"; RROOT="$T/R"; SCR="$T/scratch"; TMPD="$T/tmpdir"; BIN="$T/bin"
  mkdir -p "$G" "$RROOT/.fable-team/state" "$SCR" "$TMPD" "$BIN"
  git -C "$G" init -q -b main && echo a > "$G/a.txt" && git -C "$G" add a.txt && git -C "$G" -c user.name=t -c user.email=t@t commit -q -m c1
  printf '#!/bin/sh\n[ "$1" = list-sessions ] || exit 0\nprintf "%%s\\n" live-owner\n' > "$BIN/tmux"
  printf '#!/bin/sh\nprintf "p1\\nczsh\\nfcwd\\nn/\\n"\n' > "$BIN/lsof"
  chmod 755 "$BIN/tmux" "$BIN/lsof"
  CAND="$SCR/repo-12345678-1-1"; mkdir -p "$CAND"   # 지워지면 안 되는 후보(등록부를 못 읽으니 «모름» = 덜 지우는 쪽)
  mkdir -p "$RROOT/.fable-team/state/scratch-repos.tsv"   # 등록부 자리 = 폴더(읽기 실패)
  : > "$RROOT/.fable-team/state/scratch-sweep.armed"; : > "$RROOT/.fable-team/state/scratch-sweep.log"
  OUTS="$(env PATH="$BIN:$PATH" FT_RES_ROOT="$RROOT" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER=live-owner \
    FT_SCRATCH_JUDGE_BUDGET=20 FT_SCRATCH_AGE_MIN=1440 bash "$SUT" --sweep 2>&1)"; RCS=$?
  { [ "$RCS" = 0 ] && printf '%s' "$OUTS" | grep -q 'ERROR 등록부 못 읽음 — 삭제 0' && [ -d "$CAND" ]; } \
    && ok "ⓑ 실 SUT --sweep: 등록부 못 읽음 = ERROR 1줄 · 삭제 0 · 후보 생존" || bad "ⓑ sweep rc=$RCS [$OUTS]"
  rm -rf "$RROOT/.fable-team/state/scratch-repos.tsv"
fi

# ── ⓒ 600줄 등록부 = 1초 안 · 외부 명령 수가 줄 수에 비례하지 않음(60줄과 같다) ──────────────
if want ⓒ; then
  REALS=""; for c in cat awk grep; do REALS="$REALS $c=$(command -v "$c")"; done
  cat > "$T/cbin/cnt" <<EOF
#!/bin/sh
me=\${0##*/}; real=""
for kv in $REALS; do [ "\${kv%%=*}" = "\$me" ] && real="\${kv#*=}"; done
printf '%s\n' "\$me" >> "$T/calls"
exec "\$real" "\$@"
EOF
  chmod 755 "$T/cbin/cnt"; for c in cat awk grep; do ln -sf cnt "$T/cbin/$c"; done
  mkreg() { # <파일> <줄 수> — 서로 다른 경로 줄(등록부 1개 안 중복 0)
    local f="$1" n="$2" i=0
    : > "$f"
    while [ "$i" -lt "$n" ]; do i=$((i+1)); printf '%s/scratch/repo-%08x-%s-1\town-%s\t100\t%s/scratch\n' "$T" "$i" "$i" "$i" "$T" >> "$f"; done
  }
  mkreg "$T/reg/small.tsv" 60; mkreg "$T/reg/big.tsv" 600
  RGREP="$(command -v grep)"
  counts() { # <등록부…> → "cat=<n> awk=<n> grep=<n>" · 호출 수(세는 grep 은 대역 밖 실제 경로)
    : > "$T/calls"; run_rows "$T/impl.sh" "$*" >/dev/null 2>&1
    printf 'cat=%s awk=%s grep=%s\n' "$("$RGREP" -cx cat "$T/calls" || true)" "$("$RGREP" -cx awk "$T/calls" || true)" "$("$RGREP" -cx grep "$T/calls" || true)"
  }
  CS="$(PATH="$T/cbin:$PATH" counts "$T/reg/small.tsv")"; CB="$(PATH="$T/cbin:$PATH" counts "$T/reg/big.tsv")"
  { [ "$CS" = "$CB" ] && [ "$(printf '%s' "$CB" | awk '{print $3}')" = "grep=0" ]; } \
    && ok "ⓒ 외부 명령 수가 줄 수에 비례하지 않는다 — 60줄·600줄 모두 $CB" \
    || bad "ⓒ 60줄[$CS] ≠ 600줄[$CB] (줄마다 grep 2회 = 비례)"
  # 600줄 속에 6줄만 남기고 나머지를 «같은 줄» 로 채운 경우에도 awk 1회(내용이 늘어도 호출은 그대로)
  T0="$(date +%s)"; OUTT="$(run_rows "$T/impl.sh" "$T/reg/big.tsv")"; T1="$(date +%s)"; EL=$((T1-T0))
  { [ "$EL" -le 1 ] && [ "$(printf '%s\n' "$OUTT" | grep -c "^$T/scratch/repo-")" = "600" ]; } \
    && ok "ⓒ 600줄 등록부 reg_rows 1회 = ${EL}초 · ROWS 600줄(빈 줄 0)" \
    || bad "ⓒ 600줄 ${EL}초 · ROWS $(printf '%s\n' "$OUTT" | grep -c "^$T/scratch/repo-")줄"
  # 지우는 길 규칙: 이 함수 안에 rc 를 안 보는 `$(`·백틱·파이프 0(문자열로도 확인 — ⓨ 기계 검사와 별개로 여기서도)
  { body reg_rows | grep -vE '^[[:space:]]*#' | sed -E 's/[[:space:]]+# .*$//' | grep -qvE '\$\([^(]|<\(|`| \| '; } \
    && ok "ⓒ reg_rows 안 rc 안 보는 \`\$(\`·백틱·파이프 0" || bad "ⓒ reg_rows 에 rc 안 보는 꼴"
  grep -q 'regrows\.\$\$' "$SUT" && bad "ⓒ 옛 임시 파일(\$STATE/.regrows.\$\$) 가 남음" || ok "ⓒ 옛 임시 파일(.regrows.\$\$) 0(한 번에 세므로 필요 없음)"
fi

# ── M 변이 — 옛 판(줄마다 grep 2회) 복원이면 ⓒ 만 빨강 ────────────────────────────────────
if want M; then
  FT_MUT=old FT_CASES='ⓐ ⓑ ⓒ' bash "${BASH_SOURCE[0]}" > "$T/mut.log" 2>&1; mr=$?
  nf="$(grep -c '^FAIL' "$T/mut.log")"; nx="$(grep -cE '^FAIL ⓒ' "$T/mut.log")"
  { [ "$mr" != 0 ] && [ "$nf" -gt 0 ] && [ "$nf" = "$nx" ]; } \
    && ok "M 변이(옛 판 복원) = ⓒ 만 빨강(${nf}칸 · rc=$mr)" \
    || bad "M 변이가 기대 칸으로 안 잡힘(rc=$mr · FAIL $nf · ⓒ $nx) $(grep '^FAIL' "$T/mut.log" | head -2 | tr '\n' ' ')"
  printf 'FAIL ⓒ 대조(옛 판 600줄) [변이 자식 — 기대 칸]\n' > /dev/null
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
