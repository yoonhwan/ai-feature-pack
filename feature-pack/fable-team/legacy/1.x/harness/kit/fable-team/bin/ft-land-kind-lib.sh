#!/usr/bin/env bash
# ft-land-kind-lib.sh — «구현 착지» 판정 한 곳 + 구현 0 카드 예외 한 곳 (r2274 · source 전용)
#   ft_land_kind <repo> <sha> → stdout 1줄: 구현 | 카드 문서만 | 판정 불가 <사유>  (rc 0 · 0 · 3)
#     규칙 = sha 의 첫 부모 대비 바뀐 경로(merge 는 first-parent · 뿌리 커밋은 빈 트리 대비)가 모두 «design/ 로 시작 ∧ /indices/ 포함» = 카드 문서만
#     하나라도 밖 = 구현(팩 kit/fable-team/templates/team/indices 배포 템플릿 포함) · 바뀐 경로 0(빈 커밋) = 카드 문서만(구현 증거 0 · DA#29 H3ⓐ)
#     git 1회 7초(하드 룰 12 · env FT_LAND_KIND_SEC 는 줄이기만 = 시험 대역) · 로컬 객체만(GIT_NO_LAZY_FETCH=1 · r1401) · 실패·시간 초과 = 판정 불가(하드 룰 20)
#   ft_no_code [<카드 본문> | stdin] → 예외(구현 0 카드) 꼴 1줄 rc 0 · 예외 아님 = 출력 0 rc 1 — 고정 3꼴(r2274 C3 · r2275 도 씀)
#     ⓐ 머리 «- 구현: 없음 — <사유>» ⓑ «- 닫힘(» 또는 «- <날짜> — 닫힘(» 으로 여는 줄에 «코드 0»
#     ⓒ 마지막 «- 착지:» 줄 안에 16진수 7~40자 0 ∧ 값이 «라이브 DB 반영» 으로 시작
#   부르는 곳 = ft2 keeper_land.landing · ft2 card_stage.stage(keeper_land.land_kind·no_code 경유) · ft-card-flow.sh 착지됐는데 진행
_FT_LAND_KIND_PY='
import os, subprocess, sys
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
out("카드 문서만" if all(x.startswith("design/") and "/indices/" in x for x in paths) else "구현", 0)
'
_FT_NO_CODE_PY='
import re, sys
body = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
HEX = re.compile(r"(?<![0-9A-Za-z])[0-9a-f]{7,40}(?![0-9A-Za-z])")
lands = re.findall(r"(?m)^- 착지(?:\([^)\n]*\))?:[ \t]*(.*)$", body)
if re.search(r"(?m)^- 구현: 없음 — \S", body):
    print("ⓐ 구현 없음")
elif any("코드 0" in x for x in re.findall(r"(?m)^- (?:\d{4}-\d{2}-\d{2} — )?닫힘\(.*$", body)):
    print("ⓑ 닫힘 코드 0")
elif lands and not HEX.search(lands[-1]) and lands[-1].startswith("라이브 DB 반영"):
    print("ⓒ 라이브 DB 반영")
else:
    sys.exit(1)
'
ft_land_kind() { python3 -I -c "$_FT_LAND_KIND_PY" "${1:-}" "${2:-}"; }
ft_no_code() { python3 -I -c "$_FT_NO_CODE_PY" "$@"; }
