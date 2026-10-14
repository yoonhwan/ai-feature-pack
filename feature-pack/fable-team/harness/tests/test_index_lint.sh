#!/usr/bin/env bash
# test_index_lint.sh — ft-index-lint 시험: 스위치 꺼짐(기존 동작 그대로) · 켜짐(⑦ 사전검증 · ⑧ 조사 근거). 임시 리포에서만 돈다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LINT="$HERE/../../scripts/harness-install/fable-team/bin/ft-index-lint.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$LINT" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q . || { echo "FAIL git init"; exit 1; }
mkdir -p design src
G1='골 첫 줄 시험용 문장이다.'; G2='골 둘째 줄 시험용 문장이다.'; G3='골 셋째 줄 시험용 문장이다.'
printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > goal.txt
echo '원장 본문: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > design/LEDGER.md
printf 'l1\nl2\nl3\n' > src/target.sh
printf '판정 1: HOLD\n판정 2: APPROVE\n' > design/da-ok.md
printf '판정 1: APPROVE\n판정 2: HOLD\n' > design/da-hold.md
printf '내용 단어 없음\n' > design/da-empty.md
printf '판정: HOLD\nSUPABASE_PASSWORD 줄\n' > design/da-hold-password.md
printf '판정: HOLD\n시험 요약 26 PASS\n' > design/da-hold-pass.md
export FT_GOAL_LINES_FILE="$T/goal.txt" FT_GOAL_LEDGER="design/LEDGER.md"

# mk <이름> <사전검증 본문|-> <조사 근거 본문|-> — "-" 면 그 절을 만들지 않는다. 카드 경로를 출력.
mk() {
  local f="$T/$1.md"
  { echo "# 인덱스: $1"; echo '- 제안서: 없음 — 시험 카드'; echo "## 골 원문"; printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3"
    echo "## 골좌표"; echo '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」'
    echo "## 배경"; echo '시험 카드.'
    echo "## 구현 범위"; echo '1. src/target.sh 수정'
    echo "## 완료 조건"; echo '시험 통과.'
    [ "$2" != "-" ] && { echo "## 사전검증"; printf '%b\n' "$2"; }
    [ "$3" != "-" ] && { echo "## 조사 근거"; printf '%b\n' "$3"; }
    echo "## 상태"; echo '- 시험'; } > "$f"
  echo "$f"
}
GOODPV='소환: 예\nDA: design/da-ok.md#§1'
GOODEV='- src/target.sh:2 확인'
SW=""
run() { ( cd "$T" && FT_CARD_REQUIRE_PREVERIFY="$SW" bash "$LINT" "$1" 2>&1 ); }
expect_ok()  { local out rc; out="$(run "$1")"; rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -q '^OK ' && ok "$2" || bad "$2 → rc=$rc $out"; }
expect_rej() { local out rc; out="$(run "$1")"; rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -q "$3" && ok "$2" || bad "$2 → rc=$rc $out"; }

# ── 스위치 꺼짐: 지금 동작 그대로 ──
SW=""
expect_ok  "$(mk off-ok - -)" "꺼짐: 기존 OK 카드 OK (⑦⑧ 절 없어도)"
f="$(mk off-bad - -)"; sed -i.bak "s/^$G1\$/골 틀린 줄/" "$f"; rm -f "$f.bak"
expect_rej "$f" "꺼짐: 골 줄 불일치 REJECT 그대로" "골 1줄 불일치"
SW=0;   expect_ok "$(mk sw0 - -)"   "스위치 0 = 꺼짐"
SW=yes; expect_ok "$(mk swyes - -)" "스위치 1 이외 값 = 꺼짐"
SW=""
a="$(run "$(mk bytes - -)")"; SW=0; b="$(run "$T/bytes.md")"; [ "$a" = "$b" ] && ok "꺼짐 출력 바이트 동일(빈값 vs 0)" || bad "꺼짐 출력 상이"

# ── 스위치 켜짐: ⑦ 사전검증 ──
SW=1
expect_ok  "$(mk on-ok "$GOODPV" "$GOODEV")" "켜짐: 정상 카드 OK"
expect_rej "$(mk pv-none - "$GOODEV")"                          "⑦ 절 없음 REJECT"            "절 없음: 사전검증"
expect_rej "$(mk pv-noline '아무 줄도 없음' "$GOODEV")"          "⑦ 소환 줄 없음 REJECT"        "소환: 예.* 또는"
expect_rej "$(mk pv-nofile '소환: 예\nDA: design/없음.md' "$GOODEV")" "⑦ 소환 예 + 판정문 없음 REJECT" "DA 판정문 경로 없음"
expect_rej "$(mk pv-noda '소환: 예' "$GOODEV")"                  "⑦ 소환 예 + DA 줄 없음 REJECT" "DA: <판정문 경로>"
expect_rej "$(mk pv-hold '소환: 예\nDA: design/da-hold.md' "$GOODEV")" "⑦ 마지막 판정 HOLD(앞에 APPROVE) REJECT" "APPROVE 가 아니다 (HOLD)"
expect_rej "$(mk pv-holdpw '소환: 예\nDA: design/da-hold-password.md' "$GOODEV")" "⑦ HOLD 뒤 PASSWORD 줄 REJECT" "APPROVE 가 아니다 (HOLD)"
expect_rej "$(mk pv-holdpass '소환: 예\nDA: design/da-hold-pass.md' "$GOODEV")" "⑦ HOLD 뒤 26 PASS 줄 REJECT" "APPROVE 가 아니다 (HOLD)"
expect_rej "$(mk pv-empty '소환: 예\nDA: design/da-empty.md' "$GOODEV")" "⑦ 판정 단어 없음 REJECT" "판정 단어 없음"
expect_ok  "$(mk pv-abs "소환: 예\nDA: $T/design/da-ok.md" "$GOODEV")" "⑦ 마지막 APPROVE + 절대경로 OK"
EXOK='소환: 아니오\n면제: 오타 수정 한 줄이라 설계 불필요 — arch 서명 byz-harness-arch-claude#6'
expect_ok  "$(mk ex-ok "$EXOK" "$GOODEV")" "⑦ 아니오 + 면제 + arch 서명 OK"
expect_rej "$(mk ex-short '소환: 아니오\n면제: 아홉글자사유입니다 — arch 서명 byz-harness-arch-claude#6' "$GOODEV")" "⑦ 면제 사유 9자 REJECT" "10자 미만 (9자)"
expect_ok  "$(mk ex-ten '소환: 아니오\n면제: 열글자사유입니다요오 — arch 서명 byz-harness-arch-claude#6' "$GOODEV")" "⑦ 면제 사유 10자 경계 OK"
expect_rej "$(mk ex-nano '소환: 아니오\n면제: 오타 수정 한 줄이라 설계 불필요 — arch 서명 byz-harness-nano-x-card#0' "$GOODEV")" "⑦ nano 서명 REJECT" "역할이 arch 가 아니다 (nano)"
expect_rej "$(mk ex-badname '소환: 아니오\n면제: 오타 수정 한 줄이라 설계 불필요 — arch 서명 foo' "$GOODEV")" "⑦ 형식 틀린 좌석명 REJECT" "ft-name-lint"
expect_rej "$(mk ex-noline '소환: 아니오' "$GOODEV")" "⑦ 아니오 + 면제 줄 없음 REJECT" "면제:"

# ── 스위치 켜짐: ⑧ 조사 근거 ──
expect_rej "$(mk ev-none "$GOODPV" -)"                          "⑧ 절 없음 REJECT"         "절 없음: 조사 근거"
expect_rej "$(mk ev-noref "$GOODPV" '- 인용 없음')"              "⑧ 인용 0 REJECT"          "인용이 하나도 없다"
expect_rej "$(mk ev-nopath "$GOODPV" '- src/없음.sh:2')"          "⑧ 없는 경로 REJECT"        "경로 없음 (src/없음.sh:2)"
expect_rej "$(mk ev-long "$GOODPV" '- src/target.sh:4')"         "⑧ 줄 번호 > 파일 길이 REJECT" "벗어남"
expect_rej "$(mk ev-zero "$GOODPV" '- src/target.sh:0')"         "⑧ 줄 0 REJECT"            "벗어남"
expect_ok  "$(mk ev-last "$GOODPV" '- `src/target.sh:3` 끝 줄')"  "⑧ 마지막 줄 번호 + 백틱 OK"

# ── ⑨ 머리 `- 제안서:` 줄 (R77 r1 · 판정 826) — 값 #M | 없음 — 사유 · 새 카드 의무 · 옛 카드 WARN ──
SW=""; mkdir -p design/team; echo '# 제안서 시험용' > design/team/PROPOSAL-x-20261010.md
mkp() {  # mkp <이름> <머리 2줄 통째로|-> — mk 카드의 `- 제안서:` 줄을 바꾸거나(-면 지운다) 한 파일 경로를 출력
  local f; f="$(mk "$1" - -)"; if [ "$2" = "-" ]; then sed -i.bak '2d' "$f"; else sed -i.bak "2s|.*|$2|" "$f"; fi; rm -f "$f.bak"; echo "$f"; }
expect_ok  "$(mkp pl-none '- 제안서: 없음 — 구조 정리라 제안서 불필요')"  "⑨ 「없음 — 사유」 OK"
expect_ok  "$(mkp pl-issue '- 제안서: #12')"                              "⑨ 「#12」(제안 Issue 번호) OK"
expect_rej "$(mkp pl-nolines -)"                                          "⑨ 새 카드(미추적) 줄 없음 REJECT" "제안서:"
expect_rej "$(mkp pl-noreason '- 제안서: 없음')"                          "⑨ 「없음」 사유 없음 REJECT" "#<제안 Issue 번호>"
expect_rej "$(mkp pl-path '- 제안서: design/team/PROPOSAL-x-20261010.md')" "⑨ 새 카드의 경로 값 REJECT(r1 부터 금지)" "경로 값은 R77 r1"
expect_rej "$(mkp pl-junk '- 제안서: 나중에 쓴다')"                       "⑨ 아무 값 REJECT" "#<제안 Issue 번호>"
gc() { GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -c user.email=t@t -c user.name=t commit -qm "$2" >/dev/null 2>&1; }
oldc="$(mkp pl-old -)"; oldp="$(mkp pl-oldpath '- 제안서: design/team/PROPOSAL-x-20261010.md')"; git add "$oldc" "$oldp" >/dev/null 2>&1; gc "2026-10-01T09:00:00" old
out="$(run "$oldc")"; rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -q '^WARN .*옛 카드' && echo "$out" | grep -q '^OK ' && ok "⑨ 옛 카드(10-01 추가) 줄 없음 → WARN + rc 0" || bad "⑨ 옛 카드 WARN → rc=$rc $out"
out="$(run "$oldp")"; rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -q '^WARN .*경로·기타 값' && ok "⑨ 옛 카드의 경로 값 → WARN + rc 0" || bad "⑨ 옛 카드 경로 값 → rc=$rc $out"
newc="$(mkp pl-new -)"; git add "$newc" >/dev/null 2>&1; gc "2026-10-12T09:00:00" new
expect_rej "$newc" "⑨ 새 카드(10-12 추가 · 커밋됨) 줄 없음 REJECT" "새 카드 의무"
mkw() { local f; f="$(mkp "$1" "$2")"; sed -i.bak 's|^1\. src/target.sh 수정|1. `design/team/PROPOSAL-x-20261010.md` 제안서 1개만 쓴다|' "$f"; rm -f "$f.bak"; echo "$f"; }
expect_ok  "$(mkw proposal-x -)"                          "⑨ 제안서 작성 카드(proposal-* · 구현 범위 design/ 문서 1개+)는 줄 없어도 OK"
expect_rej "$(mkp proposal-impl -)"                        "⑨ proposal- 이름이어도 구현 범위에 코드 경로(src/target.sh)면 줄 의무" "새 카드 의무"
expect_rej "$(mkw proposal-y '- 제안서: 나중에 쓴다')"     "⑨ 작성 카드라도 줄이 있으면 값 검사" "#<제안 Issue 번호>"

# ── ⑥ 구현 범위 경로 실재: origin/main 트리도 인정 (R154) — 52행 사전검증 판정문 경로(path_exists)는 불변 ──
# R6=origin/main 에만 scripts/x.sh · scripts/kit.d/a.sh · design/da-only.md 가 있고 워크트리는 그 앞 커밋 · R6N=origin/main ref 자체가 없는 리포
gt() { git -c user.email=t@t -c user.name=t commit -qm "$1" >/dev/null 2>&1; }
R6="$T/r154"; R6N="$T/r154n"
for r in "$R6" "$R6N"; do mkdir -p "$r/design" "$r/src"; ( cd "$r" && git init -q . && cp "$T/design/LEDGER.md" design/ && printf 'l1\nl2\nl3\n' > src/target.sh && printf 'g1\ng2\ng3\n' > src/grow.sh && git add -A && gt base ); done
( cd "$R6" && mkdir -p scripts/kit.d && echo x > scripts/x.sh && echo a > scripts/kit.d/a.sh && echo '판정: APPROVE' > design/da-only.md && printf 'g4\ng5\n' >> src/grow.sh && git add -A && gt main-only \
  && git update-ref refs/remotes/origin/main HEAD && git reset -q --hard HEAD~1 )
mk6() {  # mk6 <리포> <이름> <구현 범위 한 줄> [사전검증 본문 조사 근거 본문] → 카드 경로
  local f="$1/$2.md"
  { echo "# 인덱스: $2"; echo '- 제안서: 없음 — 시험 카드'; echo "## 골 원문"; printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3"
    echo "## 골좌표"; echo '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」'
    echo "## 배경"; echo '시험 카드.'
    echo "## 구현 범위"; echo "$3"
    echo "## 완료 조건"; echo '시험 통과.'
    [ $# -ge 5 ] && { echo "## 사전검증"; printf '%b\n' "$4"; echo "## 조사 근거"; printf '%b\n' "$5"; }
    echo "## 상태"; echo '- 시험'; } > "$f"
  echo "$f"
}
run6() { local r="$1"; shift; ( cd "$r" && FT_CARD_REQUIRE_PREVERIFY="${SW6:-}" bash "$LINT" "$1" 2>&1 ); }
ok6()  { local out rc; out="$(run6 "$R6" "$(mk6 "$R6" "$1" "1. $2")")"; rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -q '^OK ' && ok "⑥ $3" || bad "⑥ $3 → rc=$rc $out"; }
rej6() { local out rc; out="$(run6 "$R6" "$(mk6 "$R6" "$1" "1. $2")")"; rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -q '구현 범위: 인용한 파일 경로가 하나도 실재하지 않는다' && ok "⑥ $3" || bad "⑥ $3 → rc=$rc $out"; }
SW6=""
ok6  s6a  'scripts/x.sh 수정'                     "ⓐ origin/main 에만 있는 경로 OK"
rej6 s6b  'scripts/none.sh 수정'                  "ⓑ origin/main·워크트리 둘 다 없음 REJECT(기존 문구)"
out="$(run6 "$R6N" "$(mk6 "$R6N" s6c '1. scripts/x.sh 수정')" 2>"$T/s6c.err")"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q '구현 범위: 인용한 파일 경로가 하나도 실재하지 않는다' && ok "⑥ ⓒ origin/main ref 없음 + 워크트리에 없음 REJECT" || bad "⑥ ⓒ → rc=$rc $out"
out="$( cd "$R6N" && bash "$LINT" "$R6N/s6c.md" 2>&1 >/dev/null | grep -v 'setlocale' )"; [ -z "$out" ] && ok "⑥ ⓒ stderr 0" || bad "⑥ ⓒ stderr: $out"
SW6=1
out="$(run6 "$R6" "$(mk6 "$R6" s6d '1. src/target.sh 수정' 'DA 소환\n소환: 예\nDA: design/da-only.md#§1' '- src/target.sh:2 확인')")"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q 'DA 판정문 경로 없음 (design/da-only.md)' && ok "⑥ ⓓ 판정문 경로가 origin/main 에만 있음 → 52행 기존 REJECT(불변)" || bad "⑥ ⓓ → rc=$rc $out"
SW6=""
ok6  s6e  './scripts/x.sh 수정'                   "ⓔ ./ 접두 OK"
rej6 s6f1 '../scripts/x.sh 수정'                  "ⓕ ../ 선행 REJECT"
rej6 s6f2 'scripts/nodir/../x.sh 수정'            "ⓕ 중간 ../ REJECT"
rej6 s6f3 'scripts/./x.sh 수정'                   "ⓕ 중간 ./ REJECT"
rej6 s6g  '/scripts/x.sh 수정'                    "ⓖ 선행 / (파일시스템에 없음) REJECT"
rej6 s6h  'scripts//x.sh 수정'                    "ⓗ 빈 성분 // REJECT"
ok6  s6i  'scripts/kit.d 수정'                    "ⓘ origin/main 의 tracked 디렉터리 OK"
# 지금의 git 은 ⓕ~ⓗ 꼴을 스스로 거절하므로(실측) 거절이 «우리 가드» 몫인지는 git 이 뭐든 받아주는 가짜로 가려낸다 — Git 의 경로 정규화에 기대지 않는다는 계약.
FG="$T/fakegit"; mkdir -p "$FG"; REALGIT="$(command -v git)"
printf '#!/bin/bash\ncase " $* " in *" cat-file "*) exit 0;; esac\nexec "%s" "$@"\n' "$REALGIT" > "$FG/git"; chmod +x "$FG/git"
fk() { local out rc; out="$( PATH="$FG:$PATH" run6 "$R6" "$(mk6 "$R6" "$1" "1. $2")" )"; rc=$?; echo "$rc|$out"; }
r="$(fk s6k0 'scripts/none.sh 수정')"; [ "${r%%|*}" = 0 ] && ok "⑥ 가짜 git(전부 실재) 대조군: 상대 경로는 OK" || bad "⑥ 가짜 git 대조군 → $r"
for c in '../scripts/x.sh' 'scripts/nodir/../x.sh' 'scripts/./x.sh' '/scripts/x.sh' 'scripts//x.sh'; do
  r="$(fk s6k1 "$c 수정")"; [ "${r%%|*}" = 1 ] && echo "${r#*|}" | grep -q '구현 범위: 인용한 파일 경로가 하나도 실재하지 않는다' && ok "⑥ 가짜 git 이 받아줘도 가드가 거절: $c" || bad "⑥ 가드 $c → $r"
done

# ── ⑧ 조사 근거 «경로:줄»: origin/main blob 도 인정 (R174) — R6 임시 리포 재사용: src/target.sh 3줄(워크트리) · scripts/x.sh 1줄(origin/main 에만) · src/grow.sh 워크트리 3줄·origin/main 5줄 ──
SW6=1; EX8='소환: 아니오\n면제: 시험용 카드라 설계 불필요 — arch 서명 byz-harness-arch-claude#6'
ev8() { local r="$1"; shift; ( cd "$r" && FT_CARD_REQUIRE_PREVERIFY=1 bash "$LINT" "$(mk6 "$r" "$1" '1. src/target.sh 수정' "$EX8" "- $2")" 2>&1 ); }
ok8()  { local out rc; out="$(ev8 "$R6" "$1" "$2")"; rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -q '^OK ' && ok "⑧ $3" || bad "⑧ $3 → rc=$rc $out"; }
rej8() { local out rc; out="$(ev8 "${4:-$R6}" "$1" "$2")"; rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -q -F "$5" && ok "⑧ $3" || bad "⑧ $3 → rc=$rc $out"; }
ok8  e8a1 'src/target.sh:2'                       "ⓐ 워크트리 파일 줄 수 안 OK(불변)"
rej8 e8a2 'src/target.sh:9' "ⓐ 워크트리 파일 줄 수 밖 REJECT(N=3)" "$R6" '줄 번호가 파일 줄 수(3)를 벗어남 (src/target.sh:9)'
ok8  e8b1 'scripts/x.sh:1'                        "ⓑ origin/main 에만 있는 파일 OK"
rej8 e8b2 'scripts/x.sh:2' "ⓑ origin/main 에만 있는 파일 줄 수 밖 REJECT(N=1)" "$R6" '줄 번호가 파일 줄 수(1)를 벗어남 (scripts/x.sh:2)'
ok8  e8c1 'src/grow.sh:5'                         "ⓑ' 워크트리 3줄·origin/main 5줄: :5 OK(origin/main 줄 수 안)"
ok8  e8c2 'src/grow.sh:3'                         "ⓑ' 워크트리 줄 수 안 :3 OK"
rej8 e8c3 'src/grow.sh:6' "ⓑ' 두 줄 수 모두 밖 :6 REJECT(N=큰 값 5)" "$R6" '줄 번호가 파일 줄 수(5)를 벗어남 (src/grow.sh:6)'
rej8 e8d1 'scripts/kit.d:1' "ⓒ origin/main 의 디렉터리(tree)는 파일이 아님 → 경로 없음" "$R6" '경로 없음 (scripts/kit.d:1)'
rej8 e8d2 'scripts/none.sh:1' "ⓒ 둘 다 없음 → 경로 없음" "$R6" '경로 없음 (scripts/none.sh:1)'
rej8 e8d3 'scripts/x.sh:1' "ⓒ origin/main ref 없는 리포 → 경로 없음" "$R6N" '경로 없음 (scripts/x.sh:1)'
rej8 e8e1 '../scripts/x.sh:1' "ⓓ ../ 선행 REJECT" "$R6" '경로 없음 (../scripts/x.sh:1)'
rej8 e8e2 'scripts/nodir/../x.sh:1' "ⓓ 중간 ../ REJECT" "$R6" '경로 없음 (scripts/nodir/../x.sh:1)'
rej8 e8e3 'scripts/./x.sh:1' "ⓓ 중간 ./ REJECT" "$R6" '경로 없음 (scripts/./x.sh:1)'
ok8  e8e4 './scripts/x.sh:1'                      "ⓓ ./ 접두 OK"
# 가짜 git: cat-file -t 는 blob · show 는 한 줄 — Git 이 뭐든 받아줘도 정규화 가드가 거절(ⓓ) · git 이 실패하면 통과 간주 없이 REJECT(ⓕ)
FG8="$T/fakegit8"; mkdir -p "$FG8"
printf '#!/bin/bash\ncase " $* " in *" cat-file "*) echo blob; exit 0;; *" show "*) echo x; exit 0;; esac\nexec "%s" "$@"\n' "$REALGIT" > "$FG8/git"; chmod +x "$FG8/git"
out="$( PATH="$FG8:$PATH" ev8 "$R6" e8f1 'scripts/none.sh:1' )"; echo "$out" | grep -q '^OK ' && ok "⑧ 가짜 git(전부 blob) 대조군: 상대 경로는 OK" || bad "⑧ 가짜 git 대조군 → $out"
out="$( PATH="$FG8:$PATH" ev8 "$R6" e8f2 '../scripts/x.sh:1' )"; echo "$out" | grep -q -F '경로 없음 (../scripts/x.sh:1)' && ok "⑧ ⓓ 가짜 git 이 받아줘도 가드가 거절" || bad "⑧ ⓓ 가드 → $out"
FG9="$T/fakegit9"; mkdir -p "$FG9"
printf '#!/bin/bash\ncase " $* " in *" cat-file "*|*" show "*) exit 1;; esac\nexec "%s" "$@"\n' "$REALGIT" > "$FG9/git"; chmod +x "$FG9/git"
out="$( PATH="$FG9:$PATH" ev8 "$R6" e8f3 'scripts/x.sh:1' )"; echo "$out" | grep -q -F '경로 없음 (scripts/x.sh:1)' && ok "⑧ ⓕ git 실패 = 보이는 REJECT(통과 간주 0)" || bad "⑧ ⓕ → $out"
SW6=""

echo "fail=$fail"; [ $fail -eq 0 ]
