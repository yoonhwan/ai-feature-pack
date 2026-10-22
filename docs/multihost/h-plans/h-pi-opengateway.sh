#!/usr/bin/env bash
# h-pi-opengateway.sh — 원격 노드(기본 OCI)의 pi 를 이 맥과 같은 opengateway(deepseek) 설정으로 맞춘다.
#   (2026-10-22 · aifp-worker-master-claude#3 · 오빠 «pi 도 설치해야지? opengateway 설정이랑»)
#   실행은 오빠가 `! bash /tmp/h<N>` 로만. mini 도 같은 장으로: `R=mini bash /tmp/h<N>`.
#
# 이 맥: ~/.pi/agent/models.json 의 apiKey = «!security find-generic-password -ws opengateway»(키체인).
# 원격(리눅스 키체인 없음): 키를 ~/.pi/agent/opengateway.key(0600)에 두고 apiKey = «!cat ~/.pi/agent/opengateway.key».
# 키 값은 화면·로그·인자에 한 번도 안 나온다 — 키체인 → 이 맥 0600 임시 파일 → ssh 표준입력 → 원격 파일(umask 077) · 임시 파일은 끝나면 삭제.
# models.json·settings.json 은 이 맥 파일에서 apiKey 한 칸만 바꿔 보낸다(나머지 동일). 기존 원격 파일은 .bak-<시각> 로 백업.
# rc: 0 성공 · 2 사전점검 실패 · 3 배치 실패 · 5 pi 호출 확인 실패(설정은 남김 — 로그 안내)
# 롤백: ssh <R> 'cd ~/.pi/agent && rm -f opengateway.key && for f in models.json settings.json; do b=$(ls -t $f.bak-* 2>/dev/null | head -1); [ -n "$b" ] && cp -p "$b" "$f"; done'
set -uo pipefail

R="${R:-oci}"
PI_DIR_LOCAL="$HOME/.pi/agent"
if [ "$R" = oci ]; then SSHX=(-o IdentitiesOnly=yes -i "${KEY:-$HOME/.ssh/oci_chuncheon}"); else SSHX=(); fi
CP="$(mktemp -d /tmp/h-pi-cm.XXXXXX)"
cleanup() { ssh -O exit -o ControlPath="$CP/s" "$R" >/dev/null 2>&1; rm -f "$CP/s" "$CP/og.key"; rmdir "$CP" 2>/dev/null; }
trap cleanup EXIT
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3
    ${SSHX[@]+"${SSHX[@]}"} -o ControlMaster=auto -o ControlPersist=120 -o ControlPath="$CP/s")
say() { printf '[h-pi] %s\n' "$*"; }
die() { printf '[h-pi] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
rs() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$R" "$@"; }
# 원격 비대화형 셸 PATH 에는 npm 사용자 prefix·~/.local/bin·homebrew 가 없다(h377·h375 실측)
RP='export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:/opt/homebrew/bin:$PATH";'

# ── 0) 로컬 사전점검 ─────────────────────────────────────────────────────────
say "0/4 로컬 사전점검 (대상 R=$R)"
[ -f "$PI_DIR_LOCAL/models.json" ] && [ -f "$PI_DIR_LOCAL/settings.json" ] || die 2 "이 맥 ~/.pi/agent/models.json·settings.json 없음"
# 키는 변수에 담지 않는다 — 키체인 → 이 맥 0600 임시 파일(종료 때 삭제) → ssh 표준입력
KF="$CP/og.key"
( umask 077; security find-generic-password -ws opengateway > "$KF" 2>/dev/null ) || true
[ -s "$KF" ] || die 2 "키체인에서 opengateway 키를 못 읽었다(키체인 잠김? 항목 이름 opengateway)"
say "        키체인 키 읽음(크기만): $(wc -c < "$KF" | tr -d ' ') bytes"
MODELS_OUT="$(python3 - "$PI_DIR_LOCAL/models.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
p = d.get("providers", {}).get("opengateway")
if not p: sys.exit("opengateway provider 없음")
p["apiKey"] = "!cat ~/.pi/agent/opengateway.key"
print(json.dumps(d, ensure_ascii=False, indent=2))
PY
)" || die 2 "models.json 변환 실패"
printf '%s' "$MODELS_OUT" | grep -q 'opengateway.key' || die 2 "변환 결과에 키 파일 참조가 없다"

# ── 1) 원격 사전점검 ─────────────────────────────────────────────────────────
say "1/4 원격 사전점검"
PRE="$(rs 20 "$RP"' echo "pi=$(pi --version 2>/dev/null)"; echo "py=$(command -v python3 >/dev/null && echo yes || echo NO)"' 2>&1)" || die 2 "$R 접속 실패"
printf '%s\n' "$PRE" | sed 's/^/        /'
printf '%s\n' "$PRE" | grep -q '^pi=[0-9]' || die 2 "원격에 pi 가 없다 — OCI 는 h377, mini 는 h375 먼저"

# ── 2) 배치(백업 → 키 파일 0600 → models·settings) ─────────────────────────
say "2/4 배치(기존 파일은 .bak-<시각> 백업)"
rs 20 'set -e; mkdir -p ~/.pi/agent; chmod 700 ~/.pi ~/.pi/agent; cd ~/.pi/agent; ts=$(date +%Y%m%d-%H%M%S); for f in models.json settings.json opengateway.key; do [ -f "$f" ] && cp -p "$f" "$f.bak-$ts"; done; echo backup=ok' >/dev/null || die 3 "백업 실패"
rs 20 'set -e; umask 077; tr -d "\n" > ~/.pi/agent/opengateway.key.tmp; test -s ~/.pi/agent/opengateway.key.tmp; mv ~/.pi/agent/opengateway.key.tmp ~/.pi/agent/opengateway.key; chmod 600 ~/.pi/agent/opengateway.key; echo key=ok' < "$KF" >/dev/null || die 3 "키 파일 쓰기 실패"
rm -f "$KF"
printf '%s\n' "$MODELS_OUT" | rs 20 'set -e; cat > ~/.pi/agent/models.json.tmp; python3 -c "import json;json.load(open(\"$HOME/.pi/agent/models.json.tmp\"))"; mv ~/.pi/agent/models.json.tmp ~/.pi/agent/models.json; chmod 644 ~/.pi/agent/models.json; echo models=ok' >/dev/null || die 3 "models.json 쓰기 실패"
rs 20 'set -e; cat > ~/.pi/agent/settings.json.tmp; python3 -c "import json;json.load(open(\"$HOME/.pi/agent/settings.json.tmp\"))"; mv ~/.pi/agent/settings.json.tmp ~/.pi/agent/settings.json; chmod 644 ~/.pi/agent/settings.json; echo settings=ok' < "$PI_DIR_LOCAL/settings.json" >/dev/null || die 3 "settings.json 쓰기 실패"
rs 15 'cd ~/.pi/agent && ls -l opengateway.key models.json settings.json | awk "{print \$1, \$9}"' 2>&1 | sed 's/^/        /'

# ── 3) 확인: pi -p ping (CLI 고정비 3.5초 + 7초 룰) ─────────────────────────
say "3/4 확인: pi -p ping (상한 11초 · 표준입력 닫음 — 안 닫으면 pi 가 입력을 기다려 멈춘다, 이 맥 실측)"
PING="$(rs 20 "$RP"' cd ~ && timeout 11 pi -p --no-session "reply with the single word pong" < /dev/null > /tmp/h-pi-ping.out 2>&1; rc=$?; tail -3 /tmp/h-pi-ping.out | cut -c1-160; echo pi_rc=$rc' 2>&1)" || true
printf '%s\n' "$PING" | sed 's/^/        /'
printf '%s\n' "$PING" | grep -q 'pi_rc=0' || die 5 "pi 호출 실패 — 원격 /tmp/h-pi-ping.out 확인(설정은 남겨 둠 · 롤백은 머리말)"

say "4/4 끝 — 닫는 증거: 위 pi_rc=0 줄 + 파일 모드 줄(opengateway.key -rw-------)"
