#!/usr/bin/env bash
# h-iap-old-keys-delete.sh — h7 성공 뒤, 쓰지 않는 «옛 키 2개»만 폐기한다(오빠 결정 · 상위 #3234). 실행은 오빠가 `! bash /tmp/h<N>` 로만. 먼저 계획: DRY=1
#   (2026-10-22 · aifp-multihost-master-claude#2 · 장부 docs/multihost/KEY-LEDGER-iap-tunnel-20261022.md)
#   지우는 것: 아래 OLD 2개 key_id 뿐(다른 키·서비스 계정·바인딩은 건드리지 않음).
#   안전장치: ① 호스트에 배치된 sa.json 의 key_id 가 NEW 와 같은지 먼저 확인(다르면 중단 — 쓰는 키를 지우지 않는다)
#            ② 지울 키가 현재 목록에 있는 것만 · NEW 는 절대 지우지 않음 · 지운 뒤 남은 키가 NEW 1개인지 확인
# rc: 0 성공 · 2 사전점검 실패 · 3 폐기 실패
# 되돌림: 없음(폐기된 키는 복구 불가 — 미사용이라 영향 0). 새 키가 필요하면 h-iap-tunnel-a1-rerun.sh(ROTATE) 로 재발급.
set -uo pipefail
P="${P:-byz-agents-484214}"; DOM="$P.iam.gserviceaccount.com"
ADMIN="${ADMIN:-developer.ts@byourz.com}"
DRY="${DRY:-0}"
OCI_KEY="${KEY:-$HOME/.ssh/oci_chuncheon}"
declare -A OLD=( [byz-mini-tunnel]=42ec5f53069f6d1203b2aba070268672e1fd1d77 [byz-oci-tunnel]=36bea09d30d515d64cd0a68e17608d8733346be8 )
declare -A NEW=( [byz-mini-tunnel]=e07046b7c932931950bf4215197413f4ef4f0748 [byz-oci-tunnel]=d9db6b342a0cd926c0ee3056d865e30ee22f77e0 )
say() { printf '[h-oldkeys] %s\n' "$*"; }
die() { printf '[h-oldkeys] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
G() { timeout 20 gcloud --account="$ADMIN" --project="$P" "$@"; }
hostkid() {  # hostkid <ssh-target> [ssh opts] → 호스트 sa.json 의 private_key_id (값 자체는 출력 0)
  local t="$1"; shift
  timeout 15 ssh -o BatchMode=yes -o ConnectTimeout=6 "$@" "$t" 'python3 -c "import json,os;print(json.load(open(os.path.expanduser(\"~/.config/byz-tunnel/sa.json\")))[\"private_key_id\"])"' 2>/dev/null
}

say "0/2 사전점검 (DRY=$DRY · 관리 계정 $ADMIN)"
declare -A HOSTKID
HOSTKID[byz-mini-tunnel]="$(hostkid mini)"
HOSTKID[byz-oci-tunnel]="$(hostkid oci -o IdentitiesOnly=yes -i "$OCI_KEY")"
for sa in byz-mini-tunnel byz-oci-tunnel; do
  [ "${HOSTKID[$sa]}" = "${NEW[$sa]}" ] || die 2 "$sa: 호스트에 배치된 키(${HOSTKID[$sa]:-읽기 실패})가 NEW(${NEW[$sa]})와 다르다 — 쓰는 키를 지우지 않으려고 중단"
  LIST="$(G iam service-accounts keys list --iam-account="$sa@$DOM" --managed-by=user --format='value(name.basename())' 2>&1)" || die 2 "$sa 키 목록 조회 실패"
  printf '%s\n' "$LIST" | grep -q "^${NEW[$sa]}$" || die 2 "$sa: NEW 키가 목록에 없다"
  if printf '%s\n' "$LIST" | grep -q "^${OLD[$sa]}$"; then say "        $sa: 폐기 대상 ${OLD[$sa]:0:8}… 존재 · 사용 중 키 ${NEW[$sa]:0:8}… 호스트 일치 ✓"; else say "        $sa: 폐기 대상 이미 없음(건너뜀)"; fi
done
[ "$DRY" = 1 ] && { say "DRY — 위 2개(존재하는 것만)를 폐기할 예정. 쓰기 0"; exit 0; }

say "1/2 폐기"
for sa in byz-mini-tunnel byz-oci-tunnel; do
  if G iam service-accounts keys list --iam-account="$sa@$DOM" --managed-by=user --format='value(name.basename())' 2>/dev/null | grep -q "^${OLD[$sa]}$"; then
    G iam service-accounts keys delete "${OLD[$sa]}" --iam-account="$sa@$DOM" --quiet >/dev/null 2>&1 || die 3 "$sa 옛 키 폐기 실패"
    say "        $sa 옛 키 ${OLD[$sa]:0:8}… 폐기"
  fi
done
say "2/2 확인 — 남은 사용자 키"
for sa in byz-mini-tunnel byz-oci-tunnel; do
  R="$(G iam service-accounts keys list --iam-account="$sa@$DOM" --managed-by=user --format='value(name.basename())' 2>/dev/null)"
  say "        $sa: $(printf '%s' "$R" | tr '\n' ' ')"
  [ "$R" = "${NEW[$sa]}" ] || die 3 "$sa 남은 키가 NEW 1개가 아니다"
done
say "완료 rc=0 — 옛 키 폐기, 사용 중 키 2개만 남음"
exit 0
