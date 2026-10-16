#!/usr/bin/env bash
# ft-seat-retire.sh <구> <후계> [--seats <파일>] — 승계 뒤 옛 좌석 행을 한 번에 은퇴시킨다 (R43).
#   구 행: tick=None · _replaced_by=<후계> · role=stop-ready(원래 role 은 _retired_role) · 후계 행: 없으면 생성·있으면 role/tick 상속·_replaces 추가.
#   최상위 _<이름> 문자열 키 중 값이 <구> 인 것(_master·_arch·_hil_route…) 전부 → <후계>. retarget_seat(ft-tick-team.sh)와 같은 규칙을 «살아 있는 승계»에 쓴다.
#   명부 = --seats · FT_SEATS_JSON · <루트>/.fable-team/seats*.json 중 키 <구> 를 가진 파일 정확히 1개.
#   rc 0 = RETIRED/NOOP · 1 = 명부 못 정함·구 행 없음 · 2 = usage · 3 = 후계 행이 이미 은퇴(쓰기 0). 쓰기 전 <파일>.bak-retire-<ts>.
#   RETIRED 줄 다음에 재개 기록 결과 1줄 — `RESUME ok <~/.claude/state/seat-resume/<구>.json>` 또는 `NORECORD <구> <이유>` (rc 에 섞지 않음 · 판정 1344). 부팅 보고 retire 칸 옆에 복붙.
#   `<구> --record-only [--seats <파일>]` (R110 · 판정 1380) — 이미 은퇴한 «살아 있는» 옛 좌석에 재개 기록만 쓴다. 명부 쓰기·.bak 0 · 구 행에 _replaced_by 없으면 REJECT rc 1(현역 좌석에 닫기 근거를 만들지 않는다) · retired_by = 그 _replaced_by. <후계> 와 같이 주면 usage rc 2.
#   R282 ① 재개 기록 model 우선순위(r2) = 실행 프로세스 argv `--model` → 명부(바탕이 jsonl 과 같으면 `[1m]` 접미사 유지) → 대화 기록(jsonl) 마지막 assistant 의 message.model → 명부 · 모두 없으면 NORECORD · 명부와 «바탕이» 다를 때만 기록에 roster_model + 출력 끝 `(명부 model 다름: <값>)`.
#   R282 ② 은퇴인데 옛 행이 어느 명부에도 없으면(--seats 없음) 이름(ft-name-lint 통과)의 팀 명부(seats.json=v65 · seats-<팀>.json)에 은퇴 행을 만든 뒤 은퇴 — 옛 이름이 «다른» 명부 `_*` 칸에 현역이면 REJECT.
#   R282 ③ 후계 행 model = 도달 파일(<루트>/.fable-team/state/successor/<구>.json · env FT_SUCCESSOR_DIR)의 model → 없으면 옛 값.
#   R296 ④ `--record-only` + 행 없음 — ⓐ 옛 이름이 어느 명부 `_*` 칸의 값도 아님 ⓑ 같은 계보로 더 큰 번호가 `_*` 칸에 현역 ⓒ 그 tmux 세션 생존 — 셋 다 참일 때만 기록(retired_by = 그 현역 이름) · 명부 쓰기 0.
set -uo pipefail
OLD="${1:-}"; [ -n "$OLD" ] || { echo "usage: $0 <구> <후계> [--seats <파일>] | $0 <구> --record-only [--seats <파일>]" >&2; exit 2; }
shift; NEW=""; RECONLY=0; ARG=""
case "${1:-}" in ""|--*) ;; *) NEW="$1"; shift;; esac
while [ $# -gt 0 ]; do case "$1" in --seats) ARG="${2:-}"; shift 2;; --record-only) RECONLY=1; shift;; *) echo "unknown $1" >&2; exit 2;; esac; done
{ [ "$RECONLY" = 1 ] && [ -z "$NEW" ]; } || { [ "$RECONLY" = 0 ] && [ -n "$NEW" ] && [ "$OLD" != "$NEW" ]; } || { echo "usage: $0 <구> <후계> [--seats <파일>] | $0 <구> --record-only [--seats <파일>]" >&2; exit 2; }
ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
python3 - "${ARG:-${FT_SEATS_JSON:-}}" "${ROOT:-.}" "$OLD" "$NEW" "$RECONLY" "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)" <<'PY'
import json, os, re, sys, glob, shutil, datetime, subprocess, collections
arg, root, old, new, reconly, here = sys.argv[1:7]
def load(f):
    try: return json.load(open(f, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
    except (OSError, ValueError): return None
def sh(*a):
    try: return subprocess.run(a, capture_output=True, text=True, timeout=7).stdout.split()
    except (OSError, subprocess.SubprocessError): return []
def jsonl_model(jsonl):   # 대화 기록 끝(8MB·2000줄)에서 거꾸로 마지막 assistant 의 message.model — 못 읽으면 None (R282 ①)
    try:
        with open(jsonl, "rb") as f: f.seek(0, 2); n = f.tell(); f.seek(max(0, n - 8 * 1024 * 1024)); tail = f.read().decode("utf-8", "replace").splitlines()
    except OSError: return None
    for ln in reversed(tail[-2000:]):
        try: r = json.loads(ln)
        except ValueError: continue
        m = r.get("message") if isinstance(r, dict) and r.get("type") == "assistant" else None
        m = m.get("model") if isinstance(m, dict) else None
        if isinstance(m, str) and m and not m.startswith("<"): return m   # <synthetic> 같은 자리표시 제외
    return None
def base_model(m): return re.sub(r"\[[^\]]*\]$", "", m)   # claude-x[1m] → claude-x
def argv_model(pid):   # 실행 중 프로세스의 `--model X`(접미사 포함 실제 값) — 없으면 None (r2)
    a = sh("ps", "-o", "args=", "-p", pid)
    for i, t in enumerate(a):
        if t == "--model" and i + 1 < len(a): return a[i + 1]
        if t.startswith("--model="): return t[8:] or None
    return None
def find_resume(model, retired_by):   # (기록|None, 이유) — 실행 중 프로세스 결속(DA② H2): pane 자식 중 세션 파일이 있는 «정확히 1개» 의 sessionId. 이름·mtime 추측 0
    home = os.path.expanduser("~"); pp = sh("tmux", "display", "-p", "-t", "=" + old + ":", "#{pane_pid}")
    if not pp: return None, "tmux 세션 없음"
    kids = [k for k in sh("pgrep", "-P", pp[0]) if os.path.isfile(f"{home}/.claude/sessions/{k}.json")]
    if len(kids) != 1: return None, f"세션 파일 {len(kids)}개"
    s = load(f"{home}/.claude/sessions/{kids[0]}.json"); s = s if isinstance(s, dict) else {}
    if s.get("name") != old or str(s.get("pid")) != kids[0]: return None, "세션 파일 name·pid 불일치"
    uuid, cwd = s.get("sessionId") or "", s.get("cwd") or ""
    jsonl = f"{home}/.claude/projects/{re.sub('[^A-Za-z0-9]', '-', cwd)}/{uuid}.jsonl"
    if not (uuid and cwd and os.path.isfile(jsonl)): return None, "uuid·cwd·jsonl 없음"
    am, jm, rm = argv_model(kids[0]), jsonl_model(jsonl), (model if isinstance(model, str) and model else None)
    use = am or (rm if rm and (not jm or base_model(rm) == base_model(jm)) else jm or rm)   # zombie-clean resume 이 --model 로 그대로 쓴다 — jsonl 값엔 [1m] 이 없어 200k 창 회귀(r2): argv → 명부(바탕 같으면 접미사 유지) → jsonl → 명부
    if not use: return None, "model 못 읽음(jsonl·명부)"
    rec = collections.OrderedDict(name=old, engine="claude", pid=int(kids[0]), uuid=uuid, jsonl=jsonl, cwd=cwd, model=use, retired_by=retired_by, at=datetime.datetime.now().isoformat(timespec="seconds"))
    if rm and base_model(rm) != base_model(use): rec["roster_model"] = rm   # 바탕이 다를 때만 — 조용히 덮지 않는다
    return rec, ""
def write_record(rec, why):   # 재개 기록(zombie-clean 이 직전 세대를 닫아도 되는 근거) — 실패는 NORECORD 로 보이고 직전 세대는 keep-last-2 로 남는다
    rd = os.environ.get("ZC_RESUME_DIR") or os.path.expanduser("~/.claude/state/seat-resume"); rp = f"{rd}/{old}.json"
    try:
        if not rec: raise ValueError(why)
        os.makedirs(rd, exist_ok=True); json.dump(rec, open(rp + ".tmp", "w", encoding="utf-8"), ensure_ascii=False, indent=2); os.replace(rp + ".tmp", rp)
        print(f"RESUME ok {rp}" + (f" (명부 model 다름: {rec['roster_model']})" if rec.get("roster_model") else ""))
    except (OSError, ValueError) as e:
        msg = f"NORECORD {old} {e}"
        if os.path.exists(rp):   # 옛 기록이 닫기 근거로 남지 않게 지우지 않고 이름만 바꾼다(zombie-clean 은 <이름>.json 만 읽는다 · DA⑥ H1)
            sp = rp + ".stale-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
            try: os.replace(rp, sp); msg += f" · 이전 기록 무효화 {sp}"
            except OSError as e2: msg += f" · 이전 기록 무효화 실패 {e2}"
        print(msg)
rosters = sorted(glob.glob(root + "/.fable-team/seats*.json"))
def reject(why): print(f"REJECT {why}"); sys.exit(1)
def active_in(f):   # 그 명부 최상위 `_*` 문자열 칸(_master·_arch·_hil_route…)의 값에 옛 이름이 있나 = 현역
    dd = load(f); return isinstance(dd, dict) and any(k.startswith("_") and v == old for k, v in dd.items() if isinstance(v, str))
def alive(name):
    try: return subprocess.run(["tmux", "has-session", "-t", "=" + name], capture_output=True, timeout=7).returncode == 0
    except (OSError, subprocess.SubprocessError): return False
def arrival_model():   # ft-successor-open.sh 가 쓴 도달 파일의 model(R282 ③)
    a = load(f"{os.environ.get('FT_SUCCESSOR_DIR') or root + '/.fable-team/state/successor'}/{old}.json"); m = a.get("model") if isinstance(a, dict) else None
    return m if isinstance(m, str) and m else None
if arg: cand = [arg]
else: cand = [f for f in rosters if isinstance(load(f), dict) and old in load(f)]
mkrow = False
if not cand and not arg and "#" in old and reconly == "1":   # R296 ④ — 행 없는 옛 좌석: ⓐⓑⓒ 셋 다 참일 때만 기록(명부 쓰기 0)
    base, _, gen = old.rpartition("#"); later = []
    for f in rosters:
        dd = load(f)
        for k, v in (dd.items() if isinstance(dd, dict) else []):
            if not (k.startswith("_") and isinstance(v, str)): continue
            if v == old: reject(f"{old} 은 현역({os.path.basename(f)} {k}) — 기록 모드는 은퇴한 좌석만")
            b, _, g = v.rpartition("#")
            if b == base and g.isdigit() and gen.isdigit() and int(g) > int(gen): later.append((int(g), v))
    if not later: reject(f"{old} 보다 번호가 큰 같은 계보 현역 이름이 어느 명부 `_*` 칸에도 없음")
    rb = max(later)[1]
    if not alive(rb): reject(f"현역 {rb} 의 tmux 세션이 없음")
    rec, why = find_resume(None, rb); write_record(rec, why); sys.exit(0)
if not cand and not arg and reconly != "1":   # R282 ② — 옛 행이 어느 명부에도 없는 «지금 승계 중»: 팀 명부에 은퇴 행을 만든다
    lint = subprocess.run(["bash", f"{here}/ft-name-lint.sh", old], capture_output=True, text=True)
    if lint.returncode != 0: reject(f"명부 후보 0개 (키 {old}) · 이름 lint 실패 — --seats 로 지정")
    parts = old.rpartition("#")[0].split("-"); tf = root + "/.fable-team/" + ("seats.json" if parts[1] == "v65" else f"seats-{parts[1]}.json")
    if not isinstance(load(tf), dict): reject(f"명부 후보 0개 (키 {old}) · 팀 명부 없음 {tf} — --seats 로 지정")
    if any(f != tf and active_in(f) for f in rosters): reject(f"{old} 은 다른 명부에서 현역 — 은퇴 행을 만들지 않는다(현역에 닫기 근거 0)")
    cand, mkrow = [tf], True
if len(cand) != 1: print(f"REJECT 명부 후보 {len(cand)}개 (키 {old}) — --seats 로 지정"); sys.exit(1)
p = cand[0]; d = load(p); o = d.get(old) if isinstance(d, dict) else None
if mkrow: rec0, _ = find_resume(None, new); o = collections.OrderedDict([("role", parts[2]), ("agent", parts[3]), ("model", rec0["model"] if rec0 else None), ("tick", None), ("_created_by", "retire")])
if not isinstance(o, dict): print(f"REJECT {p} 에 구 행 {old} 없음"); sys.exit(1)
if reconly == "1":   # 기록 모드 — 명부 쓰기 0(.bak 도 0) · 은퇴한 행(_replaced_by 있음)만
    rb = o.get("_replaced_by")
    if not (isinstance(rb, str) and rb): print(f"REJECT {old} 은 현역 행(_replaced_by 없음) — 기록 모드는 은퇴한 좌석만 file={p}"); sys.exit(1)
    rec, why = find_resume(o.get("model"), rb); write_record(rec, why); sys.exit(0)
if o.get("_replaced_by") == new: print(f"NOOP {old} 은 이미 {new} 로 은퇴 file={p}"); sys.exit(0)
n = d.get(new)
if isinstance(n, dict) and n.get("_replaced_by"): print(f"REJECT 후계 {new} 가 이미 은퇴(_replaced_by={n['_replaced_by']}) — 쓰기 0"); sys.exit(3)
shutil.copy(p, p + ".bak-retire-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S"))
if mkrow: d[old] = o   # .bak 뒤에 — 아래 은퇴 흐름이 이 행을 닫는다
rec, why = find_resume(o.get("model"), new)   # 읽기만 — 실패해도 은퇴는 그대로(기록 결과는 rc 에 섞지 않는다 · H3)
if rec: o["_resume_uuid"] = rec["uuid"]
else: o.pop("_resume_uuid", None)   # 옛 은퇴가 남긴 값이 닫기 근거로 남지 않게(DA⑥ H1)
role, tick = o.get("role"), o.get("tick")
if role != "stop-ready": o["_retired_role"] = role
o["tick"] = None; o["_replaced_by"] = new; o["role"] = "stop-ready"
if not isinstance(n, dict):
    n = d[new] = collections.OrderedDict([("role", role), ("agent", o.get("agent", "claude")), ("model", arrival_model() or o.get("model") or (rec or {}).get("model")), ("tick", tick)])
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
write_record(rec, why)
PY
