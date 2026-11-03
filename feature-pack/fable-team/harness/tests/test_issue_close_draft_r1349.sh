#!/usr/bin/env bash
# test_issue_close_draft_r1349.sh — r1349 · ft-issue-close-draft.sh (Issue #6188) · 반례 C1~C23 + 변이 17 + bin·kit cmp
#   완성 카드 → 닫는 코멘트 초안(8항 + 연결 줄 + token) · 사전 검사 PASS 일 때만 Tank 래퍼로 1회 게시.
#   가짜 래퍼(호출 기록만) · Issue JSON 픽스처(FT_CLOSE_DRAFT_CHECK_JSON) · 실 gh·네트워크 0 · 자기 재호출 0(guard_begin 의 1회 재실행 외).
#   기준판: FT_R1349_BIN=<도구 없는 폴더> → 첫 줄 «FAIL 도구 없음». 변이 = 도구 사본의 한 줄을 바꿔 그 칸의 반례가 깨지는지 본다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_R1349_BIN:-$HERE/../../harness/bin}"; MIR="$HERE/../../harness/kit/fable-team/bin"; B="$BIN"
T="$(mktemp -d)"; trap 'rm -rf "$T"; [ -z "${SLP:-}" ] || kill "$SLP" 2>/dev/null' EXIT
fail=0; SECONDS=0; WL="$T/wrap.log"; LANDSHA=""
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
stage() { echo "STAGE $1 ${SECONDS}s"; }
[ -f "$BIN/ft-issue-close-draft.sh" ] && ok "도구 있음" || bad "도구 없음"
bash -n "$BIN/ft-issue-close-draft.sh" 2>/dev/null && ok "bash -n" || bad "bash -n"

# 팩 리포 흉내(착지 sha 가 origin/main 조상) · 가짜 래퍼 · 환경 정리
PK="$T/pack"; git init -q -b main "$PK"; git -C "$PK" config user.email t@t; git -C "$PK" config user.name t
echo a > "$PK/f"; git -C "$PK" add -A; git -C "$PK" commit -qm base; git -C "$PK" update-ref refs/remotes/origin/main HEAD
LANDSHA="$(git -C "$PK" rev-parse HEAD)"; OTHER="0123456789abcdef0123456789abcdef01234567"
export FT_PACK_ROOT="$PK" FT_CLOSE_DRAFT_REPO="$PK" FT_LAND_REF=origin/main
unset FT_CLOSE_DRAFT_CHECK FT_TANK_WRAPPER FT_ISSUE_REPO GH_REPO
printf '#!/usr/bin/env bash\necho "wrap $* repo=${FT_ISSUE_REPO:-}" >> "%s"\nif [ "${FAKE_WRAP_RC:-0}" != 0 ]; then echo "REJECT boom"; exit "$FAKE_WRAP_RC"; fi\necho "OK as=byz-tank comment ${2:-} — https://github.com/x/y/issues/${2:-}#issuecomment-123456"\n' "$WL" > "$T/wrap.sh"
VF="$T/V.md"; CARD=""
vf() { printf '## §16 — CLOSE r9001\n닫힘 — r9001-demo — main(팩) `%s` / PR 777\n- 카드: x\n' "${1:-$LANDSHA}" > "$VF"; }
ij() { jq -n --argjson c "${1:-[]}" '{number:9000,state:"OPEN",title:"fx",body:"",labels:[],closedByPullRequestsReferences:[],comments:$c}' > "$T/ij.json"; }
fresh() { rm -rf "$T/st"; : > "$WL"; export FAKE_WRAP_RC=0; vf; ij; }
mk() { # mk <폴더> [del:<정규식> | add:<줄> | head:<첫 줄>]… → CARD
  local fold="$1" m; shift; CARD="$T/idx/$fold/r9001-demo.md"; mkdir -p "$T/idx/$fold"
  cat > "$CARD" <<EOF
# 인덱스: r9001-demo — 끝: 시험용 카드 한 장에서 닫는 코멘트 초안을 만든다
- Issue: #9000
- 원인 1줄: 카드에는 착지 sha 가 있는데 코멘트로 옮기는 도구가 없어 Issue 가 열린 채 쌓인다
- 정본 영향 없음: 하네스 보조 도구 — 제품 정본 0
## 상태
- 착지: $LANDSHA
- 실사건: 시험 입력 실측 mbox #232532 · state/heavy.tsv:3
- 2026-11-03 10:00 — 진행→완성 · DA $VF#§16
EOF
  for m in "$@"; do case "$m" in
    del:*) grep -vE "${m#del:}" "$CARD" > "$CARD.n"; mv "$CARD.n" "$CARD";;
    add:*) printf '%s\n' "${m#add:}" >> "$CARD";;
    head:*) { printf '%s\n' "${m#head:}"; tail -n +2 "$CARD"; } > "$CARD.n"; mv "$CARD.n" "$CARD";; esac; done
}
run() { OUT="$(FT_CLOSE_DRAFT_CHECK_JSON="$T/ij.json" FT_TANK_WRAPPER="$T/wrap.sh" FT_CLOSE_DRAFT_STATE="$T/st" FT_ISSUE_REPO=org/B bash "$B/ft-issue-close-draft.sh" "$@" 2>&1)"; RC=$?; }
wc_() { grep -c '^wrap ' "$WL"; }
has() { grep -q -- "$1" <<<"$OUT"; }
expect() { # expect <라벨> <rc> <출력 조각> <래퍼 호출 수>
  [ "$RC" -eq "$2" ] && has "$3" && [ "$(wc_)" -eq "$4" ] && ok "$1" || bad "$1 rc=$RC wrap=$(wc_) :: $OUT"; }
OKCARD() { mk 완성; }

c1() { fresh; OKCARD; run --card "$CARD" --out "$T/d1.md"
  local d="$T/d1.md"; [ -f "$d" ] || { bad "C1 초안 파일 없음 :: $OUT"; return; }
  [ $RC -eq 0 ] && has "^DRAFT #9000 token=" && [ "$(wc_)" -eq 0 ] \
   && grep -q '^닫는 사건: 시험용 카드 한 장' "$d" && grep -q "^PR: 팩 리포 PR 777 → 팩 main $LANDSHA (r9001)" "$d" && grep -q '^재현 PASS: ' "$d" \
   && grep -q '^정리: ' "$d" && grep -q '^기록: 카드 ' "$d" && grep -q '^정본 영향 없음: 하네스 보조 도구' "$d" && grep -q '^원인 확정: Y — ' "$d" \
   && grep -q '^같은 증상 보류: 0$' "$d" && grep -q "^연결 PR: 팩 PR #777 · 착지 sha $LANDSHA" "$d" && tail -1 "$d" | grep -qE '^token=[0-9a-f]{12}$' \
   && ok "C1 초안 8항+연결 줄+token · 게시 0 (사전 검사 close-check PASS 포함)" || bad "C1 rc=$RC :: $OUT"; }
c2() { fresh; OKCARD; run --card "$CARD" --post --out "$T/d2.md"
  [ $RC -eq 0 ] && has "^POSTED #9000 token=" && [ "$(wc_)" -eq 1 ] && grep -q "^wrap comment 9000 $T/d2.md --apply repo=org/B" "$WL" && ok "C2 --post 래퍼 1회 · 인자·저장소 정확" || bad "C2 rc=$RC wrap=$(wc_) :: $OUT $(cat "$WL")"; }
c3() { fresh; mk 완성 'del:^- 정본' "add:- 정본: docs/x.md#§1@$OTHER"; run --card "$CARD" --post; expect "C3 사전 검사 FAIL → 게시 0 REJECT rc1" 1 "REJECT 사전 검사 FAIL" 0; }
c4() { fresh; mk 대기; run --card "$CARD"; expect "C4 대기 폴더 → DRAFT-ONLY 완성 폴더 아님 rc4" 4 "DRAFT-ONLY 완성 폴더 아님" 0; }
c5() { fresh; mk 완성 'del:^- 실사건'; run --card "$CARD" --post; expect "C5 실사건 줄 없음 → DRAFT-ONLY rc4" 4 "DRAFT-ONLY 실사건" 0; }
c6() { fresh; mk 완성 'del:^- 착지:' "add:- 착지: $OTHER" "add:- 착지: $LANDSHA"; run --card "$CARD"
  [ $RC -eq 0 ] && has "^DRAFT #9000" && ok "C6 착지 두 줄 → 마지막 줄 sha(판정문과 같음)로 진행" || bad "C6 rc=$RC :: $OUT"; }
c7() { fresh; OKCARD; printf '## §16 — CLOSE r9001\n닫힘 — main(팩) `%s` / PR 777\n## §16 — CLOSE r9001\n닫힘 — main(팩) `%s` / PR 778\n' "$LANDSHA" "$LANDSHA" > "$VF"; run --card "$CARD" --post
  [ $RC -eq 1 ] && has "결정 불가" && [ "$(wc_)" -eq 0 ] && ok "C7a § 두 개 → REJECT 결정 불가 rc1" || bad "C7a rc=$RC :: $OUT"
  printf '## §16 — CLOSE r9999\n닫힘 — main(팩) `%s` / PR 777\n' "$LANDSHA" > "$VF"; run --card "$CARD" --post
  [ $RC -eq 1 ] && has "결정 불가" && [ "$(wc_)" -eq 0 ] && ok "C7b 다른 카드 머리만 → REJECT rc1" || bad "C7b rc=$RC :: $OUT"; }
c8() { fresh; OKCARD; run --card "$CARD" --issue 7; expect "C8 --issue 7 · 카드 #9000 → REJECT rc2" 2 "Issue 번호 불일치" 0; }
c9() { fresh; OKCARD; run --card "$CARD" --out "$T/d9.md"; local tok; tok="$(sed -n 's/^DRAFT #9000 token=\([0-9a-f]*\) .*/\1/p' <<<"$OUT")"
  ij "[{\"body\":\"앞 줄\\ntoken=$tok\\n뒷 줄\",\"author\":{\"login\":\"byz-tank\"}}]"; run --card "$CARD" --post; expect "C9 정확 token 이미 있음 → ALREADY rc0 · 래퍼 0" 0 "^ALREADY #9000 token=$tok" 0; }
c10() { fresh; OKCARD; FAKE_WRAP_RC=1; run --card "$CARD" --post; expect "C10 래퍼 실패·token 없음 → 판정 불가 rc3 · 래퍼 1회(재게시 0)" 3 "판정 불가 — 게시 결과 불명" 1; }
c11() { fresh; mk 완성 'add:```' "add:- 착지: $OTHER" "add:- 실사건: 미실행" 'add:```'; run --card "$CARD"
  [ $RC -eq 0 ] && has "^DRAFT #9000" && ok "C11 코드 울타리 안 예제 줄은 고르지 않음" || bad "C11 rc=$RC :: $OUT"; }
c12() { fresh; mk 완성 'del:^- 실사건' 'add:- 실사건: 설치 뒤 mbox #232532 실측 미실행'; run --card "$CARD"; expect "C12a 실사건 «미실행» → rc4" 4 "DRAFT-ONLY 실사건" 0
  mk 완성 'del:^- 실사건' 'add:- 실사건: 설치 뒤 실측해서 잘 됨'; run --card "$CARD"; expect "C12b 토큰 없는 실사건 → rc4" 4 "DRAFT-ONLY 실사건" 0; }
c13() { fresh; mk 완성 'del:^- 정본'; run --card "$CARD"; expect "C13a 정본 줄 없음 → DRAFT-ONLY(기본 문구 0)" 4 "DRAFT-ONLY 정본 줄 없음" 0
  OKCARD; run --card "$CARD" --out "$T/d13.md"
  [ "$(grep -c '^정본 영향 없음: ' "$T/d13.md" 2>/dev/null)" = 1 ] && ! grep -q '^정본:' "$T/d13.md" && ok "C13b 정본 줄 = 키 하나로 한 줄" || bad "C13b $OUT"; }
c14() { fresh; OKCARD; ij '[{"body":"원인 확정: N — 아직 모름","author":{"login":"x"}}]'; run --card "$CARD" --post; expect "C14a 기존 원인 확정 N → DRAFT-ONLY 기존 미해결 판정" 4 "DRAFT-ONLY 기존 미해결 판정" 0
  ij '[{"body":"원인 확정: Y — 로그로 확정함\n같은 증상 보류: 1","author":{"login":"x"}}]'; run --card "$CARD" --post; expect "C14b 기존 보류 1 → DRAFT-ONLY" 4 "DRAFT-ONLY 기존 미해결 판정" 0; }
c15() { fresh; OKCARD; vf "$OTHER"; run --card "$CARD" --post; expect "C15 카드 착지 ≠ 판정문 sha → REJECT 착지 sha 불일치 rc1" 1 "착지 sha 불일치" 0; }
c16() { fresh; OKCARD; run --card "$CARD" --out "$T/d16.md"; local tok; tok="$(sed -n 's/^DRAFT #9000 token=\([0-9a-f]*\) .*/\1/p' <<<"$OUT")"
  ij "[{\"body\":\"token=${tok}0\",\"author\":{\"login\":\"byz-tank\"}}]"; run --card "$CARD" --post; expect "C16 token 부분 일치(13자) → ALREADY 아님 · 래퍼 1" 0 "^POSTED #9000" 1; }
c17() { fresh; OKCARD; sleep 60 & SLP=$!; mkdir -p "$T/st/9000.lock"; echo "$SLP" > "$T/st/9000.lock/pid"
  run --card "$CARD" --post; kill "$SLP" 2>/dev/null; SLP=""; expect "C17 같은 Issue 잠금 보유 → REJECT 게시 중 rc1 · 래퍼 0" 1 "REJECT 같은 Issue 게시 중" 0; }
c18() { fresh; OKCARD; printf '#!/usr/bin/env bash\necho "PASS #9000 제안 마무리(approved)"\nexit 0\n' > "$T/chk.sh"
  OUT="$(FT_CLOSE_DRAFT_CHECK="$T/chk.sh" FT_CLOSE_DRAFT_CHECK_JSON="$T/ij.json" FT_TANK_WRAPPER="$T/wrap.sh" FT_CLOSE_DRAFT_STATE="$T/st" bash "$B/ft-issue-close-draft.sh" --card "$CARD" --post 2>&1)"; RC=$?
  expect "C18 사전 검사 rc0 이지만 «제안 마무리» PASS → REJECT rc1 · 래퍼 0" 1 "REJECT 사전 검사 FAIL" 0; }
c19() { fresh; OKCARD; cp "$CARD" "$T/card.bak"; cp "$VF" "$T/v.bak"
  run --card "$CARD" --out "$CARD"; [ $RC -eq 2 ] && has "출력 = 입력 파일" && cmp -s "$CARD" "$T/card.bak" && ok "C19a --out = 카드 → REJECT rc2 · 카드 바이트 그대로" || bad "C19a rc=$RC :: $OUT"
  run --card "$CARD" --out "$VF"; [ $RC -eq 2 ] && has "출력 = 입력 파일" && cmp -s "$VF" "$T/v.bak" && ok "C19b --out = 판정문 → REJECT rc2 · 판정문 바이트 그대로" || bad "C19b rc=$RC :: $OUT"; }
c20() { fresh; OKCARD; mkdir -p "$T/fb"; GL="$T/gh.log"; : > "$GL"; : > "$T/chk.log"
  printf '#!/usr/bin/env bash\necho "gh $*" >> "%s"\necho "{\\"comments\\":[]}"\n' "$GL" > "$T/fb/gh"; chmod +x "$T/fb/gh"
  printf '#!/usr/bin/env bash\necho "check GH_REPO=${GH_REPO:-} $*" >> "%s"\necho "PASS #9000 완료 8항 + Closes 연결"\n' "$T/chk.log" > "$T/chk2.sh"
  OUT="$(PATH="$T/fb:$PATH" GH_REPO=org/A FT_ISSUE_REPO=org/B FT_CLOSE_DRAFT_CHECK="$T/chk2.sh" FT_TANK_WRAPPER="$T/wrap.sh" FT_CLOSE_DRAFT_STATE="$T/st" bash "$B/ft-issue-close-draft.sh" --card "$CARD" --post 2>&1)"; RC=$?
  [ $RC -eq 0 ] && grep -q 'GH_REPO=org/B' "$T/chk.log" && ! grep -q 'org/A' "$T/chk.log" "$GL" && grep -q -- '-R org/B' "$GL" && grep -q 'repo=org/B' "$WL" \
   && ok "C20 FT_ISSUE_REPO=B · GH_REPO=A → close-check·token 조회·래퍼 모두 B" || bad "C20 rc=$RC :: $OUT :: $(cat "$GL" "$T/chk.log" "$WL")"; }
c21() { local t; for t in '^- 착지:|착지 줄 없음' '진행→완성|완성 이동' '^- 원인 1줄|원인 1줄 없음'; do fresh; mk 완성 "del:${t%%|*}"; run --card "$CARD" --post; expect "C21 «${t##*|}» → DRAFT-ONLY rc4" 4 "DRAFT-ONLY ${t##*|}" 0; done
  for t in 남김 보관; do fresh; mk 완성 "head:# 인덱스: r9001-demo — 끝: $t 처리 카드"; run --card "$CARD" --post; expect "C21 머리 «${t}» → DRAFT-ONLY rc4" 4 "DRAFT-ONLY 머리에" 0; done; }
c22() { fresh; mk 완성 'add:- 착지: abc123'; run --card "$CARD" --post; expect "C22 마지막 착지 40hex 아님(앞 줄 유효) → DRAFT-ONLY(앞 줄로 안 내려감)" 4 "DRAFT-ONLY 착지" 0; }
c23() { fresh; OKCARD; mkdir -p "$T/fg"; GL="$T/gh23.log"; : > "$GL"
  printf '#!/usr/bin/env bash\necho "gh $*" >> "%s"\ncase "$*" in "api user"*) sleep 3; echo byz-tank;; *) echo https://github.com/x/y/issues/9000#issuecomment-1;; esac\n' "$GL" > "$T/fg/gh"; chmod +x "$T/fg/gh"
  OUT="$(PATH="$T/fg:$PATH" FT_GATE_TIMEOUT_S=1 FT_ISSUE_BOT_TOKEN=x FT_CLOSE_DRAFT_CHECK_JSON="$T/ij.json" FT_CLOSE_DRAFT_STATE="$T/st" FT_ISSUE_REPO=org/B bash "$B/ft-issue-close-draft.sh" --card "$CARD" --post 2>&1)"; RC=$?
  [ $RC -eq 3 ] && has "판정 불가 — 게시 결과 불명" && ! grep -q 'issue comment' "$GL" && ok "C23 래퍼 «gh api user» 8초 응답 → 7초(시험 1초)에 끊김 · 게시 호출 0 · rc3" || bad "C23 rc=$RC :: $OUT :: $(cat "$GL")"; }

stage "시작"
c1; c2; c3; c4; c5; stage "C1~C5"; c6; c7; c8; c9; c10; stage "C6~C10"; c11; c12; c13; c14; c15; stage "C11~C15"
c16; c17; c18; c19; c20; stage "C16~C20"; c21; c22; c23; stage "C21~C23"
for f in ft-issue-close-draft.sh ft-gh-as-tank.sh; do
  [ -f "$MIR/$f" ] && cmp -s "$BIN/$f" "$MIR/$f" && ok "bin·kit 같은 판 $f" || bad "bin·kit 다름 $f"; done
[ ! -x "$HERE/test_issue_close_draft_r1349.sh" ] && ok "시험 파일 실행 비트 0" || bad "시험 파일 실행 비트 있음"

mut() { # mut <번호> <사례 함수> <파일> <옛> <새> — 도구 사본을 한 줄 바꿔 그 사례가 FAIL 로 바뀌는지
  local n="$1" fn="$2" file="$3" b0=$fail
  rm -rf "$T/mbin"; mkdir "$T/mbin"; cp "$BIN"/ft-issue-close-draft.sh "$BIN"/ft-issue-close-check.sh "$BIN"/ft-gh-as-tank.sh "$BIN"/ft-harness-root.sh "$BIN"/ft-issue-close-gate.sh "$T/mbin/"
  python3 -I -c 'import sys;p,o,n=sys.argv[1:4];s=open(p,encoding="utf-8").read();assert s.count(o)>=1,"옛 문자열 없음";open(p,"w",encoding="utf-8").write(s.replace(o,n))' "$T/mbin/$file" "$4" "$5" \
    || { bad "변이 $n 적용 실패"; return; }
  B="$T/mbin"; "$fn" >/dev/null 2>&1; local g=$((fail-b0)); B="$BIN"; fail=$b0
  [ "$g" -gt 0 ] && ok "변이 $n → $fn FAIL(정상)" || bad "변이 $n 이 $fn 을 못 깨뜨림"
}
D=ft-issue-close-draft.sh
mut 1 c3 $D '; build_draft; precheck' '; build_draft'
mut 2 c6 $D '| tail -1 | sed -E "s/^- ($1):' '| head -1 | sed -E "s/^- ($1):'
mut 3 c7 $D '[ "$cnt" = 1 ] ||' '[ "$cnt" -ge 1 ] ||'
mut 4 c10 $D '  undecided "게시 결과 불명' '  bash "$WRAP" comment "$ISSUE" "$OUT" --apply >/dev/null 2>&1; undecided "게시 결과 불명'
mut 5 c4 $D '|| donly "완성 폴더 아님"' '|| true'
mut 6 c12 $D '{ [[ "$EVT" =~ $ev ]] &&' '{ true &&'
mut 7 c13 $D '|| donly "정본 줄 없음(기본 문구로 메우지 않음)"' '|| CANON="정본 영향 없음: 하네스 변경 기본 문구"'
stage "변이 1~7"
mut 8 c14 $D 'verdict_check; prior_verdict;' 'verdict_check;'
mut 9 c15 $D '[ "$(tr '"'"'A-F'"'"' '"'"'a-f'"'"' <<<"${BASH_REMATCH[1]}")" = "$LAND" ] || die 1' 'true || die 1'
mut 10 c16 $D 'select(. == $t)' 'select(contains($t))'
mut 11 c17 $D '  lock_issue; has_token; t=$?' '  has_token; t=$?'
mut 12 c18 $D '"PASS #$ISSUE 완료 8항"* ]]' '"PASS #$ISSUE"* ]]'
mut 13 c11 $D "/^\`\`\`/{f=!f; next} !f" '1'
mut 14 c22 $D 'LAND="$(pick 착지 |' 'LAND="$(card_lines | grep -E "^- 착지:[[:space:]]*[0-9a-fA-F]{40}" | tail -1 | sed -E "s/^- 착지:[[:space:]]*//" |'
mut 15 c23 ft-gh-as-tank.sh '"$TOUT" "${FT_GATE_TIMEOUT_S:-7}" gh api user' 'gh api user'
mut 16 c19 $D ' && [ "$o" != "$(realp "$VPATH")" ]' ''
mut 17 c21 $D '[ -n "$CAUSE" ] || donly "원인 1줄 없음"' 'true'
stage "변이 9~17"
[ $fail -eq 0 ] && echo "ALL PASS (${SECONDS}초)" || echo "FAILED $fail (${SECONDS}초)"
[ $fail -eq 0 ]
