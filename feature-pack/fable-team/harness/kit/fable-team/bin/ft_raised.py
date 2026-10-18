#!/usr/bin/env python3
"""ft_raised.py — 상향 좌석(Fable 나노·astra DA) 판별과 «내릴 것» 점검 (R149 · 오빠 판정 1641).

  ft_raised.py is-raised <model>                  rc 0 = 상향 모델 · 1 = 기본 모델
  ft_raised.py check <seats.json|glob>... [--root R]
      명부 행의 raised.card 가 완성/ 이거나 없어졌으면 «▶내릴 것» 1줄씩 stdout. 없으면 출력 0 · rc 0.
      명부·카드 읽기 실패 = stderr 1줄씩 + rc 2 (이때 stdout 목록은 내지 않는다 — 조용히 0 반환 금지).
      glob 에 걸리는 파일이 없는 것은 오류가 아니다(팀 명부가 없는 설치) · 글자 그대로의 경로가 없으면 오류.
상향 판별은 모델 이름 두 패턴뿐이다: claude-fable-* · *astra* (대소문자 무시).
raised 칸이 없는 행(역할 좌석의 index=inbox 포함)과 _replaced_by 가 있는 은퇴 행은 건드리지 않는다.
"""
import glob
import json
import os
import sys

STATES = ("대기", "진행", "완성")


def is_raised(model: str) -> bool:
    m = model.lower()
    return m.startswith("claude-fable-") or "astra" in m


def exists(path: str) -> bool:
    try:
        _ = os.stat(path)
        return True
    except (FileNotFoundError, NotADirectoryError):
        return False   # 그 밖의 OSError(권한 등)는 «없음» 으로 삼키지 않고 호출자가 rc 2 로 올린다


def card_state(root: str, card: str) -> str:
    """카드가 대기·진행·완성 중 어느 폴더에 있나 — 어디에도 없으면 «없음»."""
    for src in STATES:
        if f"/{src}/" in card:
            for state in STATES:
                if exists(os.path.join(root, card.replace(f"/{src}/", f"/{state}/"))):
                    return state
    return "없음"


def check_file(seats: str, root: str, out: list[str]) -> None:
    with open(seats, encoding="utf-8") as f:
        rows = json.load(f)
    for seat, row in rows.items():
        if seat.startswith("_") or not isinstance(row, dict) or "raised" not in row or row.get("_replaced_by"):
            continue
        raised = row["raised"]
        card = raised.get("card") if isinstance(raised, dict) else None
        if not isinstance(card, str) or not card.strip():
            raise ValueError(f"{seat}: raised.card 없음")
        state = card_state(root, card)
        if state in ("완성", "없음"):
            out.append(f"▶내릴 것 {seat} 모델={row.get('model', '?')} 사유={raised.get('reason', '?')} (카드 {state})")


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
    out: list[str] = []
    rc = 0
    seen: set[str] = set()
    for seats in files:
        real = os.path.realpath(seats)   # 글자 그대로 + glob + 심링크가 같은 명부를 가리키면 한 번만 읽는다(경보 중복 0)
        if real in seen:
            continue
        seen.add(real)
        try:
            check_file(seats, root, out)
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
