#!/usr/bin/env bash
# h-db-fwd-create.sh — h1: mini 의 DB 길 «열쇠 구멍» 포워더 VM 만들기 (카드 하나 · DESIGN-db-key-vm-cycle-20261026.md §3·§6)
#   (2026-10-26 · aifp-multihost-arch-claude#2 초안 · 발주 #3313 · DA r3 APPROVE 조건부 반영 · 실행은 오빠 `! bash /tmp/h<N>` 로만)
#   먼저 계획만: `bash /tmp/h<N>` (DRY=1 기본 · gcloud 읽기 명령만 · 쓰기 0). 실제 적용: `DRY=0 bash /tmp/h<N>`.
#
# 만드는 것 4개(순서대로 · 각 단계 실패 = 거기서 멈춤 · 뒤 단계 안 함):
#   ① 내부 고정 IP 예약  byz-db-fwd-ip  (서브넷 byz-agents-subnet-dev 10.0.0.0/24 · IAP 조건식의 destination.ip 가 흔들리지 않게)
#   ② VM byz-db-fwd  e2-micro · COS stable · 외부 IP 없음 · ★서비스 계정 없음★(자격 0) · 태그 db-fwd
#        --max-run-duration=14h --instance-termination-action=STOP --no-restart-on-failure   ← Google 이 14시간 뒤 스스로 끈다(열쇠)
#        포워딩 = startup-script 의 iptables DNAT(VM:38309 → 10.2.0.10:5432). ★컨테이너(socat) 대신 iptables 인 이유★:
#        읽기 전용 실측(10-26) — vpc-dev 에 Cloud NAT 0 · VM 외부 IP 0 → Docker Hub 에서 이미지를 받을 길이 없다.
#        iptables 는 COS 에 내장이라 받아올 것이 0 이고, 서비스 계정도 필요 없다. 매 부팅 startup-script 가 다시 적용(COS 루트 읽기 전용).
#   ③ 방화벽 1줄  byz-agents-allow-iap-db-fwd : 35.235.240.0/20(IAP) → tcp:38309 · 대상 태그 db-fwd 만
#   ④ byz-mini-tunnel 의 IAP 조건식 1줄 확장: 기존 식 || (destination.ip == "<①의 IP>" && destination.port == 38309)
#        방법 = 새 조건 바인딩 add → 옛 조건 바인딩 remove (etag 경쟁 없음 · 둘 다 --condition-from-file · 옛 조건 원문은 파일로 백업)
#   ⑤ 확인: describe 의 scheduling.maxRunDuration.seconds == 50400 ∧ instanceTerminationAction == STOP — ★아니면 도입 중단(rc 6)★
#        (게스트 shutdown 타이머로 대체하지 않는다 — «Google 이 강제» 전제 · DA r1 #12). 이 맥(developer.ts · 무조건 IAP 권한)에서
#        start-iap-tunnel byz-db-fwd 38309 → pg_isready 로 «포트 열림» 이 아니라 «Postgres 응답» 확인.
#   ⑥ 끝: 자원 원장 4줄 + 되돌림 명령 4줄 출력 + ★14시간 격리 관찰 안내★(lastStartTimestamp+14h ±10분에 손 없이 TERMINATED 가 되는지 · 그동안 재기동 0)
#
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
GT="${GT:-11}"                                   # 외부 호출 1회 상한 = 7초 + gcloud 기동 고정비(약 4초)
G()  { timeout "$GT" gcloud --account="$A" --project="$P" --quiet "$@"; }
GL() { timeout "${1}" gcloud --account="$A" --project="$P" --quiet "${@:2}"; }   # 쪼갤 수 없는 쓰기 1회(상한 ≤ 40)
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

MADE_ADDR=0; MADE_VM=0; MADE_FW=0; MADE_IAM=0; ADDR_IP=""
TEST_PID=""
cleanup() { [ -n "$TEST_PID" ] && kill "$TEST_PID" 2>/dev/null; return 0; }
trap cleanup EXIT

print_rollback() {
  say "── 되돌림(아직 만든 것만 · VM·주소·방화벽 삭제는 HIL → 오빠 승인 뒤 별도 h) ──"
  [ "$MADE_IAM" = 1 ]  && say "  IAM : gcloud projects add-iam-policy-binding $P --member=serviceAccount:$MINI_SA --role=roles/iap.tunnelResourceAccessor --condition-from-file=$BK/iam-condition-old.yaml && gcloud projects remove-iam-policy-binding $P --member=serviceAccount:$MINI_SA --role=roles/iap.tunnelResourceAccessor --condition-from-file=$BK/iam-condition-new.yaml"
  [ "$MADE_FW" = 1 ]   && say "  방화벽: gcloud compute firewall-rules delete $FW --project=$P   (HIL)"
  [ "$MADE_VM" = 1 ]   && say "  VM  : gcloud compute instances delete $VM --zone=$Z --project=$P   (HIL)"
  [ "$MADE_ADDR" = 1 ] && say "  주소 : gcloud compute addresses delete $ADDR --region=$REGION --project=$P   (HIL · VM 삭제 뒤)"
  [ "$MADE_IAM$MADE_FW$MADE_VM$MADE_ADDR" = 0000 ] && say "  (만든 것 없음 — 되돌릴 것 없음)"
}

# ── 0) 사전점검 (전부 읽기) ─────────────────────────────────────────────────
say "0/6 사전점검 (DRY=$DRY · 계정 $A · 프로젝트 $P)"
command -v gcloud >/dev/null || die 2 "gcloud 없음"
command -v python3 >/dev/null || die 2 "python3 없음"
mkdir -p "$BK" || die 2 "백업 폴더 생성 실패: $BK"
say "        백업·원장 폴더: $BK"
ACC="$(G auth list --filter="account:$A" --format='value(account)' 2>/dev/null)"; [ "$ACC" = "$A" ] || die 2 "gcloud 에 $A 자격이 없다(gcloud auth login $A)"
# 이름 충돌 0
for chk in "instances list --filter=name=$VM --format=value(name)" "addresses list --filter=name=$ADDR --format=value(name)" "firewall-rules list --filter=name=$FW --format=value(name)"; do
  # shellcheck disable=SC2086
  r="$(G compute $chk 2>/dev/null)" || die 2 "조회 실패: gcloud compute $chk"
  [ -z "$r" ] || die 2 "이미 있다: $r — 이 h 는 새로 만들기만 한다(있는 것을 고치지 않는다)"
done
say "        이름 3개($VM · $ADDR · $FW) 비어 있음"
# 서브넷·네트워크 실재
SN="$(G compute networks subnets describe "$SUBNET" --region="$REGION" --format='value(ipCidrRange,network.basename(),privateIpGoogleAccess)' 2>/dev/null)" || die 2 "서브넷 $SUBNET 조회 실패"
say "        서브넷 $SUBNET = $SN"
case "$SN" in *"$NET"*) ;; *) die 2 "서브넷의 네트워크가 $NET 가 아니다";; esac
# NAT 없음 확인(iptables 선택 근거 — 있어도 동작엔 지장 없음 · 기록용)
NATN="$(G compute routers list --filter="network:$NET" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
say "        vpc-dev Cloud Router 수 = ${NATN:-?} (0 이면 외부 이미지 pull 불가 → iptables 포워더가 맞다)"
# mini SA 의 조건부 바인딩 정확히 1개 · 조각 포함
G projects get-iam-policy "$P" --format=json > "$BK/iam-policy-before.json" 2>/dev/null || die 2 "IAM 정책 조회 실패"
python3 -I - "$BK/iam-policy-before.json" "$MINI_SA" "$COND_TITLE" "$EXPECT_EXPR_PART" "$BK" <<'PY' || die 2 "mini SA 의 IAP 조건부 바인딩이 «정확히 1개 · 제목 일치 · 10.0.0.9 포함» 이 아니다 — 손으로 확인"
import json, sys
pol, sa, title, part, bk = sys.argv[1:6]
d = json.load(open(pol))
hits = [b for b in d.get("bindings", []) if b.get("role") == "roles/iap.tunnelResourceAccessor"
        and ("serviceAccount:" + sa) in b.get("members", []) and b.get("condition")]
if len(hits) != 1: print(f"bindings={len(hits)}", file=sys.stderr); sys.exit(1)
c = hits[0]["condition"]
if c.get("title") != title or part not in c.get("expression", ""): print("title/expr mismatch", file=sys.stderr); sys.exit(1)
if len(hits[0]["members"]) != 1: print("binding has other members", file=sys.stderr); sys.exit(1)
# 옛 조건 원문 → YAML(condition-from-file 꼴) · 값은 조건식뿐(비밀 0)
def yq(s): return json.dumps(s, ensure_ascii=False)
open(f"{bk}/iam-condition-old.yaml", "w").write(f"title: {yq(c['title'])}\ndescription: {yq(c.get('description',''))}\nexpression: {yq(c['expression'])}\n")
open(f"{bk}/iam-expression-old.txt", "w").write(c["expression"] + "\n")
print("OK")
PY
say "        mini SA 조건부 바인딩 1개 확인 · 옛 조건 원문 백업 → $BK/iam-condition-old.yaml"
# 이 맥 시험 포트 비어 있음
lsof -nP -iTCP:"$TEST_LPORT" -sTCP:LISTEN -t >/dev/null 2>&1 && die 2 "이 맥 127.0.0.1:$TEST_LPORT 가 사용 중(시험 포트) — TEST_LPORT 로 다른 490xx"
command -v pg_isready >/dev/null 2>&1 && PGR=1 || PGR=0
[ "$PGR" = 1 ] || say "        ⚠ 이 맥에 pg_isready 없음 → ⑤ 는 TCP 연결까지만 확인(Postgres 응답 확인은 h2 ③ 에서)"

# startup-script 본문(비밀 0 · 매 부팅 재적용)
SS="$BK/startup-script.sh"
cat > "$SS" <<EOS
#!/bin/bash
# byz-db-fwd startup-script — VM:$FWD_PORT → $DB_IP:$DB_PORT (iptables DNAT · COS 내장 · 외부 pull 0)
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -C PREROUTING -p tcp --dport $FWD_PORT -j DNAT --to-destination $DB_IP:$DB_PORT 2>/dev/null || iptables -t nat -A PREROUTING -p tcp --dport $FWD_PORT -j DNAT --to-destination $DB_IP:$DB_PORT
iptables -t nat -C POSTROUTING -d $DB_IP -p tcp --dport $DB_PORT -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -d $DB_IP -p tcp --dport $DB_PORT -j MASQUERADE
iptables -C FORWARD -d $DB_IP -p tcp --dport $DB_PORT -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -d $DB_IP -p tcp --dport $DB_PORT -j ACCEPT
iptables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -C INPUT -p tcp --dport $FWD_PORT -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport $FWD_PORT -j ACCEPT
logger -t byz-db-fwd "forward $FWD_PORT -> $DB_IP:$DB_PORT applied"
EOS
say "        startup-script → $SS ($(wc -l < "$SS")줄 · iptables DNAT)"

CREATE_CMD=(compute instances create "$VM" --zone="$Z" --machine-type=e2-micro
  --image-family=cos-stable --image-project=cos-cloud --boot-disk-size=10GB
  --network="$NET" --subnet="$SUBNET" --private-network-ip="$ADDR" --no-address
  --tags="$TAG" --no-service-account --no-scopes --shielded-secure-boot
  --max-run-duration="$MAXRUN" --instance-termination-action=STOP --no-restart-on-failure
  --metadata-from-file=startup-script="$SS" --async)
FW_CMD=(compute firewall-rules create "$FW" --network="$NET" --direction=INGRESS --priority=1000
  --source-ranges="$IAP_RANGE" --rules="tcp:$FWD_PORT" --action=ALLOW --target-tags="$TAG"
  --description="IAP -> byz-db-fwd $FWD_PORT (mini DB path · h1 2026-10-26)")

if [ "$DRY" = 1 ]; then
  say "DRY — 아래를 «할 예정» (쓰기 0):"
  say "  ① gcloud compute addresses create $ADDR --region=$REGION --subnet=$SUBNET   (IP 는 GCP 가 고름 · 이후 고정)"
  say "  ② gcloud ${CREATE_CMD[*]}"
  say "  ③ gcloud ${FW_CMD[*]}"
  say "  ④ IAM: add-iam-policy-binding(새 조건 = 옛 식 || (destination.ip == \"<①IP>\" && destination.port == $FWD_PORT)) → remove-iam-policy-binding(옛 조건)"
  say "  ⑤ describe 로 maxRunDuration.seconds==$MAXRUN_SEC ∧ STOP 확인(아니면 rc 6 중단) · 이 맥 start-iap-tunnel $VM $FWD_PORT → 127.0.0.1:$TEST_LPORT 도달 확인"
  say "  ⑥ 원장 4줄 + 되돌림 4줄 + 14시간 격리 관찰 안내"
  say "DRY 끝 — 실제 적용은 DRY=0 (오빠 승인 3가지: VM 생성 · 방화벽 1 · IAM 조건 1)"
  exit 0
fi

# ── 1) 고정 IP 예약 ───────────────────────────────────────────────────────
say "1/6 내부 고정 IP 예약 $ADDR"
GL 25 compute addresses create "$ADDR" --region="$REGION" --subnet="$SUBNET" --description="byz-db-fwd internal (h1 2026-10-26)" >/dev/null 2>"$BK/err-addr.txt" || { tail -2 "$BK/err-addr.txt" | sed 's/^/        /'; die 3 "주소 예약 실패"; }
MADE_ADDR=1
ADDR_IP="$(G compute addresses describe "$ADDR" --region="$REGION" --format='value(address)' 2>/dev/null)"
case "$ADDR_IP" in 10.0.0.*) ;; *) die 3 "예약 IP 가 10.0.0.x 가 아니다: '$ADDR_IP'";; esac
say "        $ADDR = $ADDR_IP"
printf 'address %s %s %s\n' "$ADDR" "$REGION" "$ADDR_IP" >> "$BK/ledger.txt"

# ── 2) VM 생성(--async) → RUNNING 폴링 ─────────────────────────────────────
say "2/6 VM 생성 $VM (e2-micro · COS · 자격 0 · 외부 IP 0 · max-run $MAXRUN · STOP)"
G "${CREATE_CMD[@]}" >/dev/null 2>"$BK/err-vm.txt" || { tail -3 "$BK/err-vm.txt" | sed 's/^/        /'; die 4 "VM 생성 요청 실패(플래그 조합·조직 정책 확인)"; }
MADE_VM=1
printf 'instance %s %s\n' "$VM" "$Z" >> "$BK/ledger.txt"
ST=""; for i in 1 2 3 4 5 6 7 8 9 10; do sleep 5; ST="$(G compute instances describe "$VM" --zone="$Z" --format='value(status)' 2>/dev/null)"; [ "$ST" = RUNNING ] && break; done
[ "$ST" = RUNNING ] || die 4 "VM 이 50초 안에 RUNNING 이 아니다(status=$ST)"
say "        RUNNING"

# ── 5a) 만료 설정 확인 — 여기서 틀리면 도입 중단 ───────────────────────────
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

# ── 3) 방화벽 ─────────────────────────────────────────────────────────────
say "4/6 방화벽 $FW ($IAP_RANGE → tcp:$FWD_PORT · 태그 $TAG)"
GL 40 "${FW_CMD[@]}" >/dev/null 2>"$BK/err-fw.txt" || { tail -2 "$BK/err-fw.txt" | sed 's/^/        /'; die 5 "방화벽 생성 실패"; }
MADE_FW=1; printf 'firewall %s\n' "$FW" >> "$BK/ledger.txt"

# ── 4) IAM 조건식 1줄 확장 (add 새 → remove 옛) ───────────────────────────
say "5/6 IAM: $MINI_SA 조건식에 ($ADDR_IP:$FWD_PORT) 추가"
OLD_EXPR="$(cat "$BK/iam-expression-old.txt")"
NEW_EXPR="$OLD_EXPR || (destination.ip == \"$ADDR_IP\" && destination.port == $FWD_PORT)"
python3 -I - "$BK" "$COND_TITLE" "$NEW_EXPR" <<'PY'
import json, sys
bk, title, expr = sys.argv[1:4]
desc = "llm-dev 8000 and stt-tts-dev 8000 8100 and byz-db-fwd 38309 (h1 2026-10-26)"
open(f"{bk}/iam-condition-new.yaml","w").write(f"title: {json.dumps(title)}\ndescription: {json.dumps(desc)}\nexpression: {json.dumps(expr)}\n")
PY
GL 30 projects add-iam-policy-binding "$P" --member="serviceAccount:$MINI_SA" --role=roles/iap.tunnelResourceAccessor --condition-from-file="$BK/iam-condition-new.yaml" >/dev/null 2>"$BK/err-iam-add.txt" || { tail -2 "$BK/err-iam-add.txt" | sed 's/^/        /'; die 5 "IAM 새 조건 추가 실패"; }
MADE_IAM=1
GL 30 projects remove-iam-policy-binding "$P" --member="serviceAccount:$MINI_SA" --role=roles/iap.tunnelResourceAccessor --condition-from-file="$BK/iam-condition-old.yaml" >/dev/null 2>"$BK/err-iam-rm.txt" || { tail -2 "$BK/err-iam-rm.txt" | sed 's/^/        /'; die 5 "IAM 옛 조건 제거 실패 — 지금 바인딩이 2개(옛+새)다 · 되돌림 줄 참고"; }
G projects get-iam-policy "$P" --format=json > "$BK/iam-policy-after.json" 2>/dev/null
NB="$(python3 -I -c '
import json,sys; d=json.load(open(sys.argv[1])); sa="serviceAccount:"+sys.argv[2]
h=[b for b in d["bindings"] if b["role"]=="roles/iap.tunnelResourceAccessor" and sa in b["members"]]
print(len(h), all(sys.argv[3] in (b.get("condition") or {}).get("expression","") for b in h))' "$BK/iam-policy-after.json" "$MINI_SA" "$ADDR_IP" 2>/dev/null)"
[ "$NB" = "1 True" ] || die 5 "IAM 결과가 «바인딩 1개 · 새 IP 포함» 이 아니다: $NB"
printf 'iam %s condition %s (old=%s)\n' "$MINI_SA" "$BK/iam-condition-new.yaml" "$BK/iam-condition-old.yaml" >> "$BK/ledger.txt"
say "        바인딩 1개 · 새 조건식 적용 · 전/후 정책 JSON 백업됨"

# ── 5b) 이 맥에서 도달 확인(developer.ts · 시험 포트) ─────────────────────
say "6/6 도달 확인: start-iap-tunnel $VM $FWD_PORT → 127.0.0.1:$TEST_LPORT"
timeout 120 gcloud --account="$A" --project="$P" compute start-iap-tunnel "$VM" "$FWD_PORT" --zone="$Z" --local-host-port="127.0.0.1:$TEST_LPORT" >"$BK/iap-test.log" 2>&1 &
TEST_PID=$!
OK=0
for i in 1 2 3 4 5 6 7 8; do
  sleep 7
  if [ "$PGR" = 1 ]; then pg_isready -h 127.0.0.1 -p "$TEST_LPORT" -t 5 -q 2>/dev/null && { OK=1; break; }
  else nc -z -w 5 127.0.0.1 "$TEST_LPORT" 2>/dev/null && { OK=1; break; } ; fi
done
kill "$TEST_PID" 2>/dev/null; TEST_PID=""
if [ "$OK" = 1 ]; then say "        ✓ $([ "$PGR" = 1 ] && echo 'Postgres 응답(pg_isready)' || echo 'TCP 연결')"; printf 'reach %s via iap test port %s\n' OK "$TEST_LPORT" >> "$BK/ledger.txt"
else tail -3 "$BK/iap-test.log" | sed 's/^/        /'; say "        ✗ 56초 안에 응답 없음(VM 첫 부팅 중일 수 있음 — 1~2분 뒤 h2 ③ 에서 재확인)"; printf 'reach %s\n' FAIL >> "$BK/ledger.txt"; fi

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
            TERMINATED 이면 합격 → h1b(h-db-fwd-start.sh)로 길 복구 → h2. RUNNING 그대로면 ★도입 중단★(되돌림 HIL).
            닫는 증거 3줄: maxRunDuration=$MR action=$TA · IAM 바인딩 1개(새 IP $ADDR_IP) · 도달=$( [ "$OK" = 1 ] && echo OK || echo 재확인 )
EOF
[ "$OK" = 1 ] || exit 7
exit 0
