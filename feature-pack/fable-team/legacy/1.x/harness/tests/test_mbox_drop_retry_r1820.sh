#!/usr/bin/env bash
# test_mbox_drop_retry_r1820.sh — r1820: 우편함이 팀장 자기 «[완료·닫기 요청]» 을 버리지 않고, 버린 쪽지마다 다시 보낼 주체가 정해진다.
#   ① 상한 3 · 자기 «[완료·닫기 요청]»(from = to) + 일반 3 → 닫기 요청 남음 · 버림 = 일반 1(drops log 에 그 seq)   ①′ 자기 [착지] 알림 = 가장 먼저 버림
#   ② 보호 3통 + 일반 1통 send → stdout DROPPED-SELF · rc 5   ②′ 옛 일반 seq 를 버린 send → QUEUED rc0(stderr DROPPED 그대로)
#   ③ 전달 기록 seq 가 drops log seqs= 에 있음 → judge 밀림 · notify 1회 = 재발신 1 · 기록 seq 새 값 · 다시 → 재발신 0
#   ③′ drops log 판독 불가(대역 경로 = 일반 파일 밑) → «판정 불가» 1줄 · 재발신 0   ③″ seq 가 없음(141·oldest_seq 만) → 0   ③⁰ 원장 없음(초기) → 정상 «끝»
#   ④ 손 쪽지 버림 → 받는 좌석 recv 에 DROPPED-SEEN 1줄(회귀)
#   ②s·②′s(fix1 · DA HOLD #294364) 정본 comm/mbox.sh send(옵션 없음) 경로 — ② 는 stdout DROPPED-SELF · rc 5 · ②′ 는 QUEUED rc0
#   변이 M1~M5(사본에만) · 기준판(팩 e5275f2a83) ① ② ③ Red
# 정본 .py 를 임시 폴더에 복사해 돈다 — 실 우편함·실 장부·실 발송·실 launchd 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(fix1 셸 경로)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$(cd -- "$HERE/.." && pwd)"; REPO="$(cd -- "$H/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/r1820.XXXXXX")"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$SECONDS; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
M="byz-x-master-claude#1"; NANO="byz-x-nano-a#0"; DA="byz-x-da-codex#2"; HH="$H"   # HH = 시험할 harness 꼴 폴더(comm·bin) — 기준판·변이 때 바꾼다
E=0; t() { local d="$1"; shift; "$@" && return 0; echo "  x $d :: rc=${RC:-} out=$(head -c 300 <<<"${OUT:-}")"; E=1; }

# ── 우편함(comm 사본 · 상한 3)
menv() { W="$(mktemp -d "$T/m.XXXXXX")"; C="$W/comm"; mkdir -p "$C"; cp "$HH"/comm/mbox*.py "$C/"; cp "$HH/bin/ft-name-lint.sh" "$C/"; : > "$C/mailbox.jsonl"; printf '{"_master": "%s"}\n' "$M" > "$W/seats.json"; }
mx() { FT_SEATS_JSON="$W/seats.json" FT_MBOX_DIR="$C" FT_MBOX_RING=3 FT_MBOX_SEQ_FLOOR=0 python3 "$C/mbox.py" "$@" >"$W/out" 2>"$W/err"; RC=$?; OUT="$(cat "$W/out")"; }
ms() { mx send "$1" "$2" "$3" --force; }
dlog() { cat "$C/mailbox.drops.log" 2>/dev/null; }
nq() { grep -c -- "$1" "$C/mailbox.jsonl" || true; }
c1() {  # ① + ④
  E=0; menv; ms "$M" "$M" "[완료·닫기 요청] r1820t 착지 aaaaaaaaaa · 좌석 $NANO"; ms "$M" "$NANO" "쪽지 1"; ms "$M" "$NANO" "쪽지 2"; ms "$M" "$NANO" "쪽지 3"
  t "① 4번째 send = QUEUED rc0" [ "$RC ${OUT%% *}" = "0 QUEUED" ]; t "① 닫기 요청 남음" [ "$(nq '닫기 요청')" = 1 ]
  t "① 버림 = 일반 seq 2 하나" inc "$(dlog)" "dropped=1 oldest_seq=2 seqs=2"; t "① 일반 2통 남음" [ "$(nq '쪽지 ')" = 2 ]
  mx recv "$M"; t "④ recv DROPPED-SEEN 1줄" [ "$(grep -c '^DROPPED-SEEN 1 #2 ' <<<"$OUT")" = 1 ]; return $E
}
c1b() {  # ①′
  E=0; menv; ms "$M" "$M" "[착지] $NANO r1820t"; ms "$M" "$NANO" "쪽지 1"; ms "$M" "$NANO" "쪽지 2"; ms "$M" "$NANO" "쪽지 3"
  t "①′ 자기 [착지] 가 먼저 버려짐" inc "$(dlog)" "seqs=1"; t "①′ 일반 3 남음" [ "$(nq '쪽지 ')" = 3 ]; return $E
}
c2() {  # ②
  E=0; menv; ms "$M" ft-hil-h1 "[완료 h1] rc=0"; ms "$M" "$NANO" "[완료 h2] rc=0"; ms "$M" slack-oppa "오빠 글"; ms "$M" "$DA" "일반 쪽지"
  t "② stdout DROPPED-SELF" [ "$OUT" = "DROPPED-SELF seq=4 to=$M" ]; t "② rc 5" [ "$RC" = 5 ]
  t "② drops log 에 seq 4" inc "$(dlog)" "seqs=4"; t "② 보호 3 그대로" [ "$(grep -c '"seq"' "$C/mailbox.jsonl")" = 3 ]; return $E
}
c2b() {  # ②′
  E=0; menv; ms "$M" "$DA" "옛 쪽지"; ms "$M" "$NANO" "[완료 h2] rc=0"; ms "$M" "$DA" "둘째"; ms "$M" "$DA" "새 쪽지"
  t "②′ QUEUED seq=4 rc0" [ "$RC ${OUT%% to=*}" = "0 QUEUED seq=4" ]; t "②′ stderr DROPPED 그대로" inc "$(cat "$W/err")" "DROPPED 1 to=$M"
  t "②′ 옛 seq 1 버림" inc "$(dlog)" "seqs=1"; return $E
}
inc() { case "$1" in *"$2"*) return 0;; esac; return 1; }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"   # 실 tmux 0
sx() {  # sx <to> <from> <body> — 정본 mbox.sh send(옵션 없음 · 가드 창만 끔) → OUT(stdout)·RC
  cp "$HH"/comm/mbox*.sh "$HH/comm/bang_command_check.py" "$C/"; git -C "$W" init -q 2>/dev/null
  OUT="$(cd "$W" && PATH="$T/stub:$PATH" FT_SEATS_JSON="$W/seats.json" FT_MBOX_DIR="$C" FT_MBOX_RING=3 FT_MBOX_SEQ_FLOOR=0 FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
    bash "$C/mbox.sh" send "$1" "$2" "$3" 2>"$W/err")"; RC=$?
}
c2s() {  # ②s
  E=0; menv; ms "$M" ft-hil-h1 "[완료 h1] rc=0"; ms "$M" "$NANO" "[완료 h2] rc=0"; ms "$M" slack-oppa "오빠 글"; sx "$M" "$DA" "일반 쪽지"
  t "②s 셸 stdout DROPPED-SELF" [ "$OUT" = "DROPPED-SELF seq=4 to=$M" ]; t "②s 셸 rc 5" [ "$RC" = 5 ]; t "②s drops log 에 seq 4" inc "$(dlog)" "seqs=4"; return $E
}
c2bs() {  # ②′s
  E=0; menv; ms "$M" "$DA" "옛 쪽지"; ms "$M" "$NANO" "[완료 h2] rc=0"; ms "$M" "$DA" "둘째"; sx "$M" "$DA" "새 쪽지"
  t "②′s 셸 QUEUED seq=4 rc0" [ "$RC ${OUT%% to=*}" = "0 QUEUED seq=4" ]; t "②′s 옛 seq 1 버림" inc "$(dlog)" "seqs=1"; return $E
}

# ── 기록 도구(bin 사본 · 전달 기록 사본 · send 대역)
FM="$T/fm.sh"; printf '#!/usr/bin/env bash\nn=$(( $(cat "$FM_SEQ") + 1 )); echo "$n" > "$FM_SEQ"; printf "%%s\\t%%s\\t%%s\\n" "$2" "$3" "$4" >> "$FM_LOG"; echo "QUEUED seq=$n to=$2"\n' > "$FM"
rx() {  # rx <drops 꼴: in|none|absent|bad> → OUT(파이썬 줄들)
  local R; R="$(mktemp -d "$T/r.XXXXXX")"; mkdir -p "$R/.fable-team/comm" "$R/.fable-team/state/seat-record"; echo 100 > "$R/seq"; : > "$R/log"; echo "# 세션 기록" > "$R/.fable-team/state/seat-record/byz-x-nano-r1820t#0.md"
  local cm="$R/.fable-team/comm"
  case "$1" in
    in) echo "2026-11-13T12:00:00 to=$M dropped=2 oldest_seq=40 seqs=40,41" > "$cm/mailbox.drops.log";;
    none) echo "2026-11-13T12:00:00 to=$M dropped=2 oldest_seq=41 seqs=141,4" > "$cm/mailbox.drops.log";;
    bad) : > "$R/plain"; cm="$R/plain/comm";;   # 대역 경로: 일반 파일 밑 = 읽기 OSError(파일 꼴은 그대로 · 하드 룰 19)
  esac
  OUT="$(cd "$R" && FT_INBOX_ROOT="$cm" FT_MBOX="$FM" FM_SEQ="$R/seq" FM_LOG="$R/log" PYTHONPATH="$HH/bin" python3 - "$R" 2>&1 <<'PY'
import sys
from pathlib import Path
import ft_nano_record_due as D, ft_nano_record_notify as N
from ft_nano_record import Ctx, Unjudged, marks, rec_of
ctx = Ctx(Path(sys.argv[1])); M, S, Q = "byz-x-master-claude#1", "byz-x-nano-r1820t#0", "a" * 40
sec = [f"- 세트: {'b' * 40} · 시험: t rc=0", f"- 착지: {Q[:10]} (pack · PR #7)", f"- 완료: {S} · 병합 상태: 착지 {Q[:10]} · 남은 일: 없음"]
rec, base, key = rec_of(marks(sec, S, Q)), {"pr": 7, "q": Q, "stem": "r1820t", "master": M}, f"{S}|r1820t|{Q}"
N.update(ctx, lambda st: st["close"].__setitem__(key, {"rec": rec, "seq": 41, "result": "x", "pr": 7}))
path = ctx.state / "seat-record" / f"{S}.md"
def j():
    try:
        return D.judge(ctx, base, S, "닫기", sec)
    except Unjudged as e:
        return {"k": "판정불가", "why": str(e)}
for n in (1, 2):
    r = j(); print(f"J{n} {r['k']}")
    N.notify_row(ctx, r, 0.0, 1800.0) if r["k"] == "밀림" else N.close_request(ctx, {**base, "seat": S, "rec": rec}, path)
    print(f"S{n} sends={len(open(sys.argv[1] + '/log').read().splitlines())} seq={ctx.store()['close'][key].get('seq')}")
PY
)"; RC=$?
}
c3() { E=0; rx in; t "③ judge 밀림" inc "$OUT" "J1 밀림"; t "③ 재발신 1 · 기록 seq 새 값" inc "$OUT" "S1 sends=1 seq=101"; t "③ 다시 = 끝 · 재발신 0" inc "$OUT" "J2 끝"$'\n'"S2 sends=1 seq=101"; return $E; }
c3b() { E=0; rx bad; t "③′ judge 판정 불가" inc "$OUT" "J1 판정불가"; t "③′ «판정 불가» 1줄씩" [ "$(grep -c '^판정 불가 ' <<<"$OUT")" = 2 ]; t "③′ 재발신 0" inc "$OUT" "S2 sends=0 seq=41"; return $E; }
c3c() { E=0; rx none; t "③″ 끝 · 재발신 0" inc "$OUT" "J1 끝"$'\n'"S1 sends=0 seq=41"; rx absent; t "③⁰ 원장 없음 = 끝 · 0" inc "$OUT" "J1 끝"$'\n'"S1 sends=0 seq=41"; return $E; }

run() { local o; if o="$("$2" 2>&1)"; then ok "$1"; else bad "$1" "$(head -c 500 <<<"$o")"; fi; }
red() { local o; if o="$("$2" 2>&1)"; then bad "$1 통과함(기대 FAIL)"; else ok "$1 FAIL(기대) ::$(grep -m1 '^  x ' <<<"$o" | sed 's/ :: .*//')"; fi; }
echo "== 반례"; run "① 자기 닫기 요청 보존" c1; run "①′ 자기 [착지] 먼저 버림" c1b; run "② 지금 송신 버림 rc5" c2; run "②′ 옛 seq 버림 rc0" c2b
run "②s 셸 mbox.sh 지금 송신 버림 rc5" c2s; run "②′s 셸 mbox.sh 옛 seq 버림 rc0" c2bs
run "③ 옛 seq 재발신 1" c3; run "③′ 판독 불가 = 판정 불가" c3b; run "③″·③⁰ 재발신 0" c3c; S1=$((SECONDS - T0))

echo "== 변이(사본)"
mut() {  # mut <이름> <파일(comm/·bin/)> <옛> <새> → HH = 사본
  HH="$T/mut-$1"; mkdir -p "$HH/comm" "$HH/bin"; cp "$H"/comm/mbox*.py "$HH/comm/"; cp "$H"/bin/ft_nano_record*.py "$H/bin/ft-name-lint.sh" "$HH/bin/"
  python3 - "$HH/$2" "$3" "$4" <<'PY' || bad "$1 변이 자리 못 찾음"
import sys
p, a, b = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a); open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
}
mut M1 comm/mbox_keep.py '    if (head or done) and seat(frm):
        return HUMAN                      # r1820' '    if False:
        return HUMAN                      # r1820'; red "M1 B1 순서 되돌림 → ①" c1
mut M2 comm/mbox_ops.py 'self_drop = seq in seqs' 'self_drop = bool(seqs)'; red "M2 옛 seq 에도 rc5 → ②′" c2b
mut M3 bin/ft_nano_record.py '    return any(str(seq) in m.group(1).split(",")' '    return False and any(str(seq) in m.group(1).split(",")'; red "M3 drops 대조 빼기 → ③" c3
mut M4 bin/ft_nano_record.py '        raise Unjudged(f"우편함 버림 원장 읽기 rc=1 — {type(e).__name__}") from e' '        return True'; red "M4 판독 실패 = 미전달 → ③′" c3b
HH="$H"
B="$T/base"; mkdir -p "$B"
if git -C "$H" archive e5275f2a830ed083e2863153b805fdc99527fb39 -- comm bin/ft-name-lint.sh bin/ft_nano_record.py bin/ft_nano_record_due.py bin/ft_nano_record_notify.py kit/fable-team/bin/ft-mbox.py 2>/dev/null | tar -x -C "$B" 2>/dev/null && [ -f "$B/comm/mbox_keep.py" ]; then
  V="$T/m5"; mkdir -p "$V/harness/comm" "$V/harness/bin" "$V/harness/kit/fable-team/bin" "$V/harness/tests" "$V/skill/scripts"   # M5 = comm·skill 은 고친 판 · kit 만 기준판(한 곳만 안 고침)
  cp "$H"/comm/mbox*.py "$V/harness/comm/"; cp "$H/bin/ft-name-lint.sh" "$V/harness/bin/"; cp "$REPO/skill/scripts/ft-mbox.py" "$V/skill/scripts/"; cp "$B/kit/fable-team/bin/ft-mbox.py" "$V/harness/kit/fable-team/bin/"
  cp "$HERE/test_mbox_keep_human_mail.sh" "$V/harness/tests/"
  o="$(bash "$V/harness/tests/test_mbox_keep_human_mail.sh" 2>&1)"; grep -q '^FAIL ⓘ' <<<"$o" && ok "M5 공유 블록 한 곳만 → test_mbox_keep_human_mail ⓘ FAIL(잡힘)" || bad "M5 못 잡음" "$(grep -m2 'ⓘ' <<<"$o")"
  S2=$((SECONDS - T0)); echo "== 기준판(팩 e5275f2a83)"; HH="$B"; red "기준판 ①" c1; red "기준판 ②" c2; red "기준판 ②s" c2s; red "기준판 ③" c3; HH="$H"
else bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; S2=$((SECONDS - T0)); fi
echo "단계별 초: 반례 $S1 · 변이 $((S2 - S1)) · 기준판 $((SECONDS - T0 - S2)) · 전체 $((SECONDS - T0))"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
