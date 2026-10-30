#!/usr/bin/env bash
# ft-press-baseline-check.sh --card <카드> [--repo <press 워크트리>]
#   press 기준선 게이트(Issue #834 · 설계 design/v65/20261007/DESIGN-834-baseline-gate-arch165.md §7 정정 r2 + «C2 잔여 2»).
#   왜: press 회차가 v65 기본 동작 대비로 읽히지 않으면 증거가 «원래 있던 것인지 우리가 만든 것인지» 가려지지 않는다
#       (사례 design/v65/autovad-loop/CASE-polish-ko-not-applied-baseline-gap-20261006.md). 기억이 아니라 종료코드로 막는다.
#   카드 머리줄(줄 맨 앞 «키: 값»): 기준선:(self | 기준선 파일 경로 | 없음) · 실험:(key=value,… | 없음) · 비교 언어:(기본 right=ko,left=en)
#     self 는 «기준선 전용 카드»만 — 종류: 기준선 · 회차: 1 · 실험: 없음 · 프로필: default-3bubble 전부.
#   기준선 파일 머리줄: set_sha · control · side_lang · server_ready · visible_at_settle · evidence · run_id (형식 = design/v65/baselines/README.md)
#   세트 경로 정의는 ft-press-set-check.sh --print-set-paths 를 읽는다(복사 0). 토글 정본 = <repo>/design/v65/baselines/FLAGS.md.
#   exit 0 = 통과 · 1 = 막힘(칸마다 «BLOCK <칸>: 사유» 한 줄) · 2 = usage. ★침묵 통과 0★
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CARD=""; REPO=""
usage() { echo "usage: $0 --card <카드 경로> [--repo <press 워크트리>]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --card) CARD="${2:-}"; shift 2 2>/dev/null || usage ;;
    --repo) REPO="${2:-}"; shift 2 2>/dev/null || usage ;;
    *) usage ;;
  esac
done
[ -n "$CARD" ] || usage
[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO" ] && git -C "$REPO" rev-parse HEAD >/dev/null 2>&1 || { echo "BLOCK repo: git 워크트리 아님(${REPO:-cwd})"; exit 1; }
problems=()
block() { problems+=("$1"); }
hdr() { # 파일 키 → 첫 «키:» 줄의 값(앞뒤 공백 제거) · 그 줄이 없으면 rc 1
  local v; v="$(grep -m1 -E "^$2:" "$1" 2>/dev/null)" || return 1
  v="${v#*:}"; v="${v#"${v%%[![:space:]]*}"}"; printf '%s' "${v%"${v##*[![:space:]]}"}"
}
abspath() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$REPO" "$1" ;; esac; }
finish() { # $1 = 통과 사유
  if [ "${#problems[@]}" -eq 0 ]; then echo "OK $1"; exit 0; fi
  printf 'BLOCK %s\n' "${problems[@]}"; echo "BASELINE-CHECK BLOCK — 카드 $CARD_ARG"; exit 1
}
card_from_ref() { # r1177: 작업 트리(세트 sha)에 카드 없음 → FT_CARD_REF(기본 origin/main) 판을 임시 파일로 꺼낸다(ft-nano-close r888 과 같은 ref · fetch 0)
  local ref="${FT_CARD_REF:-origin/main}" rel="${CARD#./}" rc
  case "$CARD" in "$REPO"/*) rel="${CARD#"$REPO"/}" ;; /*) block "카드: 파일 없음($CARD)"; finish "" ;; esac
  git -C "$REPO" cat-file -e "$ref:$rel" 2>/dev/null || { block "카드: 파일 없음($CARD) · $ref 에도 없음"; finish ""; }
  CARD_TMP="$(mktemp "${TMPDIR:-/tmp}/ft-press-card.XXXXXX")" || { block "카드: 판정 불가 — mktemp 실패"; finish ""; }
  trap 'rm -f "$CARD_TMP"' EXIT
  git -C "$REPO" show "$ref:$rel" >"$CARD_TMP" 2>/dev/null; rc=$?
  [ "$rc" -eq 0 ] || { block "카드: 판정 불가 — git show $ref:$rel rc=$rc"; finish ""; }
  echo "INFO 카드 출처 = $ref:$rel"; CARD="$CARD_TMP"
}
CARD_ARG="$CARD"
[ -f "$CARD" ] || card_from_ref
BASE="$(hdr "$CARD" 기준선)" || block "카드 기준선: 머리줄 없음 — 기준선 없는 발사 차단(#834)"
EXP="$(hdr "$CARD" 실험)" || block "카드 실험: 머리줄 없음(바꾸는 토글 key=value · 없으면 «없음»)"
LANGS="$(hdr "$CARD" '비교 언어')" || LANGS="right=ko,left=en"
. "$HERE/ft-team-lib.sh"   # R382b: v65 팀 폴더는 press 워크트리의 design/TEAMS.md 폴더 칸으로(리터럴 0)
V65="$(ft_team_in "$REPO" v65)" || { echo "BLOCK v65 팀 폴더를 못 풀었다($REPO/design/TEAMS.md)"; exit 1; }
FLAGS="$V65/baselines/FLAGS.md"

# 값 검사(토글·언어·control·ISO·증거 결속)는 python 한 곳 — BLOCK/NOTE 줄을 돌려준다.
pycheck() { # mode(exp|base) 실험 FLAGS.md [비교언어 기준선파일]
  python3 - "$@" <<'PY'
import sys, re, json, os, datetime
def _fail_closed(t, e, tb):  # 본문 어디서든 예상 밖 예외 = BLOCK + 비0 종료(삼키기 0 · DA⑥ r1 차단 1)
    print(f"BLOCK 검사기 내부 오류 — fail closed: {t.__name__}: {e}", flush=True); os._exit(70)
sys.excepthook = _fail_closed
mode, exp, flags_md = sys.argv[1:4]
def out(kind, msg): print(f"{kind} {msg}")
flags = {}
if os.path.isfile(flags_md):
    for ln in open(flags_md, encoding="utf-8"):
        m = re.match(r"^\|\s*`([A-Za-z0-9_.-]+)`\s*\|\s*`([^`]*)`\s*\|", ln)
        if m: flags[m.group(1)] = m.group(2)
if not flags:
    out("BLOCK", f"FLAGS.md: 없음 또는 토글 행 0 ({flags_md})"); sys.exit()
if exp != "없음":
    for kv in filter(None, (s.strip() for s in exp.split(","))):
        k = kv.split("=", 1)[0]
        if "=" not in kv: out("BLOCK", f"카드 실험: key=value 꼴 아님({kv})")
        elif k not in flags: out("BLOCK", f"카드 실험: FLAGS.md 에 없는 토글 {k}")
if mode != "base": sys.exit()
card_langs, bf = sys.argv[4:6]
def langs(v):
    if isinstance(v, dict): r, l = v.get("right"), v.get("left")
    else:
        s = str(v); r = re.search(r"right\s*[:=]\s*([A-Za-z-]+)", s); l = re.search(r"left\s*[:=]\s*([A-Za-z-]+)", s)
        r, l = (r and r.group(1)), (l and l.group(1))
    return (r, l) if r and l else None
H = {}
for ln in open(bf, encoding="utf-8"):
    m = re.match(r"^([a-z_]+):\s*(.*?)\s*$", ln)
    if m and m.group(1) not in H: H[m.group(1)] = m.group(2)
want = langs(card_langs)
if want is None: out("BLOCK", f"카드 비교 언어: right/left 해석 불가({card_langs})")
if "side_lang" in H and langs(H["side_lang"]) != want:
    out("BLOCK", f"side_lang: 기준선 {H['side_lang']} ≠ 카드 비교 언어 {card_langs}")
if "control" in H:
    ctl = dict(t.split("=", 1) for t in H["control"].split() if "=" in t)
    for k in ("lane", "stt_provider", "side_lang", "click", "flags"):
        if not ctl.get(k): out("BLOCK", f"control: {k}= 없음")
    if ctl.get("side_lang") and langs(ctl["side_lang"]) != want:
        out("BLOCK", f"control side_lang: {ctl['side_lang']} ≠ 카드 비교 언어 {card_langs}")
    if ctl.get("click") and ctl["click"] != "PRESS_SIDE_LANG_CLICK:1":
        out("BLOCK", f"control click: {ctl['click']} — 기준선 프로필은 PRESS_SIDE_LANG_CLICK:1 고정")
    got = dict(kv.split("=", 1) for kv in ctl.get("flags", "").split(",") if "=" in kv)
    for k in sorted(set(flags) | set(got)):
        if k not in got: out("BLOCK", f"control flags: {k} 누락(FLAGS.md 기본값 {flags[k]})")
        elif k not in flags: out("BLOCK", f"control flags: FLAGS.md 에 없는 토글 {k}")
        elif got[k] != flags[k]: out("BLOCK", f"control flags: {k}={got[k]} ≠ 기본값 {flags[k]}")
if "server_ready" in H:
    try: datetime.datetime.fromisoformat(H["server_ready"].replace("Z", "+00:00"))
    except ValueError: out("BLOCK", f"server_ready: ISO-8601 아님({H['server_ready']})")
if "visible_at_settle" in H and H["visible_at_settle"] != "yes":
    out("BLOCK", f"visible_at_settle: {H['visible_at_settle']} — yes 만 통과")
ev = H.get("evidence", "")
if ev:
    p = ev if os.path.isabs(ev) else os.path.join(os.environ["REPO"], ev)
    try: res = json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError) as e: out("BLOCK", f"evidence: 증거 없음 — RESULT json 실재·파싱 실패({ev}: {type(e).__name__})"); sys.exit()
    if not isinstance(res, dict) or not isinstance(res.get("marks", {}), dict):
        out("BLOCK", f"evidence: 증거 없음 — 형식(RESULT 최상위·marks 가 객체 아님 · {ev})"); sys.exit()
    pairs = (("set_sha", res.get("set_sha") or res.get("commit_sha"), H.get("set_sha")),
             ("side_lang_at_press", res.get("side_lang_at_press"), H.get("side_lang")),
             ("session_id", res.get("session_id"), H.get("run_id")))
    for name, rv, hv in pairs:
        if rv in (None, "", {}): out("BLOCK", f"evidence: 증거 없음 — RESULT 에 {name} 기록 없음({ev})")
        elif (langs(rv) != langs(hv or "")) if name == "side_lang_at_press" else (str(rv) != hv):
            out("BLOCK", f"evidence: 증거 불일치 — RESULT {name}={rv} ≠ 머리줄 {hv}")
    if True in (res.get("failed"), (res.get("marks") or {}).get("failed")): out("NOTE", "측정 실패 회차(failed=true) — 유효한 측정으로 통과 · 제품 성공 아님")
PY
}
collect() { local ln; while IFS= read -r ln; do case "$ln" in "BLOCK "*) block "${ln#BLOCK }" ;; NOTE*) echo "$ln" ;; esac; done; }
runcheck() { # pycheck 종료코드를 «실제로» 잡는다 — BLOCK 줄 부재를 통과로 읽지 않는다(프로세스 치환은 rc 를 버린다 · DA⑥ r1)
  local o rc; o="$(pycheck "$@")"; rc=$?
  collect <<<"$o"
  [ "$rc" -eq 0 ] || block "검사기: python 비정상 종료(rc=$rc) — fail closed"
}
export REPO

case "${BASE:-}" in
  ""|없음) [ "${#problems[@]}" -gt 0 ] || block "카드 기준선: 없음 — 기준선 없는 발사 차단(#834)"; finish "" ;;
  self)
    [ "$(hdr "$CARD" 종류)" = "기준선" ] || block "self: 종류: 기준선 아님 — self 는 기준선 전용 카드만"
    [ "$(hdr "$CARD" 회차)" = "1" ] || block "self: 회차: 1 아님 — self 는 기준선 전용 카드만"
    [ "${EXP:-}" = "없음" ] || block "self: 실험: 없음 아님(${EXP:-<빈 값>}) — self 는 기준선 전용 카드만"
    [ "$(hdr "$CARD" 프로필)" = "default-3bubble" ] || block "self: 프로필: default-3bubble 아님 — self 는 기준선 전용 카드만"
    runcheck exp "${EXP:-없음}" "$FLAGS"
    finish "기준선 self — 이 회차가 기준선이다: 결과로 ${V65#"$REPO"/}/baselines/BASELINE-$(git -C "$REPO" rev-parse --short=12 HEAD).md 를 쓴다(형식 ${V65#"$REPO"/}/baselines/README.md)" ;;
esac

BF="$(abspath "$BASE")"
[ -f "$BF" ] || { block "기준선 파일: 없음($BASE)"; finish ""; }
for k in set_sha control side_lang server_ready visible_at_settle evidence run_id; do
  hdr "$BF" "$k" >/dev/null || block "기준선 머리줄 빠짐: $k"
done
SHA="$(hdr "$BF" set_sha)"
if [ -n "$SHA" ]; then
  if [[ ! "$SHA" =~ ^[0-9a-f]{40}$ ]] || ! git -C "$REPO" cat-file -e "$SHA^{commit}" 2>/dev/null; then
    block "set_sha: 40자 hex 커밋 아님/이 저장소에 없음($SHA)"
  else
    SETP=(); while IFS= read -r p; do [ -n "$p" ] && SETP+=("$p"); done < <("$HERE/ft-press-set-check.sh" --print-set-paths 2>/dev/null)
    if [ "${#SETP[@]}" -eq 0 ]; then block "세트 경로: ft-press-set-check.sh --print-set-paths 실패"
    else
      git -C "$REPO" diff --quiet "$SHA" HEAD -- "${SETP[@]}" 2>/dev/null; drc=$?
      if [ "$drc" -eq 1 ]; then
        block "세트 변경: ${SHA:0:12}..HEAD 세트 경로 변경 $(git -C "$REPO" diff --name-only "$SHA" HEAD -- "${SETP[@]}" | grep -c .)개(예 $(git -C "$REPO" diff --name-only "$SHA" HEAD -- "${SETP[@]}" | head -3 | paste -sd, -)) — 기준선 다시 잰다"
      elif [ "$drc" -ne 0 ]; then block "세트 diff: git diff 오류(rc=$drc) — 통과 아님"
      fi
    fi
  fi
fi
runcheck base "${EXP:-없음}" "$FLAGS" "$LANGS" "$BF"
finish "기준선 통과 — $BASE · set_sha ${SHA:0:12} · 세트 경로 diff 0 = 커밋 소스 동일(기원 증명 아님 · 판정 어휘는 docs/rules/e2e_testing.md)"
