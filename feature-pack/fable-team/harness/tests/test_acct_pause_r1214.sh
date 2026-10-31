#!/usr/bin/env bash
# test_acct_pause_r1214.sh — 계정 풀(provider[/모델]) 단위 «정지» r1214: ft-acct-pause.sh + provider-of-model.tsv
#   + ft-tick 발사 3곳(fire·stall 깨움·goal) 가드 + 한 바퀴 판정기 + spawn 2종 게이트 + ft_model_swap 목적지 검사.
#   반례 R1~R12 + 변이 3(M1 stall 가드 제거 · M2 ring 을 send 전으로 · M3 미완료 기록 삭제) + 비정지 양성 대조.
#   실 tmux·실 우편함·실 좌석·실 정지 파일 0 — 가짜 tmux·가짜 mbox·임시 루트만 쓴다.
#   bash tests/test_acct_pause_r1214.sh            # 전 칸(재진입 표지 + ulimit/timeout 안)
#   bash tests/test_acct_pause_r1214.sh --mutate   # 변이 3종(각각 그 칸이 빨강인지)
[ "${FT_TEST_ACCT_PAUSE_RUNNING:-0}" = 1 ] && { echo "SKIP 재진입(이미 도는 시험)"; exit 0; }
export FT_TEST_ACCT_PAUSE_RUNNING=1
ulimit -u "$(( $(ps -u "$(id -u)" 2>/dev/null | wc -l | tr -d ' ') + 300 ))" 2>/dev/null || true   # r1041: 사용자 프로세스 상한 여유
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
BIN="${FT_TEST_ACCT_BIN:-$REPO/harness/bin}"; KIT="${FT_TEST_ACCT_KIT:-$REPO/harness/kit/fable-team/bin}"
SELF="$HERE/$(basename -- "${BASH_SOURCE[0]:-$0}")"
T0="$(date +%s)"
PH() { echo "PHASE ${1} +$(( $(date +%s) - T0 ))s"; }   # 단계별 초 — 회차 요약 첫 줄에 쓴다
TOOL="$BIN/ft-acct-pause.sh"; RULES="$BIN/provider-of-model.tsv"
fail=0; MUT=0; case "${1:-}" in --mutate) MUT=1;; --mutate-only) MUT=2; shift;; esac
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "${3:-판정}" || bad "${3:-판정} — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "${3:-판정}";; *) bad "${3:-판정} — 없음: «${2}» ← ${1:0:400}";; esac; }
not() { case "$1" in *"$2"*) bad "${3:-판정} — 있으면 안 됨: «${2}» ← ${1:0:300}";; *) ok "${3:-판정}";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
NOW0=1793400000
ISO() { python3 -c 'import sys,datetime;print((datetime.datetime.fromtimestamp(int(sys.argv[1])).astimezone()).isoformat())' "$1"; }
HH()  { python3 -c 'import sys,time;print(time.strftime("%H:%M",time.localtime(int(sys.argv[1]))))' "$1"; }

# ── 가짜 tmux — FAKE_PANES(줄: "<seat> <pane> [busy]") · 호출을 TMUX_LOG 에 남긴다 ──
FB="$T/fakebin"; mkdir -p "$FB"
cat > "$FB/tmux" <<'EOF'
#!/bin/bash
log() { printf '%s\n' "$*" >> "${TMUX_LOG:-/dev/null}"; }
case "$1" in
  list-panes) printf '%s\n' "${FAKE_PANES:-}" | awk 'NF>=2{print $1, $2}'; exit 0;;
  capture-pane) pane=""; prev=""; for a in "$@"; do [ "$prev" = "-t" ] && pane="$a"; prev="$a"; done
    busy="$(printf '%s\n' "${FAKE_PANES:-}" | awk -v p="$pane" '$2==p{print $3; exit}')"
    log "CAPTURE $pane busy=${busy:-0}"
    if [ "$busy" = 1 ]; then printf '✻ Working…\n  esc to interrupt\n'; else printf '❯ \n'; fi; exit 0;;
  send-keys) pane=""; prev=""; for a in "$@"; do [ "$prev" = "-t" ] && pane="$a"; prev="$a"; done
    log "SENDKEYS $pane $*"; exit 0;;
  has-session|list-sessions) exit 0;;
esac
exit 0
EOF
# ── 가짜 mbox — send 는 "<to>\t<from>\t<body>" 로 · ring 은 "RING <seat>" 로 남긴다 · doorbell/실패는 좌석별 파일로 지정 ──
cat > "$FB/mbox.sh" <<'EOF'
#!/bin/bash
case "$1" in
  send) to="$2"; from="$3"; shift 3
        printf 'TRY\t%s\t%s\n' "$to" "$from" >> "${MBOX_DIR:-/tmp}/log"
        if [ -f "${MBOX_DIR:-/tmp}/fail.$to" ]; then echo "REJECT mbox send 실패" >&2; exit 3; fi
        body="$*"; printf 'SEND\t%s\t%s\t%s\n' "$to" "$from" "$body" >> "${MBOX_DIR:-/tmp}/log"
        db="$(cat "${MBOX_DIR:-/tmp}/doorbell.$to" 2>/dev/null || echo quiet)"
        echo "QUEUED seq=$RANDOM to=$to pending=1 doorbell=$db"; exit 0;;
  ring) printf 'RING\t%s\n' "$2" >> "${MBOX_DIR:-/tmp}/log"; echo "RING $2 doorbell=sent"; exit 0;;
esac
echo "SKIP"; exit 0
EOF
# 가짜 tmm — 실제 tmuxc 조회(실머신) 0. spawn 의 보고 대상 해석이 이 목록만 본다.
cat > "$FB/tmm" <<'EOF'
#!/bin/bash
[ "$1" = ls ] && { echo "byz-v65-master-claude#1 byz-v65-nano-claude#2"; exit 0; }
exit 0
EOF
chmod +x "$FB/tmux" "$FB/mbox.sh" "$FB/tmm"
R="$T/repo"; mkdir -p "$R/.fable-team/state"; export MBOX_DIR="$T/mbox"; mkdir -p "$MBOX_DIR"; : > "$MBOX_DIR/log"
PANES='m#1 %1
a#1 %2
x#1 %3
p#1 %4
c#1 %5
o#1 %6
b#1 %7'
export FAKE_PANES="$PANES" TMUX_LOG="$T/tmux.log"; : > "$TMUX_LOG"
# 명부 합집합(seats.json + seats-harness.json) — claude 현역 3(m#1 tick · a#1 tick:null · d#1 pane 없음) · _replaced_by 1(h#0)
cat > "$R/.fable-team/seats.json" <<'EOF'
{"_master":"m#1","m#1":{"role":"master","agent":"claude","model":"claude-sonnet-5-5[1m]","tick":"ft-master-tick"},
 "a#1":{"role":"arch","agent":"claude","model":"claude-fable-5-1[1m]","tick":null},
 "d#1":{"role":"nano","agent":"claude","model":"claude-fable-5-1[1m]","tick":null},
 "x#1":{"role":"nano","agent":"codex","model":"gpt-6-luna","tick":null},
 "p#1":{"role":"nano","agent":"pi","model":"opengateway/deepseek/deepseek-v4.1-flash-ultrafast","tick":null},
 "c#1":{"role":"nano","agent":"cmd","model":"","tick":null},
 "o#1":{"role":"nano","agent":"opencode","model":"","tick":null}}
EOF
cat > "$R/.fable-team/seats-harness.json" <<'EOF'
{"h#1":{"role":"arch","agent":"claude","model":"claude-fable-5-1[1m]","tick":null},
 "h#0":{"role":"stop-ready","agent":"claude","model":"claude-fable-5-1[1m]","tick":null,"_replaced_by":"h#1"}}
EOF
H() { env FT_ACCT_ROOT="$R" FT_ACCT_TMUX="$FB/tmux" FT_ACCT_MBOX="$FB/mbox.sh" FT_ACCT_NOW="${NOWS:-$NOW0}" \
      FT_ACCT_BATCH_SEC="${BATCH:-7}" FT_ACCT_BATCH_SEATS="${BSEATS:-20}" PATH="$FB:$PATH" \
      bash "$TOOL" "$@" 2>&1; }
SENT() { grep -c '^SEND' "$MBOX_DIR/log" 2>/dev/null || true; }
REC() { python3 - "$R/.fable-team/state" "$1" <<'PYX'
import json, sys
st, q = sys.argv[1], sys.argv[2]
try:
    ent = json.load(open(st + "/ACCT_PAUSE"))
except (FileNotFoundError, ValueError):
    ent = {}
e = next(iter(ent.values()), None)
if not e:
    print(""); sys.exit(0)
r = json.load(open(f"{st}/acct-pause/{e['round_id']}.json"))
if q == "n":
    print(len(r.get("recipients") or []))
elif q.startswith("err:"):
    print(next((x.get("last_err") for x in r["recipients"] if x["seat"] == q[4:]), "?"))
elif q == "stage":
    print(r.get("stage"))
PYX
}
RECIPS() { REC n; }

if [ "$MUT" = 1 ]; then
  # 변이 = 사본에 «일부러 한 줄»을 어긋나게 하고, 그 칸이 FAIL 하는지 본다(전 칸 통과 = 변이 미검출 = 시험 구멍).
  mrun() {   # $1 = 이름 · $2 = 기대 FAIL 조각 · $3 = perl 식 · $4 = 대상 파일
    local MD OUT
    MD="$T/mut-$1"; mkdir -p "$MD"
    cp "$BIN"/ft-acct-pause.sh "$BIN"/provider-of-model.tsv "$BIN"/ft-tick.sh "$BIN"/ft-nano-spawn.sh \
       "$BIN"/ft-role-spawn.sh "$BIN"/ft_model_swap.py "$MD"/
    perl -0pi -e "$3" "$MD/$4"
    if cmp -s "$BIN/$4" "$MD/$4"; then bad "변이 $1 미적용(패치가 안 먹었다)"; return; fi
    OUT="$(env -u FT_TEST_ACCT_PAUSE_RUNNING FT_TEST_ACCT_BIN="$MD" FT_TEST_ACCT_KIT="$MD" bash "$SELF" --mutate-only 2>&1)"
    case "$OUT" in
      *"$2"*) ok "변이 $1 → 그 칸 FAIL(«$2»)" ;;
      *) bad "변이 $1 미검출 — «$2» 가 FAIL 하지 않았다: $(printf '%s' "$OUT" | grep '^FAIL' | head -2 | tr '\n' '|')" ;;
    esac
  }
  # M1 = stall 가드 제거(발사 3곳 중 하나) → «S#1 깨움 0» 이 빨강
  mrun stall-guard-removed "S#1 깨움 0" 's/\n *acct_paused "\$seat" stall \|\| continue[^\n]*\n/\n/' ft-tick.sh
  # M2 = ring 을 send «전»으로 → 「적재(S) 뒤 ring(R)」 순서 단언이 빨강
  mrun ring-before-send "R5 순서 = 적재(S) 뒤 ring(R)" 's/        doorbell, err = send_seat\(seat, body\)/        if kind == "resume":\n            ring_seat(seat)\n        doorbell, err = send_seat(seat, body)/' ft-acct-pause.sh
  # M3 = 재개 «전»에 항목 삭제 → 부분 실패 때 항목 유지 단언이 빨강
  mrun delete-before-release "항목 삭제 0" 's/(                rec\["stage"\] = "releasing"\n                write_json\(REC \/ f"\{rid\}\.json", rec\)\n)/$1                del state[prov]; write_json(FILE, state)\n/' ft-acct-pause.sh
  echo "---- fail=$fail"; [ "$fail" -eq 0 ] && echo "ALL PASS(mutate)"
  exit "$fail"
fi

PH "start"
PH "spec"
# ── 0. 파일 규격 ──────────────────────────────────────────────────────────────
bash -n "$TOOL" && ok "bash -n ft-acct-pause.sh" || bad "bash -n"
bash -n "$BIN/ft-tick.sh" && ok "bash -n ft-tick.sh" || bad "bash -n tick"
bash -n "$BIN/ft-nano-spawn.sh" && ok "bash -n ft-nano-spawn.sh" || bad "bash -n nano-spawn"
bash -n "$BIN/ft-role-spawn.sh" && ok "bash -n ft-role-spawn.sh" || bad "bash -n role-spawn"
python3 -c "import ast,sys;ast.parse(open(sys.argv[1]).read())" "$BIN/ft_model_swap.py" && ok "ft_model_swap.py 구문" || bad "model_swap 구문"
if [ -z "${FT_TEST_ACCT_BIN:-}" ]; then
  for f in ft-acct-pause.sh provider-of-model.tsv ft-tick.sh ft-nano-spawn.sh ft-role-spawn.sh ft_model_swap.py; do
    cmp -s "$BIN/$f" "$KIT/$f" && ok "bin·kit cmp0 $f" || bad "bin·kit 어긋남 $f"
  done
  # 신설 .sh 3종 = 100644(승인 경로 · FORBID mode 는 실행 비트 .sh 를 막는다 · 판정 2941/2918) — 기존 .sh 는 기준판 그대로
  MX=0
  for f in "$TOOL" "$KIT/ft-acct-pause.sh" "$HERE/test_acct_pause_r1214.sh"; do [ -x "$f" ] && MX=1; done
  [ "$MX" = 0 ] && ok "신설 .sh 3종 0o644(실행 비트 0)" || bad "신설 .sh 에 실행 비트가 붙었다"
  [ -f "$TOOL" ] && [ ! -L "$TOOL" ] && ok "일반 파일(심링크 0)" || bad "일반 파일 아님"
else
  ok "변이 사본 모드 — bin·kit cmp0 검사 생략"
fi
eq "$(grep -cvE '^#|^$' "$RULES")" 4 "규칙표 기본 4행"

PH "R1"
# ── R1 set/status/clear 규칙 ─────────────────────────────────────────────────
out="$(H set --provider claude --until "$(ISO $((NOW0+600)))" --reason 'r1214 시험 정지 · claude 풀')"; rc=$?
eq "$rc" 0 "R1 set claude rc0"
has "$out" "SET pause claude/*" "R1 set 출력"
RID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["claude"]["round_id"])' "$R/.fable-team/state/ACCT_PAUSE")"
case "$RID" in claude-"$NOW0"-????) ok "R1 round_id 꼴(<P>-<set_at>-<4자>)";; *) bad "R1 round_id 꼴: $RID";; esac
out="$(H status)"; rc=$?
{ [ "$rc" = 3 ] && has "$out" "PAUSED claude/" "R1 status rc3 PAUSED"; } || bad "R1 status rc=$rc $out"
tsr="$(H set --provider claude --until "$(ISO $((NOW0+600)))" --reason 'r1214 중복 정지 시도')"; rc=$?
{ [ "$rc" = 1 ] && has "$tsr" "이미 있다" "R1 같은 provider 재 set REJECT"; } || bad "R1 재 set rc=$rc $tsr"
out="$(H set --provider codex --until "$(ISO $((NOW0+600)))" --reason 'r1214 시험 정지 · codex 풀')"; rc=$?
eq "$rc" 0 "R1 codex set rc0(독립 추가)"
eq "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$R/.fable-team/state/ACCT_PAUSE")" 2 "R1 항목 2개"
out="$(H clear --provider codex)"; rc=$?
eq "$rc" 0 "R1 clear --provider codex rc0"
eq "$(python3 -c 'import json,sys;print(",".join(sorted(json.load(open(sys.argv[1])))))' "$R/.fable-team/state/ACCT_PAUSE")" claude "R1 claude 항목 유지"
out="$(H set --provider deepseek --until "$(ISO $((NOW0+9*3600)))" --reason 'r1214 기한 초과 시험')"; rc=$?
{ [ "$rc" = 1 ] && has "$out" "지금+8시간" "R1 until 9시간 REJECT"; } || bad "R1 until 9h rc=$rc $out"
out="$(H set --provider deepseek --until "$(ISO $((NOW0+4*3600)))" --release-at "$(ISO $((NOW0+300)))" --reason 'r1214 유효 끝 = 이른 쪽 시험')"; rc=$?
eq "$rc" 0 "R1 until+4h · release_at+300s set rc0"
NOWS=$((NOW0+600)); out="$(H status)"; rc=$?; NOWS=$NOW0
has "$out" "RELEASED deepseek/*" "R1 유효 끝 = min(until, release_at) — release_at 이 먼저면 풀린다"
not "$out" "PAUSED deepseek" "R1 deepseek 는 아직 정지 아님"
H clear >/dev/null; eq "$(ls "$R/.fable-team/state/ACCT_PAUSE" 2>/dev/null | wc -l | tr -d ' ')" 0 "R1 clear 전부 → 파일 삭제"

PH "R4"
NOWS=$NOW0
# ── R4 provider 판별(규칙표 4행 + agent 기본표 · 판정 불가) ───────────────────
H set --provider claude --until "$(ISO $((NOW0+600)))" --reason 'R4 claude 풀 전체 정지' >/dev/null
H set --provider deepseek --until "$(ISO $((NOW0+600)))" --reason 'R4 deepseek 풀 전체 정지' >/dev/null
out="$(H status --check --agent claude --model '')"; rc=$?
eq "$rc" 3 "R4 좌석 model 비고 agent=claude → claude 적용"
out="$(H status --check --agent pi --model 'opengateway/deepseek/x')"; rc=$?
eq "$rc" 3 "R4 pi 좌석 opengateway/deepseek/x → deepseek"
out="$(H status --check --agent pi --model 'deepseek-v4.1-flash-ultrafast')"; rc=$?
eq "$rc" 3 "R4 모델명 단독 deepseek-v4.1-… → deepseek"
out="$(H status --check --agent cmd --model '')"; rc=$?
eq "$rc" 3 "R4 cmd 좌석 model 없음 → agent 기본표 deepseek"
out="$(H status --check --agent opencode --model '')"; rc=$?
{ [ "$rc" = 4 ] && has "$out" "판정 불가(provider)" "R4 opencode model 없음 → 판정 불가 rc4"; } || bad "R4 opencode rc=$rc $out"
out="$(H status --check --agent codex --model 'gpt-6-luna')"; rc=$?
eq "$rc" 0 "R4 codex 좌석은 정지 아님"
out="$(H status --check claude)"; rc=$?
eq "$rc" 3 "R4 P[/M] 꼴(--check claude)도 받는다"
H clear >/dev/null

PH "R6"
NOWS=$NOW0
# ── R6 수신자 = 명부 합집합 ∩ 생존 ∩ provider · 도구 발신자 · 실패 재송 ─────
: > "$MBOX_DIR/log"
H set --provider claude --until "$(ISO $((NOW0+600)))" --reason 'R6 수신자 합집합 시험' >/dev/null
eq "$(RECIPS)" 2 "R6 수신자 = 살아 있는 claude 현역 2(m#1·a#1) — 은퇴(h#0)·죽은 좌석(d#1) 제외"
eq "$(grep -c '^SEND	' "$MBOX_DIR/log")" 2 "R6 예고 2통"
eq "$(grep -c '^SEND	.*	ft-acct-pause	' "$MBOX_DIR/log")" 2 "R6 발신자 = 도구 이름 ft-acct-pause(좌석 이름 0)"
not "$(cat "$MBOX_DIR/log")" "h#0" "R6 은퇴(_replaced_by) 좌석 0통"
not "$(cat "$MBOX_DIR/log")" "d#1" "R6 죽은 좌석(has-session 실패) 0통"
has "$(grep '^SEND' "$MBOX_DIR/log" | head -1)" "[정지 예고] claude" "R6 예고 본문 머리"
H clear >/dev/null
: > "$MBOX_DIR/log"; touch "$MBOX_DIR/fail.a#1"
H set --provider claude --until "$(ISO $((NOW0+600)))" --reason 'R6 부분 실패 재송 시험' >/dev/null
eq "$(grep -c '^TRY	a#1	' "$MBOX_DIR/log")" 1 "R6 실패 좌석도 1회는 시도"
[ -n "$(REC err:a#1)" ] && ok "R6 실패 → last_err 기록" || bad "R6 실패 last_err 없음"
rm -f "$MBOX_DIR/fail.a#1"; H status >/dev/null
eq "$(grep -c '^TRY	a#1	' "$MBOX_DIR/log")" 2 "R6 다음 status 호출에서 그 좌석만 재송"
eq "$(grep -c '^TRY	m#1	' "$MBOX_DIR/log")" 1 "R6 이미 보낸 좌석은 재송 0"
H clear >/dev/null

PH "R5"
NOWS=$NOW0
# ── R5 만료 → [재개] 적재 먼저 → 유휴 tick:null 만 ring · busy 는 다음 호출 ────
: > "$MBOX_DIR/log"; : > "$TMUX_LOG"; : > "$MBOX_DIR/doorbell.m#1"; echo sent > "$MBOX_DIR/doorbell.m#1"
echo quiet > "$MBOX_DIR/doorbell.a#1"
python3 - "$R/.fable-team/seats.json" <<'PYX'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["b#1"] = {"role": "nano", "agent": "claude", "model": "claude-fable-5-1[1m]", "tick": None}
json.dump(d, open(p, "w"))
PYX
export FAKE_PANES='m#1 %1
a#1 %2
b#1 %7 1'
R5RID="$(NOWS=$NOW0 H set --provider claude --until "$(ISO $((NOW0+600)))" --release-at "$(ISO $((NOW0+120)))" --reason 'R5 풀림·재개 시험' | sed -n 's/.*round=\([^ ]*\).*/\1/p')"
[ -n "$R5RID" ] && ok "R5 회차 id" || bad "R5 회차 id 없음"
: > "$MBOX_DIR/log"
NOWS=$((NOW0+180)); out="$(H status)"; rc=$?; NOWS=$NOW0
eq "$rc" 3 "R5 재개가 busy 좌석 때문에 미완 → rc3(항목 유지)"
has "$out" "RELEASING claude/*" "R5 RELEASING 줄"
eq "$(grep -c '^SEND	m#1	.*\[재개\]' "$MBOX_DIR/log")" 1 "R5 tick 좌석 m#1 에 [재개] 1통(먼저 적재)"
eq "$(grep -c '^SEND	b#1	' "$MBOX_DIR/log")" 0 "R5 바쁜 tick:null 좌석 b#1 은 send 0"
eq "$(grep -c '^RING	b#1' "$MBOX_DIR/log")" 0 "R5 바쁜 좌석 ring 0"
eq "$(grep -c '^RING	m#1' "$MBOX_DIR/log")" 0 "R5 doorbell=sent 좌석은 ring 0(이중 깨움 0)"
eq "$(grep -c '^RING	a#1' "$MBOX_DIR/log")" 1 "R5 doorbell=quiet 좌석만 ring 1회"
eq "$(awk -F'\t' '$1=="SEND"&&$2=="a#1"{print "S"} $1=="RING"&&$2=="a#1"{print "R"}' "$MBOX_DIR/log" | tr -d '\n')" "SR" "R5 순서 = 적재(S) 뒤 ring(R)"
eq "$(REC err:b#1)" busy "R5 바쁜 좌석 last_err=busy"
: > "$MBOX_DIR/log"; export FAKE_PANES="$PANES"
NOWS=$((NOW0+240)); out="$(H status)"; rc=$?; NOWS=$NOW0
eq "$rc" 0 "R5 유휴로 바뀐 뒤 전부 완료 rc0"
has "$out" "RELEASED claude/*" "R5 전부 찬 뒤 «RELEASED»"
eq "$(grep -c '^SEND	b#1	.*\[재개\]' "$MBOX_DIR/log")" 1 "R5 다음 호출에서 b#1 재개 1통"
eq "$(grep -c '^RING	b#1' "$MBOX_DIR/log")" 1 "R5 b#1 ring 1회"
eq "$(ls "$R/.fable-team/state/ACCT_PAUSE" 2>/dev/null | wc -l | tr -d ' ')" 0 "R5 완료 뒤 항목 삭제"
eq "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["stage"])' "$R/.fable-team/state/acct-pause/$R5RID.json")" released "R5 기록 stage=released"

PH "R7"
NOWS=$NOW0
# ── R7 부분 실패 = 기록 유지 · 잠금 8초 = rc4 · 동시 status 겹침 0 ────────────
: > "$MBOX_DIR/log"; touch "$MBOX_DIR/fail.m#1"
NOWS=$NOW0 H set --provider claude --until "$(ISO $((NOW0+600)))" --reason 'R7 부분 실패·잠금 시험' >/dev/null
: > "$MBOX_DIR/log"
NOWS=$((NOW0+800)); H status >/dev/null; NOWS=$NOW0
eq "$(python3 -c 'import json,sys,os
p=sys.argv[1]
print("claude" in json.load(open(p)) if os.path.exists(p) else False)' "$R/.fable-team/state/ACCT_PAUSE")" True "R7 재개 send 실패 → 항목 삭제 0(기록 유지)"
rm -f "$MBOX_DIR/fail.m#1"; : > "$MBOX_DIR/log"; : > "$MBOX_DIR/doorbell.m#1"
NOWS=$((NOW0+860)); H status >/dev/null; NOWS=$NOW0
eq "$(grep -c '^SEND	m#1	' "$MBOX_DIR/log")" 1 "R7 다음 status 에서 그 좌석만 재송"
eq "$(python3 -c 'import json,sys,os
p=sys.argv[1]
print("claude" in json.load(open(p)) if os.path.exists(p) else False)' "$R/.fable-team/state/ACCT_PAUSE")" False "R7 다 찬 뒤 항목 삭제"
H clear >/dev/null
# 잠금 8초 점유 → rc4 «판정 불가 잠금»
python3 - "$R/.fable-team/state/acct-pause/lock" <<'PY' &
import fcntl, sys, time
fh = open(sys.argv[1], "a+"); fcntl.flock(fh, fcntl.LOCK_EX); time.sleep(3)
PY
HOLD=$!; sleep 0.6
out="$(FT_ACCT_LOCK_WAIT=1 H status --check claude)"; rc=$?
{ [ "$rc" = 4 ] && has "$out" "판정 불가 잠금" "R7 잠금 점유 > 대기(7초 계약 · 시험은 1초) → rc4 «판정 불가 잠금»"; } || bad "R7 잠금 rc=$rc $out"
kill "$HOLD" 2>/dev/null; wait "$HOLD" 2>/dev/null
# 동시 status 2 → 좌석당 send 1회(잠금)
H set --provider claude --until "$(ISO $((NOW0+600)))" --reason 'R7 동시 status 겹침 시험' >/dev/null
: > "$MBOX_DIR/log"; echo quiet > "$MBOX_DIR/doorbell.m#1"
NOWS=$((NOW0+700)) bash -c "FT_ACCT_ROOT='$R' FT_ACCT_TMUX='$FB/tmux' FT_ACCT_MBOX='$FB/mbox.sh' FT_ACCT_NOW=$((NOW0+700)) PATH='$FB:$PATH' bash '$TOOL' status >/dev/null 2>&1" &
p1=$!; NOWS=$((NOW0+700)) bash -c "FT_ACCT_ROOT='$R' FT_ACCT_TMUX='$FB/tmux' FT_ACCT_MBOX='$FB/mbox.sh' FT_ACCT_NOW=$((NOW0+700)) PATH='$FB:$PATH' bash '$TOOL' status >/dev/null 2>&1" &
p2=$!; wait "$p1" "$p2" 2>/dev/null
eq "$(grep -c '^SEND	m#1	' "$MBOX_DIR/log")" 1 "R7 동시 status 2 → 같은 좌석 send 1회"
H clear >/dev/null

PH "R8"
NOWS=$NOW0
# ── R8 손상 = rc4 · status --check 무부작용 · 틱은 발사 유지 ──────────────────
H set --provider claude --until "$(ISO $((NOW0+600)))" --reason 'R8 파일 손상 시험' >/dev/null
cp "$R/.fable-team/state/ACCT_PAUSE" "$T/ok.json"
printf 'not json\n' > "$R/.fable-team/state/ACCT_PAUSE"
out="$(H status)"; rc=$?
{ [ "$rc" = 4 ] && has "$out" "ERROR pause" "R8 파일 손상 → status rc4 ERROR pause"; } || bad "R8 status rc=$rc $out"
h1="$(shasum -a 256 < "$R/.fable-team/state/ACCT_PAUSE")$(ls -la "$R/.fable-team/state/acct-pause" | shasum -a 256)"
out="$(H status --check --agent claude --model 'x')"; rc=$?
eq "$rc" 4 "R8 손상이면 --check 도 rc4"
h2="$(shasum -a 256 < "$R/.fable-team/state/ACCT_PAUSE")$(ls -la "$R/.fable-team/state/acct-pause" | shasum -a 256)"
eq "$h1" "$h2" "R8 status --check 무부작용(해시 같음)"
cp "$T/ok.json" "$R/.fable-team/state/ACCT_PAUSE"; H clear >/dev/null

PH "R3-R10"
NOWS=$NOW0
# ── R10·R3 spawn 게이트(두 판정 모음 · 자리) ─────────────────────────────────
CB="$T/cb"; mkdir -p "$CB"; cp "$BIN"/* "$CB"/ 2>/dev/null
printf '#!/bin/bash\n[ "${1:-}" = status ] && { echo "swap=100 memfree=99 agents=1 level=0 rate=0"; exit 0; }\necho "OK resource"\nexit 0\n' > "$CB/ft-resource-gate.sh"; chmod +x "$CB/ft-resource-gate.sh"
printf '#!/bin/bash\nexit 0\n' > "$CB/ft-all-stop.sh"; chmod +x "$CB/ft-all-stop.sh"
echo "x" > "$T/card.md"
cb() { env FT_ACCT_ROOT="$R" FT_ACCT_TMUX="$FB/tmux" FT_ACCT_MBOX="$FB/mbox.sh" FT_ACCT_NOW="${NOWS:-$NOW0}" \
       FT_RES_ROOT="$R" FT_HOLD_GATE="$CB/ft-resource-gate.sh" FT_MBOX_SH="$FB/mbox.sh" FT_RECLAIM=0 FT_PM_SEATS="$R/.fable-team/seats.json" \
       PATH="$FB:$PATH" bash "$CB/$@" 2>&1; }
out="$(cb ft-nano-spawn.sh "$T/card.md" --model 'claude-sonnet-5-5[1m]' --dry-run)"; rc=$?
not "$out" "정지 중" "R3 모델이 다르면 acct 게이트 통과"
H set --provider claude --model 'claude-fable-5-1' --until "$(ISO $((NOW0+600)))" --reason 'R3 모델 한정 정지 시험' >/dev/null
out="$(cb ft-nano-spawn.sh "$T/card.md" --model 'claude-fable-5-1[1m]' --dry-run)"; rc=$?
{ [ "$rc" = 3 ] && has "$out" "정지 중 · 풀림 $(HH $((NOW0+600)))" "R3 [1m] 정규화 일치 → rc3 «정지 중 · 풀림 HH:MM»"; } || bad "R3 rc=$rc [$(printf '%s' "$out" | tr '\n' '|')]"
out="$(cb ft-nano-spawn.sh "$T/card.md" --model 'claude-sonnet-5-5[1m]' --dry-run)"; rc=$?
not "$out" "정지 중" "R3 sonnet 은 통과"
out="$(cb ft-role-spawn.sh master --model 'claude-fable-5-1[1m]' --dry-run)"; rc=$?
{ [ "$rc" = 3 ] && has "$out" "정지 중 · 풀림" "R3 역할 spawn 도 같은 게이트 rc3"; } || bad "R3 role rc=$rc $out"
H clear >/dev/null
# R10 자원 정지 + 계정 정지 = 사유 2줄 rc3 · 워크트리·카드 쓰기 0
echo '{"verdict": 2104, "until": "2026-12-31T00:00:00+09:00", "until_epoch": 1798623600, "release": "swap<1", "reason": "R10 두 정지", "set_at": 1793400000}' > "$R/.fable-team/state/SPAWN_HOLD"
H set --provider claude --until "$(ISO $((NOW0+600)))" --reason 'R10 두 정지 동시 시험' >/dev/null
out="$(cb ft-nano-spawn.sh "$T/card.md" --model 'claude-sonnet-5-5[1m]' --dry-run)"; rc=$?
{ [ "$rc" = 3 ] && has "$out" "REJECT hold" "R10 둘 다 → rc3" && has "$out" "PAUSED claude/" "R10 둘 다 → 사유 2줄(자원 + 계정)"; } || bad "R10 rc=$rc [$(printf '%s' "$out" | tr '\n' '|')]"
eq "$(printf '%s\n' "$out" | grep -cE '^(REJECT hold|PAUSED claude)')" 2 "R10 사유 정확히 2줄"
[ ! -e "$T/worktrees" ] && ok "R10 워크트리 0" || bad "R10 워크트리 생김"
H clear >/dev/null
out="$(cb ft-nano-spawn.sh "$T/card.md" --model 'claude-sonnet-5-5[1m]' --dry-run)"; rc=$?
{ [ "$rc" = 3 ] && has "$out" "REJECT hold" "R10 계정만 clear → 자원 정지 1줄" && not "$out" "PAUSED claude" "R10 계정만 clear → 계정 사유 0"; } || bad "R10 clear 뒤 rc=$rc $out"
rm -f "$R/.fable-team/state/SPAWN_HOLD"
# R8 spawn: 계정 파일 손상 = «판정 불가» 중단
printf 'broken\n' > "$R/.fable-team/state/ACCT_PAUSE"
out="$(cb ft-nano-spawn.sh "$T/card.md" --model 'claude-sonnet-5-5[1m]' --dry-run)"; rc=$?
{ [ "$rc" = 4 ] && has "$out" "판정 불가" "R8 손상 → spawn rc4 «판정 불가» 중단"; } || bad "R8 spawn rc=$rc $out"
rm -f "$R/.fable-team/state/ACCT_PAUSE"

PH "R9"
NOWS=$NOW0
# ── R9 ft_model_swap 목적지 검사 ─────────────────────────────────────────────
swapchk() { PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$BIN" FT_ACCT_ROOT="$R" FT_ACCT_MBOX="$FB/mbox.sh" FT_ACCT_TMUX="$FB/tmux" python3 - "$BIN" "$R" "$1" <<'PY'
import argparse, importlib.util, sys
b, root, model = sys.argv[1:4]
spec = importlib.util.spec_from_file_location("ftms", b + "/ft_model_swap.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
class D: pass
d = D(); d.a = argparse.Namespace(root=root)
print(m.Swap.pause_block(d, model))
PY
}
H set --provider claude --model 'claude-opus-5-5[1m]' --until "$(ISO $((NOW0+600)))" --reason 'R9 목적지 모델 정지' >/dev/null
eq "$(swapchk 'claude-opus-5-5[1m]')" "claude/claude-opus-5-5" "R9 목적지가 정지 → PLAN «정지 중 claude/claude-opus-5-5 · 후계 0» 근거"
eq "$(swapchk 'claude-sonnet-5-5[1m]')" "" "R9 정지 아닌 목적지 → 검사 통과(기준판과 같은 교대)"
grep -q 'PLAN 정지 중 {why} · 후계 0' "$BIN/ft_model_swap.py" && ok "R9 PLAN 줄 꼴" || bad "R9 PLAN 줄 꼴 어긋남"
H clear >/dev/null
printf 'broken\n' > "$R/.fable-team/state/ACCT_PAUSE"
case "$(swapchk 'claude-opus-5-5[1m]')" in "판정 불가("*) ok "R9 손상 → 판정 불가(후계 0)";; *) bad "R9 손상 판정";; esac
rm -f "$R/.fable-team/state/ACCT_PAUSE"

PH "R12"
NOWS=$NOW0
# ── R12 접기(7일) · 배치(25 → 20 + 5) ───────────────────────────────────────
mkdir -p "$R/.fable-team/state/acct-pause"
python3 - "$R/.fable-team/state/acct-pause" "$NOW0" <<'PY'
import json, sys
d, now = sys.argv[1], int(sys.argv[2])
json.dump({"stage": "released", "set_at": now - 8 * 86400, "ended_at": now - 8 * 86400, "recipients": []}, open(f"{d}/dead-round.json", "w"))
json.dump({"stage": "releasing", "set_at": now - 30 * 86400, "recipients": [{"seat": "x#1"}]}, open(f"{d}/live-round.json", "w"))
PY
H set --provider claude --until "$(ISO $((NOW0+600)))" --reason 'R12 접기 시험 정지' >/dev/null; H status >/dev/null
{ [ ! -e "$R/.fable-team/state/acct-pause/dead-round.json" ] && ok "R12 7일 넘은 released 기록 접힘"; } || bad "R12 7일 기록 안 접힘"
{ [ -e "$R/.fable-team/state/acct-pause/live-round.json" ] && ok "R12 미완료 기록은 30일이어도 유지"; } || bad "R12 미완료 기록 삭제됨"
H clear >/dev/null
# 배치: 좌석 25 → 한 호출 20 · 다음 호출 5
python3 - "$R/.fable-team/seats.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for i in range(25):
    d[f"n{i}#1"] = {"role": "nano", "agent": "claude", "model": "claude-fable-5-1[1m]", "tick": None}
json.dump(d, open(p, "w"))
PY
export FAKE_PANES="$(for i in $(seq 0 24); do echo "n$i#1 %$((100+i))"; done)"
: > "$MBOX_DIR/log"
BATCH=60 BSEATS=20 H set --provider claude --model 'claude-fable-5-1' --until "$(ISO $((NOW0+600)))" --reason 'R12 배치 상한 시험' >/dev/null
eq "$(grep -c '^SEND	' "$MBOX_DIR/log")" 20 "R12 한 호출 발신 = 20(상한)"
BATCH=60 BSEATS=20 H status >/dev/null
eq "$(grep -c '^SEND	' "$MBOX_DIR/log")" 25 "R12 다음 호출이 남은 5를 이어서(총 25)"
H clear >/dev/null
export FAKE_PANES="$PANES"

PH "R2-R11"
NOWS=$NOW0
# ── R2·R11 틱 통합(DRY=0 전체 바퀴 · 가드 3곳 · 회차 1줄 · DRY/끄기) ──────────
LIVE="$T/repo/.fable-team/bin/ft-tick.sh"; mkdir -p "$T/repo/.fable-team/bin"; cp "$BIN/ft-tick.sh" "$LIVE"
cat > "$T/seats-tick.json" <<'EOF'
{"_master":"M#1","_hil_route":"M#1",
 "M#1":{"role":"master","agent":"claude","model":"claude-sonnet-5-5[1m]","tick":"ft-master-tick"},
 "C#1":{"role":"nano","agent":"claude","model":"claude-fable-5-1[1m]","tick":"ft-pm-tick"},
 "X#1":{"role":"nano","agent":"codex","model":"gpt-6-luna","tick":"ft-pm-tick"},
 "O#1":{"role":"nano","agent":"opencode","model":"","tick":"ft-pm-tick"},
 "S#1":{"role":"nano","agent":"claude","model":"claude-fable-5-1[1m]","tick":null}}
EOF
cat > "$T/seatstatus-stub.sh" <<'STUB'
#!/bin/bash
case "$1" in
  one) if [ "$2" = "S#1" ]; then echo "IDLE 1793400000 900000 no"; else echo "IDLE 1793400000 60 no"; fi; exit 0;;
  turn) echo "IDLE 1793400000 0 no jsonl"; exit 0;;
esac
exit 0
STUB
printf '#!/bin/bash\necho "goal-tick called $*" >> "%s/goal.log"\n' "$T" > "$T/goal-stub.sh"
printf '#!/bin/bash\nexit 0\n' > "$T/alive-stub.sh"
chmod +x "$T/seatstatus-stub.sh" "$T/goal-stub.sh" "$T/alive-stub.sh"
TPANES='M#1 %11
C#1 %12
X#1 %13
O#1 %14
S#1 %15'
BASE=(FT_TICK_SEATS="$T/seats-tick.json" FT_TICK_MBOX="$FB/mbox.sh" FT_TICK_SEAT_STATUS="$T/seatstatus-stub.sh"
  FT_TICK_IDLE_ENABLED=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_API_OUTAGE=0 FT_TICK_HIL=0 FT_TICK_LAUNCHD=0
  FT_TICK_LEAK_REAP=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 FT_TICK_QUEUE=0 FT_TICK_QUEUE_FULL=0 FT_TICK_UNPUSHED=0
  FT_TICK_RENAMED=0 FT_TICK_RAISED=0 FT_TICK_DRIFT=0 FT_TICK_PATH_FIRST="$FB"
  FT_TICK_WT_SWEEP=0 FT_TICK_AUTONOMY=0 FT_TICK_ZOMBIE_CLEAN=0 FT_TICK_IDLE_LONG=0
  FT_TICK_STALL_INTERVAL=0 FT_TICK_STALL_MIN=15 FT_TICK_STALL_WAKE_GAP=0
  FT_TICK_MASTER_INTERVAL=0 FT_TICK_MASTER_MIN_GAP=0 FT_TICK_PM_INTERVAL=0 FT_TICK_PM_MIN_GAP=0 FT_TICK_GOAL_INTERVAL=0
  FT_TICK_MASTER_MSG=x FT_TICK_PM_MSG=x FT_TICK_GOAL_TICK="$T/goal-stub.sh" FT_TICK_AGENT_ALIVE="$T/alive-stub.sh"
  FT_TICK_AGENT_ALIVE="$T/alive-stub.sh"
  FT_TICK_ACCT_PAUSE_BIN="$BIN/ft-acct-pause.sh" FT_ACCT_ROOT="$R" FT_ACCT_TMUX="$FB/tmux" FT_ACCT_MBOX="$FB/mbox.sh"
  FT_ACCT_NOW="$NOW0" FAKE_PANES="$TPANES" TMUX_LOG="$T/tmux.log" MBOX_DIR="$MBOX_DIR")
runtick() { local n="$1"; shift; mkdir -p "$T/$n/state"
  ( cd "$T/repo" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
      "${BASE[@]}" FT_TICK_STATE_DIR="$T/$n/state" FT_TICK_STAMP_PREFIX="$T/$n/p-" FT_TICK_PIDFILE="$T/$n/pid" \
      "$@" PATH="$FB:$PATH" bash "$LIVE" --once > "$T/$n/out" 2>&1 )
  echo "$T/$n/out"; }
keycount() { grep -cE "$2" "$1" 2>/dev/null || true; }
ACCT="$T/repo/.fable-team/state/ACCT_PAUSE"
# 비정지 양성 대조 — 같은 입력 · 정지 없음 → send-keys 실제 발생
rm -f "$ACCT"; : > "$TMUX_LOG"; : > "$T/goal.log"
OUT="$(runtick pos)"
{ [ "$(keycount "$TMUX_LOG" '^SENDKEYS %11 ')" -ge 1 ] && [ "$(keycount "$TMUX_LOG" '^SENDKEYS %12 ')" -ge 1 ] &&
  [ "$(keycount "$TMUX_LOG" '^SENDKEYS %13 ')" -ge 1 ] && [ "$(keycount "$TMUX_LOG" '^SENDKEYS %15 ')" -ge 1 ] &&
  [ -s "$T/goal.log" ]; } && ok "R2 양성 대조: 정지 없음 → claude 좌석 발사(≥3) + goal 호출" || bad "R2 양성 대조 실패 $(grep -c SENDKEYS "$TMUX_LOG") $(cat "$T/goal.log" 2>/dev/null)"
# 정지: claude 전체 → claude 좌석 입력 0 · codex 는 그대로 · opencode 는 판정 불가(발사 유지 + ERROR)
: > "$MBOX_DIR/log"; H set --provider claude --until "$(ISO $((NOW0+600)))" --reason 'R2 틱 가드 시험' >/dev/null
: > "$TMUX_LOG"; : > "$T/goal.log"
OUT="$(runtick r2a FT_TICK_STAMP_PREFIX="$T/r2stamp-")"
eq "$(keycount "$TMUX_LOG" '^SENDKEYS %11 ')" 0 "R2 fire 가드: master M#1 입력 0"
eq "$(keycount "$TMUX_LOG" '^SENDKEYS %12 ')" 0 "R2 fire 가드: claude pm 좌석 C#1 입력 0"
eq "$(keycount "$TMUX_LOG" '^SENDKEYS %15 ')" 0 "R2 stall 가드: 15분 멈춘 claude 좌석 S#1 깨움 0"
[ -s "$T/goal.log" ] && bad "R2 goal 가드: goal-tick 이 불렸다" || ok "R2 goal 가드: goal-tick 호출 0"
[ "$(keycount "$TMUX_LOG" '^SENDKEYS %13 ')" -ge 1 ] && ok "R2 codex 좌석 X#1 발사 그대로" || bad "R2 codex 좌석 발사 0"
[ "$(keycount "$TMUX_LOG" '^SENDKEYS %14 ')" -ge 1 ] && ok "R4 opencode 좌석 O#1 은 판정 불가 → 발사 유지" || bad "R4 opencode 발사 0"
has "$(cat "$OUT")" "skip M#1/master — acct-pause claude/" "R2 fire 로그 1줄"
has "$(cat "$OUT")" "skip S#1/stall — acct-pause claude/" "R2 stall 로그 1줄"
eq "$(keycount "$OUT" 'skip M#1/(master|stall|goal-tick) — acct-pause claude/')" 1 "R2 M#1 은 회차당 1줄(지점이 겹쳐도 표식 1개)"
has "$(cat "$OUT")" "ERROR acct_paused O#1" "R4 판정 불가 → ERROR 1줄"
has "$(cat "$OUT")" "round=" "R2 로그에 round_id"
eq "$(keycount "$OUT" 'skip .* — acct-pause ')" 3 "R2 좌석×회차 1줄씩(정지 좌석 3)"
: > "$TMUX_LOG"; OUT2="$(runtick r2b FT_TICK_STAMP_PREFIX="$T/r2stamp-")"
eq "$(keycount "$OUT2" 'skip .* — acct-pause ')" 0 "R2 같은 회차 2바퀴째 = skip 로그 0(회차당 1줄)"
# clear → set 새 회차 = 다시 1줄
H clear >/dev/null; H set --provider claude --until "$(ISO $((NOW0+900)))" --reason 'R2 새 회차 표식 시험' >/dev/null
OUT3="$(runtick r2c)"
has "$(cat "$OUT3")" "skip M#1/master — acct-pause claude/" "R2 clear→set 새 회차 → 다시 1줄(옛 표식 재사용 0)"
eq "$(keycount "$OUT3" 'skip .* — acct-pause ')" 3 "R2 새 회차도 좌석×회차 1줄씩(3)"
not "$(cat "$OUT3")" "round=claude-$NOW0-$(cat "$T/r2a/out" | sed -n 's/.*round=claude-[0-9]*-//p' | head -1)" "R2 새 회차 round_id 는 새 값"
# R11 DRY: 표식·쪽지·기록 0 · DRY 1줄 · FT_TICK_ACCT_PAUSE=0 → 함수 0
rm -rf "$T/dry"; : > "$TMUX_LOG"; : > "$MBOX_DIR/log"
TD=0; ( cd "$T/repo" && env "${BASE[@]}" FT_TICK_STATE_DIR="$T/dry/state" FT_TICK_STAMP_PREFIX="$T/dry/p-" \
      PATH="$FB:$PATH" bash "$LIVE" --once --dry-run > "$T/dry.out" 2>&1 ) || TD=$?
has "$(cat "$T/dry.out")" "DRY kind=acct-pause" "R11 DRY 1줄"
eq "$(ls "$T/dry" 2>/dev/null | grep -c '^p-.*acct\.')" 0 "R11 DRY 는 표식 쓰기 0"
eq "$(grep -c 'SKIPPED-BY-DRY' "$T/dry.out")" 0 "R11 DRY 산출 없음"
OUT4="$(runtick off FT_TICK_ACCT_PAUSE=0)"
not "$(cat "$OUT4")" "acct_pause:" "R11 FT_TICK_ACCT_PAUSE=0 → 함수 0 실행"
{ [ "$(keycount "$TMUX_LOG" '^SENDKEYS %11 ')" -ge 1 ] || [ "$(keycount "$TMUX_LOG" '^SENDKEYS %15 ')" -ge 1 ]; } && ok "R11 끄면 발사 다시 일어난다" || bad "R11 끄기 무시"
H clear >/dev/null

PH "end"
echo "---- fail=$fail"; [ "$fail" -eq 0 ] && echo "ALL PASS"
exit "$fail"
