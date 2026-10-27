#!/usr/bin/env bash
# r880 재설계 r3 변이 4 — 고침 1개당 변이 1개 · 각 변이가 «그 칸»만 KILL 하는지.
#   사용: bash feature-pack/fable-team/harness/evidence/r880/mutation.sh   (rc 0 = 넷 다 KILLED)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PK="$(cd -- "$HERE/../../../.." && pwd)"          # feature-pack
SRC="$PK/fable-team/harness/bin/ft-wt-sweep.sh"
TEST="$PK/fable-team/harness/tests/test_wt_sweep_land_plan_r880.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0

# mut <이름> <기대 FAIL 칸 접두> <파이썬 조각 파일> — 조각은 s(도구 본문 문자열)를 고쳐 쓴다
mut() {
  local name="$1" want="$2" py="$3" d="$T/$1" out
  mkdir -p "$d"; cp "$SRC" "$d/ft-wt-sweep.sh"
  python3 "$py" "$d/ft-wt-sweep.sh" || { echo "MUTATION-BROKEN $name — 치환 실패"; fail=$((fail+1)); return; }
  if cmp -s "$SRC" "$d/ft-wt-sweep.sh"; then echo "MUTATION-BROKEN $name — 치환이 안 먹었다"; fail=$((fail+1)); return; fi
  out="$(WT_TEST_SRC="$d" bash "$TEST" 2>&1)"
  if printf '%s\n' "$out" | grep '^FAIL ' | grep -q -- "$want"; then
    echo "KILLED $name — $(printf '%s\n' "$out" | grep '^FAIL ' | head -1 | cut -c1-160)"
  else
    echo "MUTATION-WRONG-CELL $name — 기대 칸 «${want}» 아님: $(printf '%s\n' "$out" | grep '^FAIL ' | head -3 | cut -c1-120 | tr '\n' ' ')"
    fail=$((fail+1))
  fi
}

echo "== 변이 1: 사본마다 직전 재검사 제거(고침 1) — ⓐ 가 잡아야 한다"
cat > "$T/m1.py" <<'MPY1'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '    if ! land_live; then echo "ERROR 판정 불가 — ${p##*/}: $LAND_ERR(계획 제외 · 삭제 0)" >&2; bad=$((bad+1)); continue; fi'
assert old in s, "사본별 재검사 줄 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, "", 1))
MPY1
mut refresher "ⓐ" "$T/m1.py"

echo "== 변이 2: tmux·lsof 실패를 «좌석 0» 으로(고침 2) — ⓑ 가 잡아야 한다"
cat > "$T/m2.py" <<'MPY2'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = """  run7 "tmux pane" "$TMUXB" list-panes -a -F '#{pane_current_path}' || { LAND_ERR="$RUN7_MSG"; return 1; }   # «no server running» 도 실패 — 문구 면제 0(DA r3 ④)"""
assert old in s, "tmux 호출 줄 없음"
new = """  run7 "tmux pane" "$TMUXB" list-panes -a -F '#{pane_current_path}' || RUN7_OUT=""   # 변이: 실패를 좌석 0 으로"""
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
MPY2
mut tmuxerr "ⓑ" "$T/m2.py"

echo "== 변이 3: 계획을 ft-hil 에 등록하지 않음(고침 3) — ⓒ 가 잡아야 한다"
cat > "$T/m3.py" <<'MPY3'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '  hmsg="$(hil_register "$out")" || { echo "ERROR ft-hil 등록 실패 — 계획 $out · 알림 0(다음 pass 재시도)" >&2; return 1; }'
assert old in s, "등록 줄 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, '  hmsg="스크립트 $out"', 1))
MPY3
mut nohil "ⓒ" "$T/m3.py"

echo "== 변이 4: 알림 «전»에 보냄 표지(고침 4) — ⓓ 가 잡아야 한다"
cat > "$T/m4.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = """    if [ -n "$to" ] && [ -n "$MB" ] && bash "$MB" send"""
ins = """    case "$ln" in *land-copies.sh.hil*) m4="$(printf '%s' "$ln" | sed -nE 's#.*계획 ([^ ]*land-copies\\.sh\\.hil).*#\\1#p')"; [ -n "$m4" ] && [ -f "$m4.sig" ] && cp "$m4.sig" "$m4.sent" ;; esac
"""
assert old in s, "고침 4 구간 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, ins + old, 1))
PY
mut earlysent "ⓓ" "$T/m4.py"

echo "== 변이 5: 경로 정규화 제거(DA r2 ①) — ⓔ① 이 잡아야 한다"
cat > "$T/m5.py" <<'MPY5'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '  LIVE="$RUN7_OUT"'
assert old in s, "LIVE 채우는 줄 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, '  LIVE="$raw"   # 변이: 정규화 없이', 1))
MPY5
mut norealpath "ⓔ①" "$T/m5.py"

echo "== 변이 6: mtime 대조 제거(DA r2 ③) — ⓔ③ 이 잡아야 한다"
cat > "$T/m6.py" <<'MPY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '[ "$mt" = "$want_mt" ] || { echo "mtime 바뀜'
assert old in s, 'mtime 대조 구간 없음'
open(p, "w", encoding="utf-8").write(s.replace(old, '[ -n "$mt" ] || { echo "mtime 바뀜', 1))
MPY
mut nomtime "ⓔ③" "$T/m6.py"

echo "== 변이 7: 사본별 land_live rc 무시(DA r3 ④) — ⓔ④ 가 잡아야 한다"
cat > "$T/m7.py" <<'MPY7'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '    if ! land_live; then echo "ERROR 판정 불가'
assert old in s, "판정 불가 줄 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, '    if false; then echo "ERROR 판정 불가', 1))
MPY7
mut ignrc "ⓔ④" "$T/m7.py"

echo "== 변이 8: tmux 시간 상한 제거(DA r3 ④) — ⓔ⑤ 가 잡아야 한다"
cat > "$T/m8.py" <<'MPY8'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '"$RUN7_SEC" "$@"'
assert old in s, "run7 상한 인자 줄 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, '9999 "$@"', 1))
MPY8
mut nocap "ⓔ⑤" "$T/m8.py"

echo "== 변이 9: h 등록 실패를 성공으로(DA r2 ⑥) — ⓒ 가 잡아야 한다"
cat > "$T/m9.py" <<'MPY9'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '  hmsg="$(hil_register "$out")" || { echo "ERROR ft-hil 등록 실패 — 계획 $out · 알림 0(다음 pass 재시도)" >&2; return 1; }'
assert old in s, "등록 실패 줄 없음"
new = '  hmsg="$(hil_register "$out")" || hmsg="스크립트 $out"'
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
MPY9
mut hilfailok "ⓒ" "$T/m9.py"

echo "== 변이 10: run7 의 rc 무시(출력 유무로 성공 판단 · DA r3 반송서) — ⓑ·ⓒ·ⓓ 가 잡아야 한다"
cat > "$T/m10.py" <<'MPY10'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '  [ "$rc" -eq 0 ] && { RUN7_OUT="$o"; return 0; }'
assert old in s, "run7 성공 판정 줄 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, '  [ -n "$o" ] && { RUN7_OUT="$o"; return 0; }   # 변이: 출력 유무로 성공', 1))
MPY10
mut run7rc "ⓑ" "$T/m10.py"
echo
if [ "$fail" -eq 0 ]; then echo "ALL MUTATIONS KILLED (10)"; exit 0; fi
echo "MUTATION PROBLEM $fail"; exit 1
