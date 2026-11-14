#!/usr/bin/env bash
# test_nano_spawn_help_usage_r1423.sh — r1423: ft-nano-spawn.sh 첫 인자가 «-» 로 시작하면(--help · -h · --dry-run 포함)
#   usage 1줄(stderr) + rc 2 로 끝나고, 원장·대기열·명부·워크트리·tmux 를 읽거나 쓰는 흐름에 들어가지 않는다.
#   실사건(knowledge #265839 · arch#106): «ft-nano-spawn.sh --help» 가 IDX=--help 로 배정 원장·대기열 판정까지 진행.
# 전부 mktemp — 임시 저장소·가짜 tmux/tmuxc/tmm·git/python3/jq 호출 기록 대역. 실 좌석·실 워크트리·실 tmux·실 명부 0.
#   U1 옵션 꼴 첫 인자 → rc2 · usage 1줄 · 가짜 루트 파일 mtime 불변 · 외부 도구 호출 0
#   U2 인자 0개 → rc2 · usage 1줄(지금과 같음) · U3 카드 경로 + --dry-run → 옵션 판독 무변경(rc0 · 회신 대상 줄)
#   변이 ① 첫 인자 검사 삭제 → U1 FAIL · ② 검사를 2.0 전환 게이트(원장 읽기) 뒤로 → U1(호출) FAIL
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'tmux_isolate_end; rm -rf "$T"' EXIT
. "$HERE/lib/tmux_isolate.sh"
. "$HERE/lib/fake_resource_env.sh"
fake_resource_env "$T/res" ok
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
G1='내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고.'
G2='하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.'
G3='메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.'
CLOSE='정본 문구 닫는증거는스무자이상이어야합니다 가나다라마바사'
PY="$(command -v python3)"

# ── 가짜 도구(PATH 앞) — tmux·tmuxc·tmm 은 기록만 · git·python3·jq 는 기록 뒤 실물로 넘긴다 ──
mkdir -p "$T/fake"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
echo "tmux $*" >> "$FAKE_CALLS"
case "$1" in
  has-session) [ -f "$FAKE_OPENED" ]; exit $?;;
  list-panes) [ -f "$FAKE_OPENED" ] || exit 1; echo 'byz-harness-nano-x#0|%1|1'; exit 0;;
  show-option) echo 1;;
esac
exit 0
EOF
printf '#!/usr/bin/env bash\necho "TMUXC $*" >> "$FAKE_CALLS"; echo "TMUXC $*"; case " $* " in *" --dry-run "*) ;; *) : > "$FAKE_OPENED";; esac\nexit 0\n' > "$T/fake/tmuxc"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${FAKE_TMM_ARGS:-/dev/null}"\necho "tmm $*" >> "$FAKE_CALLS"\n[ "${1:-}" = ls ] && [ "${2:-}" = --names ] && echo byz-harness-master-claude#3\nexit 0\n' > "$T/fake/tmm"
for t in git python3 jq; do r="$(command -v "$t" || echo /usr/bin/false)"
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$FAKE_CALLS"\nexec "%s" "$@"\n' "$t" "$r" > "$T/fake/$t"; done
printf '#!/bin/sh\nexit 0\n' > "$T/fake/sleep"
printf '#!/usr/bin/env bash\necho "{\\"number\\":1,\\"state\\":\\"OPEN\\",\\"url\\":\\"https://github.com/o/r/issues/1\\"}"\n' > "$T/fake/gh-open"
printf '#!/bin/sh\necho "RECLAIMED 0"\n' > "$T/reclaim.sh"
chmod +x "$T/fake/"* "$T/reclaim.sh"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"

BINX="$T/bin"; cp -R "$KIT" "$BINX"; rm -rf "$BINX/__pycache__"
for s in ft-send-verified.sh ft-agent-ready.sh ft-all-stop.sh; do printf '#!/usr/bin/env bash\nexit 0\n' > "$BINX/$s"; done
chmod +x "$BINX/"*.sh

CARDX="design/harness/indices/대기/x.md"
mkfix() {  # mkfix <디렉터리> — harness 팀 카드·원장·명부·팀 env (r1415 시험과 같은 꼴)
  local d="$1" tm=harness
  rm -rf "$d"; mkdir -p "$d/.fable-team/state" "$d/.fable-team/comm" "$d/.fable-team/bin-$tm" \
    "$d/design/$tm/indices/대기" "$d/design/$tm/indices/진행" "$d/scripts"
  printf '#!/bin/sh\nexit 0\n' > "$d/scripts/real.sh"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$d/.fable-team/state/all-stop.log"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| %s | `design/%s/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' "$tm" "$tm" > "$d/design/TEAMS.md"
  mkdir -p "$d/design/v65"; echo x > "$d/design/v65/SEATBELT-README.md"
  printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > "$d/.fable-team/bin-$tm/goal-lines.txt"
  printf '# GOAL — %s 제목줄\n\n## 원문 1 머리줄\n> %s\n' "$tm" "$CLOSE" > "$d/design/$tm/GOAL-$tm.md"
  printf '# 인덱스: x\n- Issue: #1\n- 제안서: 없음 — 시험용 카드\n- 상태: 대기\n- 선행: 없음\n- 시험 입력: 없음\n- 기준값: 없음 → 대체 축 시험\n- 설치: 없음\n<!-- ledger: design/'"$tm"'/GOAL-'"$tm"'.md -->\n\n## 골 원문 (항상 이 3줄)\n%s\n%s\n%s\n\n## 골좌표\n닫는 증거: 「%s」\n\n## 배경\n시험.\n\n## 구현 범위\n1. `scripts/real.sh` 를 고친다.\n\n## 완료 조건\n- 시험 rc=0\n\n## 계약↔시험 대응표\n| 계약 | 시험 |\n|---|---|\n| ① 첫 인자 | ⓐ |\n\n## 상태\n- 대기\n' \
    "$G1" "$G2" "$G3" "$CLOSE" > "$d/$CARDX"
  printf '{"_version":"1.0.0","byz-harness-master-claude#1":{"role":"master"}}\n' > "$d/.fable-team/seats-$tm.json"
  printf '{"_version":"1.0.0"}\n' > "$d/.fable-team/seats.json"
  printf "export FT_SEATS_JSON='%s/.fable-team/seats-%s.json'\nexport FT_NANO_PREFIX=byz-harness-nano-\nexport FT_GOAL_LEDGER='design/%s/GOAL-%s.md'\nexport FT_GOAL_LINES_FILE='%s/.fable-team/bin-%s/goal-lines.txt'\n" \
    "$d" "$tm" "$tm" "$tm" "$d" "$tm" > "$d/.fable-team/bin-$tm/$tm-env.sh"
  git init -q -b main "$d" && git -C "$d" -c user.name=t -c user.email=t@t add -A >/dev/null \
    && git -C "$d" -c user.name=t -c user.email=t@t commit -q -m init && git -C "$d" update-ref refs/remotes/origin/main HEAD
}
mt() { "$PY" -c 'import os,sys
for r,ds,fs in os.walk(sys.argv[1]):
  ds.sort()
  for f in sorted(fs): p=os.path.join(r,f); print(os.stat(p).st_mtime_ns, p)' "$1"; }
run() {  # run <bin 폴더> <픽스처> [인자…] — stdout+stderr 를 따로 · 호출 기록 = $T/calls
  local b="$1" d="$2"; shift 2; : > "$T/calls"; rm -f "$T/opened"
  ( cd "$d" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_CARD_FLOW=0 FT_RES_ROOT="$T/res" \
      FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_ROOT="$d" FT_RECLAIM_SH="$T/reclaim.sh" FAKE_CALLS="$T/calls" FAKE_OPENED="$T/opened" \
      FT_SEATS_JSON="$d/.fable-team/seats-harness.json" \
      timeout "${RUN_TO:-60}" bash "$b/ft-nano-spawn.sh" "$@" >"$T/out" 2>"$T/err" ); }
U="usage: "
u1() {  # u1 <bin> <이름> → 실패 칸 수 출력(0 = 통과)
  local b="$1" nm="$2" a n=0 D="$T/u1"; mkfix "$D"; mt "$D" > "$T/mt0"
  for a in --help -h --dry-run; do
    run "$b" "$D" "$a"; rc=$?
    [ "$rc" = 2 ] || { echo "  $nm U1 $a rc=$rc (2 기대)" >&2; n=$((n+1)); }
    { [ "$(wc -l < "$T/err" | tr -d ' ')" = 1 ] && grep -q "^$U" "$T/err" && [ ! -s "$T/out" ]; } \
      || { echo "  $nm U1 $a usage 1줄 아님: out=$(head -c 200 "$T/out" | tr '\n' '|') err=$(head -c 200 "$T/err" | tr '\n' '|')" >&2; n=$((n+1)); }
    [ ! -s "$T/calls" ] || { echo "  $nm U1 $a 외부 호출: $(head -3 "$T/calls" | tr '\n' '|')" >&2; n=$((n+1)); }
  done
  mt "$D" > "$T/mt1"; cmp -s "$T/mt0" "$T/mt1" || { echo "  $nm U1 가짜 루트 mtime 변함" >&2; n=$((n+1)); }
  echo "$n"; }

# ── 정적 ──
bash -n "$BIN/ft-nano-spawn.sh" && ok "bash -n 추적본" || bad "bash -n 추적본"
cmp -s "$BIN/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh" && ok "bin·kit cmp 0" || bad "bin·kit 불일치"

# ── U1 옵션 꼴 첫 인자 ──
[ "$(u1 "$BINX" 수정판)" = 0 ] && ok "U1 --help·-h·--dry-run 첫 자리 → rc2 · usage 1줄 · mtime 불변 · 호출 0" || bad "U1"

# ── U2 인자 0개 → 지금과 같음 ──
D="$T/u2"; mkfix "$D"; run "$BINX" "$D"; rc=$?
{ [ "$rc" = 2 ] && [ "$(wc -l < "$T/err" | tr -d ' ')" = 1 ] && grep -q "^$U" "$T/err"; } && ok "U2 인자 0개 → rc2 usage 1줄(불변)" || bad "U2 rc=$rc err=$(cat "$T/err")"

# ── U3 카드 경로 + --dry-run → 옵션 판독 무변경 ──
D="$T/u3"; mkfix "$D"; run "$BINX" "$D" "$CARDX" --dry-run; rc=$?
{ [ "$rc" = 0 ] && grep -q "INFO 회신 대상 = byz-harness-master-claude#3" "$T/out" "$T/err" && ! grep -q "^$U" "$T/err"; } \
  && ok "U3 카드 + --dry-run → rc0 · 회신 대상 줄(불변)" || bad "U3 rc=$rc out=$(tail -5 "$T/out") err=$(tail -5 "$T/err")"

# ── 변이 2종 — 각 bash -n rc0 먼저 · U1 이 잡는지 ──
GATE='case "$IDX" in -*) echo "usage: $0 <indices/대기/X.md>'
mk_mut() { cp -R "$BINX" "$1"; "$PY" - "$1/ft-nano-spawn.sh" "$2" <<'PY'
import sys
p, kind = sys.argv[1:3]
L = open(p, encoding="utf-8").read().split("\n")
i = next(k for k, s in enumerate(L) if s.startswith('case "$IDX" in -*)'))
g = L.pop(i)
if kind == "late":
    j = next(k for k, s in enumerate(L) if s.startswith('[ -f "$HERE/ft-heavy-slot-lib.sh" ]'))
    L.insert(j, g)
open(p, "w", encoding="utf-8").write("\n".join(L))
PY
}
grep -qF "$GATE" "$BIN/ft-nano-spawn.sh" && ok "첫 인자 검사 줄 있음" || bad "첫 인자 검사 줄 없음"
for k in del late; do M="$T/m-$k"; mk_mut "$M" "$k" || bad "변이 $k 만들기 실패"
  bash -n "$M/ft-nano-spawn.sh" && ok "변이 $k bash -n rc0" || bad "변이 $k bash -n 실패"
  [ "$(u1 "$M" "변이-$k" 2>/dev/null)" != 0 ] && ok "변이 $k → U1 FAIL(검출)" || bad "변이 $k 를 U1 이 못 잡음"
done

[ "$(git -C "$REPO" config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare != false"
tmux_isolate_leak_check || fail=$((fail+1))
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
