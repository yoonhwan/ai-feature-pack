#!/usr/bin/env bash
# ft-seat-retire.sh <구> <후계> [--seats <파일>] — 승계 뒤 옛 좌석 행을 한 번에 은퇴시킨다 (R43).
#   구 행: tick=None · _replaced_by=<후계> · role=stop-ready(원래 role 은 _retired_role) · 후계 행: 없으면 생성·있으면 role/tick 상속·_replaces 추가.
#   최상위 _<이름> 문자열 키 중 값이 <구> 인 것(_master·_arch·_hil_route…) 전부 → <후계>. retarget_seat(ft-tick-team.sh)와 같은 규칙을 «살아 있는 승계»에 쓴다.
#   명부 = --seats · FT_SEATS_JSON · <루트>/.fable-team/seats*.json 중 키 <구> 를 가진 파일 정확히 1개.
#   rc 0 = RETIRED/NOOP · 1 = 명부 못 정함·구 행 없음 · 2 = usage · 3 = 후계 행이 이미 은퇴(쓰기 0). 쓰기 전 <파일>.bak-retire-<ts>.
set -uo pipefail
OLD="${1:-}"; NEW="${2:-}"; [ -n "$OLD" ] && [ -n "$NEW" ] && [ "$OLD" != "$NEW" ] || { echo "usage: $0 <구> <후계> [--seats <파일>]" >&2; exit 2; }
shift 2; ARG=""
while [ $# -gt 0 ]; do case "$1" in --seats) ARG="${2:-}"; shift 2;; *) echo "unknown $1" >&2; exit 2;; esac; done
ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
python3 - "${ARG:-${FT_SEATS_JSON:-}}" "${ROOT:-.}" "$OLD" "$NEW" <<'PY'
import json, os, sys, glob, shutil, datetime, collections
arg, root, old, new = sys.argv[1:5]
def load(f):
    try: return json.load(open(f, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
    except (OSError, ValueError): return None
if arg: cand = [arg]
else: cand = [f for f in sorted(glob.glob(root + "/.fable-team/seats*.json")) if isinstance(load(f), dict) and old in load(f)]
if len(cand) != 1: print(f"REJECT 명부 후보 {len(cand)}개 (키 {old}) — --seats 로 지정"); sys.exit(1)
p = cand[0]; d = load(p); o = d.get(old) if isinstance(d, dict) else None
if not isinstance(o, dict): print(f"REJECT {p} 에 구 행 {old} 없음"); sys.exit(1)
if o.get("_replaced_by") == new: print(f"NOOP {old} 은 이미 {new} 로 은퇴 file={p}"); sys.exit(0)
n = d.get(new)
if isinstance(n, dict) and n.get("_replaced_by"): print(f"REJECT 후계 {new} 가 이미 은퇴(_replaced_by={n['_replaced_by']}) — 쓰기 0"); sys.exit(3)
shutil.copy(p, p + ".bak-retire-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S"))
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
PY
