#!/usr/bin/env bash
# h-iap-tunnel-a1.sh — h-A1: mini·OCI 용 «터널 전용 서비스 계정» 2개 + IAP 조건부 권한 + 새 SA 격리 시험 → 통과하면 호스트에 SA 키 배치.
#   (2026-10-22 · aifp-multihost-master-claude#2 · 발주 #3189/#3199 · 설계 DESIGN-host-iap-tunnels-20261022.md · DA r1·r2 HOLD 반영)
#   실행은 오빠가 `! bash /tmp/h<N>` 로만. 먼저 계획만 보려면 `DRY=1 bash …` (쓰기 0 · 사전점검만).
#
# ★A1 범위 = LLM·STT·TTS 터널 3개뿐 — ssh 0 · VM 메타데이터 변경 0 · DB 경로는 A2(별도)★
#   ① SA 2개  byz-mini-tunnel · byz-oci-tunnel  (프로젝트 역할은 ② 하나뿐 — byz-local-dev 의 10개 역할 복사 금지)
#   ② 프로젝트 IAM: roles/iap.tunnelResourceAccessor «조건부» — 조건 = 대상 VM 내부 IP + 포트
#        llm-dev 10.0.0.8:8000 · stt-tts-dev 10.0.0.9:8000,8100            (IAP 는 resource.name 조건 미지원 · DA r1)
#        ※ IP 조건이라 VM 내부 IP 가 바뀌면 권한이 어긋난다 — 사전점검이 실제 IP 와 대조한다
#   ③ SA 키 JSON 2개 발급(화면 0 · 0600 임시 파일)
#   ④ ★시험 먼저★ — 전용 CLOUDSDK_CONFIG + 새 SA 만으로(기존 고권한 계정·떠 있는 터널로 거짓 통과 금지 · DA r1 ⑦·r2 ④):
#        SA 마다 T1 llm-dev:8000 · T2 stt-tts-dev:8100 · T3 stt-tts-dev:8000  — 터널 + HTTP 응답(도달 증거 · 코드 표기)
#        SA 마다 T4 허용 밖(llm-dev:22 · stt-tts-dev:22) — IAP 의 «명시적 거부(4033/not authorized)» 가 로그에 있어야 통과
#        시험 포트는 시작 전에 «비어 있음» 확인 · 리스너 소유 프로세스가 내가 띄운 것인지 확인(DA r2 ④)
#   ⑤ 시험 전부 통과해야만 호스트(mini·oci)에 ~/.config/byz-tunnel/sa.json(0600) 배치 → 실패면 호스트는 건드리지 않는다(DA r2 ⑦)
#
# 시험 포트는 전부 490xx — 운영 터널(38309·8001·18703·18712)과 겹치지 않는다. 내가 띄운 프로세스만 pid 파일로 정리한다.
# rc: 0 성공 · 2 사전점검 실패 · 3 GCP 쓰기 실패 · 4 호스트 배치 실패 · 5 시험 실패(SA·바인딩·키는 남김 — 호스트는 미변경)
#
# ★롤백은 «삭제» 라서 사람(HIL) 승인 건 — 이 스크립트가 지우지 않는다. 필요할 때 오빠 승인 뒤(<KEY_ID> 는 아래 «키 장부» 출력):
#   gcloud iam service-accounts keys delete <KEY_ID> --iam-account=byz-<host>-tunnel@PROJECT.iam.gserviceaccount.com
#   gcloud projects remove-iam-policy-binding PROJECT --member=serviceAccount:byz-<host>-tunnel@… --role=roles/iap.tunnelResourceAccessor --condition=title=tunnel-byz-<host>-tunnel-only,…
#   gcloud iam service-accounts delete byz-<host>-tunnel@…
#   호스트: rm ~/.config/byz-tunnel/sa.json
set -uo pipefail

P="${P:-byz-agents-484214}"
Z="${Z:-asia-northeast3-a}"
LLM=byz-agents-gce-llm-dev;      LLM_IP="${LLM_IP:-10.0.0.8}"
STT=byz-agents-gce-stt-tts-dev;  STT_IP="${STT_IP:-10.0.0.9}"
SAS=(byz-mini-tunnel byz-oci-tunnel)
SA_DOM="$P.iam.gserviceaccount.com"
DRY="${DRY:-0}"
ADMIN="${ADMIN:-}"                       # 비우면 gcloud 활성 계정
OCI_KEY="${OCI_KEY:-$HOME/.ssh/oci_chuncheon}"

say() { printf '[h-A1] %s\n' "$*"; }
die() { printf '[h-A1] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
G() { if [ -n "$ADMIN" ]; then timeout 60 gcloud --account="$ADMIN" --project="$P" "$@"; else timeout 60 gcloud --project="$P" "$@"; fi; }

TMP="$(mktemp -d /tmp/h-A1.XXXXXX)"; chmod 700 "$TMP"
PIDS="$TMP/pids"; : > "$PIDS"
cleanup() {
  while read -r pid; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done < "$PIDS"
  rm -f "$TMP"/sa-*.json 2>/dev/null; rm -rf "$TMP"/cfg-* 2>/dev/null
  say "임시 폴더 $TMP (키 파일은 지움 — 남은 건 로그뿐, 비밀 0)"
}
trap cleanup EXIT

# ── 0) 사전점검 (읽기 전용) ─────────────────────────────────────────────────
say "0/5 사전점검 (DRY=$DRY)"
command -v gcloud >/dev/null || die 2 "gcloud 없음"
say "        관리 계정: ${ADMIN:-$(gcloud config get-value account 2>/dev/null)}"
PERMS="$(ADMIN="$ADMIN" python3 - "$P" <<'PY'
import json, os, subprocess, sys, urllib.request
p = sys.argv[1]
cmd = ["gcloud"] + (["--account=" + os.environ["ADMIN"]] if os.environ.get("ADMIN") else []) + ["auth", "print-access-token"]
tok = subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout.strip()
if not tok: sys.exit("토큰 발급 실패")
perms = ["iam.serviceAccounts.create", "iam.serviceAccountKeys.create", "resourcemanager.projects.setIamPolicy"]
req = urllib.request.Request(f"https://cloudresourcemanager.googleapis.com/v1/projects/{p}:testIamPermissions",
    data=json.dumps({"permissions": perms}).encode(), headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
got = set(json.load(urllib.request.urlopen(req, timeout=20)).get("permissions", []))
print(" ".join(sorted(set(perms) - got)))
PY
)" || die 2 "권한 점검 실패"
[ -z "$PERMS" ] || die 2 "관리 계정에 없는 권한: $PERMS  (ADMIN=<계정> 으로 다시)"
say "        관리 권한 3종 확인"
REAL_LLM="$(G compute instances describe "$LLM" --zone="$Z" --format='value(networkInterfaces[0].networkIP)' 2>/dev/null)"
REAL_STT="$(G compute instances describe "$STT" --zone="$Z" --format='value(networkInterfaces[0].networkIP)' 2>/dev/null)"
[ "$REAL_LLM" = "$LLM_IP" ] && [ "$REAL_STT" = "$STT_IP" ] || die 2 "VM 내부 IP 불일치(실제 llm=$REAL_LLM stt=$REAL_STT, 조건 $LLM_IP/$STT_IP) — LLM_IP·STT_IP 로 맞춰 다시"
say "        VM 내부 IP 일치: llm-dev=$LLM_IP stt-tts-dev=$STT_IP"
for sa in "${SAS[@]}"; do
  if G iam service-accounts describe "$sa@$SA_DOM" >/dev/null 2>&1; then say "        SA 이미 있음: $sa (재사용 · 키는 새로 발급)"; else say "        SA 없음: $sa (생성 예정)"; fi
done
for pt in 49011 49012 49013 49014 49015 49016 49017 49018 49019 49020 49021 49022; do
  lsof -ti ":$pt" -sTCP:LISTEN >/dev/null 2>&1 && die 2 "시험 포트 $pt 가 이미 사용 중 — 거짓 통과 방지를 위해 중단"
done
say "        시험 포트 490(11~22) 비어 있음"
ssh -o BatchMode=yes -o ConnectTimeout=6 mini 'echo mini=ok' >/dev/null 2>&1 || die 2 "ssh mini 실패"
ssh -o BatchMode=yes -o ConnectTimeout=6 -o IdentitiesOnly=yes -i "$OCI_KEY" oci 'echo oci=ok' >/dev/null 2>&1 || die 2 "ssh oci 실패"
say "        mini·oci ssh 확인"
IAP_COND="expression=(destination.ip == \"$LLM_IP\" && destination.port == 8000) || (destination.ip == \"$STT_IP\" && (destination.port == 8000 || destination.port == 8100))"
if [ "$DRY" = 1 ]; then
  say "DRY — 아래는 «하려던 일» 이다(쓰기 0):"
  say "  SA: ${SAS[*]} @$SA_DOM"
  say "  IAP 바인딩 조건: $IAP_COND"
  say "  시험: SA 마다 T1~T3 도달 + T4 명시적 거부 → 통과 시에만 호스트 ~/.config/byz-tunnel/sa.json 배치"
  exit 0
fi

# ── 1) SA 생성 ──────────────────────────────────────────────────────────────
say "1/5 SA 생성"
for sa in "${SAS[@]}"; do
  G iam service-accounts describe "$sa@$SA_DOM" >/dev/null 2>&1 || \
    G iam service-accounts create "$sa" --display-name="IAP tunnel only ($sa)" >/dev/null || die 3 "SA 생성 실패: $sa"
done
sleep 5

# ── 2) IAP 바인딩(조건부) ───────────────────────────────────────────────────
say "2/5 IAP 터널 권한(조건부) 부여"
for sa in "${SAS[@]}"; do
  G projects add-iam-policy-binding "$P" --member="serviceAccount:$sa@$SA_DOM" --role=roles/iap.tunnelResourceAccessor \
    --condition="$IAP_COND,title=tunnel-$sa-only,description=llm-dev 8000 and stt-tts-dev 8000 8100 only" >/dev/null \
    || die 3 "IAP 바인딩 실패: $sa (앞서 만든 SA·바인딩은 남음 — 같은 줄 재실행하면 이어감)"
done

# ── 3) SA 키 발급 (이 맥 0600 임시) ──────────────────────────────────────────
say "3/5 SA 키 발급(화면 출력 0)"
( umask 077
  for sa in "${SAS[@]}"; do
    G iam service-accounts keys create "$TMP/sa-$sa.json" --iam-account="$sa@$SA_DOM" >/dev/null 2>&1 || exit 1
  done ) || die 3 "키 발급 실패"
for sa in "${SAS[@]}"; do
  kid="$(python3 -c "import json;print(json.load(open('$TMP/sa-$sa.json'))['private_key_id'])")"
  say "        키 장부: SA=$sa key_id=$kid 발급=$(date +%Y-%m-%dT%H:%M) 교체권장=90일"
done

# ── 4) 새 SA 시험 (전용 CLOUDSDK_CONFIG) ─────────────────────────────────────
say "4/5 새 SA 시험 — SA 마다 전용 설정 폴더 · 시험 포트 490xx"
FAIL=0; PORT=49010
own_listener() {  # own_listener <port> <pid> → 리스너가 내가 띄운 pid(또는 그 자손)인가
  local pt="$1" root="$2" lp; lp="$(lsof -ti ":$pt" -sTCP:LISTEN 2>/dev/null | head -1)"; [ -n "$lp" ] || return 1
  while [ -n "$lp" ] && [ "$lp" != 1 ]; do [ "$lp" = "$root" ] && return 0; lp="$(ps -o ppid= -p "$lp" 2>/dev/null | tr -d ' ')"; done; return 1
}
tun_open() {  # tun_open <sa> <inst> <rport> → 전역 LP(로컬 포트)·TL(로그)·TPID. 리스너가 «내 프로세스» 일 때만 0
  local sa="$1" inst="$2" rp="$3"; PORT=$((PORT+1)); LP=$PORT; TL="$TMP/tun-$LP.log"
  CLOUDSDK_CONFIG="$TMP/cfg-$sa" timeout 70 gcloud --project="$P" --account="$sa@$SA_DOM" compute start-iap-tunnel "$inst" "$rp" \
    --local-host-port="127.0.0.1:$LP" --zone="$Z" >"$TL" 2>&1 &
  TPID=$!; echo "$TPID" >> "$PIDS"
  for _ in 1 2 3 4 5 6 7 8; do sleep 1; own_listener "$LP" "$TPID" && return 0; done
  return 1
}
http_code() { curl -s -m 7 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null; }
for sa in "${SAS[@]}"; do
  mkdir -p "$TMP/cfg-$sa"
  CLOUDSDK_CONFIG="$TMP/cfg-$sa" timeout 60 gcloud auth activate-service-account "$sa@$SA_DOM" --key-file="$TMP/sa-$sa.json" >/dev/null 2>&1 || die 5 "SA 활성화 실패: $sa"
  for spec in "T1 llm-dev:8000|$LLM|8000" "T2 stt-tts-dev:8100|$STT|8100" "T3 stt-tts-dev:8000|$STT|8000"; do
    IFS='|' read -r name inst rp <<<"$spec"
    ok=0
    for try in 1 2 3; do   # IAM 전파 지연: 최대 3회(20초 간격)
      if tun_open "$sa" "$inst" "$rp"; then
        c="$(http_code "http://127.0.0.1:$LP/health")"; [ "$c" = 000 ] && c="$(http_code "http://127.0.0.1:$LP/")"
        if printf '%s' "$c" | grep -q -E '^[1-5][0-9][0-9]$'; then say "        $sa $name ✅ 내 터널 LISTEN · HTTP $c (도달 증거 — health 판정 아님)"; ok=1; break; fi
        say "        $sa $name ⚠️ 터널은 열렸으나 HTTP 응답 없음(시도 $try): $(tail -1 "$TL" | cut -c1-120)"
      else
        say "        $sa $name ⚠️ 터널 안 열림(시도 $try): $(tail -2 "$TL" | tr '\n' ' ' | cut -c1-200)"
      fi
      kill "$TPID" 2>/dev/null; [ "$try" -lt 3 ] && sleep 20
    done
    [ "$ok" = 1 ] || { say "        $sa $name ❌ 3회 실패"; FAIL=1; }
  done
  for spec in "T4a llm-dev:22|$LLM|22" "T4b stt-tts-dev:22|$STT|22"; do
    IFS='|' read -r name inst rp <<<"$spec"
    if tun_open "$sa" "$inst" "$rp"; then
      python3 -c "import socket;s=socket.create_connection(('127.0.0.1',$LP),3);s.settimeout(3)
try: s.recv(8)
except Exception: pass" 2>/dev/null; sleep 3
    fi
    if grep -q -i -E '4033|not authorized|permission.*denied|PERMISSION_DENIED' "$TL" 2>/dev/null; then
      say "        $sa $name ✅ IAP 명시적 거부: $(grep -i -E '4033|not authorized|denied' "$TL" | head -1 | cut -c1-140)"
    else
      say "        $sa $name ❌ 거부 증거 없음(권한이 설계보다 넓거나 다른 이유로 실패) — 로그: $(tail -1 "$TL" | cut -c1-140)"; FAIL=1
    fi
    kill "$TPID" 2>/dev/null
  done
done
if [ "$FAIL" != 0 ]; then
  say "시험 실패 rc=5 — SA·바인딩·키는 남김(호스트는 건드리지 않음). 로그 $TMP/tun-*.log. 같은 줄 재실행하면 이어감"; exit 5
fi

# ── 5) 호스트 배치 (시험 통과 후에만 · ssh 표준입력 → 0600) ────────────────────
say "5/5 호스트에 SA 키 배치 (mini ← byz-mini-tunnel · oci ← byz-oci-tunnel)"
deploy() {  # deploy <ssh-target> <sa> [ssh opts...]
  local tgt="$1" sa="$2"; shift 2
  local -a O=(-o BatchMode=yes -o ConnectTimeout=6 "$@")
  ssh "${O[@]}" "$tgt" 'umask 077; mkdir -p ~/.config/byz-tunnel; chmod 700 ~/.config/byz-tunnel' || return 1
  ssh "${O[@]}" "$tgt" 'umask 077; cat > ~/.config/byz-tunnel/sa.json.tmp && mv ~/.config/byz-tunnel/sa.json.tmp ~/.config/byz-tunnel/sa.json && chmod 600 ~/.config/byz-tunnel/sa.json' < "$TMP/sa-$sa.json" || { ssh "${O[@]}" "$tgt" 'rm -f ~/.config/byz-tunnel/sa.json.tmp'; return 1; }
  ssh "${O[@]}" "$tgt" 'ls -l ~/.config/byz-tunnel | awk "NR>1{print \$1, \$9}"' | sed 's/^/        /'
}
deploy mini byz-mini-tunnel || die 4 "mini 배치 실패(키는 GCP 에 발급됨 — 키 장부 참조)"
deploy oci byz-oci-tunnel -o IdentitiesOnly=yes -i "$OCI_KEY" || die 4 "oci 배치 실패(mini 는 배치됨 · 키 장부 참조)"
say "완료 rc=0 — 시험 통과 + 호스트 배치. 다음: h-B(mini)·h-C(OCI) 에서 터널 상주(launchd/systemd --user)"
exit 0
