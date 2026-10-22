#!/usr/bin/env bash
# h-mini-tts-say.sh — mini(ssh 별칭 `mini`)에 tts-say 를 «say 전용» 으로 설치한다(러너 발화 경로 살리기).
#   초안(2026-10-22 · aifp-pi-master-pi#0) · 실행은 오빠가 `! bash /tmp/h<N>` 로만. 이 파일은 «설치 계획» 이다.
#   근거: docs/multihost/measured-runner-tts-path-20261022.md
#     · 러너 say 엔진은 1369-1372 에서 `tts-say speak --engine say …` 를 하드코딩 호출 → tts-say 없으면 즉시 죽는다
#     · sox 는 불필요(afconvert 114 가 1순위) · SwitchAudioSource 불필요(afplay 190 = 기본 출력장치 재생)
# 이 스크립트가 하는 것: 이 맥의 tts-say(단일 파이썬 파일) → mini ~/.local/bin/tts-say (shebang 을 mini 파이썬 3.13 으로)
#   ★소리는 내지 않는다★ — `voices --engine say` 로 목록만 확인(speak 금지: 출력장치 미설정 상태에서 소리 안 냄)
# 비대화형 · 멱등 · 비밀값 출력 0 · sudo 0 · 원격 쓰기 = tts-say 파일 1개(+.bak)뿐
# rc: 0 성공 · 2 사전점검 · 3 설치 실패 · 5 사후 점검 실패
set -uo pipefail

MINI="${MINI:-mini}"                                   # ★고정 규칙: ssh 별칭만(사용자 이름 박지 않음)★
SRC="${SRC:-$HOME/.local/bin/tts-say}"
SRC_SHA256="${SRC_SHA256:-09df9350f152708d75aebc19977834c8d4e0fd47ac1bbfc85f3f124004ab4f69}"
SRC_BYTES="${SRC_BYTES:-19983}"
MINI_PY="${MINI_PY:-/opt/homebrew/bin/python3.13}"      # mini 시스템 python 은 3.9 · tts-say 는 3.10+ 요구
DST_DIR='$HOME/.local/bin'
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-tts] %s\n' "$*"; }
die() { printf '[h-tts] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
ms() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI" "$@"; }

# ── 0) 로컬 사전점검 ────────────────────────────────────────────────────────
say "0/6 로컬 사전점검"
[ -f "$SRC" ] || die 2 "tts-say 가 없다: $SRC"
GOT_BYTES="$(wc -c <"$SRC" | tr -d ' ')"
[ "$GOT_BYTES" = "$SRC_BYTES" ] || die 2 "tts-say 크기 불일치 — 기대 $SRC_BYTES / 실제 $GOT_BYTES (버전이 바뀌었나? sha·bytes 갱신 필요)"
GOT_SHA="$(shasum -a 256 "$SRC" | awk '{print $1}')"
[ "$GOT_SHA" = "$SRC_SHA256" ] || die 2 "tts-say sha256 불일치 — 기대 $SRC_SHA256 / 실제 $GOT_SHA"
say "        원본 확인: ${SRC_BYTES}B · sha256 ${SRC_SHA256:0:16}…"
# shebang 치환용 임시 사본(로컬 /tmp 에서만 · 원본 불변)
TMP="$(mktemp /tmp/tts-say-mini.XXXXXX)"
NEW="$(mktemp /tmp/tts-say-mini-new.XXXXXX)"
cleanup() { rm -f "$TMP" "$NEW"; }
trap cleanup EXIT
cp "$SRC" "$TMP"
{ printf '#!%s\n' "$MINI_PY"; tail -n +2 "$TMP"; } > "$NEW" || die 2 "shebang 치환 실패"
head -1 "$NEW" | grep -qx "#!$MINI_PY" || die 2 "shebang 치환 결과가 다르다: $(head -1 "$NEW")"
say "        shebang: $(head -1 "$NEW")"

# ── 1) mini 사전점검 ────────────────────────────────────────────────────────
say "1/6 mini 사전점검 (ssh $MINI)"
PRE="$(ms 20 'bash -lc "echo user=$(id -un); echo py=\$(/opt/homebrew/bin/python3.13 -V 2>&1); ls -l ~/.local/bin/tts-say 2>/dev/null || echo tts_say=absent; echo localbin=$(test -d ~/.local/bin && echo yes || echo NO); echo disk=$(df -h ~ | awk \"NR==2{print \\\$4}\")"' 2>&1)" || die 2 "mini 접속 실패: $PRE"
printf '%s\n' "$PRE" | sed 's/^/        /'
printf '%s\n' "$PRE" | grep -q '^user=byz' || die 2 "원격 사용자가 byz 가 아니다(ssh 별칭 mini 확인)"
printf '%s\n' "$PRE" | grep -q '^py=Python 3\.13' || die 2 "$MINI_PY 가 없거나 3.13 이 아니다 — mini 파이썬 경로 확인"
printf '%s\n' "$PRE" | grep -q '^localbin=yes' || say "        ⚠ ~/.local/bin 이 없다 — 만들 것이다"

# ── 2) 기존 사본 백업(.bak-<ts>) ────────────────────────────────────────────
say "2/6 기존 사본 백업"
ms 25 'set -e; mkdir -p ~/.local/bin; if [ -f ~/.local/bin/tts-say ]; then ts=$(date +%Y%m%d-%H%M%S); cp -p ~/.local/bin/tts-say ~/.local/bin/tts-say.bak-$ts; echo backup=tts-say.bak-$ts; else echo backup=none_installed; fi' \
  || die 3 "백업 실패"

# ── 3) 전송(shebang 치환 사본) ──────────────────────────────────────────────
say "3/6 전송"
if timeout 90 scp -q "${SO[@]}" "$NEW" "$MINI:~/.local/bin/tts-say.new"; then
  ms 20 'set -e; chmod 755 ~/.local/bin/tts-say.new; mv ~/.local/bin/tts-say.new ~/.local/bin/tts-say; echo placed=ok' \
    || die 3 "배치 실패"
else
  die 3 "scp 실패(네트워크/권한)"
fi
# 원격 sha 대조 — shebang 치환분은 로컬 원본과 해시가 다르므로 «치환 사본» 해시와 비교한다
LOC_SHA="$(shasum -a 256 "$NEW" | awk '{print $1}')"
REM_SHA="$(ms 20 'shasum -a 256 ~/.local/bin/tts-say | awk "{print \$1}"' 2>/dev/null)"
[ "$LOC_SHA" = "$REM_SHA" ] || die 3 "전송 손상 — 로컬 $LOC_SHA / 원격 $REM_SHA"
say "        sha256 일치(치환 사본): ${LOC_SHA:0:16}…"
say "        원본과 다른 점은 첫 줄(shebang)뿐이다 — 본문 diff 0:"
DIFFN="$(ms 20 'head -1 ~/.local/bin/tts-say' 2>/dev/null)"
[ "$DIFFN" = "#!$MINI_PY" ] || die 3 "원격 첫 줄이 shebang 이 아니다: $DIFFN"
ms 20 'ls -l ~/.local/bin/tts-say | awk "{print \$1, \$5, \$9}"' 2>&1 | sed 's/^/        /'

# ── 4) 실행 확인 — ★소리 안 냄(speak 금지)★ · 목록만 ───────────────────────
say "4/6 voices --engine say (앞 3줄 · 소리 0)"
VO="$(ms 45 'bash -lc "~/.local/bin/tts-say voices --engine say 2>&1 | head -3"' 2>&1)" || true
printf '%s\n' "$VO" | sed 's/^/        /'
printf '%s\n' "$VO" | grep -qE 'en_US|ko_KR|Hello' || say "        ⚠ voices 출력이 예상과 다르다 — 아래 ko 확인과 함께 판단(치명 아님)"

say "4/6 ko 음성 유무(러너 TTS_VOICE_MAP 의 ko→Yuna)"
KO="$(ms 30 'bash -lc "say -v \"?\" 2>/dev/null | grep -icE \"ko_KR\""' 2>&1)" || KO=0
say "        ko_KR 음성 수 = $KO (0 이면 러너 발화가 영어 음성으로 떨어진다)"
YN="$(ms 30 'bash -lc "say -v \"?\" 2>/dev/null | grep -c \"Yuna\""' 2>&1)" || YN=0
say "        Yuna 음성 = $YN (0 이면 TTS_VOICE_MAP 의 ko 기본값이 비어 있다 — 대체 음성 확인 필요)"

# ── 5) 사후 점검 ────────────────────────────────────────────────────────────
say "5/6 사후 점검"
OK="$(ms 30 'bash -lc "~/.local/bin/tts-say --help >/dev/null 2>&1 && echo help_rc=0 || echo help_rc=1"' 2>&1)" || OK="help_rc=?"
printf '%s\n' "$OK" | sed 's/^/        /'
printf '%s\n' "$OK" | grep -q 'help_rc=0' || die 5 "tts-say --help 실패 — 파이썬/문법 문제(위 출력 확인)"

# ── 6) 끝 ───────────────────────────────────────────────────────────────────
say "6/6 끝"
cat <<EOF
        닫는 증거 3줄(보고에 그대로):
          · 전송 sha256 일치 + 첫 줄 \`#!$MINI_PY\` + 권한 -rwxr-xr-x
          · voices --engine say 앞 3줄
          · ko_KR 음성 수 · Yuna 유무
        ★PATH 안내(러너 실행 전 필수)★ mini 에서 러너를 돌리는 셸은 **비로그인 ssh PATH** 라 ~/.local/bin 이 없다(실측: PATH_HAS_LOCALBIN=0).
          → 러너는 `tts-say` 를 PATH 에서 찾는다(subprocess). 실행 줄은 항상 PATH 를 앞에 붙이고, 시스템 python 3.9 가 아니라 h-mini-e2e-setup.sh 가 만든 venv python 으로 돌린다:
              ssh mini 'cd ~/Project/BYZ-e2e && PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH" .venv/bin/python tests/e2e/<러너 파일> <러너 인자>'
        ★소리 0 확인★ 이 h 는 \`voices\` 만 돌렸다(\`speak\` 금지). 발화 시험은 «출력 기본장치를 BlackHole 2ch/Multi-Output 으로 맞춘 뒤» 별도 승인으로 한다.
        이 h 가 하지 않은 것: sag 설치 0 · sox 설치 0 · SwitchAudioSource 설치 0 · Chrome 기동 0 · speak 실행 0 · 원본 tts-say 수정 0(로컬 /tmp 사본만 치환)
        롤백: ssh $MINI 'rm -f ~/.local/bin/tts-say' (백업이 있으면 ~/.local/bin/tts-say.bak-<ts> 로 복구)
EOF
exit 0
