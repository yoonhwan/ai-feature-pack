#!/usr/bin/env python3
"""ft_ledger_fill — 원장 자동 채움(r851 · planner 계획 PLAN-news-magazine-normalize-20261024 §3 A1·A2·C1).

  ft-ledger-fill fill  [--repo R] [--path P] [--ref origin/main] [--no-fetch] [--push]   표 세 개 다시 쓰기 + 닫힌 줄 내림 → 바뀌었을 때만 커밋 1
  ft-ledger-fill fresh [--repo R] [--path P] [--ref origin/main]                        신선도 — «FRESH N분» rc0 · «STALE 원장 N분 낡음 · 담당 X» rc6(+ planner [긴급] 1통 · 같은 사건 1번)

커밋 = 작업 트리·로컬 가지 손대지 않음(임시 인덱스 + commit-tree) · --push 면 원장 사본 브랜치(FT_LEDGER_FILL_BRANCH · 기본 ledger/auto · ledger/ 로 시작하는 이름만 — 그 밖 rc1)에만
`git push origin <sha>:refs/heads/<브랜치>`(강제 0 · ff 만 · main 쓰기 0 — r2 planner 결정 ②). 판 = 브랜치가 main 을 품으면 브랜치 머리 위 · 아니면 main 위
(planner 판이 이김 · 갈라진 브랜치 머리는 두 번째 부모). main 착지 = planner _master 면제 경로 주기 1회:
  gh pr create --base main --head ledger/auto --title "[docs] 원장 기계 채움 착지" --body "ft-ledger-fill 사본 브랜치" → ft-merge-land <PR> --approve-sha ""
ff 거절 = 다시 받고 새 판 위에서 1번 더 · 또 거절이면 rc1 — 다른 판을 덮는 길 0. 뉴스·매거진은 ft_ledger_fill_src.read_ref 로 같은 판을 읽는다.
원천 실패 = 그 표 갱신 0 + ERROR 1줄 + rc1(다른 표는 갱신) · 그 실행의 채움 성공 기록 0 · 변화 0 = 커밋 0 rc0.
원천의 줄은 전부 그 원천의 꼴에 맞거나, 그 원천 전체가 오류(ft_ledger_fill_src.strict_rows 1곳 · 걸러내기 0 · r851 r4). «결론» 문단·사람이 쓴 칸은 바이트 그대로.
신선도 = 지금 − max(원장 «마지막 갱신» 시각, 마지막 채움 성공 시각) > FT_LEDGER_FRESH_MIN(60)분 = 낡음.
env: FT_ROOT · FT_LEDGER_REPO · FT_LEDGER_PATH · FT_LEDGER_FILL_STATE · FT_LEDGER_NOW(시험) · FT_LEDGER_QUESTIONS(콜론 구분 · 기본 ~/.hermes/state/byz_slack_questions.*.json)
     · FT_LEDGER_HIL(ft-hil.sh) · FT_LEDGER_QUEUE(AUTONOMY-QUEUE.md) · FT_MAGAZINE_STATE · FT_MBOX · FT_LEDGER_FRESH_MIN · FT_HARNESS_ROOT
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ft_ledger_fill_src as src  # noqa: E402
import ft_ledger_fill_tables as tb  # noqa: E402
from ft_ledger_fill_src import FillError, git  # noqa: E402

LOG = logging.getLogger("ft_ledger_fill")
REMOTE_S = 10.5  # 원격 1회 = CLI 기동 고정비 3.5 + 7(7초 룰 · r569 와 같은 값)
WHO = "ft-ledger-fill"
MSG = "[docs] 원장 표 기계 채움 — 지금 상태·오빠 할 일·팀 작업 (ft-ledger-fill · r851)"
UPDATED = re.compile(r"마지막 갱신:\s*(\d{4}-\d{2}-\d{2}) (\d{2}):(\d)([\dx])")


def now() -> datetime:
    v = os.environ.get("FT_LEDGER_NOW")
    return datetime.strptime(v, "%Y-%m-%d %H:%M") if v else datetime.now().replace(second=0, microsecond=0)


def state_dir(root: Path) -> Path:
    return Path(os.environ.get("FT_LEDGER_FILL_STATE") or root / ".fable-team" / "state" / "ledger-fill")


def _load(f: Path, default):
    return json.loads(f.read_text(encoding="utf-8")) if f.is_file() else default


def _save(f: Path, data) -> None:
    f.parent.mkdir(parents=True, exist_ok=True)
    tmp = f.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, f)


def goal_teams() -> list[str]:
    """골 정본 행마다 «팀» 칸(행 순번 = 원장 «메인 골» 표 행 순번) — 뉴스·매거진·쪽지 가드와 같은 판정기."""
    import ft_goal_table as gt
    try:
        return [t for _g, t, _e in gt.parse_rows(gt.load_canon()[0])]
    except Exception as e:  # noqa: BLE001 — 정본 실패 = 그 표만 갱신 0(FillError) · 뉴스 틱은 안 죽는다
        raise FillError(f"골 정본 못 읽음: {e}") from e


def published_at() -> str:
    """매거진 «발행 성공» 마지막 시각(magazine_doc 상태의 uploaded 기록 at) — 없으면 ''(내림 0). 못 읽음 = FillError."""
    f = Path(os.environ.get("FT_MAGAZINE_STATE") or Path.home() / ".hermes/state/magazine-doc.json")
    try:
        data = _load(f, {})
    except (OSError, ValueError) as e:
        raise FillError(f"매거진 상태 못 읽음: {f} ({type(e).__name__})") from e
    if not isinstance(data, dict):  # r851 r3 ⑥ — 모양 틀림 = 그 일(닫힌 줄 내림)만 0
        raise FillError(f"매거진 상태 모양 틀림: {f} (최상위 객체여야 함)")
    rows = src.strict_rows(f"매거진 상태 {f}", list(data.items()), lambda v: v if isinstance(v, dict) else None, skip=lambda v: False)  # r4 — 객체 아닌 항목 = 걸러내기 0
    return max((str(r.get("at")) for r in rows if r.get("uploaded") and r.get("at")), default="")


def _queue_text(root: Path) -> str | None:
    f = os.environ.get("FT_LEDGER_QUEUE")
    if not f:
        from ft_team_lib import TeamPathError, data_root, planner_queue
        try:
            f = str(planner_queue(data_root(root)))
        except TeamPathError as e:
            raise FillError(str(e)) from e
    try:
        return Path(f).read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    except OSError as e:
        raise FillError(f"AUTONOMY-QUEUE 못 읽음: {f} ({type(e).__name__})") from e


def _try(fn, *a):
    """원천 1개 읽기 — 어떤 예외든 FillError 로(r851 r3 ⑥ · 모양 오류 AttributeError 등이 채움 전체를 죽이지 않게 · 그 원천을 쓰는 표만 갱신 0 + ERROR + rc1)."""
    try:
        return fn(*a)
    except FillError as e:
        return e
    except Exception as e:  # noqa: BLE001 — 조용한 0 아님: 오류 줄 ERROR + rc1
        return FillError(f"{getattr(fn, '__name__', '원천')} 읽기 실패: {type(e).__name__}: {e}")


def gather(root: Path, repo: Path, ref: str, at: datetime) -> dict:
    """원천 값 — 실패한 원천은 FillError 그대로(그 원천을 쓰는 표만 건너뛴다)."""
    qpaths = [Path(p) for p in os.environ["FT_LEDGER_QUESTIONS"].split(":")] if os.environ.get("FT_LEDGER_QUESTIONS") \
        else sorted((Path.home() / ".hermes/state").glob("byz_slack_questions.*.json"))
    return {"cards": _try(src.team_cards, repo, ref, at), "notes": _try(src.mbox_done, root / ".fable-team/comm/mailbox.jsonl", at),
            "goals": _try(goal_teams), "qs": _try(src.open_questions, qpaths),
            "hil": _try(src.hil_pending, Path(os.environ.get("FT_LEDGER_HIL") or HERE / "ft-hil.sh")),
            "queue": _try(lambda: src.queue_open(_queue_text(root))), "pub": _try(published_at)}


def render(text: str, s: dict, at: datetime, seen: dict) -> tuple[str, list[str], dict, int]:
    """(새 원장, 오류 줄, 새 seen, 내린 행 수) — 원천·절 실패는 그 표만 그대로 두고 오류 줄에 남긴다."""
    lines, errs, stamp = text.split("\n"), [], f"{at:%m-%d %H:%M}"
    bad = lambda *ks: next((s[k] for k in ks if isinstance(s[k], FillError)), None)  # noqa: E731
    steps = (("메인 골 지금 상태", ("cards", "goals"), lambda ls: tb.goal_state(ls, s["goals"], s["cards"])),
             ("오빠 할 일", ("qs", "hil", "queue"), lambda ls: tb._replace(ls, "## 2. 오빠 할 일", tb.oppa_todo(s["qs"], s["hil"], s["queue"], stamp))),
             ("팀 작업", ("cards", "notes"), lambda ls: tb._replace_table(ls, "## 3. 팀 작업", tb.team_work(s["cards"], s["notes"]))))
    for name, keys, step in steps:
        e = bad(*keys)
        try:
            if e:
                raise e
            lines = step(lines)
        except Exception as err:  # noqa: BLE001 — r851 r3 ⑥ 원천 모양이 표 만들기에서 터져도 그 표만 0(오류 줄 ERROR + rc1)
            errs.append(f"{name} 표 갱신 0 — {err}")
    moved = 0
    try:
        if e := bad("pub"):
            raise e
        lines, seen, moved = tb.lower_closed(lines, seen, s["pub"], at)
    except Exception as err:  # noqa: BLE001 — 같은 규칙(그 일만 0)
        errs.append(f"닫힌 줄 내림 0 — {err}")
    return "\n".join(lines), errs, seen, moved


def _commit(repo: Path, rel: str, base: str, text: str, parents: list[str]) -> str:
    blob = subprocess.run(["git", "-C", str(repo), "hash-object", "-w", "--stdin"], input=text.encode("utf-8"), capture_output=True, timeout=src.LOCAL_S, check=False)
    if blob.returncode != 0:
        raise FillError(f"git hash-object 실패: {blob.stderr.decode('utf-8', 'replace').strip()[:200]}")
    with tempfile.TemporaryDirectory() as tmp:
        env = {**os.environ, "GIT_INDEX_FILE": str(Path(tmp) / "index")}
        run = lambda *a: subprocess.run(["git", "-C", str(repo), *a], capture_output=True, text=True, env=env, timeout=src.LOCAL_S, check=False)  # noqa: E731
        for a in (("read-tree", base), ("update-index", "--add", "--cacheinfo", f"100644,{blob.stdout.decode().strip()},{rel}")):
            if (r := run(*a)).returncode != 0:
                raise FillError(f"git {a[0]} 실패: {r.stderr.strip()[:200]}")
        tree = run("write-tree")
        if tree.returncode != 0:
            raise FillError(f"git write-tree 실패: {tree.stderr.strip()[:200]}")
    ps = [x for p in parents for x in ("-p", p)]
    return git(repo, "-c", f"user.name={WHO}", "-c", f"user.email={WHO}@byz.local", "commit-tree", tree.stdout.strip(), *ps, "-m", MSG).strip()


def bases(repo: Path, ref: str) -> tuple[str, list[str]]:
    """(읽을 판, 부모들) — 사본 브랜치가 main 을 품으면 브랜치 머리 위(부모 1) · 아니면 main 위(planner 판이 이김) —
    브랜치가 main 과 갈라졌으면(squash 착지 뒤) 브랜치 머리를 두 번째 부모로 이어 브랜치 push 를 ff 로 둔다(강제 0)."""
    main = git(repo, "rev-parse", "--verify", f"{ref}^{{commit}}").strip()
    br = f"refs/remotes/origin/{src.branch()}"
    if not src._has(repo, br):
        return main, [main]
    head = git(repo, "rev-parse", "--verify", f"{br}^{{commit}}").strip()
    if src.ancestor(repo, main, head):
        return head, [head]
    return main, ([main] if src.ancestor(repo, head, main) else [main, head])


def _remote(repo: Path, *a: str) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(["git", "-C", str(repo), *a], capture_output=True, text=True, timeout=REMOTE_S, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise FillError(f"git {a[0]} 실행 실패: {e}") from e


def fetch(repo: Path) -> None:
    """main + 사본 브랜치(원격에 아직 없음 = 정상 · 그 밖의 실패 = FillError) — 원격 추적 ref 만 갱신(가지·작업 트리 0)."""
    for spec in ("main", f"+refs/heads/{src.branch()}:refs/remotes/origin/{src.branch()}"):
        for _ in range(2):  # 재시도 1(출력 전 실패만)
            if (r := _remote(repo, "fetch", "--quiet", "origin", spec)).returncode == 0 or (spec != "main" and "couldn't find remote ref" in r.stderr):
                break
        else:
            raise FillError(f"git fetch {spec} 실패: {r.stderr.strip()[:200]}")


def fill(root: Path, repo: Path, rel: str, ref: str, at: datetime, do_fetch: bool = True, push: bool = False) -> tuple[int, str]:
    """(rc, 새 커밋 sha 또는 '') — 표 다시 쓰기 → 바뀌었으면 커밋 1(+push) · 오류 줄은 ERROR 로그 + rc1(커밋은 된 표만)."""
    st, br = state_dir(root), src.branch()  # r851 r3 ① — 입구에서 사본 브랜치 이름 검사(ledger/ 밖 = FillError rc1 · push 0)
    for attempt in range(2):
        if do_fetch or attempt:
            fetch(repo)
        base, parents = bases(repo, ref)
        text = git(repo, "show", f"{base}:{rel}")
        new, errs, seen, moved = render(text, gather(root, repo, ref, at), at, _load(st / "closed-seen.json", {}))
        for e in errs:
            LOG.error("%s", e)
        if tb.same(new, text):
            _save(st / "closed-seen.json", seen)
            _ok(st, at, errs)
            print(f"FILL 변화 없음 {base[:10]}" + (f" · 오류 {len(errs)}" if errs else ""))
            return (1 if errs else 0), ""
        sha = _commit(repo, rel, base, new, parents)
        if not push:
            print(f"FILL 커밋 {sha[:10]} (push 0) · 내림 {moved}")
            return (1 if errs else 0), sha
        r = _remote(repo, "push", "--quiet", "origin", f"{sha}:refs/heads/{br}")  # refspec 1개 · 사본 브랜치(ledger/…)만 — main 쓰기 0(planner 결정 ② · r3 ①)
        if r.returncode == 0:
            _save(st / "closed-seen.json", seen)
            _ok(st, at, errs)
            print(f"FILL 커밋 {sha[:10]} push {br} · 내림 {moved}" + (f" · 오류 {len(errs)}" if errs else ""))
            return (1 if errs else 0), sha
        if not re.search(r"non-fast-forward|fetch first|rejected", r.stderr):
            raise FillError(f"git push 실패: {r.stderr.strip()[:200]}")
        LOG.warning("원장 사본 브랜치 push ff 거절(다른 판 먼저) — 다시 받고 새 판 위에서 %s", "1번 더" if attempt == 0 else "포기")
    raise FillError("원장 사본 브랜치 push 2번 ff 거절 — 커밋 0(다른 판을 덮지 않음)")


def _ok(st: Path, at: datetime, errs: list[str]) -> None:
    if not errs:  # 표 하나라도 실패(원천 꼴 오류 포함 · r4 ②)면 «채움 성공» 이 아니다(신선도 판정이 낡은 표를 새 것으로 읽지 않게)
        _save(st / "last-ok.json", {"at": f"{at:%Y-%m-%d %H:%M}"})


def freshness(text: str, at: datetime, last_ok: str) -> tuple[int | None, str, str]:
    """(낡은 분 · 못 정하면 None, 담당 좌석, 사건 키) — 기준 = max(«마지막 갱신» 시각(…x 는 그 10분의 끝), 채움 성공 시각)."""
    m = UPDATED.search(text)
    line = next((ln for ln in text.splitlines() if "마지막 갱신:" in ln), "")
    hand = datetime.strptime(f"{m[1]} {m[2]}:{int(m[3]) * 10 + (9 if m[4] == 'x' else int(m[4])):02d}", "%Y-%m-%d %H:%M") if m else None
    owner = (re.search(r"갱신 담당 ([^)·]+)", line) or re.search(r"\d[\dx]\s*·\s*([^(·]+)", line))
    who = owner[1].strip() if owner else "모름"
    basis = max([d for d in (hand, datetime.strptime(last_ok, "%Y-%m-%d %H:%M") if last_ok else None) if d], default=None)
    return (int((at - basis).total_seconds() // 60) if basis else None), who, f"{m[0] if m else '없음'}|{last_ok}"


def fresh_note(root: Path, text: str, at: datetime) -> str:
    """'' = 신선 · 아니면 «원장 N분 낡음 · 담당 X» 1줄 — planner [긴급] 1통(같은 사건 = 같은 기준 시각이면 0)."""
    st = state_dir(root)
    mins, who, event = freshness(text, at, _load(st / "last-ok.json", {}).get("at", ""))
    if mins is not None and mins <= int(os.environ.get("FT_LEDGER_FRESH_MIN", "60")):
        return ""
    note = f"원장 {mins}분 낡음 · 담당 {who}" if mins is not None else f"원장 «마지막 갱신» 줄 못 읽음 · 담당 {who}"
    if _load(st / "fresh-alarm.json", {}).get("event") != event and _alarm(root, note) == 0:
        _save(st / "fresh-alarm.json", {"event": event, "at": f"{at:%Y-%m-%d %H:%M}"})
    return note


def _alarm(root: Path, note: str) -> int:
    try:
        planner = json.loads((root / ".fable-team/seats-planner.json").read_text(encoding="utf-8"))["_master"]
        body = f"[긴급] {note} — 표 기계 채움도 성공 0(ft-ledger-fill 오류 로그) · 원장 «마지막 갱신» 줄 또는 채움 오류를 보세요"
        p = subprocess.run(["bash", os.environ.get("FT_MBOX") or str(root / ".fable-team/comm/mbox.sh"), "send", planner, WHO, body],
                           capture_output=True, text=True, timeout=src.LOCAL_S, check=False)
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as e:
        LOG.error("원장 낡음 [긴급] 못 보냄: %s", e)
        return 1
    if p.returncode != 0:
        LOG.error("원장 낡음 [긴급] 못 보냄 rc=%s: %s", p.returncode, p.stderr.strip()[:120])
    return p.returncode


def _args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("cmd", choices=("fill", "fresh"))
    p.add_argument("--repo", default=os.environ.get("FT_LEDGER_REPO"))
    p.add_argument("--path", default=os.environ.get("FT_LEDGER_PATH") or "design/teams/planner/PLAN-oppa-ledger.md")
    p.add_argument("--ref", default="origin/main")
    p.add_argument("--no-fetch", action="store_true")
    p.add_argument("--push", action="store_true")
    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    a, root = _args(argv), Path(os.environ.get("FT_ROOT") or ".")
    repo = Path(a.repo or root / ".worktrees/news-ledger-main")
    try:
        if a.cmd == "fresh":
            ref = a.ref if a.ref != "origin/main" else src.read_ref(repo)  # 기본 = 뉴스와 같은 판(사본 브랜치가 앞서면 그 판 · r2 ④)
            note = fresh_note(root, git(repo, "show", f"{ref}:{a.path}"), now())
            print(f"STALE {note}" if note else "FRESH")
            return 6 if note else 0
        return fill(root, repo, a.path, a.ref, now(), not a.no_fetch, a.push)[0]
    except FillError as e:
        print(f"ERROR ft-ledger-fill: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    raise SystemExit(main(sys.argv[1:]))
