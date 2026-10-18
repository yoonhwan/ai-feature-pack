#!/usr/bin/env bash
# test_seat_close.sh — R297: ft-seat-close.sh «세션만 닫기» — 명부 stop-ready 표기 · 세션 kill · 거절 · 틱 resume_rows 에서 빠짐.
# 모든 쓰기는 mktemp scratch 안 — 가짜 tmux(PATH 앞) · 실제 세션·명부 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; CLOSE="${FT_SEAT_CLOSE_BIN:-$BIN/ft-seat-close.sh}"; TICK="$BIN/ft-tick.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unset FT_SEATS_JSON
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
J() { jq -r "$2" "$1"; }

# 가짜 tmux — 호출을 로그에 남긴다. FAKE_SESSION=1|0 · FAKE_TAG=1|0 · FAKE_KILL_RC=<n> · FAKE_LIVE="<살아 있는 세션 공백구분>"
mkdir -p "$TMP/bin"; LOG="$TMP/tmux.log"
cat > "$TMP/bin/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  has-session) [ "${FAKE_SESSION:-1}" = 1 ];;
  show-options) [ "${FAKE_TAG:-1}" = 1 ] && echo 1; exit 0;;
  set-option) exit 0;;
  kill-session) exit "${FAKE_KILL_RC:-0}";;
  list-sessions) for x in ${FAKE_LIVE:-}; do echo "$x"; done;;
  display-message) echo caller#0;;
esac
EOF
chmod +x "$TMP/bin/tmux"
run() { PATH="$TMP/bin:$PATH" TMUX_LOG="$LOG" "$@"; }
kills() { grep -c '^kill-session' "$LOG" 2>/dev/null || true; }
mkseats() { printf '%s' '{"_master": "M#1", "_hil_route": "P#1", "M#1": {"role": "master", "tick": "ft-master-tick"}, "P#1": {"role": "planner", "tick": "t"}, "N#0": {"role": "nano", "agent": "claude", "model": "m", "tick": null, "index": "i.md"}, "W#1": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}' > "$1"; }
export ZC_RESUME_DIR="$TMP/resume"; mkdir -p "$ZC_RESUME_DIR"

bash -n "$CLOSE" && ok "bash -n ft-seat-close.sh" || bad "bash -n ft-seat-close.sh"
chk "ft-seat-close.sh ≤ 120줄" "$([ "$(wc -l < "$CLOSE")" -le 120 ] && echo yes || echo no)" yes

resume_of() { # <명부> — 틱 resume_rows 출력의 좌석 열
  bash -c "SEATS=$1; $(sed -n '/^resume_rows() {/,/^}/p' "$TICK")"$'\n''resume_rows' | cut -f1 | xargs
}

# ① 직전 세대(W#1) + 재개 기록 + 후계 W#2 생존 + 태그 있음 → kill=ok
S="$TMP/a.json"; mkseats "$S"; : > "$LOG"; echo "{}" > "$ZC_RESUME_DIR/W#1.json"
out="$(FAKE_LIVE="W#1 W#2" FAKE_SESSION=1 FAKE_TAG=1 run bash "$CLOSE" 'W#1' --reason "판정 2050 노출 나노" --seats "$S")"; rc=$?
chk "①rc" "$rc" 0
chk "①출력" "$out" "CLOSED-SESSION W#1 file=$S role_was=tester kill=ok"
chk "①role·tick" "$(J "$S" '[.["W#1"].role,(.["W#1"].tick|tostring)]|join(",")')" "stop-ready,null"
chk "①_closed_role" "$(J "$S" '.["W#1"]._closed_role')" tester
chk "①_closed 3칸(by·at·reason)" "$(J "$S" '.["W#1"]._closed|[(.by!=null),(.at!=null),.reason]|join(",")')" "true,true,판정 2050 노출 나노"
chk "①.bak 1개" "$(ls "$S".bak-close-* 2>/dev/null | wc -l | tr -d ' ')" 1
chk "①kill 호출 1" "$(kills)" 1
chk "①태그 해제 호출 1 · kill 직전" "$(grep -c '^set-option .*-u @zc_v65_active' "$LOG") $(grep -B1 '^kill-session' "$LOG" | head -1 | cut -c1-10)" "1 set-option"
chk "①다른 행·_ 칸 불변" "$(J "$S" '[._master,._hil_route,.["M#1"].role,.["P#1"].role]|join(",")')" "M#1,P#1,master,planner"
chk "①틱 resume_rows 에 W#1 없음(M#1 P#1 만)" "$(resume_of "$S")" "M#1 P#1 N#0"

# ② 세션 없음 → kill=none · 표기는 됨 · 태그 해제·kill 호출 0
S="$TMP/b.json"; mkseats "$S"; : > "$LOG"
out="$(FAKE_SESSION=0 run bash "$CLOSE" 'N#0' --reason r --seats "$S")"; rc=$?
chk "②rc·출력" "$rc $out" "0 CLOSED-SESSION N#0 file=$S role_was=nano kill=none"
chk "②표기됨" "$(J "$S" '.["N#0"].role')" stop-ready
chk "②kill 0" "$(kills)" 0

# ③ 좌석이 _ 칸 값 → REJECT · 명부 쓰기 0
S="$TMP/c.json"; mkseats "$S"; cp "$S" "$TMP/c.orig"; : > "$LOG"
for s in 'M#1' 'P#1'; do
  out="$(run bash "$CLOSE" "$s" --reason r --seats "$S")"; rc=$?
  chk "③$s rc 1 · REJECT" "$rc ${out%% *}" "1 REJECT"
done
chk "③바이트 불변·.bak 0·kill 0" "$(cmp -s "$S" "$TMP/c.orig" && echo same || echo changed) $(ls "$TMP"/c.json.bak-close-* 2>/dev/null | wc -l | tr -d ' ') $(kills)" "same 0 0"

# ④ 명부 후보 0 / 2 → REJECT · --reason 없음 → rc 2
R="$TMP/repo"; mkdir -p "$R/.fable-team"; git -C "$R" init -q
mkseats "$R/.fable-team/seats.json"; mkseats "$R/.fable-team/seats-x.json"
(cd "$R" && run bash "$CLOSE" 'N#0' --reason r > "$TMP/d2.out"); rc=$?
chk "④후보 2개 rc 1 · REJECT" "$rc $(cut -c1-6 "$TMP/d2.out")" "1 REJECT"
chk "④후보 2개 쓰기 0" "$(ls "$R/.fable-team" | grep -c bak)" 0
(cd "$R" && run bash "$CLOSE" 'ZZ#9' --reason r > "$TMP/d0.out"); rc=$?
chk "④후보 0개 rc 1 · REJECT" "$rc $(cut -c1-6 "$TMP/d0.out")" "1 REJECT"
rm "$R/.fable-team/seats-x.json"
(cd "$R" && FAKE_SESSION=0 run bash "$CLOSE" 'N#0' --reason r > /dev/null); rc=$?
chk "④후보 1개 자동 선택 rc 0" "$rc $(J "$R/.fable-team/seats.json" '.["N#0"].role')" "0 stop-ready"
run bash "$CLOSE" 'N#0' --seats "$S" > /dev/null 2>&1; chk "④--reason 없음 rc 2" "$?" 2
run bash "$CLOSE" 'N#0' --reason "  " --seats "$S" > /dev/null 2>&1; chk "④--reason 공백 rc 2" "$?" 2
run bash "$CLOSE" > /dev/null 2>&1; chk "④좌석 없음 rc 2" "$?" 2

# ⑤ kill 실패 → FAIL rc 1 · 표기는 남음 · 틱 재개 0 (kill 범위 안: W#1 직전 세대 + 기록 + W#2 생존)
S="$TMP/e.json"; mkseats "$S"; : > "$LOG"; echo "{}" > "$ZC_RESUME_DIR/W#1.json"
out="$(FAKE_LIVE="W#1 W#2" FAKE_SESSION=1 FAKE_KILL_RC=1 run bash "$CLOSE" 'W#1' --reason r --seats "$S")"; rc=$?
chk "⑤rc 1 · FAIL kill" "$rc ${out%% W#1*}" "1 FAIL kill"
chk "⑤표기 남음" "$(J "$S" '.["W#1"].role')" stop-ready
chk "⑤틱 resume_rows 에 W#1 없음" "$(resume_of "$S")" "M#1 P#1 N#0"

# ⑥ 이미 닫힌 행 재호출 → _closed_role 이 stop-ready 로 덮이지 않는다
out="$(FAKE_SESSION=0 run bash "$CLOSE" 'W#1' --reason again --seats "$S")"
chk "⑥재호출 _closed_role 보존" "$(J "$S" '.["W#1"]._closed_role')" tester
chk "⑥재호출 reason 갱신" "$(J "$S" '.["W#1"]._closed.reason')" again

# ⑦ kill 범위(전역 표준승인) — 계보 최신 → held rc 3 · 표기 됨 · kill 0
S="$TMP/f.json"; mkseats "$S"; : > "$LOG"
out="$(FAKE_LIVE="N#0" FAKE_SESSION=1 run bash "$CLOSE" 'N#0' --reason r --seats "$S")"; rc=$?
chk "⑦a 계보 최신 rc 3 · kill=held" "$rc $(printf '%s' "$out" | grep -o 'kill=held')" "3 kill=held"
chk "⑦a 표기 됨 · kill 0" "$(J "$S" '.["N#0"].role') $(kills)" "stop-ready 0"
# ⑦b 직전 세대 + 기록 없음 + 후계 1개 → held
S="$TMP/g.json"; mkseats "$S"; : > "$LOG"; rm -f "$ZC_RESUME_DIR/W#1.json"
out="$(FAKE_LIVE="W#1 W#2" FAKE_SESSION=1 run bash "$CLOSE" 'W#1' --reason r --seats "$S")"; rc=$?
chk "⑦b 기록 없음·후계 1개 rc 3 · kill 0" "$rc $(kills)" "3 0"
# ⑦c 직전 세대 + 기록 없음 + 후계 2개 생존(keep-last-2) → ok
: > "$LOG"; S="$TMP/h.json"; mkseats "$S"
out="$(FAKE_LIVE="W#1 W#2 W#3" FAKE_SESSION=1 run bash "$CLOSE" 'W#1' --reason r --seats "$S")"; rc=$?
chk "⑦c 후계 2개 생존 rc 0 · kill 1" "$rc $(kills)" "0 1"
# ⑦d 기록 있음 + 후계 0(자기가 최신) → held
: > "$LOG"; S="$TMP/i.json"; mkseats "$S"; echo "{}" > "$ZC_RESUME_DIR/W#1.json"
FAKE_LIVE="W#1" FAKE_SESSION=1 run bash "$CLOSE" 'W#1' --reason r --seats "$S" > /dev/null; rc=$?
chk "⑦d 기록만 있고 후계 0 rc 3 · kill 0" "$rc $(kills)" "3 0"

# ⑦e 직전 세대 + 재개 기록 있음 + 후계 1개 생존 → rc 0 · kill 1 (판정 1344 주 경로 — lineage_ok 의 기록 갈래)
: > "$LOG"; S="$TMP/j.json"; mkseats "$S"; echo "{}" > "$ZC_RESUME_DIR/W#1.json"
out="$(FAKE_LIVE="W#1 W#2" FAKE_SESSION=1 run bash "$CLOSE" 'W#1' --reason r --seats "$S")"; rc=$?
chk "⑦e 기록 있음·후계 1개 rc 0 · kill=ok · kill 1" "$rc ${out##* } $(kills)" "0 kill=ok 1"

# R400 «역할 좌석 닫기» --verdict — 재개 기록은 가짜 retire 스텁(FT_SEAT_RETIRE_BIN) · 원장 루트 = FT_ROOT scratch · 실제 기록·명부·세션 0
# (ⓐ = 위 ①~⑦ 이 --verdict 없는 호출 그대로 PASS)
cat > "$TMP/bin/retire-stub" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$RETIRE_LOG"; echo "$FAKE_RETIRE_OUT"; exit "${FAKE_RETIRE_RC:-0}"
EOF
chmod +x "$TMP/bin/retire-stub"
export FT_SEAT_RETIRE_BIN="$TMP/bin/retire-stub" RETIRE_LOG="$TMP/retire.log" FT_ROOT="$TMP/root"; mkdir -p "$FT_ROOT"; VLOG="$FT_ROOT/.fable-team/state/seat-close-verdict.log"
mkrole() { printf '%s' '{"_master": "M#1", "_arch": "A#1", "_hil_route": "P#1", "M#1": {"role": "master", "tick": "t"}, "A#1": {"role": "arch", "agent": "claude", "model": "m", "tick": "ft-arch-tick"}, "P#1": {"role": "planner", "tick": "t"}}' > "$1"; }
vrun() { FAKE_RETIRE_OUT="${FAKE_RETIRE_OUT-RESUME ok $TMP/resume/$1.json}" RETIRE_LOG="$TMP/retire.log" run bash "$CLOSE" "$@"; }
# ⓑ 현역 칸(_arch) 좌석 + 기록 ok + 계보 최신(--verdict 없으면 REJECT·held 였을 좌석) → 칸 "" · .bak · kill 1 · 원장 1행
S="$TMP/v1.json"; mkrole "$S"; : > "$LOG"; : > "$TMP/retire.log"
out="$(FAKE_LIVE="A#1" FAKE_SESSION=1 vrun 'A#1' --reason "판정 2304 역할 좌석 닫기" --seats "$S" --verdict 2304)"; rc=$?
chk "ⓑrc 0 · CLOSED-ROLE 출력" "$rc $out" "0 CLOSED-ROLE A#1 verdict=2304 record=$TMP/resume/A#1.json cells=$S:_arch kill=ok"
chk "ⓑretire 스텁 인자(--record-only --verdict · --seats 전달)" "$(cat "$TMP/retire.log")" "A#1 --record-only --verdict 2304 --seats $S"
chk "ⓑ_arch \"\" · 다른 _ 칸 불변" "$(J "$S" '[._arch,._master,._hil_route]|join(",")')" ",M#1,P#1"
chk "ⓑ행 stop-ready · _closed_role · _closed.verdict·reason" "$(J "$S" '.["A#1"]|[.role,(.tick|tostring),._closed_role,._closed.verdict,._closed.reason]|join(",")')" "stop-ready,null,arch,2304,판정 2304 역할 좌석 닫기"
chk "ⓑ.bak 1 · kill 1 · 태그 해제 1" "$(ls "$S".bak-close-* | wc -l | tr -d ' ') $(kills) $(grep -c '^set-option .*-u @zc_v65_active' "$LOG")" "1 1 1"
chk "ⓑ원장 1행(판정·좌석·기록·칸·kill)" "$(wc -l < "$VLOG" | tr -d ' ') $(cut -f2- "$VLOG")" "1 verdict=2304	A#1	record=$TMP/resume/A#1.json	cells=$S:_arch	kill=ok"
# ⓒ 재개 기록 NORECORD → HELD rc 3 · 명부 바이트 동일 · .bak 0 · kill 0 · 원장 0
S="$TMP/v2.json"; mkrole "$S"; cp "$S" "$TMP/v2.orig"; : > "$LOG"; : > "$VLOG"
out="$(FAKE_RETIRE_OUT="NORECORD A#1 세션 파일 없음" FAKE_LIVE="A#1" vrun 'A#1' --reason r --seats "$S" --verdict 2304)"; rc=$?
chk "ⓒrc 3 · HELD" "$rc ${out%% — *}" "3 HELD A#1 재개 기록 실패"
chk "ⓒ사유 원문 포함" "$(printf '%s' "$out" | grep -c 'NORECORD A#1 세션 파일 없음')" 1
chk "ⓒ바이트 동일 · .bak 0 · kill 0 · 원장 0" "$(cmp -s "$S" "$TMP/v2.orig" && echo same || echo changed) $(ls "$S".bak-close-* 2>/dev/null | wc -l | tr -d ' ') $(kills) $(wc -l < "$VLOG" | tr -d ' ')" "same 0 0 0"
out="$(FAKE_RETIRE_OUT="RESUME ok /x" FAKE_RETIRE_RC=1 vrun 'A#1' --reason r --seats "$S" --verdict 2304)"; rc=$?
chk "ⓒ스텁 rc≠0 이면 RESUME ok 글자여도 HELD rc 3 · 쓰기 0" "$rc $(cmp -s "$S" "$TMP/v2.orig" && echo same || echo changed) $(kills)" "3 same 0"
# ⓓ 명부 행 없음(다른 리포 좌석) → 기록만 · NOROW rc 3 · kill 0 · 명부 바이트 동일
S="$TMP/v3.json"; mkrole "$S"; cp "$S" "$TMP/v3.orig"; : > "$LOG"
out="$(FAKE_LIVE="byz-airag-arch-claude#3" vrun 'byz-airag-arch-claude#3' --reason r --seats "$S" --verdict 2304)"; rc=$?
chk "ⓓrc 3 · NOROW 출력(앞부분 · R400 r3 §D 안내)" "$rc ${out%%<그 설치본 루트>*}" "3 NOROW byz-airag-arch-claude#3 명부 행 없음($S) — 기록 $TMP/resume/byz-airag-arch-claude#3.json · kill 0 · 다른 리포 좌석이면: FT_ROOT="
chk "ⓓNOROW 안내 끝 = 지금 인자 + --seats <그 루트>" "${out##*ft-seat-close.sh }" "'byz-airag-arch-claude#3' --verdict 2304 --reason r --seats <그 루트>/.fable-team/seats.json"
chk "ⓓ바이트 동일 · kill 0" "$(cmp -s "$S" "$TMP/v3.orig" && echo same || echo changed) $(kills)" "same 0"
# ⓔ 자기 자신(실행 pane 세션 == 좌석) → REJECT rc 1 · 기록 호출 0 · 쓰기 0
S="$TMP/v4.json"; mkrole "$S"; printf '%s' '{"caller#0": {"role": "arch", "tick": null}, "_arch": "caller#0"}' > "$S"; cp "$S" "$TMP/v4.orig"; : > "$LOG"; : > "$TMP/retire.log"
out="$(TMUX_PANE=%1 vrun 'caller#0' --reason r --seats "$S" --verdict 2304)"; rc=$?
chk "ⓔrc 1 · REJECT · 기록 호출 0 · 바이트 동일 · kill 0" "$rc ${out%% *} $(wc -l < "$TMP/retire.log" | tr -d ' ') $(cmp -s "$S" "$TMP/v4.orig" && echo same || echo changed) $(kills)" "1 REJECT 0 same 0"
# ⓕ `_*` 칸이 두 명부에 있는 좌석(루트 탐색) → 둘 다 "" · .bak 2 · 원장 1행
R="$TMP/vrepo"; mkdir -p "$R/.fable-team"; git -C "$R" init -q
mkrole "$R/.fable-team/seats.json"; printf '%s' '{"_hil_route": "A#1", "_desk": "D#1", "D#1": {"role": "desk"}}' > "$R/.fable-team/seats-x.json"; : > "$LOG"; : > "$VLOG"
out="$(cd "$R" && FAKE_LIVE="A#1" vrun 'A#1' --reason r --verdict 2304)"; rc=$?
RR="$(cd "$R" && pwd -P)"   # 루트 = git common dir(실경로) · 명부 순서 = glob 정렬(seats-x < seats.)
chk "ⓕrc 0 · cells 두 명부" "$rc ${out#*cells=}" "0 $RR/.fable-team/seats-x.json:_hil_route;$RR/.fable-team/seats.json:_arch kill=ok"
chk "ⓕ두 명부 칸 \"\" · 다른 칸 불변" "$(J "$R/.fable-team/seats.json" '[._arch,._master]|join(",")') $(J "$R/.fable-team/seats-x.json" '[._hil_route,._desk]|join(",")')" ",M#1 ,D#1"
chk "ⓕ.bak 2 · kill 1 · 원장 1행" "$(ls "$R/.fable-team"/*.bak-close-* | wc -l | tr -d ' ') $(kills) $(wc -l < "$VLOG" | tr -d ' ')" "2 1 1"
# usage — --verdict 값 없음·형식 밖 → rc 2
run bash "$CLOSE" 'A#1' --reason r --seats "$S" --verdict > /dev/null 2>&1; chk "ⓥ--verdict 값 없음 rc 2" "$?" 2
run bash "$CLOSE" 'A#1' --reason r --seats "$S" --verdict "x 1" > /dev/null 2>&1; chk "ⓥ--verdict 형식 밖 rc 2" "$?" 2

# R400 r3 §D — 다른 리포 좌석: cwd = 리포 A(그 좌석 행 없음) · 좌석 행은 리포 B 워크트리 꼴 명부 · FT_ROOT=B + --seats B 명부
A="$TMP/repoA"; mkdir -p "$A/.fable-team"; git -C "$A" init -q; mkrole "$A/.fable-team/seats.json"; cp "$A/.fable-team/seats.json" "$TMP/A.orig"
B="$TMP/B"; mkdir -p "$B/.fable-team"; printf '%s' '{"_arch": "byz-airag-arch-claude#3", "byz-airag-arch-claude#3": {"role": "arch", "tick": null}}' > "$B/.fable-team/seats.json"; cp "$B/.fable-team/seats.json" "$TMP/B.orig"
# ⓖ FT_ROOT + --seats → CLOSED-ROLE · B 명부 표기·.bak · 원장 = B 루트 · A 명부 바이트 동일
: > "$LOG"; RA='byz-airag-arch-claude#3'
out="$(cd "$A" && FT_ROOT="$B" FAKE_LIVE="$RA" vrun "$RA" --reason r --verdict 1 --seats "$B/.fable-team/seats.json")"; rc=$?
chk "ⓖrc 0 · CLOSED-ROLE · kill=ok" "$rc ${out%% *} ${out##* }" "0 CLOSED-ROLE kill=ok"
chk "ⓖB 명부 stop-ready · _arch \"\" · .bak 1" "$(J "$B/.fable-team/seats.json" "[.[\"$RA\"].role,._arch]|join(\",\")") $(ls "$B/.fable-team"/seats.json.bak-close-* | wc -l | tr -d ' ')" "stop-ready, 1"
chk "ⓖ원장 = B 루트 1행 · A 명부 바이트 동일 · kill 1" "$(wc -l < "$B/.fable-team/state/seat-close-verdict.log" | tr -d ' ') $(cmp -s "$A/.fable-team/seats.json" "$TMP/A.orig" && echo same || echo changed) $(kills)" "1 same 1"
# ⓗ 같은 상태(B 원복)에서 --seats 없이 → NOROW 안내에 FT_ROOT=·--seats · rc 3 · kill 0 · 두 명부 바이트 동일
cp "$TMP/B.orig" "$B/.fable-team/seats.json"; : > "$LOG"
out="$(cd "$A" && FT_ROOT="$B" FAKE_LIVE="$RA" vrun "$RA" --reason r --verdict 1)"; rc=$?
chk "ⓗrc 3 · NOROW · 안내에 FT_ROOT= · --seats" "$rc ${out%% *} $(grep -c 'FT_ROOT=' <<< "$out") $(grep -c -- '--seats ' <<< "$out")" "3 NOROW 1 1"
chk "ⓗkill 0 · 두 명부 바이트 동일" "$(kills) $(cmp -s "$A/.fable-team/seats.json" "$TMP/A.orig" && echo same || echo changed) $(cmp -s "$B/.fable-team/seats.json" "$TMP/B.orig" && echo same || echo changed)" "0 same same"

echo "fail=$fail"; [ "$fail" = 0 ]
