"""cairn — 일정관리 + 멀티에이전트 복구 원장 CLI."""
import argparse
import datetime
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import fcntl
import hashlib
from contextlib import contextmanager
from pathlib import Path
from ruamel.yaml import YAML, YAMLError

def _find_repo():
    # [설치형] git repo면 toplevel(프로젝트 루트=.cairn 위치)을 우선. 설치 디렉토리 ~/.cairn 오인 방지.
    try:
        r = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            return Path(r.stdout.strip())
    except Exception:
        pass
    # 비-git: cwd부터 상위로 .cairn 탐색 (단 홈 설치 디렉토리 ~/.cairn 제외). 없으면 cwd.
    p = Path.cwd()
    home_cairn = Path.home() / ".cairn"
    for d in [p, *p.parents]:
        c = d / ".cairn"
        if c.is_dir() and c != home_cairn:
            return d
    return Path.cwd()


REPO = _find_repo()
PKG_DIR = Path(__file__).resolve().parent.parent   # 패키지 루트 (dev: hook 등)
GOLDEN_PATH = Path(__file__).resolve().parent / "golden.yaml"      # cairn.py 옆 → 설치 시 core와 동행
GOLDEN_VIEW = Path(__file__).resolve().parent / "golden.view.md"
PLAN_PATH = REPO / ".cairn" / "plan.yaml"
VIEW_PATH = REPO / ".cairn" / "views" / "plan.md"
LOCK_PATH = REPO / ".cairn" / ".lock"
MAP_DIR = Path("/tmp/cairn")

STATUS_PROJECT = {"planned", "active", "done", "paused"}
STATUS_MS = {"planned", "active", "done", "blocked"}
STATUS_TASK = {"todo", "doing", "done", "blocked"}
STATUS_TODO = {"open", "claimed", "resolved", "dropped"}
_CTRL_RE = re.compile(r"[\x00-\x1f\x7f]")

yaml = YAML()                      # round-trip
yaml.preserve_quotes = True
yaml.indent(mapping=2, sequence=4, offset=2)


def load_plan(path=PLAN_PATH):
    with open(path) as f:
        return yaml.load(f)


def dump_str(data):
    buf = io.StringIO()
    yaml.dump(data, buf)
    return buf.getvalue()


def _ms_tag(status):
    return {"done": "done", "active": "active", "blocked": "crit"}.get(status, "")


def _task_tag(status):
    return {"done": "done", "doing": "active", "blocked": "crit"}.get(status, "")


def _safe_mermaid_label(name):
    """Mermaid gantt 라벨에서 구분자 ':' 충돌 방지 (project section · milestone 공통)."""
    return str(name).replace(":", "-")


def render(data):
    lines = ["# cairn — 전사 간트", "", "```mermaid", "gantt",
             "    dateFormat YYYY-MM-DD",
             "    axisFormat %y.%m.%d",   # x축 라벨: 연 2자리 + '.' 구분 (26.06.10)
             "    tickInterval 1week",    # 주 단위 눈금 — 매일 라벨 겹침 방지
             "    title 전사 마일스톤 타임라인"]
    for p in data.get("projects", []):
        proj_label = _safe_mermaid_label(p.get('name', p['id']))
        milestones = p.get("milestones", [])
        # 그룹(제품/목표묶음) 단위로 버킷화 — 등장순 유지하되 같은 group을 한 섹션에
        # 연속 배치 (mermaid section은 평면이라 정렬 안 하면 파편화됨). None=기본 섹션.
        seen_groups = []
        for m in milestones:
            g = (m.get("group") or "").strip() or None
            if g not in seen_groups:
                seen_groups.append(g)
        for g in seen_groups:
            section = proj_label if g is None else f"{proj_label} · {_safe_mermaid_label(g)}"
            lines.append(f"    section {section}")
            for m in milestones:
                if ((m.get("group") or "").strip() or None) != g:
                    continue
                tag = _ms_tag(m.get("status", ""))
                prefix = f"{tag}, " if tag else ""
                start, end = m.get("start"), m.get("end")
                tasks = m.get("tasks", [])
                # 마일스톤 날짜 미설정 시 하위 태스크에서 파생 (mermaid는 섹션 첫 바에 시작일 필수)
                if not start:
                    cand = [t["start"] for t in tasks if t.get("start")]
                    start = min(cand) if cand else None
                if not end:
                    cand = [t["due"] for t in tasks if t.get("due")]
                    end = max(cand) if cand else None
                safe_name = _safe_mermaid_label(m["name"])
                if start and end:
                    lines.append(f"    {safe_name} :{prefix}{m['id']}, {start}, {end}")
                elif start:
                    lines.append(f"    {safe_name} :{prefix}{m['id']}, {start}, 1d")
                # else: 날짜 정보 전무 → 유효 간트 위해 마일스톤 요약 바 생략
                for t in m.get("tasks", []):
                    due = t.get("due")
                    t_start = t.get("start")
                    label = _safe_mermaid_label(t['name'])
                    gid = f"{m['id']}-{t['id']}"
                    if t_start and due and t_start <= due:
                        # start→due 기간 막대 (간격이 보이게)
                        t_tag = _task_tag(t.get("status", ""))
                        t_prefix = f"{t_tag}, " if t_tag else ""
                        lines.append(f"    {label} :{t_prefix}{gid}, {t_start}, {due}")
                    elif due:
                        # start 없거나 start>due → due에 0d 마커 폴백
                        lines.append(f"    {label} :milestone, {gid}, {due}, 0d")
        lines.append("")
    lines.append("```")
    return "\n".join(lines).rstrip() + "\n"


def _derive_wt_br(t):
    """노드 표시용 워크트리/브랜치 파생. execution_ref 'worktree/X' → wt=X
    (prefix 없으면 ref 전체). br은 branch 필드 우선, 없으면 wt에서 파생,
    워크트리·브랜치 둘 다 없으면 'main'(워크트리 없음 = main 브랜치 작업)."""
    er = t.get("execution_ref")
    if not er:
        wt = None
    elif er.startswith("worktree/"):
        wt = er.split("/", 1)[1]
    else:
        wt = er
    br = t.get("branch") or wt or "main"
    return wt, br


def _short_sess(sr):
    return sr[len("session-"):] if sr.startswith("session-") else sr


def _derive_sess(t):
    """세션 표시. session_chain(핸드오프 누적)이 있으면 first→last (N)로 압축,
    하나면 그 하나만. 없으면 단일 session_ref 'session-X' → X. 둘 다 없으면 None."""
    chain = t.get("session_chain")
    if chain:
        shorts = [_short_sess(s) for s in chain]
        if len(shorts) == 1:
            return shorts[0]
        return f"{shorts[0]}→{shorts[-1]} ({len(shorts)})"
    sr = t.get("session_ref")
    if not sr:
        return None
    return _short_sess(sr)


def _node_label(t, parent):
    """6필드 노드 라벨(st·fin·wt·br·sess·note). wt/br는 '전이 마커' —
    직계 부모(spawned_from)와 워크트리/브랜치가 다른 head 노드에만 표기."""
    parts = [f"{t.get('id')} · {_safe_mermaid_label(t.get('name', t.get('id')))}"]
    dates = []
    if t.get("start"):
        dates.append(f"st {t['start']}")
    if t.get("finished_at"):
        dates.append(f"fin {t['finished_at']}")
    if dates:
        parts.append(" · ".join(dates))
    wt, br = _derive_wt_br(t)
    p_wt, p_br = _derive_wt_br(parent) if parent else (None, None)
    if (wt, br) != (p_wt, p_br):              # 전이 발생 → head
        if wt:
            seg = f"🌿 wt {wt} · 🔀 br {br}"
        else:                                 # 워크트리 없음 = main 브랜치 (🌿 아이콘 없음)
            seg = f"🔀 br {br}"
        parts.append(seg)
    sess = _derive_sess(t)
    if sess:
        parts.append(f"🖥 sess {sess}")
    if t.get("note"):
        parts.append(f"📝 note {_safe_mermaid_label(str(t['note']))}")
    return "<br/>".join(parts)


def _is_merged(t):
    """작업이 부모로 병합 완료됨 — merge_back_to 설정 = 통합됨."""
    return bool(t.get("merge_back_to"))


def _is_stale(t):
    """스테일 워크트리 — execution_ref 있고 미병합인 done 태스크
    (작업 끝났는데 병합 안 된 채 남은 브랜치)."""
    return bool(t.get("execution_ref")) and not t.get("merge_back_to") and t.get("status") == "done"


def _node_depth(t, by_id):
    """spawned_from 체인을 거슬러 루트(분기원 없음)까지의 홉 수 = fan-out 깊이(루트=0).
    필드(fanout_depth)가 아니라 그래프 구조에서 파생 — 유효 원장(spawned_from
    순환 없음, validate 통과)에서 일관. 순환은 validate가 사전 차단한다."""
    depth, cur, seen = 0, t, set()
    while cur is not None:
        sf = cur.get("spawned_from")
        cid = cur.get("id")
        if not sf or cid in seen:                 # 루트 도달 or 순환 방지
            break
        seen.add(cid)
        parent = by_id.get(sf)
        if parent is None:                        # 분기원이 그래프 밖
            break
        depth += 1
        cur = parent
    return depth


def render_recovery_map(data, focus=None, show_merged=False):
    lines = ["graph TD"]
    all_tasks = [t for p in data.get("projects", [])
                 for m in p.get("milestones", [])
                 for t in m.get("tasks", [])]
    by_id = {t.get("id"): t for t in all_tasks}

    def _focused(t):
        if not focus:
            return True
        tid = t.get("id")
        if focus in (tid, t.get("return_to"), t.get("merge_back_to")):
            return True
        # focus의 자손 서브트리 전체 포함 (spawned_from 체인 상향 추적) —
        # 직계 자식만 보면 손자(depth2+) stale 노드가 누락된다.
        cur, seen = t, set()
        while cur is not None:
            cid = cur.get("id")
            if cid == focus:
                return True
            if cid in seen:                       # 순환 방지
                break
            seen.add(cid)
            cur = by_id.get(cur.get("spawned_from"))
        return False

    # 가시 노드: 병합된 것은 기본 숨김(show_merged로 해제) + focus 필터
    visible = {t.get("id") for t in all_tasks
               if _focused(t) and (show_merged or not _is_merged(t))}
    hidden = set(by_id) - visible                 # 숨겨진 '태스크'만 (마일스톤 타겟은 항상 유지)
    stale_ids = []
    for t in all_tasks:
        tid = t.get("id")
        if tid not in visible:
            continue
        lines.append(f'    {tid}["{_node_label(t, by_id.get(t.get("spawned_from")))}"]')
        if _is_stale(t):
            stale_ids.append(tid)
        sf = t.get("spawned_from")
        if sf and sf not in hidden:               # 숨겨진 노드와의 고아 엣지 방지
            lines.append(f"    {sf} --> {tid}")
        rt = t.get("return_to")
        if rt and rt not in hidden:
            lines.append(f"    {tid} -.return.-> {rt}")
        mb = t.get("merge_back_to")
        if mb and mb not in hidden:
            lines.append(f"    {tid} ==merge==> {mb}")
    # fan-out 깊이별 시각 구분(Ops#2: nested fan-out 식별) — depth>=3은 depth3로 클램프.
    depth_buckets = {}
    for t in all_tasks:
        tid = t.get("id")
        if tid not in visible:
            continue
        d = _node_depth(t, by_id)
        if d >= 1:                                # depth0(루트)은 기본 스타일
            depth_buckets.setdefault(min(d, 3), []).append(tid)
    _DEPTH_SHADE = {1: "#eff6ff,stroke:#93c5fd",
                    2: "#dbeafe,stroke:#3b82f6",
                    3: "#bfdbfe,stroke:#1d4ed8"}
    for lvl in sorted(depth_buckets):             # stale 앞에 두어 stale 빨강이 우선
        lines.append(f"    classDef depth{lvl} fill:{_DEPTH_SHADE[lvl]};")
        lines.append(f"    class {','.join(depth_buckets[lvl])} depth{lvl};")
    if stale_ids:                                 # 스테일 브랜치 시각 구분
        lines.append("    classDef stale fill:#fee2e2,stroke:#dc2626,stroke-dasharray:4 3;")
        lines.append(f"    class {','.join(stale_ids)} stale;")
    return "\n".join(lines) + "\n"


def _find_chrome():
    """puppeteer 캐시의 chrome-headless-shell 경로 자동 탐색.
    mmdc 기본 Chrome 버전과 캐시 버전 불일치로 인한 'Could not find Chrome' 회피."""
    cache = Path.home() / ".cache" / "puppeteer"
    hits = sorted(cache.glob("chrome-headless-shell/*/chrome-headless-shell-*/chrome-headless-shell")) if cache.exists() else []
    return str(hits[-1]) if hits else None


def render_png(text, out_png):
    """mermaid 텍스트 → PNG (mmdc/puppeteer). 성공 시 Path, 실패 시 None.
    mermaid 코드블록은 클라이언트에서 안 보이는 경우가 많아 PNG로 구워 Preview에 띄움."""
    out_png = Path(out_png)
    out_png.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        mmd = Path(td) / "g.mmd"
        mmd.write_text(text, encoding="utf-8")
        cmd = ["npx", "-y", "@mermaid-js/mermaid-cli", "-i", str(mmd), "-o", str(out_png), "-b", "white"]
        chrome = _find_chrome()
        if chrome:
            pptr = Path(td) / "pptr.json"
            pptr.write_text(json.dumps({"executablePath": chrome, "args": ["--no-sandbox"]}), encoding="utf-8")
            cmd += ["-p", str(pptr)]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True)
        except FileNotFoundError:        # npx 미설치
            return None
    return out_png if (r.returncode == 0 and out_png.exists()) else None


def render_html(text):
    """mermaid 텍스트 → 자체완결 HTML. mermaid.js를 CDN에서 로드해 브라우저에서
    바로 렌더(termaid/mmdc 등 로컬 의존성 불필요). 파일 하나로 공유 가능."""
    return (
        "<!DOCTYPE html>\n"
        '<html lang="ko"><head><meta charset="utf-8">\n'
        "<title>cairn recovery map</title>\n"
        '<script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>\n'
        "</head><body>\n"
        f'<pre class="mermaid">\n{text}</pre>\n'
        "<script>mermaid.initialize({startOnLoad:true});</script>\n"
        "</body></html>\n"
    )


def write_view(data, path=VIEW_PATH):
    # [DA#1] PLAN과 동일 atomic 경로 — write_view 실패 시 부분쓰기 방지
    _atomic_write_text(render(data), path)


def find_project(data, pid):
    return next((p for p in data.get("projects", []) if p.get("id") == pid), None)


def find_milestone(proj, mid):
    return next((m for m in proj.get("milestones", []) if m.get("id") == mid), None)


def find_task(ms, tid):
    return next((t for t in ms.get("tasks", []) if t.get("id") == tid), None)


def _all_node_ids(data):
    ids = set()
    for p in data.get("projects", []):
        if p.get("id"):
            ids.add(p["id"])
        for m in p.get("milestones", []):
            if m.get("id"):
                ids.add(m["id"])
            for t in m.get("tasks", []):
                if t.get("id"):
                    ids.add(t["id"])
    return ids


def find_task_anywhere(data, tid):
    out = []
    for p in data.get("projects", []):
        for m in p.get("milestones", []):
            for t in m.get("tasks", []):
                if t.get("id") == tid:
                    out.append((p, m, t))
    return out


def _find_sched_node(proj, nid):
    """프로젝트 내 일정 노드 조회 → (node, 'milestone'|'task'). 없으면 (None, None)."""
    for m in proj.get("milestones", []):
        if m.get("id") == nid:
            return m, "milestone"
    for m in proj.get("milestones", []):
        for t in m.get("tasks", []):
            if t.get("id") == nid:
                return t, "task"
    return None, None


def _has_cycle(nodes):
    """nodes: list of dicts with id + depends_on. 순환/자기참조면 True."""
    graph = {n["id"]: list(n.get("depends_on") or []) for n in nodes if n.get("id")}
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {k: WHITE for k in graph}

    def dfs(u):
        color[u] = GRAY
        for v in graph.get(u, []):
            if v not in graph:
                continue
            if color[v] == GRAY:
                return True
            if color[v] == WHITE and dfs(v):
                return True
        color[u] = BLACK
        return False

    return any(color[k] == WHITE and dfs(k) for k in graph)


def _has_spawn_cycle(tasks):
    """spawned_from 단일 부모 체인의 순환(자기참조 포함) 탐지. 순환이면
    _node_depth가 루트에 도달 못 해 fan-out 깊이가 무의미해진다."""
    parent = {t["id"]: t.get("spawned_from") for t in tasks if t.get("id")}
    for start in parent:
        seen, cur = set(), start
        while cur is not None and cur in parent:
            if cur in seen:
                return True
            seen.add(cur)
            cur = parent[cur]
    return False


@contextmanager
def _lock():
    LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(LOCK_PATH, os.O_CREAT | os.O_RDWR)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _atomic_write_text(text, path):
    """tmp+fsync+rename 원자 교체. 실패 시 tmp 정리. 호출자가 lock 보유 필요."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def save_atomic(data, path=PLAN_PATH):
    errors = validate(data)
    if errors:
        raise ValueError("validate 실패: " + "; ".join(errors))
    with _lock():
        _atomic_write_text(dump_str(data), path)


def validate(data):
    errors = []
    if not data or "projects" not in data:
        return ["missing top-level 'projects'"]
    node_ids = _all_node_ids(data)
    # [DA#2] task id는 전역 유니크여야 함 — 복구 메타(spawned_from/return_to)가 전역 참조
    global_tids = {}
    for _p in data["projects"]:
        for _m in _p.get("milestones", []):
            for _t in _m.get("tasks", []):
                _tid = _t.get("id")
                if _tid:
                    global_tids[_tid] = global_tids.get(_tid, 0) + 1
    for _tid, _cnt in global_tids.items():
        if _cnt > 1:
            errors.append(f"duplicate task id (global): {_tid}")
    pids = set()
    for p in data["projects"]:
        pid = p.get("id")
        if not pid:
            errors.append("project missing id"); continue
        if pid in pids:
            errors.append(f"duplicate project id: {pid}")
        pids.add(pid)
        if "name" not in p:
            errors.append(f"{pid}: missing name")
        elif _CTRL_RE.search(str(p.get("name", ""))):
            errors.append(f"{pid}: project name contains control characters")
        if p.get("status") not in STATUS_PROJECT:
            errors.append(f"{pid}: bad project status: {p.get('status')}")
        mids = set()
        for m in p.get("milestones", []):
            mid = m.get("id")
            if not mid:
                errors.append(f"{pid}: milestone missing id"); continue
            if mid in mids:
                errors.append(f"{pid}: duplicate milestone id: {mid}")
            mids.add(mid)
            mname = m.get("name")
            if mname is None:
                errors.append(f"{pid}/{mid}: missing name")
            elif _CTRL_RE.search(str(mname)):
                errors.append(f"{pid}/{mid}: name contains control characters")
            if m.get("group") and _CTRL_RE.search(str(m.get("group"))):
                errors.append(f"{pid}/{mid}: group contains control characters")
            if m.get("status") not in STATUS_MS:
                errors.append(f"{pid}/{mid}: bad ms status: {m.get('status')}")
            for dep in (m.get("depends_on") or []):
                if dep == mid:
                    errors.append(f"{pid}/{mid}: self-reference in depends_on")
                elif dep not in {x.get("id") for x in p.get("milestones", [])}:
                    errors.append(f"{pid}/{mid}: depends_on missing target: {dep}")
            # F4: 날짜 파싱 + start <= end
            for field in ("start", "end"):
                v = m.get(field)
                if v is not None:
                    try:
                        datetime.date.fromisoformat(str(v))
                    except ValueError:
                        errors.append(f"{pid}/{mid}: invalid {field} date: {v}")
            sv, ev = m.get("start"), m.get("end")
            if sv and ev:
                try:
                    if datetime.date.fromisoformat(str(sv)) > datetime.date.fromisoformat(str(ev)):
                        errors.append(f"{pid}/{mid}: start > end ({sv} > {ev})")
                except ValueError:
                    pass
            # F4: task depends_on 존재 확인 + 순환.
            # 태스크 의존은 프로젝트 전역에서 해소 — 마일스톤을 가로지르는 의존
            # (예: QA 태스크 → Backend 태스크)이 현실 일정에 흔하므로. task id는 전역 유니크 강제됨.
            proj_tids = {tt.get("id") for mm in p.get("milestones", [])
                         for tt in mm.get("tasks", []) if tt.get("id")}
            tids = set()
            for t in m.get("tasks", []):
                tid = t.get("id")
                if not tid:
                    errors.append(f"{pid}/{mid}: task missing id"); continue
                if tid in tids:
                    errors.append(f"{pid}/{mid}: duplicate task id: {tid}")
                tids.add(tid)
                if t.get("status") not in STATUS_TASK:
                    errors.append(f"{pid}/{mid}/{tid}: bad task status: {t.get('status')}")
                for ref in ("spawned_from", "return_to", "merge_back_to"):
                    target = t.get(ref)
                    if target is not None and target not in node_ids:
                        errors.append(f"{pid}/{mid}/{tid}: {ref} missing node: {target}")
                for dep in (t.get("depends_on") or []):
                    if dep == tid:
                        errors.append(f"{pid}/{mid}/{tid}: task self-reference in depends_on")
                    elif dep not in proj_tids:
                        errors.append(f"{pid}/{mid}/{tid}: task depends_on missing target: {dep}")
        # 순환은 프로젝트 전역 태스크 그래프에서 검사 — 크로스-마일스톤 의존도 포착
        proj_tasks = [tt for mm in p.get("milestones", []) for tt in mm.get("tasks", [])]
        if _has_cycle(proj_tasks):
            errors.append(f"{pid}: dependency cycle in tasks")
        if _has_cycle(p.get("milestones", [])):
            errors.append(f"{pid}: dependency cycle in milestones")
        if _has_spawn_cycle(proj_tasks):
            errors.append(f"{pid}: spawned_from cycle in tasks")
    # todos 톱레벨 백로그 검증 (§6.2 통합 모델) — 있을 때만(하위호환).
    # todo는 node가 아니므로 어휘(STATUS_TODO)·cross-ref를 plan.yaml 단일 트랜잭션에서 함께 검증.
    todos = data.get("todos")
    if todos is not None:
        if not isinstance(todos, list):
            errors.append("top-level 'todos' must be a list")
        else:
            # origin_node/resolved_by는 실행단위(task)만 가리킨다 — ms/project id 불가.
            task_ids = {t.get("id") for p in data.get("projects", [])
                        for m in p.get("milestones", []) for t in m.get("tasks", [])
                        if t.get("id")}
            seen_tdids = set()
            for td in todos:
                tdid = td.get("id")
                if not tdid:
                    errors.append("todo missing id"); continue
                if tdid in seen_tdids:
                    errors.append(f"duplicate todo id: {tdid}")
                seen_tdids.add(tdid)
                if "title" not in td:
                    errors.append(f"todo {tdid}: missing title")
                elif _CTRL_RE.search(str(td.get("title", ""))):
                    errors.append(f"todo {tdid}: title has control chars")
                if td.get("project") not in pids:
                    errors.append(f"todo {tdid}: unknown project: {td.get('project')}")
                if td.get("status") not in STATUS_TODO:
                    errors.append(f"todo {tdid}: bad todo status: {td.get('status')}")
                origin = td.get("origin_node")
                if origin is not None and origin not in task_ids:
                    errors.append(f"todo {tdid}: origin_node missing node: {origin}")
                for rb in (td.get("resolved_by") or []):
                    if rb not in task_ids:
                        errors.append(f"todo {tdid}: resolved_by missing node: {rb}")
    return errors


def _to_date(v):
    return datetime.date.fromisoformat(str(v))


def _today():
    return datetime.date.today()


def overdue_list(data, today):
    out = []
    for p in data.get("projects", []):
        for m in p.get("milestones", []):
            end = m.get("end")
            if end and m.get("status") != "done" and _to_date(end) < today:
                out.append((p["id"], m["id"], end))
    return out


def overdue_tasks(data, today):
    out = []
    for p in data.get("projects", []):
        for m in p.get("milestones", []):
            for t in m.get("tasks", []):
                due = t.get("due")
                if due and t.get("status") != "done" and _to_date(due) < today:
                    out.append((p["id"], m["id"], t["id"], due))
    return out


def _done_ratio(ms):
    tasks = ms.get("tasks") or []
    if not tasks:
        return None
    done = sum(1 for t in tasks if t.get("status") == "done")
    return done, len(tasks)


def cmd_status(data, args):
    for p in data.get("projects", []):
        print(f"[{p['id']}] {p.get('name','')} · {p.get('status','')} · prio={p.get('priority','-')}")
        for m in p.get("milestones", []):
            r = _done_ratio(m)
            prog = f" ({r[0]}/{r[1]} tasks)" if r else ""
            print(f"   - {m['id']} {m.get('name','')} [{m.get('status','')}] {m.get('start','')}~{m.get('end','')}{prog}")
    return 0


def cmd_show(data, args):
    p = find_project(data, args.project)
    if not p:
        print(f"no such project: {args.project}"); return 1
    print(dump_str({"projects": [p]}))
    return 0


def cmd_overdue(data, args):
    today = _to_date(args.today) if args.today else _today()
    ms_res = overdue_list(data, today)
    task_res = overdue_tasks(data, today)
    if not ms_res and not task_res:
        print(f"지연 없음 (기준일 {today})"); return 0
    for pid, mid, end in ms_res:
        print(f"지연: {pid}/{mid} (end {end} < {today})")
    for pid, mid, tid, due in task_res:
        print(f"지연: {pid}/{mid}/{tid} (due {due} < {today})")
    return 0


def cmd_render(data, args):
    errors = validate(data)
    if errors:
        for e in errors:
            print(f" - {e}", file=sys.stderr)
        print(f"INVALID ({len(errors)} errors)", file=sys.stderr)
        return 1
    write_view(data)
    print(f"rendered → {VIEW_PATH}")
    # 기본으로 간트 HTML도 생성 + 브라우저 표시 (render의 기본 산출물)
    md = render(data)   # write_view와 동일 출력 — ```mermaid 간트 블록 추출
    m = re.search(r"```mermaid\n(.*?)```", md, re.S)
    html_path = VIEW_PATH.with_suffix(".html")
    html_path.write_text(render_html(m.group(1) if m else md), encoding="utf-8")
    print(f"HTML → {html_path}")
    if sys.platform == "darwin":   # 더블클릭 없이 기본 브라우저로 바로 렌더
        subprocess.run(["open", str(html_path)], check=False)
    return 0


def _slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def _next_id(existing, prefix):
    n = 1
    while f"{prefix}{n}" in existing:
        n += 1
    return f"{prefix}{n}"


def cmd_set_date(_d, args):
    def mutate(data):
        p = find_project(data, args.project)
        if not p: raise ValueError(f"no project {args.project}")
        _to_date(args.date)                 # 형식 검증
        if args.task:
            if args.field != "due":
                raise ValueError("--task는 field=due만 지원")
            m = find_milestone(p, args.id)
            if not m: raise ValueError(f"no milestone {args.id}")
            t = find_task(m, args.task)
            if not t: raise ValueError(f"no task {args.task}")
            t["due"] = args.date
        else:
            if args.field not in ("start", "end"):
                raise ValueError("milestone field=start|end")
            m = find_milestone(p, args.id)
            if not m: raise ValueError(f"no milestone {args.id}")
            m[args.field] = args.date
    transaction(mutate, f"set-date {args.project}/{args.id} {args.field}={args.date}")
    print("OK"); return 0


def cmd_set_group(_d, args):
    def mutate(data):
        p = find_project(data, args.project)
        if not p: raise ValueError(f"no project {args.project}")
        m = find_milestone(p, args.milestone)
        if not m: raise ValueError(f"no milestone {args.milestone} in {args.project}")
        g = (args.name or "").strip()
        if g:
            m["group"] = g
        else:
            m.pop("group", None)            # 빈 문자열 = 그룹 제거
    transaction(mutate, f"set-group {args.project}/{args.milestone}={args.name}")
    print("OK"); return 0


def cmd_set_priority(_d, args):
    def mutate(data):
        p = find_project(data, args.project)
        if not p: raise ValueError(f"no project {args.project}")
        if args.priority not in ("high", "medium", "low"):
            raise ValueError("priority=high|medium|low")
        p["priority"] = args.priority
    transaction(mutate, f"set-priority {args.project}={args.priority}")
    print("OK"); return 0


def cmd_add_task(_d, args):
    captured = {}
    def mutate(data):
        m = find_milestone(find_project(data, args.project) or {}, args.milestone)
        if not m: raise ValueError(f"no milestone {args.milestone}")
        m.setdefault("tasks", [])
        # [DA#2] task id 전역 유니크 (복구 메타 전역 참조 — spawn과 동일 규칙)
        existing = {t["id"] for pp in data.get("projects", [])
                    for mm in pp.get("milestones", []) for t in mm.get("tasks", [])}
        tid = _next_id(existing, "t")
        captured["tid"] = tid
        start = _today()
        due = start + datetime.timedelta(days=args.days)
        m["tasks"].append({"id": tid, "name": args.name, "status": "todo",
                           "start": start.isoformat(), "due": due.isoformat(),
                           "depends_on": []})
    transaction(mutate, f"add-task {args.project}/{args.milestone}: {args.name}")
    print(f"OK: {captured['tid']} 추가 (due {(_today() + datetime.timedelta(days=args.days)).isoformat()})"); return 0


def cmd_spawn(_d, args):
    captured = {}
    def mutate(data):
        matches = find_task_anywhere(data, args.parent)
        if not matches:
            raise ValueError(f"no parent task {args.parent}")
        if len(matches) > 1:
            raise ValueError(f"ambiguous parent {args.parent} (multiple matches)")
        _p, m, parent = matches[0]
        if parent.get("status") == "done":           # [Ops#1-3] 완료 노드 분기 경고
            captured["parent_done"] = True
        for _t in m.get("tasks", []):                # [Ops#1-4] 같은 parent 동일 이름 경고
            if _t.get("name") == args.name and _t.get("spawned_from") == args.parent:
                captured["dup_name"] = True; break
        m.setdefault("tasks", [])
        # 복구 메타가 task id를 전역 참조 → spawn id는 전역 유니크여야 함
        existing = {t["id"] for pp in data.get("projects", [])
                    for mm in pp.get("milestones", []) for t in mm.get("tasks", [])}
        tid = _next_id(existing, "t")
        captured["tid"] = tid
        start = _today()
        node = {"id": tid, "name": args.name, "status": "todo",
                "start": start.isoformat(), "due": start.isoformat(),
                "depends_on": [],
                "spawned_from": args.parent,
                "return_to": args.return_to or args.parent,
                "fanout_depth": int(parent.get("fanout_depth", 0)) + 1}
        if args.worktree:
            node["execution_ref"] = args.worktree
        if args.session:
            node["session_ref"] = args.session
        m["tasks"].append(node)
    transaction(mutate, f"spawn {args.name} from {args.parent}")
    if captured.get("parent_done"):
        print(f"경고: 완료된 노드 {args.parent}에서 분기 — 재개 작업인지 확인", file=sys.stderr)
    if captured.get("dup_name"):
        print(f"경고: 동일 이름 '{args.name}'이 {args.parent}에서 이미 분기됨", file=sys.stderr)
    print(f"OK: spawned {captured['tid']} ← from {args.parent} "
          f"(return_to={args.return_to or args.parent})"); return 0


def cmd_complete(_d, args):
    captured = {}
    def mutate(data):
        matches = find_task_anywhere(data, args.task)
        if not matches:
            raise ValueError(f"no task {args.task}")
        if len(matches) > 1:
            raise ValueError(f"ambiguous task {args.task} (multiple matches)")
        _p, _m, t = matches[0]
        if t.get("status") == "done":       # [Ops#1-1] 이미 완료 — 멱등 no-op
            captured["was_done"] = True
            return
        rt = t.get("return_to")
        if not rt and not args.force:
            raise ValueError(f"task {args.task}: no return_to — 복귀 대상 불명 "
                             f"(spawn으로 만들거나 --force)")
        t["status"] = "done"
        t["finished_at"] = _today().isoformat()   # [DA] 완료일 — due(마감)와 구분, 노드 fin 필드
        if not rt and args.force:       # [DA#5] 강제 완료 추적 표식
            t["forced_complete"] = True
        captured["return_to"] = rt
    transaction(mutate, f"complete {args.task}")
    if captured.get("was_done"):           # [Ops#1-1] 재완료 침묵 제거 (mutate 후 판정)
        print(f"이미 완료됨: {args.task} (no-op)"); return 0
    rt = captured.get("return_to")
    if rt:
        print(f"OK: {args.task} done → 다음: '{rt}'(으)로 돌아가세요 "
              f"(cairn return --to {rt})")
    else:
        print(f"OK: {args.task} done (return_to 없음)")
    return 0


def _map_path():
    # [DA-sim] 프로젝트별 격리 — 전역 /tmp/cairn/recovery.md 오염 방지
    rid = hashlib.sha1(str(REPO).encode()).hexdigest()[:10]
    return MAP_DIR / f"{REPO.name}-{rid}" / "recovery.md"


def cmd_map(data, args):
    text = render_recovery_map(data, focus=args.focus, show_merged=getattr(args, "show_merged", False))
    out = _map_path()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(f"```mermaid\n{text}```\n")
    print(f"recovery-map → {out}")
    if args.render:
        try:
            subprocess.run(["termaid", str(out)], check=False)
        except FileNotFoundError:
            print("termaid 미설치 — 파일만 생성됨")
    if getattr(args, "png", False):
        png = render_png(text, out.with_suffix(".png"))
        if png:
            print(f"PNG → {png}")
            if sys.platform == "darwin":   # 구운 PNG를 Preview로 띄움(코드블록 비가시 회피)
                subprocess.run(["open", str(png)], check=False)
        else:
            print("PNG 렌더 실패(mmdc/chrome 미설치) — mermaid 파일만 생성됨")
    if getattr(args, "html", False):
        html_path = out.with_suffix(".html")
        html_path.write_text(render_html(text), encoding="utf-8")
        print(f"HTML → {html_path}")
        if sys.platform == "darwin":   # 더블클릭 없이 기본 브라우저로 바로 렌더
            subprocess.run(["open", str(html_path)], check=False)
    return 0


def reconcile_orphans(data, active_refs):
    out = []
    for p in data.get("projects", []):
        for m in p.get("milestones", []):
            for t in m.get("tasks", []):
                ref = t.get("execution_ref")
                if ref and ref not in active_refs:
                    out.append((p["id"], m["id"], t["id"], ref))
    return out


_BRANCH_PREFIX = "branch refs/heads/"


def _active_worktree_refs():
    res = git("worktree", "list", "--porcelain", check=False)
    if res.returncode != 0:        # [DA#4] silent 빈 set → orphan 오탐 방지
        raise RuntimeError(f"git worktree list 실패 (rc={res.returncode})")
    refs = set()
    for line in res.stdout.splitlines():
        if line.startswith(_BRANCH_PREFIX):
            refs.add(line[len(_BRANCH_PREFIX):])   # [DA#3] feature/foo 보존
    return refs


def cmd_reconcile(data, args):
    orphans = reconcile_orphans(data, _active_worktree_refs())
    if not orphans:
        print("reconcile: orphan 없음"); return 0
    for pid, mid, tid, ref in orphans:
        print(f"orphan 후보: {pid}/{mid}/{tid} (execution_ref {ref} — 활성 worktree 없음)")
    return 0


def cmd_link(_d, args):
    def mutate(data):
        matches = find_task_anywhere(data, args.node)
        if not matches:
            raise ValueError(f"no task {args.node}")
        if len(matches) > 1:
            raise ValueError(f"ambiguous task {args.node} (multiple matches)")
        _p, _m, t = matches[0]
        if args.merge_back_to is not None:
            if args.merge_back_to not in _all_node_ids(data):
                raise ValueError(f"merge-back-to missing node: {args.merge_back_to}")
            t["merge_back_to"] = args.merge_back_to
        if args.execution_ref is not None:
            t["execution_ref"] = args.execution_ref
        if args.session_ref is not None:
            t["session_ref"] = args.session_ref
        if args.add_session is not None:
            # 세션 핸드오프 누적: 기존 session_ref를 시드로 체인 시작, active는 최신으로 갱신
            chain = list(t.get("session_chain") or [])
            if not chain and t.get("session_ref"):
                chain.append(t["session_ref"])
            chain.append(args.add_session)
            t["session_chain"] = chain
            t["session_ref"] = args.add_session
    transaction(mutate, f"link {args.node}")
    print("OK"); return 0


def cmd_depends(_d, args):
    def mutate(data):
        p = find_project(data, args.project)
        if not p:
            raise ValueError(f"no project {args.project}")
        node, kind = _find_sched_node(p, args.node)
        if not node:
            raise ValueError(f"no node {args.node} in {args.project}")
        target, tkind = _find_sched_node(p, args.on)
        if not target:
            raise ValueError(f"no target {args.on} in {args.project}")
        if args.node == args.on:
            raise ValueError("self-reference not allowed in depends_on")
        if kind != tkind:
            raise ValueError(f"type mismatch: {kind} cannot depend on {tkind}")
        deps = node.setdefault("depends_on", [])
        if args.remove:
            if args.on in deps:
                deps.remove(args.on)
        elif args.on not in deps:
            deps.append(args.on)
    transaction(mutate, f"depends {args.node} {'-' if args.remove else '+'}{args.on}")
    print("OK"); return 0


def cmd_return(data, args):
    if args.to not in _all_node_ids(data):
        print(f"return: no such node {args.to}"); return 1
    _m = find_task_anywhere(data, args.to)   # [Ops#1-2] done 노드 복귀 경고
    if _m and _m[0][2].get("status") == "done":
        print(f"경고: 완료된 노드 {args.to}(으)로 복귀", file=sys.stderr)
    print(f"재앵커 대상: {args.to}")
    print("컨텍스트 재주입은 baton resume으로: cd 후 `이어서` 또는 /baton:resume")
    return 0


def cmd_add_milestone(_d, args):
    def mutate(data):
        p = find_project(data, args.project)
        if not p: raise ValueError(f"no project {args.project}")
        p.setdefault("milestones", [])
        mid = _next_id({m["id"] for m in p["milestones"]}, "ms")
        p["milestones"].append({"id": mid, "name": args.name, "status": "planned",
                                "start": None, "end": None, "depends_on": [], "tasks": []})
    transaction(mutate, f"add-milestone {args.project}: {args.name}")
    print("OK"); return 0


def cmd_new_project(_d, args):
    def mutate(data):
        pid = _slug(args.name)
        if not pid:
            raise ValueError(f"빈 slug: '{args.name}'에서 id를 만들 수 없습니다 (ASCII 영숫자 필요)")
        if find_project(data, pid): raise ValueError(f"project exists: {pid}")
        data.setdefault("projects", [])
        data["projects"].append({"id": pid, "name": args.name, "status": "planned",
                                 "owner": None, "priority": "medium", "goal": "",
                                 "milestones": []})
    transaction(mutate, f"new-project: {args.name}")
    print("OK"); return 0


def cmd_validate(data, args):
    errors = validate(data)
    if errors:
        for e in errors: print(f"  - {e}")
        print(f"INVALID ({len(errors)} errors)"); return 1
    print("valid"); return 0


def cmd_init(_data, args):
    plan = REPO / ".cairn" / "plan.yaml"
    if plan.exists():
        print("cairn: 이미 초기화됨 (.cairn/plan.yaml)"); return 0
    seed = {"version": 1, "projects": []}
    view = REPO / ".cairn" / "views" / "plan.md"
    view.parent.mkdir(parents=True, exist_ok=True)
    save_atomic(seed, plan)
    write_view(seed, view)
    # 시드 커밋 — 이후 transaction의 git rev-parse HEAD가 동작하려면 첫 커밋 필요
    git("add", str(plan), str(view))
    git("commit", "-q", "-m", "cairn init")
    print(f"cairn 초기화 완료: {REPO / '.cairn'} — 'cairn new-project <name>'으로 시작")
    return 0


def cmd_self_test(_data, args):
    data = load_plan(GOLDEN_PATH)
    if validate(data):
        print("self-test FAIL: golden invalid"); return 1
    # 교정#3: 외부 골든 스냅샷과 비교 (tautology 금지)
    expected = GOLDEN_VIEW.read_text()
    # 왕복 안정성: dump_str → reload → render
    again = yaml.load(io.StringIO(dump_str(data)))
    if render(again) != expected:
        print("self-test FAIL: render mismatch vs tests/golden.view.md"); return 1
    print("self-test OK"); return 0


def _last_plan_commit():
    """.cairn/plan.yaml 또는 .cairn/views/plan.md를 수정한 가장 최근 커밋 해시. 없으면 None."""
    result = git("log", "--format=%H", "--", str(PLAN_PATH), str(VIEW_PATH))
    lines = result.stdout.strip().splitlines()
    return lines[0] if lines else None


def _rel(path):
    return str(Path(path).resolve().relative_to(REPO.resolve()))


def cmd_revert(_d, args):
    with _lock():
        sha = _last_plan_commit()
        if sha is None:
            print("revert: cairn 원장 커밋 없음"); return 1
        parent = git("rev-parse", "--verify", f"{sha}^", check=False)
        if parent.returncode != 0:
            print("revert: 최초 원장 커밋은 되돌릴 수 없음"); return 1
        parent_sha = parent.stdout.strip()
        # plan/view 두 파일만 부모 상태로 복원 — 같은 커밋에 섞인 무관 파일은 건드리지 않음
        for path in (PLAN_PATH, VIEW_PATH):
            if git("cat-file", "-e", f"{parent_sha}:{_rel(path)}", check=False).returncode == 0:
                git("checkout", parent_sha, "--", str(path))
            else:
                git("rm", "-q", "--ignore-unmatch", "--", str(path), check=False)
        git("commit", "-m", f"revert plan to {parent_sha[:7]}", "--",
            str(PLAN_PATH), str(VIEW_PATH))
    print(f"reverted {sha[:7]}"); return 0


def git(*args, check=True):
    return subprocess.run(["git", *args], cwd=str(REPO),
                          capture_output=True, text=True, check=check)


def transaction(mutate, message):
    """쓰기 단일 경로. 실패 시 워킹트리 복원."""
    with _lock():
        # 교정#2: 진입 시 HEAD 기록
        pre = git("rev-parse", "HEAD").stdout.strip()
        # F2: CLI 밖 수동 변경이 있으면 중단 — 커밋에 불순물 섞임 방지
        if (git("diff", "--quiet", "--", str(PLAN_PATH), str(VIEW_PATH), check=False).returncode != 0 or
                git("diff", "--cached", "--quiet", "--", str(PLAN_PATH), str(VIEW_PATH), check=False).returncode != 0):
            raise RuntimeError("dirty worktree: commit or discard plan file changes first")
        data = load_plan(PLAN_PATH)
        mutate(data)
        errors = validate(data)
        if errors:
            raise ValueError("; ".join(errors))
        _atomic_write_text(dump_str(data), PLAN_PATH)
        write_view(data, VIEW_PATH)   # 모듈 변수 명시 전달(monkeypatch 반영)
        git("add", str(PLAN_PATH), str(VIEW_PATH))
        # 교정#1: no-op 크래시 방지 — staged 변경 없으면 커밋 생략
        if git("diff", "--cached", "--quiet", check=False).returncode == 0:
            return
        try:
            git("commit", "-m", message, "--", str(PLAN_PATH), str(VIEW_PATH))
        except subprocess.CalledProcessError:
            # G3: plan/view만 복원 — repo-wide reset --hard 금지
            git("reset", "HEAD", "--", str(PLAN_PATH), str(VIEW_PATH), check=False)
            git("checkout", "--", str(PLAN_PATH), str(VIEW_PATH), check=False)
            raise


def cmd_remove_task(data_unused, args):
    def mutate(data):
        p = find_project(data, args.project)
        if not p: raise ValueError(f"no project {args.project}")
        ms = find_milestone(p, args.milestone)
        if not ms: raise ValueError(f"no milestone {args.milestone}")
        tasks = ms.get("tasks") or []
        # [버그] 역참조 사전검사 — data 전체 전역 순회. 복구엣지(spawned_from/return_to/
        # merge_back_to)는 cross-project fan-out, depends_on은 cross-milestone 의존을 허용하므로
        # 한 프로젝트만 보면 누락된다. 누락 시 transaction validate가 사후 raw 'missing node'로만
        # 막아 불친절(삭제하려는 노드 기준이 아니라 참조한 노드 기준 역방향 메시지).
        for pp in data.get("projects", []):
            for mm in pp.get("milestones", []):
                for t in mm.get("tasks", []):
                    if t.get("id") == args.task:
                        continue
                    if args.task in (t.get("depends_on") or []):
                        raise ValueError(f"task {args.task} is referenced by {t['id']} in depends_on")
                    for ref in ("spawned_from", "return_to", "merge_back_to"):
                        if t.get(ref) == args.task:
                            raise ValueError(f"task {args.task} is referenced by {t['id']} in {ref}")
        # todo 역참조 사전검사(H2) — todo가 origin_node/resolved_by로 이 task를 가리키면 차단.
        # validate가 사후 raw 'missing node'로 잡지만 친절 메시지로 선제 차단.
        for td in data.get("todos", []):
            if td.get("origin_node") == args.task:
                raise ValueError(f"task {args.task} is referenced by {td['id']} in origin_node")
            if args.task in (td.get("resolved_by") or []):
                raise ValueError(f"task {args.task} is referenced by {td['id']} in resolved_by")
        orig = len(tasks)
        ms["tasks"] = [t for t in tasks if t.get("id") != args.task]
        if len(ms["tasks"]) == orig:
            raise ValueError(f"no task {args.task}")
    transaction(mutate, f"remove-task {args.project}/{args.milestone}/{args.task}")
    print(f"OK: removed task {args.task}"); return 0


def cmd_remove_milestone(data_unused, args):
    def mutate(data):
        p = find_project(data, args.project)
        if not p: raise ValueError(f"no project {args.project}")
        ms = find_milestone(p, args.milestone)
        if not ms: raise ValueError(f"no milestone {args.milestone}")
        if ms.get("tasks"):
            raise ValueError(f"milestone {args.milestone} has tasks — remove tasks first")
        for other in p.get("milestones", []):
            if other.get("id") != args.milestone and args.milestone in (other.get("depends_on") or []):
                raise ValueError(f"milestone {args.milestone} is referenced by {other['id']} in depends_on")
        p["milestones"] = [m for m in p.get("milestones", []) if m.get("id") != args.milestone]
    transaction(mutate, f"remove-milestone {args.project}/{args.milestone}")
    print(f"OK: removed milestone {args.milestone}"); return 0


def cmd_remove_project(data_unused, args):
    def mutate(data):
        p = find_project(data, args.project)
        if not p: raise ValueError(f"no project {args.project}")
        if p.get("milestones"):
            raise ValueError(f"project {args.project} has milestones — remove milestones first")
        data["projects"] = [proj for proj in data.get("projects", []) if proj.get("id") != args.project]
    transaction(mutate, f"remove-project {args.project}")
    print(f"OK: removed project {args.project}"); return 0


def cmd_set_status(data_unused, args):
    # F3: task는 milestone_id 필수 — 마일스톤마다 t1 재생성 시 충돌 방지
    # needs#1: project kind는 id 생략 (자기 자신 반복 제거)
    rest = args.rest
    if args.kind == "task":
        if len(rest) != 3:
            raise ValueError("set-status task 사용법: <project> task <milestone_id> <task_id> <status>")
        milestone_id, item_id, status = rest
    elif args.kind == "milestone":
        if len(rest) != 2:
            raise ValueError("set-status milestone 사용법: <project> milestone <milestone_id> <status>")
        milestone_id, item_id, status = None, rest[0], rest[1]
    elif args.kind == "todo":
        if len(rest) != 2:
            raise ValueError("set-status todo 사용법: <project> todo <todo_id> <status>")
        milestone_id, item_id, status = None, rest[0], rest[1]
    else:  # project
        if len(rest) != 1:
            raise ValueError("set-status project 사용법: <project> project <status>")
        milestone_id, item_id, status = None, None, rest[0]

    def mutate(data):
        p = find_project(data, args.project)
        if not p: raise ValueError(f"no project {args.project}")
        if args.kind == "milestone":
            obj = find_milestone(p, item_id)
        elif args.kind == "task":
            ms = find_milestone(p, milestone_id)
            if not ms: raise ValueError(f"no milestone {milestone_id}")
            obj = next((t for t in (ms.get("tasks") or []) if t.get("id") == item_id), None)
        elif args.kind == "todo":
            obj = next((td for td in data.get("todos", []) if td.get("id") == item_id), None)
            if obj and obj.get("project") != args.project:
                raise ValueError(f"todo {item_id} belongs to {obj.get('project')}, not {args.project}")
        else:  # project
            obj = p
        if not obj: raise ValueError(f"no {args.kind} {item_id or args.project}")
        obj["status"] = status
    label = args.project if args.kind == "project" else f"{args.project}/{item_id}"
    transaction(mutate, f"set-status {label} -> {status}")
    print(f"OK: {label} status={status}")
    return 0


def cmd_add_todo(data_unused, args):
    captured = {}
    def mutate(data):
        if not find_project(data, args.project):
            raise ValueError(f"no project {args.project}")
        data.setdefault("todos", [])
        tdid = _next_id({td["id"] for td in data["todos"]}, "td")
        captured["tdid"] = tdid
        td = {"id": tdid, "project": args.project, "title": args.name,
              "status": "open", "created": _today().isoformat(), "resolved_by": []}
        if args.parent:
            td["origin_node"] = args.parent
        if args.ssot:
            rel = f"ssot/{args.project}.{tdid}.md"
            td["ssot"] = rel
            captured["ssot"] = rel
        data["todos"].append(td)
    transaction(mutate, f"add-todo {args.project}: {args.name}")
    # ssot 파일은 commit 성공 후 생성(best-effort, dirty 게이트 제외) — DA M5
    if captured.get("ssot"):
        ssot_path = PLAN_PATH.parent / captured["ssot"]
        ssot_path.parent.mkdir(parents=True, exist_ok=True)
        if not ssot_path.exists():
            ssot_path.write_text(f"# {args.name}\n\n<!-- 자유편집 -->\n", encoding="utf-8")
            # best-effort 커밋 — 원장 git 추적(원자성 불요, 트랜잭션 밖). 실패해도 무시.
            git("add", str(ssot_path), check=False)
            git("commit", "-q", "-m", f"add-todo ssot {captured['ssot']}", check=False)
    msg = f"OK: added todo {captured['tdid']}"
    if captured.get("ssot"):
        msg += f" ({captured['ssot']})"
    print(msg)
    return 0


def cmd_todos(data, args):
    todos = data.get("todos") or []
    rows = [td for td in todos
            if (not args.project or td.get("project") == args.project)
            and (not args.status or td.get("status") == args.status)]
    if not rows:
        print("(todos 없음)")
        return 0
    for td in rows:
        origin = f"  <-{td['origin_node']}" if td.get("origin_node") else ""
        rb = td.get("resolved_by") or []
        rbs = f"  ->[{','.join(rb)}]" if rb else ""
        line = f"{td['id']}  [{td.get('status','')}]  {td.get('project','')}  {td.get('title','')}{origin}{rbs}"
        if args.verbose and td.get("ssot"):
            line += f"  ({td['ssot']})"
        print(line)
    return 0


def cmd_link_todo(data_unused, args):
    def mutate(data):
        td = next((t for t in data.get("todos", []) if t.get("id") == args.todo), None)
        if not td:
            raise ValueError(f"no todo {args.todo}")
        rb = td.setdefault("resolved_by", [])
        if args.remove:
            if args.by in rb:
                rb.remove(args.by)
        elif args.by not in rb:
            rb.append(args.by)
    op = "-=" if args.remove else "+="
    transaction(mutate, f"link-todo {args.todo} {op} {args.by}")
    print(f"OK: {args.todo} resolved_by {op} {args.by}")
    return 0


def cmd_remove_todo(data_unused, args):
    def mutate(data):
        todos = data.get("todos") or []
        orig = len(todos)
        data["todos"] = [t for t in todos if t.get("id") != args.todo]
        if len(data["todos"]) == orig:
            raise ValueError(f"no todo {args.todo}")
    transaction(mutate, f"remove-todo {args.todo}")
    print(f"OK: removed todo {args.todo}")
    return 0


def main(argv=None):
    # ★교정#4: --file을 공통 parent 파서로 분리 → 서브파서에도 부착
    file_parent = argparse.ArgumentParser(add_help=False)
    file_parent.add_argument("--file", default=str(PLAN_PATH))

    ap = argparse.ArgumentParser(prog="cairn")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status", parents=[file_parent])
    sp_show = sub.add_parser("show", parents=[file_parent])
    sp_show.add_argument("project")
    sp_od = sub.add_parser("overdue", parents=[file_parent])
    sp_od.add_argument("--today", default=None)
    sub.add_parser("render", parents=[file_parent])

    sp_ss = sub.add_parser("set-status")
    sp_ss.add_argument("project")
    sp_ss.add_argument("kind", choices=["project", "milestone", "task", "todo"])
    sp_ss.add_argument("rest", nargs="*")

    sp = sub.add_parser("set-date")
    sp.add_argument("project"); sp.add_argument("id")
    sp.add_argument("field", choices=["start", "end", "due"]); sp.add_argument("date")
    sp.add_argument("--task", default=None)

    sp = sub.add_parser("set-priority")
    sp.add_argument("project"); sp.add_argument("priority")

    sp = sub.add_parser("add-task")
    sp.add_argument("project"); sp.add_argument("milestone"); sp.add_argument("name")
    sp.add_argument("--days", type=int, default=0)

    sp = sub.add_parser("add-milestone")
    sp.add_argument("project"); sp.add_argument("name")

    sp = sub.add_parser("spawn")
    sp.add_argument("name"); sp.add_argument("--from", dest="parent", required=True)
    sp.add_argument("--return-to", dest="return_to", default=None)
    sp.add_argument("--worktree", default=None)
    sp.add_argument("--session", default=None)

    sp = sub.add_parser("complete")
    sp.add_argument("task"); sp.add_argument("--force", action="store_true")

    sp = sub.add_parser("return")
    sp.add_argument("--to", required=True)

    sp = sub.add_parser("map")
    sp.add_argument("--focus", default=None)
    sp.add_argument("--render", action="store_true")
    sp.add_argument("--png", action="store_true", help="PNG로 구워 Preview에 표시(mmdc 필요)")
    sp.add_argument("--html", action="store_true",
                    help="자체완결 HTML로 생성해 브라우저에 표시(mermaid.js CDN, 의존성 불필요)")
    sp.add_argument("--show-merged", dest="show_merged", action="store_true",
                    help="병합 완료된 노드도 포함(기본은 숨김)")

    sp = sub.add_parser("link")
    sp.add_argument("node")
    sp.add_argument("--execution-ref", dest="execution_ref", default=None)
    sp.add_argument("--session-ref", dest="session_ref", default=None)
    sp.add_argument("--add-session", dest="add_session", default=None,
                    help="세션 핸드오프(#1→#2→#3)를 session_chain에 누적")
    sp.add_argument("--merge-back-to", dest="merge_back_to", default=None)

    sp = sub.add_parser("depends")
    sp.add_argument("project")
    sp.add_argument("node")
    sp.add_argument("--on", dest="on", required=True, help="의존 대상 노드 id (동종: ms↔ms, task↔task)")
    sp.add_argument("--remove", action="store_true", help="의존 제거")

    sp = sub.add_parser("set-group")
    sp.add_argument("project")
    sp.add_argument("milestone")
    sp.add_argument("name", help="제품/목표묶음 그룹 라벨 (빈 문자열이면 제거)")

    sp = sub.add_parser("new-project")
    sp.add_argument("name")

    sub.add_parser("init")

    sub.add_parser("reconcile", parents=[file_parent])
    sub.add_parser("validate", parents=[file_parent])
    sub.add_parser("self-test", parents=[file_parent])
    sub.add_parser("revert")

    sp = sub.add_parser("add-todo")
    sp.add_argument("project"); sp.add_argument("name")
    sp.add_argument("--from", dest="parent", default=None)
    sp.add_argument("--ssot", action="store_true")

    sp = sub.add_parser("todos", parents=[file_parent])
    sp.add_argument("--project", default=None)
    sp.add_argument("--status", default=None)
    sp.add_argument("--verbose", action="store_true")

    sp = sub.add_parser("link-todo")
    sp.add_argument("todo"); sp.add_argument("--by", required=True)
    sp.add_argument("--remove", action="store_true")

    sp = sub.add_parser("remove-todo")
    sp.add_argument("todo")

    sp = sub.add_parser("remove-task")
    sp.add_argument("project"); sp.add_argument("milestone"); sp.add_argument("task")

    sp = sub.add_parser("remove-milestone")
    sp.add_argument("project"); sp.add_argument("milestone")

    sp = sub.add_parser("remove-project")
    sp.add_argument("project")

    args = ap.parse_args(argv)

    # needs#7: revert/self-test는 SoT 로드 불필요 — 깨진 SoT에서도 복구/진단 가능해야 함
    if args.cmd in ("revert", "self-test", "init"):
        handler = {"revert": cmd_revert, "self-test": cmd_self_test, "init": cmd_init}[args.cmd]
        try:
            return handler(None, args)
        except (ValueError, RuntimeError, OSError, YAMLError, subprocess.CalledProcessError) as e:
            print(f"오류: {e}"); return 1

    try:
        data = load_plan(getattr(args, "file", str(PLAN_PATH)))
    except Exception as e:
        print(f"cairn: load error: {e}", file=sys.stderr)
        return 1
    handler = {"status": cmd_status, "show": cmd_show,
               "overdue": cmd_overdue, "render": cmd_render,
               "set-status": cmd_set_status, "set-date": cmd_set_date,
               "set-priority": cmd_set_priority, "add-task": cmd_add_task,
               "add-milestone": cmd_add_milestone, "new-project": cmd_new_project,
               "spawn": cmd_spawn, "complete": cmd_complete, "return": cmd_return,
               "map": cmd_map, "link": cmd_link, "depends": cmd_depends,
               "set-group": cmd_set_group, "reconcile": cmd_reconcile,
               "validate": cmd_validate,
               "remove-task": cmd_remove_task, "remove-milestone": cmd_remove_milestone,
               "remove-project": cmd_remove_project,
               "add-todo": cmd_add_todo, "todos": cmd_todos,
               "link-todo": cmd_link_todo, "remove-todo": cmd_remove_todo}[args.cmd]
    try:
        return handler(data, args)
    except (ValueError, RuntimeError, OSError, YAMLError, subprocess.CalledProcessError) as e:
        # 교정#1: CalledProcessError도 비0; F2-fix: RuntimeError; S1: OSError; S2: YAMLError
        print(f"오류: {e}"); return 1


if __name__ == "__main__":
    raise SystemExit(main())
