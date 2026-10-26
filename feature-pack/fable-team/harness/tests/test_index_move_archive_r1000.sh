#!/usr/bin/env bash
# test_index_move_archive_r1000.sh — r1000: ft-index-move.sh 에 목적지 «아카이브» 1갈래.
#   사건(arch 152 · master 쪽지 171693): 닫는 길이 «진행→완성» 하나뿐인데 그 길은 착지 sha·설치 대조를 요구한다.
#   «버림»·«쓸모 없음» 으로 닫는 카드는 착지가 없어 대기에 쌓인다(r770·r773·r794) → 클리어 기준 «대기 0» 정면 충돌.
#   임시 git 리포 1개 + 카드·판정문 픽스처. 실 라이브·실 indices 쓰기 0.
#   SRC=<bin 폴더> 로 옛 판(전 빨강)·변이(검사 ⓐ 삭제 · 이름 부분 일치)를 같은 시험으로 돌린다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${SRC:-$(cd "$HERE/../bin" && pwd -P)}"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'chmod -R 755 "$T" 2>/dev/null; rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$T/home" LC_ALL=C
mkdir -p "$HOME"
unset FT_HARNESS_ROOT FT_INSTALL_CHECK FT_INSTALL_PENDING_DIR FT_LANDED_MARKER FT_LAND_REF FT_TEAMS_MD FT_TRACK FT_SEATS_JSON FT_MBOX FT_ROOT
BIN="$T/bin"; mkdir -p "$BIN"
cp -p "$SRC"/ft-index-move.sh "$SRC"/ft_da_hold_gate.py "$SRC"/ft_git_capped.py "$BIN/"
printf '#!/bin/bash\nexit 0\n' > "$BIN/ft-index-lint.sh"; chmod 755 "$BIN/ft-index-lint.sh"   # lint 는 이 카드의 계약이 아니다
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

CR="$T/byz"; IDX="$CR/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성}
g "$CR" init -q -b main
# 카드 — 정본 줄(ⓑ)까지 갖춘 최소 꼴. `- 정본 영향 없음:` 없는 카드는 knocanon.
card() { { echo "# 인덱스: $1"; echo "## 상태"; echo "- 정본 영향 없음: 하네스 도구만 바뀐 카드 — 제품 정본 없음"; } > "$2"; }
printf '# 인덱스: knocanon\n## 상태\n- 설치: 없음\n' > "$IDX/대기/knocanon.md"   # 정본 줄 없음(R4)
card karcha "$IDX/대기/karcha.md"
card karchs "$IDX/대기/karchs.md"                      # 판정문엔 «karchs-old» 의 버림 줄만 = 이름 정확 일치 반례(R2)
card karchh "$IDX/진행/karchh.md"; printf -- '- DA② r1 HOLD 3\n- DA② r2 HOLD 1\n' >> "$IDX/진행/karchh.md"   # 보류 미해제(R3)
card klanded "$IDX/진행/klanded.md"
card karchf "$IDX/완성/karchf.md"
card kre "$IDX/대기/kre.md"
g "$CR" add -A; g "$CR" commit -qm c0
DA="$CR/design/harness/DA-r1000.md"
cat > "$DA" <<'EOF'
# 판정문
## §1 karcha — 닫힘 (CLOSE)
닫힘 — karcha — 버림
- 사유: 선행 r964 가 같은 자리를 먼저 닫았다
## §2 karchs — 닫힘 (CLOSE)
닫힘 — karchs-old — 버림
## §3 klanded — 닫힘 (CLOSE)
닫힘 — klanded — main `0123456789abcdef0123456789abcdef01234567`
## §4 karchh — 닫힘 (CLOSE)
닫힘 — karchh — 버림
## §5 knocanon — 닫힘 (CLOSE)
닫힘 — knocanon — 쓸모 없음
## §6 karchf — 닫힘 (CLOSE)
닫힘 — karchf — 버림
## §7 kre — 닫힘 (CLOSE)
닫힘 — kre — 버림
## §9 kmut2 — 닫힘 (CLOSE)
닫힘 — kmut2-old — 버림
## §10 kf1 — 닫힘 (CLOSE)
닫힘 — kf1 — 버림
닫힘 — kf1 — main `0123456789abcdef0123456789abcdef01234567`
## §11 kf2 — 닫힘 (CLOSE)
닫힘 — kf2 — 버림
CLOSE — kf2 — main `0123456789abcdef0123456789abcdef01234567`
EOF
MON="$(date '+%Y-%m')"
mv0() { bash "$BIN/ft-index-move.sh" "$@" 2>&1; }

# ── ① ⓐ 대기 출발 · ⓑ 진행 출발 → 아카이브/<YYYY-MM>/ 이동 + 상태 줄 1
out="$(mv0 "$IDX/대기/karcha.md" 아카이브 --da "$DA#§1" --seat s1)"; rc=$?
[ "$rc" = 0 ] && [ -f "$IDX/아카이브/$MON/karcha.md" ] && [ ! -f "$IDX/대기/karcha.md" ] \
  && grep -q "— 대기→아카이브 · 좌석 s1 · 판정 $DA#§1" "$IDX/아카이브/$MON/karcha.md" \
  && ck "ⓐ 대기 출발 → 아카이브/$MON/ 이동 + 상태 줄(«대기→아카이브 · 좌석 · 판정»)" 0 || ck "ⓐ 대기 출발" 1
out="$(mv0 "$IDX/진행/klanded.md" 아카이브 --da "$DA#§2" --seat s2)"; rc=$?   # §2 는 «karchs-old» — klanded 는 이름 불일치(R2)
[ "$rc" = 1 ] && [ -f "$IDX/진행/klanded.md" ] && [[ "$out" == *"karchs"* || "$out" == *"정확 일치"* ]] \
  && ck "③ ⓓ 진행 출발 카드에 다른 이름의 버림 줄만 → REJECT · 파일 제자리" 0 || ck "③ ⓓ 이름 불일치(진행 출발) :: $out" 1
printf '## §8 klanded2 — 닫힘 (CLOSE)\n닫힘 — klanded — 쓸모 없음\n' >> "$DA"
out="$(mv0 "$IDX/진행/klanded.md" 아카이브 --da "$DA#§8" --seat s2)"; rc=$?
[ "$rc" = 0 ] && [ -f "$IDX/아카이브/$MON/klanded.md" ] \
  && grep -q "— 진행→아카이브 · 좌석 s2 · 판정 $DA#§8" "$IDX/아카이브/$MON/klanded.md" \
  && ck "ⓑ 진행 출발 + «쓸모 없음» 판정 → 아카이브 이동 + 상태 줄" 0 || ck "ⓑ 진행 출발 :: $out" 1

# ── ② ⓒ 착지한 카드(R1) — «닫힘 — <카드> — main <sha>» 는 완성 갈래로만 닫는다
card klanded "$IDX/진행/klanded.md"
card kf1 "$IDX/대기/kf1.md"; card kf2 "$IDX/대기/kf2.md"
out="$(mv0 "$IDX/진행/klanded.md" 아카이브 --da "$DA#§3" --seat s3)"; rc=$?
[ "$rc" = 1 ] && [ -f "$IDX/진행/klanded.md" ] && [[ "$out" == *"착지한 카드"* ]] \
  && ck "ⓒ 착지 카드(«닫힘 — … — main …») → REJECT(완성 갈래로) · 설치 대조 우회 0" 0 || ck "ⓒ 착지 카드 REJECT :: $out" 1
# r1 F1/A — 판정 종류는 «절 전체»: 버림 줄 «뒤» 에 착지 줄이 있어도 잡는다(첫 매치 exit = 옛 판)·
out="$(mv0 "$IDX/대기/kf1.md" 아카이브 --da "$DA#§10" --seat f1)"; rc=$?
[ "$rc" = 1 ] && [ -f "$IDX/대기/kf1.md" ] && [[ "$out" == *"착지한 카드"* ]] \
  && ck "F1 버림 줄 «뒤» 착지 줄 — 절 전체 판정 → REJECT · 파일 제자리" 0 || ck "F1 버림 뒤 착지 :: $out" 1
# r1 F2 — 착지 표식 «CLOSE — <카드> — main …» 도 닫힘 표기(완성 갈래와 같은 정규식) → 같이 잡힌다
out="$(mv0 "$IDX/대기/kf2.md" 아카이브 --da "$DA#§11" --seat f2)"; rc=$?
[ "$rc" = 1 ] && [ -f "$IDX/대기/kf2.md" ] && [[ "$out" == *"착지한 카드"* ]] \
  && ck "F2 버림 + «CLOSE — <카드> — main …» → REJECT(«닫힘|CLOSE» 둘 다)" 0 || ck "F2 CLOSE 착지 :: $out" 1

# ── ③ ⓓ 이름 불일치 · 정본 줄 없음(R2·R4)
out="$(mv0 "$IDX/대기/karchs.md" 아카이브 --da "$DA#§2" --seat s4)"; rc=$?
[ "$rc" = 1 ] && [ -f "$IDX/대기/karchs.md" ] && [[ "$out" == *"정확 일치"* ]] \
  && ck "ⓓ «karchs-old» 만 있고 카드는 karchs → REJECT(이름 정확 일치)" 0 || ck "ⓓ 이름 불일치 :: $out" 1
out="$(mv0 "$IDX/대기/knocanon.md" 아카이브 --da "$DA#§5" --seat s5)"; rc=$?
[ "$rc" = 1 ] && [ -f "$IDX/대기/knocanon.md" ] && [[ "$out" == *"정본 영향 없음"* ]] \
  && ck "ⓓ 카드에 «- 정본 영향 없음:» 줄 없음 → REJECT(R4)" 0 || ck "ⓓ 정본 줄 없음 :: $out" 1

# ── ④ ⓔ DA 보류 미해제(R3 · 진짜 판정기) · 완성 출발(R5) · 가짜 판정기 rc3(게이트 «결과» 를 본다)
out="$(mv0 "$IDX/진행/karchh.md" 아카이브 --da "$DA#§4" --seat s6)"; rc=$?
[ "$rc" = 1 ] && [ -f "$IDX/진행/karchh.md" ] && [[ "$out" == *"DA 보류 가드"* ]] \
  && ck "ⓔ 보류 2회 · 해제 0 → REJECT(기존 판정기 그대로 · 이동 0)" 0 || ck "ⓔ 보류 미해제 :: $out" 1
out="$(mv0 "$IDX/완성/karchf.md" 아카이브 --da "$DA#§6" --seat s7)"; rc=$?
[ "$rc" = 1 ] && [ -f "$IDX/완성/karchf.md" ] && [[ "$out" == *"출발은 대기|진행"* ]] \
  && ck "ⓔ 완성 출발 → REJECT(R5 · 대기·진행만)" 0 || ck "ⓔ 완성 출발 :: $out" 1
FG="$T/fakegate"; mkdir -p "$FG"; cp -p "$BIN"/ft-index-move.sh "$BIN"/ft-index-lint.sh "$FG/"
printf '#!/usr/bin/env python3\nprint("HOLD events=2 reviews=2 releases=0/0 budget_left=0")\nraise SystemExit(3)\n' > "$FG/ft_da_hold_gate.py"
out="$(bash "$FG/ft-index-move.sh" "$IDX/대기/kre.md" 아카이브 --da "$DA#§7" --seat s8 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ -f "$IDX/대기/kre.md" ] && [[ "$out" == *"DA 보류 가드: HOLD events=2"* ]] \
  && ck "ⓔ 가짜 판정기 rc3 → REJECT(카드 글자가 아니라 게이트 «결과» 를 본다)" 0 || ck "ⓔ 가짜 판정기 rc3 :: $out" 1

# ── ⑤ 기존 갈래 불변 — 대기→진행 은 그대로 동작 · 진행→완성 은 --da 없이 그대로 REJECT
card kplain "$IDX/대기/kplain.md"
out="$(mv0 "$IDX/대기/kplain.md" 진행 --seat s9)"; rc=$?
[ "$rc" = 0 ] && [ -f "$IDX/진행/kplain.md" ] && [[ "$out" == *"MOVED 대기→진행"* ]] \
  && ck "⑤ 대기→진행 회귀 0(MOVED · lint 통과)" 0 || ck "⑤ 대기→진행 :: $out" 1
out="$(mv0 "$IDX/진행/kplain.md" 완성)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"REJECT 진행→완성 은 --da"* ]] \
  && ck "⑤ 진행→완성 은 --da 없이 그대로 REJECT(완성 갈래 규칙 불변)" 0 || ck "⑤ 진행→완성 --da 필수 :: $out" 1
out="$(mv0 "$IDX/대기/kplain.md" 어딘가 2>&1)"; rc=$?
[ "$rc" = 2 ] && [[ "$out" == *"대기|진행|완성|아카이브"* ]] \
  && ck "⑤ 목적지 오타 → usage 에 네 목적지가 다 보인다" 0 || ck "⑤ usage 목적지 목록 :: $out" 1

# ── 변이 2 — 검사가 «짐»을 지고 있는지: ⓐ 판정 검사 삭제 · 이름 정확 일치를 부분 일치로
mut() { local d="$T/mut-$1"; mkdir -p "$d"; cp -p "$BIN"/ft-index-move.sh "$BIN"/ft-index-lint.sh "$BIN"/ft_da_hold_gate.py "$BIN"/ft_git_capped.py "$d/"; echo "$d"; }
d="$(mut verdict)"; python3 - "$d/ft-index-move.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding='utf-8').read(); old = '  case "$_verdict" in'
assert t.count(old) == 1
open(p, 'w', encoding='utf-8').write(t.replace(old, '  _verdict="버림"\n' + old))
PY
K2="$IDX/대기/kmut2.md"; card kmut2 "$K2"
out="$(bash "$d/ft-index-move.sh" "$K2" 아카이브 --da "$DA#§9" --seat s10 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -f "$IDX/아카이브/$MON/kmut2.md" ] \
  && ck "변이① 판정 검사 삭제 → 이름 불일치 카드가 통과해 버린다(ⓓ 가 잡는 자리)" 0 || ck "변이① 판정 검사 삭제 :: $out" 1
d="$(mut substr)"; python3 - "$d/ft-index-move.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding='utf-8').read()
old = 'if (substr(s,1,length(pre "버림"))==pre "버림") { if (v=="") v="버림" }'
assert t.count(old) == 1
open(p, 'w', encoding='utf-8').write(t.replace(old, 'if (index(s,c)>0 && index(s,"버림")>0) { v="버림" }'))
PY
card kmut2 "$K2"
out="$(bash "$d/ft-index-move.sh" "$K2" 아카이브 --da "$DA#§9" --seat s11 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -f "$IDX/아카이브/$MON/kmut2.md" ] \
  && ck "변이② 이름 정확 일치 → 부분 일치로 → 다른 이름 카드가 통과해 버린다(ⓓ 가 잡는 자리)" 0 || ck "변이② 부분 일치 :: $out" 1
d="$(mut firstmatch)"; python3 - "$d/ft-index-move.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding='utf-8').read()
old = 'END { if (land) print "착지"; else if (v!="") print v }'
assert t.count(old) == 1
open(p, 'w', encoding='utf-8').write(t.replace(old, 'END { if (v!="") print v; else if (land) print "착지" }'))
PY
card kf1 "$IDX/대기/kf1.md"
out="$(bash "$d/ft-index-move.sh" "$IDX/대기/kf1.md" 아카이브 --da "$DA#§10" --seat f3 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -f "$IDX/아카이브/$MON/kf1.md" ] \
  && ck "변이③ 착지 우선 → 첫 매치(버림) 우선으로 → F1 카드가 통과해 버린다(F1 이 잡는 자리)" 0 || ck "변이③ 첫 매치 우선 :: $out" 1

# ── 오염 0 · bash 3.2 문법
[ -z "$(g "$CR" status --porcelain | grep -v '^?? ' | grep -v 'design/harness/indices/' | grep -v 'design/harness/DA-r1000')" ] \
  && ck "픽스처 밖 변경 0(indices·판정문만)" 0 || ck "픽스처 밖 변경 0 :: $(g "$CR" status --porcelain | head -3)" 1
/bin/bash -n "$SRC/ft-index-move.sh" && ck "bash 3.2(/bin/bash) -n rc0" 0 || ck "bash 3.2 문법" 1

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
