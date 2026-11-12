#!/usr/bin/env bash
# _reject_critical_r1718_fixture.sh — r1718 시험 2파일 공용 픽스처(source 전용 · 사례 아님).
#   가짜 하네스 루트(.fable-team/comm · seats-planner.json `_desk` · seats-harness.json) + 가짜 mbox(FT_MBOX) + 변이 사본 도우미.
#   실 명부·실 우편함·실 state·실 tmux 0 · sleep 0. 부르는 시험이 real_state_guard 를 먼저 건다(git 밖 cwd).
set -uo pipefail
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CRITICAL_OFF FT_CRITICAL_NOW FT_CRITICAL_BUDGET_S FT_CRITICAL_DEDUPE_S FT_CRITICAL_STATE_DIR FT_ROOT FT_SEATS_JSON
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd -- "$HERE/../bin" && pwd)"; KIT="$HERE/../kit/fable-team/bin"
BASE="${FT_TEST_BASE_BIN:-}"   # 고치기 전 판(팩 origin/main bin 사본) — 주면 «기준판 FAIL» 대조도 돈다
fail=0; T_START=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1 :: ${2:-}"; fail=$((fail+1)); }
eqn() { [ "$1" = "$2" ] || { echo "    $3 got=[${1:0:400}] want=[${2:0:400}]" >&2; return 1; }; }          # 사례 함수 안 대조 — 어긋나면 사유 1줄 + rc 1
inc() { case "$1" in *"$2"*) return 0;; esac; echo "    $3 없음: «$2» ← ${1:0:400}" >&2; return 1; }
exc() { case "$1" in *"$2"*) echo "    $3 있으면 안 됨: «$2» ← ${1:0:400}" >&2; return 1;; esac; return 0; }
tc() { local n="$1" fn="$2"; shift 2; if "$fn" "$BIN" "$@"; then ok "$n"; else bad "$n" "$fn"; fi; }   # tc <이름> <사례 함수> — 원본 BIN 으로 1회
basefail() { [ -n "$BASE" ] || { echo "SKIP $1 기준판 대조(FT_TEST_BASE_BIN 없음)"; return 0; }; if "$2" "$BASE" >/dev/null 2>&1; then bad "$1 — 기준판에서 PASS(고치기 전에도 통과 = 시험이 못 가름)"; else ok "$1 기준판 FAIL(정상)"; fi; }
finish() { echo "단계별 초: 전체=$((SECONDS - T_START))s${STEPS:+ ·$STEPS}"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }; }
STEPS=""; step() { STEPS="$STEPS $1=$((SECONDS - ${_S0:-$T_START}))s"; _S0=$SECONDS; }   # 단계별 초(하드 룰 22)
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
ROOT="$T/root"; STATE="$ROOT/.fable-team/state"; PEND="$STATE/critical-pending.jsonl"; SENT="$STATE/critical-sent.jsonl"
DESK='byz-planner-desk-pi#9'; SEAT='byz-harness-nano-k#0'
mkdir -p "$ROOT/.fable-team/comm"
# 가짜 mbox — 발신 1건 = MLOG 1줄(받는 이·보내는 이·본문 탭 구분) · 호출마다 MCALLS 1줄 · MBOX_RC≠0 = 실패 주입 · MBOX_GATE = 그 FIFO 가 열릴 때까지 멈춤(F1)
cat > "$T/mbox.sh" <<'EOF'
#!/usr/bin/env bash
echo x >> "$MCALLS"
[ -z "${MBOX_GATE:-}" ] || { echo up > "$MBOX_GATE.up"; read -r _ < "$MBOX_GATE"; }
[ "${MBOX_RC:-0}" = 0 ] || exit "$MBOX_RC"
n=$(( $(grep -c . "$MLOG") + 501 ))
printf '%s\t%s\t%s\n' "$2" "$3" "$4" >> "$MLOG"; echo "QUEUED seq=$n to=$2"
EOF
export FT_MBOX="$T/mbox.sh" FT_MBOX_DIR="$ROOT/.fable-team/comm" MLOG="$T/mlog" MCALLS="$T/mcalls"
roster() {   # roster [desk 좌석] — 빈 값 = `_desk` 칸 없는 명부
  if [ -n "${1:-}" ]; then printf '{"_master":"byz-planner-master-pi#1","_desk":"%s"}\n' "$1"; else printf '{"_master":"byz-planner-master-pi#1"}\n'; fi > "$ROOT/.fable-team/seats-planner.json"
}
card() { printf '{"%s":{"role":"nano","agent":"pi","index":"design/harness/indices/진행/%s.md"}}\n' "$SEAT" "$1" > "$ROOT/.fable-team/seats-harness.json"; }   # 그 좌석의 명부 index 카드
fresh() { rm -rf "$STATE" "$T/sstate"; : > "$MLOG"; : > "$MCALLS"; roster "$DESK"; card k; }
nsent() { grep -c '\[크리티컬\]' "$MLOG"; }                       # desk 우편함 [크리티컬] 통 수
ncall() { grep -c . "$MCALLS"; }                                  # mbox 호출(시도) 수
npend() { local n; n="$(grep -c . "$PEND" 2>/dev/null)"; echo "${n:-0}"; }
last()  { tail -n1 "$MLOG"; }
cn() { local b="$1"; shift; bash "$b/ft-critical-notify.sh" "$@"; }   # cn <bin> <인자…>
# 변이 사본 — 원본 BIN 은 그대로 두고 사본 MB 의 파일 하나만 바꾼다(변이 뒤 bin·kit cmp0 은 시험 끝에서 본다)
MB="$T/mbin"; MUT_FILE=""
mut() {   # mut <파일> <옛 글> <새 글> [<옛 글> <새 글>…] — 옛 글은 정확히 1곳이어야 한다
  [ -d "$MB" ] || cp -R "$BIN" "$MB"
  [ -z "$MUT_FILE" ] || cp "$BIN/$MUT_FILE" "$MB/$MUT_FILE"
  MUT_FILE="$1"; shift
  python3 - "$MB/$MUT_FILE" "$@" <<'PY' || { bad "변이 패턴 없음($MUT_FILE)" "$1"; return 1; }
import io, sys
p, pairs = sys.argv[1], sys.argv[2:]; s = io.open(p, encoding="utf-8").read()
for a, b in zip(pairs[0::2], pairs[1::2]):
    if s.count(a) != 1: sys.exit(3)
    s = s.replace(a, b)
io.open(p, "w", encoding="utf-8").write(s)
PY
}
# 변이 대조 — 변이 사본에서 사례가 FAIL(rc≠0) 이고, 원본 BIN 으로 같은 사례를 1회 더 돌리면 PASS(rc 0) 여야 한다
killed() {   # killed <변이 이름> <사례 함수> [인자…]
  local name="$1" fn="$2"; shift 2
  [ -n "$MUT_FILE" ] && ! cmp -s "$BIN/$MUT_FILE" "$MB/$MUT_FILE" || { bad "$name — 변이 사본이 원본과 같음($MUT_FILE)"; return; }
  cmp -s "$BIN/$MUT_FILE" "$KIT/$MUT_FILE" || bad "$name — 변이 뒤 bin·kit 다름($MUT_FILE)"
  if "$fn" "$MB" "$@" >/dev/null 2>&1; then bad "$name — 변이가 살아남음($fn 이 못 잡음)"; return; fi
  if "$fn" "$BIN" "$@" >/dev/null 2>&1; then ok "$name → $fn FAIL · 원본 대조 PASS"; else bad "$name — 원본 BIN 대조가 FAIL($fn)"; fi
}
# 가짜 본 작업(--wrap 대상) — stdout 은 FAKE_OUT 파일 그대로 · rc = FAKE_RC · 실행마다 FAKE_RUNS 1줄 · FAKE_HEAD 가 있으면 감싼 쪽에 PR head 를 넘긴다 · FAKE_GATE = 첫 줄을 낸 뒤 그 FIFO 가 열릴 때까지 멈춤(⑭ 나오는 때)
cat > "$T/fake-main.sh" <<'EOF'
#!/usr/bin/env bash
echo x >> "$FAKE_RUNS"
[ -z "${FAKE_HEAD:-}" ] || [ -z "${FT_CRITICAL_CTX:-}" ] || printf '%s\n' "$FAKE_HEAD" > "$FT_CRITICAL_CTX"
[ -z "${FAKE_ERR:-}" ] || printf '%s' "$FAKE_ERR" >&2
if [ -n "${FAKE_GATE:-}" ]; then head -n1 "$FAKE_OUT"; read -r _ < "$FAKE_GATE"; tail -n +2 "$FAKE_OUT"; else cat "$FAKE_OUT"; fi
exit "${FAKE_RC:-1}"
EOF
export FAKE_RUNS="$T/fake.runs" FAKE_OUT="$T/fake.out"
wrap() { local b="$1" tool="$2"; shift 2; bash "$b/ft-critical-notify.sh" --wrap "$tool" "$T/fake-main.sh" "$@"; }   # wrap <bin> <도구> <인자…>
# Scan.critical(auto_close() 줄) 1회 — 실 명부·tmux·좌석 0. SCAN_NOW = 가짜 시각 · FT_NANO_AUTO_CLOSE 는 부르는 쪽이 정한다
scan() {   # scan <bin>
  FT_ROOT="$ROOT" FT_STALL_STATE_DIR="$T/sstate" FT_NANO_CLOSE_DUE="$T/cd.sh" FT_NANO_CLOSE="$T/nc.sh" python3 - "$1/ft_stall_scan.py" <<'PY'
import importlib.util, os, pathlib, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(sys.argv[1])))
spec = importlib.util.spec_from_file_location("sa", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
o = object.__new__(m.Scan); o.state_dir = pathlib.Path(os.environ["FT_STALL_STATE_DIR"]); o.now = float(os.environ.get("SCAN_NOW") or 1000)
o.mbox, o.comm = os.environ["FT_MBOX"], pathlib.Path(os.environ["FT_MBOX_DIR"]); o.state_dir.mkdir(parents=True, exist_ok=True)
o.critical(o.auto_close())
PY
}
