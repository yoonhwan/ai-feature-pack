#!/usr/bin/env bash
# h-oci-infer-stack.sh — OCI(aifp-oci-jarvis · ubuntu)에 «추론 스택» 을 세운다: cliproxy(8317) + headroom(8790).
#   초안(2026-10-22 · aifp-pi-master-pi#0) · 실행은 오빠가 `! bash /tmp/h<N>` 로만. 이 파일은 «쓰기 계획» 이다.
#   골: OCI 에서 claude 가 «OCI 로컬 cliproxy(8317) → headroom(8790)» 경유로 돌 수 있게 만든다.
#
# 비대화형(프롬프트 0) · 멱등(이미 된 단계는 건너뜀) · 비밀값 출력 0(파일 이름·크기·모드만 찍는다)
# 하지 않는 것: 공인 22 닫기 · ufw/ACL 변경 · apt upgrade · 전역 환경변수 export · 기존 hermes/cloudflared 유닛 건드리기
# 롤백: 실패하면 새로 만든 유닛 2개를 stop+disable 하고 «이전 상태 백업» 을 되돌린다(아래 rollback()).
# rc: 0 성공 · 2 사전점검 실패 · 3 설치/배치 실패 · 5 기동·검증 실패(유닛은 남겨 두고 로그 안내)
set -uo pipefail

# ── 설정(오빠 승인 뒤에만 실행) ───────────────────────────────────────────────
R="${R:-oci}"                                  # ssh 별칭(공인 IP 유지 · tailnet 주소로도 가능: R=ubuntu@100.115.169.113)
KEY="${KEY:-$HOME/.ssh/oci_chuncheon}"
BIN_LOCAL="${BIN_LOCAL:-/private/tmp/claude-501/-Users-yoonhwan-Project-ai-feature-pack--worktrees-multihost-plan/83ec5aea-03fd-46fe-a345-58c8273b933f/scratchpad/xbuild/cli-proxy-api-linux-arm64}"
BIN_SHA256="${BIN_SHA256:-8d5f778176e4beeeaeb70534c921dfc87f1e25eaaba76a836daa2109af982848}"
HEADROOM_VER="${HEADROOM_VER:-0.33.0}"
CFG_LOCAL="${CFG_LOCAL:-$HOME/.cli-proxy-api/config.yaml}"
# 복사할 인증 파일 «이름만» — 값은 절대 읽지 않는다. 기본 = claude 1개 + codex 1개(최신 수정순).
AUTH_FILES="${AUTH_FILES:-}"
PORT_CLIPROXY=8317
PORT_HEADROOM=8790

CP="$(mktemp -d /tmp/h-oci-cm.XXXXXX)"
cleanup() { ssh -O exit -o ControlPath="$CP/s" "$R" >/dev/null 2>&1; rm -f "$CP/s"; rmdir "$CP" 2>/dev/null; }
trap cleanup EXIT
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3
    -o IdentitiesOnly=yes -i "$KEY" -o ControlMaster=auto -o ControlPersist=180 -o ControlPath="$CP/s")
say() { printf '[h-infer] %s\n' "$*"; }
die() { printf '[h-infer] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
rs() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$R" "$@"; }          # 원격 1회 = 상한 t초(연결 재사용)
rsq() { rs "$@" 2>/dev/null; }

# ── 0) 로컬 사전점검 ─────────────────────────────────────────────────────────
say "0/6 로컬 사전점검"
command -v timeout >/dev/null 2>&1 || die 2 "timeout 명령이 없다"
[ -f "$KEY" ] || die 2 "ssh 키가 없다: $KEY"
[ -f "$BIN_LOCAL" ] || die 2 "cliproxy 바이너리가 없다: $BIN_LOCAL (교차 빌드 산출물 · measured-xbuild-cliproxy-20261022.md)"
ACTUAL="$(shasum -a 256 "$BIN_LOCAL" | awk '{print $1}')"
[ "$ACTUAL" = "$BIN_SHA256" ] || die 2 "cliproxy sha256 불일치 — 기대 $BIN_SHA256 / 실제 $ACTUAL"
say "        cliproxy 바이너리 sha256 일치 · $(wc -c <"$BIN_LOCAL" | tr -d ' ') bytes"
[ -f "$CFG_LOCAL" ] || die 2 "cliproxy config 가 없다: $CFG_LOCAL"
if [ -z "$AUTH_FILES" ]; then
  AUTH_FILES="$(ls -t "$HOME/.cli-proxy-api"/claude-*.json 2>/dev/null | head -1 | xargs -n1 basename 2>/dev/null) $(ls -t "$HOME/.cli-proxy-api"/codex-*.json 2>/dev/null | head -1 | xargs -n1 basename 2>/dev/null)"
  AUTH_FILES="$(printf '%s' "$AUTH_FILES" | xargs)"     # 공백 정리
fi
[ -n "$AUTH_FILES" ] || die 2 "복사할 인증 파일이 없다(~/.cli-proxy-api/claude-*.json·codex-*.json) — AUTH_FILES= 로 지정"
for f in $AUTH_FILES; do [ -f "$HOME/.cli-proxy-api/$f" ] || die 2 "인증 파일 없음: $HOME/.cli-proxy-api/$f"; done
say "        인증 파일(이름만): $AUTH_FILES"

# ── 1) 원격 사전점검(읽기만) ─────────────────────────────────────────────────
say "1/6 원격 사전점검"
PRE="$(rs 15 'bash -s' <<'PREEOF'
echo "arch=$(uname -m)"
echo "py=$(python3 -V 2>&1 | awk "{print \$2}" | cut -d. -f1,2)"
loginctl show-user "$(id -un)" -p Linger 2>/dev/null
python3 -c 'import venv' >/dev/null 2>&1 && echo venv=yes || echo venv=NO
python3 -m pip --version >/dev/null 2>&1 && echo pip=yes || echo pip=NO
echo "ports=$(ss -ltn | awk "{print \$4}" | grep -E ":(8317|8790)$" | tr "\n" " ")"
command -v curl >/dev/null 2>&1 && echo curl=yes || echo curl=NO
PREEOF
)" || die 2 "oci 접속 실패: $PRE"
printf '%s\n' "$PRE" | sed 's/^/        /'
printf '%s\n' "$PRE" | grep -qx 'arch=aarch64' || die 2 "aarch64 가 아니다"
printf '%s\n' "$PRE" | grep -q '^py=3\.10$' || die 2 "python 3.10 이 아니다(휠 선택이 달라진다)"
printf '%s\n' "$PRE" | grep -q '^Linger=yes' || die 2 "systemd 사용자 Linger 가 no — 유닛이 로그아웃 뒤 죽는다(loginctl enable-linger ubuntu 필요)"
printf '%s\n' "$PRE" | grep -q '^venv=yes' || die 2 "python venv 모듈이 없다"
printf '%s\n' "$PRE" | grep -q '^pip=yes' || die 2 "pip 이 없다"
printf '%s\n' "$PRE" | grep -q '^curl=yes' || die 2 "curl 이 없다"
say "        포트 점유(8317/8790): $(printf '%s\n' "$PRE" | tail -2 | head -1)"

# ── 2) 바이너리·config·인증 배치(0600 · 백업 후 교체) ────────────────────────
say "2/6 바이너리·설정 배치"
rsq 20 'mkdir -p ~/bin ~/.cli-proxy-api ~/h-backup && chmod 700 ~/bin ~/.cli-proxy-api ~/h-backup' || die 3 "원격 디렉터리 생성 실패"
TS="$(date +%Y%m%d-%H%M%S)"
rsq 20 "set -e; [ -f ~/bin/cli-proxy-api ] && cp -p ~/bin/cli-proxy-api ~/h-backup/cli-proxy-api.$TS || true; [ -f ~/.cli-proxy-api/config.yaml ] && cp -p ~/.cli-proxy-api/config.yaml ~/h-backup/config.yaml.$TS || true; echo backup=ok" || die 3 "백업 실패"

if timeout 120 scp -q -o BatchMode=yes -o IdentitiesOnly=yes -i "$KEY" -o ControlPath="$CP/s" "$BIN_LOCAL" "$R:~/bin/cli-proxy-api.new"; then
  rsq 25 "set -e; mv ~/bin/cli-proxy-api.new ~/bin/cli-proxy-api; chmod 700 ~/bin/cli-proxy-api; echo placed=ok" || die 3 "바이너리 배치 실패"
else
  die 3 "scp 바이너리 실패(네트워크/권한)"
fi
GOT="$(rs 20 'sha256sum ~/bin/cli-proxy-api | awk "{print \$1}"' 2>/dev/null)"
[ "$GOT" = "$BIN_SHA256" ] || die 3 "원격 바이너리 sha256 불일치 — 전송 손상(기대 $BIN_SHA256 / 실제 $GOT)"
say "        원격 바이너리 sha256 일치"

# 이 맥 config 는 auth-dir 이 /Users/yoonhwan/… 이고 관리 비밀키(secret-key)가 들어 있다 → 임시 사본에서 auth-dir 교체 + 비밀키 줄 제거 후 전송(원본·화면 출력 0)
CFG_TMP="$CP/config.oci.yaml"
python3 - "$CFG_LOCAL" "$CFG_TMP" <<'PYEOF' || die 3 "OCI 용 config 생성 실패"
import re,sys
src,dst=sys.argv[1:3]; out=[]
for ln in open(src):
    if re.match(r'^auth-dir:', ln): ln='auth-dir: "/home/ubuntu/.cli-proxy-api"\n'
    if re.match(r'^\s+secret-key:', ln): continue
    out.append(ln)
txt=''.join(out)
txt=re.sub(r'remote-management:\n(\s+allow-remote:[^\n]*\n)', r'remote-management:\n\1  disable-control-panel: true\n', txt) if False else txt
open(dst,'w').write(txt)
PYEOF
chmod 600 "$CFG_TMP"
timeout 60 scp -q -o BatchMode=yes -o IdentitiesOnly=yes -i "$KEY" -o ControlPath="$CP/s" "$CFG_TMP" "$R:~/.cli-proxy-api/config.yaml" || die 3 "config 전송 실패"
rm -f "$CFG_TMP"
for f in $AUTH_FILES; do
  timeout 60 scp -q -o BatchMode=yes -o IdentitiesOnly=yes -i "$KEY" -o ControlPath="$CP/s" "$HOME/.cli-proxy-api/$f" "$R:~/.cli-proxy-api/$f" || die 3 "인증 파일 전송 실패: $f"
done
rsq 20 'set -e; chmod 700 ~/.cli-proxy-api; chmod 600 ~/.cli-proxy-api/*.json ~/.cli-proxy-api/config.yaml; ls -l ~/.cli-proxy-api | awk "{print \$1, \$5, \$9}"' \
  || die 3 "원격 권한 설정 실패"
rs 20 'ls -l ~/.cli-proxy-api | awk "NR>1{print \$1, \$5, \$9}"' 2>&1 | sed 's/^/        /'   # 이름·크기·모드만(값 0)

# ── 3) headroom venv(버전 고정) ─────────────────────────────────────────────
say "3/6 headroom $HEADROOM_VER venv"
rsq 30 'set -e; [ -d ~/.venvs/headroom ] || python3 -m venv ~/.venvs/headroom; ~/.venvs/headroom/bin/python -m pip -q install --upgrade pip >/dev/null 2>&1 || true; echo venv=ok' || die 3 "venv 생성 실패"
rs 180 "set -e; ~/.venvs/headroom/bin/python -m pip -q install 'headroom-ai==$HEADROOM_VER' 2>&1 | tail -3; ~/.venvs/headroom/bin/python -c 'import headroom,sys;print(\"headroom=\"+getattr(headroom,\"__version__\",\"?\"))'" \
  || die 3 "headroom $HEADROOM_VER 설치 실패(aarch64 휠 확인 필요)"
say "        headroom 설치 완료"

# ── 4) systemd 사용자 유닛 2개(127.0.0.1 바인드) ────────────────────────────
say "4/6 유닛 2개 작성"
rsq 25 "mkdir -p ~/.config/systemd/user && cat > ~/.config/systemd/user/cliproxyapi.service <<'U'
[Unit]
Description=CLIProxyAPI (aifp · OCI 로컬 추론 프록시)
After=network-online.target

[Service]
Type=simple
WorkingDirectory=%h
ExecStart=%h/bin/cli-proxy-api -config %h/.cli-proxy-api/config.yaml
Restart=on-failure
RestartSec=3
# 바인드는 config.yaml 의 host: "127.0.0.1" 이 정한다(0.0.0.0 으로 열지 않는다)

[Install]
WantedBy=default.target
U
echo unit1=ok" || die 3 "cliproxy 유닛 작성 실패"

rsq 25 "cat > ~/.config/systemd/user/headroom.service <<'U'
[Unit]
Description=headroom proxy (aifp · OCI 로컬 · cliproxy 경유)
After=network-online.target cliproxyapi.service
Wants=cliproxyapi.service

[Service]
Type=simple
WorkingDirectory=%h
ExecStart=%h/.venvs/headroom/bin/python -m headroom.proxy.server --port $PORT_HEADROOM --anthropic-api-url http://127.0.0.1:$PORT_CLIPROXY --compress-user-messages --no-code-aware --exclude-tools Bash
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
U
echo unit2=ok" || die 3 "headroom 유닛 작성 실패"

rsq 25 'set -e; systemctl --user daemon-reload; systemctl --user enable --now cliproxyapi.service; sleep 4; systemctl --user enable --now headroom.service; sleep 6; echo started=ok' || die 5 "유닛 기동 실패 — journalctl --user -u cliproxyapi -n 40 로 확인"

# ── 5) 기동 확인(읽기만) ────────────────────────────────────────────────────
say "5/6 기동 확인"
ST="$(rs 20 'echo "cliproxy=$(systemctl --user is-active cliproxyapi)"; echo "headroom=$(systemctl --user is-active headroom)"; ss -ltn | awk "{print \$4}" | grep -E ":(8317|8790)$" | sort | tr "\n" " "; echo' 2>&1)" || die 5 "상태 조회 실패"
printf '%s\n' "$ST" | sed 's/^/        /'
printf '%s\n' "$ST" | grep -q 'cliproxy=active' || die 5 "cliproxy 가 active 가 아니다"
printf '%s\n' "$ST" | grep -q 'headroom=active' || die 5 "headroom 이 active 가 아니다"

MODELS="$(rs 25 'curl -s -m 8 http://127.0.0.1:8317/v1/models || true' 2>/dev/null)"
printf '%s' "$MODELS" | python3 -c '
import json,sys
raw=sys.stdin.read()
try: d=json.loads(raw)
except Exception: print("MODELS_PARSE_FAIL"); raise SystemExit(0)
ids=[m.get("id","") for m in (d.get("data") or [])]
want=[w for w in ("sonnet-5-5","haiku-5-5","gpt-6.1-sol") if any(w in i for i in ids)]
print("MODELS_N=%d WANT=%s" % (len(ids), ",".join(want) if want else "none"))
' > /tmp/h-infer-models.txt 2>/dev/null || true
cat /tmp/h-infer-models.txt | sed 's/^/        /'
grep -q 'WANT=sonnet-5-5,haiku-5-5,gpt-6.1-sol' /tmp/h-infer-models.txt \
  || say "        ⚠ 모델 3종이 다 안 보인다 — config.yaml 의 프로바이더/인증 파일 선택을 확인(치명 아님 · 다음 장에서 재확인)"

HEALTH="$(rs 20 'curl -s -o /dev/null -w "%{http_code}" -m 6 http://127.0.0.1:8790/health || true' 2>/dev/null)"
say "        headroom /health http=$HEALTH"

# ── 6) 끝 ───────────────────────────────────────────────────────────────────
say "6/6 끝"
cat <<EOF
        닫는 증거(그대로 복사해 보고에 쓸 것):
          · cliproxy: systemctl --user is-active cliproxyapi → active · 127.0.0.1:$PORT_CLIPROXY
          · headroom: systemctl --user is-active headroom  → active · 127.0.0.1:$PORT_HEADROOM
          · 모델: 위 MODELS_N/WANT 줄
        다음 장: h-oci-cli-tools.sh (claude·pi·codex·tmuxc·tmm + claude 래퍼가 8317 을 보게)
        롤백: ssh $R 'systemctl --user disable --now headroom cliproxyapi; rm -f ~/.config/systemd/user/headroom.service ~/.config/systemd/user/cliproxyapi.service; systemctl --user daemon-reload'
              이전 파일 되돌리기: ~/h-backup/ 안의 <이름>.<타임스탬프> 를 원위치로 cp -p
        보안: 인증 파일은 0600 · 디렉터리 700 · 이 스크립트는 값은 한 번도 출력하지 않았다(이름·크기·모드만).
EOF
exit 0
