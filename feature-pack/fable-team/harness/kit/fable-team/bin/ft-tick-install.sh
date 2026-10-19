#!/bin/bash
# ft-tick-install.sh — Seatbelt 0.4 통합 틱을 launchd 에 설치/제거 (KeepAlive 가 생존을 맡는다)
#   설치:  ft-tick-install.sh [--worktree DIR] [--script PATH] [--dry-run]
#          → ft-tick.plist 템플릿의 __WORKTREE__/__SCRIPT__ 치환 → ~/Library/LaunchAgents/com.byz.ft-tick.plist
#          → plutil -lint → launchctl bootstrap gui/$UID → launchctl print 로 state 출력
#          r459: WorkingDirectory = git 공용 루트 · env FT_TICK_MBOX·FT_MBOX_DIR·FT_TICK_AGENT_ALIVE = 공용 루트 comm(__COMM__) · dry-run + FT_TICK_PRINT_PLIST=1 = 렌더본 출력
#   제거:  ft-tick-install.sh --uninstall   → launchctl bootout gui/$UID/com.byz.ft-tick + plist 삭제
#   ★팀 틱 (R199)★  ft-tick-install.sh --team <팀> [--script PATH] [--from <plist>] [--dry-run]   (--script 생략 = 메인 plist 의 스크립트 · 워크트리·키트 원본 경로는 REJECT)
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
  # `..`·심링크로 허용 패턴을 흉내 내는 경로를 막기 위해 검사 «전에» 실경로로 정규화(r3 · DA⑥ r2 H2 잔여)
  [ -n "$SCRIPT" ] && SCRIPT="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$SCRIPT" 2>/dev/null)" && [ -n "$SCRIPT" ] || { echo "REJECT --script 경로 정규화 실패(빈 값·실패)"; exit 1; }
  case "$SCRIPT" in   # 팀 plist 가 닫히는 워크트리·키트 원본을 가리키지 않게 — 라이브 bin 만 허용
    */.worktrees/v6-realtime-live/.fable-team/bin/*) ;;
    */harness/bin/*|*/harness/kit/fable-team/bin/*|*/.worktrees/*) echo "REJECT --script 가 워크트리·키트 원본 아래다: $SCRIPT — 라이브 .fable-team/bin 의 ft-tick.sh 를 준다"; exit 1;;
  esac
  [ -f "$SCRIPT" ] || { echo "REJECT ft-tick.sh 없음: $SCRIPT"; exit 1; }
  NEW="$(mktemp /tmp/ft-tick-team-plist.XXXXXX)"; trap 'rm -f "$NEW"' EXIT
  python3 - "$TSV" "$TEAM" "${FROM:-$PL}" "$([ -n "$FROM" ] && echo from || echo own)" "$SCRIPT" "$NEW" <<'PY' || exit $?
import os, plistlib, sys
tsv, team, src, mode, script, out = sys.argv[1:7]
def rej(m): print("REJECT " + m); sys.exit(1)
row = None
for ln in open(tsv, encoding="utf-8"):
    if ln.startswith("#") or not ln.strip(): continue
    c = ln.rstrip("\n").split("\t")
    if len(c) != 7: rej("팀 표 줄의 열이 7개가 아니다: " + ln[:60])
    if c[0] == team: row = c
if row is None: rej("팀 표에 팀이 없다: " + team)
_, seats, state, pidf, stamp, off, on = row
if not os.path.isfile(src): rej("원본 plist 없음: %s — 문구가 든 plist 를 --from 으로 준다" % src)
d = plistlib.load(open(src, "rb")); env = d.get("EnvironmentVariables") or {}
for k in ("FT_TICK_MASTER_MSG", "FT_TICK_PM_MSG"):
    if k not in env: rej("원본 plist 에 %s 가 없다 — 메인 문구로 돌게 된다: %s" % (k, src))
want = {"FT_TICK_PIDFILE": pidf, "FT_TICK_STAMP_PREFIX": stamp, "FT_TICK_STATE_DIR": state}
if mode == "own":   # 이 팀 자기 plist 면 값이 표와 같아야 한다(표와 라이브의 어긋남 = 사람 확인)
    for k, v in want.items():
        if env.get(k) not in (None, v): rej("plist %s=%s ≠ 표 %s — 사람 확인" % (k, env.get(k), v))
    cur = env.get("FT_TICK_SEATS")
    if cur is not None and os.path.basename(cur) != seats: rej("plist FT_TICK_SEATS=%s ≠ 표 %s — 사람 확인" % (cur, seats))
else:
    env["FT_TICK_SEATS"] = os.path.join(os.path.dirname(env.get("FT_TICK_SEATS", "")) or os.path.dirname(os.path.dirname(script)), seats)
env.update(want)
for k in filter(None, off.split(",")): env[k] = "0"
for kv in filter(None, on.split(",")): k, _, v = kv.partition("="); env[k] = v
ss = os.path.join(os.path.dirname(script), "ft-seat-status.sh")
if not os.path.isfile(ss): rej("공용 bin 폴더에 ft-seat-status.sh 없음: %s (팀 폴더 사본은 구판 — turn·jsonl 없음)" % ss)
env["FT_TICK_SEAT_STATUS"] = ss
pa = list(d.get("ProgramArguments") or ["/opt/homebrew/bin/bash", script]); pa[1:] = [script]
d["ProgramArguments"] = pa; d["EnvironmentVariables"] = env; d["Label"] = "com.byz.ft-tick-" + team
if mode == "from":
    for k in ("StandardOutPath", "StandardErrorPath"): d[k] = "/tmp/ft-tick-%s.log" % team
plistlib.dump(d, open(out, "wb"))
PY
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

# 런타임 자리(.fable-team/bin, gitignore)가 있으면 그것, 없으면 하네스 코드 루트의 추적 사본(harness/bin · r385).
if [ -z "$SCRIPT" ]; then
  if [ -f "$WT/.fable-team/bin/ft-tick.sh" ]; then SCRIPT="$WT/.fable-team/bin/ft-tick.sh"
  else HR="$([ -f "$HERE/ft-harness-root.sh" ] && . "$HERE/ft-harness-root.sh" && ft_harness_root "$HERE")"; SCRIPT="${HR:+$HR/bin/ft-tick.sh}"; fi
fi
[ -f "$TEMPLATE" ] || { echo "REJECT 템플릿 없음: $TEMPLATE"; exit 1; }
[ -f "$SCRIPT" ]   || { echo "REJECT ft-tick.sh 없음: $SCRIPT"; exit 1; }
[ -d "$WT" ]       || { echo "REJECT 워크트리 없음: $WT"; exit 1; }
[ -x /opt/homebrew/bin/bash ] || { echo "REJECT /opt/homebrew/bin/bash 없음 (plist ProgramArguments)"; exit 1; }
# r459: 메인 plist 도 팀 plist 와 같은 틀 — WorkingDirectory = git 공용 루트 · 우편함·판정기 env = 공용 루트 comm(옛 라이브 워크트리 comm 0)
COMMON="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; COMMON="${COMMON%/.git}"
[ -n "$COMMON" ] && [ -d "$COMMON/.fable-team/comm" ] || { echo "REJECT 공용 루트 comm 없음: ${COMMON:-<git 밖>}/.fable-team/comm ($WT)"; exit 1; }
COMM="$COMMON/.fable-team/comm"

render() { sed -e "s|__WORKTREE__|$COMMON|g" -e "s|__SCRIPT__|$SCRIPT|g" -e "s|__COMM__|$COMM|g" "$TEMPLATE"; }
if [ "$DRY" = 1 ]; then
  TMP="$(mktemp /tmp/ft-tick-plist.XXXXXX)"; render > "$TMP"
  plutil -lint "$TMP" >/dev/null && echo "PLAN plist lint OK · script=$SCRIPT · cwd=$COMMON · comm=$COMM · dst=$PLIST_DST · bootstrap $DOMAIN" || { echo "REJECT 렌더된 plist lint 실패: $TMP"; exit 1; }
  [ -z "${FT_TICK_PRINT_PLIST:-}" ] || cat "$TMP"
  rm -f "$TMP"; exit 0
fi

mkdir -p "$(dirname "$PLIST_DST")"
render > "$PLIST_DST"
plutil -lint "$PLIST_DST" || { echo "REJECT plist lint 실패: $PLIST_DST"; exit 1; }
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true          # 재설치 허용(이미 떠 있으면 내렸다 올린다)
launchctl bootstrap "$DOMAIN" "$PLIST_DST" || { echo "REJECT bootstrap 실패 — launchctl print $DOMAIN/$LABEL 로 확인"; exit 1; }
sleep 1
launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -E '^\s*(state|pid) ' || echo "WARN launchctl print 에 state/pid 없음"
echo "installed $LABEL → $PLIST_DST (log /tmp/ft-tick.log). ★구 데몬(ft-pm-tick/ft-master-tick)은 그대로다 — README §4-2 전환 절차★"
