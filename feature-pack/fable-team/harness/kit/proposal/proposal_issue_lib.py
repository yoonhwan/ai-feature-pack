#!/usr/bin/env python3
"""proposal_issue_lib — 제안 Issue 도구(ft-proposal-open/approve/inbox.sh)의 판정·조회·본문 보조 (R77 r1 · 판정 826). 쓰기(create/edit/comment/label)는 호출 쪽 Tank 만 한다.

  meta       --file F                        → 1행 제안 ID(`<부모 폴더>/<slug>`) · 2행 제목 (파일 이름이 PROPOSAL-<slug>-YYYYMMDD.md 가 아니면 rc 1)
  sections   --file F                        → 필수 칸 6개 중 없거나 빈 칸 이름(공백 구분)을 출력 · 빠진 게 있으면 rc 1
  open-body  --id ID --file F --out DIR      → DIR/chunk-1..N (첫 조각 첫 줄 = 숨은 표식 · 60,000자 분할) 을 쓰고 N 을 출력
  find       --repo R --id ID                → `ADOPT <번호>`(본문 첫 줄 표식 완전 일치) | `NONE`
  labels     --repo R --issue M              → 라벨 이름(공백 구분)
  ledger     --dir D --verdict N --issue M --repo R → planner 원장 `^N 오빠 인터뷰` 줄에 github.com/R/issues/M(저장소 포함 · 대소문자 무시)이 있으면 rc 0, 없으면 rc 1
  inbox      --repo R --tank T               → 열린 proposal Issue 중 마지막 코멘트 작성자가 T 가 아닌 것: `번호\\t작성자\\t시각\\t첫 줄\\t이미needs-reply(yes|no)`
조회는 ${FT_GH_READ:-gh}(읽기 전용 · 시험이 대체) — 호출마다 7초 + 재시도 1회(전역 7초 룰 · FT_GATE_GH_TIMEOUT 으로 시험만 줄인다). 실패·빈 응답 = rc 1.
"""
import argparse
import glob
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from proposal_register_lib import chunks_of, marker  # noqa: E402  # pyright: ignore[reportImplicitRelativeImport]  (60,000자 줄 경계 분할 · 숨은 표식 형식 재사용)

REQUIRED = ("결론", "오빠가 결정할 것", "배경", "제안", "되돌림", "근거")
LIST_MAX = 100


class LibError(RuntimeError):
    pass


def gh_json(*args: str) -> object:
    timeout, last = float(os.environ.get("FT_GATE_GH_TIMEOUT", "7")), ""
    for _ in range(2):  # 1회 + 재시도 1회
        try:
            r = subprocess.run(shlex.split(os.environ.get("FT_GH_READ", "gh")) + list(args), capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            last = f"시간 초과({timeout:g}초)"
            continue
        except OSError as e:
            last = type(e).__name__
            continue
        if r.returncode == 0 and r.stdout.strip():
            try:
                return json.loads(r.stdout)
            except ValueError:
                last = "JSON 아님"
                continue
        last = f"rc={r.returncode}" if r.returncode else "빈 응답"
    raise LibError(f"gh 읽기 실패({' '.join(args[:2])}): {last}")


def sections_of(text: str) -> dict[str, str]:
    return {m.group(1): m.group(2) for m in re.finditer(r"^## (\S.*?)\s*\n(.*?)(?=^## |\Z)", text + "\n", re.S | re.M)}


def cmd_meta(a: argparse.Namespace) -> int:
    p = Path(a.file)
    m = re.match(r"^PROPOSAL-([a-z0-9-]+)-\d{8}\.md$", p.name)
    if not m:
        raise LibError(f"파일 이름이 PROPOSAL-<slug>-YYYYMMDD.md 가 아니다: {p.name}")
    t = re.search(r"^# 제안서 — (.+)$", p.read_text(encoding="utf-8"), re.M)
    print(f"{p.resolve().parent.name}/{m.group(1)}\n{(t.group(1).strip() if t else p.stem)}")
    return 0


def cmd_sections(a: argparse.Namespace) -> int:
    secs = sections_of(Path(a.file).read_text(encoding="utf-8"))
    miss = [k.replace(" ", "_") for k in REQUIRED if not secs.get(k, "").strip()]
    print(" ".join(miss))
    return 1 if miss else 0


def cmd_open_body(a: argparse.Namespace) -> int:
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    pieces = chunks_of(marker(a.id) + "\n", Path(a.file).read_text(encoding="utf-8"))
    for k, text in enumerate(pieces, 1):
        (out / f"chunk-{k}").write_text(text, encoding="utf-8")
    print(len(pieces))
    return 0


def cmd_find(a: argparse.Namespace) -> int:
    rows = gh_json("issue", "list", "--repo", a.repo, "--state", "all", "--search", f'"byz-proposal-id: {a.id}" in:body', "--json", "number,body", "--limit", str(LIST_MAX))
    if not isinstance(rows, list) or len(rows) >= LIST_MAX:
        raise LibError("목록 응답 형식 오류 또는 상한 도달(끝을 못 봤다)")
    hit = [int(r["number"]) for r in rows if isinstance(r, dict) and str(r.get("body", "")).split("\n", 1)[0].strip() == marker(a.id)]
    print(f"ADOPT {min(hit)}" if hit else "NONE")
    return 0


def cmd_labels(a: argparse.Namespace) -> int:
    v = gh_json("issue", "view", str(a.issue), "--repo", a.repo, "--json", "labels")
    if not isinstance(v, dict):
        raise LibError("조회 응답 형식 오류")
    print(" ".join(sorted(str(x.get("name")) for x in v.get("labels") or [] if isinstance(x, dict))))
    return 0


def cmd_ledger(a: argparse.Namespace) -> int:
    for f in sorted(glob.glob(os.path.join(a.dir, "VERDICTS-planner-*.md"))):
        for ln in Path(f).read_text(encoding="utf-8", errors="replace").splitlines():
            if re.match(rf"^{re.escape(a.verdict)} 오빠 인터뷰", ln) and re.search(rf"(?<![\w.\-])github\.com/{re.escape(a.repo)}/issues/{re.escape(a.issue)}(?![0-9])", ln, re.I):
                return 0
    print(f"planner 원장 「{a.verdict} 오빠 인터뷰」 줄에 {a.repo} issues/{a.issue} 없음({a.dir})")
    return 1


def cmd_inbox(a: argparse.Namespace) -> int:
    rows = gh_json("issue", "list", "--repo", a.repo, "--label", "proposal", "--state", "open", "--json", "number,labels,comments", "--limit", str(LIST_MAX))
    if not isinstance(rows, list) or len(rows) >= LIST_MAX:
        raise LibError("목록 응답 형식 오류 또는 상한 도달(끝을 못 봤다)")
    for r in rows:
        cs = [c for c in r.get("comments") or [] if isinstance(c, dict)]
        last = cs[-1] if cs else None
        who = ((last or {}).get("author") or {}).get("login")
        if last is None or who == a.tank:
            continue
        has = any(isinstance(x, dict) and x.get("name") == "needs-reply" for x in r.get("labels") or [])
        first = (str(last.get("body", "")).strip().splitlines() or [""])[0][:60]
        print(f"{r['number']}\t{who}\t{last.get('createdAt', '')}\t{first}\t{'yes' if has else 'no'}")
    return 0


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, keys in (("meta", ("file",)), ("sections", ("file",)), ("open-body", ("id", "file", "out")), ("find", ("repo", "id")), ("labels", ("repo", "issue")),
                       ("ledger", ("dir", "verdict", "issue", "repo")), ("inbox", ("repo", "tank"))):
        s = sub.add_parser(name)
        for k in keys:
            s.add_argument(f"--{k}", required=True)
    a = p.parse_args(argv)
    try:
        return {"meta": cmd_meta, "sections": cmd_sections, "open-body": cmd_open_body, "find": cmd_find, "labels": cmd_labels, "ledger": cmd_ledger, "inbox": cmd_inbox}[a.cmd](a)
    except (LibError, OSError) as e:
        print(f"ERROR {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
