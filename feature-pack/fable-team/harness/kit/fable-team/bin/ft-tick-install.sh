#!/bin/bash
# ft-tick-install.sh — Seatbelt 0.4 통합 틱을 launchd 에 설치/제거 (KeepAlive 가 생존을 맡는다)
#   설치:  ft-tick-install.sh [--worktree DIR] [--script PATH] [--dry-run]
#          → ft-tick.plist 템플릿을 python plistlib 로 읽어 «값(dict)으로» 넣는다(r962 r3 — 글자 치환 0)
#            → ~/Library/LaunchAgents/com.byz.ft-tick.plist
#          → plutil -lint → launchctl bootstrap gui/$UID → launchctl print 로 state 출력
#          r459: WorkingDirectory = git 공용 루트 · env FT_TICK_MBOX·FT_MBOX_DIR·FT_TICK_AGENT_ALIVE = 공용 루트 comm(__COMM__) · dry-run + FT_TICK_PRINT_PLIST=1 = 렌더본 출력
#   제거:  ft-tick-install.sh --uninstall   → launchctl bootout gui/$UID/com.byz.ft-tick + plist 삭제
#   ★팀 틱 (R199)★  ft-tick-install.sh --team <팀> [--script PATH] [--from <plist>] [--dry-run]   (--script 생략 = 메인 plist 의 스크립트)
#   ★r962 시작 경로 (두 갈래 공통)★ 시작 경로(--script · 메인 plist 값)를 «실제 경로» 로 푼 뒤
#     <공용 루트>/.fable-team/bin/ 아래가 아니면 ERROR 1줄 + rc1 (plist 쓰기 0) — 워크트리·키트·설치본 경로는 전부 거절.
#     공용 루트 = 스크립트 폴더의 git 공용 루트(없으면 --worktree/cwd 의 공용 루트). 글자 교체·자동 고침 0.
#          → 그 팀의 «지금 plist»(또는 --from) 를 바탕으로 ProgramArguments[1] = 공용 ft-tick.sh · team-tick-env.tsv 의 팀 값(STATE_DIR) + 끌 전역 감시(값 0) + FT_TICK_FIRE_V2=1 을 더한 plist 를 만든다.
#            기존 env 키는 전부 보존(MASTER/PM 문구·간격·좌석표·pidfile·stamp 등) — 단 FT_TICK_SEAT_STATUS 는 공용 bin 폴더의 ft-seat-status.sh 로 바꾼다(팀 폴더 사본은 구판이라 `turn`·`jsonl` 이 없다).
#            --dry-run = 새 plist 내용만 출력(쓰기·launchctl 0) · 설치 = 백업 <plist>.bak-r199 → 쓰기 → plutil -lint → bootout/bootstrap(FT_TICK_LAUNCHCTL) · 이미 같으면 건너뜀.
#   ★기존 ft-pm-tick.sh / ft-master-tick.sh 프로세스는 건드리지 않는다★ — 전환(구 데몬 정지)은 사람이
#   SEATBELT-README §4-2 절차대로 한다. 설치 직후엔 틱이 2중으로 갈 수 있다(그래서 실전은 master 소관).
set -uo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; export PATH
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LABEL="com.byz.ft-tick"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
TEMPLATE="$HERE/ft-tick.plist"
DOMAIN="gui/$(id -u)"
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; SCRIPT=""; DRY=0; UNINSTALL=0; TEAM=""; FROM=""
while [ $# -gt 0 ]; do case "$1" in
  --worktree) WT="$2"; shift 2;; --script) SCRIPT="$2"; shift 2;; --dry-run) DRY=1; shift;; --uninstall) UNINSTALL=1; shift;;
  --team) TEAM="$2"; shift 2;; --from) FROM="$2"; shift 2;;
  *) echo "usage: $0 [--worktree DIR] [--script PATH] [--dry-run] | --uninstall | --team <팀> [--script PATH] [--from <plist>] [--dry-run]" >&2; exit 2;; esac; done

# ── r962: 시작 경로 검사 — 메인·팀 «두 갈래가 같은 함수» ─────────────────────────────────────
#   ft_tick_root_bin_script <경로> → OK: 실제 경로 1줄 stdout rc0 · 밖: "ERROR …" 1줄 stdout rc1 (plist 쓰기 0)
#   실제 경로 = 링크 사슬을 끝까지 푼 파일 경로(상대 경로·`..` 포함) · 경계는 «그 실제 파일의 부모 폴더»(`cd -P`)로만 판정한다
#   (링크가 놓인 폴더·그 리포는 판정에 쓰지 않는다 — DA⑥ r2 반례: 별도 리포의 링크 → 루트 bin 파일을 거절했다).
#   경계 = <공용 루트>/.fable-team/bin/ 아래 — 공용 루트 = 실제 파일 폴더의 git 공용 루트(없으면 $WT 의 공용 루트)를 `cd -P` 로 푼 값.
#   글자 교체·자동 고침 0 — 밖이면 거절만 한다(DA 반례: 상대 경로를 글자로 바꾸면 plist 에 v6 경로가 남는다).
# ── r962 r3: plist 렌더 = 함수 1개 (python plistlib — «값으로 넣기» · 글자 치환 0) ──────────────────
#   ft_tick_render_plist <main|team> <원본 plist> <출력 파일>  → rc0 = 파일 씀 · rc≠0 = stdout 1줄 + 파일 쓰기 0
#   값은 env 로 넘긴다 — FT_R_SCRIPT(시작 경로 실제 경로) · 메인은 FT_R_COMMON·FT_R_COMM · 팀은 FT_R_TEAM·FT_R_TSV·FT_R_SRCMODE(own|from)
#   틀의 자리표시자(__WORKTREE__ · __SCRIPT__ · __COMM__)는 «어느 키에 어떤 값을 넣을지» 표식으로만 읽는다 —
#   메인 틀의 값을 넣는 자리 다섯(WorkingDirectory · ProgramArguments[1] · env FT_TICK_MBOX · FT_MBOX_DIR · FT_TICK_AGENT_ALIVE).
#   모르는 표식(__X__)이나 표식이 남는 자리 = rc≠0 (fail-closed — 검사가 끝난 뒤에만 쓰므로 반쪽 plist 0).
#   ★r5: 잔재 판정 2규칙★ 거절 = ① 렌더가 채우는 틀 칸 경로( fills )의 값이 렌더 뒤에도 표식 ② 어느 칸이든 값 «전체» 가 표식 하나
#     사용자 글자 안에 표식이 섞인 것(폴더 root__SCRIPT__ · 파일 goal__SCRIPT__.sh · 경로 /tmp/__X__.log)은 값 그대로 통과한다 — 아는/모르는 표식을 가리지 않는다
#     (DA⑥ r3·r4 HOLD 반례: 값 «안» 글자로 틀 자리를 재판해 사용자 값을 거절했다 · 리서치 ff411bdfd3 §1-5 안 B).
#     남는 오탐 1 = 사용자가 값 전체를 __FOO__ 로 둔 경우 → fail-closed 로 거절(계약 명시).
#   ★메인·팀 두 갈래가 «이 함수 하나» 를 지난다★ (r784 r1 두 벌 렌더 → r962 r3 한 벌 · & \ | < 공백이 값 그대로 남는다)
ft_tick_render_plist() {
  FT_R_MODE="$1" FT_R_SRC="$2" FT_R_OUT="$3" python3 - <<'PY'
import os, plistlib, re, sys

mode = os.environ["FT_R_MODE"]; src = os.environ["FT_R_SRC"]; out = os.environ["FT_R_OUT"]
script = os.environ.get("FT_R_SCRIPT", "")
TOK = re.compile(r"__[A-Z][A-Z0-9_]*__")   # 값 «전체» 판정에만 쓴다(r5) — 값 안 글자는 보지 않는다

def die(m):
    print(m); sys.exit(1)

def walk(node, path=()):
    if isinstance(node, dict):
        for k, v in node.items(): yield from walk(v, path + (k,))
    elif isinstance(node, list):
        for i, v in enumerate(node): yield from walk(v, path + (i,))
    elif isinstance(node, str):
        yield path, node

def show(p): return "/".join(str(x) for x in p)

if not os.path.isfile(src): die("REJECT 원본 plist 없음: %s" % src)
try:
    with open(src, "rb") as f: d = plistlib.load(f)
except Exception as e:
    die("REJECT 원본 plist 를 못 읽음(%s: %s): %s" % (type(e).__name__, src, e))
if not isinstance(d, dict): die("REJECT 원본 plist 가 dict 가 아니다: %s" % src)
env = dict(d.get("EnvironmentVariables") or {}); d["EnvironmentVariables"] = env

# ── 값을 넣는 자리(fills = 경로→값) · 표식은 여기에만 둘 수 있다
set_keys = set()
if mode == "main":
    common = os.environ["FT_R_COMMON"]; comm = os.environ["FT_R_COMM"]
    fills = {
        ("WorkingDirectory",): common,
        ("ProgramArguments", 1): script,
        ("EnvironmentVariables", "FT_TICK_MBOX"): os.path.join(comm, "mbox.sh"),
        ("EnvironmentVariables", "FT_MBOX_DIR"): comm,
        ("EnvironmentVariables", "FT_TICK_AGENT_ALIVE"): os.path.join(comm, "ft-agent-alive.sh"),
    }
elif mode == "team":
    team = os.environ["FT_R_TEAM"]; tsv = os.environ["FT_R_TSV"]
    srcmode = os.environ.get("FT_R_SRCMODE", "own")
    row = None
    for ln in open(tsv, encoding="utf-8"):
        if ln.startswith("#") or not ln.strip(): continue
        c = ln.rstrip("\n").split("\t")
        if len(c) != 7: die("REJECT 팀 표 줄의 열이 7개가 아니다: " + ln[:60])
        if c[0] == team: row = c
    if row is None: die("REJECT 팀 표에 팀이 없다: " + team)
    _, seats, state, pidf, stamp, off, on = row
    for k in ("FT_TICK_MASTER_MSG", "FT_TICK_PM_MSG"):
        if k not in env: die("REJECT 원본 plist 에 %s 가 없다 — 메인 문구로 돌게 된다: %s" % (k, src))
    want = {"FT_TICK_PIDFILE": pidf, "FT_TICK_STAMP_PREFIX": stamp, "FT_TICK_STATE_DIR": state}
    if srcmode == "own":
        for k, v in want.items():
            if env.get(k) not in (None, v): die("REJECT plist %s=%s ≠ 표 %s — 사람 확인" % (k, env.get(k), v))
        cur = env.get("FT_TICK_SEATS")
        if cur is not None and os.path.basename(cur) != seats: die("REJECT plist FT_TICK_SEATS=%s ≠ 표 %s — 사람 확인" % (cur, seats))
    ss = os.path.join(os.path.dirname(script), "ft-seat-status.sh")
    if not os.path.isfile(ss): die("REJECT 공용 bin 폴더에 ft-seat-status.sh 없음: %s (팀 폴더 사본은 구판 — turn·jsonl 없음)" % ss)
    on_kv = [kv.partition("=") for kv in filter(None, on.split(","))]
    off_keys = [k for k in filter(None, off.split(","))]
    fills = {("ProgramArguments", 1): script, ("Label",): "com.byz.ft-tick-" + team}
    if srcmode == "from":
        for k in ("StandardOutPath", "StandardErrorPath"): fills[(k,)] = "/tmp/ft-tick-%s.log" % team
    set_keys = set(want) | {"FT_TICK_SEAT_STATUS", "FT_TICK_SEATS"} | {k for k, _, _ in on_kv} | set(off_keys)
else:
    die("REJECT 렌더 모드가 main|team 이 아니다: %s" % mode)

# ── 표식 잔재 = fail-closed, «칸 전체가 표식» 만 (r5 고침 1 · REWORK-r962-r5 · 리서치 §1-5 안 B)
#   잔재 = ① 값 «전체» 가 표식 하나와 정확히 같은 칸 ② 렌더 뒤에도 틀 칸(fills)이 표식인 채 남은 경우
#   잔재 아님 = 표식 글자가 사용자 경로·env 글자 안에 섞인 것(root__SCRIPT__ · goal__SCRIPT__.sh · /tmp/__X__.log)
#   «칸 전체» = 값 그대로(앞뒤 공백 포함) — 다듬지 않고 비교한다(r6 고침 · 앞뒤 공백이 있으면 표식 하나만의 값이 아니다).
#   판정 근거는 «값 모양» 뿐이다 — 틀 파일과 --from·기존 plist 를 값으로 구분할 수 없기 때문(틀 값은 언제나 표식 하나가 전부).
def residual(p, v):
    if TOK.fullmatch(v):
        return "REJECT 표식이 남는 자리: %s = %s — 표식은 «값을 넣는 자리» 에만 둔다" % (show(p), v)
    return None

def scan(node, where, skip_fills=True):
    for p, v in walk(node):
        if skip_fills and p in fills: continue
        if skip_fills and len(p) == 2 and p[0] == "EnvironmentVariables" and p[1] in set_keys: continue
        m = residual(p, v)
        if m: die("%s — %s" % (m, where))

scan(d, "원본 검사에서 멈춤 · 파일 쓰기 0")

# ── 값 넣기 (글자 치환 0 — dict 에 값으로)
#   ProgramArguments = 옛 판(1545012e)과 같게 «두 번째 칸부터 끝까지를 [script] 로 대체»(뒤 인자 삭제 · 빈 배열은 [bash, script])
for p, v in fills.items():
    node = d
    try:
        for k in p[:-1]: node = node[k]
        if p[0] == "ProgramArguments" and isinstance(node, list):
            node[:] = (node[:1] or ["/opt/homebrew/bin/bash"]) + [v]
            continue
        if isinstance(node, list):
            while len(node) <= p[-1]: node.append("")
        node[p[-1]] = v
    except (KeyError, IndexError, TypeError):
        die("REJECT 원본 plist 에 값을 넣을 자리가 없다: %s (%s)" % (show(p), src))
if mode == "team":
    if srcmode == "from":
        env["FT_TICK_SEATS"] = os.path.join(os.path.dirname(env.get("FT_TICK_SEATS", "")) or os.path.dirname(os.path.dirname(script)), seats)
    env.update(want)
    for k in off_keys: env[k] = "0"
    for k, _, v in on_kv: env[k] = v
    env["FT_TICK_SEAT_STATUS"] = ss

# ── dump → 재해석 → 잔재 재검사 → 그때만 파일 쓰기
try:
    data = plistlib.dumps(d, fmt=plistlib.FMT_XML)
    back = plistlib.loads(data)
except Exception as e:
    die("REJECT 렌더 실패(%s) — 파일 쓰기 0: %s" % (type(e).__name__, out))
scan(back, "렌더본에 표식이 남았다 · 파일 쓰기 0", skip_fills=False)   # r5: 틀 칸도 «값 전체가 표식» 이면 거절(안 채운 자리)
try:
    with open(out, "wb") as f: f.write(data)
except OSError as e:
    die("REJECT 렌더본 쓰기 실패(%s: %s): %s" % (type(e).__name__, e, out))
PY
}

ft_tick_root_bin_script() {
  local p="$1" dir real root
  [ -n "$p" ] || { echo "ERROR 시작 경로가 비었다 — <공용 루트>/.fable-team/bin/ft-tick.sh 를 준다"; return 1; }
  real="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$p" 2>/dev/null)"
  [ -n "$real" ] || { echo "ERROR 시작 경로를 실제 경로로 못 푼다: $p"; return 1; }
  dir="$(cd -- "$(dirname -- "$real")" 2>/dev/null && pwd -P)" || { echo "ERROR 시작 경로의 부모 폴더를 못 연다: $p"; return 1; }
  real="$dir/$(basename -- "$real")"
  root="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  root="${root%/.git}"
  [ -n "$root" ] && [ -d "$root" ] || { echo "ERROR 공용 루트를 못 풂 — git 공용 루트 없음($dir · $WT)"; return 1; }
  root="$(cd -- "$root" && pwd -P)"
  case "$real" in
    "$root"/.fable-team/bin/?*) printf '%s\n' "$real"; return 0;;
  esac
  echo "ERROR 시작 경로가 공용 루트 bin 밖이다: $real — 허용 = $root/.fable-team/bin/ 아래(워크트리·키트·설치본 경로 0)"
  return 1
}

# ── ★팀 틱 (R199)★ ────────────────────────────────────────────────────────────────────────────
if [ -n "$TEAM" ]; then
  [ "$UNINSTALL" = 0 ] || { echo "usage: --team 과 --uninstall 은 같이 못 쓴다" >&2; exit 2; }
  TSV="${FT_TICK_TEAM_TSV:-$HERE/team-tick-env.tsv}"; PDIR="${FT_TICK_PLIST_DIR:-$HOME/Library/LaunchAgents}"; LCTL="${FT_TICK_LAUNCHCTL:-launchctl}"
  PL="$PDIR/com.byz.ft-tick-$TEAM.plist"; [ -f "$TSV" ] || { echo "REJECT 팀 표 없음: $TSV"; exit 1; }
  if [ -z "$SCRIPT" ]; then   # 기본 = 메인 틱 plist 가 가리키는 스크립트(닫히는 워크트리가 아니라 라이브 bin)
    MAINPL="$PDIR/com.byz.ft-tick.plist"
    SCRIPT="$(python3 - "$MAINPL" <<'PY'
import plistlib, sys
try: pa = plistlib.load(open(sys.argv[1], "rb"))["ProgramArguments"]; print(pa[1])
except Exception as e: print("REJECT 메인 plist 에서 스크립트를 못 읽음(%s: %s) — --script 로 준다" % (sys.argv[1], type(e).__name__)); sys.exit(1)
PY
)" || { echo "$SCRIPT"; exit 1; }
  fi
  # r962: 시작 경로 = 실제 경로 기준 «공용 루트 bin 아래» 만 (메인 갈래와 같은 함수 하나 · 글자 교체 0)
  SCRIPT="$(ft_tick_root_bin_script "$SCRIPT")" || { echo "$SCRIPT"; exit 1; }
  [ -f "$SCRIPT" ] || { echo "REJECT ft-tick.sh 없음: $SCRIPT"; exit 1; }
  NEW="$(mktemp /tmp/ft-tick-team-plist.XXXXXX)"; trap 'rm -f "$NEW"' EXIT
  # r962 r3: 팀 갈래도 «같은 렌더 함수» 하나 — 인라인 python 은 함수로 올렸다(값으로 넣기 · 글자 치환 0)
  if ! ROUT="$(FT_R_SCRIPT="$SCRIPT" FT_R_TEAM="$TEAM" FT_R_TSV="$TSV" FT_R_SRCMODE="$([ -n "$FROM" ] && echo from || echo own)" \
        ft_tick_render_plist team "${FROM:-$PL}" "$NEW")"; then
    printf '%s\n' "$ROUT"; rm -f "$NEW"; exit 1
  fi
  plutil -lint "$NEW" >/dev/null || { echo "REJECT 만든 plist lint 실패"; exit 1; }
  if [ "$DRY" = 1 ]; then cat "$NEW"; echo "PLAN team=$TEAM script=$SCRIPT dst=$PL (dry-run · 쓰기·launchctl 0)" >&2; exit 0; fi
  if [ -f "$PL" ] && cmp -s "$NEW" "$PL"; then echo "이미 같음 — 건너뜀: $PL"; exit 0; fi
  mkdir -p "$PDIR"
  if [ -f "$PL" ]; then
    if [ -e "$PL.bak-r199" ]; then echo "REJECT 백업이 이미 있다: $PL.bak-r199 — 사람 확인(되돌림 전 덮어쓰기 0)"; exit 1; fi
    cp -p "$PL" "$PL.bak-r199" || { echo "REJECT 백업 실패"; exit 1; }
  fi
  cp "$NEW" "$PL" || { echo "REJECT plist 쓰기 실패: $PL"; exit 1; }
  "$LCTL" bootout "$DOMAIN/com.byz.ft-tick-$TEAM" >/dev/null 2>&1 || true
  "$LCTL" bootstrap "$DOMAIN" "$PL" || { echo "REJECT bootstrap 실패 — 되돌림: cp -p $PL.bak-r199 $PL 후 다시 bootstrap"; exit 1; }
  echo "installed com.byz.ft-tick-$TEAM → $PL (script=$SCRIPT · 되돌림 백업 $PL.bak-r199)"; exit 0
fi

if [ "$UNINSTALL" = 1 ]; then
  if [ "$DRY" = 1 ]; then echo "PLAN launchctl bootout $DOMAIN/$LABEL && rm -f $PLIST_DST"; exit 0; fi
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null && echo "bootout $LABEL OK" || echo "bootout $LABEL — not loaded (무시)"
  rm -f "$PLIST_DST"; echo "removed $PLIST_DST"; exit 0
fi

[ -d "$WT" ]       || { echo "REJECT 워크트리 없음: $WT"; exit 1; }
# r459: 메인 plist 도 팀 plist 와 같은 틀 — WorkingDirectory = git 공용 루트 · 우편함·판정기 env = 공용 루트 comm(옛 라이브 워크트리 comm 0)
COMMON="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; COMMON="${COMMON%/.git}"
[ -n "$COMMON" ] && [ -d "$COMMON/.fable-team/comm" ] || { echo "REJECT 공용 루트 comm 없음: ${COMMON:-<git 밖>}/.fable-team/comm ($WT)"; exit 1; }
COMM="$COMMON/.fable-team/comm"
# 시작 경로 기본값 = 공용 루트 bin(r962) — 없으면 옛 자리 두 개를 그대로 집어 보고, 검사 함수가 REJECT 한다.
if [ -z "$SCRIPT" ]; then
  if [ -f "$COMMON/.fable-team/bin/ft-tick.sh" ]; then SCRIPT="$COMMON/.fable-team/bin/ft-tick.sh"
  elif [ -f "$WT/.fable-team/bin/ft-tick.sh" ]; then SCRIPT="$WT/.fable-team/bin/ft-tick.sh"
  else HR="$([ -f "$HERE/ft-harness-root.sh" ] && . "$HERE/ft-harness-root.sh" && ft_harness_root "$HERE")"; SCRIPT="${HR:+$HR/bin/ft-tick.sh}"; fi
fi
[ -f "$TEMPLATE" ] || { echo "REJECT 템플릿 없음: $TEMPLATE"; exit 1; }
[ -f "$SCRIPT" ]   || { echo "REJECT ft-tick.sh 없음: $SCRIPT"; exit 1; }
[ -x /opt/homebrew/bin/bash ] || { echo "REJECT /opt/homebrew/bin/bash 없음 (plist ProgramArguments)"; exit 1; }
# r962: 시작 경로 검사(두 갈래 공통 함수) — 공용 루트 bin 밖이면 plist 쓰기 0
SCRIPT="$(ft_tick_root_bin_script "$SCRIPT")" || { echo "$SCRIPT"; exit 1; }

render() { ft_tick_render_plist main "$TEMPLATE" "$1"; }
if [ "$DRY" = 1 ]; then
  TMP="$(mktemp /tmp/ft-tick-plist.XXXXXX)" || { echo "REJECT mktemp 실패"; exit 1; }
  if ! ROUT="$(FT_R_SCRIPT="$SCRIPT" FT_R_COMMON="$COMMON" FT_R_COMM="$COMM" render "$TMP")"; then
    printf '%s\n' "$ROUT"; rm -f "$TMP"; exit 1
  fi
  plutil -lint "$TMP" >/dev/null && echo "PLAN plist lint OK · script=$SCRIPT · cwd=$COMMON · comm=$COMM · dst=$PLIST_DST · bootstrap $DOMAIN" || { echo "REJECT 렌더된 plist lint 실패: $TMP"; rm -f "$TMP"; exit 1; }
  [ -z "${FT_TICK_PRINT_PLIST:-}" ] || cat "$TMP"
  rm -f "$TMP"; exit 0
fi

mkdir -p "$(dirname "$PLIST_DST")"
TMP="$(mktemp /tmp/ft-tick-plist.XXXXXX)" || { echo "REJECT mktemp 실패"; exit 1; }
if ! ROUT="$(FT_R_SCRIPT="$SCRIPT" FT_R_COMMON="$COMMON" FT_R_COMM="$COMM" render "$TMP")"; then
  printf '%s\n' "$ROUT"; rm -f "$TMP"; exit 1
fi
plutil -lint "$TMP" >/dev/null || { echo "REJECT 렌더된 plist lint 실패: $TMP"; rm -f "$TMP"; exit 1; }
mv "$TMP" "$PLIST_DST" || { echo "REJECT plist 쓰기 실패: $PLIST_DST"; rm -f "$TMP"; exit 1; }   # r962 r3: 검사 끝난 뒤에만 쓴다(tmp→mv)
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true          # 재설치 허용(이미 떠 있으면 내렸다 올린다)
launchctl bootstrap "$DOMAIN" "$PLIST_DST" || { echo "REJECT bootstrap 실패 — launchctl print $DOMAIN/$LABEL 로 확인"; exit 1; }
sleep 1
launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -E '^\s*(state|pid) ' || echo "WARN launchctl print 에 state/pid 없음"
echo "installed $LABEL → $PLIST_DST (log /tmp/ft-tick.log). ★구 데몬(ft-pm-tick/ft-master-tick)은 그대로다 — README §4-2 전환 절차★"
