#!/bin/bash
# harness-freeze-gate — PreToolUse(Bash) 게이트: BYZ 하네스 freeze 중 하네스 4폴더를 건드리는 커밋을 막는다 (r385 · 설계 DESIGN-harness-repo-split-and-teams-move-20261018 §9-2 ⓐ).
# 판정: exit 0 허용 / exit 2 차단(사유는 stderr).
#   표식: 커밋 대상 저장소의 공용 루트(`git rev-parse --git-common-dir` 의 부모) `.fable-team/state/harness-freeze` 가 있을 때만 검사한다(모든 워크트리 공통).
#   막는 폴더: scripts/fable-team-bin · scripts/harness-install · tools/comm-canonical · design/harness · tests/harness — 하네스 코드는 팩(feature-pack/fable-team/harness)에서 고친다.
#   대상 파일: `git diff --cached --name-only` + 커밋이 작업 트리를 함께 담는 꼴(-a·--all·-o·--only·-i·--include·pathspec `--`)이면 `git diff --name-only` 도.
#   대상 저장소: 커밋 명령의 `git -C <dir>`(연속이면 누적) · 같은 명령 안 `cd <dir>` 를 따라간다 · 없으면 JSON cwd · `cd -`·`popd` 뒤 커밋은 「cd 추적 불가」 exit 2.
#   풀기: 표식 파일을 지우는 것뿐(복귀 절차 §9-2 · master). 우회 env 없음.
# 조용한 허용 0: 통과는 ①입력 파싱 불가 ②커밋 명령 아님 ③표식 없음 — 이 셋뿐. 저장소를 못 풀면 exit 2.
set +e

INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# 커밋 명령마다 «대상 디렉터리<TAB>작업 트리 포함 1/0» 한 줄씩(커밋 아니면 무출력). 따옴표 안 글자(커밋 메시지)는 한 토큰이라 커밋으로 안 본다.
TARGETS=$(python3 -c 'import json,os,shlex,sys
try: d=json.loads(sys.argv[1])
except Exception: sys.exit(0)
if d.get("tool_name")!="Bash": sys.exit(0)
cmd=(d.get("tool_input") or {}).get("command") or ""
cwd=d.get("cwd") or "."
try:
    lx=shlex.shlex(cmd,posix=True,punctuation_chars=True); lx.whitespace_split=True; toks=list(lx)
except ValueError:
    sys.exit(0)
OPS={"&&","||",";","|","&",";;","(",")"}
def join(base,p):
    p=os.path.expanduser(p); return p if os.path.isabs(p) else os.path.join(base,p)
def worktree_too(args):
    for a in args:
        if a in ("--all","--only","--include","--"): return True
        if a.startswith("-") and not a.startswith("--") and any(c in a[1:] for c in "aoi"): return True
    return False
cur=cwd
i=0
while i<len(toks):
    name=os.path.basename(toks[i])
    if name in ("cd","pushd","popd"):
        i+=1
        while i<len(toks) and toks[i].startswith("-") and toks[i]!="-": i+=1
        arg=toks[i] if i<len(toks) and toks[i] not in OPS else None
        if name=="popd" or arg is None or arg=="-": cur=None
        elif cur is not None: cur=join(cur,arg)
        if arg is not None and arg not in OPS: i+=1
        continue
    if name!="git": i+=1; continue
    g=cur; i+=1
    while i<len(toks) and toks[i].startswith("-"):
        if toks[i]=="-C" and i+1<len(toks):
            if g is not None: g=join(g,toks[i+1])
            i+=2
        elif toks[i]=="-c" and i+1<len(toks): i+=2
        else: i+=1
    if i<len(toks) and toks[i]=="commit":
        j=i+1; args=[]
        while j<len(toks) and toks[j] not in OPS: args.append(toks[j]); j+=1
        print("%s\t%d" % (g if g is not None else "!cd", 1 if worktree_too(args) else 0))
' "$INPUT" 2>/dev/null)
[ -z "$TARGETS" ] && exit 0

FROZEN='^(scripts/fable-team-bin|scripts/harness-install|tools/comm-canonical|design/harness|tests/harness)/'
BLOCK=""
while IFS=$'\t' read -r DIR WT; do
  if [ "$DIR" = "!cd" ]; then
    BLOCK="$BLOCK
🚫 [harness-freeze-gate] 검사 불가 대상(cd 추적 불가) — 'cd -'·'cd'(단독)·'popd' 뒤 커밋이다. 절대경로 cd 나 'git -C <dir>' 로 쓰세요"
    continue
  fi
  COMMON=$(git -C "$DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  if [ -z "$COMMON" ]; then
    BLOCK="$BLOCK
🚫 [harness-freeze-gate] 검사 불가 대상: $DIR (git 저장소 아님)"
    continue
  fi
  MARK="$(dirname "$COMMON")/.fable-team/state/harness-freeze"
  [ -f "$MARK" ] || continue
  FILES=$(git -C "$DIR" diff --cached --name-only 2>/dev/null)
  [ "$WT" = 1 ] && FILES="$FILES
$(git -C "$DIR" diff --name-only 2>/dev/null)"
  HIT=$(printf '%s\n' "$FILES" | grep -E "$FROZEN" | LC_ALL=C sort -u)
  [ -z "$HIT" ] && continue
  BLOCK="$BLOCK
🚫 [harness-freeze-gate] 하네스 freeze 중 — BYZ 하네스 4폴더 커밋 REJECT (표식 $MARK · $(head -1 "$MARK" 2>/dev/null))
   건드린 파일 $(printf '%s\n' "$HIT" | grep -c .)개: $(printf '%s\n' "$HIT" | head -5 | tr '\n' ' ')
   하네스 코드는 팩 feature-pack/fable-team/harness 에서 고친다(경로 표 = 설계 §9-2 역매핑 5행). freeze 해제는 복귀 절차 뒤 master 가 표식을 지운다."
done <<< "$TARGETS"

[ -z "$BLOCK" ] && exit 0
printf '%s\n' "${BLOCK#?}" >&2
exit 2
