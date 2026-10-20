#!/usr/bin/env bash
# ft-seat-retire.sh <구> <후계> [--seats <파일>] — 승계 뒤 옛 좌석 행을 한 번에 은퇴시킨다 (R43).
#   구 행: tick=None · _replaced_by=<후계> · role=stop-ready(원래 role 은 _retired_role) · 후계 행: 없으면 생성·있으면 role/tick 상속·_replaces 추가 · r499 옛 role 이 stop-ready 면 후계 role = _retired_role → 역할 칸 → 이름 토큰(못 정하면 그대로) · 재실행도 stop-ready 꼴 현역 후계를 고침 ` role stop-ready-><역할>`.
#   최상위 _<이름> 문자열 키 중 값이 <구> 인 것(_master·_arch·_hil_route…) 전부 → <후계>. retarget_seat(ft-tick-team.sh)와 같은 규칙을 «살아 있는 승계»에 쓴다.
#   명부 = --seats · FT_SEATS_JSON · <루트>/.fable-team/seats*.json 중 키 <구> 를 가진 파일 정확히 1개. r465 같은 폴더의 다른 명부 = 값이 <구> 인 `_*` 칸 전부(역할 roles + 라우팅 routes · 공유 arch) → <후계> · 전부 검증 뒤 쓰기(손상 1개 = ERROR rc 1 · 쓰기 0) · 출력 files=N roles=[…] routes=[…].
#   r465 재실행(이미 은퇴)도 남은 칸을 보정 → FIXED … · 옛 이름 칸 0 + 후계 행 실재 + 후계 역할 칸(_master·_arch·_da·_tester) 빈 값/없음 → 채움 ` FILLED <명부>:<칸>` · 그 칸이 살아 있는 다른 좌석 = REJECT rc 1(쓰기 0).
#   rc 0 = RETIRED/NOOP · 1 = 명부 못 정함·구 행 없음 · 2 = usage · 3 = 후계 행이 이미 은퇴(쓰기 0). 쓰기 전 <파일>.bak-retire-<ts>.
#   RETIRED 줄 다음에 재개 기록 결과 1줄 — `RESUME ok <~/.claude/state/seat-resume/<구>.json>` 또는 `NORECORD <구> <이유>` (rc 에 섞지 않음 · 판정 1344). 부팅 보고 retire 칸 옆에 복붙.
#   `<구> --record-only [--seats <파일>]` (R110 · 판정 1380) — 이미 은퇴한 «살아 있는» 옛 좌석에 재개 기록만 쓴다. 명부 쓰기·.bak 0 · 구 행에 _replaced_by 없으면 REJECT rc 1(현역 좌석에 닫기 근거를 만들지 않는다) · retired_by = 그 _replaced_by. <후계> 와 같이 주면 usage rc 2.
#   R282 ① 재개 기록 model 우선순위(r2) = 실행 프로세스 argv `--model` → 명부(바탕이 jsonl 과 같으면 `[1m]` 접미사 유지) → 대화 기록(jsonl) 마지막 assistant 의 message.model → 명부 · 모두 없으면 NORECORD · 명부와 «바탕이» 다를 때만 기록에 roster_model + 출력 끝 `(명부 model 다름: <값>)`.
#   R282 ② 은퇴인데 옛 행이 어느 명부에도 없으면(--seats 없음) 이름(ft-name-lint 통과)의 팀 명부(seats.json=v65 · seats-<팀>.json)에 은퇴 행을 만든 뒤 은퇴 — 옛 이름이 «다른» 명부 `_*` 칸에 현역이면 REJECT. 옛 이름이 lint 를 못 넘으면 «후계» 이름(r573 · 후계도 lint 실패 = REJECT)에서 팀·역할·에이전트를 뽑는다.
#   R282 ③ 후계 행 model = 도달 파일(<루트>/.fable-team/state/successor/<구>.json · env FT_SUCCESSOR_DIR)의 model → 없으면 옛 값.
#   R296 ④ `--record-only` + 행 없음 — ⓐ 옛 이름이 어느 명부 `_*` 칸의 값도 아님 ⓑ 같은 계보로 더 큰 번호가 `_*` 칸에 현역 ⓒ 그 tmux 세션 생존 — 셋 다 참일 때만 기록(retired_by = 그 현역 이름) · 명부 쓰기 0.
#   R400 `<구> --record-only --verdict <번호>` (판정 2304) — 승계가 아닌 «판정에 의한 닫기»(ft-seat-close --verdict 가 부른다): _replaced_by·R296 ⓑⓒ 없이 결속만으로 기록(retired_by = `verdict <번호>`) · 행 없음(다른 리포 좌석)은 ⓐ 만 · 명부 쓰기 0.
#   r427 `--record-only --keep-existing` (죽은 좌석 · ft-seat-close 가 tmux 세션 없을 때 부른다): 기존 기록 있으면 새 시도 0 → `RESUME kept <경로>` · 없고 세션도 없으면 대화 기록 탐색 1회
#     (~/.claude/history.jsonl 의 그 좌석 이름 줄 → project·sessionId → 그 jsonl 머리 64KB 에 `"agentName":"<구>"` «정확히 1개») → `RESUME ok` · 아니면 NORECORD.
#   r427 기록 실패(NORECORD)는 옛 기록을 건드리지 않는다(무효화 0 — 닫기는 zombie-clean 이 binding --expect 로 다시 본다) · 새 기록 «성공» 때만 옛 것을 <경로>.prev-<ts> 로.
set -uo pipefail
USAGE="usage: $0 <구> <후계> [--seats <파일>] | $0 <구> --record-only [--verdict <번호>] [--keep-existing] [--seats <파일>]"
OLD="${1:-}"; [ -n "$OLD" ] || { echo "$USAGE" >&2; exit 2; }
shift; NEW=""; RECONLY=0; ARG=""; VERDICT=""; KEEP=0
case "${1:-}" in ""|--*) ;; *) NEW="$1"; shift;; esac
while [ $# -gt 0 ]; do case "$1" in --seats) ARG="${2:-}"; shift 2;; --record-only) RECONLY=1; shift;; --keep-existing) KEEP=1; shift;; --verdict) VERDICT="${2:-}"; [[ "$VERDICT" =~ ^[0-9][0-9A-Za-z._-]*$ ]] || { echo "$USAGE — --verdict <번호>" >&2; exit 2; }; shift 2;; *) echo "unknown $1" >&2; exit 2;; esac; done
{ [ "$RECONLY" = 1 ] && [ -z "$NEW" ]; } || { [ "$RECONLY" = 0 ] && [ "$KEEP" = 0 ] && [ -n "$NEW" ] && [ "$OLD" != "$NEW" ] && [ -z "$VERDICT" ]; } || { echo "$USAGE" >&2; exit 2; }
ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
python3 - "${ARG:-${FT_SEATS_JSON:-}}" "${ROOT:-.}" "$OLD" "$NEW" "$RECONLY" "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)" "$VERDICT" "$KEEP" <<'PY'
import json, os, re, sys, glob, shutil, shlex, datetime, subprocess, collections
arg, root, old, new, reconly, here, verdict, keep = sys.argv[1:9]
sys.path.insert(0, here)   # 소유 결속 판정기 하나(R364) — 같은 폴더(자기 번들) 고정 경로 · 없으면 명시 rc 2(닫기 근거 0 · 옛 판정 후퇴 0)
try: import ft_seat_bind; from ft_roster_lib import load, dump, scan_cells, apply_cells, role_cell, held_roles, succ_role, fix_role   # 명부 읽기·원자 쓰기·남의 명부 칸 쓸기(r429→r465)·후계 role 도출(r499) = 같은 폴더 lib
except ImportError as e: print(f"ERROR 결속 판정기·명부 lib 없음 {here}/ft_seat_bind.py · ft_roster_lib.py ({e}) — 은퇴·기록 0"); sys.exit(2)
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
        m = r.get("message") if isinstance(r, dict) and r.get("type") == "assistant" else r.get("payload") if isinstance(r, dict) and r.get("type") == "turn_context" else None   # codex rollout = turn_context.payload.model (R400)
        m = m.get("model") if isinstance(m, dict) else None
        if isinstance(m, str) and m and not m.startswith("<"): return m   # <synthetic> 같은 자리표시 제외
    return None
def base_model(m): return re.sub(r"\[[^\]]*\]$", "", m)   # claude-x[1m] → claude-x
def argv_model(pid):   # 실행 중 프로세스의 `--model X`(접미사 포함 실제 값) — 없으면 None (r2)
    a = sh("ps", "-o", "args=", "-p", pid)
    for i, t in enumerate(a):
        if t == "--model" and i + 1 < len(a): return a[i + 1]
        if t.startswith("--model="): return t[8:] or None
        if t in ("-c", "--config") and i + 1 < len(a) and a[i + 1].startswith("model="): return a[i + 1][6:].strip("\"'") or None   # codex `-c model=X` (R400)
    return None
def find_resume(model, retired_by):   # (기록|None, 이유) — 소유 결속은 ft_seat_bind.py 하나(R364): pane pid 자신 ∪ 직계 자식 중 세션 파일 «정확히 1개» + tmux 칸(세션·window·pane)·pid·시작시각. 이름·mtime 추측 0
    b = ft_seat_bind.bind(old)
    if b["rc"] != 0: return None, ("조회 불가: " if b["rc"] == 2 else "") + b["reason"]
    pid, uuid, cwd, jsonl = str(b["pid"]), b["uuid"], b["cwd"], b["jsonl"]
    am, jm, rm = argv_model(pid), jsonl_model(jsonl), (model if isinstance(model, str) and model else None)
    use = am or (rm if rm and (not jm or base_model(rm) == base_model(jm)) else jm or rm)   # zombie-clean resume 이 --model 로 그대로 쓴다 — jsonl 값엔 [1m] 이 없어 200k 창 회귀(r2): argv → 명부(바탕 같으면 접미사 유지) → jsonl → 명부
    if not use: return None, "model 못 읽음(jsonl·명부)"
    eng = b.get("engine", "claude")   # codex 좌석(R400) = rollout 결속 · 재개 = resume_cmd(zombie-clean resume 은 claude 기록만 받는다)
    rec = collections.OrderedDict(name=old, engine=eng, pid=b["pid"], uuid=uuid, jsonl=jsonl, cwd=cwd, model=use, retired_by=retired_by, at=datetime.datetime.now().isoformat(timespec="seconds"), binding=b["binding"])
    if eng == "codex": rec["resume_cmd"] = shlex.join(["codex"] + sh("ps", "-o", "args=", "-p", pid)[1:] + ["resume", uuid])
    if eng == "claude" and b.get("name") != old: rec["session_name"] = b.get("name")   # 세션 파일 name(참고 칸) — 소유 증거는 binding
    if rm and base_model(rm) != base_model(use): rec["roster_model"] = rm   # 바탕이 다를 때만 — 조용히 덮지 않는다
    return rec, ""
DEAD_SRC = "dead-agent-name"
def dead_resume(model, retired_by):   # r427 죽은 좌석(tmux 없음 · pane 결속 불가) — 대화 기록 탐색 1회 · 소유 증거 = jsonl 의 agent-name 줄(입력 글자만으로 고르지 않는다)
    home, hits, seen = os.path.expanduser("~"), set(), set()
    pat, key = f'"agentName":"{old}"'.encode(), old.encode()
    try:
        with open(f"{home}/.claude/history.jsonl", "rb") as f:
            for ln in f:
                if key not in ln: continue
                try: h = json.loads(ln)
                except ValueError: continue
                p, u = h.get("project"), h.get("sessionId")
                if not (isinstance(p, str) and isinstance(u, str) and u) or (p, u) in seen: continue
                seen.add((p, u)); jl = f"{home}/.claude/projects/{re.sub('[^A-Za-z0-9]', '-', p)}/{u}.jsonl"
                try:
                    with open(jl, "rb") as g: head = g.read(65536)
                except OSError: continue
                if pat in head: hits.add((jl, p, u))
    except OSError as e: return None, f"죽은 좌석 · 대화 기록 목록 못 읽음 ({e.strerror})"
    if len(hits) != 1: return None, f"죽은 좌석 · agent-name 대화 기록 {len(hits)}개"
    jl, cwd, uuid = hits.pop(); jm, rm = jsonl_model(jl), (model if isinstance(model, str) and model else None)
    use = rm if rm and (not jm or base_model(rm) == base_model(jm)) else jm or rm
    if not use: return None, "죽은 좌석 · model 못 읽음(jsonl·명부)"
    if not os.path.isdir(cwd): return None, f"죽은 좌석 · 작업 폴더 없음 {cwd}"
    return collections.OrderedDict(name=old, engine="claude", pid=None, uuid=uuid, jsonl=jl, cwd=cwd, model=use, retired_by=retired_by,
                                   at=datetime.datetime.now().isoformat(timespec="seconds"), binding=dict(source=DEAD_SRC)), ""
RD = os.environ.get("ZC_RESUME_DIR") or os.path.expanduser("~/.claude/state/seat-resume"); RP = f"{RD}/{old}.json"
def write_record(rec, why):   # 재개 기록(zombie-clean 이 직전 세대를 닫아도 되는 근거) — 실패는 NORECORD 로 보이고 직전 세대는 keep-last-2 로 남는다
    if rec and rec["binding"].get("source") != DEAD_SRC:   # 기록 직전 재확인 1회(R364) — 결속이 그새 바뀌었으면(pane·pid 교체) 기록 0
        b2 = ft_seat_bind.bind(old)
        if b2["rc"] != 0 or b2["binding"] != rec["binding"]: rec, why = None, "기록 직전 재확인 불일치"
    rd, rp = RD, RP
    try:
        if not rec: raise ValueError(why)
        os.makedirs(rd, exist_ok=True); json.dump(rec, open(rp + ".tmp", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
        prev = rp + ".prev-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S") if os.path.exists(rp) else ""
        if prev: os.replace(rp, prev)   # r427 — 옛 기록은 새 기록 «성공» 때만 옆으로(<이름>.json 만 닫기 근거)
        os.replace(rp + ".tmp", rp)
        print(f"RESUME ok {rp}" + (f" (명부 model 다름: {rec['roster_model']})" if rec.get("roster_model") else "") + (f" · 이전 기록 {prev}" if prev else ""))
    except (OSError, ValueError) as e:   # r427 — 옛 기록 무효화 0(죽은 좌석의 유일한 재개 근거를 지우던 길) · 닫기 판정은 zombie-clean 의 binding --expect 가 다시 본다
        print(f"NORECORD {old} {e}" + (f" · 기존 기록 보존 {rp}" if os.path.exists(rp) else ""))
def record(model, retired_by):   # 기록 모드 공통 — r427 --keep-existing: 기존 기록 있으면 새 시도 0 · 세션 없으면 대화 기록 탐색
    if keep == "1" and os.path.exists(RP): print(f"RESUME kept {RP}"); return True
    rec, why = dead_resume(model, retired_by) if keep == "1" and not alive(old) else find_resume(model, retired_by)
    write_record(rec, why); return rec
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
mkrow = False; cand = [arg] if arg else [f for f in rosters if isinstance(load(f), dict) and old in load(f)]
if verdict:   # R400 판정 닫기 — 현역 역할 좌석도 기록(판정 번호가 승인) · 행 없음 = R296 ⓐ 만 · 명부 쓰기 0
    if len(cand) > 1: reject(f"명부 후보 {len(cand)}개 (키 {old}) — --seats 로 지정")
    o = load(cand[0]).get(old) if cand and isinstance(load(cand[0]), dict) else None
    if not isinstance(o, dict):
        for f in rosters:
            if active_in(f): reject(f"{old} 은 {os.path.basename(f)} 의 `_*` 칸 값인데 행이 없음 — 명부 확인 — 다른 리포 좌석이면: FT_ROOT=<그 설치본 루트> … --seats <그 루트>/.fable-team/seats.json")
        o = None
    rec = record((o or {}).get("model"), f"verdict {verdict}")
    if o is None and not rec: print("  - 다른 리포 좌석이면: FT_ROOT=<그 설치본 루트> … --seats <그 루트>/.fable-team/seats.json")   # R400 r3 §D — 행 없음 NORECORD 에도 같은 안내(첫 줄 꼴 그대로)
    sys.exit(0)
if not cand and not arg and "#" in old and reconly == "1":   # R296 ④ — 행 없는 옛 좌석: ⓐⓑⓒ 셋 다 참일 때만 기록(명부 쓰기 0)
    base, _, gen = old.rpartition("#"); later = []
    for f in rosters:
        dd = load(f)
        for k, v in (dd.items() if isinstance(dd, dict) else []):
            if not (k.startswith("_") and isinstance(v, str)): continue
            if v == old: reject(f"{old} 은 현역({os.path.basename(f)} {k}) — 기록 모드는 은퇴한 좌석만")
            b, _, g = v.rpartition("#")
            if b == base and g.isdigit() and gen.isdigit() and int(g) > int(gen): later.append((int(g), v))
    if not later: reject(f"{old} 보다 번호가 큰 같은 계보 현역 이름이 어느 명부 `_*` 칸에도 없음 — 다른 리포 좌석이면: FT_ROOT=<그 설치본 루트> … --seats <그 루트>/.fable-team/seats.json")
    rb = max(later)[1]
    if not alive(rb): reject(f"현역 {rb} 의 tmux 세션이 없음 — 다른 리포 좌석이면: FT_ROOT=<그 설치본 루트> … --seats <그 루트>/.fable-team/seats.json")
    record(None, rb); sys.exit(0)
if not cand and not arg and reconly != "1":   # R282 ② — 옛 행이 어느 명부에도 없는 «지금 승계 중»: 팀 명부에 은퇴 행을 만든다
    lint = lambda n: subprocess.run(["bash", f"{here}/ft-name-lint.sh", n], capture_output=True, text=True).returncode; ok, okn = lint(old) == 0, bool(new) and lint(new) == 0   # R573 — 옛 이름 lint 실패 = «칸 뽑을 이름» 만 후계로 후퇴(새 이름 lint 규칙 불변)
    if not ok and not (okn and not any(active_in(f) for f in rosters)): reject(f"명부 후보 0개 (키 {old}) · 이름 lint 실패" + (" · 후계도 이름 lint 실패" if not okn else " · 다른 명부 `_*` 칸의 현역 — --seats 로 지정"))
    src = old if ok else new
    if not ok: print(f"INFO 옛 이름 lint 실패 — 후계 {new} 이름으로 팀·역할·에이전트")
    parts = src.rpartition("#")[0].split("-"); tf = root + "/.fable-team/" + ("seats.json" if parts[1] == "v65" else f"seats-{parts[1]}.json")
    if not isinstance(load(tf), dict): reject(f"명부 후보 0개 (키 {old}) · 팀 명부 없음 {tf} — --seats 로 지정")
    cand, mkrow = [tf], True
if len(cand) != 1: print(f"REJECT 명부 후보 {len(cand)}개 (키 {old}) — --seats 로 지정"); sys.exit(1)
p = cand[0]; d = load(p); o = d.get(old) if isinstance(d, dict) else None
if mkrow: rec0, _ = find_resume(None, new); o = collections.OrderedDict([("role", parts[2]), ("agent", parts[3]), ("model", rec0["model"] if rec0 else None), ("tick", None), ("_created_by", "retire")])
if not isinstance(o, dict): print(f"REJECT {p} 에 구 행 {old} 없음"); sys.exit(1)
if reconly == "1":   # 기록 모드 — 명부 쓰기 0(.bak 도 0) · 은퇴한 행(_replaced_by 있음)만
    rb = o.get("_replaced_by")
    if not (isinstance(rb, str) and rb): print(f"REJECT {old} 은 현역 행(_replaced_by 없음) — 기록 모드는 은퇴한 좌석만 file={p}"); sys.exit(1)
    record(o.get("model"), rb); sys.exit(0)
noop, n = o.get("_replaced_by") == new, d.get(new)   # r465 재실행도 남은 칸 보정·빈 칸 채우기 — 바꿀 것 0 일 때만 옛 NOOP
if not noop and isinstance(n, dict) and n.get("_replaced_by"): print(f"REJECT 후계 {new} 가 이미 은퇴(_replaced_by={n['_replaced_by']}) — 쓰기 0"); sys.exit(3)
others, cells, bad = scan_cells(p, old)   # r465 같은 폴더(루트 .fable-team) 다른 명부 전부 — 값이 <구> 인 `_*` 칸 전부(역할·라우팅)
if bad: print(f"ERROR 명부 JSON 손상 {bad} — 전부 검증 뒤 쓰기라 쓰기 0 file={p}"); sys.exit(1)
keys = [k for k, v in d.items() if k.startswith("_") and v == old]; fc, fv = (None, None) if keys else role_cell(d, new)   # r465 사례 2 — 옛 이름 칸 0 이면 후계 역할 칸이 빈 값/없음일 때 채움
if fc and isinstance(fv, str) and fv not in ("", new) and alive(fv): reject(f"{os.path.basename(p)} {fc} = 살아 있는 다른 좌석 {fv} — 채우지 않는다(쓰기 0 · 추측 0)")
fc = fc if fv in (None, "") else None; rc_ = held_roles(d, keys + [fc], new); pr = n.get("role") if isinstance(n, dict) else o.get("role"); rfx = fix_role(o, n, rc_, new) if noop else ""   # r499 ⓙ 재실행 — 현역 역할 칸 값인 후계가 stop-ready 꼴이면 도출 role(메모리 · 아래 dump)
if noop and not (keys or cells or fc or rfx): print(f"NOOP {old} 은 이미 {new} 로 은퇴 file={p}"); sys.exit(0)
own, ts, rec, why = not noop or bool(keys or fc or rfx),datetime.datetime.now().strftime("%Y%m%d%H%M%S"), None, ""   # own = 자기 명부를 쓰나
if own: shutil.copy(p, p + ".bak-retire-" + ts)
if not noop:
    if mkrow: d[old] = o   # .bak 뒤에 — 아래 은퇴 흐름이 이 행을 닫는다
    rec, why = find_resume(o.get("model"), new)   # 읽기만 — 실패해도 은퇴는 그대로(기록 결과는 rc 에 섞지 않는다 · H3)
    if rec: o["_resume_uuid"] = rec["uuid"]
    else: o.pop("_resume_uuid", None)   # 옛 은퇴가 남긴 값이 닫기 근거로 남지 않게(DA⑥ H1)
    role, tick, sr = o.get("role"), o.get("tick"), succ_role(o, rc_, new)   # r499 후계 role = 옛 role · 옛 role 이 stop-ready 면 _retired_role → 옮기는 역할 칸 → 이름 토큰(사슬 상속 0)
    if role != "stop-ready": o["_retired_role"] = role
    o["tick"] = None; o["_replaced_by"] = new; o["role"] = "stop-ready"
    if not isinstance(n, dict):
        n = d[new] = collections.OrderedDict([("role", sr),("agent", o.get("agent", "claude")), ("model", arrival_model() or o.get("model") or (rec or {}).get("model")), ("tick", tick)])
    else:
        if role != "stop-ready" or n.get("role") == "stop-ready": n["role"] = sr   # r499 ⓘ 후계가 stop-ready 꼴(_replaced_by 없음 — 위 rc 3 이 걸렀다)이면 도출값
        if not n.get("tick"): n["tick"] = tick
    if o.get("index") and not n.get("index"): n["index"] = o["index"]   # R370 카드 경로 상속(덮어쓰기 0) — 없으면 nano-close ⑥ 이 «카드 못 찾음»
    n["_replaces"] = sorted(set(n.get("_replaces", []) + [old]))
for k in keys + ([fc] if fc else []): d[k] = new
if own: dump(p, d)   # 쓰기 중 죽어도 원본 무손상(tmp→교체)
roles, rk = apply_cells(others, cells, new, ts)   # r465 남의 명부 = 값이 <구> 인 칸 전부 · 파일마다 .bak
tail = f"keys={keys} files={int(own) + len(cells)} roles={roles} routes={rk}" + (f" FILLED {os.path.basename(p)}:{fc}" if fc else "") + (f" role stop-ready->{n['role']}" if isinstance(n, dict) and pr == "stop-ready" and n.get("role") != "stop-ready" else "")
if noop: print(f"FIXED {old} -> {new} file={p} {tail}"); sys.exit(0)
print(f"RETIRED {old} -> {new} file={p} {tail}")
write_record(rec, why)
PY
prc=$?
# r448: 은퇴 뒤 옛 좌석의 «고아(ppid 1)» 백그라운드 루프만 정지(--orphans-only — 살아 있는 에이전트·pane 나무는 zombie-clean 이 재개 기록으로 닫는다) · 기록 모드·실패는 0
[ "$prc" -eq 0 ] && [ "$RECONLY" = 0 ] || exit "$prc"
RO="$(bash "${FT_SEAT_REAP_BIN:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft-seat-reap.sh}" "$OLD" --orphans-only 2>&1)"; rrc=$?; RL="$(printf '%s\n' "$RO" | grep -oE 'left=[0-9?]+' | tail -1)"
printf '%s\n' "$RO" >&2
[ "$rrc" -eq 0 ] && [ "$RL" = left=0 ] || { echo "CLOSE-FAIL reap ${RL:-left=?} rc=$rrc — $OLD 은퇴 기록은 끝남 · 고아 루프 잔존(사람 판단)"; exit 1; }
echo "reap left=0 rc=0"
