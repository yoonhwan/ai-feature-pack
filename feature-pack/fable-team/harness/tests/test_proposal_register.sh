#!/usr/bin/env bash
# test_proposal_register.sh — ft-proposal-register.sh 시험(설계 §7-2): 가짜 Tank(FT_TANK_CMD = 호출을 파일에 적는 스크립트).
#   확인 실패 5종 → rc≠0 + ★Tank 호출 0회★ · 승인 — 판정 351 → create 1회 + label 1회 · create 실패 → label 0회 · --check → 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REG="$HERE/../../scripts/harness-install/proposal/ft-proposal-register.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$REG" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export TANK_LOG="$T/tank.log"
cat > "$T/fake-tank.sh" <<'EOF'
#!/usr/bin/env bash
echo "$1" >> "$TANK_LOG"
case "$1" in
  create) [ -n "${TANK_FAIL_CREATE:-}" ] && { echo "boom" >&2; exit 1; }; echo "OK as=byz-tank create — PAIR issue=#901 manager=x";;
  label)  [ -n "${TANK_FAIL_LABEL:-}" ] && exit 1; echo "OK as=byz-tank label $2";;
esac
EOF
export FT_TANK_CMD="bash $T/fake-tank.sh"
calls() { [ -f "$TANK_LOG" ] && wc -l < "$TANK_LOG" | tr -d ' ' || echo 0; }

# mk <상태 머리줄> <검증 본문|-> [추가 본문줄] → 제안서 경로
mk() {
  local f="$T/p-$RANDOM.md"
  { echo '# 제안서 — 줄바꿈 CSS'; echo "- 상태: $1"; echo; echo '## 결론'; echo '한 줄이면 된다.'
    [ "$2" != "-" ] && { echo; echo '## 검증'; printf '%b\n' "$2"; }
    [ -n "${3:-}" ] && { echo; echo "$3"; }; } > "$f"
  echo "$f"
}
GOODV='화면에서 줄이 단어 중간에서 안 끊긴다.'

fails() {  # <이름> <파일> — rc≠0 + Tank 호출 0회
  : > "$TANK_LOG"
  local out rc; out="$(bash "$REG" "$2" --apply 2>&1)"; rc=$?
  local n; n="$(calls)"
  echo "    [$1] rc=$rc · Tank 호출 ${n}회 · $(echo "$out" | head -1)"
  [ $rc -ne 0 ] && [ "$n" = 0 ] && ok "$1 → rc≠0 · Tank 호출 0회" || bad "$1 rc=$rc 호출 ${n}회"
}
fails "머리줄 초안"            "$(mk '초안' "$GOODV")"
fails "머리줄 컨펌 대기"        "$(mk '컨펌 대기' "$GOODV")"
fails "머리줄 수정 요청 r1"     "$(mk '수정 요청 r1' "$GOODV")"
fails "머리줄 폐기 — 판정 9"    "$(mk '폐기 — 판정 9' "$GOODV")"
fails "「승인 — 판정 」 번호 없음" "$(mk '승인 — 판정 ' "$GOODV")"
fails "승인인데 Issue #12 이미 있음" "$(mk '승인 — 판정 351' "$GOODV" '- Issue #12 등록됨')"
fails "승인인데 ## 검증 칸 없음"   "$(mk '승인 — 판정 351' '-')"
fails "승인인데 ## 검증 빈 칸"     "$(mk '승인 — 판정 351' '\n  \n')"
P_DUP="$T/dup-status.md"
{ echo '# 제안서 — 줄바꿈 CSS'; echo '- 상태: 승인 — 판정 351'; echo '- 상태: 폐기 — 판정 352'; echo; echo '## 결론'; echo '한 줄이면 된다.'; echo; echo '## 검증'; echo "$GOODV"; } > "$P_DUP"
fails "머리 상태 줄 2개(승인 다음 폐기)" "$P_DUP"
fails "파일 없음"               "$T/없는.md"

: > "$TANK_LOG"
P="$(mk '승인 — 판정 351' "$GOODV")"
out="$(bash "$REG" "$P" --apply 2>&1)"; rc=$?
echo "    $out"
[ $rc -eq 0 ] && [ "$(grep -c '^create$' "$TANK_LOG")" = 1 ] && [ "$(grep -c '^label$' "$TANK_LOG")" = 1 ] && ok "승인 — 판정 351 → create 1회 + label 1회" || bad "승인 경로 rc=$rc 호출=$(tr '\n' ' ' < "$TANK_LOG")"
echo "$out" | grep -qx 'REGISTERED #901 판정 351' && ok "출력 REGISTERED #901 판정 351" || bad "REGISTERED 줄 없음"

: > "$TANK_LOG"
out="$(TANK_FAIL_CREATE=1 bash "$REG" "$P" --apply 2>&1)"; rc=$?
[ $rc -ne 0 ] && [ "$(grep -c '^create$' "$TANK_LOG")" = 1 ] && [ "$(grep -c '^label$' "$TANK_LOG")" = 0 ] && ok "create 실패 → rc≠0 · label 0회" || bad "create 실패 rc=$rc 호출=$(tr '\n' ' ' < "$TANK_LOG")"

: > "$TANK_LOG"
out="$(TANK_FAIL_LABEL=1 bash "$REG" "$P" --apply 2>&1)"; rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q '#901 등록됨 · 라벨 수동' && ok "label 실패 → rc≠0 + 「#901 등록됨 · 라벨 수동」" || bad "label 실패 rc=$rc"

: > "$TANK_LOG"
out="$(bash "$REG" "$P" --check 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$(calls)" = 0 ] && ok "--check → rc=0 · Tank 호출 0" || bad "--check rc=$rc 호출 $(calls)"
: > "$TANK_LOG"
bash "$REG" "$(mk '초안' "$GOODV")" --check >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && [ "$(calls)" = 0 ] && ok "--check 틀린 머리줄 → rc≠0 · Tank 호출 0" || bad "--check 틀린 머리줄 rc=$rc"

: > "$TANK_LOG"
out="$(bash "$REG" "$P" 2>&1)"; rc=$?
[ "$(grep -c '^label$' "$TANK_LOG")" = 0 ] && echo "$out" | grep -q '^DRY ' && ok "--apply 없음 → create(dry-run)만 · label 0" || bad "dry 경로 rc=$rc 호출=$(tr '\n' ' ' < "$TANK_LOG")"

bash "$REG" "$P" --check --apply >/dev/null 2>&1; [ $? -eq 2 ] && ok "--check --apply 동시 → usage rc=2" || bad "--check --apply 동시"

# ★확인 후 파일이 바뀌어도 어긋나지 않는다★ — 1회 읽기: Tank 가 호출되는 «동안» 제안서를 초안으로 바꿔도 이미 읽은 판정으로 등록된다.
P2="$(mk '승인 — 판정 77' "$GOODV")"
cat > "$T/mutating-tank.sh" <<EOF
#!/usr/bin/env bash
[ "\$1" = create ] && sed -i.bak 's/^- 상태: .*/- 상태: 초안/' "$P2"
echo "\$1" >> "$TANK_LOG"; [ "\$1" = create ] && echo "OK PAIR issue=#902"
exit 0
EOF
: > "$TANK_LOG"
out="$(FT_TANK_CMD="bash $T/mutating-tank.sh" bash "$REG" "$P2" --apply 2>&1)"
echo "$out" | grep -qx 'REGISTERED #902 판정 77' && ok "1회 읽기: 읽은 값(판정 77)으로 일관되게 등록" || bad "1회 읽기 $out"

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
