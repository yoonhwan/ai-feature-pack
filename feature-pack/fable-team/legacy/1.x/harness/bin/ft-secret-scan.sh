#!/usr/bin/env bash
# ft-secret-scan.sh — 세션 기록(claude jsonl · codex rollout)·옛 계획 파일에 남은 비밀 «모양» 사후 스캔 (R135b ③ · 판정 1585 ⓐ «위치만 알림»)
#   대상: ~/.claude/projects/**/*.jsonl · ~/.codex/sessions/**/rollout-*.jsonl · 계획 파일(<루트>/design/**/*.sh.hil · /tmp/h*; 판정기 R135a plan() 소급)
#   증분: 상태 파일(~/.fable-team/state/secret-scan.state · 파일별 mtime·크기)과 같으면 읽지 않는다 · 줄 단위 스트리밍(전체 적재 0)
#   원장: ~/.fable-team/state/secret-scan.log — «파일:줄 종류» 만(값 0) · 새로 찾은 것만 planner `_hil_route` 앞 [HIL] 묶음 1통
#   사용: ft-secret-scan.sh [--plans <경로>…]   스캔(첫 실행은 nice -n 10)
#         ft-secret-scan.sh --report            스캔 0·쪽지 0 — 「비밀 기록 스캔: 새 N건 · 마지막 실행 시각」 1줄(주간 점검용)
#   rc: 0 정상 · 2 usage · 4 상태 파일 손상(전수 재스캔 대신 ERROR) · 5 쪽지 실패(상태·원장 미갱신 → 다음 실행이 다시 보낸다)
#   env(시험용): HOME · FT_SECRET_SCAN_ROOT · FT_MBOX_SH · FT_SEATS_JSON
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_SECRET_SCAN_ROOT:-}"   # r385: 리포 공용 루트 = env → ft_repo_root(옛 설치 꼴 · cwd) → ERROR (새 설치본이 git 밖이라 자기 위치로 풀지 않는다)
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 3
SCAN_MBOX="${FT_MBOX_SH:-}"; [ -n "$SCAN_MBOX" ] || { . "$HERE/ft-harness-root.sh"; _CM="$(ft_comm_dir "$HERE")" || exit 3; SCAN_MBOX="$_CM/mbox.sh"; }   # r385 r3: 설치본엔 형제 comm 폴더가 없다 — 데이터 루트의 comm
export SCAN_HERE="$HERE" SCAN_ROOT="$ROOT" SCAN_MBOX SCAN_SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats-planner.json}"
export SCAN_STATE="$HOME/.fable-team/state/secret-scan.state" SCAN_LOG="$HOME/.fable-team/state/secret-scan.log"
MODE=scan; PLANS=()
case "${1:-}" in
  "") ;;
  --report) MODE=report ;;
  --plans) shift; PLANS=("$@") ;;
  *) echo "usage: ft-secret-scan.sh [--plans <경로>…] | --report" >&2; exit 2 ;;
esac
SCAN_PLANS="$(printf '%s\n' "${PLANS[@]:-}")"; export SCAN_MODE="$MODE" SCAN_PLANS
PY=(python3 -I -)
[ "$MODE" = scan ] && [ ! -f "$SCAN_STATE" ] && PY=(nice -n 10 python3 -I -)  # 첫 실행 = 전수 — 다른 일을 밀어내지 않게
"${PY[@]}" <<'PYEOF'
import glob, json, os, subprocess, sys, time
sys.path.insert(0, os.environ["SCAN_HERE"])
from ft_secret_shapes import mask

E = os.environ
STATE, LOG, MODE = E["SCAN_STATE"], E["SCAN_LOG"], E["SCAN_MODE"]
home, root = os.path.expanduser("~"), E["SCAN_ROOT"]


def load_state() -> dict:
    if not os.path.exists(STATE):
        return {"files": {}, "last": {}}
    try:
        d = json.load(open(STATE))
        assert isinstance(d["files"], dict) and isinstance(d["last"], dict)
        return d
    except (ValueError, KeyError, AssertionError, OSError):
        print(f"ERROR secret-scan: 상태 파일 손상 — 전수 재스캔 대신 중단 ({STATE})", file=sys.stderr)
        sys.exit(4)


st = load_state()
if MODE == "report":
    last = st["last"]
    print(f"비밀 기록 스캔: 새 {last.get('new', 0)}건 · 마지막 실행 {last.get('ts', '없음')}")
    sys.exit(0)

seen = set()
if os.path.exists(LOG):
    seen = {ln.split("\t", 1)[1].rstrip("\n") for ln in open(LOG) if "\t" in ln}
plans = [p for p in E["SCAN_PLANS"].split("\n") if p] or glob.glob(root + "/design/**/*.sh.hil", recursive=True) + glob.glob("/tmp/h*")
logs = glob.glob(home + "/.claude/projects/**/*.jsonl", recursive=True) + glob.glob(home + "/.codex/sessions/**/rollout-*.jsonl", recursive=True)
files, new, read, skipped = dict(st["files"]), [], 0, 0
plan_only = set(plans) - set(logs)

for p in logs + plans:
    try:
        s = os.stat(p)
    except OSError:
        continue
    sig = [s.st_mtime_ns, s.st_size]  # 정수 초면 같은 초 안 두 번째 수정을 놓친다
    if files.get(p) == sig:
        skipped += 1
        continue
    read += 1
    found: list[str] = []
    if p in plan_only:
        r = subprocess.run([sys.executable, E["SCAN_HERE"] + "/ft_secret_judge.py", "--plan", p], capture_output=True, text=True, timeout=7)
        found = [f"{p}:{x.split(' ', 2)[1]} plan:{x.split(' ', 2)[2]}" for x in r.stdout.splitlines() if x.startswith("reject ")]
    else:
        with open(p, errors="replace") as f:
            for n, line in enumerate(f, 1):
                found += [f"{p}:{n} {kind}" for kind, _ in mask(line)[1]]
    new += [k for k in dict.fromkeys(found) if k not in seen]
    files[p] = sig

now = time.strftime("%F %T")
if new and MODE == "scan":
    try:
        route = json.load(open(E["SCAN_SEATS"]))["_hil_route"]
    except (OSError, ValueError, KeyError):
        print(f"ERROR secret-scan: planner _hil_route 없음 — 쪽지 못 보냄 ({E['SCAN_SEATS']})", file=sys.stderr)
        sys.exit(5)
    shown = "\n".join(new[:5]) + (f"\n…외 {len(new) - 5}건(원장 {LOG})" if len(new) > 5 else "")
    msg = f"[HIL] 비밀 기록 스캔 — 새 {len(new)}건(위치만 · 값 0 · 교체는 오빠 롤아웃 판정 1583)\n{shown}"
    r = subprocess.run(["bash", E["SCAN_MBOX"], "send", route, "ft-secret-scan", msg], capture_output=True, text=True)
    if r.returncode != 0:
        print("ERROR secret-scan: 쪽지 실패 — 상태·원장 미갱신(다음 실행이 다시 보낸다)", file=sys.stderr)
        sys.exit(5)
os.makedirs(os.path.dirname(STATE), exist_ok=True)
with open(LOG, "a") as f:
    f.writelines(f"{now}\t{k}\n" for k in new)
tmp = STATE + ".tmp"
json.dump({"files": files, "last": {"ts": now, "new": len(new), "read": read, "skipped": skipped}}, open(tmp, "w"))
os.replace(tmp, STATE)
print(f"SCAN read={read} skipped={skipped} new={len(new)}")
PYEOF
