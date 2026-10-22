#!/usr/bin/env bash
# test_agent_probe_claude_path.sh — r736(BYZ 2597): 세션 저장 판정 session_agent_probe 의 결함 2개
#   ① claude 를 실경로(~/.local/share/claude/versions/<버전>)로 띄우면 basename 이 «2.1.308» 이라
#      에이전트 미검출 → cmd_save 가 agent=shell 로 적고 restore 가 그 좌석을 건너뛴다.
#   ② 뒤 후손(도구 하위 프로세스 = pi 등)이 앞서 찾은 종류를 덮어쓴다 → agent=pi.
#   픽스처 = ps/pgrep/tmux 스텁(프로세스 표 파일) · 실 tmux 서버 0 · 스냅샷 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TMUXC="$HERE/../core/bin/tmuxc"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail + 1)); }

# ---------- 스텁: ps · pgrep · tmux (실 프로세스/실 tmux 서버 없이 결정적 재현) ----------
cat > "$T/bin/ps" <<'SH'
#!/usr/bin/env bash
pid="${!#}"
awk -F'|' -v p="$pid" '$1==p {print $2; f=1} END{exit !f}' "$FAKE_PROCS"
SH
cat > "$T/bin/pgrep" <<'SH'
#!/usr/bin/env bash
pid="${!#}"
awk -v p="$pid" '$1==p {for (i=2;i<=NF;i++) print $i; f=1} END{exit !f}' "$FAKE_KIDS"
SH
cat > "$T/bin/tmux" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_TMUX_LOG:-/dev/null}"
case "$1" in
  show-environment) exit 1 ;;
  list-panes) printf '%s\n' "${FAKE_PANE_PID:-0}" ;;
  *) exit 0 ;;
esac
SH
chmod +x "$T/bin/ps" "$T/bin/pgrep" "$T/bin/tmux"

# ---------- 함수 추출 + 픽스처 실행 ----------
extract() {
  sed -n '/^pane_descendant_pids()/,/^}/p; /^session_agent_probe()/,/^}/p; /^snapshot_resume_cmd()/,/^}/p' "$1" > "$2"
}
run_probe() { # $1=함수정의 파일 $2=픽스처 폴더 → agent/rc/resume_cmd 줄
  env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" \
    FAKE_PROCS="$2/procs" FAKE_KIDS="$2/kids" FAKE_PANE_PID="$(cat "$2/pane_pid")" \
    FAKE_TMUX_LOG="$T/tmux.log" \
    bash -c '
      source "$1"
      out="$(session_agent_probe FIX 2>/dev/null)"; rc=$?
      printf "%s\n" "$out"
      printf "rc=%s\n" "$rc"
      if [ -n "$out" ]; then
        ag="$(printf "%s\n" "$out" | sed -n "s/^agent=//p")"
        md="$(printf "%s\n" "$out" | sed -n "s/^model=//p")"
        ef="$(printf "%s\n" "$out" | sed -n "s/^effort=//p")"
        sd="$(printf "%s\n" "$out" | sed -n "s/^sid=//p")"
        printf "resume_cmd=%s\n" "$(snapshot_resume_cmd "$ag" FIX "$md" "$ef" "$sd")"
      fi
    ' _ "$1"
}

# 픽스처 ⓐ — claude 실경로(argv 에 --resume uuid --model) · 후손 1개
A="$T/a"; mkdir -p "$A"; echo 100 > "$A/pane_pid"
cat > "$A/procs" <<'P'
100|zsh
200|/Users/tester/.local/share/claude/versions/2.1.308 --resume 11111111-2222-3333-4444-555555555555 --model claude-sonnet-5[1m]
P
printf '100 200\n' > "$A/kids"

# 픽스처 ⓑ — 같은 실경로 claude(모델만 · sid 없음) + 뒤 후손 pi 하위 프로세스(sid 없음)
B="$T/b"; mkdir -p "$B"; echo 100 > "$B/pane_pid"
cat > "$B/procs" <<'P'
100|zsh
200|/Users/tester/.local/share/claude/versions/2.1.308 --model claude-sonnet-5
300|node /usr/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js
P
printf '100 200\n200 300\n' > "$B/kids"

# 픽스처 ⓓ — 진짜 셸 좌석(후손에 claude·codex·pi·cmd 0)
D="$T/d"; mkdir -p "$D"; echo 100 > "$D/pane_pid"
printf '100|zsh\n' > "$D/procs"; printf '100\n' > "$D/kids"

# 픽스처 ⓔ-E — claude 좌석(model 만 · sid 없음) + pi 후손(--model deepseek/flash --session X):
#   다른 엔진의 model·sid 가 섞이면 restore 가 «엉뚱한 대화»를 claude --resume X 로 되살린다(r736 반송1)
E="$T/e"; mkdir -p "$E"; echo 100 > "$E/pane_pid"
cat > "$E/procs" <<'P'
100|zsh
200|/Users/tester/.local/share/claude/versions/2.1.308 --model claude-sonnet-5
300|node /usr/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js --model deepseek/flash --session X
P
printf '100 200\n200 300\n' > "$E/kids"

extract "$TMUXC" "$T/defs.sh"

# ⓐ 실경로 claude 판정 (빨강 → 초록)
out="$(run_probe "$T/defs.sh" "$A")"
printf '%s\n' "$out" | grep -qx 'agent=claude' \
  && ok "ⓐ 실경로 claude(.../claude/versions/2.1.308) → agent=claude" \
  || bad "ⓐ 실경로 claude 미검출: $(printf '%s' "$out" | tr '\n' ' ')"
printf '%s\n' "$out" | grep -qx 'model=claude-sonnet-5\[1m\]' \
  && ok "ⓐ model 보존" || bad "ⓐ model: $(printf '%s' "$out" | tr '\n' ' ')"
printf '%s\n' "$out" | grep -qx 'sid=11111111-2222-3333-4444-555555555555' \
  && ok "ⓐ sid 보존" || bad "ⓐ sid: $(printf '%s' "$out" | tr '\n' ' ')"

# ⓑ 첫 매칭(종류) 유지 — 뒤 후손이 덮어쓰지 않는다 (빨강 → 초록)
out="$(run_probe "$T/defs.sh" "$B")"
printf '%s\n' "$out" | grep -qx 'agent=claude' \
  && ok "ⓑ 뒤 후손 pi 가 종류를 덮어쓰지 않는다(agent=claude)" \
  || bad "ⓑ 뒤 후손 덮어씀: $(printf '%s' "$out" | tr '\n' ' ')"

# ⓒ 후판 둘 다 agent=claude · resume_cmd 비지 않음
for c in "$A:ⓒ-a" "$B:ⓒ-b"; do
  dir="${c%%:*}"; tag="${c##*:}"
  out="$(run_probe "$T/defs.sh" "$dir")"
  rc="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
  cmd="$(printf '%s\n' "$out" | sed -n 's/^resume_cmd=//p')"
  [ "$rc" = 0 ] && [ -n "$cmd" ] && ok "$tag resume_cmd 비지 않음" \
    || bad "$tag resume_cmd rc=$rc cmd='$cmd'"
  case "$cmd" in
    *.headroom/claude-hr.sh*) ok "$tag claude 복구 커맨드 합성" ;;
    *) bad "$tag 복구 커맨드: $cmd" ;;
  esac
done

# ⓔ-E 다른 엔진 후손의 model/sid 는 안 섞는다 (빨강 → 초록)
out="$(run_probe "$T/defs.sh" "$E")"
printf '%s\n' "$out" | grep -qx 'agent=claude' \
  && ok "ⓔ-E claude 좌석 + pi 후손 → agent=claude" \
  || bad "ⓔ-E agent: $(printf '%s' "$out" | tr '\n' ' ')"
printf '%s\n' "$out" | grep -qx 'model=claude-sonnet-5' \
  && ok "ⓔ-E model 은 claude 후손 것만" \
  || bad "ⓔ-E 다른 엔진 model 섞임: $(printf '%s' "$out" | tr '\n' ' ')"
printf '%s\n' "$out" | grep -q '^sid=' \
  && bad "ⓔ-E 다른 엔진 sid 섞임: $(printf '%s' "$out" | tr '\n' ' ')" \
  || ok "ⓔ-E sid 빈칸(다른 엔진 --session X 안 섞임)"
cmd="$(printf '%s\n' "$out" | sed -n 's/^resume_cmd=//p')"
case "$cmd" in
  *'--resume'*) bad "ⓔ-E resume_cmd 에 엉뚱한 --resume: $cmd" ;;
  *.headroom/claude-hr.sh*'--model "claude-sonnet-5"'*) ok "ⓔ-E resume_cmd = claude 모델만(--resume 0)" ;;
  *) bad "ⓔ-E resume_cmd: $cmd" ;;
esac

# ⓓ 진짜 셸 좌석 — 회귀 0 (미검출 = cmd_save 가 agent=shell 로 적는다)
out="$(run_probe "$T/defs.sh" "$D")"
printf '%s\n' "$out" | grep -qx 'rc=1' \
  && ok "ⓓ 순수 셸 좌석은 지금처럼 미검출(rc=1 → agent=shell)" \
  || bad "ⓓ 셸 좌석 오검출: $(printf '%s' "$out" | tr '\n' ' ')"

# ⓕ 변이 — 고침 ①·② 를 각각 되돌리면 ⓐ·ⓑ 가 다시 빨강
sed 's|if \[\[ -z "\$kind" && "\$t" == \*/claude/versions/\* \]\]; then|if false; then|' \
  "$TMUXC" > "$T/mut1"   # 결함 ① 되돌림
extract "$T/mut1" "$T/defs-mut1.sh"
printf '%s\n' "$(run_probe "$T/defs-mut1.sh" "$A")" | grep -qx 'agent=claude' \
  && bad "ⓕ① 변이(실경로 되돌림)인데 ⓐ 초록 — 시험이 결함을 안 잡는다" \
  || ok "ⓕ① 실경로 고침 되돌림 → ⓐ 다시 빨강"

sed 's|if \[\[ -z "\$agent" \]\]; then agent="\$kind"; fi|agent="$kind"|' \
  "$TMUXC" > "$T/mut2"   # 결함 ② 되돌림
extract "$T/mut2" "$T/defs-mut2.sh"
printf '%s\n' "$(run_probe "$T/defs-mut2.sh" "$B")" | grep -qx 'agent=claude' \
  && bad "ⓕ② 변이(덮어쓰기 되돌림)인데 ⓑ 초록 — 시험이 결함을 안 잡는다" \
  || ok "ⓕ② 덮어쓰기 고침 되돌림 → ⓑ 다시 빨강"

# ⓕ③ 변이 — «같은 종류에서만 model/sid 보충» 조건을 없애면 ⓔ-E 가 다시 빨강
sed 's|if \[\[ "\$kind" == "\$agent" \]\]; then|if true; then|' \
  "$TMUXC" > "$T/mut3"
extract "$T/mut3" "$T/defs-mut3.sh"
printf '%s\n' "$(run_probe "$T/defs-mut3.sh" "$E")" | grep -qx 'model=claude-sonnet-5' \
  && bad "ⓕ③ 변이(같은 종류 조건 제거)인데 ⓔ-E 초록 — 시험이 결함을 안 잡는다" \
  || ok "ⓕ③ 같은 종류 조건 되돌림 → ⓔ-E 다시 빨강"

# ⓖ 격리 — 실 tmux 서버 0 · new-session 호출 0 · 스냅샷 쓰기 0
mkdir -p "$T/tmx"   # tmux 는 TMUX_TMPDIR 디렉터리가 없으면 기본 소켓으로 되돌아간다(실측)
env -u TMUX TMUX_TMPDIR="$T/tmx" tmux list-sessions >/dev/null 2>&1 \
  && bad "ⓖ 실 tmux 서버가 생겼다" || ok "ⓖ 실 tmux 서버 0"
grep -q 'new-session' "$T/tmux.log" 2>/dev/null \
  && bad "ⓖ new-session 호출됨: $(cat "$T/tmux.log")" || ok "ⓖ tmux 쓰기 호출 0"
[ -d "$T/home/.tmuxc/snapshots" ] \
  && bad "ⓖ 스냅샷 디렉터리 생성됨" || ok "ⓖ 스냅샷 쓰기 0"

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAILED $fail"; exit 1
