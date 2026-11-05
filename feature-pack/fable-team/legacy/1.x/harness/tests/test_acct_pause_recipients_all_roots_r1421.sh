#!/usr/bin/env bash
# test_acct_pause_recipients_all_roots_r1421.sh — ft-acct-pause 받는 좌석 풀 = «머신의 현역 루트 전부»(r1421 · Issue #7839).
#   지금 = 자기 루트(.fable-team/seats*.json)만 → kakao·aifp 좌석이 계정 정지·재개를 못 받고 심박이 빈다(11-06 02:07~05:07 실사건).
#   이 시험 = 루트를 넓힌 결과만 본다: A1~A6 + 변이 5 + 기준판(넓히기 전) FAIL. 실 tmux·실 우편함·실 좌석·실 정지 파일 0.
#   bash tests/test_acct_pause_recipients_all_roots_r1421.sh            # 전 칸
#   bash tests/test_acct_pause_recipients_all_roots_r1421.sh --mutate   # 변이 5(사본 한 줄을 어긋나게 하고 «그 칸이 무너지는지»)
[ "${FT_TEST_ACCT_ROOTS_RUNNING:-0}" = 1 ] && { echo "SKIP 재진입(이미 도는 시험)"; exit 0; }
export FT_TEST_ACCT_ROOTS_RUNNING=1
ulimit -u "$(( $(ps -u "$(id -u)" 2>/dev/null | wc -l | tr -d ' ') + 300 ))" 2>/dev/null || true   # r1041: 사용자 프로세스 상한 여유
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
TOOL="${FT_TEST_ACCT_ROOTS_TOOL:-$BIN/ft-acct-pause.sh}"
fail=0; MUT=0; case "${1:-}" in --mutate) MUT=1;; esac
T0="$(date +%s)"
PH() { echo "PHASE ${1} +$(( $(date +%s) - T0 ))s"; }
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "${3:-판정}" || bad "${3:-판정} — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "${3:-판정}";; *) bad "${3:-판정} — 없음: «${2}» ← ${1:0:400}";; esac; }
not() { case "$1" in *"$2"*) bad "${3:-판정} — 있으면 안 됨: «${2}» ← ${1:0:300}";; *) ok "${3:-판정}";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
NOW0=1793400000
ISO() { python3 -c 'import sys,datetime;print((datetime.datetime.fromtimestamp(int(sys.argv[1])).astimezone()).isoformat())' "$1"; }

# ── 가짜 도구 3종 — 실머신 호출 0 ──────────────────────────────────────────────
FB="$T/fakebin"; mkdir -p "$FB"
cat > "$FB/tmux" <<'EOF'
#!/bin/bash
log() { printf '%s\n' "$*" >> "${TMUX_LOG:-/dev/null}"; }
pane_arg() { local prev=""; for a in "$@"; do [ "$prev" = "-t" ] && { echo "$a"; return; }; prev="$a"; done; }
case "$1" in
  list-panes) printf '%s\n' "${FAKE_PANES:-}" | awk 'NF>=2{print $1, $2}'; exit 0;;
  capture-pane) pane="$(pane_arg "$@")"
    busy="$(printf '%s\n' "${FAKE_PANES:-}" | awk -v p="$pane" '$2==p{print $3; exit}')"
    log "CAPTURE $pane busy=${busy:-0}"
    if [ "$busy" = 1 ]; then printf '✻ Working…\n  esc to interrupt\n'; else printf '❯ \n'; fi; exit 0;;
  display-message) echo 4242; exit 0;;
esac
exit 0
EOF
cat > "$FB/mbox.sh" <<'EOF'
#!/bin/bash
case "$1" in
  send) printf 'SEND\t%s\t%s\n' "$2" "$*" >> "${MBOX_DIR:-/tmp}/log"; echo "QUEUED seq=1 to=$2 pending=1 doorbell=quiet"; exit 0;;
  ring) printf 'RING\t%s\n' "$2" >> "${MBOX_DIR:-/tmp}/log"; echo "RING $2 doorbell=sent"; exit 0;;
esac
echo "SKIP"; exit 0
EOF
chmod +x "$FB/tmux" "$FB/mbox.sh"
export PATH="$FB:$PATH" TMUX_LOG="$T/tmux.log"; : > "$TMUX_LOG"
export MBOX_DIR="$T/mbox"; mkdir -p "$MBOX_DIR"; : > "$MBOX_DIR/log"
# 생존 pane = a#1 %1 · b#1 %2 · c#1 %3 · dup#1 %4 (루트 3개에 흩어져 있다)
PANES_IDLE='a#1 %1
b#1 %2
c#1 %3
dup#1 %4'
export FAKE_PANES="$PANES_IDLE"

# ── 가짜 루트 4개: A(자기) · B(다른 현역) · C(휴면 행) · D(현역 행인데 .fable-team 없음) ─────────
A="$T/roots/A"; B="$T/roots/B"; C="$T/roots/C"; D="$T/roots/D"
mk_seats() {  # $1 = 루트 · $2 = seats.json 본문
  mkdir -p "$1/.fable-team/state"; printf '%s\n' "$2" > "$1/.fable-team/seats.json"
}
mk_seats "$A" '{"a#1":{"role":"nano","agent":"claude","model":"claude-sonnet-5-5[1m]","tick":null},
 "dup#1":{"role":"nano","agent":"claude","model":"claude-sonnet-5-5[1m]","tick":null}}'
mk_seats "$B" '{"b#1":{"role":"nano","agent":"claude","model":"claude-sonnet-5-5[1m]","tick":null},
 "dup#1":{"role":"nano","agent":"codex","model":"gpt-6-luna","tick":null}}'
mk_seats "$C" '{"c#1":{"role":"nano","agent":"claude","model":"claude-sonnet-5-5[1m]","tick":null}}'
mkdir -p "$D"                     # .fable-team 없음 → 그 루트만 WARN

TSV() { printf '%s\n' "$@" > "$T/roots.tsv"; printf '%s' "$T/roots.tsv"; }
ROW() { printf '%s\t%s\t%s\torigin/main\t.\t기본\n' "$1" "$2" "$3"; }   # 이름 · 경로 · 상태 · 6칸(줄끝 개행 포함)
TSV_AB="$T/roots-ab.tsv";        { ROW a "$A" 현역; ROW b "$B" 현역; } > "$TSV_AB"
TSV_SELF="$T/roots-self.tsv";    { ROW a "$A" 현역; ROW b "$B" 현역; ROW a2 "$A" 현역; } > "$TSV_SELF"   # 자기 ROOT 행 2개 = 한 번만
TSV_HIB="$T/roots-hib.tsv";      { ROW a "$A" 현역; ROW b "$B" 휴면; ROW c "$C" 현역; ROW d "$D" 현역; } > "$TSV_HIB"
TSV_BROKEN="$T/roots-broken.tsv"; printf '%s\n' "a	$A	현역" > "$TSV_BROKEN"                                     # 3칸 = 깨짐
TSV_NONE="$T/roots-none.tsv"                                                                                 # 파일 없음

H() {  # 도구 한 번 — FT_ROOTS_TSV 는 늘 명시(실 ~/.claude 명부를 읽지 않는다)
  env FT_ACCT_ROOT="$A" FT_ACCT_TMUX="$FB/tmux" FT_ACCT_MBOX="$FB/mbox.sh" FT_ACCT_NOW="${NOWS:-$NOW0}" \
      FT_ROOTS_TSV="${TSV:-$TSV_NONE}" FT_ACCT_BATCH_SEC=7 FT_ACCT_BATCH_SEATS=20 \
      bash "${TOOLX:-$TOOL}" "$@" 2>&1
}
LOG() { cat "$MBOX_DIR/log"; }
CNT() { grep -c "$1" "$MBOX_DIR/log" 2>/dev/null || true; }
RESET() { rm -rf "$A/.fable-team/state"; mkdir -p "$A/.fable-team/state"; : > "$MBOX_DIR/log"; : > "$TMUX_LOG"; }
RECIPS() { python3 - "$A/.fable-team/state" <<'PYX'
import json, sys
st = sys.argv[1]
try:
    ent = json.load(open(st + "/ACCT_PAUSE"))
except (FileNotFoundError, ValueError):
    ent = {}
e = next(iter(ent.values()), None)
if not e:
    print(""); sys.exit(0)
try:
    r = json.load(open(f"{st}/acct-pause/{e['round_id']}.json"))
except (FileNotFoundError, ValueError):
    print(""); sys.exit(0)
print(",".join(sorted(x.get("seat") or "" for x in r.get("recipients") or [])))
PYX
}

PH "spec"
bash -n "$TOOL" && ok "bash -n ft-acct-pause.sh" || bad "bash -n ft-acct-pause.sh"
if [ -z "${FT_TEST_ACCT_ROOTS_TOOL:-}" ]; then
  cmp -s "$BIN/ft-acct-pause.sh" "$KIT/ft-acct-pause.sh" && ok "bin·kit cmp0 ft-acct-pause.sh" || bad "bin·kit 어긋남 ft-acct-pause.sh"
  [ ! -x "$HERE/test_acct_pause_recipients_all_roots_r1421.sh" ] && ok "신설 시험 0o644(실행 비트 0)" || bad "신설 시험에 실행 비트가 붙었다"
  [ -f "$TOOL" ] && [ ! -L "$TOOL" ] && ok "일반 파일(심링크 0)" || bad "일반 파일 아님"
else
  ok "변이 사본 모드 — bin·kit cmp0 검사 생략"
fi

a1() {   # A1 — 자기 루트 A · B 현역 → B 좌석도 받는다
  RESET; TSV="$TSV_AB" NOWS="$NOW0"
  local out; out="$(H set --provider claude --until "$(ISO $((NOW0 + 600)))" --reason 'r1421 시험 · claude 풀')"; local rc=$?
  eq "$rc" 0 "A1 set rc0"
  eq "$(RECIPS)" "a#1,b#1,dup#1" "A1 받는 좌석 = 자기 루트 + B 루트"
  eq "$(CNT 'SEND	b#1')" 1 "A1 B 루트 좌석에 «[정지 예고]» 1통"
  has "$out" "recipients=3" "A1 SET 요약 좌석 3"
  not "$out" "roots=ERR" "A1 깨짐 아님 = roots=ERR 칸 0"
  not "$(LOG)" "WARN" "A1 WARN 0"
}
a2() {   # A2 — 그 set 의 releasing → B 좌석에도 «[재개]» · B 좌석이 끝나야 항목 삭제
  RESET; TSV="$TSV_AB"; NOWS="$NOW0"
  H set --provider claude --until "$(ISO $((NOW0 + 1200)))" --release-at "$(ISO $((NOW0 + 300)))" \
    --reason 'r1421 시험 · 재개에 B 좌석' >/dev/null 2>&1
  eq "$(RECIPS)" "a#1,b#1,dup#1" "A2 set 이 B 좌석을 회차에 넣었다"
  : > "$MBOX_DIR/log"; : > "$TMUX_LOG"
  NOWS="$((NOW0 + 400))"
  export FAKE_PANES="a#1 %1
b#1 %2 1
c#1 %3
dup#1 %4"                         # b#1 만 바쁘다 — 재개가 B 좌석을 건너뛰지 않는지 본다
  local out; out="$(H status)"; local rc=$?
  eq "$rc" 3 "A2 B 좌석이 바쁘면 rc3(항목 유지)"
  has "$out" "RELEASING claude/" "A2 RELEASING — 항목 못 지운다"
  [ -f "$A/.fable-team/state/ACCT_PAUSE" ] && ok "A2 항목 아직 있음(B 좌석 안 끝남)" || bad "A2 항목이 먼저 삭제됐다"
  export FAKE_PANES="$PANES_IDLE"
  out="$(H status)"; rc=$?
  eq "$rc" 0 "A2 A·B 다 끝나면 rc0"
  has "$out" "RELEASED claude/" "A2 RELEASED"
  eq "$(CNT 'SEND	b#1')" 1 "A2 B 루트 좌석에 «[재개]» 1통"
  case "$(LOG)" in *"[재개]"*) ok "A2 본문 = [재개]";; *) bad "A2 본문이 [재개] 아님";; esac
  [ ! -f "$A/.fable-team/state/ACCT_PAUSE" ] && ok "A2 전 좌석 끝난 뒤 항목 삭제" || bad "A2 항목이 남았다"
}
a3() {   # A3 — roots.tsv 없음 = 지금 동작 그대로(자기 루트만)
  RESET; TSV="$TSV_NONE" NOWS="$NOW0"
  local out; out="$(H set --provider claude --until "$(ISO $((NOW0 + 600)))" --reason 'r1421 시험 · 명부 없음')"; local rc=$?
  eq "$rc" 0 "A3 set rc0"
  eq "$(RECIPS)" "a#1,dup#1" "A3 자기 루트 좌석만"
  eq "$(CNT 'SEND	b#1')" 0 "A3 B 좌석 0통"
  not "$out" "roots=ERR" "A3 roots=ERR 0"
  not "$out" "WARN" "A3 WARN 0(파일 없음은 깨짐이 아니다)"
}
a4() {   # A4 — 명부 깨짐 = 자기 루트는 보내고 WARN 1줄 + roots=ERR 칸
  RESET; TSV="$TSV_BROKEN" NOWS="$NOW0"
  local out; out="$(H set --provider claude --until "$(ISO $((NOW0 + 600)))" --reason 'r1421 시험 · 명부 깨짐')"; local rc=$?
  eq "$rc" 0 "A4 set rc0(자기 루트 좌석은 그대로)"
  eq "$(RECIPS)" "a#1,dup#1" "A4 자기 루트 좌석에 보냄"
  eq "$(CNT 'SEND	b#1')" 0 "A4 B 좌석 0(판정 불가)"
  has "$out" "WARN 다른 루트 판정 불가" "A4 WARN 1줄"
  eq "$(printf '%s\n' "$out" | grep -c 'WARN 다른 루트 판정 불가')" 1 "A4 WARN 은 정확히 1줄"
  has "$(printf '%s\n' "$out" | tail -1)" "roots=ERR" "A4 종료 줄 끝 roots=ERR 칸"
  has "$(printf '%s\n' "$out" | tail -1)" "SET pause claude/" "A4 종료 줄 = SET 요약"
}
a5() {   # A5 — 휴면 행 제외 · 명부 없는 루트 WARN 1줄 · 나머지 정상
  RESET; TSV="$TSV_HIB" NOWS="$NOW0"
  local out; out="$(H set --provider claude --until "$(ISO $((NOW0 + 600)))" --reason 'r1421 시험 · 휴면 행')"; local rc=$?
  eq "$rc" 0 "A5 set rc0"
  eq "$(RECIPS)" "a#1,c#1,dup#1" "A5 현역 루트(A·C) 좌석만 — 휴면 B 제외"
  eq "$(CNT 'SEND	b#1')" 0 "A5 휴면 루트 좌석 0통"
  eq "$(CNT 'SEND	c#1')" 1 "A5 현역 루트 C 좌석 1통"
  has "$out" "WARN 루트 d 명부 없음" "A5 명부 없는 루트 WARN 1줄"
  not "$out" "roots=ERR" "A5 휴면·빠진 루트는 깨짐이 아니다(roots=ERR 0)"
}
a6() {   # A6 — 같은 이름 두 루트 = 1통 · roots.tsv 에 자기 ROOT 행 2개 = 한 번만
  RESET; TSV="$TSV_SELF" NOWS="$NOW0"
  local out; out="$(H set --provider claude --until "$(ISO $((NOW0 + 600)))" --reason 'r1421 시험 · 중복 이름')"; local rc=$?
  eq "$rc" 0 "A6 set rc0"
  eq "$(RECIPS)" "a#1,b#1,dup#1" "A6 같은 이름은 첫 루트(A) 것 하나만"
  eq "$(CNT 'SEND	dup#1')" 1 "A6 dup#1 은 1통(중복 0)"
  eq "$(CNT 'SEND	a#1')" 1 "A6 자기 ROOT 행이 둘이어도 a#1 은 1통"
}

PH "A1"; a1
PH "A2"; a2
PH "A3"; a3
PH "A4"; a4
PH "A5"; a5
PH "A6"; a6

# ── 변이 5 — 사본 한 줄을 어긋나게 하고 «그 칸이 무너지는지» 를 같은 프로세스에서 본다 ─────────
mangle() {   # $1 = 이름 · $2 = 원문 · $3 = 바꾼 문장 → 사본 경로를 TOOLX 로
  local name="$1" from="$2" to="$3"
  local d; d="$(mktemp -d "$T/mut.$name.XXXX")"; mkdir -p "$d/bin"
  cp "$BIN/provider-of-model.tsv" "$d/bin/"; cp "$TOOL" "$d/bin/ft-acct-pause.sh"
  python3 - "$d/bin/ft-acct-pause.sh" "$from" "$to" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    print(f"MANGLED-NOT-UNIQUE {s.count(old)}")
    sys.exit(3)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  [ $? -eq 0 ] && printf '%s' "$d/bin/ft-acct-pause.sh" || printf ''
}
try_mut() {   # $1 = 이름 · $2 = 사본 경로 · $3 = 칸 함수 → «돌려도 fail 이 늘어야» 통과
  local name="$1" copy="$2" fn="$3"
  [ -n "$copy" ] || { bad "변이 $name — 치환 실패(원문 불일치)"; return; }
  local before="$fail" line
  TOOLX="$copy" "$fn" >/dev/null 2>&1
  if [ "$fail" -gt "$before" ]; then ok "변이 $name → 그 칸이 무너진다(fail +$((fail - before)))"; else bad "변이 $name → 그 칸이 그대로 통과(변이를 못 잡는다)"; fi
  fail="$before"
}
if [ "$MUT" = 1 ]; then
  PH "mutate"
  try_mut "M1(루트 넓힘 삭제)" "$(mangle m1 'for where in root_dirs():' 'for where in [ROOT]:')" a1
  try_mut "M2(재개가 자기 루트만 봄)" "$(mangle m2 '        joined = panes(budget)
        if joined is None:                       # ⑧ 조회 자체를 건너뛴다 — 남은 좌석은 다음 호출
            break' '        joined = panes(budget)
        if kind == "resume":
            rec["recipients"] = [x for x in rec.get("recipients") or [] if (x.get("seat") or "").startswith("a")]
        if joined is None:                       # ⑧ 조회 자체를 건너뛴다 — 남은 좌석은 다음 호출
            break')" a2
  try_mut "M3(깨짐을 조용히 건너뜀)" "$(mangle m3 '    if ROOTS["err"]:
        print(f"WARN 다른 루트 판정 불가 {ROOTS[\"err\"]}", file=out)' '    if False:
        print(f"WARN 다른 루트 판정 불가 {ROOTS[\"err\"]}", file=out)')" a4
  try_mut "M4(휴면 행 포함)" "$(mangle m4 '        if state != "현역":
            continue' '        if False:
            continue')" a5
  try_mut "M5(첫 루트 우선 삭제)" "$(mangle m5 '                if not isinstance(k, str) or k.startswith("_") or not isinstance(v, dict) or k in seen:' '                if not isinstance(k, str) or k.startswith("_") or not isinstance(v, dict):')" a6
fi

PH "end"
echo "---- fail=$fail"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED"
exit $(( fail > 0 ))
