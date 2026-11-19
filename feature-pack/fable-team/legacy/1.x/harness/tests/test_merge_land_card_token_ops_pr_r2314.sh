#!/usr/bin/env bash
# test_merge_land_card_token_ops_pr_r2314.sh — r2314: ops 팀 손 PR(가지 ops/<slug>-<N> · 제목 r<N> 0)도 제목 «card:<카드 이름>» 표지로 카드 착지 줄을 쓴다 · BYZ 착지 토큰 0 = WARN 1줄
#   fm_card_tokens · fm_card_only · fm_land_card_line · fm_land_turn_first · fm_land_notify_land 직접(source) · 가짜 카드 리포(cards.git ops/main-base · design/teams/ops/indices)
#   실 gh·실 리포·네트워크 0 · sleep 0 · 반례 ①~⑭ · ⑫b(카드 r2314 동결 · ⑩ = 기존 시험 목록 재실행은 따로) · 변이 M1~M7 = 사본 bin + 원본 대조
#   FT_R2314_BIN = 다른 bin(기준판) 주입 · 그때 변이 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "${FT_R2314_BIN:-$HERE/../bin}" && pwd -P)" || { echo "판정 불가 — bin 없음(${FT_R2314_BIN:-})"; exit 2; }; KIT="$HERE/../kit/fable-team/bin"; T0=$SECONDS
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; OUT=""
ck() { local l="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $l"; else echo "FAIL $l :: out=[${OUT:0:500}]"; fail=$((fail + 1)); fi; }
miss() { ! "$@"; }
gq() { git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "${@:2}"; }

# 가짜 카드 리포: cards.git(ops/main-base) + clone C(= 카드 루트 · directive-roots.tsv ops 행)
CB="$T/cards.git"; C="$T/croot"; IX="design/teams/ops/indices"; HX="design/harness/indices"
git init -q --bare -b ops/main-base "$CB"; git clone -q "$CB" "$C" 2>/dev/null; gq "$C" checkout -q -b ops/main-base
mkdir -p "$C/$IX/대기" "$C/$HX/대기" "$C/.fable-team/state"
printf 'ops\t.\torigin/ops/main-base\t%s\n' "$IX" > "$C/.fable-team/state/directive-roots.tsv"
printf '/.fable-team/\n' >> "$C/.git/info/exclude"
for s in ops-cfo-super-operator-dev ops-login-rt-concurrency ops-a ops-b ops-c ops-r2244-follow; do printf '# 카드 %s\n\n## 상태\n- 대기\n' "$s" > "$C/$IX/대기/$s.md"; done
printf '# 카드\n\n## 상태\n- 대기\n' > "$C/$HX/대기/r2244-card-read-write-byte-cap.md"
gq "$C" add -A && gq "$C" commit -qm seed && gq "$C" push -q origin ops/main-base
export FT_ROOT="$C" FT_AUTONOMY_STATE_DIR="$T/state" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
lands() { git -C "$CB" show "ops/main-base:$1" 2>/dev/null | grep -c '^- 착지:'; }   # lands <카드 경로> = 원격 카드 ref 의 착지 줄 수

# 착지 리포 P: M(기준) → Qx(indices 밖 1개 + 카드) · Qc(카드 파일만)
P="$T/pack"; git init -q -b main "$P"; echo a > "$P/a"; gq "$P" add -A; gq "$P" commit -qm m; M="$(git -C "$P" rev-parse HEAD)"
mkdir -p "$P/design/teams/ops/plans" "$P/$IX/대기"; echo x > "$P/design/teams/ops/plans/PLAN-a.sh"; echo x > "$P/$IX/대기/ops-a.md"
gq "$P" add -A; gq "$P" commit -qm qx; QX="$(git -C "$P" rev-parse HEAD)"
gq "$P" checkout -q -B c "$M"; mkdir -p "$P/$IX/대기"; echo y > "$P/$IX/대기/ops-a.md"; gq "$P" add -A; gq "$P" commit -qm qc; QC="$(git -C "$P" rev-parse HEAD)"

tok() { OUT="$(. "$1/ft-merge-lib.sh" && fm_card_tokens "$2" "$3")"; }   # tok <bin> <가지> <제목>
line() {  # line <bin> <Q> <M→Q 판정 0|1|빈> <가지> <제목> → OUT = fm_land_card_line 출력(카드 ref 실제 push)
  OUT="$(. "$1/ft-merge-lib.sh" && { case "$3" in '') unset FM_CARD_ONLY;; *) fm_card_only "$P" "$M" "$2" >/dev/null; [ "$FM_CARD_ONLY" = "$3" ] || { echo "FM_CARD_ONLY=$FM_CARD_ONLY ≠ $3"; exit 1; };; esac
    fm_land_card_line "$C" 77 "$2" "$5" "$4" pack main; } 2>&1)"
}
T1="[chore] ops 계획: cfo 슈퍼 운영 card:ops-cfo-super-operator-dev"
c1() { line "$1" "$QX" 0 ops/cfo-super-operator-dev-122 "$T1"; [[ "$OUT" == "DONE 카드 착지 줄 ops-cfo-super-operator-dev "* ]] && [ "$(lands "$IX/대기/ops-cfo-super-operator-dev.md")" = 1 ]; }
c1t() { tok "$1" ops/cfo-super-operator-dev-122 "$T1"; [ "$OUT" = ops-cfo-super-operator-dev ]; }
c2() { line "$1" "$QX" 0 ops/cfo-super-operator-dev-122 "[chore] ops 계획: cfo 슈퍼 운영"; [ "$OUT" = "WARN 카드 토큰 0 — PR #77 제목에 card:<카드 이름> 없음 · 착지 줄 쓰기 0" ]; }
c3() { tok "$1" nano/ops-login-rt-concurrency "[chore] login rt"; [ "$OUT" = ops-login-rt-concurrency ] || return 1
  line "$1" "$QX" 0 nano/ops-login-rt-concurrency "[chore] login rt"; [[ "$OUT" == "DONE 카드 착지 줄 ops-login-rt-concurrency "* ]] && [ "$(lands "$IX/대기/ops-login-rt-concurrency.md")" = 1 ]; }
c4() { tok "$1" nano/r2244-card-read-write-byte-cap "[fix] 꼬리 card:ops-x"; [ "$OUT" = r2244 ]; }
c5() { tok "$1" docs/x "r2310 묶음 card:ops-a card:ops-a"; [ "$OUT" = "r2310 ops-a" ]; }
c6a() { tok "$1" docs/x "[docs] discard:ops-a"; [ -z "$OUT" ]; }
c6b() { tok "$1" docs/x "[docs] card:Ops-A"; [ -z "$OUT" ]; }
c6c() { tok "$1" docs/x "[docs] card:-x"; [ -z "$OUT" ]; }
c6d() { tok "$1" docs/x "[docs] (card:ops-a) card:ops-b)"; [ "$OUT" = "ops-a ops-b" ]; }   # 경계 ( ) 는 표지 앞뒤로 받음
c7() { line "$1" "$QC" 1 ops/x-1 "[docs] 카드만"; [ "$OUT" = "SKIP 카드 파일만 바꾼 PR #77 — 카드 착지 줄 쓰기 0" ]; }
c8() { line "$1" "$QX" 0 planner/verdict-12 "[docs] planner 판정 12"; [ "$OUT" = "SKIP 카드 없음 — 카드 토큰 0(카드 착지 줄 쓰기 0)" ]; }
c8e() { line "$1" "$QX" "" ops/x-1 "[docs] 판정 안 부름"; [ "$OUT" = "SKIP 카드 없음 — 카드 토큰 0(카드 착지 줄 쓰기 0)" ]; }   # FM_CARD_ONLY 빈 값(옛 호출) = 옛 SKIP
c9() { line "$1" "$QX" 0 ops/none-1 "[chore] ops 계획 card:ops-none"; [[ "$OUT" == "SKIP 카드 없음 — 토큰 ops-none 카드 0장"* ]]; }
c11() { line "$1" "$QX" 0 docs/plan-a-x "[chore] ops 계획 a card:ops-a"; [[ "$OUT" == "DONE 카드 착지 줄 ops-a "* ]] && [ "$(lands "$IX/대기/ops-a.md")" = 1 ]; }
c12() { line "$1" "$QX" 0 ops/main-base "[chore] ops 계획 b card:ops-b"; [[ "$OUT" == "DONE 카드 착지 줄 ops-b "* ]] && [ "$(lands "$IX/대기/ops-b.md")" = 1 ]; }
c12b() { line "$1" "$QC" 1 docs/x "[docs] 카드 c card:ops-c"; [ "$OUT" = "SKIP 카드 파일만 바꾼 PR #77 — 카드 착지 줄 쓰기 0" ] && [ "$(lands "$IX/대기/ops-c.md")" = 0 ]; }
c13t() { tok "$1" docs/x "[docs] 후속 card:ops-r2244-follow"; [ "$OUT" = ops-r2244-follow ]; }
c13() { line "$1" "$QX" 0 docs/x "[docs] 후속 card:ops-r2244-follow"; [[ "$OUT" == "DONE 카드 착지 줄 ops-r2244-follow "* ]] && [ "$(lands "$HX/대기/r2244-card-read-write-byte-cap.md")" = 0 ]; }
c14() {  # 장부 cards · 착지 알림 카드 칸(fm_land_turn_ledger · fm_land_notify 대역 = 받은 인자만 찍음)
  OUT="$(. "$1/ft-merge-lib.sh" && fm_land_turn_ledger() { shift 3; printf 'L %s\n' "$*"; } && fm_land_notify() { shift 1; printf 'N %s\n' "$*"; } && fm_land_turn_notify() { :; } \
    && FM_CARD_ONLY=0 && fm_land_turn_first "$C" 77 ops/cfo-super-operator-dev-122 "$T1" && fm_land_notify_land "$C" 77 abc "$T1" 0 "OK n=1" ops/cfo-super-operator-dev-122 2>/dev/null)"
  grep -qx 'L ops-cfo-super-operator-dev' <<<"$OUT" && grep -q "^N \[착지\] pr=77 sha=abc 카드 ops-cfo-super-operator-dev · 설치 OK $C/$IX/대기/ops-cfo-super-operator-dev.md$" <<<"$OUT"
}

reset_cards() { gq "$C" fetch -q origin; gq "$C" reset -q --hard origin/ops/main-base; gq "$C" push -q -f origin "$(git -C "$C" rev-list --max-parents=0 HEAD):refs/heads/ops/main-base"; }   # 원격 카드 ref = seed 로(변이마다 줄 0 에서)
cases() {  # cases <bin> <머리>
  ck "$2① ops/<slug>-<N> · 제목 card: → 토큰 = 카드 이름" c1t "$1"
  ck "$2① 착지 줄 1커밋" c1 "$1"
  ck "$2② 제목 card: 0 → WARN 1줄 · 쓰기 0" c2 "$1"
  ck "$2③ nano/<stem> · card: 0 → stem 토큰 · 줄 씀" c3 "$1"
  ck "$2④ 가지 r<N> 우선 → 토큰 r2244 하나" c4 "$1"
  ck "$2⑤ r2310 + card: 중복 → r2310 ops-a" c5 "$1"
  ck "$2⑥ discard: → 토큰 0" c6a "$1"; ck "$2⑥ card:Ops-A → 토큰 0" c6b "$1"; ck "$2⑥ card:-x → 토큰 0" c6c "$1"; ck "$2⑥ ( ) 경계 받음" c6d "$1"
  ck "$2⑦ 카드 파일만 PR · 토큰 0 → SKIP 카드 파일만 · WARN 0" c7 "$1"
  ck "$2⑧ planner/verdict-12 · 토큰 0 → WARN 0" c8 "$1"
  ck "$2⑧ FM_CARD_ONLY 빈 값 → 옛 SKIP · WARN 0" c8e "$1"
  ck "$2⑨ card:ops-none → SKIP 카드 0장 그대로" c9 "$1"
  ck "$2⑪ docs/<임의> · indices 밖 1개 · card:ops-a → 착지 줄 1커밋" c11 "$1"
  ck "$2⑫ ops/main-base · card:ops-b → 착지 줄 1커밋" c12 "$1"
  ck "$2⑫b 카드 파일만 · card:ops-c → SKIP · 줄 0 · WARN 0" c12b "$1"
  ck "$2⑬ card:ops-r2244-follow → 토큰 그 하나(r2244 0)" c13t "$1"
  ck "$2⑬ 착지 줄 = follow 카드 · r2244 카드 0" c13 "$1"
  ck "$2⑭ 장부 cards · 알림 카드 칸 = ops 카드" c14 "$1"
}
echo "### 반례 (bin=$BIN)"; S0=$SECONDS
cases "$BIN" ""
echo "단계 반례: $((SECONDS - S0))초"

echo "### 변이(사본 · 원본 대조)"; S1=$SECONDS
mut() {  # mut <이름> <옛 글자> <새 글자> [<옛> <새>…] — 사본 bin 에서 쌍마다 정확히 1곳
  local n="$1"; shift; rm -rf "${T:?}/${n:?}"; cp -R "$BIN" "$T/$n"; rm -rf "$T/$n/__pycache__"
  python3 - "$T/$n/ft-merge-lib.sh" "$@" <<'PY' || { echo "FAIL $n 변이 못 끼움"; fail=$((fail + 1)); return 1; }
import sys
p, pr = sys.argv[1], sys.argv[2:]; s = open(p, encoding="utf-8").read()
for a, b in zip(pr[::2], pr[1::2]):
    if s.count(a) != 1: sys.exit(1)
    s = s.replace(a, b)
open(p, "w", encoding="utf-8").write(s)
PY
}
mc() {  # mc <변이> <사례> <설명> — 변이 사본 = 잡힘(FAIL) · 원본 = PASS(같은 사례 · 카드 ref 는 매번 seed)
  reset_cards; ck "$1 $3 → $2 잡힘" miss "$2" "$T/$1"; reset_cards; ck "$1 원본 대조 $2" "$2" "$BIN"
}
WARN_L='echo "WARN 카드 토큰 0 — PR #$pr 제목에 card:<카드 이름> 없음 · 착지 줄 쓰기 0"'
if [ -z "${FT_R2314_BIN:-}" ]; then
  mut M1 '; sed -n '"'"'s/^c //p'"'"' <<<"$sp"; }' '; }' && mc M1 c1 "card: 갈래 지움"
  mut M2 "$WARN_L" 'echo "SKIP 카드 없음 — 카드 토큰 0(카드 착지 줄 쓰기 0)"' && mc M2 c2 "WARN 을 SKIP 으로"
  mut M3 '{ printf '"'"'%s'"'"' "${t%-}"; return 0; }' 'printf '"'"'%s '"'"' "${t%-}"' && mc M3 c4 "가지 우선 지움"
  mut M4 '/[ (]card:' '/.card:' && mc M4 c6a "card: 앞 경계 지움"
  mut M5 '1) echo "SKIP 카드 파일만 바꾼 PR #$pr — 카드 착지 줄 쓰기 0"; return 0;;' '' '[ "${FM_CARD_ONLY:-}" = 0 ] && ' '' && { mc M5 c7 "FM_CARD_ONLY 조건 지움"; mc M5 c12b "FM_CARD_ONLY 조건 지움"; }
  mut M6 '! [[ "$head" == planner/verdict-* ]]' ':' && mc M6 c8 "planner/verdict 조건 지움"
  mut M7 'sed -n '"'"'s/^r //p'"'"' <<<"$sp"' 'printf '"'"'%s\n'"'"' "${2:-}"' && mc M7 c13t "r<N> 셈 전 card: 덩이 빼기 지움"
else echo "SKIP 변이(기준판 주입)"; fi
echo "단계 변이: $((SECONDS - S1))초"

echo "### 짝 사본"
ck "bin·kit cmp0(ft-merge-lib.sh)" cmp -s "$HERE/../bin/ft-merge-lib.sh" "$KIT/ft-merge-lib.sh"
echo "단계별 초: 전체 $((SECONDS - T0))"
printf '### 결과: %s\n' "$([ "$fail" = 0 ] && echo PASS || echo "FAIL $fail")"
[ "$fail" = 0 ]
