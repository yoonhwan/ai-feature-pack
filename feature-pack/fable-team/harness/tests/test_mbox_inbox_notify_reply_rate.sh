#!/usr/bin/env bash
# test_mbox_inbox_notify_reply_rate.sh — mbox send (판정 423 ③④)
#  ③ 인박스 적재 분류 ①~④·미상이면 받는 좌석의 tick 유무와 무관하게 doorbell · ⑤⑥ 은 지금 규칙(tick 있음→quiet · 없음→ring) 그대로
#  ④ 회신 = 본문 앞 80자의 「쪽지 #<seq>」(받은 seq) 인용만 RATE_LIMIT(5건/60초)에서 면제 · 받은 seq 1개당 1회 · 「PR #N」·「Issue #N」·맨 「#N」 은 면제 0
#     면제 판정은 send 1건당 1회(verdict·record 공유) · 옛 기록 r:1(int) 호환 · 변이 대조 2종(접두 조건·seq 중복 판정을 빼면 시험이 잡는다)
# 임시 comm 사본 + 임시 FT_ROOT + 가짜 seats.json + 가짜 Haiku — 실제 tmux·claude·라이브 .fable-team 쓰기 0 (없는 세션명이라 doorbell 은 absent).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

ROOT="$T/root"; C="$ROOT/.fable-team/comm"; BIN="$ROOT/.fable-team/bin"; mkdir -p "$C" "$BIN"
cp "$REPO/harness/comm/mbox.sh" "$REPO/harness/comm/mbox_doorbell.sh" "$REPO/harness/comm/mbox_guard.sh" "$REPO/harness/comm/mbox_guard_goal.sh" "$REPO/harness/comm/"mbox*.py "$C/"
cp "$REPO/harness/bin/ft-inbox.sh" "$REPO/harness/bin/ft-inbox.py" "$REPO/harness/bin/ft_inbox_core.py" "$BIN/"
printf '#!/bin/sh\ncat >/dev/null; exit 1\n' > "$T/haiku-fail.sh"; chmod +x "$T/haiku-fail.sh"   # 미상은 미상으로 남는다
export FT_ROOT="$ROOT" FT_MBOX_DIR="$C" FT_SEATS_JSON="$T/seats.json" FT_INBOX_HAIKU="$T/haiku-fail.sh"
echo '{"tick-seat#1": {"tick": "ft-master-tick"}, "tick-seat#2": {"tick": "ft-master-tick"}}' > "$T/seats.json"

send() { bash "$C/mbox.sh" send "$@" 2>"$T/err"; }   # <to> <from> <body>
db()   { sed -n 's/.*doorbell=\([a-z]*\).*/\1/p' <<<"$1" | head -1; }
seqof() { sed -n 's/.*QUEUED seq=\([0-9]*\).*/\1/p' <<<"$1" | head -1; }

# ── ③ 알림: tick 있는 좌석(기존 규칙 = quiet)에도 ①~④·미상은 울린다
n=0
for pair in "①:오빠 원문: 이것 확인" "②:[HIL] 행3 질문" "③:판정 요청: A안 B안" "④:[BLOCK] 포트 충돌" "미상:가나다 라마바 규칙표에 없는 문장"; do
  cls="${pair%%:*}"; body="${pair#*:}"; n=$((n+1))
  out="$(send tick-seat#1 "s$n#1" "$body")"
  [ "$(db "$out")" != quiet ] && ok "tick 있는 좌석 + $cls → doorbell 울림($(db "$out"))" || bad "tick 있는 좌석 + $cls 인데 quiet: $out"
done
for pair in "⑤:판정 430 집행 완료" "⑥:참고: 접수했습니다"; do
  cls="${pair%%:*}"; body="${pair#*:}"; n=$((n+1))
  out="$(send tick-seat#2 "s$n#1" "$body")"
  eq "tick 있는 좌석 + $cls → quiet 그대로" "$(db "$out")" quiet
done
out="$(send no-tick-seat#1 s20#1 "참고: 접수했습니다")"
[ "$(db "$out")" != quiet ] && ok "tick 없는 좌석 + ⑥ → 기존 규칙대로 울림" || bad "tick 없는 좌석 + ⑥ 인데 quiet: $out"
out="$(send no-tick-seat#2 s21#1 "[HIL] 질문")"
[ "$(db "$out")" != quiet ] && ok "tick 없는 좌석 + ② → 울림" || bad "tick 없는 좌석 + ② quiet: $out"
out="$(send tick-seat#1 s22#1 "판정 430 집행 완료 두 번째" --urgent)"
[ "$(db "$out")" != quiet ] && ok "--urgent 는 ⑤ 도 그대로 울림" || bad "--urgent quiet: $out"

# ── 오빠 대면 좌석(seats-planner.json `_master`) = doorbell 0 (판정 876 · R85) — ①~④·미상·--urgent 모두 quiet · 다른 좌석은 지금 그대로 · 명시 ring 은 울림
echo '{"_master": "planner-uf#7"}' > "$T/seats-planner.json"
n=40
for pair in "①:오빠 원문: 이것 확인" "②:[HIL] 행3 질문" "③:판정 요청: A안 B안" "④:[BLOCK] 포트 충돌" "미상:가나다 라마바 규칙표에 없는 문장" "⑥:참고: 접수했습니다"; do
  cls="${pair%%:*}"; body="${pair#*:}"; n=$((n+1))
  out="$(send planner-uf#7 "uf$n#1" "$body")"
  eq "오빠 대면 좌석 + $cls → doorbell=quiet" "$(db "$out")" quiet
done
out="$(send planner-uf#7 uf50#1 "판정 430 집행 완료 urgent" --urgent)"
eq "오빠 대면 좌석 + --urgent → doorbell=quiet" "$(db "$out")" quiet
out="$(bash "$C/mbox.sh" relay planner-uf#7 uf51#1 "$HERE/test_mbox_inbox_notify_reply_rate.sh" "[HIL] relay 요약")"
eq "오빠 대면 좌석 + relay ② → doorbell=quiet" "$(db "$out")" quiet
out="$(send no-tick-seat#3 uf52#1 "[HIL] 대면 아닌 좌석 질문")"
[ "$(db "$out")" != quiet ] && ok "대면 아닌 좌석(tick 없음) + ② → 지금 그대로 울림" || bad "대면 아닌 좌석이 quiet: $out"
out="$(send tick-seat#1 uf53#1 "[HIL] 대면 아닌 tick 좌석 질문")"
[ "$(db "$out")" != quiet ] && ok "대면 아닌 좌석(tick 있음) + ② → 지금 그대로 울림" || bad "대면 아닌 tick 좌석이 quiet: $out"
out="$(bash "$C/mbox.sh" ring planner-uf#7 2>&1)"
[ "$(db "$out")" != quiet ] && ok "명시 ring 은 대면 좌석에도 울림(예외)" || bad "명시 ring 이 quiet: $out"
rm -f "$T/seats-planner.json"
out="$(send planner-uf#7 uf54#1 "[HIL] seats-planner.json 없음")"
[ "$(db "$out")" != quiet ] && ok "seats-planner.json 없음 → 판정 불가는 기존대로 울림" || bad "파일 없는데 quiet: $out"

# 적재 실패(ft-inbox.sh 가 rc≠0) → 분류를 모르므로 기존 규칙(tick 있음 = quiet)·WARN·전송 rc 0
mv "$BIN/ft-inbox.sh" "$BIN/ft-inbox.sh.off"; printf '#!/bin/sh\nexit 9\n' > "$BIN/ft-inbox.sh"; chmod +x "$BIN/ft-inbox.sh"
out="$(send tick-seat#1 s23#1 "[HIL] 적재 실패 시험")"; rc=$?
eq "적재 실패여도 send rc 0" "$rc" 0
eq "적재 실패 + tick 있는 좌석 → 기존 규칙(quiet)" "$(db "$out")" quiet
grep -q "WARN inbox ingest 실패" "$T/err" && ok "적재 실패는 stderr WARN" || bad "WARN 없음"
mv "$BIN/ft-inbox.sh.off" "$BIN/ft-inbox.sh"

# ── ④ 회신은 발신 상한에서 뺀다 (회신 인용 = `쪽지 #<seq>` 꼴만 · 받은 seq 1개당 1회)
GUARD="$C/.mbox-guard.json"
# 6건/60초 회신: a#1 이 받은 쪽지 6통(R1..R6)에 각각 `쪽지 #R` 로 회신 → 막힘 0 · RATE_LIMIT 0
Rs=(); for i in 1 2 3 4 5 6; do out="$(send a#1 "asker$i#1" "받을 쪽지 $i")"; Rs+=("$(seqof "$out")"); done
blocked=0
for i in 1 2 3 4 5 6; do
  send "peer-$i#1" a#1 "[a#1->peer-$i#1] 쪽지 #${Rs[$((i-1))]} 처리 $i" >/dev/null || blocked=$((blocked+1))
  grep -q RATE_LIMIT "$T/err" && blocked=$((blocked+100))
done
eq "회신 6건/60초(서로 다른 받은 seq) → 막힘 0 · RATE_LIMIT 0" "$blocked" 0

# 읽혀서 큐에서 빠진 쪽지(recv 뒤)도 받은 기록으로 인정 — 보낸 행 사본
out="$(send a2#1 asker9#1 "읽힐 쪽지")"; R9="$(seqof "$out")"
bash "$C/mbox.sh" recv a2#1 >/dev/null 2>&1
send peer-9#1 a2#1 "[a2#1->peer-9#1] 쪽지 #$R9 처리 (recv 뒤)" >/dev/null; rc=$?
eq "recv 로 큐에서 빠진 뒤의 회신도 면제(rc 0)" "$rc" 0

# 음성: 비회신 6건 → 6번째에서 RATE_LIMIT
for i in 1 2 3 4 5 6; do
  send "q-$i#1" b#1 "[b#1->q-$i#1] 그냥 보고 $i" >/dev/null; rc=$?
  [ "$i" -le 5 ] && eq "비회신 ${i}번째 통과" "$rc" 0
done
eq "비회신 6번째 → 막힘(exit 3)" "$rc" 3
grep -q RATE_LIMIT "$T/err" && ok "비회신 6번째 사유 = RATE_LIMIT" || bad "RATE_LIMIT 사유 없음: $(cat "$T/err")"

# ── 반송 r1 Q1: 상한을 2건으로 낮춰(FT_MBOX_RATE_N=2) 3번째 발신이 막히는지로 면제 여부를 본다
mksend() { local c="$1" r="$2"; shift 2; FT_MBOX_DIR="$c" FT_ROOT="$r" FT_MBOX_RATE_N=2 bash "$c/mbox.sh" send "$@" 2>/dev/null; }
rn2() { mksend "$C" "$ROOT" "$@"; }
third() {  # <send 함수> <frm> <3번째 본문 · @S@=받은 seq> → 3번째 발신 rc (frm 은 받은 쪽지 1통 + 비회신 2건 뒤)
  local fn="$1" frm="$2" body="$3" out S b="${2%%#*}"
  out="$($fn "$frm" "mk-$b#1" "받을 쪽지 $b")"; S="$(seqof "$out")"
  $fn "pl-$b-1#1" "$frm" "plain 1 $b" >/dev/null; $fn "pl-$b-2#1" "$frm" "plain 2 $b" >/dev/null
  $fn "pl-$b-3#1" "$frm" "${body//@S@/$S}" >/dev/null; echo $?
}
eq "① 받은 seq 를 「PR #seq 업데이트」로 적으면 면제 0 → 3번째 막힘" "$(third rn2 c1a#1 "PR #@S@ 업데이트입니다")" 3
eq "① 「Issue #seq」 → 면제 0" "$(third rn2 c1b#1 "Issue #@S@ 확인")" 3
eq "① 접두 없는 「#seq」 → 면제 0" "$(third rn2 c1c#1 "#@S@ 단독 인용")" 3
eq "② 「쪽지 #seq」 → 면제(3번째 통과)" "$(third rn2 c2#1 "쪽지 #@S@ 처리했습니다")" 0

# ③ 「쪽지 #S1·#S2」 → 면제 · 가드 기록 r = 두 seq
o1="$(rn2 c3#1 mk3#1 "받을 쪽지 A")"; S1="$(seqof "$o1")"; o2="$(rn2 c3#1 mk3#1 "받을 쪽지 B")"; S2="$(seqof "$o2")"
rn2 pl3-1#1 c3#1 "plain 1 c3" >/dev/null; rn2 pl3-2#1 c3#1 "plain 2 c3" >/dev/null
rn2 pl3-3#1 c3#1 "쪽지 #${S1}·#${S2} 처리" >/dev/null; rc=$?
eq "③ 「쪽지 #S1·#S2」 → 면제(rc 0)" "$rc" 0
eq "③ 가드 기록 r = [S1,S2]" "$(python3 -c 'import json,sys;g=[r for r in json.load(open(sys.argv[1])) if r["f"]=="c3#1"][-1];print(g["r"]==[int(sys.argv[2]),int(sys.argv[3])])' "$GUARD" "$S1" "$S2")" True

# ④ 같은 「쪽지 #S」 를 다른 본문으로 두 번째 인용 → 두 번째는 셈 포함(RATE_N 넘으면 RATE_LIMIT)
fourth() {  # <send 함수> <frm> → 첫 인용 rc 와 두 번째 인용 rc ("0 3")
  local fn="$1" frm="$2" out S b="${2%%#*}"
  out="$($fn "$frm" "mk-$b#1" "받을 쪽지 $b")"; S="$(seqof "$out")"
  $fn "pl-$b-1#1" "$frm" "plain 1 $b" >/dev/null; $fn "pl-$b-2#1" "$frm" "plain 2 $b" >/dev/null
  $fn "pl-$b-3#1" "$frm" "쪽지 #$S 첫 인용" >/dev/null; local r1=$?
  $fn "pl-$b-4#1" "$frm" "쪽지 #$S 두 번째 인용 다른 본문" >/dev/null; echo "$r1 $?"
}
eq "④ 첫 인용 면제(0) · 같은 seq 두 번째 인용은 셈 포함 → RATE_LIMIT(3)" "$(fourth rn2 c4#1)" "0 3"

# ⑤ 면제 계산 1회 — verdict·record 가 같은 결과를 쓴다(스텁 카운터) · ⑥ 옛 기록 `r: 1`(int) 이 섞여도 예외 0(fail-open 에 안 가리게 직접 호출)
python3 - "$C" "$GUARD" <<'PYEOF' > "$T/probe.out" 2>&1
import json, os, sys, time
C, GUARD = sys.argv[1], sys.argv[2]
sys.path.insert(0, C)
import mbox, mbox_ops
fx = "fx5#1"
mbox.send(fx, "mk5#1", "받을 쪽지 fx5")
S = [r for r in mbox._load(C) if r["to"] == fx][-1]["seq"]
calls = []
orig = mbox_ops._reply_exempt
mbox_ops._reply_exempt = lambda *a, **k: (calls.append(1), orig(*a, **k))[1]
mbox.send("peer-f#1", fx, "[fx5#1->peer-f#1] 쪽지 #%d 처리" % S)
g = [r for r in json.load(open(GUARD)) if r["f"] == fx][-1]
print("CALLS", len(calls), "R", g["r"] == [S])
log = json.load(open(GUARD)) + [{"t": time.time(), "f": fx, "to": "z#1", "h": "x", "r": 1}]
try:
    ex = mbox._reply_exempt(fx, "쪽지 %d 또 인용 쪽지 #%d" % (S, S), log)
    v = mbox._guard_verdict("peer-f#2", fx, "쪽지 #%d 또 인용" % S, ex)
    print("OLD_R", ex == [], v is None or isinstance(v, tuple))
except Exception as e:
    print("OLD_R_EXC", type(e).__name__, e)
PYEOF
eq "⑤ send 1건당 면제 계산 1회 · record 가 같은 결과(r=[seq])" "$(grep '^CALLS' "$T/probe.out")" "CALLS 1 R True"
eq "⑥ 옛 기록 r:1(int) 혼재 → 예외 0 · 중복 판정에 안 씀" "$(grep '^OLD_R' "$T/probe.out")" "OLD_R True True"

# ── 변이 대조: 조건을 빼면 위 시험이 «잡는다» (mbox.py 사본에 한 줄씩 변이)
mutant() {  # <이름> <원문> <대체> → 변이 comm 을 만들고 MC 에 경로
  MC="$T/mut-$1/.fable-team/comm"; MR="$T/mut-$1"; mkdir -p "$MC" "$MR/.fable-team/bin"
  cp "$REPO/harness/comm/mbox.sh" "$REPO/harness/comm/mbox_doorbell.sh" "$REPO/harness/comm/mbox_guard.sh" "$REPO/harness/comm/mbox_guard_goal.sh" "$REPO/harness/comm/"mbox*.py "$MC/"; cp "$BIN"/ft-inbox.* "$BIN"/ft_inbox_core.py "$MR/.fable-team/bin/"
  python3 - "$MC" "$2" "$3" <<'PYEOF'
import glob, os, sys
d, t, r = sys.argv[1], sys.argv[2], sys.argv[3]
hit = [p for p in sorted(glob.glob(os.path.join(d, "mbox*.py"))) if t in open(p, encoding="utf-8").read()]
assert len(hit) == 1, "변이 대상 없음/중복: %s %s" % (t, hit)
s = open(hit[0], encoding="utf-8").read()
open(hit[0], "w", encoding="utf-8").write(s.replace(t, r, 1))
PYEOF
}
mutant noprefix 'r"쪽지 ?#(\d{4,})' 'r"(?:쪽지 ?)?#(\d{4,})'
mm() { mksend "$MC" "$MR" "$@"; }
eq "변이: 「쪽지」 접두 조건을 빼면 ①(PR #seq)이 면제돼 시험이 잡는다(3번째 rc 0)" "$(third mm m1#1 "PR #@S@ 업데이트입니다")" 0
mutant nodup 'cand = [x for x in seqs if x not in used]' 'cand = list(seqs)'
mm() { mksend "$MC" "$MR" "$@"; }
eq "변이: seq 중복 판정을 빼면 ④ 두 번째 인용이 면제돼 시험이 잡는다(0 0)" "$(fourth mm m2#1)" "0 0"

bash -n "$C/mbox.sh" && ok "bash -n mbox.sh" || bad "bash -n"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
