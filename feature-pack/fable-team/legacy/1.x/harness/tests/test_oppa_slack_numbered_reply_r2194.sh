#!/usr/bin/env bash
# test_oppa_slack_numbered_reply_r2194.sh — 끝: 묶음 할 일 글에 오빠가 «1.네 / 2.네» 로 답하면 그 번호 항목의 sha 만 승인·거절로 읽힌다 (카드 r2194-oppa-slack-numbered-reply-binds-item)
#   ②~⑭ · bin·kit cmp0 · 변이 M1~M8(+원본 대조) · ① 기존 시험 12개는 따로 돌린다(시험 1개 70초)
#   FT_R2194_CHECK = 판정기 경로 덮어쓰기(기준판 Red 대조용) · FT_R2194_BASE = 기준판 경로(⑪ 출력 같은 바이트 대조 · 없으면 고정 문자열만)
# 격리: 임시 루트 · 가짜 슬랙 조회(FT_SLACK_REPLIES_CMD) · 실 Slack 0 · 네트워크 0 · 고정 sleep 0 · 안전선 ulimit -u(현재+64) · timeout 70
NPROC=$(ulimit -u 2>/dev/null || echo 3000); ulimit -u $((NPROC + 64)) 2>/dev/null || true
TO=70
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"
CHECK="${FT_R2194_CHECK:-$BIN/ft_oppa_slack_check.py}"
P=1794000000.000100; E=1794000000.000150; L=1794000000.000200; L2=1794000000.000250; A=1794000000.000300; A2=1794000000.000400; Z=1794000000.000500
OPPA=U0AC2JF0M7D; S1="$(sha 9001)"; S2="$(sha 9025)"; SE="$(sha 7)"
export FT_SLACK_REPLIES_CMD="cat $T/replies.json"
bot() { local e=""; [ -n "${3:-}" ] && e=",\"edited\":{\"ts\":\"$3\"}"; printf '{"ts":"%s","user":"UBOT1","bot_id":"B0BOT1","text":"%s"%s}' "$1" "$2" "$e"; }  # bot <ts> <글> [고친 ts]
opp() { printf '{"ts":"%s","user":"%s","text":"%s"}' "$1" "$OPPA" "$2"; }
thread() { local IFS=,; printf '{"ok":true,"messages":[%s]}' "$*" > "$T/replies.json"; }
ROOT2="[오빠 할 일]\\n⑤ 오빠 할 일 3 · PR 9025 착지\\n9025 $S2"            # 실사건 꼴 루트(고친 시각 있음 · 동그라미 번호 · 열쇠 줄)
LIST2="[알림] 오빠 할 일 목록\\n1. ENFORCE 켜기 «네 ENFORCE»\\n2. PR 9025 착지 «네 9025»"  # 실사건 꼴 목록(40hex 0)
real() { thread "$(bot $P "$ROOT2" $E)" "$(bot $L "$LIST2")" "$(opp $A "$1")"; }  # real <답>
ok_() { run timeout $TO python3 "${F:-$CHECK}" "$P" "$1"; [ "$rc" = 0 ] && [ "$out" = "SLACK-OK $1 parent=$P reply=${2:-$A}" ]; }  # ok_ <sha> [답 ts]
no_() { run timeout $TO python3 "${F:-$CHECK}" "$P" "$1"; [ "$rc" = 2 ] && ! grep -q '^SLACK-OK' <<<"$out" && { [ -z "${2:-}" ] || grep -q -- "$2" <<<"$out"; }; }  # no_ <sha> [사유 글]
UJ="판정 불가"
all() { local f=$1 bad=0; shift; for c in "$@"; do eval "$c" || { bad=1; echo "  어긋남: $c :: rc=$rc ${out:0:120}"; }; done; return $bad; }

# ② 실사건 꼴
all "" 'real "1.네\\n2.네"; ok_ $S2'; ck "② 루트(고침)+[알림] 목록+«1.네 ⏎ 2.네» → SLACK-OK reply=답" $?
# ③ 번호별 거절
Q3="승인 요청\\n1. PR 9001 착지\\n2. PR 9025 착지\\n9001 $S1\\n9025 $S2"
all "" 'thread "$(bot $P "$Q3")" "$(opp $A "1.네 / 2.아니오")"; ok_ $S1' 'no_ $S2 "오빠 거절 답글 reply=$A"'; ck "③ «1.네 / 2.아니오» → 9001 SLACK-OK · 9025 거절" $?
# ④ 일부만 답함
all "" 'real "2.네"; ok_ $S2' 'real "2) 네 넓혀요"; ok_ $S2' 'real "1.네"; no_ $S2'; ck "④ «2.네»·«2) 네 넓혀요» → SLACK-OK · «1.네» 만 → 승인 0" $?
# ⑤ 고친 목록
all "" 'thread "$(bot $P "$ROOT2" $E)" "$(bot $L "$LIST2" $A2)" "$(opp $A "2.네")"; no_ $S2 "$UJ"' \
       'thread "$(bot $P "$ROOT2" $E)" "$(bot $L "$LIST2" $L2)" "$(opp $A "2.네")"; ok_ $S2'; ck "⑤ 목록 edited 답 뒤 → 승인 0 · 답 앞 → SLACK-OK" $?
# ⑥ 열쇠 겹침
QE="[오빠 할 일]\\nENFORCE $SE\\n9025 $S2"
lst() { thread "$(bot $P "${3:-$ROOT2}")" "$(bot $L "[알림]\\n$1")" "$(opp $A "$2")"; }   # lst <목록 줄> <답> [루트]
S6=('lst "1. PR 9025 먼저\\n2. PR 9025 착지" "2.네"' 'lst "1. PR 9025 먼저\\n2. PR 9025 착지" "1.네\\n2.네"' 'lst "1. 다른 일\\n2. PR 9025 ENFORCE 같이" "2.네" "$QE"' 'lst "1. 다른 일\\n2. PR 9025\\n2. 또 다른 일" "2.네"')
all "" "${S6[0]}; no_ \$S2 \"\$UJ\"" "${S6[1]}; no_ \$S2 \"\$UJ\"" "${S6[2]}; no_ \$S2 \"\$UJ\"" "${S6[3]}; no_ \$S2 \"\$UJ\""; ck "⑥ 항목 1 에도 9025 · 한 항목에 열쇠 둘 · «2.» 줄 둘 → 승인 0" $?
# ⑦ 열쇠 줄 없음
all "" 'lst "1. 다른 일\\n2. PR 9025" "2.네" "[오빠 할 일]\\nPR 9025 $S2 착지"; no_ $S2 "$UJ"' \
       'lst "1. 다른 일\\n2. PR 9025" "2.네" "[오빠 할 일]\\n9025 $S2\\n9025 $S1"; no_ $S2 "$UJ"' \
       'lst "1. 다른 일\\n2. PR 25" "2.네" "[오빠 할 일]\\n25 $S2"; no_ $S2 "$UJ"'; ck "⑦ sha 가 문장 속 · 같은 열쇠 sha 둘 · 열쇠 2자 → 승인 0" $?
# ⑧ 목록 여럿
QA="[오빠 할 일]\\n9001 $S1\\n9025 $S2"
all "" 'thread "$(bot $P "$QE")" "$(bot $L "[알림]\\n1. ENFORCE\\n2. PR 9025")" "$(bot $L2 "[알림]\\n1. PR 9025 착지 뒤 확인")" "$(opp $A "2.네")"; no_ $S2 "$UJ"' \
       'thread "$(bot $P "$QE")" "$(bot $L "[알림]\\n1. ENFORCE\\n2. PR 9025")" "$(bot $L2 "[알림]\\n1. PR 9025 착지 뒤 확인")" "$(opp $A "1.네")"; no_ $S2 "$UJ"' \
       'thread "$(bot $P "$QA")" "$(bot $L "[알림]\\n1. 다른 일\\n2. PR 9001")" "$(bot $L2 "[알림]\\n1. 또 다른 일\\n2. PR 9025")" "$(opp $A "2.네")"; no_ $S1 "$UJ"' 'no_ $S2 "$UJ"' \
       'thread "$(bot $P "$ROOT2" $E)" "$(bot $L "$LIST2")" "$(opp $A "2.네")" "$(bot $Z "[알림]\\n1. PR 9025 다시")"; ok_ $S2'; ck "⑧ 답 앞 목록 둘 → «2.네»·«1.네» 승인 0 · A2=9001/B2=9025 «2.네» → 둘 다 0 · 답 뒤 목록 = 세지 않음 SLACK-OK" $?
# ⑨ 다른 작성자의 목록(user·bot_id 둘 다 다름)
all "" 'thread "$(bot $P "$ROOT2")" "{\"ts\":\"$L\",\"user\":\"UOTHER\",\"bot_id\":\"B0OTHER\",\"text\":\"[알림]\\n1. 다른 일\\n2. PR 9025\"}" "$(opp $A "2.네")"; no_ $S2 "$UJ"'; ck "⑨ 다른 작성자 목록 → 승인 0" $?
# ⑩ 섞인 답
all "" 'real "2.네 / 2.아니오"; no_ $S2' 'real "2.네\\n근데 잠깐"; no_ $S2' 'real "2.네?"; no_ $S2' 'real "2.승인 안 함"; no_ $S2'; ck "⑩ «2.네 / 2.아니오»·«2.네 ⏎ 근데 잠깐»·«2.네?»·«2.승인 안 함» → 승인 0" $?
# ⑪ 번호 없는 답 = 기준판 그대로
same() { [ -z "${FT_R2194_BASE:-}" ] && return 0; local o=$out r=$rc; run timeout $TO python3 "$FT_R2194_BASE" "$P" "$S2"; [ "$out" = "$o" ] && [ "$rc" = "$r" ]; }
all "" 'real "네"; ok_ $S2 && same' 'real "아니오"; no_ $S2 && [ "$out" = "REJECT 오빠 슬랙 승인 확인 실패: 오빠 거절 답글 reply=$A" ] && same' 'real "네 9025"; ok_ $S2 && same'; ck "⑪ «네» → SLACK-OK · «아니오» → 거절 · «네 9025» → SLACK-OK · 출력 기준판과 같음" $?
# ⑫ 답 둘
all "" 'thread "$(bot $P "$ROOT2" $E)" "$(bot $L "$LIST2")" "$(opp $A "2.네")" "$(opp $A2 "2.아니오")"; no_ $S2 "오빠 거절 답글 reply=$A2"' \
       'thread "$(bot $P "$ROOT2" $E)" "$(bot $L "$LIST2")" "$(opp $A "1.네")" "$(opp $A2 "2.네")"; ok_ $S2 $A2'; ck "⑫ «2.네» 뒤 «2.아니오» → 거절 · «1.네» 뒤 «2.네» → SLACK-OK reply=둘째" $?
# ⑬ 낱말 경계
all "" 'lst "1. ENFORCE\\n2. PR 19025" "2.네"; no_ $S2 "$UJ"' 'lst "1. ENFORCE\\n2. PR 90250" "2.네"; no_ $S2 "$UJ"'; ck "⑬ «PR 19025»·«90250» → 승인 0" $?
# ⑭ 답 뒤 고친 다른 글 — 판정 sha = ENFORCE(목록 A 1번)
b14() { thread "$(bot $P "$QE")" "$(bot $L "[알림]\\n1. ENFORCE\\n2. PR 9025")" "$(bot $L2 "[알림] 정리됨" "$1")" "$(opp $A "1.네")"; }
all "" 'b14 $A2; no_ $SE "$UJ"' 'b14 $L2; ok_ $SE' 'b14 $A; no_ $SE "$UJ"'; ck "⑭ 목록 B 를 답 뒤에 고침 → 승인 0 · 답 앞 → SLACK-OK(A 1번 = ENFORCE) · edited = 답 ts → 승인 0" $?
cmp -s "$BIN/ft_oppa_slack_check.py" "$ROOT/harness/kit/fable-team/bin/ft_oppa_slack_check.py"; ck "bin·kit cmp0" $?

[ -n "${FT_R2194_CHECK:-}" ] && { echo "단계 합계 ${SECONDS}s (판정기 덮어씀 · 변이 생략)"; [ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES: $fail"; exit 1; }; }
mut() {  # mut <이름> <바꿀 글> <바꾼 글> → $MUT · 안 먹으면 FAIL
  MUT="$T/mut-$1.py"; cp "$CHECK" "$MUT"
  python3 - "$MUT" "$2" "$3" <<'PY' || { rc=1; out="변이 미적용: $1"; ck "변이 적용($1)" 1; }
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
assert t.count(sys.argv[2]) == 1, sys.argv[2]
p.write_text(t.replace(sys.argv[2], sys.argv[3], 1), encoding="utf-8")
PY
}
pair() { local c=$1; F=$MUT eval "$c" && ! F=$CHECK eval "$c"; }  # 변이 = 승인됨(시험이 잡음) · 원본 = 승인 0(반대 결과)
mut M1 'nr = numbered(m)' 'nr = None'; ! F=$MUT eval 'real "1.네\\n2.네"; ok_ $S2' && F=$CHECK eval 'real "1.네\\n2.네"; ok_ $S2'; ck "M1 번호 답 판독 뺌 → ② 승인 0 · 원본 SLACK-OK" $?
mut M2 'nr.get(n)' 'next(iter(nr.values()))'; pair 'real "1.네"; ok_ $S2'; ck "M2 아무 조각 → ④ «1.네» 만 승인 · 원본 0" $?
mut M3 '    if any(m.get("edited") is not None' '    if False and any(m.get("edited") is not None'; pair 'thread "$(bot $P "$ROOT2" $E)" "$(bot $L "$LIST2" $A2)" "$(opp $A "2.네")"; ok_ $S2'; ck "M3 고친 시각 검사 두 문장 다 뺌 → ⑤ 승인 · 원본 0" $?
mut M4 'len(hit) != 1' 'len(hit) < 1'; pair "${S6[1]}; ok_ \$S2"; ck "M4 항목 1개 이상 → ⑥ 승인 · 원본 0" $?
mut M5 'set(me) & {m.get("user"), m.get("bot_id")} - {None}' 'True'; pair 'thread "$(bot $P "$ROOT2")" "{\"ts\":\"$L\",\"user\":\"UOTHER\",\"bot_id\":\"B0OTHER\",\"text\":\"[알림]\\n1. 다른 일\\n2. PR 9025\"}" "$(opp $A "2.네")"; ok_ $S2'; ck "M5 목록 작성자 검사 뺌 → ⑨ 승인 · 원본 0" $?
mut M6 '(?<![A-Za-z0-9_-])%s(?![A-Za-z0-9_-])' '%s'; pair 'lst "1. ENFORCE\\n2. PR 19025" "2.네"; ok_ $S2'; ck "M6 낱말 경계 뺌 → ⑬ 승인 · 원본 0" $?
mut M7 'len(lists) != 1' 'not lists'; pair 'thread "$(bot $P "$QE")" "$(bot $L "[알림]\\n1. ENFORCE\\n2. PR 9025")" "$(bot $L2 "[알림]\\n1. PR 9025 착지 뒤 확인")" "$(opp $A "1.네")"; ok_ $S2'; ck "M7 가장 최근 목록 → ⑧ «1.네» 승인 · 원본 0" $?
mut M8 'for m in pool)' 'for m in [lm])'; pair 'b14 $A2; ok_ $SE'; ck "M8 고친 시각 검사 고른 목록에만 → ⑭ 답 뒤 고친 꼴 승인 · 원본 0" $?

echo "단계 합계 ${SECONDS}s"; [ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES: $fail"; exit 1; }
