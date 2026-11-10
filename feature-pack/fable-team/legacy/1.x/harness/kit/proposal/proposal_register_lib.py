#!/usr/bin/env python3
"""proposal_register_lib — ft-proposal-register.sh 의 판정·조회·본문·기록 보조 (판정 357 설계 §r2-1). 쓰기(create/comment/label)는 호출 쪽 Tank 만 한다.

  id    --repo R --rel P --verdict N --file F           → 제안서 식별자 ID 한 줄
  body  --id ID --rel P --verdict N --sha S --file F --top T --out DIR  → DIR/chunk-1..N 을 쓰고 N 을 출력(조각 60,000자 이하)
  plan  --id ID --title T --repo R --state S [--force-create] → ADOPT <번호> <phase> | CONFLICT <번호> | UNKNOWN | CREATE  (조회 실패·불완전 = rc 1)
  rec   S set ID PHASE [--issue M] | S del ID | S get ID   → 시도 기록 ~/.hermes/state/proposal_register.json
조회는 ${FT_GH_READ:-gh} (읽기 전용 · 시험이 대체) — 후보 = 표식 hash 본문 검색 ∪ 정확 제목 검색, 후보마다 본문 첫 줄 표식을 «완전 일치» 로 대조한다.
"""
import argparse
import hashlib
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

LIMIT = 60000  # GitHub 본문 한도 65,536자 아래의 안전 한도
LIST_MAX = 100  # 목록 조회 상한 — 이 수만큼 오면 «끝을 못 봤다» (불완전)


class LibError(RuntimeError):
    pass


def marker(pid: str) -> str:
    return f"<!-- byz-proposal-id: {pid} -->"


def make_id(repo: str, rel: str, verdict: str, data: bytes) -> str:
    return f"{repo}:{rel}@판정{verdict}#{hashlib.sha256(data).hexdigest()[:16]}"


def evidence_lines(top: Path, rel: str) -> list[str]:
    parts = Path(rel).parts
    slug = Path(rel).name.removeprefix("PROPOSAL-").rsplit("-", 1)[0]
    if len(parts) < 3 or parts[0] != "design":
        return []
    folder = top / "design" / parts[1] / "evidence" / f"proposal-{slug}"
    if not folder.is_dir():
        return []
    return [f"증거 폴더: {folder.relative_to(top)}/"] + [f"- {p.relative_to(top)}" for p in sorted(folder.rglob("*")) if p.is_file()]


def chunks_of(head: str, body: str) -> list[str]:
    """줄 경계로 LIMIT 자 이하 조각. 첫 조각 = head + 전문 앞부분 · 뒤 조각은 («이어서 k/N» 줄을 붙일 자리를 비운다)."""
    pieces: list[str] = []
    cur = head
    for line in body.splitlines(keepends=True):
        for seg in (line[i:i + LIMIT - 200] for i in range(0, len(line), LIMIT - 200)) if len(line) > LIMIT - 200 else (line,):
            if len(cur) + len(seg) > LIMIT - 40 and cur:
                pieces.append(cur)
                cur = ""
            cur += seg
    pieces.append(cur)
    n = len(pieces)
    return [pieces[0]] + [f"(이어서 {k}/{n})\n{pieces[k - 1]}" for k in range(2, n + 1)]


def cmd_body(a: argparse.Namespace) -> int:
    data = Path(a.file).read_bytes()
    ev = evidence_lines(Path(a.top), a.rel)
    head = "\n".join([marker(a.id), f"제안서 식별자: {a.id}", f"구현 시 이 본문을 참고 — 제안서 전문(판정 {a.verdict} 승인본)",
                      f"제안서: {a.rel} @ {a.sha}", f"오빠 컨펌: 판정 {a.verdict} (승인)", *ev, "---", ""])
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    pieces = chunks_of(head, data.decode("utf-8"))
    for k, text in enumerate(pieces, 1):
        (out / f"chunk-{k}").write_text(text, encoding="utf-8")
    print(len(pieces))
    return 0


def gh_read(*args: str) -> str:
    argv = shlex.split(os.environ.get("FT_GH_READ", "gh")) + list(args)
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise LibError(f"조회 실행 실패: {type(e).__name__}") from e
    if r.returncode != 0:
        raise LibError(f"조회 실패 rc={r.returncode}: {(r.stderr or r.stdout).strip()[:200]}")
    return r.stdout


def gh_json(*args: str) -> object:
    try:
        return json.loads(gh_read(*args))
    except ValueError as e:
        raise LibError("조회 응답이 JSON 이 아니다") from e


def first_line_of(repo: str, num: int) -> tuple[str, str]:
    v = gh_json("issue", "view", str(num), "--repo", repo, "--json", "title,body")
    if not isinstance(v, dict):
        raise LibError(f"#{num} 조회 응답 형식 오류")
    return str(v.get("title", "")), str(v.get("body", "")).split("\n", 1)[0].strip()


def candidates(repo: str, pid: str, title: str) -> set[int]:
    found: set[int] = set()
    for query in (f"{pid.rsplit('#', 1)[1]} in:body", f'"{title}" in:title'):
        rows = gh_json("issue", "list", "--repo", repo, "--state", "all", "--search", query, "--json", "number,title", "--limit", str(LIST_MAX))
        if not isinstance(rows, list):
            raise LibError("목록 응답 형식 오류")
        if len(rows) >= LIST_MAX:
            raise LibError(f"목록이 {LIST_MAX}건 상한에 닿았다(끝을 못 봤다) — 검색어를 좁혀야 한다")
        found |= {int(r["number"]) for r in rows}
    return found


def read_rec(state: Path) -> dict:
    if not state.exists():
        return {}
    try:
        d = json.loads(state.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise LibError(f"시도 기록 읽기 실패: {state}") from e
    if not isinstance(d, dict):
        raise LibError(f"시도 기록 형식 오류: {state}")
    return d


def cmd_plan(a: argparse.Namespace) -> int:
    rec = read_rec(Path(a.state)).get(a.id, {})
    if rec.get("issue"):  # 이미 번호를 받은 기록 — 검색에 안 보여도 새 create 0 (그 번호를 직접 확인)
        _, mark = first_line_of(a.repo, int(rec["issue"]))
        if mark != marker(a.id):
            raise LibError(f"기록의 #{rec['issue']} 본문 첫 줄이 이 제안서 표식이 아니다 — 사람이 확인(새 create 0)")
        print(f"ADOPT {rec['issue']} {rec.get('phase', '')}")
        return 0
    same, clash = [], []
    for num in sorted(candidates(a.repo, a.id, a.title)):
        title, mark = first_line_of(a.repo, num)
        if mark == marker(a.id):
            same.append(num)
        elif title == a.title:
            clash.append(num)
    if same:
        print(f"ADOPT {same[0]} 원격 표식 일치" + (f" (같은 표식 {len(same)}건: {same})" if len(same) > 1 else ""))
    elif clash:
        print(f"CONFLICT {clash[0]}")
    elif rec.get("phase") == "creating" and not a.force_create:
        print("UNKNOWN")
    else:
        print("CREATE")
    return 0


def cmd_rec(a: argparse.Namespace) -> int:
    state = Path(a.state)
    d = read_rec(state)
    if a.op == "get":
        print(json.dumps(d.get(a.id, {}), ensure_ascii=False))
        return 0
    if a.op == "set":
        d[a.id] = {"phase": a.phase, **({"issue": a.issue} if a.issue else {k: v for k, v in d.get(a.id, {}).items() if k == "issue"})}
    else:
        d.pop(a.id, None)
    state.parent.mkdir(parents=True, exist_ok=True)
    tmp = state.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, state)
    return 0


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, keys in (("id", ("repo", "rel", "verdict", "file")), ("body", ("id", "rel", "verdict", "sha", "file", "top", "out")),
                       ("plan", ("id", "title", "repo", "state"))):
        s = sub.add_parser(name)
        for k in keys:
            s.add_argument(f"--{k}", required=True)
        if name == "plan":
            s.add_argument("--force-create", action="store_true")
    s = sub.add_parser("rec")
    s.add_argument("state")
    s.add_argument("op", choices=("set", "del", "get"))
    s.add_argument("id")
    s.add_argument("phase", nargs="?", default="")
    s.add_argument("--issue", type=int)
    a = p.parse_args(argv)
    try:
        if a.cmd == "id":
            print(make_id(a.repo, a.rel, a.verdict, Path(a.file).read_bytes()))
            return 0
        return {"body": cmd_body, "plan": cmd_plan, "rec": cmd_rec}[a.cmd](a)
    except (LibError, OSError) as e:
        print(f"ERROR {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
