#!/usr/bin/env bash
# ft-nano-accept.sh — r1670 인수 영수증 1줄. 팀장 역할이 «이 세트를 이어받았다» 를 카드 «## 상태» 절 끝에 적는다.
#   usage: ft-nano-accept.sh <카드> <40hex> "<종류>=<담당>[ <종류>=<담당>…]" [--by <이름>]
#   쓰는 줄: `- 인수: <40hex> · 남은 일: <종류>=<담당> … · 쓴 이: <이름>`
#   ★같은 sha 재실행 = 0줄(rc 0 · ALREADY) · 다른 sha = 새 줄★ — 인수는 «세트 단위» 다(r1670 ⓐ · READ ≠ 인수).
#   남은 일 칸이 비면 REJECT — 「남은 것 0」 도 `남은 일: 없음` 으로 적는다(빈 칸과 «없음» 을 가른다).
#   쓴 이 = 팀장 역할(실행자 이름 기록) · --by 생략이면 env FT_SEAT · 둘 다 없으면 REJECT.
#   rc 0 = 씀/이미 있음 · 1 = REJECT(사유 stdout 1줄) · 2 = usage. 카드 «## 상태» 절 밖은 안 건드린다.
#   쓰기 1곳(그 카드 파일) · 명부·원장·tmux·브랜치 손 0 · 실행 비트 0(100644 · bash <경로> 로 부른다).
set -uo pipefail
CARD="${1:-}"; SHA="${2:-}"; REST="${3:-}"
[ -n "$CARD" ] && [ -n "$SHA" ] || { echo "usage: ft-nano-accept.sh <카드> <40hex> \"<종류>=<담당>[ …]\" [--by <이름>]" >&2; exit 2; }
shift 3 2>/dev/null || shift $# || true
BY="${FT_SEAT:-}"
while [ $# -gt 0 ]; do case "$1" in --by) BY="${2:-}"; shift 2;; *) echo "usage: ft-nano-accept.sh <카드> <40hex> \"…\" [--by <이름>]" >&2; exit 2;; esac; done
exec python3 - "$CARD" "$SHA" "$REST" "$BY" <<'PY'
import os, re, sys
card, sha, rest, by = sys.argv[1:5]
if not re.fullmatch(r"[0-9a-f]{40}", sha):
    print(f"REJECT 40hex 소문자 아님: {sha}"); sys.exit(1)
if not rest.strip():
    print("REJECT 남은 일 칸이 비어 있다 — «<종류>=<담당> …» 또는 «없음» 을 적어라"); sys.exit(1)
if any(not re.fullmatch(r"[^\s=]+=[^\s=]+", t) for t in rest.split()):
    print(f"REJECT 남은 일 꼴 아님(«<종류>=<담당>»): {rest.strip()[:60]}"); sys.exit(1)
if not by.strip():
    print("REJECT 쓴 이 없음 — --by <이름> 또는 env FT_SEAT"); sys.exit(1)
try: txt = open(card, encoding="utf-8").read()
except OSError as e:
    print(f"REJECT 카드 읽기 rc=1: {e}"); sys.exit(1)
lines = txt.split("\n")
try: st = next(n for n, l in enumerate(lines) if l.startswith("## 상태"))
except StopIteration:
    print(f"REJECT 카드 «## 상태» 절 없음: {card}"); sys.exit(1)
end = next((n for n in range(st + 1, len(lines)) if lines[n].startswith("## ")), len(lines))
sec = lines[st + 1:end]
line = f"- 인수: {sha} · 남은 일: {rest.strip()} · 쓴 이: {by.strip()}"
if any(re.search(r"인수:\s*" + sha, l) for l in sec):
    print(f"ALREADY 인수 {sha[:9]} — 0줄(같은 세트 재실행)"); sys.exit(0)
while end > st + 1 and not lines[end - 1].strip(): end -= 1   # 절 끝 빈 줄 «뒤» 가 아니라 마지막 내용 줄 다음에 넣는다
tmp = card + ".tmp-" + str(os.getpid())
try:
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines[:end] + [line] + lines[end:]))
    os.replace(tmp, card)
except OSError as e:
    try: os.unlink(tmp)
    except OSError: pass
    print(f"REJECT 카드 쓰기 rc=1: {e}"); sys.exit(1)
print(f"ACCEPT {sha[:9]} — {card} «## 상태» 에 인수 줄 1개(남은 일: {rest.strip()[:60]} · 쓴 이: {by.strip()})")
PY
