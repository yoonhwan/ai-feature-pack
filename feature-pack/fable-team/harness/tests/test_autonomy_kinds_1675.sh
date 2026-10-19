#!/usr/bin/env bash
# test_autonomy_kinds_1675.sh — 자율 대리 종류 개정(판정 1675 · R162): push-merge = QUEUE 고정 · nano-reopen·docs-push 추가 ·
#   병합 승인 출처 분리(autonomy-merge-approved + log 줄) · 병합 가드·상태 가드 전환. 축 ⓐ~ⓖ + 변이 3.
# 격리: 임시 FT_ROOT·상태·원장·재개 기록 + 임시 git 저장소(브랜치·원격 픽스처) + 훅 stdin JSON — 실 상태·실 gh·실 원격 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; HK="$ROOT/harness/kit/fable-team/templates/hooks"; BIN="$ROOT/harness/bin"; MIR="$ROOT/harness/kit/fable-team/bin"
SG="$HK/autonomy-state-guard.sh"; MG="$HK/autonomy-merge-guard.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
S="$T/state"; AP="$S/autonomy-merge-approved"; OK="$S/autonomy-merge-ok"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/planner" FT_AUTONOMY_SH="$BIN/ft-autonomy.sh" FT_AUTONOMY_HOOK_LOG="$T/hook.log" FT_SEAT_RESUME_DIR="$T/resume"
mkdir -p "$T/.fable-team" "$S" "$T/planner" "$T/resume"
printf '%s\n' '- **100** (오빠) x 착수 승인' > "$T/planner/VERDICTS-planner-1.md"
LEDGER="$T/planner/VERDICTS-planner-1.md"
printf '#!/bin/bash\nexit 0\n' > "$T/gate-ok.sh"; printf '#!/bin/bash\necho "REJECT resource disk=1 limit=30"; exit 3\n' > "$T/gate-no.sh"

a() { "$BASH" "$BIN/ft-autonomy.sh" "$@"; }
mode_off() { rm -rf "$S/autonomy.json" "$S/autonomy.log" "$AP"; }
mode_on() { mode_off; a on >/dev/null 2>&1; }
mkbash() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "${2:-$T}"; }
mkfile() { python3 -c 'import json,sys;print(json.dumps({"tool_name":sys.argv[1],"cwd":sys.argv[3],"tool_input":{"file_path":sys.argv[2],"content":"x"}},ensure_ascii=False))' "$1" "$2" "${3:-$T}"; }
run() { out="$(printf '%s' "$2" | "$BASH" "$1" 2>"$T/err")"; rc=$?; }
denies() { run "$1" "$2"; [ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; }   # <훅> <stdin JSON>
bdn() { denies "$1" "$(mkbash "$2" "${4:-$T}")"; ck "$3" $?; }
bal() { run "$1" "$(mkbash "$2" "${4:-$T}")"; [ "$rc" = 0 ] && [ -z "$out" ]; ck "$3" $?; }
mkrepo() { git -c init.defaultBranch=main init -q "$1" && git -C "$1" checkout -q -B main && git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$2"; }

for f in "$SG" "$MG" "$BIN/ft-autonomy.sh" "$BIN/ft-proxy-decide.sh"; do bash -n "$f" 2>/dev/null; ck "bash -n $(basename "$f")" $?; done
python3 -m py_compile "$BIN/autonomy_classify.py" 2>/dev/null; ck "py_compile autonomy_classify.py" $?
for f in ft-autonomy.sh autonomy_classify.py ft-proxy-decide.sh; do
  cmp -s "$BIN/$f" "$MIR/$f"; ck "키트 미러 cmp 0 $f" $?; [ "$(wc -l < "$BIN/$f")" -le 200 ]; ck "200줄 이하 $f" $?
done

# ===== ⓐ~ⓒ 병합 가드: 옛 ok 파일 · 오빠 승인 + log 줄 · 승인 파일만 =====
R1="$T/r1"; R2="$T/r2"; R3="$T/r3"; mkrepo "$R1" one; mkrepo "$R2" two; mkrepo "$R3" three
H="$(git -C "$R1" rev-parse HEAD)"; F="$(git -C "$R2" rev-parse HEAD)"; G="$(git -C "$R3" rev-parse HEAD)"
mkdir -p "$OK"; echo "101 pr=7 da=x ev=A1" > "$OK/$F"; echo "101 pr=7 da=x ev=A1" > "$OK/$G"   # 옛 push-merge PROXY 시절 ok 파일
mode_on
bdn "$MG" "gh pr merge 7 --squash --match-head-commit $F" "ⓐ 옛 ok 파일만 있는 sha → deny (--match-head-commit)" "$R2"
bdn "$MG" "git push origin HEAD:main" "ⓐ 옛 ok 파일만 있는 sha → deny (main push)" "$R2"
a approve-merge "$H" >"$T/o" 2>&1; rc=$?; out="$(cat "$T/o")"
[ "$rc" = 0 ] && grep -q "^APPROVED $H A1$" "$T/o" && [ "$(cat "$AP/$H")" = "$(grep "^approve-merge $H " "$S/autonomy.log")" ]; ck "ⓑ approve-merge → APPROVED · 승인 파일 1줄 == log 줄" $?
[ "$(a mode)" = on ] && [ "$(a event)" = A1 ] && a status | grep -q '^\[자율 ON A1'; ck "ⓑ 승인 줄이 log 에 있어도 mode·event·status 정상(위변조 아님)" $?
bal "$MG" "gh pr merge 7 --squash --match-head-commit $H" "ⓑ 승인 + log 줄 일치 → allow (pr merge)" "$R1"
bal "$MG" "git push origin HEAD:main" "ⓑ 승인 + log 줄 일치 → allow (main push)" "$R1"
echo "approve-merge $G A1 123" > "$AP/$G"
bdn "$MG" "gh pr merge 7 --match-head-commit $G" "ⓒ 승인 파일만(log 줄 없음) → deny" "$R3"
echo "approve-merge $G A1 124" >> "$S/autonomy.log"
bdn "$MG" "gh pr merge 7 --match-head-commit $G" "ⓒ 승인 파일 ≠ log 줄(epoch 다름) → deny" "$R3"
echo "approve-merge $H A1 999" > "$AP/$G"; echo "approve-merge $H A1 999" >> "$S/autonomy.log"
bdn "$MG" "gh pr merge 7 --match-head-commit $G" "ⓒ 다른 sha 의 승인 줄을 복사한 파일 → deny" "$R3"
bdn "$MG" "gh pr merge 7 --squash --match-head-commit $F" "ⓑ 승인 안 한 다른 sha → 계속 deny" "$R2"
mode_off; bal "$MG" "gh pr merge 7 --squash" "ⓑ OFF → allow(불변)" "$R2"
before="$(ls "$AP" 2>/dev/null | wc -l | tr -d ' ')"; out="$(a approve-merge "$H" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "${out%%$'\n'*}" = "APPROVED $H OFF" ] && grep -q '^EQUIV 허용 범위: ' <<<"$out" &&[ "$(ls "$AP" 2>/dev/null | wc -l | tr -d ' ')" = "$((before+1))" ] && grep -qE "^approve-merge $H OFF [0-9]+$" "$AP/$H" && grep -qxF "$(head -n1 "$AP/$H")" "$S/autonomy.log"; ck "ⓑ OFF 에서 approve-merge → 기록(이벤트 칸 OFF · 파일+log 한 줄 · R336)" $?
rm -f "$AP/$H" "$S/autonomy.log"
mode_on; n0="$(wc -l < "$S/autonomy.log" | tr -d ' ')"
for bad in "" "abc" "${H}0" "$(printf '%s' "$H" | tr a-f A-F)" "--help"; do
  out="$(a approve-merge $bad 2>&1)"; rc=$?
  [ "$rc" = 2 ] && grep -q '^REJECT' <<<"$out" && [ "$(wc -l < "$S/autonomy.log" | tr -d ' ')" = "$n0" ] && [ ! -e "$AP" ]; ck "ⓑ 형식 틀림 [$bad] → REJECT rc 2 · 쓰기 0" $?
done
out="$(a approve-merge "$H" "$G" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(grep -c '^approve-merge ' "$S/autonomy.log")" = 2 ] && [ -f "$AP/$H" ] && [ -f "$AP/$G" ] && [ "$(a mode)" = on ]; ck "ⓑ sha 둘 → 승인 파일 2 · log 줄 2" $?
a off >/dev/null; [ "$(a mode)" = off ] && [ "$(a event)" = A1 ]; ck "ⓑ 승인 뒤 off → off · event 유지" $?
a on >/dev/null 2>&1; [ "$(a mode)" = on ] && [ "$(a event)" = A2 ]; ck "ⓑ 승인 줄이 섞인 log 에서 다시 on → A2" $?

# ===== ⓓ 상태 가드: 좌석의 approve-merge 실행·승인 파일 쓰기 deny =====
for c in "bash /x/ft-autonomy.sh approve-merge $H" "ft-autonomy.sh approve-merge $H" "FT_ROOT=/x bash -c 'ft-autonomy.sh approve-merge $H'" "env -S 'bash /x/ft-autonomy.sh approve-merge $H'" \
         "echo x > $AP/$H" "printf a | tee $AP/$H" "cp /tmp/x $AP/$H" "mv /tmp/x $AP/$H" "touch $AP/$H" "rm $AP/$H" \
         "bash /x/ft-queue-digest.sh issue" "ft-resume-attempt.sh allow seat uuid" "echo x > $S/autonomy-digest/a.json" "touch $S/seat-resume-attempts/a.state" "echo x > $OK/$H"; do
  bdn "$SG" "$c" "ⓓ 좌석 경로 deny: ${c:0:64}"
done
denies "$SG" "$(mkfile Write "$AP/$H")"; ck "ⓓ Write 승인 파일 → deny" $?
denies "$SG" "$(mkfile Edit "$S/seat-resume-attempts/x.state")"; ck "ⓓ Edit 재개 원장 → deny" $?
for c in "ft-autonomy.sh status" "bash ft-autonomy.sh mode" "cat $AP/$H" "ls $AP/" "ls $S/autonomy-digest/" "ft-queue-digest.sh show" "ft-resume-attempt.sh status" "echo \"ft-autonomy.sh approve-merge $H\"" "mbox.sh send x y \"approve-merge 는 막힌다\""; do
  bal "$SG" "$c" "ⓓ 읽기·글자만 allow: ${c:0:64}"
done

# ===== ⓔ 대리 도구·판정기: push-merge = QUEUE 고정 · ok 쓰기 0 =====
D() { out="$(cd "${CWD:-$T}" && "$BASH" "$BIN/ft-proxy-decide.sh" "$@" 2>"$T/err")"; rc=$?; }
ledger_n() { grep -c '\[대리 · 자율 ON' "$LEDGER"; }
mode_on; rm -rf "$OK"; n0="$(ledger_n)"
D --kind push-merge --q "병합 승인 e1" --choice 병합 --why "DA6 승인" --undo "git revert" --sha "$H" --da "$T/da.md" --pr 7
[ "$rc" = 2 ] && grep -q '^QUEUE main 병합·main push = 오빠 값(판정 1675)' <<<"$out" && [ ! -e "$OK" ] && [ "$(ledger_n)" = "$n0" ]; ck "ⓔ push-merge → QUEUE rc 2 · ok 폴더 0 · 원장 대리 줄 0" $?
python3 "$BIN/autonomy_classify.py" --kind push-merge --text "진행"; rc=$?; [ "$rc" = 2 ]; ck "ⓔ 판정기 push-merge = QUEUE" $?
for k in nano-reopen docs-push card-start press-order; do out="$(python3 "$BIN/autonomy_classify.py" --kind $k --text "진행")"; rc=$?; [ "$rc" = 0 ]; ck "ⓔ 판정기 $k = PROXY" $?; done
out="$(python3 "$BIN/autonomy_classify.py" --kind nano-reopen --text "브랜치 삭제")"; rc=$?; [ "$rc" = 2 ]; ck "ⓔ nano-reopen 도 제외 어휘 = QUEUE" $?

# ===== ⓕ nano-reopen: 근거 ①~④ + 기준선 ⑤ 각각 =====
SEAT="byz-harness-nano-t#0"; WT="$T/wt"; CARD="$WT/design/harness/indices/진행/c.md"; BR="nano/t"
jw() { python3 -c 'import json,sys;json.dump(dict(zip(sys.argv[2::2],sys.argv[3::2])),open(sys.argv[1],"w"))' "$@"; }   # <파일> <키> <값> …
setup_nano() {
  rm -rf "$WT" "$S/nano-card-base" "$T/resume"; mkdir -p "$WT/design/harness/indices/진행" "$S/nano-card-base" "$T/resume"
  git -c init.defaultBranch=main init -q "$WT" && git -C "$WT" checkout -q -b "$BR"
  printf '# 인덱스: c\n## 구현 범위\n1. 도구 하나.\n' > "$CARD"
  git -C "$WT" add -A && git -C "$WT" -c user.email=t@t -c user.name=t commit -q -m c
  jw "$S/nano-card-base/$SEAT.json" card_path "$CARD" card_blob "$(git hash-object "$CARD")" branch "$BR" worktree "$WT" at t
  jw "$T/resume/$SEAT.json" name "$SEAT" cwd "$WT" uuid u
}
nr() { FT_RESOURCE_GATE="${GATE:-$T/gate-ok.sh}" D --kind nano-reopen --q "나노 재개 $1" --choice 재개 --why "근거 확인" --undo "ft-nano-close.sh" --card "${2:-$CARD}" --seat "${3:-$SEAT}"; }
nq() { [ "$rc" = 2 ] && grep -q '^QUEUE' <<<"$out" && [ "$(ledger_n)" = "$n0" ]; ck "ⓕ $1 → QUEUE rc 2 · 대리 줄 0 ($(grep -o '^QUEUE .*' <<<"$out" | cut -c1-60))" $?; }
mode_on; n0="$(ledger_n)"
setup_nano; nr ok; [ "$rc" = 0 ] && grep -q '^PROXY' <<<"$out" && [ "$(ledger_n)" = "$((n0+1))" ] && tail -1 "$LEDGER" | grep -q '나노 재개 ok'; ck "ⓕ 근거 ①~⑤ 전부 충족 → PROXY rc 0 · 원장 대리 줄 +1" $?
n0="$(ledger_n)"
setup_nano; mkdir -p "$WT/design/harness/indices/대기"; cp "$CARD" "$WT/design/harness/indices/대기/c.md"; nr c1 "$WT/design/harness/indices/대기/c.md"; nq "① 카드가 진행/ 폴더 아님"
setup_nano; rm -f "$S/nano-card-base/$SEAT.json"; nr c2; nq "⑤ spawn 기준선 파일 없음"
setup_nano; echo "2. 새 범위 추가" >> "$CARD"; nr c3; nq "⑤ 카드가 기준선 뒤 확장됨"
setup_nano; rm -f "$T/resume/$SEAT.json"; nr c4; nq "③ 재개 기록 없음"
setup_nano; jw "$T/resume/$SEAT.json" name "byz-other#0" cwd "$WT" uuid u; nr c5; nq "③⑤ 다른 좌석의 재개 기록(name 다름)"
setup_nano; jw "$T/resume/$SEAT.json" name "$SEAT" cwd "$T/elsewhere" uuid u; nr c6; nq "③⑤ 재개 기록 cwd ≠ 기준선 워크트리"
setup_nano; git -C "$WT" checkout -q -b nano/other; nr c7; nq "③⑤ 워크트리 HEAD 가 기준선 가지가 아님"
setup_nano; jw "$S/nano-card-base/$SEAT.json" card_path "$CARD" card_blob "$(git hash-object "$CARD")" branch feat/x worktree "$WT" at t; nr c8; nq "② 기준선 가지가 nano/* 아님"
setup_nano; jw "$S/nano-card-base/$SEAT.json" card_path "$CARD" card_blob "$(git hash-object "$CARD")" branch nano/gone worktree "$WT" at t; nr c9; nq "② nano/* 가지가 실재하지 않음"
setup_nano; GATE="$T/gate-no.sh" nr c10; nq "④ 자원 문지기 REJECT"
setup_nano; nr c11 "$CARD" "../x"; nq "--seat 형식 틀림"
setup_nano; jw "$S/nano-card-base/$SEAT.json" card_path "$CARD" branch "$BR" worktree "$WT" at t; nr c12; nq "⑤ 기준선 필드(card_blob) 누락"
mode_off; setup_nano; nr off; [ "$rc" = 3 ]; ck "ⓕ OFF → rc 3" $?

# ===== ⓖ docs-push: 문서만 · main/배포 가지 제외 · fast-forward =====
export FT_DEPLOY_BRANCHES="v6 v65 release/*"
LR="$T/local"; REM="$T/remote.git"
lg() { git -C "$LR" -c user.email=t@t -c user.name=t "$@"; }
setup_docs() {
  rm -rf "$REM" "$LR"; git -c init.defaultBranch=main init -q --bare "$REM"; git -c init.defaultBranch=main init -q "$LR"
  echo base > "$LR/README.md"; lg add -A; lg commit -q -m base; lg remote add origin "$REM"; lg push -q origin main; lg checkout -q -b docs/x; lg push -q origin docs/x
}
commit_files() { local f; for f in "$@"; do mkdir -p "$(dirname "$LR/$f")"; echo "$RANDOM" > "$LR/$f"; done; lg add -A; lg commit -q -m c; lg rev-parse HEAD; }
dp() { CWD="$LR" D --kind docs-push --q "문서 push $1" --choice 올리기 --why "문서만" --undo "git revert" --branch "${3:-docs/x}" --sha "$2"; }
mode_on; n0="$(ledger_n)"
setup_docs; SD="$(commit_files NOTES.md design/harness/a.json)"; dp d1 "$SD"
[ "$rc" = 0 ] && grep -q '^PROXY' <<<"$out" && [ "$(ledger_n)" = "$((n0+1))" ]; ck "ⓖ md + design/** 만 · docs/x · ff → PROXY rc 0" $?
n0="$(ledger_n)"
gq() { [ "$rc" = 2 ] && grep -q '^QUEUE' <<<"$out" && [ "$(ledger_n)" = "$n0" ]; ck "ⓖ $1 → QUEUE rc 2 · 대리 줄 0 ($(grep -o '^QUEUE .*' <<<"$out" | cut -c1-60))" $?; }
setup_docs; SD="$(commit_files NOTES.md app/main.py)"; dp d2 "$SD"; gq "코드 파일 1개 섞임"
setup_docs; SD="$(commit_files NOTES.md)"; dp d3 "$SD" main; gq "대상 가지 main"
setup_docs; SD="$(commit_files NOTES.md)"; dp d4 "$SD" v65; gq "배포 가지 v65"
setup_docs; SD="$(commit_files NOTES.md)"; dp d5 "$SD" release/1.0; gq "배포 가지 release/* (glob)"
setup_docs; SD="$(commit_files NOTES.md)"; FT_DEPLOY_BRANCHES= dp d6 "$SD"; gq "FT_DEPLOY_BRANCHES 미설정(빈 값)"
setup_docs; SD="$(commit_files NOTES.md)"; dp d7 "$SD" docs/nope; gq "원격에 가지 없음"
setup_docs; commit_files A.md >/dev/null; lg push -q origin docs/x; lg reset -q --hard HEAD~1; SD="$(commit_files B.md)"; dp d8 "$SD"; gq "fast-forward 아님(원격이 앞섬)"
setup_docs; dp d9 "$(git -C "$LR" rev-parse HEAD)"; gq "diff 비어 있음"
setup_docs; SD="$(commit_files NOTES.md)"; CWD="$LR" D --kind docs-push --q "문서 push d10" --choice 올리기 --why "문서만" --undo "git revert" --branch docs/x --sha abc123; gq "--sha 형식 틀림"
mkdir -p "$T/hang"; printf '#!/bin/bash\n[ "$1" = ls-remote ] && { sleep 9; exit 0; }\nexec %s "$@"\n' "$(command -v git)" > "$T/hang/git"; chmod +x "$T/hang/git"
setup_docs; SD="$(commit_files NOTES.md)"; s=$(date +%s); PATH="$T/hang:$PATH" dp d11 "$SD"; e=$(( $(date +%s) - s )); gq "원격 비교(ls-remote) 7초 초과 ×2 (${e}s)"
[ "$e" -lt 26 ]; ck "ⓖ 원격 비교 총 시간 상한(7초×2 + 유예) (${e}s)" $?

# ===== ⓗ 원장(autonomy.log) 줄 분류 (DA⑥ H1): 정상 부가 줄은 통과 · 불완전·모르는 줄 = tamper =====
mutate() { python3 - "$@" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src, encoding="utf-8").read()
assert old in t, "mutation anchor missing"
open(dst, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}
LOGF="$S/autonomy.log"
mode_on; echo "approve-merge $H A1 123" >> "$LOGF"
[ "$(a mode)" = on ] && [ "$(a event)" = A1 ]; ck "ⓗ① 정상 승인 부가 줄 → mode on · event A1 유지" $?
mode_on; printf '2\toff\n' >> "$LOGF"; [ "$(a mode)" = tamper ] && [ "$(a status)" = "[자율 ?? 위변조 → OFF]" ]; ck "ⓗ② 불완전 OFF 줄(2<TAB>off) → tamper (ON 유지 0)" $?
mode_on; printf '2\toff\tA1\textra\n' >> "$LOGF"; [ "$(a mode)" = tamper ]; ck "ⓗ② 칸이 많은 모드 줄 → tamper" $?
mode_on; printf 'junk line\n' >> "$LOGF"; [ "$(a mode)" = tamper ]; ck "ⓗ③ 모르는 형식 줄 → tamper" $?
mode_on; echo "approve-merge zz A1 123" >> "$LOGF"; [ "$(a mode)" = tamper ]; ck "ⓗ③ 형식 틀린 승인 줄(sha 아님) → tamper" $?
mode_on; printf '%s\toff\tA1\n' 9 >> "$LOGF"; [ "$(a mode)" = tamper ]; ck "ⓗ④ 정상 OFF 줄 + JSON(on) 어긋남 → tamper" $?
mode_on; a off >/dev/null; [ "$(a mode)" = off ] && a on >/dev/null 2>&1 && [ "$(a mode)" = on ] && [ "$(a event)" = A2 ]; ck "ⓗ⑤ 정상 on→off→on 전환 → off 뒤 on(A2)" $?

# ===== 변이 4: 불완전 줄 판정(ⓒ)을 버리기로 되돌리면 ⓗ② 가 실패해야 한다 =====
rm -rf "$T/mutbin"; cp -R "$BIN" "$T/mutbin"
axis_h2() { rm -rf "$S/autonomy.json" "$LOGF"; "$BASH" "$1" on >/dev/null 2>&1; printf '2\toff\n' >> "$LOGF"; [ "$("$BASH" "$1" mode)" = tamper ]; }
axis_h2 "$BIN/ft-autonomy.sh"; ck "변이 기준: 원본은 ⓗ② 를 통과(tamper)" $?
mutate "$BIN/ft-autonomy.sh" "$T/mutbin/ft-autonomy.sh" "else bad=1; fi" "else :; fi"; ! cmp -s "$BIN/ft-autonomy.sh" "$T/mutbin/ft-autonomy.sh"; ck "변이 4 적용됨(ⓒ 판정 제거 = 불완전 줄 버림)" $?
! axis_h2 "$T/mutbin/ft-autonomy.sh"; ck "변이 4 → ⓗ② 실패(검출)" $?

# ===== 변이 3: 장치를 깨뜨리면 해당 축이 실패해야 한다 =====
axis_a() { mode_on; mkdir -p "$OK"; echo "101 pr=7 da=x ev=A1" > "$OK/$F"; denies "$1" "$(mkbash "gh pr merge 7 --squash --match-head-commit $F" "$R2")"; }   # ⓐ 옛 ok 파일만 있는 sha → deny
axis_c() { mode_on; mkdir -p "$AP"; echo "approve-merge $G A1 123" > "$AP/$G"; denies "$1" "$(mkbash "gh pr merge 7 --match-head-commit $G" "$R3")"; }   # ⓒ 승인 파일만 → deny
axis_d() { denies "$1" "$(mkbash "echo x > $AP/$H")"; }                                                          # ⓓ 승인 폴더 쓰기 → deny
axis_a "$MG"; ck "변이 기준: 원본 가드는 ⓐ 를 통과(deny)" $?
axis_c "$MG"; ck "변이 기준: 원본 가드는 ⓒ 를 통과(deny)" $?
axis_d "$SG"; ck "변이 기준: 원본 상태 가드는 ⓓ 를 통과(deny)" $?
python3 - "$MG" "$T/mut1.sh" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
i, j = t.index("    def ok(self, sha):"), t.index("    def git(self")
old_ok = '    def ok(self, sha):\n        return bool(SHA.match(sha)) and os.path.isfile(os.path.join(os.path.dirname(self.approved), "autonomy-merge-ok", sha))\n\n'
open(sys.argv[2], "w", encoding="utf-8").write(t[:i] + old_ok + t[j:])
PY
! cmp -s "$MG" "$T/mut1.sh"; ck "변이 1 적용됨(가드가 merge-ok 를 다시 읽음)" $?
! axis_a "$T/mut1.sh"; ck "변이 1 → ⓐ 실패(검출)" $?
mutate "$MG" "$T/mut2.sh" " and lines[0] in logged" ""; ! cmp -s "$MG" "$T/mut2.sh"; ck "변이 2 적용됨(log 대조 삭제)" $?
! axis_c "$T/mut2.sh"; ck "변이 2 → ⓒ 실패(검출)" $?
mutate "$SG" "$T/mut3.sh" "autonomy-merge-approved|" ""; ! cmp -s "$SG" "$T/mut3.sh"; ck "변이 3 적용됨(PROT 의 approved 삭제)" $?
! axis_d "$T/mut3.sh"; ck "변이 3 → ⓓ 실패(검출)" $?

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
