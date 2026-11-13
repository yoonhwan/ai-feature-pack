#!/usr/bin/env bash
# ft-ledger-repo-sync.sh <사본 경로>   (r503 · 뉴스·매거진이 읽는 오빠 원장 «사본 체크아웃» 을 매 회 origin/main 으로 전진)
#   사본 = 읽기 전용 detached 체크아웃(예 <루트>/.worktrees/news-ledger-main). 뉴스(ft_news_ledger·ft_news_html)·매거진(magazine_from_news.sh)이 시작에서 부른다.
#   · 가지 위(symbolic-ref 성공) = 누군가의 작업 공간 → 전진 0 + ERROR rc3
#   · 추적 파일 미커밋 수정(status --porcelain -uno) → 전진 0 + ERROR rc3 (미추적 파일 = 뉴스 html 등은 «깨끗함»)
#   · r847: ls-remote(7초) 원격 main(+ r851 r3 원장 사본 브랜치) == 원격 추적 ref → fetch 0 · 아니면 fetch(이 스크립트만 시도당 30초 · 재시도 1 = 첫 시도 출력 0바이트만 · 총 70초 안) · 실패 → ERROR rc4
#   · HEAD == origin/main → `SYNC up-to-date` · 아니면 checkout --detach origin/main → `SYNC <옛 10자>..<새 10자>` rc0
#   출력 1줄(stdout) · 삭제 0 · 되돌림 = git -C <사본> checkout --detach <옛 sha> · exit 0 정상 · 2 usage · 3 전진 거절 · 4 fetch 실패 · 5 checkout 시간 부족(전진 0 · 다음 회차) · 1 그 밖
#   r1373 단계: --fetch-only = 가지 확인+ls-remote+fetch 만(«FETCH ok <origin/main 10자>») · --advance = 판정+checkout 만(advance 전체 마감 25초 · checkout 상한 = 남은 시간 − 유예 · 실측 최악 11.19초) · 없음 = 둘 다(옛 호출 호환)
#   r1373 죽은 checkout 흔적: 어긋난 경로가 전부 «작업 트리 = 전진 판 NEW 의 그 파일» 또는 «NEW 에도 작업 트리에도 없음»(미추적은 NEW 에 있는 경로만 · 조상·자손 충돌 = 흔적 아님)
#            → checkout -f --detach NEW + `RESUME <옛 10자>..<새 10자> 경로 N` rc0 · 하나라도 아니면 추적 변경 rc3(지금 문구) · 추적 변경 0 이면 일반 checkout(막히면 rc1 · r1348 알림)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft-merge-lib.sh"
MODE=all
case "${1:-}" in --fetch-only|--advance) MODE="${1#--}"; shift ;; esac
[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: $0 [--fetch-only|--advance] <사본 경로>" >&2; exit 2; }
REPO="$1"
ADVANCE_S=25  # r1373 — advance 단계 전체 마감(로컬 하네스 25초 · 원장 리포 56846 파일 실측: 평소 0.14~0.37초 · 빈 트리 전체 11.19초)
GRACE_S=3     # r1373 DA#10 R2 — 종료 유예 = SECONDS 정수(최대 1초 덜 셈) + TERM→KILL 1 + 끝 여유 1 → 바깥 25초가 checkout 중간을 먼저 끊지 않음
# r851 r3 ①③: 원장 사본 브랜치(FT_LEDGER_FILL_BRANCH · 기본 ledger/auto · ledger/ 로 시작하는 이름만 — 그 밖 = rc1 입구 거절) — main 과 «둘 다» 묻고 받는다(뉴스 ft_news_ledger.fetch_if_stale 와 같은 두 ref)
LBR="${FT_LEDGER_FILL_BRANCH:-ledger/auto}"
case "$LBR" in ledger/?*) git check-ref-format "refs/heads/$LBR" || { echo "ERROR 원장 사본 브랜치 이름 형식 틀림: $LBR"; exit 1; } ;;
  *) echo "ERROR 원장 사본 브랜치는 ledger/ 로 시작해야 함: $LBR (main·HEAD 등 거절)"; exit 1 ;; esac
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR ledger 사본이 git 체크아웃이 아니다: $REPO"; exit 1; }
if BR="$(git -C "$REPO" symbolic-ref -q --short HEAD)"; then
  echo "ERROR ledger 사본이 가지 $BR 위 — 전진 0 ($REPO)"; exit 3
fi
TB="$(fm_timeout_bin)" || { echo "ERROR timeout/gtimeout 없음 — 상한을 걸 수 없어 fetch 거절"; exit 4; }
gq() { git -c core.quotePath=false -C "$REPO" "$@"; }
# r1373 — 죽은 checkout 흔적 판정 · $1 = NEW · stdout = 흔적 경로 수 · rc0 전부 흔적 · rc1 흔적 아닌 것 있음 · rc2 흔적 후보 0(추적 어긋남 0 · NEW 에 있는 미추적 0)
half_trace() {
  local nw="$1" w rc; w="$(mktemp -d)" || return 1
  gq diff-index --cached --quiet HEAD -- || { rm -rf "$w"; return 1; }  # index 가 HEAD 와 다름 = 죽은 checkout 꼴 아님
  { gq diff-files --name-only | awk '{print "D\t" $0}' && gq ls-files --others --exclude-standard | awk '{print "U\t" $0}'; } > "$w/p" || { rm -rf "$w"; return 1; }
  cut -f2- "$w/p" | awk -v n="$nw" '{print n ":" $0}' | gq cat-file --batch-check='%(objecttype) %(objectname)' \
    | awk 'NF==2 && $1~/^(blob|tree|commit)$/ {print $1 "\t" $2; next} {print "none\t-"}' > "$w/t" \
    && [ "$(wc -l < "$w/t")" = "$(wc -l < "$w/p")" ] || { rm -rf "$w"; return 1; }  # git 실패 = 흔적 아님(덮어쓰기 0)
  cut -f2- "$w/p" | while IFS= read -r p; do { [ -f "$REPO/$p" ] || [ -L "$REPO/$p" ]; } && printf '%s\n' "$p"; done > "$w/e"
  [ -s "$w/e" ] && gq hash-object --stdin-paths < "$w/e" | paste "$w/e" - > "$w/h" || : > "$w/h"
  # 조상 경로: NEW 에 없는 미추적의 상위 폴더들 — 그중 하나라도 NEW 에서 파일이면 충돌
  paste "$w/p" "$w/t" | awk -F'\t' '$1=="U" && $3=="none" {n=split($2,a,"/"); s=""; for(i=1;i<n;i++){s=(i==1?a[1]:s "/" a[i]); print s}}' | sort -u > "$w/a"
  awk -v n="$nw" '{print n ":" $0}' "$w/a" | gq cat-file --batch-check='%(objecttype)' > "$w/at" || { rm -rf "$w"; return 1; }
  grep -qx blob "$w/at" && { rm -rf "$w"; return 1; }
  paste "$w/p" "$w/t" | awk -F'\t' -v hf="$w/h" 'FILENAME==hf {h[$1]=$2; next}
    { k=$1; ty=$3; ns=$4; ws=($2 in h) ? h[$2] : "-"
      if (k=="D") { c++; if (!((ty=="blob" && ws==ns) || (ty!="blob" && ws=="-"))) bad=1; next }
      if (ty=="blob") { c++; if (ws!=ns) bad=1 } else if (ty!="none") bad=1 }
    END { print c+0; exit (c==0 ? 2 : bad) }' "$w/h" -
  rc=$?; rm -rf "$w"; return "$rc"
}
checkout_new() {  # $1 = -f 또는 빈 값 · 상한 = advance 마감 남은 시간 − 유예 · 1초 미만 = checkout 0 rc5 · 실패 = rc1 1줄
  local out rc fake="${FT_LEDGER_ADV_ELAPSED:-0}" left  # FT_LEDGER_ADV_ELAPSED = 시험 전용 가짜 경과 초(숫자만)
  case "$fake" in ''|*[!0-9]*) fake=0 ;; esac
  left=$(( ADVANCE_S - (SECONDS - ADV0) - fake - GRACE_S ))
  [ "$left" -ge 1 ] || { echo "DEFER ledger 사본 checkout 시간 부족(남은 ${left}초 · 마감 ${ADVANCE_S}초) — 전진 0 · 다음 회차 ($REPO)"; exit 5; }
  out="$("$TB" -k 1 "$left" git -C "$REPO" checkout -q $1 --detach "$NEW" 2>&1)" && return 0
  rc=$?; case "$rc" in 124|137) out="상한 ${left}초 초과 — 다음 회차 RESUME 이 이어 끝냄${out:+ · ${out%%$'\n'*}}";; esac
  echo "ERROR ledger 사본 checkout 실패: ${out%%$'\n'*}"; exit 1
}
if [ "$MODE" != advance ]; then
# r847 — 원격 main sha(ls-remote 7초)가 사본 origin/main 과 같으면 fetch 0 · 묻기 실패는 fetch 로 진행(stderr 1줄)
#   fetch 는 이 스크립트만 시도당 30초(오빠 «뉴스는 30초로 상향») · TERM→1초 KILL(묶음) · 공용 fm_fetch 7초는 그대로
#   r847 r2: 단계 상한 = min(단계 상한, 남은 시간 − 유예) — SECONDS 는 정수(최대 1초 덜 셈) + TERM→KILL 유예 1 + 기동 여유 1 → «67 − SECONDS» · 0 이하 = 시작 0
#            재시도 1 = 첫 시도 stdout·stderr «둘 다 0바이트» 일 때만(파일 크기로 판정) · 출력이 있으면 그 첫 줄이 오류
cap() { local c=$(( 67 - SECONDS )); [ "$c" -gt "$1" ] && c="$1"; echo "$c"; }
C="$(cap 7)"
RAW="$([ "$C" -gt 0 ] && "$TB" -k 1 "$C" git -C "$REPO" ls-remote origin refs/heads/main "refs/heads/$LBR" 2>/dev/null)" || RAW=""
LS="$(printf '%s\n' "$RAW" | awk -F'\t' '$2=="refs/heads/main"{print $1; exit}')"
LSB="$(printf '%s\n' "$RAW" | awk -F'\t' -v r="refs/heads/$LBR" '$2==r{print $1; exit}')"
[ -n "$LS" ] || echo "WARN ls-remote 실패 — fetch 로 진행 ($REPO)" >&2
C="$(cap 7)"
LOCAL="$([ "$C" -gt 0 ] && "$TB" -k 1 "$C" git -C "$REPO" rev-parse --verify -q refs/remotes/origin/main 2>/dev/null)" || LOCAL=""
C="$(cap 7)"
LOCALB="$([ "$C" -gt 0 ] && "$TB" -k 1 "$C" git -C "$REPO" rev-parse --verify -q "refs/remotes/origin/$LBR" 2>/dev/null)" || LOCALB=""
if [ -z "$LS" ] || [ "$LS" != "$LOCAL" ] || [ "$LSB" != "$LOCALB" ]; then
  FO="$(mktemp)" FE="$(mktemp)" || { echo "ERROR ledger 사본 fetch 출력 임시 파일 못 만듦"; exit 4; }
  trap 'rm -f "$FO" "$FE"' EXIT
  ERR="fetch 시도 0"
  for TRY in 1 2; do
    CAP="$(cap 30)"
    [ "$CAP" -gt 0 ] || { ERR="총 마감 70초 안에 시도 못 함"; break; }
    "$TB" -k 1 "$CAP" git -c gc.auto=0 -C "$REPO" fetch --quiet origin main '+refs/heads/ledger/*:refs/remotes/origin/ledger/*' > "$FO" 2> "$FE" && { ERR=""; break; }
    RC=$?
    FIRST="$(head -n 1 "$FE")"; [ -n "$FIRST" ] || FIRST="$(head -n 1 "$FO")"
    case "$RC" in 124|137) ERR="시도 상한 ${CAP}초 초과${FIRST:+ · $FIRST}";; *) ERR="${FIRST:-rc=$RC 출력 없음}";; esac
    if [ -s "$FO" ] || [ -s "$FE" ]; then break; fi  # 출력이 있는 실패 = 확정 실패 · 재시도 0(첫 출력 전 실패만 재시도)
  done
  [ -z "$ERR" ] || { echo "ERROR ledger 사본 fetch 실패: $ERR"; exit 4; }
fi
if [ "$MODE" = fetch-only ]; then
  M="$(git -C "$REPO" rev-parse --verify -q 'origin/main^{commit}')" || { echo "ERROR ledger 사본에 origin/main 없음 ($REPO)"; exit 1; }
  echo "FETCH ok ${M:0:10}"; exit 0
fi
fi
ADV0=0; [ "$MODE" = all ] && ADV0=$SECONDS  # advance 마감 기준 = --advance 는 스크립트 시작 · 인자 없음은 fetch 끝
OLD="$(git -C "$REPO" rev-parse HEAD)" || exit 1
NEW="$(git -C "$REPO" rev-parse --verify -q 'origin/main^{commit}')" || { echo "ERROR ledger 사본에 origin/main 없음 ($REPO)"; exit 1; }
# 판 = 사본 브랜치가 main 을 품으면(앞섬) 그 브랜치 · 없거나 뒤처짐 = origin/main (뉴스 ft_ledger_fill_src.read_ref 와 같은 규칙)
if BRS="$(git -C "$REPO" rev-parse --verify -q "refs/remotes/origin/$LBR^{commit}")" && git -C "$REPO" merge-base --is-ancestor "$NEW" "$BRS"; then NEW="$BRS"; fi
if N="$(half_trace "$NEW")"; then
  checkout_new -f
  echo "RESUME ${OLD:0:10}..${NEW:0:10} 경로 $N"; exit 0
fi
DIRTY="$(git -C "$REPO" status --porcelain -uno 2>&1)" || { echo "ERROR ledger 사본 status 실패: ${DIRTY%%$'\n'*}"; exit 1; }
if [ -n "$DIRTY" ]; then
  N="$(printf '%s\n' "$DIRTY" | grep -c .)"
  FIRST="$(printf '%s\n' "$DIRTY" | head -1 | cut -c4-)"
  echo "ERROR ledger 사본 미커밋 추적 변경 $N — 전진 0 ($FIRST)"; exit 3
fi
[ "$OLD" = "$NEW" ] && { echo "SYNC up-to-date ${NEW:0:10}"; exit 0; }
checkout_new ""
echo "SYNC ${OLD:0:10}..${NEW:0:10}"
