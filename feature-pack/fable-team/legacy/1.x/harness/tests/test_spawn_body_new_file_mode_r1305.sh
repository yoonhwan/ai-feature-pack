#!/usr/bin/env bash
# test_spawn_body_new_file_mode_r1305.sh — 나노 발주문(ft-nano-spawn.sh BODY)에 «새 파일 모드» 고정 줄이 BODY+ 둘째 자리로 실렸는가 (정적 · 파일 읽기만 · 실행·tmux·네트워크 0).
#   계기(r1305): 자율 범위 게이트(scope-approve)는 «새 파일(A) + 100755» 를 사람 승인으로 돌리고 그 종류는 학습하지 않는다 — 11-02 r1301 나노가 새 시험을 755 로 커밋해 SCOPE-REJECT(h5796) → 재작업·재격리·재승인 한 바퀴 · r1298 새 bin 도구는 755 가 맞는데 산출 보고에 «사람 승인 필요» 줄이 없어 아침 질문으로 늦게 올라갔다. 나노가 읽는 유일한 자리(발주문)에 규칙 1줄을 고정한다.
#   R0 시험 파일 자신이 실행 비트 0(100644) — 규칙의 첫 적용
#   R1 추적본·키트 각각 `^_NFX="` 정의 정확히 1개 · 그 줄에 «100644»·«bash»·«사람 승인»·«새 실행 파일» 네 낱말 전부
#   R2 `echo "BODY+${_NFX}"` 가 `echo "BODY+${_WFX}"` 의 바로 다음 줄(둘째 자리)
#   R3 `^BODY=` 줄에서 ${_WFX} 가 첫 BODY+ 자리 · ${_NFX} 가 그 바로 뒤(둘째) — r1299 첫 자리 그대로
#   R4 추적본 == 키트(_NFX 정의 줄·BODY+_NFX echo 줄 바이트)
#   변이 3(음성 대조 · 임시 사본): ①_NFX 정의 삭제 → R1 FAIL ②_NFX 를 _WFX 앞으로 → R2·R3 FAIL ③키트만 고침 → R4 FAIL
#   입력 경로 재정의: FT_SPAWN_BIN · FT_SPAWN_KIT (파일 없음 = «판정 불가» 1줄 rc1)
#   시험 = 이 파일 하나(자기 재호출 0) · timeout 70 안에서 돈다(grep·awk 만 · 외부 호출 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SPAWN_BIN="${FT_SPAWN_BIN:-$HERE/../bin/ft-nano-spawn.sh}"
SPAWN_KIT="${FT_SPAWN_KIT:-$HERE/../kit/fable-team/bin/ft-nano-spawn.sh}"
SELF="${BASH_SOURCE[0]:-$0}"
KIT_ORIG="$SPAWN_KIT"   # 변이 3 이 «진짜 키트» 를 쓰도록 — 본판 경로를 고정한다
BIN_ORIG="$SPAWN_BIN"   # 변이마다 추적본 진본에서 다시 뜯는다
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# ── 판정 불가: 입력 파일이 없으면 함수가 아니라 여기서 1줄로 끝낸다(하드 룰 20).
if [ ! -f "$SPAWN_BIN" ] || [ ! -f "$SPAWN_KIT" ]; then
  echo "판정 불가: 입력 파일 없음 (bin=$SPAWN_BIN kit=$SPAWN_KIT)"
  exit 1
fi

nfx_def_line() { grep -m1 '^_NFX="' "$1" 2>/dev/null; }
nfx_def_count() { grep -c '^_NFX="' "$1" 2>/dev/null || true; }
nfx_echo_lineno() { grep -n -F 'echo "BODY+${_NFX}"' "$1" 2>/dev/null | head -1 | cut -d: -f1; }
wfx_echo_lineno() { grep -n -F 'echo "BODY+${_WFX}"' "$1" 2>/dev/null | head -1 | cut -d: -f1; }
body_var_line() { grep -m1 '^BODY=' "$1" 2>/dev/null; }
# BODY+ 로 echo 되는 고정 줄 변수 이름들(순서대로)
echo_vars() { grep -oE 'echo "BODY\+\$\{[A-Za-z0-9_]+\}"' "$1" 2>/dev/null | sed -E 's/.*\$\{([A-Za-z0-9_]+)\}.*/\1/'; }
# 약속: 서브셸이 아니라 awk ENVIRON 으로 4만 자짜리 BODY= 줄을 넘긴다(인자 길이 한계 회피)
line_pos() { BL="$1" V="$2" awk 'BEGIN{print index(ENVIRON["BL"], "${" ENVIRON["V"] "}")}'; }
line_has() { case "$1" in *"$2"*) return 0;; *) return 1;; esac; }

r0() {  # R0 — 시험 파일 자신이 실행 비트 0
  if [ ! -f "$SELF" ]; then bad "R0 시험 파일 없음 — 판정 불가: $SELF"; return 0; fi
  if [ -x "$SELF" ]; then bad "R0 시험 파일에 실행 비트가 있다(규칙 위반: 100644 · bash <파일> 로 부른다): $SELF"
  else ok "R0 시험 파일 실행 비트 0"; fi
}

r1_one() {  # R1 — 파일 1개
  local lbl="$1" f="$2" n line w=1
  if [ ! -f "$f" ]; then bad "R1 $lbl 없음 — 판정 불가: $f"; return 0; fi
  n="$(nfx_def_count "$f")"
  if [ "$n" != 1 ]; then bad "R1 $lbl ^_NFX= 정의 ${n:-0}개 (기대 1)"; return 0; fi
  line="$(nfx_def_line "$f")"
  for word in 100644 bash 사람 승인 '새 실행 파일'; do
    line_has "$line" "$word" || w=0
  done
  if [ "$w" = 1 ]; then ok "R1 $lbl ^_NFX= 정의 1개 + «100644·bash·사람 승인·새 실행 파일» 4낱말"
  else bad "R1 $lbl _NFX 줄에 네 낱말(100644·bash·사람 승인·새 실행 파일)이 다 있지 않음"; fi
}
r1() { r1_one "추적본" "$SPAWN_BIN"; r1_one "키트" "$SPAWN_KIT"; }

r2_one() {  # R2 — echo _NFX 가 echo _WFX 바로 다음 줄
  local lbl="$1" f="$2" wn nn
  if [ ! -f "$f" ]; then bad "R2 $lbl 없음 — 판정 불가: $f"; return 0; fi
  wn="$(wfx_echo_lineno "$f")"; nn="$(nfx_echo_lineno "$f")"
  if [ -z "$wn" ]; then bad "R2 $lbl echo _WFX 줄 없음"; return 0; fi
  if [ -z "$nn" ]; then bad "R2 $lbl echo _NFX 줄 없음"; return 0; fi
  if [ "$nn" = "$((wn + 1))" ]; then ok "R2 $lbl BODY+ 둘째 줄 = _NFX (줄 $nn)"
  else bad "R2 $lbl echo _NFX 줄($nn)이 echo _WFX 줄($wn) 바로 다음이 아님"; fi
}
r2() { r2_one "추적본" "$SPAWN_BIN"; r2_one "키트" "$SPAWN_KIT"; }

r3_one() {  # R3 — BODY= 줄 안 순서
  local lbl="$1" f="$2" bl pw pn v p moved=0
  if [ ! -f "$f" ]; then bad "R3 $lbl 없음 — 판정 불가: $f"; return 0; fi
  bl="$(body_var_line "$f")"
  if [ -z "$bl" ]; then bad "R3 $lbl ^BODY= 줄 없음"; return 0; fi
  pw="$(line_pos "$bl" _WFX)"; pn="$(line_pos "$bl" _NFX)"
  if [ "${pw:-0}" -le 0 ]; then bad "R3 $lbl BODY= 줄에 \${_WFX} 없음"; return 0; fi
  if [ "${pn:-0}" -le 0 ]; then bad "R3 $lbl BODY= 줄에 \${_NFX} 없음"; return 0; fi
  for v in $(echo_vars "$f"); do
    [ "$v" = _WFX ] && continue
    p="$(line_pos "$bl" "$v")"
    [ "${p:-0}" -gt 0 ] || continue          # BODY= 줄에 안 쓰이는 변수($로만 참조 등)는 건너뛴다
    [ "$p" -gt "$pw" ] || moved=1
  done
  if [ "$moved" = 0 ]; then ok "R3 $lbl BODY= 줄 첫 BODY+ 자리 = \${_WFX}"
  else bad "R3 $lbl BODY= 줄에서 \${_WFX} 가 첫 BODY+ 자리 아님"; fi
  if [ "$(line_pos "$bl" _NFX)" = "$((pw + 7))" ]; then ok "R3 $lbl BODY= 줄 둘째 자리 = \${_NFX}"
  else bad "R3 $lbl BODY= 줄에서 \${_NFX} 가 \${_WFX} 바로 뒤가 아님"; fi
}
r3() { r3_one "추적본" "$SPAWN_BIN"; r3_one "키트" "$SPAWN_KIT"; }

r4() {  # R4 — 추적본 == 키트(그 두 줄 바이트)
  local b1 b2 k1 k2
  if [ ! -f "$SPAWN_BIN" ] || [ ! -f "$SPAWN_KIT" ]; then bad "R4 입력 파일 없음 — 판정 불가"; return 0; fi
  b1="$(nfx_def_line "$SPAWN_BIN")"; k1="$(nfx_def_line "$SPAWN_KIT")"
  b2="$(grep -m1 -F 'echo "BODY+${_NFX}"' "$SPAWN_BIN" 2>/dev/null)"; k2="$(grep -m1 -F 'echo "BODY+${_NFX}"' "$SPAWN_KIT" 2>/dev/null)"
  if [ -n "$b1" ] && [ "$b1" = "$k1" ]; then ok "R4 추적본 == 키트 (_NFX 정의 줄)"
  else bad "R4 추적본 != 키트 (_NFX 정의 줄 — 키트 미반영?)"; fi
  if [ -n "$b2" ] && [ "$b2" = "$k2" ]; then ok "R4 추적본 == 키트 (BODY+_NFX echo 줄)"
  else bad "R4 추적본 != 키트 (BODY+_NFX echo 줄 — 키트 미반영?)"; fi
}

run_all() { r0; r1; r2; r3; r4; }

echo "== 본판 (FT_SPAWN_BIN=$( [ -n "${FT_SPAWN_BIN:-}" ] && echo set || echo default ))"
run_all

# ── 변이 3(음성 대조) — 임시 사본에서 같은 함수가 FAIL 을 내는지. 본판 fail 총합에 넣지 않는다.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mut() {  # mut <이름> <기대 함수...> — 하나라도 FAIL 을 안 내면 bad
  local name="$1"; shift
  local before out fn allfail
  before="$fail"; allfail=1
  for fn in "$@"; do
    out="$("$fn")" || true
    case "$out" in *FAIL*) ;; *) allfail=0;; esac
  done
  fail="$before"
  if [ "$allfail" = 1 ]; then ok "변이: $name → $* FAIL(기대)"
  else bad "변이: $name 를 만들었는데 $* 가 FAIL 을 안 냄"; fi
}

# 변이 1 — _NFX 정의 삭제 → R1 FAIL
D="$TMP/m1"; mkdir -p "$D"
grep -v '^_NFX="' "$BIN_ORIG" > "$D/spawn.sh"
SPAWN_BIN="$D/spawn.sh"
mut "_NFX 정의 삭제" r1

# 변이 2 — _NFX 를 _WFX 앞으로(echo 줄·BODY= 줄 둘 다) → R2·R3 FAIL
D="$TMP/m2"; mkdir -p "$D"
python3 - "$BIN_ORIG" "$D/spawn.sh" <<'PY'
import sys, io
src = io.open(sys.argv[1], encoding='utf-8').read()
a = 'echo "BODY+${_WFX}"\necho "BODY+${_NFX}"\n'
b = 'echo "BODY+${_NFX}"\necho "BODY+${_WFX}"\n'
if a not in src:
    sys.exit('SWAP-PATTERN-MISSING')
src = src.replace(a, b, 1).replace('${_WFX}${_NFX}', '${_NFX}${_WFX}', 1)
io.open(sys.argv[2], 'w', encoding='utf-8').write(src)
PY
SPAWN_BIN="$D/spawn.sh"
mut "_NFX 를 _WFX 앞으로" r2 r3

# 변이 3 — 키트만 고침(추적본 사본에 _NFX 없음) → R4 FAIL
D="$TMP/m3"; mkdir -p "$D"
grep -v '^_NFX="' "$BIN_ORIG" | grep -v -F 'echo "BODY+${_NFX}"' > "$D/spawn.sh"
SPAWN_BIN="$D/spawn.sh"; SPAWN_KIT="$KIT_ORIG"
mut "키트만 고침" r4

echo "== 총 FAIL $fail"
[ "$fail" = 0 ] || exit 1
exit 0
