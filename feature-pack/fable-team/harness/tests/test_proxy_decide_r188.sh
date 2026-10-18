#!/usr/bin/env bash
# test_proxy_decide_r188.sh — ft-proxy-decide.sh 결함 2종 + 문구(R188): docs-push 배포 가지 목록 파일 · card-start 판정 줄 표 행.
#   ⓐ 표 행(`| N |`)에서도 카드 이름·부정 낱말 검사가 글머리 꼴과 같다 · ⓑ 번호 경계 · ⓒ 목록 없음 → QUEUE + 파일 경로
#   ⓓ env 우선 · ⓔ 배포 가지 이름이면 QUEUE · ⓕ 인자 부족 문구 예시 · 변이 1(표 행 패턴 제거 → ⓐ 실패)
#   R410(판정 2326): wt-clean 종류 ⓐ PROXY · ⓑ STALE·세션 실재·경로·글자 → QUEUE · ⓒ 실행 줄 제외 어휘 · ⓓ 쪽지 가드 [아침 묶음 «결정 N:» 대리= 칸
# 격리: 임시 FT_ROOT·상태·원장 + 임시 git 저장소 — 실 상태·실 mbox·실 /tmp/h* 쓰기 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; MIR="$HERE/../../harness/kit/fable-team/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
S="$T/state"; P="$T/planner"; LEDGER="$P/VERDICTS-planner-1.md"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$P" FT_AUTONOMY_HOOK_LOG="$T/hook.log"
mkdir -p "$S" "$P"; unset FT_DEPLOY_BRANCHES
printf '%s\n' '- **100** (오빠) x 착수 승인' > "$LEDGER"
"$BASH" "$BIN/ft-autonomy.sh" on >/dev/null 2>&1; [ "$("$BASH" "$BIN/ft-autonomy.sh" mode)" = on ]; ck "준비: 자율 ON" $?

cmp -s "$BIN/ft-proxy-decide.sh" "$MIR/ft-proxy-decide.sh"; ck "키트 미러 cmp 0" $?
[ "$(wc -l < "$BIN/ft-proxy-decide.sh")" -le 200 ]; ck "200줄 이하" $?

SB="$BIN"; n=0
D() { n=$((n+1)); out="$(cd "${CWD:-$T}" && "$BASH" "$SB/ft-proxy-decide.sh" --q "질문 $n" --choice 추천 --why 근거 --undo 되돌림 "$@" 2>"$T/err")"; rc=$?; }
led() { grep -c '\[대리 · 자율 ON' "$LEDGER"; }
CARD="$T/design/x/indices/대기/r188-x.md"; mkdir -p "$(dirname "$CARD")"; printf '# 인덱스: r188-x\n## 구현 범위\n1. 도구 하나.\n' > "$CARD"
cs() { D --kind card-start --card "$CARD" --verdict "$1"; }   # <판정 번호>
okp() { [ "$rc" = 0 ] && grep -q '^PROXY' <<<"$out"; }
okq() { [ "$rc" = 2 ] && grep -q "^QUEUE.*$1" <<<"$out"; }   # <사유 조각>

# ===== ⓐⓑ card-start 판정 줄: 글머리 · 표 행 =====
printf '%s\n' \
  '- **200** (오빠) r188-x 착수 승인' \
  '| 201 | 16:0x | (오빠) r188-x 착수 승인 | harness |' \
  '|202| 16:0x | (오빠) r188-x 착수 승인 | harness |' \
  '|   203   | 16:0x | (오빠) r188-x 착수 승인 | harness |' \
  '| 204 | 16:0x | (오빠) 다른카드 착수 승인 | harness |' \
  '| 205 | 16:0x | (오빠) r188-x 보류 · 착수 아님 | harness |' \
  '| 206 | 16:0x | (오빠) r188-x 설계만 승인 | harness |' \
  '| 207 | 16:0x | (오빠) r188-x 확인 | harness |' \
  '| 17060 | 16:0x | (오빠) r188-x 착수 승인 | harness |' \
  '| 11706 | 16:0x | (오빠) r188-x 착수 승인 | harness |' \
  '- **17061** (오빠) r188-x 착수 승인' >> "$LEDGER"
n0="$(led)"; cs 200; okp; ck "ⓐ 글머리 꼴 판정 → PROXY (기존 동작)" $?
for v in 201 202 203; do cs "$v"; okp; ck "ⓐ 표 행 판정 $v → PROXY" $?; done
[ "$(led)" = "$((n0+4))" ]; ck "ⓐ PROXY 4건 → 원장 대리 줄 +4" $?
n0="$(led)"
cs 204; okq "카드 이름"; ck "ⓐ 표 행: 카드 이름 없음 → QUEUE" $?
cs 205; okq "부정·보류"; ck "ⓐ 표 행: 부정·보류 낱말 → QUEUE" $?
cs 206; okq "설계·제안서까지만"; ck "ⓐ 표 행: 설계만 → QUEUE" $?
cs 207; okq "착수 낱말 없음"; ck "ⓐ 표 행: 착수 낱말 없음 → QUEUE" $?
[ "$(led)" = "$n0" ]; ck "ⓐ QUEUE 4건 → 대리 줄 0" $?
cs 1706; okq "원장에 판정 1706 줄 없음"; ck "ⓑ 17060·11706·17061 이 1706 에 안 걸림 → QUEUE" $?
cs 170; okq "원장에 판정 170 줄 없음"; ck "ⓑ 접두 170 이 17060 에 안 걸림" $?
cs 17060; okp; ck "ⓑ 정확히 17060 은 찾음" $?

# ===== ⓕ 인자 부족 문구 =====
D --kind card-start; okq "예) ft-proxy-decide.sh --kind card-start --card design/<팀>/indices/대기/<카드>.md --verdict <판정 번호> --q <질문> --choice <추천안> --why <근거> --undo <되돌림>"; ck "ⓕ card-start 인자 부족 → 예시 1줄(--kind 로 시작 · 필수 인자 전부)" $?
D --kind nano-reopen; okq "예) ft-proxy-decide.sh --kind nano-reopen --card design/<팀>/indices/진행/<카드>.md --seat <좌석> --q <질문> --choice <추천안> --why <근거> --undo <되돌림>"; ck "ⓕ nano-reopen 인자 부족 → 예시 1줄(--kind 로 시작 · 필수 인자 전부)" $?
grep -q '예) ft-proxy-decide.sh --kind ' <<<"$(grep -h '예) ft-proxy-decide.sh' "$BIN/ft-proxy-decide.sh")" && ! grep -q '예) ft-proxy-decide.sh [a-z]' "$BIN/ft-proxy-decide.sh"; ck "ⓕ 소스의 예시 문구는 전부 --kind 로 시작" $?

# ===== ⓒⓓⓔ docs-push 배포 가지 목록 =====
LR="$T/local"; REM="$T/remote.git"; DF="$S/deploy-branches.txt"
lg() { git -C "$LR" -c user.email=t@t -c user.name=t "$@"; }
setup_docs() {
  rm -rf "$REM" "$LR" "$DF"; git -c init.defaultBranch=main init -q --bare "$REM"; git -c init.defaultBranch=main init -q "$LR"
  echo base > "$LR/README.md"; lg add -A; lg commit -q -m base; lg remote add origin "$REM"; lg push -q origin main
  lg checkout -q -b docs/x; lg push -q origin docs/x; lg checkout -q -b v6; lg push -q origin v6; lg checkout -q -b release/1.0; lg push -q origin release/1.0; lg checkout -q docs/x
  echo "$RANDOM" > "$LR/NOTES.md"; lg add -A; lg commit -q -m c; SD="$(lg rev-parse HEAD)"
}
dp() { CWD="$LR" D --kind docs-push --branch "${1:-docs/x}" --sha "$SD"; }
n0="$(led)"
setup_docs; dp; okq "② 배포 가지 목록 없음 — FT_DEPLOY_BRANCHES 또는 $DF"; ck "ⓒ env·파일 둘 다 없음 → QUEUE + 사유에 파일 경로" $?
setup_docs; : > "$DF"; dp; okq "배포 가지 목록 없음"; ck "ⓒ 빈 파일 → QUEUE" $?
setup_docs; printf '# 주석만\n\n   \n' > "$DF"; dp; okq "배포 가지 목록 없음"; ck "ⓒ 주석·공백만 있는 파일 → QUEUE" $?
[ "$(led)" = "$n0" ]; ck "ⓒ QUEUE 3건 → 대리 줄 0" $?
setup_docs; printf '# 배포 가지\nv6\nrelease/*   # glob\n' > "$DF"; dp docs/x; okp; ck "파일만: 배포 가지 아닌 docs/x → PROXY" $?
setup_docs; printf 'v6\nrelease/*\n' > "$DF"; dp v6; okq "배포 가지(v6)"; ck "ⓔ 파일에 적힌 배포 가지 v6 → QUEUE" $?
setup_docs; printf 'v6\nrelease/*\n' > "$DF"; dp release/1.0; okq "배포 가지(release/\*)"; ck "ⓔ 파일의 glob release/* → QUEUE" $?
setup_docs; printf 'v6\n' > "$DF"; FT_DEPLOY_BRANCHES="v65" dp docs/x; okp; ck "ⓓ env 가 있으면 env 우선(파일 v6 은 무시) → docs/x PROXY" $?
setup_docs; printf 'docs/x\n' > "$DF"; FT_DEPLOY_BRANCHES="v65" dp docs/x; okp; ck "ⓓ env 우선(파일이 docs/x 를 배포 가지로 적어도 env 에 없으면 PROXY)" $?
setup_docs; printf 'v6\n' > "$DF"; FT_DEPLOY_BRANCHES="docs/*" dp docs/x; okq "배포 가지(docs/\*)"; ck "ⓓ env 가 docs/* 면 파일 v6 과 무관하게 QUEUE" $?
setup_docs; FT_DEPLOY_BRANCHES="v6 release/*" dp release/1.0; okq "배포 가지"; ck "ⓔ env 의 배포 가지 → QUEUE 그대로" $?
setup_docs; dp main; okq "main"; ck "ⓔ main → 목록과 무관하게 QUEUE" $?

# ===== R410 ⓐ~ⓒ wt-clean 종류(판정 2326) — 근거 = ft-nano-close 계획 파일 · 실 계획 꼴은 fixtures/r410 (plan-ver 만 바꿔 굽는다) =====
cmp -s "$BIN/autonomy_classify.py" "$MIR/autonomy_classify.py"; ck "R410 판정기 키트 미러 cmp 0" $?
python3 -m py_compile "$BIN/autonomy_classify.py"; ck "R410 py_compile autonomy_classify.py" $?
WD="$S/wt-clean"; mkdir -p "$WD"; GENB="$(git hash-object "$BIN/ft-nano-close.sh")"; FIX="$HERE/../fixtures/r410/wt-clean-plan.sh.hil"
printf '#!/bin/sh\nexit 1\n' > "$T/tmux-none"; printf '#!/bin/sh\nexit 0\n' > "$T/tmux-live"; chmod +x "$T/tmux-none" "$T/tmux-live"
mkplan() { sed "s/^# plan-ver: .*/# plan-ver: $2/" "$FIX" > "$1"; [ -z "${3:-}" ] || printf '%s\n' "$3" >> "$1"; }   # <파일> <plan-ver> [덧붙일 실행 줄]
wcd() { FT_TMUX_BIN="${TM:-$T/tmux-none}" D --kind wt-clean --plan "$1"; }
qrows() { local n; n="$(grep -c '| wt-clean |' "$P/AUTONOMY-QUEUE.md" 2>/dev/null)"; echo "${n:-0}"; }
n0="$(led)"; mkplan "$WD/a.sh.hil" "$GENB"; wcd "$WD/a.sh.hil"; okp; ck "R410 ⓐ 실 계획 꼴 · plan-ver = 생성기 blob · 브랜치 보존 글자 · 세션 0 → PROXY rc0" $?
echo "  ⓐ 원문: $out"
[ "$(led)" = "$((n0+1))" ] && grep -q '\[대리 · 자율 ON' <<<"$(tail -1 "$LEDGER")"; ck "R410 ⓐ 판정 원장 «대리» 1줄" $?
n0="$(led)"; q0="$(qrows)"
mkplan "$WD/b1.sh.hil" 0000000000000000000000000000000000000000; wcd "$WD/b1.sh.hil"; okq "② STALE 계획"; ck "R410 ⓑ plan-ver 불일치 → QUEUE STALE rc2" $?
echo "  ⓑ 원문: $out"
mkplan "$WD/b2.sh.hil" "$GENB"; TM="$T/tmux-live" wcd "$WD/b2.sh.hil"; okq "④ 좌석 세션 실재"; ck "R410 ⓑ 좌석 tmux 세션 실재 → QUEUE rc2" $?
TM="$T/no-such-tmux" wcd "$WD/b2.sh.hil"; okq "④ tmux 실행 불가"; ck "R410 ⓑ tmux 실행 불가 → QUEUE(세션 0 을 확인 못 함)" $?
mkdir -p "$T/elsewhere"; mkplan "$T/elsewhere/c.sh.hil" "$GENB"; wcd "$T/elsewhere/c.sh.hil"; okq "① 계획이"; ck "R410 ⓑ 상태/wt-clean 밖 계획 → QUEUE" $?
mkplan "$WD/../wt-clean/../x.sh.hil" "$GENB"; wcd "$WD/../wt-clean/../x.sh.hil"; okq "① 계획이"; ck "R410 ⓑ .. 로 빠져나간 경로 → QUEUE" $?
sed 's/브랜치는 지우지 않는다/브랜치는 그대로/' "$WD/b2.sh.hil" > "$WD/b3.sh.hil"; wcd "$WD/b3.sh.hil"; okq "③ 계획에"; ck "R410 ⓑ «브랜치는 지우지 않는다» 없음 → QUEUE" $?
D --kind wt-clean; okq "예) ft-proxy-decide.sh --kind wt-clean --plan"; ck "R410 ⓑ --plan 없음 → QUEUE + 예시 1줄" $?
mkplan "$WD/c1.sh.hil" "$GENB" 'git -C "$ROOTD" branch -D "$br"'; wcd "$WD/c1.sh.hil"; okq "계획 본문 제외 어휘 \[브랜치 삭제\]"; ck "R410 ⓒ 실행 줄 branch -D → QUEUE" $?
mkplan "$WD/c2.sh.hil" "$GENB" 'git -C "$ROOTD" worktree remove --force "$WT"'; wcd "$WD/c2.sh.hil"; okq "계획 본문 제외 어휘 \[force-push\]"; ck "R410 ⓒ 실행 줄 --force → QUEUE" $?
[ "$(led)" = "$n0" ] && [ "$(qrows)" = "$((q0+9))" ]; ck "R410 ⓑⓒ QUEUE 9건 → 대리 줄 0 · 큐 행 +9" $?
[ ! -e "$WD/b2.sh.hil.ignored.list" ] && [ ! -e "$WD/a.sh.hil.deleting" ]; ck "R410 ⓐⓑ 계획 실행 0(도구는 판정만)" $?
python3 "$BIN/autonomy_classify.py" --kind wt-clean --text '끝난 나노 워크트리 정리' --plan-text '# 브랜치는 지우지 않는다' >/dev/null; ck "R410 주석 줄은 실행 줄 검사 밖 → PROXY" $?

# ===== R410 ⓓ 쪽지 가드 — [아침 묶음 «결정 N:» 줄마다 대리= 칸 (mbox.sh send/relay · 격리 큐) =====
SRC="$HERE/../comm"; ENV="$T/menv"; mkdir -p "$ENV/.fable-team/comm" "$ENV/.fable-team/state" "$ENV/seats"
cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$ENV/.fable-team/comm/"; echo '{}' > "$ENV/seats/seats.json"; : > "$ENV/.fable-team/comm/mailbox.log.jsonl"
bash -n "$SRC/mbox_guard.sh" && bash -n "$SRC/mbox_guard_morning.sh"; ck "R410 bash -n 가드 2 파일" $?
[ "$(wc -l < "$SRC/mbox_guard.sh")" -le 200 ]; ck "R410 mbox_guard.sh ≤ 200줄" $?
TO='byz-x-desk-claude#1'
ms() { out="$(cd "$ENV" && PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENV/seats/seats.json" FT_MBOX_DIR="$ENV/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 bash "$ENV/.fable-team/comm/mbox.sh" "$@" 2>&1)"; rc=$?; }
mq() { local n; n="$(grep -c "\"to\": *\"$TO\"" "$ENV/.fable-team/comm/mailbox.jsonl" 2>/dev/null)"; echo "${n:-0}"; }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
q0="$(mq)"; ms send "$TO" 'me#1' "$(printf '[아침 묶음·급] 결정 2건\n- 결정 1: h97 워크트리 정리 — 추천 «실행»\n- 결정 2: 시험 2회차 진행 — 대리=PROXY 2331')"
{ [ "$rc" = 3 ] && grep -q 'REJECT 아침 묶음 결정 줄에 대리 시도 칸' <<<"$out" && [ "$(mq)" = "$q0" ]; }; ck "R410 ⓓ 결정 1 에 대리= 없음 → REJECT rc3 · 큐 0" $?
echo "  ⓓ 원문: $(grep '^REJECT' <<<"$out" | head -1 | cut -c1-200)"
ms send "$TO" 'me#1' "$(printf '[아침 묶음] 결정 2건\n- 결정 1: h97 정리 — 대리=QUEUE 대리 가능 종류 아님: x\n결정 2: 시험 — 대리=PROXY 2331')"; [ "$rc" = 0 ] && [ "$(mq)" = "$((q0+1))" ]; ck "R410 ⓓ 대리=QUEUE <사유> · 대리=PROXY <번호> → 통과" $?
ms send "$TO" 'me#1' "$(printf '[아침 묶음] 결정 1건\n- 결정 1: x — 대리=PROXY')"; [ "$rc" = 3 ]; ck "R410 ⓓ 대리=PROXY 번호 없음 → REJECT" $?
ms send "$TO" 'me#1' "$(printf '[아침 묶음] 승인 1줄만\n- h102 승인')"; [ "$rc" = 0 ] && [ "$(mq)" = "$((q0+2))" ]; ck "R410 ⓓ 결정 줄 없는 아침 묶음 → 영향 0" $?
ms send "$TO" 'me#1' "$(printf '[완료·휴식] x\n- 결정 1: 머리가 아침 묶음이 아님')"; [ "$rc" = 0 ]; ck "R410 ⓓ 다른 머리의 «결정» 줄 → 검사 0" $?
printf '# 상세\n- 결정 1: h97~h99 워크트리 3개 정리 — 추천 «실행»\n' > "$T/bundle.txt"
ms relay "$TO" 'me#1' "$T/bundle.txt" '[아침 묶음·급] 결정 1건'; [ "$rc" = 3 ] && grep -q '대리 시도 칸' <<<"$out"; ck "R410 ⓓ relay 첨부의 결정 줄도 검사(실사건 #110310 꼴) → REJECT" $?
printf '# 상세\n- 결정 1: h97~h99 정리 — 대리=PROXY 2331\n' > "$T/bundle.txt"
ms relay "$TO" 'me#1' "$T/bundle.txt" '[아침 묶음·급] 결정 1건'; [ "$rc" = 0 ]; ck "R410 ⓓ relay 첨부 대리= 있음 → 통과" $?
mv "$ENV/.fable-team/comm/mbox_guard_morning.sh" "$T/mg.bak"
ms send "$TO" 'me#1' "$(printf '[아침 묶음] 승인 1줄만')"; [ "$rc" = 3 ] && grep -q '아침 묶음 가드 본체 없음' <<<"$out"; ck "R410 ⓓ 본체 파일 없음 → 아침 묶음 머리 fail-closed REJECT" $?
ms send "$TO" 'me#1' '[완료·휴식] 본체 없어도 다른 머리는 통과'; [ "$rc" = 0 ]; ck "R410 ⓓ 본체 없음 · 다른 머리 → 통과" $?
mv "$T/mg.bak" "$ENV/.fable-team/comm/mbox_guard_morning.sh"

# ===== 변이 1: 표 행 패턴을 지우면 ⓐ 가 실패해야 한다 =====
rm -rf "$T/mutbin"; cp -R "$BIN" "$T/mutbin"
python3 - "$BIN/ft-verdict-row.sh" "$T/mutbin/ft-verdict-row.sh" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
old = '|\\\\|[[:space:]]*${1}[[:space:]]*\\\\|)'   # 표 행 패턴은 공용 함수 파일(R255)로 옮겨 갔다
assert old in t, "mutation anchor missing"
open(sys.argv[2], "w", encoding="utf-8").write(t.replace(old, ')', 1))
PY
! cmp -s "$BIN/ft-verdict-row.sh" "$T/mutbin/ft-verdict-row.sh"; ck "변이 1 적용됨(표 행 패턴 제거)" $?
SB="$BIN"; cs 201; okp; ck "변이 기준: 원본은 ⓐ 표 행 PROXY" $?
SB="$T/mutbin"; cs 201; ! okp; ck "변이 1 → ⓐ 실패(검출)" $?

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
