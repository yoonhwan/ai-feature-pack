#!/usr/bin/env bash
# test_sheet_verify.sh — ft-sheet-verify.sh (S3 r-sheet-verify-session · PLAN-status-sheet r4 §5).
# 실 LLM·실 좌석 쪽지 0: 스텁 claude(FT_SHEET_VERIFY_CMD) + 가짜 mbox(tests/scripts/_fake_mbox.sh) + 임시 FT_ROOT.
# FT_SHEET_VERIFY_REAL=1 일 때만 실제 launch 인자 1회(7초+1) — 기본 suite 밖.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
V="$ROOT/harness/bin/ft-sheet-verify.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FT="$T/ft"; ST="$FT/.fable-team/state"; S="$T/stub"; MB="$T/mb"
mkdir -p "$ST" "$S" "$MB"
printf '{"_label":"통역 팀","_master":"byz-v6-master-claude#4"}\n' > "$FT/.fable-team/seats-v6.json"
printf '{"_label":"issues","_master":"byz-issues-master-claude#2"}\n' > "$FT/.fable-team/seats-issues.json"
printf '{"ts":"2026-10-13T07:00:00","ev":"done","key":"k1","seat":"x","id":"a"}\n' > "$ST/sheet-events.jsonl"

# 스텁 board — render --sheet --rev → 발행 rev(파일 rev) · render --sheet → 시트 md(파일 sheet.md)
cat > "$S/fake-board" <<'EOF'
#!/usr/bin/env bash
D="$(dirname "$0")"
[ "$1 $2" = "render --sheet" ] || exit 2
if [ "${3:-}" = "--rev" ]; then printf '{"structure":"s","publish":"%s"}' "$(cat "$D/rev")"; else cat "$D/sheet.md"; fi
EOF
# 스텁 claude — stdin 을 stdin.last 에 남기고 호출 횟수 +1 · mode: ok(고정 JSON) | slow8(8초 지연) | refuse(도구 거절 출력)
cat > "$S/claude" <<'EOF'
#!/usr/bin/env bash
D="$(dirname "$0")"; cat > "$D/stdin.last"; echo x >> "$D/calls"
case "$(cat "$D/mode")" in
  ok)   cat "$D/out.json" ;;
  slow1) sleep 1; cat "$D/out.json" ;;
  slow8) sleep 8; cat "$D/out.json" ;;
esac
EOF
chmod +x "$S/fake-board" "$S/claude"
cat > "$S/out.json" <<'EOF'
{"unconfirmed":["③ 통역 팀","⑤ issues","⑦ 없는칸"],"term_candidates":[{"id":"sheet-events#k1","field":"ev","wrong":"새 slug foo","suggest":"치환표에 foo 추가"},{"id":"sheet-events#nokey","field":"ev","wrong":"무효","suggest":"무효"}],"question_lint":[]}
EOF
cat > "$S/sheet.md" <<'EOF'
확인 중 0 · 소유자 미확인 2칸
## 자세히
### 칸별 소유자 미확인 · 확인된 칸
- ③ 통역 팀: 소유자 미확인(통역 팀 master · [정지 레디]/[완료] 0)
- ③ 결제 팀: 완료 10:00
- ⑤ issues: 소유자 미확인(issues · 라벨 사건 0 · 캐시 10:00)
EOF
echo r1 > "$S/rev"; echo ok > "$S/mode"
export FT_ROOT="$FT" FT_BOARD_BIN="$S/fake-board" FT_SHEET_VERIFY_CMD="$S/claude" FT_MBOX="$ROOT/tests/scripts/_fake_mbox.sh" FAKE_MBOX="$MB/x" FT_SHEET_VERIFY_NOW="2026-10-13T09:30:00"
LED="$ST/sheet-verify-sent.jsonl"; NOTES="$ST/sheet-notes.md"; HEAD="$ST/sheet-verify-head.txt"
run() { bash "$V" >"$T/out.txt" 2>"$T/err.txt"; echo $?; }
calls() { wc -l < "$S/calls" 2>/dev/null | tr -d ' ' || echo 0; }
rows() { wc -l < "$1" 2>/dev/null | tr -d ' ' || echo 0; }
: > "$S/calls"

bash -n "$V" 2>/dev/null && ok "bash -n" || bad "bash -n (스크립트 없음/문법)"

# 1) 고정 JSON → 소유자 쪽지 2통(템플릿 바이트 일치 · 없는 칸 무시) + 메모 1줄(lint 통과분만) + ③ 머리 1줄
snap_before="$(cd "$FT" && find . -type f | sort | xargs md5 -r 2>/dev/null)"
rc="$(run)"
B1='[요청] ③ 통역 팀 사실 0 — [정지 레디]·[완료] 머리 쪽지(mbox.sh send) 으로 남겨 주세요'
B2='[요청] ⑤ issues 사실 0 — ft-gh-as-tank.sh label --apply 으로 남겨 주세요'
python3 - "$MB/x" "$B1" "$B2" <<'PY' && m_ok=1 || m_ok=0
import json, sys, os
rows = [json.loads(l) for l in open(os.path.join(os.path.dirname(sys.argv[1]), "mailbox.jsonl"))]
exp = [("byz-v6-master-claude#4", sys.argv[2]), ("byz-issues-master-claude#2", sys.argv[3])]
sys.exit(0 if [(r["to"], r["body"]) for r in rows] == exp and all(r["from"] == "byz-planner-pm-sheet" for r in rows) else 1)
PY
[ "$rc" = 0 ] && [ "$m_ok" = 1 ] && ok "고정 JSON → 소유자 쪽지 2통(템플릿 바이트 일치 · 없는 칸 무시)" || bad "쪽지 rc=$rc m_ok=$m_ok $(cat "$T/err.txt")"
[ "$(cat "$NOTES" 2>/dev/null)" = 'sheet-events#k1.ev | 새 slug foo | 치환표에 foo 추가' ] && ok "메모 «미적용» 1줄(원장 id 실재분만 · 무효 id 거절)" || bad "메모: $(cat "$NOTES" 2>/dev/null)"
[ "$(cat "$HEAD" 2>/dev/null)" = '검증 09:30 · 미확인 2 · 메모 1 · 요청 2' ] && ok "③ 칸 머리 1줄" || bad "머리: $(cat "$HEAD" 2>/dev/null)"
[ "$(rows "$LED")" = 3 ] && ok "발송 원장 3행(쪽지 2 + 실행 표식 1)" || bad "원장 행수 $(rows "$LED")"

# 2) 래퍼가 쓴 파일 = sheet-notes.md · sheet-verify-sent.jsonl · 머리 파일 뿐(그 밖 경로 변경 0)
snap_after="$(cd "$FT" && find . -type f | sort | xargs md5 -r 2>/dev/null)"
changed="$(diff <(echo "$snap_before") <(echo "$snap_after") | grep '^[<>]' | awk '{print $3}' | sort -u | tr '\n' ' ')"
[ "$changed" = "./.fable-team/state/sheet-notes.md ./.fable-team/state/sheet-verify-head.txt ./.fable-team/state/sheet-verify-sent.jsonl " ] && ok "쓴 파일 = 메모·원장·머리 3개뿐(원장·seats 쓰기 0)" || bad "변경 파일: $changed"

# 3) 같은 발행 rev 2회 → LLM·쪽지 0
c0="$(calls)"; rc="$(run)"
[ "$rc" = 0 ] && [ "$(calls)" = "$c0" ] && [ "$(rows "$MB/mailbox.jsonl")" = 2 ] && ok "같은 rev 2회 → 1회만(LLM·쪽지 0)" || bad "같은 rev rc=$rc calls=$(calls)"

# 4) 새 rev · 같은 칸 같은 날 → LLM 1회 더 · 쪽지 0(같은 칸 하루 1회)
echo r2 > "$S/rev"; c0="$(calls)"; rc="$(run)"
[ "$rc" = 0 ] && [ "$(calls)" = $((c0+1)) ] && [ "$(rows "$MB/mailbox.jsonl")" = 2 ] && [ "$(cat "$HEAD")" = '검증 09:30 · 미확인 2 · 메모 0 · 요청 0' ] && ok "같은 칸 2회 → 쪽지 1회만(새 rev 도 같은 칸 하루 1회 · 메모 중복 0)" || bad "같은 칸 rc=$rc head=$(cat "$HEAD")"

# 5) 동시 호출 2 → 1개만 실행
echo r3 > "$S/rev"; echo slow1 > "$S/mode"; c0="$(calls)"
( bash "$V" >"$T/a.out" 2>&1 & bash "$V" >"$T/b.out" 2>&1 & wait )
[ "$(calls)" = $((c0+1)) ] && ok "동시 호출 2 → 1개만 실행" || bad "동시 호출 calls=$(( $(calls) - c0 ))"
echo ok > "$S/mode"

# 6) 스텁 8초 → 7초 중단 → 재시도 1 → 실패 줄 + skip(폴백 0 · 쪽지 0)
echo r4 > "$S/rev"; echo slow8 > "$S/mode"; c0="$(calls)"; t0=$(date +%s)
rc="$(run)"; el=$(( $(date +%s) - t0 ))
[ "$rc" = 0 ] && [ "$(calls)" = $((c0+2)) ] && [ "$el" -ge 13 ] && [ "$el" -le 17 ] && grep -q '검증 실패(timeout)' "$T/err.txt" && grep -q '검증 실패(timeout)' "$HEAD" && [ "$(rows "$MB/mailbox.jsonl")" = 2 ] \
  && ok "8초 지연 → 7초 중단 → 재시도 1(${el}s) → 실패 줄 + skip" || bad "timeout rc=$rc el=$el calls=$(( $(calls) - c0 )) err=$(cat "$T/err.txt")"
echo ok > "$S/mode"

# 7) 일일 상한 — 오늘 행 24 → 25회째 skip(LLM 0)
: > "$LED"; for i in $(seq 24); do printf '{"rev":"old%s","cell":"-","seat":"-","ts":"2026-10-13T08:%02d:00"}\n' "$i" "$i" >> "$LED"; done
echo r5 > "$S/rev"; c0="$(calls)"; rc="$(run)"
[ "$rc" = 0 ] && [ "$(calls)" = "$c0" ] && grep -q '상한' "$T/err.txt" && ok "상한 25회째 → skip(LLM 0 · 로그 1줄)" || bad "상한 rc=$rc calls=$(( $(calls) - c0 ))"

# 7b) ⓘ 상한 env 상향 금지(DA⑥ H2) — 오늘 원장 24행 + FT_SHEET_VERIFY_LIMIT=25 → 여전히 skip·LLM 0·원장 24행 유지
echo r6 > "$S/rev"; c0="$(calls)"; rc="$(FT_SHEET_VERIFY_LIMIT=25 run)"
[ "$rc" = 0 ] && [ "$(calls)" = "$c0" ] && [ "$(rows "$LED")" = 24 ] && ok "ⓘ LIMIT=25 → 24 로 고정(skip · LLM 0 · 원장 24행 유지)" || bad "ⓘ rc=$rc calls=$(( $(calls) - c0 )) rows=$(rows "$LED")"

# 7c) ⓗ 시간 env 상향 금지(DA⑥ H1) — 8초 스텁 + FT_SHEET_VERIFY_TIMEOUT=9 → 7초 고정 → timeout 실패 경로(재시도 1 · 로그 1줄)
: > "$LED"; echo r7 > "$S/rev"; echo slow8 > "$S/mode"; c0="$(calls)"; t0=$(date +%s)
rc="$(FT_SHEET_VERIFY_TIMEOUT=9 run)"; el=$(( $(date +%s) - t0 ))
[ "$rc" = 0 ] && [ "$(calls)" = $((c0+2)) ] && [ "$el" -ge 13 ] && [ "$el" -le 17 ] && grep -q '검증 실패(timeout)' "$T/err.txt" && grep -q '상한 7 고정' "$T/err.txt" \
  && ok "ⓗ TIMEOUT=9 → 7 로 고정(8초 스텁 timeout · 재시도 1 · 「상한 7 고정」 로그)" || bad "ⓗ rc=$rc el=$el calls=$(( $(calls) - c0 )) err=$(cat "$T/err.txt")"
echo ok > "$S/mode"

# 7d) ⓙ env 형식 검사(DA⑥ 2차) — 양의 정수만 받고 그 밖(8.5·0·07·abc·빈값)은 기본값 → 8초 스텁은 전부 7초 중단 + 재시도 1 + 실패 줄
echo slow8 > "$S/mode"; n=8
for v in 8.5 0 07 abc ""; do
  : > "$LED"; n=$((n+1)); echo "r$n" > "$S/rev"; c0="$(calls)"; t0=$(date +%s)
  rc="$(FT_SHEET_VERIFY_TIMEOUT=$v run)"; el=$(( $(date +%s) - t0 ))
  [ "$rc" = 0 ] && [ "$(calls)" = $((c0+2)) ] && [ "$el" -ge 13 ] && [ "$el" -le 17 ] && grep -q '검증 실패(timeout)' "$T/err.txt" \
    && ok "ⓙ TIMEOUT='$v' → 7 로(8초 스텁 timeout · 재시도 1 · ${el}s)" || bad "ⓙ TIMEOUT='$v' rc=$rc el=$el calls=$(( $(calls) - c0 )) err=$(cat "$T/err.txt")"
done
echo ok > "$S/mode"
for v in 0 abc 8.5 ""; do  # LIMIT 형식 오류 → 24 : 빈 원장이면 실행(0 으로 읽혀 전부 skip 되면 안 된다) · 24행이면 skip
  : > "$LED"; n=$((n+1)); echo "r$n" > "$S/rev"; c0="$(calls)"; rc="$(FT_SHEET_VERIFY_LIMIT=$v run)"; ran=$(( $(calls) - c0 ))
  for i in $(seq 24); do printf '{"rev":"old%s","cell":"-","seat":"-","ts":"2026-10-13T08:%02d:00"}\n' "$i" "$i" >> "$LED"; done
  echo "r$((n+100))" > "$S/rev"; c1="$(calls)"; FT_SHEET_VERIFY_LIMIT=$v run >/dev/null; skipped=$(( $(calls) - c1 ))
  [ "$rc" = 0 ] && [ "$ran" = 1 ] && [ "$skipped" = 0 ] && ok "ⓙ LIMIT='$v' → 24(빈 원장 실행 · 24행 skip)" || bad "ⓙ LIMIT='$v' ran=$ran skipped=$skipped"
done

# 8) 7초 룰 — 새 스크립트에 600/300 초 값 0
! grep -nE '\b(600|300)\b' "$V" 2>/dev/null | grep -v '^[0-9]*:#' | grep -q . && ok "새 스크립트에 600/300 초 값 0" || bad "600/300 잔존"

# 9) publish 연결 — --sheet 발행 rc 0 ∧ FT_SHEET_VERIFY=1 일 때만 검증 1회 · 검증 실패는 발행 rc 를 바꾸지 않는다
PB="$T/pub"; mkdir -p "$PB"; cp "$ROOT/harness/bin/ft-board-publish.sh" "$PB/"; : > "$PB/tp.py"
printf '#!/usr/bin/env bash\nexit "$(cat "$(dirname "$0")/pub_rc")"\n' > "$PB/ft-sheet-publish.sh"
printf '#!/usr/bin/env bash\necho x >> "$(dirname "$0")/vcalls"\nexit "$(cat "$(dirname "$0")/v_rc" 2>/dev/null || echo 0)"\n' > "$PB/ft-sheet-verify.sh"
pub() { echo "$1" > "$PB/pub_rc"; : > "$PB/vcalls"; env FT_THREAD_POST="$PB/tp.py" FT_ROOT="$FT" ${2:+FT_SHEET_VERIFY=$2} bash "$PB/ft-board-publish.sh" --sheet >/dev/null 2>&1; echo "$? $(wc -l < "$PB/vcalls" | tr -d ' ')"; }
[ "$(pub 0 1)" = "0 1" ] && [ "$(pub 0)" = "0 0" ] && [ "$(pub 3 1)" = "3 0" ] && echo 5 > "$PB/v_rc" && [ "$(pub 0 1)" = "0 1" ] \
  && ok "publish --sheet: 성공 ∧ FT_SHEET_VERIFY=1 → 검증 1회 · env 없음/발행 rc≠0 → 0회 · 검증 rc=5 여도 발행 rc 0" || bad "publish 연결: $(pub 0 1) $(pub 0) $(pub 3 1)"

# 10) N1 seats-lint ⓒ — `_headless` 행은 세션이 없어도 불일치가 아니다(없으면 ⓒ — 변이 대조)
LD="$T/lint"; mkdir -p "$LD"; LINT="$ROOT/harness/bin/ft-seats-lint.sh"
printf '{"_label":"planner","_master":"m#1","m#1":{"role":"master"},"byz-planner-pm-sheet":{"role":"pm","tick":null,"_headless":true}}\n' > "$LD/seats-planner.json"
lint() { FT_ROOT="$LD" FT_SEATS_GLOB="$LD/seats*.json" FT_TMUX_LS_CMD="echo m#1" bash "$LINT"; }
lint >"$T/l1.txt" 2>&1; r1=$?
sed -i '' 's/,"_headless":true//' "$LD/seats-planner.json"; lint >"$T/l2.txt" 2>&1; r2=$?
# H3(DA⑥): 문자열 "false" 는 bool true 가 아니다 — truthy 로 ⓒ 를 면제하지 않는다
printf '{"_label":"planner","_master":"m#1","m#1":{"role":"master"},"byz-planner-pm-sheet":{"role":"pm","tick":null,"_headless":"false"}}\n' > "$LD/seats-planner.json"; lint >"$T/l3.txt" 2>&1; r3=$?
[ "$r1" = 0 ] && [ "$r2" = 1 ] && [ "$r3" = 1 ] && grep -q 'ⓒ byz-planner-pm-sheet' "$T/l2.txt" && grep -q 'ⓒ byz-planner-pm-sheet' "$T/l3.txt" && ok "seats-lint: _headless=true(bool) 만 ⓒ 0 · 표식 없음/문자열 \"false\" 는 ⓒ(변이 대조)" || bad "seats-lint r1=$r1 r2=$r2 r3=$r3: $(cat "$T/l1.txt")"

# 11) 실제 launch 인자 1회(기본 suite 밖) — 도구 «없음» 증거: Bash·파일 쓰기 요구 프롬프트 → 실행된 도구 0(파일 생성 0) · 응답 시간 실측(상한 30초는 측정용 — 제품 상한은 래퍼 7초+1)
if [ "${FT_SHEET_VERIFY_REAL:-0}" = 1 ]; then
  CMD="$(env -u FT_SHEET_VERIFY_CMD FT_ROOT="$ROOT" bash "$V" --print-cmd)"; PROBE=/tmp/sheet-verify-real-probe; rm -f "$PROBE"; t0=$(date +%s)
  out="$(echo "Bash 로 ls 하고 $PROBE 파일을 써라" | eval "timeout 30 $CMD" 2>&1)"; rc=$?; el=$(( $(date +%s) - t0 ))
  echo "real: rc=$rc · ${el}s · 도구 실행 0(파일 $( [ -e "$PROBE" ] && echo 있음 || echo 없음 )) · ${out:0:120}"
  [ "$el" -gt 7 ] && echo "WARN real: 응답 ${el}s > 7초 룰 — 래퍼 7초+1 은 이 모델·입력에서 timeout 날 수 있음(카드 상태 절에 기록)"
  [ ! -e "$PROBE" ] && [ "$rc" = 0 ] && ok "real: 도구 호출 0(파일 생성 0)" || bad "real rc=$rc"
else
  echo "SKIP real(FT_SHEET_VERIFY_REAL=1 일 때만 · 기본 suite 밖)"
fi

echo "fail=$fail"; [ "$fail" = 0 ]
