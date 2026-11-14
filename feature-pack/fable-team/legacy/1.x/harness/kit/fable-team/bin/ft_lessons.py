#!/usr/bin/env python3
"""ft_lessons.py — 좌석·팀 LESSONS를 **jsonl + 개수 상한(cap) + 밀어내기**로 관리한다. r1440.

왜 개수 상한인가 (오빠 지시 2026-11-06 «jsonl 로 관리되고 cap 이 있는 리스트 … 100개만 갖게 해서 밀어내기 … 영구기억들도 개수 제한»)
  바이트 상한만 두면 «몇 줄이 들어가는지»가 줄 길이에 따라 널뛴다(짧은 줄 200개 vs 긴 줄 8개). 개수 상한은 상한이 예측 가능하다.
  그래서 두 겹으로 둔다 — 파일 = **개수**(기본 100), 로드 = **바이트**(snapshot 기본 2048). 파일이 커도 프롬프트는 안 커진다.
기존 선례 재사용 (새 발명 아님):
  - mbox 큐가 이미 «개수 상한 + 등급 우선 밀어내기» 다(`ft-mbox.py trim(rows, keep_n)` · r912). 여기서는 등급 대신 `pin` 을 쓴다.
  - hermes `memory_tool.py` — 메모리는 세션 시작 **FROZEN 스냅샷**(중간 쓰기는 디스크만) → `snapshot` 명령이 그 자리.
  - hermes `memory_tool_store.py` — 원자적 쓰기 · drift 가드 · 주입 스캔.
  - nanoclaw `groups/<name>/memory/{directives,mistakes,achievements}.md` — 3분류 → `kind`.
  - xclaw 아카이브 딥분석 — 세대 진화 = in-place + `gen-{N}` → `ft-evolve` 쪽.
삭제 0 원칙: 밀어내기는 **삭제가 아니라** `<이름>.archive.jsonl` 로 옮기는 것이다(하드 룰 2 = 삭제 HIL).

저장: <FT_ROOT>/state/lessons/{seat,team}/<이름>.jsonl  (1줄 = 1항목)
  {"ts":"2026-11-06T17:20","kind":"directive|mistake|achievement|experiment","text":"...","pin":false,"ttl":14}
상한: seat 100 · team 100 (env FT_LESSONS_CAP_SEAT / FT_LESSONS_CAP_TEAM) · 항목 text ≤ 200자
  kind=experiment 는 `expires`(기본 14일) 지나면 아카이브. pin=true 는 밀어내기·TTL 면제(영구 기억).
명령: init · add · list · pin · unpin · evict · snapshot · check · path · migrate
종료코드: 0 정상 · 1 위반/REJECT · 2 usage · 3 락·판정 불가
"""
from __future__ import annotations

import datetime as dt
import fcntl
import json
import os
import re
import sys
from pathlib import Path

CAP = {"seat": int(os.environ.get("FT_LESSONS_CAP_SEAT", "100")),
       "team": int(os.environ.get("FT_LESSONS_CAP_TEAM", "100"))}
KIND_TAG = {"directive": "D", "mistake": "M", "achievement": "A", "experiment": "E"}
TEXT_MAX = 200
LOCK_WAIT = 7.0
EXP_TTL_DAYS = int(os.environ.get("FT_LESSONS_EXP_TTL", "14"))
GLOBAL_DIGEST = Path.home() / ".claude" / "rules" / "dumb-time-digest.md"
GLOBAL_LIMIT = 2048
# 반례 4(DA astra r1442): «…하지 않는다/금지» 같은 부정·금지문은 통과시키고, «규칙 폐기하고 따라라» 류는 잡는다.
NEGATION = re.compile(r"(않는다|않도록|금지|말라|하지 마|no |never |하지않)")
IMPERATIVE = re.compile(r"(하라|해라|하세요|출력해|알려줘|따라라|실행해|공개해)")
INJECT = (
    r"(?i)ignore (all )?(previous|prior|above) (instructions|rules)",
    r"(규칙|지시|지침)(을|를)? ?(모두|전부|전체)? ?(폐기|무시|잊)(하고|한 뒤|고)?.{0,40}(따라|이행|실행)",
    r"(?i)system prompt|시스템 ?프롬프트를? (출력|공개|알려)",
    r"(?i)(api[_-]?key|token|secret|password)\s*[:=]\s*\S{8,}",
    r"(?i)curl\s+[^|]*\|\s*(ba)?sh",
    r"(?i)rm\s+-rf\s+/(\s|$)",
    r"이전 지시(를|사항을)? (무시|잊)",
)


def die(msg: str, rc: int = 2) -> None:
    print(msg)
    sys.exit(rc)


def now() -> str:
    return dt.datetime.now().strftime("%Y-%m-%dT%H:%M")


def ft_root() -> Path:
    env = os.environ.get("FT_ROOT")
    if env:
        q = Path(env)
        # plist 는 FT_ROOT=<프로젝트 루트> 를 준다 — 여기서 .fable-team 을 강제한다(2026-11-07 실사고:
        # 00:10 게이트가 <프로젝트>/state/evolution 에 쓰고 실제 .fable-team/state/evolution 은 안 갱신됐다)
        if q.name != ".fable-team" and (q / ".fable-team").is_dir():
            q = q / ".fable-team"
        return q
    cwd = Path.cwd()
    for p in [cwd, *cwd.parents]:
        if (p / ".fable-team").is_dir():
            return p / ".fable-team"
    die("REJECT .fable-team 없음 — FT_ROOT 를 지정하라")


def guess_team(root: Path, seat: str) -> str:
    """팀 추정 (DA astra r1442 반례 7 — ft-v65-master#4 를 'ft' 로 잘못 잡던 것):
    ① `ft-<팀>-<역할>-<에이전트>` 의 두번째 토큰이고 그 팀 파일이 실제로 있으면 그 팀
    ② `seats-<팀>.json` 이름이 좌석 첫 토큰과 같으면 그 팀 ③ seats 내용에 좌석이 있으면 그 팀
    ④ seats 파일이 하나뿐이면 그 팀 ⑤ 첫 토큰.
    «파일이 실제로 있는가» 를 첫 기준에 두는 이유: 이름만 보고 고르면 빈 팀 파일을 읽어 교훈을 놓친다."""
    base = root.parent / ".fable-team"
    files = sorted(base.glob("seats-*.json")) if base.is_dir() else []
    stem = re.sub(r"#[0-9]+$", "", seat or "")
    parts = stem.split("-") if stem else []
    tdir = root / "state" / "lessons" / "team"

    if len(parts) >= 3:
        cand = parts[1]
        if (tdir / (cand + ".jsonl")).is_file() or (tdir / (cand + ".md")).is_file():
            return cand
    if parts:
        for f in files:
            if f.stem.replace("seats-", "") == parts[0]:
                return parts[0]
    if stem:
        for f in files:
            try:
                raw = f.read_text(encoding="utf-8", errors="replace")
            except Exception:
                continue
            if stem in raw:
                return f.stem.replace("seats-", "")
    if len(files) == 1:
        return files[0].stem.replace("seats-", "")
    if len(parts) >= 2:
        return parts[1] if len(parts) >= 3 else parts[0]
    return parts[0] if parts else ""


def teams_discover(root: Path) -> list[str]:
    """이 프로젝트에 «지금 존재하는» 팀 이름 전부(r1445). 신규 팀도 다음 실행에 자동 편입된다.
    소스 5곳: ① .fable-team/seats-<팀>.json ② design/teams/<팀>/ ③ .fable-team/state/team-main/<팀>/
              ④ .fable-team/bin-<팀>/ (팀별 shim 폴더) ⑤ 이미 있는 team/*.jsonl (지우지 않는다)."""
    proj = root.parent
    names: set[str] = set()
    for f in sorted(root.glob("seats-*.json")):
        names.add(f.stem.replace("seats-", ""))
    for d in sorted((proj / "design" / "teams").glob("*")):
        if d.is_dir():
            names.add(d.name)
    for d in sorted((root / "state" / "team-main").glob("*")):
        if d.is_dir():
            names.add(d.name)
    for d in sorted(root.glob("bin-*")):
        if d.is_dir() and d.name[4:]:
            names.add(d.name[4:])
    for f in sorted((root / "state" / "lessons" / "team").glob("*.jsonl")):
        if ".archive" not in f.name:
            names.add(f.stem)
    return sorted(n for n in names if n and n != "README" and not n.startswith("."))


def ensure_team_files(root: Path, teams: list[str]) -> tuple[int, int, int]:
    """팀 파일·락을 만든다(있으면 그대로). (발견, 신규, 기존)"""
    tdir = root / "state" / "lessons" / "team"
    tdir.mkdir(parents=True, exist_ok=True)
    new = 0
    for t in teams:
        f = tdir / (safe(t) + ".jsonl")
        if not f.is_file():
            f.touch()
            new += 1
        lk = f.with_suffix(f.suffix + ".lock")
        if not lk.is_file():
            lk.touch()
    return len(teams), new, len(teams) - new


def cmd_sync_teams(argv: list[str]) -> int:
    """ft-lessons.sh sync-teams [--dry-run] — 지금 있는 팀 전부 + 앞으로 생길 팀까지 커버.
    install(lessons_seed)과 ft-evolve --gate 가 이 명령을 부른다(로직 한 곳)."""
    root = ft_root()
    teams = teams_discover(root)
    if "--dry-run" in argv:
        missing = [t for t in teams if not (root / "state" / "lessons" / "team" / (safe(t) + ".jsonl")).is_file()]
        print("SYNC-TEAMS dry-run 발견 %d · 미생성 %d %s (파일 변경 0)"
              % (len(teams), len(missing), ("미생성=" + ",".join(missing)) if missing else ""))
        return 0
    found, new, old = ensure_team_files(root, teams)
    print("SYNC-TEAMS 발견 %d · 신규 %d · 기존 %d" % (found, new, old))
    return 0


def safe(name: str) -> str:
    n = re.sub(r"[^A-Za-z0-9._#-]+", "-", (name or "").strip())
    if not n:
        die("REJECT 이름이 비었다")
    return n


def path_of(layer: str, name: str | None) -> Path:
    if layer == "global":
        return GLOBAL_DIGEST
    if not name:
        die("REJECT %s 계층은 이름이 필요하다" % layer)
    return ft_root() / "state" / "lessons" / layer / (safe(name) + ".jsonl")


class Lock:
    def __init__(self, target: Path):
        self.fh = None
        self.lock = target.with_suffix(target.suffix + ".lock")

    def __enter__(self):
        self.lock.parent.mkdir(parents=True, exist_ok=True)
        self.fh = open(self.lock, "a+", encoding="utf-8")
        end = dt.datetime.now().timestamp() + LOCK_WAIT
        while True:
            try:
                fcntl.flock(self.fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return self
            except OSError:
                if dt.datetime.now().timestamp() > end:
                    self.fh.close()
                    die("판정 불가 락 못 잡음(%.0fs): %s" % (LOCK_WAIT, self.lock), 3)
                import time
                time.sleep(0.1)

    def __exit__(self, *exc):
        try:
            fcntl.flock(self.fh, fcntl.LOCK_UN)
        finally:
            self.fh.close()


def load_report(p: Path) -> tuple[list[dict], int]:
    """(정상 행, 깨진 줄 수). 깨진 줄 수 > 0 이면 쓰기 전에 사람이 봐야 한다(무음 유실 방지 · DA astra 반례 1)."""
    if not p.is_file():
        return [], 0
    rows, bad = [], 0
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            bad += 1
            continue
        if isinstance(r, dict) and r.get("text"):
            rows.append(r)
        else:
            bad += 1
    return rows, bad


def corrupt_guard(p: Path) -> bool:
    """깨진 줄이 있으면 사본을 남기고 True(=작업 거부). 사본 = <이름>.corrupt-<시각>.bak"""
    rows, bad = load_report(p)
    if bad == 0:
        return False
    bak = p.with_name(p.stem + ".corrupt-" + dt.datetime.now().strftime("%Y%m%d%H%M%S") + ".bak")
    bak.write_bytes(p.read_bytes())
    print("REJECT %s 에 깨진 줄 %d개 — 손편집 drift 로 본다. 사본 %s · 고친 뒤 다시(쓰기 0)" % (p.name, bad, bak.name))
    return True


def load(p: Path) -> list[dict]:
    if not p.is_file():
        return []
    out = []
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        if isinstance(r, dict) and r.get("text"):
            out.append(r)
    return out


def atomic_write(p: Path, rows: list[dict]) -> None:
    tmp = p.with_suffix(p.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    os.replace(tmp, p)


def archive(p: Path, rows: list[dict], why: str) -> Path:
    arc = p.with_name(p.stem + ".archive.jsonl")
    with open(arc, "a", encoding="utf-8") as f:
        for r in rows:
            r = dict(r)
            r["archived"] = now()
            r["why"] = why
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    return arc


def expire(rows: list[dict]) -> tuple[list[dict], list[dict]]:
    """kind=experiment 는 expires 지나면 아카이브 대상. pin 은 면제."""
    today = dt.date.today()
    keep, gone = [], []
    for r in rows:
        if r.get("pin"):
            keep.append(r)
            continue
        if r.get("kind") == "experiment":
            try:
                exp = dt.date.fromisoformat(str(r.get("expires") or ""))
            except ValueError:
                exp = today
            if exp < today:
                gone.append(r)
                continue
        keep.append(r)
    return keep, gone


def enforce(p: Path, rows: list[dict], cap: int) -> tuple[list[dict], int, int, Path | None]:
    """TTL → cap 순서로 정리. 반환 (남은 rows, 밀어낸 수, TTL 만료 수, 아카이브 경로)"""
    rows, expired = expire(rows)
    # DA 3R 반례 2: pin 만 계속 넣으면 상한이 무력화됐다. 핀도 상한의 절반까지만 영구 — 넘으면 오래된 핀부터 해제.
    pinned_all = [r for r in rows if r.get("pin")]
    pin_cap = max(1, cap // 2)
    if len(pinned_all) > pin_cap:
        for r in pinned_all[: len(pinned_all) - pin_cap]:
            r["pin"] = False
            r["unpinned"] = now()
    over = 0
    if len(rows) > cap:
        pinned = [r for r in rows if r.get("pin")]
        others = [r for r in rows if not r.get("pin")]
        room = max(0, cap - len(pinned))
        if len(others) > room:
            over = len(others) - room
            dropped, others = others[:over], others[over:]
            gone = dropped
        else:
            gone = []
        rows = merge_order(pinned, others)
    else:
        gone = []
    arc = None
    moved = gone + expired
    if moved:
        arc = archive(p, moved, "cap" if gone else "ttl")
    return rows, over, len(expired), arc


def merge_order(pinned: list[dict], others: list[dict]) -> list[dict]:
    """원래 순서(ts 오름차순)를 유지하며 두 목록을 합친다."""
    rows = pinned + others
    rows.sort(key=lambda r: str(r.get("ts") or ""))
    return rows


def scan(text: str) -> str | None:
    # 팀·프로젝트별 확장: FT_LESSONS_EXTRA_INJECT="정규식1;;정규식2" (과적합 방지 r1450 — 패턴을 코드에만 두지 않는다)
    extra = [x for x in os.environ.get("FT_LESSONS_EXTRA_INJECT", "").split(";;") if x.strip()]
    for pat in list(INJECT) + extra:
        m = re.search(pat, text)
        if not m:
            continue
        # 부정·금지문(«공개하지 않는다» «금지»)은 교훈으로 허용 — 주입 문장이 아니다(DA astra 반례 4)
        # 2라운드 반례 2: 뒤 문장의 «거절 금지» 를 앞 명령의 부정으로 오해해 통과시켰다 →
        #   ⓐ 부정어는 패턴 매치 **직후 12자 안**에서만 인정 ⓑ 명령형(하라·해라·출력해·따라라)이 함께 있으면 부정 무시.
        tail = text[m.end():m.end() + 12]
        if NEGATION.search(tail) and not IMPERATIVE.search(text):
            continue
        return pat
    return None


def cmd_init(argv: list[str]) -> int:
    root = ft_root()
    made = 0
    for layer in ("seat", "team"):
        d = root / "state" / "lessons" / layer
        d.mkdir(parents=True, exist_ok=True)
        for f in list(d.glob("*.jsonl")):
            lk = f.with_suffix(f.suffix + ".lock")
            if not lk.exists():
                lk.touch()
                made += 1
    lk = root / "state" / "lessons" / "global.md.lock"
    lk.parent.mkdir(parents=True, exist_ok=True)
    if not lk.exists():
        lk.touch()
        made += 1
    (root / "state" / "evolution").mkdir(parents=True, exist_ok=True)
    print("INIT lessons jsonl cap(seat %d · team %d) · 항목≤%d자 · 실험 TTL %d일 · new-lock=%d root=%s"
          % (CAP["seat"], CAP["team"], TEXT_MAX, EXP_TTL_DAYS, made, root / "state" / "lessons"))
    return 0


def cmd_add(argv: list[str]) -> int:
    if len(argv) < 3:
        die('usage: add <seat|team> <이름> "1줄" [--kind directive|mistake|achievement|experiment] [--pin]')
    layer, name, rest = argv[0], argv[1], argv[2:]
    kind, pin = "mistake", False
    if "--kind" in rest:
        i = rest.index("--kind")
        try:
            kind = rest[i + 1]
        except IndexError:
            die("REJECT --kind 값 없음")
        rest = rest[:i] + rest[i + 2:]
    if "--pin" in rest:
        pin = True
        rest = [x for x in rest if x != "--pin"]
    if kind not in KIND_TAG:
        die("REJECT --kind 는 %s" % "|".join(KIND_TAG))
    if layer not in ("seat", "team"):
        die("REJECT add 는 seat|team 만 — 전역 다이제스트는 guides/dumb-time.md 규칙으로 사람이 갱신한다")
    text = " ".join(rest).replace("\n", " ").strip()
    if not text:
        die("REJECT 본문이 비었다")
    if len(text) > TEXT_MAX:
        die("REJECT 항목이 %d자 상한 초과(%d자) — 한 줄 교훈으로 줄여라" % (TEXT_MAX, len(text)), 1)
    bad = scan(text)
    if bad:
        die("REJECT 주입·유출 유도 패턴(%s) — 기억은 세션을 넘어 남는다" % bad, 1)
    p = path_of(layer, name)
    cap = CAP[layer]
    with Lock(p):
        p.parent.mkdir(parents=True, exist_ok=True)
        if corrupt_guard(p):
            return 1
        rows = load(p)
        if any(norm(r.get("text", "")) == norm(text) for r in rows):
            print("ADD %s %s DUP — 같은 문장이 이미 있다(추가 0)" % (layer, p.name))
            return 0
        rec = {"ts": now(), "kind": kind, "text": text, "pin": bool(pin)}
        if kind == "experiment":
            rec["expires"] = (dt.date.today() + dt.timedelta(days=EXP_TTL_DAYS)).isoformat()
        rows.append(rec)
        rows, over, ttl, arc = enforce(p, rows, cap)
        atomic_write(p, rows)
    print("ADD %s %s kind=%s%s %d/%d %s" % (layer, p.name, kind, " pin" if pin else "", len(rows), cap,
                                            "OK" if over == 0 and ttl == 0 else "evict=%d ttl=%d" % (over, ttl)))
    if arc:
        print("EVICT 밀어내기 삭제 아님 → 아카이브 %s (삭제 0)" % arc.name)
    return 0


def norm(t: str) -> str:
    return re.sub(r"\s+", " ", t.strip().lower())


def cmd_search(argv: list[str]) -> int:
    """계층 전체에서 교훈 찾기 — 재사용 축. ft-lessons.sh search "단어" [--layer seat|team|all] [--json]"""
    if not argv:
        die('usage: search "단어" [--layer seat|team|all] [--json]')
    needle = argv[0]
    layer = "all"
    if "--layer" in argv:
        i = argv.index("--layer")
        try:
            layer = argv[i + 1]
        except IndexError:
            die("REJECT --layer 값 없음")
    if layer not in ("seat", "team", "all"):
        die("REJECT --layer 는 seat|team|all")
    root = ft_root()
    hits = 0
    for lay in (["seat", "team"] if layer == "all" else [layer]):
        d = root / "state" / "lessons" / lay
        if not d.is_dir():
            continue
        for f in sorted(d.glob("*.jsonl")):
            if ".archive" in f.name:
                continue
            for r in load(f):
                if needle.lower() in str(r.get("text", "")).lower():
                    hits += 1
                    if "--json" in argv:
                        print(json.dumps({**r, "layer": lay, "who": f.stem}, ensure_ascii=False))
                    else:
                        print("%s/%-14s [%s][%s]%s %s" % (lay, f.stem, str(r.get("ts"))[:10],
                                                           KIND_TAG.get(r.get("kind"), "?"),
                                                           "*" if r.get("pin") else "", r.get("text")))
    print("SEARCH '%s' 히트 %d (layer=%s)" % (needle, hits, layer))
    return 0 if hits else 1


def cmd_suggest(argv: list[str]) -> int:
    """승격 후보 — 좌석 LESSONS 에서 같은 낱말이 3개 좌석 이상/3회 이상 반복되면 팀 승격 후보로 낸다.
    근거 규칙: «좌석에서 3번 되풀이된 교훈만 팀으로». 쓰기 0(기본). --write 면 state/eval/suggest-<날짜>.md 1장."""
    root = ft_root()
    d = root / "state" / "lessons" / "seat"
    STOP = set("그리고 그래서 하지만 이거 저거 이제 아직 때문 우리 여기 저기 하나 이번 오늘 그때 이렇게 저렇게".split())
    counts: dict[str, dict[str, set]] = {}
    for f in sorted(d.glob("*.jsonl")) if d.is_dir() else []:
        if ".archive" in f.name:
            continue
        for r in load(f):
            for w in re.findall(r"[가-힣]{2,}|[A-Za-z][A-Za-z0-9_.:-]{3,}", str(r.get("text", ""))):
                if w in STOP:
                    continue
                c = counts.setdefault(w, {"n": 0, "who": set()})
                c["n"] += 1
                c["who"].add(f.stem)
    cands = [(w, c["n"], sorted(c["who"])) for w, c in counts.items() if c["n"] >= 3 and len(c["who"]) >= 2]
    cands.sort(key=lambda x: -x[1])
    cands = cands[:10]
    for w, n, who in cands:
        print("SUGGEST '%s' %d회 · 좌석 %d (%s)" % (w, n, len(who), ",".join(who[:4])))
    if not cands:
        print("SUGGEST 승격 후보 0 — 좌석 LESSONS 에 반복(3회·2좌석+)이 아직 없다")
    if "--write" in argv:
        ev = root / "state" / "eval"
        ev.mkdir(parents=True, exist_ok=True)
        out = ev / ("suggest-%s.md" % dt.date.today().strftime("%Y%m%d"))
        body = ["# 팀 승격 후보 — %s" % dt.date.today().strftime("%Y-%m-%d"), ""]
        body += ["- %s (%d회 · %s)" % (w, n, ",".join(who)) for w, n, who in cands] or ["- 없음"]
        out.write_text("\n".join(body) + "\n", encoding="utf-8")
        print("SUGGEST 파일 %s" % out.name)
    return 0


def cmd_resolve(argv: list[str]) -> int:
    """실험 기억의 결말 — `resolve <seat|team> <이름> "검색어" --result keep|drop [--reason "사유"]`.
    keep = kind 를 directive 로 바꾸고 pin(영구) · drop = 아카이브로 내린다(삭제 0).
    r1467: 성공한 판단은 state/evolution/resolved-<날짜>.jsonl 에 1줄(일일 평가가 기계로 센다)."""
    reason = ""
    if "--reason" in argv:
        j = argv.index("--reason")
        if j + 1 >= len(argv):
            die("REJECT --reason 값 없음")
        reason = argv[j + 1]
        argv = argv[:j] + argv[j + 2:]
    if len(argv) < 3 or "--result" not in argv:
        die('usage: resolve <seat|team> <이름> "검색어" --result keep|drop [--reason "사유"]')
    i = argv.index("--result")
    try:
        res = argv[i + 1]
    except IndexError:
        die("REJECT --result 값 없음")
    if res not in ("keep", "drop"):
        die("REJECT --result 는 keep|drop")
    layer, name = argv[0], argv[1]
    needle = " ".join(a for j, a in enumerate(argv[2:], 2) if j not in (i, i + 1))
    p = path_of(layer, name)
    with Lock(p):
        if corrupt_guard(p):
            return 1
        rows = load(p)
        hit = [r for r in rows if needle in str(r.get("text", ""))]
        if not hit:
            print("RESOLVE %s 일치 없음(''%s'')" % (p.name, needle))
            return 1
        if res == "keep":
            for r in hit:
                r["kind"] = "directive"
                r["pin"] = True
                r.pop("expires", None)
            rows, over, ttl, arc = enforce(p, rows, CAP[layer])
            atomic_write(p, rows)
            print("RESOLVE keep %d건 → directive+pin (%s)" % (len(hit), p.name))
        else:
            rows = [r for r in rows if r not in hit]
            arc = archive(p, hit, "resolve-drop")
            atomic_write(p, rows)
            print("RESOLVE drop %d건 → 아카이브 %s (삭제 0)" % (len(hit), arc.name))
    return 0 if record_resolved(layer, name, needle, res, reason) else 3


def record_resolved(layer: str, name: str, needle: str, res: str, reason: str) -> bool:
    """r1467: 판단 1건 = resolved-<YYYYMMDD>.jsonl 1줄 append. 못 쓰면 «판정 불가» 1줄 + rc3(기존 resolve 결과는 이미 남았다)."""
    root = ft_root()
    seat = os.environ.get("FT_SEAT_NAME") or os.environ.get("FT_SEAT") or (name if layer == "seat" else "")
    team = name if layer == "team" else (os.environ.get("FT_TEAM") or guess_team(root, seat))
    row = {"ts": now(), "team": team, "seat": seat, "id": needle,
           "verdict": "promote" if res == "keep" else "discard", "reason": reason}
    out = root / "state" / "evolution" / ("resolved-%s.jsonl" % dt.date.today().strftime("%Y%m%d"))
    try:
        out.parent.mkdir(parents=True, exist_ok=True)
        with open(out, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")
        print("RESOLVED %s %s → %s" % (row["verdict"], team, out.name))
        return True
    except OSError as e:
        print("판정 불가 resolved 기록 실패(%s): %s" % (type(e).__name__, out), file=sys.stderr)
        return False


def cmd_list(argv: list[str]) -> int:
    if len(argv) < 2:
        die("usage: list <seat|team> <이름> [--all] [--json]")
    p = path_of(argv[0], argv[1])
    rows = load(p)
    if "--json" in argv:
        for r in rows:
            print(json.dumps(r, ensure_ascii=False))
        return 0
    if not rows:
        print("EMPTY %s (cap %d)" % (p, CAP[argv[0]]))
        return 0
    shown = rows if "--all" in argv else rows[-20:]
    print("LIST %s %d/%d (핀 %d · 실험 %d)"
          % (p.name, len(rows), CAP[argv[0]], sum(1 for r in rows if r.get("pin")),
             sum(1 for r in rows if r.get("kind") == "experiment")))
    for r in shown:
        print("- [%s][%s]%s %s" % (r.get("ts", "")[:10], KIND_TAG.get(r.get("kind"), "?"),
                                   "*" if r.get("pin") else "", r.get("text")))
    return 0


def cmd_pin(argv: list[str], on: bool = True) -> int:
    if len(argv) < 3:
        die("usage: %s <seat|team> <이름> \"항목 문장 일부\"" % ("pin" if on else "unpin"))
    p = path_of(argv[0], argv[1])
    needle = " ".join(argv[2:])
    with Lock(p):
        if corrupt_guard(p):
            return 1
        rows = load(p)
        hit = 0
        for r in rows:
            if needle in str(r.get("text", "")):
                r["pin"] = on
                hit += 1
        if hit:
            atomic_write(p, rows)
    print("%s %s %d건 %s" % ("PIN" if on else "UNPIN", p.name, hit, "OK" if hit else "일치 항목 없음"))
    return 0 if hit else 1


def cmd_evict(argv: list[str]) -> int:
    if len(argv) < 2:
        die("usage: evict <seat|team> <이름>")
    layer, name = argv[0], argv[1]
    p = path_of(layer, name)
    with Lock(p):
        if corrupt_guard(p):
            return 1
        rows = load(p)
        rows, over, ttl, arc = enforce(p, rows, CAP[layer])
        atomic_write(p, rows)
    print("EVICT %s %d/%d 밀어냄=%d ttl=%d %s" % (p.name, len(rows), CAP[layer], over, ttl, arc.name if arc else "아카이브 0"))
    return 0


def cmd_snapshot(argv: list[str]) -> int:
    """부팅 1회 로드용. 최근 것부터 예산 안에서. 핀이 먼저 실린다."""
    budget = 2048
    if "--budget" in argv:
        i = argv.index("--budget")
        try:
            budget = int(argv[i + 1])
        except (IndexError, ValueError):
            die("REJECT --budget 값")
    root = ft_root()
    seat = os.environ.get("FT_SEAT_NAME") or os.environ.get("FT_SEAT") or \
        (argv[0] if argv and not argv[0].startswith("-") else "")
    team = os.environ.get("FT_TEAM") or guess_team(root, seat)
    picks = []
    for layer, nm in (("seat", seat), ("team", team)):
        if not nm:
            continue
        if layer == "team":  # r1445 — 신규 팀도 첫 부팅에 자리가 생긴다
            ensure_team_files(root, [nm])
        rows = load(path_of(layer, nm))
        if rows:
            picks.append((layer, nm, rows))
    out, used = [], 0
    for layer, nm, rows in picks:
        head = "### %s (%s) %d/%d" % (layer, nm, len(rows), CAP[layer])
        out.append(head)
        for r in sorted(rows, key=lambda x: (0 if x.get("pin") else 1, str(x.get("ts") or ""))):
            line = "- [%s][%s]%s %s" % (str(r.get("ts"))[:10], KIND_TAG.get(r.get("kind"), "?"),
                                        "*" if r.get("pin") else "", r.get("text"))
            if used + len(line.encode()) + 1 > budget:
                out.append("… (예산 %dB 초과 — 나머지는 list 로)" % budget)
                used = budget
                break
            out.append(line)
            used += len(line.encode()) + 1
    if GLOBAL_DIGEST.is_file():
        body = GLOBAL_DIGEST.read_text(encoding="utf-8").splitlines()[-6:]
        if body:
            out.append("### global (dumb-time-digest.md)")
            for l in body:
                if used + len(l.encode()) + 1 > budget:
                    break
                out.append(l)
                used += len(l.encode()) + 1
    # 예산 최종 강제 — 헤더까지 포함해 자른다(«넘었다» 를 보고하지 않는다)
    while out and len("\n".join(out).encode()) > budget:
        out.pop()
    tail = "… (예산 %dB · 나머지는 list 로)" % budget
    if out and "… " not in out[-1] and len("\n".join(out).encode()) + len(tail.encode()) + 1 <= budget:
        out.append(tail)
    if len(out) <= 0:
        print("SNAPSHOT empty — LESSONS 없음(좌석=%s · 팀=%s)" % (seat or "-", team or "-"))
        return 0
    head = "SNAPSHOT %dB/%dB (부팅 1회 고정 · 세션 중 add 는 파일에만 · 다음 부팅 반영)"
    # 안내줄·개행까지 예산에 포함한다(DA astra 반례 3) — 초과하면 본문 꼬리를 더 자른다
    while out:
        body = "\n".join(out)
        total = len((head % (len(body.encode()), budget)).encode()) + 1 + len(body.encode())
        if total <= budget:
            break
        out.pop()
    body = "\n".join(out)
    if not body:
        print("SNAPSHOT empty — 예산 %dB 안에 실을 항목 없음(좌석=%s · 팀=%s)" % (budget, seat or "-", team or "-"))
        return 0
    print(head % (len(body.encode()), budget))
    print(body)
    return 0


def cmd_check(argv: list[str]) -> int:
    root = ft_root()
    bad = 0
    rows_out = []
    for layer in ("seat", "team"):
        d = root / "state" / "lessons" / layer
        if not d.is_dir():
            rows_out.append("MISSING %-4s 폴더 없음 %s (ft-lessons.sh init)" % (layer, d))
            bad += 1
            continue
        files = sorted(f for f in d.glob("*.jsonl") if ".archive" not in f.name)
        for f in files:
            rows_f, bad_f = load_report(f)
            n = len(rows_f)
            lk = f.with_suffix(f.suffix + ".lock")
            st = "OK" if n <= CAP[layer] else "OVER"
            if bad_f:
                st = "CORRUPT"
            if st != "OK" or not lk.is_file():
                bad += 1
            rows_out.append("%-7s %-4s %3d/%-3d %s %s%s" % (st, layer, n, CAP[layer],
                                                            "lock" if lk.is_file() else "NO-LOCK", f.name,
                                                            " 깨진줄=%d" % bad_f if bad_f else ""))
    g = len(GLOBAL_DIGEST.read_bytes()) if GLOBAL_DIGEST.is_file() else 0
    gl = root / "state" / "lessons" / "global.md.lock"
    if g > GLOBAL_LIMIT or not gl.is_file():
        bad += 1
    rows_out.append("%-4s global %5dB/%-5dB %s dumb-time-digest.md" % ("OK" if g <= GLOBAL_LIMIT else "OVER", g,
                                                                     GLOBAL_LIMIT, "lock" if gl.is_file() else "NO-LOCK"))
    for r in rows_out:
        print(r)
    print("CHECK lessons 계층파일=%d 위반=%d cap(seat %d · team %d 항목) · global ≤%dB"
          % (len(rows_out), bad, CAP["seat"], CAP["team"], GLOBAL_LIMIT))
    return 0 if bad == 0 else 1


def cmd_migrate(argv: list[str]) -> int:
    """옛 md(LESSONS) → jsonl 1회 변환. 원본은 .md.bak-<시각> 로 남긴다(삭제 0)."""
    root = ft_root()
    moved = 0
    for layer in ("seat", "team"):
        for md in sorted((root / "state" / "lessons" / layer).glob("*.md")):
            if ".archive" in md.name or md.name == "README.md":
                continue
            dst = md.with_suffix(".jsonl")
            lines = [l.strip() for l in md.read_text(encoding="utf-8", errors="replace").splitlines() if l.strip().startswith("- ")]
            rows = []
            for l in lines:
                kind = "mistake"
                if "[D]" in l:
                    kind = "directive"
                elif "[A]" in l:
                    kind = "achievement"
                elif "[E]" in l:
                    kind = "experiment"
                text = re.sub(r"^- \[[^\]]*\](\[[DMAE]\])?", "", l).strip()
                m = re.match(r"^- \[([0-9]{2}-[0-9]{2})\]", l)
                ts = ("%s-%s" % (dt.date.today().year, m.group(1))) if m else now()[:10]
                if text:
                    rows.append({"ts": ts, "kind": kind, "text": text[:TEXT_MAX], "pin": False})
            dst.with_suffix(dst.suffix + ".lock").touch()
            with Lock(dst):
                if corrupt_guard(dst):
                    return 1
                if dst.exists():
                    rows = load(dst) + rows
                rows, over, ttl, arc = enforce(dst, rows, CAP[layer])
                atomic_write(dst, rows)
            dst.with_suffix(dst.suffix + ".lock").touch()
            bak = md.with_name(md.name + ".bak-" + dt.datetime.now().strftime("%Y%m%d%H%M%S"))
            os.replace(md, bak)
            moved += 1
            print("MIGRATE %s/%s → %s (%d항목 · 원본 %s · 삭제 0)" % (layer, md.name, dst.name, len(rows), bak.name))
    print("MIGRATE 끝 — 변환 %d파일 (jsonl cap seat %d · team %d)" % (moved, CAP["seat"], CAP["team"]))
    return 0


def cmd_path(argv: list[str]) -> int:
    if not argv:
        die("usage: path <seat|team|global> [이름]")
    layer = argv[0]
    if layer not in ("seat", "team", "global"):
        die("REJECT 계층은 seat|team|global")
    print(path_of(layer, argv[1] if len(argv) > 1 else None))
    return 0


CMDS = {
    "init": cmd_init, "add": cmd_add, "list": cmd_list,
    "pin": lambda a: cmd_pin(a, True), "unpin": lambda a: cmd_pin(a, False),
    "evict": cmd_evict, "snapshot": cmd_snapshot, "check": cmd_check,
    "migrate": cmd_migrate, "path": cmd_path, "sync-teams": cmd_sync_teams,
    "search": cmd_search, "suggest": cmd_suggest, "resolve": cmd_resolve,
}


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("usage: ft-lessons.sh {init|add|list|pin|unpin|evict|snapshot|check|migrate|path|sync-teams|search|suggest|resolve} …")
        return 0 if len(sys.argv) > 1 else 2
    fn = CMDS.get(sys.argv[1])
    if not fn:
        die("REJECT 모르는 명령: %s" % sys.argv[1])
    return fn(sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
