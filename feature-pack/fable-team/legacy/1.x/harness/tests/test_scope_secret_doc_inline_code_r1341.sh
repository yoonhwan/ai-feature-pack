#!/usr/bin/env bash
# test_scope_secret_doc_inline_code_r1341.sh — r1341: 문서(.md) 줄이 «백틱이 있다» 는 이유만으로 골라졌으면
#   줄 전체가 아니라 짝 맞는 백틱 안 글(인라인 코드)만 셸 판정기에 넘긴다(표 «|»·산문 «env» 오탐 0).
#   A1 울타리·들여쓰기·«$ »/«! »/«> » 줄 = 줄 전체 · A2 백틱 때문에만 고른 줄 = 백틱 안 글만 · A3 홀수 백틱 = 줄 전체 · A4 다른 갈래 그대로
#   r1387 갱신: 산문 줄의 백틱은 아예 판정 밖 — A2(백틱 안 글만)·A3(홀수 백틱 = 줄 전체) 갈래는 걷어냄 · S3'·S6·S9 = CLASS · 변이 M1~M4 대상 코드 없음(r1387 시험 변이 1 이 대신함)
#   임시 origin(bare)+clone · 기준판 = git HEAD 판 사본($T/base) · 변이는 사본($T/mut)에서만 · 실 저장소·네트워크 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
CLS="$BIN/autonomy_scope_classify.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:200}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope"; export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"
mkf() {  # mkf <가지> <경로> <줄…> — 파일 하나 쓰고 커밋 → SHA
  local br="$1" p="$2"; shift 2
  git -C "$W" checkout -q -B "$br" "$M0"; mkdir -p "$W/$(dirname "$p")"
  printf '%s\n' "$@" > "$W/$p"; cm "$W" "$br"; SHA="$(sha "$W" HEAD)"
}
run() { out="$(python3 "$1" classify "$2" --repo "$W" --scope S1 2>&1)"; rc=$?; }
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }
same() {  # same <이름> <가지> — 새 판과 기준판 rc·출력이 같다
  run "$BASE/autonomy_scope_classify.py" "$(git -C "$W" rev-parse "$2")"; local brc="$rc" bout="$out"
  run "$CLS" "$(git -C "$W" rev-parse "$2")"
  [ "$rc" = "$brc" ] && [ "$out" = "$bout" ]; ck "$1 (기준판 rc=$brc 같음)" $?
}
MD='design/teams/ops/indices/대기/ops-x.md'
BASE="$T/base"; mkdir -p "$BASE"; cp "$BIN"/autonomy_scope_*.py "$BIN"/ft_secret_*.py "$BASE"/
# 기준판 = «고치기 전 판» 을 sha 로 고정한다(HEAD 를 쓰면 커밋 뒤 고친 판이 기준판이 돼 영원히 빨강 · r1132 꼴)
BASE_SHA=251b1f00
( cd "$HERE/.." && git show "$BASE_SHA:feature-pack/fable-team/legacy/1.x/harness/bin/autonomy_scope_secret.py" ) > "$BASE/autonomy_scope_secret.py" \
  && ck "기준판 사본 = $BASE_SHA 판(r1341 전 · sha 고정)" 0 || ck "기준판 사본" 1
python3 -I -m py_compile "$BIN/autonomy_scope_secret.py"; ck "py_compile secret" $?

# S1 — ops 6076 원문(표 산문 · 백틱 2쌍) → 고친 판 FORBID 0 · 기준판 FORBID
mkf s1 "$MD" '| ① | (시험 파일 `tests/gateway/unit/test_gpu_vm_control.py` · …) env `GCE_VM_STT_TTS` 1개(기본) → … |'
run "$BASE/autonomy_scope_classify.py" "$SHA"; want "S1 기준판 = FORBID secret(오판 재현)" 3 "FORBID kind=secret"
run "$CLS" "$SHA"; want "S1 표 산문 (env 인라인 코드) → secret 0" 0 "CLASS "
# S2 — chatbot 6054 원문(산문 · 백틱 3쌍)
mkf s2 'design/teams/chatbot/indices/대기/c-fix.md' '- 끝 칸: … ①`settings.worker_health_url`(…) 을 격리 스택 기동 절차에 명시(env `WORKER_HEALTH_URL`) 하거나 …'
run "$BASE/autonomy_scope_classify.py" "$SHA"; want "S2 기준판 = FORBID secret(오판 재현)" 3 "FORBID kind=secret"
run "$CLS" "$SHA"; want "S2 산문 (env 인라인 코드) → secret 0" 0 "CLASS "
# S3' — 백틱 안 진짜 명령 = 지금처럼 검출(회귀)
mkf s3 'design/teams/ops/indices/대기/s3.md' '실행: `env "$X" bash x.sh`'
run "$BASE/autonomy_scope_classify.py" "$SHA"; want "S3' 기준판도 검출(FORBID)" 3 "FORBID kind=secret"   # 둘 다 검출 · 이유 글자는 갈래마다 다를 수 있다
run "$CLS" "$SHA"; want "S3' 백틱 안 env 명령 → 판정 밖(r1387 · 울타리·«\$ » 줄은 판정)" 0 "CLASS "
# S4 — PR 6020 꼴 «VAR_DSN=… timeout pytest» = 둘 다 0
mkf s4 'design/teams/ops/indices/대기/s4.md' '`VAR_DSN=postgres://u:p@h/db timeout 70 pytest`'
run "$CLS" "$SHA"; want "S4 «VAR_DSN=… timeout» → secret 0" 0 "CLASS "
same "S4 기준판 대조" s4
# S5 — 울타리 안은 줄 전체(A1)
mkf s5 'design/teams/ops/indices/대기/s5.md' '```bash' 'env "$X"' '```'
run "$CLS" "$SHA"; want "S5 울타리 안 «env \"\$X\"» → secret(A1)" 3 "FORBID kind=secret"
same "S5 기준판 대조" s5
# S6 — 홀수 백틱 = 줄 전체(A3)
mkf s6 'design/teams/ops/indices/대기/s6.md' 'env `X 1개'
run "$CLS" "$SHA"; want "S6 백틱 홀수 «env \`X 1개» → 판정 밖(r1387 · A3 걷어냄)" 0 "CLASS "
# S7 — .sh 추가 줄은 문서 갈래 아님(A4)
mkf s7 'scripts/x.sh' 'env "${ENV[@]}" bash x.sh'
run "$CLS" "$SHA"; want "S7 .sh «env \"\${ENV[@]}\" bash x.sh» → secret(A4)" 3 "FORBID kind=secret"
same "S7 기준판 대조" s7
# S8 — BYZ PR 6792 원문(산문 · 백틱 4쌍) = 둘 다 0
mkf s8 'design/teams/ccu/indices/대기/ccu-worker-cap-open-measure.md' \
  '1. 코드(1곳 · v65 승인): `act_green_ready_helpers.py` 의 `_LLM_CONCURRENCY_LIMIT` 를 `parse_permits("V6_TRANSLATION_PERMITS", os.getenv(...), 12)` 로 읽는다(…)'
run "$CLS" "$SHA"; want "S8 6792 산문 → secret 0" 0 "CLASS "
same "S8 기준판 대조" s8

# S9 — 이중 백틱 구간 안 명령(DA R1): 같은 길이 run 끼리 짝 = 구간 전체를 판정 · 차례로 묶으면 안쪽 명령이 사라진다
mkf s9 'design/teams/ops/indices/대기/s9.md' '실행: ``echo `env "$X" bash x.sh` ``'
run "$CLS" "$SHA"; want "S9 이중 백틱 구간 안 «env» → 판정 밖(r1387)" 0 "CLASS "
run "$BASE/autonomy_scope_classify.py" "$SHA"; want "S9 기준판도 검출(FORBID)" 3 "FORBID kind=secret"

cmp -s "$BIN/autonomy_scope_secret.py" "$KIT/autonomy_scope_secret.py"; ck "kit 사본 cmp0" $?
[ "$(stat -f %Lp "$HERE/test_scope_secret_doc_inline_code_r1341.sh")" = 644 ]; ck "새 시험 파일 모드 644(실행 비트 0)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
