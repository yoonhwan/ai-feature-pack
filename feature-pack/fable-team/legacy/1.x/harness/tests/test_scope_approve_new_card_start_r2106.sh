#!/usr/bin/env bash
# test_scope_approve_new_card_start_r2106.sh — r2106: scope-approve 의 SCOPE-OK 뒤 «새 대기 카드» 마다 NEW-CARD 1줄(착지 뒤 keeper 가 열지 · 막을지)
#   ① A1 알림 줄 꼴 · 2장 순서 · 40자 · 배정 없음  ② A2 판정(keeper_next.py prereq 앞 두 단계와 같은 순서 · 같은 글자 처리 + ft2 사본 글자 대조)
#   ③ A3 불변(고치기만 · 완성 이동 · 문서만 · FORBID · 원장 줄 수 · bin=kit cmp0)  ④ A4 카드 본문 읽기 실패 = 판정 불가 · SCOPE-OK·rc0 그대로
#   변이 M1~M6(사본에서만 · 변이마다 그 칸 FAIL) · 막는 낱말 6개 = ft2 keeper_next.py MARK 줄 글자 대조
#   격리: 임시 FT_ROOT 를 git 리포로(가짜 origin/main = update-ref) · 가짜 분류기 · 실 리포 fetch 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
BIN0="$BIN"; KIT="$ROOT/harness/kit/fable-team/bin"; KN="$ROOT/../../ft2/adapters/pi/keeper_next.py"
L="design/teams/lecture/indices"; D="$L/대기"
g() { git -C "$T" "$@"; }
g init -q -b main; g config user.name t; g config user.email t@t; g config commit.gpgsign false
mkdir -p "$T/$D" "$T/$L/완성" "$T/docs"; printf '# old\n- 배정: 없음\n' > "$T/$D/old.md"; echo d > "$T/docs/a.md"
g add design docs; g commit -q -m base; g update-ref refs/remotes/origin/main HEAD
SEED="$T/seeds.tsv"; : > "$SEED"
pr() {  # pr <이름> <셸 한 줄($T 안)> — origin/main 에서 1커밋 · 이름 → sha
  g checkout -q -B "pr-$1" refs/remotes/origin/main && (cd "$T" && eval "$2") && g add -A design docs && g commit -q -m "$1" || { echo "FAIL 준비 $1"; fail=$((fail+1)); }
  printf '%s\t%s\n' "$1" "$(g rev-parse HEAD)" >> "$SEED"; g checkout -q main; }
s() { awk -F'\t' -v k="$1" '$1==k{print $2}' "$SEED"; }
w() { printf '%b' "$2" > "$D/$1.md"; }   # w <stem> <본문(\n)> — 대기 카드 1장
LONG="대기(석 · 2026-11-16T15:20 · 아주아주아주긴사유글자넘침확인용꼬리)"
pr p1 'w L1-x "# L1\n- 배정: 대기(석 · 2026-11-16T15:20)\n- 선행: 충족(…)\n"'
pr p2 'w b2 "- 배정: 없음\n"; w a2 "- 배정: 없음\n"'
pr p3 "w long \"- 배정: $LONG\n\""
pr p4 'w nob "# 배정 줄 없음\n"'
H=(h01 "- 배정: 대기(사람 · 2026-11-16T10:00)\n" "held(사람)"   h02 "- 배정: 대기(정지 · t)\n" "held(정지)"
   h03 "- 배정: 대기(DA · t)\n" "held(DA)"                     h04 "- 배정: 대기(lint · t)\n" "held(lint)"
   h05 "- 배정: 대기(면제대기 · t)\n" "held(면제대기)"          h06 "- 배정: 대기(선행 · t)\n" "held(선행)"
   h07 "- 배정: 없음\n" "open"                                 h08 "- 배정: 대기(석 · 2026-11-16T15:20)\n" "open"
   h09 "- 상태: 대기(NEW_CARD_HOLD · x)\n" "held(껍데기)"       h10 "- 배정: 대기(사람)\n" "held(사람)"
   h11 "- 배정: 대기(DA)\n" "held(DA)"                         h12 "- 배정: 대기(석 · t)\n- 배정: 대기(사람 · t)\n" "open"
   h13 "- 대기(NEW_CARD_HOLD · x)\n- 배정: 대기(사람 · t)\n" "held(껍데기)"   h14 "- 선행: r9999 착지\n" "open")
cmd=""; for ((i=0; i<${#H[@]}; i+=3)); do cmd+="w ${H[i]} \"${H[i+1]}\"; "; done; pr p5 "$cmd"
pr p6 'printf "%s\n" "- 배정: 대기(사람 · t)" >> "$D/old.md"'
pr p7 'git mv "$D/old.md" "$L/완성/old.md"'
pr p8 'echo e >> docs/a.md'
pr p9 'w f9 "- 배정: 없음\n"'
mkdir -p "$T/fakegit"; REALGIT="$(command -v git)"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = show ] && exit 9; done\nexec "%s" "$@"\n' "$REALGIT" > "$T/fakegit/git"; chmod +x "$T/fakegit/git"

cases() {  # cases <bin> — PASS/FAIL 줄만 · 틀린 수 = rc
  local B="$1" f=0 o k i ln n0
  t() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; f=$((f+1)); fi; }
  ap() { out="$(FT_NOW="$NOW" "$BASH" "$B/ft-autonomy.sh" scope-approve "$(s "$1")" 2>&1)"; rc=$?; }
  ok1() { [ "$rc" = 0 ] && [[ "$(sed -n 1p <<<"$out")" =~ ^SCOPE-OK\ $(s "$1")\ class=docs ]]; }
  rm -rf "$S"; mkdir -p "$S"; NOW=$T0; FT_NOW="$NOW" "$BASH" "$B/ft-autonomy.sh" on >/dev/null 2>&1
  FT_NOW="$NOW" "$BASH" "$B/ft-autonomy.sh" approve-scope --for 10h --max 100 --daily 100 --classes docs >/dev/null 2>&1
  ap p1; ok1 p1 && [ "$(sed -n 2p <<<"$out")" = "NEW-CARD L1-x start=open 배정=대기(석 · 2026-11-16T15:20) 선행=충족(…)" ] && [ "$(wc -l <<<"$out")" -eq 2 ]
  t "① 알림 줄 꼴(SCOPE-OK 다음 줄)" $?
  ap p2; ok1 p2 && [ "$(sed -n '2,$p' <<<"$out" | cut -d' ' -f2 | tr '\n' ,)" = "a2,b2," ]; t "① 새 카드 2장 = 2줄 · 파일 이름 순" $?
  ap p3; ok1 p3 && grep -qxF "NEW-CARD long start=open 배정=${LONG:0:40} 선행=-" <<<"$out"; t "① 값 40자까지" $?
  ap p4; ok1 p4 && grep -qxF "NEW-CARD nob start=open 배정=- 선행=-" <<<"$out"; t "① 배정 줄 없음 = 배정=- · open" $?
  ap p5; o="$out"
  for ((i=0; i<${#H[@]}; i+=3)); do
    ln="$(grep "^NEW-CARD ${H[i]} " <<<"$o")"; out="$o"; rc=0
    [[ "$ln" == "NEW-CARD ${H[i]} start=${H[i+2]} "* ]]; t "② ${H[i]} → start=${H[i+2]}" $?
  done
  grep -qxF "NEW-CARD h14 start=open 배정=- 선행=r9999 착지" <<<"$o"; t "② 선행 값만 보임(판정 0)" $?
  n0="$(wc -l < "$S/autonomy-scope/S1.ledger.tsv" | tr -d ' ')"
  for k in p6 p7 p8; do ap $k; ok1 $k && [ "$(wc -l <<<"$out")" -eq 1 ]; t "③ $k 새 대기 카드 없음 = SCOPE-OK 1줄뿐(기준판 글자)" $?; done
  [ "$(wc -l < "$S/autonomy-scope/S1.ledger.tsv" | tr -d ' ')" = $((n0 + 3)) ] && ! grep -q NEW-CARD "$S/autonomy-scope/S1.ledger.tsv" "$LOG"
  t "③ 범위 원장 = 승인마다 1줄 · 알림 줄 0" $?
  out="$(STUB_OUT="FORBID kind=x y" STUB_RC=3 FT_NOW="$NOW" "$BASH" "$B/ft-autonomy.sh" scope-approve "$(s p9)" 2>&1)"; rc=$?
  [ "$rc" = 2 ] && ! grep -q NEW-CARD <<<"$out"; t "③ FORBID = 알림 줄 0 · rc2" $?
  out="$(PATH="$T/fakegit:$PATH" FT_NOW="$NOW" "$BASH" "$B/ft-autonomy.sh" scope-approve "$(s p9)" 2>&1)"; rc=$?
  ok1 p9 && [ "$(sed -n 2p <<<"$out")" = "NEW-CARD f9 start=판정 불가" ]; t "④ 본문 읽기 rc9 = 판정 불가 · SCOPE-OK·rc0 그대로" $?
  return "$f"
}

cases "$BIN0"; fail=$((fail+$?))
cmp -s "$BIN0/ft-autonomy-scope.sh" "$KIT/ft-autonomy-scope.sh"; ck "③ bin = kit 사본 cmp0" $?
km="$(python3 -c 'import ast,sys
for n in ast.parse(open(sys.argv[1],encoding="utf-8").read()).body:
    if isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Tuple) and [getattr(e,"id","") for e in n.targets[0].elts][:1]==["MARK"]: print(" ".join(ast.literal_eval(n.value.elts[0])))' "$KN")"
sm="$(sed -n 's/^SCOPE_HOLD_MARKS="\([^"]*\)".*/\1/p' "$BIN0/ft-autonomy-scope.sh")"
out="ft2=$km scope=$sm"; [ -n "$km" ] && [ "$km" = "$sm" ]; ck "막는 낱말 6개 = ft2 keeper_next.py MARK 글자 같음" $?
for ((i=0; i<${#H[@]}; i+=3)); do printf '%b' "${H[i+1]}" | grep -v '^- 선행:' > "$T/kc-${H[i]}"; done   # 선행 줄 = keeper 셋째 단계(범위 밖) — 앞 두 단계만 대조
kv="$(python3 - "$KN" "$T" <<'PY'
import ast, os, re, sys   # ft2 사본 = keeper_next.py 의 MARK·SHELL 줄 + REF 줄 + prereq 함수만 떼어 실행(코어 import 0)
ns, want = {"re": re}, {"MARK", "REF"}
for n in ast.parse(open(sys.argv[1], encoding="utf-8").read()).body:
    names = {getattr(e, "id", "") for t in getattr(n, "targets", []) for e in (t.elts if isinstance(t, ast.Tuple) else [t])}
    if isinstance(n, ast.FunctionDef) and n.name == "prereq" or names & want:
        exec(compile(ast.Module([n], []), "keeper_next", "exec"), ns)
for f in sorted(os.listdir(sys.argv[2])):
    if f.startswith("kc-"):
        v = ns["prereq"](open(os.path.join(sys.argv[2], f), encoding="utf-8").read().splitlines(), {})[0]
        print(f[3:], "open" if v == "" else "held(%s)" % v)
PY
)"
bad=0; for ((i=0; i<${#H[@]}; i+=3)); do grep -qxF "${H[i]} ${H[i+2]}" <<<"$kv" || bad=$((bad+1)); done
out="$kv"; [ "$bad" = 0 ] && [ "$(wc -l <<<"$kv")" -eq $(( ${#H[@]} / 3 )) ]; ck "② ft2 keeper_next.py prereq 사본 판정 = 같은 입력 글자 같음" $?

mut() {  # mut <이름> <sed 식> <기대 FAIL 머리> — 사본에서만 · 그 칸이 FAIL 이어야 변이 통과
  local M="$T/$1"; cp -R "$BIN0" "$M"; local F="$M/ft-autonomy-scope.sh"; sed -i.bak -E "$2" "$F"
  if cmp -s "$F" "$F.bak"; then echo "FAIL 변이 $1 적용 실패"; fail=$((fail+1)); return; fi
  local o; o="$(cases "$M")"
  if grep -q "^FAIL $3" <<<"$o"; then echo "PASS 변이 $1 → FAIL $3"; else echo "FAIL 변이 $1 가 «$3» 를 못 깸"; fail=$((fail+1)); fi
}
mut M1 's/^  scope_new_cards "\$sha".*$/  :/' "① 알림 줄 꼴"
mut M2 's/^SCOPE_HOLD_MARKS="사람 /SCOPE_HOLD_MARKS="/' "② h01"
mut M4 's#\(split / · /, \$1, 2\)\[0\] // ""#($1 =~ / · / ? (split / · /, $1, 2)[0] : "")#' "② h10"
mut M5 's/!defined \$why && //' "② h12"
mut M6 's/my \$start = \$shell \? "held\(껍데기\)" : (defined \$why && \$mark\{\$why\} \? "held\(\$why\)") :/my $start = \1 : $shell ? "held(껍데기)" :/' "② h13"
mut M3 's/^  scope_new_cards "\$sha"/  scope_new_cards "$sha" | tee -a "$SDIR\/$G_S.ledger.tsv"/' "③ 범위 원장"

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS r2106"; [ "$fail" = 0 ]
