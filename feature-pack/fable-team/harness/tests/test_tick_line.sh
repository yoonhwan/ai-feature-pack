#!/usr/bin/env bash
# test_tick_line.sh — N1 r-net-tick-line: ft-tick-line.sh · ft-seats-lint.sh · ft-board ⑤ 절 · ft-measure-net.sh (PLAN-harness-networking D2·D8·D9·§9).
# 전부 mktemp 임시 FT_ROOT + 픽스처(tests/fixtures/tick_line/) — 실 tmux·실 명부·루트 .fable-team 쓰기 0 · gh 호출 0(캐시 파일 픽스처) · press 0.
# 좌석 턴은 실 ft-seat-status.sh `turn --file <픽스처 jsonl> --json` 을 스텁 경유로 부른다(턴 경계 판정식까지 실물).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"; FX="$HERE/../fixtures/tick_line"
MIRROR="$HERE/../../scripts/harness-install/fable-team/bin"
TICK="$BIN/ft-tick-line.sh"; LINT="$BIN/ft-seats-lint.sh"; MEAS="$BIN/ft-measure-net.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || bad "$1 (없음: $3)"; }
lacks() { printf '%s' "$2" | grep -qF -- "$3" && bad "$1 (있으면 안 됨: $3)" || ok "$1"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }
jeq() {  # <라벨> <json> <파이썬 식(d=파싱 결과)> <기대 값(JSON)> — 부분 문자열이 아니라 파싱한 값의 정확한 equality
  local got; got="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(json.dumps(eval(sys.argv[2], {"d": d}), sort_keys=True))' "$2" "$3" 2>&1)"
  eq "$1" "$got" "$4"
}

export FT_BOARD_NOW="2026-10-12T10:00:00" FT_SEATS_JSON="$T/none.json"
export FT_BOARD_SEAT_STATUS="$T/seat.sh" TURN_MAP="$T/map" FX
mkdir -p "$T/map"
mkdir -p "$T/bin"; cp "$BIN/ft-seat-status.sh" "$T/bin/"
cat > "$T/seat.sh" <<EOF
#!/bin/sh
# 지원 호출: \$1=jsonl \$2=좌석 (경로 해석) · \$1=turn --file <경로> --json [--bytes] (실 판정) · \$1=turn \$2=좌석 --json (옛 경로)
# map/<좌석>.rc 가 있으면 그 좌석 호출은 그 rc 로 실패. map/<좌석> = 픽스처 파일명 · JSONL_DIR(기본 \$FX/jsonl) 안에서 찾는다.
D="\${JSONL_DIR:-\$FX/jsonl}"
case "\$1" in
  jsonl) [ -f "\$TURN_MAP/\$2.rc" ] && exit "\$(cat "\$TURN_MAP/\$2.rc")"; echo "\$D/\$(cat "\$TURN_MAP/\$2")"; exit 0 ;;
  turn) if [ "\$2" = --file ]; then exec bash "$T/bin/ft-seat-status.sh" "\$@"; fi
        [ -f "\$TURN_MAP/\$2.rc" ] && exit "\$(cat "\$TURN_MAP/\$2.rc")"
        exec bash "$T/bin/ft-seat-status.sh" turn --file "\$D/\$(cat "\$TURN_MAP/\$2")" --json ;;
esac
exit 2
EOF

# 루트 만들기: mkroot <이름> [명부 파일…] → $T/<이름> (+ alive 파일 $T/<이름>.alive)
mkroot() {
  local n="$1"; shift; local R="$T/$n"; mkdir -p "$R/.fable-team/comm" "$R/.fable-team/state/board/2026-10-12"
  for f in "$@"; do cp "$FX/$f" "$R/.fable-team/${f##*/}"; done; : > "$R/.fable-team/comm/mailbox.jsonl"
  printf '%s' "$R"
}
snap() { cp "$FX/snapshot/$2" "$1/.fable-team/state/board/2026-10-12/$3"; }
turnmap() { printf '%s' "$3" > "$T/map/$2"; rm -f "$T/map/$2.rc"; }   # <무시> <좌석> <픽스처>
ME="byz-tt-master-claude#1"; ARCH="byz-tt-arch-claude#1"; NANO="byz-tt-nano-a-claude#0"
tick() {  # <루트> [now] [좌석] → stdout (좌석→jsonl 경로 캐시는 매 호출 비운다 — 같은 루트에서 좌석 픽스처를 바꿔 가며 보기 때문 · 캐시 적중은 F5 시험 ticki 가 본다)
  local R="$1"; rm -f "$R/tickout/seat-jsonl.json"
  FT_ROOT="$R" FT_BOARD_NOW="${2:-2026-10-12T10:00:00}" FT_TMUX_LS_CMD="cat $R/alive.txt" FT_SEATS_GLOB="$R/.fable-team/seats*.json" \
    FT_TICK_OUT_DIR="$R/tickout" bash "$TICK" "${3:-$ME}" 2>"$T/tick.err"
}
lint() {  # <루트> [옵션…] → stdout (rc 는 $LRC)
  local R="$1"; shift
  FT_ROOT="$R" FT_TMUX_LS_CMD="cat $R/alive.txt" FT_SEATS_GLOB="$R/.fable-team/seats*.json" bash "$LINT" "$@" 2>&1; echo $? > "$T/lrc"
}

for f in "$TICK" "$LINT" "$MEAS" "$BIN/ft-seat-status.sh"; do
  [ -f "$f" ] || { bad "있어야 함: $(basename "$f")"; continue; }
  bash -n "$f" && ok "bash -n $(basename "$f")" || bad "bash -n $f"
  case "$f" in */ft-seat-status.sh) ;; *)  # 신규 sh 만 ≤200줄(ft-seat-status.sh 는 기존 파일)
    [ "$(wc -l < "$f")" -le 200 ] && ok "≤200줄 $(basename "$f")" || bad "200줄 초과 $(basename "$f")";; esac
  cmp -s "$f" "$MIRROR/$(basename "$f")" && ok "미러 cmp 0 $(basename "$f")" || bad "미러 불일치 $(basename "$f")"
done
for f in ft_tick_line.py ft_tick_line_io.py ft_board_env.py ft_board_render.py ft_board_decide.py ft-board.py; do
  [ -f "$BIN/$f" ] && { [ "$(wc -l < "$BIN/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 초과 $f"; }
  [ -f "$BIN/$f" ] || continue
  python3 -m py_compile "$BIN/$f" && ok "py_compile $f" || bad "py_compile $f"
  cmp -s "$BIN/$f" "$MIRROR/$f" && ok "미러 cmp 0 $f" || bad "미러 불일치 $f"
done

# ── ①② D2 회귀 3 + 정상 경로 ───────────────────────────────────────────────
R="$(mkroot t1 seats-tt.json)"; cp "$FX/tmux/alive-tt.txt" "$R/alive.txt"
turnmap x "$ARCH" turn-idle.jsonl; turnmap x "$NANO" turn-idle.jsonl; turnmap x "byz-tt-da-codex#0" turn-idle.jsonl
snap "$R" fresh-0stall.json 095945-aaaa1111.json
out="$(tick "$R")"
has "T1 첫 줄 TICK 좌석" "$out" "TICK $ME @2026-10-12T10:00:00"
has "T1 스냅샷 age=15s" "$out" "age=15s"
has "T1 src=turn-live(2)+snapshot@" "$out" "src=turn-live(2)+snapshot@2026-10-12T09:59:45"
has "T1 할 일 없음" "$out" "할 일 없음"
eq "T1 한 줄" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1
# 회귀 1: 스냅샷(45초 전) 정지 행 0 → 지금 라이브 턴 끝 09:57:15 → 195초 = 3분 → 행 1
out="$(tick "$R" 2026-10-12T10:00:30)"
has "T2 스냅샷 0행인데 라이브 3분 → 정지 3분 행" "$out" "정지 3분"
has "T2 행에 좌석" "$out" "$ARCH"
lacks "T2 할 일 없음 아님" "$out" "할 일 없음"
# 회귀 2: 라이브 turn-end 09:56:30 → NOW 10:00:30 = 240초 = 4분
turnmap x "$ARCH" turn-idle-old.jsonl; turnmap x "$NANO" turn-working.jsonl
out="$(tick "$R" 2026-10-12T10:00:30)"
has "T3 라이브 IDLE 4분 → 행" "$out" "정지 4분"
lacks "T3 WORKING 나노는 행 아님" "$out" "정지 3분"
# 회귀 3: 스냅샷에 8분 정지 행이 있어도 라이브 WORKING 이면 행 0
R3="$(mkroot t3 seats-tt.json)"; cp "$FX/tmux/alive-tt.txt" "$R3/alive.txt"; snap "$R3" old-8min-stall.json 095500-bbbb2222.json
turnmap x "$ARCH" turn-working.jsonl; turnmap x "$NANO" turn-working.jsonl; turnmap x "byz-tt-da-codex#0" turn-working.jsonl
out="$(tick "$R3")"
lacks "T4 스냅샷 옛 8분 행을 따르지 않음" "$out" "8분"
has "T4 라이브 WORKING → 할 일 없음" "$out" "할 일 없음"

# ── UNKNOWN 은 0 이 아니다 ────────────────────────────────────────────────
turnmap x "$ARCH" turn-idle.jsonl; turnmap x "$NANO" turn-idle.jsonl; turnmap x "byz-tt-da-codex#0" turn-idle.jsonl
printf '1' > "$T/map/$NANO.rc"
out="$(tick "$R")"
has "U1 좌석 측정 실패 → UNKNOWN" "$out" "UNKNOWN"
has "U1 UNKNOWN 행에 좌석+이유" "$out" "$NANO"
lacks "U1 할 일 없음 금지" "$out" "할 일 없음"
rm -f "$T/map/$NANO.rc"; turnmap x "$NANO" turn-idle.jsonl
R4="$(mkroot t4 seats-tt.json)"; cp "$FX/tmux/alive-tt.txt" "$R4/alive.txt"
out="$(tick "$R4")"
has "U2 스냅샷 없음 → 첫 줄 UNKNOWN 1건" "$(printf '%s\n' "$out" | head -1)" "UNKNOWN 1건"
has "U2 이유는 행으로" "$out" "UNKNOWN 스냅샷 없음"
lacks "U2 할 일 없음 금지" "$out" "할 일 없음"
out="$(tick "$R" 2026-10-12T10:00:00 "byz-tt-nobody-claude#9")"
has "U3 명부에 없는 좌석 → UNKNOWN(명부" "$out" "UNKNOWN(명부"

# ── F2: 8석 전부 turn 실패 → 첫 줄은 개수만 · 이유는 행 · 전체 ≤5줄·≤500자(문자 수·바이트 둘 다 잼) ──
R8="$(mkroot t8 seats-tt.json)"; python3 - "$R8/.fable-team/seats-tt.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"))
for i in range(6): d[f"byz-tt-nano-s{i}-claude#0"] = {"role": "nano", "agent": "claude"}
json.dump(d, open(p, "w"), ensure_ascii=False)
PY
{ cat "$FX/tmux/alive-tt.txt"; for i in 0 1 2 3 4 5; do echo "byz-tt-nano-s$i-claude#0"; done; } > "$R8/alive.txt"; snap "$R8" fresh-0stall.json 095945-aaaa1111.json
for s in "$ARCH" "$NANO" byz-tt-nano-s0-claude#0 byz-tt-nano-s1-claude#0 byz-tt-nano-s2-claude#0 byz-tt-nano-s3-claude#0 byz-tt-nano-s4-claude#0 byz-tt-nano-s5-claude#0; do printf '1' > "$T/map/$s.rc"; done
out="$(tick "$R8")"
eq "F2 출력 ≤5줄" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 5
[ "$(printf '%s' "$out" | wc -m | tr -d ' ')" -le 500 ] && ok "F2 ≤500자($(printf '%s' "$out" | wc -m | tr -d ' ') 문자 · $(printf '%s' "$out" | wc -c | tr -d ' ') 바이트)" || bad "F2 500자 초과"
has "F2 첫 줄 UNKNOWN 8석" "$(printf '%s\n' "$out" | head -1)" "UNKNOWN 8석"
lacks "F2 첫 줄에 이유 없음" "$(printf '%s\n' "$out" | head -1)" "turn 조회 실패"
lacks "F2 할 일 없음 금지" "$out" "할 일 없음"
fp="$(printf '%s\n' "$out" | tail -1 | sed 's/.*→ //')"
has "F2 마지막 줄 잘림 표시" "$(printf '%s\n' "$out" | tail -1)" "… 전체 8행 →"
[ -f "$fp" ] && eq "F2 경로 줄 실재 · 8행" "$(wc -l < "$fp" | tr -d ' ')" 8 || bad "F2 경로 파일 없음($fp)"
case "$fp" in *"/byz-tt-master-claude#1-"*.txt) ok "F2 파일명 <좌석>-<ts>.txt";; *) bad "F2 파일명 규약($fp)";; esac
for s in "$ARCH" "$NANO" byz-tt-nano-s0-claude#0 byz-tt-nano-s1-claude#0 byz-tt-nano-s2-claude#0 byz-tt-nano-s3-claude#0 byz-tt-nano-s4-claude#0 byz-tt-nano-s5-claude#0; do rm -f "$T/map/$s.rc"; done
# 틱을 25번 돌려도 같은 좌석 전체 행 파일은 20개로 접힌다(무한 증가 0)
for i in $(seq 1 25); do tick "$R8" "2026-10-12T10:00:$(printf '%02d' $i)" >/dev/null; done
eq "F2 전체 행 파일 좌석당 20개 상한" "$(ls "$R8/tickout" | grep -c 'byz-tt-master-claude#1-')" 20

# ── F5: turn 8회 ≠ I/O 8회 — 경로 해석 캐시 · 끝 64KB 읽기(부족하면 2배씩) · stderr 'io:' 줄 ──
RI="$(mkroot t9 seats-tt.json)"; python3 - "$RI/.fable-team/seats-tt.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"))
for i in range(6): d[f"byz-tt-nano-s{i}-claude#0"] = {"role": "nano", "agent": "claude"}
json.dump(d, open(p, "w"), ensure_ascii=False)
PY
{ cat "$FX/tmux/alive-tt.txt"; for i in 0 1 2 3 4 5; do echo "byz-tt-nano-s$i-claude#0"; done; } > "$RI/alive.txt"; snap "$RI" fresh-0stall.json 095945-aaaa1111.json
mkdir -p "$T/jf"; SEATS8="$ARCH $NANO byz-tt-nano-s0-claude#0 byz-tt-nano-s1-claude#0 byz-tt-nano-s2-claude#0 byz-tt-nano-s3-claude#0 byz-tt-nano-s4-claude#0 byz-tt-nano-s5-claude#0"
i=0; for s in $SEATS8; do i=$((i+1)); cp "$FX/jsonl/turn-idle.jsonl" "$T/jf/w$i.jsonl"; turnmap x "$s" "w$i.jsonl"; done
export JSONL_DIR="$T/jf"
ticki() { FT_ROOT="$RI" FT_BOARD_NOW=2026-10-12T10:00:00 FT_TMUX_LS_CMD="cat $RI/alive.txt" FT_SEATS_GLOB="$RI/.fable-team/seats*.json" FT_TICK_OUT_DIR="$RI/.fable-team/state/tick" \
    bash "$TICK" "$ME" 2>"$T/io.err"; }
io_field() { tr ' ' '\n' < "$T/io.err" | sed -n "s/^$1=//p"; }
out="$(ticki)"
has "I1 첫 틱 stderr io 줄" "$(cat "$T/io.err")" "io: files=8"
eq "I1 첫 틱 resolve=8 (경로 신규 해석)" "$(io_field resolve)" 8
[ -f "$RI/.fable-team/state/tick/seat-jsonl.json" ] && ok "I1 경로 캐시 파일 실재" || bad "I1 경로 캐시 파일 없음"
out="$(ticki)"
eq "I2 두 번째 틱 files=8" "$(io_field files)" 8
eq "I2 두 번째 틱 resolve=0 (경로 캐시 적중)" "$(io_field resolve)" 0
[ "$(io_field bytes)" -le $((8 * 65536)) ] && ok "I2 bytes=$(io_field bytes) ≤ 8×64KB · ms=$(io_field ms)" || bad "I2 bytes 초과($(io_field bytes))"
eq "I2 작은 jsonl 은 파일 전체만 읽음(8×파일 크기)" "$(io_field bytes)" "$((8 * $(wc -c < "$FX/jsonl/turn-idle.jsonl" | tr -d ' ')))"
# 캐시 stale: mtime 역행(캐시가 더 최신) → 그 좌석만 재해석 1회
python3 - "$RI/.fable-team/state/tick/seat-jsonl.json" "$ARCH" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d[sys.argv[2]]["mtime"] += 100000; json.dump(d, open(p, "w"))
PY
out="$(ticki)"; eq "I3 mtime 역행 → 재해석 1회" "$(io_field resolve)" 1
out="$(ticki)"; eq "I3 그 다음 틱은 다시 캐시 적중" "$(io_field resolve)" 0
# 파일 삭제 → 그 좌석만 재해석(새 경로) 1회
cp "$FX/jsonl/turn-idle.jsonl" "$T/jf/w-new.jsonl"; rm -f "$T/jf/w2.jsonl"; turnmap x "$NANO" "w-new.jsonl"
out="$(ticki)"; eq "I4 파일 삭제 → 그 좌석만 전수 재해석 1회(나머지 7석은 새 항목만 스캔)" "$(io_field resolve)" 1
eq "I4 재해석 뒤에도 files=8" "$(io_field files)" 8
# F5(fix2): 같은 디렉터리에 더 최신 jsonl 이 생기면(= 디렉터리 mtime 변화) 그 좌석만 재해석 1회 → 새 파일을 읽는다 · 무변화/다른 디렉터리 변화는 재해석 0
FD="$T/fdir"; mkdir -p "$FD" "$T/other"; cp "$FX/jsonl/turn-idle.jsonl" "$FD/old.jsonl"
cat > "$T/seat-dir.sh" <<EOF
#!/bin/sh
# jsonl <좌석>: \$FD 안에서 mtime 최신 jsonl (newest_jsonl_of 와 같은 선택 규칙) · turn: 실 ft-seat-status.sh
if [ "\$1" = jsonl ]; then ls -t "$FD"/*.jsonl | head -1; exit 0; fi
exec bash "$T/bin/ft-seat-status.sh" "\$@"
EOF
RF="$(mkroot t10)"; printf '{"_master": "%s", "%s": {"role": "master"}, "%s": {"role": "arch"}}' "$ME" "$ME" "$ARCH" > "$RF/.fable-team/seats-tt.json"; printf '%s\n' "$ME" "$ARCH" > "$RF/alive.txt"; snap "$RF" fresh-0stall.json 095945-aaaa1111.json
tickf() { FT_BOARD_SEAT_STATUS="$T/seat-dir.sh" FT_ROOT="$RF" FT_BOARD_NOW=2026-10-12T10:00:00 FT_TMUX_LS_CMD="cat $RF/alive.txt" FT_SEATS_GLOB="$RF/.fable-team/seats*.json" \
    FT_TICK_OUT_DIR="$RF/.fable-team/state/tick" bash "$TICK" "$ME" 2>"$T/io.err"; }
touch -t 202601010000 "$FD/old.jsonl"; sleep 1; out="$(tickf)"
has "D1 첫 틱: old(IDLE) 를 읽음 → 할 일 없음" "$out" "할 일 없음"
eq "D1 첫 틱 resolve=1" "$(io_field resolve)" 1
out="$(tickf)"; eq "D2 디렉터리 무변화 → resolve=0" "$(io_field resolve)" 0
touch "$T/other/x.jsonl"; out="$(tickf)"; eq "D3 다른 디렉터리 변화 → 재해석 0" "$(io_field resolve)" 0
sleep 1; { printf '{"type":"agent-name","agentName":"%s"}\n' "$ARCH"; cat "$FX/jsonl/turn-working.jsonl"; } > "$FD/new.jsonl"; sleep 1   # fix2b: 새 파일은 좌석명 레코드로 매칭된다
out="$(tickf)"
eq "D4 같은 디렉터리에 새 최신 jsonl → 전수 재해석 0 · 새 파일만 읽음(new=1)" "$(io_field resolve)$(io_field new)" 01
has "D4 새 파일(WORKING)을 읽는다 → 정지 행 없음" "$out" "0/0/0"
python3 - "$RF/.fable-team/state/tick/seat-jsonl.json" "$ARCH" "$FD" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); e = d[sys.argv[2]]
assert e["path"].endswith("new.jsonl"), e
assert e["dir"] == sys.argv[3] and isinstance(e["dir_mtime"], (int, float)), e
PY
[ $? -eq 0 ] && ok "D4 캐시에 new.jsonl · dir · dir_mtime 저장" || bad "D4 캐시 항목 형식"
out="$(tickf)"; eq "D5 이후 무변화 틱 → resolve=0" "$(io_field resolve)" 0
[ "$(io_field bytes)" -le 65536 ] && ok "D5 bytes=$(io_field bytes) ≤ 1석×64KB" || bad "D5 bytes 초과"
# 같은 디렉터리의 파일 삭제도 디렉터리 변화 → 재해석 1회(old 만 남으면 old)
rm -f "$FD/new.jsonl"; sleep 1; out="$(tickf)"; eq "D6 캐시 경로 파일 삭제 → 전수 재해석 1(old 로 복귀)" "$(io_field resolve)" 1

# ── F5(fix2b): 디렉터리 mtime 변화 = «전수 재해석» 이 아니라 «새로 생긴 파일만 앞 1MB» (그 폴더는 그 워크트리의 모든 세션 jsonl — 397MB~1.65GB) ──
RD="$T/rdir"; mkdir -p "$RD"
seatfile() {  # <경로> <좌석> <본문 픽스처> [패딩 바이트] — 첫 줄 = 좌석명 레코드(newest_jsonl_of 와 같은 needle) · 뒤에 판정용 본문
  { printf '{"type":"agent-name","agentName":"%s"}\n' "$2"; [ -n "${4:-}" ] && { head -c "$4" /dev/zero | tr '\0' x; printf '\n'; }; cat "$FX/jsonl/$3"; } > "$1"; }
for i in $(seq 1 200); do seatfile "$RD/other-$i.jsonl" "byz-tt-other-$i-claude#0" turn-idle.jsonl 65536; done
seatfile "$RD/me-old.jsonl" "$ME" turn-idle.jsonl; seatfile "$RD/arch-old.jsonl" "$ARCH" turn-idle.jsonl
cat > "$T/seat-r.sh" <<EOF
#!/bin/sh
# jsonl <좌석>: 전수 해석 스텁(= 전수 재해석이 불리면 resolve 가 오른다) — 좌석명 레코드가 있는 jsonl 중 mtime 최신 · turn: 실 ft-seat-status.sh
if [ "\$1" = jsonl ]; then for f in \$(ls -t "$RD"/*.jsonl); do grep -qF "\"agentName\":\"\$2\"" "\$f" && { echo "\$f"; exit 0; }; done; exit 1; fi
exec bash "$T/bin/ft-seat-status.sh" "\$@"
EOF
RR="$(mkroot t11)"; printf '{"_master": "%s", "%s": {"role": "master"}, "%s": {"role": "arch"}}' "$ME" "$ME" "$ARCH" > "$RR/.fable-team/seats-tt.json"; printf '%s\n' "$ME" "$ARCH" > "$RR/alive.txt"; snap "$RR" fresh-0stall.json 095945-aaaa1111.json
tickr() { FT_BOARD_SEAT_STATUS="$T/seat-r.sh" FT_ROOT="$RR" FT_BOARD_NOW=2026-10-12T10:00:00 FT_TMUX_LS_CMD="cat $RR/alive.txt" FT_SEATS_GLOB="$RR/.fable-team/seats*.json" \
    FT_TICK_OUT_DIR="$RR/.fable-team/state/tick" bash "$TICK" "$ME" 2>"$T/io.err"; }
touch -t 202601010000 "$RD"/me-old.jsonl "$RD"/arch-old.jsonl; sleep 1
out="$(tickr)"; eq "F5b-R4 캐시 없음(첫 틱) → 전수 재해석(기존 경로) 1석(틱이 읽는 좌석 = arch)" "$(io_field resolve)" 1
out="$(tickr)"; eq "F5b-R3 디렉터리 무변화 → scan=0" "$(io_field scan)" 0
eq "F5b-R3 디렉터리 무변화 → new=0" "$(io_field new)" 0
eq "F5b-R3 디렉터리 무변화 → resolve=0" "$(io_field resolve)" 0
[ "$(io_field bytes)" -le $((2 * 65536)) ] && ok "F5b-R3 bytes=$(io_field bytes) ≤ 2×64KB" || bad "F5b-R3 bytes 초과($(io_field bytes))"
sleep 1; seatfile "$RD/other-new.jsonl" "byz-tt-other-new-claude#0" turn-idle.jsonl 65536; sleep 1
out="$(tickr)"
eq "F5b-R1 다른 좌석 새 파일 1개 → 전수 재해석 0 (200개를 다시 훑지 않는다)" "$(io_field resolve)" 0
eq "F5b-R1 새 파일만 앞을 읽음 new=1" "$(io_field new)" 1
[ "$(io_field bytes)" -le $((65536 + 1048576)) ] && ok "F5b-R1 bytes=$(io_field bytes) ≤ 64KB+1MB" || bad "F5b-R1 bytes 초과($(io_field bytes))"
has "F5b-R1 대상 좌석(arch)은 old(IDLE) 유지 → 할 일 없음" "$out" "할 일 없음"
out="$(tickr)"; eq "F5b-R1 다음 틱(무변화) → new=0 (새 파일은 한 번만 본다)" "$(io_field new)" 0
sleep 1; seatfile "$RD/arch-new.jsonl" "$ARCH" turn-working.jsonl; sleep 1
out="$(tickr)"
eq "F5b-R2 새 파일로 교체 new=1" "$(io_field new)" 1
eq "F5b-R2 전수 재해석 0" "$(io_field resolve)" 0
python3 - "$RR/.fable-team/state/tick/seat-jsonl.json" "$ARCH" <<'PY'
import json, sys
e = json.load(open(sys.argv[1]))[sys.argv[2]]; assert e["path"].endswith("arch-new.jsonl"), e
PY
[ $? -eq 0 ] && ok "F5b-R2 캐시 경로 = arch-new.jsonl" || bad "F5b-R2 캐시 경로"
# R5: 새 파일 매칭 규칙 == newest_jsonl_of (agentName·customTitle 각 1 · 다른 좌석 1) — 실 ft-seat-status.sh jsonl 과 같은 파일을 고른다
HD="$T/home/.claude/projects/-tmp-r5"; mkdir -p "$HD" "$T/fakebin"
printf '{"agentName":"%s"}\n' "$ME" > "$HD/a.jsonl"; sleep 1; printf '{"customTitle":"%s"}\n' "$ME" > "$HD/b.jsonl"; printf '{"agentName":"other-seat"}\n' > "$HD/c.jsonl"
printf '#!/bin/sh\n[ "$1" = display-message ] && { echo /tmp/r5; exit 0; }\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
real="$(HOME="$T/home" PATH="$T/fakebin:$PATH" bash "$BIN/ft-seat-status.sh" jsonl "$ME")"
mine="$(cd "$BIN" && python3 -c 'import sys; import ft_tick_line_io as t; print(t.fresh_match(sys.argv[1], sys.argv[2], 0.0) or "")' "$HD" "$ME")"
eq "F5b-R5 needle 정합: 새 경로 == newest_jsonl_of" "$mine" "$real"
eq "F5b-R5 customTitle 파일(b)을 고름(mtime 최신)" "$(basename "$real")" "b.jsonl"

# jsonl 없는 좌석(rc 1) → 부정 캐시: 다음 틱은 jsonl 해석(전수 순회)을 다시 부르지 않는다
printf '1' > "$T/map/$NANO.rc"; rm -f "$RI/.fable-team/state/tick/seat-jsonl.json"
out="$(ticki)"; eq "I4b 해석 실패 좌석 포함 첫 틱 resolve=8" "$(io_field resolve)" 8
out="$(ticki)"; eq "I4b 부정 캐시 → 둘째 틱 resolve=0" "$(io_field resolve)" 0
rm -f "$T/map/$NANO.rc"
unset JSONL_DIR
# ft-seat-status.sh: read_bytes — 작은 파일은 전체 · 큰 턴은 64KB → 128KB → … 2배씩(읽은 바이트 합)
SS="$BIN/ft-seat-status.sh"
sz="$(wc -c < "$FX/jsonl/turn-idle.jsonl" | tr -d ' ')"
jv="$(bash "$SS" turn --file "$FX/jsonl/turn-idle.jsonl" --json)"
jeq "I5 작은 파일 read_bytes == 파일 크기" "$jv" "d['read_bytes']" "$sz"
python3 - "$T/big.jsonl" <<'PY'
import json, sys
recs = [{"type": "user", "timestamp": "2026-10-12T09:40:00.000"}, {"type": "system", "subtype": "turn_duration", "timestamp": "2026-10-12T09:41:00.000", "durationMs": 1},
        {"type": "user", "timestamp": "2026-10-12T09:42:00.000"}, {"type": "assistant", "timestamp": "2026-10-12T09:43:00.000", "message": {"content": [{"type": "text", "text": "x" * 150000}]}},
        {"type": "system", "subtype": "turn_duration", "timestamp": "2026-10-12T09:57:15.000", "durationMs": 1}]
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in recs))
PY
bsz="$(wc -c < "$T/big.jsonl" | tr -d ' ')"
jv="$(bash "$SS" turn --file "$T/big.jsonl" --json)"
jeq "I5 큰 턴 state == IDLE (끝 레코드 2개를 찾을 때까지 넓힘)" "$jv" "d['state']" '"IDLE"'
jeq "I5 큰 턴 read_bytes == 파일 크기(넓힐 때 앞서 읽은 꼬리를 다시 읽지 않는다 — 합이 아니라 최종 창)" "$jv" "d['read_bytes']" "$bsz"
jeq "I5 큰 턴 turn_end 는 마지막 레코드" "$jv" "d['turn_end']" '"2026-10-12T09:57:15.000"'
jv="$(bash "$SS" turn --file "$T/big.jsonl" --json --no-reported)"
jeq "I5b --no-reported: 끝 레코드 1개면 멈춤 → read_bytes == 64KB(실 좌석 jsonl 의 긴 턴 2배 확장 방지)" "$jv" "d['read_bytes']" 65536
jeq "I5b --no-reported: state 는 그대로 IDLE" "$jv" "d['state']" '"IDLE"'
jeq "I5b --no-reported: reported 는 null" "$jv" "d['reported']" null
# 열린 턴(끝 레코드 없음 · 창 안에 user/assistant) — 상태 전용 모드는 64KB 에서 WORKING 으로 닫는다(턴 끝 시각 불요)
python3 - "$T/open.jsonl" <<'PY'
import json, sys
recs = [{"type": "user", "timestamp": "2026-10-12T09:40:00.000"}, {"type": "assistant", "timestamp": "2026-10-12T09:43:00.000", "message": {"content": [{"type": "text", "text": "x" * 400000}]}},
        {"type": "assistant", "timestamp": "2026-10-12T09:59:00.000", "message": {"content": []}}]
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in recs))
PY
jv="$(bash "$SS" turn --file "$T/open.jsonl" --json --no-reported)"
jeq "I5c 열린 턴 상태 전용 → WORKING" "$jv" "d['state']" '"WORKING"'
jeq "I5c 열린 턴 read_bytes == 64KB (1MB 확장 0)" "$jv" "d['read_bytes']" 65536
jv="$(bash "$SS" turn --file "$T/open.jsonl" --json)"
jeq "I5c 기본 모드도 끝 레코드를 끝까지 찾은 뒤 창 안 user/assistant 로 WORKING (R144 — 옛 UNKNOWN 교정)" "$jv" "d['state']" '"WORKING"'
jeq "I5c 기본 모드 WORKING 의 reported 는 null" "$jv" "d['reported']" null
eq "I5 텍스트 기본은 5열(ft-tick.sh read 보호)" "$(bash "$SS" turn --file "$FX/jsonl/turn-idle.jsonl" | awk '{print NF}')" 5
eq "I5 --bytes 는 6열째에 바이트" "$(bash "$SS" turn --file "$FX/jsonl/turn-idle.jsonl" --bytes | awk '{print $6}')" "$sz"
bash "$SS" jsonl no-such-seat-xyz >/dev/null 2>&1; eq "I6 jsonl 서브커맨드: 없는 좌석 rc 1" "$?" 1

# ── 큐 머리별 건수 + 주의 seq ─────────────────────────────────────────────
R5="$(mkroot t5 seats-tt.json)"; cp "$FX/tmux/alive-tt.txt" "$R5/alive.txt"; snap "$R5" fresh-0stall.json 095945-aaaa1111.json
python3 - "$R5/.fable-team/comm/mailbox.jsonl" "$ME" <<'PY'
import json, sys
p, me = sys.argv[1], sys.argv[2]
rows = [(11, "[HIL] 막힘"), (12, "[결정] 합치기 여부"), (13, "머리 없음"), (14, "[HIL·merge] 별칭"), (15, "[완료·휴식] 끝")]
with open(p, "w", encoding="utf-8") as f:
    for s, b in rows: f.write(json.dumps({"seq": s, "ts": "2026-10-12T09:50:00", "to": me, "from": "x#1", "body": f"[x#1->{me}] {b}"}, ensure_ascii=False) + "\n")
    f.write(json.dumps({"seq": 16, "ts": "2026-10-12T09:50:00", "to": "다른#1", "from": "x#1", "body": "[x#1->다른#1] [HIL] 남의 것"}, ensure_ascii=False) + "\n")
PY
out="$(tick "$R5")"
has "Q1 큐 5건" "$out" "큐 5"
has "Q1 주의 seq 11" "$out" "#11"
has "Q1 주의 seq 12" "$out" "#12"
has "Q1 주의 seq 15" "$out" "#15"
lacks "Q1 남의 쪽지 제외" "$out" "#16"
lacks "Q1 머리 없음은 주의 아님" "$out" "#13"
lacks "Q1 할 일 없음 아님" "$out" "할 일 없음"

# ── 5줄·500자 상한 + 잘림 줄 ──────────────────────────────────────────────
R6="$(mkroot t6 seats-tt.json)"; python3 - "$R6/.fable-team/seats-tt.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"))
for i in range(6): d[f"byz-tt-nano-s{i}-claude#0"] = {"role": "nano", "agent": "claude"}
json.dump(d, open(p, "w"), ensure_ascii=False)
PY
{ cat "$FX/tmux/alive-tt.txt"; for i in 0 1 2 3 4 5; do echo "byz-tt-nano-s$i-claude#0"; done; } > "$R6/alive.txt"; snap "$R6" fresh-0stall.json 095945-aaaa1111.json
for i in 0 1 2 3 4 5; do turnmap x "byz-tt-nano-s$i-claude#0" turn-idle-old.jsonl; done
turnmap x "$ARCH" turn-idle-old.jsonl; turnmap x "$NANO" turn-idle-old.jsonl; turnmap x "byz-tt-da-codex#0" turn-working.jsonl
out="$(tick "$R6" 2026-10-12T10:00:30)"
eq "C1 출력 ≤5줄" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 5
[ "$(printf '%s' "$out" | wc -m | tr -d ' ')" -le 500 ] && ok "C1 ≤500자" || bad "C1 500자 초과"
has "C1 마지막 줄 잘림 표시" "$(printf '%s\n' "$out" | tail -1)" "… 전체 8행 →"
fullpath="$(printf '%s\n' "$out" | tail -1 | sed 's/.*→ //')"
[ -f "$fullpath" ] && eq "C1 전체 행 파일 8행" "$(wc -l < "$fullpath" | tr -d ' ')" 8 || bad "C1 전체 행 파일 없음($fullpath)"
has "C1 첫 줄 정지 8" "$(printf '%s\n' "$out" | head -1)" "정지 8"

# ── 불일치 수가 틱 줄에 실린다 ────────────────────────────────────────────
R7="$(mkroot t7 seats-tt.json)"; { cat "$FX/tmux/alive-tt.txt"; echo "byz-tt-ghost-claude#0"; } > "$R7/alive.txt"; snap "$R7" fresh-0stall.json 095945-aaaa1111.json
out="$(tick "$R7")"
has "L0 틱 줄에 불일치 1" "$out" "불일치 1"
lacks "L0 할 일 없음 아님" "$out" "할 일 없음"

# ── ft-seats-lint.sh ⓐ~ⓕ ──────────────────────────────────────────────────
RC="$(mkroot lc seats-tt.json seats-cl.json)"; cp "$FX/tmux/alive-tt-cl.txt" "$RC/alive.txt"
out="$(lint "$RC")"; eq "S0 정상 + 닫힌 팀 보존 좌석 → 불일치 0" "$(printf '%s' "$out" | head -1)" "불일치 0 (UNKNOWN 0)"; eq "S0 rc 0" "$(cat "$T/lrc")" 0
out="$(lint "$RC" --team "$RC/.fable-team/seats-tt.json")"; eq "S0b --team 정상" "$(printf '%s' "$out" | head -1)" "불일치 0 (UNKNOWN 0)"
RA="$(mkroot la seats-tt.json seats-cl.json)"; { cat "$FX/tmux/alive-tt-cl.txt"; echo "byz-tt-ghost-claude#0"; echo "byz-cl-nano-x-claude#0"; } > "$RA/alive.txt"
out="$(lint "$RA")"
has "S1 ⓐ 행 없는 세션" "$out" "ⓐ byz-tt-ghost-claude#0"
has "S1 ⓐ 닫힌 팀 보존 표시 없는 세션" "$out" "ⓐ byz-cl-nano-x-claude#0"
eq "S1 불일치 2" "$(printf '%s' "$out" | head -1)" "불일치 2 (UNKNOWN 0)"; eq "S1 rc 1" "$(cat "$T/lrc")" 1
out="$(lint "$RA" --team "$RA/.fable-team/seats-tt.json")"
eq "S1b --team tt 는 ghost 만" "$(printf '%s' "$out" | head -1)" "불일치 1 (UNKNOWN 0)"
RB="$(mkroot lb seats-tt.json)"; cp "$FX/tmux/alive-tt.txt" "$RB/alive.txt"
python3 - "$RB/.fable-team/seats-tt.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["_master"] = "byz-tt-master-claude#0"; json.dump(d, open(p, "w"))
PY
out="$(lint "$RB")"; has "S2 ⓑ _master 가 은퇴(_replaced_by)" "$out" "ⓑ _master byz-tt-master-claude#0"
python3 - "$RB/.fable-team/seats-tt.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["_master"] = "byz-tt-master-claude#7"; d["_hil_route"] = "byz-tt-master-claude#1"; json.dump(d, open(p, "w"))
PY
out="$(lint "$RB")"; has "S2b ⓑ _master 세션 죽음" "$out" "ⓑ _master byz-tt-master-claude#7"
python3 - "$RB/.fable-team/seats-tt.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["_master"] = ""; d.pop("_opened", None); json.dump(d, open(p, "w"))
PY
touch -t 202610120955 "$RB/.fable-team/seats-tt.json"
out="$(FT_BOARD_NOW=2026-10-12T10:00:00 lint "$RB")"; has "S2c 개설 중 빈 _master → OPENING" "$out" "OPENING"; eq "S2c 불일치 아님" "$(printf '%s' "$out" | head -1)" "불일치 0 (UNKNOWN 0)"
touch -t 202610120900 "$RB/.fable-team/seats-tt.json"
out="$(FT_BOARD_NOW=2026-10-12T10:00:00 lint "$RB")"; has "S2d _opened 없이 30분 넘음 → 불일치" "$out" "ⓑ _master 비어 있음"
RCC="$(mkroot lcc seats-tt.json)"; grep -v 'byz-tt-nano-a-claude#0' "$FX/tmux/alive-tt.txt" > "$RCC/alive.txt"
out="$(lint "$RCC")"; has "S3 ⓒ 활성 행인데 세션 없음" "$out" "ⓒ byz-tt-nano-a-claude#0"
RD="$(mkroot ld seats-tt.json)"; { cat "$FX/tmux/alive-tt.txt"; echo "byz-tt-arch-claude#2"; echo "byz-tt-arch-claude#3"; } > "$RD/alive.txt"
python3 - "$RD/.fable-team/seats-tt.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for n in (2, 3): d[f"byz-tt-arch-claude#{n}"] = {"role": "stop-ready", "_replaced_by": "byz-tt-arch-claude#%d" % (n + 1)}
json.dump(d, open(p, "w"))
PY
out="$(lint "$RD")"; has "S4 ⓓ 계보당 세션 3 > 2" "$out" "ⓓ byz-tt-arch-claude 3"
RE="$(mkroot le seats-tt.json seats-dup.json)"; cp "$FX/tmux/alive-tt.txt" "$RE/alive.txt"
out="$(lint "$RE")"; has "S5 ⓔ 같은 키가 명부 2개" "$out" "ⓔ byz-tt-nano-a-claude#0"
printf '{"byz-tt-x-claude#1": {"role": "nano"}, "byz-tt-x-claude#1": {"role": "nano"}}' > "$RE/.fable-team/seats-dup.json"
out="$(lint "$RE")"; has "S5b ⓔ 한 파일 안 중복 키" "$out" "ⓔ byz-tt-x-claude#1"
RF="$(mkroot lf seats-tt.json seats-broken.json)"; cp "$FX/tmux/alive-tt.txt" "$RF/alive.txt"
out="$(lint "$RF")"; has "S6 ⓕ 파싱 실패 UNKNOWN 파일" "$out" "UNKNOWN seats-broken.json"
eq "S6 불일치 0 이지만 UNKNOWN 1" "$(printf '%s' "$out" | head -1)" "불일치 0 (UNKNOWN 1)"; eq "S6 rc 1" "$(cat "$T/lrc")" 1

# ── ft-board render ⑤ 절 ───────────────────────────────────────────────────
render() {  # <루트> → term 출력
  FT_ROOT="$1" FT_BOARD_NOW=2026-10-12T10:00:00 FT_BOARD_TMUX="cat $1/alive.txt" FT_BOARD_GH="cat $1/gh.json" FT_BOARD_GH_TTL="${GHTTL:-600}" \
    FT_VERDICT_BIN="$T/verdict.sh" FT_BOARD_INBOX="bash $T/inbox.sh" FT_BOARD_SEAT_STATUS="$T/seat.sh" \
    FT_BOARD_HIL_LEDGER="$1/HIL-LEDGER.md" FT_BOARD_MERGE_QUEUE="$1/MERGE-QUEUE.md" python3 "$BIN/ft-board.py" render "${2:---term}" 2>&1
}
printf '#!/bin/sh\necho "[]"\n' > "$T/verdict.sh"; printf '#!/bin/sh\necho EMPTY\n' > "$T/inbox.sh"
RR="$(mkroot rr)"; : > "$RR/alive.txt"; mkdir -p "$RR/.fable-team/state/board"
cp "$FX/gh-cache/fresh.json" "$RR/gh.json"; cp "$FX/gh-cache/fresh.json" "$RR/.fable-team/state/board/gh-cache.json"
printf '| # | 일시 | 좌석 | 좌석seq | 질문 | 선택지 | 추천 | 상태 |\n|---|---|---|---|---|---|---|---|\n| 1 | 10-12 | a | 1 | q1 | x | x | open |\n| 2 | 10-12 | b | 2 | q2 | x | x | answered |\n' > "$RR/HIL-LEDGER.md"
printf '| 항목 | 상태 |\n|---|---|\n| PR 1 | 대기 |\n| PR 2 | 완료 |\n' > "$RR/MERGE-QUEUE.md"
touch -t 202610120959 "$RR/.fable-team/state/board/gh-cache.json"
python3 - "$RR/.fable-team/comm/mailbox.jsonl" <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({"seq": 7, "ts": "2026-10-12T09:50:00", "to": "byz-planner-master-claude#27", "from": "x#1", "body": "[x#1->byz-planner-master-claude#27] [긴급] 급함"}, ensure_ascii=False) + "\n")
PY
echo '{"_master": "byz-planner-master-claude#27"}' > "$RR/.fable-team/seats-planner.json"; echo "byz-planner-master-claude#27" > "$RR/alive.txt"
out="$(GHTTL=999999 render "$RR")"
has "R1 ⑤ 절 제목" "$out" "⑤ 오빠가 정할 것"
has "R1 HIL-LEDGER open 1건" "$out" "HIL-LEDGER open 1"
has "R1 큐 긴급 #7" "$out" "#7"
has "R1 MERGE-QUEUE 대기 1" "$out" "MERGE-QUEUE 대기 1"
has "R1 제안 승인/반려 없음 1" "$out" "제안 미결정 1"
has "R1 관찰 중 1" "$out" "관찰 중 1"
lacks "R1 비어 있지 않으면 '없음' 줄 없음" "$out" "오늘 질문 0"
has "R1 ④ 오늘 판정표 뒤에 ⑤" "$(printf '%s\n' "$out" | awk '/④ 오늘 판정표/{a=1} a&&/⑤ 오빠가 정할 것/{print "ok"; exit}')" "ok"
out="$(GHTTL=999999 render "$RR" --slack)"; has "R2 슬랙 꼴에도 ⑤" "$out" "⑤ 오빠가 정할 것"
# 오래된 캐시(mtime 09:00 → 60분) = 미확인 · 없음으로 접지 않는다
touch -t 202610120900 "$RR/.fable-team/state/board/gh-cache.json"
out="$(GHTTL=999999 render "$RR")"
has "R3 캐시 오래됨 → 미확인 표기" "$out" "캐시 09:00 · 미확인"
lacks "R3 없음으로 접지 않음" "$out" "오늘 질문 0"
# 전부 0 ∧ 신선 → 없음
RZ="$(mkroot rz)"; echo "byz-planner-master-claude#27" > "$RZ/alive.txt"; echo '{"_master": "byz-planner-master-claude#27"}' > "$RZ/.fable-team/seats-planner.json"
mkdir -p "$RZ/.fable-team/state/board"; cp "$FX/gh-cache/none.json" "$RZ/gh.json"; cp "$FX/gh-cache/none.json" "$RZ/.fable-team/state/board/gh-cache.json"; touch -t 202610120959 "$RZ/.fable-team/state/board/gh-cache.json"
printf '| # | 일시 | 좌석 | 좌석seq | 질문 | 선택지 | 추천 | 상태 |\n|---|---|---|---|---|---|---|---|\n' > "$RZ/HIL-LEDGER.md"; printf '| 항목 | 상태 |\n|---|---|\n' > "$RZ/MERGE-QUEUE.md"
out="$(GHTTL=999999 render "$RZ")"
has "R4 전부 0 ∧ 신선 → 없음 한 줄" "$out" "오빠가 정할 것: 없음 — 오늘 질문 0"
rm "$RZ/MERGE-QUEUE.md"; out="$(GHTTL=999999 render "$RZ")"
has "R5 원장 파일 없음 → 확인 불가(없음으로 접지 않음)" "$out" "MERGE-QUEUE 확인 불가"
lacks "R5 없음 한 줄 아님" "$out" "오늘 질문 0"

# ── F3(fix2): 기본 = 캐시 전용(플래그 없는 호출은 외부 0) · 갱신은 --refresh-gh / FT_BOARD_GH_REFRESH=1 일 때만 7초+1 ──
RG="$(mkroot rg)"; : > "$RG/alive.txt"; mkdir -p "$RG/.fable-team/state/board"
printf '#!/bin/sh\necho x >> "%s/gh-called"\necho "[]"\n' "$RG" > "$RG/gh-spy.sh"; printf '#!/bin/sh\necho x >> "%s/gh-called"\nexit 1\n' "$RG" > "$RG/gh-fail.sh"
ghrender() {  # 인자: ft-board.py render 뒤에 붙일 것 (기본 --term) · 환경에 FT_BOARD_GH_CACHE_ONLY/REFRESH 를 «넣지 않는다» — CLI 기본 진입점 그대로
  env -u FT_BOARD_GH_CACHE_ONLY -u FT_BOARD_GH_REFRESH FT_ROOT="$RG" FT_BOARD_NOW=2026-10-12T10:00:00 FT_BOARD_TMUX="cat $RG/alive.txt" FT_BOARD_GH="bash $RG/${GHSPY:-gh-spy.sh}" FT_BOARD_GH_TTL="${GHTTL:-600}" \
    FT_VERDICT_BIN="$T/verdict.sh" FT_BOARD_INBOX="bash $T/inbox.sh" FT_BOARD_SEAT_STATUS="$T/seat.sh" \
    FT_BOARD_HIL_LEDGER="$RG/H.md" FT_BOARD_MERGE_QUEUE="$RG/M.md" python3 "$BIN/ft-board.py" render "${@:---term}" 2>&1; }
printf '| # | 상태 |\n|---|---|\n' > "$RG/H.md"; cp "$RG/H.md" "$RG/M.md"
rm -f "$RG/gh-called"; out="$(ghrender)"
[ ! -e "$RG/gh-called" ] && ok "G1 CLI 기본(env 미지정) + 캐시 없음 → gh 외부 실행 0" || bad "G1 gh 가 실행됨"
has "G1 ⑤ 에 캐시 없음 · 미확인" "$out" "캐시 없음 · 미확인"
lacks "G1 질문 0 으로 접지 않음" "$out" "오늘 질문 0"
cp "$FX/gh-cache/none.json" "$RG/.fable-team/state/board/gh-cache.json"; touch -t 202610120900 "$RG/.fable-team/state/board/gh-cache.json"
out="$(GHTTL=60 ghrender)"
[ ! -e "$RG/gh-called" ] && ok "G2 CLI 기본 + 오래된 캐시 → gh 외부 실행 0" || bad "G2 gh 가 실행됨"
has "G2 캐시 09:00 · 미확인" "$out" "캐시 09:00 · 미확인"
lacks "G2 질문 0 으로 접지 않음" "$out" "오늘 질문 0"
# 명시 갱신: --term --refresh-gh → spy 1회
rm -f "$RG/gh-called" "$RG/.fable-team/state/board/gh-cache.json"
out="$(ghrender --term --refresh-gh)"
eq "G2b --refresh-gh → spy 호출 1회" "$(wc -l < "$RG/gh-called" 2>/dev/null | tr -d ' ')" 1
# 갱신 모드의 run timeout 인자 7
rm -f "$RG/gh-called" "$RG/.fable-team/state/board/gh-cache.json"
seen="$(FT_BOARD_GH_REFRESH=1 FT_BOARD_GH="bash $RG/gh-spy.sh" python3 -c '
import sys; from pathlib import Path
sys.path.insert(0, sys.argv[1]); import ft_board_env as e
seen = []; orig = e.run
e.run = lambda cmd, what, env=None, timeout=60: (seen.append(timeout), orig(cmd, what, env, timeout))[1]
e.gh_issues(Path(sys.argv[2])); print(seen)' "$BIN" "$RG" 2>&1)"
eq "G3 갱신 모드 run timeout 인자 [7]" "$seen" "[7]"
eq "G3 spy 호출 1회" "$(wc -l < "$RG/gh-called" | tr -d ' ')" 1
# 같은 함수를 플래그 없이 → 외부 0
rm -f "$RG/gh-called" "$RG/.fable-team/state/board/gh-cache.json"
env -u FT_BOARD_GH_REFRESH FT_BOARD_GH="bash $RG/gh-spy.sh" python3 -c '
import sys; from pathlib import Path
sys.path.insert(0, sys.argv[1]); import ft_board_env as e
print(e.gh_issues(Path(sys.argv[2])))' "$BIN" "$RG" >/dev/null 2>&1
[ ! -e "$RG/gh-called" ] && ok "G3b gh_issues 플래그 없음 → 외부 0" || bad "G3b gh_issues 가 외부 실행"
# 실패: 재시도 1회(총 2회) · 캐시 있으면 캐시 유지(raise 0) · 캐시 없으면 raise
rm -f "$RG/gh-called"; cp "$FX/gh-cache/none.json" "$RG/.fable-team/state/board/gh-cache.json"
FT_BOARD_GH_REFRESH=1 FT_ROOT="$RG" FT_BOARD_GH="bash $RG/gh-fail.sh" FT_BOARD_GH_TTL=0 python3 -c '
import sys; from pathlib import Path
sys.path.insert(0, sys.argv[1]); import ft_board_env as e
print(len(e.gh_issues(Path(sys.argv[2]))))' "$BIN" "$RG" > "$T/g4.out" 2>&1; echo $? > "$T/g4.rc"
eq "G4 실패 + 캐시 있음 → raise 0 · 캐시 유지(1건)" "$(cat "$T/g4.rc") $(cat "$T/g4.out")" "0 1"
eq "G4 gh 호출 2회(시도 1 + 재시도 1)" "$(wc -l < "$RG/gh-called" | tr -d ' ')" 2
rm -f "$RG/gh-called" "$RG/.fable-team/state/board/gh-cache.json"
FT_BOARD_GH_REFRESH=1 FT_ROOT="$RG" FT_BOARD_GH="bash $RG/gh-fail.sh" FT_BOARD_GH_TTL=0 python3 -c '
import sys; from pathlib import Path
sys.path.insert(0, sys.argv[1]); import ft_board_env as e
e.gh_issues(Path(sys.argv[2]))' "$BIN" "$RG" > /dev/null 2>&1; rc=$?
eq "G5 실패 + 캐시 없음 → raise(rc≠0)" "$([ $rc -ne 0 ] && echo y || echo n)" y
# launchd 발행 경로 — ft-board-publish.sh 가 갱신 플래그를 «명시적으로» 붙인다 (render --slack · snapshot 둘 다)
printf '#!/bin/sh\necho "$@" >> "%s/board-args"\nexit 3\n' "$RG" > "$RG/board-stub.sh"; echo '# x' > "$RG/tp.py"; chmod +x "$RG/board-stub.sh"
rm -f "$RG/board-args"; FT_ROOT="$RG" FT_BOARD_BIN="$RG/board-stub.sh" FT_THREAD_POST="$RG/tp.py" bash "$BIN/ft-board-publish.sh" >/dev/null 2>&1
has "G6 publish render 호출 인자에 --refresh-gh" "$(cat "$RG/board-args" 2>/dev/null)" "render --slack --refresh-gh"
has "G6 publish snapshot 호출도 --refresh-gh" "$(grep -n '"$BOARD" snapshot' "$BIN/ft-board-publish.sh")" "snapshot --refresh-gh"
# ft-tick-line.sh 는 더는 env 를 켜지 않는다(기본이 캐시 전용)
lacks "G7 tick-line 에 CACHE_ONLY export 없음" "$(cat "$TICK")" "FT_BOARD_GH_CACHE_ONLY=1"

# ── ft-measure-net.sh (PLAN §9 정규식·분류 규칙을 코드로 고정) ──────────────
RM="$(mkroot rm)"; cp "$FX"/measure/mailbox.log.jsonl "$FX"/measure/mailbox.log.jsonl.1 "$RM/.fable-team/comm/"; cp "$FX/measure/seats-planner.json" "$RM/.fable-team/"
meas() { FT_ROOT="$RM" FT_MEASURE_PROJECTS_DIRS="$FX/measure/projects" bash "$MEAS" "$@" 2>&1; echo $? > "$T/mrc"; }
W1="2026-10-08T00:00:00"; W2="2026-10-11T23:59:59"
out="$(meas succession "$W1" "$W2")"
eq "M1 1줄 JSON" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1
jeq "M1 raw == 5" "$out" "d['raw']" 5
jeq "M1 succession == 2" "$out" "d['succession']" 2
jeq "M1 first_boot == 3" "$out" "d['first_boot']" 3
jeq "M1 lineages == 3" "$out" "d['lineages']" 3
out="$(meas interview "$W1" "$W2")"
jeq "M2 total == 3 (id 중복 제거·창 밖 제외)" "$out" "d['total']" 3
jeq "M2 일자별 == {10-09:2, 10-10:1}" "$out" "d['by_day']" '{"2026-10-09": 2, "2026-10-10": 1}'
out="$(meas planner-mail "$W1" "$W2")"
jeq "M3 부팅 보고 없는 fixture → total == 0" "$out" "d['total']" 0
jeq "M3 unclassified == 7 (첫 부팅 전 구간)" "$out" "d['unclassified']" 7
jeq "M3 by_seat == {}" "$out" "d['by_seat']" '{}'
# F4 — «그날 현역» 을 불변 로그(부팅 보고 쪽지 ts)로 재현: 현역 #27 · 같은 날 #26/#27 각 1건 + #27 부팅 보고가 둘 사이
RP="$(mkroot rp)"; echo '{"_master": "byz-planner-master-claude#27"}' > "$RP/.fable-team/seats-planner.json"
python3 - "$RP/.fable-team/comm/mailbox.log.jsonl" <<'PY'
import json, sys
P26, P27 = "byz-planner-master-claude#26", "byz-planner-master-claude#27"
rows = [(1, "x#1", P26, "x", "2026-10-11T12:00:00"), (2, P27, "byz-ops-master-claude#1", "[부팅 보고] 승계", "2026-10-11T12:00:30"),
        (3, "x#1", P27, "y", "2026-10-11T12:01:00")]
with open(sys.argv[1], "w", encoding="utf-8") as f:
    for s, a, b, body, ts in rows: f.write(json.dumps({"seq": s, "ts": ts, "from": a, "to": b, "body": f"[{a}->{b}] {body}"}, ensure_ascii=False) + "\n")
PY
pm() { FT_ROOT="$RP" bash "$MEAS" planner-mail "$1" "$2" 2>&1; }
out="$(pm 2026-10-11T00:00:00 2026-10-11T23:59:59)"
jeq "P1 DA fixture: 현역 #27 → total == 1" "$out" "d['total']" 1
jeq "P1 by_seat == {#27: 1}" "$out" "d['by_seat']" '{"byz-planner-master-claude#27": 1}'
jeq "P1 부팅 전 1건 → unclassified == 1" "$out" "d['unclassified']" 1
# 승계가 두 번(#26 부팅 11:00 → #27 부팅 12:00:30): 각 부팅 뒤 «그 시각 현역» 앞 쪽지만 센다 · #27 부팅 뒤 #26 앞 쪽지 = 은퇴 좌석이라 안 센다 · 창 밖 제외
python3 - "$RP/.fable-team/comm/mailbox.log.jsonl" <<'PY'
import json, sys
P26, P27 = "byz-planner-master-claude#26", "byz-planner-master-claude#27"
rows = [(10, P26, "byz-ops-master-claude#1", "[부팅 보고] 먼저", "2026-10-11T11:00:00"), (11, "x#1", P26, "a", "2026-10-11T11:30:00"),
        (12, "x#1", P26, "b", "2026-10-11T12:00:40"), (13, "x#1", P27, "c", "2026-10-12T00:10:00")]
with open(sys.argv[1], "a", encoding="utf-8") as f:
    for s, a, b, body, ts in rows: f.write(json.dumps({"seq": s, "ts": ts, "from": a, "to": b, "body": f"[{a}->{b}] {body}"}, ensure_ascii=False) + "\n")
PY
out="$(pm 2026-10-11T00:00:00 2026-10-11T23:59:59)"
jeq "P2 total == 3 (#26 몫 2 + #27 몫 1 · 은퇴 뒤 #26 앞·창 밖 제외)" "$out" "d['total']" 3
jeq "P2 by_seat 정확" "$out" "d['by_seat']" '{"byz-planner-master-claude#26": 2, "byz-planner-master-claude#27": 1}'
jeq "P2 #26 부팅이 앞서므로 unclassified == 0" "$out" "d['unclassified']" 0
jeq "P2 일자별은 센 것만" "$out" "d['by_day']" '{"2026-10-11": 3}'
# baseline 서브커맨드 — 창 고정(10-08 21:04 ~ 10-11 23:45) · fixture 로그에 창 밖 행이 섞여 있어 창 필터를 equality 로 확인
out="$(FT_ROOT="$RM" FT_MEASURE_PROJECTS_DIRS="$FX/measure/projects" bash "$MEAS" baseline 2>&1)"
jeq "M6 baseline raw == 2 (창 밖 부팅 보고 제외)" "$out" "d['raw']" 2
jeq "M6 baseline succession == 1" "$out" "d['succession']" 1
jeq "M6 baseline first_boot == 1" "$out" "d['first_boot']" 1
jeq "M6 baseline interview == 3" "$out" "d['interview']" 3
jeq "M6 baseline window 고정" "$out" "d['window']" '{"interview": ["2026-10-08T00:00:00Z", "2026-10-11T14:45:59Z"], "mailbox": ["2026-10-08T21:04:00", "2026-10-11T23:45:59"]}'
out="$(meas bogus "$W1" "$W2")"; eq "M4 알 수 없는 지표 rc 2" "$(cat "$T/mrc")" 2
out="$(meas succession "$W1")"; eq "M4b 인자 부족 rc 2" "$(cat "$T/mrc")" 2
out="$(FT_ROOT="$T/none-root" bash "$MEAS" succession "$W1" "$W2" 2>&1)"; MRC=$?; eq "M5 로그 없음 → 실패(0 아님)" "$([ "$MRC" -ne 0 ] && echo y || echo n)" y

echo "---"; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL $fail"
exit "$fail"
