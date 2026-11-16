#!/usr/bin/env bash
# test_card_evidence_r2087.sh — r2087(설계 r1944 §3·§4): D2 좌석 동사 ft-card-evidence.sh 가 카드 ref «## 상태» 끝에 세트 줄 0줄 또는 1줄만 쓴다
#   반례 ① ①' ② ③ ③' ④ ⑤ ⑤' + E8 입력 꼴 1줄 + 변이 M1(조상 검사 삭제 → ②) · M2(완료 줄도 더함 → ③') · 원본 대조
#   세계 = _nano_record_r1717_fixture.sh(임시 bare 2개 = 카드 CREM · 코드 PREM) + gh 스텁 · 실 원장·실 리포·실 우편함 쓰기 0 · sleep 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
unset FT2_HOLDER FT_SEAT_NAME; export T; TST='bash tests/t.sh rc=0'; MI="design/teams/ops/indices"; mkdir -p "$T/gb"; printf '#!/bin/sh\nexit 7\n' > "$T/gb/git"
cat > "$FK/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$T/gh.log"; [ "${GH_RC:-0}" = 0 ] || exit "$GH_RC"
echo "{\"state\":\"${GH_ST:-OPEN}\",\"headRefOid\":\"$GH_HEAD\",\"headRefName\":\"$GH_BR\"}"
EOF
chmod +x "$FK/gh" "$T/gb/git"; world; printf '*\t.\torigin/main\tdesign/teams/*/indices\n' >> "$STATE/directive-roots.tsv"
code() {  # code <stem> → A(세트) · H(PR head = A 위 1커밋) · X(A 의 형제 = 조상 아님) · gh 스텁 값
  g "$PACK" checkout -q -B "nano/$1" origin/main; echo a > "$PACK/a-$1"; g "$PACK" add -A; g "$PACK" commit -qm "a $1"; A="$(g "$PACK" rev-parse HEAD)"
  echo x > "$PACK/x-$1"; g "$PACK" add -A; g "$PACK" commit -qm "x $1"; X="$(g "$PACK" rev-parse HEAD)"; g "$PACK" reset -q --hard "$A"
  echo h >> "$PACK/a-$1"; g "$PACK" commit -qam "h $1"; H="$(g "$PACK" rev-parse HEAD)"; export GH_HEAD="$H" GH_BR="nano/$1"
}
mcard() { g "$ROOT" pull -q --rebase origin main; mkdir -p "$ROOT/$MI/진행"; printf '# 인덱스: %s\n\n## 상태\n- 대기\n- 세트: \n' "$1" > "$ROOT/$MI/진행/$1.md"; g "$ROOT" add -A; g "$ROOT" commit -qm "card $1"; g "$ROOT" push -q origin main; }
ev() { OUT="$(cd "$PACK" && bash "$BIN/ft-card-evidence.sh" --card "$1" --set "${2:-$A}" --pr 7 --test "${3:-$TST}" 2>&1)"; RC=$?; }
mtext() { g "$CREM" show "main:$MI/진행/$1.md"; }
refs() { g "$CREM" for-each-ref --format='%(objectname)' refs/heads; }
one() { [ "$RC $(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = "$1 1" ] && inc "$OUT" "$2"; }   # one <rc> <글> — 출력 1줄 · 그 rc · 그 글
c1() {  # ① * 팀 카드(origin/main) · 빈 양식 → DONE · 세트 줄 1개 · scope_code_check 통과 · ③ 바이트 diff = 더한 줄 1 · 지운 줄 0 · 완료 0
  local s="c1$1" b; fresh; code "$s"; mcard "$s"; b="$(mtext "$s")"; ev "$s"; t "① DONE" [ "$RC ${OUT%%$'\n'*}" = "0 DONE" ]
  t "① 세트 A 1줄" [ "$(mtext "$s" | grep -c "^- 세트: $A · 시험: $TST · 이슈: 0$")" = 1 ]
  t "③ 더한 1 · 지운 0 · 완료 0" [ "$(diff <(echo "$b") <(mtext "$s") | grep -c '^>') $(diff <(echo "$b") <(mtext "$s") | grep -c '^<') $(mtext "$s" | grep -c '완료:')" = "1 0 0" ]
  g "$ROOT" pull -q --rebase origin main
  t "① scope_code_check" bash -c '. "$1/ft-autonomy-scope-code.sh"; scope_err() { echo "SCOPE-REJECT $*"; exit 1; }; HERE="$1" ROOT="$2" SCOPE_REPO="$3"; scope_code_check "$4" "$5"' _ "$BIN" "$ROOT" "$PACK" "$A" "$ROOT/$MI/진행/$s.md"; return $E
}
c1h() {  # ①' harness 카드(ops/base) → DONE · ops/base 에 1줄 · main 불변
  local s="c1h$1" m; fresh; code "$s"; card "$s"; m="$(g "$CREM" rev-parse main)"; ev "$s"; t "①' DONE" [ "$RC ${OUT%%$'\n'*}" = "0 DONE" ]
  t "①' ops/base 1줄 · main 그대로" [ "$(nline "$s" "^- 세트: $A ") $(g "$CREM" rev-parse main)" = "1 $m" ]; return $E
}
c2() {  # ② A 가 PR head 조상 아님 → REJECT · bare ref 불변
  local s="c2$1" r; fresh; code "$s"; card "$s"; r="$(refs)"; ev "$s" "$X"; t "② REJECT 조상 아님" one 1 "조상 아님"; t "② ref 불변" [ "$(refs)" = "$r" ]; return $E
}
c3b() {  # ③' 마지막 세트 B(≠A) → 세트 A 1줄만 · 완료 0
  local s="c3b$1" c0; fresh; code "$s"; card "$s" "- 세트: $X · 시험: $TST · 이슈: 0"; c0="$(ncommit)"; ev "$s"
  t "③' DONE · 커밋 +1" [ "$RC ${OUT%%$'\n'*} $(ncommit)" = "0 DONE $((c0 + 1))" ]
  t "③' 세트 2줄 · 마지막 = A · 완료 0" [ "$(nline "$s" '세트:') $(ctext "$s" | grep -o '세트: [0-9a-f]*' | tail -1 | cut -c9-) $(nline "$s" '완료:')" = "2 $A 0" ]; return $E
}
c4() {  # ④ 같은 A 2회 → ALREADY · 커밋 0
  local s="c4$1" c0; fresh; code "$s"; card "$s"; ev "$s"; c0="$(ncommit)"; ev "$s"; t "④ ALREADY · 커밋 0" [ "$RC ${OUT%%$'\n'*} $(ncommit)" = "0 ALREADY $c0" ]; return $E
}
c5() {  # ⑤ 나노 좌석 → REJECT · push·gh 시도 0 · ⑤' gh rc≠0 · git rc≠0 → rc3 «판정 불가» 1줄 · 쓰기 0 · E8 입력 꼴
  local s="c5$1" r; fresh; code "$s"; card "$s"; r="$(refs)"; : > "$T/gh.log"
  FT_SEAT_NAME='byz-x-nano-r9#0' ev "$s"; t "⑤ REJECT 나노" one 1 "나노 좌석"; t "⑤ gh 0회" [ ! -s "$T/gh.log" ]
  GH_RC=4 ev "$s"; t "⑤' gh rc3" one 3 "판정 불가"; PATH="$T/gb:$PATH" ev "$s"; t "⑤' git rc3" one 3 "판정 불가"
  ev "$s" "${A:0:12}"; t "E8 --set 40hex" one 1 REJECT; ev "$s" "$A" "bash t.sh rc=1"; t "E8 --test rc=0" one 1 REJECT; t "⑤·⑤'·E8 ref 불변" [ "$(refs)" = "$r" ]; return $E
}
step "반례"; run "① * 팀 카드 + ③ diff" c1; run "①' harness 카드" c1h; run "② 조상 아님" c2; run "③' 세트 B 뒤 A" c3b; run "④ 멱등" c4; run "⑤ 나노 · ⑤' 실패 · E8" c5
step "bin = kit"; for f in ft-card-evidence.sh ft_card_evidence.py; do if cmp -s "$SRC/$f" "$KIT/$f"; then ok "cmp $f"; else bad "cmp $f"; fi; done
step "변이 M1·M2 (+원본 대조)"
mutbin m1 ft_card_evidence.py 'rc, _o, _e = run(["git", "merge-base"' 'rc, _o, _e = 0, "", ""  # run(["git", "merge-base"'; cp "$SRC/ft-card-evidence.sh" "$MB/"; mutcase M1 c2 1
mutbin m2 ft_card_evidence.py '이슈: 0"]' '이슈: 0", f"- 완료: D2 · 세트 {a.set[:10]}"]'; cp "$SRC/ft-card-evidence.sh" "$MB/"; mutcase M2 c3b 2
finish
