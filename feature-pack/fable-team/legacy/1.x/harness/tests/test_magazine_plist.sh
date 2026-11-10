#!/usr/bin/env bash
# test_magazine_plist.sh — 설계 §9 시험 9: install-magazine.sh 치환 뒤 plutil -lint · Hour 8 Minute 0 · KeepAlive 없음 · RunAtLoad false
# + launchctl 0 (--load 없음) · .bak · ops/magazine 워크트리는 «없을 때만» 생성. HOME·BYZ_ROOT 를 임시로 바꿔 실 ~/.hermes·launchd 는 건드리지 않는다.
# r707 추가 칸: 예약 회차 3개(08:00·08:10·08:20) · magazine_from_news.sh 날짜당 1회 가드(올린 날 skip rc0 · 안 올린 날 진행 · 깨진 상태 rc7 · 재발행 표지 · --publish 없는 실행 불변) · 변이 2.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
INSTALL="$HERE/../../harness/kit/slack-mirror/install-magazine.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$INSTALL" && ok "bash -n install-magazine.sh" || bad "bash -n"

# launchctl 가짜 — 호출되면 기록한다 (--load 없이 불리면 실패)
mkdir -p "$T/bin" "$T/home" "$T/root"
printf '#!/usr/bin/env bash\necho "$@" >> "%s/launchctl.calls"\n' "$T" > "$T/bin/launchctl"; chmod +x "$T/bin/launchctl"

# 임시 리포 + 가짜 origin(main) — 워크트리 생성 시험용
git init -q --bare -b main "$T/origin.git"
git clone -q "$T/origin.git" "$T/root" 2>/dev/null
git -C "$T/root" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$T/root" push -q origin HEAD:main 2>/dev/null; git -C "$T/root" fetch -q

run() { HOME="$T/home" BYZ_ROOT="$T/root" GH_REPO="o/r" MAGAZINE_CHANNEL="C9" PATH="$T/bin:$PATH" bash "$INSTALL" "$@" 2>&1; }
OUT="$(run)"; rc=$?
[ $rc -eq 0 ] && ok "install rc=0" || { bad "install rc=$rc: $OUT"; }
P="$T/home/Library/LaunchAgents/com.byz.ft-magazine.plist"
[ -f "$P" ] && ok "plist 생성" || bad "plist 없음"
plutil -lint "$P" >/dev/null 2>&1 && ok "plutil -lint" || bad "plutil -lint"
[ "$(plutil -extract StartCalendarInterval.0.Hour raw "$P")" = "8" ] && ok "Hour 8" || bad "Hour"   # r707: 회차 배열(08:00·08:10·08:20)의 첫 칸
[ "$(plutil -extract StartCalendarInterval.0.Minute raw "$P")" = "0" ] && ok "Minute 0" || bad "Minute"
# r707 ⓐ 회차 3개 = 08:00·08:10·08:20 (StartCalendarInterval 배열 · 4번째 칸은 없음)
slots="$(for i in 0 1 2 3; do h="$(plutil -extract "StartCalendarInterval.$i.Hour" raw "$P" 2>/dev/null)" || break; printf '%02d:%02d ' "$h" "$(plutil -extract "StartCalendarInterval.$i.Minute" raw "$P")"; done)"
[ "$slots" = "08:00 08:10 08:20 " ] && ok "ⓐ 회차 3개 = 08:00 08:10 08:20" || bad "ⓐ 회차 '$slots'"
[ "$(plutil -extract RunAtLoad raw "$P")" = "false" ] && ok "RunAtLoad false" || bad "RunAtLoad"
plutil -extract KeepAlive raw "$P" >/dev/null 2>&1 && bad "KeepAlive 가 있다" || ok "KeepAlive 없음"
[ "$(plutil -extract Label raw "$P")" = "com.byz.ft-magazine" ] && ok "Label" || bad "Label"
[ "$(plutil -extract EnvironmentVariables.GH_REPO raw "$P")" = "o/r" ] && [ "$(plutil -extract EnvironmentVariables.MAGAZINE_CHANNEL raw "$P")" = "C9" ] && ok "환경값 치환" || bad "환경값"
[ "$(plutil -extract EnvironmentVariables.MAGAZINE_MALFORMED_CARDS raw "$P")" = "report" ] && ok "형식 미달 카드 opt-in(report)" || bad "MAGAZINE_MALFORMED_CARDS=report 없음"
grep -q '__[A-Z_]*__' "$P" && bad "미치환 토큰 남음" || ok "미치환 토큰 0"
# R184 ⓐ 08:00 예약 명령 = 발행 길(magazine_from_news.sh --publish) · --emit-model 단독 아님 · FT_ROOT 주입
grep -q "$T/home/.hermes/scripts/magazine_from_news.sh" "$P" && grep -q '<string>--publish</string>' "$P" && ok "ⓐ 예약 명령 = magazine_from_news.sh --publish" || bad "ⓐ 예약 명령이 발행 길이 아님"
grep -q -- '--emit-model' "$P" && bad "ⓐ 발행 예약에 --emit-model 이 남음(게시 0 모드)" || ok "ⓐ 발행 예약에 --emit-model 0"
[ "$(plutil -extract EnvironmentVariables.FT_ROOT raw "$P")" = "$T/root" ] && ok "ⓐ FT_ROOT 주입" || bad "ⓐ FT_ROOT"
PM="$T/home/Library/LaunchAgents/com.byz.ft-magazine-model.plist"
plutil -lint "$PM" >/dev/null 2>&1 && grep -q -- '--emit-model' "$PM" && grep -q "$T/root/.fable-team/state/sheet-story.json" "$PM" && ok "ⓐ 시트 모델 예약은 별 Label(--emit-model)" || bad "ⓐ 별 Label 예약"
[ -x "$T/home/.hermes/scripts/magazine_from_news.sh" ] && ok "magazine_from_news.sh 설치(+x)" || bad "magazine_from_news.sh 미설치"
[ -f "$T/home/.hermes/scripts/magazine_publish.py" ] && ok "모듈 복사" || bad "모듈 복사"
[ -f "$T/launchctl.calls" ] && bad "--load 없이 launchctl 호출됨" || ok "launchctl 호출 0"
[ -e "$T/root/.worktrees/ops-magazine/.git" ] && [ "$(git -C "$T/root/.worktrees/ops-magazine" rev-parse --abbrev-ref HEAD)" = "ops/magazine" ] && ok "ops/magazine 워크트리 생성" || bad "워크트리 생성"

# 멱등: 두 번째 실행은 .bak 을 남기고 워크트리는 그대로 둔다
OUT2="$(run)"; rc=$?
[ $rc -eq 0 ] && echo "$OUT2" | grep -q "worktree 있음" && ok "재실행: 워크트리 그대로" || bad "재실행 rc=$rc: $OUT2"
ls "$T/home/.hermes/scripts"/magazine_publish.py.bak-* >/dev/null 2>&1 && ok ".bak 생성" || bad ".bak 없음"

# --load 일 때만 launchctl
run --load >/dev/null
grep -q "bootstrap" "$T/launchctl.calls" 2>/dev/null && ok "--load 는 bootstrap 호출" || bad "--load 인데 bootstrap 없음"

# R184 ⓑ disabled 인데 --load → rc 1 + ERROR · enable/bootstrap 호출 0 (몰래 켜지 않는다)
: > "$T/launchctl.calls"
printf '#!/usr/bin/env bash\necho "$@" >> "%s/launchctl.calls"\n[ "$1" = print-disabled ] && printf "disabled services = {\\n\\t\\"com.byz.ft-magazine\\" => disabled\\n}\\n"\nexit 0\n' "$T" > "$T/bin/launchctl"
OUTD="$(run --load)"; rcd=$?
[ $rcd -eq 1 ] && echo "$OUTD" | grep -q 'ERROR 예약이 꺼져 있음(disabled): com.byz.ft-magazine' && ok "ⓑ disabled + --load → rc 1 + ERROR" || bad "ⓑ rc=$rcd: $OUTD"
grep -qE '^(enable|bootstrap|bootout)' "$T/launchctl.calls" && bad "ⓑ disabled 인데 enable/bootstrap/bootout 호출됨" || ok "ⓑ enable·bootstrap 호출 0"

# ── r707 ⓑ~ⓔ 날짜당 1회 가드 (magazine_from_news.sh) ──────────────────────────────
#   가드 판정은 magazine_doc.parse_args 로 읽는다 — 대역 doc.py 가 «진짜 파서» 를 그대로 쓴다(대역이 파서를 바꾸지 않는다).
#   원장 동기화·원장 신선도(r851)는 이 카드 범위 밖 — 동기화는 대역 스크립트, 신선도 게이트는 끔(FT_LEDGER_FRESH_GATE=0).
MFS="$HERE/../../harness/kit/slack-mirror/magazine_from_news.sh"
KITDIR="$(cd -- "$(dirname -- "$MFS")" && pwd)"
G="$T/g"; A="$G/state/a.json"; B="$G/state/b.json"
mkdir -p "$G/root/.fable-team" "$G/repo/design/teams/planner" "$G/state"
git -C "$G/repo" init -q -b main
echo "# 원장" > "$G/repo/design/teams/planner/PLAN-oppa-ledger.md"
git -C "$G/repo" add -A && git -C "$G/repo" -c user.email=t@t -c user.name=t commit -q -m ledger
printf '#!/usr/bin/env bash\necho sync >> "%s/sync.calls"\n' "$G" > "$G/sync.sh"
cat > "$G/doc.py" <<PY
import sys
sys.path.insert(0, r"$KITDIR")
import magazine_doc as _real
def parse_args(argv=None):
    return _real.parse_args(argv)
if __name__ == "__main__":  # 가드가 모듈로 import 할 때는 기록하지 않는다 — 기록 = 실제 실행 1회
    open(r"$G/doc.calls", "a").write(" ".join(sys.argv[1:]) + "\\n")
PY
dl() { [ -f "$G/doc.calls" ] && wc -l < "$G/doc.calls" | tr -d ' ' || echo 0; }
mfn() {  # $1 = 스크립트 · $2 = 상태 JSON(빈 문자 = 파일 없음) · 나머지 = 인자
  local S="$1" ST="$2"; shift 2
  rm -f "$G/doc.calls" "$G/sync.calls" "$A" "$B"
  [ -z "$ST" ] || printf '%s' "$ST" > "$A"
  FT_ROOT="$G/root" FT_LEDGER_REPO="$G/repo" FT_LEDGER_SYNC="$G/sync.sh" FT_LEDGER_FRESH_GATE=0 \
    FT_MAGAZINE_DOC="$G/doc.py" FT_NEWS_NOW="2026-10-22 08:10" \
    env ${REPUBLISH:+FT_MAGAZINE_REPUBLISH=1} bash "$S" "$@" 2>&1
}
sy() { [ -f "$G/sync.calls" ] && wc -l < "$G/sync.calls" | tr -d ' ' || echo 0; }
UP='{"aaa:p": {"root_ts": "1.1", "uploaded": true, "date": "2026-10-22"}}'
DOWN='{"aaa:p": {"root_ts": "1.1", "uploaded": false, "date": "2026-10-22"}}'
YDAY='{"aaa:p": {"root_ts": "1.1", "uploaded": true, "date": "2026-10-21"}}'
# guard 칸 11개 — $1 = 스크립트 · 실패 칸 수를 gfail 에 누적 · 상세는 FAIL 줄
guard_check() {
  local S="$1" tag="$2" out rc d s
  gfail=0
  out="$(mfn "$S" "$UP" --publish --state "$A")"; rc=$?; d="$(dl)"
  [ $rc -eq 0 ] && [ "$d" = 0 ] && [ "$(sy)" = 0 ] && printf '%s' "$out" | grep -q '^skip date=2026-10-22 이미 발행됨' \
    && echo "PASS ⓑ 올린 날 uploaded=True → skip rc0 · 발행 0 · 동기화 0" || { echo "FAIL ⓑ 올린 날 skip rc=$rc docs=$d out=$out"; gfail=$((gfail+1)); }
  out="$(mfn "$S" "$DOWN" --publish --state "$A")"; d="$(dl)"
  [ "$d" = 1 ] && echo "PASS ⓑ 같은 날 uploaded=False(업로드 실패 회차) → 다시 발행" || { echo "FAIL ⓑ uploaded=False 인데 docs=$d out=$out"; gfail=$((gfail+1)); }
  out="$(mfn "$S" "$YDAY" --publish --state "$A")"; d="$(dl)"
  [ "$d" = 1 ] && echo "PASS ⓑ 어제 발행 표식만 있음 → 오늘은 발행" || { echo "FAIL ⓑ 어제 표식인데 docs=$d out=$out"; gfail=$((gfail+1)); }
  out="$(mfn "$S" '' --publish --state "$A")"; d="$(dl)"
  [ "$d" = 1 ] && echo "PASS ⓑ 상태 파일 없음 → 발행" || { echo "FAIL ⓑ 상태 없음 docs=$d out=$out"; gfail=$((gfail+1)); }
  out="$(mfn "$S" 'not json' --publish --state "$A")"; rc=$?; d="$(dl)"
  [ $rc -eq 7 ] && [ "$d" = 0 ] && printf '%s' "$out" | grep -q 'ERROR magazine_from_news: 발행 상태 파일' \
    && echo "PASS ⓓ 상태 파일 깨짐 → ERROR rc7(조용한 skip 0 · 조용한 재발행 0)" || { echo "FAIL ⓓ 깨진 상태 rc=$rc docs=$d out=$out"; gfail=$((gfail+1)); }
  out="$(REPUBLISH=1 mfn "$S" "$UP" --publish --state "$A")"; d="$(dl)"
  [ "$d" = 1 ] && echo "PASS ⓔ FT_MAGAZINE_REPUBLISH=1 = 일부러 재발행" || { echo "FAIL ⓔ 재발행 표지 docs=$d out=$out"; gfail=$((gfail+1)); }
  out="$(mfn "$S" "$UP" --dry-run --state "$A")"; d="$(dl)"
  [ "$d" = 1 ] && [ "$(sy)" = 1 ] && echo "PASS ⓕ --publish 없는 실행(미리보기) → 가드 무관하게 그대로" || { echo "FAIL ⓕ 비발행 실행 docs=$d out=$out"; gfail=$((gfail+1)); }
  # D1 — 값 속에 든 «--publish»(경로)는 발행 플래그가 아니다 · 기준판처럼 진행(동기화 1 · 미리보기 1)
  out="$(mfn "$S" "$UP" --dry-run --out-dir "$G/out --publish output" --state "$A")"; rc=$?; d="$(dl)"; s="$(sy)"
  [ $rc -eq 0 ] && [ "$d" = 1 ] && [ "$s" = 1 ] \
    && echo "PASS D1 값 속 --publish 는 플래그 아니고 진행 · 동기화 1 · 미리보기 1" || { echo "FAIL D1 rc=$rc docs=$d sync=$s out=$out"; gfail=$((gfail+1)); }
  # D2 — argparse 줄임말 --pub 도 발행이다(올린 날 = skip rc0)
  out="$(mfn "$S" "$UP" --pub --state "$A")"; rc=$?; d="$(dl)"
  [ $rc -eq 0 ] && [ "$d" = 0 ] && printf '%s' "$out" | grep -q '^skip date=2026-10-22 이미 발행됨' \
    && echo "PASS D2 --pub = 발행 → 올린 날 skip rc0" || { echo "FAIL D2 rc=$rc docs=$d out=$out"; gfail=$((gfail+1)); }
  # D3 — --state 다른 파일을 보고 판정한다(그 파일에 올림 있음 = skip · 그 파일엔 없고 A 에만 올림 = 진행)
  rm -f "$G/doc.calls" "$G/sync.calls" "$A" "$B"; printf '%s' "$UP" > "$B"; printf '%s' "$DOWN" > "$A"
  out="$(FT_ROOT="$G/root" FT_LEDGER_REPO="$G/repo" FT_LEDGER_SYNC="$G/sync.sh" FT_LEDGER_FRESH_GATE=0 FT_MAGAZINE_DOC="$G/doc.py" FT_NEWS_NOW="2026-10-22 08:10" bash "$S" --publish --state "$B" 2>&1)"; rc=$?; d="$(dl)"
  [ $rc -eq 0 ] && [ "$d" = 0 ] && printf '%s' "$out" | grep -q '^skip date=2026-10-22 이미 발행됨' || { echo "FAIL D3a --state B 에 올림이 있는데 진행 rc=$rc docs=$d out=$out"; gfail=$((gfail+1)); }
  rm -f "$G/doc.calls" "$G/sync.calls" "$B"; printf '%s' "$UP" > "$A"
  out="$(FT_ROOT="$G/root" FT_LEDGER_REPO="$G/repo" FT_LEDGER_SYNC="$G/sync.sh" FT_LEDGER_FRESH_GATE=0 FT_MAGAZINE_DOC="$G/doc.py" FT_NEWS_NOW="2026-10-22 08:10" bash "$S" --publish --state "$B" 2>&1)"; rc=$?; d="$(dl)"
  if [ $rc -eq 0 ] && [ "$d" = 1 ]; then echo "PASS D3 --publish --state <다른 파일> 의 표식을 본다(둘 다)"; else echo "FAIL D3b --state B 는 비었는데 건너뜀 rc=$rc docs=$d out=$out"; gfail=$((gfail+1)); fi
  # ⓛ 판 날짜 = magazine_doc 이 고른 --date (없을 때만 지금 날짜) — 10-21 표식이면 skip · 10-22 표식만 있으면 진행
  out="$(mfn "$S" "$YDAY" --publish --date 2026-10-21 --state "$A")"; rc=$?; d="$(dl)"
  [ $rc -eq 0 ] && [ "$d" = 0 ] && printf '%s' "$out" | grep -q '^skip date=2026-10-21 이미 발행됨' \
    && echo "PASS ⓛ --date 2026-10-21 + 10-21 표식 → skip rc0" || { echo "FAIL ⓛ 앞 rc=$rc docs=$d out=$out"; gfail=$((gfail+1)); }
  out="$(mfn "$S" "$UP" --publish --date 2026-10-21 --state "$A")"; rc=$?; d="$(dl)"
  [ $rc -eq 0 ] && [ "$d" = 1 ] \
    && echo "PASS ⓛ --date 2026-10-21 + 10-22 표식만 → 진행(판 날짜를 따른다)" || { echo "FAIL ⓛ 뒤 rc=$rc docs=$d out=$out"; gfail=$((gfail+1)); }
  echo "CHECK $tag gfail=$gfail"
}
guard_check "$MFS" 본판; gn=$gfail
[ "$gn" = 0 ] && ok "ⓑ~ⓕ·D1~D3·ⓛ 날짜 가드 11칸(본판)" || bad "ⓑ~ⓕ·D1~D3·ⓛ 날짜 가드 본판 실패 ${gn}칸"
# 변이 4 — 옛 case 꼴(글자 모양) · 판 날짜를 --date 대신 지금 날짜로 · 날짜 비교/uploaded 조건 삭제
MB="$T/mut"; mkdir -p "$MB"
perl -0pe 's/if not getattr\(args, "publish", False\):/if " --publish " not in " " + " ".join(user) + " ":/' "$MFS" > "$MB/mut-case.sh"
sed 's/v.get("date") == date/True/' "$MFS" > "$MB/mut-date.sh"
sed 's/ and v.get("uploaded") is True//' "$MFS" > "$MB/mut-uploaded.sh"
perl -0pe 's/date = getattr\(args, "date", None\) or now_date/date = now_date/' "$MFS" > "$MB/mut-datesrc.sh"
for m in case date uploaded datesrc; do cmp -s "$MFS" "$MB/mut-$m.sh" && bad "변이 사본이 같다($m)"; done
ok "변이 사본 4종 생성"
guard_check "$MB/mut-case.sh" 변이1-옛case꼴 >/dev/null; gc1=$gfail
guard_check "$MB/mut-date.sh" 변이2-날짜비교삭제 >/dev/null; gc2=$gfail
guard_check "$MB/mut-uploaded.sh" 변이3-uploaded조건삭제 >/dev/null; gc3=$gfail
guard_check "$MB/mut-datesrc.sh" 변이4-판날짜무시 >/dev/null; gc4=$gfail
[ "$gc1" -ge 1 ] && ok "변이 1 옛 case 꼴(글자 모양) → FAIL ${gc1}칸" || bad "변이 1 안 잡힘"
[ "$gc2" -ge 1 ] && ok "변이 2 날짜 비교 삭제 → FAIL ${gc2}칸" || bad "변이 2 안 잡힘"
[ "$gc3" -ge 1 ] && ok "변이 3 uploaded 조건 삭제 → FAIL ${gc3}칸" || bad "변이 3 안 잡힘"
[ "$gc4" -ge 1 ] && ok "변이 4 가드 날짜를 지금 날짜로 고정 → FAIL ${gc4}칸" || bad "변이 4 안 잡힘"

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }