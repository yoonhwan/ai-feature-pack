#!/usr/bin/env bash
# test_autonomy_scope_code_hook.sh — 범위 승인 시험 3/3: r3 grants.audit · R411 종류 code(임시 origin+clone) · 상태 폴더 훅 (r1197 · 옛 test_autonomy_scope.sh 177행~끝 그대로)
# 격리·공용 준비 = lib/autonomy_scope_setup.sh · 다른 두 파일(grant · stop_tamper)과 상태를 나누지 않는다(구역마다 fresh).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"

# ===== r3: grant 슬랙 1줄 + grants.audit + scope-status --audit (판정 2078 ⓐ — 직접 쓰기는 막지 못하고 «들킨다») =====
AU="$S/autonomy-scope/grants.audit"; : > "$STUB_POST_LOG"
fresh; grant --for 10h --max 5 --daily 2 --classes docs,ff
[ $rc = 0 ] && [ "$(wc -l < "$AU" | tr -d ' ')" = 1 ] && printf 'S1\tA1\t%s\tuntil=%s\tmax=5\tdaily=2\tclasses=docs,ff\tslack_ts=1800000000.000100\n' "$T0" "$((T0+36000))" | cmp -s - "$AU"; ck "게시 성공 → grant + grants.audit 1줄(슬랙 ts 포함)" $?
[ "$(wc -l < "$STUB_POST_LOG" | tr -d ' ')" = 3 ] && grep -qE '^자율 켜짐\([^)]+\)$' <(sed -n 1p "$STUB_POST_LOG") \
  && [ "$(sed -n 2p "$STUB_POST_LOG")" = "혼자 해도 되는 것: 문서 병합 · 빨리 감기 병합 5건까지 · 하루 2건" ] \
  && grep -qE '^언제까지: [0-9]{2}:[0-9]{2} 까지$' <(sed -n 3p "$STUB_POST_LOG") \
  && ! grep -Eqi 'max|daily|classes|level|부여|[0-9]{10}' "$STUB_POST_LOG"; ck "슬랙 본문 3줄 꼴(켜짐·혼자 해도 되는 것·언제까지 · 내부 번호 0 · r658)" $?
n0="$(lines)"; rm -f "$AU"
STUB_POST_RC=1 grant --for 10h --max 5 --classes docs; [ $rc = 1 ] && has '슬랙 게시 실패 rc=1'; ck "게시 실패 → REJECT rc 1" $?
[ "$(lines)" = "$n0" ] && [ ! -e "$AU" ] && ! grep -q '^approve-scope S2' "$LOG"; ck "게시 실패 → grant·audit 쓰기 0" $?
FT_SCOPE_SLACK_POST=/nonexistent grant --for 10h --max 5 --classes docs; [ $rc = 1 ] && has '슬랙 게시 도구 없음'; ck "게시 도구 없음 → REJECT rc 1 · 쓰기 0" $?
[ "$(lines)" = "$n0" ]; ck "도구 없음 쓰기 0" $?
run a scope-status --audit; [ $rc = 3 ] && has '^AUDIT-MISMATCH'; ck "audit 줄을 지운 상태(S1 grant 만 남음) → MISMATCH rc 3" $?
fresh; run a scope-status --audit; [ $rc = 0 ] && has '^AUDIT-OK grants=0 used=0$'; ck "--audit grant 없음 → AUDIT-OK grants=0" $?
grant --for 10h --max 5 --classes docs >/dev/null; run a scope-approve "$(sha 71)"; run a scope-approve "$(sha 72)"
run a scope-status --audit; [ $rc = 0 ] && has '^AUDIT-OK grants=1 used=2$'; ck "정상 흐름 → AUDIT-OK grants=1 used=2" $?
cp "$LOG" "$T/log.keep"; cp "$AU" "$T/au.keep"
printf 'approve-scope S2 A1 %s until=%s max=30 daily=30 classes=docs,ff,revert\n' "$((T0+5))" "$((T0+999999))" >> "$LOG"
run a scope-status --audit; [ $rc = 3 ] && has '^AUDIT-MISMATCH S2 grant'; ck "log 에 직접 덧붙인 grant(슬랙 줄 없음) → MISMATCH S2 rc 3" $?
[ "$(a mode)" = on ]; ck "덧붙인 grant 줄 꼴은 위변조 판정에 안 걸림(그래서 --audit 이 잡는다)" $?
cp "$T/log.keep" "$LOG"; sed -i '' 's/max=5/max=9/' "$AU"
run a scope-status --audit; [ $rc = 3 ] && has '^AUDIT-MISMATCH S1 grant'; ck "audit 값을 바꿈(max=9) → MISMATCH S1" $?
cp "$T/au.keep" "$AU"; sed -i '' 's/slack_ts=[0-9.]*/slack_ts=/' "$AU"
run a scope-status --audit; [ $rc = 3 ] && has '^AUDIT-MISMATCH S1 grant'; ck "audit 의 슬랙 ts 를 비움 → MISMATCH" $?
cp "$T/au.keep" "$AU"
grep -v "^scope-use S1 $(sha 72) " "$LOG" > "$T/log.cut" && cp "$T/log.cut" "$LOG"
run a scope-status --audit; [ $rc = 3 ] && has '^AUDIT-MISMATCH S1 used: scope-use 1 ≠ 원장 2행'; ck "scope-use 줄 삭제 → MISMATCH used(원장 행과 어긋남) rc 3" $?
cp "$T/log.keep" "$LOG"; rm -f "$AP/$(sha 72)"
run a scope-status --audit; [ $rc = 3 ] && has '^AUDIT-MISMATCH S1 used: scope-use 2 > 승인 파일 1'; ck "승인 파일 삭제 → MISMATCH used(승인 파일 수 < scope-use 수) rc 3" $?
printf 'approve-merge %s A1 %s\n' "$(sha 73)" "$((T0+7))" > "$AP/$(sha 73)"; printf '%s\n' "approve-merge $(sha 72) A1 $T0" > "$AP/$(sha 72)"
run a scope-status --audit; [ $rc = 0 ] && has '^AUDIT-OK grants=1 used=2$'; ck "오빠 수동 approve-merge 가 더 있어도(파일 3 ≥ 2) AUDIT-OK" $?

# ===== R411: 종류 code — 시험 통과 세트만 · code-max 안 (판정 2326) · 실 git(임시 origin+clone) + 실 evidence-check·approval-equiv · 분류기만 스텁 =====
R="$T/r"; OR="$T/origin.git"; CARD="$T/card.md"; export STUB_OUT="CLASS code"
G() { git -C "$R" "$@"; }; cm() { G add -A && G commit -q -m "$1"; }; hd() { G rev-parse HEAD; }
git init -q --bare -b main "$OR"; git clone -q "$OR" "$R" 2>/dev/null; G config user.name t; G config user.email t@t
echo base > "$R/README.md"; cm base; G push -q origin HEAD:main; G fetch -q origin
G checkout -q -B nano origin/main; mkdir -p "$R/src"; echo 'x = 1' > "$R/src/x.py"; cm code1; A="$(hd)"                       # 나노 세트 A(코드 1커밋)
G checkout -q -B main origin/main; echo m > "$R/b.txt"; cm main1; G push -q origin main; G fetch -q origin                   # main 이 1커밋 나아감
G checkout -q nano; G merge -q --no-edit origin/main >/dev/null 2>&1; SM="$(hd)"                                               # SM = A 위 main 병합만
G checkout -q -B nano2 "$A"; echo 'y = 2' > "$R/src/y.py"; cm own2; SX="$(hd)"                                                 # SX = A 위 자기 변경 더(동일 승인 아님)
G checkout -q -B other origin/main; mkdir -p "$R/src"; echo z > "$R/src/z.py"; cm other; X="$(hd)"; G checkout -q nano                          # X = A 의 조상 아님
card() { printf '# 카드\n## 상태\n- 세트: %s · 시험: %s · 이슈: 0\n' "$1" "${2:-bash t.sh rc=0}" > "$CARD"; }
ar() { FT_ROOT="$R" a "$@"; }
# ⓐ grant
fresh; grant --for 2h --max 5 --classes docs,ff,revert,code --code-max 2
[ $rc = 0 ] && has '^SCOPE-GRANTED S1 A1 until=[0-9]{2}:[0-9]{2} max=5 daily=5 classes=docs,ff,revert,code codemax=2$'; ck "ⓐ code grant → SCOPE-GRANTED … codemax=2" $?
grep -qxF "approve-scope S1 A1 $T0 until=$((T0+7200)) max=5 daily=5 classes=docs,ff,revert,code codemax=2" "$LOG" && [ "$(a mode)" = on ]; ck "ⓐ log grant 줄 꼴 · SCOPE_GRANT_RE 통과(mode=on)" $?
run a scope-status; has '^\[범위 승인 S1 · A1 · .* 0/5 · 오늘 0/5 · docs,ff,revert,code · code 0/2\]$'; ck "ⓐ scope-status code 0/2" $?
grep -qxF "혼자 해도 되는 것: 문서 병합 · 빨리 감기 병합 · 되돌림 5건까지 · 코드 병합 2건까지 · 하루 5건" "$STUB_POST_LOG" && run a scope-status --audit && [ $rc = 0 ]; ck "ⓐ 슬랙 2줄에 코드 병합 2건까지(r658) · --audit AUDIT-OK(codemax 칸)" $?
# ⓓ 거절 — 쓰기 0
n0="$(lines)"; card "$A"
run ar scope-approve "$A"; [ $rc = 2 ] && has '--card <카드.md> 필요'; ck "ⓓ --card 없음 → REJECT" $?
printf '# 카드\n## 상태\n- 없음\n' > "$CARD"; run ar scope-approve "$A" --card "$CARD"; [ $rc = 2 ] && has '꼴 아님'; ck "ⓓ 증거 줄 없음 → REJECT" $?
card "$A" "bash t.sh rc=1"; run ar scope-approve "$A" --card "$CARD"; [ $rc = 2 ] && has '꼴 아님'; ck "ⓓ 시험 rc≠0 → REJECT" $?
card "$X"; run ar scope-approve "$A" --card "$CARD"; [ $rc = 2 ] && has '증거 검사 rc=1: REJECT .*조상이 아니다'; ck "ⓓ 세트 sha 가 head 의 조상 아님 → REJECT" $?
card "$A"; run ar scope-approve "$SX" --card "$CARD"; [ $rc = 2 ] && has '동일 승인 아님 rc=1: NOT-EQUIV'; ck "ⓓ A 위 자기 변경 더(NOT-EQUIV) → REJECT" $?
run ar scope-approve "$A" --card "$T/none.md"; [ $rc = 2 ] && has '카드 없음'; ck "ⓓ 카드 파일 없음 → REJECT" $?
[ "$(lines)" = "$n0" ] && [ ! -d "$AP" ] && [ ! -e "$S/autonomy-scope/S1.ledger.tsv" ]; ck "ⓓ 거절 전부 쓰기 0(승인 파일·원장 0)" $?
# ⓑ 세트 == head
card "$A"; run ar scope-approve "$A" --card "$CARD" --pr 9
[ $rc = 0 ] && has "^SCOPE-OK $A class=code code=1/2 used=1/5 today=1/5\$"; ck "ⓑ 세트 == head → SCOPE-OK class=code code=1/2" $?
[ "$(cat "$AP/$A")" = "approve-merge $A A1 $T0" ] && grep -qxF "$(cat "$AP/$A")" "$LOG" && grep -qxF "scope-use S1 $A code $T0" "$LOG"; ck "ⓑ 승인 파일 1줄 == log 한 줄 · scope-use code" $?
printf '%s\t%s\t9\tcode\tevidence=%s@%s\t\t\n' "$T0" "$A" "$CARD" "$A" | cmp -s - "$S/autonomy-scope/S1.ledger.tsv"; ck "ⓑ 원장 5번째 칸 evidence=<카드>@<A>" $?
[ "$(a mode)" = on ]; ck "ⓑ scope-use code 줄은 위변조 아님" $?
STUB_OUT="CLASS docs" run ar scope-approve "$(sha 81)"; [ $rc = 0 ] && has "^SCOPE-OK $(sha 81) class=docs used=2/5 today=2/5\$"; ck "ⓔ docs 는 --card 없이 · code 건수와 별개" $?
# ⓒ head = 세트 위 main 병합만(EQUIV)
run ar scope-approve "$SM" --card "$CARD"
[ $rc = 0 ] && has "^SCOPE-OK $SM class=code code=2/2 used=3/5 today=3/5 equiv=$A\$"; ck "ⓒ 세트 위 main 병합 head → SCOPE-OK equiv=A" $?
[ "$(awk -F'\t' 'NR==3{print $5}' "$S/autonomy-scope/S1.ledger.tsv")" = "evidence=$CARD@$A" ]; ck "ⓒ 원장 evidence=<카드>@<A>" $?
# ⓔ code-max 도달
run ar scope-approve "$SX" --card "$CARD"; [ $rc = 2 ] && has '정지: code 건수 도달\(2/2\)'; ck "ⓔ code-max 도달 → REJECT" $?
[ -f "$S/autonomy-scope/S1.stopped" ] && grep -q '^scope-stop S1 [0-9]* code 건수 도달(2/2)$' "$LOG" && [ ! -e "$AP/$SX" ]; ck "ⓔ 도달 = 기존 건수 도달과 같은 정지(log + .stopped) · 승인 0" $?
run a scope-status --audit; [ $rc = 0 ] && has '^AUDIT-OK grants=1 used=3$'; ck "ⓔ 정상 흐름 --audit AUDIT-OK" $?
fresh; grant --for 2h --max 5 --classes docs,ff,revert >/dev/null; card "$A"; run ar scope-approve "$A" --card "$CARD"; [ $rc = 2 ] && has '종류 code 는 승인 범위\(docs,ff,revert\) 밖'; ck "ⓔ 옛 grant(code 없음 · codemax 없음) → code 범위 밖 REJECT(기본 닫힘)" $?
export STUB_OUT="CLASS docs"

# ===== 훅: 상태 폴더·approve-scope 보호 =====
mkbash() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "$T"; }
mkfile() { python3 -c 'import json,sys;print(json.dumps({"tool_name":sys.argv[1],"cwd":sys.argv[3],"tool_input":{"file_path":sys.argv[2],"content":"x"}},ensure_ascii=False))' "$1" "$2" "$T"; }
hook() { out="$(printf '%s' "$1" | "$BASH" "$SG" 2>/dev/null)"; rc=$?; }
dn() { hook "$1"; [ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; ck "$2" $?; }
al() { hook "$1"; [ "$rc" = 0 ] && [ -z "$out" ]; ck "$2" $?; }
bash -n "$SG"; ck "bash -n autonomy-state-guard.sh" $?
dn "$(mkbash "bash $BIN/ft-autonomy.sh approve-scope --for 10h --max 5 --classes docs")" "좌석 approve-scope 실행 → deny"
dn "$(mkbash "ft-autonomy.sh approve-scope --for 1h --max 1 --classes ff")" "ft-autonomy.sh approve-scope → deny"
dn "$(mkbash "FT_ROOT=/x bash -c 'ft-autonomy.sh approve-scope --for 1h'")" "bash -c 안 approve-scope → deny"
al "$(mkbash "bash $BIN/ft-autonomy.sh scope-approve $(sha 1) --pr 3")" "scope-approve → allow (좌석 경로)"
al "$(mkbash "bash $BIN/ft-autonomy.sh scope-stop S1 사유")" "scope-stop → allow"
al "$(mkbash "bash $BIN/ft-autonomy.sh scope-status")" "scope-status → allow"
al "$(mkbash "cat $S/autonomy-scope/S1.ledger.tsv")" "autonomy-scope/ 읽기 → allow"
dn "$(mkbash "echo x > $S/autonomy-scope/S1.stopped")" "autonomy-scope/ 리다이렉트 쓰기 → deny"
dn "$(mkbash "rm $S/autonomy-scope/S1.stopped")" "autonomy-scope/ rm → deny"
dn "$(mkbash "cp /tmp/x $S/autonomy-scope/S9.ledger.tsv")" "autonomy-scope/ cp 대상 → deny"
dn "$(mkfile Write "$S/autonomy-scope/S1.stopped")" "Write autonomy-scope/ → deny"
dn "$(mkfile Edit "$S/autonomy-scope/S1.ledger.tsv")" "Edit autonomy-scope/ → deny"
al "$(mkfile Write "$T/other.txt")" "다른 경로 Write → allow"

echo "fail=$fail"; [ "$fail" = 0 ]
