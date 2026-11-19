#!/usr/bin/env bash
# ft-land-kind-lib.sh — «구현 착지» 판정 한 곳 (r2274 · source 전용)
#   ft_land_kind <repo> <sha> → stdout 1줄: 구현 | 카드 문서만 | 판정 불가 <사유>  (rc 0 · 0 · 3)
#   규칙 = sha 의 첫 부모 대비 바뀐 경로(merge 는 first-parent · 뿌리 커밋은 빈 트리 대비)가 모두 `*/indices/*` 밑 = 카드 문서만 · 하나라도 밖 = 구현 · 바뀐 경로 0(빈 커밋) = 구현(문서만 증거 없음 = 지금 길)
#   git 1회 7초(하드 룰 12 · env FT_LAND_KIND_SEC 는 줄이기만 = 시험 대역) · 로컬 객체만(GIT_NO_LAZY_FETCH=1 · r1401) · 실패·시간 초과 = 판정 불가(하드 룰 20 · 이 함수가 끝낸다)
#   부르는 곳 = ft2 keeper_land.landing · ft2 card_stage.stage(keeper_land.land_kind 경유) · ft-card-flow.sh 착지됐는데 진행
_FT_LAND_KIND_PY='
import fnmatch, os, subprocess, sys
repo, sha = sys.argv[1], sys.argv[2]
try:
    cap = min(7.0, float(os.environ.get("FT_LAND_KIND_SEC") or 7))
except ValueError:
    cap = 7.0
def out(word, rc):
    print(word)
    sys.exit(rc)
if not sha or len(sha) < 7 or len(sha) > 40 or any(c not in "0123456789abcdef" for c in sha):
    out("판정 불가 착지 sha 꼴 아님 %s" % sha, 3)
argv = ["git", "-C", repo, "diff-tree", "-r", "-z", "--name-only", "--no-commit-id", "--root", "--diff-merges=first-parent", sha + "^{commit}", "--"]
env = dict(os.environ, GIT_NO_LAZY_FETCH="1")
try:
    p = subprocess.run(argv, capture_output=True, text=True, timeout=cap, env=env)
except subprocess.TimeoutExpired:
    out("판정 불가 git diff-tree 시간초과 7초 %s" % sha[:8], 3)
except OSError as exc:
    out("판정 불가 git 시작 실패 %s" % exc.__class__.__name__, 3)
if p.returncode:
    out("판정 불가 git diff-tree rc %s %s" % (p.returncode, sha[:8]), 3)
paths = [x for x in p.stdout.split("\0") if x]
out("카드 문서만" if paths and all(fnmatch.fnmatchcase(x, "*/indices/*") for x in paths) else "구현", 0)
'
ft_land_kind() { python3 -I -c "$_FT_LAND_KIND_PY" "${1:-}" "${2:-}"; }
