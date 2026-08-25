#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/core/bin/tmuxc" --help >/dev/null
"$ROOT/core/bin/tmuxc" open "$ROOT" --name TMUXC_VERIFY --agent codex --role worker --dry-run | grep -q 'session=TMUXC_VERIFY'

# tmuxc는 호출자나 기존 tmux 서버의 NO_COLOR를 세션 기본값으로 상속하지 않는다.
# 격리 소켓에서 신규 서버와 기존 서버를 각각 실제 기동해 pane 환경까지 확인한다.
COLOR_NEW="$(mktemp -d)"
COLOR_EXISTING="$(mktemp -d)"
cleanup_color_tmux() {
  env -u TMUX TMUX_TMPDIR="$COLOR_NEW" tmux kill-server 2>/dev/null || true
  env -u TMUX TMUX_TMPDIR="$COLOR_EXISTING" tmux kill-server 2>/dev/null || true
  rm -rf "$COLOR_NEW" "$COLOR_EXISTING"
}
trap cleanup_color_tmux EXIT
run_color_spawn() {
  env -u TMUX NO_COLOR=1 TMUX_TMPDIR="$1" bash -c '
    eval "$(sed -n "/^prepare_color_environment()/,/^}/p; /^create_tmux_session()/,/^}/p" "$1")"
    create_tmux_session "$2" "$3"
  ' _ "$ROOT/core/bin/tmuxc" "$2" "$ROOT"
}
assert_no_color() {
  local socket_dir="$1" session="$2" pane_env try
  env -u TMUX TMUX_TMPDIR="$socket_dir" tmux show-environment -g NO_COLOR 2>/dev/null | grep -q '^NO_COLOR=' && {
    echo "FAIL: tmux global NO_COLOR survived for $session"; exit 1;
  }
  pane_env="$socket_dir/$session.env"
  env -u TMUX TMUX_TMPDIR="$socket_dir" tmux send-keys -t "$session" -l "env > '$pane_env'"
  env -u TMUX TMUX_TMPDIR="$socket_dir" tmux send-keys -t "$session" Enter
  for try in 1 2 3 4 5; do
    [ -s "$pane_env" ] && break
    sleep 0.2
  done
  [ -s "$pane_env" ] || {
    echo "FAIL: pane environment capture timed out for $session"; exit 1;
  }
  grep -q '^NO_COLOR=' "$pane_env" && {
    echo "FAIL: pane inherited NO_COLOR for $session"; exit 1;
  }
  return 0
}

run_color_spawn "$COLOR_NEW" TMUXC_COLOR_NEW
assert_no_color "$COLOR_NEW" TMUXC_COLOR_NEW

env -u TMUX NO_COLOR=1 TMUX_TMPDIR="$COLOR_EXISTING" tmux new-session -d -s TMUXC_COLOR_SENTINEL -c "$ROOT"
env -u TMUX TMUX_TMPDIR="$COLOR_EXISTING" tmux show-environment -g NO_COLOR | grep -q '^NO_COLOR=1$' || {
  echo 'FAIL: existing-server fixture did not seed NO_COLOR=1'; exit 1;
}
run_color_spawn "$COLOR_EXISTING" TMUXC_COLOR_EXISTING
env -u TMUX TMUX_TMPDIR="$COLOR_EXISTING" tmux has-session -t TMUXC_COLOR_SENTINEL || {
  echo 'FAIL: color preparation destroyed the existing sentinel session'; exit 1;
}
assert_no_color "$COLOR_EXISTING" TMUXC_COLOR_EXISTING

python3 - "$ROOT/core/bin/tmuxc" <<'PY'
import sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
calls = [i for i, line in enumerate(lines) if line.strip().startswith('create_tmux_session "')]
if len(calls) != 2:
    raise SystemExit(f"FAIL: expected open and restore to share 2 guarded spawn calls, found {len(calls)}")
raw_spawns = [i for i, line in enumerate(lines) if line.strip().startswith("tmux new-session ")]
if len(raw_spawns) != 1:
    raise SystemExit(f"FAIL: unguarded tmux spawn path found; expected 1 centralized spawn, found {len(raw_spawns)}")
PY
cleanup_color_tmux
trap - EXIT

# --model/--effort 오버라이드: alias 우회 + headroom 직접 합성 + [1m] 대괄호 인용 보존
# (증류 시 1m/effort 유실 회귀 방지 — task #8). dry-run은 zshrc/파일 존재에 비의존(밀폐).
_ov="$("$ROOT/core/bin/tmuxc" open "$ROOT" --name TMUXC_OVR --agent claude --role worker \
  --model 'claude-sonnet-5[1m]' --effort high --dry-run)"
printf '%s\n' "$_ov" | grep -q 'session=TMUXC_OVR' || { echo 'FAIL: --model dry-run session'; exit 1; }
printf '%s\n' "$_ov" | grep -qF -- '--model "claude-sonnet-5[1m]"' || {
  echo 'FAIL: --model [1m] bracket not preserved in dry-run'; printf '%s\n' "$_ov"; exit 1; }
printf '%s\n' "$_ov" | grep -q -- '--effort high' || { echo 'FAIL: --effort not applied'; exit 1; }
printf '%s\n' "$_ov" | grep -q 'claude-hr.sh --dangerously-skip-permissions --model' || {
  echo 'FAIL: --model override must synthesize headroom launch (alias bypass)'; printf '%s\n' "$_ov"; exit 1; }
# codex 는 --model 을 받는다 (2026-08-24 핫패치) — 세션 한정 `-c model="ID"` 오버라이드로 합성.
# 전역 config.toml 은 건드리지 않는다.
_ovc="$("$ROOT/core/bin/tmuxc" open "$ROOT" --name TMUXC_OVR2 --agent codex --role worker \
  --model 'openai/gpt-5.5' --dry-run 2>&1 || true)"
printf '%s\n' "$_ovc" | grep -qF -- '-c model="openai/gpt-5.5"' || {
  echo 'FAIL: codex --model must synthesize -c model= override'; printf '%s\n' "$_ovc"; exit 1; }
# omx 는 role→effort 고정이라 --model 미지원 — 거부해야 한다(침묵 무시 금지)
_ovx="$("$ROOT/core/bin/tmuxc" open "$ROOT" --name TMUXC_OVR3 --agent omx --role worker --model x --dry-run 2>&1 || true)"
printf '%s\n' "$_ovx" | grep -q '에서만 사용' || {
  echo 'FAIL: --model with omx must be rejected'; printf '%s\n' "$_ovx"; exit 1; }
# model 서브커맨드: 미기동 세션 조회는 실패로 종료(침묵 성공 금지)
if "$ROOT/core/bin/tmuxc" model TMUXC_NO_SUCH_SESSION_XYZ >/dev/null 2>&1; then
  echo 'FAIL: model subcommand must fail for non-live session'; exit 1
fi

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
# ★ TMUXC_SNAPSHOT_DIR 도 반드시 격리한다 — restore 는 스냅샷이 있으면 그쪽을 자동 채택하므로,
# 격리하지 않으면 실사용 ~/.tmuxc/snapshots/latest.json 을 집어 «로그 스캔» 경로를 안 탄다
# (2026-08-25: 이 누락으로 밀폐가 깨져 테스트가 실호스트 스냅샷에 의존했다).
NOSNAP="$EMPTY/nosnap"
_restore=$(TMUXC_CLAUDE_GLOB="$EMPTY/none/*.jsonl" TMUXC_CODEX_GLOB="$EMPTY/none/*.jsonl" TMUXC_CODEX_INDEX="$EMPTY/none.jsonl" \
  TMUXC_SNAPSHOT_DIR="$NOSNAP" "$ROOT/core/bin/tmuxc" restore --since 0.001 </dev/null)
echo "$_restore" | grep -q '복구 후보 없음'
go_out="$(TMUXC_SNAPSHOT_DIR="$NOSNAP" "$ROOT/core/bin/tmuxc" restore --go </dev/null 2>&1 || true)"
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

# ⑦ codex 익명 세션 역할명 추론 + AGENTS.md 노이즈 요약 제거
# thread_name 없어도 mbox/화살표/me= 에서 역할명을 뽑아 UUID 대신 쓴다.
printf '{"type":"session_meta","payload":{"session_id":"dddd0040-0000-0000-0000-000000000040","cwd":"%s","source":"cli"},"timestamp":"%s"}\n{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions <INSTRUCTIONS> noise"}]},"timestamp":"%s"}\n{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"[V6_HELM#28→V6_POLISH_ORCH#0] tmuxc Codex 세션. 통신 표준"}]},"timestamp":"%s"}\n{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"bash %s/.fable-team/comm/mbox.sh recv V6_POLISH_ORCH#0"}]},"timestamp":"%s"}\n' \
  "$FIX" "$NOW" "$NOW" "$NOW" "$FIX" "$NOW" \
  > "$FIX/codex/2026/01/01/rollout-x-dddd0040-0000-0000-0000-000000000040.jsonl"
# ⑧ alias 없는 모델 → status=synth (복구 가능). claude-opus-5는 MODEL_ALIAS 미매핑.
printf '{"type":"user","message":{"content":"세션명(me)=synth-role#1 시작"},"timestamp":"%s","cwd":"%s"}\n{"type":"assistant","message":{"model":"claude-opus-5"},"timestamp":"%s"}\n' \
  "$NOW" "$FIX" "$NOW" \
  > "$FIX/claude/proj/aaaaaaaa-0000-0000-0000-0000000000aa.jsonl"
OUT4="$(scan_fixture)"
printf '%s\n' "$OUT4" | awk -F$'\x1f' '$1=="codex" && $2=="V6_POLISH_ORCH#0" && $6=="dddd0040-0000-0000-0000-000000000040"' | grep -q . || {
  echo 'FIXTURE FAIL: anonymous codex must infer role name from mbox/arrow'; printf '%s\n' "$OUT4"; exit 1; }
printf '%s\n' "$OUT4" | awk -F$'\x1f' '$1=="codex" && $6=="dddd0040-0000-0000-0000-000000000040" && $9 ~ /AGENTS\.md/' | grep -q . && {
  echo 'FIXTURE FAIL: summary must not lead with AGENTS.md noise'; printf '%s\n' "$OUT4"; exit 1; }
printf '%s\n' "$OUT4" | awk -F$'\x1f' '$1=="codex" && $6=="dddd0040-0000-0000-0000-000000000040" && $9 ~ /mbox recv V6_POLISH_ORCH#0/' | grep -q . || {
  echo 'FIXTURE FAIL: summary should surface mbox recv work hint'; printf '%s\n' "$OUT4"; exit 1; }
printf '%s\n' "$OUT4" | awk -F$'\x1f' '$1=="claude" && $2=="synth-role#1" && $8=="synth"' | grep -q . || {
  echo 'FIXTURE FAIL: unmapped model must be status=synth (restorable)'; printf '%s\n' "$OUT4"; exit 1; }

# ⑨ 복원 결과 리포트 헬퍼 — 세션명/번호/이전 대화 요약 출력 계약
_rep=$(bash -c '
  source /dev/null
  eval "$(sed -n "/^restore_summary_clip()/,/^}/p; /^restore_record()/,/^}/p; /^restore_print_final_report()/,/^}/p" "'"$ROOT"'/core/bin/tmuxc")"
  RESTORE_REP_IDX=() RESTORE_REP_NAME=() RESTORE_REP_AGENT=()
  RESTORE_REP_PROJ=() RESTORE_REP_OUTCOME=() RESTORE_REP_SUMMARY=()
  restore_record 14 LOOM_DOMAIN#0 claude loom-domain-hierarchy ok "[LOOM_PACK#0→LOOM_DOMAIN#0] … ⇢ 아키텍처 크론/임베딩"
  restore_record 16 ft-loomdomain-da#0 codex loom-domain-hierarchy ok "mbox recv ft-loomdomain-da#0"
  restore_print_final_report
')
printf '%s\n' "$_rep" | grep -q '복원 결과 2개' || { echo 'FIXTURE FAIL: final report header'; printf '%s\n' "$_rep"; exit 1; }
printf '%s\n' "$_rep" | grep -q 'LOOM_DOMAIN#0' || { echo 'FIXTURE FAIL: final report session name'; printf '%s\n' "$_rep"; exit 1; }
printf '%s\n' "$_rep" | grep -q '#14' || { echo 'FIXTURE FAIL: final report index'; printf '%s\n' "$_rep"; exit 1; }
printf '%s\n' "$_rep" | grep -q '이전 대화 요약' || { echo 'FIXTURE FAIL: final report summary column'; printf '%s\n' "$_rep"; exit 1; }
printf '%s\n' "$_rep" | grep -q 'mbox recv ft-loomdomain-da#0' || { echo 'FIXTURE FAIL: final report prior summary'; printf '%s\n' "$_rep"; exit 1; }

# ---------- UC13: --ctx 1m + save/restore 스냅샷 ----------

# ⑩ --ctx 1m — 명시 --model 에 창 선택자 부착 (괄호 보존)
_c1="$("$ROOT/core/bin/tmuxc" open "$ROOT" --name TMUXC_CTX1 --agent claude --role worker \
  --model claude-opus-5 --effort high --ctx 1m --dry-run)"
printf '%s\n' "$_c1" | grep -qF -- '--model "claude-opus-5[1m]"' || {
  echo 'FAIL: --ctx 1m must append [1m] to explicit --model'; printf '%s\n' "$_c1"; exit 1; }

# ⑪ 멱등 — 이미 [1m] 인 모델에 이중 부착 금지
_c2="$("$ROOT/core/bin/tmuxc" open "$ROOT" --name TMUXC_CTX2 --agent claude --role worker \
  --model 'claude-sonnet-5[1m]' --ctx 1m --dry-run)"
printf '%s\n' "$_c2" | grep -qF -- '--model "claude-sonnet-5[1m]"' || {
  echo 'FAIL: --ctx 1m must be idempotent'; printf '%s\n' "$_c2"; exit 1; }
printf '%s\n' "$_c2" | grep -qF -- '[1m][1m]' && {
  echo 'FAIL: --ctx 1m double-appended'; printf '%s\n' "$_c2"; exit 1; }

# ⑫ --ctx 는 claude 전용 (침묵 무시 금지)
_c3="$("$ROOT/core/bin/tmuxc" open "$ROOT" --name TMUXC_CTX3 --agent codex --role worker --ctx 1m --dry-run 2>&1 || true)"
printf '%s\n' "$_c3" | grep -q -- '--ctx 는' || {
  echo 'FAIL: --ctx with codex must be rejected'; printf '%s\n' "$_c3"; exit 1; }
_c4="$("$ROOT/core/bin/tmuxc" open "$ROOT" --name TMUXC_CTX4 --agent claude --role worker --ctx xxl --dry-run 2>&1 || true)"
printf '%s\n' "$_c4" | grep -q '형식 오류' || {
  echo 'FAIL: malformed --ctx must be rejected'; printf '%s\n' "$_c4"; exit 1; }

# ⑬ apply_ctx_window / alias_body_apply_ctx — [1m] 이 글롭으로 새지 않는지 (밀폐 단위테스트)
_ctxu=$(bash -c '
  eval "$(sed -n "/^die()/,/^}/p; /^apply_ctx_window()/,/^}/p; /^alias_body_apply_ctx()/,/^}/p" "'"$ROOT"'/core/bin/tmuxc")"
  apply_ctx_window claude-opus-5 1m; printf "|"
  apply_ctx_window "claude-opus-5[1m]" 1m; printf "|"
  apply_ctx_window claude-opus-5 ""; printf "|"
  alias_body_apply_ctx "hr.sh --model claude-sonnet-5 --effort high" 1m; printf "|"
  alias_body_apply_ctx "hr.sh --model \"claude-opus-4-8[1m]\" --effort high" 1m
')
[[ "$_ctxu" == 'claude-opus-5[1m]|claude-opus-5[1m]|claude-opus-5|hr.sh --model "claude-sonnet-5[1m]" --effort high|hr.sh --model "claude-opus-4-8[1m]" --effort high' ]] || {
  echo "FIXTURE FAIL: ctx helpers"; printf '%s\n' "$_ctxu"; exit 1; }

# ⑭ 스냅샷 파이프라인 — resolve/emit 스키마 (tmux 무의존, stdin 픽스처)
SNAP_PY="$ROOT/core/libexec/tmuxc-snapshot.py"
US=$'\x1f'
_rows="alpha#0${US}/nonexistent/xyz${US}1${US}node${US}claude${US}claude-opus-5[1m]${US}high${US}sid-aaa
beta#1${US}/nonexistent/xyz${US}0${US}node${US}codex${US}${US}high${US}sid-bbb"
_res="$(printf '%s\n' "$_rows" | python3 "$SNAP_PY" resolve)"
[[ "$(printf '%s\n' "$_res" | wc -l | tr -d ' ')" == "2" ]] || {
  echo 'FIXTURE FAIL: resolve must emit one row per input'; printf '%s\n' "$_res"; exit 1; }
printf '%s\n' "$_res" | awk -F$'\x1f' '$1=="alpha#0" && $9=="argv"' | grep -q . || {
  echo 'FIXTURE FAIL: argv sid must be sid_source=argv'; printf '%s\n' "$_res"; exit 1; }

_emit="$(printf '%s\n' "$_res" | sed "s|\$|${US}RESUMECMD|" | python3 "$SNAP_PY" emit --stdout)"
printf '%s\n' "$_emit" | python3 -m json.tool >/dev/null || {
  echo 'FIXTURE FAIL: emit must produce valid JSON'; printf '%s\n' "$_emit"; exit 1; }
printf '%s\n' "$_emit" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["schema"]==1, "schema"
assert d["session_count"]==2, d["session_count"]
s={x["name"]:x for x in d["sessions"]}
assert s["alpha#0"]["model"]=="claude-opus-5[1m]", s["alpha#0"]["model"]
assert s["alpha#0"]["effort"]=="high"
assert s["alpha#0"]["resume_cmd"]=="RESUMECMD"
assert s["alpha#0"]["attached"] is True and s["beta#1"]["attached"] is False
assert d["created_at"].endswith("Z")
' || { echo 'FIXTURE FAIL: emit schema contract'; printf '%s\n' "$_emit"; exit 1; }

# ⑭-b 후보 cap 회귀: 마커가 «오래된 mtime» 파일에 있어도 sid 를 찾아야 한다.
# (cap=12 시절 한 워크트리 27세션 중 mtime 14위 파일이 잘려 sid 미해결이 났다.)
CAPFIX="$FIX/capdir"; CAPPROJ="$CAPFIX/-tmp-capcwd"; mkdir -p "$CAPPROJ"
CAPCWD="$FIX/capcwd"; mkdir -p "$CAPCWD"
CAPPROJ2="$CAPFIX/$(printf '%s' "$CAPCWD" | sed 's|[/.]|-|g')"; mkdir -p "$CAPPROJ2"
for i in $(seq -w 1 30); do
  printf '{"type":"user","message":{"content":"noise %s"},"timestamp":"%s"}\n' "$i" "$NOW" \
    > "$CAPPROJ2/cap$i.jsonl"
done
# 타깃 세션의 마커를 «가장 오래된» 파일에 둔다
printf '{"type":"user","message":{"content":"[o→CAPTGT#1] 세션명(me)=CAPTGT#1 시작"},"timestamp":"%s"}\n{"type":"user","message":{"content":"캡 테스트 작업"},"timestamp":"%s"}\n' "$NOW" "$NOW" \
  > "$CAPPROJ2/capold.jsonl"
touch -t 202601010101 "$CAPPROJ2/capold.jsonl"
_cap="$(printf 'CAPTGT#1\x1f%s\x1f1\x1fnode\x1fclaude\x1f\x1f\x1f\n' "$CAPCWD" \
  | TMUXC_CLAUDE_PROJECTS="$CAPFIX" python3 "$SNAP_PY" resolve)"
printf '%s\n' "$_cap" | awk -F$'\x1f' '$8=="capold" && $9=="transcript"' | grep -q . || {
  echo 'FIXTURE FAIL: marker in old-mtime file must still resolve (candidate cap regression)'
  printf '%s\n' "$_cap"; exit 1; }
printf '%s\n' "$_cap" | grep -q '캡 테스트 작업' || {
  echo 'FIXTURE FAIL: title must come from the sid-bearing transcript'; printf '%s\n' "$_cap"; exit 1; }

# ⑭-c sid 선점: 같은 cwd 의 두 세션이 같은 트랜스크립트를 물면 안 된다
_dup="$(printf 'CAPTGT#1\x1f%s\x1f1\x1fnode\x1fclaude\x1f\x1f\x1f\nCAPOTHER#2\x1f%s\x1f0\x1fnode\x1fclaude\x1f\x1f\x1f\n' "$CAPCWD" "$CAPCWD" \
  | TMUXC_CLAUDE_PROJECTS="$CAPFIX" python3 "$SNAP_PY" resolve)"
[ "$(printf '%s\n' "$_dup" | awk -F$'\x1f' '$8!=""{print $8}' | sort | uniq -d | wc -l | tr -d ' ')" -eq 0 ] || {
  echo 'FIXTURE FAIL: two sessions must not claim the same sid'; printf '%s\n' "$_dup"; exit 1; }

# ⑮ restore --from — 스냅샷을 읽어 표만 찍고 tmux 를 건드리지 않는다(--go 없음)
SNAPFIX="$FIX/snap"; mkdir -p "$SNAPFIX"
cat > "$SNAPFIX/snapshot-20260801T000000Z.json" <<JSON
{"schema":1,"created_at":"2026-08-01T00:00:00Z","host":"t","session_count":2,
 "sessions":[
  {"name":"snapA#0","cwd":"$FIX","agent":"claude","model":"claude-opus-5[1m]","effort":"high",
   "session_id":"sid-a","sid_source":"transcript","title":"작업 A","attached":true,
   "pane_command":"node","resume_cmd":"hr.sh --model \"claude-opus-5[1m]\" --effort high --resume sid-a"},
  {"name":"snapShell#0","cwd":"$FIX","agent":"shell","model":null,"effort":null,
   "session_id":null,"sid_source":"none","title":null,"attached":false,
   "pane_command":"zsh","resume_cmd":null}]}
JSON
_from="$(TMUXC_SNAPSHOT_DIR="$SNAPFIX" "$ROOT/core/bin/tmuxc" restore --from "$SNAPFIX/snapshot-20260801T000000Z.json" 2>&1)"
printf '%s\n' "$_from" | grep -q '📸 스냅샷 사용' || {
  echo 'FIXTURE FAIL: restore --from must announce snapshot source'; printf '%s\n' "$_from"; exit 1; }
printf '%s\n' "$_from" | grep -qF -- '--model "claude-opus-5[1m]" --effort high --resume sid-a' || {
  echo 'FIXTURE FAIL: snapshot resume_cmd must be replayed verbatim ([1m]/effort 보존)'
  printf '%s\n' "$_from"; exit 1; }
printf '%s\n' "$_from" | grep -q 'snapShell#0' || {
  echo 'FIXTURE FAIL: shell row must still be listed (as skip)'; printf '%s\n' "$_from"; exit 1; }
printf '%s\n' "$_from" | grep -q '작업 A' || {
  echo 'FIXTURE FAIL: snapshot title must show in table'; printf '%s\n' "$_from"; exit 1; }
printf '%s\n' "$_from" | grep -q '오래됐습니다' || {
  echo 'FIXTURE FAIL: stale snapshot must warn'; printf '%s\n' "$_from"; exit 1; }
# --baton: 표가 «실제로 실행될» 커맨드를 보여야 한다 — --resume 만 빠지고 model/effort 는 남는다
_bat="$(TMUXC_SNAPSHOT_DIR="$SNAPFIX" "$ROOT/core/bin/tmuxc" restore --from "$SNAPFIX/snapshot-20260801T000000Z.json" --baton 2>&1)"
printf '%s\n' "$_bat" | grep -qF -- '--resume sid-a' && {
  echo 'FIXTURE FAIL: --baton table must not show --resume'; printf '%s\n' "$_bat"; exit 1; }
printf '%s\n' "$_bat" | grep -qF -- '--model "claude-opus-5[1m]" --effort high' || {
  echo 'FIXTURE FAIL: --baton must keep model/effort'; printf '%s\n' "$_bat"; exit 1; }

# ⑮-b 소스 우선순위: 인자 없는 restore 는 스냅샷이 있으면 «자동으로» 그쪽을 쓰고,
# --scan 은 스냅샷이 있어도 로그 스캔을 강제한다. (이 자동채택이 밀폐 테스트를 깨뜨린
# 적이 있어 계약으로 못박는다 — 위 NOSNAP 격리와 짝.)
ln -sfn "$SNAPFIX/snapshot-20260801T000000Z.json" "$SNAPFIX/latest.json"
_auto="$(TMUXC_SNAPSHOT_DIR="$SNAPFIX" "$ROOT/core/bin/tmuxc" restore --since 0.001 </dev/null 2>&1)"
printf '%s\n' "$_auto" | grep -q '📸 스냅샷 사용' || {
  echo 'FIXTURE FAIL: bare restore must auto-adopt snapshot when present'; printf '%s\n' "$_auto"; exit 1; }
_forced="$(TMUXC_CLAUDE_GLOB="$EMPTY/none/*.jsonl" TMUXC_CODEX_GLOB="$EMPTY/none/*.jsonl" \
  TMUXC_CODEX_INDEX="$EMPTY/none.jsonl" TMUXC_SNAPSHOT_DIR="$SNAPFIX" \
  "$ROOT/core/bin/tmuxc" restore --scan --since 0.001 </dev/null 2>&1)"
printf '%s\n' "$_forced" | grep -q '📸 스냅샷 사용' && {
  echo 'FIXTURE FAIL: --scan must ignore snapshot'; printf '%s\n' "$_forced"; exit 1; }
printf '%s\n' "$_forced" | grep -q '복구 후보 없음' || {
  echo 'FIXTURE FAIL: --scan must take log-scan path'; printf '%s\n' "$_forced"; exit 1; }

# --from 과 --scan 동시 사용 금지
"$ROOT/core/bin/tmuxc" restore --from latest --scan >/dev/null 2>&1 && {
  echo 'FAIL: --from with --scan must be rejected'; exit 1; }
# 존재하지 않는 스냅샷은 조용히 성공하지 않는다
"$ROOT/core/bin/tmuxc" restore --from "$SNAPFIX/nope.json" >/dev/null 2>&1 && {
  echo 'FAIL: missing snapshot must fail loudly'; exit 1; }

# ⑯ --keep 검증 — 0/음수/비정수 거부
for bad in 0 -1 abc; do
  "$ROOT/core/bin/tmuxc" save --keep "$bad" --dry-run >/dev/null 2>&1 && {
    echo "FAIL: save --keep $bad must be rejected"; exit 1; }
done

echo "tmuxc verify OK"
