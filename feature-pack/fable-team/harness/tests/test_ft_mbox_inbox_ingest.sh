#!/usr/bin/env bash
# test_ft_mbox_inbox_ingest.sh — R180: `ft-mbox.sh send` 도 전송 직후 인박스 적재(ft-inbox ingest) + 분류 알림 (comm/mbox.sh 와 같은 계약)
#  ⓐ send 뒤 받는 좌석 계보 큐에 그 seq 행 1  ⓑ적재 도구 실패 = 전송 rc 0 + stderr WARN  ⓒ같은 seq 두 번 적재해도 큐 행 1
#  ⓓ분류 ①~④·미상은 tick 유무와 무관하게 알림 · ⑤⑥ 은 기존 정책(tick 있음 → quiet)  ⓔ변이: 적재 호출을 빼면 ⓐ 가 FAIL
#  ⓗFT_MBOX_DIR≠FT_ROOT 면 py 가 고른 우편함 기준 적재  ⓘ변이(FT_ROOT 우선) → ⓗ FAIL  ⓙ우편함 경로가 .fable-team/comm 꼴 아니면 적재 건너뜀 + WARN
#  ⓕ오빠 대면 좌석(seats-planner.json _master)은 ①~④·--urgent·relay 여도 doorbell 0 · 큐 적재는 그대로  ⓖ변이: 억제를 빼면 ⓕ 가 FAIL
# 임시 FT_ROOT(키트 bin 사본) + 가짜 seats.json + 가짜 tmux + 가짜 Haiku — 실 우편함·실 state/inbox·실 claude 0 · GIT_* 는 건다 않는다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../scripts/harness-install/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

mkroot() {  # <이름> → $T/<이름> 에 키트 bin 사본 (FT_ROOT 는 export 하지 않는다 — 스크립트 위치 유도를 시험)
  local R="$T/$1"; mkdir -p "$R/.fable-team/bin" "$R/.fable-team/comm"
  cp "$KIT"/ft-mbox.sh "$KIT"/ft-mbox.py "$KIT"/ft-lib.sh "$KIT"/ft-inbox.sh "$KIT"/ft-inbox.py "$KIT"/ft_inbox_core.py "$R/.fable-team/bin/"
  echo "$R"
}
ROOT="$(mkroot main)"; BIN="$ROOT/.fable-team/bin"; Q="$ROOT/.fable-team/state/inbox"
mkdir -p "$T/fakebin"; printf '#!/bin/sh\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
printf '#!/bin/sh\ncat >/dev/null; exit 1\n' > "$T/haiku-fail.sh"; chmod +x "$T/haiku-fail.sh"   # 미상은 미상으로 남는다
echo '{"tick-seat#1": {"tick": "ft-master-tick"}, "tick-seat#2": {"tick": "ft-master-tick"}}' > "$T/seats.json"
export PATH="$T/fakebin:$PATH" FT_SEATS_JSON="$T/seats.json" FT_INBOX_HAIKU="$T/haiku-fail.sh"
unset FT_ROOT FT_MBOX_DIR

send() { local bin="$1"; shift; bash "$bin/ft-mbox.sh" send "$@" 2>"$T/err"; }   # <bin> <to> <from> <body>
db()   { sed -n 's/.*doorbell=\([a-z]*\).*/\1/p' <<<"$1" | head -1; }
seqof() { sed -n 's/.*QUEUED seq=\([0-9]*\).*/\1/p' <<<"$1" | head -1; }
rows() {  # <큐 경로> <seq> → 그 seq 행 수
  python3 - "$1" "$2" <<'PYEOF'
import json, sys
try:
    print(sum(1 for l in open(sys.argv[1], encoding="utf-8") if l.strip() and json.loads(l)["seq"] == int(sys.argv[2])))
except FileNotFoundError:
    print(0)
PYEOF
}

# ⓐ send 뒤 받는 좌석 계보 큐에 그 seq 행 1 (⑥ 본문 · tick 없는 좌석)
out="$(send "$BIN" rcv-a#1 snd-a#1 "참고: 접수했습니다")"; rc=$?; S="$(seqof "$out")"
eq "ⓐ send rc 0" "$rc" 0
eq "ⓐ 받는 계보 큐(rcv-a.jsonl)에 그 seq 행 1" "$(rows "$Q/rcv-a.jsonl" "$S")" 1
# relay 도 같은 적재(비교 대상 comm/mbox.sh relay 와 같은 계약)
printf '긴 본문\n' > "$T/long.txt"
out="$(bash "$BIN/ft-mbox.sh" relay rcv-r#1 snd-r#1 "$T/long.txt" "[HIL] relay 요약" 2>"$T/err")"; R="$(seqof "$out")"
eq "ⓐ relay 도 받는 계보 큐에 그 seq 행 1" "$(rows "$Q/rcv-r.jsonl" "$R")" 1

# ⓒ 같은 seq 를 ingest 두 번 더 불러도 큐 행 1 (두 도구가 겹쳐 불러도 같다)
FT_ROOT="$ROOT" bash "$BIN/ft-inbox.sh" ingest "$S" >/dev/null 2>&1; FT_ROOT="$ROOT" bash "$BIN/ft-inbox.sh" ingest "$S" >/dev/null 2>&1
eq "ⓒ 같은 seq 재적재 2회 뒤에도 큐 행 1" "$(rows "$Q/rcv-a.jsonl" "$S")" 1

# ⓓ 분류 알림 — tick 있는 좌석에도 ①~④·미상은 울린다 · ⑤⑥ 은 quiet 그대로 · tick 없음 + ⑥ 은 기존대로 울림
n=0
for pair in "①:오빠 원문: 이것 확인" "②:[HIL] 행3 질문" "③:판정 요청: A안 B안" "④:[BLOCK] 포트 충돌" "미상:가나다 라마바 규칙표에 없는 문장"; do
  cls="${pair%%:*}"; body="${pair#*:}"; n=$((n+1))
  out="$(send "$BIN" tick-seat#1 "s$n#1" "$body")"
  [ "$(db "$out")" != quiet ] && ok "ⓓ tick 있는 좌석 + $cls → doorbell 울림($(db "$out"))" || bad "ⓓ tick 있는 좌석 + $cls 인데 quiet: $out"
done
for pair in "⑤:판정 430 집행 완료" "⑥:참고: 접수했습니다"; do
  cls="${pair%%:*}"; body="${pair#*:}"; n=$((n+1))
  out="$(send "$BIN" tick-seat#2 "s$n#1" "$body")"
  eq "ⓓ tick 있는 좌석 + $cls → quiet 그대로" "$(db "$out")" quiet
done
out="$(send "$BIN" no-tick-seat#1 s20#1 "참고: 접수했습니다")"
[ "$(db "$out")" != quiet ] && ok "ⓓ tick 없는 좌석 + ⑥ → 기존 규칙대로 울림" || bad "ⓓ tick 없는 좌석 + ⑥ 인데 quiet: $out"

# ⓑ 적재 도구 실패(ft-inbox.sh rc 9) → 전송 rc 0 + stderr WARN · 분류 모름 → 기존 규칙(tick 있음 = quiet) · 큐 행 0
mv "$BIN/ft-inbox.sh" "$BIN/ft-inbox.sh.off"; printf '#!/bin/sh\nexit 9\n' > "$BIN/ft-inbox.sh"; chmod +x "$BIN/ft-inbox.sh"
out="$(send "$BIN" tick-seat#1 s30#1 "[HIL] 적재 실패 시험")"; rc=$?; F="$(seqof "$out")"
eq "ⓑ 적재 실패여도 send rc 0" "$rc" 0
eq "ⓑ 적재 실패 + tick 있는 좌석 → 기존 규칙(quiet)" "$(db "$out")" quiet
grep -q "WARN inbox ingest 실패 seq=$F" "$T/err" && ok "ⓑ 적재 실패는 stderr WARN" || bad "ⓑ WARN 없음: $(cat "$T/err")"
eq "ⓑ 큐 행 0 (적재 안 됨 — 조용한 0 아님: WARN 있음)" "$(rows "$Q/tick-seat.jsonl" "$F")" 0
mv "$BIN/ft-inbox.sh.off" "$BIN/ft-inbox.sh"

# ⓔ 변이: 적재 호출(inbox_ingest "$(seq_of …)")을 빼면 ⓐ 가 FAIL — 시험이 «잡는다»
MR="$(mkroot mut)"; MBIN="$MR/.fable-team/bin"
grep -v 'inbox_ingest "\$(seq_of' "$BIN/ft-mbox.sh" > "$MBIN/ft-mbox.sh.m" && mv "$MBIN/ft-mbox.sh.m" "$MBIN/ft-mbox.sh"
[ "$(grep -c 'inbox_ingest "\$(seq_of' "$MBIN/ft-mbox.sh")" = 0 ] && ok "ⓔ 변이 사본: 적재 호출 0" || bad "ⓔ 변이 사본에 적재 호출이 남음"
out="$(send "$MBIN" rcv-m#1 snd-m#1 "참고: 접수했습니다")"; M="$(seqof "$out")"
eq "ⓔ 변이(적재 호출 제거) → 큐 행 0 이라 ⓐ 단언이 잡는다" "$(rows "$MR/.fable-team/state/inbox/rcv-m.jsonl" "$M")" 0

# ⓕ 오빠 대면 좌석(seats-planner.json `_master`) = doorbell 0 · 큐 적재는 그대로 — ①·--urgent·relay ② 모두 quiet · 대면 아닌 좌석은 지금 그대로
echo '{"_master": "planner-uf#7"}' > "$T/seats-planner.json"
out="$(send "$BIN" planner-uf#7 uf1#1 "오빠 원문: 이것 확인")"; U="$(seqof "$out")"
eq "ⓕ 대면 좌석 + ① → doorbell=quiet" "$(db "$out")" quiet
eq "ⓕ 대면 좌석 + ① → 큐 행 1(적재는 그대로)" "$(rows "$Q/planner-uf.jsonl" "$U")" 1
out="$(send "$BIN" planner-uf#7 uf2#1 "[HIL] urgent 질문" --urgent)"
eq "ⓕ 대면 좌석 + --urgent → doorbell=quiet" "$(db "$out")" quiet
out="$(bash "$BIN/ft-mbox.sh" relay planner-uf#7 uf3#1 "$T/long.txt" "[HIL] relay 요약" 2>"$T/err")"
eq "ⓕ 대면 좌석 + relay ② → doorbell=quiet" "$(db "$out")" quiet
out="$(send "$BIN" no-tick-seat#2 uf4#1 "[HIL] 대면 아닌 좌석 질문")"
[ "$(db "$out")" != quiet ] && ok "ⓕ 대면 아닌 좌석 + ② → 지금 그대로 울림" || bad "ⓕ 대면 아닌 좌석이 quiet: $out"
out="$(bash "$BIN/ft-mbox.sh" ring planner-uf#7 2>&1)"
[ "$(db "$out")" != quiet ] && ok "ⓕ 명시 ring 은 대면 좌석에도 울림(예외)" || bad "ⓕ 명시 ring 이 quiet: $out"
rm -f "$T/seats-planner.json"
out="$(send "$BIN" planner-uf#7 uf5#1 "[HIL] seats-planner.json 없음")"
[ "$(db "$out")" != quiet ] && ok "ⓕ seats-planner.json 없음 → 판정 불가는 기존대로 울림" || bad "ⓕ 파일 없는데 quiet: $out"

# ⓖ 변이: 억제(user_facing 줄)를 빼면 ⓕ 가 FAIL — 대면 좌석 ① 이 울린다
echo '{"_master": "planner-uf#7"}' > "$T/seats-planner.json"
GR="$(mkroot mut2)"; GBIN="$GR/.fable-team/bin"
grep -v 'if user_facing "\$to"; then notify=0; fi' "$BIN/ft-mbox.sh" > "$GBIN/ft-mbox.sh.m" && mv "$GBIN/ft-mbox.sh.m" "$GBIN/ft-mbox.sh"
[ "$(grep -c 'if user_facing "\$to"; then notify=0; fi' "$GBIN/ft-mbox.sh")" = 0 ] && ok "ⓖ 변이 사본: 억제 줄 0" || bad "ⓖ 변이 사본에 억제 줄이 남음"
out="$(send "$GBIN" planner-uf#7 uf6#1 "오빠 원문: 이것 확인")"
[ "$(db "$out")" != quiet ] && ok "ⓖ 변이(억제 제거) → 대면 좌석 ① 이 울려 ⓕ 단언이 잡는다($(db "$out"))" || bad "ⓖ 변이인데 quiet: $out"

# ⓗ FT_MBOX_DIR(A) 와 FT_ROOT(B) 가 다르면 py 가 고른 A 우편함 기준으로 적재 — A 큐 행 1 · B 큐 0 (DA⑥ H1 · env FT_ROOT 는 안 본다)
AR="$(mkroot hA)"; BR="$(mkroot hB)"
hsend() { local bin="$1"; shift; FT_MBOX_DIR="$AR/.fable-team/comm" FT_ROOT="$BR" bash "$bin/ft-mbox.sh" send "$@" 2>"$T/err"; }
out="$(hsend "$AR/.fable-team/bin" rcv-h#1 snd-h#1 "참고: 접수했습니다")"; rc=$?; H="$(seqof "$out")"
eq "ⓗ FT_MBOX_DIR≠FT_ROOT send rc 0" "$rc" 0
eq "ⓗ A 우편함에 쪽지 행 1" "$(grep -c "\"seq\": *$H[,}]" "$AR/.fable-team/comm/mailbox.jsonl")" 1
eq "ⓗ A 큐(rcv-h.jsonl)에 그 seq 행 1" "$(rows "$AR/.fable-team/state/inbox/rcv-h.jsonl" "$H")" 1
eq "ⓗ B 큐 행 0" "$(rows "$BR/.fable-team/state/inbox/rcv-h.jsonl" "$H")" 0
# ⓘ 변이: FT_ROOT 우선 순서로 되돌리면 ⓗ 가 FAIL(A 큐 0)
IR="$(mkroot hI)"; IBIN="$IR/.fable-team/bin"
python3 - "$IBIN/ft-mbox.sh" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
t = '''  [ -n "${FT_MBOX_DIR:-}" ] && { printf '%s' "$FT_MBOX_DIR"; return; }\n  local d="$BINDIR" root=""'''
assert s.count(t) == 1, "변이 대상 없음/중복"
open(p, "w", encoding="utf-8").write(s.replace(t, '''  [ -n "${FT_ROOT:-}" ] && { printf '%s/.fable-team/comm' "$FT_ROOT"; return; }\n''' + t))
PYEOF
out="$(FT_MBOX_DIR="$IR/.fable-team/comm" FT_ROOT="$BR" bash "$IBIN/ft-mbox.sh" send rcv-i#1 snd-i#1 "참고: 접수했습니다" 2>"$T/err")"; HI="$(seqof "$out")"
eq "ⓘ 변이(FT_ROOT 우선) → A 큐 행 0 이라 ⓗ 단언이 잡는다" "$(rows "$IR/.fable-team/state/inbox/rcv-i.jsonl" "$HI")" 0
# ⓙ 우편함 경로가 <루트>/.fable-team/comm 꼴이 아니면 적재 건너뜀 — rc 0 + stderr WARN(조용한 0 아님)
mkdir -p "$T/weird-mailbox"
out="$(FT_MBOX_DIR="$T/weird-mailbox" bash "$BIN/ft-mbox.sh" send rcv-j#1 snd-j#1 "참고: 접수했습니다" 2>"$T/err")"; rc=$?; J="$(seqof "$out")"
eq "ⓙ 꼴 아닌 FT_MBOX_DIR → send rc 0" "$rc" 0
grep -q "WARN inbox ingest 건너뜀 — 우편함 경로가 <루트>/.fable-team/comm 꼴 아님" "$T/err" && ok "ⓙ stderr WARN" || bad "ⓙ WARN 없음: $(cat "$T/err")"
eq "ⓙ 큐 행 0 (적재 안 함)" "$(rows "$ROOT/.fable-team/state/inbox/rcv-j.jsonl" "$J")" 0

bash -n "$BIN/ft-mbox.sh" && ok "bash -n ft-mbox.sh" || bad "bash -n"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
