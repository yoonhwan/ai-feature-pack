#!/usr/bin/env bash
# test_scope_speed_r1815.sh — r1815: 승인 대조 여러 후보 한 프로세스(A1·A2) · scope_equiv_sha 1회(A3) · log 판독 1회(A4) · 판정 바이트 그대로(A5).
#   ① 후보 30 · EQUIV = 30번째 → 30번째 A · git 프로세스 ≤ 5 + 4×30(PATH 앞 git 대역 셈)  ①′ EQUIV 뒤 후보가 남는 입력 → 첫 EQUIV 에서 멈춤(M2)
#   ② 후보 30 · EQUIV 0 → rc1 · 줄 30 · 줄마다 = 단건 출력 바이트  ③ partial clone · 없는 sha → ERROR 그대로 · 다음 후보 계속 · GIT_TRACE fetch 0(M3)
#   ④ 단건 꼴 바이트 그대로  ⑤ log 6,000줄+(정상·부가 9종·doc-exempt-reject 포함) → mode·event = 기준 판독기(옛 bash 줄 판독) · scope-approve 의 log 판독 1회(M4·M5)
#   ⑤′ 끝 모르는 줄 → tamper  ⑤″ 빈 log · 경계(모르는 줄 뒤 새 모드 줄 · 끝 개행 없음 · 모드 뒤 빈 줄)  ⑥ scope-approve 전 경로 후보 30 → SCOPE-OK·원장·log 바이트
# 격리: 임시 리포·임시 상태·고정 시계(FT_NOW)·가짜 분류기·슬랙 — 실 장부·원장·log·라이브 bin 0 · sleep 0 · 변이·기준판 = FT_TEST_BIN=<bin 폴더>.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_NO_LAZY_FETCH GIT_TRACE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_TEST_BIN:-$HERE/../bin}"
fail=0; rc=0; out=""; t_start=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/fake_gh_base.sh"; fake_gh_base "$T/ghb"   # r1955: --pr 의 base 조회(autonomy_pr_target) = 가짜 gh(main)
RG="$(command -v git)"; mkdir -p "$T/shim"
printf '#!/bin/sh\necho x >> "%s/gitcount"\nexec "%s" "$@"\n' "$T" "$RG" > "$T/shim/git"; chmod +x "$T/shim/git"

# ===== 임시 리포: main B0→L1..L15→M1 · feat(L15 위) A · S = A + main 병합 · U1..U16 = B0 위 남남 커밋 =====
W="$T/w"; git -c init.defaultBranch=main init -q "$W"
g() { git -C "$W" -c user.email=t@t -c user.name=t "$@"; }
put() { printf '%s\n' "$2" > "$W/$1"; g add "$1"; g commit -qm "$1"; g rev-parse HEAD; }
B0="$(put base.txt base)"; L=(); for i in $(seq 1 15); do L+=("$(put "l$i.txt" "l$i")"); done
g checkout -qb feat; AQ="$(put own.txt own1)"; g checkout -q main; M1="$(put m1.txt m1)"; g update-ref refs/remotes/origin/main "$M1"
S="$(g checkout -q -B s "$AQ" && g merge -q --no-edit main && g rev-parse HEAD)"
U=(); for i in $(seq 1 16); do g checkout -q -B "u$i" "$B0"; U+=("$(put "u$i.txt" "u$i")"); done
NE=(); for i in $(seq 0 14); do NE+=("${L[$i]}"); [ "$i" -lt 14 ] && NE+=("${U[$i]}"); done   # EQUIV 아닌 후보 29개(L 15 · U 14 섞음)
EQ() { out="$("$BASH" "$BIN/ft-approval-equiv.sh" "$@" 2>&1)"; rc=$?; }
t1=$SECONDS

# ① 후보 30 · EQUIV 30번째 · git 프로세스 수
printf '%s\n' "${NE[@]}" "$AQ" > "$T/c1"; : > "$T/gitcount"
out="$(PATH="$T/shim:$PATH" "$BASH" "$BIN/ft-approval-equiv.sh" "$S" --candidates "$T/c1" --repo "$W" 2>&1)"; rc=$?
n="$(wc -l < "$T/gitcount" | tr -d ' ')"
[ "$rc" = 0 ] && [ "$(wc -l <<<"$out" | tr -d ' ')" = 30 ] && [ "$(tail -1 <<<"$out")" = "$AQ EQUIV approve=$AQ head=$S merges=1 files=1 mode=merge overlap=0 base=${M1:0:10}" ]
ck "① 후보 30 → 30번째 A EQUIV 줄 · rc0 · 줄 30" $?
[ "$rc" = 0 ] && [ "${n:-999}" -le 125 ]; ck "① git 프로세스 수 ≤ 5+4×30=125 (받은 값: ${n:-없음})" $?
# ①′ EQUIV 뒤 후보가 남는 입력 → 첫 EQUIV 에서 멈춤
EQ "$S" --candidates - --repo "$W" < <(printf '%s\n' "${NE[@]:0:5}" "$AQ" "${U[@]:0:5}")
[ "$rc" = 0 ] && [ "$(wc -l <<<"$out" | tr -d ' ')" = 6 ] && [[ "$(tail -1 <<<"$out")" == "$AQ EQUIV "* ]]; ck "①′ 첫 EQUIV(6번째)에서 멈춤 · 줄 6 · 뒤 후보 5 판정 0" $?
EQ "$S" --candidates - --repo "$W" <<<"nothex"; [ "$rc" = 2 ]; ck "①″ 후보 입력 오류 → rc2" $?
t2=$SECONDS

# ② EQUIV 0 · 줄마다 단건 바이트
C2=("${L[@]}" "${U[@]:0:15}"); printf '%s\n' "${C2[@]}" > "$T/c2"
EQ "$S" --candidates "$T/c2" --repo "$W"; many="$out"; mrc=$rc
exp=""; for a in "${C2[@]}"; do EQ "$a" "$S" --repo "$W"; exp+="$a $out"$'\n'; done
rc=$mrc; out="$many"; [ "$mrc" = 1 ] && [ "$(wc -l <<<"$many" | tr -d ' ')" = 30 ] && [ "$many"$'\n' = "$exp" ]; ck "② EQUIV 0 → rc1 · 줄 30 · 줄마다 = 단건 출력 바이트" $?
t3=$SECONDS

# ③ partial clone · 없는 sha 섞임 → ERROR 그대로 · 다음 후보 계속 · 원격 호출 0
OR="$T/remote.git"; git init -q --bare -b main "$OR"; git -C "$OR" config uploadpack.allowFilter true
g push -q "file://$OR" main s 2>/dev/null; C3="$T/c3"; git clone -q --no-checkout --filter=blob:none "file://$OR" "$C3" 2>/dev/null
MISS="0123456789abcdef0123456789abcdef01234567"
EQ "$B0" "$S" --repo "$C3"; one="$out"
out="$(GIT_TRACE="$T/trace3" "$BASH" "$BIN/ft-approval-equiv.sh" "$S" --candidates - --repo "$C3" < <(printf '%s\n' "$MISS" "$B0") 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ "$out" = "$MISS ERROR 승인 sha ${MISS:0:10} 객체가 이 저장소에 없음(네트워크 0 — 대조 불가·재승인)"$'\n'"$B0 $one" ]; ck "③ 없는 sha → ERROR 문구 그대로 · 다음 후보 계속(단건 바이트)" $?
n="$(grep -cE 'upload-pack|git fetch|built-in: git fetch|run_command: .*fetch' "$T/trace3" 2>/dev/null)"; [ "${n:-x}" = 0 ]; ck "③ GIT_TRACE upload-pack·fetch 0 (받은 값: ${n:-없음})" $?
t4=$SECONDS

# ④ 단건 꼴 바이트 그대로
EQ "$AQ" "$S" --repo "$W"; [ "$rc" = 0 ] && [ "$out" = "EQUIV approve=$AQ head=$S merges=1 files=1 mode=merge overlap=0 base=${M1:0:10}" ]; ck "④ 단건 EQUIV 바이트 그대로" $?
EQ "${U[0]}" "$S" --repo "$W"; [ "$rc" = 1 ] && [ "$out" = "NOT-EQUIV rebase 한 자기 변경이 승인 때와 다름(main 대비 diff 불일치: own.txt, u1.txt)" ]; ck "④ 단건 NOT-EQUIV 바이트 그대로" $?
t5=$SECONDS

# ===== ⑤ log 판독 =====
SB="$T/h/bin"; mkdir -p "$T/h"; cp -R "$BIN" "$SB"; cp -R "$HERE/../kit/fable-team/templates" "$T/h/templates"
printf '#!/usr/bin/env bash\n[ "$1" = check-revert ] && { echo OK; exit 0; }\necho "CLASS docs"\n' > "$T/cls.sh"
printf '#!/usr/bin/env bash\necho "SLACK-TS 1800000000.000100"\n' > "$T/post.sh"; : > "$T/tbl.tsv"
export FT_ROOT="$W" FT_PLANNER_DIR="$T/planner" FT_AUTONOMY_GOAL_TABLE=0 FT_SCOPE_CLASSIFY="$T/cls.sh" FT_SCOPE_SLACK_POST="$T/post.sh" FT_SCOPE_PACK_TABLE="$T/tbl.tsv" FT_SCOPE_DDL_RECORDS="$T/tbl.tsv"
mkdir -p "$T/planner"; T0=1800000000
a() { FT_AUTONOMY_STATE_DIR="$ST" FT_NOW="$T0" "$BASH" "$SB/ft-autonomy.sh" "$@"; }
# 기준 판독기 = 고치기 전 bash 줄 판독(정규식은 시험 대상 bin 에서 그대로 읽는다)
eval "$(grep -E '^(MODE_RE|SCOPE_GRANT_RE|SCOPE_USE_RE|STANDING_GRANT_RE)=' "$SB/ft-autonomy.sh")"
oracle() { local line last="" bad=0
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ $MODE_RE ]]; then last="$line"; bad=0
    elif [[ "$line" =~ $APPROVE_RE || "$line" =~ $SCOPE_GRANT_RE || "$line" =~ $SCOPE_USE_RE || "$line" =~ $SCOPE_STOP_RE || "$line" =~ $DOC_EXEMPT_RE || "$line" =~ $DOC_EXEMPT_REJ_RE || "$line" =~ $STANDING_GRANT_RE || "$line" =~ $STANDING_USE_RE || "$line" =~ $STANDING_STOP_RE ]]; then :
    else bad=1; fi
  done 2>/dev/null < "$1"; printf '%s' "$last"; return $bad; }
h40() { printf '%040x' "$1"; }
pad() { awk -v n="$1" -v t="$T0" 'BEGIN { for (i = 1; i <= n; i++) { h = sprintf("%040x", i); k = i % 10; e = t - 5000   # 정상 부가 9종 + 모드 줄
  if (k == 0) printf "%d\ton\tA1\n", t - 9000 + i; else if (k == 1) print "approve-merge " h " A1 " e
  else if (k == 2) print "approve-scope S0 A1 " e " until=" (e + 1000) " max=5 daily=5 classes=docs"; else if (k == 3) print "scope-use S0 " h " docs " e
  else if (k == 4) print "scope-stop S0 " e " 사유 " i; else if (k == 5) print "doc-exempt " h " team=harness files=2 by=nano#1"; else if (k == 6) print "doc-exempt-reject " h " by=nano#1"
  else if (k == 7) print "approve-standing D2 " e " repos=byz classes=docs oppa_decision=1800000000.000100"; else if (k == 8) print "standing-use D2 " h " " e " pr=7 repo=byz da=" h
  else print "standing-stop D2 " e " 사유" } }'; }
expect_mode() {  # <log> → 기준 판독기 결과 + json(마지막 모드 줄 그대로)로 기대 mode·event
  local last bad; last="$(oracle "$1")"; bad=$?
  [ -n "$last" ] && [ "$bad" = 0 ] && XM="$(cut -f2 <<<"$last")" || XM=tamper; XE="$(cut -f3 <<<"$last")"; }
mkjson() { local l; l="$(oracle "$ST/autonomy.log" | tail -1)"; printf '{"mode":"%s","since":%s,"event":"%s","until":null}\n' "$(cut -f2 <<<"$l")" "$(cut -f1 <<<"$l")" "$(cut -f3 <<<"$l")" > "$ST/autonomy.json"; }
judge() {  # <이름> — mode·event 출력 = 기대값
  expect_mode "$ST/autonomy.log"; out="$(a mode)/$(a event)"; rc=$?; [ "$out" = "$XM/$XE" ]; ck "$1 mode/event = 기준 판독기($XM/$XE)" $?; }
ST="$T/st5"; mkdir -p "$ST"; pad 6000 > "$ST/autonomy.log"
a on --for 12h >/dev/null 2>&1; grep -q "^approve-scope S601 A601 $T0 " "$ST/autonomy.log"; ck "⑤ 픽스처: log 6,000줄 위 자율 ON A601 · 범위 S601" $?
pad 9 | grep -v '^approve-scope ' >> "$ST/autonomy.log"   # 마지막 모드 줄 «뒤» 정상 부가 줄(doc-exempt-reject 포함 · DA 메모: M5 검출)
judge "⑤ 6,000줄 + 마지막 모드 줄 뒤 부가 8종(doc-exempt-reject 포함)"
X5="$(h40 777777)"; FT_AUTONOMY_STATE_DIR="$ST" FT_NOW="$T0" "$BASH" -x "$SB/ft-autonomy.sh" scope-approve "$X5" > "$T/o5" 2> "$T/x5"; rc=$?; out="$(cat "$T/o5")"
[ "$rc" = 0 ] && grep -q "^SCOPE-OK $X5 class=docs used=1/" "$T/o5"; ck "⑤ scope-approve SCOPE-OK" $?
n="$(grep -cE '^\++ log_last_mode$' "$T/x5")"; [ "$n" = 1 ]; ck "⑤ scope-approve 1회의 log 판독 = 1회 (받은 값: $n)" $?
echo "garbage line" >> "$ST/autonomy.log"; judge "⑤′ 끝 모르는 줄 → 위변조"
printf '%s\toff\tA601\n' "$T0" >> "$ST/autonomy.log"; mkjson; judge "⑤″ 모르는 줄 뒤 새 모드 줄 → 정상"
printf '%s\ton\tA602' "$T0" >> "$ST/autonomy.log"; mkjson; judge "⑤″ 끝 개행 없는 모드 줄"
printf '\n\n' >> "$ST/autonomy.log"; judge "⑤″ 모드 뒤 빈 줄 → 위변조"
: > "$ST/autonomy.log"; judge "⑤″ 빈 log(json 있음)"
rm -f "$ST/autonomy.json"; out="$(a mode)/$(a event)"; [ "$out" = "off/" ]; ck "⑤″ 빈 log · json 없음 → off/" $?
t6=$SECONDS

# ===== ⑥ scope-approve 전 경로 · 원장 후보 30(EQUIV = 맨 끝 = 가장 오래된 줄) =====
ST="$T/st6"; mkdir -p "$ST/autonomy-scope"; a on --for 12h >/dev/null 2>&1
{ printf '%s\t%s\t\tdocs\t\t\t\n' 1 "$AQ"; i=2; for x in "${NE[@]}"; do printf '%s\t%s\t\tdocs\t\t\t\n' "$i" "$x"; i=$((i+1)); done; } > "$ST/autonomy-scope/S1.ledger.tsv"
out="$(a scope-approve "$S" --pr 9 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" =~ ^SCOPE-OK\ $S\ class=equiv\ used=0/[0-9]+\ today=0/[0-9]+\ equiv=$AQ$ ]]; ck "⑥ SCOPE-OK class=equiv · 셈 0 · equiv=<맨 끝 A>" $?
[ "$(tail -2 "$ST/autonomy.log")" = "scope-use S1 $S equiv $T0"$'\n'"approve-merge $S A1 $T0" ]; ck "⑥ log 줄 바이트(scope-use equiv · approve-merge)" $?
[ "$(tail -1 "$ST/autonomy-scope/S1.ledger.tsv")" = "$T0"$'\t'"$S"$'\t'9$'\t'equiv$'\t'"equiv=$AQ"$'\t\t' ]; ck "⑥ 원장 줄 바이트" $?
[ "$(cat "$ST/autonomy-merge-approved/$S")" = "approve-merge $S A1 $T0" ]; ck "⑥ 승인 파일 바이트" $?
t7=$SECONDS

kc=0; for f in ft_approval_equiv.py ft-approval-equiv.sh ft-autonomy-scope.sh ft-autonomy.sh; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f" || kc=1; done
[ "$kc" = 0 ] || [ -n "${FT_TEST_BIN:-}" ]; ck "정본 미러 cmp0(bin ↔ kit 4파일)" $?
echo "단계별 초: 픽스처 $((t1 - t_start)) · ① $((t2 - t1)) · ② $((t3 - t2)) · ③ $((t4 - t3)) · ④ $((t5 - t4)) · ⑤ $((t6 - t5)) · ⑥ $((t7 - t6)) · 전체 $((SECONDS - t_start))"
echo "fail=$fail"; [ "$fail" = 0 ]
