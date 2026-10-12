#!/usr/bin/env python3
"""autonomy_classify.py — 자율 대리 결정 판정기 (DESIGN-autonomy-proxy-decision r3 §3 · 판정 1322).

  autonomy_classify.py --kind <종류> [--text <질문·선택지·카드 본문>]...
  autonomy_classify.py da-check <DA⑥ 판정문> <40hex sha>     push-merge 근거: «마지막 판정 머리» 가 APPROVE ∧ 그 절의 «고정 세트» 줄이 sha

출력 한 줄: `PROXY` (rc 0) | `QUEUE <사유>` (rc 2). 판정기 실패·인자 오류도 QUEUE (대리 쪽으로 새지 않는다 · #0 RULE).
대리 가능 종류는 세 가지뿐 — `reversible-choice` 는 오빠 값(판정 1322)으로 넣지 않는다(모르는 종류 = QUEUE).
제외 어휘는 종류 선언과 무관하게 글에 있으면 QUEUE — 오탐은 QUEUE(안전한 쪽)로만 난다.
"""
import re
import sys

PROXY_KINDS = ("push-merge", "card-start", "press-order")

# (이름, 정규식) — 하드 룰 2 파괴·비가역 + 설계 §3 절대 제외. 표본 시험: tests/harness/fixtures/autonomy-exclusions.tsv
EXCLUDE = [
    ("삭제", r"삭제|지우|\brm\b|\bdelete\b|\bunlink\b"),
    ("kill", r"\bkill\b|\bpkill\b|죽이"),
    ("drop", r"\bdrop\b|\btruncate\b"),
    ("force-push", r"force[- ]?push|push\s+(-f\b|--force)|--force|강제\s*(push|푸시)"),
    ("브랜치 삭제", r"브랜치.{0,6}(삭제|지우)|branch\s+(-D\b|--delete)"),
    ("DB 쓰기·DDL", r"\bDDL\b|(ALTER|CREATE)\s+TABLE|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM|DB\s*(쓰기|write)"),
    ("인프라·GPU·VM", r"인프라|\binfra\b|terraform|\bGPU\b|\bVM\b|인스턴스"),
    ("비용 증가", r"비용.{0,8}(증가|늘|지출|추가)|지출|예산|유료"),
    ("외부 발송", r"이메일|e-?mail|메일\s*발송|고객.{0,6}(발송|전송|공지|안내)|외부\s*(채널|발송)|슬랙.{0,6}외부|뉴스레터|\bSMS\b"),
    ("법무", r"법무|법적|약관|개인정보|\blegal\b|\bGDPR\b"),
    ("가격", r"가격|단가|요금|\bprice\b|\bpricing\b|마진"),
    ("전역 지침", r"~/\.claude|CLAUDE\.md|COMM-GUIDE|\.claude/rules|전역\s*지침|글로벌\s*지침"),
    ("오빠 원문과 다른 설계", r"원문과\s*다른|원문.{0,6}(변경|바꾸)|오빠\s*원문.{0,10}다른"),
]
_COMPILED = [(name, re.compile(rx, re.IGNORECASE)) for name, rx in EXCLUDE]


def classify(kind: str, texts: list[str]) -> tuple[str, str]:
    """→ ("PROXY", "") | ("QUEUE", 사유)"""
    if kind not in PROXY_KINDS:
        return "QUEUE", "대리 가능 종류 아님: %s" % kind
    for text in texts:
        for name, rx in _COMPILED:
            if rx.search(text):
                return "QUEUE", "제외 어휘 [%s]" % name
    return "PROXY", ""


_VERDICT = re.compile(r"\b(APPROVE|HOLD|REJECT)\b")
_SHA40 = re.compile(r"(?<![0-9a-f])[0-9a-f]{40}(?![0-9a-f])")
_FIXED_SET = re.compile(r"고정\s*세트\W*(?<![0-9a-f])[0-9a-f]{40}(?![0-9a-f])")  # «고정 세트» 바로 뒤에 40hex 가 오는 줄
_CURRENT_BAD = re.compile(r"^\s*(현재|최종)\s*판정\s*[:：]?\s*(HOLD|REJECT)")


def da_check(path: str, sha: str) -> tuple[str, str]:
    """판정문의 마지막 판정 머리(# 줄 + APPROVE|HOLD|REJECT 하나)가 APPROVE 이고 그 절(머리~끝)이 sha 를 명시할 때만 PROXY."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError as exc:
        return "QUEUE", "DA 판정문을 못 읽음: %s" % exc
    heads = [(i, set(_VERDICT.findall(ln))) for i, ln in enumerate(lines) if ln.startswith("#") and _VERDICT.search(ln)]
    if not heads:
        return "QUEUE", "DA 판정문에 판정 머리(# … APPROVE|HOLD|REJECT) 없음"
    idx, words = heads[-1]
    if words != {"APPROVE"}:
        return "QUEUE", "마지막 판정 머리가 APPROVE 아님/모순: %s" % ",".join(sorted(words))
    section = lines[idx:]
    fixed = [ln.replace("*", "").replace("`", "") for ln in section if _FIXED_SET.search(ln.replace("*", "").replace("`", ""))]
    if len(fixed) != 1:
        return "QUEUE", "마지막 판정 절의 «고정 세트» 줄이 %d개(정확히 1개여야 함)" % len(fixed)
    found = _SHA40.findall(fixed[0])
    if len(found) != 1:
        return "QUEUE", "«고정 세트» 줄의 40hex 가 %d개(정확히 1개여야 함)" % len(found)
    if found[0] != sha:
        return "QUEUE", "«고정 세트» 의 sha(%s…)가 --sha 와 다름" % found[0][:10]
    if any(_CURRENT_BAD.search(ln) for ln in section):
        return "QUEUE", "절 안에 현재 판정 HOLD/REJECT"
    return "PROXY", ""


def parse(argv: list[str]) -> tuple[str, list[str]]:
    kind: str | None = None
    texts: list[str] = []
    i = 0
    while i < len(argv):
        if argv[i] == "--kind" and i + 1 < len(argv):
            kind = argv[i + 1]
        elif argv[i] == "--text" and i + 1 < len(argv):
            texts.append(argv[i + 1])
        else:
            raise ValueError("알 수 없는 인자: %s" % argv[i])
        i += 2
    if kind is None:
        raise ValueError("--kind 필수")
    return kind, texts


def main(argv: list[str]) -> int:
    try:
        if argv[:1] == ["da-check"]:
            if len(argv) != 3:
                raise ValueError("usage: da-check <판정문> <sha>")
            verdict, why = da_check(argv[1], argv[2])
        else:
            verdict, why = classify(*parse(argv))
    except Exception as exc:  # 판정기 실패 = QUEUE + 로그
        print("QUEUE 판정기 오류: %s" % exc)
        print("autonomy_classify: %s" % exc, file=sys.stderr)
        return 2
    print("PROXY" if verdict == "PROXY" else "QUEUE %s" % why)
    return 0 if verdict == "PROXY" else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
