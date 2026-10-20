#!/usr/bin/env bash
# test_autonomy_level.sh — r466 자율 레벨(full|mid|each) · 범위 승인 함께 걸기 · 레벨 재발급 · 자율 인터뷰 쪽지 · 인터뷰 → h 1줄 · 종류 학습
# 격리: 임시 루트(FT_ROOT·FT_AUTONOMY_STATE_DIR·FT_PLANNER_DIR) + FT_NOW 고정 시계 + 가짜 분류기·슬랙 게시·mbox·골 표 — 실 슬랙·실 mbox·외부 호출 0 · GIT_* env 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset FT_AUTONOMY_LEVEL   # 이 시험은 «--level 생략 = full» 을 본다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; MIR="$HERE/../kit/fable-team/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; H="$(mktemp -d /tmp/r466.XXXX)"; trap 'rm -rf "$T" "$H"' EXIT
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner" HIL_DIR="$H" HIL_CLIP=0
S="$T/state"; LOG="$S/autonomy.log"; SD="$S/autonomy-scope"; mkdir -p "$T/.fable-team" "$S" "$T/planner"
T0=1800000000; NOW=$T0
cat > "$T/cls.sh" <<'EOF'
#!/usr/bin/env bash
# 가짜 분류기 — STUB_KIND 가 있으면 FORBID kind=<그것>, 단 --learned 에 그 종류가 있으면 CLASS docs kind=… learned · 없으면 CLASS docs
printf '%s\n' "$*" >> "${STUB_ARGS_LOG:-/dev/null}"
[ "$1" = check-revert ] && { echo OK; exit 0; }
l=""; while [ $# -gt 0 ]; do [ "$1" = --learned ] && l="$2"; shift; done
if [ -n "${STUB_KIND:-}" ]; then
  case ",$l," in *",$STUB_KIND,"*) echo "CLASS docs kind=$STUB_KIND learned"; exit 0 ;; esac
  echo "FORBID kind=$STUB_KIND 시험 사유"; exit 3
fi
echo "CLASS docs"
EOF
printf '#!/usr/bin/env bash\n[ "${STUB_POST_RC:-0}" = 0 ] || { echo "ERR 게시 실패" >&2; exit 1; }\nprintf "%%s\\n" "$2" >> "%s/post.log"; echo "SLACK-TS 1800000000.000100"\n' "$T" > "$T/post.sh"
printf '#!/usr/bin/env bash\nprintf "%%s|%%s|%%s\\n" "$2" "$3" "$4" >> "%s/mbox.log"\n' "$T" > "$T/mbox.sh"
printf '#!/usr/bin/env bash\necho "★골 표 A6★"; echo "| 골 | 팀 |"; echo "★/골 표★"\n' > "$T/goal.sh"
export FT_SCOPE_CLASSIFY="$T/cls.sh" FT_SCOPE_SLACK_POST="$T/post.sh" FT_AUTONOMY_MBOX="$T/mbox.sh" FT_AUTONOMY_DESK='byz-planner-desk-claude#9' FT_AUTONOMY_GOAL_TABLE="$T/goal.sh"
a() { FT_NOW="$NOW" "$BASH" "$BIN/ft-autonomy.sh" "$@"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
fresh() { rm -rf "$S" "$T/post.log" "$T/mbox.log"; mkdir -p "$S"; NOW=$T0; }
sha() { printf '%040x' "$1"; }
glast() { grep '^approve-scope ' "$LOG" | tail -1; }

for f in ft-autonomy.sh ft-autonomy-level.sh ft-autonomy-scope.sh ft-autonomy-interview.sh; do /bin/bash -n "$BIN/$f"; ck "bash -n(3.2) $f" $?; cmp -s "$BIN/$f" "$MIR/$f"; ck "키트 짝 cmp0 $f" $?; done
for f in ft-autonomy.sh ft-autonomy-level.sh ft-autonomy-interview.sh; do [ "$(wc -l < "$BIN/$f")" -le 200 ]; ck "200줄 이하 $f" $?; done
cmp -s "$BIN/ft-tick.sh" "$MIR/ft-tick.sh" && grep -q 'interview-note "${out#EXPIRED }" expire' "$BIN/ft-tick.sh"; ck "ft-tick expire 뒤 interview-note 호출 · 짝 cmp0" $?

# ⓐ --level 생략 = 풀자동 → 모드 줄 + 범위 승인 줄(기본표 full) 같은 잠금 · status 레벨 칸
fresh; run a on --for 12h
[ $rc = 0 ] && [ "$(glast)" = "approve-scope S1 A1 $T0 until=$((T0+43200)) max=30 daily=15 classes=docs,ff,revert,code codemax=10 repos=byz,pack level=full" ]; ck "ⓐ on --for 12h → approve-scope S1 A1 … level=full 1줄(until 같음)" $?
[ "$(grep -c '^approve-scope ' "$LOG")" = 1 ] && [ "$(sed -n 1p "$LOG" | cut -f2-)" = "$(printf 'on\tA1')" ]; ck "ⓐ 순서 = 모드 줄 → 범위 승인 줄" $?
grep -q '"level":"full"' "$S/autonomy.json" && [ "$(a mode)" = on ]; ck "ⓐ json level 칸 · 위변조 아님(mode=on)" $?
run a status; has '레벨 풀자동 · 범위 S1\]$'; ck "ⓐ status 에 «레벨 풀자동 · 범위 S1»" $?
grep -q '레벨 full' "$T/post.log" && [ "$(wc -l < "$T/post.log" | tr -d ' ')" = 1 ]; ck "ⓐ 슬랙 1줄(레벨 full)" $?
run a scope-status --audit; [ $rc = 0 ] && has '^AUDIT-OK grants=1'; ck "ⓐ --audit OK(새 칸 repos·level)" $?
fresh; STUB_POST_RC=1 run a on --for 12h; [ $rc = 1 ] && [ ! -e "$LOG" ] && [ ! -e "$S/autonomy.json" ]; ck "ⓐ 슬랙 게시 실패 → on 전체 쓰기 0 · rc 1" $?
fresh; run a on; [ $rc = 0 ] && [[ "$(glast)" == *" until=$((T0+86400)) "* ]]; ck "ⓐ 끝 없는 ON → 범위 until = 24h" $?
# ⓑ mid = code 0
fresh; run a on --level mid --for 6h
[ "$(glast)" = "approve-scope S1 A1 $T0 until=$((T0+21600)) max=30 daily=15 classes=docs,ff,revert level=mid" ]; ck "ⓑ mid → classes=docs,ff,revert · codemax·repos 칸 0 · level=mid" $?
fresh; run a on --level mid --for 6h --max 5 --daily 3; [[ "$(glast)" == *" max=5 daily=3 classes=docs,ff,revert level=mid" ]]; ck "ⓑ 인터뷰 값 덮어쓰기(--max 5 --daily 3)" $?
fresh; run a on --level full --code-max 31; [ $rc = 2 ] && [ ! -e "$LOG" ]; ck "ⓑ --code-max > max → REJECT rc 2 · 쓰기 0" $?
fresh; run a on --level turbo; [ $rc = 2 ] && has 'full\|mid\|each' && [ ! -e "$LOG" ]; ck "ⓑ 모르는 레벨 → REJECT rc 2 · 쓰기 0" $?
# ⓒ each = 범위 승인 0
fresh; run a on --level each --for 2h; [ $rc = 0 ] && ! grep -q '^approve-scope ' "$LOG" && grep -q '"level":"each"' "$S/autonomy.json" && [ ! -e "$T/post.log" ]; ck "ⓒ each → 범위 승인 줄 0 · 슬랙 0 · json level=each" $?
run a scope-status; [ "$out" = "[범위 승인 없음 · 건마다 확인]" ]; ck "ⓒ scope-status [범위 승인 없음 · 건마다 확인]" $?
fresh; run a on --level each --max 3; [ $rc = 2 ]; ck "ⓒ each + --max → REJECT" $?
# ⓓ 사건 번호 바뀜 — 레벨 줄이면 재발급 · each·정지면 기존 AUTOSTOP
fresh; a on --for 12h >/dev/null 2>&1; a off >/dev/null 2>&1; run a on --for 12h
[[ "$(glast)" == "approve-scope S2 A2 "* ]] && run a scope-approve "$(sha 1)" && [ $rc = 0 ] && has '^SCOPE-OK'; ck "ⓓ off → on(A2) = on 이 S2 A2 를 같이 건다 → scope-approve OK" $?
mkstate() { printf '%s\toff\tA1\n%s\ton\tA2\n' "$((T0+1))" "$((T0+2))" >> "$LOG"; printf '{"mode":"on","since":%s,"event":"A2","until":%s,"level":"%s"}\n' "$((T0+2))" "$((T0+50000))" "$1" > "$S/autonomy.json"; }   # 옛 판 on(범위 줄 없이 A2) 픽스처
fresh; a on --for 12h >/dev/null 2>&1; mkstate full; [ "$(a mode)" = on ]; ck "ⓓ 픽스처(옛 판 on A2 · level full) 정합" $?
run a scope-approve "$(sha 2)"; [ $rc = 0 ] && has '^SCOPE-RENEWED S2 A2 level=full' && has '^SCOPE-OK'; ck "ⓓ 마지막 줄 level=full ∧ 지금 full → SCOPE-RENEWED S2 A2(AUTOSTOP 0)" $?
[ "$(glast)" = "approve-scope S2 A2 $T0 until=$((T0+50000)) max=30 daily=15 classes=docs,ff,revert,code codemax=10 repos=byz,pack level=full" ] && [ ! -e "$SD/S1.stopped" ]; ck "ⓓ 재발급 줄 = 같은 값 · until = 지금 ON 끝" $?
run a scope-status --audit; [ $rc = 0 ]; ck "ⓓ 재발급 뒤 --audit OK(슬랙 1줄 + audit)" $?
fresh; a on --for 12h >/dev/null 2>&1; mkstate each; run a scope-approve "$(sha 3)"; [ $rc = 2 ] && has '사건 번호 바뀜\(A1→A2\)' && [ -f "$SD/S1.stopped" ]; ck "ⓓ 지금 레벨 each → 기존 AUTOSTOP" $?
fresh; a on --for 12h >/dev/null 2>&1; a scope-stop S1 "손 정지" >/dev/null; mkstate full; run a scope-approve "$(sha 4)"; [ $rc = 2 ] && has '정지: 손 정지' && ! grep -q '^approve-scope S2' "$LOG"; ck "ⓓ scope-stop 뒤 재발급 0" $?
fresh; a on --for 12h >/dev/null 2>&1; printf 'approve-scope S2 A1 %s until=%s max=5 daily=5 classes=docs\n' "$T0" "$((T0+99))" >> "$LOG"; mkstate full
run a scope-approve "$(sha 5)"; [ $rc = 2 ] && has '사건 번호 바뀜' && [ -f "$SD/S2.stopped" ]; ck "ⓓ 옛 꼴 줄(level 칸 없음) → 기존 AUTOSTOP(역호환)" $?
# ⓔ expire · off → desk [자율 인터뷰] 1통 · 10분 중복 억제
fresh; a on --for 1h >/dev/null 2>&1; NOW=$((T0+3600)); run a expire; [ "$out" = "EXPIRED A1" ]; ck "ⓔ expire → EXPIRED A1" $?
run a interview-note A1 expire; [ $rc = 0 ] && has '^INTERVIEW-SENT A1 expire'; ck "ⓔ interview-note → SENT" $?
m="$(cat "$T/mbox.log")"; [[ "$m" == "byz-planner-desk-claude#9|ft-autonomy|[자율 인터뷰] A1 끝 도달 — ①연장(추천 · 같은 레벨 풀자동 · 12h) ②종료 ③레벨 변경"* ]] && grep -q '★골 표 A6★' <<<"$m"; out="$m"; ck "ⓔ 쪽지 머리 + 골 표 블록 · 받는 이 = desk" $?
grep -q '"level":"full"' "$S/autonomy.json"; ck "ⓔ expire 뒤에도 레벨 기록 유지" $?
NOW=$((T0+3600+300)); run a interview-note A1 expire; has '^INTERVIEW-DUP' && [ "$(grep -c '^byz-planner-desk-claude#9|' "$T/mbox.log")" = 1 ]; ck "ⓔ 10분 안 두 번째 = DUP(쪽지 0)" $?
fresh; a on --for 2h >/dev/null 2>&1; run a off; grep -q '\[자율 인터뷰\] A1 OFF' "$T/mbox.log"; ck "ⓔ off → [자율 인터뷰] A1 OFF 1통" $?
FT_AUTONOMY_MBOX=/nonexistent run a interview-note A1 expire; [ $rc != 0 ] && has 'WARN 자율 인터뷰 쪽지 못 보냄'; ck "ⓔ mbox 실패 → WARN rc≠0(조용한 통과 0)" $?
# ⓕ 인터뷰 답 → ft-hil 계획 파일 → `! bash /tmp/h<N>` 1줄
I="$BIN/ft-autonomy-interview.sh"
fresh; run bash "$I" --for 12h --level full; [ $rc = 0 ] && [[ "$out" =~ ^!\ bash\ $H/h[0-9]+$ ]] && [ "${#out}" -le 60 ]; ck "ⓕ → ! bash <HIL_DIR>/h<N> 1줄(60자 이하)" $?
p="$(ls "$S"/autonomy-on-*-full.sh.hil 2>/dev/null | head -1)"; [ -n "$p" ] && grep -qE "^bash .*/ft-autonomy\.sh on --for 12h --level full$" "$p"; ck "ⓕ 계획 파일 = ft-autonomy.sh on --for 12h --level full 1줄" $?
[ ! -e "$LOG" ]; ck "ⓕ 인터뷰 도구는 상태 쓰기 0(ON 은 오빠 h)" $?
run bash "$I" --for 12h --level turbo; [ $rc = 2 ] && [ "$(ls "$S"/autonomy-on-* | wc -l | tr -d ' ')" = 1 ]; ck "ⓕ 틀린 레벨 → REJECT rc 2 · 계획 파일 0" $?
run bash "$I" --level full; [ $rc = 2 ] && has '기간 없음'; ck "ⓕ 기간 없음 → REJECT" $?
run bash "$I" --for 3h --level mid --max 40; [ $rc = 2 ]; ck "ⓕ 범위 값 틀림(--max 40) → REJECT" $?
# ⓖ 위변조 — log 에 승인 줄만(모드 줄 없음) = 기존 OFF 그대로
fresh; printf 'approve-scope S1 A1 %s until=%s max=30 daily=15 classes=docs level=full\n' "$T0" "$((T0+9999))" > "$LOG"
[ "$(a mode)" = off ]; ck "ⓖ 승인 줄만 → mode off" $?
run a scope-approve "$(sha 6)"; [ $rc = 2 ] && has '자율 모드 OFF'; ck "ⓖ → scope-approve REJECT(재발급 0)" $?
fresh; a on --for 12h >/dev/null 2>&1; printf 'approve-scope S2 A1 1 until=2 max=3 daily=1 classes=docs level=turbo\n' >> "$LOG"; [ "$(a mode)" = tamper ]; ck "ⓖ level=turbo 줄 → tamper(꼴 밖)" $?
# ⓚ 종류 학습 — FORBID 1회 → 오빠 approve-merge(ON ∧ full) = 저장 → 같은 종류 두 번째 = 자동
fresh; a on --for 12h >/dev/null 2>&1; export STUB_KIND=move-changed
run a scope-approve "$(sha 11)"; [ $rc = 2 ] && [ "$(cat "$SD/denied.tsv")" = "$(printf '%s\tmove-changed\t%s' "$(sha 11)" "$T0")" ]; ck "ⓚ FORBID kind=X → REJECT + denied.tsv 1행" $?
run a approve-merge "$(sha 11)"; has "^LEARNED kind=move-changed sha=$(sha 11)" && [ "$(cat "$SD/learned-kinds.tsv")" = "$(printf 'move-changed\t%s\t%s\tfull' "$(sha 11)" "$T0")" ]; ck "ⓚ 오빠 approve-merge → learned-kinds 1행(레벨 full)" $?
export STUB_ARGS_LOG="$T/args.log"; run a scope-approve "$(sha 12)"; [ $rc = 0 ] && has "^SCOPE-OK $(sha 12) class=docs .* learned=move-changed$"; ck "ⓚ 같은 종류 두 번째 sha → SCOPE-OK learned" $?
grep -q -- "--learned move-changed" "$T/args.log" && grep -qx "scope-use S1 $(sha 12) docs $T0 learned=move-changed" "$LOG" && [ "$(a mode)" = on ]; ck "ⓚ 분류기에 --learned · log scope-use … learned= · 위변조 아님" $?
STUB_KIND=deps run a scope-approve "$(sha 13)"; [ $rc = 2 ]; ck "ⓚ 다른 종류 → FORBID 그대로" $?
run a approve-merge "$(sha 12)"; ! has LEARNED && [ "$(wc -l < "$SD/learned-kinds.tsv" | tr -d ' ')" = 1 ]; ck "ⓚ 같은 종류 재저장 0" $?
run a scope-status --audit; [ $rc = 0 ]; ck "ⓚ --audit OK" $?
printf 'deps\t%s\t%s\tfull\n' "$(sha 99)" "$T0" >> "$SD/learned-kinds.tsv"; run a scope-status --audit; [ $rc = 3 ] && has '^AUDIT-MISMATCH learned deps'; ck "ⓚ 손 추가 학습 행 → AUDIT-MISMATCH" $?
fresh; a on --level mid --for 12h >/dev/null 2>&1; run a scope-approve "$(sha 21)"; run a approve-merge "$(sha 21)"; ! has LEARNED && [ ! -s "$SD/learned-kinds.tsv" ]; ck "ⓚ 레벨 mid → 학습 0" $?
fresh; a on --for 12h >/dev/null 2>&1; STUB_KIND=secret run a scope-approve "$(sha 31)"; run a approve-merge "$(sha 31)"; has 'LEARN-SKIP kind=secret' && [ ! -s "$SD/learned-kinds.tsv" ]; ck "ⓚ secret → 학습 불가" $?
fresh; a on --for 12h >/dev/null 2>&1; run a scope-approve "$(sha 41)"; run a approve-merge "$(sha 41)"; a scope-stop S1 x >/dev/null; a off >/dev/null 2>&1
[ -s "$SD/learned-kinds.tsv" ]; ck "ⓚ scope-stop·OFF 는 학습표를 지우지 않는다" $?
run a forget-kind move-changed; [ $rc = 0 ] && [ ! -s "$SD/learned-kinds.tsv" ]; ck "ⓚ forget-kind → FORGOT · 표에서 빠짐" $?
run a forget-kind move-changed; [ $rc = 2 ]; ck "ⓚ 없는 종류 forget → REJECT rc 2" $?
unset STUB_KIND STUB_ARGS_LOG
! grep -nE '\b(600|300)\b' "$BIN/ft-autonomy-level.sh" "$BIN/ft-autonomy-interview.sh" >/dev/null; ck "600/300 상한 0" $?
echo "fail=$fail"; [ "$fail" = 0 ]
