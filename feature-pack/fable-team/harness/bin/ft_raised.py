#!/usr/bin/env python3
"""ft_raised.py — 상향 좌석(Fable 나노·astra DA) 판별과 «내릴 것» 점검 (R149 · 오빠 판정 1641).

  ft_raised.py is-raised <model>                  rc 0 = 상향 모델 · 1 = 기본 모델
  ft_raised.py check <seats.json|glob>... [--root R]
      명부 행의 raised.card 가 완성/ 이거나 없어졌으면 «▶내릴 것» 1줄씩 stdout. 없으면 출력 0 · rc 0.
      카드 상태 = 데이터 루트(LIVE_ROOT) · R(공용 루트) 체크아웃 · ref origin/main 세 자리 중 가장 앞선 것(완성 > 진행 > 대기 · r518).
      ref 못 읽음·LIVE_ROOT 깨짐 = rc 2 · LIVE_ROOT 파일 없음 = 줄 끝에 «못 본 자리» 표기(rc 0 일 때 stderr 0 — 틱이 2>&1 로 받는다).
      명부·카드 읽기 실패 = stderr 1줄씩 + rc 2 (이때 stdout 목록은 내지 않는다 — 조용히 0 반환 금지).
      glob 에 걸리는 파일이 없는 것은 오류가 아니다(팀 명부가 없는 설치) · 글자 그대로의 경로가 없으면 오류.
상향 판별은 모델 이름 두 패턴뿐이다: claude-fable-* · *astra* (대소문자 무시).
raised 칸이 없는 행(역할 좌석의 index=inbox 포함)과 _replaced_by 가 있는 은퇴 행은 건드리지 않는다.
"""
import glob
import json
import os
import subprocess
import sys

STATES = ("대기", "진행", "완성")
REF = "origin/main"


def is_raised(model: str) -> bool:
    m = model.lower()
    return m.startswith("claude-fable-") or "astra" in m


def exists(path: str) -> bool:
    try:
        _ = os.stat(path)
        return True
    except (FileNotFoundError, NotADirectoryError):
        return False   # 그 밖의 OSError(권한 등)는 «없음» 으로 삼키지 않고 호출자가 rc 2 로 올린다


def ref_present(root: str, paths: list[str]) -> set[str]:
    """ref origin/main 트리에 있는 경로들 — 리포 아님·origin 없음·7초 초과는 ValueError(«없음» 으로 삼키지 않는다)."""
    def git(*args: str, stdin: str | None = None) -> subprocess.CompletedProcess[str]:
        try:
            return subprocess.run(["git", "-C", root, *args], input=stdin, capture_output=True, text=True, timeout=7)
        except subprocess.TimeoutExpired:
            raise ValueError(f"ref {REF} 읽기 7초 초과: {root}") from None
    if git("rev-parse", "--verify", "-q", f"{REF}^{{commit}}").returncode != 0:
        raise ValueError(f"ref {REF} 못 읽음(리포 아님·origin 없음): {root}")
    p = git("cat-file", "--batch-check", stdin="".join(f"{REF}:{x}\n" for x in paths))
    rows = p.stdout.splitlines()
    if p.returncode != 0 or len(rows) != len(paths):
        raise ValueError(f"ref {REF} 트리 읽기 실패 rc={p.returncode}: {root}")
    return {x for x, row in zip(paths, rows) if not row.endswith(" missing")}


def data_place(root: str) -> tuple[str, str]:
    """(데이터 루트, 못 본 자리 표기) — r515 data_root(FT_ROOT → 공용 루트 LIVE_ROOT 1행 → 공용 루트). LIVE_ROOT 파일이 없으면 표기를 남긴다."""
    from ft_team_lib import TeamPathError, data_root   # check 만 쓰는 짝 — is-raised 만 부르는 spawn 의 임시 bin 엔 없어도 된다
    try:
        data = data_root(root)
    except TeamPathError as e:
        raise ValueError(str(e)) from None
    live = os.path.join(root, ".fable-team", "LIVE_ROOT")
    blind = "" if os.environ.get("FT_ROOT") or os.path.isfile(live) else f" · 못 본 자리: 데이터 루트(LIVE_ROOT 없음 {live})"
    return data, blind


def card_state(root: str, card: str, data: str | None = None) -> str:
    """카드가 대기·진행·완성 중 어디인가 — 데이터 루트·공용 루트 체크아웃·ref origin/main 중 가장 앞선 상태 · 셋 다 없으면 «없음»(r518)."""
    for src in STATES:
        if f"/{src}/" in card:
            paths = {state: card.replace(f"/{src}/", f"/{state}/") for state in STATES}
            in_ref = ref_present(root, list(paths.values()))
            for state in reversed(STATES):
                p = paths[state]
                if p in in_ref or any(exists(os.path.join(r, p)) for r in (data or root, root)):
                    return state
    return "없음"


def check_file(seats: str, root: str, out: list[str], data: str | None = None, blind: str = "") -> None:
    with open(seats, encoding="utf-8") as f:
        rows = json.load(f)
    for seat, row in rows.items():
        if seat.startswith("_") or not isinstance(row, dict) or "raised" not in row or row.get("_replaced_by"):
            continue
        raised = row["raised"]
        card = raised.get("card") if isinstance(raised, dict) else None
        if not isinstance(card, str) or not card.strip():
            raise ValueError(f"{seat}: raised.card 없음")
        state = card_state(root, card, data)
        if state in ("완성", "없음"):
            out.append(f"▶내릴 것 {seat} 모델={row.get('model', '?')} 사유={raised.get('reason', '?')} (카드 {state}){blind}")


def expand(arg: str) -> list[str]:
    return sorted(glob.glob(arg)) if glob.has_magic(arg) else [arg]


def check(args: list[str]) -> int:
    root, files = ".", []
    while args:
        a = args.pop(0)
        if a == "--root" and args:
            root = args.pop(0)
        else:
            files += expand(a)
    try:
        data, blind = data_place(root)
    except (ImportError, OSError, ValueError) as e:
        print(f"ft_raised: ERROR 데이터 루트 {root}: {e}", file=sys.stderr)
        return 2
    out: list[str] = []
    rc = 0
    seen: set[str] = set()
    for seats in files:
        real = os.path.realpath(seats)   # 글자 그대로 + glob + 심링크가 같은 명부를 가리키면 한 번만 읽는다(경보 중복 0)
        if real in seen:
            continue
        seen.add(real)
        try:
            check_file(seats, root, out, data, blind)
        except (OSError, ValueError, AttributeError) as e:
            print(f"ft_raised: ERROR {seats}: {e}", file=sys.stderr)
            rc = 2
    if out and rc == 0:
        print("\n".join(out))
    return rc


def main(argv: list[str]) -> int:
    if len(argv) == 3 and argv[1] == "is-raised":
        return 0 if is_raised(argv[2]) else 1
    if len(argv) >= 3 and argv[1] == "check":
        return check(argv[2:])
    print("usage: ft_raised.py is-raised <model> | check <seats.json|glob>... [--root <repo>]", file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
