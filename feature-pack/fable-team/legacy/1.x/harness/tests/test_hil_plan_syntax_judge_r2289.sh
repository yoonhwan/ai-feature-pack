#!/usr/bin/env bash
# test_hil_plan_syntax_judge_r2289.sh — r2289(r1101 재접수): ft-hil 등록 전 계획의 bash 문법 · 해석기 공백 빠짐 · 절대 경로 실재 · 상대 경로 진입 검사.
#   사례 ①~⑥(카드 반례 동결) + 줄·사본 · 변이 M1~M4(bash -n 끔 · heredoc 빼기 끔 · 사슬 칸 뺌 · C4 전수 루프 되살림) — 변이마다 원본으로 같은 사례 1회 더
#   격리: 임시 HIL_DIR·계획 · FT_*_JUDGE 대역(다른 판정기 건너뜀) · 실 h 폴더·실 팩 쓰기 0 · 고정 sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + 재진입 표지(RSG_ACTIVE)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="$HERE/../bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
sec() { echo "== $1 (누적 $((SECONDS - T0))s)"; }
run() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

mkdir -p "$T/home" "$T/comm"; HD="$T/hil"; mkdir -p "$HD"
printf 'import sys\nsys.exit(2)\n' > "$T/die.py"; printf '#!/usr/bin/env bash\necho ok\n' > "$T/ok.sh"
hil() {  # <bin> <--add 계획 | --cmd 글> [판정기 경로] — 임시 HIL_DIR 등록 1회 · HO=stdout · HE=stderr · HV=rc
  local a=(env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_MBOX_DIR="$T/comm"
    FT_SECRET_JUDGE="$T/none.py" FT_TRAFFIC_JUDGE="$T/none.py" FT_SCOPE_JUDGE="$T/none.py" FT_MIX_JUDGE="$T/none.py" FT_PACK_PATH_JUDGE="$T/none.py")
  [ -z "${4:-}" ] || a+=(FT_PLAN_SYNTAX_JUDGE="$4")
  HO="$("${a[@]}" bash "$1/ft-hil.sh" "$2" "$3" 2>"$T/err.txt")"; HV=$?; HE="$(cat "$T/err.txt")"
}
nh() { find "$HD" -maxdepth 1 -name 'h[0-9]*' ! -name '*.*' | wc -l | tr -d ' '; }
plan() { printf '#!/usr/bin/env bash\n# ft-hil-request seat=byz-planner-master-claude#1\nset -uo pipefail\n%s\n' "$2" > "$T/$1.hil"; }
plan nofi 'if true; then echo a'
printf '#!/usr/bin/env python3\n# ft-hil-request seat=byz-planner-master-claude#1\ndef f():\n    return 1\n' > "$T/py.hil"
plan glued 'bash/Users/x/run.sh'
plan gluedpre 'FOO=1 timeout 5 bash/tmp/a.sh'
plan heredoc "cat > /tmp/r2289-never.txt <<'EOF'
bash/tmp/a.sh
EOF
echo done"
plan nopath 'bash /없는/파일.sh'
plan varpath 'bash "$R/x.sh"'
plan abspath "bash $T/ok.sh"
plan readme 'cat ./README.md'
plan gluedcd 'cd /x && bash/Users/a.sh'
plan gitarg 'git -C /r add harness/bin/x.sh'
plan assign 'A=scripts/x.sh'
plan array 'FILES=(
  design/a.sql
  design/teams/k/values.sh
)
for f in "${FILES[@]}"; do echo "$f"; done'
plan good "bash $T/ok.sh && echo ok"

rej() {  # <bin> <계획 이름> <REJECT 낱말> [판정기] — rc1 · h 수 그대로 · REJECT 줄에 낱말
  local n0; n0="$(nh)"; hil "$1" --add "$T/$2.hil" "${4:-}"
  [ "$HV" = 1 ] && [ "$(nh)" = "$n0" ] && case "$HE" in *"REJECT $3"*) return 0;; esac; return 1
}
fresh() { local f; f="$(mktemp "$T/$1.XXXXXX")" && { cat "$T/$1.hil"; echo "# 사본 ${f##*.}"; } > "$f" && echo "$f"; }  # 같은 계획 다시 등록 = 같은 번호(r2078 재사용) → 등록마다 새 사본
pass() { local n0; n0="$(nh)"; hil "$1" --add "$(fresh "$2")" "${3:-}"; [ "$HV" = 0 ] && [ "$(nh)" = $((n0 + 1)) ]; }
c1()  { rej "$1" nofi "계획 문법 오류"; }
c1b() { pass "$1" py; }
c2()  { rej "$1" glued "해석기와 경로 사이 공백 빠짐: bash/Users/x/run.sh — 줄 4"; }
c2b() { rej "$1" gluedpre "해석기와 경로 사이 공백 빠짐: bash/tmp/a.sh — 줄 4"; }
c2c() { pass "$1" heredoc; }
c2d() { rej "$1" gluedcd "해석기와 경로 사이 공백 빠짐: bash/Users/a.sh — 줄 4"; }
c3()  { rej "$1" nopath "명령 경로 없음: /없는/파일.sh — 줄 4"; }
c3b() { pass "$1" varpath; }
c3c() { pass "$1" abspath; }
c4()  {  # --cmd 상대 경로 진입 = REJECT · h 0
  local n0; n0="$(nh)"; hil "$1" --cmd '.fable-team/state/x.sh | bash'
  [ "$HV" = 1 ] && [ "$(nh)" = "$n0" ] && case "$HE" in *"REJECT 상대 경로 — 절대 경로로: .fable-team/state/x.sh"*) return 0;; esac; return 1
}
c4b() { pass "$1" readme; }
c4c() { pass "$1" gitarg; }
c4d() { pass "$1" assign; }
c4e() { pass "$1" array; }
c5()  { pass "$1" good && [ "$(printf '%s\n' "$HO" | wc -l | tr -d ' ')" = 1 ] && [[ "$HO" =~ ^!\ bash\ .*/h[0-9]+$ ]]; }
c6()  { pass "$1" good "$T/none.py" && [ "$(printf '%s\n' "$HE" | grep -c 'WARN 계획 문법·명령 경로 검사를 건너뛴다')" = 1 ]; }
c6b() { local n0; n0="$(nh)"; hil "$1" --add "$(fresh good)" "$T/die.py"
  [ "$HV" = 1 ] && [ "$(nh)" = "$n0" ] && case "$HE" in *"ERROR ft-hil 판정기 실행 실패(rc=2)"*) return 0;; esac; return 1; }

sec "①~⑥ ft-hil 등록 검사"
run "① fi 없는 계획 = REJECT 계획 문법 오류 · h 수 그대로" c1 "$BIN0"
run "①ⓑ python3 셔뱅 계획 = 문법 검사 0 · 등록 rc0" c1b "$BIN0"
run "② bash/Users/x/run.sh = REJECT 공백 빠짐 — 줄 4" c2 "$BIN0"
run "②ⓑ FOO=1 timeout 5 bash/tmp/a.sh = REJECT 공백 빠짐" c2b "$BIN0"
run "②ⓒ heredoc 본문 안 bash/tmp/a.sh = 통과" c2c "$BIN0"
run "②ⓓ cd /x && bash/Users/a.sh = REJECT 공백 빠짐(명령 자리 = && 뒤)" c2d "$BIN0"
run "③ bash /없는/파일.sh = REJECT 명령 경로 없음" c3 "$BIN0"
run "③ⓑ bash \"\$R/x.sh\" = 검사 0 · 통과" c3b "$BIN0"
run "③ⓒ 있는 절대 경로 = 통과" c3c "$BIN0"
run "④ --cmd '.fable-team/state/x.sh | bash' = REJECT 상대 경로 · h 0" c4 "$BIN0"
run "④ⓑ cat ./README.md = 통과" c4b "$BIN0"
run "④ⓒ git -C /r add harness/bin/x.sh(인자) = 통과" c4c "$BIN0"
run "④ⓓ A=scripts/x.sh(대입) = 통과" c4d "$BIN0"
run "④ⓔ 여러 줄 배열 원소 design/teams/k/values.sh = 통과(표본 오탐 회귀 · knowledge ddl65 계획 꼴)" c4e "$BIN0"
run "⑤ 정상 계획 = 등록 rc0 · stdout «! bash \$HIL_DIR/h<N>» 1줄" c5 "$BIN0"
run "⑥ 판정기 없음 = WARN 1줄 · 등록 rc0" c6 "$BIN0"
run "⑥ⓑ 판정기 rc2 = ERROR · 등록 0" c6b "$BIN0"

sec "줄·사본"
n="$(wc -l < "$BIN0/ft-hil.sh" | tr -d ' ')"; [ "$n" -le 200 ] && ok "ft-hil.sh ${n}줄 ≤200" || bad "ft-hil.sh ${n}줄 >200"
n="$(wc -l < "$BIN0/ft_hil_plan_syntax_judge.py" | tr -d ' ')"; [ "$n" -le 130 ] && ok "판정기 ${n}줄 ≤130" || bad "판정기 ${n}줄 >130"
for f in ft_hil_plan_syntax_judge.py ft-hil.sh; do
  cmp -s "$BIN0/$f" "$HERE/../kit/fable-team/bin/$f" && ok "bin=kit $f" || bad "bin≠kit $f"
done

sec "변이 M1~M4 — 변이 사본에서 사례 FAIL · 원본으로 같은 사례 1회 더 PASS"
mut() {  # <사본이름> <파일> <옛 글> <새 글> — 바꾼 사본 경로를 stdout(옛 글이 없으면 rc1)
  local d="$T/$1"; cp -R "$BIN0" "$d" || return 1
  python3 - "$BIN0/$2" "$d/$2" "$3" "$4" <<'PY' || return 1
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if old not in s:
    sys.exit("옛 글 없음: " + old)
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  printf '%s\n' "$d"
}
caught() {  # <설명> <사례함수> <변이 bin>
  if [ -z "$3" ]; then bad "$1 사본 못 만듦"; return; fi
  if "$2" "$3" >/dev/null 2>&1; then bad "변이 $1 를 못 잡음($2 가 변이 사본에서도 통과)"; else ok "변이 $1 → $2 FAIL 검출"; fi
  if "$2" "$BIN0" >/dev/null 2>&1; then ok "원본 $2 1회 더 PASS"; else bad "원본 $2 1회 더 FAIL"; fi
}
caught "M1(bash -n 칸 끔)" c1 "$(mut mut1 ft_hil_plan_syntax_judge.py 'if r.returncode == 0:' 'if True:')"
caught "M2(heredoc 빼기 끔)" c2c "$(mut mut2 ft_hil_plan_syntax_judge.py 'ends = [(m.group(1) == "-", m.group(3)) for m in HEREDOC.finditer(cut)]' 'ends = []')"
caught "M3(사슬 칸 뺌)" c2 "$(mut mut3 ft-hil.sh ' && lint "$f" "${FT_PLAN_SYNTAX_JUDGE:-$l/ft_hil_plan_syntax_judge.py}" "계획 문법·명령 경로" ""' '')"
M4="$(mut mut4 ft_hil_plan_syntax_judge.py '            for cmd, arg in commands(toks):' '            for w in toks:  # 변이 = 옛 전수 루프
                if "/" in w and w[0] not in "/$~" and w.endswith((".sh", ".py")):
                    out.append("상대 경로 — 절대 경로로: %s — 줄 %d" % (w, n))
            for cmd, arg in commands(toks):')"  # C4 전수 루프 되살림(DA#32 HOLD 원인)
caught "M4(C4 전수 루프 되살림)" c4c "$M4"
caught "M4(C4 전수 루프 되살림)" c4d "$M4"

sec "끝"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
