#!/usr/bin/env bash
# h-iap-tunnel-sa.sh — h-A: mini·OCI 용 «터널 전용 서비스 계정» 2개 + IAP 권한(조건부) + DB ssh 전용 키 + 호스트 배치 + 새 SA 시험.
#   (2026-10-22 · aifp-multihost-master-claude#2 · 발주 #3189 · 설계 DESIGN-host-iap-tunnels-20261022.md · DA r1 HOLD 반영)
#   실행은 오빠가 `! bash /tmp/h<N>` 로만. 먼저 계획만 보려면 `DRY=1 bash …` (쓰기 0 · 사전점검만).
#
# 하는 일 (GCP 쓰기는 4곳뿐):
#   ① SA 2개 생성  byz-mini-tunnel · byz-oci-tunnel  (프로젝트 역할 0 — 아래 ②만)
#   ② 프로젝트 IAM: roles/iap.tunnelResourceAccessor «조건부» — 조건 = 대상 VM 내부 IP + 포트
#        llm-dev 10.0.0.8:8000 · stt-tts-dev 10.0.0.9:22,8000,8100   (IAP 는 resource.name 조건 미지원 · DA r1)
#   ③ SA 키 JSON 2개 발급(화면 0 · 0600 임시 파일)
#   ④ stt-tts-dev «인스턴스» 메타데이터 ssh-keys 에 전용 키 2줄 «보존 추가»(덮어쓰기 0 · 프로젝트 ssh-keys·block-project 불변)
# 그 뒤: 키 2종(SA JSON · DB ssh 개인키)을 ssh 표준입력으로 각 호스트 ~/.config/byz-tunnel/ (0700/0600) 에 배치하고
#        이 맥 임시본 삭제. ★시험은 전용 CLOUDSDK_CONFIG + 새 SA 만으로★(기존 고권한 계정·떠 있는 터널로 거짓 통과 금지 · DA r1 ⑦):
#        T1 llm-dev:8000  T2 stt-tts-dev:8100  T3 stt-tts-dev:8000  — 새 SA 터널 + HTTP 응답
#        T4 허용 밖(llm-dev:22) — «거부»되어야 통과(조건이 먹는다는 증거)
#        T5 DB: ssh ProxyCommand(start-iap-tunnel :22) -L → 10.2.0.10:5432 TCP 연결
#        T6 정보 수집(통과/실패 아님): 전용 ssh 사용자의 sudo 가능 여부 · VM 안 8000 리스너 바인딩(8001 교체 판단용)
#
# 시험 포트는 전부 49xxx — 운영 터널(38309·8001·18703·18712)과 겹치지 않는다. 내가 띄운 프로세스만 pid 파일로 정리한다.
# rc: 0 성공 · 2 사전점검 실패 · 3 GCP 쓰기 실패 · 4 호스트 배치 실패 · 5 시험 실패(자원은 남김 — 아래 롤백 안내)
#
# ★롤백은 «삭제» 라서 사람(HIL) 승인 건 — 이 스크립트가 지우지 않는다. 필요할 때 오빠 승인 뒤:
#   gcloud iam service-accounts keys delete <KEY_ID> --iam-account=<SA>            (키 폐기 · 호스트별)
#   gcloud projects remove-iam-policy-binding PROJECT --member=serviceAccount:<SA> --role=roles/iap.tunnelResourceAccessor --condition=…
#   gcloud iam service-accounts delete <SA>
#   gcloud compute instances add-metadata stt-tts-dev --metadata-from-file ssh-keys=<이 스크립트가 남긴 ssh-keys.before 백업>
set -uo pipefail

P="${P:-byz-agents-484214}"
Z="${Z:-asia-northeast3-a}"
LLM=byz-agents-gce-llm-dev;      LLM_IP="${LLM_IP:-10.0.0.8}"
STT=byz-agents-gce-stt-tts-dev;  STT_IP="${STT_IP:-10.0.0.9}"
DB_HOST_PORT="${DB_HOST_PORT:-10.2.0.10:5432}"
SA_MINI=byz-mini-tunnel; SA_OCI=byz-oci-tunnel
SA_DOM="$P.iam.gserviceaccount.com"
DRY="${DRY:-0}"
ADMIN="${ADMIN:-}"                       # 비우면 gcloud 활성 계정
OCI_KEY="${OCI_KEY:-$HOME/.ssh/oci_chuncheon}"
HOSTPATH='export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH";'

say() { printf '[h-A] %s\n' "$*"; }
die() { printf '[h-A] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
G() { if [ -n "$ADMIN" ]; then timeout 60 gcloud --account="$ADMIN" --project="$P" "$@"; else timeout 60 gcloud --project="$P" "$@"; fi; }

TMP="$(mktemp -d /tmp/h-A.XXXXXX)"; chmod 700 "$TMP"
PIDS="$TMP/pids"; : > "$PIDS"
cleanup() {
  while read -r pid; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done < "$PIDS"
  # 키 임시본 삭제(ssh-keys.before 백업만 남긴다 — 롤백용, 비밀 아님)
  rm -f "$TMP"/sa-*.json "$TMP"/db_* "$TMP"/db_*.pub 2>/dev/null
  rm -rf "$TMP/cfg" 2>/dev/null
  say "임시 폴더 $TMP (남은 것: ssh-keys.before · 로그 — 비밀 0)"
}
trap cleanup EXIT

# ── 0) 사전점검 (읽기 전용) ─────────────────────────────────────────────────
say "0/6 사전점검 (DRY=$DRY)"
command -v gcloud >/dev/null || die 2 "gcloud 없음"
ACTIVE="$(gcloud config get-value account 2>/dev/null)"; say "        관리 계정: ${ADMIN:-$ACTIVE}"
need_perm='iam.serviceAccounts.create iam.serviceAccountKeys.create resourcemanager.projects.setIamPolicy compute.instances.setMetadata'
if [ -n "$ADMIN" ]; then TOK="$(gcloud --account="$ADMIN" auth print-access-token 2>/dev/null)"; else TOK="$(gcloud auth print-access-token 2>/dev/null)"; fi
[ -n "$TOK" ] || die 2 "관리 계정 토큰 발급 실패"
PERMS="$(TOK="$TOK" python3 - "$P" $need_perm <<'PY'
import json, os, sys, urllib.request
p, perms = sys.argv[1], sys.argv[2:]
req = urllib.request.Request(f"https://cloudresourcemanager.googleapis.com/v1/projects/{p}:testIamPermissions",
    data=json.dumps({"permissions": perms}).encode(), headers={"Authorization": "Bearer " + os.environ["TOK"], "Content-Type": "application/json"})
got = set(json.load(urllib.request.urlopen(req, timeout=20)).get("permissions", []))
print(" ".join(sorted(set(perms) - got)))
PY
)" || die 2 "권한 점검 호출 실패"
[ -z "$PERMS" ] || die 2 "관리 계정에 없는 권한: $PERMS  (ADMIN=<계정> 으로 다시)"
say "        관리 권한 4종 확인"
for sa in "$SA_MINI" "$SA_OCI"; do
  if G iam service-accounts describe "$sa@$SA_DOM" >/dev/null 2>&1; then say "        SA 이미 있음: $sa (재사용)"; else say "        SA 없음: $sa (생성 예정)"; fi
done
CUR_KEYS="$(G compute instances describe "$STT" --zone="$Z" --format=json | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(next((i.get('value','') for i in d['metadata'].get('items',[]) if i['key']=='ssh-keys'),''))")" || die 2 "인스턴스 메타 읽기 실패"
printf '%s' "$CUR_KEYS" > "$TMP/ssh-keys.before"
say "        stt-tts-dev 인스턴스 ssh-keys 현재 줄 수: $(printf '%s' "$CUR_KEYS" | grep -c . || true) (백업 $TMP/ssh-keys.before)"
ssh -o BatchMode=yes -o ConnectTimeout=6 mini 'echo mini=ok' >/dev/null 2>&1 || die 2 "ssh mini 실패"
ssh -o BatchMode=yes -o ConnectTimeout=6 -o IdentitiesOnly=yes -i "$OCI_KEY" oci 'echo oci=ok' >/dev/null 2>&1 || die 2 "ssh oci 실패"
say "        mini·oci ssh 확인"
IAP_COND="expression=(destination.ip == \"$LLM_IP\" && destination.port == 8000) || (destination.ip == \"$STT_IP\" && (destination.port == 22 || destination.port == 8000 || destination.port == 8100))"
if [ "$DRY" = 1 ]; then
  say "DRY — 아래는 «하려던 일» 이다(쓰기 0):"
  say "  SA: $SA_MINI@ · $SA_OCI@$SA_DOM"
  say "  IAP 바인딩 조건: $IAP_COND"
  say "  인스턴스 ssh-keys 에 보존 추가: tunmini · tunoci (ed25519 전용 키)"
  say "  호스트 배치: mini·oci ~/.config/byz-tunnel/{sa.json,db_ed25519}"
  exit 0
fi

# ── 1) SA 생성 ──────────────────────────────────────────────────────────────
say "1/6 SA 생성"
for sa in "$SA_MINI" "$SA_OCI"; do
  G iam service-accounts describe "$sa@$SA_DOM" >/dev/null 2>&1 || \
    G iam service-accounts create "$sa" --display-name="IAP tunnel only ($sa)" >/dev/null || die 3 "SA 생성 실패: $sa"
done
sleep 5   # IAM 전파

# ── 2) IAP 바인딩(조건부) ───────────────────────────────────────────────────
say "2/6 IAP 터널 권한(조건부) 부여"
for sa in "$SA_MINI" "$SA_OCI"; do
  G projects add-iam-policy-binding "$P" --member="serviceAccount:$sa@$SA_DOM" --role=roles/iap.tunnelResourceAccessor \
    --condition="$IAP_COND,title=tunnel-$sa-only,description=llm-dev 8000 and stt-tts-dev 22 8000 8100 only" >/dev/null || die 3 "IAP 바인딩 실패: $sa"
done

# ── 3) SA 키 · DB ssh 키 생성 (이 맥 0600 임시) ──────────────────────────────
say "3/6 키 발급(화면 출력 0)"
( umask 077
  for h in mini oci; do
    sa="byz-$h-tunnel"
    G iam service-accounts keys create "$TMP/sa-$h.json" --iam-account="$sa@$SA_DOM" >/dev/null 2>&1 || exit 1
    ssh-keygen -q -t ed25519 -N '' -C "tun$h" -f "$TMP/db_$h" || exit 1
  done ) || die 3 "키 발급 실패"
for h in mini oci; do
  kid="$(python3 -c "import json;print(json.load(open('$TMP/sa-$h.json'))['private_key_id'])")"
  say "        키 장부: 호스트=$h SA=byz-$h-tunnel key_id=$kid 발급=$(date +%Y-%m-%dT%H:%M) 교체권장=90일"
done

# ── 4) 인스턴스 메타데이터 ssh-keys «보존 추가» ───────────────────────────────
say "4/6 stt-tts-dev 인스턴스 ssh-keys 에 전용 키 2줄 보존 추가"
{ printf '%s' "$CUR_KEYS" | sed '/^$/d'
  for h in mini oci; do
    grep -q "^tun$h:" "$TMP/ssh-keys.before" && continue
    printf 'tun%s:%s\n' "$h" "$(cat "$TMP/db_$h.pub")"
  done; } > "$TMP/ssh-keys.after"
G compute instances add-metadata "$STT" --zone="$Z" --metadata-from-file="ssh-keys=$TMP/ssh-keys.after" >/dev/null || die 3 "메타데이터 추가 실패(백업: $TMP/ssh-keys.before)"
say "        줄 수 $(grep -c . "$TMP/ssh-keys.before" || true) → $(grep -c . "$TMP/ssh-keys.after")"

# ── 5) 호스트 배치 (ssh 표준입력 → 0600) ─────────────────────────────────────
say "5/6 호스트에 키 배치"
deploy() {  # deploy <ssh-target> <h> [ssh opts...]
  local tgt="$1" h="$2"; shift 2
  local -a O=(-o BatchMode=yes -o ConnectTimeout=6 "$@")
  ssh "${O[@]}" "$tgt" 'umask 077; mkdir -p ~/.config/byz-tunnel; chmod 700 ~/.config/byz-tunnel' || return 1
  ssh "${O[@]}" "$tgt" 'umask 077; cat > ~/.config/byz-tunnel/sa.json.tmp && mv ~/.config/byz-tunnel/sa.json.tmp ~/.config/byz-tunnel/sa.json && chmod 600 ~/.config/byz-tunnel/sa.json' < "$TMP/sa-$h.json" || return 1
  ssh "${O[@]}" "$tgt" 'umask 077; cat > ~/.config/byz-tunnel/db_ed25519.tmp && mv ~/.config/byz-tunnel/db_ed25519.tmp ~/.config/byz-tunnel/db_ed25519 && chmod 600 ~/.config/byz-tunnel/db_ed25519' < "$TMP/db_$h" || return 1
  ssh "${O[@]}" "$tgt" 'ls -l ~/.config/byz-tunnel | awk "NR>1{print \$1, \$9}"' | sed 's/^/        /'
}
deploy mini mini || die 4 "mini 배치 실패(키는 GCP 에 이미 발급됨 — 키 장부 참조)"
deploy oci oci -o IdentitiesOnly=yes -i "$OCI_KEY" || die 4 "oci 배치 실패(키는 GCP 에 이미 발급됨 — 키 장부 참조)"

# ── 6) 새 SA 시험 (전용 CLOUDSDK_CONFIG · 시험 포트 49xxx) ────────────────────
say "6/6 새 SA 시험 (mini 용 SA 로)"
export CLOUDSDK_CONFIG="$TMP/cfg"; mkdir -p "$CLOUDSDK_CONFIG"
timeout 60 gcloud auth activate-service-account "$SA_MINI@$SA_DOM" --key-file="$TMP/sa-mini.json" >/dev/null 2>&1 || die 5 "SA 활성화 실패"
GN() { timeout 70 gcloud --project="$P" --account="$SA_MINI@$SA_DOM" "$@"; }
FAIL=0
tun() {  # tun <inst> <remote-port> <local-port> → 0 이면 로컬 포트 LISTEN
  GN compute start-iap-tunnel "$1" "$2" --local-host-port="127.0.0.1:$3" --zone="$Z" >"$TMP/tun-$3.log" 2>&1 &
  echo $! >> "$PIDS"
  for _ in 1 2 3 4 5 6 7 8 9 10; do sleep 1; python3 -c "import socket;socket.create_connection(('127.0.0.1',$3),2).close()" 2>/dev/null && return 0; done
  return 1
}
http_code() { curl -s -m 7 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null; }
t_http() {  # t_http <이름> <inst> <rport> <lport> <path>
  if tun "$2" "$3" "$4"; then
    c="$(http_code "http://127.0.0.1:$4$5")"
    if [ "$c" != 000 ] && [ -n "$c" ]; then say "        $1 ✅ 터널 LISTEN · HTTP $c"; else say "        $1 ❌ 터널은 열렸지만 HTTP 응답 없음(000)"; FAIL=1; fi
  else say "        $1 ❌ 터널 안 열림: $(tail -2 "$TMP/tun-$4.log" | tr '\n' ' ')"; FAIL=1; fi
}
t_http "T1 llm-dev:8000    " "$LLM" 8000 49001 /health
t_http "T2 stt-tts-dev:8100" "$STT" 8100 49002 /health
t_http "T3 stt-tts-dev:8000" "$STT" 8000 49003 /health
# T4 거부 확인
if tun "$LLM" 22 49004; then
  if timeout 8 bash -c 'exec 3<>/dev/tcp/127.0.0.1/49004; printf "SSH-2.0-t\r\n" >&3; head -c 4 <&3' 2>/dev/null | grep -q SSH; then
    say "        T4 ❌ llm-dev:22 가 열렸다 — 조건이 먹지 않는다(권한이 설계보다 넓음)"; FAIL=1
  else say "        T4 ✅ llm-dev:22 는 연결해도 SSH 응답 없음(거부)"; fi
else say "        T4 ✅ llm-dev:22 터널이 열리지 않음(거부) — $(tail -1 "$TMP/tun-49004.log" | cut -c1-100)"; fi
# T5 DB — ProxyCommand + 전용 키
PX="gcloud --project=$P --account=$SA_MINI@$SA_DOM compute start-iap-tunnel $STT 22 --listen-on-stdin --zone=$Z"
SSHT=(ssh -i "$TMP/db_mini" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$TMP/kh"
      -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ConnectTimeout=30 -o "ProxyCommand=$PX")
sleep 20   # 메타데이터 키 전파(게스트 에이전트)
"${SSHT[@]}" -N -L "127.0.0.1:49005:$DB_HOST_PORT" tunmini@"$STT" >"$TMP/ssh-db.log" 2>&1 &
echo $! >> "$PIDS"
ok=0; for _ in $(seq 1 20); do sleep 1; python3 -c "import socket;socket.create_connection(('127.0.0.1',49005),2).close()" 2>/dev/null && { ok=1; break; }; done
if [ "$ok" = 1 ]; then
  if timeout 8 python3 -c "
import socket;s=socket.create_connection(('127.0.0.1',49005),5);s.settimeout(5)
s.sendall(bytes([0,0,0,8,4,210,22,47]))   # PG SSLRequest
print(s.recv(1).decode(errors='replace'))" 2>/dev/null | grep -q -E '^[SN]$'; then say "        T5 ✅ DB: ssh(ProxyCommand) 포워딩 → $DB_HOST_PORT 에서 PostgreSQL 응답(SSLRequest S/N)"
  else say "        T5 ❌ 포워딩 포트는 열렸지만 PostgreSQL 응답 없음"; FAIL=1; fi
else say "        T5 ❌ DB ssh 안 붙음: $(tail -2 "$TMP/ssh-db.log" | tr '\n' ' ' | cut -c1-200)"; FAIL=1; fi
# T6 정보 수집
"${SSHT[@]}" tunmini@"$STT" 'echo "sudo_nopass=$(sudo -n true 2>/dev/null && echo YES || echo no)"; echo "groups=$(id -nG)"; echo "listen8000=$(ss -ltn 2>/dev/null | awk "\$4 ~ /:8000\$/{print \$4}" | tr "\n" " ")"' 2>&1 | sed 's/^/        T6 /' || true

if [ "$FAIL" = 0 ]; then say "완료 rc=0 — 시험 T1~T5 통과. T6 은 정보(위). 다음: h-B(mini)·h-C(OCI)"; exit 0; fi
say "일부 시험 실패 rc=5 — 자원(SA·바인딩·키·호스트 파일)은 남김. 롤백은 위 헤더(사람 승인). 로그 $TMP/tun-*.log"; exit 5
