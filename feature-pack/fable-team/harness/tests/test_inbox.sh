#!/usr/bin/env bash
# test_inbox.sh — ft-inbox.sh(ingest·show·mark·report·archive) + mbox.sh send 훅 시험.
# 전부 mktemp 임시 FT_ROOT(가짜 mailbox.jsonl·bodies/). r1560 퇴역: haiku 호출·classify 자식·show --compact 사례는 «없어졌음» 기대로 바꿨다(스텁은 «불리면 파일에 적는다»). 실제 mbox·claude 호출 0 · 라이브 .fable-team 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
INBOX="$REPO/harness/bin/ft-inbox.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_ROOT="$T/root"; mkdir -p "$FT_ROOT/.fable-team/comm/bodies"
MB="$FT_ROOT/.fable-team/comm/mailbox.jsonl"
Q="$FT_ROOT/.fable-team/state/inbox"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

# 분류기 스텁(r1560 퇴역): 불리면 «불렸다» 를 파일에 적는다 — 0 호출을 그 파일 부재로 본다
printf '#!/bin/sh\necho called >> "%s/stub-called"\ncat >/dev/null\nexit 1\n' "$T" > "$T/haiku-boom.sh"; chmod +x "$T/haiku-boom.sh"
export FT_INBOX_HAIKU="$T/haiku-boom.sh"

add_mail() {  # <seq> <to> <from> <body>
  python3 - "$MB" "$@" <<'PY'
import json, sys
p, seq, to, frm, body = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
open(p, "a", encoding="utf-8").write(json.dumps({"seq": seq, "ts": "2026-10-08T15:00:00", "to": to, "from": frm, "body": body}, ensure_ascii=False) + "\n")
PY
}
field() {  # <큐파일> <seq> <키>
  python3 -c 'import json,sys
for l in open(sys.argv[1]):
    x=json.loads(l)
    if x["seq"]==int(sys.argv[2]): print(x[sys.argv[3]])' "$@"
}
M=master-x; ME="$M#9"; export FT_SEAT="$ME"  # R326: mark·report 는 호출 좌석 큐만
ing() { add_mail "$1" "${3:-$ME}" "${4:-a#1}" "$2"; bash "$INBOX" ingest "$1" >/dev/null 2>&1; }

# 1) 분류표 6 + 미상(r1560 퇴역: 미상은 규칙표 밖 · 라벨·자식 0)
ing 101 "[a#1->$ME] 오빠 원문: 이것 확인해줘"
ing 102 "[a#1->$ME] [HIL] 행#3 질문"
ing 103 "[a#1->$ME] 판정 요청: A안 B안"
ing 104 "[a#1->$ME] [BLOCK] 포트 충돌"
ing 105 "[a#1->$ME] 판정 430 집행 완료"
ing 106 "[a#1->$ME] 참고: 접수했습니다"
for pair in 101:① 102:② 103:③ 104:④ 105:⑤ 106:⑥; do eq "분류 ${pair%%:*}" "$(field "$Q/$M.jsonl" "${pair%%:*}" cls)" "${pair##*:}"; done
ing 107 "[a#1->$ME] 이상한 문장 가나다"
eq "미상은 규칙표 즉시 적재 시 cls=미상" "$(field "$Q/$M.jsonl" 107 cls)" "미상"
eq "미상 cls 는 나중에도 그대로(라벨 호출 0)" "$(field "$Q/$M.jsonl" 107 cls)" "미상"
eq "미상 prio ①과 ② 사이" "$(field "$Q/$M.jsonl" 107 prio)" "1.5"
eq "미상 + 분류기 스텁 호출 0" "$([ -f "$T/stub-called" ] && echo called || echo none)" "none"
eq "미상 + hook-errors.log 0줄(분류 자식 0)" "$([ -f "$FT_ROOT/.fable-team/state/hook-errors.log" ] && echo yes || echo none)" "none"
for s in 101 102 103 104 105 106; do eq "via 분류 출처 $s = rule" "$(field "$Q/$M.jsonl" $s via)" "rule"; done
eq "via 107 (미상) = unknown" "$(field "$Q/$M.jsonl" 107 via)" "unknown"

# 2) 묶음 2쌍(같은 from·정규화 본문 같음 · 접두·seq·시각만 다름) + 다른 본문은 안 묶임
ing 201 "[a#1->$ME] [발주 #62296] 보고 14:01 빌드 결과를 확인하라" "$ME" b#1
ing 202 "[a#2->$ME] [발주 #62305] 보고 14:07 빌드 결과를 확인하라" "$ME" b#1
ing 203 "[c#1->$ME] 참고 seq=62298 정리 안내 15:00" "$ME" c#1
ing 204 "[c#2->$ME] 참고 seq=62335 정리 안내 15:09" "$ME" c#1
ing 205 "[c#2->$ME] 참고 PR #881 병합" "$ME" c#1
ing 206 "[c#2->$ME] 참고 PR #883 병합" "$ME" c#1
g() { field "$Q/$M.jsonl" "$1" group; }
[ "$(g 201)" = "$(g 202)" ] && ok "묶음 짝 1 (201·202)" || bad "묶음 짝 1"
[ "$(g 203)" = "$(g 204)" ] && ok "묶음 짝 2 (203·204)" || bad "묶음 짝 2"
[ "$(g 205)" != "$(g 206)" ] && ok "PR 번호 다르면 안 묶임" || bad "PR 번호 다른데 묶임"
[ "$(g 201)" != "$(g 203)" ] && ok "다른 from·본문은 다른 묶음" || bad "다른 묶음이 같음"

# 3) 계보 키: #9 → #10 승계 후에도 같은 큐
ing 301 "[a#1->$M#10] 승계 뒤 쪽지" "$M#10" a#1
[ "$(ls "$Q" | grep -c "^$M.jsonl$")" = 1 ] && [ -n "$(field "$Q/$M.jsonl" 301 seq)" ] && ok "계보 키: #9·#10 같은 큐" || bad "계보 키"
eq "큐 파일 수(계보 1개)" "$(ls "$Q"/*.jsonl | wc -l | tr -d ' ')" "1"
eq "본문 보존 bodies/301.txt" "$([ -f "$FT_ROOT/.fable-team/comm/bodies/301.txt" ] && echo yes)" "yes"
eq "재적재 멱등(SKIP)" "$(bash "$INBOX" ingest 301 | cut -d' ' -f1)" "SKIP"

# 4) ★정본 술어★ S(cls③) mark 후 report 없음 → show 유지 · archive 이동 거부 → report → 닫힘·이동
bash "$INBOX" mark 103 처리 "답변 작성함" >/dev/null
echo "$(bash "$INBOX" show "$ME")" | grep -q "seq=103" && ok "술어: mark 만(③) → show 에 남음" || bad "술어: mark 만인데 show 에서 사라짐"
A1="$(bash "$INBOX" archive "$ME")"; echo "$A1" | sed -n '/seq=103/p'
echo "$A1" | grep -q "REFUSED seq=103 .*reported=false" && ok "술어: mark 후 report 없음 → archive 이동 거부" || bad "술어: archive 거부 출력 없음"
[ -n "$(field "$Q/$M.jsonl" 103 seq)" ] && ok "거부된 줄은 큐에 그대로(유실 0)" || bad "103 유실"
bash "$INBOX" report 103 >/dev/null
echo "$(bash "$INBOX" show "$ME")" | grep -q "seq=103" && bad "술어: report 후에도 show 에 남음" || ok "술어: report 후 show 에서 닫힘"
A2="$(bash "$INBOX" archive "$ME")"
echo "$A2" | grep -q "ARCHIVED [1-9]" && [ -z "$(field "$Q/$M.jsonl" 103 seq)" ] && ok "술어: report 후 archive 이동" || bad "술어: report 후 archive 안 됨 ($A2)"
AR="$(ls "$Q/archive/$M"-*.jsonl 2>/dev/null)"; [ -n "$AR" ] && grep -q '"seq": 103' "$AR" && ok "보관함에 103 존재(삭제 0)" || bad "보관함에 103 없음"

# 5) ⑥ 은 mark 만으로 닫힘
bash "$INBOX" mark 106 보류 "참고용" >/dev/null
echo "$(bash "$INBOX" show "$ME")" | grep -q "seq=106" && bad "⑥ mark 만인데 show 에 남음" || ok "⑥ 은 mark 만으로 닫힘"
# 5b) 미상(107)은 ①~④ 급 — mark 만으로는 닫힘 거부, report 해야 닫힘
bash "$INBOX" mark 107 처리 "확인함" >/dev/null
bash "$INBOX" archive "$ME" | grep -q "REFUSED seq=107 cls=미상 reported=false" && ok "미상: mark 만 → archive 이동 거부(REFUSED)" || bad "미상이 mark 만으로 닫힘(조용한 강등)"
bash "$INBOX" report 107 >/dev/null
bash "$INBOX" show "$ME" | grep -q "seq=107" && bad "미상: report 후에도 show 에 남음" || ok "미상: report 후 닫힘"

# 6) 묶음 G={S1,S2}: S1 만 report → G 미닫힘
add_mail 401 "$ME" d#1 "[d#1->$ME] 판정 요청: 같은 질문 12:00"; bash "$INBOX" ingest 401 >/dev/null 2>&1
add_mail 402 "$ME" d#1 "[d#1->$ME] 판정 요청: 같은 질문 12:30"; bash "$INBOX" ingest 402 >/dev/null 2>&1
[ "$(g 401)" = "$(g 402)" ] && ok "G 구성(401·402 같은 묶음)" || bad "G 구성"
GID="$(g 401)"
bash "$INBOX" mark "$GID" 처리 "묶음 처리" >/dev/null
bash "$INBOX" report 401 >/dev/null
bash "$INBOX" show "$ME" | grep -q "$GID" && ok "묶음: S1 만 report → G 미닫힘(show 유지)" || bad "묶음: G 가 닫힘"
bash "$INBOX" archive "$ME" | grep -q "REFUSED seq=402" && ok "묶음: S2 대상 유지(archive 거부)" || bad "묶음: archive 가 S2 를 안 막음"
bash "$INBOX" report 402 >/dev/null
bash "$INBOX" show "$ME" | grep -q "$GID" && bad "묶음: 둘 다 report 후에도 남음" || ok "묶음: 둘 다 report → 닫힘"

# 7) show --compact = 퇴역(r1560): 인자 오류 rc≠0 1줄 · 큐 무변경 · 스텁 호출 0
H1="$(md5 -q "$Q/$M.jsonl")"
rm -f "$T/stub-called"
OC="$(bash "$INBOX" show "$ME" --compact 2>&1)"; ORC=$?
[ "$ORC" -ne 0 ] && ok "--compact → rc≠0($ORC)" || bad "--compact 인데 rc 0"
eq "--compact 오류 1줄" "$(printf '%s\n' "$OC" | wc -l | tr -d ' ')" "1"
printf '%s\n' "$OC" | grep -q '퇴역' && ok "--compact 오류 문구가 퇴역을 말함" || bad "--compact 오류 문구: $OC"
eq "--compact 큐 무변경" "$(md5 -q "$Q/$M.jsonl")" "$H1"
eq "--compact 분류기 스텁 호출 0" "$([ -f "$T/stub-called" ] && echo called || echo none)" "none"

# 8) 알 수 없는 대상·usage 는 raise
bash "$INBOX" mark 999999 처리 "x" >/dev/null 2>&1; [ $? -ne 0 ] && ok "없는 seq mark → rc≠0" || bad "없는 seq mark 통과"
bash "$INBOX" bogus >/dev/null 2>&1; [ $? -eq 2 ] && ok "usage → rc 2" || bad "usage rc"

# 8b) via 마이그레이션 0: via 키 없는 옛 행 — show·mark·report·archive 동작 그대로 + via 키가 써지지 않음 · show 출력 바이트 불변
python3 - "$Q/$M.jsonl" "$FT_ROOT/.fable-team/comm/bodies/501.txt" <<'PY'
import json, sys
q, bp = sys.argv[1], sys.argv[2]
open(bp, "w", encoding="utf-8").write("[old#1->master-x#9] 판정 요청: 옛 행 시험\n")
row = {"seq": 501, "ts": "2026-10-08T15:00:00", "from": "old#1", "cls": "③", "prio": 3, "group": "old-group-501",
       "body_path": bp, "mark": None, "reported": False}
open(q, "a", encoding="utf-8").write(json.dumps(row, ensure_ascii=False) + "\n")
PY
has_via() { python3 -c 'import json,sys
for l in open(sys.argv[1]):
    x=json.loads(l)
    if x["seq"]==int(sys.argv[2]): print("via" in x)' "$@"; }
add_mail 502 "$ME" new#1 "[new#1->$ME] 판정 요청: 새 행 시험"; bash "$INBOX" ingest 502 >/dev/null 2>&1
eq "새 행 502 via=rule" "$(field "$Q/$M.jsonl" 502 via)" "rule"
printf '#!/bin/sh\ncat\n' > "$T/haiku-echo.sh"; chmod +x "$T/haiku-echo.sh"
strip_via_show() {  # <show 인자…> — 큐에서 via 키를 뺀 사본으로 같은 명령 실행 뒤 원복
  cp "$Q/$M.jsonl" "$T/q.bak"
  python3 - "$Q/$M.jsonl" <<'PY'
import json, sys
p = sys.argv[1]
rows = [json.loads(l) for l in open(p, encoding="utf-8")]
open(p, "w", encoding="utf-8").write("".join(json.dumps({k: v for k, v in x.items() if k != "via"}, ensure_ascii=False) + "\n" for x in rows))
PY
  bash "$INBOX" show "$ME" "$@"; cp "$T/q.bak" "$Q/$M.jsonl"
}
SH_A="$(bash "$INBOX" show "$ME")"
eq "show 출력 바이트: via 있음 = via 키 제거본" "$SH_A" "$(strip_via_show)"
echo "$SH_A" | grep -q "seq=501" && ok "옛 행 501 show 에 보임" || bad "옛 행 501 show 에서 누락"
bash "$INBOX" mark 501 처리 "옛 행 처리" >/dev/null; bash "$INBOX" report 501 >/dev/null
eq "옛 행 mark·report 뒤에도 via 키 없음(마이그레이션 0)" "$(has_via "$Q/$M.jsonl" 501)" "False"
bash "$INBOX" show "$ME" | grep -q "seq=501" && bad "옛 행 report 후에도 show 에 남음" || ok "옛 행 report 후 show 에서 닫힘"
bash "$INBOX" mark 502 처리 "새 행 처리" >/dev/null; bash "$INBOX" report 502 >/dev/null
bash "$INBOX" archive "$ME" | grep -q "ARCHIVED [1-9]" && ok "옛 행·새 행 archive 이동" || bad "archive 이동 안 됨"
AR2="$(ls "$Q/archive/$M"-*.jsonl)"; eq "보관된 옛 행 501 에도 via 키 없음" "$(has_via "$AR2" 501)" "False"

# 9) mbox.sh send: ingest 실패가 send rc·출력 불변 + 성공 시 큐 적재 (임시 comm 사본)
C="$T/sendroot/.fable-team/comm"; mkdir -p "$C" "$T/sendroot/.fable-team/bin"
cp "$REPO/harness/comm/"mbox*.sh "$REPO/harness/comm/"mbox*.py "$C/"
export FT_MBOX_DIR="$C" FT_SEATS_JSON="$T/seats.json"; echo '{}' > "$T/seats.json"
printf '#!/bin/sh\nexit 9\n' > "$T/sendroot/.fable-team/bin/ft-inbox.sh"
OUT="$(FT_ROOT="$T/sendroot" bash "$C/mbox.sh" send ghost-seat#1 sender#1 "[판정 요청] 시험" 2>"$T/err")"; RC=$?
eq "ingest 실패해도 send rc 0" "$RC" "0"
echo "$OUT" | grep -q "QUEUED seq=" && ok "ingest 실패해도 QUEUED 출력 유지" || bad "QUEUED 출력 없음: $OUT"
grep -q "WARN inbox ingest 실패" "$T/err" && ok "ingest 실패는 stderr WARN" || bad "WARN 없음"
cp "$INBOX" "$REPO/harness/bin/ft-inbox.py" "$REPO/harness/bin/ft_inbox_core.py" "$REPO/harness/bin/ft_inbox_rotate.py" "$REPO/harness/bin/ft_inbox_window.py" "$T/sendroot/.fable-team/bin/"  # 모듈 4개 — 빠지면 ingest 가 ImportError 로 죽어 이 절이 통째로 빈값이 된다
OUT2="$(FT_ROOT="$T/sendroot" bash "$C/mbox.sh" send ghost-seat#2 sender#2 "[판정 요청] 다른 시험" 2>/dev/null)"; RC=$?
S2="$(echo "$OUT2" | sed -n 's/.*seq=\([0-9]*\).*/\1/p' | head -1)"
eq "ingest 성공 send rc 0" "$RC" "0"
eq "send 훅 큐 적재(cls ③)" "$(field "$T/sendroot/.fable-team/state/inbox/ghost-seat.jsonl" "$S2" cls)" "③"

# 9b) ★분류기 0★: 규칙표에 안 맞는 쪽지 → send 는 기다리지 않고 rc 0 · 적재 시점 cls=미상 · 스폰 0 이라 나중에도 미상
GQ="$T/sendroot/.fable-team/state/inbox/ghost-seat.jsonl"
rm -f "$T/stub-called"
OUT3="$(FT_ROOT="$T/sendroot" bash "$C/mbox.sh" send ghost-seat#3 sender#3 "가나다 규칙표에 없는 문장" 2>/dev/null)"; RC=$?
S3="$(echo "$OUT3" | sed -n 's/.*seq=\([0-9]*\).*/\1/p' | head -1)"
eq "미상 쪽지도 send rc 0" "$RC" "0"
eq "적재 시점 cls=미상" "$(field "$GQ" "$S3" cls)" "미상"
eq "적재 뒤에도 cls=미상(분류 자식 0)" "$(field "$GQ" "$S3" cls)" "미상"
eq "적재 뒤 prio 1.5" "$(field "$GQ" "$S3" prio)" "1.5"
eq "send 경로에서 분류기 스텁 호출 0" "$([ -f "$T/stub-called" ] && echo called || echo none)" "none"

# 9c) 10-10 RULES 4줄(R57) — 규칙으로 즉시 분류(via=rule) · 새 줄은 본문 첫머리(\A)만
ing 701 "[a#1->$ME] [완료·휴식] 골 끝남 증거 줄 첨부"
ing 702 "[a#1->$ME] [첫 보고] 세션 인사"
ing 703 "[a#1->$ME] [HIL · 판정 881] 질문 하나"
ing 704 "[a#1->$ME] [Issue 등록] 제안 한 건"
for pair in 701:⑤ 702:⑥ 703:② 704:⑤; do
  s="${pair%%:*}"; eq "새 RULES $s 분류" "$(field "$Q/$M.jsonl" "$s" cls)" "${pair##*:}"
  eq "새 RULES $s via = rule" "$(field "$Q/$M.jsonl" "$s" via)" "rule"
done
ing 705 "[a#1->$ME] 가나다 둘째 줄에만
[완료·휴식] 본문 중간 줄 머리"
eq "새 줄은 \\A — 본문 중간 줄 머리 [완료·휴식] 는 규칙에 안 걸림(미상)" "$([ "$(field "$Q/$M.jsonl" 705 via)" = rule ] && echo rule || echo nonrule)" "nonrule"
eq "규칙표 밖 705 = 미상 유지" "$(field "$Q/$M.jsonl" 705 cls)" "미상"

# 9d) 지운 옵션·명령은 오류로 말한다(r1560 · 조용한 무시 0)
bash "$INBOX" classify 107 "$ME" > "$T/cls.out" 2>&1; [ $? -ne 0 ] && ok "classify 하위 명령 → rc≠0" || bad "classify 가 아직 동작"
eq "classify 오류 1줄" "$(wc -l < "$T/cls.out" | tr -d ' ')" "1"
grep -q 'usage: ft-inbox.sh' "$T/cls.out" && ok "classify 는 usage 1줄" || bad "classify 오류 문구: $(cat "$T/cls.out")"

# 9e) ★close — r916★ 한 잠금 안에서 mark(처리·사유) + reported · 없는 대상은 NOTFOUND rc≠0 · 사유 빈 값 usage rc2 · 남의 큐 보존
ing 801 "[a#1->$ME] 판정 요청: close 시험 하나"
ing 802 "[a#1->$ME] 판정 요청: close 시험 둘"
bash "$INBOX" close 801 "close 한 줄 시험" --seat "$ME" > "$T/close1.out" 2>&1; eq "ⓐ close rc 0" "$?" "0"
grep -q "^CLOSED 801 seq=801$" "$T/close1.out" && ok "ⓐ close 출력 CLOSED 801" || bad "ⓐ close 출력: $(cat "$T/close1.out")"
[ "$(field "$Q/$M.jsonl" 801 reported)" = "True" ] && ok "ⓐ close 가 mark 와 reported 를 같이 찍음" || bad "ⓐ reported 안 찍힘(mark 만)"
eq "ⓐ close 사유가 mark.note 에" "$(python3 -c 'import json,sys
for l in open(sys.argv[1]):
    x=json.loads(l)
    if x["seq"]==int(sys.argv[2]): print(x["mark"]["kind"], x["mark"]["note"])' "$Q/$M.jsonl" 801)" "처리 close 한 줄 시험"
bash "$INBOX" show "$ME" | grep -q "seq=801" && bad "ⓐ close 뒤 show 에 남음(닫힘 아님)" || ok "ⓐ close 뒤 show 에서 닫힘(정본 술어 참)"
bash "$INBOX" archive "$ME" | grep -q "ARCHIVED [1-9]" && [ -z "$(field "$Q/$M.jsonl" 801 seq)" ] && ok "ⓐ close 뒤 archive 이동" || bad "ⓐ close 뒤 archive 거부"
H9="$(md5 -q "$Q/$M.jsonl")"
bash "$INBOX" close 802 999999 "일부 없는 대상" --seat "$ME" > "$T/close2.out" 2>&1; [ $? -ne 0 ] && ok "ⓑ 없는 대상 NOTFOUND → rc≠0" || bad "ⓑ NOTFOUND 인데 rc 0"
grep -q "NOTFOUND 999999" "$T/close2.out" && ok "ⓑ NOTFOUND 줄 출력" || bad "ⓑ NOTFOUND 줄 없음: $(cat "$T/close2.out")"
grep -q "CLOSED 802" "$T/close2.out" && ok "ⓑ 나머지 대상은 닫음(부분 성공)" || bad "ⓑ 802 안 닫힘"
H10="$(md5 -q "$Q/$M.jsonl")"
bash "$INBOX" close 803 "" --seat "$ME" > "$T/close4.out" 2>&1; [ $? -eq 2 ] && ok "ⓒ 사유 빈 값 → usage rc 2" || bad "ⓒ 사유 빈 값 rc"
grep -q "usage: close" "$T/close4.out" && ok "ⓒ close 전용 usage 문구" || bad "ⓒ close usage 문구 아님: $(cat "$T/close4.out")"
eq "ⓒ 사유 빈 값은 큐 무변경" "$(md5 -q "$Q/$M.jsonl")" "$H10"
ing 811 "[a#1->$ME] [발주 #70001] 닫기 묶음 시험 10:00 a" "$ME" z#1
ing 812 "[a#1->$ME] [발주 #70002] 닫기 묶음 시험 10:00 a" "$ME" z#1
GZ="$(g 811)"; [ "$GZ" = "$(g 812)" ] && ok "close 묶음 구성(811·812)" || bad "close 묶음 구성"
bash "$INBOX" close "$GZ" "묶음 통째 닫기" --seat "$ME" >/dev/null 2>&1
bash "$INBOX" show "$ME" | grep -q "$GZ" && bad "묶음 close 뒤 show 에 남음" || ok "묶음 close = 그 묶음 전부 닫힘"
ing 821 "[a#1->other-x#1] 판정 요청: 남의 큐 줄" "other-x#1" a#1
HB="$(md5 -q "$Q/other-x.jsonl")"
bash "$INBOX" close 821 "남의 큐 시험" --seat "$ME" > "$T/close5.out" 2>&1; [ $? -ne 0 ] && ok "내 좌석에 없는 seq → NOTFOUND rc≠0" || bad "남의 큐 seq 를 닫음"
grep -q "NOTFOUND 821" "$T/close5.out" && ok "남의 큐 seq 는 NOTFOUND 줄" || bad "남의 큐 seq NOTFOUND 줄 없음: $(cat "$T/close5.out")"
eq "남의 좌석 큐 보존" "$(md5 -q "$Q/other-x.jsonl")" "$HB"

# 10) 키트 사본 동기
bash "$HERE/test_kit_bin_sync.sh" >/dev/null 2>&1 && ok "test_kit_bin_sync.sh PASS" || bad "test_kit_bin_sync.sh FAIL"

echo "RESULT fail=$fail"
[ "$fail" = 0 ]
