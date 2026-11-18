#!/usr/bin/env bash
# test_directive_watch_harness_line_r2256.sh — r2256 감시가 «- 지시 #:» 줄과 «4323②» 꼴 번호도 담당으로 읽는다: 반례 ①~⑥ + 변이 M1~M3(원본 대조) + bin·kit 같은 글자.
# 임시 git 리포(가짜 md 원장 · 가짜 harness·팀 카드) · --now 고정 · 실 STATE·실 쪽지 0 · 네트워크 0 · sleep 0.
# 돌리기: timeout 70 bash harness/tests/test_directive_watch_harness_line_r2256.sh   (기준판 대조 = TOOL_RUN=<옛 파일> 로 같은 시험)
set -uo pipefail
export TZ=Asia/Seoul
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
TOOL="$BIN/ft_directive_watch.py"; export PYTHONPATH="$BIN"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
RC=""; OUT=""; LINKS=""; fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
NOW=1794900000; S_OLD=$((NOW - 7200)); D_CARD="@$((NOW - 600)) +0900"; D0="2026-10-01 09:30:00 +0900"
gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
new_root() {  # 임시 루트 = git 리포(main) + 카드 루트 표(팀 카드 · harness 카드) + 명부 + 가짜 mbox + 원장(오빠 행 <번호...>)
  R="$(mktemp -d "$T/r.XXXXXX")"; R="$(cd "$R" && pwd -P)"; mkdir -p "$R/.fable-team/state" "$R/design/teams/planner"
  git -C "$R" init -q -b main; printf '.fable-team/\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "2026-10-01 09:00:00 +0900" init
  printf '*\t.\tmain\tdesign/teams/*/indices\nharness\t.\tmain\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"byz-planner-master-claude#9"}\n' > "$R/.fable-team/seats-planner.json"
  printf '#!/usr/bin/env bash\necho "QUEUED seq=1 to=$2"\n' > "$R/mbox.sh"
  { printf '%s\n' "# VERDICTS planner#99" "| # | 시각 | 판정 |" "|---|---|---|"; for n in "$@"; do printf '| %s | 11-18 19:0x | 오빠 «네»(slack %s.1) 지시 |\n' "$n" "$S_OLD"; done; } > "$R/design/teams/planner/VERDICTS-planner-99-x.md"
  git -C "$R" add -A design; gc "$R" "$D0" ledger
}
card() {  # <카드 경로(루트 기준)> <줄...> — 카드를 쓰고 10분 전 커밋(멈춤 0)
  mkdir -p "$R/$(dirname "$1")"; local f="$1"; shift; printf '%s\n' "# 인덱스: x" "$@" > "$R/$f"; git -C "$R" add -A design; gc "$R" "$D_CARD" card
}
run() { OUT="$(cd "$R" && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" FT_DIRECTIVE_NANO_REPOS="$R" FT_DIRECTIVE_FLOOR=0 python3 "${TOOL_RUN:-$TOOL}" status --now "$NOW" 2>&1)"; RC=$?; }
links() {  # 판정 번호 → 담당 카드 stem (한 줄에 «n stem»)
  LINKS="$(cd "$R" && FT_ROOT="$R" python3 - "${TOOL_RUN:-$TOOL}" "$R" "$NOW" <<'PY' 2>&1
import importlib.util, sys
from pathlib import Path
s = importlib.util.spec_from_file_location("w", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
found, _ = m.Watch(Path(sys.argv[2]), float(sys.argv[3]), True).links()
print("\n".join(f"{n} {c['stem']}" for n in sorted(found) for c in found[n]))
PY
)"; }
owned() { links; printf '%s\n' "$LINKS" | grep -qx "$1 $2"; }      # <n> <stem> — n 의 담당 = stem
none() { run; printf '%s' "$OUT" | grep -q "^담당 없음 판정 $1 · "; }  # <n> — status 에 «담당 없음 n»
HC=design/harness/indices/대기/hc.md
C1="- 지시 #: master#320 #328897 · planner#357 #328891(오빠 지시 감시 4323② 담당 없음)"
C2="- 지시 #: master#332 #337208 · 판정 4392"
C3="- 지시 #: master-pi#238 #296079 · 오빠 «네» 1794561170.522909 · 개설 #296045 2008자 · 4784"
C6="- 지시 #: #4323② · r4323② · a4323②"
c1() { new_root 4323; card "$HC" "$C1"; }; c2() { new_root 4392; card "$HC" "$C2"; }; c3() { new_root 4784 1794; card "$HC" "$C3"; }; c6() { new_root 4323; card "$HC" "$C6"; }

# ① harness 카드 «- 지시 #: … 4323② …» → 4323 담당 = hc · 담당 없음 0
c1; owned 4323 hc && ! none 4323 && [ "$RC" = 0 ] && ok "① «- 지시 #:» + 4323② → 담당 hc · 담당 없음 0 · rc0" || bad "① rc=$RC :: $LINKS :: $OUT"
lap ①
# ② «- 지시 #: … 판정 4392» → 담당 1
c2; owned 4392 hc && ! none 4392 && ok "② «- 지시 #: 판정 4392» → 담당 hc" || bad "② rc=$RC :: $LINKS :: $OUT"
lap ②
# ③ 맨 숫자(4784 · slack ts 1794… · 2008자 · #seq) → 담당 0 · 4784·1794 모두 담당 없음
c3; links; [ -z "$LINKS" ] && none 4784 && printf '%s' "$OUT" | grep -q '^담당 없음 판정 1794 · ' && ok "③ 맨 숫자·slack ts·글자 수 → 담당 0(4784 · 1794 담당 없음)" || bad "③ :: $LINKS :: $OUT"
lap ③
# ④ 팀 카드 «- 지시: 판정 4409» → 담당 1 (기존 꼴 불변)
new_root 4409; card design/teams/qa/indices/대기/tc.md "- 지시: 판정 4409"; owned 4409 tc && ! none 4409 && ok "④ 팀 카드 «- 지시: 판정 4409» → 담당 tc" || bad "④ :: $LINKS :: $OUT"
lap ④
# ⑤ 근거 줄에만 4323② → 지시 줄 아님 → 담당 0
new_root 4323; card "$HC" "- 근거:" "  - ⓧ1 live 감시가 4323② 를 놓침"; links; [ -z "$LINKS" ] && none 4323 && ok "⑤ 근거 줄 4323② → 담당 0" || bad "⑤ :: $LINKS :: $OUT"
lap ⑤
# ⑥ #4323② · r4323② · a4323② → 담당 0
c6; links; [ -z "$LINKS" ] && none 4323 && ok "⑥ #·글자 붙은 4323② → 담당 0" || bad "⑥ :: $LINKS :: $OUT"
lap ⑥

# 변이 (사본에서만) — 변이마다 같은 사례를 원본으로 1회 더(반대 결과 대조)
mut() { python3 - "$TOOL" "$1" "$2" "$3" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]; s = open(src, encoding="utf-8").read(); assert a in s, a
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
mut "$T/m1.py" '"-E", "-e", "^- 지시( #)?:"' '"-e", "^- 지시:"'
mut "$T/m2.py" '(?<![#\d.A-Za-z:/-])(\d{4,5})' '(\d{4,5})'
mut "$T/m3.py" '(\d{4,5})[①-⑳]' '(\d{4,5})[①-⑳]?'
c1; TOOL_RUN="$T/m1.py" none 4323 && m1a=1 || m1a=0; ! none 4323 && o1a=1 || o1a=0
c2; TOOL_RUN="$T/m1.py" none 4392 && m1b=1 || m1b=0; ! none 4392 && o1b=1 || o1b=0
[ "$m1a$m1b$o1a$o1b" = 1111 ] && ok "M1(grep «^- 지시:» 로 되돌림) → ① ② 담당 없음 · 원본 = 담당 1" || bad "M1 m=$m1a$m1b o=$o1a$o1b"
c6; TOOL_RUN="$T/m2.py" owned 4323 hc && m2=1 || m2=0; links; [ -z "$LINKS" ] && o2=1 || o2=0
[ "$m2$o2" = 11 ] && ok "M2(원문자 앞 거름 뺌) → ⑥ 담당 1 · 원본 = 0" || bad "M2 m=$m2 o=$o2"
c3; TOOL_RUN="$T/m3.py" owned 4784 hc && m3=1 || m3=0; links; [ -z "$LINKS" ] && o3=1 || o3=0
[ "$m3$o3" = 11 ] && ok "M3(원문자 없는 맨 숫자도 읽음) → ③ 담당 1 · 원본 = 0" || bad "M3 m=$m3 o=$o3"
lap mutation

# bin·kit 같은 글자 · 문법 · 줄 수
cmp -s "$BIN/ft_directive_watch.py" "$KIT/ft_directive_watch.py" && ok "bin·kit 같은 글자" || bad "bin·kit 다름"
python3 -m py_compile "$TOOL" 2>/dev/null && ok "py_compile" || bad "문법"
n="$(wc -l < "$TOOL")"; [ "$n" -le 320 ] && ok "ft_directive_watch.py ≤320줄($n)" || bad "줄수 $n"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
