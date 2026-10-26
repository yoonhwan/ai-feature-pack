#!/usr/bin/env bash
# h-oci-hermes-opengateway.sh — OCI hermes(jarvis 슬랙 봇)의 모델을 OpenGateway 의 deepseek-v4.1-flash-ultrafast 로 바꾼다. 실행은 오빠가 `! bash /tmp/h<N>` 로만.
#   2026-10-26 · aifp-multihost-master-claude#4 · 오빠 «로컬환경의 opengateway 설정으로 deepseek ultrafast 넣어주자» (OCI hermes 가 OpenRouter 뒤 업체 GMICloud 의 Cloudflare 403 으로 간헐 실패)
#   로컬 정본(이 맥 ~/.pi/agent/models.json): provider=opengateway · baseUrl=https://apis.opengateway.ai/v1 · api=openai-completions · 모델 deepseek/deepseek-v4.1-flash-ultrafast · 키=macOS 키체인 항목 `opengateway`(명령 `security find-generic-password -ws opengateway`)
#   순서(하나라도 실패하면 거기서 멈춤 — ★3번 «OCI 에서 직접 호출 시험» 이 실패하면 OCI 설정은 한 글자도 안 바꾼다★):
#     ① 사전점검(키체인 항목 존재·OCI 접속·hermes-gateway 서비스·providers: 중복 없음)
#     ② OCI 에서 opengateway 에 짧은 chat 1회(값 출력 0 · HTTP 코드와 응답 글자 수만)
#     ③ 백업(config.yaml·.env 를 시각 붙여 복사) → .env 에 OPENGATEWAY_API_KEY 추가(이름 없을 때만 · 600 유지) → config.yaml 의 model: 블록 교체 + providers: opengateway 블록 추가
#     ④ YAML 파싱 확인 → `systemctl --user restart hermes-gateway` → 활성·최근 로그 오류 확인
#   하지 않는 일: 키 값 출력 0(화면·명령줄·디스크 임시파일은 600 · 끝나면 삭제) · 다른 설정 변경 0 · OPENAI/OPENROUTER 키 건드리기 0 · fallback 추가 0(원하시면 별도)
#   되돌리기: 출력 끝에 적힌 백업 두 개를 cp 로 복원 + 같은 restart (이 h 는 자동 복원하지 않는다)
# 사용: bash /tmp/h<N> · DRY=1 → ①②까지(②는 키를 쓰므로 DRY 에서는 하지 않고 ①만)
# rc: 0 성공 · 2 전제 실패 · 3 OCI 에서 opengateway 호출 실패(설정 변경 0) · 4 설정 변경 실패 · 5 재시작 뒤 이상
set -uo pipefail
OCI="${OCI:-oci}"; DRY="${DRY:-0}"
MODEL="deepseek/deepseek-v4.1-flash-ultrafast"; BASE="https://apis.opengateway.ai/v1"; PNAME="opengateway"; KENV="OPENGATEWAY_API_KEY"
SO=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-ocihm] %s\n' "$*"; }
die() { printf '[h-ocihm] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
oc() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$OCI" "$@"; }

say "1/4 사전점검"
security find-generic-password -s opengateway >/dev/null 2>&1 || die 2 "이 맥 키체인에 opengateway 항목이 없다(pi 가 쓰는 키체인 항목)"
PRE="$(oc 25 'H=$HOME/.hermes; echo cfg=$([ -f $H/config.yaml ] && echo ok || echo MISSING); echo env=$([ -f $H/.env ] && echo ok || echo MISSING); echo svc=$(systemctl --user is-active hermes-gateway 2>/dev/null); echo providers_block=$(grep -c "^providers:" $H/config.yaml 2>/dev/null); echo og_key_name=$(grep -c "^OPENGATEWAY_API_KEY=" $H/.env 2>/dev/null); echo py=$(command -v python3 >/dev/null && echo ok || echo MISSING); echo yaml=$(python3 -c "import yaml;print(yaml.__version__)" 2>/dev/null || echo MISSING); echo model_now=$(sed -n "2,3p" $H/config.yaml | tr -s " \n" " ")' 2>&1)" || die 2 "OCI 접속 실패: ${PRE}"
printf '%s\n' "$PRE" | sed 's/^/        /'
case "$PRE" in *MISSING*) die 2 "OCI 에 필요한 것이 없다(위 MISSING)";; esac
case "$PRE" in *"svc=active"*) ;; *) die 2 "hermes-gateway 서비스가 active 가 아니다";; esac
case "$PRE" in *"providers_block=0"*) ;; *) die 2 "config.yaml 에 providers: 블록이 이미 있다 — 자동 병합하지 않는다(사람이 확인)";; esac
if [ "$DRY" = "1" ]; then say "DRY — 쓰기 0 · 키 사용 0. 조건 OK. 실제 실행은 ②에서 OCI→opengateway 호출 시험부터 한다"; exit 0; fi

# 키는 «600 임시 파일 → ssh stdin» 으로만(화면·명령줄 0). 끝나면 삭제.
KF="$(mktemp "${TMPDIR:-/tmp}/h-ocihm.XXXXXX")"; chmod 600 "$KF"; trap 'rm -f "$KF" "$KF.s" "$KF.t"' EXIT
security find-generic-password -ws opengateway 2>/dev/null | tr -d '\r\n' > "$KF"
[ -s "$KF" ] || die 2 "키체인에서 키를 읽지 못했다"

say "2/4 OCI 에서 opengateway 직접 호출 시험(값 출력 0)"
TEST="$(oc 40 'IFS= read -r OGK; R=$(curl -s -m 25 -o /tmp/.ocihm.out -w "%{http_code}" "'"$BASE"'/chat/completions" -H "Authorization: Bearer $OGK" -H "Content-Type: application/json" -d "{\"model\":\"'"$MODEL"'\",\"messages\":[{\"role\":\"user\",\"content\":\"한 글자로 답: 가\"}],\"max_tokens\":8}"); echo http=$R; echo reply_chars=$(python3 -c "import json;d=json.load(open(\"/tmp/.ocihm.out\"));print(len(d[\"choices\"][0][\"message\"][\"content\"] or \"\"))" 2>/dev/null || echo ERR); head -c 160 /tmp/.ocihm.out | grep -oiE "cloudflare|attention required|error[^,]{0,60}" | head -1; : > /tmp/.ocihm.out' < "$KF" 2>&1)" || die 3 "OCI 호출 시험 실행 실패: ${TEST}"
printf '%s\n' "$TEST" | sed 's/^/        /'
case "$TEST" in *"http=200"*) ;; *) die 3 "OCI 에서 opengateway 가 200 이 아니다 — OCI 설정은 바꾸지 않았다(위 http 값·메시지 확인)";; esac
case "$TEST" in *"reply_chars=ERR"*) die 3 "응답 형식을 못 읽었다 — OCI 설정은 바꾸지 않았다";; esac

say "3/4 백업 → 키 추가 → config.yaml 교체"
TS="$(date +%Y%m%d-%H%M%S)"
CH=$(cat <<'PYEOF'
import re,sys
p="/home/ubuntu/.hermes/config.yaml"
s=open(p,encoding="utf-8").read()
m=re.search(r"^model:\n((?:  .*\n)+)",s,re.M)
assert m, "model: 블록을 못 찾음"
blk=m.group(1)
def setkey(b,k,v):
    if re.search(r"^  %s:.*$"%k,b,re.M): return re.sub(r"^  %s:.*$"%k,"  %s: %s"%(k,v),b,flags=re.M)
    return b+"  %s: %s\n"%(k,v)
for k,v in (("default","MODEL_ID"),("provider","PNAME_ID"),("base_url","BASE_URL")): blk=setkey(blk,k,v)
s=s[:m.start(1)]+blk+s[m.end(1):]
assert not re.search(r"^providers:",s,re.M), "providers: 이미 있음"
if not s.endswith("\n"): s+="\n"
s+="\n# 2026-10-26 h-oci-hermes-opengateway: OpenGateway(openai 호환) — 로컬 pi 와 같은 base_url·모델 · 키는 .env 의 KENV_ID\nproviders:\n  PNAME_ID:\n    base_url: BASE_URL\n    key_env: KENV_ID\n"
open(p,"w",encoding="utf-8").write(s)
print("patched")
PYEOF
)
CH="${CH//MODEL_ID/$MODEL}"; CH="${CH//PNAME_ID/$PNAME}"; CH="${CH//BASE_URL/$BASE}"; CH="${CH//KENV_ID/$KENV}"
{
  cat "$KF"; printf '\n'
  cat <<REMOTE
H=\$HOME/.hermes
cp -p \$H/config.yaml \$H/config.yaml.bak-og-$TS && cp -p \$H/.env \$H/.env.bak-og-$TS || { echo BACKUP_FAIL; exit 1; }
echo backup=\$H/config.yaml.bak-og-$TS,\$H/.env.bak-og-$TS
grep -q '^$KENV=' \$H/.env || { printf '%s=%s\n' '$KENV' "\$OGK" >> \$H/.env; echo env_added=1; }
chmod 600 \$H/.env
python3 - <<'PYX'
$CH
PYX
python3 -c "import yaml;d=yaml.safe_load(open('/home/ubuntu/.hermes/config.yaml'));m=d['model'];print('yaml_ok model=',m.get('default'),'provider=',m.get('provider'),'providers=',list((d.get('providers') or {}).keys()))" || { echo YAML_FAIL; exit 2; }
REMOTE
} > "$KF.s"; chmod 600 "$KF.s"
# 첫 줄이 키(OGK 로 읽힘): 원격 스크립트 앞에 read 를 붙인다
{ printf 'IFS= read -r OGK\n'; cat "$KF.s"; } > "$KF.t"; chmod 600 "$KF.t"
OUT="$(timeout 60 ssh "${SO[@]}" "$OCI" 'bash -s' < "$KF.t" 2>&1)"; RC=$?; rm -f "$KF.s" "$KF.t"
printf '%s\n' "$OUT" | sed 's/^/        /'
[ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q "yaml_ok" || die 4 "설정 변경 실패(rc=$RC) — 위 출력 확인. 백업이 만들어졌다면 그대로 있다"

say "4/4 재시작 + 확인"
oc 40 'systemctl --user restart hermes-gateway; sleep 12; echo svc=$(systemctl --user is-active hermes-gateway); journalctl --user -u hermes-gateway --since "-90 sec" --no-pager 2>/dev/null | grep -iE "error|traceback|opengateway|model" | tail -4 | cut -c1-200; grep -c "403" $HOME/.hermes/logs/errors.log >/dev/null 2>&1; tail -2 $HOME/.hermes/logs/errors.log 2>/dev/null | cut -c1-160' 2>&1 | sed 's/^/        /'
say "완료 — 오빠 확인 1회: 슬랙에서 jarvis 봇에게 짧게 말을 걸어 답이 오는지 · 되돌리기: 위 backup= 두 파일을 cp 로 복원 + systemctl --user restart hermes-gateway"
exit 0
