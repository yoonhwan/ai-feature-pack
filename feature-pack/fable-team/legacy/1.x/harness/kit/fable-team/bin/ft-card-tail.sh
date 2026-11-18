#!/usr/bin/env bash
# ft-card-tail.sh — r2244 O1: 카드 머리 1줄 + «## 상태» 마지막 N줄만 2048바이트 안으로 본다(쓰기 0).
# 쓰는 법: ft-card-tail.sh <카드 경로> [--ref <ref>] [--lines N]   (현재 폴더의 git 리포에서 읽는다)
#   ref 기본 origin/ops/main-base · N 기본 6 · 덧붙인 직후 확인은 --ref <ft-card-append 가 낸 PUSHED sha> 로만
#   (로컬 추적 ref 는 묵을 수 있다) · 꼬리가 길면 --lines 3.
# 출력: 머리 1줄(200바이트에서 자름) · 꼬리 N줄 · 합이 2048바이트를 넘으면 300바이트 넘는 줄은 앞 300바이트 +
#   «…(자름 <원래 바이트>B)» · 그래도 넘으면 꼬리 앞줄부터 빼고 «…(앞 <k>줄 뺌)» 1줄
#   · «## 상태» 없음 = «상태 절 없음» 1줄 · «## 상태» 뒤에 ## 절 = 끝에 «뒤에 ## 절 있음: <절 이름>» 1줄.
# rc: 0 = 보임 · 2 = ref 에 카드 없음 · 64 = 인자 틀림
set -uo pipefail
CARD=""; REF="origin/ops/main-base"; LINES=6
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REF="${2:-}"; shift 2 || { echo "인자 틀림: --ref <ref>" >&2; exit 64; } ;;
    --lines) LINES="${2:-}"; shift 2 || { echo "인자 틀림: --lines N" >&2; exit 64; } ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) [ -z "$CARD" ] || { echo "인자 틀림: 카드 경로 2개" >&2; exit 64; }; CARD="$1"; shift ;;
  esac
done
[ -n "$CARD" ] && [ -n "$REF" ] || { echo "쓰는 법: ft-card-tail.sh <카드 경로> [--ref <ref>] [--lines N]" >&2; exit 64; }
case "$LINES" in ''|*[!0-9]*|0) echo "인자 틀림: --lines 는 1 이상 정수" >&2; exit 64 ;; esac
git cat-file -e "$REF:$CARD" 2>/dev/null || { echo "카드 없음 $REF:$CARD"; exit 2; }
git show "$REF:$CARD" | python3 -c '
import sys
CAP, HEAD_CAP, LINE_CAP = 2048, 200, 300
n = int(sys.argv[1])
raw = sys.stdin.buffer.read().split(b"\n")
if raw and raw[-1] == b"":
    raw.pop()

def cut(b, lim):
    if len(b) <= lim:
        return b
    return b[:lim].decode("utf-8", "ignore").encode("utf-8")

head = [cut(raw[0], HEAD_CAP)] if raw else []
st = next((i for i, l in enumerate(raw) if l.rstrip() == "## 상태".encode()), None)
out_tail, note = [], []
if st is None:
    note = ["상태 절 없음".encode()]
else:
    end = next((j for j in range(st + 1, len(raw)) if raw[j].startswith(b"## ")), len(raw))
    sec = raw[st + 1:end]
    while sec and not sec[-1].strip():
        sec.pop()
    out_tail = sec[-n:]
    after = [l[3:].strip() for l in raw[end:] if l.startswith(b"## ")]
    if after:
        note = ["뒤에 ## 절 있음: ".encode() + b" \xc2\xb7 ".join(after)]

def size(ls):
    return sum(len(l) + 1 for l in ls)

if size(head + out_tail + note) > CAP:
    out_tail = [l if len(l) <= LINE_CAP else cut(l, LINE_CAP) + ("…(자름 %dB)" % len(l)).encode() for l in out_tail]
    note = [cut(l, LINE_CAP) for l in note]
k = 0
while out_tail and size(head + [b"x" * 24] + out_tail + note) > CAP:
    out_tail.pop(0)
    k += 1
if k:
    out_tail.insert(0, ("…(앞 %d줄 뺌)" % k).encode())
sys.stdout.buffer.write(b"".join(l + b"\n" for l in head + out_tail + note))
' "$LINES"
