#!/usr/bin/env bash
# ft-seat-retire.sh <구> <후계> [--seats <파일>] — 승계 뒤 옛 좌석 행을 한 번에 은퇴시킨다 (R43).
#   구 행: tick=None · _replaced_by=<후계> · role=stop-ready(원래 role 은 _retired_role) · 후계 행: 없으면 생성·있으면 role/tick 상속·_replaces 추가.
#   최상위 _<이름> 문자열 키 중 값이 <구> 인 것(_master·_arch·_hil_route…) 전부 → <후계>. retarget_seat(ft-tick-team.sh)와 같은 규칙을 «살아 있는 승계»에 쓴다.
#   명부 = --seats · FT_SEATS_JSON · <루트>/.fable-team/seats*.json 중 키 <구> 를 가진 파일 정확히 1개.
#   rc 0 = RETIRED/NOOP · 1 = 명부 못 정함·구 행 없음 · 2 = usage · 3 = 후계 행이 이미 은퇴(쓰기 0). 쓰기 전 <파일>.bak-retire-<ts>.
#   RETIRED 줄 다음에 재개 기록 결과 1줄 — `RESUME ok <~/.claude/state/seat-resume/<구>.json>` 또는 `NORECORD <구> <이유>` (rc 에 섞지 않음 · 판정 1344). 부팅 보고 retire 칸 옆에 복붙.
set -uo pipefail
OLD="${1:-}"; NEW="${2:-}"; [ -n "$OLD" ] && [ -n "$NEW" ] && [ "$OLD" != "$NEW" ] || { echo "usage: $0 <구> <후계> [--seats <파일>]" >&2; exit 2; }
shift 2; ARG=""
while [ $# -gt 0 ]; do case "$1" in --seats) ARG="${2:-}"; shift 2;; *) echo "unknown $1" >&2; exit 2;; esac; done
ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
python3 - "${ARG:-${FT_SEATS_JSON:-}}" "${ROOT:-.}" "$OLD" "$NEW" <<'PY'
import json, os, re, sys, glob, shutil, datetime, subprocess, collections
arg, root, old, new = sys.argv[1:5]
def load(f):
    try: return json.load(open(f, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
    except (OSError, ValueError): return None
def sh(*a):
    try: return subprocess.run(a, capture_output=True, text=True, timeout=7).stdout.split()
    except (OSError, subprocess.SubprocessError): return []
def find_resume(model):   # (기록|None, 이유) — 실행 중 프로세스 결속(DA② H2): pane 자식 중 세션 파일이 있는 «정확히 1개» 의 sessionId. 이름·mtime 추측 0
    home = os.path.expanduser("~"); pp = sh("tmux", "display", "-p", "-t", "=" + old + ":", "#{pane_pid}")
    if not pp: return None, "tmux 세션 없음"
    kids = [k for k in sh("pgrep", "-P", pp[0]) if os.path.isfile(f"{home}/.claude/sessions/{k}.json")]
    if len(kids) != 1: return None, f"세션 파일 {len(kids)}개"
    s = load(f"{home}/.claude/sessions/{kids[0]}.json"); s = s if isinstance(s, dict) else {}
    if s.get("name") != old or str(s.get("pid")) != kids[0]: return None, "세션 파일 name·pid 불일치"
    uuid, cwd = s.get("sessionId") or "", s.get("cwd") or ""
    jsonl = f"{home}/.claude/projects/{re.sub('[^A-Za-z0-9]', '-', cwd)}/{uuid}.jsonl"
    if not (uuid and cwd and os.path.isfile(jsonl)): return None, "uuid·cwd·jsonl 없음"
    if not (isinstance(model, str) and model): return None, "명부 model 없음"
    return collections.OrderedDict(name=old, engine="claude", pid=int(kids[0]), uuid=uuid, jsonl=jsonl, cwd=cwd, model=model, retired_by=new, at=datetime.datetime.now().isoformat(timespec="seconds")), ""
if arg: cand = [arg]
else: cand = [f for f in sorted(glob.glob(root + "/.fable-team/seats*.json")) if isinstance(load(f), dict) and old in load(f)]
if len(cand) != 1: print(f"REJECT 명부 후보 {len(cand)}개 (키 {old}) — --seats 로 지정"); sys.exit(1)
p = cand[0]; d = load(p); o = d.get(old) if isinstance(d, dict) else None
if not isinstance(o, dict): print(f"REJECT {p} 에 구 행 {old} 없음"); sys.exit(1)
if o.get("_replaced_by") == new: print(f"NOOP {old} 은 이미 {new} 로 은퇴 file={p}"); sys.exit(0)
n = d.get(new)
if isinstance(n, dict) and n.get("_replaced_by"): print(f"REJECT 후계 {new} 가 이미 은퇴(_replaced_by={n['_replaced_by']}) — 쓰기 0"); sys.exit(3)
shutil.copy(p, p + ".bak-retire-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S"))
rec, why = find_resume(o.get("model"))   # 읽기만 — 실패해도 은퇴는 그대로(기록 결과는 rc 에 섞지 않는다 · H3)
if rec: o["_resume_uuid"] = rec["uuid"]
else: o.pop("_resume_uuid", None)   # 옛 은퇴가 남긴 값이 닫기 근거로 남지 않게(DA⑥ H1)
role, tick = o.get("role"), o.get("tick")
if role != "stop-ready": o["_retired_role"] = role
o["tick"] = None; o["_replaced_by"] = new; o["role"] = "stop-ready"
if not isinstance(n, dict):
    n = d[new] = collections.OrderedDict([("role", role), ("agent", o.get("agent", "claude")), ("model", o.get("model")), ("tick", tick)])
else:
    if role != "stop-ready": n["role"] = role
    if not n.get("tick"): n["tick"] = tick
n["_replaces"] = sorted(set(n.get("_replaces", []) + [old]))
keys = [k for k, v in d.items() if k.startswith("_") and v == old]
for k in keys: d[k] = new
tmp = p + ".tmp-" + str(os.getpid())   # 쓰기 중 죽어도 원본 무손상 — tmp 에 다 쓴 뒤 한 번에 교체(N3 · D3 승계 원자성)
with open(tmp, "w", encoding="utf-8") as f: json.dump(d, f, ensure_ascii=False, indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
shutil.copymode(p, tmp); os.replace(tmp, p)
print(f"RETIRED {old} -> {new} file={p} keys={keys}")
rd = os.environ.get("ZC_RESUME_DIR") or os.path.expanduser("~/.claude/state/seat-resume"); rp = f"{rd}/{old}.json"
try:   # 재개 기록(zombie-clean 이 직전 세대를 닫아도 되는 근거) — 실패는 NORECORD 로 보이고 직전 세대는 keep-last-2 로 남는다
    if not rec: raise ValueError(why)
    os.makedirs(rd, exist_ok=True); json.dump(rec, open(rp + ".tmp", "w", encoding="utf-8"), ensure_ascii=False, indent=2); os.replace(rp + ".tmp", rp)
    print(f"RESUME ok {rp}")
except (OSError, ValueError) as e:
    msg = f"NORECORD {old} {e}"
    if os.path.exists(rp):   # 옛 기록이 닫기 근거로 남지 않게 지우지 않고 이름만 바꾼다(zombie-clean 은 <이름>.json 만 읽는다 · DA⑥ H1)
        sp = rp + ".stale-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
        try: os.replace(rp, sp); msg += f" · 이전 기록 무효화 {sp}"
        except OSError as e2: msg += f" · 이전 기록 무효화 실패 {e2}"
    print(msg)
PY
