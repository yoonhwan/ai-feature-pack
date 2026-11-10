#!/usr/bin/env bash
# test_oppa_slack_reply_words_r1606.sh — 끝: ft_oppa_slack_check 가 창 안 오빠 답글의 «내용» 을 본다 (카드 r1606-oppa-slack-check-reply-text-approve-words · BYZ #8243 «tmddls»)
#   ⓐ Red(지금 판 = 작성자만) → ⓑ 오타·모르는 말 = 승인 0 · ⓒ 거절 낱말 = REJECT(승인 뒤여도) · ⓓ 오타 뒤 승인 = 승인 ts 로 OK
#   ⓔ 답글 전체 일치만 · ⓕ 창 규칙 그대로 · ⓖ 기존 길 회귀 0 · ⓗ kit 사본 cmp0 · 변이 M1~M3
# 격리: 임시 루트 · 가짜 슬랙 조회(FT_SLACK_REPLIES_CMD) · 실 Slack 0 · 네트워크 0 · 자기 재호출 0 · 고정 sleep 0
# 안전선(r1041): ulimit -u(현재+64) · timeout 70
NPROC=$(ulimit -u 2>/dev/null || echo 3000); ulimit -u $((NPROC + 64)) 2>/dev/null || true
TO=70
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"
CHECK="$BIN/ft_oppa_slack_check.py"; KITBIN="$ROOT/harness/kit/fable-team/bin"
P=1793500000.500000; A1=1793500001.000000; A2=1793500002.000000; A3=1793500003.000000; A4=1793500004.000000
OPPA=U0AC2JF0M7D; BOT=UBOT1; X="$(sha 71)"
export FT_SLACK_REPLIES_CMD="cat $T/replies.json"
rep() { printf '%s' "$1" > "$T/replies.json"; }
par() { printf '{"ts":"%s","user":"%s","text":"승인 요청 %s"%s}' "$P" "$BOT" "$X" "${1:+,$1}"; }        # par [추가 칸]
op() { printf '{"ts":"%s","user":"%s","text":"%s"}' "$1" "$OPPA" "$2"; }                              # op <ts> <본문>
bot() { printf '{"ts":"%s","user":"%s","text":"%s"}' "$1" "$BOT" "$2"; }
tj() { printf '{"ok":true,"messages":[%s]}' "$(IFS=,; echo "$*")"; }
chk() { run timeout $TO python3 "$CHECK" "$P" "$X"; }
no_ok() { ! grep -q '^SLACK-OK' <<<"$out"; }

# ===== ⓐ Red — «지금 판»(답글 내용 검사 없음)은 오타도 «아니오» 도 승인한다 =====
BASE=9ac9dbe88cf14c190ba4ea6c4cfaaf7cd23c139b   # 팩 origin/main @ 카드 착수(내용 검사 이전 판)
OLD="$T/old/ft_oppa_slack_check.py"; mkdir -p "$T/old"
REPO="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$REPO" ] && git -C "$REPO" show "$BASE:feature-pack/fable-team/legacy/1.x/harness/bin/ft_oppa_slack_check.py" > "$OLD" 2>/dev/null && [ -s "$OLD" ]; then OSRC="팩 base 커밋 ${BASE:0:9}"
else cp "$CHECK" "$OLD"; python3 - "$OLD" <<'PY' && OSRC="M1 사본(내용 검사 뺌)"
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
t = t.replace("if w in REJECT_WORDS]", "if False]").replace("if w in APPROVE_WORDS]", "if True]")
p.write_text(t, encoding="utf-8")
PY
fi
echo "ⓐ 지금 판 출처 = $OSRC"
rep "$(tj "$(par)" "$(op "$A1" tmddls)")"; run timeout $TO python3 "$OLD" "$P" "$X"; [ $rc = 0 ] && grep -q "^SLACK-OK $X parent=$P reply=$A1" <<<"$out"; ck "ⓐ Red 오타 «tmddls» 1개 → 지금 판은 SLACK-OK rc0" $?
rep "$(tj "$(par)" "$(op "$A1" 아니오)")"; run timeout $TO python3 "$OLD" "$P" "$X"; [ $rc = 0 ] && grep -q '^SLACK-OK' <<<"$out"; ck "ⓐ Red 거절 «아니오» 1개 → 지금 판은 SLACK-OK rc0" $?

# ===== ⓑ 오타·모르는 말 = 승인 0 =====
rep "$(tj "$(par)" "$(op "$A1" tmddls)")"; chk
[ $rc = 2 ] && has '^REJECT 오빠 슬랙 승인 확인 실패: 판정 불가: 답글 내용 승인 낱말 아님' && no_ok; ck "ⓑ 답글 «tmddls» → REJECT rc2 «판정 불가: 답글 내용 승인 낱말 아님» · SLACK-OK 0줄" $?

# ===== ⓒ 거절 낱말 = REJECT (승인 뒤여도) =====
rep "$(tj "$(par)" "$(op "$A1" 아니오)")"; chk; [ $rc = 2 ] && has "오빠 거절 답글 reply=$A1" && no_ok; ck "ⓒ 답글 «아니오» → REJECT rc2 «오빠 거절 답글 reply=${A1}»" $?
rep "$(tj "$(par)" "$(op "$A1" 네)" "$(op "$A2" 아니오)")"; chk; [ $rc = 2 ] && has "오빠 거절 답글 reply=$A2" && no_ok; ck "ⓒb 승인(«네») 뒤 거절(«아니오») → REJECT(승인 0)" $?
rep "$(tj "$(par)" "$(op "$A1" 거절)")"; chk; [ $rc = 2 ] && has "오빠 거절 답글 reply=$A1"; ck "ⓒc 답글 «거절» → REJECT" $?

# ===== ⓓ 오타 뒤 승인 = 승인 ts 로 OK =====
rep "$(tj "$(par)" "$(op "$A1" tmddls)" "$(op "$A2" 승인)")"; chk
[ $rc = 0 ] && grep -q "^SLACK-OK $X parent=$P reply=$A2$" <<<"$out"; ck "ⓓ «tmddls» → «승인» → SLACK-OK reply=$A2(오타 ts 아님)" $?

# ===== ⓔ 답글 «전체» 일치만 + 정규화 =====
ok=0; for w in '승인 안 함' '네? 왜요' '확정 보류' '아니오 그래도 승인'; do rep "$(tj "$(par)" "$(op "$A1" "$w")")"; chk; { [ $rc = 2 ] && no_ok; } || { ok=1; echo "승인 0 아님: $w rc=$rc out=${out:0:120}"; }; done; [ $ok = 0 ]; ck "ⓔ «승인 안 함»·«네? 왜요»·«확정 보류»·«아니오 그래도 승인» = 승인 0" $?
ok=0; for w in '네.' '  승인  ' 'OK' '네!'; do rep "$(tj "$(par)" "$(op "$A1" "$w")")"; chk; { [ $rc = 0 ] && grep -q "^SLACK-OK $X parent=$P reply=$A1$" <<<"$out"; } || { ok=1; echo "승인 아님: «$w» rc=$rc out=${out:0:120}"; }; done; [ $ok = 0 ]; ck "ⓔb 정규화(끝 문장부호·앞뒤 공백·영문 소문자) 뒤 일치 = 승인" $?

# ===== ⓕ 창 규칙 그대로 — 창 밖 승인은 무시 =====
rep "$(tj "$(par)" "$(bot "$A2" '4. 다음 질문')" "$(op "$A3" 승인)")"; chk
[ $rc = 2 ] && has '오빠 답글 없음' && no_ok; ck "ⓕ 다음 질문 뒤 «승인» → REJECT(창 밖 승인 무시)" $?
rep "$(tj "$(par "\"edited\":{\"user\":\"U1\",\"ts\":\"$A4\"}")" "$(op "$A1" 승인)")"; chk
[ $rc = 2 ] && has '오빠 답글 없음' && no_ok; ck "ⓕb 부모 수정 뒤 «승인» → REJECT(창 밖)" $?
rep "$(tj "$(par)" "$(op "$A1" 승인)" "$(bot "$A2" '4. 다음 질문')")"; chk
[ $rc = 0 ] && grep -q "reply=$A1$" <<<"$out"; ck "ⓕc 다음 질문 «앞» 승인 → SLACK-OK(창 규칙 안 바뀜)" $?

# ===== ⓖ 기존 길 회귀 0 =====
rep "$(tj "$(par)" "$(op "$A1" tmddls)")"; run timeout $TO python3 "$CHECK" --reply-only "$P"
[ $rc = 0 ] && [ "$out" = "REPLY-SEEN parent=$P reply=$A1" ] && no_ok; ck "ⓖ --reply-only 는 내용 판정 안 함(«tmddls» 도 REPLY-SEEN rc0 · SLACK-OK 0줄)" $?
rep "$(tj "$(par)")"; run timeout $TO python3 "$CHECK" --reply-only "$P"; [ $rc = 3 ] && has '^REPLY-NONE'; ck "ⓖb --reply-only 답글 없음 → rc3 그대로" $?
ok=0; for t in test_approval_gate_r1275.sh test_hil_oppa_only_r1275.sh test_hil_oppa_thread_r1275.sh test_desk_reply_wake_question_r1591.sh; do timeout $TO bash "$HERE/$t" >"$T/$t.log" 2>&1 || { ok=1; echo "rc≠0: $t"; tail -3 "$T/$t.log"; }; done; [ $ok = 0 ]; ck "ⓖc 기존 4시험 rc0(approval_gate·oppa_only·oppa_thread·desk_reply_wake_question)" $?

# ===== ⓗ kit 사본 cmp0 =====
cmp -s "$CHECK" "$KITBIN/ft_oppa_slack_check.py"; ck "ⓗ bin·kit cmp0(ft_oppa_slack_check.py)" $?

# ===== 변이 M1~M3 — 복사본에서 한 곳만 바꾼다(안 먹으면 그 자체가 FAIL) =====
mut() {  # mut <이름> <바꿀 글> <바꾼 글> → $MUT 에 그 파일 경로
  local d="$T/mut-$1"; mkdir -p "$d"; cp "$CHECK" "$d/ft_oppa_slack_check.py"; MUT="$d/ft_oppa_slack_check.py"
  python3 - "$MUT" "$2" "$3" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
assert sys.argv[2] in t, "변이 미적용: " + sys.argv[2]
p.write_text(t.replace(sys.argv[2], sys.argv[3], 1), encoding="utf-8")
PY
  [ $? = 0 ] || { rc=0; out="변이 미적용: $2"; ck "변이 적용($1)" 1; }
}
runm() { run timeout $TO python3 "$MUT" "$P" "$X"; }
mut M1 'if w in REJECT_WORDS]' 'if False]'; python3 - "$MUT" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
p.write_text(t.replace("if w in APPROVE_WORDS]", "if True]", 1), encoding="utf-8")
PY
rep "$(tj "$(par)" "$(op "$A1" tmddls)")"; runm; [ $rc != 2 ]; ck "M1 내용 검사 뺌(작성자만) → ⓑ 가 못 막음(= 시험이 잡음)" $?
mut M2 'if w in APPROVE_WORDS]' 'if any(a in w for a in APPROVE_WORDS)]'
rep "$(tj "$(par)" "$(op "$A1" '승인 안 함')")"; runm; [ $rc != 2 ]; ck "M2 전체 일치를 부분 포함으로 → ⓔ «승인 안 함» 이 못 막음(= 시험이 잡음)" $?
mut M3 'if w in REJECT_WORDS]' 'if False]'
rep "$(tj "$(par)" "$(op "$A1" 네)" "$(op "$A2" 아니오)")"; runm; [ $rc != 2 ] && grep -q "^SLACK-OK $X parent=$P reply=$A1$" <<<"$out"; ck "M3 거절 우선 뺌 → ⓒ «네» → «아니오» 가 승인됨(= 시험이 잡음)" $?

echo "단계 합계 ${SECONDS}s"; [ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES: $fail"; exit 1; }
