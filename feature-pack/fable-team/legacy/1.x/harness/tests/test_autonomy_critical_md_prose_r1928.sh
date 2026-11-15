#!/usr/bin/env bash
# test_autonomy_critical_md_prose_r1928.sh — r1928 D2 ⑤ destroy 판정은 .md 에서 코드 줄(펜스 안 · 인라인 `코드` · 들여쓰기 4칸)만 본다
#   반례 ①~⑧·⑩~⑫ · 키트 사본 cmp0 · 변이 M1~M6 · 기존 크리티컬 시험(⑨)은 따로 돌린다(시험 1개 70초 상한)
#   격리: 임시 리포(origin bare + clone) · 실 상태·실 원격·press 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:200}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T/iso"; R="$W"
pr() {  # pr <경로> <줄…> → PRSHA(origin/main 에서 1커밋)
  git -C "$R" checkout -q -B "pr$RANDOM" origin/main; mkdir -p "$R/$(dirname -- "$1")"
  printf '%s\n' "${@:2}" > "$R/$1"; cm "$R" "r1928 case"; PRSHA="$(sha "$R" HEAD)"; git -C "$R" checkout -q main; }
crit() { out="$(python3 "${2:-$BIN}/autonomy_scope_classify.py" classify "$1" --repo "$R" --critical 2>&1)"; rc=$?; }
okc() { [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; }
dst() { [ "$rc" = 3 ] && [[ $out =~ ^CRITICAL\ kind=destroy\  ]]; }
G1='| G1 닫으려고 직접 실험한다 | 칸의 닫는 증거가 «실제 동작 1건» 이면, 닫기 주인이 그 동작을 일으킬 **진짜 입력 1개**를 표준 입구로 넣는다(실제 대기 카드 1장 접수 · 실제 Slack 글 1개 · 실제 좌석 승계 1회). 실험 줄 = «넣은 입력 · 넣은 입구 · 기대한 기록 · 나온 기록» 4칸 | journal·state·Redis·화면에 직접 쓰기 · 손 launch·손 Enter·손 kill · 가짜 카드 · 통과하도록 입력 고르기(하드 룰 11 그대로). 실험이 실패하면 그 값이 그 칸의 값이다 | [정리] 둘째 줄 «오늘 실험 n(닫힌 칸 k)» · 쪽지 lint(r1916)의 반송 문구에 «실험 1개를 적어라» |'
pr docs/c1.md '# 지침' '' '손 launch·손 Enter·손 kill · 가짜 카드'; C1="$PRSHA"; crit "$C1"; okc; ck "① .md 본문 줄 «손 kill» → CRITICAL-OK" $?
pr docs/c2.md '# 정리' '' '```bash' 'rm -rf /tmp/x' '```'; C2="$PRSHA"; crit "$C2"; dst; ck "② .md \`\`\`bash 펜스 안 rm -rf → destroy" $?
pr docs/c3.md '정리는 `tmux kill-server` 로 하지 않는다'; C3="$PRSHA"; crit "$C3"; dst; ck "③ .md 펜스 밖 인라인 코드 tmux kill-server → destroy" $?
pr docs/c4.md '~~~' 'git push --force origin main' '~~~'; C4="$PRSHA"; crit "$C4"; dst; ck "④ .md ~~~ 펜스 안 git push --force → destroy" $?
pr bin/c5.sh '# 손 kill 금지'; C5="$PRSHA"; crit "$C5"; dst; ck "⑤ .sh 주석 줄 손 kill → destroy(코드 파일 그대로)" $?
out="$(python3 -c "
import sys; sys.path.insert(0, '$BIN'); import autonomy_scope_rules as r
b = [('docs/c6.md', [(1, '손 kill')], True)]
print(r.critical_kinds(b, show=lambda p: '')[0], r.critical_kinds(b)[0], r.prose_line_exempt('docs/c6.md', 1, '손 kill', lambda p: '손 kill\n'))" 2>&1)"; rc=$?
[ "$out" = "destroy destroy True" ]; ck "⑥ show 가 \"\"·없음 → destroy(닫힌 쪽) · 같은 줄 판독되면 예외" $?
pr docs/c7.md '-----BEGIN RSA PRIVATE KEY-----' '손 kill'; crit "$PRSHA"; [ "$rc" = 3 ] && [[ $out =~ ^CRITICAL\ kind=secret\  ]]; ck "⑦ .md 비밀 꼴 줄 → kind=secret 그대로" $?
pr docs/main-team-governance.md '| 지침 | 좌석이 하는 일(셀 수 있게) | 하지 않는 일 | 걸리는 곳 |' '|---|---|---|---|' "$G1"; C8="$PRSHA"; crit "$C8"; okc; ck "⑧ 팩 PR #1138 의 214행 원문 → CRITICAL-OK" $?
pr docs/c10.md '손 kill 본문' '' '실행: `rm -rf /tmp/x' '`'; C10="$PRSHA"; crit "$C10"; dst && [[ $out == *"docs/c10.md:3 "* ]]; ck "⑩ 여러 줄 inline code(백틱 짝 남음) → destroy · ⑪ 다른 문단 «손 kill» 은 거절 사유 아님" $?
pr docs/c11.md '손 kill 본문' '' '`열린 백틱'; C11="$PRSHA"; crit "$C11"; okc; ck "⑪ 다른 문단의 백틱 짝 남음이 «손 kill» 본문 줄로 번지지 않음 → CRITICAL-OK" $?
pr docs/c12.md '# 예' '' '    kill -9 1'; crit "$PRSHA"; dst; ck "⑫ 들여쓰기 4칸 줄 kill -9 1 → destroy" $?
cmp -s "$BIN/autonomy_scope_rules.py" "$BIN/../kit/fable-team/bin/autonomy_scope_rules.py"; ck "키트 사본 cmp0 autonomy_scope_rules.py" $?
mut() {  # mut <이름> <원문> <바꿀 글> → $T/mut-<이름>(rules 만 바꾼 bin)
  local mb="$T/mut-$1"; mkdir -p "$mb"; for f in "$BIN"/*; do ln -s "$f" "$mb/$(basename "$f")"; done; rm -f "$mb/autonomy_scope_rules.py"
  python3 - "$BIN/autonomy_scope_rules.py" "$mb/autonomy_scope_rules.py" "$2" "$3" <<'PY' || { echo "FAIL 변이 $1 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1, sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
}
mut m1 ' or prose_line_exempt(path, no, txt, show)' ''
crit "$C1" "$T/mut-m1"; dst && { crit "$C8" "$T/mut-m1"; dst; }; ck "M1 prose_line_exempt 호출 삭제 → ①·⑧ destroy(빨강)" $?
mut m2 '    if fence or at:' '    if False:'
crit "$C2" "$T/mut-m2"; okc && { crit "$C4" "$T/mut-m2"; okc; }; ck "M2 펜스 판정 삭제 → ②·④ 새어 통과(빨강)" $?
mut m3 'return not any(CRIT_DESTROY.search(s) for s in md_spans(txt) or [])' 'return True'
crit "$C3" "$T/mut-m3"; okc; ck "M3 인라인 코드 검사 삭제 → ③ 새어 통과(빨강)" $?
mut m4 'if show and (path or "").lower().endswith(".md") else' 'if show else'
crit "$C5" "$T/mut-m4"; okc; ck "M4 .md 확장자 검사 삭제 → ⑤ 새어 통과(빨강)" $?
mut m5 'if any(md_spans(ln) is None for ln in lines[a:b + 1]):' 'if False:'
crit "$C10" "$T/mut-m5"; okc; ck "M5 문단 백틱 짝 검사 삭제 → ⑩ 새어 통과(빨강)" $?
mut m6 'for ln in lines[a:b + 1]):' 'for ln in lines):'
crit "$C11" "$T/mut-m6"; dst; ck "M6 문단 경계 무시(파일 전체) → ⑪ destroy(빨강)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
