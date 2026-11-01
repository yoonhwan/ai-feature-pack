#!/usr/bin/env bash
# test_hil_oppa_only_r1275.sh — approve-merge --oppa-slack (r1275 · 판정 2904): R1~R13·R6b + 변이 7 (카드 «반례 집합» 동결)
# 가짜 슬랙 조회(FT_SLACK_REPLIES_CMD = replies JSON 파일 cat) · 격리 루트 · 네트워크 0 · 자기 재호출 0 · 고정 sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"
P=1793500000.500000; OPPA=U0AC2JF0M7D; X="$(sha 71)"; export FT_SLACK_REPLIES_CMD="cat $T/replies.json"
rep() { printf '%s' "$1" > "$T/replies.json"; }
par() { printf '{"ts":"%s","text":"승인 요청 %s"%s}' "${3:-$P}" "$1" "${2:+,$2}"; }   # par <본문 sha> [추가 칸] [ts]
okrep() { printf '{"ts":"%s","user":"%s","text":"ok"}' "$1" "$2"; }
body() { printf '{"ok":%s,"messages":[%s]}' "${2:-true}" "$1"; }
nothing_written() { [ "$(lines)" = "$n0" ] && [ ! -e "$AP/${1:-$X}" ]; }
appr() { run a approve-merge "$@"; }
fresh; G1="$T/g1"; cp -R "$S" "$G1"; grant --for 10h --max 5 --classes docs >/dev/null; G2="$T/g2"; cp -R "$S" "$G2"   # 상태 2벌(범위 없음 · 범위 S1 살아 있음)을 한 번만 만들고 사례마다 복사(on 한 번 ≈4초)
scoped() { rm -rf "$S"; cp -R "$G2" "$S"; n0="$(lines)"; }
unscoped() { rm -rf "$S"; cp -R "$G1" "$S"; n0="$(lines)"; }
good() { rep "$(body "$(par "$X"),$(okrep 1793500001.000000 $OPPA)")"; }

# ===== R1 R2 판정기 =====
export FT_SCOPE_STATUS_CMD="echo [범위 승인 S1 · A1 · x]"; J="python3 $BIN/ft_scope_plan_judge.py --plan"
printf 'bash ft-autonomy.sh approve-merge %s\n' "$X" > "$T/p1"; run $J "$T/p1"; [ $rc = 1 ] && has '^reject '; ck "R1 범위 살아 있음 · --oppa-slack 없음 → reject(지금 그대로)" $?
printf 'bash ft-autonomy.sh approve-merge %s --oppa-slack %s\n' "$X" "$P" > "$T/p2"; run $J "$T/p2"; [ $rc = 0 ] && has '^ok$'; ck "R2 approve-merge --oppa-slack <ts> → 판정기 ok" $?
unset FT_SCOPE_STATUS_CMD

# ===== 확인 (범위 없음 · R3~R9) =====
unscoped; good; appr "$X" --oppa-slack "$P"
[ $rc = 0 ] && has "APPROVED $X" && has "SLACK-OK $X parent=$P reply=1793500001.000000" && grep -q "^approve-merge $X A1 [0-9]*$" "$LOG" && [ -f "$AP/$X" ]; ck "R3 부모 글에 sha · 오빠 답글(부모 뒤) → APPROVED + SLACK-OK" $?
unscoped; rep "$(body "$(par "$X")")"; appr "$X" --oppa-slack "$P"; [ $rc = 2 ] && has '^REJECT 오빠 슬랙 승인 확인 실패' && nothing_written; ck "R4 답글 0 → REJECT rc2 · 기록 0" $?
unscoped; rep "$(body "$(par "$X"),$(okrep 1793500001.000000 U999OTHER)")"; appr "$X" --oppa-slack "$P"; [ $rc = 2 ] && nothing_written; ck "R5 오빠 아닌 사용자 답글 → REJECT" $?
unscoped; rep "$(body "$(par "$X"),$(okrep 1793500000.500000 $OPPA)")"; appr "$X" --oppa-slack "$P"; [ $rc = 2 ] && nothing_written; ck "R6 답글 ts == 부모 ts → REJECT" $?
unscoped; rep "$(body "$(par "$X" '' 1793500000.500001),$(okrep 1793500000.500000 $OPPA)")"; appr "$X" --oppa-slack 1793500000.500001; [ $rc = 2 ] && nothing_written; ck "R6 같은 초 · 마이크로초가 앞섬 → REJECT" $?
unscoped; rep "$(body "$(par "$X" '' 1793500000.500001),$(okrep 1793500000.500002 $OPPA)")"; appr "$X" --oppa-slack 1793500000.500001; [ $rc = 0 ] && has "APPROVED $X"; ck "R6b 같은 초 · 1마이크로초 뒤 → APPROVED" $?
unscoped; rep "$(body "$(par "${X}a"),$(okrep 1793500001.000000 $OPPA)")"; appr "$X" --oppa-slack "$P"; r7a=$rc; nothing_written; w1=$?
rep "$(body "$(par "${X%?}0"),$(okrep 1793500001.000000 $OPPA)")"; appr "$X" --oppa-slack "$P"; [ $r7a = 2 ] && [ $rc = 2 ] && [ $w1 = 0 ] && nothing_written; ck "R7 더 긴 16진 · 앞 39자만 같은 sha 만 있음 → REJECT" $?
unscoped; rep "$(body "$(par "$X" '"edited":{"user":"U1","ts":"1793500002.000000"}'),$(okrep 1793500001.000000 $OPPA)")"; appr "$X" --oppa-slack "$P"; [ $rc = 2 ] && nothing_written; ck "R8 오빠 답글 뒤 부모 수정(edited.ts > 답글 ts) → REJECT" $?
unscoped; rep "$(body "$(par "$X" '"edited":{"user":"U1","ts":"1793500000.900000"}'),$(okrep 1793500001.000000 $OPPA)")"; appr "$X" --oppa-slack "$P"; [ $rc = 0 ]; ck "R8b 답글 앞 부모 수정 → APPROVED" $?
unscoped; ok=0
rep 'not json'; appr "$X" --oppa-slack "$P"; [ $rc = 2 ] && has '판정 불가' && nothing_written || ok=1
rep "$(body "$(par "$X"),$(okrep 1793500001.000000 $OPPA)" false)"; appr "$X" --oppa-slack "$P"; [ $rc = 2 ] && has '판정 불가' && nothing_written || ok=1
rep '{"ok":true,"messages":[{"ts":"1793500000.500000"}]}'; appr "$X" --oppa-slack "$P"; [ $rc = 2 ] && has '판정 불가' && nothing_written || ok=1
rep '{"ok":true}'; appr "$X" --oppa-slack "$P"; [ $rc = 2 ] && has '판정 불가' && nothing_written || ok=1
FT_SLACK_REPLIES_CMD="false" appr "$X" --oppa-slack "$P"; [ $rc = 2 ] && has '판정 불가' && nothing_written || ok=1
[ $ok = 0 ]; ck "R9 조회 rc≠0 · JSON 아님 · ok:false · 칸 빠짐 → 판정 불가 rc2 · 기록 0" $?

# ===== R10~R13 (범위 살아 있음 포함) =====
scoped; good; appr "$(sha 72)" --oppa-slack "$P"; [ $rc = 2 ] && has '질문 글에' && nothing_written "$(sha 72)"; ck "R10 등록 뒤 계획을 고쳐 다른 sha 로 → 실행 때 REJECT" $?
scoped; good; appr "$X" --oppa-slack "$P"; [ $rc = 0 ] && has "APPROVED $X"; ck "R10b 범위 살아 있음 · 확인 통과 sha → APPROVED" $?
unscoped; appr "$X"; [ $rc = 0 ] && has "APPROVED $X" && grep -q "^approve-merge $X A1 [0-9]*$" "$LOG"; ck "R11 인자 없음 · 범위 없음 → 지금과 같은 출력·기록" $?
scoped; appr "$X"; [ $rc = 2 ] && has '^REJECT 범위 승인 S1 중 approve-merge 는 --oppa-slack' && nothing_written; ck "R12 범위 살아 있음 · 인자 없는 approve-merge 직접 실행 → REJECT rc2 · 기록 0" $?
unscoped; good; appr "$X" --oppa-slack "$P"; r1=$rc; appr "$(sha 75)"; r2=$rc; bad=0
while read -r l; do [[ "$l" =~ ^approve-merge\ [0-9a-f]{40}\ (A[0-9]+|OFF)\ [0-9]+$ || "$l" =~ ^[0-9]+$'\t'(on|off)$'\t'A[0-9]+$ ]] || bad=1; done < "$LOG"
[ $r1 = 0 ] && [ $r2 = 0 ] && [ "$(a mode)" = on ] && [ $bad = 0 ]; ck "R13 R3 꼴 승인 직후 R11 → 둘 다 APPROVED · mode on(tamper 아님) · log 줄 APPROVE_RE" $?

# ===== 변이 7 — 복사본 bin 에서 해당 반례가 «통과하지 못해야» 한다(변이가 안 먹으면 그 자체가 FAIL) =====
M="$T/mbin"; MB="$BIN"
mut() { rm -rf "$M"; mkdir "$M"; ln -s "$MB"/* "$M"/; rm "$M/$1"; cp "$MB/$1" "$M/$1"; cp "$MB/$1" "$M/$1.bak"; sed -i.sedbak "$2" "$M/$1"; if cmp -s "$M/$1" "$M/$1.bak"; then rc=0; out="변이 미적용: $2"; ck "변이 적용($1)" 1; fi; BIN="$M"; }   # <파일> <sed>
mut ft_oppa_slack_check.py 's/u == OPPA_SLACK_UID and //'; unscoped; rep "$(body "$(par "$X"),$(okrep 1793500001.000000 U999OTHER)")"; appr "$X" --oppa-slack "$P"; [ $rc != 2 ]; ck "변이 1 user 검사 제거 → R5 가 못 막음(= 시험이 잡음)" $?
mut ft_oppa_slack_check.py 's/t > parent/int(t) > int(parent)/'; unscoped; rep "$(body "$(par "$X" '' 1793500000.500001),$(okrep 1793500000.500002 $OPPA)")"; appr "$X" --oppa-slack 1793500000.500001; [ $rc != 0 ]; ck "변이 2 초 절삭 비교 → R6b 가 깨짐(= 시험이 잡음)" $?
mut ft_oppa_slack_check.py 's/if not re.search(.*$/if sha not in text:/'; unscoped; rep "$(body "$(par "${X}a"),$(okrep 1793500001.000000 $OPPA)")"; appr "$X" --oppa-slack "$P"; [ $rc != 2 ]; ck "변이 3 sha 부분 문자열 검사 → R7 이 못 막음(= 시험이 잡음)" $?
mut ft_oppa_slack_check.py 's/ and (edited is None or dec(edited\["ts"\]) < t)//'; unscoped; rep "$(body "$(par "$X" '"edited":{"user":"U1","ts":"1793500002.000000"}'),$(okrep 1793500001.000000 $OPPA)")"; appr "$X" --oppa-slack "$P"; [ $rc != 2 ]; ck "변이 4 edited 검사 제거 → R8 이 못 막음(= 시험이 잡음)" $?
mut ft_oppa_slack_check.py 's/body.get("ok") is not True/False/'; unscoped; rep "$(body "$(par "$X"),$(okrep 1793500001.000000 $OPPA)" false)"; appr "$X" --oppa-slack "$P"; [ $rc != 2 ]; ck "변이 5 ok:false 통과 → R9 가 못 막음(= 시험이 잡음)" $?
mut ft-autonomy-oppa.sh 's/^    \[\[ "\$st" =~ .*$/    :/'; scoped; appr "$X"; [ $rc != 2 ]; ck "변이 6 실행 때 범위 검사 제거 → R12 가 못 막음(= 시험이 잡음)" $?
mut ft-autonomy.sh 's/line="approve-merge \$sha \$ev \$now"/line="approve-merge $sha $ev $now slack=1"/'; unscoped; good; appr "$X" --oppa-slack "$P"; [ "$(a mode)" = tamper ]; ck "변이 7 log 줄에 slack= 칸 → R13 이 깨짐(tamper · = 시험이 잡음)" $?
BIN="$MB"

echo "단계 합계 ${SECONDS}s"; [ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES: $fail"; exit 1; }
