#!/usr/bin/env bash
# ft-nano-cherry-gate.sh <feat 브랜치> <nano 브랜치> [--repo <dir>]
#   ft-nano-close.sh 의 «산출물이 들어왔는가» 게이트 (G4 · 골좌표 M7 — 나노 브랜치에만 남은 커밋은 feat push 가 따라오지 않는다).
#   `git cherry <feat> <nano>` 의 «+»(feat 에 같은 patch 가 없는 커밋): design/ 밖 경로를 건드린 것이 있으면 목록 출력 + exit 1 ·
#   design/ 만 건드린 «+» 는 WARN 목록 + exit 0(브랜치 보존으로 복구 가능 — G4 실측 docs-only 134 를 전부 막으면 닫기 정지) · «+» 0 이면 `OK` + exit 0.
#   코드 «+» 는 ①merge-tree 실제 delta 가 design/ 밖 0 → PASS(content_landed_via_merge_tree) ②충돌·delta 면 «+» 경로마다 tip 의 (mode,blob) 이 feat 역사에 있으면 PASS(content_landed_then_superseded) ③아니면 REJECT.
#   면제 목록·무조건 우회 없음. 유일한 사람 우회 = `--override "<사유>"`(코드 «+» 의 내용 REJECT 만 · 사유 빈 문자열 거부 · ERROR 로그 + 원장 1행 — #0 RULE 예외 3조건).
#   --mode land|close (기본 close = 위 동작 그대로): land = 랜딩 «요청» 시점 — nano 가 feat HEAD 를 조상으로 포함(최신 루트 병합 완료)하지 않으면 REJECT(M7 · single_set_testing §2 규칙 2).
#   close 에는 이 검사를 걸지 않는다 — squash 랜딩 뒤엔 feat 가 앞서 가 «포함» 이 항상 거짓이다(REVIEW arch141 §2-3).
#   exit 0 = 통과 · 1 = REJECT(+ 있음 / ref 없음 / 호출 실패 — 전부 사유 stdout) · 2 = usage. ★침묵 통과 0★ — 어느 경로든 한 줄 이상 출력한다.
set -uo pipefail
#   squash 랜딩 전용 = `--squashed-pr <N> --reason "<사유>"`(R29 · 둘 다 필요 · --override 와 동시 사용 불가): PR 사실(gh) + 경로 분류(ft-nano-cherry-pr.sh) 뒤
#   «PR 안에서 고쳐짐» 만 사유로 통과(되돌림·제거·PR 에 없음 = 플래그로도 REJECT) · 원장 kind=squashed-pr 1행. 플래그 없으면 위 동작 그대로.
#   superseded 검사에서 WARN 으로 낮추는 경로 = design/ 아래 문서 종류(md html png jpg jpeg svg pdf)만 — 그 밖은 코드 경로.
#   ★r958 묶음 호출(하드 룰 12 · 외부 호출 7초 룰)★ — «+» 커밋마다 log·diff-tree 2회, 경로마다 ls-tree·log 3회 부르면 커밋·경로 수에 비례해 늘어난다
#   (실사건: 커밋 많은 나노가 닫기 ⑤ 에서 70초 초과 REJECT 2회 · planner #170097). 묶음 1회로 묻고, 1회 상한 FT_CHERRY_LIM_S(기본 7초)를 넘으면
#   그 묶음을 반으로 쪼개 «재시도 1»(ⓒ) · 항목 하나까지 쪼개도 넘으면 사유 있는 REJECT · 끝난 묶음은 FT_CHERRY_PROGRESS 파일에 남겨 다시 부르면 건너뛴다(ⓓ).
#   FT_CHERRY_BATCH(기본 100) = 한 묶음의 최대 항목 수(닫기 쪽 상한 계산과 같은 값이어야 한다 · ft-nano-close.sh nf_mult_batches).
#   ★r958 r3 = 구조로 닫는다(DA⑥ r2 HOLD 2 · 같은 축 보류 2회 = 하드 룰 14 재설계)★ — ①이 스크립트의 호출은 «한 함수 G» 만 지난다(맨 호출은 G 안 cg_git 한 곳):
#   자리마다 상한을 따로 걸면 남은 자리(rev-parse·merge-base·diff-tree·ls-tree)가 또 샌다(r1 cherry·r2 rev-parse 실측). ②경로를 내는 출력은 전부 `-z`(NUL)로 받는다:
#   따옴표·공백·탭·한글·rename 경로가 «없는 이름» 으로 새어 통과하던 자리(r2 반례 1)를 꼴 자체로 없앤다. ③안전망 시험 ⓚ 가 «맨 호출 0 · -z 빠짐 0» 을 문자열로 본다.
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
# ★r958 묶음 호출 도구★ — CG_LIM = 호출 1회 상한(초 · 시험은 FT_CHERRY_LIM_S 로 줄인다) · CG_BATCH = 한 묶음 항목 수 · CG_PROG = 진행 파일(없으면 매번 새로 잰다).
CG_LIM="${FT_CHERRY_LIM_S:-7}"; CG_BATCH="${FT_CHERRY_BATCH:-100}"; CG_PROG="${FT_CHERRY_PROGRESS:-}"
case "$CG_LIM" in ''|0|*[!0-9]*) CG_LIM=7;; esac
case "$CG_BATCH" in ''|0|*[!0-9]*) CG_BATCH=100;; esac
CG_PYDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# cg_git <초> <인자…> — 리포는 $REPO · stdout 만 넘긴다 · 시간 초과 rc 124(자식 프로세스 그룹까지 정리 · 재시도 1 은 ft_git_capped.py 안).
#   ★이 파일에서 맨 호출이 허용되는 유일한 자리★(안전망 시험 ⓚ) — 본문은 전부 아래 G 를 지난다.
cg_git() { local lim="$1"; shift
  if [ -f "$CG_PYDIR/ft_git_capped.py" ]; then python3 "$CG_PYDIR/ft_git_capped.py" "$lim" "$REPO" "$@"; return $?; fi
  echo "WARN cherry 게이트 — $CG_PYDIR/ft_git_capped.py 없음: ${lim}초 상한 없이 1회 호출(설치 누락 의심)" >&2
  git -C "$REPO" "$@"
}
# cg_fail <단계> <rc> <묶음 n> <마지막 항목> — rc 124 = 상한 초과(쪼개도 넘음) · 그 밖 = 호출 실패. 둘 다 사유 있는 REJECT(조용한 통과 0).
cg_fail() {
  if [ "$2" -eq 124 ]; then echo "REJECT cherry 게이트 — $1 ${CG_LIM}초 초과(묶음 $3 · 마지막 $4) — 쪼개도 넘어 판정 불가(조용한 통과 0)"
  else echo "REJECT cherry 게이트 — $1 실패(rc=$2) 마지막 $4 — 판정 불가(조용한 통과 0)"; fi
  exit 1
}
CG_TMPV="$(mktemp)"; CG_TMP2="$(mktemp)"; CG_TMP3="$(mktemp)"
# G <단계> <출력 목적지> <인자…> — 이 스크립트의 호출 단일 통로. 목적지 = `-`(그대로 stdout) · `/dev/null`(버림) · `<파일>`.
#   목적지를 인자로 받는 이유 = 리다이렉트 사고 방지 — 상한 초과 REJECT 는 언제나 «진짜 stdout» 으로 나가야 한다(파일로 새면 조용한 실패).
G() { local step="$1" dst="$2"; shift 2
  local last="${!#:-}" rc
  cg_git "$CG_LIM" "$@" > "$dst"; rc=$?
  [ "$rc" -ne 124 ] || cg_fail "$step" "$rc" 1 "$last"
  return "$rc"
}
# 진행 파일 한 묶음 = 헤더 1줄 `#B<TAB>단계<TAB>첫 항목<TAB>개수<TAB>바이트수` + 그 바이트수만큼의 출력 «원문»(ⓓ).
#   출력이 NUL 프레임(경로)일 수 있어 줄 단위가 아니라 «길이 단위»로 싣는다 — 셸 변수는 NUL 을 못 담는다.
cg_prog_get() {  # <단계> <첫 항목> <개수> <받을 파일> → 있으면 0
  [ -n "$CG_PROG" ] && [ -f "$CG_PROG" ] || return 1
  python3 - "$CG_PROG" "$1" "$2" "$3" "$4" <<'PY'
import sys
src, stage, first, count, dst = sys.argv[1:6]
d = open(src, "rb").read()
i = 0
while i < len(d):
    j = d.find(b"\n", i)
    if j < 0: sys.exit(1)
    f = d[i:j].decode("utf-8", "surrogateescape").split("\t")
    i = j + 1
    if len(f) != 5 or f[0] != "#B":
        sys.exit(1)
    try:
        n = int(f[4])
    except ValueError:
        sys.exit(1)
    blob = d[i:i + n]
    i += n
    if len(blob) != n:
        sys.exit(1)
    if f[1] == stage and f[2] == first and f[3] == count:
        open(dst, "wb").write(blob)
        sys.exit(0)
sys.exit(1)
PY
}
cg_prog_put() {  # <단계> <첫 항목> <개수> <출력 파일>
  [ -n "$CG_PROG" ] || return 0
  python3 - "$CG_PROG" "$1" "$2" "$3" "$4" <<'PY'
import sys
dst, stage, first, count, src = sys.argv[1:6]
d = open(src, "rb").read()
head = "#B\t%s\t%s\t%s\t%d\n" % (stage, first, count, len(d))
with open(dst, "ab") as f:
    f.write(head.encode("utf-8", "surrogateescape"))
    f.write(d)
PY
  [ "$?" -eq 0 ] || echo "WARN cherry 게이트 — 진행 파일 기록 실패($CG_PROG) — 이번 판정은 그대로 쓴다" >&2
}
# cg_fetch <단계> <시작> <끝> <쪼갠 횟수> — CG_ITEMS[시작..끝) 을 CG_CMD 한 번으로 묻고 결과 원문을 CG_SINK 에 잇는다. 상한 초과면 반으로 쪼개 재시도 1(ⓒ).
cg_fetch() {
  local st="$1" a="$2" b="$3" d="$4" n rc
  n=$(( b - a )); [ "$n" -gt 0 ] || return 0
  if cg_prog_get "$st" "${CG_ITEMS[$a]}" "$n" "$CG_TMP3"; then cat "$CG_TMP3" >> "$CG_SINK"; return 0; fi
  if [ "$n" -gt "$CG_BATCH" ]; then
    cg_fetch "$st" "$a" $(( a + CG_BATCH )) "$d"; cg_fetch "$st" $(( a + CG_BATCH )) "$b" "$d"; return 0
  fi
  "$CG_CMD" "$CG_TMP3" "${CG_ITEMS[@]:$a:$n}"; rc=$?
  if [ "$rc" -eq 124 ] && [ "$n" -gt 1 ] && [ "$d" -lt 1 ]; then   # 쪼개서 «재시도 1» — 반씩 두 번
    cg_fetch "$st" "$a" $(( a + n / 2 )) 1; cg_fetch "$st" $(( a + n / 2 )) "$b" 1; return 0
  fi
  [ "$rc" -eq 0 ] || cg_fail "$st" "$rc" "$n" "${CG_ITEMS[$(( b - 1 ))]}"
  cat "$CG_TMP3" >> "$CG_SINK"; cg_prog_put "$st" "${CG_ITEMS[$a]}" "$n" "$CG_TMP3"
}
# cg_cmd_commits <받을 파일> <sha…> — 커밋 묶음: «로그 줄 + 건드린 경로» 를 한 번에 · -z 라 경로가 NUL 로 온다(따옴표·공백·탭·한글 그대로).
#   --no-walk=unsorted = 인자 순서 보존 · -m = 머지 커밋은 부모별 delta · --root = 첫 커밋도 · blob 은 기본 축약형(앞자리로 대조).
#   ★--no-renames 필수(r958 r2 · DA⑥ r1 반례 1)★ — rename 을 켜면 원시 한 칸에 «옛경로·새경로» 가 같이 실려 경로 하나가 «없는 이름» 이 되고,
#   그 이름은 tip·feat 어디에도 없어 «sup» 로 통과한다(무변경 이동이 미랜딩인데 통과 — base 판은 두 경로를 따로 봐 REJECT). --no-renames 면 D 옛 + A 새 두 항목이 된다.
cg_cmd_commits() { local dst="$1"; shift; G "커밋(log)" "$dst" log --no-walk=unsorted --raw -m --root --no-renames --format='C %H	%h %s' -z "$@"; }
# cg_cmd_hist <받을 파일> <경로…> — 경로 묶음: 분기 뒤 feat 역사의 원시 delta(경로별 «새 blob 이 있었나» 를 한 번에 본다) · -z 로 경로를 NUL 프레임.
cg_cmd_hist() { local dst="$1"; shift; G "경로이력(log)" "$dst" --literal-pathspecs log "$CG_MBASE..$FEAT" --no-renames --format='C %h' --raw -z -- "$@"; }
# cg_py <모드> <인자…> — 묶음 출력 해석(커밋 분류·경로 분류·이력 대조). 판정 규칙은 종전 루프와 같다.
#   출력 = NUL 프레임 4칸 레코드(kind, 값1, 값2, 값3) — 경로가 탭·개행을 품어도 셸을 거치며 깨지지 않는다.
cg_py() {
  python3 - "$@" <<'PY'
import re, sys
mode = sys.argv[1]
DOC = re.compile(r"^design/.*\.(md|html|png|jpg|jpeg|svg|pdf)$")
def toks(path):
    with open(path, "rb") as f:
        d = f.read()
    out = d.split(b"\x00")
    if out and out[-1] == b"":
        out.pop()
    return out
def dec(b):
    return b.decode("utf-8", "surrogateescape")
def emit(kind, a="", b="", c=""):
    sys.stdout.buffer.write(b"\x00".join(x.encode("utf-8", "surrogateescape") for x in (kind, a, b, c)) + b"\x00")
def treemap(path):
    m = {}
    for b in toks(path):
        e = dec(b).lstrip("\n")
        if "\t" not in e:
            continue
        meta, _, p = e.partition("\t")
        f = meta.split()
        if len(f) < 3:
            continue
        m[p] = (f[0], f[2])
    return m
if mode == "commits":   # 커밋 묶음 → B(차단)·W(WARN)·P(경로)
    chunks = toks(sys.argv[2])
    block, warn, paths = [], [], []
    cur = None; line = ""; outside = False
    j = 0
    while j < len(chunks):
        c = dec(chunks[j]).lstrip("\n"); j += 1
        if c.startswith("C ") and "\t" in c:
            head, _, rest = c[2:].partition("\t")
            if head != cur:
                if cur is not None:
                    (block if outside else warn).append(line)
                cur = head; line = ("  + " + rest)[:120]; outside = False
            continue
        if c.startswith(":"):
            p = dec(chunks[j]) if j < len(chunks) else ""; j += 1
            paths.append(p)
            if not p.startswith("design/"):
                outside = True
    if cur is not None:
        (block if outside else warn).append(line)
    for x in block: emit("B", x)
    for x in warn: emit("W", x)
    for p in paths: emit("P", p)
elif mode == "paths":   # 경로 분류: «경로목록 · tip 트리 · feat HEAD 트리» 대조 → sup/nid/doc/miss/need (miss 상한 20 은 종전과 같다)
    feat_name, base = sys.argv[5], sys.argv[6]
    tip, feat = treemap(sys.argv[3]), treemap(sys.argv[4])
    seen = set()
    for b in toks(sys.argv[2]):
        p = dec(b)
        if p:
            seen.add(p)
    nmiss = 0
    for p in sorted(seen):
        if nmiss >= 20:
            break
        t, f = tip.get(p), feat.get(p)
        if t is None:
            if f is None: emit("sup", p)
            elif DOC.match(p): emit("doc", p)
            else:
                nmiss += 1
                emit("miss", p, "(tip 삭제 · %s 에는 존재)" % feat_name)
            continue
        if f is not None and f == t:
            emit("nid", p); continue
        emit("need", p, t[0], t[1])
elif mode == "hist":   # 이력 대조: need 경로마다 «분기 뒤 feat 구간에 그 blob 이 있었나» — 첫(=최신) 일치가 sup
    need = []
    t = toks(sys.argv[2])
    for i in range(0, len(t) - 2, 3):
        need.append((dec(t[i]), dec(t[i + 1]), dec(t[i + 2])))
    feat_name, base = sys.argv[4], sys.argv[5]
    pend = {}   # 모드로만 묶는다 — blob 은 앞자리 대조(startswith)라 축약 길이가 달라도 맞는다
    for i, (p, m, s) in enumerate(need):
        pend.setdefault(m, []).append(i)
    hit = {}; cur = ""
    chunks = toks(sys.argv[3]); j = 0
    while j < len(chunks):
        c = dec(chunks[j]).lstrip("\n"); j += 1
        if c.startswith("C "):
            cur = c[2:]; continue
        if not c.startswith(":"):
            continue
        path = dec(chunks[j]) if j < len(chunks) else ""; j += 1
        f = c[1:].split(" ")
        if len(f) < 5 or not f[4][:1].isupper():
            continue
        for i in pend.get(f[1], []):
            if need[i][0] == path and i not in hit and need[i][2].startswith(f[3]):
                hit[i] = cur
    for i, (p, m, s) in enumerate(need):
        if i in hit: emit("sup", p, hit[i])
        elif DOC.match(p): emit("doc", p)
        else: emit("miss", p, "(tip %s %s 가 분기 뒤 %s 구간(%s..)에 새 blob 으로 없음)" % (m, s[:9], feat_name, base[:9]))
PY
}
# design/ 아래 문서 종류(md html png jpg jpeg svg pdf)만 0 — 그 밖(sql·sh·py·json·확장자 없음 …)은 코드 경로(ft-nano-cherry-pr.sh 가 이 함수를 쓴다 — gate 가 source 하는 같은 셸).
is_doc_path() {
  case "$1" in design/*.md|design/*.html|design/*.png|design/*.jpg|design/*.jpeg|design/*.svg|design/*.pdf) return 0 ;; esac
  return 1
}
# feat 는 로컬 브랜치 또는 원격 추적 ref(origin/<b>) — 좌석(nano) 브랜치는 로컬이어야 한다(R22).
G rev-parse /dev/null rev-parse --verify -q "refs/heads/$FEAT" \
  || G rev-parse /dev/null rev-parse --verify -q "refs/remotes/$FEAT" \
  || { echo "REJECT cherry 게이트 — 브랜치 없음: $FEAT (refs/heads/ · refs/remotes/)"; exit 1; }
G rev-parse /dev/null rev-parse --verify -q "refs/heads/$NANO" || { echo "REJECT cherry 게이트 — 브랜치 없음: $NANO (refs/heads/)"; exit 1; }
if [ "$MODE" = land ]; then
  if ! G merge-base /dev/null merge-base --is-ancestor "$FEAT" "$NANO"; then
    _mb=""; G merge-base "$CG_TMPV" merge-base "$FEAT" "$NANO" && _mb="$(cat "$CG_TMPV")"
    _fh=""; G rev-parse "$CG_TMPV" rev-parse --short "$FEAT" && _fh="$(cat "$CG_TMPV")"
    echo "REJECT cherry 게이트 — land: $NANO 가 feat HEAD($_fh)를 포함하지 않음(merge-base ${_mb:0:7}) — 최신 루트를 병합한 뒤 다시 랜딩 요청 (docs/rules/single_set_testing.md §3 ②)"
    exit 1
  fi
fi
# ★`cherry` 도 같은 통로로(r958 r2 · DA⑥ r1 반례 2)★ — 여기만 상한 밖이면 «cherry 1회가 8초» 인 입력에서 통과가 샌다(계약 ②: 조용한 통과 0).
G cherry "$CG_TMPV" cherry "$FEAT" "$NANO"; rc=$?
out="$(cat "$CG_TMPV")"
[ "$rc" -eq 0 ] || { echo "REJECT cherry 게이트 — git cherry 실패(rc=$rc): ${out:0:120}"; exit 1; }
plus="$(printf '%s\n' "$out" | grep '^+' || true)"
# «+» 커밋을 둘로 가른다 — design/ 밖 경로(코드·시험·스크립트)를 건드린 것 = 차단 · design/ 만 건드린 것 = WARN 통과(브랜치가 남아 복구 가능 · arch#137)
#   ★경로 목록은 변수로 «완독» 한 뒤 분류한다(DA 575 H2: 조기 종료로 큰 혼합 커밋이 «design/ 만» 으로 판정되는 자리) · 각 묶음 rc 를 따로 본다(H1: 실패가 WARN 통과)★
block=""; warn=""
delta_file="$(mktemp)"; plus_file="$(mktemp)"; cls_file="$(mktemp)"; tip_map="$(mktemp)"; feat_map="$(mktemp)"; paths_file="$(mktemp)"; need_file="$(mktemp)"; hist_file="$(mktemp)"
trap 'rm -f "$delta_file" "$plus_file" "$cls_file" "$tip_map" "$feat_map" "$paths_file" "$need_file" "$hist_file" "$CG_TMPV" "$CG_TMP2" "$CG_TMP3"' EXIT
# ①커밋 분류 = 묶음 1회(종전: 커밋마다 log 1 + diff-tree 2) — 경로는 NUL 프레임이라 꼴에 상관없이 온전하다.
CG_ITEMS=(); while read -r _ sha; do [ -n "$sha" ] || continue; CG_ITEMS+=("$sha"); done <<< "$plus"
CG_CMD=cg_cmd_commits; CG_SINK="$cls_file"; : > "$CG_SINK"; cg_fetch 커밋 0 "${#CG_ITEMS[@]}" 0
cg_py commits "$cls_file" > "$CG_TMP2" || { echo "REJECT cherry 게이트 — git log(커밋 묶음) 해석 실패(«+» 커밋 ${#CG_ITEMS[@]}개) — 판정 불가"; exit 1; }
while IFS= read -r -d '' _k && IFS= read -r -d '' _v && IFS= read -r -d '' _x && IFS= read -r -d '' _y; do
  case "$_k" in
    B) block="${block}${_v}"$'\n';;
    W) warn="${warn}${_v}"$'\n';;
    P) printf '%s\0' "$_v" >> "$plus_file";;
  esac
done < "$CG_TMP2"
nb="$(printf '%s' "$block" | grep -c . || true)"; nw="$(printf '%s' "$warn" | grep -c . || true)"
if [ "$nb" -gt 0 ]; then
  # G4c: patch-id 는 «같은 변경» 의 충분조건일 뿐(cherry-pick 이 다른 문맥 base 에 앉으면 «+» 로 남는다). 정본은 «머지하면 무엇이 바뀌나» = merge-tree.
  # ★«+» 경로와의 교집합이 아니라 «실제 merge delta»(merge-tree 결과 트리 vs feat HEAD 트리)를 본다 — rename·경로 인코딩 불일치가 교집합을 비우는 누출(DA 597 H1)★
  # design/ 밖 delta 가 하나라도 있으면 REJECT · 없으면 PASS. 종료코드는 1행 OID 와 따로 본다(5c). 경로는 -z 로 완독(quotepath 무관).
  conflict=0
  G merge-tree "$CG_TMPV" merge-tree --write-tree "$FEAT" "$NANO"; mrc=$?
  mt="$(cat "$CG_TMPV")"
  if [ "$mrc" -eq 1 ]; then conflict=1
  elif [ "$mrc" -ne 0 ]; then
    echo "REJECT cherry 게이트 — git merge-tree 실패(rc=$mrc): ${mt:0:120}"; exit 1
  fi
  differ=""; ndesign=0
  if [ "$conflict" -eq 0 ]; then
    tree="${mt%%$'\n'*}"
    G diff-tree "$delta_file" diff-tree -r --name-only -z --no-commit-id "$FEAT^{tree}" "$tree"; drc=$?
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
  G merge-base "$CG_TMPV" merge-base "$NANO" "$FEAT"; mbrc=$?
  mbase="$(cat "$CG_TMPV")"
  [[ "$mbrc" -eq 0 && "$mbase" =~ ^[0-9a-f]{40,64}$ ]] || { echo "REJECT cherry 게이트 — git merge-base 실패(rc=$mbrc) — superseded 증거 구간을 못 정함"; exit 1; }
  # ②경로 분류 = 트리 2회(종전: 경로마다 ls-tree 2~3회) — tip·feat HEAD 의 (mode,blob) 를 한 번씩 받아 경로별로 대조한다(-z 원문 그대로).
  # ③이력 대조 = 경로 묶음 1회(종전: 경로마다 log 1회) — 분기 뒤 feat 구간의 원시 delta 를 경로 묶음으로 한 번에 받는다.
  cg_maps() {  # <ref> <map 파일> — ls-tree -r -t -z(NUL) 원문을 그대로 둔다(해석은 cg_py paths 가 NUL 로 한다)
    local mrc2; G ls-tree "$2" ls-tree -r -t -z --full-tree "$1"; mrc2=$?
    [ "$mrc2" -eq 0 ] || { echo "REJECT cherry 게이트 — git ls-tree 실패(rc=$mrc2) 트리 $1 — 판정 불가"; exit 1; }
  }
  cg_maps "$NANO" "$tip_map"; cg_maps "$FEAT" "$feat_map"
  : > "$paths_file"
  cg_py paths "$plus_file" "$tip_map" "$feat_map" "$FEAT" "$mbase" > "$paths_file" || { echo "REJECT cherry 게이트 — 경로 분류 해석 실패 — 판정 불가"; exit 1; }
  CG_MBASE="$mbase"; CG_ITEMS=(); : > "$need_file"
  while IFS= read -r -d '' _k && IFS= read -r -d '' _p && IFS= read -r -d '' _a && IFS= read -r -d '' _b; do
    [ "$_k" = need ] || continue
    CG_ITEMS+=("$_p"); printf '%s\0%s\0%s\0' "$_p" "$_a" "$_b" >> "$need_file"
  done < "$paths_file"
  CG_CMD=cg_cmd_hist; CG_SINK="$hist_file"; : > "$CG_SINK"; cg_fetch 경로이력 0 "${#CG_ITEMS[@]}" 0
  : > "$CG_TMP2"
  [ ! -s "$need_file" ] || cg_py hist "$need_file" "$hist_file" "$FEAT" "$mbase" > "$CG_TMP2" || { echo "REJECT cherry 게이트 — git log(경로이력) 해석 실패 — 판정 불가"; exit 1; }
  nsup=0; nid=0; nmiss=0; ndoc=0; missing=""; sup_commit=""   # nid = tip 내용이 feat HEAD 와 같은 경로(R70) · ndoc = design/ 문서 종류 경로 중 feat 역사에 없는 것(WARN 만 · 코드 종류는 nmiss)
  for _f in "$paths_file" "$CG_TMP2"; do
    while IFS= read -r -d '' _k && IFS= read -r -d '' _p && IFS= read -r -d '' _a && IFS= read -r -d '' _b; do
      [ -n "$_k" ] || continue
      [ "$nmiss" -lt 20 ] || break   # REJECT 확정 + 목록 상한 20 — 종전 루프와 같은 상한
      case "$_k" in
        sup) nsup=$((nsup + 1)); [ -z "$_a" ] || sup_commit="$_a";;
        nid) nid=$((nid + 1));;
        doc) ndoc=$((ndoc + 1));;
        miss) nmiss=$((nmiss + 1)); missing="${missing}  ${_p} ${_a}"$'\n';;
      esac
    done < "$_f"
  done
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
    root=""; r1=0; G rev-parse "$CG_TMPV" rev-parse --path-format=absolute --git-common-dir && root="$(cat "$CG_TMPV")" || r1=$?
    tip_s=""; r2=0; G rev-parse "$CG_TMPV" rev-parse --short "$NANO" && tip_s="$(cat "$CG_TMPV")" || r2=$?
    feat_s=""; r3=0; G rev-parse "$CG_TMPV" rev-parse --short "$FEAT" && feat_s="$(cat "$CG_TMPV")" || r3=$?
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
