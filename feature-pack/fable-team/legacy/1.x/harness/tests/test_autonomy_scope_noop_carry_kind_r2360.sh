#!/usr/bin/env bash
# test_autonomy_scope_noop_carry_kind_r2360.sh — r2360 범위 승인 재사용(SCOPE-NOOP)이 «처음 판정의 class·learned» 를 실어 try --land 가 «kind 판독 불가» 로 닫히지 않는다
#   계약 = K1 NOOP 분류 실음 · K2 원장 줄 못 읽음(닫힌 쪽) · K3 try 판독 · K4 다른 길 그대로 · 반례 ①~⑨ · 변이 M1~M6 · 기준판(origin/main) Red = ① · ⑤
#   격리: 임시 FT_ROOT·STATE(실 상태 0) · FT_NOW 고정 시계 · 가짜 분류기·슬랙 게시·gh base · 가짜 ft-merge-land(호출만 기록) — 실 원격·실 gh·실 슬랙·실 착지 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"   # T·S·LOG·AP·T0·a()·run()·grant()·sha()·lines() + 이 파일의 onfix()
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/fake_gh_base.sh"; fake_gh_base "$T/ghb"   # --pr 의 PR base 조회(autonomy_pr_target) = 가짜 gh(main)
fail=0; rc=0; out=""; el=0; BASE=""; BASE_OK=0; NOW=$T0
export FT_AUTONOMY_LEVEL=each
s0() { S0=$SECONDS; }
ck() { el=$((SECONDS - S0)); if [ "$2" = 0 ]; then echo "PASS $1 [t=${el}s]"; else echo "FAIL $1 [t=${el}s] :: rc=$rc out=${out:0:320}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
onfix() {  # 상태를 픽스처가 직접 쓴다(r1577 꼴) — `a on` 의 사전 점검을 매 사례마다 돌리지 않는다
  rm -rf "$S"; mkdir -p "$S"; printf '%s\ton\tA1\n' "$T0" > "$LOG"
  printf '{"mode":"on","since":%s,"event":"A1","until":null,"level":"each"}\n' "$T0" > "$S/autonomy.json"; }
land_n() { [ -f "$T/land.log" ] && wc -l < "$T/land.log" | tr -d ' ' || echo 0; }

# ── 도구 판(러너) = bin 사본 + 가짜 ft-merge-land · 기준판(base) = origin/main 두 파일 · 변이(mut) = 도구 판에서 한 파일만 바꾼 것
mkr() { local d="$1" f; for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done; rm -f "$d/ft-merge-land.sh"; cp "$T/land-stub.sh" "$d/ft-merge-land.sh"; }   # rm 먼저 — 심링크 너머 실 파일을 덮지 않는다
printf '#!/usr/bin/env bash\necho "LAND $*" >> "%s/land.log"\necho "LANDED 대역"\n' "$T" > "$T/land-stub.sh"; chmod +x "$T/land-stub.sh"
RUN="$T/run"; mkdir -p "$RUN"; mkr "$RUN"; rm -f "$RUN/ft-autonomy.sh"; cp "$BIN/ft-autonomy.sh" "$RUN/ft-autonomy.sh"
a()  { FT_NOW="$NOW" "$BASH" "${ABIN:-$RUN}/ft-autonomy.sh" "$@"; }   # ABIN = 기준판·변이 판
fx_base() {  # 기준판(origin/main) 사본 — ①·⑤ Red 대조 · 못 만들면 BASE_OK=0
  local RP REL f; BASE="$T/base"; mkdir -p "$BASE"; mkr "$BASE"
  RP="$(git -C "$BIN" rev-parse --show-toplevel 2>/dev/null)"; REL="$(cd "$BIN" && pwd -P)"; REL="${REL#"$RP"/}"
  for f in ft-autonomy-scope.sh ft-autonomy-try.sh; do
    rm -f "$BASE/$f" && git -C "$RP" show "origin/main:$REL/$f" > "$BASE/$f" || return 0
  done; BASE_OK=1; }
mut() {  # mut <이름> <파일> <원문> <바꿀 글> — 도구 판 사본에서 그 글자 1곳만 바꾼다
  local mb="$T/mut-$1" f t; rm -rf "$mb"; mkdir -p "$mb"; for f in "$RUN"/*; do t="$(readlink "$f")"; ln -s "${t:-$f}" "$mb/$(basename "$f")"; done
  rm -f "$mb/$2"; python3 - "$RUN/$2" "$mb/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1, sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
}
# 원장 픽스처 — grant 줄(범위 S<n>)·scope-use 줄(처음 판정)을 직접 쓴다(쓰기 경로 = 기존 명령 그대로 본다)
sgr() { printf 'approve-scope %s A1 %s until=%s max=30 daily=15 classes=%s codemax=5 repos=byz,pack\n' "$1" "$T0" "$((T0 + 3600))" "$2" >> "$LOG"; }
use() { printf 'scope-use %s %s %s %s%s\n' "$1" "$2" "$3" "$T0" "${4:-}" >> "$LOG"; }
brk() {  # brk <sha> [칸] — 꼴 깨진 원장 줄(칸 0 · epoch 아님) — tamper 검사에 걸리므로 모드 줄을 다시 넣어 그 줄에 도달한다(K2 입력)
  [ -n "${2:-}" ] && printf 'scope-use S57 %s code %s\n' "$1" "$2" >> "$LOG" || printf 'scope-use S57 %s \n' "$1" >> "$LOG"
  printf '%s\ton\tA1\n' "$T0" >> "$LOG"; }
A="$(sha 41)"; A2="$(sha 42)"; el=0
fx_base

# ══ ① K1 원장 «scope-use S57 <A> code <t>» 1줄 · 같은 A 재승인 → NOOP 끝 class=code · 원장 그대로(기준판 = class 0 → Red)
s0; onfix; sgr S57 docs,ff,code; use S57 "$A" code ""; n0="$(lines)"; run a scope-approve "$A"
[ $rc = 0 ] && has "^SCOPE-NOOP $A used=[0-9]+/30 today=[0-9]+/15 class=code$" && [ "$(lines)" = "$n0" ]; ck "① NOOP 끝 class=code · 원장 줄 수 그대로" $?
if [ "$BASE_OK" = 1 ]; then s0; onfix; sgr S57 docs,ff,code; use S57 "$A" code ""; ABIN="$BASE" run a scope-approve "$A"; ! has 'class='; ck "① 기준판 Red: 같은 입력 = class 0" $?; fi

# ══ ② K1 원장 꼬리« repo=pack learned=x» → NOOP 끝 «class=code repo=pack learned=x»(글자 그대로)
s0; onfix; sgr S57 docs,ff,code; use S57 "$A" code " repo=pack learned=x"; run a scope-approve "$A"
[ $rc = 0 ] && has "^SCOPE-NOOP $A used=[0-9]+/30 today=[0-9]+/15 class=code repo=pack learned=x$"; ck "② 꼬리 repo=·learned= 글자 그대로" $?

# ══ ③ K1 범위 대조(그 줄 S == 지금 G_S ∧ cls ∈ G_CLASSES) — 둘 중 하나만 어긋나도 class 0 · try --land 는 판독 불가로 닫힌다
s0; onfix; sgr S57 docs; use S56 "$A2" code ""; run a scope-approve "$A2"
[ $rc = 0 ] && has "^SCOPE-NOOP $A2 " && ! has 'class='; ck "③a 원장 줄 S56 ≠ 지금 S57 → class 0" $?
run a try-auto "$A2" --pr 7 --repo byz --card c.md --land
[ $rc = 0 ] && has '자동 착지 0 · kind 판독 불가 · h 길' && [ "$(land_n)" = 0 ]; ck "③a 판독 불가 · merge-land 0" $?
s0; onfix; sgr S57 docs; use S57 "$A" code ""; run a scope-approve "$A"
[ $rc = 0 ] && has "^SCOPE-NOOP $A " && ! has 'class='; ck "③b 같은 S57 이지만 cls=code ∉ classes=docs → class 0" $?

# ══ ④ K2 원장 줄 꼴 깨짐(칸 0 · epoch 아님) → NOOP 지금 꼴(class 0) · 지어내지 않는다
s0; onfix; sgr S57 docs; brk "$A"; run a scope-approve "$A"; o4a="$out"
[ $rc = 0 ] && has "^SCOPE-NOOP $A used=[0-9]+/30 today=[0-9]+/15$"; ck "④a 칸 0 = class 0(현재 꼴)" $?
s0; onfix; sgr S57 docs,ff,code; brk "$A" xx; run a scope-approve "$A"
[ $rc = 0 ] && has "^SCOPE-NOOP $A used=[0-9]+/30 today=[0-9]+/15$"; ck "④b epoch 자리 글자 = class 0(꼴 못 읽음)" $?

# ══ ⑤ K3 NOOP class=code learned 0 → try-auto --land 가 merge-land 1회(기준판 = «kind 판독 불가» → Red)
s0; onfix; sgr S57 docs,ff,code; use S57 "$A" code ""; rm -f "$T/land.log"; run a try-auto "$A" --pr 7 --repo byz --card c.md --land
[ $rc = 0 ] && has "^TRY-OK via=S57 SCOPE-NOOP $A " && has '^LANDED 대역' && [ "$(land_n)" = 1 ]; ck "⑤ TRY-OK → merge-land 1회" $?
if [ "$BASE_OK" = 1 ]; then s0; onfix; sgr S57 docs,ff,code; use S57 "$A" code ""; rm -f "$T/land.log"; ABIN="$BASE" run a try-auto "$A" --pr 7 --repo byz --card c.md --land
  has 'kind 판독 불가' && [ "$(land_n)" = 0 ]; ck "⑤ 기준판 Red: 같은 입력 = 판독 불가 · merge-land 0" $?; fi

# ══ ⑥ K3 NOOP class=code learned=x → «자동 착지 제외 kind=x · h 길» · merge-land 0
s0; onfix; sgr S57 docs,ff,code; use S57 "$A" code " learned=x"; rm -f "$T/land.log"; run a try-auto "$A" --pr 7 --repo byz --card c.md --land
[ $rc = 0 ] && has '자동 착지 제외 kind=x · h 길' && [ "$(land_n)" = 0 ]; ck "⑥ learned 있음 = h 길 · merge-land 0" $?

# ══ ⑦ K4 처음 승인(원장 줄 0) → SCOPE-OK 줄 글자 그대로 · scope-use 1줄 더함
s0; onfix; sgr S57 docs; run a scope-approve "$A"; o7="${out%%$'\n'*}"; u7="$(grep -c '^scope-use ' "$LOG")"
[ $rc = 0 ] && [ "$o7" = "SCOPE-OK $A class=docs used=1/30 today=1/15" ] && [ "$u7" = 1 ]; ck "⑦ 처음 승인 SCOPE-OK 꼴 그대로 · scope-use 1줄" $?
s0; onfix; sgr S57 docs; ABIN="$BASE" run a scope-approve "$A"
[ "${out%%$'\n'*}" = "$o7" ]; ck "⑦ 기준판 같은 글자(class 칸 붙지 않음)" $?

# ══ ⑧ K3 NOOP class 0(④ 꼴) → try-auto --land «kind 판독 불가 · h 길» 그대로 · merge-land 0
s0; onfix; sgr S57 docs; brk "$A"; rm -f "$T/land.log"; run a try-auto "$A" --pr 7 --repo byz --card c.md --land
[ $rc = 0 ] && has '자동 착지 0 · kind 판독 불가 · h 길' && [ "$(land_n)" = 0 ]; ck "⑧ class 0 → 판독 불가 · merge-land 0" $?

# ══ ⑨ K4 amt_same 다름(승인 base 바뀜) → 지금처럼 SCOPE-REJECT · NOOP 줄 0 · class 0
s0; onfix; sgr S57 docs; use S57 "$A" code ""; mkdir -p "$S/autonomy-merge-target"; echo ops/main-base > "$S/autonomy-merge-target/$A"; run a scope-approve "$A"
[ $rc = 2 ] && has '판정 불가 — 승인 base ops/main-base ≠ 지금 PR base main' && ! has 'SCOPE-NOOP'; ck "⑨ target 다름 = REJECT rc 2 · NOOP 0" $?

# ══ 변이 M1~M6 — 변이 판이 «빨강이어야 할 칸» 을 통과시키는지(각 변이 뒤 원본 같은 사례로 반대 결과 대조)
mut m1 ft-autonomy-scope.sh 'printf '\'' class=%s%s'\'' "$c" "$t"' ':'   # M1 NOOP class 실음 지움
s0; onfix; sgr S57 docs,ff,code; use S57 "$A" code ""; ABIN="$T/mut-m1" run a scope-approve "$A"
! has 'class='; ck "㉠M1 NOOP class 실음 지움 → ① 칸이 class 0(빨강)" $?
s0; onfix; sgr S57 docs,ff,code; use S57 "$A" code ""; run a scope-approve "$A"; has 'class=code'; ck "㉠M1 원본 대조: 같은 입력 = class=code(초록)" $?
mut m2 ft-autonomy-scope.sh '  t="${l#"scope-use $s $1 $c $ev"}"' '  t=""'; s0; onfix; sgr S57 docs,ff,code; use S57 "$A" code " repo=pack learned=x"; ABIN="$T/mut-m2" run a scope-approve "$A"
has 'class=code$'; ck "㉠M2 꼬리 실음 지움 → ② 칸이 꼬리 없음(빨강)" $?
mut m3 ft-autonomy-scope.sh '  [[ "$l" =~ ^scope-use\ S[0-9]+\ [0-9a-f]{40}\ (docs|ff|revert|code)\ [0-9]+ ]] || return 0' '  :'; s0; onfix; sgr S57 docs,ff,code; brk "$A" xx; ABIN="$T/mut-m3" run a scope-approve "$A"
has 'class=code'; ck "㉠M3 꼴 검사 지움 → ④b 칸이 class=code(빨강)" $?
s0; onfix; sgr S57 docs,ff,code; brk "$A" xx; run a scope-approve "$A"; ! has 'class='; ck "㉠M3 원본 대조: 같은 입력 = class 0(초록)" $?
mut m4 ft-autonomy-try.sh "'^(STANDING|SCOPE)-(OK|NOOP) '" "'^(STANDING|SCOPE)-OK '"; s0; onfix; sgr S57 docs,ff,code; use S57 "$A" code ""; rm -f "$T/land.log"; ABIN="$T/mut-m4" run a try-auto "$A" --pr 7 --repo byz --card c.md --land
has 'kind 판독 불가' && [ "$(land_n)" = 0 ]; ck "㉠M4 try 의 NOOP 읽기 지움 → ⑤ 칸이 판독 불가(빨강)" $?
mut m5 ft-autonomy-try.sh 'case "$k" in kind=*|learned=*)' 'case "$k" in kind=*)'; s0; onfix; sgr S57 docs,ff,code; use S57 "$A" code " learned=x"; rm -f "$T/land.log"; ABIN="$T/mut-m5" run a try-auto "$A" --pr 7 --repo byz --card c.md --land
[ "$(land_n)" = 1 ]; ck "㉠M5 learned 낱말 거름 지움 → ⑥ 칸이 착지한다(빨강)" $?
mut m6 ft-autonomy-scope.sh '  [ "$s" = "$G_S" ] || return 0
  case ",$G_CLASSES," in *",$c,"*) ;; *) return 0 ;; esac' '  :'   # M6 범위 대조(S 대조 + classes 대조) 지움
s0; onfix; sgr S57 docs; use S56 "$A2" code ""; ABIN="$T/mut-m6" run a scope-approve "$A2"
has 'class=code'; ck "㉠M6 범위 대조 지움 → ③a 칸이 class=code(빨강)" $?
s0; onfix; sgr S57 docs; use S56 "$A2" code ""; run a scope-approve "$A2"; ! has 'class='; ck "㉠M6 원본 대조: 같은 입력 = class 0(초록)" $?

# ══ 크기·사본 — bin↔kit cmp0 · 새 파일 실행 비트 0 · try 상한(≤100줄)
s0; for f in ft-autonomy-scope.sh ft-autonomy-try.sh; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f" || { echo "FAIL 키트 사본 $f"; fail=$((fail+1)); }; done
[ ! -x "$HERE/test_autonomy_scope_noop_carry_kind_r2360.sh" ] && [ "$(wc -l < "$BIN/ft-autonomy-try.sh" | tr -d ' ')" -le 100 ]; ck "키트 사본 cmp0 · 새 파일 실행 비트 0 · try ≤100줄" $?

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
