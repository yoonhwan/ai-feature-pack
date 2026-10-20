#!/usr/bin/env bash
# test_merge_land_equiv.sh — R247 판정 1917: 승인 sha A 뒤 «main 병합만» 한 PR head S 는 같은 승인으로 착지 (임시 origin+clone · gh 는 스텁 · 실 gh·실 원격 0)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each   # r466: --level 생략 = full(범위 승인 + 슬랙 게시) — 이 시험은 레벨 밖이라 each(실 슬랙 0)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; LAND="$BIN/ft-merge-land.sh"; EQV="$BIN/ft-approval-equiv.sh"; EQP="$BIN/ft_approval_equiv.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/shim" "$T/.fable-team"
REAL_GIT="$(command -v git)"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json"
printf '#!/bin/bash\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\nbody=""; for a in "$@"; do [ -f "$a" ] && body="$(cat "$a")"; done\necho "$* :: $body" >> "$STUB_LOG"\n' > "$T/gh-stub"
printf '#!/bin/bash\nfor a in "$@"; do [ -n "${FAIL_GIT:-}" ] && [ "$a" = "$FAIL_GIT" ] && { echo injected >&2; exit 128; }; done\nexec "%s" "$@"\n' "$REAL_GIT" > "$T/shim/git"
chmod +x "$T/gh-stub" "$T/shim/git"
omain() { sha "$ORIGIN" refs/heads/main; }
G() { git -C "$W" "$@"; }
adv() { G checkout -q -B main origin/main; printf '%s\n' "$2" >> "$W/$1"; cm "$W" "main $2"; G push -q origin main; G fetch -q origin; }       # adv <파일> <줄> main 에 한 줄 추가
setf() { G checkout -q -B main origin/main; printf '%b' "$2" > "$W/$1"; cm "$W" "main set $1"; G push -q origin main; G fetch -q origin; }  # setf <파일> <내용> main 의 파일 덮어쓰기
own() { G checkout -q -B "pr$1" origin/main; printf 'own%s\n' "$1" > "$W/own$1.txt"; cm "$W" "own $1"; A="$(sha "$W" HEAD)"; }            # own <번호> 자기 변경 1커밋 = 승인 세트 A
mrg() { G checkout -q "pr$1"; G merge -q --no-edit origin/main >/dev/null 2>&1; }                                                      # mrg <번호> 최신 main 병합
setpr() {  # setpr <번호> — 현재 HEAD(= S) 를 PR head 로 올리고 스텁 JSON 작성
  S="$(sha "$W" HEAD)"; G push -q -f origin "HEAD:refs/pull/$1/head"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"본문","state":"OPEN","baseRefName":"main"}))' "$S" "$1" > "$STUB_JSON"; }
land() { apv "$@"; out="$(bash "$LAND" "$@" --repo "$W" 2>&1)"; rc=$?; }
okland() { [ "$rc" = 0 ] && [[ "$out" == *"EQUIV approve=$A head=$S"* ]] && [[ "$out" == *"LANDED"* ]] && [ "$(sha "$ORIGIN" "$(omain)^{tree}")" = "$(sha "$W" "$S^{tree}")" ]; }
refused() { [ "$rc" = 1 ] && [[ "$out" == *"NOT-EQUIV"* ]] && [[ "$out" == *"착지 0"* ]] && [ "$(omain)" = "$M" ] && [ ! -s "$STUB_LOG" ]; }   # NOT-EQUIV 거절 · main 불변 · PR 쓰기 0

bash -n "$EQV"; ck "bash -n equiv" $?
[ "$(wc -l < "$EQV" | tr -d ' ')" -le 80 ]; ck "ft-approval-equiv.sh ≤ 80줄" $?
[ "$(wc -l < "$EQP" | tr -d ' ')" -le 200 ]; ck "ft_approval_equiv.py ≤ 200줄(R281 rebase 경로 추가로 120 → 200)" $?
[ -f "$EQV" ] && [ -f "$EQP" ] && ! cat "$EQV" "$EQP" | grep -vE '^\s*#' | grep -qE 'git[^|]* (push|update-ref|checkout|switch|reset|restore|commit|commit-tree|fetch|branch|rebase|merge|gc|prune)( |$)|"(push|update-ref|checkout|switch|reset|restore|commit|commit-tree|fetch|branch|rebase|merge|gc|prune)"'; ck "정적: equiv 쓰기·네트워크 동사 0(읽기 전용 · merge-tree·merge-base 만)" $?
bash "$EQV" >/dev/null 2>&1; [ "$?" = 2 ]; ck "usage → rc2" $?
rc=0; out="$(bash "$EQV" "$M0" "$M0" --repo "$T/none" 2>&1)" || rc=$?; [ "$rc" = 3 ] && [[ "$out" == ERROR* ]]; ck "저장소 못 읽음 → ERROR rc3(통과 0)" $?

# ⓐ A 승인 → main 병합 1번(충돌 0) → S
own 1; adv b.txt m1; mrg 1; setpr 1; M="$(omain)"; land 1 --approve-sha "$A"
okland && [[ "$out" == *"merges=1 files=1"* ]]; ck "ⓐ main 병합 1번 → EQUIV 착지" $?
grep -q "head=$S method=ft-merge-land .*pr=1 approve=$A" "$T/state/merge-gate.log"; ck "ⓐ 결속 기록에 approve=A head=S 둘 다" $?
grep -q "pr-close 1 .*:: .*동일승인 대조 EQUIV" "$STUB_LOG"; ck "ⓐ PR 코멘트에 «동일승인 대조 EQUIV»" $?
# ⓑ main 병합 2번
: > "$STUB_LOG"; own 2; adv b.txt m2; mrg 2; adv b.txt m3; mrg 2; setpr 2; land 2 --approve-sha "$A"
okland && [[ "$out" == *"merges=2"* ]]; ck "ⓑ main 병합 2번 → EQUIV 착지" $?
# ⓒ A 뒤 일반 커밋 1개
: > "$STUB_LOG"; own 3; adv b.txt m4; mrg 3; echo x > "$W/extra3.txt"; cm "$W" extra; setpr 3; M="$(omain)"; land 3 --approve-sha "$A"
refused; ck "ⓒ A 뒤 일반 커밋 → NOT-EQUIV · 착지 0" $?
# ⓓ 충돌 해소 중 자기 변경을 바꿈(evil merge) · 병합 커밋에 파일 끼워넣기 · 같은 줄을 위치만 옮김
setf c.txt 'base\n'; G checkout -q -B pr4 origin/main; echo OWN > "$W/c.txt"; cm "$W" own4; A="$(sha "$W" HEAD)"
setf c.txt 'MAIN\n'; G checkout -q pr4; G merge -q --no-edit origin/main >/dev/null 2>&1; echo EVIL > "$W/c.txt"; G add -A; G commit -q --no-edit; setpr 4; M="$(omain)"; land 4 --approve-sha "$A"
[ "$rc" = 1 ] && [ "$(omain)" = "$M" ] && [ ! -s "$STUB_LOG" ]; ck "ⓓ 충돌 해소가 자기 변경을 바꿈 → 착지 0(줄 계약 게이트가 먼저 막음)" $?
out="$(bash "$EQV" "$A" "$S" --repo "$W" 2>&1)"; rc=$?; [ "$rc" = 1 ] && [[ "$out" == "NOT-EQUIV"* ]]; ck "ⓓ 같은 입력을 equiv 에 직접 → NOT-EQUIV rc1" $?
own 5; adv b.txt m5; G checkout -q pr5; G merge -q --no-commit --no-ff origin/main >/dev/null 2>&1; echo evil > "$W/evil5.txt"; G add -A; G commit -q -m evilmerge; setpr 5; M="$(omain)"; land 5 --approve-sha "$A"
refused; ck "ⓓ 병합 커밋에 새 파일 끼워넣기 → NOT-EQUIV" $?
setf p.txt 'p1\np2\np3\n'; G checkout -q -B pr6 origin/main; printf 'p1\nOWN6\np2\np3\n' > "$W/p.txt"; cm "$W" own6; A="$(sha "$W" HEAD)"
adv p.txt p4; G checkout -q pr6; G merge -q --no-commit --no-ff origin/main >/dev/null 2>&1; printf 'p1\np2\np3\nOWN6\np4\n' > "$W/p.txt"; G add -A; G commit -q -m shuffle; setpr 6; M="$(omain)"; land 6 --approve-sha "$A"
refused && [[ "$out" == *"깨끗한 병합"* ]]; ck "ⓓ 같은 줄을 위치만 옮김(+/- 목록 같음) → NOT-EQUIV" $?
# ⓔ main 아닌 다른 브랜치 병합
own 7; adv b.txt m6; mrg 7; G checkout -q -B oth7 origin/main; echo o > "$W/oth7.txt"; cm "$W" oth; G checkout -q pr7; G merge -q --no-edit oth7 >/dev/null 2>&1; setpr 7; M="$(omain)"; land 7 --approve-sha "$A"
refused; ck "ⓔ main 아닌 브랜치 병합 → NOT-EQUIV" $?
# ⓕ A 가 S 의 조상 아님(rebase·force)
own 8; adv b.txt m7; G checkout -q -B pr8 origin/main; echo own8-edited > "$W/own8.txt"; cm "$W" own8again; setpr 8; M="$(omain)"; land 8 --approve-sha "$A"
refused && [[ "$out" == *"승인 때와 다름"* ]]; ck "ⓕ A 가 조상 아님 + 내용이 다름(force-push) → NOT-EQUIV  (R281: 내용 같은 rebase 는 ⓜ 에서 EQUIV)" $?
# ⓖ main 이 같은 파일 다른 곳만 바꿈(문맥만 달라짐)
setf g.txt 'g1\ng2\ng3\n'; G checkout -q -B pr9 origin/main; { echo OWN9; cat "$W/g.txt"; } > "$W/g.tmp"; mv "$W/g.tmp" "$W/g.txt"; cm "$W" own9; A="$(sha "$W" HEAD)"
adv g.txt g4; mrg 9; setpr 9; : > "$STUB_LOG"; land 9 --approve-sha "$A"
okland; ck "ⓖ 같은 파일 다른 곳만 변경 → EQUIV 착지" $?
# ⓗ head == A: 대조 호출 없음(현행 그대로)
own 10; setpr 10; : > "$STUB_LOG"; land 10 --approve-sha "$A"
[ "$rc" = 0 ] && [[ "$out" == *LANDED* ]] && [[ "$out" != *EQUIV* ]] && ! grep -q '동일승인' "$STUB_LOG" && grep -q "head=$A .*approve=$A" "$T/state/merge-gate.log"; ck "ⓗ head==A → 대조 줄 0 · 착지 · approve=A" $?
# ⓙ git 실패 주입 → ERROR → 착지 0
own 11; adv b.txt m8; mrg 11; setpr 11; M="$(omain)"; : > "$STUB_LOG"
for f in --merges merge-tree; do
  apv --approve-sha "$A"; out="$(PATH="$T/shim:$PATH" FAIL_GIT="$f" bash "$LAND" 11 --approve-sha "$A" --repo "$W" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && [[ "$out" == *ERROR* ]] && [ "$(omain)" = "$M" ] && [ ! -s "$STUB_LOG" ]; ck "ⓙ git($f) 실패 주입 → ERROR · 착지 0" $?
done
land 11 --approve-sha "$A"; okland; ck "ⓙ 주입 뒤 정상 환경 → 같은 PR EQUIV 착지(주입이 원인)" $?
# ⓚ DA⑥ HOLD2-①: 게이트·대조가 본 main(M0) 뒤에 추적 ref 가 M1 로 전진 → 착지 부모(M1)를 S 가 품지 않으면 REJECT · M1 새 파일 보존
mkdir -p "$T/shim2"; rm -f "$T/cnt"; git -C "$T" clone -q "$ORIGIN" "$T/race" 2>/dev/null; git -C "$T/race" config user.name t; git -C "$T/race" config user.email t@t
cat > "$T/shim2/git" <<EOF
#!/bin/bash
for a in "\$@"; do if [ "\$a" = "refs/remotes/origin/main^{commit}" ]; then n=\$(( \$(cat "$T/cnt" 2>/dev/null || echo 0) + 1 )); echo \$n > "$T/cnt"
  if [ "\$n" = "\${RACE_AT:-0}" ]; then "$REAL_GIT" -C "$T/race" pull -q origin main && echo m1 > "$T/race/m1.txt" && "$REAL_GIT" -C "$T/race" add -A && "$REAL_GIT" -C "$T/race" commit -q -m m1 && "$REAL_GIT" -C "$T/race" push -q origin HEAD:main && "$REAL_GIT" -C "$W" fetch -q origin; fi; fi; done
for a in "\$@"; do [ "\$a" = "\${SLOW_ARG:-@}" ] && sleep "\${SLOW_S:-0}"; done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/shim2/git"
own 20; setpr 20; M="$(omain)"; : > "$STUB_LOG"
apv --approve-sha "$A"; out="$(PATH="$T/shim2:$PATH" RACE_AT=2 bash "$LAND" 20 --approve-sha "$A" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"main 이 움직였다"* ]] && [ "$(omain)" != "$M" ] && [ "$(git -C "$ORIGIN" show main:m1.txt 2>/dev/null)" = m1 ] && [ ! -s "$STUB_LOG" ]; ck "ⓚ 게이트 뒤 main 전진(M1) → REJECT · 착지 0 · M1 새 파일 main 에 보존" $?
G fetch -q origin; G checkout -q -B pr20 origin/main; echo own20b > "$W/own20b.txt"; cm "$W" own20b; A="$(sha "$W" HEAD)"; setpr 20; : > "$STUB_LOG"; land 20 --approve-sha "$A"
[ "$rc" = 0 ] && [ "$(git -C "$ORIGIN" show main:m1.txt)" = m1 ]; ck "ⓚ 최신화한 세트는 착지 · M1 보존" $?
# ⓛ DA⑥ HOLD2-②: push «시작» 시점에 남은 시간 < 7 s 면 REJECT(총 마감 70 s 안에 못 끝남) — 시험은 총 마감을 12 s 로 줄이고 commit-tree 를 6 s 지연
own 21; setpr 21; M="$(omain)"; : > "$STUB_LOG"
apv --approve-sha "$A"; out="$(PATH="$T/shim2:$PATH" SLOW_ARG=commit-tree SLOW_S=6 FT_LAND_TOTAL_S=12 bash "$LAND" 21 --approve-sha "$A" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"push 를 끝낼 수 없음"* ]] && [ "$(omain)" = "$M" ] && [ ! -s "$STUB_LOG" ]; ck "ⓛ 남은 시간 < 7 s → push 시작 0 · REJECT" $?
apv --approve-sha "$A"; out="$(FT_LAND_TOTAL_S=999 bash "$LAND" 21 --approve-sha "$A" --repo "$W" 2>&1)"; rc=$?; [ "$rc" = 0 ] && [ "$(omain)" != "$M" ]; ck "ⓛ 총 마감 주입은 줄이기만(999 → 70 s 로 간주) · 정상 착지" $?
# ⓜ R281 rebase 동일: A 를 지금 main 위로 «손 편집 0» rebase(cherry-pick) 한 S — A 는 S 의 조상이 아님
rb() { G checkout -q -B "pr$1r" "${2:-origin/main}"; G cherry-pick "$A" >/dev/null 2>&1; }                                                  # rb <번호> [기준] A 를 기준(기본 지금 main) 위로 옮긴 S 작업 브랜치
eqv() { out="$(bash "$EQV" "$A" "$S" --repo "$W" 2>&1)"; rc=$?; }
own 30; adv b.txt r1; rb 30; setpr 30; M="$(omain)"; : > "$STUB_LOG"; land 30 --approve-sha "$A"
okland && [[ "$out" == *"mode=rebase"* ]] && [[ "$out" == *"overlap=0"* ]]; ck "ⓜ rebase 동일(손 편집 0) → EQUIV mode=rebase 착지" $?
grep -q "head=$S method=ft-merge-land .*pr=30 approve=$A equiv=rebase overlap=0" "$T/state/merge-gate.log"; ck "ⓜ 결속 기록에 equiv=rebase overlap=0" $?
grep -q "pr-close 30 .*:: .*동일승인 대조 EQUIV .*equiv=rebase" "$STUB_LOG"; ck "ⓜ PR 코멘트에 equiv=rebase" $?
setf o.txt 'o1\no2\no3\n'; G checkout -q -B pr31 origin/main; { echo OWN31; cat "$W/o.txt"; } > "$W/o.tmp"; mv "$W/o.tmp" "$W/o.txt"; cm "$W" own31; A="$(sha "$W" HEAD)"
adv o.txt o4; rb 31; setpr 31; : > "$STUB_LOG"; land 31 --approve-sha "$A"
okland && [[ "$out" == *"mode=rebase"* ]] && [[ "$out" == *"overlap=1"* ]]; ck "ⓜ main 이 같은 파일 다른 곳을 바꾼 rebase → EQUIV overlap=1(막지 않음)" $?
own 32; adv b.txt r2; rb 32; echo extra > "$W/extra32.txt"; cm "$W" extra32; setpr 32; M="$(omain)"; : > "$STUB_LOG"; land 32 --approve-sha "$A"
refused; ck "ⓜ rebase 하며 한 줄(파일) 추가 → NOT-EQUIV · 착지 0" $?
G checkout -q -B pr33 origin/main; printf '  a\n' > "$W/ws33.txt"; cm "$W" own33; A="$(sha "$W" HEAD)"; adv b.txt r3
rb 33; printf '    a\n' > "$W/ws33.txt"; cm "$W" ws33; setpr 33; M="$(omain)"; land 33 --approve-sha "$A"
refused; ck "ⓜ 들여쓰기(공백)만 바꾼 rebase → NOT-EQUIV · 착지 0" $?
G checkout -q -B pr34 origin/main; echo a > "$W/own34a.txt"; echo b > "$W/own34b.txt"; cm "$W" own34; A="$(sha "$W" HEAD)"; adv b.txt r4
rb 34; G rm -qf own34b.txt; cm "$W" drop34b; setpr 34; M="$(omain)"; land 34 --approve-sha "$A"
refused; ck "ⓜ 파일 하나 빠진 rebase → NOT-EQUIV · 착지 0" $?
own 35; adv b.txt r5; OLD="$(omain)"; adv b.txt r6; rb 35 "$OLD"; S="$(sha "$W" HEAD)"; eqv
[ "$rc" = 0 ] && [[ "$out" == EQUIV* ]] && [[ "$out" == *"mode=rebase"* ]] && [[ "$out" == *"base=${OLD:0:10}"* ]]; ck "ⓜ r560: 옛 main 위 rebase 도 기준 main = merge-base(S,main)=옛 main → EQUIV(옛 판 = 지금 main 요구라 NOT-EQUIV)" $?
setpr 35; M="$(omain)"; : > "$STUB_LOG"; land 35 --approve-sha "$A"
[ "$rc" = 1 ] && [[ "$out" == *"현재 main"*"포함하지 않음"* ]] && [ "$(omain)" = "$M" ] && [ ! -s "$STUB_LOG" ]; ck "ⓜ r560: 옛 main 위 head 는 착지 게이트가 막는다(«현재 main 을 포함하지 않음») — 판정 완화가 착지 틈이 아니다" $?
setf c36.txt 'base\n'; G checkout -q -B pr36 origin/main; echo OWN36 > "$W/c36.txt"; cm "$W" own36; A="$(sha "$W" HEAD)"; setf c36.txt 'MAIN\n'
G checkout -q -B pr36r origin/main; G cherry-pick "$A" >/dev/null 2>&1; echo EVIL > "$W/c36.txt"; G add -A; GIT_EDITOR=true G cherry-pick --continue >/dev/null 2>&1; S="$(sha "$W" HEAD)"; eqv
[ "$rc" = 1 ] && [[ "$out" == "NOT-EQUIV"* ]]; ck "ⓜ 충돌을 손으로 푼 rebase → NOT-EQUIV rc1" $?
G checkout -q -B pr37 origin/main; echo own37 > "$W/own37.txt"; cm "$W" own37; A="$(sha "$W" HEAD)"; G checkout -q -B pr37x origin/main; echo extra > "$W/extra37.txt"; cm "$W" extra37; S="$(sha "$W" HEAD)"; eqv
[ "$rc" = 1 ] && [[ "$out" == "NOT-EQUIV"* ]]; ck "ⓜ A 와 전혀 다른 변경을 가진 S(main 위) → NOT-EQUIV rc1" $?
A=0123456789abcdef0123456789abcdef01234567; eqv; [ "$rc" = 3 ] && [[ "$out" == ERROR* ]]; ck "ⓜ A 객체가 로컬에 없음 → ERROR rc3(통과 0)" $?
# ⓘ 자율 ON: 승인 파일은 A 로 찾는다
bash "$BIN/ft-autonomy.sh" on >/dev/null 2>&1; own 12; adv b.txt m9; mrg 12; setpr 12; M="$(omain)"; : > "$STUB_LOG"
NOAP=1 land 12 --approve-sha "$A"; [ "$rc" = 2 ] && [[ "$out" == *approve-merge* ]] && [ "$(omain)" = "$M" ]; ck "ⓘ 자율 ON · A 승인 파일 없음 → rc2" $?
bash "$BIN/ft-autonomy.sh" approve-merge "$S" >/dev/null 2>&1; NOAP=1 land 12 --approve-sha "$A"; [ "$rc" = 2 ] && [ "$(omain)" = "$M" ]; ck "ⓘ S 만 승인(A 아님) → 여전히 rc2" $?
bash "$BIN/ft-autonomy.sh" approve-merge "$A" >/dev/null 2>&1; land 12 --approve-sha "$A"; okland; ck "ⓘ A 승인 파일 → EQUIV 착지" $?
[ "$(G config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
