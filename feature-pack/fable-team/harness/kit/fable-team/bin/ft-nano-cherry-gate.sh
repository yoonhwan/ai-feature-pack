#!/usr/bin/env bash
# ft-nano-cherry-gate.sh <feat 브랜치> <nano 브랜치> [--repo <dir>]
#   ft-nano-close.sh 의 «산출물이 들어왔는가» 게이트 (G4 · 골좌표 M7 — 나노 브랜치에만 남은 커밋은 feat push 가 따라오지 않는다).
#   `git cherry <feat> <nano>` 의 «+»(feat 에 같은 patch 가 없는 커밋): design/ 밖 경로를 건드린 것이 있으면 목록 출력 + exit 1 ·
#   design/ 만 건드린 «+» 는 WARN 목록 + exit 0(브랜치 보존으로 복구 가능 — G4 실측 docs-only 134 를 전부 막으면 닫기 정지) · «+» 0 이면 `OK` + exit 0.
#   코드 «+» 는 ①merge-tree 실제 delta 가 design/ 밖 0 → PASS(content_landed_via_merge_tree) ②충돌·delta 면 «+» 경로마다 tip 의 (mode,blob) 이 feat 역사에 있으면 PASS(content_landed_then_superseded) ③아니면 REJECT.
#   면제 목록·무조건 우회 없음. 유일한 사람 우회 = `--override "<사유>"`(코드 «+» 의 내용 REJECT 만 · 사유 빈 문자열 거부 · ERROR 로그 + 원장 1행 — #0 RULE 예외 3조건).
#   --mode land|close (기본 close = 위 동작 그대로): land = 랜딩 «요청» 시점 — nano 가 feat HEAD 를 조상으로 포함(최신 루트 병합 완료)하지 않으면 REJECT(M7 · single_set_testing §2 규칙 2).
#   close 에는 이 검사를 걸지 않는다 — squash 랜딩 뒤엔 feat 가 앞서 가 «포함» 이 항상 거짓이다(REVIEW arch141 §2-3).
#   exit 0 = 통과 · 1 = REJECT(+ 있음 / ref 없음 / git 실패 — 전부 사유 stdout) · 2 = usage. ★침묵 통과 0★ — 어느 경로든 한 줄 이상 출력한다.
set -uo pipefail
#   squash 랜딩 전용 = `--squashed-pr <N> --reason "<사유>"`(R29 · 둘 다 필요 · --override 와 동시 사용 불가): PR 사실(gh) + 경로 분류(ft-nano-cherry-pr.sh) 뒤
#   «PR 안에서 고쳐짐» 만 사유로 통과(되돌림·제거·PR 에 없음 = 플래그로도 REJECT) · 원장 kind=squashed-pr 1행. 플래그 없으면 위 동작 그대로.
#   superseded 검사에서 WARN 으로 낮추는 경로 = design/ 아래 문서 종류(md html png jpg jpeg svg pdf)만 — 그 밖은 코드 경로.
#   ★r958 묶음 호출(하드 룰 12 · 외부 호출 7초 룰)★ — «+» 커밋마다 log·diff-tree 2회, 경로마다 ls-tree·log 3회 부르면 커밋·경로 수에 비례해 늘어난다
#   (실사건: 커밋 많은 나노가 닫기 ⑤ 에서 70초 초과 REJECT 2회 · planner #170097). 묶음 1회로 묻고, 1회 상한 FT_CHERRY_LIM_S(기본 7초)를 넘으면
#   그 묶음을 반으로 쪼개 «재시도 1»(ⓒ) · 항목 하나까지 쪼개도 넘으면 사유 있는 REJECT · 끝난 묶음은 FT_CHERRY_PROGRESS 파일에 남겨 다시 부르면 건너뛴다(ⓓ).
#   FT_CHERRY_BATCH(기본 100) = 한 묶음의 최대 항목 수(닫기 쪽 상한 계산과 같은 값이어야 한다 · ft-nano-close.sh nf_mult_batches).
USAGE="usage: $0 <feat-branch> <nano-branch> [--repo <dir>] [--mode land|close] [--override <사유>] [--squashed-pr <N> --reason <사유>]"
FEAT="${1:-}"; NANO="${2:-}"; shift 2 2>/dev/null || { echo "$USAGE" >&2; exit 2; }
REPO="."; HAVE_OVERRIDE=0; OVERRIDE=""; MODE="close"; SQUASHED_PR=""; HAVE_REASON=0; REASON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-.}"; shift 2 2>/dev/null || shift ;;
    --mode) MODE="${2:-}"; shift 2 2>/dev/null || shift
            case "$MODE" in land|close) ;; *) echo "usage: --mode land|close (받은 값: ${MODE:-<빈 값>})" >&2; exit 2 ;; esac ;;
    --override) HAVE_OVERRIDE=1; OVERRIDE="${2:-}"; shift 2 2>/dev/null || shift ;;
    --squashed-pr) SQUASHED_PR="${2:-}"; shift 2 2>/dev/null || shift
                   [[ "$SQUASHED_PR" =~ ^[0-9]+$ ]] || { echo "usage: --squashed-pr <PR 번호> (받은 값: ${SQUASHED_PR:-<빈 값>})" >&2; exit 2; } ;;
    --reason) HAVE_REASON=1; REASON="${2:-}"; shift 2 2>/dev/null || shift ;;
    *) echo "$USAGE" >&2; exit 2 ;;
  esac
done
[ "$HAVE_OVERRIDE" -eq 0 ] || [ -z "$SQUASHED_PR" ] || { echo "usage: --squashed-pr 와 --override 는 동시에 못 쓴다(우회 길이 둘이 되면 원장 의미가 갈린다)" >&2; exit 2; }
[ -n "$SQUASHED_PR" ] || [ "$HAVE_REASON" -eq 0 ] || { echo "usage: --reason 은 --squashed-pr 와 함께만 쓴다" >&2; exit 2; }
[ -z "$SQUASHED_PR" ] || [ "$HAVE_REASON" -eq 1 ] || { echo "usage: --squashed-pr 에는 --reason \"<사유>\" 가 필요하다" >&2; exit 2; }
if [ "$HAVE_OVERRIDE" -eq 1 ] && [ -z "${OVERRIDE//[[:space:]]/}" ]; then
  echo "REJECT cherry 게이트 — --override 사유가 비어 있음(사유 없는 우회 거부)"; exit 1
fi
if [ -n "$SQUASHED_PR" ] && [ -z "${REASON//[[:space:]]/}" ]; then
  echo "REJECT cherry 게이트 — --reason 사유가 비어 있음(사유 없는 --squashed-pr 거부)"; exit 1
fi
# 플래그를 쓸 때만 분류 도우미를 읽는다 — 플래그 없는 기존 닫기는 이 파일 하나만 있어도 그대로 돈다(런타임 bin 에 pr.sh 가 아직 없어도 닫기 0 영향).
if [ -n "$SQUASHED_PR" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ft-nano-cherry-pr.sh" || { echo "REJECT cherry 게이트 — --squashed-pr: ft-nano-cherry-pr.sh 를 못 읽음(같은 디렉터리에 있어야 함)"; exit 1; }
fi
# ★r958 묶음 호출 도구★ — CG_LIM = 외부 호출 1회 상한(초 · 시험은 FT_CHERRY_LIM_S 로 줄인다) · CG_BATCH = 한 묶음 항목 수 · CG_PROG = 진행 파일(없으면 매번 새로 잰다).
CG_LIM="${FT_CHERRY_LIM_S:-7}"; CG_BATCH="${FT_CHERRY_BATCH:-100}"; CG_PROG="${FT_CHERRY_PROGRESS:-}"
case "$CG_LIM" in ''|0|*[!0-9]*) CG_LIM=7;; esac
case "$CG_BATCH" in ''|0|*[!0-9]*) CG_BATCH=100;; esac
CG_PYDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# cg_git <초> <git 인자…> — 리포는 $REPO · stdout 만 넘긴다 · 시간 초과 rc 124(자식 프로세스 그룹까지 정리 · 재시도 1 은 ft_git_capped.py 안)
cg_git() { local lim="$1"; shift
  if [ -f "$CG_PYDIR/ft_git_capped.py" ]; then python3 "$CG_PYDIR/ft_git_capped.py" "$lim" "$REPO" "$@"; return $?; fi
  echo "WARN cherry 게이트 — $CG_PYDIR/ft_git_capped.py 없음: ${lim}초 상한 없이 git 1회(설치 누락 의심)" >&2
  git -C "$REPO" "$@"
}
# cg_fail <단계> <rc> <묶음 n> <마지막 항목> — rc 124 = 상한 초과(쪼개도 넘음) · 그 밖 = git 실패. 둘 다 사유 있는 REJECT(조용한 통과 0).
cg_fail() {
  if [ "$2" -eq 124 ]; then echo "REJECT cherry 게이트 — $1 ${CG_LIM}초 초과(묶음 $3 · 마지막 $4) — 쪼개도 넘어 판정 불가(조용한 통과 0)"
  else echo "REJECT cherry 게이트 — $1 git 실패(rc=$2) 마지막 $4 — 판정 불가(조용한 통과 0)"; fi
  exit 1
}
# 진행 파일 한 묶음 = 헤더 1줄 `#B<TAB>단계<TAB>첫 항목<TAB>개수<TAB>출력 줄 수` + 그 줄 수만큼의 출력 줄(ⓓ).
cg_prog_get() {  # <단계> <첫 항목> <개수> → CG_PGOUT · CG_PG=1 이면 «저장된 묶음이 있었다»(서브셸 없이 전역으로 돌려준다 — command substitution 은 변수를 못 물려준다)
  CG_PG=0; CG_PGOUT=""
  [ -n "$CG_PROG" ] && [ -f "$CG_PROG" ] || return 0
  local rc
  CG_PGOUT="$(awk -F'\t' -v st="$1" -v fi="$2" -v n="$3" '$1=="#B"&&$2==st&&$3==fi&&$4==n{f=NR+1;e=NR+$5;h=1} f&&NR>=f&&NR<=e{print} END{exit(h?0:3)}' "$CG_PROG")"; rc=$?
  [ "$rc" -eq 0 ] || { CG_PGOUT=""; return 0; }
  CG_PG=1
}
cg_prog_put() {  # <단계> <첫 항목> <개수> <출력>
  [ -n "$CG_PROG" ] || return 0
  local n=0
  [ -z "$4" ] || n="$(printf '%s\n' "$4" | wc -l | tr -d ' ')"
  { printf '#B\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$n"; [ "$n" -eq 0 ] || printf '%s\n' "$4"; } >> "$CG_PROG" \
    || echo "WARN cherry 게이트 — 진행 파일 기록 실패($CG_PROG) — 이번 판정은 그대로 쓴다" >&2
}
# cg_fetch <단계> <시작> <끝> <쪼갠 횟수> — CG_ITEMS[시작..끝) 을 CG_CMD 한 번으로 묻고 stdout 을 CG_OUT 에 잇는다. 상한 초과면 반으로 쪼개 재시도 1(ⓒ).
cg_fetch() {
  local st="$1" a="$2" b="$3" d="$4" n out rc
  n=$(( b - a )); [ "$n" -gt 0 ] || return 0
  cg_prog_get "$st" "${CG_ITEMS[$a]}" "$n"
  if [ "$CG_PG" -eq 1 ]; then CG_OUT="$CG_OUT$CG_PGOUT"$'\n'; return 0; fi
  if [ "$n" -gt "$CG_BATCH" ]; then
    cg_fetch "$st" "$a" $(( a + CG_BATCH )) "$d"; cg_fetch "$st" $(( a + CG_BATCH )) "$b" "$d"; return 0
  fi
  out="$("$CG_CMD" "${CG_ITEMS[@]:$a:$n}")"; rc=$?
  if [ "$rc" -eq 124 ] && [ "$n" -gt 1 ] && [ "$d" -lt 1 ]; then   # 쪼개서 «재시도 1» — 반씩 두 번
    cg_fetch "$st" "$a" $(( a + n / 2 )) 1; cg_fetch "$st" $(( a + n / 2 )) "$b" 1; return 0
  fi
  [ "$rc" -eq 0 ] || cg_fail "$st" "$rc" "$n" "${CG_ITEMS[$(( b - 1 ))]}"
  CG_OUT="$CG_OUT$out"$'\n'; cg_prog_put "$st" "${CG_ITEMS[$a]}" "$n" "$out"
}
# cg_cmd_commits <sha…> — 커밋 묶음: 로그 줄(`C <full><TAB><abbrev> <subject>`) + 건드린 경로(원시 줄 `:mode mode old new STATUS<TAB>path`) 를 한 번에.
#   --no-walk=unsorted = 인자 순서 보존 · -m = 머지 커밋은 부모별 delta · --root = 첫 커밋도 · blob 은 기본 축약형(앞자리로 대조 — --no-abbrev 를 걸면 %h 까지 40자가 되어 종전 로그 줄과 달라진다).
cg_cmd_commits() { cg_git "$CG_LIM" -c core.quotepath=false log --no-walk=unsorted --raw -m --root --format='C %H	%h %s' "$@"; }
# cg_cmd_hist <경로…> — 경로 묶음: 분기 뒤 feat 역사의 원시 delta(경로별 «새 blob 이 있었나» 를 한 번에 본다).
cg_cmd_hist() { cg_git "$CG_LIM" -c core.quotepath=false --literal-pathspecs log "$CG_MBASE..$FEAT" --no-renames --format='C %h' --raw -- "$@"; }
# cg_py <모드> <인자…> — 묶음 출력 해석(커밋 분류·경로 분류·이력 대조). 판정 규칙은 종전 루프와 같다.
cg_py() {
  python3 - "$@" <<'PY'
import re, sys
mode = sys.argv[1]
DOC = re.compile(r"^design/.*\.(md|html|png|jpg|jpeg|svg|pdf)$")
def slurp(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8", "surrogateescape")
def tabmap(path):
    m = {}
    for ln in slurp(path).split("\n"):
        if ln:
            parts = ln.split("\t", 2)
            if len(parts) == 3:
                m[parts[2]] = (parts[0], parts[1])
    return m
if mode == "commits":   # 커밋 묶음 → B(차단)·W(WARN)·P(경로)
    block, warn, paths = [], [], []
    cur = None; line = ""; outside = False
    def flush():
        if cur is None:
            return
        (block if outside else warn).append(line)
    for ln in slurp(sys.argv[2]).split("\n"):
        if ln.startswith("C "):
            head, _, rest = ln[2:].partition("\t")
            if head != cur:
                flush(); cur = head; line = ("  + " + rest)[:120]; outside = False
            continue
        if ln.startswith(":") and "\t" in ln:
            p = ln.split("\t", 1)[1]
            paths.append(p)
            if not p.startswith("design/"):
                outside = True
    flush()
    for x in block: print("B\t" + x)
    for x in warn: print("W\t" + x)
    for p in paths: print("P\t" + p)
elif mode == "paths":   # 경로 분류: «경로목록 · tip 트리 · feat HEAD 트리» 대조 → sup/nid/doc/miss/need (nmiss 상한 20 은 종전 루프와 같다)
    feat_name, base = sys.argv[5], sys.argv[6]
    tip, feat = tabmap(sys.argv[3]), tabmap(sys.argv[4])
    nmiss = 0
    for p in slurp(sys.argv[2]).split("\n"):
        if not p or nmiss >= 20:
            break
        t, f = tip.get(p), feat.get(p)
        if t is None:
            if f is None: print("sup\t" + p)
            elif DOC.match(p): print("doc\t" + p)
            else: nmiss += 1; print("miss\t%s\t(tip 삭제 · %s 에는 존재)" % (p, feat_name))
            continue
        if f is not None and f == t: print("nid\t" + p); continue
        print("need\t%s\t%s\t%s" % (p, t[0], t[1]))
elif mode == "hist":   # 이력 대조: need 경로마다 «분기 뒤 feat 구간에 그 blob 이 있었나» — 첫(=최신) 일치가 sup
    feat_name, base = sys.argv[4], sys.argv[5]
    need = []
    for ln in slurp(sys.argv[2]).split("\n"):
        if ln:
            p, m, s = ln.split("\t")[:3]
            need.append((p, m, s))
    pend = {}   # 모드로만 묶는다 — blob 은 앞자리 대조(startswith)라 축약 길이가 달라도 맞는다
    for i, (p, m, s) in enumerate(need):
        pend.setdefault(m, []).append(i)
    hit = {}; cur = ""
    for ln in slurp(sys.argv[3]).split("\n"):
        if ln.startswith("C "):
            cur = ln[2:]; continue
        if not ln.startswith(":") or "\t" not in ln:
            continue
        meta, path = ln[1:].split("\t", 1)[:2]
        f = meta.split(" ")
        if len(f) < 5 or not f[4][:1].isupper():
            continue
        for i in pend.get(f[1], []):
            if need[i][0] == path and i not in hit and need[i][2].startswith(f[3]):
                hit[i] = cur
    for i, (p, m, s) in enumerate(need):
        if i in hit: print("sup\t%s\t%s" % (p, hit[i]))
        elif DOC.match(p): print("doc\t" + p)
        else: print("miss\t%s\t(tip %s %s 가 분기 뒤 %s 구간(%s..)에 새 blob 으로 없음)" % (p, m, s[:9], feat_name, base[:9]))
PY
}
# design/ 아래 문서 종류(md html png jpg jpeg svg pdf)만 0 — 그 밖(sql·sh·py·json·확장자 없음 …)은 코드 경로(ft-nano-cherry-pr.sh 가 이 함수를 쓴다 — gate 가 source 하는 같은 셸).
is_doc_path() {
  case "$1" in design/*.md|design/*.html|design/*.png|design/*.jpg|design/*.jpeg|design/*.svg|design/*.pdf) return 0 ;; esac
  return 1
}
# feat 는 로컬 브랜치 또는 원격 추적 ref(origin/<b>) — 좌석(nano) 브랜치는 로컬이어야 한다(R22).
git -C "$REPO" rev-parse --verify -q "refs/heads/$FEAT" >/dev/null || git -C "$REPO" rev-parse --verify -q "refs/remotes/$FEAT" >/dev/null \
  || { echo "REJECT cherry 게이트 — 브랜치 없음: $FEAT (refs/heads/ · refs/remotes/)"; exit 1; }
git -C "$REPO" rev-parse --verify -q "refs/heads/$NANO" >/dev/null || { echo "REJECT cherry 게이트 — 브랜치 없음: $NANO (refs/heads/)"; exit 1; }
if [ "$MODE" = land ] && ! git -C "$REPO" merge-base --is-ancestor "$FEAT" "$NANO"; then
  _mb="$(git -C "$REPO" merge-base "$FEAT" "$NANO" 2>/dev/null)"
  echo "REJECT cherry 게이트 — land: $NANO 가 feat HEAD($(git -C "$REPO" rev-parse --short "$FEAT"))를 포함하지 않음(merge-base ${_mb:0:7}) — 최신 루트를 병합한 뒤 다시 랜딩 요청 (docs/rules/single_set_testing.md §3 ②)"
  exit 1
fi
out="$(git -C "$REPO" cherry "$FEAT" "$NANO" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || { echo "REJECT cherry 게이트 — git cherry 실패(rc=$rc): ${out:0:120}"; exit 1; }
plus="$(printf '%s\n' "$out" | grep '^+' || true)"
# «+» 커밋을 둘로 가른다 — design/ 밖 경로(코드·시험·스크립트)를 건드린 것 = 차단 · design/ 만 건드린 것 = WARN 통과(브랜치가 남아 복구 가능 · arch#137)
#   ★경로 목록은 변수로 «완독» 한 뒤 분류한다(DA 575 H2: `diff-tree | grep -qv` 는 grep 조기 종료 → SIGPIPE → 큰 혼합 커밋이 «design/ 만» 으로 판정) · diff-tree·log 각 rc 를 따로 본다(H1: 실패가 WARN 통과)★
block=""; warn=""
delta_file="$(mktemp)"; plus_file="$(mktemp)"; cg_out="$(mktemp)"; tip_map="$(mktemp)"; feat_map="$(mktemp)"; paths_file="$(mktemp)"; need_file="$(mktemp)"; hist_file="$(mktemp)"
trap 'rm -f "$delta_file" "$plus_file" "$cg_out" "$tip_map" "$feat_map" "$paths_file" "$need_file" "$hist_file"' EXIT
# ①커밋 분류 = 묶음 1회(종전: 커밋마다 log 1 + diff-tree 2) — 줄 단위라 탭·개행이 든 경로는 종전의 비-z 파싱과 같은 한계(모자라면 차단 쪽으로 떨어진다).
CG_ITEMS=(); while read -r _ sha; do [ -n "$sha" ] || continue; CG_ITEMS+=("$sha"); done <<< "$plus"
CG_CMD=cg_cmd_commits; CG_OUT=""; cg_fetch 커밋 0 "${#CG_ITEMS[@]}" 0
printf '%s\n' "$CG_OUT" > "$cg_out"
_cgp="$(cg_py commits "$cg_out")" || { echo "REJECT cherry 게이트 — 커밋 묶음 해석 실패(«+» 커밋 ${#CG_ITEMS[@]}개) — 판정 불가"; exit 1; }
while IFS= read -r _l; do
  case "$_l" in
    B$'\t'*) block="${block}${_l:2}"$'\n';;
    W$'\t'*) warn="${warn}${_l:2}"$'\n';;
    P$'\t'*) printf '%s\0' "${_l:2}" >> "$plus_file";;
  esac
done <<< "$_cgp"
nb="$(printf '%s' "$block" | grep -c . || true)"; nw="$(printf '%s' "$warn" | grep -c . || true)"
if [ "$nb" -gt 0 ]; then
  # G4c: patch-id 는 «같은 변경» 의 충분조건일 뿐(cherry-pick 이 다른 문맥 base 에 앉으면 «+» 로 남는다). 정본은 «머지하면 무엇이 바뀌나» = merge-tree.
  # ★«+» 경로와의 교집합이 아니라 «실제 merge delta»(merge-tree 결과 트리 vs feat HEAD 트리)를 본다 — rename·경로 인코딩 불일치가 교집합을 비우는 누출(DA 597 H1)★
  # design/ 밖 delta 가 하나라도 있으면 REJECT · 없으면 PASS. 종료코드는 1행 OID 와 따로 본다(5c). 경로는 -z 로 완독(quotepath 무관).
  conflict=0
  mt="$(git -C "$REPO" merge-tree --write-tree "$FEAT" "$NANO")"; mrc=$?
  if [ "$mrc" -eq 1 ]; then conflict=1
  elif [ "$mrc" -ne 0 ]; then
    echo "REJECT cherry 게이트 — git merge-tree 실패(rc=$mrc): ${mt:0:120}"; exit 1
  fi
  differ=""; ndesign=0
  if [ "$conflict" -eq 0 ]; then
    tree="${mt%%$'\n'*}"
    git -C "$REPO" -c core.quotepath=false diff-tree -r --name-only -z --no-commit-id "$FEAT^{tree}" "$tree" > "$delta_file"; drc=$?
    [ "$drc" -eq 0 ] || { echo "REJECT cherry 게이트 — git diff-tree(merge-tree 결과 대조) 실패(rc=$drc)"; exit 1; }
    while IFS= read -r -d '' p; do
      case "$p" in design/*) ndesign=$((ndesign + 1)) ;; *) differ="${differ}  ${p}"$'\n' ;; esac
    done < "$delta_file"
    if [ -z "$differ" ]; then
      echo "INFO cherry 게이트 — $NANO 의 «+» 커밋 $((nb + nw))개는 git cherry 로는 미랜딩이나 merge-tree 실제 delta 가 design/ 밖 0개(design/ ${ndesign}개) — 통과 (사유 content_landed_via_merge_tree)"
      exit 0
    fi
  fi
  # G4c r3: 반영 «뒤» feat 가 같은 파일을 더 고치면 merge-tree 는 충돌/delta 가 된다(G4b 실가동). 판정 단순화 = «이 브랜치 내용이 feat 역사에 한 번이라도 있었나».
  # «+» 커밋이 건드린 경로 P 전부(NUL 완독)에 대해 tip 의 (mode,blob) 이 feat 역사의 P 에 존재 → 전부 있으면 PASS. tip 에서 P 가 삭제됐으면 feat HEAD 에도 없을 때만 존재로 친다.
  # ★superseded 증거 = merge-base(NANO,FEAT)..FEAT 구간의 «새 blob» 뿐(DA 599 H1)★ — 분기 전 역사의 옛 blob 으로 rollback 한 브랜치를 PASS 시키지 않는다.
  mbase="$(git -C "$REPO" merge-base "$NANO" "$FEAT")"; mbrc=$?
  [[ "$mbrc" -eq 0 && "$mbase" =~ ^[0-9a-f]{40,64}$ ]] || { echo "REJECT cherry 게이트 — git merge-base 실패(rc=$mbrc) — superseded 증거 구간을 못 정함"; exit 1; }
  # ②경로 분류 = 트리 2회(종전: 경로마다 ls-tree 2~3회) — tip·feat HEAD 의 (mode,blob) 를 한 번씩 받아 경로별로 대조한다.
  # ③이력 대조 = 경로 묶음 1회(종전: 경로마다 git log 1회) — 분기 뒤 feat 구간의 원시 delta 를 경로 묶음으로 한 번에 받는다.
  cg_maps() {  # <ref> <map 파일> — ls-tree -r -t -z(NUL) → «mode<TAB>sha<TAB>경로» 줄(탭·개행 든 경로는 줄 단위 한계)
    cg_git "$CG_LIM" -c core.quotepath=false ls-tree -r -t -z --full-tree "$1" > "$2.z"; local mrc2=$?
    [ "$mrc2" -eq 0 ] || cg_fail "트리($1)" "$mrc2" 1 "$1"
    tr '\0' '\n' < "$2.z" | awk '{ i=index($0,"\t"); if (!i) next; n=split(substr($0,1,i-1),a," "); if (n<3) next; print a[1] "\t" a[3] "\t" substr($0,i+1) }' > "$2" \
      || { echo "REJECT cherry 게이트 — 트리($1) 해석 실패 — 판정 불가"; exit 1; }
    rm -f "$2.z"
  }
  cg_maps "$NANO" "$tip_map"; cg_maps "$FEAT" "$feat_map"
  tr '\0' '\n' < "$plus_file" | sort -u > "$paths_file"
  CG_MBASE="$mbase"
  _recs="$(cg_py paths "$paths_file" "$tip_map" "$feat_map" "$FEAT" "$mbase")" || { echo "REJECT cherry 게이트 — 경로 분류 해석 실패 — 판정 불가"; exit 1; }
  CG_ITEMS=(); : > "$need_file"
  while IFS=$'\t' read -r _k _p _m _s; do
    [ "$_k" = need ] || continue
    CG_ITEMS+=("$_p"); printf '%s\t%s\t%s\n' "$_p" "$_m" "$_s" >> "$need_file"
  done <<< "$_recs"
  CG_CMD=cg_cmd_hist; CG_OUT=""; cg_fetch 경로이력 0 "${#CG_ITEMS[@]}" 0
  printf '%s\n' "$CG_OUT" > "$hist_file"
  _hrecs="$(cg_py hist "$need_file" "$hist_file" "$FEAT" "$mbase")" || { echo "REJECT cherry 게이트 — 이력 대조 해석 실패 — 판정 불가"; exit 1; }
  nsup=0; nid=0; nmiss=0; ndoc=0; missing=""; sup_commit=""   # nid = tip 내용이 feat HEAD 와 같은 경로(R70) · ndoc = design/ 문서 종류 경로 중 feat 역사에 없는 것(WARN 만 · 코드 종류는 nmiss)
  while IFS=$'\t' read -r _k _p _x; do
    [ -n "$_k" ] || continue
    [ "$nmiss" -lt 20 ] || break   # REJECT 확정 + 목록 상한 20 — 종전 루프와 같은 상한
    case "$_k" in
      sup) nsup=$((nsup + 1)); [ -z "$_x" ] || sup_commit="$_x";;
      nid) nid=$((nid + 1));;
      doc) ndoc=$((ndoc + 1));;
      miss) nmiss=$((nmiss + 1)); missing="${missing}  ${_p} ${_x}"$'\n';;
    esac
  done <<< "${_recs}"$'\n'"${_hrecs}"
  docwarn="WARN cherry 게이트 — design/ 문서 종류 경로 ${ndoc}개가 $FEAT 역사에 없음(코드 0 · 브랜치 보존으로 복구 가능)"   # 첫 줄은 INFO·REJECT 로 둔다(WARN 은 뒤에)
  if [ -z "$missing" ] && [ $((nsup + nid)) -gt 0 ]; then
    reason="content_landed_then_superseded"; [ "$nsup" -gt 0 ] || reason="content_identical_to_feat_head"; [ "$nsup" -eq 0 ] || [ "$nid" -eq 0 ] || reason="${reason}+content_identical_to_feat_head"
    echo "INFO cherry 게이트 — $NANO 의 «+» 커밋 $((nb + nw))개: 경로 ${nsup}개 tip 내용이 분기 뒤 $FEAT 구간에 새 blob 으로 있음(예 ${sup_commit:-없음}) · feat HEAD 와 동일 ${nid}개 — 통과 (사유 $reason)"
    [ "$ndoc" -eq 0 ] || echo "$docwarn"
    exit 0
  fi
  if [ -n "$SQUASHED_PR" ]; then
    cherry_squashed_pr_gate "$REPO" "$FEAT" "$NANO" "$SQUASHED_PR" "$REASON" "$plus_file"; prc=$?
    [ "$prc" -ne 0 ] || [ "$ndoc" -eq 0 ] || echo "$docwarn"
    exit "$prc"
  fi
  if [ "$conflict" -eq 1 ]; then
    echo "REJECT cherry 게이트 — $NANO 와 $FEAT 의 merge-tree 충돌(rc=1) + tip 내용이 $FEAT 역사에 없는 경로가 있음 — 사람이 판정:"
  else
    echo "REJECT cherry 게이트 — $NANO 머지 시 $FEAT 에 design/ 밖 변경 $(printf '%s' "$differ" | grep -c .)개가 생김(내용 미랜딩 · merge-tree 실제 delta):"
    printf '%s' "$differ" | head -20
  fi
  echo "  tip 내용이 $FEAT 역사에 없는 경로:"; printf '%s' "$missing" | head -20
  echo "REJECT cherry 게이트 — $NANO 에 $FEAT 로 안 들어온 코드·시험·스크립트 커밋 ${nb}개 (git cherry '+' · design/ 밖 경로):"
  printf '%s' "$block" | head -20
  [ "$nb" -le 20 ] || echo "  … 외 $((nb - 20))개"
  [ "$nw" -eq 0 ] || { echo "  (별도 WARN: design/ 만 건드린 미랜딩 문서 커밋 ${nw}개)"; printf '%s' "$warn" | head -5; }
  [ "$ndoc" -eq 0 ] || echo "  (별도 WARN: design/ 문서 종류 경로 ${ndoc}개 — 코드 판정에서 제외)"
  echo "  → cherry-pick -x 로 $FEAT 에 반영하거나 폐기 사유를 값으로 적은 뒤 닫는다 (사람 우회: --override \"<사유>\")"
  if [ "$HAVE_OVERRIDE" -eq 1 ]; then
    # 원장 메타는 행 합성 «전» 에 각각 조회 · rc 와 값 검증 — 하나라도 실패하면 빈 값 행 없이 exit 1 (DA 599 H2)
    root="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)"; r1=$?
    tip_s="$(git -C "$REPO" rev-parse --short "$NANO")"; r2=$?
    feat_s="$(git -C "$REPO" rev-parse --short "$FEAT")"; r3=$?
    root="${root%/.git}"
    if [ "$r1" -ne 0 ] || [ "$r2" -ne 0 ] || [ "$r3" -ne 0 ] || [ ! -d "$root" ] || [[ ! "$tip_s" =~ ^[0-9a-f]{7,64}$ ]] || [[ ! "$feat_s" =~ ^[0-9a-f]{7,64}$ ]]; then
      echo "REJECT cherry 게이트 — --override 원장 메타 조회 실패(common-dir rc=$r1 tip rc=$r2 feat rc=$r3) — 원장 행 0 · 우회 불가"; exit 1
    fi
    ledger="${FT_CHERRY_OVERRIDE_LEDGER:-$root/.fable-team/state/cherry-gate-override.log}"
    row="$(date '+%F %T')	seat=${FT_SEAT:-$NANO}	nano=$NANO	tip=$tip_s	feat=$feat_s	reason=$(printf '%s' "$OVERRIDE" | tr '\n\t' '  ')"
    { mkdir -p "$(dirname "$ledger")" && printf '%s\n' "$row" >> "$ledger"; } || { echo "REJECT cherry 게이트 — --override 원장 기록 실패($ledger) — 보이는 기록 없이는 우회 불가"; exit 1; }
    echo "ERROR cherry 게이트 OVERRIDE — 위 REJECT 를 사람 사유로 우회: $OVERRIDE (원장 $ledger)" >&2
    echo "OVERRIDE cherry 게이트 — 위 REJECT 를 우회해 통과 · 사유: $OVERRIDE · 원장 1행 기록: $ledger"
    exit 0
  fi
  exit 1
fi
if [ "$nw" -gt 0 ]; then
  echo "WARN cherry 게이트 — $NANO 의 design/ 문서 커밋 ${nw}개가 $FEAT 에 없음(코드 0 · 브랜치 보존으로 복구 가능) — 통과:"
  printf '%s' "$warn" | head -20
  [ "$nw" -le 20 ] || echo "  … 외 $((nw - 20))개"
  exit 0
fi
echo "OK cherry 게이트 — $NANO 의 모든 커밋이 $FEAT 에 patch 단위로 존재(+ 0)"
exit 0
