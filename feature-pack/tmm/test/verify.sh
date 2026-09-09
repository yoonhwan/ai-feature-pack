#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMM="$ROOT/core/bin/tmm"
SCAN="$ROOT/core/libexec/seat-scan.sh"

# (a) --help 는 exit 0 이고 출력에 tmm 이 있어야 한다
help_out="$("$TMM" --help)"
printf '%s\n' "$help_out" | grep -q 'tmm' || { echo 'FAIL: --help 출력에 tmm 없음'; exit 1; }

# (b) 문법 검사 (4개 스크립트)
bash -n "$TMM" "$SCAN" "$ROOT/install.sh" "$ROOT/uninstall.sh"

# ---------- 격리 tmux 서버 (기본 소켓 절대 미접촉) ----------
# tmm 은 tmux 를 PATH 에서 부르므로 격리는 TMUX_TMPDIR 환경변수로만 한다.
# tmm 안에서 부르는 tmux 도 같은 env 를 상속해야 하니 매 호출을 env 로 감싼다.
SOCK_DIR="$(mktemp -d)"
tm()  { env -u TMUX TMUX_TMPDIR="$SOCK_DIR" tmux "$@"; }
# TMPDIR 도 격리 — tmm 의 상태 파일(mode/auto/waitset/bell)과 캐시가 실사용본과 섞이지 않게
# TMM_RUN 도 지운다 — 개발 셸에 export 된 수동 실험용 TMM_RUN 이 상속되면 상태 파일이 격리 밖으로 새어
# (f) 가 «mode 파일 없음» 으로 실패한다 (2026-09-09 복원 세션 실측). 코드 결함이 아니라 환경 오염.
tmm() { env -u TMUX -u TMM_RUN TMUX_TMPDIR="$SOCK_DIR" TMPDIR="$SOCK_DIR" TMM_SCAN="${TMM_SCAN_OVERRIDE:-$SCAN}" TMM_CACHE_TTL=0 TMM_CATEGORIES=/dev/null "$TMM" "$@"; }
STATE="$SOCK_DIR/tmm-$(id -u)"
cleanup() {
  env -u TMUX TMUX_TMPDIR="$SOCK_DIR" tmux kill-server 2>/dev/null || true
  rm -rf "$SOCK_DIR"
}
trap cleanup EXIT

tm new-session -d -s TMM_VERIFY_A -x 80 -y 24
# 셸 프롬프트가 자리잡을 시간
sleep 0.5

# (c) rows 출력에 TMM_VERIFY_A + 필드 3개(탭 구분)
rows_out="$(tmm rows time)"
printf '%s\n' "$rows_out" | grep -q 'TMM_VERIFY_A' || {
  echo 'FAIL: rows 출력에 TMM_VERIFY_A 없음'; printf '%s\n' "$rows_out"; exit 1; }
printf '%s\n' "$rows_out" | awk -F'\t' '/TMM_VERIFY_A/ && NF==3' | grep -q . || {
  echo 'FAIL: TMM_VERIFY_A 행이 탭 3필드가 아님'
  printf '%s\n' "$rows_out" | awk -F'\t' '/TMM_VERIFY_A/{print "NF="NF}'; exit 1; }

# (d) ls VERIFY 는 한 줄 매치
ls_out="$(tmm ls VERIFY)"
[ "$(printf '%s\n' "$ls_out" | grep -c 'TMM_VERIFY_A')" -eq 1 ] || {
  echo 'FAIL: ls VERIFY 매치가 1줄이 아님'; printf '%s\n' "$ls_out"; exit 1; }

# (e) s TMM_VERIFY_A ping — 셸-only 좌석이라 차단(exit 1) + "차단" 문구,
#     그리고 pane 에 ping 이 타이핑되지 않아야 한다.
set +e
send_out="$(tmm s TMM_VERIFY_A ping 2>&1)"; send_rc=$?
set -e
[ "$send_rc" -eq 1 ] || { echo "FAIL: send 가 exit 1 이 아님 (rc=$send_rc)"; printf '%s\n' "$send_out"; exit 1; }
printf '%s\n' "$send_out" | grep -q '차단' || { echo 'FAIL: send 출력에 "차단" 문구 없음'; printf '%s\n' "$send_out"; exit 1; }
pane="$(tm capture-pane -t '=TMM_VERIFY_A:' -p)"
printf '%s\n' "$pane" | grep -q 'ping' && {
  echo 'FAIL: 차단됐는데 pane 에 ping 이 타이핑됨'; printf '%s\n' "$pane"; exit 1; }

# (f) 정렬 모드는 상태 파일에 남고 rows-cur 가 그것을 따른다 (^R·자동 갱신이 모드를 잃지 않게)
tmm mode wait h
[ "$(cat "$STATE/mode")" = "wait h" ] || { echo "FAIL: mode 파일이 'wait h' 가 아님: $(cat "$STATE/mode" 2>&1)"; exit 1; }
tmm rows-cur | grep -q 'TMM_VERIFY_A' && { echo 'FAIL: 대기만(h) 모드인데 IDLE 좌석이 rows-cur 에 나옴'; exit 1; }
tmm mode time
tmm rows-cur | grep -q 'TMM_VERIFY_A' || { echo 'FAIL: time 모드 rows-cur 에 TMM_VERIFY_A 없음'; exit 1; }

# (g) ^U 는 «미리보기» 주기만 순환: 5 → 10 → 15 → 5 (off 없음). 전좌석 주기는 20 고정, 헤더에 둘 다 표시
rm -f "$STATE/auto"
tmm header | grep -q 'pane 5s · 전체 20s' || { echo "FAIL: 기본 헤더가 pane 5s · 전체 20s 아님"; tmm header; exit 1; }
[ "$(tmm auto-cycle)" = 10 ] || { echo "FAIL: auto-cycle 5→10 아님"; exit 1; }
[ "$(tmm auto-cycle)" = 15 ] || { echo "FAIL: auto-cycle 10→15 아님"; exit 1; }
[ "$(tmm auto-cycle)" = 5 ]  || { echo "FAIL: auto-cycle 15→5 아님 (off 가 끼어들었나)"; exit 1; }
tmm header | grep -q 'pane 5s' || { echo "FAIL: 순환 후 헤더에 pane 5s 없음"; tmm header; exit 1; }
[ "$(TMM_AUTO=30 tmm header | grep -o '전체 [0-9]*s')" = '전체 30s' ] || { echo "FAIL: TMM_AUTO 가 전체 에 반영 안 됨"; exit 1; }
rm -f "$STATE/auto"   # 상태 파일이 env 보다 우선 — TUI 진입 시 env 로 다시 쓰므로 여기선 지우고 잰다
[ "$(TMM_AUTO_PREVIEW=0 tmm header | grep -o 'pane [a-z0-9]*')" = 'pane off' ] || { echo "FAIL: TMM_AUTO_PREVIEW=0 인데 pane off 아님"; exit 1; }

# (j) 헤더는 폰 60열에서 잘리지 않아야 한다 — fzf 는 헤더를 줄바꿈 없이 자르므로 각 줄 표시폭(동아시아 W/F=2) ≤ 60
for a in 0 15 dead; do
  if [ "$a" = dead ]; then tmm view dead >/dev/null; printf '24\n' > "$STATE/since"; else tmm view live >/dev/null; printf '%s\n' "$a" > "$STATE/auto"; fi
  tmm header | python3 -c '
import sys, re, unicodedata
bad = [(len_, l) for raw in sys.stdin.read().splitlines()
       for l in [re.sub(r"\x1b\[[0-9;]*m", "", raw)]
       for len_ in [sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in l)] if len_ > 58]
for w, l in bad: print(f"FAIL: 헤더 {w}열 > 58 (fzf 들여쓰기 2 포함 60): {l}")
sys.exit(1 if bad else 0)' || exit 1
done
tmm view live >/dev/null; rm -f "$STATE/since"

# (h) 벨 플래그: 직전 스캔 대비 «새로» HUMAN/BLOCK/STUCK 이 된 좌석이 있을 때만 bell 파일 생성
printf '#!/usr/bin/env bash\necho "TMM_VERIFY_A IDLE"\n'  > "$SOCK_DIR/scan-idle.sh"
printf '#!/usr/bin/env bash\necho "TMM_VERIFY_A HUMAN"\n' > "$SOCK_DIR/scan-human.sh"
rm -f "$STATE/waitset" "$STATE/bell"
TMM_SCAN_OVERRIDE="$SOCK_DIR/scan-human.sh" tmm rows time >/dev/null
[ -f "$STATE/bell" ] && { echo 'FAIL: 첫 스캔(비교 대상 없음)인데 bell 생성됨'; exit 1; }
TMM_SCAN_OVERRIDE="$SOCK_DIR/scan-idle.sh" tmm rows time >/dev/null
[ -f "$STATE/bell" ] && { echo 'FAIL: HUMAN→IDLE 인데 bell 생성됨'; exit 1; }
TMM_SCAN_OVERRIDE="$SOCK_DIR/scan-human.sh" tmm rows time >/dev/null
[ -f "$STATE/bell" ] || { echo 'FAIL: IDLE→HUMAN 인데 bell 없음'; exit 1; }

# (i) 소켓 post: 격리 세션 안의 fzf --listen 에 액션을 쏘면 화면이 바뀐다 (핑거가 쓰는 경로)
tm send-keys -t '=TMM_VERIFY_A:' -l "fzf --listen=$SOCK_DIR/t.sock --prompt='P> ' </dev/null"
tm send-keys -t '=TMM_VERIFY_A:' Enter
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -S "$SOCK_DIR/t.sock" ] && break; sleep 0.3; done
[ -S "$SOCK_DIR/t.sock" ] || { echo 'FAIL: fzf --listen 소켓이 안 생김'; exit 1; }
tmm __post "$SOCK_DIR/t.sock" 'change-prompt(ZZ> )'
sleep 0.5
tm capture-pane -t '=TMM_VERIFY_A:' -p | grep -q 'ZZ>' || { echo 'FAIL: post 한 change-prompt 가 화면에 반영 안 됨'; tm capture-pane -t '=TMM_VERIFY_A:' -p; exit 1; }
tm send-keys -t '=TMM_VERIFY_A:' Escape

# (k) 미리보기 렌더러 골든 — Claude 입력박스(구분선+❯)·statusline 제거, Codex 프롬프트 제거, 본문 표 구분선 보존, 색 유지, 연속 빈줄 1줄
SEP="$(printf '─%.0s' $(seq 1 60))"
render_in="$(printf '%b\n' \
  '⏺ 첫 응답' '' '' '  Ran 1 shell command' "$SEP" '  표 아래 본문 — 구분선 뒤에 프롬프트가 없으니 자르면 안 됨' \
  '\033[1m⏺ 굵은 응답\033[0m' '✻ Cooked for 3s · done 오후 10:41' \
  "\033[38;2;136;136;136m${SEP} sess#1 ${SEP}\033[39m" '\033[38;2;153;153;153m❯ \033[39m' "$SEP" \
  '  branch:main | !1' '  [OMC#5.3.0L] | Model: X' '  ⏵⏵ auto mode on')"
render_out="$(printf '%s\n' "$render_in" | env -u TMUX "$TMM" __render)"
plain="$(printf '%s\n' "$render_out" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g')"
printf '%s\n' "$plain" | grep -q '표 아래 본문' || { echo 'FAIL: 본문 속 표 구분선에서 잘림'; printf '%s\n' "$plain"; exit 1; }
printf '%s\n' "$plain" | grep -qE '❯|branch:main|OMC#|auto mode' && { echo 'FAIL: 입력박스/statusline 이 남음'; printf '%s\n' "$plain"; exit 1; }
[ "$(printf '%s\n' "$plain" | tail -1)" = '✻ Cooked for 3s · done 오후 10:41' ] || { echo 'FAIL: 마지막 줄이 완료 마커가 아님'; printf '%s\n' "$plain"; exit 1; }
blank_n="$(printf '%s\n' "$render_in" | env -u TMUX "$TMM" __render | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | grep -c '^$')"
[ "$blank_n" -eq 1 ] || { echo "FAIL: 연속 빈 줄이 1줄로 안 눌림 (blank=$blank_n)"; printf '%s\n' "$plain"; exit 1; }
printf '%s\n' "$render_out" | LC_ALL=C grep -aq $'\x1b\[1m' || { echo 'FAIL: SGR 색 코드가 사라짐'; exit 1; }
codex_out="$(printf '%s\n' '• Ran rg foo' '' '› Ask Codex to do anything' '' '  gpt-6 high · main · Context 31% left' | env -u TMUX "$TMM" __render)"
[ "$codex_out" = '• Ran rg foo' ] || { echo 'FAIL: Codex 프롬프트 이하가 안 잘림'; printf '%s\n' "$codex_out"; exit 1; }

# ---------- (l)(m)(n) 종료된 세션 뷰 + 복구 ----------
# 스캐너가 픽스처 HOME 만 보게 env 로 글롭을 갈아끼운다(스캐너 상단이 이 env 를 읽는다).
# find_transcript 가 경로의 /.claude//.codex/ 로 agent 를 가르므로 픽스처 경로에 그 세그먼트를 둔다.
FIX="$SOCK_DIR/home"; DEAD_RUN="$SOCK_DIR/dead-run"; mkdir -p "$FIX" "$DEAD_RUN"
SID_CC="AAAA1111-2222-3333-4444-555566667777"
SID_CC2="AAAA2222-2222-3333-4444-555566667777"
SID_ARCH="AAAA3333-2222-3333-4444-555566667777"
SID_CDX="bbbbbbbb-1111-2222-3333-444455556666"
SID_CMD="cccccccc-1111-2222-3333-444455556666"
SNAP_FIX="$FIX/nosnap.json"; RTRIES=20   # (n) 에서 snap.json·3 으로 바꾼다
dtmm() {
  env -u TMUX TMUX_TMPDIR="$SOCK_DIR" TMPDIR="$SOCK_DIR" \
      TMM_RUN="$DEAD_RUN" TMM_CACHE_TTL=0 TMM_CATEGORIES=/dev/null \
      TMM_CLAUDE_GLOB="$FIX/.claude/projects/*/*.jsonl" \
      TMM_CODEX_GLOB="$FIX/.codex/sessions/*/*/*/rollout-*.jsonl" \
      TMM_CMD_GLOB="$FIX/.commandcode/projects/*/*.jsonl" \
      TMM_OPENCODE_DB=/nonexistent TMM_SNAPSHOT="$SNAP_FIX" \
      TMM_RESTORE_TRIES="$RTRIES" \
      "$TMM" "$@"
}

# 픽스처 3종(claude 신·구세대+fable, codex, cmd) 생성. mtime 은 라이브 유예(90s) 밖 과거로.
python3 - "$FIX" "$SID_CC" "$SID_CC2" "$SID_ARCH" "$SID_CDX" "$SID_CMD" "$FIX" <<'PY'
import json, os, sys, time
from datetime import datetime, timezone
FIX, sid_cc, sid_cc2, sid_arch, sid_cdx, sid_cmd, cwd = sys.argv[1:8]
def iso(delta): return datetime.fromtimestamp(time.time()-delta, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
def wl(path, records, delta):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for r in records: f.write(json.dumps(r, ensure_ascii=False) + "\n")
    os.utime(path, (time.time()-delta, time.time()-delta))
H1, H20 = 3600, 72000
wl(os.path.join(FIX, ".claude/projects/-x", sid_cc + ".jsonl"), [
    {"type": "agent-name", "agentName": "ft-fx-impl#3"},
    {"type": "user", "cwd": cwd, "timestamp": iso(H1), "message": {"content": "hello"}},
    {"type": "assistant", "timestamp": iso(H1), "message": {"model": "claude-sonnet-5", "content": [{"type": "text", "text": "LAST ANSWER"}]}}], H1)
wl(os.path.join(FIX, ".claude/projects/-x", sid_cc2 + ".jsonl"), [
    {"type": "agent-name", "agentName": "ft-fx-impl#2"},
    {"type": "user", "cwd": cwd, "timestamp": iso(H1), "message": {"content": "old"}},
    {"type": "assistant", "timestamp": iso(H1), "message": {"model": "claude-sonnet-5", "content": [{"type": "text", "text": "OLD ANSWER"}]}}], H1)
wl(os.path.join(FIX, ".claude/projects/-x", sid_arch + ".jsonl"), [
    {"type": "agent-name", "agentName": "ft-fx-arch#0"},
    {"type": "user", "cwd": cwd, "timestamp": iso(H20), "message": {"content": "arch"}},
    {"type": "assistant", "timestamp": iso(H20), "message": {"model": "claude-fable-5-1", "content": [{"type": "text", "text": "ARCH ANSWER"}]}}], H20)
wl(os.path.join(FIX, ".codex/sessions/2026/09/09", "rollout-2026-09-09T00-00-00-" + sid_cdx + ".jsonl"), [
    {"type": "session_meta", "timestamp": iso(H1), "payload": {"session_id": sid_cdx, "cwd": cwd, "source": "cli"}},
    {"type": "response_item", "timestamp": iso(H1), "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "[ORCH→ft-fx-codex#1] hi"}]}},
    {"type": "response_item", "timestamp": iso(H1), "payload": {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "CODEX LAST"}]}}], H1)
pm = os.path.join(FIX, ".commandcode/projects/-x", sid_cmd + ".jsonl")
wl(pm, [
    {"type": "session", "id": sid_cmd, "cwd": cwd, "timestamp": iso(H1)},
    {"type": "message", "timestamp": iso(H1), "message": {"role": "user", "content": "cmd hi"}},
    {"type": "message", "timestamp": iso(H1), "message": {"role": "assistant", "content": "CMD LAST"}}], H1)
with open(pm[:-6] + ".meta.json", "w", encoding="utf-8") as f:
    json.dump({"title": "ft-fx-cmd#0", "userRenamed": True}, f)
with open(os.path.join(FIX, "snap.json"), "w", encoding="utf-8") as f:
    json.dump({"sessions": [{"name": "ft-fx-impl#3", "session_id": sid_cc,
        "resume_cmd": "printf 'ctx:0%% ❯ \\n'; sleep 20", "model": "claude-sonnet-5"}]}, f, ensure_ascii=False)
PY

# (l) 스캐너·계보·창(since) — 기본(since=12, latest gen)
dr="$(dtmm dead-rows time)"
for want in 'ft-fx-impl#3' 'ft-fx-codex#1' 'ft-fx-cmd#0'; do
  printf '%s\n' "$dr" | grep -q "$want" || { echo "FAIL: (l) dead-rows 에 $want 없음"; printf '%s\n' "$dr"; exit 1; }
done
printf '%s\n' "$dr" | grep -q 'ft-fx-impl#2' && { echo 'FAIL: (l) latest gen 인데 구세대 ft-fx-impl#2 가 나옴'; printf '%s\n' "$dr"; exit 1; }
printf '%s\n' "$dr" | grep -q 'ft-fx-arch#0' && { echo 'FAIL: (l) since=12 인데 20h 짜리 ft-fx-arch#0 이 나옴'; printf '%s\n' "$dr"; exit 1; }
printf '%s\n' "$dr" | grep 'ft-fx-impl#3' | grep -q ' CC ' || { echo 'FAIL: (l) ft-fx-impl#3 배지가 CC 가 아님'; printf '%s\n' "$dr"; exit 1; }
printf '%s\n' "$dr" | grep 'ft-fx-codex#1' | grep -q ' CDX ' || { echo 'FAIL: (l) ft-fx-codex#1 배지가 CDX 가 아님'; printf '%s\n' "$dr"; exit 1; }
printf '%s\n' "$dr" | grep 'ft-fx-cmd#0' | grep -q ' CMD ' || { echo 'FAIL: (l) ft-fx-cmd#0 배지가 CMD 가 아님'; printf '%s\n' "$dr"; exit 1; }
printf '%s\n' "$dr" | awk -F'\t' '/ft-fx-impl#3/ && NF==3' | grep -q . || {
  echo 'FAIL: (l) dead-rows 행이 탭 3필드가 아님'
  printf '%s\n' "$dr" | awk -F'\t' '/ft-fx-impl#3/{print "NF="NF}'; exit 1; }
# 계보 전체(gen all) 로 바꾸면 구세대도 나온다
dtmm gen >/dev/null
dtmm dead-rows time | grep -q 'ft-fx-impl#2' || { echo 'FAIL: (l) gen all 인데 ft-fx-impl#2 가 안 나옴'; dtmm dead-rows time; exit 1; }
# 창을 24h 로 넓히면 20h 짜리 arch 가 들어온다
dtmm since 24 >/dev/null
dtmm dead-rows time | grep -q 'ft-fx-arch#0' || { echo 'FAIL: (l) since=24 인데 ft-fx-arch#0 이 안 나옴'; dtmm dead-rows time; exit 1; }

# (m) 미리보기(dp)·복구 커맨드 합성(dry-run)
dp_out="$(dtmm dp 'ft-fx-impl#3' 5 | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g')"
printf '%s\n' "$dp_out" | grep -q 'LAST ANSWER' || { echo 'FAIL: (m) dp 출력에 LAST ANSWER 없음'; printf '%s\n' "$dp_out"; exit 1; }
printf '%s\n' "$dp_out" | grep -q '✻ done' || { echo 'FAIL: (m) dp 출력에 완료 마커(✻ done) 없음'; printf '%s\n' "$dp_out"; exit 1; }
r_impl="$(dtmm restore 'ft-fx-impl#3' --dry-run)"
printf '%s\n' "$r_impl" | grep -qF 'claude-sonnet-5[1m]' || { echo 'FAIL: (m) claude 복구 cmd 에 claude-sonnet-5[1m] 없음'; printf '%s\n' "$r_impl"; exit 1; }
printf '%s\n' "$r_impl" | grep -qF -- '--effort high' || { echo 'FAIL: (m) claude 복구 cmd 에 --effort high 없음'; printf '%s\n' "$r_impl"; exit 1; }
printf '%s\n' "$r_impl" | grep -qF -- "--resume $SID_CC" || { echo 'FAIL: (m) claude 복구 cmd 에 --resume <sid> 없음'; printf '%s\n' "$r_impl"; exit 1; }
r_arch="$(dtmm restore 'ft-fx-arch#0' --dry-run)"
printf '%s\n' "$r_arch" | grep -qF 'claude-fable-5-1"' || { echo 'FAIL: (m) fable 복구 cmd 모델이 claude-fable-5-1 아님'; printf '%s\n' "$r_arch"; exit 1; }
printf '%s\n' "$r_arch" | grep -qF '[1m]' && { echo 'FAIL: (m) fable 복구 cmd 에 [1m] 이 붙음(붙으면 안 됨)'; printf '%s\n' "$r_arch"; exit 1; }
r_cdx="$(dtmm restore 'ft-fx-codex#1' --dry-run)"
printf '%s\n' "$r_cdx" | grep -qF "resume $SID_CDX" || { echo 'FAIL: (m) codex 복구 cmd 에 resume <sid> 없음'; printf '%s\n' "$r_cdx"; exit 1; }

# (n) 실복구 — 스냅샷 resume_cmd(가짜 명령) 를 격리 tmux 에 그대로 주입. claude 를 실제로 띄우지 않는다.
SNAP_FIX="$FIX/snap.json"; RTRIES=3
dtmm restore 'ft-fx-impl#3' </dev/null >"$SOCK_DIR/restore.out" 2>&1 || true
tm has-session -t '=ft-fx-impl#3' 2>/dev/null || { echo 'FAIL: (n) 복구 후 ft-fx-impl#3 세션이 없음'; cat "$SOCK_DIR/restore.out"; exit 1; }
npane="$(tm capture-pane -t '=ft-fx-impl#3:' -p 2>/dev/null)"
printf '%s\n' "$npane" | grep -q 'sleep 20' || { echo 'FAIL: (n) pane 에 resume_cmd(sleep 20) 가 안 보임'; printf '%s\n' "$npane"; exit 1; }
printf '%s\n' "$npane" | grep -q '\[restore→ft-fx-impl#3\]' || { echo 'FAIL: (n) pane 에 claude 복원 안내가 안 보임'; printf '%s\n' "$npane"; exit 1; }
tm kill-session -t 'ft-fx-impl#3' 2>/dev/null || true

# (o) 일괄 복구 — 창 안 «전부». dry-run 은 건수·커맨드만, 실행은 스냅샷 픽스처를 impl#3·codex#1 두 건으로 넓혀
#     둘 다 가짜 resume_cmd 로 격리 tmux 에 뜨는지 + 이미 살아있는 건 ⏭ 로 건너뛰는지 + 집계 줄.
csid_real="$(grep -o '"session_id": *"[^"]*"' "$FIX"/.codex/sessions/2026/09/09/rollout-*.jsonl | head -1 | sed 's/.*: *"//;s/"//')"
python3 - "$FIX" "$csid_real" <<'PY'
import json, os, sys
FIX, csid = sys.argv[1], sys.argv[2]
p = os.path.join(FIX, "snap.json"); snap = json.load(open(p))
snap["sessions"] = [x for x in snap["sessions"] if x["name"] != "ft-fx-codex#1"]
snap["sessions"].append({"name": "ft-fx-codex#1", "session_id": csid, "resume_cmd": "printf 'ctx:0%% ❯ \\n'; sleep 20", "model": ""})
json.dump(snap, open(p, "w"), ensure_ascii=False)
PY
dry="$(dtmm restore-all --dry-run 2>&1)"   # 조용히 — 검사만
n_dry="$(printf '%s\n' "$dry" | grep -c '^session=')"
[ "$n_dry" -ge 3 ] || { echo "FAIL: (o) restore-all --dry-run 건수 $n_dry < 3"; printf '%s\n' "$dry"; exit 1; }
printf '%s\n' "$dry" | grep -qE '일괄 복구: 창 [0-9]+h' || { echo 'FAIL: (o) dry-run 헤더에 창 표시 없음'; printf '%s\n' "$dry"; exit 1; }
# 실행: impl#3 을 먼저 살려 두어 ⏭ 경로를 만든다
tm new-session -d -s 'ft-fx-impl#3' -x 80 -y 24 'sleep 30'
out="$(dtmm restore-all --yes </dev/null 2>&1 || true)"
# 살아있는 세션(impl#3)은 스캐너 --live 로 목록에서 제외되므로 복구 대상에 나타나면 안 된다
printf '%s\n' "$out" | grep -q '✅ ft-fx-impl#3' && { echo 'FAIL: (o) 살아있는 impl#3 을 다시 복구했다'; printf '%s\n' "$out"; exit 1; }
tm has-session -t '=ft-fx-codex#1' 2>/dev/null || { echo 'FAIL: (o) 일괄 복구 후 ft-fx-codex#1 세션 없음'; printf '%s\n' "$out"; exit 1; }
tm capture-pane -t '=ft-fx-codex#1:' -p | grep -q 'sleep 20' || { echo 'FAIL: (o) codex#1 pane 에 resume_cmd 없음'; exit 1; }
printf '%s\n' "$out" | grep -qE '── 완료: ✅ [0-9]+ +❌ [0-9]+ +/ [0-9]+' || { echo 'FAIL: (o) 집계 줄 없음'; printf '%s\n' "$out"; exit 1; }
tm kill-session -t 'ft-fx-impl#3' 2>/dev/null || true; tm kill-session -t 'ft-fx-codex#1' 2>/dev/null || true
for x in ft-fx-cmd#0 ft-fx-arch#0; do tm kill-session -t "$x" 2>/dev/null || true; done

echo "✅ tmm verify OK"
