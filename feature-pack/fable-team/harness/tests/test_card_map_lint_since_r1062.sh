#!/usr/bin/env bash
# test_card_map_lint_since_r1062.sh — 카드 lint «첫 추가일» 조회가 좁은 창(문턱 뒤 커밋)만 훑는지(r1062).
#   계약 ① 판정 그대로 — R1 스위치 뒤 = BAD · R2 스위치 전(=창 밖) = WARN · R3 이력 없음 = 지금과 같다(오늘 날짜)
#            · R5 재추가 = 스위치 뒤 날짜 · 창 안(2026-10-20) 카드 = 실제 날짜(제안서 문턱 2026-10-11 소비자가 날짜를 잃지 않는다)
#   계약 ② 범위 축소 — R4 스위치 전 커밋 2,000개 픽스처: 사전에 «옛 카드 날짜» 0장(표식뿐) · 1초 안
#   계약 ③ 회귀 — r984 lint 시험 rc0(실데이터 절은 시간 상한 때문에 SKIP · 따로 1회 실측해 evidence 에 적는다)
#   변이 2: ⓐ --since 를 스위치+1일로 → R1 이 WARN 으로 무너짐 · ⓑ --since 삭제 → 사전에 옛 카드 «날짜» 가 들어옴.
#   실 리포 0(임시 git 픽스처) · 자기 재호출 0 · 시각 고정(GIT_AUTHOR_DATE/GIT_COMMITTER_DATE) · 고정 sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
MOD="$HERE/../bin/ft_card_map_lint.py"
KIT="$HERE/../kit/fable-team/bin/ft_card_map_lint.py"
SW=2026-10-30
WINDOW=2026-10-11
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$HERE/test_card_map_lint_since_r1062.sh" && ok "bash -n 자기 파일" || bad "bash -n 자기 파일"
python3 -c 'import ast,sys; ast.parse(open(sys.argv[1],encoding="utf-8").read())' "$MOD" && ok "python ast ft_card_map_lint.py" || bad "python ast"
cmp -s "$MOD" "$KIT" && ok "kit 짝 cmp0 (ft_card_map_lint.py)" || bad "kit 짝 다름"
grep -q -- '--since={sw} 00:00:00' "$MOD" && ok "build_map 이 --since=<문턱 00:00:00> 를 넘긴다" || bad "--since 인자 없음"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R/indices/대기"; cd "$R" || { echo "FAIL cd"; exit 1; }
git -c init.defaultBranch=main init -q . || { echo "FAIL git init"; exit 1; }
BAD_TBL=$'## 계약↔시험 대응표\n| 계약 | 입력 | 기대 | 시험 |\n|---|---|---|---|\n| C1 계약 | 입력 A | 기대 A |  |'
OK_TBL=$'## 계약↔시험 대응표\n| 계약 | 입력 | 기대 | 시험 |\n|---|---|---|---|\n| C1 계약 | 입력 A | 기대 A | 시험 ① |'
mkcard() { printf '# 인덱스: %s\n%s\n' "$2" "$3" > "$R/indices/대기/$2.md"; }
cmt() { git -C "$R" add -A >/dev/null 2>&1; GIT_AUTHOR_DATE="$1T09:00:00" GIT_COMMITTER_DATE="$1T09:00:00" git -C "$R" -c user.email=t@t -c user.name=t commit -qm "$2" >/dev/null 2>&1; }
# run <모듈> <카드경로> [스위치] → 모듈 출력 전문(마지막 줄에 rc 별도)
run() { ( cd "$R" && FT_CARD_GATE_STRICT_FROM="${3:-$SW}" python3 "$1" "$2" 2>&1 ); }
# expect <라벨> <모듈> <카드> <STATUS> <rc> [스위치] — strict 는 STATUS 가 정한다(BAD=1 · WARN=0 · OK=줄의 strict=)
expect() {
  local out rc st sc want=strict=?
  out="$(run "$2" "$3" "${6:-}")"; rc=$?; st="$(printf '%s\n' "$out" | head -1 | cut -f1)"
  case "$st" in BAD) sc=strict=1;; WARN) sc=strict=0;; *) sc="$(printf '%s\n' "$out" | grep -o 'strict=[01]' | head -1)";; esac
  [ "$4" = BAD ] && want=strict=1; [ "$4" = WARN ] && want=strict=0
  [ "$st" = "$4" ] && [ "$rc" = "$5" ] && { [ "$want" = strict=? ] || [ "$sc" = "$want" ]; } \
    && ok "$1 → $st · ${sc:-strict=?} · rc=$rc" \
    || bad "$1 → $st · ${sc:-strict=?} · rc=$rc (기대 $4 · ${want} · rc=$5) $(printf '%s' "$out" | tr '\n' ';' | cut -c1-140)"
}

# ── 계약 ① 판정 그대로 — R1 / R2 / R5 / 창 안 카드 / 대조군 (커밋은 시간 순서로 — git log --since 는 오래된 조상을 만나면 순회를 끊는다) ──
mkcard r2 R2-pre "$BAD_TBL";     cmt 2026-10-01 "R2 스위치 전 추가"
mkcard r5 R5-readd "$BAD_TBL";   cmt 2026-10-05 "R5 스위치 전 추가"
git -C "$R" rm -q "indices/대기/R5-readd.md"; cmt 2026-10-06 "R5 삭제"
mkcard mm M-mid "$BAD_TBL";      cmt 2026-10-20 "M 스위치 전·제안서 문턱 뒤 추가"
mkcard r1 R1-post "$BAD_TBL";    cmt 2026-10-30 "R1 스위치 뒤 추가"
mkcard ok OK-post "$OK_TBL";     cmt 2026-10-30 "OK 스위치 뒤 추가·표 정상"
mkcard r5 R5-readd "$BAD_TBL";   cmt 2026-10-30 "R5 스위치 뒤 재추가"
mkcard r3 R3-untracked "$BAD_TBL"   # 커밋 0 — 이력 없는 카드
expect "R1 스위치 뒤 추가 + 표 결함 = BAD"                   "$MOD" "$R/indices/대기/R1-post.md"      BAD  1
expect "R2 스위치 전(창 밖) 추가 + 표 결함 = WARN"            "$MOD" "$R/indices/대기/R2-pre.md"       WARN 0
expect "R5 스위치 뒤 재추가 = BAD(스위치 뒤 날짜)"            "$MOD" "$R/indices/대기/R5-readd.md"     BAD  1
expect "M 창 밖(10-20)·제안서 문턱 뒤 + 표 결함 = WARN(strict 0)" "$MOD" "$R/indices/대기/M-mid.md"      WARN 0
expect "대조군 스위치 뒤 추가 + 표 정상 = OK"                 "$MOD" "$R/indices/대기/OK-post.md"      OK   0
# R3 «이력 없음 = 지금과 같다» — 스위치가 과거면 오늘 날짜로 strict(REJECT), 미래면 WARN. 오늘 날짜에 안 기댄 두 값.
expect "R3 이력 없음 · 스위치 2025-01-01(과거) = BAD(오늘 날짜)" "$MOD" "$R/indices/대기/R3-untracked.md" BAD  1 2025-01-01
expect "R3 이력 없음 · 스위치 2099-01-01(미래) = WARN"          "$MOD" "$R/indices/대기/R3-untracked.md" WARN 0 2099-01-01
# 사전에 «창 안 카드는 실제 날짜 · 창 밖 카드는 표식» — 제안서 문턱(2026-10-11) 소비자가 날짜를 잃지 않는다
( cd "$R" && : > "$T/map0.txt" && FT_CARD_GATE_STRICT_FROM=$SW FT_CARD_ADDED_MAP_FILE="$T/map0.txt" python3 "$MOD" "$R/indices/대기/R1-post.md" --map-only >/dev/null 2>&1 )   # 사전 파일은 부르는 쪽이 미리 만든다(ft-index-lint mktemp 와 같은 꼴)
grep -qx $'R1-post.md\t2026-10-30' "$T/map0.txt" \
  && ok "사전 R1-post = 실제 날짜 2026-10-30" || bad "사전 R1-post 날짜 이상: $(grep '^R1-post' "$T/map0.txt" | tr '\n' ';')"
grep -qx $'M-mid.md\t2026-10-11' "$T/map0.txt" && ok "사전 M-mid = 2026-10-11 표식(창 밖·제안서 문턱 뒤 → 제안서 검사는 «새 카드» 로 본다)" \
  || bad "사전 M-mid 표식 이상: $(grep '^M-mid' "$T/map0.txt" | tr '\n' ';')"
grep -qx $'R2-pre.md\t0000-00-00' "$T/map0.txt" && ok "사전 R2-pre = 표식 0000-00-00(창 밖 · 날짜 안 읽음)" \
  || bad "사전 R2-pre 표식 아님: $(grep '^R2-pre' "$T/map0.txt" | tr '\n' ';')"

# ── 골든: 고치기 전 판(origin/main 사본)과 STATUS 가 같다(added= 문자열은 창 밖·이력 없음에서 달라진다) ──
OLD="$T/old_mod.py"
if git -C "$HERE" rev-parse --git-dir >/dev/null 2>&1 \
   && git -C "$HERE" show "origin/main:feature-pack/fable-team/harness/bin/ft_card_map_lint.py" > "$OLD" 2>/dev/null; then
  for c in R1-post R2-pre R5-readd M-mid OK-post; do
    a="$(run "$MOD" "$R/indices/대기/$c.md")"; b="$(run "$OLD" "$R/indices/대기/$c.md")"
    sa="$(printf '%s\n' "$a" | head -1 | cut -f1)"; sb="$(printf '%s\n' "$b" | head -1 | cut -f1)"
    [ "$sa" = "$sb" ] && ok "골든 $c — 고치기 전 판과 같은 판정($sa)" \
      || bad "골든 $c → 고침 $sa ≠ 옛 판 $sb"
  done
else
  echo "SKIP 골든 — origin/main 사본을 못 꺼냈다(임시 리포/사본 실행)"
fi

# ── 변이 ⓐ --since 를 스위치+1일로 → R1 이 WARN 으로 무너진다(계약 ① 이 빨강) ──
mut() {   # mut <출력> <바꿀 조각> <새 조각>
  python3 - "$MOD" "$1" "$2" "$3" <<'EOF'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if old not in s:
    sys.exit(9)
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
EOF
}
if mut "$T/mut-a.py" 'f"--since={sw} 00:00:00"' '"--since=2026-10-31 00:00:00"'; then
  outa="$(run "$T/mut-a.py" "$R/indices/대기/R1-post.md")"; rca=$?
  [ "$(printf '%s\n' "$outa" | head -1 | cut -f1)" = WARN ] \
    && ok "변이 ⓐ(--since=스위치+1일) = R1 이 WARN 으로 무너짐 → 계약 ① FAIL 로 잡힌다" \
    || bad "변이 ⓐ 를 못 잡음 — R1 이 $(printf '%s\n' "$outa" | head -1 | cut -f1) (rc=$rca)"
else
  bad "변이 ⓐ 적용 실패 — --since 조각 없음"
fi

# ── 계약 ② R4: 스위치 전 커밋 2,000개 픽스처 — 사전이 옛 카드 «날짜» 를 안 읽는다 ──
R2D="$T/repo2000"; mkdir -p "$R2D"; git -C "$R2D" -c init.defaultBranch=main init -q . || { echo "FAIL git init 2000"; exit 1; }
python3 - "$BAD_TBL" > "$T/fi.stream" <<'EOF'
import datetime
import sys

tbl = sys.argv[1]
out = []
for i in range(1, 2001):
    d = datetime.date(2026, 1, 1) + datetime.timedelta(days=i % 270)   # 전부 2026-10-05 이전(창 2026-10-11 밖)
    ts = int(datetime.datetime(d.year, d.month, d.day, 9, 0, tzinfo=datetime.timezone.utc).timestamp())
    body = f"# 인덱스: OLD-{i:04d}\n{tbl}\n".encode()
    msg = f"old {i}".encode()
    out.append("commit refs/heads/main")
    out.append(f"mark :{i}")
    out.append(f"committer t <t@t> {ts} +0000")
    out.append(f"data {len(msg)}")
    out.append(msg.decode())
    out.append(f"M 100644 inline indices/대기/OLD-{i:04d}.md")
    out.append(f"data {len(body)}")
    out.append(body.decode())
    out.append("")
print("\n".join(out))
EOF
git -C "$R2D" fast-import --quiet < "$T/fi.stream" && git -C "$R2D" reset -q --hard main \
  && ok "픽스처 2,000커밋(전부 창 밖: 2026-01~10-05) 생성" || bad "픽스처 2,000커밋 생성 실패"
printf '# 인덱스: NEW-post\n%s\n' "$OK_TBL" > "$R2D/indices/대기/NEW-post.md"
git -C "$R2D" add -A >/dev/null 2>&1
GIT_AUTHOR_DATE="2026-10-30T09:00:00" GIT_COMMITTER_DATE="2026-10-30T09:00:00" git -C "$R2D" -c user.email=t@t -c user.name=t commit -qm new >/dev/null 2>&1
ncmt="$(git -C "$R2D" rev-list --count main 2>/dev/null)"
[ "$ncmt" -ge 2001 ] && ok "픽스처 커밋 수 $ncmt ≥ 2001" || bad "픽스처 커밋 수 $ncmt"
mapof() {   # mapof <모듈> <사전파일> → 경과초를 stdout 에
  local t0 t1
  t0=$(python3 -c 'import time;print(time.time())')
  ( cd "$R2D" && : > "$2" && FT_CARD_GATE_STRICT_FROM=$SW FT_CARD_ADDED_MAP_FILE="$2" python3 "$1" "$R2D/indices/대기/NEW-post.md" --map-only >/dev/null 2>&1 )
  t1=$(python3 -c 'import time;print(time.time())')
  python3 -c "print(f'{$t1-$t0:.2f}')"
}
mapstat() {   # mapstat <사전파일> → «옛 카드 실제날짜 수 · 표식 수 · 창 안 카드 수»
  python3 - "$1" <<'EOF'
import sys

try:
    lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
except OSError:
    lines = []
real = sum(1 for ln in lines if ln.startswith("OLD-") and ln.split("\t")[-1].startswith("2026-"))
mark = sum(1 for ln in lines if ln.startswith("OLD-") and ln.split("\t")[-1] == "0000-00-00")
new = sum(1 for ln in lines if ln.startswith("NEW-post.md\t"))
print(real, mark, new)
EOF
}
el=$(mapof "$MOD" "$T/map1.txt")
read -r nr nmark nnew <<< "$(mapstat "$T/map1.txt")"
[ "$nr" -eq 0 ] && ok "사전에 옛 카드 «날짜» 0장(2,000장 전부 표식)" || bad "사전에 옛 카드 날짜 $nr장 — 창 밖을 읽었다"
[ "$nmark" -eq 2000 ] && ok "사전 옛 카드 2,000장 = 표식 0000-00-00" || bad "표식 $nmark장(2,000 이어야 한다)"
[ "$nnew" -eq 1 ] && ok "사전에 창 안 카드 1(NEW-post = 실제 날짜)" || bad "사전에 창 안 카드 $nnew"
awk -v e="$el" 'BEGIN{exit !(e<=1)}' && ok "2,001커밋 리포 조회 경과 ${el}초 ≤ 1초" || bad "조회 경과 ${el}초 > 1초"
if mut "$T/mut-b.py" ', f"--since={sw} 00:00:00"' ''; then
  el2=$(mapof "$T/mut-b.py" "$T/map2.txt")
  read -r nr2 _ _ <<< "$(mapstat "$T/map2.txt")"
  [ "$nr2" -gt 0 ] && ok "변이 ⓑ(--since 삭제) = 사전에 옛 카드 날짜 ${nr2}장 → 계약 ② FAIL 로 잡힌다(경과 ${el2}초)" \
    || bad "변이 ⓑ 를 못 잡음 — --since 를 지워도 옛 카드 날짜 0"
else
  bad "변이 ⓑ 적용 실패 — --since 조각 없음"
fi

# ── 계약 ③ 회귀: r984 lint 시험 rc0(실데이터 절 = 8초 지연 래퍼 ×2 + 전체 lint 라 70초 상한 밖 → SKIP 경로로 돈다) ──
t0=$(python3 -c 'import time;print(time.time())')
FT_R984_INDICES=/nonexistent bash "$HERE/test_card_map_lint_r984.sh" > "$T/r984.log" 2>&1; rc9=$?
t1=$(python3 -c 'import time;print(time.time())')
el9=$(python3 -c "print(f'{$t1-$t0:.2f}')")
[ "$rc9" -eq 0 ] && ok "회귀 test_card_map_lint_r984.sh rc0 (${el9}초 · 실데이터 절 SKIP)" \
  || bad "회귀 r984 rc=$rc9 $(grep -m3 '^FAIL' "$T/r984.log" | tr '\n' ';')"
mkdir -p "$HERE/../evidence/r1062"
echo "INFO 2,001커밋 조회 --since 판=${el}초 · 변이(--since 삭제)=${el2:-?}초 · r984 회귀=${el9}초" >> "$HERE/../evidence/r1062/timing.txt"

echo "fail=$fail"; [ $fail -eq 0 ]
