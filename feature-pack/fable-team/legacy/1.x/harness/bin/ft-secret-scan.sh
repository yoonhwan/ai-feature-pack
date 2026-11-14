#!/usr/bin/env bash
# ft-secret-scan.sh — 세션 기록(claude jsonl · codex rollout)·옛 계획 파일에 남은 비밀 «모양» 사후 스캔 (R135b ③ · 판정 1585 ⓐ «위치만 알림»)
#   대상: ~/.claude/projects/**/*.jsonl · ~/.codex/sessions/**/rollout-*.jsonl · 계획 파일(<루트>/design/**/*.sh.hil · /tmp/h*; 판정기 R135a plan() 소급)
#   증분: 상태 파일(~/.fable-team/state/secret-scan.state · 파일별 mtime·크기)과 같으면 읽지 않는다 · 줄 단위 스트리밍(전체 적재 0)
#   원장: ~/.fable-team/state/secret-scan.log — «파일:줄 종류» 만(값 0) · 새로 찾은 것만 planner `_hil_route` 앞 [HIL] 묶음 1통
#   사용: ft-secret-scan.sh [--plans <경로>…]   스캔(첫 실행은 nice -n 10)
#         ft-secret-scan.sh --report            스캔 0·쪽지 0 — 「비밀 기록 스캔: 새 N건 · 마지막 실행 시각」 1줄(주간 점검용)
#   rc: 0 정상 · 3 판정 불가(judge_unknown>0 · 0 과 구분) · 2 usage · 4 상태 파일 손상(전수 재스캔 대신 ERROR) · 5 쪽지 실패(상태·원장 미갱신 → 다음 실행이 다시 보낸다)
#   r1341 단계 2: 계획 1건 판정기의 시간 초과·rc=2·출력 꼴 어긋남 = «판정 불가» 1줄 + 그 파일만 세고(sig 저장 0) 반복 계속 · 같은 파일 3회차 연속이면 [긴급] 1통
#   env(시험용): HOME · FT_SECRET_SCAN_ROOT · FT_MBOX_SH · FT_SEATS_JSON · FT_SECRET_SCAN_TMP(기본 계획 목록 /tmp/h* 의 폴더 · 기본 /tmp)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_SECRET_SCAN_ROOT:-}"   # r385: 리포 공용 루트 = env → ft_repo_root(옛 설치 꼴 · cwd) → ERROR (새 설치본이 git 밖이라 자기 위치로 풀지 않는다)
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 3
SCAN_MBOX="${FT_MBOX_SH:-}"; [ -n "$SCAN_MBOX" ] || { . "$HERE/ft-harness-root.sh"; _CM="$(ft_comm_dir "$HERE")" || exit 3; SCAN_MBOX="$_CM/mbox.sh"; }   # r385 r3: 설치본엔 형제 comm 폴더가 없다 — 데이터 루트의 comm
export SCAN_HERE="$HERE" SCAN_ROOT="$ROOT" SCAN_MBOX SCAN_SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats-planner.json}" SCAN_TMP="${FT_SECRET_SCAN_TMP:-/tmp}"
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
import codecs, glob, json, os, subprocess, sys, time
sys.path.insert(0, os.environ["SCAN_HERE"])
from ft_secret_shapes import mask

E = os.environ
STATE, LOG, MODE = E["SCAN_STATE"], E["SCAN_LOG"], E["SCAN_MODE"]
home, root = os.path.expanduser("~"), E["SCAN_ROOT"]


def judge_plan(p: str) -> tuple[list[str], str | None]:
    """계획 1건 — 판정기 rc 계약(0 ok / 1 reject / 2 내부 오류)대로 가른다 → (found, 판정 불가 사유|None).
    재시도 1회는 «시간 초과»일 때만(하드 룰 12) · 판정기 호출 상한은 7초 그대로."""
    for attempt in (1, 2):
        try:
            r = subprocess.run([sys.executable, E["SCAN_HERE"] + "/ft_secret_judge.py", "--plan", p],
                               capture_output=True, text=True, timeout=7)
        except subprocess.TimeoutExpired:
            if attempt == 1:
                continue
            return [], "판정기 7초"
        except OSError:
            return [], "판정기 실행 실패"
        outs = r.stdout.strip()
        if r.returncode == 0:   # 계약 = rc0 + «ok» 만 깨끗하다(그 밖 출력 = 판정 불가 · DA R2)
            return ([], None) if outs == "ok" else ([], "판정기 출력 꼴")
        if r.returncode == 1:   # ★정상 검출은 지금처럼 수집★ — 단 «reject <줄번호> <이유>» 문법일 때만(IndexError 0)
            parts = [x.split(" ", 2) for x in outs.splitlines() if x.startswith("reject ")]
            if not parts or any(len(x) != 3 or not x[1].isdigit() for x in parts):
                return [], "판정기 출력 꼴"
            return [f"{p}:{x[1]} plan:{x[2]}" for x in parts], None
        if r.returncode in (124,) and attempt == 1:
            continue
        return [], "판정기 rc=2" if r.returncode == 2 else "판정기 출력 꼴"
    return [], "판정기 7초"


def hil_route() -> str:
    try:
        return json.load(open(E["SCAN_SEATS"]))["_hil_route"]
    except (OSError, ValueError, KeyError):
        print(f"ERROR secret-scan: planner _hil_route 없음 — 쪽지 못 보냄 ({E['SCAN_SEATS']})", file=sys.stderr)
        sys.exit(5)


def send_mail(msg: str) -> None:
    r = subprocess.run(["bash", E["SCAN_MBOX"], "send", hil_route(), "ft-secret-scan", msg], capture_output=True, text=True)
    if r.returncode != 0:
        print("ERROR secret-scan: 쪽지 실패 — 상태·원장 미갱신(다음 실행이 다시 보낸다)", file=sys.stderr)
        sys.exit(5)


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
print(f"RUN {time.strftime('%Y-%m-%dT%H:%M:%S%z')} root={root} seats={E['SCAN_SEATS']}", flush=True)   # r1956: 회차 머리(시각·경로만 · 값 0)

seen = set()
if os.path.exists(LOG):
    seen = {ln.split("\t", 1)[1].rstrip("\n") for ln in open(LOG) if "\t" in ln}
def is_text(p: str) -> bool:   # r1956: 앞 4KB 에 NUL 0 · UTF-8 로 읽힘 = 계획 파일 · 못 열면 지금처럼 판정기로
    try:
        b = open(p, "rb").read(4096)
        codecs.getincrementaldecoder("utf-8")().decode(b)   # 4KB 끝에서 잘린 글자는 오류 0
        return b"\0" not in b
    except (OSError, UnicodeDecodeError) as e:
        return isinstance(e, OSError)
tmp_h = [] if E["SCAN_PLANS"].strip() else [p for p in glob.glob(E["SCAN_TMP"] + "/h*") if os.path.isfile(p)]  # r1825: 기본 목록 = 일반 파일만(폴더 판정 0)
texts = [p for p in tmp_h if is_text(p)]   # r1956: 이진(jpg 등)은 계획 파일 아님
plans = [p for p in E["SCAN_PLANS"].split("\n") if p] or glob.glob(root + "/design/**/*.sh.hil", recursive=True) + texts
logs = glob.glob(home + "/.claude/projects/**/*.jsonl", recursive=True) + glob.glob(home + "/.codex/sessions/**/rollout-*.jsonl", recursive=True)
files, new, read, skipped = dict(st["files"]), [], 0, 0
unknown = dict(st.get("unknown") or {})   # rd1341: 파일별 «연속 판정 불가» 횟수 · 사유
judge_unknown, escalate = 0, []
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
        found, why = judge_plan(p)
        if why:   # 판정 불가 = 그 파일만 세고 sig 저장 0(«안 읽음» · 다음 회차 재판정) · 조용한 영구 건너뜀 0
            judge_unknown += 1
            cnt = int((unknown.get(p) or [0, ""])[0]) + 1
            unknown[p] = [cnt, why]
            print(f"판정 불가 {p} {why}", file=sys.stderr)
            if cnt == 3:
                escalate.append((p, why))
            continue
        unknown.pop(p, None)
    else:
        with open(p, errors="replace") as f:
            for n, line in enumerate(f, 1):
                found += [f"{p}:{n} {kind}" for kind, _ in mask(line)[1]]
    new += [k for k in dict.fromkeys(found) if k not in seen]
    files[p] = sig

now = time.strftime("%F %T")
if new and MODE == "scan":
    shown = "\n".join(new[:5]) + (f"\n…외 {len(new) - 5}건(원장 {LOG})" if len(new) > 5 else "")
    send_mail(f"[HIL] 비밀 기록 스캔 — 새 {len(new)}건(위치만 · 값 0 · 교체는 오빠 롤아웃 판정 1583)\n{shown}")
for p, why in escalate:   # 같은 파일 3회차 연속 판정 불가 = [긴급] 1통(경로 · 마지막 사유)
    if MODE == "scan":
        send_mail(f"[긴급] 비밀 스캔 판정 불가 3회차 — {p} (마지막 사유: {why})")
os.makedirs(os.path.dirname(STATE), exist_ok=True)
with open(LOG, "a") as f:
    f.writelines(f"{now}\t{k}\n" for k in new)
tmp = STATE + ".tmp"
json.dump({"files": files, "last": {"ts": now, "new": len(new), "read": read, "skipped": skipped},
           "unknown": unknown}, open(tmp, "w"))
os.replace(tmp, STATE)
print(f"SCAN read={read} skipped={skipped} new={len(new)} judge_unknown={judge_unknown}" + (f" skipped_binary={len(tmp_h) - len(texts)}" if len(tmp_h) > len(texts) else ""))
sys.exit(3 if judge_unknown else 0)
PYEOF
