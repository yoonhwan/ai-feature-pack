#!/usr/bin/env bash
# ft-nano-suspended-check.sh <카드> --wt <워크트리> --reason "<사유>" [--apply]
#   ft-nano-close.sh --suspended 의 ⑥ 자리 검사·기록 한 곳 (r450): 팀 정지 등으로 «미완» 인 채 멈춘 나노는 rc=0 증거 줄이 없다 — 거짓 rc=0 대신 아래를 요구한다.
#     ⓐ 워크트리 HEAD 가 브랜치(detached 아님) 위의 40hex 커밋
#     ⓑ 미커밋 0 (.serena/project.yml 노이즈 · ' D' 지우다 만 흔적 제외) — 있으면 REJECT «[wip] 먼저»(close 가 앞서 [wip] 커밋을 한다)
#     ⓒ --apply 면 카드 «## 상태» 절 맨 끝에 `중단: <사유> · 세트 <HEAD> · <YYYY-MM-DD HH:MM> · 재개 = planner 발주 뒤 새 세션(브랜치 <이름> 보존)` 1줄
#        — 절의 마지막 줄이 이미 같은 세트의 `중단:` 줄이면 쓰지 않는다(멱등)
#   사유는 비지 않은 한 줄. 값 추론 금지 — 하나라도 아니면 REJECT(사유 stdout). exit 0 = 통과 · 1 = REJECT · 2 = usage
set -uo pipefail
USAGE="usage: $0 <카드> --wt <워크트리> --reason \"<사유>\" [--apply]"
CARD="${1:-}"; shift 2>/dev/null || { echo "$USAGE" >&2; exit 2; }
WT=""; REASON=""; HAVE_REASON=0; APPLY=0
while [ $# -gt 0 ]; do case "$1" in
  --wt) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; WT="$2"; shift 2;;
  --reason) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; HAVE_REASON=1; REASON="$2"; shift 2;;
  --apply) APPLY=1; shift;;
  *) echo "$USAGE" >&2; exit 2;; esac; done
[ -n "$CARD" ] && [ -n "$WT" ] && [ "$HAVE_REASON" -eq 1 ] || { echo "$USAGE" >&2; exit 2; }
[[ "$REASON" =~ [^[:space:]] ]] || { echo "usage: --reason 사유가 비어 있음(사유 없는 면제 거부)" >&2; exit 2; }
case "$REASON" in *$'\n'*|*$'\r'*) echo "usage: --reason 은 한 줄이어야 한다" >&2; exit 2;; esac
[ -f "$CARD" ] || { echo "REJECT 중단 — 카드 없음: $CARD"; exit 1; }
grep -qE '^## 상태[[:space:]]*$' "$CARD" || { echo "REJECT 중단 — 카드에 «## 상태» 절이 없다: $CARD"; exit 1; }
[ -d "$WT" ] || { echo "REJECT 중단 — 워크트리 없음: $WT"; exit 1; }

# ⓐ HEAD = 브랜치 위 40hex
BR="$(git -C "$WT" symbolic-ref --short -q HEAD)" || BR=""
[ -n "$BR" ] || { echo "REJECT 중단 — 워크트리 HEAD 가 브랜치가 아니다(detached): $WT"; exit 1; }
HEAD="$(git -C "$WT" rev-parse --verify -q HEAD)" || HEAD=""
[[ "$HEAD" =~ ^[0-9a-f]{40}$ ]] || { echo "REJECT 중단 — 워크트리 HEAD 커밋을 못 읽었다: $WT"; exit 1; }

# ⓑ 미커밋 0
st="$(git -C "$WT" status --porcelain 2>&1)" || { echo "REJECT 중단 — git status 실패: ${st:0:120}"; exit 1; }
dirty="$(printf '%s\n' "$st" | grep -v '\.serena/project\.yml$' | grep -v '^ D ' | grep -c .)"
[ "$dirty" -eq 0 ] || { echo "REJECT 중단 — 미커밋 ${dirty}파일 — [wip] 먼저(close 의 [wip] 커밋이 앞서 돈다): $WT"; exit 1; }

# ⓒ 기록 (--apply) — 절의 마지막 비지 않은 줄 바로 뒤에 넣는다(뒤에 다른 ## 절이 있어도 그 앞)
WHAT="검사만"
if [ "$APPLY" -eq 1 ]; then
  line="중단: $REASON · 세트 $HEAD · $(date '+%Y-%m-%d %H:%M') · 재개 = planner 발주 뒤 새 세션(브랜치 $BR 보존)"
  WHAT="$(python3 - "$CARD" "$HEAD" "$line" <<'PY'
import os, re, sys
p, head, line = sys.argv[1:4]
lines = open(p, encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines) if re.fullmatch(r"## 상태\s*", l))
end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
last = max([i for i in range(start + 1, end) if lines[i].strip()], default=start)
if lines[last].startswith("중단:") and (" · 세트 %s · " % head) in lines[last]:
    print("이미 있음"); sys.exit(0)
lines.insert(last + 1, line)
tmp = p + ".tmp.%d" % os.getpid()
with open(tmp, "w", encoding="utf-8") as f:
    f.write("\n".join(lines)); f.flush(); os.fsync(f.fileno())
os.replace(tmp, p)
print("append")
PY
)" || { echo "REJECT 중단 — 카드 기록 실패: $CARD"; exit 1; }
fi
echo "SUSPENDED-OK card=$CARD set=$HEAD branch=$BR 기록=$WHAT"
exit 0
