#!/usr/bin/env bash
# test_index_lint_one_repo_r1138.sh — ft-index-lint ⑬ «대상:» 줄 한 카드 = 한 리포 · 라이브 설치 경로 0 (r1138 · 반례 R1~R5 · 변이 2).
#   임시 리포·임시 팩 폴더(FT_PACK_ROOT)·임시 HOME 경로에서만 돈다 · 실 리포 0 · 자기 재호출 0 · 고정 sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; BIN="$HERE/../bin"; LINT="$KIT/ft-index-lint.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in ft-card-target-lib.sh ft-nano-close.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "ⓒ bin·kit 같은 내용 $f" || bad "ⓒ bin·kit 다름 $f"; done
bash -n "$LINT" && bash -n "$KIT/ft-card-target-lib.sh" && ok "bash -n" || bad "bash -n"
LINES="$(awk 'END{print NR}' "$LINT")"; [ "$LINES" -le 160 ] && ok "키트 lint ${LINES}줄 ≤160" || bad "키트 lint ${LINES}줄 > 160"
grep -q 'ft_card_target_side "\$pk" "\$t"' "$BIN/ft-nano-close.sh" && grep -q 'ft_card_targets "\${CARD_READ:-}"' "$BIN/ft-nano-close.sh" \
  && ok "ⓒ 닫기 ⑥ 가 공용 함수(ft_card_targets·ft_card_target_side)를 부른다 — 두 벌 0" || bad "ⓒ 닫기 ⑥ 공용 함수 호출 없음"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q . || { echo "FAIL git init"; exit 1; }
mkdir -p design src pack/bin byz/hooks
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| planner | `design/planner/` | p | 현역 |\n' > design/TEAMS.md
G1='골 첫 줄 시험용 문장이다.'; G2='골 둘째 줄 시험용 문장이다.'; G3='골 셋째 줄 시험용 문장이다.'
printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > goal.txt
echo '원장 본문: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > design/LEDGER.md
printf 'l1\n' > src/target.sh
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1
git update-ref refs/remotes/origin/main HEAD
PK="$(cd "$T/pack" && pwd -P)"; BYZ="$(cd "$T/byz" && pwd -P)"; LIVE="$(cd "$T" && pwd -P)/home/.claude/fable-team/live/1.1.255/bin/x.sh"
export FT_GOAL_LINES_FILE="$T/goal.txt" FT_GOAL_LEDGER="design/LEDGER.md" FT_PACK_ROOT="$T/pack"
unset FT_CARD_REQUIRE_PREVERIFY

mkc() {  # mkc <이름> <머리 줄들(\n)> — 카드 경로 출력
  local f="$T/$1.md"
  { echo "# 인덱스: $1"; echo '- 제안서: 없음 — 시험 카드'; printf '%b\n' "$2"; echo "## 골 원문"; printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3"
    echo "## 골좌표"; echo '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」'
    echo "## 배경"; echo '시험 카드.'
    echo "## 구현 범위"; echo '1. src/target.sh 수정'
    echo "## 완료 조건"; echo '- 시험 통과.'
    echo "## 계약↔시험 대응표"; echo '| 계약 | 시험 |'; echo '|---|---|'; echo '| ① 시험 | ⓐ 시험 |'
    echo "## 상태"; echo '- 시험'; } > "$f"
  echo "$f"
}
run() { ( cd "$T" && FT_CARD_GATE_STRICT_FROM=2099-01-01 bash "${2:-$LINT}" "$1" 2>&1 ); }
MIX='한 카드 = 한 리포 — 대상에 팩·BYZ 경로가 섞임'; LIV='대상에 라이브 설치 경로 — 팩 경로(feature-pack/…)로 쓰고 라이브는 «- 설치:» 줄로'
expect_ok()  { local out rc; out="$(run "$1" "${3:-}")"; rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -q '^OK ' && ok "$2" || bad "$2 → rc=$rc $out"; }
expect_rej() { local out rc n; out="$(run "$1")"; rc=$?; n="$(echo "$out" | grep -c "^  - ")"; [ $rc -eq 1 ] && echo "$out" | grep -qF "  - $3" && [ "$n" = 1 ] && ok "$2" || bad "$2 → rc=$rc n=$n $out"; }

R1="$(mkc r1 "- 대상: $PK/bin/x.sh · 시험 tests/t.sh(신설)")"
R2="$(mkc r2 "- 대상: $BYZ/hooks/y.sh")"
R3="$(mkc r3 "- 대상: $PK/bin/x.sh · $BYZ/hooks/y.sh")"
R4="$(mkc r4 "- 대상: $PK/bin/x.sh\n- 기록(BYZ 훅 y): $BYZ/hooks/y.sh")"
R5="$(mkc r5 "- 대상: $LIVE 의 팩 원본(팩 feature-pack/fable-team/harness/bin/x.sh)\n- 설치: 있음 — $LIVE cmp0")"
R5B="$(mkc r5b "- 대상: $PK/bin/x.sh\n- 설치: 있음 — $LIVE cmp0")"
R0="$(mkc r0 "- 대상: feature-pack/fable-team/harness/bin/x.sh(상대 경로뿐)")"

expect_ok  "$R1"  "ⓐ R1 대상 = 팩 경로만 → OK"
expect_ok  "$R2"  "ⓐ R2 대상 = BYZ 경로만 → OK"
expect_rej "$R3"  "ⓐ R3 대상 = 팩 + BYZ 섞임 → REJECT 1줄" "$MIX($PK/bin/x.sh · $BYZ/hooks/y.sh) · 카드를 둘로 나누고 다른 리포 일은 기록 줄로"
expect_ok  "$R4"  "ⓑ R4 대상 = 팩 · 기록 줄의 BYZ 경로 → OK(대상 줄만 봄)"
expect_rej "$R5"  "ⓓ R5 대상 = 라이브 설치 경로 → REJECT 1줄" "$LIV($LIVE)"
expect_ok  "$R5B" "ⓓ R5 «- 설치:» 줄의 라이브 경로 → OK(대상 줄만 봄)"
expect_ok  "$R0"  "r1053 절대경로 0 카드 → OK(그대로)"

# 공용 함수 = 닫기 ⑥ 판정과 같은 갈래(팩 1 · 밖 1)
( . "$KIT/ft-card-target-lib.sh"; pk="$(ft_card_pack_root)"; s=""; while IFS= read -r t; do s="$s$(ft_card_target_side "$pk" "$t") "; done <<< "$(ft_card_targets "$R3")"; [ "$s" = "pack out " ] ) \
  && ok "ⓒ 공용 함수 R3 갈래 = pack out" || bad "ⓒ 공용 함수 R3 갈래 다름"

# 변이 2 — 임시 사본의 공용 파일에서 검사 줄을 지우면 반례가 통과해야 한다(= 이 시험이 잡는다)
mut() { local d="$T/mut-$1"; mkdir -p "$d"; cp -p "$KIT"/* "$d/" 2>/dev/null; grep -vF "$2" "$KIT/ft-card-target-lib.sh" > "$d/ft-card-target-lib.sh"; echo "$d/ft-index-lint.sh"; }
M1="$(mut mix '한 카드 = 한 리포')"; out="$(run "$R3" "$M1")"; [ $? -eq 0 ] && ok "변이 1(섞임 검사 삭제) → R3 통과 = 시험 FAIL 로 잡힘" || bad "변이 1 이 R3 를 여전히 REJECT → $out"
M2="$(mut live '대상에 라이브 설치 경로')"; out="$(run "$R5" "$M2")"; [ $? -eq 0 ] && ok "변이 2(라이브 검사 삭제) → R5 통과 = 시험 FAIL 로 잡힘" || bad "변이 2 가 R5 를 여전히 REJECT → $out"

echo "fail=$fail"; [ $fail -eq 0 ]
