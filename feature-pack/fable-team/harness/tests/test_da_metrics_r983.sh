#!/usr/bin/env bash
# test_da_metrics_r983.sh — r983: 카드별 DA «전» 값 측정기(ft-da-metrics · ft_da_metrics.py).
#   ⓐ 합성 폴더 기대값 1:1 (반송 2+1 · 호출 3+1 · 첫 판정 · 간격 30분 · 벽시계 104.5h · 재spawn 2 · 범위 3+1 · 되돌림 1)
#   ⓑ 반례 집합 전수 (카드 폴더 · .out · 상태 줄 · 되돌림) — DA r1 수용 7건(폴더 권한 · 날짜 없는 카드 · 쪼갠 카드 합산 ·
#      개행 이름 한 행 · `[확인 필요]` 3값 매칭 · 같은 날 되돌림 · 검사식 rc 보존) 각각 칸 1개
#   ⓒ 실데이터 대조 = ANALYSIS §1 산식(gap 39분 · first_approve 분수 꼴 · 수를 지어내지 않음) · 7초 룰
#   ⓓ 변이 3종 KILLED (호출=반송 · 읽기 실패 = 0 · 되돌림 = no)
#   ⓔ kit 짝 cmp0 · /bin/bash 3.2 · 읽기 전용(카드·증거 mtime 불변)
# 격리: 임시 루트만 쓴다. 실데이터 대조만 FT_R983_REAL 사본을 «읽는다»(쓰기 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
PY="$BIN/ft_da_metrics.py"; SH="$BIN/ft-da-metrics.sh"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:-}"; fail=$((fail+1)); }
# ck <검사식 rc> <라벨> [메시지] — rc 를 «첫 인자» 로 받아야 `$(...)` 가 $? 를 덮지 않는다(DA r1 수용 1)
ck() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export FT_DA_METRICS_NOW=2026-10-27

# ── 0. 문법 · kit 짝 · ruff · bash 3.2 ──
bash -n "$SH"; ck $? "bash -n ft-da-metrics.sh" ""
cmp -s "$PY" "$KIT/ft_da_metrics.py"; ck $? "키트 cmp 0 ft_da_metrics.py" ""
cmp -s "$SH" "$KIT/ft-da-metrics.sh"; ck $? "키트 cmp 0 ft-da-metrics.sh" ""
python3 -m ruff check "$PY" >/dev/null 2>&1; ck $? "ruff ft_da_metrics.py" ""
/bin/bash "$SH" --help >/dev/null 2>&1; [ $? -le 2 ]; ck $? "/bin/bash 3.2 로도 돈다(usage rc≤2)" ""

# ── 픽스처 ──
R="$T/repo"; I="$R/design/harness/indices"; E="$R/design/harness/evidence"
mkdir -p "$I/대기" "$I/진행" "$I/완성" "$E/r900-a-da1" "$E/r900-a-r2-da1" "$E/r901-side-da1"
card() { local d="$1" n="$2"; shift 2; { echo "# 인덱스: $n"; echo "## 구현 범위"; printf '%s\n' "$@"; } > "$I/$d/$n.md"; }
card 진행 r900-a '1. 하나' '2. 둘' '3. 셋' && cat >> "$I/진행/r900-a.md" <<'EOF'
## 상태
- 2026-10-20 10:00 — 대기→진행 · 좌석 a#0
- 2026-10-20 10:05 — DA② r1 HOLD 2
- 2026-10-21 11:30 — DA② r2 HOLD 1
- 2026-10-22 12:00 — 진행→대기
- 2026-10-23 09:00 — 대기→진행 · 좌석 a#0
- 2026-10-24 18:30 — 진행 중
EOF
card 진행 r900-a-r2 '1. 하나' && printf -- '- 선행: r900-a (쪼갠 카드)\n## 상태\n- 2026-10-24 19:00 — DA② r1 HOLD 1\n' >> "$I/진행/r900-a-r2.md"
card 진행 r901-side '1. 하나' '2. 둘' && printf -- '- 선행: r900-a (이름 변형 아님 = 단순 선행)\n## 상태\n- 2026-10-25 09:00 — 대기→진행 · 좌석 b#0\n' >> "$I/진행/r901-side.md"
card 완성 r902-old-revert '1. 하나' && printf '## 상태\n- 2026-08-01 10:00 — 진행→완성 · DA 판정문#§1\n- 2026-08-10 12:00 — 완성→진행 (되돌림)\n' >> "$I/완성/r902-old-revert.md"
card 완성 r903-new '1. 하나' && printf '## 상태\n- 2026-10-20 10:00 — 진행→완성 · DA 판정문#§2\n' >> "$I/완성/r903-new.md"
card 완성 r904-no-time '1. 하나' && printf '## 상태\n- 진행→완성 · DA 판정문#§3\n' >> "$I/완성/r904-no-time.md"
card 완성 r905-same-day '1. 하나' && printf '## 상태\n- 2026-09-01 10:00 — 진행→완성 · DA 판정문#§4\n- 2026-09-01 12:00 — 완성→진행 (같은 날 2시간 뒤)\n' >> "$I/완성/r905-same-day.md"
card 완성 r907-no-dates '1. 하나' && printf '## 상태\n- 진행→완성 · DA 판정문#§5\n- 오늘도 진행\n' >> "$I/완성/r907-no-dates.md"
card 완성 r908-zero-respawn '1. 하나' && printf '## 상태\n- 2026-10-20 10:00 — 진행→완성\n' >> "$I/완성/r908-zero-respawn.md"
card 완성 r909-x-approx '1. 하나' && printf '## 상태\n- 2026-10-20 2x:xx — 진행→완성\n- 2026-10-21 15:0x — 판정\n' >> "$I/완성/r909-x-approx.md"
card 완성 r910-new-variant '1. 하나' && printf -- '- 선행: r907-no-dates\n## 상태\n- 2026-10-20 10:00 — 진행→완성\n' >> "$I/완성/r910-new-variant.md"
printf '판정: APPROVE — 합성\n' > "$E/r900-a-da1/da-20261020-100000-1.out"
printf '판정: HOLD 2\n' > "$E/r900-a-da1/da-20261020-103000-2.out"
printf '판정: APPROVE — 합성\n' > "$E/r900-a-da1/da-20261020-110000-3.out"
printf '판정: APPROVE — 쪼갠 카드 증거\n' > "$E/r900-a-r2-da1/da-20261020-120000-4.out"
printf '판정: [확인 필요] int 파일 없음\n' > "$E/r901-side-da1/da-20261025-090000-5.out"
run() { out="$(bash "$SH" "$R" "$@" 2>"$T/err")"; rc=$?; }
row() { grep -F "$1	" <<<"$out" | head -1; }

# ── ⓐ 기대값 1:1 ──
run
[ "$rc" = 0 ]; ck $? "ⓐ rc0" "rc=$rc $(cat "$T/err")"
[ "$(head -1 <<<"$out")" = "cards=2 calls_mean=2.50 first_approve=1/2 gap_median=30min holds=3" ]
ck $? "ⓐ 요약 1줄 — 카드 2(쪼갠 카드는 모카드 1장) · 평균 2.50 · 첫 APPROVE 1/2 · 간격 30분 · 반송 3" "$(head -1 <<<"$out")"
r="$(row r900-a)"; [ "$(cut -f2-9 <<<"$r")" = "$(printf '2+1\t3+1\tAPPROVE\t30\t104.5h\t2\t3+1\t-')" ]
ck $? "ⓐ r900-a 행 = 반송 2+1 · 호출 3+1(자식 증거 합산) · 첫 APPROVE · 간격 30 · 104.5h · 재spawn 2 · 범위 3+1" "$r"
r="$(row '[미완료] r900-a-r2 ↳r900-a')"; [ -n "$r" ] && [ "$(cut -f2,3 <<<"$r")" = "$(printf '1\t1')" ]
ck $? "ⓐ 쪼갠 카드 행 = ↳모카드 표식 · 자기 반송 1 · 자기 호출 1" "$r"
r="$(row '[미완료] r901-side')"; [ -n "$r" ] && ! grep -q '↳' <<<"$r"
ck $? "ⓐ 이름 변형 아닌 선행 = 단독 카드(↳ 표식 0)" "$r"
[ "$(row r902-old-revert | cut -f9)" = yes ]; ck $? "ⓐ 되돌림 = yes(완성 8-01 · 되돌림 8-10)" "$(row r902-old-revert)"
[ "$(row r905-same-day | cut -f9)" = yes ]; ck $? "ⓐ 수용 7: 같은 날 2시간 뒤 완성→진행도 yes(0일 = 창 안)" "$(row r905-same-day)"
[ "$(row r903-new | cut -f9)" = 미도래 ]; ck $? "ⓐ 완성 10-20 = 창 전 → 미도래" "$(row r903-new)"
[ "$(row r904-no-time | cut -f9)" = '확인 불가' ]; ck $? "ⓐ 완성 이동 시각 없음 = «확인 불가» 칸" "$(row r904-no-time)"
[ "$(row r907-no-dates | cut -f6)" = '확인 불가' ]; ck $? "ⓐ 날짜 없는 상태 줄 = 벽시계 «확인 불가»" "$(row r907-no-dates)"
[ "$(row r908-zero-respawn | cut -f7)" = 0 ]; ck $? "ⓐ 대기→진행 0회 = 재spawn 0" "$(row r908-zero-respawn)"
[ "$(row r909-x-approx | cut -f6)" = '39.0h~' ]; ck $? "ⓐ 시각 «2x:xx» = 근사 «~» 표식(0h 아님)" "$(row r909-x-approx)"
[ "$(grep -F '[미완료] r901-side' <<<"$out" | cut -f4)" = '[확인 필요]' ]
ck $? "ⓐ 수용 6: 첫 판정 «[확인 필요]» 가 잘리지 않는다(3값 매칭)" "$(grep -F '[미완료] r901-side' <<<"$out")"
grep -q '^\[미완료\] r900-a	' <<<"$out"; ck $? "ⓐ 미완료 카드는 빼지 않고 [미완료] 표식" ""
grep -q '^r902-old-revert	' <<<"$out"; ck $? "ⓐ 완성 카드에는 [미완료] 표식 0" ""

# ── ⓑ 반례 집합 ──
run --since 2026-10-25
[ "$rc" = 0 ] && [ "$(head -1 <<<"$out" | cut -d' ' -f1-3)" = "cards=1 calls_mean=1.00 first_approve=0/1" ]
ck $? "ⓑ since 필터 = 그 날짜 뒤 .out 있는 카드만(1장 · first_approve 0/1)" "$(head -1 <<<"$out")"
grep -q '^r907-no-dates	' <<<"$out"; ck $? "ⓑ 수용 3: 날짜 없는 카드는 --since 에서도 표에서 사라지지 않는다" "$(grep -c . <<<"$out")"
P="$T/perm/design/harness/indices/진행"; mkdir -p "$P" "$T/perm/design/harness/indices/완성"
cp "$I/진행/r900-a.md" "$P/"; cp "$I/완성/r903-new.md" "$T/perm/design/harness/indices/완성/"
chmod 000 "$P"; out="$(bash "$SH" "$T/perm" 2>/dev/null)"; rc=$?; chmod 755 "$P"
[ "$rc" = 3 ] && grep -q '확인 불가: 카드 폴더를 못 읽음' <<<"$out"
ck $? "ⓑ 수용 2: 못 읽는 카드 폴더 = «확인 불가» rc3(다른 폴더가 정상이어도)" "rc=$rc $(head -2 <<<"$out")"
mkdir -p "$T/badrepo"; cp -R "$R/design" "$T/badrepo/"
rm "$T/badrepo/design/harness/indices/완성/r903-new.md"; mkdir "$T/badrepo/design/harness/indices/완성/r903-new.md"
out="$(bash "$SH" "$T/badrepo" 2>/dev/null)"; rc=$?
[ "$rc" = 3 ] && grep -q 'r903-new	확인 불가' <<<"$out" && grep -q '확인 불가 1장' <<<"$out"
ck $? "ⓑ 폴더로 만든 카드 = 그 행 «확인 불가» + 요약 표식 + rc3" "rc=$rc $(head -1 <<<"$out")"
out="$(bash "$SH" "$T/none" 2>/dev/null)"; rc=$?
[ "$rc" = 3 ] && grep -q '확인 불가: 카드 폴더 없음' <<<"$out"
ck $? "ⓑ 카드 폴더 없음 = «확인 불가» rc3" "rc=$rc $out"
mkdir -p "$T/empty/design/harness/indices/진행"; out="$(bash "$SH" "$T/empty" 2>/dev/null)"; rc=$?
[ "$rc" = 3 ] && grep -q '확인 불가: 카드 0장' <<<"$out"
ck $? "ⓑ 카드 0장 = «확인 불가» rc3" "rc=$rc $out"
mkdir -p "$T/nl/design/harness/indices/완성" "$T/nl/design/harness/evidence/r906-da1"
cp "$I/완성/r902-old-revert.md" "$T/nl/design/harness/indices/완성/r906-$(printf 'line\nbreak').md"
printf '판정: APPROVE\n' > "$T/nl/design/harness/evidence/r906-da1/da-20261020-090000-9.out"
out="$(bash "$SH" "$T/nl" 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [ "$(grep -F 'r906-line?break' <<<"$out" | awk -F'\t' '{print NF}')" = 9 ]
ck $? "ⓑ 수용 5: 파일명 속 개행 = «?» 치환 · 9열 한 행 유지" "rc=$rc NF=$(grep -F 'r906-line?break' <<<"$out" | awk -F'\t' '{print NF}')"
printf '판정: HOLD 2\n판정: APPROVE — 마지막만\n' > "$E/r900-a-da1/da-20261020-120000-6.out"
run; [ "$(row r900-a | cut -f3,4)" = "$(printf '4+1\tAPPROVE')" ]
ck $? "ⓑ 판정 줄 2개 = 마지막만 · 호출 4+1" "$(row r900-a)"
: > "$E/r900-a-da1/da-20261020-130000-7.out"; run; [ "$(row '[미완료] r900-a' | cut -f3)" = '5+1' ]
ck $? "ⓑ 빈 .out = 호출에 포함(판정 줄 없음)" "$(row '[미완료] r900-a')"
printf '판정: HOLD 1\n' > "$E/r900-a-da1/da-cursor-20261020.out"; run
[ "$(row '[미완료] r900-a' | cut -f3)" = '6+1?' ] && grep -q '^NOTE 시각없음 r900-a da-cursor-20261020.out' <<<"$out"
ck $? "ⓑ 파일명에 시각 없음 = 호출엔 넣고 «?» 표식 + NOTE 1줄" "$(row '[미완료] r900-a')"
rm -f "$E/r900-a-da1/da-cursor-20261020.out" "$E/r900-a-da1/da-20261020-120000-6.out" "$E/r900-a-da1/da-20261020-130000-7.out"

# ── ⓒ 실데이터 (읽기만) ──
REAL="${FT_R983_REAL:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops}"
if [ -d "$REAL/design/harness/indices" ]; then
  s="$( { /usr/bin/time -p bash "$SH" "$REAL" --since 2026-10-25 2>"$T/time"; } 2>/dev/null | head -1 )"
  sec="$(awk '/^real/{print $2}' "$T/time")"; [ -n "$sec" ] || sec=0
  grep -q 'gap_median=39min' <<<"$s"; ck $? "ⓒ gap_median = 39분 (ANALYSIS §1)" "$s"
  grep -qE 'first_approve=[0-9]+/[0-9]+' <<<"$s"; ck $? "ⓒ first_approve = 분수 꼴(지어낸 값 0)" "$s"
  grep -qE 'calls_mean=[0-9]+\.[0-9]{2}' <<<"$s"; ck $? "ⓒ calls_mean = 산식값 2자리(지어낸 값 0)" "$s"
  awk -v x="$sec" 'BEGIN{exit !(x>0 && x<7)}'; ck $? "ⓒ 7초 룰 (실측 ${sec}s < 7s)" ""
  echo "INFO 실데이터: $s"
  echo "INFO 문서값:   calls_mean=4.12 first_approve=2/41 gap_median=39min (ANALYSIS §1 · since 2026-10-25)"
else
  echo "SKIP ⓒ 실데이터 없음 ($REAL)"
fi

# ── ⓓ 변이 KILLED ──
mut() { sed -e "$1" "$PY" > "$T/mut.py"; cp "$BIN/ft_da_hold_gate.py" "$BIN/ft_git_capped.py" "$T/" 2>/dev/null; printf '#!/usr/bin/env bash\nexec python3 "%s/mut.py" "$@"\n' "$T" > "$T/mut.sh"; }
mut 's/^    return len(r\["outs"\]) if key == "calls" else r\["cnt"\]\[key\]$/    return r["cnt"]["holds"]/'
out="$(bash "$T/mut.sh" "$R" 2>/dev/null)"; r="$(row '[미완료] r900-a')"; [ "$(cut -f3 <<<"$r")" != '3+1' ]
ck $? "ⓓ 변이 1(호출 = 반송으로 셈) KILLED — 시험 ⓐ ②의 «3+1» 이 잡는다" "$r"
mut 's/^    return 3 if bad or not live else 0$/    return 0/'
bash "$T/mut.sh" "$T/badrepo" >/dev/null 2>&1; mrc=$?; [ "$mrc" != 3 ]
ck $? "ⓓ 변이 2(읽기 실패 = 0) KILLED — 시험 ⓑ ②의 rc3 이 잡는다(검사식 rc 보존 확인)" "mut_rc=$mrc"
mut 's/^    return "yes" if any(timedelta(0) < (rv - mv) <= win for mv in due for rv, _ in cnt\["reverts"\]) else "no"$/    return "no"/'
out="$(bash "$T/mut.sh" "$R" 2>/dev/null)"; [ "$(grep -F 'r905-same-day	' <<<"$out" | cut -f9)" != yes ]
ck $? "ⓓ 변이 3(되돌림 = 늘 no) KILLED — 시험 ⓐ ④·⑦의 yes 가 잡는다" "$(grep -F 'r905-same-day	' <<<"$out")"

# ── ⓔ 읽기 전용 ──
before="$(find "$R/design" -type f -newermt '-2 seconds' | wc -l | tr -d ' ')"; run
after="$(find "$R/design" -type f -newermt '-2 seconds' | wc -l | tr -d ' ')"; [ "$before" = "$after" ]
ck $? "ⓔ 카드·증거 파일 쓰기 0(읽기 전용)" "before=$before after=$after"

echo "---- fail=$fail"; [ "$fail" = 0 ] || exit 1
