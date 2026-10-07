#!/usr/bin/env bash
# ft-land.sh --feat <ref> [--target main] [--remote origin] [--repo <dir>] [--dry-run]
#   랜딩 ④ «대상 동기화 → 후보 커밋 1개» 기계 부분 (SPEC-full-flow 단계 11 ④ · SPEC-planner-issue-queue L-5 · S10 재발 차단).
#   fetch → T=<remote>/<target> 기록 → is-ancestor T feat 참 = ff 후보(feat 그대로) / 거짓 = merge-tree --write-tree → OID 기록 → commit-tree OID -p T -p feat
#   → 후보^{tree}==OID ∧ is-ancestor T 후보 아니면 abort → T 대비 삭제 파일은 feat 가 삭제한 것뿐(아니면 abort).
#   ★push 경로 없음★ — 이 스크립트는 후보 sha·검사 tree OID·T 를 «출력만» 한다(--dry-run 은 기본값, 받기만 한다). --push 는 usage 로 거부.
#   commit-tree 는 객체만 만들고 ref 는 건드리지 않는다. 충돌·fetch 실패·검증 불일치는 전부 abort(조용한 폴백 0).
#   exit 0 = 후보 확정 · 1 = ABORT(사유 stdout) · 2 = usage
#   FT_LAND_INJECT_S10=1 = «시험 전용» — 후보를 feat 트리로 만들어(S10 사고 재현) 검증이 abort 하는지 본다.
set -uo pipefail
FEAT="HEAD"; TARGET="main"; REMOTE="origin"; REPO=""
usage() { echo "usage: $0 --feat <ref> [--target main] [--remote origin] [--repo <dir>] [--dry-run]  (push 옵션 없음)" >&2; exit 2; }
while [ $# -gt 0 ]; do case "$1" in
  --feat) [ $# -ge 2 ] || usage; FEAT="$2"; shift 2;;
  --target) [ $# -ge 2 ] || usage; TARGET="$2"; shift 2;;
  --remote) [ $# -ge 2 ] || usage; REMOTE="$2"; shift 2;;
  --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2;;
  --dry-run) shift;;
  *) echo "unknown $1" >&2; usage;; esac; done
[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel)" || { echo "ABORT repo 를 찾을 수 없음"; exit 1; }
G() { git -C "$REPO" "$@"; }
abort() { echo "ABORT $*"; exit 1; }

G fetch --quiet "$REMOTE" "$TARGET" || abort "fetch $REMOTE $TARGET 실패"
T="$(G rev-parse --verify "refs/remotes/$REMOTE/$TARGET^{commit}")" || abort "T(refs/remotes/$REMOTE/$TARGET) 확인 실패"
F="$(G rev-parse --verify "$FEAT^{commit}")" || abort "feat($FEAT) 확인 실패"

if G merge-base --is-ancestor "$T" "$F"; then
  MODE=ff; OID="$(G rev-parse "$F^{tree}")"; CAND="$F"
else
  MODE=merge
  OUT="$(G merge-tree --write-tree "$T" "$F")"; rc=$?   # 첫 줄만 읽지 않는다 — 충돌이어도 1행에 OID 가 찍힌다(종료코드 따로)
  [ "$rc" -eq 0 ] || abort "merge-tree 충돌(rc=$rc) — 자동 병합 금지, arch 1줄 판정"
  OID="$(printf '%s\n' "$OUT" | head -n1)"
  TREE_FOR_CAND="$OID"; [ "${FT_LAND_INJECT_S10:-0}" = 1 ] && TREE_FOR_CAND="$(G rev-parse "$F^{tree}")"
  CAND="$(G commit-tree "$TREE_FOR_CAND" -p "$T" -p "$F" -m "[land-candidate] $FEAT -> $TARGET (T=${T:0:10})")" || abort "commit-tree 실패"
fi

[ "$(G rev-parse "$CAND^{tree}")" = "$OID" ] || abort "후보 tree != 검사 tree OID (S10 방어) cand=$CAND OID=$OID"
G merge-base --is-ancestor "$T" "$CAND" || abort "T 가 후보의 조상이 아님 cand=$CAND T=$T"
MB="$(G merge-base "$T" "$F")" || abort "merge-base 없음(무관 이력)"
BAD="$(comm -23 <(G diff --diff-filter=D --name-only "$T" "$CAND" | sort) <(G diff --diff-filter=D --name-only "$MB" "$F" | sort))"
[ -z "$BAD" ] || abort "feat 가 지우지 않은 파일이 후보에서 사라짐: $(echo "$BAD" | tr '\n' ' ')"

echo "LAND-CANDIDATE mode=$MODE T=$T OID=$OID CANDIDATE=$CAND feat=$F target=$REMOTE/$TARGET"
echo "DRY-RUN push 안 함 — 이 후보 sha 만 ⑤ 게이트로 넘긴다(수락·push 는 C7·C10 뒤)"
