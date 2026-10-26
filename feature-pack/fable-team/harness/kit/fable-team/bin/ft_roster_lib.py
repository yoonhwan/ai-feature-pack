"""ft_roster_lib.py — 명부(seats*.json) 읽기·원자 쓰기·라우팅 칸 쓸기 공용 (ft-seat-retire.sh · ft-seat-close.sh 가 같은 폴더에서 import).
r429 묶음: 두 도구에 같은 글자로 있던 load/쓰기와 retire 의 라우팅 칸 쓸기를 한 곳으로 옮겼다(동작 불변 · 줄 수 상한).
r5(seat_facts): 명부 경로·행·agent·role·재개 기록 경로를 입구에서 1회 확정(닫기 도구의 갈래·자식 재해석 0).
r960: pi 좌석 재개 기록(pi_seat_resume)도 여기 — ft-seat-retire.sh 는 200줄 상한이라 파일 안에 못 넣는다(시험 ⓔ 가 줄 수를 잰다)."""
import collections, datetime, glob, json, os, shutil, subprocess, sys

ROUTE = ("_hil_route", "_planner", "_desk_route")   # r429 라우팅 칸(+ 이름이 _route 로 끝나는 칸) · r465 부터 은퇴는 남의 명부 역할 칸도 바꾼다(scan_cells) — 이 표는 출력 roles/routes 구분용


def is_route(k): return k in ROUTE or k.endswith("_route")


def load(f):
    try: return json.load(open(f, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
    except (OSError, ValueError): return None


def dump(f, dd):   # 쓰기 중 죽어도 원본 무손상 — tmp 에 다 쓴 뒤 한 번에 교체(N3 · D3 승계 원자성)
    tmp = f + ".tmp-" + str(os.getpid())
    with open(tmp, "w", encoding="utf-8") as fh: json.dump(dd, fh, ensure_ascii=False, indent=2); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
    shutil.copymode(f, tmp); os.replace(tmp, f)


def scan_routes(p, old):   # r429 같은 폴더(루트 .fable-team) 다른 명부 전부 → (others{파일: 명부}, routes{파일: [칸…]} 바꿀 것 있는 파일만, bad[손상 파일 이름])
    others = {f: load(f) for f in sorted(glob.glob(os.path.dirname(os.path.abspath(p)) + "/seats*.json")) if os.path.abspath(f) != os.path.abspath(p)}
    bad = [os.path.basename(f) for f, v in others.items() if not isinstance(v, dict)]
    routes = {} if bad else {f: ks for f, ks in ((f, [k for k, v in dd.items() if is_route(k) and v == old]) for f, dd in others.items()) if ks}
    return others, routes, bad


def apply_routes(others, routes, new, ts):   # r429 남의 명부 = 라우팅 칸만 · 파일마다 .bak-retire-<ts> → 출력용 [파일:칸…]
    for f, ks in routes.items():
        shutil.copy(f, f + ".bak-retire-" + ts); others[f].update((k, new) for k in ks); dump(f, others[f])
    return [os.path.basename(f) + ":" + k for f, ks in routes.items() for k in ks]


def role_cell(dd, new):   # r465 사례 2 — 후계 이름(byz-<팀>-<역할>-<에이전트>#N)의 역할 칸(_master·_arch·_da·_tester) · 후계 행 실재일 때만 → (칸, 지금 값) · 아니면 (None, None)
    c = "_" + (new.rpartition("#")[0].split("-") + ["", "", ""])[2]
    return (c, dd.get(c)) if c in ("_master", "_arch", "_da", "_tester") and isinstance(dd.get(new), dict) else (None, None)


ROLES = ("_master", "_arch", "_desk", "_da", "_tester", "_pm")   # r499 후계 role 도출용 역할 칸


def held_roles(dd, keys, new):   # r499 후계가 맡는(맡을) 역할 칸 — 옮기는 칸(keys 순) + 이미 값이 후계인 칸
    return [k for k in list(keys) + [c for c in ROLES if dd.get(c) == new] if k in ROLES]


def succ_role(o, cells, name):   # r499 후계 role — 옛 role(stop-ready 아니면) → 옛 _retired_role → 역할 칸(cells 순) 이름 → 이름 토큰(byz-<팀>-<역할>-<에이전트>#N) · 다 없으면 stop-ready(추측 0)
    if o.get("role") != "stop-ready": return o.get("role")
    r = o.get("_retired_role")
    if isinstance(r, str) and r and r != "stop-ready": return r
    for k in cells:
        if k in ROLES: return k[1:]
    t = "_" + (name.rpartition("#")[0].split("-") + ["", "", ""])[2]
    return t[1:] if t in ROLES else "stop-ready"


def fix_role(o, n, cells, name):   # r499 재실행 보정 — 후계 행이 역할 칸 값(cells) ∧ role=stop-ready ∧ _replaced_by 없음 → 도출 role 로 고침(메모리 · 쓰기는 호출자) → 고친 role · 아니면 ""
    ok = bool(cells) and isinstance(n, dict) and n.get("role") == "stop-ready" and not n.get("_replaced_by")
    r = succ_role(o, cells, name) if ok else "stop-ready"
    if r != "stop-ready": n["role"] = r
    return "" if r == "stop-ready" else r


def scan_cells(p, old):   # r465 같은 폴더 다른 명부 전부 — 최상위 `_*` 문자열 칸 중 값 == old 전부(라우팅·역할 구분 없이 · 공유 arch 의 남의 팀 `_arch` 포함) · 꼴은 scan_routes 와 같다
    others, _, bad = scan_routes(p, old)
    cells = {} if bad else {f: ks for f, ks in ((f, [k for k, v in dd.items() if k.startswith("_") and v == old]) for f, dd in others.items()) if ks}
    return others, cells, bad


def apply_cells(others, cells, new, ts):   # r465 = apply_routes 와 같은 쓰기(파일마다 .bak-retire-<ts> · tmp→교체) → (roles[파일:칸…], routes[파일:칸…]) 출력용
    out = apply_routes(others, cells, new, ts)
    return [c for c in out if not is_route(c.split(":", 1)[1])], [c for c in out if is_route(c.split(":", 1)[1])]


PI_NOREC = "pi 세션 없음 — 산출 커밋 보존"   # r960 ⓓ: ft-seat-close 가 이 글자를 보고 «살아 있는 pi 좌석»도 닫는다(사유가 곧 근거) · claude 좌석은 지금처럼 HELD


def _pi_sh(*a):   # 외부 조회 7초 상한 · 실행 불가·시간 초과 = "" (ft-seat-retire 의 sh 와 같은 규율)
    try: return subprocess.run(a, capture_output=True, text=True, timeout=7, env={**os.environ, "LC_ALL": "C"}).stdout
    except (OSError, subprocess.SubprocessError): return ""


def _pi_model(path, head):   # r960 ⓢ model 은 세션 파일 «전체» 에서 마지막 model_change.modelId(pi 머리 줄에는 modelId 가 없다) → 없으면 머리 modelId
    last = None
    try:
        for ln in open(path, encoding="utf-8"):
            try: d = json.loads(ln)
            except ValueError: continue
            if isinstance(d, dict) and d.get("type") == "model_change" and isinstance(d.get("modelId"), str) and d["modelId"]: last = d["modelId"]
    except OSError: return None
    if last: return last
    return head.get("modelId") if isinstance(head.get("modelId"), str) and head.get("modelId") else None


def seat_facts(arg, env, root, seat, rd):   # r5 — 명부 경로·좌석 행·agent·role·재개 기록 경로를 «입구에서 1회» 확정한다(닫기 도구가 갈래마다·자식이 다시 읽지 않는다) → (명부파일, agent, role, 재개기록경로) · 판정 불가 = print + exit 1
    files = sorted(glob.glob(root + "/.fable-team/seats*.json"))
    cand = [arg] if arg else [env] if env else files
    cand = [f for f in cand if isinstance(load(f), dict) and isinstance(load(f).get(seat), dict)]
    if len(cand) > 1:   # r5 ① — 후보 2개+ = 어느 행이 사실인지 모른다(판정 아님 · 명부 쓰기 0 · kill 0)
        print(f"REJECT 판정 안 함 — 명부 후보 {len(cand)}개 (키 {seat}) · --seats 로 지정"); raise SystemExit(1)
    if not cand: return ("", "", "", rd + "/" + seat + ".json")   # 행 없음 = 부르는 쪽의 NOROW/NORECORD 갈래 그대로
    p = cand[0]; o = load(p)[seat]; a, r = o.get("agent") or "", o.get("role") or ""
    seen = [] if arg else files   # r5 ⓦ2 — --seats 는 확정이 이긴다(FT_SEATS_JSON·루트 글롭을 보지 않는다)
    for f in seen:   # r5 ④ — 확정 밖 명부의 같은 좌석이 다른 agent/role 이면 판정 아님(REJECT · 명부 쓰기 0 · kill 0)
        o2 = load(f).get(seat) if f != p and isinstance(load(f), dict) else None
        if not isinstance(o2, dict): continue
        a2, r2 = o2.get("agent") or "", o2.get("role") or ""
        if (a, r) != (a2, r2):
            print(f"REJECT {seat} 명부 불일치 {p}={a or '-'}/{r or '-'} ≠ {f}={a2 or '-'}/{r2 or '-'} — 명부 쓰기 0 · kill 0"); raise SystemExit(1)
    if len([f for f in seen if isinstance(load(f), dict) and isinstance(load(f).get(seat), dict)]) > 1:
        print(f"WARN {seat} 명부 중복 등록 — 확정 {p} 로 진행", file=sys.stderr)   # r5 — 같으면 진행(중복 등록 정리는 범위 밖 · 경고 1줄)
    return (p, a, r, rd + "/" + seat + ".json")


def pi_seat_resume(seat, model, retired_by):   # r960 ⓒ — pi 좌석 재개 기록 = 그 pane cwd 의 pi 세션 파일(가장 최근 1개 · 첫 줄 cwd 가 pane cwd 와 같고 timestamp ≥ 좌석 프로세스 시작) → (record|None, 이유)
    #   폴더 이름 인코딩 추측 0 — 세션 파일 첫 줄(type=session)의 cwd 로 고른다. 뿌리는 FT_PI_SESSIONS(시험) 아니면 ~/.pi/agent/sessions.
    pid, _, cwd = _pi_sh("tmux", "display", "-p", "-t", "=" + seat + ":", "#{pane_pid} #{pane_current_path}").strip().partition(" ")   # cwd 에 공백이 있어도 살린다(첫 칸 = pid)
    pid = pid if pid.isdigit() else ""; cwd = cwd if pid else ""
    if not cwd or not os.path.isdir(cwd): return None, PI_NOREC + " · pane cwd 못 읽음(tmux 좌석 없음·경로 아님)"
    try: since = datetime.datetime.utcfromtimestamp(datetime.datetime.strptime(" ".join(_pi_sh("ps", "-o", "lstart=", "-p", pid).split()), "%a %b %d %H:%M:%S %Y").timestamp()).strftime("%Y-%m-%dT%H:%M:%S")
    except ValueError: since = ""
    best = None
    for f in glob.glob(os.path.expanduser(os.environ.get("FT_PI_SESSIONS") or "~/.pi/agent/sessions") + "/*/*.jsonl"):
        try: h = json.loads(open(f, encoding="utf-8").readline() or "{}")
        except (OSError, ValueError): continue
        if isinstance(h, dict) and h.get("type") == "session" and h.get("cwd") == cwd and str(h.get("timestamp") or "") >= since and (best is None or os.path.getmtime(f) > best[0]): best = (os.path.getmtime(f), f, h)
    if not best: return None, PI_NOREC + f" · {cwd} 세션 파일 0"
    use = model if isinstance(model, str) and model else _pi_model(best[1], best[2])   # r960-mut:firstline
    if not use: return None, "pi 좌석 · model 못 읽음(세션 파일·명부)"
    return collections.OrderedDict(name=seat, engine="pi", pid=int(pid), uuid=best[2].get("id"), jsonl=best[1], cwd=cwd, model=use, retired_by=retired_by,
                                   at=datetime.datetime.now().isoformat(timespec="seconds"), binding=dict(source="pi-session", session=cwd)), ""
