#!/usr/bin/env bash
# test_nano_docker_guard_r1418.sh — r1418: 나노 좌석(에이전트 종류 무관) 셸의 docker·podman·nerdctl 이름이 «가드» 로 풀리고,
#   이미지·볼륨 지우기·정리 하위 명령(전역 옵션·compose 꼴 포함)은 늘 REJECT 1줄 + rc 3 · 그 밖 명령은 진짜 바이너리로 argv·stdin·env·출력·rc 그대로.
#   사건: ops 나노(pi 좌석 = Claude 훅 0)가 공유 베이스 이미지 7개를 h 없이 지움 → DB 쓰는 나노 시험이 전부 멈춤(ops #265101 · r1418).
# 계약↔시험: G1~G10(카드 §반례 집합) · 변이 9종(각 계약 위반을 실제로 잡는지).
# 전부 mktemp — 가짜 진짜 docker·podman·nerdctl(호출 기록만 · 실 이미지 손 0) · 가짜 tmux/tmuxc/tmm · 가짜 센서.
#   실 좌석·실 워크트리·실 tmux·실 명부·실 docker 0 · 자기 재호출 0(재진입 표지 불필요).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
GUARD="$BIN/ft-nano-docker-guard.sh"
TMC="$(cd "$REPO/../../tmuxc/core/bin" 2>/dev/null && pwd)/tmuxc"
[ -f "$TMC" ] || TMC="$(cd "$HERE/../../../tmuxc/core/bin" 2>/dev/null && pwd)/tmuxc"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$HERE/lib/fake_resource_env.sh"
fake_resource_env "$T/res" ok
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← $(printf '%s' "$1" | head -c 300)";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
DENY='나노 좌석은 이미지·볼륨 지우기 금지 — h 로 올려라(ft-hil.sh --add)'

echo "== 정적: 문법 · bin·kit 같은 파일"
for f in "$BIN/ft-nano-spawn.sh" "$GUARD" "$TMC"; do
  bash -n "$f" 2>/dev/null && ok "bash -n $(basename "$f")" || bad "bash -n $(basename "$f")"
done
cmp -s "$BIN/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh" && ok "spawn bin·kit cmp 0" || bad "spawn bin·kit 불일치"
cmp -s "$GUARD" "$KIT/ft-nano-docker-guard.sh" && ok "guard bin·kit cmp 0" || bad "guard bin·kit 불일치"

# ── 가짜 «진짜» 바이너리 — argv·stdin 바이트·env·rc 기록만 · 실 이미지 손 0 ──
RD="$T/real"; mkdir -p "$RD"
cat > "$RD/fake-real" <<'EOF'
#!/usr/bin/env bash
n="$(basename -- "$0")"
rec="${FAKE_REC:-/dev/null}"
{ printf '%s argv:' "$n"; printf ' [%s]' "$@"; printf '\n'; } >> "$rec"
printf '%s DOCKER_HOST=%s\n' "$n" "${DOCKER_HOST:-<none>}" >> "$rec"
printf '%s stdin=%s\n' "$n" "$(cat | shasum -a 256 | cut -d' ' -f1)" >> "$rec"
printf 'REAL-OUT %s\n' "$n"
printf 'REAL-ERR %s\n' "$n" >&2
exit "${FAKE_RC:-0}"
EOF
for n in docker podman nerdctl; do cp "$RD/fake-real" "$RD/$n"; chmod 755 "$RD/$n"; done

# 가드 폴더 — spawn 이 만드는 것과 같은 꼴(래퍼 1줄 · 일반 파일)
GD="$T/guard-bin"; mkdir -p "$GD"
for n in docker podman nerdctl; do
  printf '#!/usr/bin/env bash\n# ft-nano-docker-guard 래퍼 (r1418) — 나노 좌석 전용\n' > "$GD/$n"
  printf 'exec %q %s "$@"\n' "$GUARD" "$n" >> "$GD/$n"
  chmod 755 "$GD/$n"
done
rec() { : > "$T/rec"; }
g() {  # g <이름> [인자…] → OUT(2>&1)·RC · 가드 폴더를 PATH «앞» 에 두고 진짜 바이너리는 그다음
  local n="$1"; shift
  OUT="$(env -i HOME="$HOME" PATH="$GD:$RD:/usr/bin:/bin:/usr/sbin:/sbin" FAKE_REC="$T/rec" FAKE_RC="${FAKE_RC:-0}" \
        bash "$GD/$n" "$@" </dev/null 2>&1)"; RC=$?
}
grec() {  # grec <이름> [인자…] → 진짜 바이너리 직접 호출(argv 비교 기준 · 기록 = $T/rec-direct)
  local n="$1"; shift
  env -i HOME="$HOME" PATH="$RD:/usr/bin:/bin" FAKE_REC="$T/rec-direct" FAKE_RC="${FAKE_RC:-0}" bash "$RD/$n" "$@" </dev/null 2>&1
}

echo "== G1 지우기 꼴 = rc 3 + REJECT 1줄 · 진짜 호출 0"
g1_case() {  # g1_case <설명> <이름> [인자…]
  local d="$1"; shift; local n="$1"; shift
  rec; FAKE_RC=0 g "$n" "$@"; local rc="$RC" out="$OUT" nrec
  nrec="$(grep -c . "$T/rec" 2>/dev/null || true)"
  if [ "$rc" = 3 ] && [ "$out" = "$DENY" ] && [ "$nrec" = 0 ]; then ok "G1 $d — rc3 · 1줄 · 진짜 0"
  else bad "G1 $d — rc=$rc 줄='$out' 진짜기록=$nrec"; fi
}
g1_case "docker image rm x"        docker image rm x
g1_case "docker image remove x"    docker image remove x
g1_case "docker rmi x"             docker rmi x
g1_case "podman rmi x"             podman rmi x
g1_case "nerdctl image rm y"       nerdctl image rm y
g1_case "docker buildx prune -f"   docker buildx prune -f
g1_case "docker system prune -af"  docker system prune -af
g1_case "docker volume prune -f"   docker volume prune -f
g1_case "docker image prune"       docker image prune
g1_case "docker container prune"   docker container prune
g1_case "docker builder prune"     docker builder prune

echo "== G2 전역 옵션 뒤에도 같은 판정"
g1_case "--context default image rm x"  docker --context default image rm x
g1_case "-H unix:///var/run/docker.sock rmi x" docker -H unix:///var/run/docker.sock rmi x
g1_case "--config '/tmp/a b' image rm x" docker --config '/tmp/a b' image rm x
g1_case "--log-level=debug rmi x"       docker --log-level=debug rmi x
g1_case "--tls verify 뒤 volume rm"     docker --tlsverify volume rm v

echo "== G3 compose 꼴"
g1_case "compose -f 'a b.yml' down --rmi all" docker compose -f 'a b.yml' down --rmi all
g1_case "compose down --rmi local"      docker compose down --rmi local
g1_case "compose -p p down -v"          docker compose -p p down -v
rec; FAKE_RC=0 g docker compose ps
if [ "$RC" = 0 ] && grep -q 'argv: \[compose\] \[ps\]' "$T/rec"; then ok "G3 compose ps → 진짜로 넘김"; else bad "G3 compose ps rc=$RC $(cat "$T/rec")"; fi
rec; FAKE_RC=0 g docker compose up -d
if [ "$RC" = 0 ] && grep -q 'argv: \[compose\] \[up\] \[-d\]' "$T/rec"; then ok "G3 compose up -d → 진짜로 넘김"; else bad "G3 compose up -d rc=$RC $(cat "$T/rec")"; fi
rec; FAKE_RC=0 g docker compose down
if [ "$RC" = 0 ] && grep -q 'argv: \[compose\] \[down\]' "$T/rec"; then ok "G3 compose down(--rmi·-v 없음) → 진짜로 넘김"; else bad "G3 compose down rc=$RC $(cat "$T/rec")"; fi

echo "== G4 인자 속 글자 = 오탐 0"
rec; FAKE_RC=0 g docker run --rm alpine echo 'image rm'
if [ "$RC" = 0 ] && grep -q "argv: \[run\] \[--rm\] \[alpine\] \[echo\] \[image rm\]" "$T/rec"; then ok "G4 run … 'image rm' → 진짜로 넘김"; else bad "G4 run rc=$RC $(cat "$T/rec")"; fi
rec; FAKE_RC=0 g docker logs rmi-container
if [ "$RC" = 0 ] && grep -q 'argv: \[logs\] \[rmi-container\]' "$T/rec"; then ok "G4 logs rmi-container → 진짜로 넘김"; else bad "G4 logs rc=$RC $(cat "$T/rec")"; fi

echo "== G5 전달 보존 (argv 경계 · stdin · env · 출력 · rc)"
rec; rec_direct="$T/rec-direct"; : > "$rec_direct"
FAKE_RC=0 g docker --config '/tmp/a b' ps; g_rc="$RC"; g_out="$OUT"
FAKE_RC=0 grec docker --config '/tmp/a b' ps >/dev/null 2>&1
if [ "$(grep 'argv:' "$T/rec")" = "$(grep 'argv:' "$rec_direct")" ]; then ok "G5 argv 공백 인자 경계 같음"; else bad "G5 argv 다름: $(grep 'argv:' "$T/rec") vs $(grep 'argv:' "$rec_direct")"; fi
printf 'abc\n' > "$T/stdin.bin"; : > "$T/rec"
env -i HOME="$HOME" PATH="$GD:$RD:/usr/bin:/bin" FAKE_REC="$T/rec" FAKE_RC=0 bash "$GD/docker" load < "$T/stdin.bin" >/dev/null 2>&1
: > "$rec_direct"; env -i HOME="$HOME" PATH="$RD:/usr/bin:/bin" FAKE_REC="$rec_direct" FAKE_RC=0 bash "$RD/docker" load < "$T/stdin.bin" >/dev/null 2>&1
if [ "$(grep 'stdin=' "$T/rec")" = "$(grep 'stdin=' "$rec_direct")" ] && [ "$(grep 'stdin=' "$T/rec")" != "docker stdin=$(shasum -a 256 </dev/null | cut -d' ' -f1)" ]; then ok "G5 stdin 바이트 같음"; else bad "G5 stdin 다름: $(grep 'stdin=' "$T/rec") vs $(grep 'stdin=' "$rec_direct")"; fi
printf 'hello' | env -i HOME="$HOME" PATH="$GD:$RD:/usr/bin:/bin" FAKE_REC="$T/rec2" bash "$GD/docker" exec -i ctr cat >/dev/null 2>&1
expect="docker stdin=$(printf 'hello' | shasum -a 256 | cut -d' ' -f1)"
grep -qx -- "$expect" "$T/rec2" && ok "G5 exec -i stdin 같음(파이프)" || bad "G5 exec -i stdin: $(cat "$T/rec2")"
: > "$T/rec"
OUT="$(env -i HOME="$HOME" PATH="$GD:$RD:/usr/bin:/bin" DOCKER_HOST='tcp://10.0.0.5:2375' FAKE_REC="$T/rec" bash "$GD/docker" ps </dev/null 2>&1)"
grep -qx -- 'docker DOCKER_HOST=tcp://10.0.0.5:2375' "$T/rec" && ok "G5 DOCKER_HOST env 그대로" || bad "G5 DOCKER_HOST: $(cat "$T/rec")"
FAKE_RC=37 g docker ps; rc37="$RC"; out37="$OUT"
env -i HOME="$HOME" PATH="$RD:/usr/bin:/bin" FAKE_RC=37 bash "$RD/docker" ps </dev/null >"$T/direct.out" 2>&1; drc=$?
if [ "$rc37" = 37 ] && [ "$drc" = 37 ] && [ "$out37" = "$(cat "$T/direct.out")" ]; then ok "G5 rc 37 · stdout/stderr 같음"; else bad "G5 rc=$rc37 direct=$drc out 같음=$([ "$out37" = "$(cat "$T/direct.out")" ] && echo y || echo n)"; fi

echo "== G6 진짜 바이너리 없음 = 판정 불가 rc 127"
OUT="$(env -i HOME="$HOME" PATH="$GD:/usr/bin:/bin" bash "$GD/docker" ps </dev/null 2>&1)"; RC=$?
{ [ "$RC" = 127 ] && has "$OUT" "판정 불가 — 진짜 docker 없음" "G6 rc127 + «판정 불가»"; } || bad "G6 rc=$RC [$OUT]"
rec; FAKE_RC=0 g docker ps; [ "$RC" = 0 ] && grep -q 'argv: \[ps\]' "$T/rec" && ok "G6 진짜가 있으면 그대로 넘김(대조)" || bad "G6 대조 실패 rc=$RC $(cat "$T/rec" 2>/dev/null)"

# ── 사본 bin(임시) — 실 키트를 그대로 복사하고 형제 도구 몇 개만 대역으로 바꾼다 ──
BINX="$T/bin"; cp -R "$KIT" "$BINX"; rm -rf "$BINX/__pycache__"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BINX/ft-send-verified.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BINX/ft-agent-ready.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BINX/ft-all-stop.sh"
chmod +x "$BINX/"*.sh 2>/dev/null
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/reclaim-rec.sh"; chmod 755 "$T/reclaim-rec.sh"

# ── 가짜 tmux·tmuxc·tmm (실 tmux·실 tmuxc 0) ──
mkdir -p "$T/fake"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) [ -f "$FAKE_OPENED" ]; exit $?;;
  list-panes) [ -f "$FAKE_OPENED" ] || exit 1; cat "$FAKE_PANES"; exit 0;;
  show-option) echo 1;;
esac
exit 0
EOF
printf '#!/usr/bin/env bash\nprintf "TMUXC %%s\\n" "$*" >> "${FAKE_TMUXC_ARGS:-/dev/null}"; case " $* " in *" --dry-run "*) ;; *) : > "$FAKE_OPENED";; esac\nexit 0\n' > "$T/fake/tmuxc"
printf '#!/bin/sh\nexit 0\n' > "$T/fake/sleep"
cat > "$T/fake/tmm" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = ls ] && [ "${2:-}" = --names ]; then awk '{print $3}' "$FAKE_TMM_LIST" 2>/dev/null; exit 0; fi
cat "$FAKE_TMM_LIST" 2>/dev/null
EOF
printf '#!/usr/bin/env bash\necho "{\\"number\\":1,\\"state\\":\\"OPEN\\",\\"url\\":\\"https://github.com/o/r/issues/1\\"}"\n' > "$T/fake/gh-open"
chmod +x "$T/fake/"*
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
G1L='내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고.'
G2L='하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.'
G3L='메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.'
CLOSE='정본 문구 닫는증거는스무자이상이어야합니다 가나다라마바사'
tl() { : > "$T/tmm.lst"; local n; for n in "$@"; do printf 'harne ● %s IDLE  fabl5·hi 09~14  0m harness-ops\n' "$n" >> "$T/tmm.lst"; done; }
CARDX='design/harness/indices/대기/x.md'
mkfix() {  # mkfix <폴더> — 팀 harness · 접두 byz-harness-nano- 픽스처 카드
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/.fable-team/state" "$d/.fable-team/comm" "$d/.fable-team/bin-harness" \
    "$d/design/harness/indices/대기" "$d/design/harness/indices/진행" "$d/scripts"
  printf '#!/bin/sh\nexit 0\n' > "$d/scripts/real.sh"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$d/.fable-team/state/all-stop.log"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$d/design/TEAMS.md"
  mkdir -p "$d/design/v65"; echo x > "$d/design/v65/SEATBELT-README.md"
  printf '%s\n%s\n%s\n' "$G1L" "$G2L" "$G3L" > "$d/.fable-team/bin-harness/goal-lines.txt"
  printf '# GOAL — harness 제목줄\n\n## 원문 1 머리줄\n> %s\n' "$CLOSE" > "$d/design/harness/GOAL-harness.md"
  printf '# 인덱스: x\n- Issue: #1\n- 제안서: 없음 — 시험용 카드\n- 상태: 대기\n- 선행: 없음\n- 시험 입력: 없음\n- 기준값: 없음 → 대체 축 시험\n- 설치: 없음\n<!-- ledger: design/harness/GOAL-harness.md -->\n\n## 골 원문 (항상 이 3줄)\n%s\n%s\n%s\n\n## 골좌표\n닫는 증거: 「%s」\n\n## 배경\n시험.\n\n## 구현 범위\n1. `scripts/real.sh` 를 고친다.\n\n## 완료 조건\n- 시험 rc=0\n\n## 계약↔시험 대응표\n| 계약 | 시험 |\n|---|---|\n| ① 가드 | ⓐ |\n\n## 상태\n- 대기\n' \
    "$G1L" "$G2L" "$G3L" "$CLOSE" > "$d/$CARDX"
  printf '{"_version":"1.0.0","byz-harness-master-claude#1":{"role":"master"}}\n' > "$d/.fable-team/seats-harness.json"
  printf '{"_version":"1.0.0"}\n' > "$d/.fable-team/seats.json"
  { printf "export FT_SEATS_JSON='%s/.fable-team/seats-harness.json'\n" "$d"
    printf "export FT_NANO_PREFIX=byz-harness-nano-\n"
    printf "export FT_GOAL_LEDGER='design/harness/GOAL-harness.md'\nexport FT_GOAL_LINES_FILE='%s/.fable-team/bin-harness/goal-lines.txt'\n" "$d"
  } > "$d/.fable-team/bin-harness/harness-env.sh"
  git init -q -b main "$d" && git -C "$d" -c user.name=t -c user.email=t@t add -A >/dev/null \
    && git -C "$d" -c user.name=t -c user.email=t@t commit -q -m init && git -C "$d" update-ref refs/remotes/origin/main HEAD
}
sp() {  # sp <픽스처> [인자…] — env -i 격리 · 가짜 tmux/tmuxc/tmm
  local d="$1"; shift
  rm -f "$T/opened" "$T/tmuxc.args"; printf 'byz-harness-nano-x#0|%%1|1\n' > "$T/panes"
  ( cd "$d" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_CARD_FLOW=0 FT_RES_ROOT="$T/res" \
      FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_ROOT="$d" FT_RECLAIM_SH="$T/reclaim-rec.sh" \
      FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" FAKE_TMM_LIST="$T/tmm.lst" \
      FAKE_TMUXC_ARGS="$T/tmuxc.args" FT_DISK_FREE_GIB=50 \
      bash "$BINX/ft-nano-spawn.sh" "$CARDX" "$@" 2>&1 )
}
binx_sp() { local b="$1" d="$2"; shift 2
  ( cd "$d" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_CARD_FLOW=0 FT_RES_ROOT="$T/res" \
      FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_ROOT="$d" FT_RECLAIM_SH="$T/reclaim-rec.sh" \
      FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" FAKE_TMM_LIST="$T/tmm.lst" \
      FAKE_TMUXC_ARGS="$T/tmuxc.args" FT_DISK_FREE_GIB=50 \
      bash "$b/ft-nano-spawn.sh" "$CARDX" "$@" 2>&1 )
}

echo "== G7 spawn 이 가드 폴더를 만들고 실행 줄 PATH 접두를 넘긴다"
D="$T/p7"; mkfix "$D"; tl byz-harness-master-claude#3
o="$(sp "$D")"; rc=$?
WTD="$D/.worktrees/v65-x"; GDS="$WTD/.fable-team/guard-bin"
[ -d "$GDS" ] && ok "G7 가드 폴더 생김: $(basename "$(dirname "$GDS")")/guard-bin" || bad "G7 가드 폴더 없음(rc=$rc) $(printf '%s' "$o" | tail -3)"
miss=""
for n in docker podman nerdctl; do
  f="$GDS/$n"
  [ -f "$f" ] && [ ! -L "$f" ] && [ -x "$f" ] || { miss="$miss $n(파일/모드)"; continue; }
  grep -q 'ft-nano-docker-guard' "$f" || miss="$miss $n(내용)"
done
[ -z "$miss" ] && ok "G7 세 파일 = 일반 파일(심링크 0 · 실행 비트) · 각각 가드 exec" || bad "G7 가드 래퍼 이상:$miss"
grep -qx -- "$(printf 'TMUXC open %s --name byz-harness-nano-x#0 --agent pi --model %s --path-prepend %s --effort high' "$WTD" "$(sed -n 's/.*--model \([^ ]*\) --path-prepend.*/\1/p' <<< "$(grep -o 'TMUXC open.*' "$T/tmuxc.args" | head -1)")" "$GDS")" "$T/tmuxc.args" 2>/dev/null \
  && ok "G7 tmuxc 인자에 --path-prepend <워크트리>/guard-bin" || bad "G7 tmuxc 인자: $(cat "$T/tmuxc.args" 2>/dev/null)"
hasnt "$o" "REJECT docker 가드" "G7 가드 단계 REJECT 0"

# 네 에이전트 각각 — spawn --dry-run 이 tmuxc 로 넘기는 인자
for ag in claude pi opencode codex; do
  Dd="$T/p7-$ag"; mkfix "$Dd"; tl byz-harness-master-claude#3
  case "$ag" in
    claude) extra=(--raise "시험: 계약 G7");;
    codex) extra=(--raise "시험: 계약 G7");;
    opencode) extra=(--model 'deepseek/deepseek-v4.1-flash-free');;
    *) extra=();;
  esac
  rm -f "$T/tmuxc.args"; o="$(sp "$Dd" --agent "$ag" "${extra[@]+"${extra[@]}"}" --dry-run)"; rc=$?
  [ -d "$Dd/.worktrees/v65-x/.fable-team/guard-bin" ] || mkdir -p "$Dd/.worktrees/v65-x/.fable-team/guard-bin"
  if grep -q -- "--path-prepend $Dd/.worktrees/v65-x/.fable-team/guard-bin" "$T/tmuxc.args" 2>/dev/null; then ok "G7 $ag spawn --dry-run → --path-prepend 넘김"
  else bad "G7 $ag --path-prepend 없음(rc=$rc): $(cat "$T/tmuxc.args" 2>/dev/null | head -2)"; fi
done

# 진짜 tmuxc(팩 사본) — command= 줄 접두 · 그 접두를 로그인 셸에서 실행
mkdir -p "$T/home"; printf 'export PATH="/usr/local/bin:$PATH"\n' > "$T/home/.zshenv"; printf 'export PATH="/usr/local/bin:$PATH"\n' > "$T/home/.bash_profile"
cmdf() {  # cmdf <에이전트> [추가 인자…] → command= 줄
  local ag="$1"; shift
  env -i HOME="$T/home" PATH="$RD:/usr/bin:/bin:/usr/sbin:/sbin" bash "$TMC" open "$WTD" --name "g-$ag" --agent "$ag" \
    --model 'claude-sonnet-5[1m]' --path-prepend "$GDS" "$@" --dry-run 2>&1 | sed -n 's/^command=//p'
}
for ag in claude pi opencode codex; do
  case "$ag" in claude) c="$(cmdf "$ag" --ctx 1m --effort high)";; codex) c="$(cmdf "$ag" --effort high)";; pi) c="$(cmdf "$ag" --effort high)";; *) c="$(cmdf "$ag")";; esac
  case "$c" in "PATH=$GDS:\"\$PATH\" "*) ok "G7 $ag command= 앞머리 = PATH=<가드 폴더>:\"\$PATH\"";; *) bad "G7 $ag command= [$c]";; esac
  pre="${c%% *}"   # PATH=<가드 폴더>:"$PATH"
  for sh in bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || { ok "G7 $ag $sh 없음 — 건너뜀"; continue; }
    got="$(env -i HOME="$T/home" PATH="$RD:/usr/bin:/bin:/usr/sbin:/sbin" "$sh" -lc "$pre"$'\n''command -v docker podman nerdctl' 2>&1 | tr '\n' ' ')"
    if [ "$got" = "$GDS/docker $GDS/podman $GDS/nerdctl " ]; then ok "G7 $ag $sh -lc → command -v 셋 다 가드 폴더"; else bad "G7 $ag $sh → [$got]"; fi
  done
done

echo "== G8 사건 꼴 — pi 셸의 for 반복 안 이름 지정 지우기 2회"
PICMD="$(cmdf pi --effort high)"; PIPRE="${PICMD%% *}"
rec
LOOPOUT="$(env -i HOME="$T/home" PATH="$RD:/usr/bin:/bin:/usr/sbin:/sbin" FAKE_REC="$T/rec" zsh -lc \
  "$PIPRE"$'\n''for i in 1 2; do docker image rm "img$i"; echo "rc=$?"; done' 2>&1)"
{ [ "$(printf '%s\n' "$LOOPOUT" | grep -c '^rc=3$')" = 2 ] && [ "$(grep -c . "$T/rec" 2>/dev/null || true)" = 0 ]; } \
  && ok "G8 for 반복 2회 매회 rc 3 · 진짜 호출 0" || bad "G8 [$LOOPOUT] rec=$(cat "$T/rec" 2>/dev/null)"

echo "== G9 가드 폴더를 못 쓰면 좌석 0 · 재사용 워크트리에서도 다시 씀"
D9="$T/p9"; mkfix "$D9"; tl byz-harness-master-claude#3
mkdir -p "$D9/.worktrees/v65-x/.fable-team"; printf 'not a dir\n' > "$D9/.worktrees/v65-x/.fable-team/guard-bin"
# worktree 폴더가 있으면 spawn 은 «재사용» 갈래 — 브랜치 일치 필요
git -C "$D9" worktree add -q -b nano/x "$D9/.worktrees/v65-x" main 2>/dev/null
printf '{"branch":"nano/x","base":"main","base_sha":"%s","created_at":"x","purpose":"nano"}\n' "$(git -C "$D9" rev-parse --short main)" > "$D9/.worktrees/v65-x/.worktree-info.json"
rm -f "$T/tmuxc.args"
o="$(sp "$D9")"; rc=$?
{ [ "$rc" != 0 ] && has "$o" "REJECT docker 가드" "G9 쓰기 실패 → spawn REJECT rc=$rc"; } || bad "G9 rc=$rc [$o]"
[ ! -s "$T/tmuxc.args" ] && ok "G9 좌석 개설 0(tmuxc open 호출 0)" || bad "G9 tmuxc 를 불렀다: $(cat "$T/tmuxc.args" 2>/dev/null)"
# 재사용 갈래에서도 다시 쓴다 — 자리에서 일반 파일을 치우고 다시
rm -f "$D9/.worktrees/v65-x/.fable-team/guard-bin"
o="$(sp "$D9")"; rc=$?
miss=""
for n in docker podman nerdctl; do [ -f "$D9/.worktrees/v65-x/.fable-team/guard-bin/$n" ] || miss="$miss $n"; done
[ -z "$miss" ] && ok "G9 재사용 워크트리에서 가드 폴더 다시 씀(rc=$rc)" || bad "G9 재사용 갈래 가드 없음:$miss rc=$rc [$(printf '%s' "$o" | tail -2)]"

echo "== G10 tmuxc 새 옵션 — 줄 때만 · 잘못된 값은 die"
base="$(env -i HOME="$T/home" PATH="$RD:/usr/bin:/bin" bash "$TMC" open "$WTD" --name g10 --agent pi --model 'm1' --effort high --dry-run 2>&1 | sed -n 's/^command=//p')"
case "$base" in "PATH="*) bad "G10 옵션 없이 접두가 붙었다: $base";; "") bad "G10 기준 command= 0";; *) ok "G10 --path-prepend 없으면 command= 지금과 같음(접두 0)";; esac
OUT="$(env -i HOME="$T/home" PATH="$RD:/usr/bin:/bin" bash "$TMC" open "$WTD" --name g10b --agent pi --model m1 --path-prepend rel/dir --dry-run 2>&1)"; RC=$?
{ [ "$RC" != 0 ] && has "$OUT" "--path-prepend 는 절대경로만" "G10 상대경로 → die 1줄"; } || bad "G10 상대경로 rc=$RC [$OUT]"
OUT="$(env -i HOME="$T/home" PATH="$RD:/usr/bin:/bin" bash "$TMC" open "$WTD" --name g10c --agent pi --model m1 --path-prepend "$T/nope" --dry-run 2>&1)"; RC=$?
{ [ "$RC" != 0 ] && has "$OUT" "--path-prepend 폴더 없음" "G10 없는 폴더 → die 1줄"; } || bad "G10 없는 폴더 rc=$RC [$OUT]"
OUT="$(env -i HOME="$T/home" PATH="$RD:/usr/bin:/bin" bash "$TMC" open "$WTD" --host 127.0.0.1 --name g10d --agent pi --model m1 --path-prepend "$GDS" --dry-run 2>&1)"; RC=$?
{ [ "$RC" != 0 ] && has "$OUT" "--path-prepend 는 원격 미지원" "G10 원격 open + 옵션 → die «원격 미지원»"; } || bad "G10 원격 rc=$RC [$OUT]"

echo "== 변이 9종 — 각 계약 위반을 실제로 잡는가"
mk_mut() {  # mk_mut <폴더> <파일> <old> <new>
  local dir="$1" f="$2" old="$3" new="$4"
  rm -rf "$dir"; mkdir -p "$dir"
  python3 - "$BIN/$f" "$dir/$f" "$old" "$new" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old[:80]
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  chmod 755 "$dir/$f" 2>/dev/null || true
}
mut_run() {  # mut_run <폴더> <이름> [인자…] → 가드 폴더의 래퍼가 변이본 가드를 부르게 임시 교체
  local dir="$1"; shift
  local mg="$T/mguard"; rm -rf "$mg"; mkdir -p "$mg"
  local n
  for n in docker podman nerdctl; do
    printf '#!/usr/bin/env bash\n# ft-nano-docker-guard 래퍼 (변이 시험)\n' > "$mg/$n"; printf 'exec %q %s "$@"\n' "$dir/ft-nano-docker-guard.sh" "$n" >> "$mg/$n"; chmod 755 "$mg/$n"
  done
  local name="$1"; shift
  OUT="$(env -i HOME="$HOME" PATH="$mg:$RD:/usr/bin:/bin" FAKE_REC="$T/rec-m" FAKE_RC=0 bash "$mg/$name" "$@" </dev/null 2>&1)"; RC=$?
}
: > "$T/rec-m"
# 변이① 지우기 판정 삭제 → G1 FAIL
mk_mut "$T/m1" ft-nano-docker-guard.sh '_sub_deny() {   # $1 = 하위 명령' '_sub_deny() { return 1;   # 변이①: 지우기 판정 삭제
  # $1 = 하위 명령' && bash -n "$T/m1/ft-nano-docker-guard.sh" && ok "변이① bash -n" || bad "변이① bash -n"
mut_run "$T/m1" docker rmi x
{ [ "$RC" = 0 ] && ! [[ "$OUT" == *"$DENY"* ]]; } && ok "변이① 지우기 판정 삭제 = G1 위반 검출(기준판 FAIL)" || bad "변이① 계약을 안 깼다 rc=$RC"
# 변이② 전역 옵션 소비 삭제 → G2 FAIL
mk_mut "$T/m2" ft-nano-docker-guard.sh '    -H|--host|-c|--context|--config|-l|--log-level|--tlscacert|--tlscert|--tlskey) shift; [ "$#" -gt 0 ] && shift ;;' '    *) shift ;;   # 변이②' && bash -n "$T/m2/ft-nano-docker-guard.sh" && ok "변이② bash -n" || bad "변이② bash -n"
mut_run "$T/m2" docker --context default image rm x
{ [ "$RC" = 0 ] && ! [[ "$OUT" == *"$DENY"* ]]; } && ok "변이② 전역 옵션 소비 삭제 = G2 위반 검출" || bad "변이② 계약을 안 깼다 rc=$RC [$OUT]"
# 변이③ compose --rmi 판독 삭제 → G3 FAIL
mk_mut "$T/m3" ft-nano-docker-guard.sh '      --rmi|--rmi=*|-v|--volumes) return 0 ;;' '      --rmi|--rmi=*|-v|--volumes) : ;;   # 변이③' && bash -n "$T/m3/ft-nano-docker-guard.sh" && ok "변이③ bash -n" || bad "변이③ bash -n"
mut_run "$T/m3" docker compose down --rmi all
{ [ "$RC" = 0 ] && ! [[ "$OUT" == *"$DENY"* ]]; } && ok "변이③ compose --rmi 판독 삭제 = G3 위반 검출" || bad "변이③ 계약을 안 깼다 rc=$RC [$OUT]"
# 변이④ 첫 낱말 아닌 글자 대조(인자 속 «image rm» 도 막음) → G4 FAIL
mk_mut "$T/m4" ft-nano-docker-guard.sh '# ★첫 낱말만 본다★' 'case "$ALL" in *"image rm"*|*"rmi"*) deny=1;; esac   # 변이④
# ★첫 낱말만 본다★' && bash -n "$T/m4/ft-nano-docker-guard.sh" && ok "변이④ bash -n" || bad "변이④ bash -n"
mut_run "$T/m4" docker run --rm alpine echo 'image rm'
{ [[ "$OUT" == *"$DENY"* ]] || [ "$RC" = 3 ]; } && ok "변이④ 인자 속 글자 대조 = G4 위반 검출" || bad "변이④ 계약을 안 깼다 rc=$RC"
# 변이⑤ exec 대신 출력 캡처·rc 고정 → G5 FAIL
mk_mut "$T/m5" ft-nano-docker-guard.sh 'exec "$real" "${orig[@]}"' '"$real" "${orig[@]}" >/dev/null 2>&1; exit 0   # 변이⑤' && bash -n "$T/m5/ft-nano-docker-guard.sh" && ok "변이⑤ bash -n" || bad "변이⑤ bash -n"
: > "$T/rec-m"; mut_run "$T/m5" docker ps; rc5="$RC"
env -i HOME="$HOME" PATH="$T/mguard:$RD:/usr/bin:/bin" FAKE_RC=37 FAKE_REC="$T/rec-m" bash "$T/mguard/docker" ps </dev/null >/dev/null 2>&1; rc5b=$?
{ [ "$rc5b" = 0 ] || [ -z "$OUT" ]; } && ok "변이⑤ exec 캡처 = G5 위반 검출(출력·rc 안 그대로) rc=$rc5b" || bad "변이⑤ 계약을 안 깼다"
# 변이⑥ 실행 줄 PATH 삭제(-e env 만) → G7·G8 FAIL
rm -rf "$T/m6"; mkdir -p "$T/m6"; python3 - "$BIN/ft-nano-spawn.sh" "$T/m6/ft-nano-spawn.sh" <<'PY'
import sys
src, dst = sys.argv[1:3]
s = open(src, encoding="utf-8").read()
old = 'OPEN+=(--path-prepend "$WTDIR/.fable-team/guard-bin")'
assert old in s
open(dst, "w", encoding="utf-8").write(s.replace(old, ":   # 변이⑥: 실행 줄 PATH 삭제", 1))
PY
rm -rf "$T/bin6"; cp -R "$BINX" "$T/bin6"; cp "$T/m6/ft-nano-spawn.sh" "$T/bin6/ft-nano-spawn.sh"
bash -n "$T/bin6/ft-nano-spawn.sh" && ok "변이⑥ bash -n" || bad "변이⑥ bash -n"
D6="$T/p6"; mkfix "$D6"; tl byz-harness-master-claude#3; rm -f "$T/tmuxc.args" "$T/opened"
o="$(binx_sp "$T/bin6" "$D6" --dry-run)"; rc=$?
grep -q -- '--path-prepend' "$T/tmuxc.args" 2>/dev/null && bad "변이⑥ 계약을 안 깼다" || ok "변이⑥ 실행 줄 PATH 삭제 = G7 위반 검출"
# 변이⑦ pi 분기만 PATH 빠짐 → G7·G8 FAIL
rm -rf "$T/m7"; mkdir -p "$T/m7"; python3 - "$BIN/ft-nano-spawn.sh" "$T/m7/ft-nano-spawn.sh" <<'PY'
import sys
src, dst = sys.argv[1:3]
s = open(src, encoding="utf-8").read()
old = 'OPEN+=(--path-prepend "$WTDIR/.fable-team/guard-bin")'
assert old in s
new = '[ "$AGENT" = pi ] || OPEN+=(--path-prepend "$WTDIR/.fable-team/guard-bin")   # 변이⑦: pi 만 빠짐'
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
rm -rf "$T/bin7"; cp -R "$BINX" "$T/bin7"; cp "$T/m7/ft-nano-spawn.sh" "$T/bin7/ft-nano-spawn.sh"
bash -n "$T/bin7/ft-nano-spawn.sh" && ok "변이⑦ bash -n" || bad "변이⑦ bash -n"
D7="$T/p7b"; mkfix "$D7"; tl byz-harness-master-claude#3; rm -f "$T/tmuxc.args"
o="$(binx_sp "$T/bin7" "$D7" --dry-run)"; rc=$?
grep -q -- '--path-prepend' "$T/tmuxc.args" 2>/dev/null && bad "변이⑦ 계약을 안 깼다" || ok "변이⑦ pi 분기만 PATH 빠짐 = G7 위반 검출(pi 가 기본)"
# 변이⑧ 쓰기 실패를 WARN 으로 넘김 → G9 FAIL
rm -rf "$T/m8"; mkdir -p "$T/m8"; python3 - "$BIN/ft-nano-spawn.sh" "$T/m8/ft-nano-spawn.sh" <<'PY'
import sys
src, dst = sys.argv[1:3]
s = open(src, encoding="utf-8").read()
old = 'nano_docker_guard_install "$WTDIR" || exit 1'
assert old in s
open(dst, "w", encoding="utf-8").write(s.replace(old, 'nano_docker_guard_install "$WTDIR" || echo "WARN 가드 실패(변이⑧)" >&2', 1))
PY
rm -rf "$T/bin8"; cp -R "$BINX" "$T/bin8"; cp "$T/m8/ft-nano-spawn.sh" "$T/bin8/ft-nano-spawn.sh"
bash -n "$T/bin8/ft-nano-spawn.sh" && ok "변이⑧ bash -n" || bad "변이⑧ bash -n"
D8="$T/p8"; mkfix "$D8"; tl byz-harness-master-claude#3
mkdir -p "$D8/.worktrees/v65-x/.fable-team"; printf 'not a dir\n' > "$D8/.worktrees/v65-x/.fable-team/guard-bin"
git -C "$D8" worktree add -q -b nano/x "$D8/.worktrees/v65-x" main 2>/dev/null
printf '{"branch":"nano/x","base":"main","base_sha":"%s","created_at":"x","purpose":"nano"}\n' "$(git -C "$D8" rev-parse --short main)" > "$D8/.worktrees/v65-x/.worktree-info.json"
rm -f "$T/tmuxc.args"; rm -f "$T/opened"
rm -f "$T/tmuxc.args" "$T/opened"; o="$(binx_sp "$T/bin8" "$D8")"; rc=$?
[ -s "$T/tmuxc.args" ] && ok "변이⑧ 쓰기 실패 WARN = G9 위반 검출(좌석 개설 시도 rc=$rc)" || bad "변이⑧ 계약을 안 깼다(여전히 좌석 0)"
# 변이⑨ 옵션 없을 때도 접두를 붙임 → G10 FAIL
rm -rf "$T/m9"; mkdir -p "$T/m9"; cp -R "$(cd "$(dirname "$TMC")/.." && pwd)" "$T/m9/core"
python3 - "$TMC" "$T/m9/core/bin/tmuxc" <<'PY'
import sys
src, dst = sys.argv[1:3]
s = open(src, encoding="utf-8").read()
old = '  [[ -z "$path_prepend" ]] || run_cmd="PATH=${path_prepend}:\\"\\$PATH\\" ${run_cmd}"'
assert old in s, "변이⑨ 대상 없음"
open(dst, "w", encoding="utf-8").write(s.replace(old, '  run_cmd="PATH=${path_prepend}:\\"\\$PATH\\" ${run_cmd}"   # 변이⑨', 1))
PY
chmod 755 "$T/m9/core/bin/tmuxc"; bash -n "$T/m9/core/bin/tmuxc" && ok "변이⑨ bash -n" || bad "변이⑨ bash -n"
o9="$(env -i HOME="$T/home" PATH="$RD:/usr/bin:/bin" bash "$T/m9/core/bin/tmuxc" open "$WTD" --name g9 --agent pi --model m1 --effort high --dry-run 2>&1)"; r9=$?
c9="$(printf '%s\n' "$o9" | sed -n 's/^command=//p')"
case "$c9" in "PATH="*) ok "변이⑨ 옵션 없이도 접두 = G10 위반 검출";; *) bad "변이⑨ 계약을 안 깼다(rc=$r9): $(printf '%s' "$o9" | head -3)";; esac

echo "== 기준판(HEAD) FAIL — 수정 전 코드는 같은 시험에서 G1·G7·G8·G10 이 실패해야 한다"
BASE="$T/base"; rm -rf "$BASE"; mkdir -p "$BASE"
ROOTG="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)"
# r1132: 기준판은 «고치기 직전 main 의 고정 40hex sha» — 떠다니는 이름(origin/main)을 쓰지 않는다
BASE_SHA="${R1418_BASE_SHA:-1bd4edb325530e535b4072c9ffef9649ed854acc}"
for f in ft-nano-docker-guard.sh ft-nano-spawn.sh; do git -C "$ROOTG" show "$BASE_SHA:feature-pack/fable-team/harness/bin/$f" > "$BASE/$f" 2>/dev/null || : ; done
git -C "$ROOTG" show "$BASE_SHA:feature-pack/tmuxc/core/bin/tmuxc" > "$BASE/tmuxc" 2>/dev/null || :
[ -s "$BASE/ft-nano-docker-guard.sh" ] && ok "기준판 가드 있음(뜻밖 — 카드 신설 파일)" || ok "기준판 가드 없음(신설 = G1·G2·G3·G5·G6 실패가 맞다)"
grep -q -- '--path-prepend' "$BASE/ft-nano-spawn.sh" 2>/dev/null && bad "기준판 spawn 에 이미 --path-prepend" || ok "기준판 spawn 에 --path-prepend 없음 = G7·G8 FAIL"
grep -q -- 'path_prepend' "$BASE/tmuxc" 2>/dev/null && bad "기준판 tmuxc 에 이미 옵션" || ok "기준판 tmuxc 에 옵션 없음 = G10 FAIL"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
