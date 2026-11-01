#!/usr/bin/env python3
# pyright: basic
"""ft_card_assign_watch.py prepare|status|tick [--now <ISO|epoch>] [--json] | record <카드> init|seat <이름>|waiting <사유> | lint <카드> — 카드→좌석 배정 감시 (r1224 r2 · Issue #5342).
배정 원장 = <루트>/.fable-team/state/card-assign/<카드 stem>.json(도구만 씀 · lock 1개 ≤7초) {state seat|waiting|none · seat · reason · since(연속 미배정 시작 · 사유가 바뀌어도 유지) · updated · released_at · urgent}.
  같은 사유 재거절 = 파일 변경 0 · 배정(seat) = since 삭제 · 카드가 완성·아카이브 폴더로 가면 status 가 원장 삭제. 카드 머리 «- 배정:» 줄은 거울(seat 때만 쓰고 git add · 정본은 원장).
사유 = 정지·석·부하·면제대기·선행·lint·DA. 카드 루트 = r1212 표(state/directive-roots.tsv)를 strict 로(표 없음·유효 행 0 = 판정 불가 · 기본값 대체 0) · 카드는 ref «평가 시각 이하» 커밋에서 읽는다.
prepare = 루트마다 카드·발주문 생성 커밋 시각 캐시(예산 60초 · 틱 밖 1회) + 설치 stamp(installed_at) · status = 원장 + ref 대기·진행 폴더(예산 FT_CARD_ASSIGN_STATUS_SEC 3초 · prepare 없음 = 판정 불가).
셈: 원장 없음·none = 배정 없음(즉시) · waiting = max(since, released_at) 부터 4시간(원장 urgent 또는 카드 «- 긴급: 예» = 1시간) 넘으면 대기 초과 · 사유 정지·석·부하 + 원장 pause{kind,key} 카드는
  실제 도구에 부작용 0 으로 묻는다(hold = ft-spawn-hold.sh status --check <판정 N> rc0 유효 · acct = ft-acct-pause.sh status --check <P[/M]> rc3 유효) → 유효 = 정지 중(초과 0) · key·도구 없음·그 밖 rc = 판정 불가 Q(rc 에 안 셈)
  · 유효를 본 정지가 풀리면 원장 released_at = 그 시각. inbox/<역할>/NN-*.md = 상위 «N.» 항목(하위 «①…» 가 있으면 하위가 단위 · 상위는 묶음 머리)마다 «- 카드: <경로>»(빈 값·없는 경로·
  긴급 항목인데 카드 «- 긴급: 예» 없음 = 미연결) · 생성 커밋(없으면 mtime) 2시간 넘은 미연결 단위 = 카드 없는 발주.
머리 «배정 없는 카드 N · 대기 초과 M(사유별) · 정지 중 P · 카드 없는 발주 K · 판본 <stamp>» → 전용 card-assign/stamps.tsv 1줄(stamp N M K 입력 해시) · rc 0 = N·M·K 0 · 1 = 하나라도 · 3 = «배정 감시 판정 불가 · <사유>» 1줄.
tick = status + 그 팀 master·planner 에 [긴급](표식 = 받는이마다 정렬된 (stem·사유·종류) 해시 · 판본·경과 시간 제외 · 60분 억제 · QUEUED 뒤에만) · rc3 = planner 판정 불가 1통 · rc0 = 표식 지움.
r1291 — 팀 정지 표식(<루트>/.fable-team/state/<팀>-tick/PAUSED · team-pause·team-resume · ft_card_assign_pause.py)이 있는 팀의 카드 = «정지 중»(경보 0 · 사유 정지·석·부하보다 먼저) · 꼴 틀림 = «판정 불가 Q» + 팀당 1줄 ·
  표식이 사라진 뒤 처음 본 tick 에 그 팀 waiting released_at = 지금 · 24시간 넘은 정지 = planner 팀당 하루 1통 · 사유 «사람»(record … waiting 사람 verdict <N> 필수)은 4시간 뒤 첫 경보가 QUEUED 로 나간 뒤 «보류 중 H»(경보 0).
lint = ft-index-lint ⑭(대기·진행 카드 · «- 배정:» 꼴 · 줄 없음은 새 카드(생성 커밋 ≥ installed_at · 미커밋)만 REJECT · installed_at 없음 = 미설치 리포 검사 0).
env FT_ROOT · FT_CARD_ASSIGN_NOW · FT_CARD_ASSIGN_STATUS_SEC(3) · FT_CARD_ASSIGN_PREPARE_SEC(60) · FT_MBOX_SH · FT_CARD_ASSIGN_FROM · FT_DIRECTIVE_GIT_SEC(7)."""
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from contextlib import contextmanager
from fnmatch import fnmatch
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ft_directive_watch import Git, Undecided, hhmm, team_master, tsv, until  # noqa: E402
from ft_penalty import root  # noqa: E402
from ft_latest_write import write_latest  # noqa: E402
from ft_card_assign_pause import DAY_S, held_add, held_once, held_prune, jload, jsave, notice, team_pause, team_paused, team_resume  # noqa: E402
from ft_team_lib import TeamPathError, team_names  # noqa: E402

REASONS = ("정지", "석", "부하", "면제대기", "선행", "lint", "DA", "사람")
PAUSED = ("정지", "석", "부하")
VALUE = re.compile(r"좌석 \S+|없음|대기\((?:" + "|".join(REASONS) + r") · \d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?\)")
WAIT_S, URGENT_S, ORDER_S, MUTE_S = 4 * 3600, 3600, 2 * 3600, 3600
OPEN, CLOSED = ("대기", "진행"), ("완성", "아카이브")
QUIET = ("정지 중", "보류 중", "판정 불가")  # 경보·rc 에 안 세는 칸
ITEM, CIRCLED = re.compile(r"^\d+[.)]\s"), re.compile(r"^\s+[①-⑳]")
HERE = Path(__file__).resolve().parent


def adir(R: Path) -> Path:
    return R / ".fable-team/state/card-assign"


def iso(s: str) -> float | None:
    for f in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M"):
        try:
            return time.mktime(time.strptime(s, f))
        except ValueError:
            pass
    return None


def head(text: str) -> list[str]:
    lines = text.splitlines()
    return lines[:next((i for i, ln in enumerate(lines) if re.match(r"##\s", ln)), len(lines))]


def urgent_head(lines: list[str]) -> bool:
    return any(re.fullmatch(r"- 긴급:\s*예\s*", ln) for ln in lines)


@contextmanager
def locked(R: Path, wait: float = 7.0):
    d = adir(R)
    d.mkdir(parents=True, exist_ok=True)
    with open(d / "lock", "a+") as fh:
        end = time.monotonic() + max(0.0, min(7.0, wait))
        while True:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() > end:
                    raise Undecided(f"원장 잠금 {min(7.0, wait):.0f}초 넘김")
                time.sleep(0.05)
        try:
            yield d
        finally:
            fcntl.flock(fh, fcntl.LOCK_UN)


def load(d: Path, stem: str) -> dict:
    try:
        return json.loads((d / f"{stem}.json").read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except ValueError as e:
        raise Undecided(f"원장 손상 {stem}.json {e.__class__.__name__}")


def save(d: Path, stem: str, row: dict) -> None:
    tmp = d / f".{stem}.json.tmp-{os.getpid()}"
    tmp.write_text(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(d / f"{stem}.json")


def mirror(card: Path, val: str) -> None:
    """카드 머리 «- 배정:» 거울 줄 1개만 치환(없으면 머리 블록 끝에 삽입) · 바이트로 읽고 써서 다른 줄(공유 워크트리 미커밋 · CRLF)을 그대로 둔다 · git add 0 — 원장 잠금 안에서만 부른다."""
    lines = card.read_bytes().splitlines(keepends=True)
    end = next((i for i, ln in enumerate(lines) if re.match(rb"##\s", ln)), len(lines))
    hit = [i for i in range(end) if lines[i].startswith("- 배정:".encode())]
    eol = next((ln[len(ln.rstrip(b"\r\n")):] for ln in lines if ln.endswith(b"\n")), b"\n")
    new = f"- 배정: {val}".encode()
    for i in reversed(hit[1:]):
        del lines[i]
    if hit:
        old = lines[hit[0]]
        lines[hit[0]] = new + (old[len(old.rstrip(b"\r\n")):] or eol)
    else:
        at = end
        while at > 0 and not lines[at - 1].strip():
            at -= 1
        if at and not lines[at - 1].endswith(b"\n"):
            lines[at - 1] += eol
        lines.insert(at, new + eol)
    tmp = card.with_name(f".{card.name}.tmp-{os.getpid()}")
    tmp.write_bytes(b"".join(lines))
    tmp.replace(card)


class Rejected(Exception):
    """record 진입 거절(r1306) — main 이 1줄 인쇄 + rc1(조용한 통과 0)."""


def resolve(R: Path, arg: str) -> tuple[Path, str | None]:
    """record 인자 → (디스크 경로, tip 본문|None). 이름(stem)이면 status 와 같은 곳(tip 객체의 대기·진행·완성 · 같은 깊이)에서 찾는다 — 0 = REJECT rc1 · 2+ = REJECT rc1(원장 키가 이름이라 못 가른다) · tip 에만 있으면 원장만 쓰고 거울 0 · 경로 인자는 디스크만 본다(r1306).
    카드 루트 표가 없으면 이름 풀이·중복 검사가 불가 = Undecided(rc3) — 단 경로 인자이고 그 파일이 디스크에 있으면 카드는 아는 것이므로 그대로 쓴다(표 없음이면 status 자체가 rc3)."""
    stem, ispath = (m[:-3] if (m := arg.rsplit("/", 1)[-1]).endswith(".md") else m), "/" in arg or arg.endswith(".md")
    if ispath and Path(arg).is_file() and not (R / ".fable-team/state/directive-roots.tsv").is_file():
        return Path(arg), None
    git, hits = Git(float(os.environ.get("FT_DIRECTIVE_GIT_SEC") or 7)), []
    for r in strict_roots(R):
        repo, base, depth = repo_of(R, r), r[3].split("*")[0].rstrip("/"), len(r[3].split("/"))
        tip = git(repo, "rev-list", "-1", r[2]).strip()
        paths = git(repo, "ls-tree", "-r", "--name-only", tip, "--", base).splitlines() if tip else []
        hits += [(repo, tip, p) for p in paths if p.endswith(".md") and fnmatch(p, r[3] + "/*") and len(p.split("/")) == depth + 2 and p.split("/")[depth] in ("대기", "진행", "완성") and p.rsplit("/", 1)[-1][:-3] == stem and (repo, p) not in {(h[0], h[2]) for h in hits}]
    if len(hits) > 1:
        raise Rejected(f"REJECT 배정 원장 — 이름 중복 {stem} ({', '.join(h[2] for h in hits)}) · 원장 키가 이름이라 기록 불가 · 카드 이름을 바꿔라")
    path = Path(arg) if ispath else Path(hits[0][0], hits[0][2]) if hits else Path(arg)
    if path.is_file():
        return path, None
    if ispath or not hits:
        raise Rejected(f"REJECT 배정 원장 — 카드 없음 {arg if ispath else stem + '(tip·디스크)'}")
    print(f"NOTE 거울 줄 0 — 디스크에 카드 없음(tip 에만 · {hits[0][0]}:{hits[0][2]})")
    return path, git(hits[0][0], "show", f"{hits[0][1]}:{hits[0][2]}")


def record(card: str | Path, kind: str, arg: str, now: float, pause: dict | None = None, verdict: str | None = None) -> int:
    """spawn 종료 분기·성공이 부르는 공용 1함수 — init(원장 없을 때만 none) · waiting <사유> [hold <판정 N>|acct <P[/M]>](같은 사유·같은 정지 = 변경 0 · since = 이른 쪽 · 정지 표식은 사유가 바뀌어도 유지)
    · seat <이름>(since 삭제). 거울 줄(없음 · 대기(사유 · since) · 좌석 이름)은 셋 다 같은 잠금 안에서 쓴다. 카드 = 경로 또는 이름(stem — status 와 같은 곳에서 풀고, 못 찾거나 이름이 겹치면 REJECT rc1 · tip 에만 있으면 원장만 + NOTE · r1306)."""
    stem = n[:-3] if (n := str(card).rsplit("/", 1)[-1]).endswith(".md") else n
    if kind == "waiting" and arg not in REASONS or kind == "seat" and (not arg or re.search(r"\s", arg)) or kind not in ("init", "waiting", "seat"):
        print(f"REJECT 배정 원장 값 꼴 — init | waiting <{'|'.join(REASONS)}> | seat <이름> (받은 값: {kind} {arg})")
        return 2
    if kind == "waiting" and arg == "사람" and not (verdict or "").isdigit():
        print("REJECT 사람 보류는 판정 번호 필수 — record <카드> waiting 사람 verdict <N>")
        return 2
    card, body = resolve(root(), str(card))
    urgent = urgent_head(head(body if body is not None else card.read_text(encoding="utf-8")))
    with locked(root()) as d:
        old = load(d, stem)
        if kind == "init" and old or kind == "waiting" and old.get("state") == "waiting" and old.get("reason") == arg and (not pause or old.get("pause", {}).get("key") == pause["key"]) and old.get("verdict") == verdict:
            return 0
        if kind == "seat":
            new = {"state": "seat", "seat": arg, "updated": now, "urgent": urgent}
        else:
            since = min(float(old["since"]), now) if old.get("state") in ("none", "waiting") and old.get("since") else now  # 연속 미배정 시작 = 이른 쪽
            new = {"state": "none" if kind == "init" else "waiting", "since": since, "updated": now, "urgent": urgent or bool(old.get("urgent"))}
            if kind == "waiting":
                new["reason"] = arg
            for k in ("released_at", "pause"):
                if old.get(k) and old.get("state") == "waiting":
                    new[k] = old[k]
            if pause:
                new["pause"] = pause
            if verdict and arg == "사람":
                new["verdict"] = verdict
        save(d, stem, new)
        if body is None:  # tip 에만 있는 카드 = 디스크 쓰기 0(거울 줄을 만들지 않는다)
            mirror(card, f"좌석 {arg}" if kind == "seat" else "없음" if kind == "init" else f"대기({arg} · {time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime(new['since']))})")
    if kind != "init":  # init(진입 식별)은 조용히 — spawn 출력 첫 줄을 바꾸지 않는다
        print(f"배정 원장 {stem} → {new['state']} {arg}".rstrip())
    return 0


def installed_at(card: Path) -> float | None:
    r = os.environ.get("FT_ROOT")
    if not r:
        p = subprocess.run(["git", "-C", str(card.parent), "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, timeout=7)
        r = str(Path(p.stdout.strip()).parent) if p.returncode == 0 else ""
    f = Path(r) / ".fable-team/state/card-assign/installed_at" if r else None
    try:
        return float(f.read_text().strip()) if f else None
    except (OSError, ValueError):
        return None


def lint(card: Path) -> int:
    """ft-index-lint ⑭ — 출력 = REJECT 사유 1줄 rc1 · 빈 출력 rc0."""
    card = card.resolve()  # git -C <폴더> 의 pathspec 은 그 폴더 기준 — 절대경로로 묻는다
    if card.parent.name not in OPEN:
        return 0
    vals = [ln[len("- 배정:"):].strip() for ln in head(card.read_text(encoding="utf-8")) if ln.startswith("- 배정:")]
    if vals:
        if VALUE.fullmatch(vals[0]):
            return 0
        print(f"「- 배정:」 값 꼴 — 좌석 <이름> | 대기(<{'|'.join(REASONS)}> · <YYYY-MM-DDTHH:MM>) | 없음: {vals[0][:40]}")
        return 1
    inst = installed_at(card)
    if inst is None:
        return 0  # 이 리포엔 r1224 미설치(prepare 가 installed_at 을 쓴다) — 새 카드 판별 기준이 없다
    spec = str(card.parent.parent / "*" / card.name)
    p = subprocess.run(["git", "-C", str(card.parent), "log", "--no-renames", "--diff-filter=A", "--format=%ct", "--", spec], capture_output=True, text=True, timeout=7)
    if p.returncode != 0:
        print(f"배정 줄 검사 판정 불가 — git log rc={p.returncode} {p.stderr.strip()[:80]}")
        return 1
    made = [float(x) for x in p.stdout.split()]
    if made and min(made) < inst:
        return 0  # 옛 카드 — spawn 진입 때 원장 none 행이 생긴다
    print("머리 「- 배정: 좌석 <이름> | 대기(<사유> · <시각>) | 없음」 줄 없음 (새 카드 의무 · r1224)")
    return 1


def strict_roots(R: Path) -> list[list[str]]:
    f = R / ".fable-team/state/directive-roots.tsv"
    rows = [r[:4] for r in tsv(f) if len(r) >= 4 and all(x.strip() for x in r[:4])]
    if not rows:
        raise Undecided(f"카드 루트 표 없음·유효 행 0({f})")
    return rows


def repo_of(R: Path, r: list[str]) -> str:
    return r[1] if os.path.isabs(r[1]) else str((R / r[1]).resolve())


def cache_of(R: Path, r: list[str]) -> Path:
    return adir(R) / ("created-" + hashlib.sha1("\t".join(r[1:4]).encode()).hexdigest()[:12] + ".tsv")


def created_log(git: Git, repo: str, span: str, r: list[str], now: float, long: bool) -> dict[str, float]:
    """stem → 처음 생긴 커밋 시각(폴더 이동은 생성 아님 · --no-renames 의 A 중 가장 이른 것)."""
    out, ct, got = git(repo, "log", until(now), "--no-renames", "--diff-filter=A", "--format=@%ct", "--name-only", span, "--", r[3].split("*")[0].rstrip("/"), long=long), 0.0, {}
    for ln in out.splitlines():
        if ln.startswith("@"):
            ct = float(ln[1:])
        elif ln.endswith(".md") and fnmatch(ln, r[3] + "/*"):
            s = ln.rsplit("/", 1)[-1][:-3]
            got[s] = min(got.get(s, ct), ct)
    return got


def prepare(R: Path, now: float) -> list[str]:
    git, out = Git(float(os.environ.get("FT_CARD_ASSIGN_PREPARE_SEC") or 60)), []
    d = adir(R)
    for r in strict_roots(R):
        repo = repo_of(R, r)
        tip = git(repo, "rev-list", "-1", until(now), r[2]).strip()
        made = created_log(git, repo, tip, r, now, True) if tip else {}
        d.mkdir(parents=True, exist_ok=True)
        cache_of(R, r).write_text(f"@sha\t{tip}\n" + "".join(f"{k}\t{v:.0f}\n" for k, v in sorted(made.items())), encoding="utf-8")
        out.append(f"준비 {r[0]} {r[2]} · 카드·발주문 {len(made)} · tip {tip[:10] or '-'}")
    if not (d / "installed_at").is_file():
        (d / "installed_at").write_text(f"{now:.0f}\n", encoding="utf-8")
    return out + [f"배정 감시 준비 끝 · installed_at {hhmm(float((d / 'installed_at').read_text().strip()))}"]


def pause_check(R: Path, now: float, kind: str, key: str, left: float = 7.0) -> str:
    """원장 pause 표식 → 실제 도구 계약(부작용 0): hold = ft-spawn-hold.sh status --check <N> rc0 유효 · rc3 정지 없음 / acct = ft-acct-pause.sh status --check <P[/M]> rc3 유효 · rc0 없음
    · key 없음·도구 없음·그 밖 rc = 판정 불가. 반환 on|off|q."""
    tool = {"hold": "ft-spawn-hold.sh", "acct": "ft-acct-pause.sh"}.get(kind)
    if not tool or not key or not (HERE / tool).is_file():
        return "q"
    if left <= 0:
        raise Undecided("status 마감 넘김(정지 확인 전)")
    env = dict(os.environ, FT_RES_ROOT=str(R), FT_ROOT=str(R), FT_HOLD_NOW=str(int(now)))
    try:
        p = subprocess.run(["bash", str(HERE / tool), "status", "--check", key], capture_output=True, text=True, timeout=min(7.0, left), env=env)
    except subprocess.TimeoutExpired:
        raise Undecided(f"status 마감 넘김({tool} status --check)")
    on, off = (0, 3) if kind == "hold" else (3, 0)
    return "on" if p.returncode == on else "off" if p.returncode == off else "q"


class Status:
    def __init__(self, R: Path, now: float, virtual: bool) -> None:
        self.R, self.now, self.virtual = R, now, virtual
        self.roots = strict_roots(R)
        self.git = Git(float(os.environ.get("FT_CARD_ASSIGN_STATUS_SEC") or 3))
        self.d = adir(R)
        self.asked: dict[tuple, str] = {}
        self.tp: dict[str, tuple] = {}  # 팀 → team_paused 결과(팀마다 1회)
        self.notes: list[str] = []  # 정지 표식 판정 불가 팀마다 1줄(r1291)
        self.long: list[tuple[str, str]] = []  # 24시간 넘은 정지(팀 · 판정 N)
        self.team_counts = (0, 0)
        self.seen, self.held = jload(self.d / "paused-seen.json"), jload(self.d / "held-once.json")

    def team_pause(self, team: str) -> tuple:
        if team not in self.tp:
            self.tp[team] = team_paused(self.R, team)
            if self.tp[team][0] == "q":
                self.notes.append(f"정지 표식 판정 불가 {team} {self.tp[team][1]}")
            elif self.tp[team][0] == "on" and self.now - self.tp[team][2] > DAY_S:
                self.long.append((team, self.tp[team][3]))
        return self.tp[team]

    def released(self, stem: str, L: dict, team: str) -> None:
        """정지를 본 팀의 표식이 사라진 뒤 처음 본 tick — 그 팀 waiting 원장 released_at = 지금(4시간을 새로 센다 · 운영만)."""
        if self.virtual or team not in self.seen:
            return
        with locked(self.R, self.git.end - time.monotonic()) as d:
            j = load(d, stem)
            j["released_at"] = self.now
            save(d, stem, j)
            L.update(j)

    def created(self, r: list[str], repo: str, tip: str) -> dict[str, float]:
        c = cache_of(self.R, r)
        rows = tsv(c)
        if not rows:
            raise Undecided(f"prepare 없음 — ft-card-assign-watch.sh prepare 먼저({c.name})")
        last = next((x[1] for x in rows if x[0] == "@sha"), "")
        made = {x[0]: float(x[1]) for x in rows if x[0] != "@sha"}
        if tip and last != tip:
            for k, v in created_log(self.git, repo, f"{last}..{tip}" if last else tip, r, self.now, False).items():
                made[k] = min(made.get(k, v), v)
            if not self.virtual:
                c.write_text(f"@sha\t{tip}\n" + "".join(f"{k}\t{v:.0f}\n" for k, v in sorted(made.items())), encoding="utf-8")
        return made

    def pause(self, stem: str, L: dict) -> str:
        """그 카드의 정지 판정 on|off|q(같은 도구·key 는 한 번만 묻는다) · 유효를 본 정지가 풀리면 released_at = 지금 + 표식 지움(전이 시각 보존 · 운영만)."""
        pz = L.get("pause") or {}
        k = (pz.get("kind", ""), str(pz.get("key") or ""))
        if k not in self.asked:
            self.asked[k] = pause_check(self.R, self.now, *k, left=self.git.end - time.monotonic())
        v = self.asked[k]
        if not self.virtual and v != "q" and (v == "on") != bool(pz.get("seen")):
            with locked(self.R, self.git.end - time.monotonic()) as d:
                j = load(d, stem)
                if v == "on":
                    j["pause"] = dict(pz, seen=True)
                else:
                    j.pop("pause", None)
                    j["released_at"] = self.now
                save(d, stem, j)
                L.update(j)
        return v

    def rows(self) -> tuple[list[dict], str, int]:
        try:
            active_teams = set(team_names(self.R))
        except TeamPathError as e:
            raise Undecided(f"팀 명단 판정 불가 {e}") from None
        ledger = {p.stem: load(self.d, p.stem) for p in self.d.glob("*.json")} if self.d.is_dir() else {}
        rows, tips, opened, closed, allpaths, urgent_paths, inbox = [], [], set(), set(), set(), set(), []
        outside_teams, ref_teams = set(), set()
        for r in self.roots:
            repo, base = repo_of(self.R, r), r[3].split("*")[0].rstrip("/")
            tip = self.git(repo, "rev-list", "-1", until(self.now), r[2]).strip()
            tips.append(tip)
            if not tip:
                continue
            made = self.created(r, repo, tip)
            files = [p for p in self.git(repo, "ls-tree", "-r", "--name-only", tip, "--", base).splitlines() if p.endswith(".md") and fnmatch(p, r[3] + "/*")]
            for ln in self.git(repo, "grep", "-I", "-n", "-e", "^- 긴급:", "-e", "^## ", tip, "--", f":(glob){r[3].rstrip('/')}/**/*.md", ok=(0, 1)).splitlines():  # 카드 폴더의 .md 만(r1251 · 증거 포함 팀 폴더 전체 grep = 부하에서 «판정 불가»)
                path, _, rest = ln[len(tip) + 1:].partition(":")
                text = rest.partition(":")[2]
                if text.startswith("## "):
                    urgent_paths.add("#" + path)
                elif "#" + path not in urgent_paths and re.fullmatch(r"- 긴급:\s*예\s*", text):
                    urgent_paths.add(path)
            depth, star = len(r[3].split("/")), r[3].split("/").index("*") if "*" in r[3] else -1
            for path in files:
                parts, stem = path.split("/"), path.rsplit("/", 1)[-1][:-3]
                team = parts[star] if r[0] == "*" else r[0]
                if team not in active_teams:
                    outside_teams.add(team)
                    continue
                ref_teams.add(team)
                if len(parts) == depth + 2 and parts[depth] in ("대기", "진행", "완성"):
                    allpaths.add(path)
                if len(parts) == depth + 2 and parts[depth] in CLOSED:
                    closed.add(stem)
                elif len(parts) == depth + 2 and parts[depth] in OPEN:
                    opened.add(stem)
                    rows.extend(self.judge(team, stem, ledger.get(stem), made.get(stem, 0.0), path in urgent_paths))
                elif len(parts) == depth + 3 and parts[depth] == "inbox" and re.match(r"\d\d-", parts[-1]):
                    inbox.append((repo, tip, team, path, self.born_of(repo, path, made.get(stem))))
        old = [x for x in inbox if self.now - x[4] > ORDER_S]  # 나이로 먼저 거른다 · 본문은 루트마다 1회(r1269)
        text = {k: v for rp, tp in dict.fromkeys((x[0], x[1]) for x in old) for k, v in self.bodies(rp, tp, [x[3] for x in old if (x[0], x[1]) == (rp, tp)]).items()}
        for repo, tip, team, path, born in inbox:
            rows.extend(self.orders(team, path, born, allpaths, urgent_paths, text.get((repo, tip, path))))
        if not self.virtual:
            for stem in set(ledger) & closed - opened:
                (self.d / f"{stem}.json").unlink(missing_ok=True)
            seen = {t: 1 for t in set(self.seen) - {t for t, v in self.tp.items() if v[0] == "none"} | {t for t, v in self.tp.items() if v[0] == "on"}}  # 정지를 본 팀 · 표식이 사라진 팀은 지움(released_at 은 judge 가 이미 씀)
            held = held_prune(self.held, ledger, closed - opened)
            for f, j, old in ((self.d / "paused-seen.json", seen, self.seen), (self.d / "held-once.json", held, self.held)):
                if j != old:
                    jsave(f, j)
        raw = "\n".join(sorted(ledger)) + "".join(tips)
        h = hashlib.sha1(raw.encode()).hexdigest()
        self.team_counts = (len(outside_teams), len(active_teams - ref_teams))
        return sorted(rows, key=lambda x: x["since"]), f"{int(self.now)}-{h[:8]}", int(h[:8], 16)

    def judge(self, team: str, stem: str, L: dict | None, born: float, urgent: bool) -> list[dict]:
        L = L or {}
        row: dict = dict(team=team, stem=stem, urgent=urgent or bool(L.get("urgent")), reason="")
        if L.get("state") == "seat":
            return []
        waiting = L.get("state") == "waiting"
        if waiting:
            row.update(reason=L.get("reason", ""), label=f"대기({L.get('reason')})", since=float(L.get("since") or 0))
        else:
            row.update(label="없음" if L else "원장 없음", since=float(L.get("since") or born))
        tp = self.team_pause(team)  # 팀 정지 표식이 사유 정지·석·부하보다 먼저(r1291 · 긴급 카드도 같다)
        if tp[0] != "none":
            return [dict(row, kind="정지 중" if tp[0] == "on" else "판정 불가")]
        if not waiting:
            return [dict(row, kind="없음")]
        self.released(stem, L, team)
        v = self.pause(stem, L) if row["reason"] in PAUSED and L.get("pause") else "off"
        if v != "off":
            return [dict(row, kind="정지 중" if v == "on" else "판정 불가")]
        start = max(row["since"], float(L.get("released_at") or 0))
        if self.now - start <= (URGENT_S if row["urgent"] else WAIT_S):
            return []
        return [dict(row, kind="보류 중" if row["reason"] == "사람" and held_once(self.held, stem, "사람", row["since"]) else "초과")]

    def born_of(self, repo: str, path: str, born: float | None) -> float:
        """발주문 나이 = 생성 커밋 시각(없으면 mtime · 파일도 없으면 지금)."""
        return born if born is not None else Path(repo, path).stat().st_mtime if Path(repo, path).is_file() else self.now

    def bodies(self, repo: str, tip: str, paths: list[str]) -> dict[tuple, str]:
        """발주문 본문을 루트마다 «git cat-file --batch» 1회로(r1269 · 경로마다 git show 프로세스 N개 = 부하에서 3초 예산 넘김) · missing 하나라도 = 판정 불가 · 같은 Git 예산."""
        if not paths:
            return {}
        try:
            p = subprocess.run(["git", "-C", repo, "cat-file", "--batch"], input="".join(f"{tip}:{x}\n" for x in paths).encode(), capture_output=True, timeout=max(0.001, min(self.git.per, self.git.end - time.monotonic())))
        except subprocess.TimeoutExpired:
            raise Undecided(f"git 상한 넘김(cat-file {repo})")
        out, i, got = p.stdout, 0, {}
        for x in paths:
            j = out.find(b"\n", i)
            h = out[i:j].split(b" ") if p.returncode == 0 and j >= 0 else []
            if len(h) != 3 or h[1] != b"blob":
                raise Undecided(f"git cat-file rc={p.returncode} {repo} {x} {(h and h[-1] or p.stderr).decode(errors='replace').strip()[:80]}")
            got[(repo, tip, x)], i = out[j + 1:j + 1 + int(h[2])].decode(errors="replace"), j + 2 + int(h[2])
        return got

    def orders(self, team: str, path: str, born: float, allpaths: set, urgent_paths: set, body: str | None) -> list[dict]:
        """발주문 번호 항목마다 «- 카드: <경로>» — 빈 값·없는 경로·긴급 항목인데 카드 «- 긴급: 예» 없음 = 미연결 · 나이 = 생성 커밋(없으면 mtime) · 본문 = bodies() 가 미리 읽은 것(2시간 안 = None)."""
        if body is None or self.now - born <= ORDER_S:
            return []
        tops: list[list[list[str]]] = []  # 상위 항목마다 [머리 본문, 하위1, 하위2 …]
        for ln in body.splitlines():
            if ITEM.match(ln):
                tops.append([[ln]])
            elif tops and CIRCLED.match(ln):
                tops[-1].append([ln])
            elif tops:
                tops[-1][-1].append(ln)
        items = [u for t in tops for u in (t[1:] if len(t) > 1 else t[:1])]  # 하위가 있으면 하위가 단위 · 상위는 묶음 머리
        out = []
        for n, it in enumerate(items or [[path]], 1):
            ptr = next((m.group(1).strip() for ln in it if (m := re.match(r"^\s*- 카드:(.*)$", ln))), "")
            hot = any(w in it[0] for w in ("긴급", "크리티컬"))
            why = "포인터 없음" if not ptr else "없는 경로" if ptr not in allpaths else "카드 긴급 줄 없음" if hot and ptr not in urgent_paths else ""
            if why:
                out.append(dict(team=team, stem=f"{path.rsplit('/', 1)[-1][:-3]}#{n}", kind="발주", label=why, reason=why, since=born, urgent=hot))
        return out


def render(rows: list[dict], stamp: str, team_counts: tuple[int, int] = (0, 0)) -> list[str]:
    n = {k: [x for x in rows if x["kind"] == k] for k in ("없음", "초과", "정지 중", "보류 중", "판정 불가", "발주")}
    by = [f"{r} {sum(1 for x in n['초과'] if x['reason'] == r)}" for r in dict.fromkeys(x["reason"] for x in n["초과"])]  # 사유는 가장 오래된 since 순
    when = lambda t: hhmm(t) if t else "-"  # noqa: E731
    by_s = "(" + " · ".join(by) + ")" if by else ""
    held = f" · 보류 중 {len(n['보류 중'])}"
    q = f" · 판정 불가 Q {len(n['판정 불가'])}"
    out = [f"배정 없는 카드 {len(n['없음'])} · 대기 초과 {len(n['초과'])}{by_s} · 정지 중 {len(n['정지 중'])}{held if n['보류 중'] else ''}{q if n['판정 불가'] else ''} · 카드 없는 발주 {len(n['발주'])} · 판본 {stamp}"]
    outside, ref_missing = team_counts
    out[0] += f" · 명단 밖 팀 {outside} · ref 미반영 팀 {ref_missing}"
    for x in rows:  # rows() 가 since 순으로 정렬해 준다 — tick 이 rows·lines[1:] 를 짝짓는다
        out.append(f"{x['kind']} {x['team']} {x['stem']} · {x['label']} · since {when(x['since'])}{' · 긴급' if x['urgent'] else ''}")
    return out


def _empty_undecided(day: str) -> dict:
    return {"day": day, "n": 0, "first": None, "last": None, "reasons": {}}


def _undecided_text(bucket: dict) -> str:
    first, last = (time.strftime("%H:%M", time.localtime(bucket[k])) for k in ("first", "last"))
    reasons = sorted(bucket["reasons"].items(), key=lambda x: (-x[1], x[0]))[:3]
    top = " · ".join(f"{why} {n}" for why, n in reasons) or "없음"
    return f"[정리] 배정 감시 판정 불가 묶음 {bucket['day']} {bucket['n']}회 · 첫 {first} · 마지막 {last} · 사유 상위 3: {top} (ft-card-assign-watch · 숫자로 읽지 말 것)"


def _send_undecided(bucket: dict, planner: str | None, mbox: str, me: str) -> tuple[bool, str]:
    if not planner:
        return False, "tick 정리 발신 판정 불가 · planner 명부 없음"
    try:
        p = subprocess.run(["bash", mbox, "send", planner, me, _undecided_text(bucket)], capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.SubprocessError) as e:
        return False, f"tick 정리 발신 판정 불가 · {e.__class__.__name__}"
    if "QUEUED" in p.stdout + p.stderr:
        return True, f"tick [정리] 1통 → {planner}"
    return False, f"tick 정리 발신 판정 불가 · rc={p.returncode}"


def _record_undecided(R: Path, now: float, alarm: list | None, why: str, marks: dict,
                      planner: str | None, mbox: str, me: str) -> list[str]:
    day, log = time.strftime("%Y-%m-%d", time.localtime(now)), []
    bucket = marks.get("undecided_day")
    pending = list(marks.get("undecided_pending", []))
    if bucket and bucket.get("day") != day:
        if bucket.get("n", 0):
            pending.append(bucket)
        bucket = _empty_undecided(day)
    if alarm is None:
        bucket = bucket or _empty_undecided(day)
        reason = " ".join(why.split())
        d = adir(R)
        d.mkdir(parents=True, exist_ok=True)
        with open(d / "undecided.log", "a", encoding="utf-8") as f:
            f.write(f"{int(now)} {reason}\n")
        bucket["n"] += 1
        bucket["first"] = bucket["first"] or now
        bucket["last"] = now
        reasons = bucket.setdefault("reasons", {})
        reasons[reason] = reasons.get(reason, 0) + 1
    if bucket:
        marks["undecided_day"] = bucket
    remaining = []
    for prior in pending:
        sent, result = _send_undecided(prior, planner, mbox, me)
        log.append(result)
        if not sent:
            remaining.append(prior)
    if remaining:
        marks["undecided_pending"] = remaining
    else:
        marks.pop("undecided_pending", None)
    return log


def _save_alarm(mf: Path, marks: dict) -> None:
    if marks:
        mf.parent.mkdir(parents=True, exist_ok=True)
        mf.write_text(json.dumps(marks, ensure_ascii=False), encoding="utf-8")
    else:
        mf.unlink(missing_ok=True)


def tick(R: Path, now: float, rows: list[dict] | None, why: str, lines: list[str]) -> list[str]:
    mf = adir(R) / "alarm.state"
    alarm = None if rows is None else [(x, ln) for x, ln in zip(rows, lines[1:]) if x["kind"] not in QUIET]
    marks = json.loads(mf.read_text(encoding="utf-8")) if mf.is_file() else {}
    planner = team_master(R, "planner")
    mbox = os.environ.get("FT_MBOX_SH") or str(R / ".fable-team/comm/mbox.sh")
    me = os.environ.get("FT_CARD_ASSIGN_FROM", "ft-card-assign-watch")
    log = _record_undecided(R, now, alarm, why, marks, planner, mbox, me)
    if alarm is None:
        log.append("tick 판정 불가 기록 · rc3 유지")
        _save_alarm(mf, marks)
        return log
    if alarm == []:
        marks = {k: v for k, v in marks.items() if k.startswith("undecided_")}
        _save_alarm(mf, marks)
        return log + ["tick 경보 0 · 표식 지움"]
    groups = {}
    for x, ln in alarm:
        for to in dict.fromkeys([planner, team_master(R, x["team"])]):
            g = groups.setdefault(to, (to, [], [], []))
            g[1].append(ln)
            g[2].append((x["stem"], x["reason"], x["kind"]))
            g[3].append(x)
    old = min((x for x, _ in alarm), key=lambda x: x["since"], default=None)
    oldest = f" · 가장 오래된 {old['stem']} · {hhmm(old['since']) if old['since'] else '-'} · {old['label']}" if old else ""
    for to, (key, body, keys, grows) in groups.items():
        if not to:
            log.append("tick 받는이 없음(명부 _master 못 읽음) · 0통")
            continue
        h, m = hashlib.sha1(repr(sorted(keys)).encode()).hexdigest()[:12], marks.get(key) or {}
        if m.get("h") == h and now - float(m.get("t", 0)) < MUTE_S:
            continue
        text = "\n".join([f"[긴급] 배정 없는 카드 — {lines[0]}{oldest} · 원장에 좌석·대기 사유를 남기거나 spawn (ft-card-assign-watch)",
                           *body[:3], *([f"외 {len(body) - 3}건"] if len(body) > 3 else [])])
        p = subprocess.run(["bash", mbox, "send", to, me, text], capture_output=True, text=True, timeout=7)
        if "QUEUED" in p.stdout + p.stderr:
            marks[key] = {"h": h, "t": now}
            log.append(f"tick 1통 → {to}")
            for x in grows:  # 사람 보류 카드 = 첫 경보가 QUEUED 로 나간 뒤에만 «보류 중» 으로(r1291)
                if x["reason"] == "사람":
                    held_add(R, x["stem"], "사람", x["since"])
        else:
            log.append(f"tick 발신 실패 → {to} rc={p.returncode} · 다음 틱 다시")
    _save_alarm(mf, marks)
    return log


def pause_notice(R: Path, now: float, long: list[tuple[str, str]]) -> list[str]:
    """24시간 넘은 정지 팀 → planner 에 팀당 하루 1통(r1291 · 발신 = 기존 mbox send timeout 7)."""
    planner = team_master(R, "planner")
    if not long or not planner:
        return ["정지 24시간 받는이 없음(명부 _master 못 읽음) · 0통"] if long else []
    mbox, me = os.environ.get("FT_MBOX_SH") or str(R / ".fable-team/comm/mbox.sh"), os.environ.get("FT_CARD_ASSIGN_FROM", "ft-card-assign-watch")

    def send(text: str) -> bool:
        try:
            p = subprocess.run(["bash", mbox, "send", planner, me, text], capture_output=True, text=True, timeout=7)
        except subprocess.TimeoutExpired:
            return False
        return "QUEUED" in p.stdout + p.stderr
    return notice(R, now, long, send)


def main(argv: list[str]) -> int:
    real, v = time.time(), argv[argv.index("--now") + 1] if "--now" in argv[:-1] else os.environ.get("FT_CARD_ASSIGN_NOW")
    now = real if not v else float(v) if re.fullmatch(r"\d+(\.\d+)?", v) else iso(v[:19])
    cmd = argv[0] if argv else ""
    write = "--write-latest" in argv
    if write and cmd not in ("status", "tick"):
        print("사용: ft-card-assign-watch.sh status|tick [--write-latest]", file=sys.stderr)
        print("latest 안 씀(rc 2)", file=sys.stderr)
        return 2
    if cmd == "lint" and len(argv) == 2:
        return lint(Path(argv[1]))
    if cmd == "record" and len(argv) >= 3:
        try:
            pz = {"kind": argv[4], "key": argv[5] if len(argv) > 5 else ""} if len(argv) > 4 and argv[4] in ("hold", "acct") else None
            vd = argv[5] if len(argv) > 5 and argv[4] == "verdict" else None
            return record(argv[1], argv[2], argv[3] if len(argv) > 3 else "", now or real, pz, vd)
        except Rejected as e:
            print(e)
            return 1
        except Undecided as e:
            print(f"배정 원장 판정 불가 · {e}")
            return 3
    if cmd in ("team-pause", "team-resume") and len(argv) >= 2:
        val = lambda k: argv[argv.index(k) + 1] if k in argv[2:-1] else ""  # noqa: E731
        return team_pause(root(), argv[1], val("--verdict"), val("--reason"), now or real) if cmd == "team-pause" else team_resume(root(), argv[1])
    if cmd not in ("prepare", "status", "tick"):
        print("사용: ft-card-assign-watch.sh prepare|status|tick [--now <YYYY-MM-DDTHH:MM:SS|epoch>] [--json] [--write-latest] | record <카드> init|seat <이름>|waiting <사유> [hold <판정 N>|acct <P[/M]>|verdict <N>(사람 보류)] | team-pause <팀> --verdict <N> --reason <10자+> | team-resume <팀> | lint <카드>")
        return 2
    if now is None:
        print(f"배정 감시 판정 불가 · --now 꼴 아님({v})")
        if write:
            print("latest 안 씀(rc 3)", file=sys.stderr)
        return 3
    virtual, R = now < real - 1, root()
    if cmd != "status" and virtual:
        print(f"배정 감시 판정 불가 · {cmd} 은 가상 시각을 받지 않는다")
        if write:
            print("latest 안 씀(rc 3)", file=sys.stderr)
        return 3
    try:
        if cmd == "prepare":
            print("\n".join(prepare(R, now)))
            return 0
        st = Status(R, now, virtual)
        rows, stamp, _ = st.rows()
    except (Undecided, OSError, subprocess.SubprocessError) as e:
        why = " ".join((str(e) if isinstance(e, Undecided) else f"{e.__class__.__name__} {e}").split())  # 1줄(하드 룰 20)
        print(f"배정 감시 판정 불가 · {why}")
        if cmd == "tick":
            print("\n".join(tick(R, now, None, why, [])))
        if write:
            print("latest 안 씀(rc 3)", file=sys.stderr)
        return 3
    lines = render(rows, stamp, st.team_counts) + st.notes  # notes = 행 뒤 꼬리(tick 은 zip 으로 행만 짝짓는다)
    output = json.dumps(rows, ensure_ascii=False) if "--json" in argv else "\n".join(lines)
    print(output)
    hot = [x for x in rows if x["kind"] not in QUIET]  # 정지 중·보류 중·Q 는 rc 에 안 셈(머리에만)
    if not virtual:
        c = {k: sum(1 for x in rows if x["kind"] == k) for k in ("없음", "초과", "발주")}
        with open(adir(R) / "stamps.tsv", "a", encoding="utf-8") as fh:
            fh.write(f"{stamp}\t{c['없음']}\t{c['초과']}\t{c['발주']}\t{stamp.split('-')[1]}\n")
    if cmd == "tick":
        print("\n".join(tick(R, now, rows, "", lines) + pause_notice(R, now, st.long)))
    rc = 1 if hot else 0
    if write:
        write_latest(R, "card-assign", "ft-card-assign-watch.sh", output.splitlines()[0] if output else "", rows, int(now), stamp)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
