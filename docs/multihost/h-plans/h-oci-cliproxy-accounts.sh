#!/usr/bin/env bash
# h-oci-cliproxy-accounts.sh — OCI cliproxy(8317)에 계정을 «목표 개수» 까지 차례로 OAuth 로그인한다.
#   (2026-10-22 · aifp-worker-master-claude#3 · 오빠 결정: claude 5 + codex 2 · BYZ 파일 복사 0 — 토큰 갱신 충돌 방지)
#   실행은 오빠가 `! bash /tmp/h<N>` 로만. h-oci-infer-stack.sh 의 login_one 과 같은 방식(claude=콜백 포워딩 · codex=기기 코드).
#
# 계정마다: 주소/코드 출력 → (OPEN=1 이면) 크롬 시크릿 창 1개로 연다 → 오빠가 «그 계정» 으로 승인 → 파일 수가 늘면 다음.
# 이미 있는 계정으로 승인하면 파일이 덮어써져 수가 안 늘어난다 → 대기 초과(rc=4). 화면의 «지금 계정 목록» 을 보고 다른 계정으로.
# 비대화형(프롬프트 0) · 멱등(목표 수에 찬 종류는 건너뜀) · 비밀값 출력 0(파일 이름·모드만)
# rc: 0 성공 · 2 사전점검 실패 · 4 승인 대기 초과(같은 h 재실행으로 이어감) · 5 로그인/재시작 실패
# 롤백: 늘어난 계정 파일을 지우면 된다 — ssh oci 'ls ~/.cli-proxy-api/' 로 이름 확인 후 사람이 판단(자동 삭제 0)
set -uo pipefail

R="${R:-oci}"
KEY="${KEY:-$HOME/.ssh/oci_chuncheon}"
WANT_CLAUDE="${WANT_CLAUDE:-5}"
WANT_CODEX="${WANT_CODEX:-2}"
LOGIN_WAIT="${LOGIN_WAIT:-600}"     # 계정 1개당 승인 대기 상한(초) — 사람 승인 대기(외부 호출 아님) · 원격 호출은 각 25초 이하
OPEN="${OPEN:-1}"                   # 1 = 계정마다 크롬 시크릿 창 1개로 주소를 연다(현재 브라우저 로그인 보존)

CP="$(mktemp -d /tmp/h-oci-cm.XXXXXX)"
cleanup() { ssh -O exit -o ControlPath="$CP/s" "$R" >/dev/null 2>&1; rm -f "$CP/s"; rmdir "$CP" 2>/dev/null; }
trap cleanup EXIT
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3
    -o IdentitiesOnly=yes -i "$KEY" -o ControlMaster=auto -o ControlPersist=180 -o ControlPath="$CP/s")
say() { printf '[h-acct] %s\n' "$*"; }
die() { printf '[h-acct] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
rs() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$R" "$@"; }

open_incognito() {
  [ "$OPEN" = 1 ] || return 0
  open -na "Google Chrome" --args --incognito "$1" >/dev/null 2>&1 || say "        (크롬 자동 열기 실패 — 위 주소를 시크릿 창에 직접 붙여 넣으세요)"
}
count() { rs 15 "ls ~/.cli-proxy-api/$1-*.json 2>/dev/null | wc -l" 2>/dev/null | tr -d ' '; }
list_accounts() { rs 15 'ls ~/.cli-proxy-api/ | grep -E "^(claude|codex)-.*\.json$"' 2>/dev/null | sed 's/^/          · /'; }

# ── 0) 사전점검 ──────────────────────────────────────────────────────────────
say "0/3 사전점검 (목표: claude $WANT_CLAUDE · codex $WANT_CODEX)"
PRE="$(rs 20 'echo "cliproxy=$(systemctl --user is-active cliproxyapi)"; test -x ~/bin/cli-proxy-api && echo bin=yes || echo bin=NO; test -f ~/.cli-proxy-api/config.yaml && echo cfg=yes || echo cfg=NO' 2>&1)" || die 2 "oci 접속 실패"
printf '%s\n' "$PRE" | sed 's/^/        /'
printf '%s\n' "$PRE" | grep -qx 'cliproxy=active' || die 2 "cliproxy 가 active 가 아니다 — h376(h-oci-infer-stack.sh) 먼저"
printf '%s\n' "$PRE" | grep -qx 'bin=yes' || die 2 "~/bin/cli-proxy-api 없음"
printf '%s\n' "$PRE" | grep -qx 'cfg=yes' || die 2 "~/.cli-proxy-api/config.yaml 없음"
say "        지금 계정 목록:"; list_accounts

# ── 1) 종류별로 목표 수까지 로그인 ──────────────────────────────────────────
login_until() {   # $1=claude|codex  $2=로그인 플래그  $3=목표 수
  local kind="$1" flag="$2" want="$3" have url port t fwd n
  while :; do
    have="$(count "$kind")"; [ -n "$have" ] || die 5 "$kind 계정 수 조회 실패"
    [ "$have" -ge "$want" ] && { say "        $kind $have/$want — 목표 도달"; return 0; }
    n=$((have + 1)); fwd=0; url=""
    say "1/3 $kind 로그인 $n/$want — 아직 없는 계정으로 승인하세요"
    rs 25 "mkdir -p ~/h-login; [ -f ~/h-login/$kind.pid ] && kill \$(cat ~/h-login/$kind.pid) 2>/dev/null; : > ~/h-login/$kind.log; chmod 600 ~/h-login/$kind.log; nohup ~/bin/cli-proxy-api -config ~/.cli-proxy-api/config.yaml -no-browser $flag > ~/h-login/$kind.log 2>&1 < /dev/null & echo \$! > ~/h-login/$kind.pid; echo started" >/dev/null \
      || die 5 "$kind 로그인 프로세스 시작 실패"
    t=0
    while [ "$t" -lt 40 ]; do
      url="$(rs 10 "grep -oE 'https://[^ ]+' ~/h-login/$kind.log | head -1" 2>/dev/null)"
      [ -n "$url" ] && break; sleep 2; t=$((t+2))
    done
    [ -n "$url" ] || die 5 "$kind 로그인 주소가 안 나왔다(~/h-login/$kind.log)"
    if [ "$kind" = claude ]; then
      port="$(python3 -c 'import sys,urllib.parse as u;q=u.parse_qs(u.urlparse(sys.argv[1]).query).get("redirect_uri",[""])[0];print(u.urlparse(q).port or "")' "$url")"
      [ -n "$port" ] || die 5 "claude 콜백 포트를 주소에서 못 읽었다"
      ssh -O forward -L "$port:127.0.0.1:$port" -o ControlPath="$CP/s" "$R" >/dev/null 2>&1 \
        || die 5 "이 맥 localhost:$port 포워딩 실패(이미 쓰는 중?) — 그 포트를 쓰는 프로세스를 끄고 같은 h 를 다시"
      fwd=1
      say "        새 시크릿 창에서 claude 계정 로그인 → 승인 (콜백 localhost:$port → OCI)"
      printf '        %s\n' "$url"
      open_incognito "$url"
    else
      say "        새 시크릿 창에서 ChatGPT 계정 로그인 → 아래 코드 입력 → 승인 (보안 설정의 기기 코드 로그인이 켜져 있어야 함)"
      rs 10 "grep -iE 'https://|code' ~/h-login/$kind.log | head -4" 2>/dev/null | sed 's/^/        /'
      open_incognito "$url"
    fi
    t=0
    while [ "$t" -lt "$LOGIN_WAIT" ]; do
      have="$(count "$kind")"
      if [ -n "$have" ] && [ "$have" -ge "$n" ]; then
        [ "$fwd" = 1 ] && ssh -O cancel -L "$port:127.0.0.1:$port" -o ControlPath="$CP/s" "$R" >/dev/null 2>&1
        rs 10 "chmod 600 ~/.cli-proxy-api/${kind}-*.json; kill \$(cat ~/h-login/$kind.pid) 2>/dev/null; rm -f ~/h-login/$kind.pid" >/dev/null 2>&1
        say "        $kind $have/$want 완료 · 지금 계정 목록:"; list_accounts
        break
      fi
      sleep 5; t=$((t+5))
    done
    if [ "$t" -ge "$LOGIN_WAIT" ]; then
      [ "$fwd" = 1 ] && ssh -O cancel -L "$port:127.0.0.1:$port" -o ControlPath="$CP/s" "$R" >/dev/null 2>&1
      rs 10 "kill \$(cat ~/h-login/$kind.pid) 2>/dev/null; rm -f ~/h-login/$kind.pid" >/dev/null 2>&1
      printf '[h-acct] %s %s/%s 승인이 %s초 안에 안 왔다(이미 있는 계정으로 승인했으면 수가 안 늘어난다) — 같은 h 재실행으로 이어감(rc=4)\n' "$kind" "$n" "$want" "$LOGIN_WAIT" >&2
      exit 4
    fi
  done
}
login_until claude -claude-login "$WANT_CLAUDE"
login_until codex -codex-device-login "$WANT_CODEX"

# ── 2) cliproxy 재시작 → 3) 확인 ────────────────────────────────────────────
say "2/3 cliproxy 재시작(새 계정 읽기)"
rs 25 'systemctl --user restart cliproxyapi.service; sleep 5; systemctl --user is-active cliproxyapi' 2>/dev/null | grep -qx active || die 5 "cliproxy 재시작 실패 — journalctl --user -u cliproxyapi -n 40"
say "3/3 확인"
C1="$(count claude)"; C2="$(count codex)"
M="$(rs 15 "curl -s -m 7 http://127.0.0.1:8317/v1/models | python3 -c 'import sys,json;print(len(json.load(sys.stdin).get(\"data\",[])))'" 2>/dev/null)"
printf '        claude=%s/%s codex=%s/%s models=%s\n' "$C1" "$WANT_CLAUDE" "$C2" "$WANT_CODEX" "$M"
list_accounts
[ "$C1" -ge "$WANT_CLAUDE" ] && [ "$C2" -ge "$WANT_CODEX" ] || die 5 "목표 수 미달"
say "끝 — 닫는 증거: 위 claude=/codex=/models= 줄"
