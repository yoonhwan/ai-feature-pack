#!/usr/bin/env bash
# test_hil_oppa_thread_r1275.sh — 단계 3 (오빠 «왜 자꾸 되물어?»): 결정 스레드 안 질문 글도 부모로 읽는다 · U1~U8 + 변이 X1~X3 (카드 «반례 집합(단계 3)» 동결)
# 가짜 슬랙 조회(FT_SLACK_REPLIES_CMD = env FT_SLACK_TS 로 r-<ts>.json 을 고르는 스크립트 · 호출마다 calls.log 1줄) · 격리 루트 · 네트워크 0 · 자기 재호출 0 · 고정 sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"
R=1793699000.000000; Q=1793700000.100000; Q2=1793700050.000000; A=1793700100.000000; OPPA=U0AC2JF0M7D; BOT=UBOT1; X="$(sha 81)"
cat > "$T/fake.sh" <<EOF
#!/usr/bin/env bash
echo "\$FT_SLACK_TS" >> "$T/calls.log"
f="$T/r-\$FT_SLACK_TS.json"; [ -f "\$f" ] || f="$T/r-default.json"; cat "\$f"
EOF
export FT_SLACK_REPLIES_CMD="bash $T/fake.sh"
msg() { printf '{"ts":"%s","user":"%s","text":"%s"%s}' "$1" "$2" "$3" "${4:+,$4}"; }   # msg <ts> <user> <본문> [추가 칸]
root() { msg "$R" "$BOT" "결정 스레드" "\"thread_ts\":\"$R\""; }
qmsg() { msg "$Q" "$BOT" "${1:-3. 승인 요청 $X}" "\"thread_ts\":\"$R\"${2:+,$2}"; }   # 스레드 답글꼴 질문 글 [본문] [추가 칸]
tj() { printf '{"ok":true,"messages":[%s]}' "$(IFS=,; echo "$*")"; }
put() { printf '%s' "$2" > "$T/r-$1.json"; }   # put <ts|default> <json>
reset() { rm -f "$T"/r-*.json "$T/calls.log"; : > "$T/calls.log"; }
ncalls() { wc -l < "$T/calls.log" | tr -d ' '; }
chk() { run python3 "$BIN/ft_oppa_slack_check.py" "$Q" "$X"; }
yes_() { [ $rc = 0 ] && has "^SLACK-OK $X parent=$Q reply=$A$"; }

# ===== U1 U2 질문 글이 스레드 답글 =====
reset; put default "$(tj "$(root)" "$(qmsg)" "$(msg $A $OPPA 예)")"; chk; yes_ && [ "$(ncalls)" = 1 ]; ck "U1 스레드 안 질문 글 · 조회가 루트부터 줌 → SLACK-OK parent=Q reply=A rc0 (조회 1회)" $?
reset; put "$Q" "$(tj "$(qmsg)")"; put "$R" "$(tj "$(root)" "$(qmsg)" "$(msg $A $OPPA 예)")"; chk; yes_ && [ "$(ncalls)" = 2 ]; ck "U2 ts=Q 조회가 [Q] 하나 → 루트 R 로 다시 조회 → SLACK-OK (조회 2회)" $?

# ===== U3 U4 답글 창 =====
reset; put default "$(tj "$(root)" "$(qmsg)" "$(msg $Q2 $BOT '4. 다음 질문')" "$(msg $A $OPPA 예)")"; chk; [ $rc = 2 ] && has '^REJECT 오빠 슬랙 승인 확인 실패: 오빠 답글 없음'; ck "U3 오빠 글이 다음 질문(같은 작성자 Q2) 뒤 → REJECT rc2" $?
reset; put default "$(tj "$(root)" "$(qmsg)" "$(msg $A UOTHER 예)")"; chk; [ $rc = 2 ] && has '^REJECT 오빠 슬랙 승인 확인 실패: 오빠 답글 없음'; ck "U4 창 안에 오빠 아닌 사람 글만 → REJECT" $?
reset; put default "$(tj "$(root)" "$(qmsg)" "$(msg 1793700010.000000 $OPPA 승인)" "$(msg $Q2 $BOT '4. 다음 질문')" "$(msg $A $OPPA 예)")"; chk; [ $rc = 0 ] && has "reply=1793700010.000000"; ck "U3b 오빠 글이 다음 질문 앞 → SLACK-OK(reply = 앞 글)" $?   # r1606: 답글 내용 판정(«먼저» 는 승인 낱말 아님) → 픽스처 답글을 «승인» 으로

# ===== U5 질문 글 못 찾음 · 조회 2회 상한 =====
reset; put "$Q" "$(tj "$(qmsg)")"; put "$R" "$(tj "$(root)" "$(msg $A $OPPA 예)")"; chk; [ $rc = 2 ] && has '^REJECT 오빠 슬랙 승인 확인 실패: 판정 불가' && [ "$(ncalls)" = 2 ]; ck "U5 루트 조회에도 질문 글 없음 → 판정 불가 rc2 · 조회 2회(3번째 0)" $?
reset; put default "$(tj "$(root)" "$(msg $A $OPPA 예)")"; chk; [ $rc = 2 ] && has '^REJECT 오빠 슬랙 승인 확인 실패: 판정 불가' && [ "$(ncalls)" -le 2 ]; ck "U5b 두 조회 모두 질문 글 없음(같은 응답) → 판정 불가 rc2 · 조회 ≤2" $?

# ===== U6 질문 글 sha 없음 · 수정 =====
reset; put default "$(tj "$(root)" "$(qmsg '3. 승인 요청 다른 것')" "$(msg $A $OPPA 예)")"; chk; [ $rc = 2 ] && has '질문 글에'; ck "U6 질문 글에 sha 없음 → REJECT" $?
reset; put default "$(tj "$(root)" "$(qmsg '' "\"edited\":{\"user\":\"U1\",\"ts\":\"1793700200.000000\"}")" "$(msg $A $OPPA 예)")"; chk; [ $rc = 2 ] && has '오빠 답글 없음'; ck "U6b 오빠 답 뒤 질문 글 수정(edited.ts > 답 ts) → REJECT" $?

# ===== U7 회귀 — 질문 글 = 루트 · 다음 질문 없음 · 다음 질문 앞 오빠 글 =====
reset; put default "$(tj "$(msg $Q $BOT "3. 승인 요청 $X")" "$(msg $A $OPPA 예)")"; chk; yes_; ck "U7 질문 글 = 루트 · 다음 질문 없음 → 지금 동작 그대로 SLACK-OK" $?
reset; put default "$(tj "$(msg $Q $BOT "3. 승인 요청 $X" "\"thread_ts\":\"$Q\"")" "$(msg $Q2 $BOT '4. 다음')" "$(msg $A $OPPA 예)")"; chk; [ $rc = 2 ]; ck "U7b 루트 질문 글 뒤 같은 작성자 다음 글 뒤의 오빠 글 → REJECT(창 규칙이 루트에도)" $?

# ===== 끝까지 — approve-merge 안에서(범위 없음 · 스레드 안 질문 글) =====
fresh; reset; put default "$(tj "$(root)" "$(qmsg)" "$(msg $A $OPPA 예)")"; run a approve-merge "$X" --oppa-slack "$Q"
[ $rc = 0 ] && has "APPROVED $X" && has "SLACK-OK $X parent=$Q reply=$A" && grep -q "^approve-merge $X A1 [0-9]*$" "$LOG" && [ -f "$AP/$X" ]; ck "E1 approve-merge --oppa-slack <스레드 안 질문 글 ts> → APPROVED + SLACK-OK · 기록 꼴 그대로" $?

# ===== U8 bin·kit 같은 판 =====
KB="$ROOT/harness/kit/fable-team/bin"; ok=0
for f in ft_oppa_slack_check.py ft-autonomy-oppa.sh ft-autonomy.sh ft_scope_plan_judge.py; do cmp -s "$BIN/$f" "$KB/$f" || { ok=1; echo "다름: $f"; }; done
[ $ok = 0 ]; ck "U8 bin·kit cmp0(4파일)" $?

# ===== 변이 X1~X3 — 복사본 bin 에서 해당 반례가 «통과하지 못해야» 한다(변이가 안 먹으면 그 자체가 FAIL) =====
M="$T/mbin"; MB="$BIN"
mut() { rm -rf "$M"; mkdir "$M"; ln -s "$MB"/* "$M"/; rm "$M/$1"; cp "$MB/$1" "$M/$1"; cp "$MB/$1" "$M/$1.bak"; sed -i.sedbak "$2" "$M/$1"; if cmp -s "$M/$1" "$M/$1.bak"; then rc=0; out="변이 미적용: $2"; ck "변이 적용($1)" 1; fi; BIN="$M"; }
mut ft_oppa_slack_check.py 's/if q is not None and (root in (None, ts) or msgs\[0\].get("ts") == root):/if q is not None and msgs[0].get("ts") == ts:/'
reset; put default "$(tj "$(root)" "$(qmsg)" "$(msg $A $OPPA 예)")"; chk; [ $rc != 0 ]; ck "X1 첫 글 ts ≠ Q 면 바로 판정 불가(지금 판) → U1 이 깨짐(= 시험이 잡음)" $?
mut ft_oppa_slack_check.py 's/^        target = root.*$/        break/'
reset; put "$Q" "$(tj "$(qmsg)")"; put "$R" "$(tj "$(root)" "$(qmsg)" "$(msg $A $OPPA 예)")"; chk; [ $rc != 0 ]; ck "X2 루트 재조회 뺌 → U2 가 깨짐(= 시험이 잡음)" $?
mut ft_oppa_slack_check.py 's/(nxt is None or t < nxt) and //'
reset; put default "$(tj "$(root)" "$(qmsg)" "$(msg $Q2 $BOT '4. 다음 질문')" "$(msg $A $OPPA 예)")"; chk; [ $rc != 2 ]; ck "X3 창 끝 검사 뺌 → U3 이 못 막음(= 시험이 잡음)" $?
BIN="$MB"

echo "단계 합계 ${SECONDS}s"; [ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES: $fail"; exit 1; }
