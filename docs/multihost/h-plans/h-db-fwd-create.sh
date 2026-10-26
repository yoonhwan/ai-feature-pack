#!/usr/bin/env bash
# h-db-fwd-create.sh — h1: mini 의 DB 길 «열쇠 구멍» 포워더 VM 만들기 (카드 하나 · DESIGN-db-key-vm-cycle-20261026.md §3·§6)
#   (2026-10-26 · aifp-multihost-arch-claude#2 초안 r3 · 발주 #3313/#3315 · DA r3 APPROVE 조건부 + DA 델타 r1 HOLD 7건 + 델타 r2 APPROVE 조건 4건 반영 · 실행은 오빠 `! bash /tmp/h<N>` 로만)
#   먼저 계획만: `bash /tmp/h<N>` (DRY=1 기본 · gcloud 읽기 명령만 · ★클라우드 변경 0 · 로컬 증거 파일(백업·startup-script)은 만든다★). 실제 적용: `DRY=0 bash /tmp/h<N>`.
#
# 만드는 것 4개(순서대로 · 각 단계 실패 = 거기서 멈춤 · 뒤 단계 안 함):
#   ① 내부 고정 IP 예약  byz-db-fwd-ip  (서브넷 byz-agents-subnet-dev 10.0.0.0/24 · IAP 조건식의 destination.ip 가 흔들리지 않게)
#   ② VM byz-db-fwd  e2-micro · COS stable · 외부 IP 없음 · ★서비스 계정 없음★(자격 0) · 태그 db-fwd
#        --max-run-duration=14h --instance-termination-action=STOP --no-restart-on-failure   ← Google 이 14시간 뒤 스스로 끈다(열쇠)
#        포워딩 = startup-script 의 iptables DNAT(VM:38309 → 10.2.0.10:5432). ★컨테이너(socat) 대신 iptables 인 이유★:
#        읽기 전용 실측(10-26) — vpc-dev 에 Cloud NAT 0 · VM 외부 IP 0 → Docker Hub 에서 이미지를 받을 길이 없다.
#        iptables 는 COS 에 내장이라 받아올 것이 0 이고, 서비스 계정도 필요 없다. 매 부팅 startup-script 가 다시 적용(COS 루트 읽기 전용).
#        startup-script 는 실패 즉시 중단 · iptables -w 10(잠금 대기) · 끝에 규칙 4개+sysctl 재검사 뒤에만 applied(DA 델타 #2·r2 #4).
#   ③ 방화벽 1줄  byz-agents-allow-iap-db-fwd : 35.235.240.0/20(IAP) → tcp:38309 · 대상 태그 db-fwd 만 (VPC 방화벽은 DNAT 전 목적지 VM:38309 를 본다)
#   ④ byz-mini-tunnel 의 IAP 조건식 1줄 확장: 기존 식 || (destination.ip == "<①의 IP>" && destination.port == 38309)
#        방법 = 새 조건 바인딩 add → 옛 조건 바인딩 remove (둘 다 --condition-from-file · 옛 조건 원문은 파일로 백업)
#        완료 판정 = 새 조건식 «정확 일치» 바인딩 1개 ∧ 옛 조건식 0 ∧ 그 SA 의 IAP 바인딩 총 1개(DA 델타 r2 #2).
#   ⑤ 확인: describe 의 scheduling.maxRunDuration.seconds == 50400 ∧ instanceTerminationAction == STOP — ★아니면 도입 중단(rc 6)★
#        (게스트 shutdown 타이머로 대체하지 않는다 — «Google 이 강제» 전제 · DA r1 #12). 이 맥(developer.ts · 무조건 IAP 권한)에서
#        start-iap-tunnel byz-db-fwd 38309 → ★pg_isready 필수★(«포트 열림» 이 아니라 «Postgres 응답» · DA 델타 #3).
#   ⑥ 끝: 자원 원장 + 되돌림 명령 + ★14시간 격리 관찰 안내★(lastStartTimestamp+14h ±10분에 손 없이 TERMINATED 가 되는지 · 그동안 재기동 0)
#
# 조회 3상태(DA 델타 r2 #1): exists_* 는 0=있음 · 1=없음 · 2=조회 실패(권한·timeout). 사전점검에서 2 면 중단 · 쓰기 뒤에는 «성공 반환 즉시 MADE_* 기록».
# 쓰기 «미확정»(DA 델타 #4): 쓰기가 timeout(rc 124)이면 실패가 아니라 미확정 → 사전에 «없음» 이 확인된 자원이므로 조회로 «있음» 이면 생성으로 기록,
#   «없음/조회 실패» 면 UNSURE 에 올려 되돌림 안내에 남긴다. VM 생성은 --async 로 반환 객체를 파일에 보존(작업 이름 추출은 추정 · err-vm-op.json 확인).
# 외부 호출 상한(하드 룰 12 · DA 델타 #6): 읽기 1회 GT=11(7초 + gcloud 기동 고정비 4). 쓰기 3종(주소 예약·방화벽·IAM 바인딩)은 gcloud 가 단일 API 작업
#   완료까지 기다리는 호출이고 --async 가 없어(도움말 확인 · 주소 create·firewall create·add-iam-policy-binding 모두 0) 요청/완료를 못 가른다 → «쪼갤 수 없는
#   배치» 로 min(4 + 7×배수, 70): 주소 25(배수 3 · 지역 자원) · IAM 32(배수 4 · 정책 읽기-수정-쓰기) · 방화벽 39(배수 5 · 전파 대기). VM 생성만 --async 로 가른다.
#   IAP 터널 시험은 «호출» 이 아니라 백그라운드 리스너(상한 70) + 7초 회차.
# 마감 루프(DA 델타 r2 #3): poll() 은 회차마다 남은 시간을 재고, «sleep + 조회 상한» 이 남은 시간보다 크면 더 돌지 않는다 → 마감을 넘기는 회차 0.
#   (bash SECONDS 는 벽시계 기반이라 엄밀한 단조 시계는 아니다 — 수십 초 단위 마감에는 충분하다고 보고 쓴다.)
# 바꾸지 않는 것: 기존 VM 2대 · 기존 방화벽 · byz-local-dev 권한 · mini 의 무엇도(mini 쪽은 h2) · 이 맥 터널(오빠 결정 2)
# 비밀: 키·DSN 값 0 — 이 h 는 자격을 만들지도 읽지도 않는다. 출력은 이름·IP·rc·시각만.
# rc: 0 성공 · 2 사전점검 · 3 ① 실패 · 4 ② 실패 · 5 ③/④ 실패 · 6 만료 설정 미확인(도입 중단) · 7 ⑤ 도달 확인 실패(자원은 남김 · 되돌림 출력)
set -uo pipefail

P="${P:-byz-agents-484214}"
A="${A:-developer.ts@byourz.com}"                 # 고정(오빠 10-25) · 바꾸지 않는다
REGION="${REGION:-asia-northeast3}"; Z="${Z:-asia-northeast3-a}"
NET="${NET:-byz-agents-vpc-dev}"; SUBNET="${SUBNET:-byz-agents-subnet-dev}"
VM="${VM:-byz-db-fwd}"; ADDR="${ADDR:-byz-db-fwd-ip}"; FW="${FW:-byz-agents-allow-iap-db-fwd}"; TAG="${TAG:-db-fwd}"
FWD_PORT="${FWD_PORT:-38309}"; DB_IP="${DB_IP:-10.2.0.10}"; DB_PORT="${DB_PORT:-5432}"
MAXRUN="${MAXRUN:-14h}"; MAXRUN_SEC="${MAXRUN_SEC:-50400}"
IAP_RANGE="35.235.240.0/20"
MINI_SA="byz-mini-tunnel@$P.iam.gserviceaccount.com"
COND_TITLE="${COND_TITLE:-tunnel-byz-mini-tunnel-only}"
EXPECT_EXPR_PART='destination.ip == "10.0.0.9"'    # 기존 조건식에 반드시 있어야 하는 조각(엉뚱한 바인딩을 고치지 않게)
DRY="${DRY:-1}"
TEST_LPORT="${TEST_LPORT:-49309}"                # ⑤ 이 맥 시험용 로컬 포트(운영 38309·18703·18712 와 겹치지 않음)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BK="${BK:-$ROOT/docs/multihost/evidence/db-fwd-$(date +%Y%m%d-%H%M%S)}"   # 백업·원장(tracked 경로 · 비밀 0)

say() { printf '[h1-db-fwd] %s\n' "$*"; }
die() { printf '[h1-db-fwd] REJECT rc=%s %s\n' "$1" "$2" >&2; print_rollback; exit "$1"; }
GT="${GT:-11}"
G()  { timeout "$GT" gcloud --account="$A" --project="$P" --quiet "$@"; }
GL() { timeout "${1}" gcloud --account="$A" --project="$P" --quiet "${@:2}"; }   # 쪼갤 수 없는 쓰기 1회(상한은 위 공식)
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

MADE_ADDR=0; MADE_VM=0; MADE_FW=0; MADE_IAM=0; ADDR_IP=""; UNSURE=""
TEST_PID=""
cleanup() { [ -n "$TEST_PID" ] && kill "$TEST_PID" 2>/dev/null; return 0; }
trap cleanup EXIT

print_rollback() {
  say "── 되돌림(아직 만든 것만 · VM·주소·방화벽 삭제는 HIL → 오빠 승인 뒤 별도 h) ──"
  [ "$MADE_IAM" = 1 ]  && say "  IAM : gcloud projects add-iam-policy-binding $P --member=serviceAccount:$MINI_SA --role=roles/iap.tunnelResourceAccessor --condition-from-file=$BK/iam-condition-old.yaml && gcloud projects remove-iam-policy-binding $P --member=serviceAccount:$MINI_SA --role=roles/iap.tunnelResourceAccessor --condition-from-file=$BK/iam-condition-new.yaml"
  [ "$MADE_FW" = 1 ]   && say "  방화벽: gcloud compute firewall-rules delete $FW --project=$P   (HIL)"
  [ "$MADE_VM" = 1 ]   && say "  VM  : gcloud compute instances delete $VM --zone=$Z --project=$P   (HIL)"
  [ "$MADE_ADDR" = 1 ] && say "  주소 : gcloud compute addresses delete $ADDR --region=$REGION --project=$P   (HIL · VM 삭제 뒤)"
  [ -n "$UNSURE" ]     && say "  ★미확정(쓰기 timeout 뒤 조회로도 확인 못 함 — 손으로 확인 뒤 위 명령으로): $UNSURE"
  [ "$MADE_IAM$MADE_FW$MADE_VM$MADE_ADDR" = 0000 ] && [ -z "$UNSURE" ] && say "  (만든 것 없음 — 되돌릴 것 없음)"
}
# 조회 3상태: 0=있음 · 1=없음 · 2=조회 실패
q_exists() { local out rc; out="$(G compute "$@" 2>/dev/null)"; rc=$?; [ "$rc" = 0 ] || return 2; [ -n "$out" ]; }
exists_addr() { q_exists addresses list --filter="name=$ADDR" --regions="$REGION" --format='value(name)'; }
exists_vm()   { q_exists instances list --filter="name=$VM" --zones="$Z" --format='value(name)'; }
exists_fw()   { q_exists firewall-rules list --filter="name=$FW" --format='value(name)'; }
pre_absent() { # 사전점검: 반드시 «없음»(1) 이어야 통과 · 있음/조회 실패는 중단
  "$1"; case $? in 0) die 2 "이미 있다: $2 — 이 h 는 새로 만들기만 한다";; 2) die 2 "조회 실패: $2 (권한·네트워크·timeout)";; esac
}
# 쓰기 1회: rc 0 → 즉시 MADE 기록(검증 실패는 경고만) · rc 124 → 미확정 → 조회 «있음» 만 생성으로 인정 · 그 밖 → 실패
do_write() { # $1=상한초 $2=이름 $3=MADE변수명 $4=exists함수 $5=err파일 $6...=gcloud 인자
  local lim="$1" nm="$2" mv="$3" ex="$4" ef="$5"; shift 5
  GL "$lim" "$@" >/dev/null 2>"$ef"; local rc=$?
  if [ "$rc" = 0 ]; then
    printf -v "$mv" 1
    "$ex"; case $? in 0) return 0;; 1) say "        ⚠ 성공 반환했으나 조회에 아직 안 보임($nm) — 5초 뒤 재조회"; sleep 5; "$ex" && return 0; say "        ⚠ 여전히 안 보임 — 만든 것으로 기록은 유지(성공 반환)"; return 0;; 2) say "        ⚠ 성공 반환 · 확인 조회는 실패(만든 것으로 기록)"; return 0;; esac
  fi
  if [ "$rc" = 124 ]; then
    say "        ⚠ ${lim}초 안에 안 끝남($nm) — 미확정 → 5초 뒤 조회로 판정"; sleep 5
    "$ex"; case $? in 0) printf -v "$mv" 1; say "        조회됨 → 만들어진 것으로 기록"; return 0;; 1) UNSURE="$UNSURE $nm(없음으로 보임)";; 2) UNSURE="$UNSURE $nm(조회 실패)";; esac
    return 1
  fi
  tail -2 "$ef" | sed 's/^/        /'; return 1
}
# 마감 루프: $1=마감초 $2=sleep초 $3=회차 상한초(조회·검사) $4...=검사 명령(성공=끝). 남은 시간 < sleep+회차 상한 이면 더 돌지 않는다.
poll() { local lim="$1" s="$2" per="$3"; shift 3; local T=$SECONDS left
  while :; do left=$((lim-(SECONDS-T))); [ "$left" -ge $((s+per)) ] || return 1; sleep "$s"; "$@" && return 0; done; }

# ── 0) 사전점검 (전부 읽기) ─────────────────────────────────────────────────
say "0/6 사전점검 (DRY=$DRY · 계정 $A · 프로젝트 $P)"
command -v gcloud >/dev/null || die 2 "gcloud 없음"
command -v python3 >/dev/null || die 2 "python3 없음"
command -v pg_isready >/dev/null 2>&1 || die 2 "이 맥에 pg_isready 없음(brew libpq) — ⑤ 는 Postgres 응답으로만 합격이라 필수"
mkdir -p "$BK" || die 2 "백업 폴더 생성 실패: $BK"
say "        백업·원장 폴더: $BK (DRY 에서도 로컬 증거 파일은 만든다 · 클라우드 변경 0)"
ACC="$(G auth list --filter="account:$A" --format='value(account)' 2>/dev/null)"; [ "$ACC" = "$A" ] || die 2 "gcloud 에 $A 자격이 없다(gcloud auth login $A)"
pre_absent exists_vm   "VM $VM"
pre_absent exists_addr "주소 $ADDR"
pre_absent exists_fw   "방화벽 $FW"
say "        이름 3개($VM · $ADDR · $FW) 비어 있음(조회 성공 · 없음)"
SN="$(G compute networks subnets describe "$SUBNET" --region="$REGION" --format='value(ipCidrRange,network.basename(),privateIpGoogleAccess)' 2>/dev/null)" || die 2 "서브넷 $SUBNET 조회 실패"
say "        서브넷 $SUBNET = $SN"
case "$SN" in *"$NET"*) ;; *) die 2 "서브넷의 네트워크가 $NET 가 아니다";; esac
NATN="$(G compute routers list --filter="network:$NET" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
say "        vpc-dev Cloud Router 수 = ${NATN:-?} (0 이면 외부 이미지 pull 불가 → iptables 포워더가 맞다)"
G projects get-iam-policy "$P" --format=json > "$BK/iam-policy-before.json" 2>/dev/null || die 2 "IAM 정책 조회 실패"
python3 -I - "$BK/iam-policy-before.json" "$MINI_SA" "$COND_TITLE" "$EXPECT_EXPR_PART" "$BK" <<'PY' || die 2 "mini SA 의 IAP 조건부 바인딩이 «정확히 1개 · 제목 일치 · 10.0.0.9 포함 · 구성원 1» 이 아니다 — 손으로 확인"
import json, sys
pol, sa, title, part, bk = sys.argv[1:6]
d = json.load(open(pol))
hits = [b for b in d.get("bindings", []) if b.get("role") == "roles/iap.tunnelResourceAccessor"
        and ("serviceAccount:" + sa) in b.get("members", []) and b.get("condition")]
if len(hits) != 1: print(f"bindings={len(hits)}", file=sys.stderr); sys.exit(1)
c = hits[0]["condition"]
if c.get("title") != title or part not in c.get("expression", ""): print("title/expr mismatch", file=sys.stderr); sys.exit(1)
if len(hits[0]["members"]) != 1: print("binding has other members", file=sys.stderr); sys.exit(1)
def yq(s): return json.dumps(s, ensure_ascii=False)
open(f"{bk}/iam-condition-old.yaml", "w").write(f"title: {yq(c['title'])}\ndescription: {yq(c.get('description',''))}\nexpression: {yq(c['expression'])}\n")
open(f"{bk}/iam-expression-old.txt", "w").write(c["expression"] + "\n")
print("OK")
PY
say "        mini SA 조건부 바인딩 1개 확인 · 옛 조건 원문 백업 → $BK/iam-condition-old.yaml"
lsof -nP -iTCP:"$TEST_LPORT" -sTCP:LISTEN -t >/dev/null 2>&1 && die 2 "이 맥 127.0.0.1:$TEST_LPORT 가 사용 중(시험 포트) — TEST_LPORT 로 다른 490xx"

# startup-script 본문(비밀 0 · 매 부팅 재적용 · 실패 즉시 중단 · 끝에 규칙 4개+sysctl 재검사 뒤에만 applied)
SS="$BK/startup-script.sh"
cat > "$SS" <<EOS
#!/bin/bash
# byz-db-fwd startup-script — VM:$FWD_PORT → $DB_IP:$DB_PORT (iptables DNAT · COS 내장 · 외부 pull 0)
# 한 줄이라도 실패하면 즉시 끝나고 «applied» 를 남기지 않는다(journal: byz-db-fwd FAIL <단계>).
set -u
fail() { logger -t byz-db-fwd "FAIL \$1"; exit 1; }
sysctl -w net.ipv4.ip_forward=1 >/dev/null || fail sysctl
IPT="iptables -w 10"
\$IPT -t nat -C PREROUTING -p tcp --dport $FWD_PORT -j DNAT --to-destination $DB_IP:$DB_PORT 2>/dev/null || \$IPT -t nat -A PREROUTING -p tcp --dport $FWD_PORT -j DNAT --to-destination $DB_IP:$DB_PORT || fail dnat
\$IPT -t nat -C POSTROUTING -d $DB_IP -p tcp --dport $DB_PORT -j MASQUERADE 2>/dev/null || \$IPT -t nat -A POSTROUTING -d $DB_IP -p tcp --dport $DB_PORT -j MASQUERADE || fail masq
\$IPT -C FORWARD -d $DB_IP -p tcp --dport $DB_PORT -j ACCEPT 2>/dev/null || \$IPT -I FORWARD 1 -d $DB_IP -p tcp --dport $DB_PORT -j ACCEPT || fail fwd-out
\$IPT -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \$IPT -I FORWARD 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || fail fwd-est
# 재검사 4+1(DNAT 된 패킷은 INPUT 이 아니라 FORWARD 를 탄다 — INPUT 규칙은 두지 않는다)
[ "\$(sysctl -n net.ipv4.ip_forward)" = 1 ] || fail verify-sysctl
\$IPT -t nat -C PREROUTING -p tcp --dport $FWD_PORT -j DNAT --to-destination $DB_IP:$DB_PORT || fail verify-dnat
\$IPT -t nat -C POSTROUTING -d $DB_IP -p tcp --dport $DB_PORT -j MASQUERADE || fail verify-masq
\$IPT -C FORWARD -d $DB_IP -p tcp --dport $DB_PORT -j ACCEPT || fail verify-fwd
\$IPT -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || fail verify-fwd-est
logger -t byz-db-fwd "applied $FWD_PORT -> $DB_IP:$DB_PORT"
EOS
bash -n "$SS" || die 2 "startup-script 구문 오류"
say "        startup-script → $SS ($(wc -l < "$SS" | tr -d ' ')줄 · iptables DNAT · 실패 즉시 중단 · 재검사 5개)"

CREATE_CMD=(compute instances create "$VM" --zone="$Z" --machine-type=e2-micro
  --image-family=cos-stable --image-project=cos-cloud --boot-disk-size=10GB
  --network="$NET" --subnet="$SUBNET" --private-network-ip="$ADDR" --no-address
  --tags="$TAG" --no-service-account --no-scopes --shielded-secure-boot
  --max-run-duration="$MAXRUN" --instance-termination-action=STOP --no-restart-on-failure
  --metadata-from-file=startup-script="$SS" --async --format=json)
FW_CMD=(compute firewall-rules create "$FW" --network="$NET" --direction=INGRESS --priority=1000
  --source-ranges="$IAP_RANGE" --rules="tcp:$FWD_PORT" --action=ALLOW --target-tags="$TAG"
  --description="IAP -> byz-db-fwd $FWD_PORT (mini DB path · h1 2026-10-26)")

if [ "$DRY" = 1 ]; then
  say "DRY — 아래를 «할 예정» (클라우드 변경 0 · 로컬 증거 파일만 생성):"
  say "  ① gcloud compute addresses create $ADDR --region=$REGION --subnet=$SUBNET   (IP 는 GCP 가 고름 · 이후 고정 · 상한 25초)"
  say "  ② gcloud ${CREATE_CMD[*]}   (반환 객체 보존 · RUNNING 마감 60초)"
  say "  ③ gcloud ${FW_CMD[*]}   (상한 39초)"
  say "  ④ IAM: add-iam-policy-binding(새 조건 = 옛 식 || (destination.ip == \"<①IP>\" && destination.port == $FWD_PORT)) → remove-iam-policy-binding(옛 조건)   (각 32초 · 완료 = 새 식 정확 일치 1 ∧ 옛 식 0 ∧ 총 1)"
  say "  ⑤ describe 로 maxRunDuration.seconds==$MAXRUN_SEC ∧ STOP 확인(아니면 rc 6 중단) · 이 맥 start-iap-tunnel $VM $FWD_PORT → 127.0.0.1:$TEST_LPORT pg_isready(마감 60초)"
  say "  ⑥ 원장 + 되돌림 + 14시간 격리 관찰 안내"
  say "DRY 끝 — 실제 적용은 DRY=0 (오빠 승인 3가지: VM 생성 · 방화벽 1 · IAM 조건 1)"
  exit 0
fi

# ── 1) 고정 IP 예약 ───────────────────────────────────────────────────────
say "1/6 내부 고정 IP 예약 $ADDR"
do_write 25 "주소 $ADDR" MADE_ADDR exists_addr "$BK/err-addr.txt" compute addresses create "$ADDR" --region="$REGION" --subnet="$SUBNET" --description="byz-db-fwd internal (h1 2026-10-26)" || die 3 "주소 예약 실패/미확정"
ADDR_IP="$(G compute addresses describe "$ADDR" --region="$REGION" --format='value(address)' 2>/dev/null)"
case "$ADDR_IP" in 10.0.0.*) ;; *) die 3 "예약 IP 가 10.0.0.x 가 아니다: '$ADDR_IP'";; esac
say "        $ADDR = $ADDR_IP"
printf 'address %s %s %s\n' "$ADDR" "$REGION" "$ADDR_IP" >> "$BK/ledger.txt"

# ── 2) VM 생성(--async · 반환 객체 보존) → RUNNING 마감 60초 ─────────────────
say "2/6 VM 생성 $VM (e2-micro · COS · 자격 0 · 외부 IP 0 · max-run $MAXRUN · STOP)"
GL 25 "${CREATE_CMD[@]}" >"$BK/err-vm-op.json" 2>"$BK/err-vm.txt"; rc=$?
if [ "$rc" != 0 ] && [ "$rc" != 124 ]; then tail -3 "$BK/err-vm.txt" | sed 's/^/        /'; die 4 "VM 생성 요청 실패(플래그 조합·조직 정책 확인)"; fi
[ "$rc" = 0 ] && MADE_VM=1
[ "$rc" = 124 ] && say "        ⚠ 생성 요청이 25초 안에 안 돌아옴 — 미확정 → 조회로 판정"
OPN="$(python3 -I -c 'import json,sys
try:
    d=json.load(open(sys.argv[1])); d=d[0] if isinstance(d,list) and d else d
    print(d.get("name","") if d.get("kind","").endswith("operation") or "operationType" in d else "(반환 객체가 작업이 아님: kind=%s)"%d.get("kind","?"))
except Exception as e: print("(해석 실패)")' "$BK/err-vm-op.json" 2>/dev/null)"
say "        반환 객체 → $BK/err-vm-op.json · 작업 이름(추정 해석): ${OPN:-(없음)} — 오류 추적: gcloud compute operations describe <작업> --zone=$Z"
vm_status() { ST="$(G compute instances describe "$VM" --zone="$Z" --format='value(status)' 2>/dev/null)" || return 1; [ -n "$ST" ] && MADE_VM=1; [ "$ST" = RUNNING ]; }
ST=""; poll 60 5 "$GT" vm_status || true
printf 'instance %s %s made=%s status=%s\n' "$VM" "$Z" "$MADE_VM" "${ST:-?}" >> "$BK/ledger.txt"
if [ "$MADE_VM" != 1 ]; then UNSURE="$UNSURE VM:$VM(반환 $BK/err-vm-op.json)"; die 4 "VM 이 마감 60초 안에 조회되지 않는다 — 반환 객체·작업으로 확인"; fi
[ "$ST" = RUNNING ] || die 4 "VM 이 마감 60초 안에 RUNNING 이 아니다(status=${ST:-?})"
say "        RUNNING"

# ── 3) 만료 설정 확인 — 여기서 틀리면 도입 중단 ─────────────────────────────
say "3/6 만료 설정 확인(핵심)"
SCHED="$(G compute instances describe "$VM" --zone="$Z" --format='value(scheduling.maxRunDuration.seconds,scheduling.instanceTerminationAction,scheduling.automaticRestart,lastStartTimestamp,networkInterfaces[0].networkIP)' 2>/dev/null)"
MR="$(printf '%s' "$SCHED" | cut -f1)"; TA="$(printf '%s' "$SCHED" | cut -f2)"; AR="$(printf '%s' "$SCHED" | cut -f3)"; LST="$(printf '%s' "$SCHED" | cut -f4)"; NIP="$(printf '%s' "$SCHED" | cut -f5)"
say "        maxRunDuration.seconds=$MR terminationAction=$TA automaticRestart=$AR lastStart=$LST ip=$NIP"
printf 'scheduling maxRunDuration=%s action=%s autoRestart=%s lastStart=%s\n' "$MR" "$TA" "$AR" "$LST" >> "$BK/ledger.txt"
[ "$MR" = "$MAXRUN_SEC" ] && [ "$TA" = STOP ] || die 6 "★도입 중단★ Google 쪽 만료 설정이 확인되지 않는다(maxRunDuration=$MR action=$TA) — 게스트 타이머로 대체하지 않는다. VM·주소는 되돌림(HIL)"
[ "$NIP" = "$ADDR_IP" ] || die 6 "VM 내부 IP($NIP)가 예약 IP($ADDR_IP)와 다르다"
G compute instances describe "$VM" --zone="$Z" --format=json > "$BK/instance-after-create.json" 2>/dev/null
TT="$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1])).get("scheduling",{}).get("terminationTime","(없음 · 필수 아님)"))' "$BK/instance-after-create.json" 2>/dev/null)"
say "        terminationTime=$TT (기록만)"

# ── 4) 방화벽 ─────────────────────────────────────────────────────────────
say "4/6 방화벽 $FW ($IAP_RANGE → tcp:$FWD_PORT · 태그 $TAG)"
do_write 39 "방화벽 $FW" MADE_FW exists_fw "$BK/err-fw.txt" "${FW_CMD[@]}" || die 5 "방화벽 생성 실패/미확정"
printf 'firewall %s\n' "$FW" >> "$BK/ledger.txt"

# ── 5) IAM 조건식 1줄 확장 (add 새 → remove 옛 · 완료 = 정확 일치) ────────────
say "5/6 IAM: $MINI_SA 조건식에 ($ADDR_IP:$FWD_PORT) 추가"
OLD_EXPR="$(cat "$BK/iam-expression-old.txt")"
NEW_EXPR="$OLD_EXPR || (destination.ip == \"$ADDR_IP\" && destination.port == $FWD_PORT)"
printf '%s\n' "$NEW_EXPR" > "$BK/iam-expression-new.txt"
python3 -I - "$BK" "$COND_TITLE" "$NEW_EXPR" <<'PY'
import json, sys
bk, title, expr = sys.argv[1:4]
desc = "llm-dev 8000 and stt-tts-dev 8000 8100 and byz-db-fwd 38309 (h1 2026-10-26)"
open(f"{bk}/iam-condition-new.yaml","w").write(f"title: {json.dumps(title)}\ndescription: {json.dumps(desc)}\nexpression: {json.dumps(expr)}\n")
PY
# 상태 조회: 출력 "new=<0|1> old=<0|1> n=<총개수>" (정확 일치) · 조회 실패면 빈 문자열
iam_state() { G projects get-iam-policy "$P" --format=json 2>/dev/null | python3 -I -c '
import json,sys; d=json.load(sys.stdin); sa="serviceAccount:"+sys.argv[1]; new=open(sys.argv[2]).read().strip(); old=open(sys.argv[3]).read().strip()
h=[b for b in d["bindings"] if b["role"]=="roles/iap.tunnelResourceAccessor" and sa in b["members"]]
ex=[(b.get("condition") or {}).get("expression","").strip() for b in h]
print("new=%d old=%d n=%d"%(ex.count(new), ex.count(old), len(h)))' "$MINI_SA" "$BK/iam-expression-new.txt" "$BK/iam-expression-old.txt" 2>/dev/null; }
GL 32 projects add-iam-policy-binding "$P" --member="serviceAccount:$MINI_SA" --role=roles/iap.tunnelResourceAccessor --condition-from-file="$BK/iam-condition-new.yaml" >/dev/null 2>"$BK/err-iam-add.txt"; rc=$?
if [ "$rc" = 0 ]; then MADE_IAM=1
elif [ "$rc" = 124 ]; then say "        ⚠ add 가 32초 안에 안 끝남 — 미확정 → 조회"; sleep 5; S1="$(iam_state)"; case "$S1" in new=1*) MADE_IAM=1; say "        조회: 새 조건 보임($S1)";; "") UNSURE="$UNSURE IAM-add(조회 실패)"; die 5 "IAM add 미확정 + 조회 실패";; *) UNSURE="$UNSURE IAM-add(미적용으로 보임 $S1)"; die 5 "IAM add 미확정 · 새 조건 안 보임";; esac
else tail -2 "$BK/err-iam-add.txt" | sed 's/^/        /'; die 5 "IAM 새 조건 추가 실패"; fi
GL 32 projects remove-iam-policy-binding "$P" --member="serviceAccount:$MINI_SA" --role=roles/iap.tunnelResourceAccessor --condition-from-file="$BK/iam-condition-old.yaml" >/dev/null 2>"$BK/err-iam-rm.txt"; rc=$?
[ "$rc" = 0 ] || [ "$rc" = 124 ] || { tail -2 "$BK/err-iam-rm.txt" | sed 's/^/        /'; die 5 "IAM 옛 조건 제거 실패 — 지금 바인딩이 2개(옛+새)다 · 되돌림 줄 참고"; }
[ "$rc" = 124 ] && { say "        ⚠ remove 가 32초 안에 안 끝남 — 미확정 → 조회"; sleep 5; }
S2="$(iam_state)"; G projects get-iam-policy "$P" --format=json > "$BK/iam-policy-after.json" 2>/dev/null
[ "$S2" = "new=1 old=0 n=1" ] || die 5 "IAM 결과가 «새 식 정확 일치 1 · 옛 식 0 · 총 1» 이 아니다: '${S2:-조회 실패}' (옛 제거가 미확정이면 잠시 뒤 get-iam-policy 재확인 · 되돌림 줄 참고)"
printf 'iam %s condition %s (old=%s) state=%s\n' "$MINI_SA" "$BK/iam-condition-new.yaml" "$BK/iam-condition-old.yaml" "$S2" >> "$BK/ledger.txt"
say "        $S2 · 새 조건식 정확 일치 · 전/후 정책 JSON 백업됨"

# ── 6) 이 맥에서 도달 확인(developer.ts · 시험 포트 · Postgres 응답만 합격 · 마감 60초) ──
say "6/6 도달 확인: start-iap-tunnel $VM $FWD_PORT → 127.0.0.1:$TEST_LPORT → pg_isready"
timeout 70 gcloud --account="$A" --project="$P" compute start-iap-tunnel "$VM" "$FWD_PORT" --zone="$Z" --local-host-port="127.0.0.1:$TEST_LPORT" >"$BK/iap-test.log" 2>&1 &
TEST_PID=$!
pg_probe() { pg_isready -h 127.0.0.1 -p "$TEST_LPORT" -t 5 -q 2>/dev/null; }
OK=0; poll 60 7 6 pg_probe && OK=1          # 회차 = sleep 7 + pg_isready ≤ 6 · 남은 시간 < 13 이면 안 돈다 → 마감 60초 안
kill "$TEST_PID" 2>/dev/null; TEST_PID=""
if [ "$OK" = 1 ]; then say "        ✓ Postgres 응답(pg_isready · IAP → VM DNAT → $DB_IP:$DB_PORT)"; printf 'reach OK via iap test port %s\n' "$TEST_LPORT" >> "$BK/ledger.txt"
else tail -3 "$BK/iap-test.log" | sed 's/^/        /'; say "        ✗ 마감 60초 안에 Postgres 응답 없음(VM 첫 부팅·startup-script 진행 중일 수 있음 — 2분 뒤 h2 ③ 에서 재확인 · journal 에 byz-db-fwd FAIL 이 있으면 iptables 단계 실패)"; printf 'reach FAIL\n' >> "$BK/ledger.txt"; fi

# ── 끝 ───────────────────────────────────────────────────────────────────
EXP="$(python3 -I -c '
import sys,datetime as d; s=sys.argv[1]
t=d.datetime.fromisoformat(s.replace("Z","+00:00")); print((t+d.timedelta(seconds=int(sys.argv[2]))).astimezone().strftime("%Y-%m-%d %H:%M %Z"))' "$LST" "$MAXRUN_SEC" 2>/dev/null || echo '?')"
say "── 자원 원장($BK/ledger.txt) ──"; sed 's/^/  /' "$BK/ledger.txt"
print_rollback
cat <<EOF
[h1-db-fwd] ★14시간 격리 관찰(DA r3 조건 5)★ — 지금부터 $VM 을 «아무도» 재기동·정지하지 않는다(h2 의 stop/start 시험 · h3 설치는 관찰 뒤).
            마지막 기동 $LST → 만료 예상 $EXP (±10분). 그 시각 뒤 확인:
              gcloud compute instances describe $VM --zone=$Z --project=$P --account=$A --format='value(status,lastStopTimestamp)'
            TERMINATED 이면 합격 → h1b(h-db-fwd-start.sh · 기동·정지 시각 둘 다 있어야 켠다)로 길 복구 → h2. RUNNING 그대로면 ★도입 중단★(되돌림 HIL).
            로그: VM 에 서비스 계정이 없어 Cloud Logging 전송 0 — startup-script 결과는 게스트 journal(byz-db-fwd applied|FAIL)에만 남는다(수용 · 합격 증거는 pg_isready 응답).
            닫는 증거 3줄: maxRunDuration=$MR action=$TA · IAM $S2 (새 IP $ADDR_IP) · 도달=$( [ "$OK" = 1 ] && echo OK || echo 재확인 )
EOF
[ "$OK" = 1 ] || exit 7
exit 0
