#!/usr/bin/env bash
# test_file_cap_rule_subject_r1299.sh — «한 턴에 코드 파일 2개까지» 문장의 ★주어★(오케스트레이터)와 ★면제★(나노·구현 워커)가 5곳에 같은 꼴로 있는가 (정적 · 파일 읽기만 · 실행·네트워크·tmux 0).
#   계기(r1299): 문장에 주어가 없고 면제는 다른 파일(orchestration.md)에만 있어 codex 나노가 자기 규칙으로 읽고 턴을 끊었다 — 11-01 22:5x r1294(«남은 일은 다음 작업 턴에서») · 11-02 02:10~02:17 r1298 7분 멈춤(발주문에 «한도 없음» 이 있어도 AGENTS.md 가 이겼다).
#   R1 5곳 각각 «2개까지» 줄 1줄 + 그 줄에 «오케스트레이터»·«나노»·«면제» 세 낱말 전부
#   R2 codex 두 사본의 그 줄 == 정본 그 줄(바이트 — 손 편집 0 · sync-globals.py 산출)
#   R3 나노 spawn 도구(추적본·키트) BODY 첫 줄 = `echo "BODY+${_WFX}"` · `^_WFX="` 정의 1개 · `^BODY=` 줄에서 ${_WFX} 가 첫 자리
#   R4 정본의 «코드 파일 직접 수정은 한 턴 2개까지» 1회(중복 추가 방지)
#   변이 4(음성 대조 · 임시 사본): ①정본에서 «면제» 삭제 → R1 FAIL ②codex 사본만 고침 → R2 FAIL ③_WFX 를 둘째 자리로 → R3 FAIL ④정본에 문장 중복 → R4 FAIL
#   입력 경로 재정의(임시 사본 · h 전 실행): FT_RULE_FILES="<정본>:<orchestration.md>:<프로젝트 CLAUDE.md>:<codex AGENTS.md>:<codex AGENTS.user.md>" · FT_SPAWN_BIN · FT_SPAWN_KIT
#   시험 = 이 파일 하나(자기 재호출 0) · timeout 70 안에서 돈다(grep 만 · 외부 호출 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SPAWN_BIN="${FT_SPAWN_BIN:-$HERE/../bin/ft-nano-spawn.sh}"
SPAWN_KIT="${FT_SPAWN_KIT:-$HERE/../kit/fable-team/bin/ft-nano-spawn.sh}"
DEF_CANON="$HOME/.claude/CLAUDE.md"
DEF_ORCH="$HOME/.claude/rules/orchestration.md"
DEF_PROJ="$HOME/Project/Agent/BYZ-Work/BYZ-Agents/CLAUDE.md"
DEF_C1="$HOME/.codex/AGENTS.md"
DEF_C2="$HOME/.codex/AGENTS.user.md"
if [ -n "${FT_RULE_FILES:-}" ]; then
  IFS=':' read -r CANON ORCH PROJ CODEX1 CODEX2 _rest <<<"$FT_RULE_FILES"
  CANON="${CANON:-$DEF_CANON}"; ORCH="${ORCH:-$DEF_ORCH}"; PROJ="${PROJ:-$DEF_PROJ}"
  CODEX1="${CODEX1:-$DEF_C1}"; CODEX2="${CODEX2:-$DEF_C2}"
else
  CANON="$DEF_CANON"; ORCH="$DEF_ORCH"; PROJ="$DEF_PROJ"; CODEX1="$DEF_C1"; CODEX2="$DEF_C2"
fi
KEY='2개까지'
CANON_SENT='코드 파일 직접 수정은 한 턴 2개까지'
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# 줄 읽기 — 파일 없으면 «판정 불가» 1줄(하드 룰 20: 실패를 한 함수가 끝낸다)
key_line() { [ -f "$1" ] || { echo '__MISSING__'; return 0; }; grep -F -- "$KEY" "$1" | head -1; }
key_count() { [ -f "$1" ] || { echo -1; return 0; }; grep -Fc -- "$KEY" "$1"; }

r1() {  # R1 — 5곳 같은 꼴
  local lbl f n line w bad_n=0
  for pair in "정본:$CANON" "orchestration:$ORCH" "프로젝트:$PROJ" "codex-AGENTS:$CODEX1" "codex-AGENTS.user:$CODEX2"; do
    lbl="${pair%%:*}"; f="${pair#*:}"
    n="$(key_count "$f")"
    if [ "$n" = -1 ]; then bad "R1 $lbl 파일 없음: $f"; bad_n=1; continue; fi
    if [ "$n" != 1 ]; then bad "R1 $lbl «${KEY}» 줄 ${n}개 (기대 1): $f"; bad_n=1; continue; fi
    line="$(key_line "$f")"
    w=1
    for word in 오케스트레이터 나노 면제; do case "$line" in *"$word"*) ;; *) w=0;; esac; done
    [ "$w" = 1 ] || { bad "R1 $lbl 줄에 «오케스트레이터·나노·면제» 3낱말 다 있지 않음"; bad_n=1; }
  done
  [ "$bad_n" = 1 ] || ok "R1 5곳 «${KEY}» 줄 1줄 + 주어(오케스트레이터)·면제(나노) 3낱말"
}

r2() {  # R2 — codex 두 사본 == 정본(바이트)
  local c o1 o2
  c="$(key_line "$CANON")"; o1="$(key_line "$CODEX1")"; o2="$(key_line "$CODEX2")"
  if [ "$c" = '__MISSING__' ]; then bad "R2 정본 없음 — 판정 불가: $CANON"; return 0; fi
  if [ "$o1" = "$c" ]; then ok "R2 codex AGENTS.md 줄 == 정본"; else bad "R2 codex AGENTS.md 줄 != 정본(손 편집? sync-globals.py 재실행 필요)"; fi
  if [ "$o2" = "$c" ]; then ok "R2 codex AGENTS.user.md 줄 == 정본"; else bad "R2 codex AGENTS.user.md 줄 != 정본(손 편집? sync-globals.py 재실행 필요)"; fi
}

first_body_line() { grep -m1 -F 'echo "BODY+' "$1" 2>/dev/null; }
body_var_line()   { grep -m1 '^BODY=' "$1" 2>/dev/null; }
wfx_def_count()   { grep -c '^_WFX="' "$1" 2>/dev/null || true; }

r3_one() {  # R3 — 파일 1개
  local lbl="$1" f="$2" fb bl n
  [ -f "$f" ] || { bad "R3 $lbl 없음 — 판정 불가: $f"; return 0; }
  n="$(wfx_def_count "$f")"; [ "$n" = 1 ] && ok "R3 $lbl ^_WFX= 정의 1개" || bad "R3 $lbl ^_WFX= 정의 ${n:-0}개 (기대 1)"
  fb="$(first_body_line "$f")"
  [ "$fb" = 'echo "BODY+${_WFX}"' ] && ok "R3 $lbl BODY 첫 줄 = _WFX" || bad "R3 $lbl BODY 첫 줄이 _WFX 아님: ${fb:-<없음>}"
  bl="$(body_var_line "$f")"
  case "$bl" in *'${_WFX}${_SPX}'*) ok "R3 $lbl BODY 구성 첫 자리 = \${_WFX}";; *) bad "R3 $lbl BODY 구성에서 \${_WFX} 가 첫 자리 아님";; esac
}
r3() { r3_one "추적본" "$SPAWN_BIN"; r3_one "키트" "$SPAWN_KIT"; }

r4() {  # R4 — 정본 문장 중복 0
  local n
  [ -f "$CANON" ] || { bad "R4 정본 없음 — 판정 불가: $CANON"; return 0; }
  n="$(grep -Fc -- "$CANON_SENT" "$CANON")"
  [ "$n" = 1 ] && ok "R4 정본 «${CANON_SENT}» 1회" || bad "R4 정본에 같은 문장 ${n}회 (기대 1 — 중복 추가 금지)"
}

run_all() { r1; r2; r3; r4; }

echo "== 본판 (FT_RULE_FILES=$( [ -n "${FT_RULE_FILES:-}" ] && echo set || echo default ))"
run_all

# ── 변이 4(음성 대조) — 임시 사본에서 같은 함수가 FAIL 을 내는지. 본판 fail 총합에 넣지 않는다.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mk5() {  # mk5 <디렉토리> — 다섯 파일 사본
  local d="$1"
  cp "$CANON" "$d/canon.md" 2>/dev/null || printf '%s\n' "3. **오케스트레이션 게이트**(오케스트레이터 세션): 코드 파일 직접 수정은 한 턴 2개까지 · 나노·구현 워커는 면제 · Bash 로 우회 수정 금지" > "$d/canon.md"
  cp "$ORCH" "$d/orch.md" 2>/dev/null || printf '%s\n' "- **직접**: **한 턴에 코드 파일 2개까지**(3개째 게이트 차단) — 오케스트레이터 세션에만 · 나노·구현 워커는 면제" > "$d/orch.md"
  cp "$PROJ" "$d/proj.md" 2>/dev/null || printf '%s\n' "**한 턴에 코드 파일 2개까지만 직접 수정한다(오케스트레이터 세션 · 나노·워커 면제).**" > "$d/proj.md"
  cp "$CODEX1" "$d/c1.md" 2>/dev/null || cp "$d/canon.md" "$d/c1.md"
  cp "$CODEX2" "$d/c2.md" 2>/dev/null || cp "$d/canon.md" "$d/c2.md"
}
mut() {  # mut <이름> <기대 R> — 임시 사본으로 r1~r4 중 하나를 돌려 FAIL 이 나오는지
  local name="$1" want="$2" before out
  before="$fail"
  out="$("$want")"
  fail="$before"
  case "$out" in *FAIL*) ok "변이: $name → $want FAIL(기대)";; *) bad "변이: $name 를 만들었는데 $want 가 FAIL 을 안 냄";; esac
}

# 변이 1 — 정본에서 «면제» 삭제 → R1 FAIL
D="$TMP/m1"; mkdir -p "$D"; mk5 "$D"
python3 - "$D/canon.md" <<'PY'
import sys,io
p=sys.argv[1]
s=io.open(p,encoding='utf-8').read().replace('면제','')
io.open(p,'w',encoding='utf-8').write(s)
PY
CANON="$D/canon.md"; CODEX1="$D/c1.md"; CODEX2="$D/c2.md"; ORCH="$D/orch.md"; PROJ="$D/proj.md"
mut "정본 «면제» 삭제" r1

# 변이 2 — codex 사본만 고침(정본 그대로) → R2 FAIL
D="$TMP/m2"; mkdir -p "$D"
printf '%s\n' "3. **오케스트레이션 게이트**(오케스트레이터 세션): 코드 파일 직접 수정은 한 턴 2개까지 · 나노·구현 워커는 면제 · Bash 로 우회 수정 금지" > "$D/canon.md"
printf '%s\n' "$(key_line "$D/canon.md")" > "$D/c1.md"
printf '%s\n' "3. **오케스트레이션 게이트**: 코드 파일 직접 수정은 한 턴 2개까지 · Bash 로 우회 수정 금지" > "$D/c2.md"
printf '%s\n' "- **직접**: **한 턴에 코드 파일 2개까지**(3개째 게이트 차단) — 오케스트레이터 세션에만 · 나노·구현 워커는 면제" > "$D/orch.md"
printf '%s\n' "**한 턴에 코드 파일 2개까지만 직접 수정한다(오케스트레이터 세션 · 나노·워커 면제).**" > "$D/proj.md"
CANON="$D/canon.md"; CODEX1="$D/c1.md"; CODEX2="$D/c2.md"; ORCH="$D/orch.md"; PROJ="$D/proj.md"
mut "codex 사본만 고침" r2

# 변이 3 — _WFX 를 둘째 자리로(첫 BODY+ 자리에서 밀어냄) → R3 FAIL
D="$TMP/m3"; mkdir -p "$D"
python3 - "$SPAWN_BIN" "$D/spawn.sh" <<'PY'
import sys,io
src=io.open(sys.argv[1],encoding='utf-8').read()
wfx='echo "BODY+${_WFX}"\n'
i=src.index(wfx)
src2=src[:i]+src[i+len(wfx):]
j=src2.index('echo "BODY+')
k=src2.index('\n', j)+1
src2=src2[:k]+wfx+src2[k:]
io.open(sys.argv[2],'w',encoding='utf-8').write(src2)
PY
SPAWN_BIN="$D/spawn.sh"
mut "_WFX 둘째 자리" r3

# 변이 4 — 정본에 같은 문장 중복 → R4 FAIL
D="$TMP/m4"; mkdir -p "$D"
printf '%s\n' "3. **오케스트레이션 게이트**(오케스트레이터 세션): 코드 파일 직접 수정은 한 턴 2개까지 · 나노·구현 워커는 면제" "복사본: 코드 파일 직접 수정은 한 턴 2개까지" > "$D/canon.md"
printf '%s\n' "$(key_line "$D/canon.md")" > "$D/c1.md"; cp "$D/c1.md" "$D/c2.md"
printf '%s\n' "- **직접**: **한 턴에 코드 파일 2개까지**(3개째 게이트 차단) — 오케스트레이터 세션에만 · 나노·구현 워커는 면제" > "$D/orch.md"
printf '%s\n' "**한 턴에 코드 파일 2개까지만 직접 수정한다(오케스트레이터 세션 · 나노·워커 면제).**" > "$D/proj.md"
CANON="$D/canon.md"; CODEX1="$D/c1.md"; CODEX2="$D/c2.md"; ORCH="$D/orch.md"; PROJ="$D/proj.md"
mut "정본 문장 중복" r4

echo "== 총 FAIL $fail"
[ "$fail" = 0 ] || exit 1
exit 0
