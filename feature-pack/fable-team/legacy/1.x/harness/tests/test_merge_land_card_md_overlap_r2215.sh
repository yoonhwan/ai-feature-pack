#!/usr/bin/env bash
# test_merge_land_card_md_overlap_r2215.sh — r2215: 코드·문서 PR 과 먼저 착지한 증거 줄이 겹친 파일이 «카드 .md» 뿐이고 깨끗이 병합되면 자동 병합 C 로 착지
#   반례 ②~⑪(카드 동결) + ⑤b(58행 길: 사람 병합 head · 코드 겹침은 equiv 쪽에만 보임 = M2 대상) + ⑥b(문서 갈래 GOAL .md = M1 대상) · 기준판 Red ② · 변이 M1~M5 + 원본 대조 = 짝 시험 test_merge_land_card_md_overlap_mut_r2215.sh(r2253 · 70초 상한 · 쪼갬)
#   임시 origin(bare)+clone · gh 는 스텁 · 가짜 equiv 는 사본 폴더 안 래퍼 — 실 PR·실 main·실 gh·실 push 0 · sleep 0 · 카드 경로 = 한글 폴더 그대로(대기)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
unset FT_MERGE_LAND_CODE_AUTOMERGE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$BIN/../kit/fable-team/bin"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T_START=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/.fable-team"
git -C "$W" config core.quotepath false   # live 전역 설정과 같게(equiv 의 overlap 셈이 한글 경로를 따옴표 없이 본다)
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_MERGE_DENY_FILE="$T/deny.txt"
printf '# 시험 목록(빈)\n' > "$T/deny.txt"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; exit 2;; esac
body=""; for a in "$@"; do [ -f "$a" ] && body="$(cat "$a")"; done
echo "$* :: $body" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub"
omain() { sha "$ORIGIN" refs/heads/main; }
oshow() { git -C "$ORIGIN" show "main:$1" 2>/dev/null; }
put() { mkdir -p "$(dirname "$W/$1")"; printf '%s\n' "$2" > "$W/$1"; }
pushpr() {
  git -C "$W" push -q -f origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":"feat: PR "+sys.argv[3],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$2" "$1" > "$STUB_JSON"
}
mkpr() { local n="$1" b="$2"; shift 2; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "$b" origin/main; for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "pr $n"; pushpr "$n" "$b"; }
adv() { git -C "$W" fetch -q origin; git -C "$W" checkout -q -B main origin/main; for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "main adv"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin; }
land() { local b="$1"; shift; apv "$@"; : > "$STUB_LOG"; out="$(bash "$b" "$@" --repo "$W" 2>&1)"; rc=$?; }
rejected() { [ "$rc" = 1 ] && [[ "$out" != *LANDED* ]] && [[ "$out" == *"REJECT "* ]] && [ "$(omain)" = "$1" ]; }
landed() { [ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=$1 "* ]]; }
mkbin() { local d="$T/$1"; mkdir -p "$d"; for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done; printf '%s' "$d"; }   # 사본 폴더(전부 심링크)
medit() {  # medit <폴더> <파일> <옛 본문> <새 본문> — 그 파일만 실파일로 바꿔 1곳 치환
  python3 - "$BIN/$2" "$1/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 대상 없음 $2"; fail=$((fail+1)); }
import os, sys
s = open(sys.argv[1], encoding="utf-8").read() if not os.path.isfile(sys.argv[2]) or os.path.islink(sys.argv[2]) else open(sys.argv[2], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1, sys.argv[3]
os.path.islink(sys.argv[2]) and os.unlink(sys.argv[2])
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1))
PY
}
fakeeq() { rm -f "$1/ft-approval-equiv.sh"; printf '#!/bin/bash\no="$(bash "%s/ft-approval-equiv.sh" "$@")"; r=$?; printf "%%s\\n" "$o" | sed "s/overlap=[0-9]*/overlap=%s/"; exit $r\n' "$BIN" "$2" > "$1/ft-approval-equiv.sh"; }   # 가짜 equiv(overlap 칸만 바꿈)
AUTOC="INFO main 자동 병합(코드 · 승인 EQUIV 대상) C="; AUTOD="INFO 문서 PR main 자동 병합 C="
CB=$'# 카드\n- 상태: 대기\n- 줄 a\n- 줄 b\n- 줄 c'; CP="${CB/대기/진행}"; CE="$CB"$'\n- 증거 1'   # 카드 원본 · PR(«- 상태:» 줄) · main(끝에 증거 줄 1)
card() { printf 'design/teams/x/indices/대기/C%s.md' "$1"; }
# sc <PR> <카드 경로…> — 승인 코드 PR(코드 1 + 카드 «- 상태:» 줄) · main 이 같은 카드 끝에 증거 줄 1 → A=승인 · MB=시험 전 main
sc() { local n="$1" c kv=() ev=(); shift; for c in "$@"; do kv+=("$c=$CB"); done; adv "${kv[@]}"; kv=("bin/c$n.sh=echo c$n"); for c in "$@"; do kv+=("$c=$CP"); ev+=("$c=$CE"); done; mkpr "$n" "c$n" "${kv[@]}"; A="$PRSHA"; adv "${ev[@]}"; MB="$(omain)"; }
sc5b() {  # ⑤b: A = 코드 2행 + 카드 상태 · main 코드 28행 → 사람이 main 병합한 head S · 그 뒤 main 이 카드 증거 줄 → 50행은 카드만 겹침 · equiv 는 코드+카드 2
  local n="$1" c; c="$(card "$n")"; python3 -c 'print("\n".join("line%02d" % i for i in range(1, 31)))' > "$T/f.txt"; adv "bin/f$n.py=$(cat "$T/f.txt")" "$c=$CB"
  mkpr "$n" "c$n" "bin/f$n.py=$(sed '2s/.*/PR-LINE2/' "$T/f.txt")" "$c=$CP"; A="$PRSHA"; adv "bin/f$n.py=$(sed '28s/.*/MAIN-LINE28/' "$T/f.txt")"
  git -C "$W" checkout -q "c$n"; git -C "$W" merge -q --no-edit origin/main; pushpr "$n" "c$n"; adv "$c=$CE"; MB="$(omain)"; }
sc6b() { local n="$1" g=design/harness/GOAL-harness.md; adv "$g=$CB"; mkpr "$n" "c$n" "$g=$CP"; A="$PRSHA"; adv "$g=$CE"; MB="$(omain)"; }   # ⑥b 문서 PR · indices 밖 .md
sc8() { local n="$1" c=design/teams/x/indices-old/C.md; adv "$c=$CB"; mkpr "$n" "c$n" "bin/c$n.sh=echo" "$c=$CP"; A="$PRSHA"; adv "$c=$CE"; MB="$(omain)"; }

[ -n "${R2215_WORLD_ONLY:-}" ] && return 0   # r2253: 짝 시험(_mut)이 세계·도우미만 빌려 쓴다 — 사례 ②~⑪ 은 여기서 안 돈다
# ===== 사전 =====
bash -n "$LAND" && bash -n "$BIN/ft-merge-lib.sh"; ck "bash -n land·lib" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄" $?
cmp -s "$LAND" "$KIT/ft-merge-land.sh" && cmp -s "$BIN/ft-merge-lib.sh" "$KIT/ft-merge-lib.sh"; ck "짝 사본 bin·kit cmp0(land·lib)" $?

# ===== 기준판 Red ②: r2215 직전 main 판 = REJECT «같은 파일 <카드>» =====
BASE_SHA=e277eb61e3d23eeef9be69e70d5eb8b42a72c0d2
TOP="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" && TOP="$(cd "$TOP" && pwd -P)"; PFX="$(cd "$HERE/.." && pwd -P)"; PFX="${PFX#$TOP/}"
if [ -n "$TOP" ] && git -C "$TOP" cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then
  RED="$(mkbin red)"; for f in ft-merge-land.sh ft-merge-lib.sh; do rm -f "$RED/$f"; git -C "$TOP" show "$BASE_SHA:$PFX/bin/$f" > "$RED/$f"; done
  sc 20 "$(card 20)"; land "$RED/ft-merge-land.sh" 20 --approve-sha "$A"
  rejected "$MB" && [[ "$out" == *"같은 파일 $(card 20)(사람 최신화)"* ]]; ck "기준판 ② → REJECT «같은 파일 <카드 .md>» · 착지 0(Red)" $?
else echo "SKIP 기준판 칸 — base_sha 객체 없음(git 사본 아님)"; fi

# ===== ② 승인 코드 PR · 카드 겹침 1(한글 폴더) → 자동 병합 C · 카드 겹침 1 · EQUIV overlap=1 · LANDED =====
sc 2 "$(card 2)"; land "$LAND" 2 --approve-sha "$A"
landed 2 && [[ "$out" == *"$AUTOC"*" 카드 겹침 1"* && "$out" == *"mode=merge overlap=1"* ]] && [ "$(oshow bin/c2.sh)" = "echo c2" ] \
  && oshow "$(card 2)" | grep -qx -- '- 상태: 진행' && oshow "$(card 2)" | grep -qx -- '- 증거 1'
ck "② → INFO 자동 병합 C(… 카드 겹침 1) · EQUIV mode=merge overlap=1 · LANDED · main 에 코드 · 두 카드 줄" $?
git -C "$ORIGIN" log -1 --format=%B main | grep -qF "main 자동 병합(코드 · 승인 EQUIV) C="; ck "② 착지 커밋 메시지 AMK 글자 그대로(O5)" $?

# ===== ③ 카드 = design/harness/indices/대기/r9-x.md =====
sc 3 design/harness/indices/대기/r9-x.md; land "$LAND" 3 --approve-sha "$A"
landed 3 && [[ "$out" == *" 카드 겹침 1"* ]] && oshow design/harness/indices/대기/r9-x.md | grep -qx -- '- 증거 1'; ck "③ harness/indices 카드 → ② 와 같음(LANDED)" $?

# ===== ④ main 이 같은 «- 상태:» 줄을 바꿈 → merge-tree 충돌 REJECT =====
c="$(card 4)"; adv "$c=$CB"; mkpr 4 c4 "bin/c4.sh=echo" "$c=$CP"; A="$PRSHA"; adv "$c=${CB/대기/끝}"; MB="$(omain)"
land "$LAND" 4 --approve-sha "$A"; rejected "$MB" && [[ "$out" == *"merge-tree 충돌(사람 최신화)"* ]]; ck "④ 같은 줄 충돌 → REJECT «merge-tree 충돌» · 착지 0" $?

# ===== ⑤ main 이 카드 .md + 코드 파일을 같이 바꿈 → REJECT «같은 파일 <코드 파일>» =====
c="$(card 5)"; adv "$c=$CB"; mkpr 5 c5 "bin/c5.sh=echo c5" "$c=$CP"; A="$PRSHA"; adv "$c=$CE" "bin/c5.sh=echo main5"; MB="$(omain)"
land "$LAND" 5 --approve-sha "$A"; rejected "$MB" && [[ "$out" == *"같은 파일 bin/c5.sh(사람 최신화)"* ]]; ck "⑤ 카드+코드 겹침 → REJECT «같은 파일 bin/c5.sh» · 착지 0" $?
sc5b 51; land "$LAND" 51 --approve-sha "$A"
rejected "$MB" && [[ "$out" == *"승인 뒤 main 이 같은 파일 2개를 바꿈"* ]]; ck "⑤b 58행 길(equiv 겹침 = 코드+카드) → REJECT «같은 파일 2개» · 착지 0" $?

# ===== ⑥ 겹친 파일 = design/harness/GOAL-harness.md(indices 밖) → REJECT =====
g=design/harness/GOAL-harness.md; adv "$g=$CB"; mkpr 6 c6 "bin/c6.sh=echo" "$g=$CP"; A="$PRSHA"; adv "$g=$CE"; MB="$(omain)"
land "$LAND" 6 --approve-sha "$A"; rejected "$MB" && [[ "$out" == *"코드 PR 자동 병합 불가: 같은 파일 $g(사람 최신화)"* ]]; ck "⑥ GOAL .md 겹침 → REJECT «같은 파일 ${g}» · 착지 0" $?
sc6b 61; land "$LAND" 61 --approve-sha "$A"; rejected "$MB" && [[ "$out" == *"문서 PR 자동 병합 불가: 같은 파일 $g"* ]]; ck "⑥b 문서 PR · GOAL .md 겹침 → REJECT · 착지 0" $?

# ===== ⑦ 문서 PR(카드 .md 만 · 승인 sha == head = 문서 갈래) · main 이 같은 카드 다른 줄 → 자동 병합 C · LANDED =====
c="$(card 7)"; adv "$c=$CB"; mkpr 7 c7 "$c=$CP"; A="$PRSHA"; adv "$c=$CE"; MB="$(omain)"
land "$LAND" 7 --approve-sha "$A"
landed 7 && [[ "$out" == *"$AUTOD"*" 카드 겹침 1"* ]] && git -C "$ORIGIN" log -1 --format=%B main | grep -qF "main 자동 병합(문서 전용 · 겹침 0) C=" && oshow "$c" | grep -qx -- '- 증거 1'
ck "⑦ 문서 갈래 카드 겹침 → INFO 문서 자동 병합(… 카드 겹침 1) · LANDED · AMK 그대로" $?

# ===== ⑧ 비슷한 이름(카드 아님) → REJECT «같은 파일» =====
sc8 8; land "$LAND" 8 --approve-sha "$A"; rejected "$MB" && [[ "$out" == *"같은 파일 design/teams/x/indices-old/C.md"* ]]; ck "⑧ indices-old/C.md → REJECT · 착지 0" $?
c=design/teams/x/indices/C.txt; adv "$c=$CB"; mkpr 81 c81 "bin/c81.sh=echo" "$c=$CP"; A="$PRSHA"; adv "$c=$CE"; MB="$(omain)"
land "$LAND" 81 --approve-sha "$A"; rejected "$MB" && [[ "$out" == *"같은 파일 $c"* ]]; ck "⑧b indices/C.txt → REJECT · 착지 0" $?

# ===== ⑨ 카드 겹침 4장(names= 3개 상한 넘음) → LANDED · 카드 겹침 4 =====
sc 9 "$(card 9a)" "$(card 9b)" design/teams/y/indices/완성/C9c.md design/harness/indices/아카이브/C9d.md; land "$LAND" 9 --approve-sha "$A"
landed 9 && [[ "$out" == *" 카드 겹침 4"* && "$out" == *"overlap=4"* ]]; ck "⑨ 카드 4장 → LANDED · « 카드 겹침 4» · overlap=4" $?

# ===== ⑩ ⑪ 가짜 equiv =====
F10="$(mkbin eq-empty)"; fakeeq "$F10" ""
sc 10 "$(card 10)"; land "$F10/ft-merge-land.sh" 10 --approve-sha "$A"; rejected "$MB" && [[ "$out" == *"코드 PR 자동 병합 불가"* ]]; ck "⑩ equiv overlap 빈 값 → REJECT «코드 PR 자동 병합 불가» · 착지 0" $?
F11="$(mkbin eq-two)"; fakeeq "$F11" 2
sc 11 "$(card 11)"; land "$F11/ft-merge-land.sh" 11 --approve-sha "$A"; rejected "$MB" && [[ "$out" == *"판정 불가 · 겹침 수 다름(셈 1 · equiv 2)"* ]]; ck "⑪ equiv overlap=2 · 셈 1 → REJECT «판정 불가 · 겹침 수 다름» · 착지 0" $?

[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
