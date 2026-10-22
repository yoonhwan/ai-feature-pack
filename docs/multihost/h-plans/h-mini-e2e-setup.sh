#!/usr/bin/env bash
# h-mini-e2e-setup.sh — BYZ e2e 러너의 «폐쇄 파일만» mini(ssh 별칭 `mini`)로 배치하고 import 를 확인한다.
#   초안(2026-10-22 · aifp-pi-master-pi#0) · 실행은 오빠가 `! bash /tmp/h<N>` 로만. 이 스크립트는 «배치 계획» 이다.
#   근거: docs/multihost/measured-runner-closure-20261022.md (AST 폐쇄 실측 · 3rd-party = websockets·jwt)
# 원칙: 원본 BYZ repo 는 **읽기만** · 비밀 파일(.env*) 복사 0 · 값 출력 0 · 대화형 0 · 외부 호출 1건 상한 70초
# rc: 0 성공 · 2 사전점검 · 3 배치 실패 · 5 import/사후점검 실패
set -uo pipefail

MINI="${MINI:-mini}"                       # ★고정 규칙: ssh 별칭만(사용자 이름 박지 않음)★
SRC="${SRC:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents}"   # 원본(읽기만)
DST="${DST:-~/Project/BYZ-e2e}"            # mini 쪽 목적지(repo 와 같은 상대 구조)
PY_MODS="${PY_MODS:-websockets pyjwt}"     # 러너 폐쇄의 3rd-party(§2). 이미 있으면 건너뜀 · 버전은 python3.13 에 맞는 최신(설치 뒤 pip freeze 로 기록)
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-e2e] %s\n' "$*"; }
die() { printf '[h-e2e] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
ms() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI" "$@"; }

# 폐쇄 목록 — measured-runner-closure-20261022.md §1 과 1:1 (rsync --files-from 용)
FILES=(
  tests/__init__.py
  tests/e2e/__init__.py
  tests/e2e/realtime_multi_e2e.py
  tests/e2e/cdp_helper.py
  tests/e2e/tts_rms_gate.py
  tests/e2e/multi_realtime_corpus/__init__.py
  tests/e2e/multi_realtime_corpus/cli.py
  tests/e2e/multi_realtime_corpus/lib/__init__.py
  tests/e2e/multi_realtime_corpus/lib/loader.py
  tests/e2e/multi_realtime_corpus/lib/dialogue_runner.py
  tests/e2e/multi_realtime_corpus/lib/loom_domain.py
  tests/e2e/multi_realtime_corpus/lib/turn_execution.py
  tests/e2e/multi_realtime_corpus/lib/turn_validation.py
  tests/e2e/multi_realtime_corpus/lib/transcript_quality.py
  tests/e2e/multi_realtime_corpus/lib/voices.py
  tests/e2e/multi_realtime_corpus/scenarios/multi_realtime_corpus.jsonl
)

# ── 0) 로컬 사전점검 ────────────────────────────────────────────────────────
say "0/6 로컬 사전점검(원본 읽기만)"
[ -d "$SRC" ] || die 2 "원본 리포가 없다: $SRC"
command -v rsync >/dev/null 2>&1 || die 2 "rsync 가 없다"
MISS=0
for f in "${FILES[@]}"; do [ -f "$SRC/$f" ] || { say "        MISS $f"; MISS=$((MISS+1)); }; done
[ "$MISS" -eq 0 ] || die 2 "폐쇄 목록 중 $MISS 개가 원본에 없다 — measured-runner-closure 문서와 대조 필요"
say "        폐쇄 파일 ${#FILES[@]}개 전부 존재"
# lib/ 에 폐쇄 목록 밖 파일이 있으면 알린다(빠뜨림 방지)
EXTRA="$(cd "$SRC" && ls tests/e2e/multi_realtime_corpus/lib/*.py 2>/dev/null | grep -vFf <(printf '%s\n' "${FILES[@]}" | grep '/lib/') || true)"
[ -z "$EXTRA" ] || say "        ⚠ 목록 밖 lib/*.py (필요할 수 있음): $(printf '%s' "$EXTRA" | tr '\n' ' ')"
# 비밀 파일이 목록에 섞이지 않았는지 «가드»
printf '%s\n' "${FILES[@]}" | grep -qE '(^|/)\.env' && die 2 "폐쇄 목록에 .env 가 들어 있다 — 즉시 중단(비밀 복사 금지)"

# ── 1) mini 사전점검 ────────────────────────────────────────────────────────
say "1/6 mini 사전점검 (ssh $MINI)"
PRE="$(ms 20 'bash -lc "echo user=$(id -un); echo py=$(python3 -V 2>&1 | awk "{print \\$2}"); python3 -c \"import websockets\" 2>/dev/null && echo ws=yes || echo ws=no; python3 -c \"import jwt\" 2>/dev/null && echo jwt=yes || echo jwt=no; echo disk=$(df -h ~ | awk \"NR==2{print \\$4}\"); df -h ~ | tail -1"' 2>&1)" || die 2 "mini 접속 실패: $PRE"
printf '%s\n' "$PRE" | sed 's/^/        /'
printf '%s\n' "$PRE" | grep -q '^user=byz' || die 2 "원격 사용자가 byz 가 아니다(ssh 별칭 mini 확인)"
printf '%s\n' "$PRE" | grep -q '^py=3\.9' || say "        ⚠ python 이 3.9 가 아니다 — pip 설치 경로 확인"

# ── 2) 목적지 준비 + 이전 사본 백업 ─────────────────────────────────────────
say "2/6 목적지 준비"
ms 25 "set -e; mkdir -p $DST; if [ -d $DST/tests ]; then ts=\$(date +%Y%m%d-%H%M%S); cp -a $DST/tests $DST/tests.bak-\$ts; echo backup=tests.bak-\$ts; fi; echo dst=ok" \
  || die 3 "목적지 준비/백업 실패"

# ── 3) 폐쇄 파일만 rsync (구조 보존 · .env 제외) ─────────────────────────────
say "3/6 rsync (폐쇄 ${#FILES[@]}개)"
LIST="$(mktemp /tmp/h-e2e-files.XXXXXX)"; printf '%s\n' "${FILES[@]}" > "$LIST"
cleanup() { rm -f "$LIST"; }
trap cleanup EXIT
if timeout 70 rsync -a --files-from="$LIST" -e "ssh ${SO[*]}" "$SRC/" "$MINI:$DST/" 2>/tmp/h-e2e-rsync.err; then
  say "        rsync ok"
else
  sed 's/^/        /' /tmp/h-e2e-rsync.err | tail -5
  die 3 "rsync 실패(위 오류)"
fi
# 비밀 파일이 딸려갔는지 «사후 확인» — 있으면 즉시 알린다(삭제는 하지 않는다: 원격 쓰기 최소화 · 사람 판단)
SEC="$(ms 20 "ls -1 $DST/.env $DST/.env.local 2>/dev/null | wc -l | tr -d ' '")" || SEC=0
[ "$SEC" = "0" ] || say "        ⚠ 목적지에 .env 계열이 있다($SEC) — 이 h 가 만든 것이 아니다. 내용은 읽지 않는다."

# ── 4) 3rd-party 설치 — 전용 venv(brew python3.13) ──────────────────────────
#   이유: mini 시스템 python 은 3.9.6 이라 websockets 16(>=3.10)·러너의 `X | None` 문법과 어긋나고, brew python 에는 pip --user 가 막혀(PEP 668) 있다.
say "4/6 venv + python 모듈 설치($PY_MODS)"
ms 70 "set -e; [ -x /opt/homebrew/bin/python3.13 ] || { echo no-py313; exit 1; }; cd $DST; [ -x .venv/bin/python ] || /opt/homebrew/bin/python3.13 -m venv .venv; echo venv=ok" \
  || die 3 "venv 생성 실패(/opt/homebrew/bin/python3.13 확인)"
for m in $PY_MODS; do
  case "$m" in websockets) probe="websockets";; pyjwt) probe="jwt";; *) probe="$m";; esac
  if ms 15 "cd $DST && .venv/bin/python -c 'import $probe'" >/dev/null 2>&1; then
    say "        $m 이미 있음 — 건너뜀"
  else
    ms 70 "cd $DST && .venv/bin/python -m pip install --quiet $m && echo installed=$m" || die 3 "$m 설치 실패/70초 초과(같은 h 재실행이 pip 캐시로 이어감)"
    say "        $m 설치 완료"
  fi
done

# ── 5) import 확인 + 사후 점검(파일 수·sha) ─────────────────────────────────
say "5/6 import 확인"
PY_PROBE="cd $DST && .venv/bin/python -"          # 원격에서 stdin 으로 파이썬을 받아 실행
IMP="$(
  ms 60 "$PY_PROBE" 2>&1 <<'PYEOF'
import sys
sys.path.insert(0, ".")
sys.path.insert(0, "tests/e2e")   # 러너가 _THIS_DIR 을 path 에 넣는 것과 같다
import cdp_helper        # noqa: F401  (CDP 직접 연결)
import tts_rms_gate      # noqa: F401  (RMS 게이트)
from tests.e2e.multi_realtime_corpus import cli  # noqa: F401  (lazy import 대상)
import websockets        # noqa: F401  (3rd-party)
print("IMPORT_OK cdp_helper tts_rms_gate corpus.cli websockets")
PYEOF
) || true"
printf '%s\n' "$IMP" | tail -6 | sed 's/^/        /'
printf '%s\n' "$IMP" | grep -q 'IMPORT_OK' || die 5 "import 확인 실패 — 위 오류(모듈 누락/경로 문제)"

say "5/6 사후 점검 — 파일 수·sha256 대조"
LOCAL_SUM="$(cd "$SRC" && shasum -a 256 "${FILES[@]}" 2>/dev/null | awk '{print $1, $2}')"
REMOTE_N="$(ms 20 "find $DST/tests -type f \\( -name '*.py' -o -name '*.jsonl' \\) 2>/dev/null | wc -l | tr -d ' '")" || REMOTE_N=0
say "        로컬 폐쇄 ${#FILES[@]}개 · mini tests/ 아래 py+jsonl ${REMOTE_N}개"
REMOTE_SUM="$(ms 25 "cd $DST && shasum -a 256 $(printf '%s ' "${FILES[@]}") 2>/dev/null | awk '{print \$1, \$2}'")" || REMOTE_SUM=""
if [ -n "$REMOTE_SUM" ] && [ "$LOCAL_SUM" = "$REMOTE_SUM" ]; then
  say "        sha256 전부 일치"
else
  say "        ⚠ sha 목록이 다르다 — 아래 diff(앞 5줄)"
  diff <(printf '%s\n' "$LOCAL_SUM") <(printf '%s\n' "$REMOTE_SUM") | head -5 | sed 's/^/        /'
fi

# ── 6) 끝 ───────────────────────────────────────────────────────────────────
say "6/6 끝"
cat <<EOF
        닫는 증거 3줄(보고에 그대로):
          · rsync ok + 폐쇄 ${#FILES[@]}개
          · IMPORT_OK cdp_helper tts_rms_gate corpus.cli websockets
          · sha256 전부 일치(또는 diff 앞 5줄)
        이 h 가 «하지 않은 것»: .env* 복사 0 · TTS 3종(sag·tts-say·sox) 설치 0 · Chrome 기동 0 · 워크트리(v6-realtime-live) 배치 0 · 원본 repo 수정 0
        다음(별도 승인): TTS 3종 설치 · Chrome \`--remote-debugging-port=9333\` 재기동 · BYZ_E2E_JWT_SECRET 은 op develop 볼트에서 env 로만 주입
        롤백: ssh $MINI 'rm -rf $DST' (백업은 $DST/tests.bak-<ts> 로 남아 있다)
EOF
exit 0
