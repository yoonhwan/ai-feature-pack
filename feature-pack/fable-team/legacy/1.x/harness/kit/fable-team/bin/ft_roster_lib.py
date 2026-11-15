"""ft_roster_lib.py — 명부(seats*.json) 읽기·원자 쓰기·라우팅 칸 쓸기 공용 (ft-seat-retire.sh · ft-seat-close.sh 가 같은 폴더에서 import).
r429 묶음: 두 도구에 같은 글자로 있던 load/쓰기와 retire 의 라우팅 칸 쓸기를 한 곳으로 옮겼다(동작 불변 · 줄 수 상한).
r5(seat_facts): 명부 경로·행·agent·role·재개 기록 경로를 입구에서 1회 확정(닫기 도구의 갈래·자식 재해석 0).
r960: pi 좌석 재개 기록(pi_seat_resume)도 여기 — ft-seat-retire.sh 는 200줄 상한이라 파일 안에 못 넣는다(시험 ⓔ 가 줄 수를 잰다)."""
import collections, datetime, glob, json, os, re, shutil, subprocess, sys

ROUTE = ("_hil_route", "_planner", "_desk_route")   # r429 라우팅 칸(+ 이름이 _route 로 끝나는 칸) · r465 부터 은퇴는 남의 명부 역할 칸도 바꾼다(scan_cells) — 이 표는 출력 roles/routes 구분용


def is_route(k): return k in ROUTE or k.endswith("_route")


def load(f):
    try: return json.load(open(f, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
    except (OSError, ValueError): return None


def dump(f, dd):   # 쓰기 중 죽어도 원본 무손상 — tmp 에 다 쓴 뒤 한 번에 교체(N3 · D3 승계 원자성)
    tmp = f + ".tmp-" + str(os.getpid())
    with open(tmp, "w", encoding="utf-8") as fh: json.dump(dd, fh, ensure_ascii=False, indent=2); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
    shutil.copymode(f, tmp); os.replace(tmp, f)


BAK_TS = re.compile(r"(?:[0-9]{14}|[0-9]{8}-[0-9]{6}(?:[0-9]{6})?)\Z")   # r2043 생성기가 실제 쓰는 ts 꼴만(14자리 · YYYYmmdd-HHMMSS · +마이크로초 6 = keyrotate) · DA HOLD 1: 그 밖 꼬리 = 손 0


def bak_cap_n(v):   # r2043 A2 상한 = 정수 50~100 · 없거나 밖이면 50
    try:
        n = int(str(v).strip())
    except (TypeError, ValueError):
        return 50
    return n if 50 <= n <= 100 else 50


def _bak_key(ts):   # r2043 이름 속 ts 숫자만 → (자릿수, 숫자) 순서
    t = re.sub(r"\D", "", ts)
    return len(t), t


def bak_cap(path, kind, cap=None):   # r2043 A1·A3·A4 <path>.bak-<kind>-<ts> 일반 파일만 · ts 오래된 것부터 지워 상한개 남김 · 실패 = stderr WARN 1줄(예외 0) → 지운 이름 목록
    n, pre, gone, err = bak_cap_n(os.environ.get("FT_BAK_CAP") if cap is None else cap), os.path.basename(path) + ".bak-" + kind + "-", [], []
    d = os.path.dirname(os.path.abspath(path))
    try:
        ok = [x for x in os.listdir(d) if x.startswith(pre) and BAK_TS.match(x[len(pre):]) and not os.path.islink(os.path.join(d, x)) and os.path.isfile(os.path.join(d, x))]
        for x in sorted(ok, key=lambda x: (_bak_key(x[len(pre):]), x))[:-n]:
            try:
                os.remove(os.path.join(d, x))
                gone.append(x)
            except OSError as e:
                err.append(f"{x}({e.strerror})")
    except Exception as e:
        err.append(f"{d}({e})")
    if err:
        print(f"WARN 백업 상한 정리 실패 {len(err)}개 — {err[0]}{' 외' if len(err) > 1 else ''} · 본 작업 영향 0", file=sys.stderr)
    return gone


def scan_routes(p, old):   # r429 같은 폴더(루트 .fable-team) 다른 명부 전부 → (others{파일: 명부}, routes{파일: [칸…]} 바꿀 것 있는 파일만, bad[손상 파일 이름])
    others = {f: load(f) for f in sorted(glob.glob(os.path.dirname(os.path.abspath(p)) + "/seats*.json")) if os.path.abspath(f) != os.path.abspath(p)}
    bad = [os.path.basename(f) for f, v in others.items() if not isinstance(v, dict)]
    routes = {} if bad else {f: ks for f, ks in ((f, [k for k, v in dd.items() if is_route(k) and v == old]) for f, dd in others.items()) if ks}
    return others, routes, bad


def apply_routes(others, routes, new, ts):   # r429 남의 명부 = 라우팅 칸만 · 파일마다 .bak-retire-<ts> → 출력용 [파일:칸…]
    for f, ks in routes.items():
        shutil.copy(f, f + ".bak-retire-" + ts); others[f].update((k, new) for k in ks); dump(f, others[f])
        bak_cap(f, "retire")   # r2043 종류별 상한
    return [os.path.basename(f) + ":" + k for f, ks in routes.items() for k in ks]


def name_cell(name):   # r1641 이름 → 명부 역할 칸 — <프로젝트>-<팀>-<역할>[-<석K>]-<에이전트>#N · 석 0·옛 꼴(석 칸 없음) = _<역할> · K≥1 = _<역할>-<K> · nano·토큰 부족·앞자리 0 = None(추측 0)
    t = name.rpartition("#")[0].split("-")
    if len(t) < 3 or not t[2] or t[2] == "nano": return None
    k = t[3] if len(t) >= 5 and t[3] and set(t[3]) <= set("0123456789") else "0"
    return None if k[0] == "0" and k != "0" else "_" + t[2] + ("" if k == "0" else "-" + k)


def role_seats(dd, role):   # r1641 역할 → 석 목록 — 명부 `_<역할>`(석 0)·`_<역할>-<K>` 중 값이 빈 문자열 아닌 칸 → [(K, 이름)…] K 순 · `_<역할>x` 같은 비슷한 키 0
    ms = ((re.fullmatch("_" + re.escape(role) + "(?:-([1-9][0-9]*))?", c), v) for c, v in dd.items())
    return sorted((int(m.group(1) or 0), v) for m, v in ms if m and isinstance(v, str) and v)


def role_cell(dd, new):   # r465 사례 2 — 후계 이름의 역할 칸(_master·_arch·_desk·_da·_tester · r1641 석 K≥1 = _<역할>-<K>) · 후계 행 실재일 때만 → (칸, 지금 값) · 아니면 (None, None) (r1461: _desk 추가)
    c = name_cell(new) or ""
    return (c, dd.get(c)) if c.split("-")[0] in ("_master", "_arch", "_desk", "_da", "_tester") and isinstance(dd.get(new), dict) else (None, None)


ROLES = ("_master", "_arch", "_desk", "_da", "_tester", "_pm")   # r499 후계 role 도출용 역할 칸


def held_roles(dd, keys, new):   # r499 후계가 맡는(맡을) 역할 칸 — 옮기는 칸(keys 순) + 이미 값이 후계인 칸
    return [k for k in list(keys) + [c for c in ROLES if dd.get(c) == new] if k in ROLES]


def succ_role(o, cells, name):   # r499 후계 role — 옛 role(stop-ready 아니면) → 옛 _retired_role → 역할 칸(cells 순) 이름 → 이름 토큰(byz-<팀>-<역할>-<에이전트>#N) · 다 없으면 stop-ready(추측 0)
    if o.get("role") != "stop-ready": return o.get("role")
    r = o.get("_retired_role")
    if isinstance(r, str) and r and r != "stop-ready": return r
    for k in cells:
        if k in ROLES: return k[1:]
    t = (name_cell(name) or "").split("-")[0]   # r1641 석 칸이 있어도 역할 = 칸의 역할 부분
    return t[1:] if t in ROLES else "stop-ready"


def role_tok(name):   # r1461 이름 토큰 역할(byz-<팀>-<역할>-<에이전트>#N) · 토큰 밖 = ""(추측 0 · ft-successor-open 선등록과 같은 표)
    return t if (t := (name.rpartition("#")[0].split("-") + ["", "", ""])[2]) in ("master", "arch", "desk", "da", "tester", "pm") else ""


def fix_role(o, n, cells, name):   # r499 재실행 보정 — 후계 행이 역할 칸 값(cells) ∧ role=stop-ready ∧ _replaced_by 없음 → 도출 role 로 고침(메모리 · 쓰기는 호출자) → 고친 role · 아니면 ""
    live, tok = isinstance(n, dict) and not n.get("_replaced_by"), role_tok(name)   # r1461 tok = 이름 토큰 역할
    ok = bool(cells) and live and n.get("role") == "stop-ready"
    pre = live and bool(tok) and n.get("role") != tok and isinstance(n.get("persona"), str) and n["persona"].startswith("successor (auto-registered") and bool(n.get("_replaces"))   # r1461 선등록(r1435) 행 — persona 문구만으로는 고치지 않는다(조건 3개 다)
    if not (ok or pre): return ""
    r = succ_role(o, cells, name)
    if tok and r != tok:   # r1461 VERDICT arch#241 §A — 도출 ≠ 이름 토큰 = 추측으로 고치지 않는다(명부 쓰기 0 · 호출자 안에서 exit 1)
        print(f"REJECT 후계 {name} 도출 role={r} ≠ 이름 토큰 {tok} — 추측 채움 0(명부 쓰기 0)"); raise SystemExit(1)
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


def seat_facts(arg, env, root, seat, rd):   # r5 — 명부 경로·좌석 행·agent·role·재개 기록 경로를 «입구에서 1회» 확정한다(닫기 도구가 갈래마다·자식이 다시 읽지 않는다) → (명부파일, agent, role, 재개기록경로, _master 칸) · 판정 불가 = print + exit 1
    files = sorted(glob.glob(root + "/.fable-team/seats*.json"))
    cand = [arg] if arg else [env] if env else files
    cand = [f for f in cand if isinstance(load(f), dict) and isinstance(load(f).get(seat), dict)]
    if len(cand) > 1:   # r5 ① — 후보 2개+ = 어느 행이 사실인지 모른다(판정 아님 · 명부 쓰기 0 · kill 0)
        print(f"REJECT 판정 안 함 — 명부 후보 {len(cand)}개 (키 {seat}) · --seats 로 지정"); raise SystemExit(1)
    if not cand: return ("", "", "", rd + "/" + seat + ".json", "")   # 행 없음 = 부르는 쪽의 NOROW/NORECORD 갈래 그대로
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
    m = load(p).get("_master") if isinstance(load(p), dict) else None   # r1568 — master 칸도 «입구 1회» 확정(닫기 도구가 명부를 다시 안 읽는다)
    return (p, a, r, rd + "/" + seat + ".json", m if isinstance(m, str) else "")


def pi_seat_resume(seat, model, retired_by):   # Pi 계약 v3 — 상태 판정과 동일 locator만 사용한다.
    from ft_seat_pi import binding   # r1855 ⓒ 결속 하나 재사용 — binding dict 통째(다시 만들기 0)
    try:
        b = binding(seat)
        with open(b["jsonl"], encoding="utf-8") as f:
            head = json.loads(f.readline())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        # PI_NOREC는 close가 자동 수용하므로 결속 오류에는 쓰지 않는다. r1855 ⓓ 세션 바뀜은 사유 그대로.
        return None, "Pi 결속 판정 불가 · " + ("세션 바뀜" if str(error) == "세션 바뀜" else type(error).__name__)
    path = b["jsonl"]
    use = model if isinstance(model, str) and model else _pi_model(path, head)
    if not use:
        return None, "pi 좌석 · model 못 읽음(세션 파일·명부)"
    return collections.OrderedDict(name=seat, engine="pi", pid=b["pid"], uuid=b["uuid"], jsonl=path, cwd=b["cwd"], model=use, retired_by=retired_by,
                                   at=datetime.datetime.now().isoformat(timespec="seconds"), binding=b["binding"]), ""
