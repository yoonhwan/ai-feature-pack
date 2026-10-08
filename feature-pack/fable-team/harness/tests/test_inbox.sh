#!/usr/bin/env bash
# test_inbox.sh — ft-inbox.sh(ingest·show·mark·report·archive·--compact) + mbox.sh send 훅 시험.
# 전부 mktemp 임시 FT_ROOT(가짜 mailbox.jsonl·bodies/) + 가짜 Haiku(FT_INBOX_HAIKU 스텁). 실제 mbox·claude 호출 0 · 라이브 .fable-team 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
INBOX="$REPO/scripts/fable-team-bin/ft-inbox.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_ROOT="$T/root"; mkdir -p "$FT_ROOT/.fable-team/comm/bodies"
MB="$FT_ROOT/.fable-team/comm/mailbox.jsonl"
Q="$FT_ROOT/.fable-team/state/inbox"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

# 가짜 Haiku: 성공 스텁(⑤ 라벨) · 실패 스텁(rc 1)
printf '#!/bin/sh\ncat >/dev/null; echo 5\n' > "$T/haiku-ok.sh"; chmod +x "$T/haiku-ok.sh"
printf '#!/bin/sh\ncat >/dev/null; exit 1\n' > "$T/haiku-fail.sh"; chmod +x "$T/haiku-fail.sh"
export FT_INBOX_HAIKU="$T/haiku-ok.sh"

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
M=master-x; ME="$M#9"
ing() { add_mail "$1" "${3:-$ME}" "${4:-a#1}" "$2"; bash "$INBOX" ingest "$1" >/dev/null 2>&1; }

# 1) 분류표 6 + 미상(Haiku 성공/실패)
ing 101 "[a#1->$ME] 오빠 원문: 이것 확인해줘"
ing 102 "[a#1->$ME] [HIL] 행#3 질문"
ing 103 "[a#1->$ME] 판정 요청: A안 B안"
ing 104 "[a#1->$ME] [BLOCK] 포트 충돌"
ing 105 "[a#1->$ME] 판정 430 집행 완료"
ing 106 "[a#1->$ME] 참고: 접수했습니다"
for pair in 101:① 102:② 103:③ 104:④ 105:⑤ 106:⑥; do eq "분류 ${pair%%:*}" "$(field "$Q/$M.jsonl" "${pair%%:*}" cls)" "${pair##*:}"; done
waitcls() { for _ in $(seq 1 60); do [ "$(field "$1" "$2" cls)" != "미상" ] && return 0; sleep 0.5; done; return 1; }
ing 107 "[a#1->$ME] 이상한 문장 가나다"
eq "미상은 규칙표 즉시 적재 시 cls=미상" "$(field "$Q/$M.jsonl" 107 cls)" "미상"
waitcls "$Q/$M.jsonl" 107 && eq "미상 + Haiku 성공 → ⑤(비동기 갱신)" "$(field "$Q/$M.jsonl" 107 cls)" "⑤" || bad "미상 + Haiku 성공인데 갱신 안 됨"
FT_INBOX_HAIKU="$T/haiku-fail.sh" ing 108 "[a#1->$ME] 또 다른 문장 라마바"
for _ in $(seq 1 20); do grep -q "seq=108" "$FT_ROOT/.fable-team/state/hook-errors.log" 2>/dev/null && break; sleep 0.25; done
eq "미상 + Haiku 실패 → 미상 유지" "$(field "$Q/$M.jsonl" 108 cls)" "미상"
grep -q "ft-inbox classify seq=108" "$FT_ROOT/.fable-team/state/hook-errors.log" && ok "Haiku 실패는 hook-errors.log 1줄" || bad "hook-errors.log 기록 없음"
eq "미상 prio ①과 ② 사이" "$(field "$Q/$M.jsonl" 108 prio)" "1.5"
for s in 101 102 103 104 105 106; do eq "via 분류 출처 $s = rule" "$(field "$Q/$M.jsonl" $s via)" "rule"; done
eq "via 107 (미상 + Haiku 성공 갱신 뒤) = haiku" "$(field "$Q/$M.jsonl" 107 via)" "haiku"
eq "via 108 (미상 + Haiku 실패) = unknown" "$(field "$Q/$M.jsonl" 108 via)" "unknown"

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
# 5b) 미상(Haiku 실패로 남은 108)은 ①~④ 급 — mark 만으로는 닫힘 거부, report 해야 닫힘
bash "$INBOX" mark 108 처리 "확인함" >/dev/null
bash "$INBOX" archive "$ME" | grep -q "REFUSED seq=108 cls=미상 reported=false" && ok "미상: mark 만 → archive 이동 거부(REFUSED)" || bad "미상이 mark 만으로 닫힘(조용한 강등)"
bash "$INBOX" report 108 >/dev/null
bash "$INBOX" show "$ME" | grep -q "seq=108" && bad "미상: report 후에도 show 에 남음" || ok "미상: report 후 닫힘"

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

# 7) show --compact: Haiku 일회 호출 · 큐 무변경 · 실패 시 REJECT(rc≠0)
H1="$(md5 -q "$Q/$M.jsonl")"
printf '#!/bin/sh\ncat >/dev/null; echo COMPACT-OK\n' > "$T/haiku-compact.sh"; chmod +x "$T/haiku-compact.sh"
eq "--compact 출력" "$(FT_INBOX_HAIKU="$T/haiku-compact.sh" bash "$INBOX" show "$ME" --compact)" "COMPACT-OK"
eq "--compact 큐 무변경" "$(md5 -q "$Q/$M.jsonl")" "$H1"
FT_INBOX_HAIKU="$T/haiku-fail.sh" bash "$INBOX" show "$ME" --compact >/dev/null 2>&1; [ $? -ne 0 ] && ok "--compact Haiku 실패 → rc≠0" || bad "--compact 실패인데 rc 0"

# 8) 알 수 없는 대상·usage 는 raise
bash "$INBOX" mark 999999 처리 "x" >/dev/null 2>&1; [ $? -ne 0 ] && ok "없는 seq mark → rc≠0" || bad "없는 seq mark 통과"
bash "$INBOX" bogus >/dev/null 2>&1; [ $? -eq 2 ] && ok "usage → rc 2" || bad "usage rc"

# 8b) via 마이그레이션 0: via 키 없는 옛 행 — show·mark·report·archive 동작 그대로 + via 키가 써지지 않음 · show/--compact 출력 바이트 불변
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
  FT_INBOX_HAIKU="$T/haiku-echo.sh" bash "$INBOX" show "$ME" "$@"; cp "$T/q.bak" "$Q/$M.jsonl"
}
SH_A="$(FT_INBOX_HAIKU="$T/haiku-echo.sh" bash "$INBOX" show "$ME")"
eq "show 출력 바이트: via 있음 = via 키 제거본" "$SH_A" "$(strip_via_show)"
SC_A="$(FT_INBOX_HAIKU="$T/haiku-echo.sh" bash "$INBOX" show "$ME" --compact)"
eq "show --compact 출력 바이트: via 있음 = via 키 제거본" "$SC_A" "$(strip_via_show --compact)"
echo "$SH_A" | grep -q "seq=501" && ok "옛 행 501 show 에 보임" || bad "옛 행 501 show 에서 누락"
bash "$INBOX" mark 501 처리 "옛 행 처리" >/dev/null; bash "$INBOX" report 501 >/dev/null
eq "옛 행 mark·report 뒤에도 via 키 없음(마이그레이션 0)" "$(has_via "$Q/$M.jsonl" 501)" "False"
bash "$INBOX" show "$ME" | grep -q "seq=501" && bad "옛 행 report 후에도 show 에 남음" || ok "옛 행 report 후 show 에서 닫힘"
bash "$INBOX" mark 502 처리 "새 행 처리" >/dev/null; bash "$INBOX" report 502 >/dev/null
bash "$INBOX" archive "$ME" | grep -q "ARCHIVED [1-9]" && ok "옛 행·새 행 archive 이동" || bad "archive 이동 안 됨"
AR2="$(ls "$Q/archive/$M"-*.jsonl)"; eq "보관된 옛 행 501 에도 via 키 없음" "$(has_via "$AR2" 501)" "False"

# 9) mbox.sh send: ingest 실패가 send rc·출력 불변 + 성공 시 큐 적재 (임시 comm 사본)
C="$T/sendroot/.fable-team/comm"; mkdir -p "$C" "$T/sendroot/.fable-team/bin"
cp "$REPO/tools/comm-canonical/mbox.sh" "$REPO/tools/comm-canonical/mbox.py" "$C/"
export FT_MBOX_DIR="$C" FT_SEATS_JSON="$T/seats.json"; echo '{}' > "$T/seats.json"
printf '#!/bin/sh\nexit 9\n' > "$T/sendroot/.fable-team/bin/ft-inbox.sh"
OUT="$(FT_ROOT="$T/sendroot" bash "$C/mbox.sh" send ghost-seat#1 sender#1 "[판정 요청] 시험" 2>"$T/err")"; RC=$?
eq "ingest 실패해도 send rc 0" "$RC" "0"
echo "$OUT" | grep -q "QUEUED seq=" && ok "ingest 실패해도 QUEUED 출력 유지" || bad "QUEUED 출력 없음: $OUT"
grep -q "WARN inbox ingest 실패" "$T/err" && ok "ingest 실패는 stderr WARN" || bad "WARN 없음"
cp "$INBOX" "$REPO/scripts/fable-team-bin/ft-inbox.py" "$REPO/scripts/fable-team-bin/ft_inbox_core.py" "$T/sendroot/.fable-team/bin/"
OUT2="$(FT_ROOT="$T/sendroot" bash "$C/mbox.sh" send ghost-seat#2 sender#2 "[판정 요청] 다른 시험" 2>/dev/null)"; RC=$?
S2="$(echo "$OUT2" | sed -n 's/.*seq=\([0-9]*\).*/\1/p' | head -1)"
eq "ingest 성공 send rc 0" "$RC" "0"
eq "send 훅 큐 적재(cls ③)" "$(field "$T/sendroot/.fable-team/state/inbox/ghost-seat.jsonl" "$S2" cls)" "③"

# 9b) ★Haiku 비동기★: 규칙표에 안 맞는 쪽지 + Haiku 스텁 sleep 8 → send 1초 미만 · 적재 시점 cls=미상 · 나중에 cls 갱신
printf '#!/bin/sh\ncat >/dev/null; sleep 8; echo 5\n' > "$T/haiku-slow.sh"; chmod +x "$T/haiku-slow.sh"
GQ="$T/sendroot/.fable-team/state/inbox/ghost-seat.jsonl"
t0="$(python3 -c 'import time;print(time.time())')"
OUT3="$(FT_INBOX_HAIKU="$T/haiku-slow.sh" FT_ROOT="$T/sendroot" bash "$C/mbox.sh" send ghost-seat#3 sender#3 "가나다 규칙표에 없는 문장" 2>/dev/null)"; RC=$?
t1="$(python3 -c 'import time;print(time.time())')"
S3="$(echo "$OUT3" | sed -n 's/.*seq=\([0-9]*\).*/\1/p' | head -1)"
eq "느린 Haiku 중에도 send rc 0" "$RC" "0"
python3 -c 'import sys;sys.exit(0 if float(sys.argv[2])-float(sys.argv[1])<1.0 else 1)' "$t0" "$t1" && ok "send 소요 1초 미만(Haiku sleep 8 대기 0)" || bad "send 가 Haiku 를 기다림($t0→$t1)"
eq "적재 시점 cls=미상" "$(field "$GQ" "$S3" cls)" "미상"
waitcls "$GQ" "$S3" && eq "나중에 cls 갱신(Haiku ⑤)" "$(field "$GQ" "$S3" cls)" "⑤" || bad "cls 가 갱신되지 않음"
eq "갱신 prio 도 반영" "$(field "$GQ" "$S3" prio)" "5.0"

# 10) 키트 사본 동기
bash "$HERE/test_kit_bin_sync.sh" >/dev/null 2>&1 && ok "test_kit_bin_sync.sh PASS" || bad "test_kit_bin_sync.sh FAIL"

echo "RESULT fail=$fail"
[ "$fail" = 0 ]
