#!/usr/bin/env bash
# ft-wt-add.sh — 팀 좌석(master·arch)의 착지·카드·DA 워크트리를 나노와 같은 sparse 로 만든다 (r835 · master 154176 · planner 154162)
#   왜: sparse(r444)는 ft-nano-spawn 안에만 있어 팀 좌석이 맨손 `git worktree add` 로 만들면 풀 체크아웃(1.43GiB · 나노 0.24GiB) — 45분 4곳 6Gi.
#   쓰기: ft-wt-add.sh <이름> (--team <팀> [--also <경로>]… | --full <사유 10자 이상>) (-b <새 가지> [--base <ref>] | --branch <기존 가지>)
#     --team  : 패턴 = ft_sparse_patterns(ft-team-lib.sh) — 남의 팀 design/teams/<남>/ 제외 · --also 는 그 경로도(기준 ref 에 없는 경로 = REJECT)
#     --full  : 풀 체크아웃 · <루트>/.fable-team/state/wt-add-full.log 에 «시각 · 좌석 · 경로 · 사유» 1줄 · 둘 다 없으면 REJECT(추측 0)
#     표식   : <워크트리 gitdir>/ft-wt-mode = sparse | full <사유> (post-checkout 과 같은 파일 · 훅이 찍었으면 그대로)
#     -b      : 새 가지(--base 기본 origin/main) · --branch = 이미 있는 가지(다른 워크트리에 걸렸으면 git 문구 그대로 REJECT)
#   루트 = 호출 cwd 의 git «주 워크트리»(--git-common-dir 의 부모) · 폴더 = <루트>/.worktrees/<이름>
#   순서: add --no-checkout → sparse set → checkout(실패 시 2 s 뒤 재시도 · 최대 3회 · r831 과 같은 규칙) → info·.venv/.env 링크·shim-init(실패는 NOTE)
#   끝줄: WT <경로> sparse team=<팀> size=<KB>  |  WT <경로> full size=<KB>  · 되돌림: git -C <경로> sparse-checkout disable
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
USAGE="ft-wt-add.sh <이름> (--team <팀> [--also <경로>]… | --full <사유>) (-b <새 가지> [--base <ref>] | --branch <기존 가지>)"
die() { echo "REJECT $*"; exit 1; }
need() { [ -n "${2:-}" ] || die "$1 값이 없다 — $USAGE"; }

NAME="${1:-}"; [ $# -gt 0 ] && shift
case "$NAME" in ''|-*) die "이름이 없다 — $USAGE";; esac
printf '%s' "$NAME" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || die "이름은 영문·숫자·._- 만(슬래시 0): $NAME"
TEAM="" FULL="" FULL_SET="" NEWB="" OLDB="" BASE="origin/main"; ALSO=()
while [ $# -gt 0 ]; do
  case "$1" in
    --team)   need "$1" "${2:-}"; TEAM="$2"; shift 2;;
    --also)   need "$1" "${2:-}"; ALSO+=("$2"); shift 2;;
    --full)   FULL_SET=1; case "${2:-}" in ''|-*) shift;; *) FULL="$2"; shift 2;; esac;;
    -b)       need "$1" "${2:-}"; NEWB="$2"; shift 2;;
    --base)   need "$1" "${2:-}"; BASE="$2"; shift 2;;
    --branch) need "$1" "${2:-}"; OLDB="$2"; shift 2;;
    *) die "모르는 인자: $1 — $USAGE";;
  esac
done
if [ -n "$TEAM" ] && [ -n "$FULL_SET" ]; then die "--team 과 --full 은 하나만"; fi
if [ -z "$TEAM" ] && [ -z "$FULL_SET" ]; then die "--team <팀> 또는 --full <사유 10자 이상> 이 필요하다(추측 0) — $USAGE"; fi
if [ -n "$FULL_SET" ]; then
  n="$(python3 -c 'import sys; print(len(sys.argv[1].strip()))' "$FULL" 2>/dev/null)"
  [ "${n:-0}" -ge 10 ] || die "--full 사유는 10자 이상(지금 ${n:-0}자) — 풀 체크아웃은 1.43GiB · 보통은 --team <팀>"
  [ ${#ALSO[@]} -eq 0 ] || die "--also 는 --team 과만 쓴다(--full 은 이미 전부)"
fi
[ -z "$TEAM" ] || printf '%s' "$TEAM" | grep -Eq '^[a-z0-9][a-z0-9_-]*$' || die "팀 이름 꼴이 아니다: $TEAM"
if [ -n "$NEWB" ] && [ -n "$OLDB" ]; then die "-b 와 --branch 는 하나만"; fi
if [ -z "$NEWB" ] && [ -z "$OLDB" ]; then die "-b <새 가지> 또는 --branch <기존 가지> 가 필요하다 — $USAGE"; fi

GCD="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die "git 리포 안에서 실행해야 한다(cwd $PWD)"
ROOT="$(cd "$GCD/.." && pwd -P)" || die "주 워크트리를 못 풀었다: $GCD"
WT="$ROOT/.worktrees/$NAME"
[ ! -e "$WT" ] || die "이미 있다: $WT — 다른 이름으로"
BR="${NEWB:-$OLDB}"; REF="${NEWB:+$BASE}"; REF="${REF:-$OLDB}"
git -C "$ROOT" rev-parse -q --verify "$REF^{commit}" >/dev/null || die "기준을 못 찾았다: $REF"
for p in ${ALSO[@]+"${ALSO[@]}"}; do
  q="${p#/}"; q="${q%/}"
  [ -n "$q" ] && git -C "$ROOT" cat-file -e "$REF:$q" 2>/dev/null || die "--also 경로가 $REF 에 없다: $p"
done
if [ -n "$TEAM" ] && ! git -C "$ROOT" cat-file -e "$REF:design/teams/$TEAM" 2>/dev/null; then
  echo "NOTE design/teams/$TEAM/ 이 $REF 에 없다 — 남의 팀 폴더만 빠진다"
fi

# ① 워크트리(빈 채로) — 실패는 git 문구 그대로
ADD=(worktree add --no-checkout "$WT")
if [ -n "$NEWB" ]; then ADD+=(-b "$NEWB" "$BASE"); else ADD+=("$OLDB"); fi
out="$(git -C "$ROOT" "${ADD[@]}" 2>&1)" || {
  msg="$(grep -E '^(fatal|error):' <<<"$out" | head -1)"; die "worktree add 실패 — ${msg:-$(tail -1 <<<"$out")}"; }
# ② sparse 패턴(r444 와 같은 3줄 + --also)
if [ -n "$TEAM" ]; then
  # shellcheck source=/dev/null
  . "$HERE/ft-team-lib.sh" || die "ft-team-lib.sh 를 못 읽었다: $HERE · 워크트리 남김: $WT · 가지 $BR"
  ft_sparse_patterns "$TEAM" ${ALSO[@]+"${ALSO[@]}"} | git -C "$WT" sparse-checkout set --no-cone --stdin >/dev/null 2>&1 \
    || die "sparse set 실패 · 워크트리 남김: $WT · 가지 $BR — 사람 판정"
fi
# ③ 체크아웃 — 1회 실패면 2 s 뒤 다시(최대 3회)
#   --full 은 FT_WT_FULL 을 실어 보낸다 — BYZ post-checkout(r835)이 풀을 «선택» 으로 알고 sparse 로 바꾸지 않게(표식 full)
[ -z "$FULL_SET" ] || export FT_WT_FULL="$FULL"
for n in 1 2 3; do
  err="$(git -C "$WT" checkout -q 2>&1)" && break
  [ "$n" = 3 ] && die "체크아웃 3회 실패($(tail -1 <<<"$err")) · 워크트리 남김: $WT · 가지 $BR — 사람 판정"
  echo "RETRY checkout $n/3 실패 — 2 s 뒤 다시: $(tail -1 <<<"$err")"; sleep 2
done
# ④ 나노와 같은 꼴의 info · 링크 · 하네스 입구(ft-nano-spawn 436~441행)
printf '{"branch":"%s","base":"%s","base_sha":"%s","created_at":"%s","purpose":"%s"}\n' "$BR" "$REF" \
  "$(git -C "$ROOT" rev-parse --short "$REF")" "$(date '+%F %T')" "wt-add · ${TEAM:-full}" > "$WT/.worktree-info.json"
for l in .venv .env; do if [ -e "$ROOT/$l" ]; then ln -sfn "../../$l" "$WT/$l"; fi; done
LB="$(sed -n 1p "$ROOT/.fable-team/LIVE_BIN" 2>/dev/null)"
if [ -z "$LB" ]; then echo "NOTE shim-init 생략 — $ROOT/.fable-team/LIVE_BIN 없음"
else _o="$(bash "$HERE/ft-root-bin-shim.sh" --root "$WT" --live "$LB" --init 2>&1)" \
  && echo "$(tail -1 <<<"$_o") (shim-init $WT)" || echo "NOTE shim-init 실패: $(tail -1 <<<"$_o")"; fi
KB="$(du -sk "$WT" 2>/dev/null | cut -f1)"
# ⑤ 워크트리 표식(r835 · post-checkout 과 같은 파일) — 훅이 이미 찍었으면(BYZ) 그대로, 없으면(훅 없는 리포) 여기서 찍는다. 풀 로그도 같은 자리에서 1번만.
MARK="$(git -C "$WT" rev-parse --path-format=absolute --git-dir)/ft-wt-mode"
if [ -n "$FULL_SET" ]; then
  if [ ! -f "$MARK" ]; then
    printf 'full %s\n' "$FULL" > "$MARK"
    SEAT="${FT_SEAT:-$(tmux display-message -p '#S' 2>/dev/null)}"
    mkdir -p "$ROOT/.fable-team/state" \
      && printf '%s · %s · %s · %s\n' "$(date '+%F %T')" "${SEAT:-?}" "$WT" "$FULL" >> "$ROOT/.fable-team/state/wt-add-full.log"
  fi
  echo "WT $WT full size=$KB"
else
  [ -f "$MARK" ] || echo sparse > "$MARK"
  echo "WT $WT sparse team=$TEAM size=$KB"
fi
