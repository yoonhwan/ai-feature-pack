#!/usr/bin/env bash
# test_index_move_canon_team_list_r1628.sh — r1628: 팀 정본 목록(design/harness/CANON-FILES.txt)의 경로는 «착지 ref blob» 으로 실재·절을 본다.
#   ⓐ 목록 경로 통과(md·html · 작업 트리에 파일이 없어도) ⓑ 목록 밖 research 경로 = REJECT「팀 정본 목록에도 없다」
#   ⓒ 절 없음 REJECT(md·html) · 착지 ref 에 파일 없음 REJECT 「파일이 없다」 ⓓ docs/architect 갈래 회귀
#   ⓔ 착지 ref 없음·조회 실패 = REJECT 「판정 불가」 (파일 없음으로 읽지 않는다)
# 임시 git 리포·가짜 카드만 — 실 리포·실 indices·실 카드 쓰기 0 · sleep 0 · 사례 ≤70초
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../bin"; BB="${BASH_BIN:-bash}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { printf '%s' "$2" | grep -qF -- "$1"; }
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_SEATS_JSON FT_LAND_REF

"$BB" -n "$SRCDIR/ft-index-move-canon.sh" && ok "bash -n ft-index-move-canon.sh" || bad "bash -n ft-index-move-canon.sh"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
BIN="$T/bin"; mkdir -p "$BIN"
cp "$SRCDIR/ft-index-move-canon.sh" "$SRCDIR/ft-team-lib.sh" "$SRCDIR/ft_git_capped.py" "$BIN/"

WT="$T/repo"; mkdir -p "$WT/design/harness" "$WT/docs/architect"
G() { git -C "$WT" "$@"; }
G init -q -b main . && G config user.email t@t && G config user.name t
P=design/harness/research/ft-2.0/PLAN.md
H=design/harness/research/ft-2.0/core.html
N=design/harness/research/ft-2.0/GONE.md      # 목록에는 있고 착지 ref 에는 없는 경로
printf '%s\n%s\n%s\n' "$P" "$H" "$N" > "$WT/design/harness/CANON-FILES.txt"
printf '## 절A 제목\nv1\n' > "$WT/docs/architect/X.md"
G add -A && G commit -qm base
G checkout -q -b card                              # 카드 가지 = 작업 트리 — 정본은 main(착지 ref)에만 있다
G checkout -q main
mkdir -p "$WT/design/harness/research/ft-2.0"
printf '# PLAN\n\n## 운영 경로 1줄\n' > "$WT/$P"
printf '<html><body><h2>운영 경로 절</h2></body></html>\n' > "$WT/$H"
printf 'v2\n' >> "$WT/docs/architect/X.md"
G add -A && G commit -qm canon                     # 착지 S = 정본 3파일 등장 + docs/architect/X.md 갱신
S="$(G rev-parse HEAD)"
G checkout -q card
[ ! -f "$WT/$P" ] && [ ! -f "$WT/$H" ] && ok "작업 트리에 정본 3파일 없음(카드 가지)" || bad "작업 트리에 정본이 있다 — ⓐ 가 의미 없다"

card() { local f="$WT/design/harness/indices/진행/$1.md"; mkdir -p "$(dirname "$f")"
  { echo "# 인덱스: $1"; echo "## 상태"; echo "- $2"; echo "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)"; echo "- 설치: 없음"; } > "$f"; echo "$f"; }
gate() { "$BB" "$BIN/ft-index-move-canon.sh" "$1" "$WT" "$S" 2>&1 <<<"$2"; }   # $2 = 판정문 §절 본문
diff_ok() { echo "정본 diff 확인: $1 §$2 @$S — 시험"; }

# ⓐ1 목록 경로(md) — 작업 트리에 없고 착지 ref blob 에 있으면 OK
c="$(card ka "- 정본 갱신: $P §운영 경로")"; out="$(FT_LAND_REF=main gate "$c" "$(diff_ok "$P" 운영\ 경로)")"; rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -qx "OK	정본 $P §운영 경로" && ok "ⓐ1 목록 경로(md) 착지 ref blob → OK" || bad "ⓐ1 rc=$rc: $out"

# ⓐ2 목록 경로(html) — <h2> 글자로 절 확인
c="$(card kb "- 정본 갱신: $H §운영 경로 절")"; out="$(FT_LAND_REF=main gate "$c" "$(diff_ok "$H" '운영 경로 절')")"; rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -qx "OK	정본 $H §운영 경로 절" && ok "ⓐ2 목록 경로(html) <h2> 글자 → OK" || bad "ⓐ2 rc=$rc: $out"

# ⓑ 목록 밖 research 경로 — 지금 문구 + 「팀 정본 목록에도 없다」
c="$(card kc "- 정본 갱신: design/harness/research/ft-2.0/OTHER.md §아무절")"; out="$(FT_LAND_REF=main gate "$c" "")"; rc=$?
[ "$rc" = 0 ] && has "REJECT" "$out" && has "docs/architect/….md 여야 한다: design/harness/research/ft-2.0/OTHER.md" "$out" \
  && has "팀 정본 목록에도 없다" "$out" && ok "ⓑ 목록 밖 research 경로 → REJECT(목록에도 없다)" || bad "ⓑ rc=$rc: $out"

# ⓒ1·2 절 없음 — md·html 둘 다 「정본 문서에 그 절 제목이 없다」
c="$(card kd "- 정본 갱신: $P §없는절")"; out="$(FT_LAND_REF=main gate "$c" "")"
has "REJECT	정본 문서에 그 절 제목이 없다: $P §없는절" "$out" && ok "ⓒ1 목록 md 에 절 없음 → REJECT" || bad "ⓒ1: $out"
c="$(card ke "- 정본 갱신: $H §없는절")"; out="$(FT_LAND_REF=main gate "$c" "")"
has "REJECT	정본 문서에 그 절 제목이 없다: $H §없는절" "$out" && ok "ⓒ2 목록 html 에 절 없음 → REJECT" || bad "ⓒ2: $out"

# ⓒ3 목록 경로가 착지 ref 에 없음 — 「파일이 없다」 (조회 실패와 구분)
c="$(card kf "- 정본 갱신: $N §절")"; out="$(FT_LAND_REF=main gate "$c" "")"
has "REJECT	정본 갱신 줄의 파일이 없다(착지 ref main): $N" "$out" && ok "ⓒ3 착지 ref 에 파일 없음 → REJECT(파일이 없다)" || bad "ⓒ3: $out"

# ⓓ docs/architect 갈래 회귀 — 작업 트리 파일·«#» 머리줄 그대로 OK
c="$(card kg "- 정본 갱신: docs/architect/X.md §절A")"; out="$(FT_LAND_REF=main gate "$c" "$(diff_ok docs/architect/X.md 절A)")"
printf '%s' "$out" | grep -qx "OK	정본 docs/architect/X.md §절A" && ok "ⓓ docs/architect 갈래 회귀 0" || bad "ⓓ: $out"

# ⓔ1 착지 ref 없음 → 판정 불가
c="$(card kh "- 정본 갱신: $P §운영 경로")"; out="$(FT_LAND_REF=nosuch-ref gate "$c" "")"
has "REJECT	판정 불가 — 착지 ref nosuch-ref 조회 실패" "$out" && ok "ⓔ1 착지 ref 없음 → 판정 불가" || bad "ⓔ1: $out"

# ⓔ2 git 조회 실행 실패(rc=128) → 판정 불가(«파일 없음» 으로 읽지 않는다)
FG="$T/fakegit"; mkdir -p "$FG"
printf '#!/bin/sh\ncase "$*" in *cat-file*) exit 128;; esac\nexec %s "$@"\n' "$(command -v git)" > "$FG/git"; chmod 755 "$FG/git"
c="$(card ki "- 정본 갱신: $P §운영 경로")"; out="$(PATH="$FG:$PATH" FT_LAND_REF=main gate "$c" "")"
has "REJECT	판정 불가" "$out" && has "rc=128" "$out" && ok "ⓔ2 git 조회 실패 → 판정 불가" || bad "ⓔ2: $out"

# ⓔ3 경로 rev-parse 가 rc=128 로 실패 → 판정 불가 (없음 rc=1 과 구분 · 하드 룰 20)
FG2="$T/fakegit2"; mkdir -p "$FG2"; printf '#!/bin/sh\ncase "$*" in *rev-parse*main:*) exit 128;; esac\nexec %s "$@"\n' "$(command -v git)" > "$FG2/git"; chmod 755 "$FG2/git"
c="$(card kj "- 정본 갱신: $P §운영 경로")"; out="$(PATH="$FG2:$PATH" FT_LAND_REF=main gate "$c" "")"
has "판정 불가" "$out" && has "rc=128" "$out" && ! has "파일이 없다" "$out" && ok "ⓔ3 경로 rev-parse 실패(rc=128) → 판정 불가" || bad "ⓔ3: $out"
echo "fail=$fail"; [ "$fail" = 0 ]
