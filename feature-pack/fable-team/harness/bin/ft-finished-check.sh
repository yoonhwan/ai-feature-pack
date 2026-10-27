#!/usr/bin/env bash
# ft-finished-check.sh <폴더|브랜치> [--repo <리포>] — 끝난 것 판정기 하나(r444 · planner 설계 §2 E0~E3). 정리 도구는 전부 이것만 본다. 삭제·이동 0.
#   출력 1행 = `FINISHED|EMPTY|ACTIVE|ORPHAN <대상>` · 2행부터 근거 `E0~E3 ok|no …` · `branch=… sha=… card=…`.
#   ★rc 계약 = 0 또는 2 뿐 — 0 = 정상 판정(FINISHED·EMPTY·ACTIVE·ORPHAN **전부**) · 2 = 판정 불가(ERROR — 호출자는 «안 끝남» 으로 다룬다). 1 은 나오지 않는다(DA⑥ r4 HOLD 1 · r5).★
#   E0 폴더 porcelain 0(폴더 없으면 참) · E1 카드 `- 착지: <sha>` 가 기준(main) 조상 · E2 카드가 indices/완성/ · E3 좌석 없음(tmux 세션·명부 seats*.json 키·폴더 cwd 프로세스 0)
#   E1f: 가지가 merge-base(main,가지) 이후 바꾼 «각 경로» 에서 main:<경로> 와 <가지 tip>:<경로> 의 (모드·형·blob) 이 «같음» — 없는 경로끼리도 같음. main 과 파일 단위 내용이 같으면 끝(판정 2745 · 오빠 «1.1 2.1 3.1 4.1» 의 2번).
#   순서: E0·E3 하나라도 거짓 = ACTIVE(살아 있는 것 먼저) → 가지가 기준 대비 커밋 0 = EMPTY → E1f 참 = FINISHED(카드 불일치는 WARN 1줄 · 카드 이동은 이 도구 몫 아님) → 카드 0·2+ = ORPHAN → E1·E2 거짓 = ACTIVE → FINISHED.
#   카드 = 가지 이름 nano/<slug>[-rN] 의 slug 와 «카드 파일 이름 slug»(ft-nano-spawn 과 같은 규칙) 가 같은 것 — 팀 폴더는 ft_team_cands_ref(명단 = ref · 폴더 = 리포)만.
#   ★E1f = C≠∅ ∧ C∩D=∅ (C = `<merge-base>..<tip>` diff 이름 · D = `<main>..<tip>` diff 이름) — 경로를 git 에 넘기지 않는다(pathspec 매직 0) · 호출 = `merge-base --all` + diff 2 = 3회 고정★ · 비교 단위 = 파일(블롭·심링크·gitlink) — 폴더(tree) 자체의 존재 차이는 정의 밖(DA⑥ r3 정의)
#   ★여러 merge-base(criss-cross · `merge-base --all` >1) = rc2 «판정 불가»(안 끝남 쪽)★ · 서브모듈 변경은 리포·전역 설정(`diff.ignoreSubmodules`)을 덮고 잡는다 · 경로는 바이트로 읽고 비교하며, 화면에 낼 때만 비 UTF-8 바이트·개행을 `\xNN`/`\n` 으로 이스케이프한다(판정 자체는 바이트 집합)
#   env: FT_FINISHED_MAIN(기준 ref · 기본 origin/main 있으면 그것 없으면 main) · FT_TEAMS_REF · FT_TMUX_BIN · FT_TMUX_SOCKET · FT_SEATS_DIR(기본 <리포>/.fable-team)
#        FT_FINISHED_GIT(기본 git · 시험용 대역) · FT_FINISHED_GIT_TIMEOUT_S(E1f git 읽기 1회 상한 · 기본 7초 · 넘으면 rc2 «판정 불가»)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
T="${1:-}"; shift 2>/dev/null; R=""
while [ $# -gt 0 ]; do case "$1" in --repo) R="${2:-}"; shift 2;; *) echo "usage: $0 <폴더|브랜치> [--repo <리포>]" >&2; exit 2;; esac; done
[ -n "$T" ] || { echo "usage: $0 <폴더|브랜치> [--repo <리포>]" >&2; exit 2; }
err() { echo "ERROR $1"; exit 2; }
[ -f "$HERE/ft-team-lib.sh" ] || err "ft-team-lib.sh 없음: $HERE"
. "$HERE/ft-team-lib.sh"
DIR=""; BR=""
if [ -d "$T" ]; then DIR="$(cd "$T" && pwd -P)"; [ -n "$R" ] || R="$(git -C "$DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
  BR="$(git -C "$DIR" symbolic-ref -q --short HEAD 2>/dev/null)"
else BR="${T#refs/heads/}"; fi
[ -n "$R" ] || R="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
[ -n "$R" ] && [ -d "$R" ] || err "리포를 못 찾음(--repo 필요): ${R:-<없음>}"
M="${FT_FINISHED_MAIN:-}"; [ -n "$M" ] || { git -C "$R" rev-parse -q --verify origin/main >/dev/null && M=origin/main || M=main; }
git -C "$R" rev-parse -q --verify "$M^{commit}" >/dev/null || err "기준 ref 없음: $M"
if [ -n "$BR" ]; then SHA="$(git -C "$R" rev-parse -q --verify "refs/heads/$BR^{commit}")" || err "가지 없음: $BR"
  [ -n "$DIR" ] || DIR="$(git -C "$R" worktree list --porcelain | awk -v b="branch refs/heads/$BR" '/^worktree /{p=substr($0,10)} $0==b{print p; exit}')"
else SHA="$(git -C "$DIR" rev-parse -q --verify HEAD)" || err "폴더 HEAD 없음: $DIR"; fi
SLUG="${BR#nano/}"; [ "$SLUG" != "$BR" ] || SLUG=""; SLUG="$(printf '%s' "$SLUG" | sed -E 's/-r[0-9]+$//')"
# 카드 찾기 — 팀 명단(ref) × 폴더(리포) 후보의 indices/{대기,진행,완성}/*.md 중 파일 이름 slug 가 같은 것
CARDS=()
if [ -n "$SLUG" ]; then
  MD="$(mktemp)" || err "mktemp 실패"; trap 'rm -f "$MD"' EXIT
  git -C "$R" show "${FT_TEAMS_REF:-origin/main}:design/TEAMS.md" > "$MD" 2>/dev/null || err "팀 명단(${FT_TEAMS_REF:-origin/main}:design/TEAMS.md)을 못 읽음: $R"
  # 카드 루트 = FT_FINISHED_CARD_ROOTS(: 구분) → 원장 워크트리(FT_NANO_LEDGER_WT · 기본 <리포>/.worktrees/v6-realtime-live) → 리포 — 카드가 나온 «첫 루트» 만 쓴다(미커밋 이동이 루트마다 다르다)
  IFS=: read -r -a BASES <<< "${FT_FINISHED_CARD_ROOTS:-${FT_NANO_LEDGER_WT:-$R/.worktrees/v6-realtime-live}}"; BASES+=("$R")
  for b in "${BASES[@]}"; do [ -d "$b" ] && [ "${#CARDS[@]}" = 0 ] || continue
    for t in $(ft_team_names "$MD"); do
      while IFS= read -r c; do [ -n "$c" ] || continue
        for f in "$c"/indices/대기/*.md "$c"/indices/진행/*.md "$c"/indices/완성/*.md; do [ -f "$f" ] || continue
          s="$(basename "$f" .md | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-40)"; [ "$s" = "$SLUG" ] && CARDS+=("$f")
        done
      done < <(ft_team_cands_ref "$b" "$t" "${FT_TEAMS_REF:-origin/main}" 2>/dev/null)
    done
  done
fi
CARD=""; [ "${#CARDS[@]}" = 1 ] && CARD="${CARDS[0]}"
# E0 — 폴더 porcelain 0
E0=1; E0W="폴더 없음"; if [ -n "$DIR" ] && [ -d "$DIR" ]; then E0W="$DIR"; [ -z "$(git -C "$DIR" status --porcelain 2>/dev/null)" ] || { E0=0; E0W="미커밋 있음 $DIR"; }; fi
# E3 — 좌석 없음. tmux 목록을 못 읽으면 «없음» 으로 세지 않는다(ACTIVE · #0 RULE)
E3=1; E3W=""; TB="${FT_TMUX_BIN:-$(command -v tmux 2>/dev/null)}"
for _t in /opt/homebrew/bin/tmux /usr/local/bin/tmux; do [ -n "$TB" ] || { [ -x "$_t" ] && TB="$_t"; }; done
if [ -n "$SLUG" ]; then
  if S="$("${TB:-false}" ${FT_TMUX_SOCKET:+-S "$FT_TMUX_SOCKET"} list-sessions -F '#{session_name}' 2>/dev/null)"; then
    hit="$(printf '%s\n' "$S" | grep -F -- "$SLUG#" | head -1)"; [ -z "$hit" ] || { E3=0; E3W="tmux $hit"; }
  else E3=0; E3W="tmux 목록 못 읽음(tmux=${TB:-없음})"; fi
  if [ "$E3" = 1 ]; then hit="$(python3 - "$SLUG#" "${FT_SEATS_DIR:-$R/.fable-team}" <<'PY'
import glob, json, os, sys
for f in sorted(glob.glob(os.path.join(sys.argv[2], "seats*.json"))):
    try: d = json.load(open(f, encoding="utf-8"))
    except (OSError, ValueError): continue
    for k, v in d.items():
        if sys.argv[1] in k and isinstance(v, dict) and not v.get("_replaced_by"): print(os.path.basename(f) + ":" + k); sys.exit(0)
PY
)"; [ -z "$hit" ] || { E3=0; E3W="명부 $hit"; }; fi
fi
if [ "$E3" = 1 ] && [ -n "$DIR" ] && [ -d "$DIR" ]; then
  hit="$(lsof -w -d cwd -Fpn 2>/dev/null | awk -v d="$DIR" '/^p/{p=substr($0,2)} /^n/{n=substr($0,2); if (n==d || index(n, d "/")==1) {print "pid " p; exit}}')"
  [ -z "$hit" ] || { E3=0; E3W="cwd $hit"; }
fi
[ -n "$E3W" ] || E3W="좌석 0"
# E1·E2 — 카드
E1=0; E1W="카드 없음"; E2=0; E2W="카드 없음"
if [ -n "$CARD" ]; then
  L="$(sed -nE 's/^[[:space:]]*-[[:space:]]*착지:[[:space:]]*([0-9a-f]{7,40}).*/\1/p' "$CARD" | tail -1)"
  if [ -z "$L" ]; then E1W="착지 줄 없음"
  elif git -C "$R" merge-base --is-ancestor "$L" "$M" 2>/dev/null; then E1=1; E1W="착지 $L ⊂ $M"
  else
    # r978 고침 2 — 코드 0 문서 카드면 문서 가지 착지도 인정(조건 셋은 ft_doc_card_landed 한 곳) · 아니면 지금처럼 origin/main 조상만
    _dc=""; _dc="$(ft_doc_card_landed "$R" "$L" "$CARD" 2>/dev/null)"; _drc=$?
    if [ "$_drc" -eq 0 ]; then E1=1; E1W="착지 $L ⊂ ${FT_DOC_LAND_REF:-origin/ops/main-base}(문서 카드 · 설치는 없음 · design/**.md 만)"
    else E1W="착지 $L 가 $M 조상 아님(${_dc:-문서 카드 아님})"; fi
  fi
  case "$CARD" in */indices/완성/*) E2=1; E2W="완성/";; *) E2W="$(basename "$(dirname "$CARD")")/";; esac
fi
AHEAD="$(git -C "$R" rev-list --count "$M..$SHA" 2>/dev/null)" || err "rev-list 실패: $M..$SHA"
# E1f — main 과 파일 단위 내용 같음. python3 한 번: merge-base → 바꾼 경로 → 두 rev 의 (모드·형·sha) 대조. 읽기 실패·시간 초과 = rc2(«안 끝남» 쪽 · 조용한 FINISHED 0)
E1F=0; E1FW="files=0 (ahead=0 — E1f 대상 아님)"; E1FN=0
if [ "$AHEAD" != 0 ]; then
  command -v python3 >/dev/null 2>&1 || err "python3 없음 — E1f 판정 불가"
  J="$(FT_FINISHED_GIT="${FT_FINISHED_GIT:-git}" FT_FINISHED_GIT_TIMEOUT_S="${FT_FINISHED_GIT_TIMEOUT_S:-7}" \
       FT_FINISHED_DEADLINE_S="${FT_FINISHED_DEADLINE_S:-70}" python3 - "$R" "$M" "$SHA" <<'PY'
# E1f = C ≠ ∅ ∧ C ∩ D = ∅   (C = 가지가 merge-base 이후 바꾼 경로 · D = 지금 main 과 tip 이 다른 경로)
#   경로를 git 에 넘기지 않는다(순수 pathspec 매직 오판 0) · 호출은 merge-base + diff 2 = 3회 고정(쪼개기·누적 시간 0)
import os, subprocess, sys, time
repo, main, tip = sys.argv[1], sys.argv[2], sys.argv[3]
GIT = os.environ.get("FT_FINISHED_GIT") or "git"
def num(k, d):
    try: return float(os.environ.get(k) or d)
    except ValueError: return float(d)
CALL = num("FT_FINISHED_GIT_TIMEOUT_S", 7)     # 호출 1회 상한(7초 룰)
DEAD = num("FT_FINISHED_DEADLINE_S", 70)       # 전체 마감(하드 룰 12 · 남은 시간으로 다음 호출을 줄인다)
T0 = time.monotonic()
def bad(msg): sys.exit("ERROR ft-finished-check E1f: %s" % msg)
def run(*a):
    left = DEAD - (time.monotonic() - T0)
    if left <= 0: bad("총 마감 %.0fs 초과 — 남은 시간 0 %s" % (DEAD, " ".join(a)))
    try: p = subprocess.run([GIT, "-C", repo] + list(a), capture_output=True, timeout=min(CALL, left))
    except subprocess.TimeoutExpired: bad("git 시간 초과(호출 상한 %.3gs · 남은 %.3gs) %s" % (CALL, left, " ".join(a)))
    except OSError as e: bad("git 실행 실패 %s: %s" % (GIT, e))
    if p.returncode != 0: bad("git rc=%d %s %s" % (p.returncode, " ".join(a), p.stderr.decode("utf-8", "replace").strip()[:200]))
    return p.stdout
mbs = run("merge-base", "--all", main, tip).decode().split()
if len(mbs) != 1: bad("여러 merge-base(%d개) 또는 없음 — criss-cross 는 판정 불가 %s %s" % (len(mbs), main, tip))
# 리포·전역 설정(diff.ignoreSubmodules)을 명시로 덮는다(서브모듈 변경도 잡는다) · 외부 diff·textconv 0
OPTS = ("-c", "diff.ignoreSubmodules=none", "diff", "--ignore-submodules=none", "--no-renames", "--no-ext-diff", "--no-textconv", "--name-only", "-z")
def names(a, b):
    return {p for p in run(*(OPTS + (a, b))).split(b"\0") if p}   # 경로는 바이트 그대로(정렬·정규화 0)
def disp(raw):
    # 표시용 1줄 — 비 UTF-8 바이트는 \xNN · 개행/탭은 \n/\t (경로 자체는 바이트 그대로 판정한다)
    out = []
    for c in raw.decode("utf-8", "surrogateescape"):
        o = ord(c)
        if 0xDC80 <= o <= 0xDCFF: out.append("\\x%02x" % (o - 0xDC00))
        elif c == "\n": out.append("\\n")
        elif c == "\r": out.append("\\r")
        elif c == "\t": out.append("\\t")
        else: out.append(c)
    return "".join(out)
def emit(s):
    # stdout 인코딩(locale)에 기대지 않는다 — UTF-8 고정 + 실패 바이트는 backslashreplace
    sys.stdout.buffer.write(s.encode("utf-8", "backslashreplace") + b"\n")
C = names(mbs[0], tip)
if not C: emit("none 0"); raise SystemExit(0)
D = names(main, tip)
var = sorted(C & D)
if var: emit("no %d" % len(var)); emit(disp(var[0]))
else: emit("ok %d" % len(C))
PY
)" || err "E1f 판정 불가 — git 읽기 실패·시간 초과(«안 끝남» 쪽)"
  J1="${J%%$'\n'*}"; J2="${J#*$'\n'}"; [ "$J2" = "$J" ] && J2=""
  case "$J1" in
    ok\ *) E1F=1; E1FN="${J1#ok }"; E1FW="files=${E1FN}";;
    none* ) E1FW="files=0 (바꾼 파일 없음 — E1f 대상 아님 · 카드 규칙으로)";;
    no\ *) E1FN="${J1#no }"; E1FW="files=${E1FN} first=${J2:-?}";;
    *) err "E1f 출력 해석 실패: $J1";;
  esac
fi
if [ "$E0" = 0 ] || [ "$E3" = 0 ]; then V=ACTIVE
elif [ "$AHEAD" = 0 ]; then V=EMPTY
elif [ "$E1F" = 1 ]; then V=FINISHED
elif [ -z "$CARD" ]; then V=ORPHAN
elif [ "$E1" = 0 ] || [ "$E2" = 0 ]; then V=ACTIVE
else V=FINISHED; fi
echo "$V $T"
echo "E0 $([ "$E0" = 1 ] && echo ok || echo no) $E0W"
echo "E1 $([ "$E1" = 1 ] && echo ok || echo no) $E1W"
echo "E2 $([ "$E2" = 1 ] && echo ok || echo no) $E2W"
echo "E3 $([ "$E3" = 1 ] && echo ok || echo no) $E3W"
echo "E1f $([ "$E1F" = 1 ] && echo ok || echo no) $E1FW"
echo "branch=${BR:-<detached>} sha=$SHA ahead=$AHEAD main=$M card=${CARD:-<${#CARDS[@]}개>} dir=${DIR:-<없음>}"
if [ "$E1F" = 1 ] && [ "$V" = FINISHED ]; then { [ "$E1" = 1 ] && [ "$E2" = 1 ] || echo "WARN card ${CARD:-없음} — E1f ok 로 끝 처리(착지 줄·완성/ 불일치) · 카드 이동은 이 도구 몫 아님"; }; fi
exit 0   # rc 계약: 정상 판정(무슨 갈래든) = 0 · 판정 불가 = 2(위 err 경로)
