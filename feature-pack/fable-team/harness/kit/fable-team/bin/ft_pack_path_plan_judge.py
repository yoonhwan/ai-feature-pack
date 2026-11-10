#!/usr/bin/env python3
"""ft_pack_path_plan_judge — h 계획 파일의 «날 팩 1.x 경로 접두» 검사 (r1556 · r1544 legacy/1.x 이동).
CLI: ft_pack_path_plan_judge.py --plan <파일> → `ok`(rc0) | `reject <이유> — 줄 <n>`(줄마다 · rc1) | 내부 오류 rc2
- 주석 아닌 줄의 «<ref>: 바로 뒤» 날 `feature-pack/fable-team/harness/`(또는 `…/legacy/1.x/harness/`) = reject — 접두는 PACK_1X 변수 하나
  (값은 ft-pack-1x-prefix.sh 가 ref 마다 정한다). 따옴표(큰·작은)는 벗긴 뒤 같은 판정 — 체크아웃·절대 경로(`cp <팩>/…`)는 검사 밖.
  문자열만 본다(실행 0). ft-hil.sh lint 가 등록 전에 부른다."""
from __future__ import annotations
import re
import sys
RAW = re.compile(r"feature-pack/fable-team/(?:legacy/1\.x/)?harness/")
VAR = "${PACK_1X}/"
WHY = "팩 1.x 하네스 경로 접두는 PACK_1X 변수로 쓴다(${PACK_1X}/harness/…) — 줄 %d"

def logical_lines(text: str):
    """(첫 줄 번호, 이어 쓰기를 합친 줄) — 주석 줄은 건너뛴다."""
    buf, start = "", 0
    for n, line in enumerate(text.splitlines(), 1):
        if not buf:
            start = n
            if line.lstrip().startswith("#"):
                continue
        if line.endswith("\\"):
            buf += line[:-1] + " "
            continue
        yield start, buf + line
        buf = ""
    if buf:
        yield start, buf

def plan(text: str) -> list[str]:
    out: list[str] = []
    for n, line in logical_lines(text):
        flat = line.replace('"', "").replace("'", "")  # 따옴표(큰·작은)를 벗긴 뒤 같은 판정 — 따옴표로 빠져나가기 0
        for m in RAW.finditer(flat):
            if flat[: m.start()].endswith(VAR):
                continue  # ${PACK_1X}/ 꼴 = 통과
            if flat[: m.start()].endswith(":"):  # ref 콜론 바로 뒤만 날 접두(체크아웃 경로는 통과)
                out.append(WHY % n)
                break
    return out
def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] != "--plan":
        print("usage: ft_pack_path_plan_judge.py --plan <파일>", file=sys.stderr)
        return 2
    try:
        with open(argv[2], encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as e:
        print("ft_pack_path_plan_judge 내부 오류: %s" % type(e).__name__, file=sys.stderr)
        return 2
    found = plan(text)
    for why in found:
        print("reject " + why)
    if not found:
        print("ok")
    return 1 if found else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
