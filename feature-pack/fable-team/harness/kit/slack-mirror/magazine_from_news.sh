#!/usr/bin/env bash
# magazine_from_news.sh [magazine_doc.py 인자…] — 08:00 매거진 원본 연결 (R125 · 판정 1437: 매거진 = 오빠 원장 전체)
# 원본 = 오빠 원장(PLAN-oppa-ledger.md)의 «지금 커밋» 한 판 — 뉴스(바뀐 줄만)와 같은 파일, 크기만 다르다. magazine_doc.py(r117)를 부른다.
# 원장이 없거나 커밋 전이면 ERROR + rc≠0 · 커밋 뒤 고쳤으면 «미커밋 수정» ERROR + rc 5 — 빈·낡은 매거진을 만들지 않는다(#0 RULE · 폴백 0).
# r503: 원본 사본은 뉴스와 같은 사본·같은 경로 — 시작에서 ft-ledger-repo-sync.sh 로 origin/main 전진(가지 위·더러움·fetch 실패 = exit 6 · 낡은 매거진 발행 0) · 같은 틱에 이미 했으면(FT_LEDGER_SYNCED=1) 건너뜀
# env: FT_ROOT(필수) · FT_LEDGER_REPO(기본 <루트>/.worktrees/news-ledger-main) · FT_LEDGER_PATH(기본 design/teams/planner/PLAN-oppa-ledger.md) · FT_LEDGER_SYNC(기본 <루트>/.fable-team/LIVE_BIN 의 ft-ledger-repo-sync.sh · 시험 대역) · FT_NEWS_NOW(판 날짜 · 시험) · FT_MAGAZINE_DOC(시험용 대역)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${FT_ROOT:?magazine_from_news: FT_ROOT 필요}"
REPO="${FT_LEDGER_REPO:-$ROOT/.worktrees/news-ledger-main}"
REL="${FT_LEDGER_PATH:-design/teams/planner/PLAN-oppa-ledger.md}"
# 오빠 원장 제목에는 날짜가 없다 — 판 날짜는 발행 시각(FT_NEWS_NOW 또는 지금)의 날짜
NOW="${FT_NEWS_NOW:-$(date '+%Y-%m-%d %H:%M')}"
# r707 날짜당 1회: 예약은 08:00·08:10·08:20 세 번 돈다 — 발행인데 상태 파일에 그 판 날짜 uploaded=True 기록이 있으면 동기화·발행 «전에» skip rc0.
#   판정은 글자 모양(`case " $* "`)이 아니라 magazine_doc.py 의 parse_args 로 읽는다 — 값 속에 든 «--publish»(D1)·줄임말 «--pub»(D2)·«--state 다른 파일»(D3) 을 사람이 짐작하지 않는다(DA⑥ r1 HOLD 3건).
#   uploaded=True 는 magazine_doc.publish 가 HTML 업로드 «성공 뒤» 에만 쓴다 — 실패한 회차는 표식이 없어 다음 회차가 다시 돈다.
#   상태 = parse_args 가 고른 args.state(magazine_doc 기본값과 같음 · --state 를 넘기면 그 파일) · 깨진 상태 파일 = ERROR rc7 · 인자가 틀리면 판정 0(뒤 exec 가 같은 오류를 낸다)
#   사람이 일부러 같은 날 다시 올릴 때만 FT_MAGAZINE_REPUBLISH=1
if [ "${FT_MAGAZINE_REPUBLISH:-}" != 1 ]; then
  MOD="${FT_MAGAZINE_DOC:-$HERE/magazine_doc.py}"
  GUARD="$(python3 - "$MOD" "${NOW:0:10}" "$@" <<'PY'
import importlib.util, json, os, sys
path, now_date, user = sys.argv[1], sys.argv[2], sys.argv[3:]
try:
    sys.path.insert(0, os.path.dirname(os.path.abspath(path)))
    spec = importlib.util.spec_from_file_location("ft_magazine_doc_guard", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    try:
        args = mod.parse_args(["--src-repo", "-", "--src-sha", "-", "--src-path", "-"] + user)
    except SystemExit:  # 인자가 틀림 — 판정 0 으로 보내고 뒤 exec 가 같은 오류를 원문으로 낸다(조용한 skip 0)
        print("PROCEED")
        raise SystemExit(0)
    if not getattr(args, "publish", False):  # --dry-run 등 미리보기 — 가드 무관
        print("PROCEED")
        raise SystemExit(0)
    state_path = os.path.expanduser(args.state)
    try:
        state = json.load(open(state_path, encoding="utf-8")) if os.path.exists(state_path) else {}
    except (OSError, ValueError) as e:
        print(f"ERROR {state_path}: {type(e).__name__}: {e}")
        raise SystemExit(2)
    date = getattr(args, "date", None) or now_date
    hit = next((f"{k} root_ts={v.get('root_ts')}" for k, v in state.items() if isinstance(v, dict) and v.get("date") == date and v.get("uploaded") is True), "")
    print(f"SKIP {date} {hit}" if hit else "PROCEED")
except SystemExit:
    raise
except Exception as e:  # 모듈 없음·import 실패 등 — 조용히 통과시키지 않는다
    print(f"ERROR {type(e).__name__}: {e}")
    raise SystemExit(3)
PY
)" || { echo "ERROR magazine_from_news: 발행 상태 파일 못 읽음 — ${GUARD:-python3 rc=$?}" >&2; exit 7; }
  if [ "${GUARD%% *}" = SKIP ]; then
    rest="${GUARD#SKIP }"; gdate="${rest%% *}"; gdetail="${rest#* }"
    echo "skip date=$gdate 이미 발행됨 — $gdetail (같은 날 재발행 0 · 일부러면 FT_MAGAZINE_REPUBLISH=1)"
    exit 0
  fi
fi
if [ "${FT_LEDGER_SYNCED:-}" != 1 ]; then
  SYNC="${FT_LEDGER_SYNC:-$(cat "$ROOT/.fable-team/LIVE_BIN" 2>/dev/null)/ft-ledger-repo-sync.sh}"
  OUT="$(bash "$SYNC" "$REPO" 2>&1)" || { echo "ERROR magazine_from_news: 원장 사본 갱신 실패 — ${OUT:-$SYNC 실행 실패}" >&2; exit 6; }
  echo "$OUT" >&2
fi
[ -f "$REPO/$REL" ] || { echo "ERROR magazine_from_news: 매거진 원본 없음 — 원장 $REPO/$REL 이 없다(빈 매거진 발행 0)" >&2; exit 2; }
SHA="$(git -C "$REPO" log -1 --format=%H -- "$REL" 2>&1)" || { echo "ERROR magazine_from_news: git log 실패 — $SHA" >&2; exit 4; }
[ -n "$SHA" ] || { echo "ERROR magazine_from_news: 매거진 원본 없음 — $REL 이 커밋되지 않았다(magazine_doc 은 git 원문을 읽는다)" >&2; exit 3; }
# 커밋 뒤 고친 원장은 옛 커밋 내용이 넘어간다 — 지금 파일과 그 커밋의 blob 이 같을 때만 진행한다
NOW_BLOB="$(git -C "$REPO" hash-object -- "$REPO/$REL")"
SHA_BLOB="$(git -C "$REPO" rev-parse "$SHA:$REL" 2>&1)" || { echo "ERROR magazine_from_news: git rev-parse 실패 — $SHA_BLOB" >&2; exit 4; }
[ "$NOW_BLOB" = "$SHA_BLOB" ] || { echo "ERROR magazine_from_news: 매거진 원본 미커밋 수정 — $REL 의 지금 내용이 커밋 $SHA 와 다르다(커밋 뒤 다시)" >&2; exit 5; }
# r851 A2 — 원장 신선도: max(«마지막 갱신», 기계 채움 성공) 이 FT_LEDGER_FRESH_MIN(60)분 넘게 낡으면 발행 0(exit 6 과 같은 급 · planner [긴급] 1통은 도구가 같은 사건 1번)
#   FT_LEDGER_FRESH_GATE=0 = 끔(되돌림) · FT_LEDGER_FRESH = 도구 경로(시험 대역)
if [ "${FT_LEDGER_FRESH_GATE:-1}" != 0 ]; then
  FRESH="${FT_LEDGER_FRESH:-$(cat "$ROOT/.fable-team/LIVE_BIN" 2>/dev/null || true)/ft-ledger-fill}"
  OUT="$(bash "$FRESH" fresh --repo "$REPO" --path "$REL" --ref "$SHA" 2>&1)" || { echo "ERROR magazine_from_news: 원장 신선도 — ${OUT:-$FRESH 실행 실패} (낡은 매거진 발행 0)" >&2; exit 6; }
fi
# r1005 — 발행 뒤 9칸 재측정 1줄(ft-news-verify --kind magazine · --tail = 발행본 꼬리 «검증 N/9») · 검증 실패는 발행 rc 를 바꿔지 않는다
#   발행이 «실제로 쓴» 출력 폴더(--out-dir 반영) 에서 찾는다 · 못 찾으면 ERROR 1줄 + rc7(조용한 건너뜀 0)
#   «~» 는 사람이 쓴 대로 펼칩니다(발행기 magazine_doc 는 expanduser 를 한다) · HOME 없이 «~» 출력 폴더면 rc7 · 그 밖은 ${HOME:-} 끌로 안전
DOC="${FT_MAGAZINE_DOC:-$HERE/magazine_doc.py}"
RC=0
OUT="$(python3 "$DOC" --src-repo "$REPO" --src-sha "$SHA" --src-path "$REL" --date "${NOW:0:10}" "$@" 2>&1)" || RC=$?
printf '%s\n' "$OUT"
[ "$RC" -eq 0 ] || exit "$RC"
if [ "${FT_NEWS_VERIFY:-1}" != 0 ]; then
  OUTDIR=""; WANT=""
  for ARG in "$@"; do
    case "$ARG" in
      --out-dir) WANT=out ;;
      --out-dir=*) OUTDIR="${ARG#--out-dir=}" ;;
      *) [ "$WANT" = out ] && OUTDIR="$ARG" && WANT="" ;;
    esac
  done
  SEARCH="${OUTDIR:-${FT_MAGAZINE_OUT:-${HOME:-}/.hermes/magazine}}"
  case "$SEARCH" in  # r1005 반례 6 — «~» 를 글자 그대로 찾아 rc7 나던 길(발행기 magazine_doc 는 expanduser 를 한다)
    "~"|"~/"*)
      if [ -z "${HOME:-}" ]; then
        echo "ERROR magazine_from_news: 출력 폴더 «${SEARCH}» — HOME 없음(«~» 펼침 불가)" >&2
        exit 7
      fi
      SEARCH="$HOME${SEARCH#\~}"  # «~» → HOME · «~/x» → HOME/x
      ;;
  esac
  HTML="$(printf '%s\n' "$OUT" | sed -n 's/.* html=\([^ ]*\.html\).*/\1/p' | tail -1)"
  case "$HTML" in  # r1005 반례 6 — 발행 출력이 «~» 달고 오는 경우도 같은 자리에서 펼친다(HOME 없으면 rc7)
    "~"|"~/"*)
      if [ -z "${HOME:-}" ]; then
        echo "ERROR magazine_from_news: 발행 출력 경로 «${HTML}» — HOME 없음(«~» 펼침 불가)" >&2
        exit 7
      fi
      HTML="$HOME${HTML#\~}"  # «~» → HOME · «~/x» → HOME/x
      ;;
  esac
  case "$HTML" in  # 발행기가 상대 경로를 찍으면 그대로 · 이름만 찍으면 출력 폴더 기준
    /*) BODY="$HTML" ;;
    "") BODY="" ;;
    *) BODY="$SEARCH/$HTML" ;;
  esac
  if [ -z "$HTML" ]; then
    echo "WARN magazine_from_news: 발행 출력에 html= 줄 없음 — 검증 건너뜀(발행 대역)" >&2
  elif [ ! -f "$BODY" ]; then
    echo "ERROR magazine_from_news: 검증할 발행본 못 찾음 — $BODY (--out-dir 반영 · 발행 출력 html=$HTML)" >&2
    exit 7
  else
    VERIFY="${FT_NEWS_VERIFY_BIN:-$(cat "$ROOT/.fable-team/LIVE_BIN" 2>/dev/null || true)/ft-news-verify}"
    if [ -e "$VERIFY" ]; then bash "$VERIFY" --kind magazine --body "$BODY" --tail || true
    else echo "ERROR magazine_from_news: 검증기 없음 — $VERIFY (설치 확인 · 발행은 그대로)" >&2; fi
  fi
fi
exit 0
