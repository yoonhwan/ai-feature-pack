#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/core/bin/tmuxc" --help >/dev/null
"$ROOT/core/bin/tmuxc" open "$ROOT" --name TMUXC_VERIFY --agent codex --role worker --dry-run | grep -q 'session=TMUXC_VERIFY'
python3 -m json.tool "$ROOT/manifest.json" >/dev/null
bash -n "$ROOT/install.sh"
bash -n "$ROOT/uninstall.sh"
test -f "$ROOT/claude-code/skills/tmuxc/SKILL.md"
test -f "$ROOT/claude-code/skills/tmuxc/COMM-GUIDE.md"

# UC11 restore: 스캐너 존재 + 비대화형 plan 모드가 실행/미실행 없이 종료
# (실호스트 세션 로그가 3.6초 창에 걸리면 flake → 빈 글롭으로 밀폐)
test -f "$ROOT/core/libexec/tmuxc-restore-scan.py"
EMPTY="$(mktemp -d)"
TMUXC_CLAUDE_GLOB="$EMPTY/none/*.jsonl" TMUXC_CODEX_GLOB="$EMPTY/none/*.jsonl" TMUXC_CODEX_INDEX="$EMPTY/none.jsonl" \
  python3 "$ROOT/core/libexec/tmuxc-restore-scan.py" --since 0.001 >/dev/null
_restore=$(TMUXC_CLAUDE_GLOB="$EMPTY/none/*.jsonl" TMUXC_CODEX_GLOB="$EMPTY/none/*.jsonl" TMUXC_CODEX_INDEX="$EMPTY/none.jsonl" \
  "$ROOT/core/bin/tmuxc" restore --since 0.001 </dev/null)
echo "$_restore" | grep -q '복구 후보 없음'
go_out="$("$ROOT/core/bin/tmuxc" restore --go </dev/null 2>&1 || true)"
printf '%s' "$go_out" | grep -q -- '--go 는 --select' || {
  echo 'restore --go without --select must be rejected'; exit 1; }

# UC11 회귀 fixture (DA 2026-07-08: corrupt-meta / 빈 cwd 필드 보존 / 혼재 동명 /
# ':' 세션명 sanitize / 무관 reader lsof 오탐)
FIX="$(mktemp -d)"
trap 'rm -rf "$EMPTY" "$FIX"' EXIT
NOW="$(python3 -c 'from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')"

mkdir -p "$FIX/claude/proj" "$FIX/codex/2026/01/01"
# claude A: 정상 + 이름에 ':' 포함 (sanitize 검증) + 빈 cwd (필드 보존 검증)
printf '{"type":"user","message":{"content":"세션명(me)=bad:name#1 시작"},"timestamp":"%s","cwd":""}\n{"type":"assistant","message":{"model":"claude-sonnet-5"},"timestamp":"%s"}\n' "$NOW" "$NOW" \
  > "$FIX/claude/proj/aaaaaaaa-0000-0000-0000-000000000001.jsonl"
# claude B: codex와 동명 (혼재 충돌 검증)
printf '{"type":"user","message":{"content":"세션명(me)=DUP#1 작업"},"timestamp":"%s","cwd":"%s"}\n{"type":"assistant","message":{"model":"claude-sonnet-5"},"timestamp":"%s"}\n' "$NOW" "$FIX" "$NOW" \
  > "$FIX/claude/proj/aaaaaaaa-0000-0000-0000-000000000002.jsonl"
# codex A: 손상 첫 줄 + 2번째 줄에 유효 session_meta (corrupt-meta 전방탐색 검증)
printf 'GARBAGE-NOT-JSON\n{"type":"session_meta","payload":{"session_id":"019f0000-0000-0000-0000-000000000001","cwd":"%s"},"timestamp":"%s"}\n{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"DUP 작업"}]},"timestamp":"%s"}\n' "$FIX" "$NOW" "$NOW" \
  > "$FIX/codex/2026/01/01/rollout-x-019f0000-0000-0000-0000-000000000001.jsonl"
printf '{"id":"019f0000-0000-0000-0000-000000000001","thread_name":"DUP#1","updated_at":"%s"}\n' "$NOW" \
  > "$FIX/codex_index.jsonl"

scan_fixture() {
  TMUXC_CLAUDE_GLOB="$FIX/claude/*/*.jsonl" \
  TMUXC_CODEX_GLOB="$FIX/codex/*/*/*/rollout-*.jsonl" \
  TMUXC_CODEX_INDEX="$FIX/codex_index.jsonl" \
  python3 "$ROOT/core/libexec/tmuxc-restore-scan.py" --since 1 "$@" 2>/dev/null
}
OUT="$(scan_fixture)"
# ':' 이름 → sanitize (bad-name#1), 빈 cwd → 필드 안 밀림 (status=no-cwd 정확 판정)
printf '%s\n' "$OUT" | awk -F$'\x1f' '$2=="bad-name#1" && $3=="" && $8=="no-cwd"' | grep -q . || {
  echo 'FIXTURE FAIL: sanitize/empty-cwd field preservation'; printf '%s\n' "$OUT"; exit 1; }
# 혼재 동명 DUP#1 → claude/codex 둘 다 존재 + tmux명 충돌 없음 (suffix 분리)
[ "$(printf '%s\n' "$OUT" | awk -F$'\x1f' '$2 ~ /^DUP#1/' | wc -l)" -eq 2 ] || {
  echo 'FIXTURE FAIL: mixed-agent same-name must yield 2 rows'; printf '%s\n' "$OUT"; exit 1; }
[ "$(printf '%s\n' "$OUT" | awk -F$'\x1f' '{print $2}' | sort | uniq -d | wc -l)" -eq 0 ] || {
  echo 'FIXTURE FAIL: duplicate tmux names in output'; printf '%s\n' "$OUT"; exit 1; }
# corrupt-meta 전방탐색: codex 세션이 살아있어야 함 (위 2행 중 codex 1행이 그 증거)
printf '%s\n' "$OUT" | awk -F$'\x1f' '$1=="codex" && $2 ~ /^DUP#1/' | grep -q . || {
  echo 'FIXTURE FAIL: corrupt first line must not drop codex session'; exit 1; }
# 무관 reader가 파일을 열어도 후보 유지 (lsof 필터는 에이전트 프로세스만 인정)
python3 - "$FIX/claude/proj/aaaaaaaa-0000-0000-0000-000000000002.jsonl" <<'PY' &
import sys, time
f = open(sys.argv[1]); time.sleep(6); f.close()
PY
READER_PID=$!
sleep 1
scan_fixture | awk -F$'\x1f' '$1=="claude" && $2 ~ /^DUP#1/' | grep -q . || {
  echo 'FIXTURE FAIL: unrelated reader must not hide candidate'; kill "$READER_PID" 2>/dev/null; exit 1; }
kill "$READER_PID" 2>/dev/null || true

# bare node reader도 무관 reader로 취급 (DA 2차 ①: node 자체는 에이전트 아님)
if command -v node >/dev/null 2>&1; then
  node -e 'const fs=require("fs");const fd=fs.openSync(process.argv[1],"r");setTimeout(()=>{fs.closeSync(fd)},6000)' \
    "$FIX/claude/proj/aaaaaaaa-0000-0000-0000-000000000002.jsonl" &
  NODE_PID=$!
  sleep 1
  scan_fixture | awk -F$'\x1f' '$1=="claude" && $2 ~ /^DUP#1/' | grep -q . || {
    echo 'FIXTURE FAIL: bare node reader must not hide candidate'; kill "$NODE_PID" 2>/dev/null; exit 1; }
  kill "$NODE_PID" 2>/dev/null || true
fi

# 3개 이상이 같은 safe_name으로 collapse해도 tmux명 전부 유일 (DA 2차 ② + 3차:
# raw name이 같으면 dedupe()가 먼저 접어버려 suffix 경로를 안 탐 — 반드시 서로 다른
# raw name(A:B#9 / A;B#9 / codex A.B#9)이 같은 safe_name(A-B#9)으로 collapse해야 함)
raw3=('A:B#9' 'A;B#9' 'A/B#9')
for i in 3 4 5; do
  printf '{"type":"user","message":{"content":"세션명(me)=%s x"},"timestamp":"%s","cwd":"%s"}\n{"type":"assistant","message":{"model":"claude-sonnet-5"},"timestamp":"%s"}\n' "${raw3[$((i-3))]}" "$NOW" "$FIX" "$NOW" \
    > "$FIX/claude/proj/aaaaaaaa-0000-0000-0000-00000000000$i.jsonl"
done
printf '{"type":"session_meta","payload":{"session_id":"019f0000-0000-0000-0000-000000000002","cwd":"%s"},"timestamp":"%s"}\n{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"x"}]},"timestamp":"%s"}\n' "$FIX" "$NOW" "$NOW" \
  > "$FIX/codex/2026/01/01/rollout-x-019f0000-0000-0000-0000-000000000002.jsonl"
printf '{"id":"019f0000-0000-0000-0000-000000000002","thread_name":"A.B#9","updated_at":"%s"}\n' "$NOW" \
  >> "$FIX/codex_index.jsonl"
OUT2="$(scan_fixture)"
# collapse 4행(claude 3 + codex 1) 전부 생존 + 전부 유일 + while 루프('-2') 경로 실증
[ "$(printf '%s\n' "$OUT2" | awk -F$'\x1f' '$2 ~ /^A-B#9/' | wc -l)" -eq 4 ] || {
  echo 'FIXTURE FAIL: 4 distinct raw names must survive as 4 rows'; printf '%s\n' "$OUT2"; exit 1; }
[ "$(printf '%s\n' "$OUT2" | awk -F$'\x1f' '$2 ~ /^A-B#9/ {print $2}' | sort -u | wc -l)" -eq 4 ] || {
  echo 'FIXTURE FAIL: 3+ collapsed names must all be unique'; printf '%s\n' "$OUT2"; exit 1; }
printf '%s\n' "$OUT2" | awk -F$'\x1f' '$2 ~ /^A-B#9.*-2$/' | grep -q . || {
  echo 'FIXTURE FAIL: same-agent 3-way collapse must reach the -2 suffix path'; printf '%s\n' "$OUT2"; exit 1; }
[ "$(printf '%s\n' "$OUT2" | awk -F$'\x1f' '{print $2}' | sort | uniq -d | wc -l)" -eq 0 ] || {
  echo 'FIXTURE FAIL: duplicate tmux names in collapse output'; printf '%s\n' "$OUT2"; exit 1; }

# 익명 codex 대화형 세션 fallback (fix/tmuxc-codex-anon-fallback, ac56819 + DA 5차 수정):
# source 필드로 헤드리스(exec)/서브에이전트(dict)를 제외하고, thread_name 없는
# cli(익명) 세션은 codex-{sid 전체}로 fallback 이름을 받아 후보에 남아야 한다
# (DA 5차: sid 앞 8자만 쓰면 prefix 충돌 시 dedupe()에서 세션이 소실되는 버그 실증 → sid 전체로 수정).
# 기존 codex fixture(위 DUP#1/A-B#9)는 source 필드가 없는 구버전 형태로,
# 이 블록 이후에도 여전히 생존해야 한다(후방호환).
printf '{"type":"session_meta","payload":{"session_id":"aaaa0010-0000-0000-0000-000000000010","cwd":"%s","source":"cli"},"timestamp":"%s"}\n{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"익명 cli 세션"}]},"timestamp":"%s"}\n' "$FIX" "$NOW" "$NOW" \
  > "$FIX/codex/2026/01/01/rollout-x-aaaa0010-0000-0000-0000-000000000010.jsonl"
printf '{"type":"session_meta","payload":{"session_id":"aaaa0011-0000-0000-0000-000000000011","cwd":"%s","source":"exec"},"timestamp":"%s"}\n{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"헤드리스 exec 세션"}]},"timestamp":"%s"}\n' "$FIX" "$NOW" "$NOW" \
  > "$FIX/codex/2026/01/01/rollout-x-aaaa0011-0000-0000-0000-000000000011.jsonl"
printf '{"type":"session_meta","payload":{"session_id":"aaaa0012-0000-0000-0000-000000000012","cwd":"%s","source":{"type":"subagent","id":"z"}},"timestamp":"%s"}\n{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"서브에이전트 세션"}]},"timestamp":"%s"}\n' "$FIX" "$NOW" "$NOW" \
  > "$FIX/codex/2026/01/01/rollout-x-aaaa0012-0000-0000-0000-000000000012.jsonl"
# ⑤ sid 앞 8자 충돌: 서로 다른 두 익명 세션이 같은 prefix(bbbb0020)를 공유 — 둘 다 생존해야 함
printf '{"type":"session_meta","payload":{"session_id":"bbbb0020-1111-0000-0000-000000000020","cwd":"%s","source":"cli"},"timestamp":"%s"}\n{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"충돌 세션 A"}]},"timestamp":"%s"}\n' "$FIX" "$NOW" "$NOW" \
  > "$FIX/codex/2026/01/01/rollout-x-bbbb0020-1111-0000-0000-000000000020.jsonl"
printf '{"type":"session_meta","payload":{"session_id":"bbbb0020-2222-0000-0000-000000000021","cwd":"%s","source":"cli"},"timestamp":"%s"}\n{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"충돌 세션 B"}]},"timestamp":"%s"}\n' "$FIX" "$NOW" "$NOW" \
  > "$FIX/codex/2026/01/01/rollout-x-bbbb0020-2222-0000-0000-000000000021.jsonl"
# ⑥ source:"unknown" (exec도 dict도 아닌 미지 문자열) — fail-safe로 후보에 남아야 함(계약 명시)
printf '{"type":"session_meta","payload":{"session_id":"cccc0030-0000-0000-0000-000000000030","cwd":"%s","source":"unknown"},"timestamp":"%s"}\n{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"미지 source 세션"}]},"timestamp":"%s"}\n' "$FIX" "$NOW" "$NOW" \
  > "$FIX/codex/2026/01/01/rollout-x-cccc0030-0000-0000-0000-000000000030.jsonl"
OUT3="$(scan_fixture)"
# ① thread_name 없는 cli 세션 → codex-{sid 전체} fallback 이름으로 생존
printf '%s\n' "$OUT3" | awk -F$'\x1f' '$1=="codex" && $2=="codex-aaaa0010-0000-0000-0000-000000000010"' | grep -q . || {
  echo 'FIXTURE FAIL: anonymous cli session must get codex-{sid} fallback name'; printf '%s\n' "$OUT3"; exit 1; }
# ② source:"exec" (헤드리스) → 후보에서 완전 제외
printf '%s\n' "$OUT3" | awk -F$'\x1f' '$6 ~ /^aaaa0011/' | grep -q . && {
  echo 'FIXTURE FAIL: source=exec session must be excluded'; printf '%s\n' "$OUT3"; exit 1; }
# ③ source가 dict(서브에이전트 스폰) → 후보에서 완전 제외
printf '%s\n' "$OUT3" | awk -F$'\x1f' '$6 ~ /^aaaa0012/' | grep -q . && {
  echo 'FIXTURE FAIL: source=dict (subagent) session must be excluded'; printf '%s\n' "$OUT3"; exit 1; }
# 후방호환: source 필드 없는 구버전 codex fixture(DUP#1, A-B#9)가 여전히 생존
printf '%s\n' "$OUT3" | awk -F$'\x1f' '$1=="codex" && $2 ~ /^DUP#1/' | grep -q . || {
  echo 'FIXTURE FAIL: legacy codex fixture without source field must still survive'; printf '%s\n' "$OUT3"; exit 1; }
# ⑤ sid8 충돌 두 세션 모두 생존(고유 이름) — DA 5차 회귀 방지
printf '%s\n' "$OUT3" | awk -F$'\x1f' '$1=="codex" && $6=="bbbb0020-1111-0000-0000-000000000020"' | grep -q . || {
  echo 'FIXTURE FAIL: sid8-collision session A must survive'; printf '%s\n' "$OUT3"; exit 1; }
printf '%s\n' "$OUT3" | awk -F$'\x1f' '$1=="codex" && $6=="bbbb0020-2222-0000-0000-000000000021"' | grep -q . || {
  echo 'FIXTURE FAIL: sid8-collision session B must survive (was dropped by dedupe before fix)'; printf '%s\n' "$OUT3"; exit 1; }
# ⑥ source:"unknown" → fail-safe로 생존해야 함(exec/dict만 명시 제외 계약)
printf '%s\n' "$OUT3" | awk -F$'\x1f' '$1=="codex" && $6=="cccc0030-0000-0000-0000-000000000030"' | grep -q . || {
  echo 'FIXTURE FAIL: source=unknown session must survive (only exec/dict are excluded by contract)'; printf '%s\n' "$OUT3"; exit 1; }

echo "tmuxc verify OK"
