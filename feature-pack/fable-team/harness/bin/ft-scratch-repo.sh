#!/usr/bin/env bash
# ft-scratch-repo.sh — 시험·검토용 «저장소 사본»을 통째 복사 대신 등록형 git worktree(--detach)로 만든다 (R246).
#   ft-scratch-repo.sh <sha|ref> [--repo <저장소>] [--full] [--with <경로>]…   사본 생성 → 경로 1줄 출력 · 등록 `.fable-team/state/scratch-repos.tsv`(경로·주인·시각)
#     r891: 기본 = sparse(no-cone) — `/*` 에서 `design/teams/*/` 와 `evidence/` 아래 미디어(wav·mp3·mp4·webm·mov·png·jpg·jpeg·gif·zip·tar·gz)만 뺀다(design/harness·bin·tests·feature-pack 은 들어 있음)
#           --full = 통째(옛 동작) · --with <경로> = 그 경로를 다시 넣음(반복 가능 · 미디어 제외는 그대로 — 미디어까지면 --full) · 재사용은 sha·주인·규칙 셋이 같을 때만
#     r891: 등록부 = ROOT 등록부 하나(--done·--sweep 이 읽는 곳 · --repo 가 다른 저장소여도 · 원 저장소 기준 등록부는 r897) · 주인 = FT_SCRATCH_OWNER → FT_ME → tmux 세션
#           등록은 체크아웃이 다 끝난 뒤 마지막 단계(기준판 순서) · worktree add·sparse 체크아웃 실패 = rc 4 · 생성은 아무것도 지우지 않는다(반쯤 만든 폴더 = --report --orphans · 자동 정리 = r897)
#   ft-scratch-repo.sh --report --orphans            r891: $FT_SCRATCH_DIR/repo-* 중 어느 등록부에도 없는 사본 표(경로·원 저장소·HEAD·크기·만든 시각·주인 추정) — 삭제 0
#     ROOT 등록부 + 사본들의 원 저장소 등록부(옛 판이 거기 적은 사본)를 읽는다(보고 전용 · 지우기 0) · 못 읽은 등록부는 «부분 읽기» 줄 · env FT_SCRATCH_MBOX(주인 추정용 mailbox.jsonl)
#   ft-scratch-repo.sh --done <경로>                 등록된 사본만 worktree 제거 + 등록 줄 삭제 (등록 밖 경로는 거부)
#     r845: 지우기 조건 = 장부의 «3열 · 정확히 같은 글자» 줄 ∧ 그 경로가 «분리(detached) git 워크트리» 둘 다 — 옛/깨진 줄(필드 수 ≠3 · 경로에 제어 문자)은 건너뛰고 WARN 1줄(지우기 0)
#     r7: 여기에 «그 줄 주인의 사본 자리(FT_SCRATCH_DIR 또는 $TMPDIR/ft-scratch/<주인>/) 아래» 를 더한다 — 남의 owner 폴더·자리 밖 경로는 건너뜀 + WARN(장부 줄도 그대로) · --sweep 도 같다
#     r7: 사본이 온전한지(요청 sha == HEAD ∧ git status 깨끗)는 체크아웃 훅 rc 와 «무관하게 항상» 확인 — 어긋나면 die 4 · 등록 0
#   ★r845 (오빠 결정 10-27 «tmp 에 임시를 쌓으면 재부팅에 정리된다»)★ 기본 생성 자리 = $TMPDIR/ft-scratch/<주인>/ (TMPDIR 없으면 /tmp/ft-scratch/<주인>/) — 임시 자리라 재부팅이 지운다.
#     장부는 «있으면 참고» — 등록 쓰기 실패는 WARN 1줄이고 사본은 그대로 쓸 수 있다(die 0) · 생성 경로(FT_SCRATCH_DIR·DEST)에 제어 문자(0x00–0x1F·0x7F)가 있으면 만들기 전에 rc2 거절
#     훅(post-checkout) 실패로 worktree add/checkout 이 rc≠0 이어도 DEST 가 «요청 sha 그대로 + status 깨끗» 이면 WARN + 경로 출력 rc0 · 아니면 지금처럼 die 4(등록 0 · 지우기 0)
#   ft-scratch-repo.sh --report [--summary]          «주인 없는 사본» 크기 목록 — 삭제 0. --summary = `주인 없는 임시 사본 N개 N.N GiB` 한 줄(0개면 출력 없음)
#   ft-scratch-repo.sh --sweep                       주인 없는 사본 정리(판정 1920): 첫 1회 = 목록 보고만(실삭제 0, 표식 scratch-sweep.armed) · 그 뒤부터 자동 삭제 · 지울 게 없으면 출력 0
#     r444: tmux 목록을 못 읽으면 stdout `ERROR tmux unreadable …` 1줄(호출자 ft-disk-alarm 이 planner 로) + 삭제 0 · 지운 뒤 로그 `swept=N owner-dead=N tmp=N held=N`
#     r548: 어떤 프로세스의 cwd(그 폴더 또는 그 아래)인 사본은 지우지 않고 붙잡는다 — 로그 `붙잡음 …` 줄 + stdout `[장비 정리] 주인 <좌석> 사본 <경로> 에서 pid <n> <명령> 실행 중 — 삭제 보류` 최대 3줄(나머지 개수 1줄)
#     r548: cwd 를 묻는 lsof 가 실패하거나 0줄이면 «아무도 안 씀» 으로 읽지 않는다 — 로그·stdout `ERROR lsof 실패 — 삭제 0` 1줄 + 이번 정리 전체 생략(등록 사본·tmp.* 포함)
#   ft-scratch-repo.sh --judged <경로>               «판정 끝난» 사본이면 rc 0 · 아니면 1 · 등록 사본 아님/없는 경로 2 — 사본 HEAD 가 main 에 착지했거나, 그 sha 앞 8자가 main 의 design/ 문서에 적혔고 그 문서 커밋이 AGE 분 지났을 때(삭제 0 · r-disk-drop-worktree-scratch-census)
#     r645: 그 «적혔나» 는 지금 main 한 트리 문자열 검색(`git grep -F`) + 7초 상한 — 전 히스토리 pickaxe 검색(RSS 1~1.7GB·1분+) 0. 초과·실패 = «판정 안 끝남»(rc 1) + WARN 1줄 · warn_many 전체 예산 FT_SCRATCH_JUDGE_BUDGET(기본 20초)
#   같은 주인의 «등록 사본» 이 3개를 넘게 살아 있으면 새로 만들 때 stderr WARN + 가장 오래된 «판정 끝난» 사본 경로(삭제는 좌석 손 — `--done <경로>`). env FT_SCRATCH_MAIN(판정 기준 ref · 기본 origin/main 있으면 그것 없으면 main)
#   ★cwd 로 쓰이는 사본은 두 종류 모두 삭제 0 + «붙잡음» 목록(경로·pid·명령·주인) — 붙잡힌 사본은 그 팀이 시험 장비를 정리해야 지워진다(오빠 10-20 «시험 끝 = 띄운 장비 정리»)★
#   «주인 없는 사본» = 등록 사본 중 주인 세션이 tmux 에 없고 «등록 뒤 FT_SCRATCH_AGE_MIN(1440분) 지난» 것(판정 1920 문구 · r444 의 나이 문턱 0 을 r548 이 되돌림 · tmux 목록 실패면 이 판정 생략) + TMPDIR `tmp.*` 중 FT_SCRATCH_AGE_MIN 지나고 내 소유이며 어떤 프로세스의 cwd 도 아닌 것
#   같은 sha·같은 주인의 등록 사본이 디스크에 있으면 새로 만들지 않고 그 경로를 다시 준다(r444).
#   env: FT_RES_ROOT · FT_SCRATCH_DIR(사본 부모, 기본 $TMPDIR) · FT_SCRATCH_OWNER(주인, 기본 현재 tmux 세션)
#        FT_TMUX_BIN(기본 PATH → /opt/homebrew/bin → /usr/local/bin — launchd PATH 엔 homebrew 가 없다 · r444) · FT_TMUX_SOCKET(있으면 -S) · FT_TMUX_TMPDIR(있으면 TMUX_TMPDIR)
#        FT_SCRATCH_JUDGE_BUDGET(판정 예산 초 · 기본 20 — 넘으면 남은 사본은 판정 안 함 · r645)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_RES_ROOT:-}"   # r385: 리포 공용 루트 = env → ft_repo_root(옛 설치 꼴 · cwd) → ERROR (새 설치본이 git 밖이라 자기 위치로 풀지 않는다)
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 3
STATE="$ROOT/.fable-team/state"; TSV="$STATE/scratch-repos.tsv"; ARMED="$STATE/scratch-sweep.armed"; SLOG="$STATE/scratch-sweep.log"; AGE="${FT_SCRATCH_AGE_MIN:-1440}"
TIMEOUT_BIN=""; command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN="$(command -v gtimeout)"; [ -n "$TIMEOUT_BIN" ] || { command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN="$(command -v timeout)"; }
TMO=""; [ -z "$TIMEOUT_BIN" ] || TMO="$TIMEOUT_BIN 7"
JUDGE_TMO=7   # r645: judged 1회 검색 상한(초) — warn_many 가 남은 예산으로 줄여 넘긴다
bounded() { # <초> <명령…> → 상한 초과 = rc 124 (timeout/gtimeout 없으면 자식을 직접 죽인다 — macOS 기본엔 없다)
  local secs="$1" p w rc; shift
  [ -z "$TIMEOUT_BIN" ] || { "$TIMEOUT_BIN" "$secs" "$@"; return $?; }
  "$@" & p=$!
  ( sleep "$secs"; kill -TERM "$p" 2>/dev/null ) & w=$!
  wait "$p"; rc=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  [ "$rc" -lt 124 ] || return 124
  return "$rc"
}
die() { echo "ERROR $1" >&2; exit "${2:-1}"; }
TMUX_BIN="${FT_TMUX_BIN:-$(command -v tmux 2>/dev/null)}"
for _t in /opt/homebrew/bin/tmux /usr/local/bin/tmux; do [ -n "$TMUX_BIN" ] || { [ -x "$_t" ] && TMUX_BIN="$_t"; }; done
[ -z "${FT_TMUX_TMPDIR:-}" ] || export TMUX_TMPDIR="$FT_TMUX_TMPDIR"
tmux_sessions() { [ -n "$TMUX_BIN" ] || return 127; "$TMUX_BIN" ${FT_TMUX_SOCKET:+-S "$FT_TMUX_SOCKET"} list-sessions -F '#{session_name}' 2>/dev/null; }
mkdir -p "$STATE" 2>/dev/null || die "상태 폴더 생성 실패: $STATE" 4
# r939 H1: «곧 끝나는 일» 자기 등록 — 승계(retire)가 이 사본 생성을 죽이지 않고 후계에게 넘긴다(장부 state/bg-finite.tsv)
bash "$HERE/ft-bg-finite.sh" register "${FT_SEAT:--}" "${FT_BG_FINITE_SCRATCH_SEC:-1200}" "$$" "ft-scratch-repo.sh $*" >/dev/null 2>&1 || true   # 등록 실패 = 넘김 대상 아님(오늘과 같은 reap) — 도구 stdout 계약을 흔들지 않는다
trap 'bash "$HERE/ft-bg-finite.sh" unregister $$ >/dev/null 2>&1 || true' EXIT
gib() { awk -v k="$1" 'BEGIN{ if (k ~ /^[0-9]+$/) printf "%.2f", k/1048576; else printf "?" }'; }
kb()  { $TMO du -sk "$1" 2>/dev/null | awk '{print $1}'; }
has_ctl() { # r845: <글자> 에 제어 문자(0x00-0x1F·0x7F)가 있으면 0 — 경로가 장부 줄을 깨뜨리는 길을 입구에서 닫는다
  case "$1" in *[[:cntrl:]]*) return 0;; esac; return 1
}
reg_has() { # r845: <경로> → 0 = 장부에 «3열 · 정확히 같은 글자» 줄이 있다(정규식 0 · 옛 줄 해석 0)
  P="$1" awk 'BEGIN{FS="\t"; p=ENVIRON["P"]} NF==3 && $1==p {f=1} END{exit !f}' "$TSV" 2>/dev/null
}
drop_reg() { P="$1" awk 'BEGIN{FS="\t"; p=ENVIRON["P"]} !(NF==3 && $1==p)' "$TSV" > "$TSV.tmp.$$" 2>/dev/null && mv "$TSV.tmp.$$" "$TSV"; }
reg_owner() { # r845 r7: <경로> → 장부 «3열 · 같은 글자» 줄의 주인(2열) · 없으면 빈 글자
  P="$1" awk 'BEGIN{FS="\t"; p=ENVIRON["P"]} NF==3 && $1==p {print $2; exit}' "$TSV" 2>/dev/null
}
owner_base() { # r845 r7: <주인> → 그 주인의 사본 자리(생성 때 쓰는 BASE 와 같은 규칙 · FT_SCRATCH_DIR 이 있으면 그것 하나)
  if [ -n "${FT_SCRATCH_DIR:-}" ]; then printf '%s\n' "${FT_SCRATCH_DIR%/}"; return; fi
  local t="${TMPDIR:-/tmp}"; printf '%s/ft-scratch/%s\n' "${t%/}" "$1"
}
under_base() { # r845 r7: <경로> <부모> → 0 = 그 경로가 부모 «아래»다(폴더 경계 · 실경로로 대조 — /var↔/private 정규화)
  local b p
  b="$(cd "$2" 2>/dev/null && pwd -P)" || return 1
  p="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  case "$p" in "$b"/*) return 0;; esac
  return 1
}
own_wt() { # r845: <경로> → 0 = 그 경로가 «분리(detached)» git 워크트리(장부에 적힌 글자만으로는 지우지 않는다)
  local b; b="$(bounded 7 git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  [ "$b" = HEAD ]
}
rm_copy() { git -C "$1" worktree remove --force "$1" 2>/dev/null || rm -r -f "$1" || return 1; }   # 등록 사본·24h 지난 내 tmp.* 만 호출된다(판정 1920)
registered() { # <경로> → 0 = 등록부에 있음(실경로로 대조 — git 은 /private/var 로, 등록부는 $TMPDIR 의 /var 로 적는다)
  local want p rest; want="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  while IFS="$(printf '\t')" read -r p rest; do [ -d "$p" ] && [ "$(cd "$p" && pwd -P)" = "$want" ] && return 0; done < <(cat "$TSV" 2>/dev/null)
  return 1
}
common_root() { # <git 경로> → 원 저장소 공용 루트(사본·워크트리여도 원 저장소) · 못 읽으면 rc 1 (r891)
  local d; d="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  case "$d" in */.git) printf '%s\n' "${d%/.git}";; *) printf '%s\n' "$d";; esac
}
copy_reg() { # <사본> → 그 사본의 원 저장소 등록부(워크트리 .git 파일의 gitdir 로) · 원 저장소에 .fable-team/ 없으면 rc 1 (r891 · --report --orphans 보고 전용 읽기)
  local l g; [ -f "$1/.git" ] && read -r l < "$1/.git" || return 1; g="${l#gitdir: }"
  case "$g" in */.git/worktrees/*) g="${g%%/.git/worktrees/*}";; *) return 1;; esac
  [ -d "$g/.fable-team" ] && printf '%s/.fable-team/state/scratch-repos.tsv\n' "$g"
}
SPARSE_EXT="wav mp3 mp4 webm mov png jpg jpeg gif zip tar gz"
want_spec() { # → 요청한 체크아웃 규칙(sparse-checkout list 와 같은 꼴) · --full 이면 FULL (r891)
  [ "$FULL" = 0 ] || { echo FULL; return; }
  printf '%s\n' '/*' '!/design/teams/*/'; for e in $SPARSE_EXT; do printf '!**/evidence/**/*.%s\n' "$e"; done; printf '%s' "$WITH"
}
spec_of() { # <사본> → 그 사본의 체크아웃 규칙 · sparse 아니면 FULL — 재사용은 규칙이 같을 때만(sparse 사본을 --full 요청에 돌려주지 않는다)
  if [ "$(git -C "$1" config --bool --get core.sparseCheckout 2>/dev/null)" = true ]; then git -C "$1" sparse-checkout list 2>/dev/null; else echo FULL; fi
}
guess_owner() { # <sha8> → 주인 추정(r891 ⓘ): 그 sha 를 처음 적은 mbox 쪽지 «#seq 보낸->받는» · 없으면 그 sha 를 적은 main design 파일 · 둘 다 없으면 «모름» (각 7초 상한)
  local h="$1" mb="${FT_SCRATCH_MBOX:-$ROOT/.fable-team/comm/mailbox.jsonl}" m hit=""
  [ -f "$mb" ] && hit="$(bounded 7 grep -m1 -F "$h" "$mb" 2>/dev/null | sed -n 's/.*"seq": *\([0-9]*\).*"to": *"\([^"]*\)".*"from": *"\([^"]*\)".*/mbox #\1 \3->\2/p')"
  if [ -z "$hit" ]; then m="${FT_SCRATCH_MAIN:-}"; [ -n "$m" ] || { git -C "$ROOT" rev-parse -q --verify origin/main >/dev/null 2>&1 && m=origin/main || m=main; }
    hit="$(bounded 7 git -C "$ROOT" grep -F -l "$h" "$m" -- design 2>/dev/null | awk 'NR==1{sub(/^[^:]*:/,""); print "파일 " $0}')"; fi
  printf '%s\n' "${hit:-모름}"
}
scratch_bases() { # r845: 사본이 놀 수 있는 부모 폴더 — FT_SCRATCH_DIR 가 있으면 그 하나, 없으면 $TMPDIR 과 그 아래 ft-scratch/<주인>/
  local t
  if [ -n "${FT_SCRATCH_DIR:-}" ]; then printf '%s\n' "${FT_SCRATCH_DIR%/}"; return; fi
  t="${TMPDIR:-/tmp}"; t="${t%/}"
  printf '%s\n' "$t"
  for _b in "$t"/ft-scratch/*; do [ -d "$_b" ] && printf '%s\n' "$_b"; done
}
unregistered_copies() { # r891 ⓘ: $FT_SCRATCH_DIR/repo-* 중 어느 등록부(ROOT + 사본들의 원 저장소)에도 없는 사본 표 — ★보고만 · 지우기 0★ · 못 읽은 등록부 = «부분 읽기» 줄
  local f b p rest rows keys="" failed="" n h root sha ep me
  for f in $( { printf '%s\n' "$TSV"; while IFS= read -r b; do for p in "$b"/repo-*; do [ -d "$p" ] && copy_reg "$p"; done; done <<EOF
$(scratch_bases)
EOF
} | awk '!s[$0]++'); do
    [ -e "$f" ] || continue
    if rows="$(cat -- "$f" 2>/dev/null)"; then
      while IFS="$(printf '\t')" read -r p rest; do [ -d "$p" ] && keys="$keys$(cd "$p" && pwd -P)
"; done <<EOF
$rows
EOF
    else failed="$failed$f
"; fi
  done
  printf '경로\t원 저장소\tHEAD\t크기 GiB\t만든 시각\t주인 추정\n'
  while IFS= read -r b; do for p in "$b"/repo-*; do
    [ -d "$p" ] || continue
    me="$(cd "$p" && pwd -P)"; case "
$keys" in *"
$me
"*) continue;; esac
    n="${p##*/}"; h="$(printf '%s' "$n" | cut -d- -f2)"; ep="$(printf '%s' "$n" | cut -d- -f3)"
    root="$(common_root "$p")" || root="못 읽음"; sha="$(git -C "$p" rev-parse HEAD 2>/dev/null)" || sha="-"
    case "$ep" in ''|*[!0-9]*) ep="-";; *) ep="$(date -r "$ep" '+%F %H:%M' 2>/dev/null || echo -)";; esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "$root" "$sha" "$(gib "$(kb "$p")")" "$ep" "$(guess_owner "$h")"
  done; done <<EOF
$(scratch_bases)
EOF
  printf '%s' "$failed" | awk 'NF{print "부분 읽기\t등록부 읽기 실패 — 그 등록부 사본은 «미등록» 으로 보일 수 있음\t" $0}'
}
judged() { # <경로> → 0 = 판정 끝남(착지됐거나 판정문에 적히고 AGE 분 지남)
  local sha h8 m ct f oldest="" out rc tmo="${JUDGE_TMO:-7}"
  sha="$(git -C "$1" rev-parse HEAD 2>/dev/null)" || return 1; h8="${sha:0:8}"
  m="${FT_SCRATCH_MAIN:-}"; [ -n "$m" ] || { git -C "$ROOT" rev-parse -q --verify origin/main >/dev/null 2>&1 && m=origin/main || m=main; }
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 1   # 판정 기준 트리가 없으면 «안 끝남»(환경 없음 — WARN 아님)
  git -C "$ROOT" merge-base --is-ancestor "$sha" "$m" 2>/dev/null && return 0
  # r645: 히스토리 전수 pickaxe 대신 «지금 main 한 트리 · design 경로 한정» 문자열 검색 + 상한(초과·실패 = 조용한 «끝남» 0)
  out="$(bounded "$tmo" git -C "$ROOT" grep -F -l "$h8" "$m" -- design 2>/dev/null)"; rc=$?
  case "$rc" in
    0) ;;
    1) return 1;;   # 판정문에 그 sha 8자 없음 = 판정 안 끝남
    124) echo "WARN ft-scratch-repo judged — 시간 초과(${tmo}s) · 판정 안 끝남 $1" >&2; return 1;;
    *) echo "WARN ft-scratch-repo judged — git grep 실패(rc=$rc) · 판정 안 끝남 $1" >&2; return 1;;
  esac
  while IFS= read -r f; do   # 걸린 문서의 «마지막 커밋 시각» 중 가장 이른 것 = 보수 쪽(더 늦게 끝남)
    [ -n "$f" ] || continue
    f="${f#"$m":}"   # rev 를 준 git grep 은 «<ref>:<경로>» 로 적는다
    ct="$(bounded "$tmo" git -C "$ROOT" log -1 --format=%ct "$m" -- "$f" 2>/dev/null)"
    case "$ct" in ''|*[!0-9]*) echo "WARN ft-scratch-repo judged — 마지막 커밋 시각 못 읽음 · 판정 안 끝남 $f" >&2; return 1;; esac
    [ -n "$oldest" ] && [ "$ct" -ge "$oldest" ] || oldest="$ct"
  done <<EOF
$out
EOF
  [ -n "$oldest" ] && [ $(( $(date +%s) - oldest )) -ge $((AGE*60)) ]
}
warn_many() { # <주인> — 등록 사본(디스크에 있는 것) > 3 이면 WARN + 가장 오래된 «판정 끝난» 사본 (r645: 판정 예산 FT_SCRATCH_JUDGE_BUDGET 초 · 넘으면 남은 사본은 판정 안 함)
  local o="$1" n=0 p ow t oldest="" budget="${FT_SCRATCH_JUDGE_BUDGET:-20}" dl over=0
  dl=$(( $(date +%s) + budget ))
  while IFS="$(printf '\t')" read -r p ow t; do
    [ "$ow" = "$o" ] && [ -d "$p" ] || continue
    n=$((n+1))
    [ -z "$oldest" ] && [ "$over" = 0 ] || continue
    JUDGE_TMO=$(( dl - $(date +%s) )); [ "$JUDGE_TMO" -gt 7 ] && JUDGE_TMO=7
    if [ "$JUDGE_TMO" -le 0 ]; then over=1; else judged "$p" && oldest="$p"; fi
  done < <(cat "$TSV" 2>/dev/null)
  JUDGE_TMO=7
  [ "$n" -gt 3 ] || return 0
  [ "$over" = 0 ] || echo "WARN ft-scratch-repo — 판정 예산(${budget}초) 초과 · 남은 사본은 판정 안 함" >&2
  echo "WARN 주인 $o 의 등록 사본이 ${n}개 — 가장 오래된 «판정 끝난» 사본: ${oldest:-없음(판정 끝난 사본 0)}${oldest:+ (삭제는 좌석 손: ft-scratch-repo.sh --done $oldest)}" >&2
}
CWDROWS=""; HPID=""; HCMD=""   # r548: lsof 결과(경로·pid·명령) 1회 파싱분 · cwd_holder 의 출력 자리
cwd_holder() { # <폴더> → 0 = 어떤 프로세스가 그 폴더 «또는 그 아래» 를 cwd 로 쓴다(폴더 경계 비교) · HPID/HCMD 에 그 프로세스 첫 줄 · 없으면 1
  local d="$1" p pid cmd
  HPID=""; HCMD=""
  while IFS="$(printf '\t')" read -r p pid cmd; do
    case "$p" in "$d"|"$d"/*) HPID="$pid"; HCMD="$cmd"; return 0;; esac
  done <<EOF
$CWDROWS
EOF
  return 1
}
held_report() { # r548: 붙잡은 사본 = 로그 «붙잡음» 줄 전부 + stdout «[장비 정리]» 최대 3줄 + «…외 N건»
  local k p ty why own pid cmd i=0
  while IFS="$(printf '\t')" read -r k p ty why own pid cmd; do
    [ -n "$p" ] || continue
    i=$((i+1))
    printf '%s 붙잡음 %s (pid %s %s · 주인 %s)\n' "$(date +%F)" "$p" "$pid" "$cmd" "$own" >> "$SLOG"
    [ "$i" -le 3 ] && echo "[장비 정리] 주인 $own 사본 $p 에서 pid $pid $cmd 실행 중 — 삭제 보류"
  done <<EOF
$HOLD
EOF
  [ "$HELD" -le 3 ] || echo "[장비 정리] …외 $((HELD-3)) 건"
}
orphans() { # → ORPH = "kb<TAB>경로<TAB>reg|tmp<TAB>사유" 줄들 · HOLD = "kb<TAB>경로<TAB>reg|tmp<TAB>사유(붙잡음)·…<TAB>주인<TAB>pid<TAB>명령" · N · K · HELD · TMUX_OK · LSOF_OK
  local SESS p o t d TD now RAW; ORPH=""; HOLD=""; N=0; K=0; HELD=0; TMUX_OK=1; LSOF_OK=1; now="$(date +%s)"
  add() { ORPH="$ORPH$1	$2	$3	$4
"; N=$((N+1)); case "$1" in ''|*[!0-9]*) ;; *) K=$((K+$1));; esac; }
  hold() { HOLD="$HOLD$1	$2	$3	$4	$5	$6	$7
"; HELD=$((HELD+1)); }
  # r548: «누가 이 폴더를 cwd 로 쓰나» 를 한 번($TMO lsof -Fpcn)만 묻고 등록 사본·tmp 둘 다에 쓴다. 실패(rc≠0)하거나 0줄이면 «아무도 안 씀» 으로 읽지 않고 이번 판정 전체를 접는다(조용한 통과 0).
  RAW="$($TMO lsof -w -d cwd -Fpcn 2>/dev/null)" || LSOF_OK=0
  [ -n "$RAW" ] || LSOF_OK=0
  if [ "$LSOF_OK" = 0 ]; then echo "ERROR lsof 실패 — 삭제 0 (cwd 판정 불가)" >&2; return 0; fi
  CWDROWS="$(printf '%s\n' "$RAW" | awk '/^p/{pid=substr($0,2);next} /^c/{cmd=substr($0,2);next} /^n/{if (pid!="") printf "%s\t%s\t%s\n", substr($0,2), pid, cmd}')"
  # 등록 사본: tmux 목록을 못 읽으면(rc≠0) «세션 0» 으로 세지 않고 이 판정 전체를 건너뛴다(#0 RULE) · 후보 = 주인 없음 ∧ 등록 뒤 AGE 분 지남(판정 1920 문구 · r548 이 r444 의 문턱 0 을 되돌림)
  if SESS="$(tmux_sessions)"; then
    while IFS="$(printf '\t')" read -r p o t; do
      [ -n "$p" ] && [ -d "$p" ] || continue
      # r845: 경로에 제어 문자 = 장부 줄이 깨진 것 — 해석 0(지우기 0) · 필드 수 ≠3(옛 줄)도 건너뛴다 · 분리 워크트리 아니면 지우지 않는다
      if has_ctl "$p"; then echo "WARN ft-scratch-repo — 장부 줄의 경로에 제어 문자 — 건너뜀(지우기 0): $(printf '%q' "$p")" >&2; continue; fi
      if has_ctl "$t"; then echo "WARN ft-scratch-repo — 장부의 옛/깨진 줄(필드 수 ≠3) — 건너뜀(지우기 0): $p" >&2; continue; fi
      printf '%s\n' "$SESS" | grep -qx -- "$o" && continue
      case "$t" in ''|*[!0-9]*) echo "ERROR 등록표 3열이 숫자 아님 — 삭제 0 (경로 $p · 3열 '${t}')" >&2; continue;; esac
      [ $((now - t)) -ge $((AGE*60)) ] || continue
      if ! own_wt "$p"; then echo "WARN ft-scratch-repo — 장부에 있으나 분리(detached) 워크트리가 아님 — 건너뜀(삭제 0): $p" >&2; continue; fi
      # r845 r7: 그 줄 주인의 사본 자리 아래가 아니면 지우지 않는다(남의 owner 폴더·폴더 밖 줄 = 장부 줄도 그대로)
      under_base "$p" "$(owner_base "$o")" || { echo "WARN ft-scratch-repo — 주인($o) 사본 자리 밖 등록 사본 — 건너뜀(삭제 0): $p" >&2; continue; }
      if cwd_holder "$p"; then hold "$(kb "$p")" "$p" reg "등록 사본 · 주인 $o 없음 · 붙잡음 pid $HPID $HCMD" "$o" "$HPID" "$HCMD"
      else add "$(kb "$p")" "$p" reg "등록 사본 · 주인 $o 없음"; fi
    done < <(cat "$TSV" 2>/dev/null)
  else TMUX_OK=0; echo "ERROR tmux 목록 실패 — 등록 사본 판정 생략 (tmux=${TMUX_BIN:-없음})" >&2; fi
  TD="${TMPDIR:-/tmp}"; TD="${TD%/}"
  for d in $(find "$TD" -maxdepth 1 -type d -name 'tmp.*' -user "$(id -un)" -mmin +"$AGE" 2>/dev/null); do
    if cwd_holder "$d"; then hold "$(kb "$d")" "$d" tmp "TMPDIR tmp.* ${AGE}분 지남 · 붙잡음 pid $HPID $HCMD" "-" "$HPID" "$HCMD"
    else add "$(kb "$d")" "$d" tmp "TMPDIR tmp.* ${AGE}분 지남"; fi
  done
}

case "${1:-}" in
  --done)
    P="${2:-}"; [ -n "$P" ] && reg_has "$P" || die "등록된 사본이 아님: ${P:-<없음>}" 2
    # r845 r7: 지우기 세 조건 «모두» — ① 그 줄 주인의 사본 자리 아래 ② 장부 3열 같은 글자(위 reg_has) ③ 분리 워크트리
    OW="$(reg_owner "$P")"; OB="$(owner_base "$OW")"
    under_base "$P" "$OB" || { echo "WARN ft-scratch-repo — 주인(${OW:-모름}) 사본 자리($OB) 밖 등록 사본 — 건너뜀(삭제 0): $P" >&2; die "사본 자리 밖 — 삭제 0: $P" 2; }
    own_wt "$P" || die "장부에 있으나 분리(detached) 워크트리가 아님 — 삭제 0: $P" 2   # r845: 장부 글자만으로는 지우지 않는다
    rm_copy "$P" || die "제거 실패: $P" 4; drop_reg "$P"; echo "DONE $P";;
  --judged)
    P="${2:-}"; [ -n "$P" ] && [ -d "$P" ] && registered "$P" || die "등록된 사본이 아님: ${P:-<없음>}" 2
    judged "$P"; exit $?;;
  --report)
    [ "${2:-}" != --orphans ] || { unregistered_copies; exit 0; }
    orphans
    if [ "${2:-}" = --summary ]; then [ "$N" = 0 ] || printf '주인 없는 임시 사본 %s개 %s GiB\n' "$N" "$(gib "$K")"
    else printf '%s%s' "$ORPH" "$HOLD" | awk -F'\t' '$2!=""{k=$1; if (k !~ /^[0-9]+$/) k=0; printf "%s\t%s\t%s\n", sprintf("%.2f", k/1048576), $2, $4}'; fi;;   # r548: 붙잡은 사본도 «붙잡음 pid …» 칸으로 보인다 · --summary 는 지울 수 있는 것만 센다
  --sweep)
    orphans
    # r548: cwd 를 못 물으면 «아무도 안 씀» 으로 읽지 않는다 — 로그·stdout ERROR 1줄 + 삭제 0(등록 사본·tmp.* 포함)
    if [ "$LSOF_OK" = 0 ]; then printf '%s ERROR lsof 실패 — 삭제 0\n' "$(date +%F)" >> "$SLOG"
      echo "ERROR lsof 실패 — 임시 사본 정리 생략·삭제 0 (cwd 판정 불가)"; exit 0; fi
    # r444: launchd 에서 tmux 를 못 읽으면 «생략» 으로 조용히 끝내지 않는다 — stdout 1줄(호출자가 planner 쪽지로) + 삭제 0(tmp.* 포함)
    if [ "$TMUX_OK" = 0 ]; then printf '%s ERROR tmux unreadable — 삭제 0 (tmux=%s)\n' "$(date +%F)" "${TMUX_BIN:-없음}" >> "$SLOG"
      echo "ERROR tmux unreadable — 임시 사본 정리 생략·삭제 0 (tmux=${TMUX_BIN:-없음} · FT_TMUX_BIN/FT_TMUX_SOCKET 확인)"; exit 0; fi
    [ "$HELD" = 0 ] || held_report   # r548: 붙잡은 사본은 지우지 않고 알린다(삭제 후보 0 이어도 알린다)
    [ "$N" != 0 ] || exit 0
    if [ ! -f "$ARMED" ]; then date +%s > "$ARMED"; printf '%s [목록 보고 · 실삭제 0] %s개 %s GiB\n%s' "$(date +%F)" "$N" "$(gib "$K")" "$ORPH" >> "$SLOG"
      printf '[임시 사본 목록 보고 · 실삭제 0 · 다음 정리부터 자동] 주인 없는 사본 %s개 %s GiB: %s\n' "$N" "$(gib "$K")" "$(printf '%s' "$ORPH" | awk -F'\t' 'NR<=3{printf "%s%s", (NR>1?", ":""), $2}')"; exit 0; fi
    DEL=0; DK=0; DREG=0
    while IFS="$(printf '\t')" read -r k p ty why; do
      [ -n "$p" ] || continue
      if rm_copy "$p"; then DEL=$((DEL+1)); case "$k" in ''|*[!0-9]*) ;; *) DK=$((DK+k));; esac; [ "$ty" != reg ] || { drop_reg "$p"; DREG=$((DREG+1)); }; printf '%s 삭제 %s (%s)\n' "$(date +%F)" "$p" "$why" >> "$SLOG"
      else echo "ERROR 삭제 실패: $p" >&2; fi
    done <<EOF
$ORPH
EOF
    printf '%s swept=%s owner-dead=%s tmp=%s held=%s\n' "$(date +%F)" "$DEL" "$DREG" "$((DEL-DREG))" "$HELD" >> "$SLOG"
    [ "$DEL" = 0 ] || printf '[임시 사본 자동 삭제] 주인 없는 사본 %s개 %s GiB 삭제(되살릴 수 있는 사본만) — 목록: .fable-team/state/scratch-sweep.log\n' "$DEL" "$(gib "$DK")";;
  -*|"") die "usage: ft-scratch-repo.sh <sha|ref> [--repo <저장소>] [--full] [--with <경로>]… | --done <경로> | --judged <경로> | --report [--summary|--orphans] | --sweep" 2;;
  *)
    REF="$1"; shift; SRC="$(git rev-parse --show-toplevel 2>/dev/null)"; FULL=0; WITH=""
    while [ $# -gt 0 ]; do case "$1" in
      --repo) [ $# -ge 2 ] || die "--repo 뒤에 저장소가 없다" 2; SRC="$2"; shift 2;;
      --full) FULL=1; shift;;
      --with) [ $# -ge 2 ] && [ -n "$2" ] || die "--with 뒤에 경로가 없다" 2; P="${2#/}"; WITH="$WITH/${P%/}
"; shift 2;;
      *) die "모르는 인자: $1" 2;;
    esac; done
    [ -n "$SRC" ] || die "저장소를 못 찾음(--repo 필요)" 2
    SHA="$(git -C "$SRC" rev-parse --verify -q "$REF^{commit}")" || die "ref 를 못 찾음: $REF" 2
    OWNER="${FT_SCRATCH_OWNER:-${FT_ME:-$(tmux display-message -p '#S' 2>/dev/null || echo -)}}"
    case "$OWNER" in ''|-) die "주인 세션을 모른다(tmux 밖 · FT_SCRATCH_OWNER·FT_ME 없음) — 주인 모르는 사본은 만들지 않는다" 2;; esac
    # r845 입구 거절: 경로에 제어 문자(탭·줄바꿈 등)가 있으면 사본·장부를 «만들기 전에» 끝낸다 — 장부 줄이 깨져 남의 폴더를 가리키는 길을 닫는다
    has_ctl "${FT_SCRATCH_DIR:-}" && die "FT_SCRATCH_DIR 에 제어 문자(탭·줄바꿈 등) — 사본·장부를 만들지 않는다: $(printf '%q' "$FT_SCRATCH_DIR")" 2
    has_ctl "$OWNER" && die "주인 이름에 제어 문자 — 사본·장부를 만들지 않는다: $(printf '%q' "$OWNER")" 2
    SPEC="$(want_spec)"
    while IFS="$(printf '\t')" read -r p ow t; do   # r444: 같은 sha·같은 주인 사본이 살아 있으면 재사용(사본 0 추가) · r891: 체크아웃 규칙도 같을 때만
      [ "$ow" = "$OWNER" ] && [ -d "$p" ] && [ "$(git -C "$p" rev-parse HEAD 2>/dev/null)" = "$SHA" ] && [ "$(spec_of "$p")" = "$SPEC" ] && { echo "$p"; exit 0; }
    done < <(cat "$TSV" 2>/dev/null)
    if [ -n "${FT_SCRATCH_DIR:-}" ]; then BASE="${FT_SCRATCH_DIR%/}"; else BASE="${TMPDIR:-/tmp}"; BASE="${BASE%/}/ft-scratch/$OWNER"; fi   # r845: 임시 자리(재부팅이 지운다)
    has_ctl "$BASE" && die "사본 부모 경로에 제어 문자 — 사본·장부를 만들지 않는다: $(printf '%q' "$BASE")" 2
    mkdir -p "$BASE" 2>/dev/null || die "사본 부모 폴더 생성 실패: $BASE" 4
    DEST="${BASE%/}/repo-$(printf '%.8s' "$SHA")-$(date +%s)-$$"
    has_ctl "$DEST" && die "사본 경로에 제어 문자 — 사본·장부를 만들지 않는다: $(printf '%q' "$DEST")" 2
    # r845: 체크아웃 훅(post-checkout 등)이 죽어도 «그 sha 워크트리가 온전히 생겼으면» 사본은 쓸 수 있다 — status 깨끗할 때만 인정(반쯤 = 파일 누락·필터 실패는 거절)
    verify_complete() { # r845 r7: → 0 = DEST 가 «요청 sha 그대로 + status 깨끗»(필터가 파일을 빠뜨리면 status 가 깨끗하지 않다)
      local h st
      [ -d "$DEST" ] || return 1
      h="$(bounded 7 git -C "$DEST" rev-parse HEAD 2>/dev/null)" || return 1
      [ "$h" = "$SHA" ] || return 1
      st="$(bounded 7 git -C "$DEST" status --porcelain 2>/dev/null)" || return 1
      [ -z "$st" ]
    }
    addfail() { # <무엇이 실패했나> — DEST 가 요청 sha 그대로 + status 깨끗 → WARN(rc0 유지) · 아니면 die 4(등록 0 · 지우기 0)
      [ -d "$DEST" ] || die "$1 실패: $DEST" 4
      if verify_complete; then
        echo "WARN ft-scratch-repo — $1 rc≠0 이지만 사본 생성됨(HEAD=${SHA:0:8} · status 깨끗) · 장부 등록 · 그대로 쓴다: $DEST" >&2
      else
        local h; h="$(bounded 7 git -C "$DEST" rev-parse HEAD 2>/dev/null)"
        die "$1 실패: $DEST (HEAD=${h:-못 읽음} · 요청 sha 아님/체크아웃 불완전 — 지우기 0 · 등록 0 · 통째 = --full)" 4
      fi
    }
    if [ "$FULL" = 1 ]; then git -C "$SRC" worktree add -q --detach "$DEST" "$SHA" >/dev/null || addfail "worktree add"
    else   # r891: 설계 폴더(design/teams/*)·증거 미디어 빼고 체크아웃 — 사본당 1.4G·파일 수만 개 → 코드·시험·하네스 경로만
      git -C "$SRC" worktree add -q --no-checkout --detach "$DEST" "$SHA" >/dev/null || addfail "worktree add"
      printf '%s\n' "$SPEC" | git -C "$DEST" sparse-checkout set --no-cone --stdin >/dev/null 2>&1 && git -C "$DEST" checkout -q >/dev/null 2>&1 || addfail "sparse 체크아웃"
    fi
    # r845 r7: 훅 rc 가 0 이어도 «온전한 사본» 인지는 항상 확인한다 — 파일이 옮겨졌거나 HEAD 가 다른 sha 면 등록 0 · die 4
    verify_complete || { hh="$(bounded 7 git -C "$DEST" rev-parse HEAD 2>/dev/null)"; die "사본이 온전하지 않음: $DEST (HEAD=${hh:-못 읽음} · 요청 ${SHA:0:8} · status 더러움/파일 누락 — 등록 0 · 지우기 0)" 4; }
    # r891 r7: 등록은 체크아웃이 «다 끝난 뒤» 마지막 단계(기준판 순서) — 등록 줄이 있는 사본 = 체크아웃 끝난 사본 · 생성은 아무것도 지우지 않는다
    # r845: 장부는 «있으면 참고» — 쓰기 실패는 WARN 1줄이고 사본은 그대로 돌려준다(die 0)
    printf '%s\t%s\t%s\n' "$DEST" "$OWNER" "$(date +%s)" >> "$TSV" 2>/dev/null \
      || echo "WARN ft-scratch-repo — 장부 등록 실패($TSV) · 사본은 그대로 쓸 수 있다(정리 = 재부팅 임시 자리·--report): $DEST" >&2
    reg_has "$DEST" && warn_many "$OWNER"; echo "$DEST";;
esac
