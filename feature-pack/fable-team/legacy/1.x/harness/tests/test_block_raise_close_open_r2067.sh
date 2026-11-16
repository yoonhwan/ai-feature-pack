#!/usr/bin/env bash
# test_block_raise_close_open_r2067.sh — r2067: 닫기·열기 도구의 «기다림» 종료(rc 3~7)를 막힘 장부에 1줄 올리고 성공이면 지운다.
#   ① lib 인자·루트·OFF·160자·첫 줄 ② lib 실패·멈춤(상한) ③④ --wrap(ft-seat-close·ft-nano-close) ⑤ ft-successor-open ⑥ ft-nano-spawn
#   ⑦ 장부 없음·멈춤 실행과 rc·stdout·stderr 바이트 같음 ⑧ 장부 스텁이 block.sh 인자 규칙 검사(rc 2 0회 · 빈 칸 0) · 변이 M1~M3(사본만 · 원본 대조)
#   칸 나눔(하드 룰 22) FT_R2067_PART=1(①②③④⑦⑧·M1~M3) · 2(⑤⑦⑧) · 3(⑥⑦⑧) · all(기본)
#   장부 = FT_BLOCK_BIN 스텁(실 장부 0) · 실 tmux·실 좌석·실 우편함 0 · sleep 0(멈춘 스텁 = fifo 읽기)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_reject_critical_r1718_fixture.sh"
PART="${FT_R2067_PART:-all}"; case "$PART" in 1|2|3|all) ;; *) echo "usage: FT_R2067_PART=1|2|3|all"; exit 2;; esac
in_part() { [ "$PART" = all ] || [ "$PART" = "$1" ]; }
TO="$(command -v timeout || command -v gtimeout)"
unset FT_BLOCK_BIN FT_BLOCK_TIMEOUT_S
# ── 장부 스텁: 호출 1회 = BLK_LOG 1줄(json · 루트·인자·규칙 통과) · block.sh 인자 규칙 그대로(틀림 = rc 2) · BLK_FIFO = 멈춤 · BLK_ERR·BLK_RC = 실패 주입
STUB="$T/block-stub.sh"; BLK_LOG="$T/blk.log"; NONE="$T/no-block.sh"; export BLK_LOG
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
python3 - "$@" <<'PY'
import json, os, sys
a = sys.argv[1:]
def good():
    if a[:1] == ["raise"] and len(a) >= 4:
        if a[2] not in ("seat", "card", "team") or not a[1] or not a[3]: return False
        o, r = {}, a[4:]
        while r:
            if len(r) < 2 or r[0] not in ("--cause", "--fix", "--period"): return False
            o[r[0]] = r[1]; r = r[2:]
        return bool(o.get("--cause", "").strip()) and bool(o.get("--fix", "").strip()) and (o.get("--period") or "0").isdigit()
    return a[:1] == ["clear"] and len(a) == 3 and all(x.strip() for x in a[1:])
g = good()
with open(os.environ["BLK_LOG"], "a", encoding="utf-8") as f: f.write(json.dumps({"root": os.environ.get("FT20_SCAN_ROOT", ""), "args": a, "ok": g}, ensure_ascii=False) + "\n")
sys.exit(0 if g else 2)
PY
rc=$?
[ -z "${BLK_FIFO:-}" ] || read -r _ < "$BLK_FIFO"
[ -z "${BLK_ERR:-}" ] || echo "$BLK_ERR" >&2
exit "${BLK_RC:-$rc}"
EOF
chmod +x "$STUB"; ALLLOG="$T/blk.all"; : > "$ALLLOG"
bl() {   # bl n | bl a <i> (인자 « | » 이음) | bl root <i> | bl opt <i> <--이름> | bl bad(규칙 어긋남 수)
  python3 - "$BLK_LOG" "$@" <<'PY'
import json, sys
p, cmd, rest = sys.argv[1], sys.argv[2], sys.argv[3:]
try: rows = [json.loads(l) for l in open(p, encoding="utf-8") if l.strip()]
except OSError: rows = []
if cmd == "n": print(len(rows))
elif cmd == "bad": print(sum(1 for r in rows if not r["ok"]))
else:
    r = rows[int(rest[0])] if len(rows) > int(rest[0]) else {"args": [], "root": ""}
    if cmd == "a": print(" | ".join(r["args"]))
    elif cmd == "root": print(r["root"])
    elif cmd == "opt": a = r["args"]; print(next((a[i + 1] for i in range(len(a) - 1) if a[i] == rest[1]), ""))
PY
}
blr() { [ -f "$BLK_LOG" ] && cat "$BLK_LOG" >> "$ALLLOG"; : > "$BLK_LOG"; }   # 호출 기록 비움(⑧ 은 전체 누적으로 본다)
FIFO="$T/blk.fifo"; mkfifo "$FIFO"
unstick() { "$TO" 2 sh -c ': > "$1"' _ "$FIFO" 2>/dev/null; return 0; }   # 남은 멈춘 스텁을 푼다(읽는 쪽이 없으면 2초 뒤 그냥 끝남)
benv() {   # benv <stub|none|stuck> → env 인자(경로에 공백 없음)
  case "$1" in stub) echo "FT_BLOCK_BIN=$STUB";; none) echo "FT_BLOCK_BIN=$NONE";; stuck) echo "FT_BLOCK_BIN=$STUB BLK_FIFO=$FIFO FT_BLOCK_TIMEOUT_S=1";; esac; }
# same3 <이름> <사례 실행 함수> <bin> — stub·none·stuck 세 번 돌려 rc·stdout·stderr 바이트 대조 + stuck 경과 ≤ 없음 경과 + 호출 수 × 상한(1) + 2초(⑦)
same3() {
  local name="$1" fn="$2" b="$3" m t0 dt dnone=0 dstuck=0 nc
  for m in none stuck stub; do blr; t0=$SECONDS; "$fn" "$b" "$m"; dt=$((SECONDS - t0))
    printf '%s\n' "$RC" > "$T/s3.$m.rc"; cp "$T/c.out" "$T/s3.$m.out"; cp "$T/c.err" "$T/s3.$m.err"
    case "$m" in none) dnone=$dt;; stuck) dstuck=$dt; unstick;; esac; done
  nc="$(bl n)"; [ "$dstuck" -le $((dnone + nc + 2)) ] || { bad "$name ⑦ 멈춘 장부 경과 ${dstuck}s > 없음 ${dnone}s + 호출 ${nc} × 1s + 2s"; return 1; }
  for m in stuck stub; do
    cmp -s "$T/s3.none.rc" "$T/s3.$m.rc" && cmp -s "$T/s3.none.out" "$T/s3.$m.out" && cmp -s "$T/s3.none.err" "$T/s3.$m.err" \
      || { bad "$name ⑦ $m ≠ none" "$(diff "$T/s3.none.out" "$T/s3.$m.out" | head -3 | tr '\n' ' ') err: $(diff "$T/s3.none.err" "$T/s3.$m.err" | head -3 | tr '\n' ' ')"; return 1; }; done
  ok "$name ⑦ rc·stdout·stderr = 장부 없음·멈춤과 바이트 같음(멈춤 ${dstuck}s ≤ 없음 ${dnone}s + 호출 ${nc} × 1s + 2s)"
}
export FT_ROOT="$ROOT"   # lib 의 데이터 루트(ft_data_root ①) — comm 은 FT_MBOX_DIR 가 먼저라 r1718 길 불변

if in_part 1; then
# ── ① lib ──
lib() { local b="$1"; shift; bash -c '. "$1/ft-block-lib.sh"; shift; ft_block "$@"; echo "ret=$?"' _ "$b" "$@" > "$T/c.out" 2> "$T/c.err"; RC=$?; }
c1a() { local b="$1"; blr; FT_BLOCK_BIN="$STUB" lib "$b" raise t seat s --cause c --fix f
  eqn "$(bl n)" 1 "호출 1회" && eqn "$(bl a 0)" "raise | t | seat | s | --cause | c | --fix | f" "인자 그대로" && eqn "$(bl root 0)" "$ROOT" "FT20_SCAN_ROOT" \
    && eqn "$(cat "$T/c.out")" "ret=0" "반환 0" && eqn "$(cat "$T/c.err")" "" "stderr 0"; }
c1b() { local b="$1"; blr; lib "$b" raise t seat s --cause c --fix f   # FT_BLOCK_BIN 없음 ∧ 데이터 루트에 block.sh 없음
  eqn "$(bl n)" 0 "호출 0" && eqn "$(cat "$T/c.out")" "ret=0" "반환 0" && eqn "$(cat "$T/c.err")" "" "stderr 0" || return 1
  mkdir -p "$ROOT/.fable-team/state/ft20-r1483-watch" && cp "$STUB" "$ROOT/.fable-team/state/ft20-r1483-watch/block.sh"
  lib "$b" clear t s; rm -rf "$ROOT/.fable-team/state/ft20-r1483-watch"
  eqn "$(bl n)" 1 "기본 자리 block.sh 호출 1회" && eqn "$(bl a 0)" "clear | t | s" "clear 인자" || return 1
  blr; ( unset FT_ROOT; FT_BLOCK_BIN="$STUB" lib "$b" clear t s; cp "$T/c.err" "$T/c.err2" )
  eqn "$(bl n)" 0 "데이터 루트 못 풂 = 호출 0" && eqn "$(cat "$T/c.err2")" "" "stderr 0"; }
c1c() { local b="$1"; blr; FT_CRITICAL_OFF=1 FT_BLOCK_BIN="$STUB" lib "$b" raise t seat s --cause c --fix f; eqn "$(bl n)" 0 "OFF = 호출 0"; }
c1d() { local b="$1" long; long="$(printf 'ㄱ%.0s' $(seq 1 200))"; blr
  FT_BLOCK_BIN="$STUB" lib "$b" raise t seat s --cause "$long" --fix f
  eqn "$(bl opt 0 --cause | python3 -c 'import sys;print(len(sys.stdin.read().rstrip("\n")))')" 160 "200자 → 160자" || return 1
  blr; FT_BLOCK_BIN="$STUB" lib "$b" raise t seat s --cause $'첫 줄\n둘째 줄' --fix f; eqn "$(bl opt 0 --cause)" "첫 줄" "첫 줄만"; }
tc "① lib 인자 그대로 1회 · FT20_SCAN_ROOT · 반환 0 · stderr 0" c1a
tc "① 장부 없음 = 호출 0 · 기본 자리 block.sh · 데이터 루트 못 풂 = 호출 0" c1b
tc "① FT_CRITICAL_OFF=1 = 호출 0" c1c
tc "① 원인 200자 → 160자 · 줄바꿈 → 첫 줄" c1d
step ①
# ── ② lib 실패·멈춤 ──
c2a() { local b="$1"; blr; FT_BLOCK_BIN="$STUB" BLK_RC=9 BLK_ERR="스텁 오류 글" lib "$b" clear t s
  eqn "$(bl n)" 1 "호출 1" && eqn "$(cat "$T/c.out")" "ret=0" "rc 9 → 반환 0" && eqn "$(cat "$T/c.err")" "" "stderr 0"; }
c2b() { local b="$1" t0 dt; blr; t0=$SECONDS
  FT_BLOCK_BIN="$STUB" BLK_FIFO="$FIFO" "$TO" 12 bash -c '. "$1/ft-block-lib.sh"; ft_block clear t s; echo "ret=$?"' _ "$b" > "$T/c.out" 2>&1; dt=$((SECONDS - t0)); unstick
  eqn "$(cat "$T/c.out")" "ret=0" "멈춤 → 반환 0" && [ "$dt" -le 9 ] || { echo "    경과 ${dt}s > 상한 7+2" >&2; return 1; }; }
tc "② 스텁 rc 9 + stderr → 반환 0 · 부른 쪽 stderr 0" c2a
tc "② 스텁 멈춤 → 상한 7초 + 2초 안 반환 0" c2b
step ②
# ── ③④ --wrap ──
wcase() {   # wcase <bin> <mode> — WTOOL·WRC·WOUT·WARGS 로 감싸기 1회
  local b="$1" m="$2"; fresh; printf '%s' "$WOUT" > "$FAKE_OUT"
  env $(benv "$m") FAKE_RC="$WRC" bash "$b/ft-critical-notify.sh" --wrap "$WTOOL" "$T/fake-main.sh" $WARGS > "$T/c.out" 2> "$T/c.err"; RC=$?; }
W() { WTOOL="$1"; WRC="$2"; WOUT="$3"; WARGS="${4:-s1 --reason r}"; }
FIX3="판정 필요 ft-seat-close rc 3 — 원인을 고친 뒤 같은 명령 다시"
c3a() { local b="$1"; W ft-seat-close 3 $'HELD s1 재개 기록 실패 — 시험\n그 밖 줄\n'; blr; wcase "$b" stub
  eqn "$RC" 3 "wrap rc" && eqn "$(cat "$T/c.out")" "$(printf '%s' "$WOUT")" "stdout 그대로" && eqn "$(bl n)" 1 "raise 1회" \
    && eqn "$(bl a 0)" "raise | ft-seat-close | seat | s1 | --cause | HELD s1 재개 기록 실패 — 시험 | --fix | $FIX3" "인자"; }
c3b() { local b="$1"; W ft-seat-close 3 $'CLOSED-SESSION s1 x kill=held(attached)\nNORECORD s1 기록 0\n'; blr; wcase "$b" stub
  eqn "$(bl n)" 1 "raise 1회" && eqn "$(bl opt 0 --cause)" "CLOSED-SESSION s1 x kill=held(attached)" "원인 = kill=held 줄"; }
c4a() { local b="$1"; W ft-nano-close 4 $'앞 줄\nWAIT --replan: 계보 세션 살아 있음(x)\n'; blr; wcase "$b" stub
  eqn "$RC" 4 "rc" && eqn "$(bl n)" 1 "raise 1회" && eqn "$(bl a 0)" "raise | ft-nano-close | seat | s1 | --cause | WAIT --replan: 계보 세션 살아 있음(x) | --fix | 판정 필요 ft-nano-close rc 4 — 원인을 고친 뒤 같은 명령 다시" "인자"; }
c4b() { local b="$1"; W ft-nano-close 99 $'줄 하나\n마지막 줄\n\n'; blr; wcase "$b" stub; eqn "$(bl n)" 1 "raise 1회" && eqn "$(bl opt 0 --cause)" "마지막 줄" "원인 = 마지막 비지 않은 줄"; }
c4c() { local b="$1"; W ft-nano-close 0 $'CLOSED s1\n'; blr; wcase "$b" stub; eqn "$RC" 0 "rc" && eqn "$(bl n)" 1 "호출 1" && eqn "$(bl a 0)" "clear | ft-nano-close | s1" "clear 1회 · raise 0"; }
c4d() { local b="$1"; W ft-seat-close 1 $'REJECT s1\n  - 시험 사유\n'; blr; wcase "$b" stub
  eqn "$RC" 1 "rc" && eqn "$(bl n)" 0 "rc 1 = 장부 0" && eqn "$(nsent)" 1 "[크리티컬] 길 그대로 1통"; }
c4e() { local b="$1"; W ft-nano-close 2 $'usage\n'; blr; wcase "$b" stub; eqn "$RC" 2 "rc" && eqn "$(bl n)" 0 "rc 2 = 장부 0"; }
c4f() { local b="$1"; W ft-merge-land 3 $'HELD x\n' "7"; blr; wcase "$b" stub; eqn "$RC" 3 "rc" && eqn "$(bl n)" 0 "다른 도구 = 장부 0"; }
tc "③ ft-seat-close HELD rc 3 → raise 1회(seat·s1·그 줄) · rc 3 · stdout 그대로" c3a
tc "③ kill=held + NORECORD rc 3 → 원인 = kill=held 줄" c3b
tc "④ ft-nano-close WAIT rc 4 → raise 1회(그 줄)" c4a
tc "④ rc 99 · 표식 줄 없음 → 마지막 비지 않은 줄" c4b
tc "④ rc 0 → clear 1회 · raise 0" c4c
tc "④ rc 1 → 장부 0 · [크리티컬] 그대로(ft-seat-close · A5b 기록 부작용 회피)" c4d
tc "④ rc 2 → 장부 0" c4e
tc "④ ft-merge-land rc 3 → 장부 0" c4f
W ft-seat-close 3 $'HELD s1 재개 기록 실패 — 시험\n'; same3 "③" wcase "$BIN"
W ft-nano-close 0 $'CLOSED s1\n'; same3 "④ rc0" wcase "$BIN"
W ft-seat-close 1 $'REJECT s1\n  - 시험 사유\n'; same3 "④ rc1" wcase "$BIN"
step ③④⑦
# ── 변이 M1~M3(사본만 · 원본 대조) ──
mut ft-critical-notify.sh '       ft_block raise "$tool" seat' '       : ft_block raise "$tool" seat' && killed "M1 wrap raise 지움" c3a
mut ft-critical-notify.sh 'in 0) ft_block clear "$tool" "$t";;' 'in 0) :;;' && killed "M2 rc 0 clear 지움" c4c
mut ft-block-lib.sh 'try: p.wait(timeout=lim)' 'try: p.wait()' && killed "M3 lib 상한 지움" c2b
cp "$BIN/ft-block-lib.sh" "$MB/ft-block-lib.sh"; MUT_FILE=""
step M1~M3
fi

if in_part 2; then
# ── ⑤ ft-successor-open(r1660 시험 틀 · 가짜 tmux·mbox·reach · 가짜 시계) ──
. "$HERE/lib/r1660_successor_env.sh"; trap 'rm -rf "$T" "$TMP"' EXIT
printf 'import sys\nprint("OPEN-WORK 0 받을 일 없음(시험)")\nsys.exit(0)\n' > "$TMP/ow.py"
printf '#!/usr/bin/env bash\nexit 3\n' > "$TMP/send3"; chmod +x "$TMP/send3"
scase() {   # scase <bin> <mode> — SK = ow|budget|hil|ok|rej
  local b="$1" m="$2" ex=() body="$BODY" sv="$FAKE/send"; world; echo 1000 > "$CLK"
  case "$SK" in ow) ex=(FT_SEAT_OPEN_WORK="$TMP/ow.py");; budget) ex=(FT_SO_BUDGET=1);; hil) sv="$TMP/send3"; ex=(REACH_RC=0);; ok) ex=(REACH_RC=0);; rej) body="$TMP/없는-본문";; esac
  env TZ=Asia/Seoul HOME="$TMP/home" PANE_CWD="$REPO" PATH="$FAKE:$PATH" LOG="$LOG" CLK="$CLK" HCNT="$HCNT" PCNT="$PCNT" \
      FT_SO_POLL=0 FT_SO_WAIT_MAX=2 FT_RES_ROOT="$RES" SENSORS="$SENSORS" FT_PI_SESSIONS_DIR="$PI" \
      FT_GOV_MD="$HERE/../../skill/references/main-team-governance.md" FT_SEND_VERIFIED="$sv" \
      FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" FT_SEAT_RETIRE="$FAKE/retire" FT_ROOT="$REPO" \
      $(benv "$m") ${ex[@]+"${ex[@]}"} bash "$b/ft-successor-open.sh" "$OLD" "$REPO" --name "$NEW" --agent codex --model model-x --body-file "$body" > "$T/c.out" 2> "$T/c.err"
  RC=$?; }
FIX6="판정 필요 $OLD 닫기 — ft-seat-close.sh $OLD --reason \"받을 일 0\" --verdict <판정 번호>"
FIX5="같은 인자로 다시 실행 — 그래도 rc 5 면 판정 필요 후계 pane 확인"
c5a() { local b="$1"; SK=ow; blr; scase "$b" stub
  eqn "$RC" 6 "rc" && eqn "$(bl n)" 1 "raise 1회" && inc "$(bl a 0)" "raise | ft-successor-open | seat | $OLD | --cause | OPEN-WORK-0 $OLD — 후계 0(받을 일 0)" "seat·구·원인" \
    && eqn "$(bl opt 0 --fix)" "$FIX6" "해결 길" && inc "$(bl opt 0 --fix)" '--reason "받을 일 0"' "--reason" && inc "$(bl opt 0 --fix)" "--verdict" "--verdict" \
    && exc "$(bl a 0)" "--period" "period 인자" && eqn "$(bl root 0)" "$REPO" "FT20_SCAN_ROOT"; }
c5b() { local b="$1"; SK=budget; blr; scase "$b" stub
  eqn "$RC" 5 "rc" && eqn "$(bl n)" 1 "raise 1회" && inc "$(bl opt 0 --cause)" "시간 상한 1초 — " "원인 «시간 상한 …»" && eqn "$(bl opt 0 --fix)" "$FIX5" "해결 길"; }
c5c() { local b="$1"; SK=hil; blr; scase "$b" stub
  eqn "$RC" 5 "rc" && eqn "$(bl n)" 1 "raise 1회" && inc "$(bl opt 0 --cause)" "[HIL] 후계 $NEW 도달 미확인" "원인 «[HIL] …»" && inc "$(bl a 0)" "| seat | $OLD |" "seat·구"; }
c5d() { local b="$1"; SK=ok; blr; scase "$b" stub; eqn "$RC" 0 "rc" && eqn "$(bl n)" 1 "호출 1" && eqn "$(bl a 0)" "clear | ft-successor-open | $OLD" "clear 1회"; }
c5e() { local b="$1"; SK=rej; blr; scase "$b" stub; eqn "$RC" 1 "rc" && eqn "$(bl n)" 0 "REJECT = 장부 0"; }
tc "⑤ 받을 일 0(rc 6) → raise 1회(seat·구·OPEN-WORK-0 · period 0 · --reason \"받을 일 0\"·--verdict)" c5a
tc "⑤ 시간 상한(rc 5) → raise 1회(원인 «시간 상한 …»)" c5b
tc "⑤ 도달 미확인(rc 5) → raise 1회(원인 «[HIL] …»)" c5c
tc "⑤ 성공(rc 0) → clear 1회" c5d
tc "⑤ REJECT(rc 1) → 장부 0" c5e
for SK in ow budget hil ok rej; do same3 "⑤ $SK" scase "$BIN"; done
step ⑤⑦
fi

if in_part 3; then
# ── ⑥ ft-nano-spawn(r975 시험 틀 축소 · 사본 bin 에 송신·본체·정지 대역 · env -i) ──
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/res" ok
G1='내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고.'
G2='하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.'
G3='메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.'
CLOSE='정본 문구 닫는증거는스무자이상이어야합니다 가나다라마바사'
mkdir -p "$T/fake"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) [ -f "$FAKE_OPENED" ]; exit $?;;
  list-panes) [ -f "$FAKE_OPENED" ] || exit 1; cat "$FAKE_PANES"; exit 0;;
  list-sessions) cat "$FAKE_SESS" 2>/dev/null; exit 0;;
  show-option) echo 1;;
esac
exit 0
EOF
printf '#!/usr/bin/env bash\necho "TMUXC $*"; case " $* " in *" --dry-run "*) ;; *) : > "$FAKE_OPENED";; esac\nexit 0\n' > "$T/fake/tmuxc"
printf '#!/bin/sh\nexit 0\n' > "$T/fake/sleep"
printf '#!/usr/bin/env bash\nif [ "$1 $2" = "ls --names" ]; then printf "byz-harness-master-claude#3\\n"; fi\nexit 0\n' > "$T/fake/tmm"
printf '#!/usr/bin/env bash\necho "{\\"number\\":1,\\"state\\":\\"OPEN\\",\\"url\\":\\"https://github.com/o/r/issues/1\\"}"\n' > "$T/fake/gh-open"
chmod +x "$T/fake/"*; printf '#!/bin/sh\nexit 0\n' > "$T/reclaim.sh"; chmod 755 "$T/reclaim.sh"
NB="$T/nbin"; cp -R "$KIT" "$NB"; rm -rf "$NB/__pycache__"
printf '#!/usr/bin/env bash\nexit "${SV_RC:-0}"\n' > "$NB/ft-send-verified.sh"
printf '#!/usr/bin/env bash\n[ "$1" = --proxy ] && { [ "${PX_RC:-0}" = 0 ] || echo "REJECT 프록시 시험"; exit "${PX_RC:-0}"; }\nexit 0\n' > "$NB/ft-agent-ready.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$NB/ft-all-stop.sh"; chmod +x "$NB/"*.sh
cat > "$T/TEAMSET.md" <<'EOF'
## 표 1 — 역할
| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |
|---|---|---|---|---|---|---|
| nano | 상한 N | `sonnet-5-5` | high | — | a | b |
- 나노 상한 기본: 3
## 표 2 — 팀
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| harness | 1 | 0 | 상시 |
EOF
printf 'byz-harness-nano-a#0\nbyz-harness-nano-b#0\n' > "$T/sess.full"
D="$T/fx"; CARDX="design/harness/indices/대기/x.md"
mkfix() {
  rm -rf "$D"; mkdir -p "$D/.fable-team/state" "$D/.fable-team/comm" "$D/.fable-team/bin-harness" "$D/design/harness/indices/대기" "$D/design/harness/indices/진행" "$D/scripts" "$D/design/v65"
  printf '#!/bin/sh\nexit 0\n' > "$D/scripts/real.sh"; echo x > "$D/design/v65/SEATBELT-README.md"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$D/.fable-team/state/all-stop.log"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$D/design/TEAMS.md"
  printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > "$D/.fable-team/bin-harness/goal-lines.txt"
  printf '# GOAL — harness 제목줄\n\n## 원문 1 머리줄\n> %s\n' "$CLOSE" > "$D/design/harness/GOAL-harness.md"
  printf '# 인덱스: x\n- Issue: #1\n- 제안서: 없음 — 시험용 카드\n- 상태: 대기\n- 선행: 없음\n- 시험 입력: 없음\n- 기준값: 없음 → 대체 축 시험\n- 설치: 없음\n<!-- ledger: design/harness/GOAL-harness.md -->\n\n## 골 원문 (항상 이 3줄)\n%s\n%s\n%s\n\n## 골좌표\n닫는 증거: 「%s」\n\n## 배경\n시험.\n\n## 구현 범위\n1. `scripts/real.sh` 를 고친다.\n\n## 완료 조건\n- 시험 rc=0\n\n## 계약↔시험 대응표\n| 계약 | 시험 |\n|---|---|\n| ① 장부 | ⓐ |\n\n## 상태\n- 대기\n' \
    "$G1" "$G2" "$G3" "$CLOSE" > "$D/$CARDX"
  printf '{"_version":"1.0.0","byz-harness-master-claude#3":{"role":"master"}}\n' > "$D/.fable-team/seats-harness.json"
  printf '{"_version":"1.0.0"}\n' > "$D/.fable-team/seats.json"
  printf "export FT_SEATS_JSON='%s/.fable-team/seats-harness.json'\nexport FT_NANO_PREFIX=byz-harness-nano-\nexport FT_NANO_WT_PREFIX=harness-\nexport FT_GOAL_LEDGER='design/harness/GOAL-harness.md'\nexport FT_GOAL_LINES_FILE='%s/.fable-team/bin-harness/goal-lines.txt'\n" "$D" "$D" > "$D/.fable-team/bin-harness/harness-env.sh"
  git init -q -b main "$D" && git -C "$D" -c user.name=t -c user.email=t@t add -A >/dev/null \
    && git -C "$D" -c user.name=t -c user.email=t@t commit -q -m init && git -C "$D" update-ref refs/remotes/origin/main HEAD
}
ncase() {   # ncase <bin> <mode> — NK = ok|unv|queue|proxy|dry · 매번 같은 경로에 새 픽스처(출력 바이트 대조)
  local b="$1" m="$2" ex=() args=(); mkfix; rm -f "$T/opened"; printf 'byz-harness-nano-x#0|%%1|1\n' > "$T/panes"; mkdir -p "$T/sheet/.fable-team/state"
  case "$NK" in unv) ex=(SV_RC=3);; queue) ex=(FT_TEAMSET=1 FT_TEAMSET_MD="$T/TEAMSET.md" FAKE_SESS="$T/sess.full");; proxy) ex=(PX_RC=1);; dry) args=(--dry-run);; esac
  if [ "$b" = "$BIN" ]; then cp "$BIN/ft-nano-spawn.sh" "$BIN/ft-block-lib.sh" "$NB/"; else cp "$b/ft-nano-spawn.sh" "$b/ft-block-lib.sh" "$NB/"; fi
  ( cd "$D" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_RES_ROOT="$T/res" \
      FT_SHEET_ROOT="$T/sheet" FT_ROOT="$D" FT_RECLAIM_SH="$T/reclaim.sh" FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" BLK_LOG="$BLK_LOG" \
      $(benv "$m") ${ex[@]+"${ex[@]}"} bash "$NB/ft-nano-spawn.sh" "$CARDX" ${args[@]+"${args[@]}"} > "$T/c.out" 2> "$T/c.err" ); RC=$?; }
SEATN='byz-harness-nano-x#0'
c6a() { local b="$1"; NK=unv; blr; ncase "$b" stub
  eqn "$RC" 5 "rc" && eqn "$(bl n)" 1 "raise 1회" && eqn "$(bl a 0)" "raise | ft-nano-spawn | seat | $SEATN | --cause | SPAWNED-UNVERIFIED $SEATN rc=3 — 좌석은 떴다. 도달을 사람이 확인 | --fix | 판정 필요 $SEATN pane 도달 확인 | --period | 900" "인자" \
    && eqn "$(bl root 0)" "$D" "FT20_SCAN_ROOT"; }
c6b() { local b="$1"; NK=queue; blr; ncase "$b" stub
  eqn "$RC" 7 "rc" && eqn "$(bl n)" 1 "raise 1회" && inc "$(bl a 0)" "raise | ft-nano-spawn | card | x | --cause | QUEUED " "card·stem·QUEUED" \
    && eqn "$(bl opt 0 --period)" 900 "period" && eqn "$(bl opt 0 --fix)" "판정 필요 정원·프록시 — 순번 큐가 다음 틱에 다시 시도" "해결 길"; }
c6c() { local b="$1"; NK=proxy; blr; ncase "$b" stub
  eqn "$RC" 7 "rc" && eqn "$(bl n)" 1 "raise 1회" && inc "$(bl opt 0 --cause)" "INFO 프록시 확인 실패" "원인" && inc "$(bl a 0)" "| card | x |" "card·stem"; }
c6d() { local b="$1"; NK=ok; blr; ncase "$b" stub
  eqn "$RC" 0 "rc" && eqn "$(bl n)" 2 "clear 2회" && eqn "$(bl a 0)" "clear | ft-nano-spawn | $SEATN" "새 좌석" && eqn "$(bl a 1)" "clear | ft-nano-spawn | x" "카드 stem"; }
c6e() { local b="$1"; NK=dry; blr; ncase "$b" stub; eqn "$RC" 0 "rc" && eqn "$(bl n)" 0 "dry = 장부 0"; }
tc "⑥ 도달 미확인(rc 5) → raise 1회(seat·새 좌석·--period 900)" c6a
tc "⑥ 정원 포화 큐(rc 7) → raise 1회(card·stem·QUEUED · 900)" c6b
tc "⑥ 프록시 실패 큐(rc 7) → raise 1회(INFO 프록시 확인 실패)" c6c
tc "⑥ SPAWNED(rc 0) → clear 2회(새 좌석 · 카드 stem)" c6d
tc "⑥ --dry-run → 장부 0" c6e
for NK in unv queue ok; do same3 "⑥ $NK" ncase "$BIN"; done
step ⑥⑦
fi

# ── ⑧ 인자 문법(전체 누적) · 사본 cmp ──
blr; eqn "$(BLK_LOG="$ALLLOG" bl bad)" 0 "규칙 어긋남" && ok "⑧ 모든 호출 $(BLK_LOG="$ALLLOG" bl n)회 block.sh 인자 규칙 통과(rc 2 0 · 빈 칸 0)" || bad "⑧ 규칙 어긋난 호출 $(BLK_LOG="$ALLLOG" bl bad)회" "$(grep '"ok": false' "$ALLLOG" | head -2)"
for f in ft-block-lib.sh ft-critical-notify.sh ft-successor-open.sh ft-nano-spawn.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "사본 cmp 0 $f" || bad "사본 다름 $f"; done
finish
