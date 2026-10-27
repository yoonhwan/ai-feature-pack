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
#   ft-scratch-repo.sh --report [--summary]          «주인 없는 사본» 크기 목록 — 삭제 0. --summary = `주인 없는 임시 사본 N개 N.N GiB` 한 줄(0개면 출력 없음)
#   ft-scratch-repo.sh --sweep                       주인 없는 사본 정리(판정 1920): 첫 1회 = 목록 보고만(실삭제 0, 표식 scratch-sweep.armed) · 그 뒤부터 자동 삭제 · 지울 게 없으면 출력 0
#     r897 r10.3 (DA⑥ r1 반송 r2): ⒜빠른 길의 «못 읽음» 은 전부 «빠른 길 아님» — detached 판정은 rc=1 «만»(rc≥2 오류를 detached 로 읽지 않는다) · ⒝지우기 직전 재확인의 tmux·lsof 호출은 남은 예산(min(7초, 마감-지금))으로 상한 · 예산 0 이하면 호출 0 · 호출 «뒤» 에도 마감 검사(넘었으면 그 항목 삭제 0 + WARN · 남은 항목 다음 정리)
#     r897 r10.4 (DA⑥ r2 반송 r3): 빠른 길이 부르는 judged() 안의 외부 호출도 «rc=0 일 때만» 그 결과를 쓴다 — merge-base 는 rc=0 만 «착지»(rc≥2 = 못 읽음 = 판정 안 끝남) · git log -1 --format=%ct 는 rc0 일 때만 시각으로 읽는다(숫자를 찍고 rc128 이면 24시간 전에 지우던 길 · 반례 1)
#     r897 r10.5 (DA⑥ r3 반송 r4 · 하드 룰 14 재설계): «rc 를 안 보는 `$(…)`» 를 지우는 길에서 쓸 수 없게 — 지우는 길 함수(fast·judged·main_ref·orphans·cwd_holder·remtmo·sweep_run·done_run · r5 부터 delete_copy 포함)는
#           출력 받기를 전부 `cap 변수 명령…`(rc 그대로 돌려줌)으로만 한다 · `$(` 0 · 파이프 0(시험 ⓨ 가 기계로 센다) · 이름꼴은 셸 정규식(cut 0) · 시계(date +%s)도 rc0∧숫자일 때만
#           «A 실패면 B» 후퇴는 A 가 rc1(정말 없음)일 때만 — origin/main 확인 rc≥2 = 판정 안 끝남(main 으로 후퇴 0)
#     r444: tmux 목록을 못 읽으면 stdout `ERROR tmux unreadable …` 1줄(호출자 ft-disk-alarm 이 planner 로) + 삭제 0 · 지운 뒤 로그 `swept=N owner-dead=N tmp=N held=N`
#     r548: 어떤 프로세스의 cwd(그 폴더 또는 그 아래)인 사본은 지우지 않고 붙잡는다 — 로그 `붙잡음 …` 줄 + stdout `[장비 정리] 주인 <좌석> 사본 <경로> 에서 pid <n> <명령> 실행 중 — 삭제 보류` 최대 3줄(나머지 개수 1줄)
#     r548: cwd 를 묻는 lsof 가 실패하거나 0줄이면 «아무도 안 씀» 으로 읽지 않는다 — 로그·stdout `ERROR lsof 실패 — 삭제 0` 1줄 + 이번 정리 전체 생략(등록 사본·tmp.* 포함)
#   ft-scratch-repo.sh --gate <경로> [--kind reg|tmp] [--owner O]   r897 r5: 출구 게이트 진단(조건 G0~G8 줄 + rc · 삭제 0)
#     r897 r5 (DA⑥ r4 → fable 설계 · DESIGN-r897-exit-gate-r5 + DECISION-r897-design-final): ★삭제는 delete_copy 한 곳★ — 그 함수가 지금 다시 읽어 «우리가 만든 사본» 임을 증명할 때만 지운다
#           (경로 글자 · 베이스 바로 아래 · 이름꼴 · 등록부 정확히 1줄 · 시계·마감 · 점유 0 · 주인 없음 · 자격(나이 또는 판정 끝) · git 연결 워크트리 루트·detached · 장치·inode)
#           후퇴 0(등록 사본 = worktree remove 하나 · tmp = 격리 이동 뒤 inode 대조 · 폴더 제거 하나) · rc3 = 그 항목만 건너뜀 · rc2 = 남은 항목 전부 0 · 등록 줄 4칸 = 생성 당시 베이스
#   ft-scratch-repo.sh --judged <경로>               «판정 끝난» 사본이면 rc 0 · 아니면 1 · 등록 사본 아님/없는 경로 2 — 사본 HEAD 가 main 에 착지했거나, 그 sha 앞 8자가 main 의 design/ 문서에 적혔고 그 문서 커밋이 AGE 분 지났을 때(삭제 0 · r-disk-drop-worktree-scratch-census)
#     r645: 그 «적혔나» 는 지금 main 한 트리 문자열 검색(`git grep -F`) + 7초 상한 — 전 히스토리 pickaxe 검색(RSS 1~1.7GB·1분+) 0. 초과·실패 = «판정 안 끝남»(rc 1) + WARN 1줄 · warn_many 전체 예산 FT_SCRATCH_JUDGE_BUDGET(기본 20초)
#   같은 주인의 «등록 사본» 이 3개를 넘게 살아 있으면 새로 만들 때 stderr WARN + 가장 오래된 «판정 끝난» 사본 경로(삭제는 좌석 손 — `--done <경로>`). env FT_SCRATCH_MAIN(판정 기준 ref · 기본 origin/main 있으면 그것 없으면 main)
#   ★cwd 로 쓰이는 사본은 두 종류 모두 삭제 0 + «붙잡음» 목록(경로·pid·명령·주인) — 붙잡힌 사본은 그 팀이 시험 장비를 정리해야 지워진다(오빠 10-20 «시험 끝 = 띄운 장비 정리»)★
#   «주인 없는 사본» = 등록 사본 중 주인 세션이 tmux 에 없고 «등록 뒤 FT_SCRATCH_AGE_MIN(1440분) 지난» 것(판정 1920 문구 · r444 의 나이 문턱 0 을 r548 이 되돌림 · tmux 목록 실패면 이 판정 생략) + TMPDIR `tmp.*` 중 FT_SCRATCH_AGE_MIN 지나고 내 소유이며 어떤 프로세스의 cwd 도 아닌 것
#   같은 sha·같은 주인의 등록 사본이 디스크에 있으면 새로 만들지 않고 그 경로를 다시 준다(r444).
#   ★계약(r897 r10)★ 사본은 일회용 — 남길 것(커밋·산출)은 좌석 워크트리·--out-dir 로 · 사본 안 고유 작업은 자동 정리로 사라질 수 있다(같은 sha 로 재생성) · --done 은 주인 자신만(남의 사본 = rc2 · 주인 없는 사본은 --sweep)
#   env: FT_RES_ROOT · FT_SCRATCH_DIR(사본 부모, 기본 $TMPDIR) · FT_SCRATCH_OWNER(주인, 기본 현재 tmux 세션)
#        FT_TMUX_BIN(기본 PATH → /opt/homebrew/bin → /usr/local/bin — launchd PATH 엔 homebrew 가 없다 · r444) · FT_TMUX_SOCKET(있으면 -S) · FT_TMUX_TMPDIR(있으면 TMUX_TMPDIR)
#        FT_SCRATCH_JUDGE_BUDGET(판정 예산 초 · 기본 20 — 넘으면 남은 사본은 판정 안 함 · r645)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_RES_ROOT:-}"   # r385: 리포 공용 루트 = env → ft_repo_root(옛 설치 꼴 · cwd) → ERROR (새 설치본이 git 밖이라 자기 위치로 풀지 않는다)
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 3
TAB=$'\t'
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
cap() { # <변수> <명령…> → 명령 출력을 그 변수에 · rc = 명령 rc 그대로 (r897 r10.5: 지우는 길의 `X="$(…)"` 대신 — rc 를 버리는 꼴을 못 쓰게 · 파이프는 전역 pipefail)
  local __cap_v="$1" __cap_o __cap_r; shift
  __cap_o="$("$@")"; __cap_r=$?
  printf -v "$__cap_v" '%s' "$__cap_o"
  return "$__cap_r"
}
isnum() { case "$1" in ''|*[!0-9]*) return 1;; esac; }
die() { echo "ERROR $1" >&2; exit "${2:-1}"; }
TMUX_BIN="${FT_TMUX_BIN:-$(command -v tmux 2>/dev/null)}"
for _t in /opt/homebrew/bin/tmux /usr/local/bin/tmux; do [ -n "$TMUX_BIN" ] || { [ -x "$_t" ] && TMUX_BIN="$_t"; }; done
[ -z "${FT_TMUX_TMPDIR:-}" ] || export TMUX_TMPDIR="$FT_TMUX_TMPDIR"
TMUX_ARGS=(); [ -z "$TMUX_BIN" ] || TMUX_ARGS=("$TMUX_BIN"); [ -z "${FT_TMUX_SOCKET:-}" ] || TMUX_ARGS+=(-S "$FT_TMUX_SOCKET")
tmux_sessions() { [ -n "$TMUX_BIN" ] || return 127; "${TMUX_ARGS[@]}" list-sessions -F '#{session_name}' 2>/dev/null; }
tmux_sessions_tmo() { # <초> r897 r10.3: 재확인용 — 남은 예산으로 상한(멈춘 tmux 가 정리 예산을 통째로 먹지 않게 · bounded 는 timeout 없이도 자식을 죽인다)
  [ -n "$TMUX_BIN" ] || return 127
  bounded "$1" "${TMUX_ARGS[@]}" list-sessions -F '#{session_name}' 2>/dev/null
}
RBUD=0   # r897 r10.3: 재확인 마감(epoch) — --sweep 이 RSTART+70 으로 세운다 · 0 = 마감 없음(재확인 단독 호출)
remtmo() { # → 이번 호출에 쓸 초 = min(7, 마감 - 지금) · 마감 없으면 7 · 0 이하 = 0(그 뒤 호출 0) · 시계 못 읽음 = 0(r10.5)
  local t=7 now
  if [ "$RBUD" != 0 ]; then
    cap now date +%s && isnum "$now" || { printf '0\n'; return 0; }
    t=$(( RBUD - now )); [ "$t" -gt 7 ] && t=7
  fi
  [ "$t" -gt 0 ] || t=0
  printf '%s\n' "$t"
}
mkdir -p "$STATE" 2>/dev/null || die "상태 폴더 생성 실패: $STATE" 4
# r939 H1: «곧 끝나는 일» 자기 등록 — 승계(retire)가 이 사본 생성을 죽이지 않고 후계에게 넘긴다(장부 state/bg-finite.tsv)
bash "$HERE/ft-bg-finite.sh" register "${FT_SEAT:--}" "${FT_BG_FINITE_SCRATCH_SEC:-1200}" "$$" "ft-scratch-repo.sh $*" >/dev/null 2>&1 || true   # 등록 실패 = 넘김 대상 아님(오늘과 같은 reap) — 도구 stdout 계약을 흔들지 않는다
trap 'bash "$HERE/ft-bg-finite.sh" unregister $$ >/dev/null 2>&1 || true' EXIT
gib() { awk -v k="$1" 'BEGIN{ if (k ~ /^[0-9]+$/) printf "%.2f", k/1048576; else printf "?" }'; }
kb()  { $TMO du -sk "$1" 2>/dev/null | awk '{print $1}'; }
has_ctl() { case "$1" in *"$TAB"*|*$'\n'*) return 0;; esac; return 1; }   # r897 r10.2: 등록부는 TSV — 탭·개행이 든 경로는 표현할 수 없다
has_line() { case $'\n'"$1"$'\n' in *$'\n'"$2"$'\n'*) return 0;; esac; return 1; }   # <목록> <이름> → 0 = 그 줄이 «정확히» 있다 · r10.5: 외부 명령·리다이렉트 0(grep <<< 는 임시 파일 실패가 rc1 = «주인 없음» 으로 읽혔다)
phys() { ( cd "$1" 2>/dev/null && pwd -P ); }   # r897 r10: 물리 경로(/private/var…) — 못 읽으면 rc≠0
drop_reg() { # <등록 원문 경로> 그 등록 줄만 삭제 — «경로 정확 대조»(r10.1: awk -v 는 역슬래시를 해석해 `\161`→`q` 로 남의 줄과 맞는다 · ENVIRON 은 바이트 그대로) · r5 고침 6: 0줄 지우면 rc≠0(조용한 rc0 0)
  [ -f "$TSV" ] || return 3
  P_EXACT="$1" awk -F'\t' '$1==ENVIRON["P_EXACT"]{n++; next} {print} END{exit (n>0 ? 0 : 3)}' "$TSV" > "$TSV.tmp.$$" && mv "$TSV.tmp.$$" "$TSV"
}
cwd_parse() { printf '%s\n' "$1" | awk '/^p/{pid=substr($0,2);next} /^c/{cmd=substr($0,2);next} /^n/{if (pid!="") printf "%s\t%s\t%s\n", substr($0,2), pid, cmd}'; }   # <lsof -Fpcn 출력> → 경로·pid·명령 줄 · rc = awk rc(pipefail · r10.5: 지우는 길은 cap 으로 받아 rc≠0 = 못 읽음)
reg_owner() { [ -f "$TSV" ] || return 0; P_EXACT="$1" awk -F'\t' '$1==ENVIRON["P_EXACT"]{print $2; exit}' "$TSV"; }   # <경로> → 등록 주인(정확 대조) · 등록부 없음 = 빈 값 rc0 · awk 실패 = rc≠0
first_paths() { printf '%s' "$1" | awk -F'\t' 'NR<=3{printf "%s%s", (NR>1?", ":""), $2}'; }   # <ORPH> → 앞 3개 경로(표시 전용)
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
unregistered_copies() { # r891 ⓘ: $FT_SCRATCH_DIR/repo-* 중 어느 등록부(ROOT + 사본들의 원 저장소)에도 없는 사본 표 — ★보고만 · 지우기 0★ · 못 읽은 등록부 = «부분 읽기» 줄
  local base="${FT_SCRATCH_DIR:-${TMPDIR:-/tmp}}" f p rest rows keys="" failed="" n h root sha ep me
  for f in $( { printf '%s\n' "$TSV"; for p in "${base%/}"/repo-*; do [ -d "$p" ] && copy_reg "$p"; done; } | awk '!s[$0]++'); do
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
  for p in "${base%/}"/repo-*; do
    [ -d "$p" ] || continue
    me="$(cd "$p" && pwd -P)"; case "
$keys" in *"
$me
"*) continue;; esac
    n="${p##*/}"; h="$(printf '%s' "$n" | cut -d- -f2)"; ep="$(printf '%s' "$n" | cut -d- -f3)"
    root="$(common_root "$p")" || root="못 읽음"; sha="$(git -C "$p" rev-parse HEAD 2>/dev/null)" || sha="-"
    case "$ep" in ''|*[!0-9]*) ep="-";; *) ep="$(date -r "$ep" '+%F %H:%M' 2>/dev/null || echo -)";; esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "$root" "$sha" "$(gib "$(kb "$p")")" "$ep" "$(guess_owner "$h")"
  done
  printf '%s' "$failed" | awk 'NF{print "부분 읽기\t등록부 읽기 실패 — 그 등록부 사본은 «미등록» 으로 보일 수 있음\t" $0}'
}
main_ref() { # <변수> → 판정 기준 ref = FT_SCRATCH_MAIN → origin/main(있으면) → main · r10.5(DA⑥ r3 반례 3): main 으로 후퇴는 origin/main 확인이 rc1(정말 없음)일 때만 · rc≥2 = 못 읽음 = rc1
  local r
  [ -z "${FT_SCRATCH_MAIN:-}" ] || { printf -v "$1" '%s' "$FT_SCRATCH_MAIN"; return 0; }
  git -C "$ROOT" rev-parse -q --verify origin/main >/dev/null 2>&1; r=$?
  case "$r" in
    0) printf -v "$1" '%s' origin/main;;
    1) printf -v "$1" '%s' main;;
    *) echo "WARN ft-scratch-repo judged — origin/main 확인 실패(rc=$r) · 판정 안 끝남(main 으로 후퇴 0)" >&2; return 1;;
  esac
}
judged() { # <경로> → 0 = 판정 끝남(착지됐거나 판정문에 적히고 AGE 분 지남)
  local sha h8 m ct f oldest="" out rc now tmo="${JUDGE_TMO:-7}"
  cap sha git -C "$1" rev-parse HEAD 2>/dev/null || return 1; h8="${sha:0:8}"
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 1   # 판정 기준 트리가 없으면 «안 끝남»(환경 없음 — WARN 아님 · r10.5: ref 확인보다 먼저)
  main_ref m || return 1
  # r897 r10.4: rc=0 만 «착지» · rc=1(조상 아님) = 다음 증거로 · rc≥2(오류·못 읽음) = 판정 안 끝남(덜 지우는 쪽 · DA⑥ r2 반송 r3 «전수 rc 검사»)
  git -C "$ROOT" merge-base --is-ancestor "$sha" "$m" 2>/dev/null; rc=$?
  case "$rc" in 0) return 0;; 1) ;; *) echo "WARN ft-scratch-repo judged — merge-base 실패(rc=$rc) · 판정 안 끝남 $1" >&2; return 1;; esac
  # r645: 히스토리 전수 pickaxe 대신 «지금 main 한 트리 · design 경로 한정» 문자열 검색 + 상한(초과·실패 = 조용한 «끝남» 0)
  cap out bounded "$tmo" git -C "$ROOT" grep -F -l "$h8" "$m" -- design 2>/dev/null; rc=$?
  case "$rc" in
    0) ;;
    1) return 1;;   # 판정문에 그 sha 8자 없음 = 판정 안 끝남
    124) echo "WARN ft-scratch-repo judged — 시간 초과(${tmo}s) · 판정 안 끝남 $1" >&2; return 1;;
    *) echo "WARN ft-scratch-repo judged — git grep 실패(rc=$rc) · 판정 안 끝남 $1" >&2; return 1;;
  esac
  while IFS= read -r f; do   # 걸린 문서의 «마지막 커밋 시각» 중 가장 이른 것 = 보수 쪽(더 늦게 끝남)
    [ -n "$f" ] || continue
    f="${f#"$m":}"   # rev 를 준 git grep 은 «<ref>:<경로>» 로 적는다
    cap ct bounded "$tmo" git -C "$ROOT" log -1 --format=%ct "$m" -- "$f" 2>/dev/null; rc=$?
    # r897 r10.4: rc0 일 때만 그 숫자를 «시각» 으로 쓴다 — 숫자를 찍고 rc≠0 이면 못 읽음(DA⑥ r2 반례 1: rc128 숫자로 24시간 전에 지웠다)
    [ "$rc" = 0 ] || { echo "WARN ft-scratch-repo judged — git log 실패(rc=$rc) · 판정 안 끝남 $f" >&2; return 1; }
    case "$ct" in ''|*[!0-9]*) echo "WARN ft-scratch-repo judged — 마지막 커밋 시각 못 읽음 · 판정 안 끝남 $f" >&2; return 1;; esac
    [ -n "$oldest" ] && [ "$ct" -ge "$oldest" ] || oldest="$ct"
  done <<EOF
$out
EOF
  [ -n "$oldest" ] || return 1
  # r10.5(DA⑥ r3 반례 2): 시계도 외부 명령 — rc0 ∧ 숫자일 때만 «지금» 으로 쓴다(숫자 + rc128 이면 못 읽음)
  cap now date +%s || { echo "WARN ft-scratch-repo judged — 시계(date) 실패 · 판정 안 끝남 $1" >&2; return 1; }
  isnum "$now" || { echo "WARN ft-scratch-repo judged — 시계 값 숫자 아님 · 판정 안 끝남 $1" >&2; return 1; }
  [ $(( now - oldest )) -ge $((AGE*60)) ]
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
cwd_holder() { # <폴더> <lsof 해석 줄> → 0 = 어떤 프로세스가 그 폴더 «또는 그 아래» 를 cwd 로 쓴다(폴더 경계 비교) · HPID/HCMD 에 그 프로세스 첫 줄 · 없으면 1 · r5 고침 2: 줄은 인자로(전역 재사용 0)
  local d dr p pid cmd
  HPID=""; HCMD=""
  dr="$1"
  # r897 r10: 등록부는 /var/folders/… 로 적고 lsof 는 /private/var/… 로 낸다 — «물리 경로» 로 맞춘다(못 읽으면 «붙잡음» = 지우기 0) · 물리로 못 맞추는 lsof 줄은 글자로 한 번 더 본다(델 지우는 쪽)
  cap d phys "$1" && [ -n "$d" ] || { HPID="?"; HCMD="경로 못 읽음"; return 0; }
  while IFS="$TAB" read -r p pid cmd; do
    case "$p" in "$d"|"$d"/*|"$dr"|"$dr"/*) HPID="$pid"; HCMD="$cmd"; return 0;; esac
  done <<EOF
$2
EOF
  return 1
}
held_report() { # <날짜> r548: 붙잡은 사본 = 로그 «붙잡음» 줄 전부 + stdout «[장비 정리]» 최대 3줄 + «…외 N건»
  local k p ty why own pid cmd i=0
  while IFS="$TAB" read -r k p ty why own pid cmd; do
    [ -n "$p" ] || continue
    i=$((i+1))
    printf '%s 붙잡음 %s (pid %s %s · 주인 %s)\n' "$1" "$p" "$pid" "$cmd" "$own" >> "$SLOG"
    [ "$i" -le 3 ] && echo "[장비 정리] 주인 $own 사본 $p 에서 pid $pid $cmd 실행 중 — 삭제 보류"
  done <<EOF
$HOLD
EOF
  [ "$HELD" -le 3 ] || echo "[장비 정리] …외 $((HELD-3)) 건"
}
orphans() { # → ORPH = "kb<TAB>경로<TAB>reg|tmp<TAB>사유" 줄들 · HOLD = "kb<TAB>경로<TAB>reg|tmp<TAB>사유(붙잡음)·…<TAB>주인<TAB>pid<TAB>명령" · N · K · HELD · TMUX_OK · LSOF_OK
  local SESS p o t b d TD now RAW r why jdl jt jnow jover=0 kbv me tdl rows=""; ORPH=""; HOLD=""; N=0; K=0; HELD=0; TMUX_OK=1; LSOF_OK=1; READ_OK=1
  # r10.5: «지금» 을 못 읽으면(rc≠0·숫자 아님) 24시간 문턱도 빠른 길도 못 가린다 — 이번 판정 전체를 접는다(READ_OK=0 → sweep 삭제 0)
  cap now date +%s && isnum "$now" || { READ_OK=0; echo "ERROR 시계(date +%s) 못 읽음 — 삭제 0" >&2; return 0; }
  jdl=$(( now + ${FT_SCRATCH_JUDGE_BUDGET:-20} ))   # 2720 빠른 길 판정 예산(초) — 넘으면 «즉시 삭제 후보» 를 만들지 않는다(덜 지우는 쪽 · warn_many 와 같은 꼴)
  add() { ORPH="$ORPH$1	$2	$3	$4	$5
"; N=$((N+1)); case "$1" in ''|*[!0-9]*) ;; *) K=$((K+$1));; esac; }   # 5열 = 주인(r897 r10: 지우기 직전 재확인용 · --report awk 는 $2·$4 만 읽는다)
  hold() { HOLD="$HOLD$1	$2	$3	$4	$5	$6	$7
"; HELD=$((HELD+1)); }
  # r548: «누가 이 폴더를 cwd 로 쓰나» 를 한 번($TMO lsof -Fpcn)만 묻고 등록 사본·tmp 둘 다에 쓴다. 실패(rc≠0)하거나 0줄이면 «아무도 안 씀» 으로 읽지 않고 이번 판정 전체를 접는다(조용한 통과 0).
  cap RAW $TMO lsof -w -d cwd -Fpcn 2>/dev/null || LSOF_OK=0
  [ -n "$RAW" ] || LSOF_OK=0
  # r10.5: lsof 출력 해석(awk)도 rc 를 본다 — 해석 실패 = cwd 판정 불가(빈 표 = «아무도 안 씀» 으로 읽지 않는다)
  [ "$LSOF_OK" = 0 ] || cap CWDROWS cwd_parse "$RAW" || LSOF_OK=0
  if [ "$LSOF_OK" = 0 ]; then echo "ERROR lsof 실패 — 삭제 0 (cwd 판정 불가)" >&2; return 0; fi
  # 등록 사본: tmux 목록을 못 읽으면(rc≠0) «세션 0» 으로 세지 않고 이 판정 전체를 건너뛴다(#0 RULE) · 후보 = 주인 없음 ∧ 등록 뒤 AGE 분 지남(판정 1920 문구 · r548 이 r444 의 문턱 0 을 되돌림)
  # r5(DA⑥ r4 반례 1a): 등록부 읽기도 rc 를 본다 — 못 읽음 = 이번 판정 전체를 접는다(READ_OK=0 · sweep 삭제 0) · `<(…)` 0
  if [ -e "$TSV" ]; then cap rows bounded 7 cat -- "$TSV" || { READ_OK=0; echo "ERROR 등록부 못 읽음 — 삭제 0" >&2; return 0; }; fi
  if cap SESS tmux_sessions; then
    while IFS="$TAB" read -r p o t b; do
      [ -n "$p" ] && [ -d "$p" ] || continue
      # r897 r10: 주인 대조 = 정확 대조 — 이름에 정규식 글자(예: seat[)가 있어도 글자 그대로 · r10.5: 셸 안 대조(has_line · 실패할 외부 호출 0)
      has_line "$SESS" "$o" && continue
      case "$t" in ''|*[!0-9]*) echo "ERROR 등록표 3열이 숫자 아님 — 삭제 0 (경로 $p · 3열 '${t}')" >&2; continue;; esac
      why="등록 사본 · 주인 $o 없음"
      if [ $((now - t)) -lt $((AGE*60)) ]; then   # 2720 빠른 길: «판정 끝 표식 ∧ 이름·HEAD·detached» — 예산 안에서만 · 못 읽거나 거짓이면 24시간 규칙으로 후퇴
        [ "$jover" = 0 ] || continue
        # r10.5: 예산 시계도 rc0 ∧ 숫자일 때만
        cap jnow date +%s && isnum "$jnow" || { READ_OK=0; echo "ERROR 시계(date +%s) 못 읽음 — 삭제 0" >&2; return 0; }   # r5: 시계 못 읽음 = 이번 실행 전체 삭제 0(tmp 포함)
        jt=$(( jdl - jnow )); [ "$jt" -gt 7 ] && jt=7
        if [ "$jt" -le 0 ]; then jover=1; echo "WARN ft-scratch-repo — 판정 예산(${FT_SCRATCH_JUDGE_BUDGET:-20}초) 초과 · 남은 사본은 즉시 삭제 후보 아님" >&2; continue; fi
        JUDGE_TMO=$jt; fast "$p" || { JUDGE_TMO=7; continue; }; JUDGE_TMO=7
        why="$why · judged"
      fi
      cap kbv kb "$p"; isnum "$kbv" || kbv='?'   # 표시 전용(크기) — 결정 입력 0 · r5: 빈 칸 0(탭 IFS 가 빈 칸을 접어 열이 밀리던 길 · DA⑥ r4 반례 1b)
      if cwd_holder "$p" "$CWDROWS"; then hold "$kbv" "$p" reg "$why · 붙잡음 pid $HPID $HCMD" "$o" "$HPID" "$HCMD"
      else add "$kbv" "$p" reg "$why" "$o"; fi
    done <<EOF
$rows
EOF
  else TMUX_OK=0; echo "ERROR tmux 목록 실패 — 등록 사본 판정 생략 (tmux=${TMUX_BIN:-없음})" >&2; fi
  TD="${TMPDIR:-/tmp}"; TD="${TD%/}"
  # r10.5: 내 이름·목록(id·find)도 rc 를 본다 — 하나라도 실패하면 tmp.* 는 이번에 지우지 않는다 · 줄 단위로 읽고 «$TD/tmp.*» 꼴이 아닌 줄(공백·개행 든 이름의 조각)은 버린다
  if cap me id -un && cap tdl find "$TD" -maxdepth 1 -type d -name 'tmp.*' -user "$me" -mmin +"$AGE" 2>/dev/null; then
    while IFS= read -r d; do
      case "$d" in "$TD"/tmp.*) [ -d "$d" ] || continue;; *) continue;; esac
      case "${d#"$TD"/}" in */*) continue;; esac
      cap kbv kb "$d"; isnum "$kbv" || kbv='?'   # 표시 전용(크기)
      if cwd_holder "$d" "$CWDROWS"; then hold "$kbv" "$d" tmp "TMPDIR tmp.* ${AGE}분 지남 · 붙잡음 pid $HPID $HCMD" "-" "$HPID" "$HCMD"
      else add "$kbv" "$d" tmp "TMPDIR tmp.* ${AGE}분 지남" "-"; fi
    done <<EOF
$tdl
EOF
  else echo "WARN ft-scratch-repo — TMPDIR 목록(id·find) 못 읽음 · tmp.* 삭제 0" >&2; fi
}
fast() { # <사본> → 0 = «판정 끝 표식 ∧ 주인 없음» 중 이름꼴·HEAD·detached 가 모두 참(2720 빠른 길 · r897 r10) · 하나라도 못 읽거나 거짓 = rc1(24시간 규칙으로 후퇴 · 덜 지우는 쪽)
  local p="$1" n h sha r re='^repo-([0123456789abcdef]{8})-[0123456789]+-[0123456789]+$'
  n="${p##*/}"
  [[ $n =~ $re ]] || return 1   # ①이름 = repo-<sha8>-<숫자>-<숫자> — r10.5: 셸 정규식(외부 cut 0 · DA⑥ r3 반례 1: cut 빈 출력 + rc128 이 이름 검사를 통과시켰다)
  h="${BASH_REMATCH[1]}"
  cap sha git -C "$p" rev-parse HEAD 2>/dev/null || return 1   # ②HEAD 를 읽을 수 있고 이름 sha8 과 같다(만든 뒤 커밋 0)
  [ "${sha:0:8}" = "$h" ] || return 1
  git -C "$p" symbolic-ref -q HEAD >/dev/null 2>&1; r=$?   # ③detached — ★rc=1(가지 없음) 만 «detached»★ · rc0(가지 워크트리)·rc≥2(오류·못 읽음) = 빠른 길 아님(«못 읽음» 을 detached 로 읽지 않는다 · DA⑥ r1 반례 1)
  [ "$r" = 1 ] || return 1
  judged "$p" || return 1   # ④판정 끝 표식 — rc0 만 참(그 밖 = 빠른 길 아님)
  return 0
}
# ── 출구 게이트(r897 r5 · DESIGN-r897-exit-gate-r5 + DECISION-r897-design-final 고침 11) ──────────────────────────
#   rm·worktree remove 는 delete_copy 안에만 · 조건은 전부 «지금» 다시 읽는다(앞 단계 ORPH·fast·lsof 값을 믿지 않는다) · 조회마다 min(7초, 마감-지금)
#   rc: 0 삭제됨 · 1 HELD(점유·주인 생김) · 2 UNREADABLE/BUDGET(남은 항목 전부 삭제 0) · 3 REFUSED(이 항목 대상 아님 — 그 항목만 건너뜀) · 4 FAILED(삭제 명령 실패 · 등록 줄 유지 · 다음 sweep 재시도)
GWHY=""; GATE_DRY=0
gfail() { # <조건> <rc> <사유> → GWHY · --gate 면 조건 줄 · rc 그대로
  GWHY="$1 $3"
  if [ "$GATE_DRY" != 0 ]; then case "$2" in 1) printf '%s HELD (%s)\n' "$1" "$3";; 2) printf '%s UNREADABLE (%s)\n' "$1" "$3";; *) printf '%s REFUSED (%s)\n' "$1" "$3";; esac; fi
  return "$2"
}
gok() { [ "$GATE_DRY" = 0 ] || printf '%s ok\n' "$1"; }
past_deadline() { # → 0 = 마감 넘음(또는 시계 못 읽음) · 1 = 안 넘음 · 마감 없음(RBUD=0 · --done·--gate) = 1
  local now
  [ "$RBUD" != 0 ] || return 1
  cap now date +%s && isnum "$now" || return 0
  [ $(( now - RBUD )) -gt 0 ]
}
phys_tmo() { # <경로> → 물리 경로 · 외부 pwd(-P) 를 남은 예산으로 상한 · rc≠0 = 못 읽음(124 = 시간 초과)
  local t; cap t remtmo; [ "$t" -gt 0 ] || return 124
  bounded "$t" /bin/sh -c 'cd -- "$1" 2>/dev/null && exec pwd -P' sh "$1"
}
gq() { # <변수> <외부 명령…> → 남은 예산 상한으로 cap · 예산 0 = rc124(호출 0) · 셸 함수는 넘기지 않는다(gtimeout 이 못 부른다)
  local __gq_t; cap __gq_t remtmo; [ "$__gq_t" -gt 0 ] || return 124
  local __gq_v="$1"; shift
  cap "$__gq_v" bounded "$__gq_t" "$@"
}
gate_rows() { # <P> <주인> → G5: 등록부를 «지금» 읽어 첫 칸 물리 경로 == P 인 줄이 정확히 1줄 · GRAW(원문 경로)·GOWN·GT·GBASE(없으면 빈 값) · rc 2/3
  local P="$1" rows line c1 rest tabs pp n=0
  [ -e "$TSV" ] || { gfail G5 3 "등록부 없음"; return; }
  gq rows cat -- "$TSV" 2>/dev/null || { gfail G5 2 "등록부 못 읽음"; return; }
  GRAW=""; GOWN=""; GT=""; GBASE=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    c1="${line%%"$TAB"*}"
    [ -e "$c1" ] || continue   # 폴더 없는 줄 = 그 사본일 수 없다(stale)
    cap pp phys_tmo "$c1" || { gfail G5 2 "등록 줄 경로 못 읽음 $c1"; return; }
    [ "$pp" = "$P" ] || continue
    n=$((n+1)); tabs="${line//[!$TAB]/}"
    [ "${#tabs}" = 2 ] || [ "${#tabs}" = 3 ] || { gfail G5 3 "등록 줄 칸 깨짐"; return; }
    rest="${line#*"$TAB"}"; GRAW="$c1"; GOWN="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"; GT="${rest%%"$TAB"*}"
    [ "${#tabs}" = 3 ] && GBASE="${rest#*"$TAB"}"
  done <<EOF
$rows
EOF
  [ "$n" = 1 ] || { gfail G5 3 "등록 줄 ${n}개(정확히 1줄 아님)"; return; }
  [ "$GOWN" = "$2" ] || { gfail G5 3 "등록 주인 $GOWN ≠ $2"; return; }
  isnum "$GT" || { gfail G5 3 "등록 시각 숫자 아님"; return; }
  gok G5
}
gate_base() { # <P> <베이스 후보…> → G1: P = B/<성분 하나> 인 후보가 있나 · 후보 경로 못 읽음 = rc2
  local P="$1" c B; shift
  for c in "$@"; do
    [ -n "$c" ] || continue
    [ -e "$c" ] || continue
    cap B phys_tmo "$c" || { gfail G1 2 "베이스 못 읽음 $c"; return; }
    [ "${P%/*}" = "$B" ] && [ -n "${P##*/}" ] && { GB="$B"; gok G1; return 0; }
  done
  gfail G1 3 "베이스 바로 아래 아님"
}
delete_copy() { # <경로> <reg|tmp> <주인|-> [sweep|done] → 위 rc 표 · GWHY = 막은 조건
  local p="$1" kind="$2" own="$3" mode="${4:-sweep}" P now RAW ROWS S T TP G C GP CP DI DI2 T2 G2 U ME M r x re dest
  GWHY=""; HPID=""; HCMD=""; GB=""
  # G0 경로 글자
  case "$p" in ''|*"$TAB"*|*$'\n'*) gfail G0 3 "빈 경로·탭·개행"; return;; esac
  case "$p" in /*) ;; *) gfail G0 3 "상대 경로"; return;; esac
  case "$p/" in */../*|*/./*) gfail G0 3 ".·.. 성분"; return;; esac
  for x in / "${HOME:-}" "$ROOT" "${TMPDIR:-/tmp}" "${FT_SCRATCH_DIR:-}"; do [ -n "$x" ] && [ "${p%/}" = "${x%/}" ] && { gfail G0 3 "보호 경로 $x"; return; }; done
  gok G0
  [ -e "$p" ] || { gfail G1 3 "없는 경로"; return; }
  cap P phys_tmo "$p" || { gfail G1 2 "물리 경로 못 읽음"; return; }
  # G5(reg) 등록부 · G1 베이스(등록 줄의 생성 당시 베이스 — 옛 줄은 기본 TMPDIR·지금 FT_SCRATCH_DIR) · G2 이름꼴
  if [ "$kind" = reg ]; then
    gate_rows "$P" "$own" || return
    if [ -n "$GBASE" ]; then gate_base "$P" "$GBASE" || return; else gate_base "$P" "${TMPDIR:-/tmp}" "${FT_SCRATCH_DIR:-}" || return; fi
    re='^repo-[0123456789abcdef]{8}-[0123456789]+-[0123456789]+$'
  else
    [ "$kind" = tmp ] || { gfail G0 3 "종류 $kind"; return; }
    gate_base "$P" "${TMPDIR:-/tmp}" || return
    re='^tmp\.[A-Za-z0-9_.-]+$'
  fi
  [[ ${P##*/} =~ $re ]] || { gfail G2 3 "이름꼴 아님 ${P##*/}"; return; }
  gok G2
  # G3 시계·마감
  cap now date +%s && isnum "$now" || { gfail G3 2 "시계 못 읽음"; return; }
  [ "$RBUD" = 0 ] || [ "$now" -le "$RBUD" ] || { gfail G3 2 "마감(70초) 넘음"; return; }
  gok G3
  # G4 점유 0 — 이 함수가 잰 lsof 를 판정에 «인자로» 넘긴다(전역 재사용 0)
  gq RAW lsof -w -d cwd -Fpcn 2>/dev/null || { gfail G4 2 "lsof 못 읽음"; return; }
  [ -n "$RAW" ] || { gfail G4 2 "lsof 0줄"; return; }
  cap ROWS cwd_parse "$RAW" || { gfail G4 2 "lsof 해석 실패"; return; }
  cwd_holder "$p" "$ROWS" && { gfail G4 1 "점유 pid $HPID $HCMD"; return; }   # 원문·물리 경로 둘 다 대조(cwd_holder 가 물리로 바꿔 한 번 더 본다)
  gok G4
  if [ "$kind" = reg ]; then
    # G6 주인 없음(sweep) — --done 은 호출자가 주인 == 나 를 이미 대조
    if [ "$mode" = sweep ]; then
      cap r remtmo; [ "$r" -gt 0 ] || { gfail G6 2 "예산 소진"; return; }
      cap S tmux_sessions_tmo "$r" || { gfail G6 2 "tmux 못 읽음"; return; }
      [ -n "$S" ] || { gfail G6 2 "tmux 0줄"; return; }
      has_line "$S" "$own" && { gfail G6 1 "주인 $own 살아 있음"; return; }
      gok G6
      # 자격(고침 1): 나이 ≥ AGE 분(등록 시각·지금 둘 다 rc0) 또는 빠른 길(판정 끝 ∧ 이름·HEAD·detached) — 상류의 «후보» 를 믿지 않는다
      if [ $(( now - GT )) -lt $((AGE*60)) ]; then
        cap JUDGE_TMO remtmo; [ "$JUDGE_TMO" -gt 0 ] || { JUDGE_TMO=7; gfail G6 2 "예산 소진"; return; }
        fast "$P" || { JUDGE_TMO=7; gfail G6 3 "자격 없음(${AGE}분 전 · 판정 안 끝남)"; return; }
        JUDGE_TMO=7
      fi
    fi
    # G7 git 사본 증명: 사본 루트 · 연결 워크트리(<공용 git>/worktrees/<이름> · bare 원 저장소 포함) · detached(rc1 만)
    gq T git -C "$P" rev-parse --show-toplevel 2>/dev/null || { gfail G7 2 "toplevel 못 읽음"; return; }
    cap TP phys_tmo "$T" || { gfail G7 2 "toplevel 물리 경로 못 읽음"; return; }
    [ "$TP" = "$P" ] || { gfail G7 3 "사본 루트 아님"; return; }
    gq G git -C "$P" rev-parse --path-format=absolute --git-dir 2>/dev/null || { gfail G7 2 "git-dir 못 읽음"; return; }
    gq C git -C "$P" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || { gfail G7 2 "git-common-dir 못 읽음"; return; }
    cap GP phys_tmo "$G" || { gfail G7 2 "git-dir 물리 경로 못 읽음"; return; }
    cap CP phys_tmo "$C" || { gfail G7 2 "git-common-dir 물리 경로 못 읽음"; return; }
    case "${GP#"$CP"/worktrees/}" in "$GP"|''|*/*) gfail G7 3 "연결 워크트리 아님"; return;; esac
    cap r remtmo; [ "$r" -gt 0 ] || { gfail G7 2 "예산 소진"; return; }
    bounded "$r" git -C "$P" symbolic-ref -q HEAD >/dev/null 2>&1; r=$?
    case "$r" in 1) ;; 0) gfail G7 3 "가지 워크트리(detached 아님)"; return;; *) gfail G7 2 "symbolic-ref 못 읽음(rc=$r)"; return;; esac
    gok G7
  else
    # G5′ git 아님 · 주인 없음 표시 · G6′ 내 소유 ∧ 나이(find 를 믿지 않고 다시 잰다)
    [ "$own" = - ] || { gfail G5 3 "tmp 인데 주인 $own"; return; }
    [ ! -e "$P/.git" ] || { gfail G5 3 "git 폴더(모르는 물건)"; return; }
    gok G5
    gq U stat -f %u "$P" || { gfail G6 2 "소유자 못 읽음"; return; }
    gq ME id -u || { gfail G6 2 "내 uid 못 읽음"; return; }
    isnum "$U" && isnum "$ME" && [ "$U" = "$ME" ] || { gfail G6 3 "내 소유 아님"; return; }
    gq M stat -f %m "$P" || { gfail G6 2 "수정 시각 못 읽음"; return; }
    isnum "$M" || { gfail G6 2 "수정 시각 숫자 아님"; return; }
    [ $(( now - M )) -ge $((AGE*60)) ] || { gfail G6 3 "${AGE}분 안 지남"; return; }
    gok G6
  fi
  gq DI stat -f %d:%i "$P" || { gfail G8 2 "장치·inode 못 읽음"; return; }
  [ "$GATE_DRY" = 0 ] || { echo "GATE ok $P"; return 0; }
  # 확인한 객체 = 지운 객체(고침 5)
  if [ "$kind" = reg ]; then
    gq T2 git -C "$P" rev-parse --show-toplevel 2>/dev/null && [ "$T2" = "$T" ] || { gfail G8 2 "제거 직전 toplevel 다름·못 읽음"; return; }
    gq G2 git -C "$P" rev-parse --path-format=absolute --git-dir 2>/dev/null && [ "$G2" = "$G" ] || { gfail G8 2 "제거 직전 git-dir 다름·못 읽음"; return; }
    gq DI2 stat -f %d:%i "$P" && [ "$DI2" = "$DI" ] || { gfail G8 2 "제거 직전 장치·inode 다름·못 읽음"; return; }
    past_deadline && { gfail G8 2 "삭제 직전 마감 초과"; return; }
    git -C "$P" worktree remove --force "$P" >/dev/null 2>&1 || { r=$?; GWHY="삭제 명령 실패(worktree remove rc=$r) · 등록 줄 유지"; return 4; }
    [ ! -e "$P" ] || { GWHY="삭제 명령 rc0 인데 폴더 남음 · 등록 줄 유지"; return 4; }
    drop_reg "$GRAW" || echo "ERROR ft-scratch-repo — 등록 줄 삭제 실패(폴더는 없음 · --report 에 stale): $GRAW" >&2
    return 0
  fi
  dest="$GB/.reaping"
  mkdir -p -- "$dest" 2>/dev/null && [ -d "$dest" ] && [ ! -L "$dest" ] || { GWHY="격리 폴더 못 만듦 $dest"; return 4; }
  dest="$dest/${P##*/}.$$"
  past_deadline && { gfail G8 2 "삭제 직전 마감 초과"; return; }
  mv -- "$P" "$dest" 2>/dev/null || { [ -e "$P" ] || [ ! -e "$dest" ] || mv -- "$dest" "$P" 2>/dev/null; GWHY="격리 이동 실패 $P · 원위치 확인"; return 4; }
  gq DI2 stat -f %d:%i "$dest" && [ "$DI2" = "$DI" ] || { mv -- "$dest" "$P" 2>/dev/null; gfail G8 2 "이동한 대상 장치·inode 다름 — 원위치 복원"; return; }
  rm -r -f -- "$dest" 2>/dev/null || { r=$?; [ ! -e "$dest" ] || mv -- "$dest" "$P" 2>/dev/null; GWHY="삭제 명령 실패(rm rc=$r) · 원위치 복원 시도"; return 4; }
  return 0
}
done_run() { # <경로> --done: 등록된 «내» 사본만 지운다(r897 r10: 주인 자신 · 정확 대조 · 붙잡음/못 읽음 rc4 · r5: 삭제는 출구 게이트 delete_copy · 신원 불일치 rc2)
  local P="$1" REG_OWN ME rc
  [ -n "$P" ] || die "등록된 사본이 아님: <없음>" 2
  has_ctl "$P" && die "등록 불가 경로(탭·개행): $P" 2   # r897 r10.2: 그런 등록 줄은 존재할 수 없다
  cap REG_OWN reg_owner "$P" 2>/dev/null || die "등록부 못 읽음 — 삭제 0: $P" 4
  [ -n "$REG_OWN" ] || die "등록된 사본이 아님: $P" 2
  ME="${FT_SCRATCH_OWNER:-${FT_ME:-}}"
  [ -n "$ME" ] || cap ME tmux display-message -p '#S' 2>/dev/null || ME=-
  [ "$REG_OWN" = "$ME" ] || die "주인 아님(등록 주인 $REG_OWN · 나 $ME) — 남의 사본은 sweep 이 지운다" 2
  RBUD=0; delete_copy "$P" reg "$ME" done; rc=$?
  case "$rc" in
    0) echo "DONE $P";;
    1) die "붙잡음($GWHY) — 쓰는 중인 사본은 지우지 않는다: $P" 4;;
    2) die "못 읽음($GWHY) — lsof·등록부·git 확인 실패 · 삭제 0: $P" 4;;
    3) die "등록된 사본이 아니다/신원 불일치($GWHY) — 삭제 0: $P" 2;;
    *) die "제거 실패($GWHY): $P" 4;;
  esac
}
sweep_run() { # --sweep: 주인 없는 사본 정리(판정 1920 · r548 · r444 · r897 r10) — 하나라도 못 읽으면 삭제 0
  local k p ty why own rc now today g l DEL=0 DK=0 DREG=0 RSTART RSTOP=0
  cap today date +%F   # 표시 전용(로그 날짜)
  orphans
  # r10.5: 시계를 못 읽었으면 24시간·빠른 길을 못 가린다 — 로그·stdout ERROR 1줄 + 삭제 0
  if [ "$READ_OK" = 0 ]; then printf '%s ERROR 시계 못 읽음 — 삭제 0\n' "$today" >> "$SLOG"
    echo "ERROR 시계(date) 못 읽음 — 임시 사본 정리 생략·삭제 0"; return 0; fi
  # r548: cwd 를 못 물으면 «아무도 안 씀» 으로 읽지 않는다 — 로그·stdout ERROR 1줄 + 삭제 0(등록 사본·tmp.* 포함)
  if [ "$LSOF_OK" = 0 ]; then printf '%s ERROR lsof 실패 — 삭제 0\n' "$today" >> "$SLOG"
    echo "ERROR lsof 실패 — 임시 사본 정리 생략·삭제 0 (cwd 판정 불가)"; return 0; fi
  # r444: launchd 에서 tmux 를 못 읽으면 «생략» 으로 조용히 끝내지 않는다 — stdout 1줄(호출자가 planner 쪽지로) + 삭제 0(tmp.* 포함)
  if [ "$TMUX_OK" = 0 ]; then printf '%s ERROR tmux unreadable — 삭제 0 (tmux=%s)\n' "$today" "${TMUX_BIN:-없음}" >> "$SLOG"
    echo "ERROR tmux unreadable — 임시 사본 정리 생략·삭제 0 (tmux=${TMUX_BIN:-없음} · FT_TMUX_BIN/FT_TMUX_SOCKET 확인)"; return 0; fi
  [ "$HELD" = 0 ] || held_report "$today"   # r548: 붙잡은 사본은 지우지 않고 알린다(삭제 후보 0 이어도 알린다)
  [ "$N" != 0 ] || return 0
  if [ ! -f "$ARMED" ]; then
    date +%s > "$ARMED"; cap g gib "$K"; cap l first_paths "$ORPH"   # 표시 전용
    printf '%s [목록 보고 · 실삭제 0] %s개 %s GiB\n%s' "$today" "$N" "$g" "$ORPH" >> "$SLOG"
    printf '[임시 사본 목록 보고 · 실삭제 0 · 다음 정리부터 자동] 주인 없는 사본 %s개 %s GiB: %s\n' "$N" "$g" "$l"; return 0
  fi
  cap RSTART date +%s && isnum "$RSTART" || { printf '%s ERROR 시계 못 읽음 — 삭제 0\n' "$today" >> "$SLOG"; echo "ERROR 시계(date) 못 읽음 — 임시 사본 정리 생략·삭제 0"; return 0; }
  RBUD=$(( RSTART + 70 ))
  # r897 r5: 삭제는 출구 게이트 delete_copy 한 곳 — 그 자리에서 신원·주인·점유·자격을 다시 읽는다 · rc2 = 남은 항목 전부 삭제 0 · rc3 = 그 항목만 건너뜀(하드 룰 12: 70초)
  while IFS="$TAB" read -r k p ty why own; do
    [ -n "$p" ] || continue
    [ "$RSTOP" = 0 ] || continue
    cap now date +%s && isnum "$now" || { RSTOP=1; echo "WARN ft-scratch-repo — 시계 못 읽음 · 남은 항목 삭제 0" >&2; continue; }
    if [ $(( now - RSTART )) -gt 70 ]; then RSTOP=1; echo "WARN ft-scratch-repo — 재확인 70초 초과 · 남은 항목은 다음 정리로" >&2; continue; fi
    delete_copy "$p" "$ty" "${own:--}" sweep; rc=$?
    case "$rc" in
      0) DEL=$((DEL+1)); case "$k" in ''|*[!0-9]*) ;; *) DK=$((DK+k));; esac; [ "$ty" != reg ] || DREG=$((DREG+1)); printf '%s 삭제 %s (%s)\n' "$today" "$p" "$why" >> "$SLOG";;
      1) HELD=$((HELD+1)); printf '%s 붙잡음 %s (%s · 주인 %s)\n' "$today" "$p" "$GWHY" "${own:--}" >> "$SLOG"
         echo "[장비 정리] 사본 $p — 재확인에서 쓰는 중·주인 생김($GWHY) — 삭제 보류";;
      3) printf '%s REFUSED %s (%s)\n' "$today" "$p" "$GWHY" >> "$SLOG"
         echo "WARN ft-scratch-repo — gate refused $p ($GWHY) · 이 항목만 건너뜀" >&2;;
      4) printf '%s ERROR 삭제 실패 %s (%s)\n' "$today" "$p" "$GWHY" >> "$SLOG"
         echo "ERROR 삭제 실패: $p ($GWHY) — 다음 정리에서 재시도" >&2;;
      *) RSTOP=1; printf '%s ERROR 재확인 못 읽음 — 남은 항목 삭제 0 (%s)\n' "$today" "$GWHY" >> "$SLOG"
         echo "WARN ft-scratch-repo — 재확인 못 읽음(rc=$rc · $GWHY) · 남은 항목 전부 삭제 0" >&2;;
    esac
  done <<EOF
$ORPH
EOF
  printf '%s swept=%s owner-dead=%s tmp=%s held=%s\n' "$today" "$DEL" "$DREG" "$((DEL-DREG))" "$HELD" >> "$SLOG"
  cap g gib "$DK"   # 표시 전용
  [ "$DEL" = 0 ] || printf '[임시 사본 자동 삭제] 주인 없는 사본 %s개 %s GiB 삭제(되살릴 수 있는 사본만) — 목록: .fable-team/state/scratch-sweep.log\n' "$DEL" "$g"
}

case "${1:-}" in
  --done) done_run "${2:-}";;
  --judged)
    P="${2:-}"; [ -n "$P" ] && [ -d "$P" ] && registered "$P" || die "등록된 사본이 아님: ${P:-<없음>}" 2
    judged "$P"; exit $?;;
  --report)
    [ "${2:-}" != --orphans ] || { unregistered_copies; exit 0; }
    orphans
    if [ "${2:-}" = --summary ]; then [ "$N" = 0 ] || printf '주인 없는 임시 사본 %s개 %s GiB\n' "$N" "$(gib "$K")"
    else printf '%s%s' "$ORPH" "$HOLD" | awk -F'\t' '$2!=""{k=$1; if (k !~ /^[0-9]+$/) k=0; printf "%s\t%s\t%s\n", sprintf("%.2f", k/1048576), $2, $4}'; fi;;   # r548: 붙잡은 사본도 «붙잡음 pid …» 칸으로 보인다 · --summary 는 지울 수 있는 것만 센다
  --sweep) sweep_run;;
  --gate)   # r5: 출구 게이트를 «삭제 단계 없이» 돌린다 — 조건별 줄 + rc · 삭제 0
    P="${2:-}"; shift 2 2>/dev/null || shift $#; GK=""; GO=""
    while [ $# -gt 0 ]; do case "$1" in
      --kind) [ $# -ge 2 ] || die "--kind 뒤에 reg|tmp" 2; GK="$2"; shift 2;;
      --owner) [ $# -ge 2 ] || die "--owner 뒤에 주인" 2; GO="$2"; shift 2;;
      *) die "모르는 인자: $1" 2;;
    esac; done
    [ -n "$GK" ] || case "${P##*/}" in repo-*) GK=reg;; *) GK=tmp;; esac
    if [ -z "$GO" ]; then if [ "$GK" = reg ]; then cap GO reg_owner "$P" 2>/dev/null || die "등록부 못 읽음" 4; [ -n "$GO" ] || GO="?"; else GO=-; fi; fi
    GATE_DRY=1; RBUD=0; delete_copy "$P" "$GK" "$GO" sweep; rc=$?; echo "GATE rc=$rc"; exit "$rc";;
  -*|"") die "usage: ft-scratch-repo.sh <sha|ref> [--repo <저장소>] [--full] [--with <경로>]… | --done <경로> | --judged <경로> | --report [--summary|--orphans] | --sweep | --gate <경로> [--kind reg|tmp] [--owner O]" 2;;
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
    SPEC="$(want_spec)"
    while IFS="$(printf '\t')" read -r p ow t; do   # r444: 같은 sha·같은 주인 사본이 살아 있으면 재사용(사본 0 추가) · r891: 체크아웃 규칙도 같을 때만
      [ "$ow" = "$OWNER" ] && [ -d "$p" ] && [ "$(git -C "$p" rev-parse HEAD 2>/dev/null)" = "$SHA" ] && [ "$(spec_of "$p")" = "$SPEC" ] && { echo "$p"; exit 0; }
    done < <(cat "$TSV" 2>/dev/null)
    BASE="${FT_SCRATCH_DIR:-${TMPDIR:-/tmp}}"; mkdir -p "$BASE"
    DEST="${BASE%/}/repo-$(printf '%.8s' "$SHA")-$(date +%s)-$$"
    has_ctl "$DEST" && die "등록 불가 경로(탭·개행): $DEST" 2   # r897 r10.2: TSV 로 표현 못 하는 경로면 사본을 만들지 않는다
    if [ "$FULL" = 1 ]; then git -C "$SRC" worktree add -q --detach "$DEST" "$SHA" >/dev/null || die "worktree add 실패: $DEST" 4
    else   # r891: 설계 폴더(design/teams/*)·증거 미디어 빼고 체크아웃 — 사본당 1.4G·파일 수만 개 → 코드·시험·하네스 경로만
      git -C "$SRC" worktree add -q --no-checkout --detach "$DEST" "$SHA" >/dev/null || die "worktree add 실패: $DEST" 4
      printf '%s\n' "$SPEC" | git -C "$DEST" sparse-checkout set --no-cone --stdin >/dev/null 2>&1 && git -C "$DEST" checkout -q >/dev/null 2>&1 \
        || die "sparse 체크아웃 실패: $DEST (반쯤 만든 폴더는 등록 밖 — --report --orphans 에 보임 · 지우기 0 · 통째 = --full)" 4
    fi
    # r891 r7: 등록은 체크아웃이 «다 끝난 뒤» 마지막 단계(기준판 순서) — 등록 줄이 있는 사본 = 체크아웃 끝난 사본 · 생성은 아무것도 지우지 않는다
    printf '%s\t%s\t%s\t%s\n' "$DEST" "$OWNER" "$(date +%s)" "${BASE%/}" >> "$TSV"; warn_many "$OWNER"; echo "$DEST";;
esac
