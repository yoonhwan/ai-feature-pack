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
#   magazine_doc.py --state 기본값과 같은 ~/.hermes/state/magazine-doc.json 을 FT_MAGAZINE_STATE 대역으로 쓴다.
#   원장 동기화·원장 신선도(r851)는 이 카드 범위 밖 — 동기화는 대역 스크립트, 신선도 게이트는 끔(FT_LEDGER_FRESH_GATE=0).
MFS="$HERE/../../harness/kit/slack-mirror/magazine_from_news.sh"
G="$T/g"; mkdir -p "$G/root/.fable-team" "$G/repo/design/teams/planner" "$G/state"
git -C "$G/repo" init -q -b main
echo "# 원장" > "$G/repo/design/teams/planner/PLAN-oppa-ledger.md"
git -C "$G/repo" add -A && git -C "$G/repo" -c user.email=t@t -c user.name=t commit -q -m ledger
printf '#!/usr/bin/env bash\necho sync >> "%s/sync.calls"\n' "$G" > "$G/sync.sh"
printf 'import sys\nopen("%s/doc.calls","a").write(" ".join(sys.argv[1:])+"\\n")\n' "$G" > "$G/doc.py"
dl() { [ -f "$G/doc.calls" ] && wc -l < "$G/doc.calls" | tr -d ' ' || echo 0; }
mfn() {  # $1 = 스크립트 · $2 = 상태 JSON(빈 문자 = 파일 없음) · 나머지 = 인자
  local S="$1" ST="$2"; shift 2
  rm -f "$G/doc.calls" "$G/sync.calls" "$G/state/magazine-doc.json"
  [ -z "$ST" ] || printf '%s' "$ST" > "$G/state/magazine-doc.json"
  FT_ROOT="$G/root" FT_LEDGER_REPO="$G/repo" FT_LEDGER_SYNC="$G/sync.sh" FT_LEDGER_FRESH_GATE=0 \
    FT_MAGAZINE_DOC="$G/doc.py" FT_MAGAZINE_STATE="$G/state/magazine-doc.json" FT_NEWS_NOW="2026-10-22 08:10" \
    env ${REPUBLISH:+FT_MAGAZINE_REPUBLISH=1} bash "$S" "$@" 2>&1
}
gfail=0
# guard 칸 7개 — $1 = 스크립트 · 실패 칸 수를 gfail 에 누적 · 상세는 FAIL 줄
guard_check() {
  local S="$1" tag="$2" out rc d
  gfail=0
  out="$(mfn "$S" '{"aaa:p": {"root_ts": "1.1", "uploaded": true, "date": "2026-10-22"}}' --publish)"; rc=$?; d="$(dl)"
  [ $rc -eq 0 ] && [ "$d" = 0 ] && [ ! -f "$G/sync.calls" ] && printf '%s' "$out" | grep -q '^skip date=2026-10-22 이미 발행됨' \
    && echo "PASS ⓑ 올린 날 uploaded=True → skip rc0 · 발행 0 · 동기화 0" || { echo "FAIL ⓑ 올린 날 skip rc=$rc docs=$d out=$out"; gfail=$((gfail+1)); }
  out="$(mfn "$S" '{"aaa:p": {"root_ts": "1.1", "uploaded": false, "date": "2026-10-22"}}' --publish)"; d="$(dl)"
  [ "$d" = 1 ] && echo "PASS ⓑ 같은 날 uploaded=False(업로드 실패 회차) → 다시 발행" || { echo "FAIL ⓑ uploaded=False 인데 docs=$d out=$out"; gfail=$((gfail+1)); }
  out="$(mfn "$S" '{"aaa:p": {"root_ts": "1.1", "uploaded": true, "date": "2026-10-21"}}' --publish)"; d="$(dl)"
  [ "$d" = 1 ] && echo "PASS ⓑ 어제 발행 표식만 있음 → 오늘은 발행" || { echo "FAIL ⓑ 어제 표식인데 docs=$d out=$out"; gfail=$((gfail+1)); }
  out="$(mfn "$S" '' --publish)"; d="$(dl)"
  [ "$d" = 1 ] && echo "PASS ⓑ 상태 파일 없음 → 발행" || { echo "FAIL ⓑ 상태 없음 docs=$d out=$out"; gfail=$((gfail+1)); }
  out="$(mfn "$S" 'not json' --publish)"; rc=$?; d="$(dl)"
  [ $rc -eq 7 ] && [ "$d" = 0 ] && printf '%s' "$out" | grep -q 'ERROR magazine_from_news: 발행 상태 파일' \
    && echo "PASS ⓓ 상태 파일 깨짐 → ERROR rc7(조용한 skip 0 · 조용한 재발행 0)" || { echo "FAIL ⓓ 깨진 상태 rc=$rc docs=$d out=$out"; gfail=$((gfail+1)); }
  out="$(REPUBLISH=1 mfn "$S" '{"aaa:p": {"root_ts": "1.1", "uploaded": true, "date": "2026-10-22"}}' --publish)"; d="$(dl)"
  [ "$d" = 1 ] && echo "PASS ⓔ FT_MAGAZINE_REPUBLISH=1 = 일부러 재발행" || { echo "FAIL ⓔ 재발행 표지 docs=$d out=$out"; gfail=$((gfail+1)); }
  out="$(mfn "$S" '{"aaa:p": {"root_ts": "1.1", "uploaded": true, "date": "2026-10-22"}}' --dry-run)"; d="$(dl)"
  [ "$d" = 1 ] && echo "PASS ⓕ --publish 없는 실행(미리보기) → 가드 무관하게 그대로" || { echo "FAIL ⓕ 비발행 실행 docs=$d out=$out"; gfail=$((gfail+1)); }
  echo "CHECK $tag gfail=$gfail"
}
guard_check "$MFS" 본판; gn=$gfail
[ "$gn" = 0 ] && ok "ⓑ~ⓕ 날짜 가드 7칸(본판)" || bad "ⓑ~ⓕ 날짜 가드 본판 실패 ${gn}칸"
# ⓔ 변이 2 — 날짜 비교 삭제 = 어제 표식 칸 FAIL · uploaded 조건 삭제 = uploaded=False 칸 FAIL
MB="$T/mut"; mkdir -p "$MB"
sed 's/v.get("date") == date/True/; s/ and v.get("uploaded") is True//' "$MFS" > "$MB/mut-both.sh"
cmp -s "$MFS" "$MB/mut-both.sh" && bad "변이 0(사본이 같다)" || ok "변이 사본 생성"
sed 's/v.get("date") == date/True/' "$MFS" > "$MB/mut-date.sh"
sed 's/ and v.get("uploaded") is True//' "$MFS" > "$MB/mut-uploaded.sh"
guard_check "$MB/mut-date.sh" 변이1-날짜비교삭제 >/dev/null; g1=$gfail
guard_check "$MB/mut-uploaded.sh" 변이2-uploaded조건삭제 >/dev/null; g2=$gfail
[ "$g1" -ge 1 ] && ok "변이 1 날짜 비교 삭제 → FAIL ${g1}칸" || bad "변이 1 안 잡힘"
[ "$g2" -ge 1 ] && ok "변이 2 uploaded 조건 삭제 → FAIL ${g2}칸" || bad "변이 2 안 잡힘"

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }