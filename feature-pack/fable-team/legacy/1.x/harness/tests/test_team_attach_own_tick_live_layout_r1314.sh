#!/usr/bin/env bash
# R1314 — live 설치본 꼴(bin 만 · kit 없음)에서 ft-team-attach --apply <팀> --own-tick 이 끝까지 돈다 · 반쪽 상태 0.
#   계약: ① 템플릿은 bin 안(ft-tick-team.plist) ② own-tick 은 팀 틱 표를 «쓰지 않는다»(행은 팩 PR — 없으면 REJECT)
#         ③ 모든 사전 확인이 어떤 쓰기보다 먼저 ④ 설치기 실패 = plist 원복(.failed-/.bak-r199 무접촉) ⑤ 설치기에 넘기는 표 = tick_table
#   격리 FT_ROOT 샌드박스 · 가짜 launchctl(FT_TICK_LAUNCHCTL) · 실제 plist/launchd/우편함 무접촉 · press 0(단위 시험만).
[ "${FT_TEST_R1314_RUNNING:-0}" = 1 ] && { echo "SKIP 재진입(이미 도는 시험)"; exit 0; }
export FT_TEST_R1314_RUNNING=1
ulimit -u "$(( $(ps -u "$(id -u)" 2>/dev/null | wc -l | tr -d ' ') + 300 ))" 2>/dev/null || true   # r1041 자기 프로세스 여유
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
export LC_ALL=C
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
BIN="${FT_ATTACH_BIN:-$REPO/bin}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
label() { printf 'com.byz.ft-tick-%s' "$1"; }

# ── 설치본 꼴 = bin 만(키트 없음) ───────────────────────────────────────────
mklive() {  # $1 = 폴더 → 그 안에 설치본 bin 사본
  mkdir -p "$1/bin"
  cp -p "$BIN/ft-team-attach.sh" "$BIN/ft_team_attach.py" "$BIN/ft_team_attach_lib.py" \
        "$BIN/ft_team_attach_ops.py" "$BIN/ft_team_attach_state.py" "$BIN/ft_team_lib.py" "$BIN/ft_team_main_assign.py" \
        "$BIN/ft-tick-install.sh" "$BIN/ft-tick-team.plist" "$1/bin/" || return 1
  [ -f "$1/bin/ft_team_attach_ops.py" ] || return 1
}
# ── 독립 git 루트(팀 zzsandbox 현역) — TEAMSET 에는 그 팀 행이 «없다»(쓰기 0 을 바이트로 본다) ──
mkroot() {  # $1 = 루트
  local r="$1"
  mkdir -p "$r/design/teams/zzsandbox/indices" "$r/.fable-team/bin" "$r/LaunchAgents"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| zzsandbox | `design/teams/zzsandbox/` | x | 현역 |\n' > "$r/design/TEAMS.md"
  printf '## 표 2 — 팀별 덮어쓰기\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n| other | 3 | 0 | 상시 |\n' > "$r/design/TEAMSET.md"
  printf 'zzsandbox\tseats-zzsandbox.json\t/tmp/ft-tick-state-zzsandbox\t/tmp/ft-tick-zzsandbox.pid\t/tmp/ft-tick-zzsandbox-\tFT_TICK_MAGAZINE\tFT_TICK_FIRE_V2=1\n' > "$r/.fable-team/bin/team-tick-env.tsv"
  printf '#!/bin/sh\nexit 0\n' > "$r/.fable-team/bin/ft-tick.sh"
  printf '#!/bin/sh\necho IDLE\n' > "$r/.fable-team/bin/ft-seat-status.sh"
  chmod +x "$r/.fable-team/bin/ft-tick.sh" "$r/.fable-team/bin/ft-seat-status.sh"
  git -C "$r" init -q -b main
  git -C "$r" -c user.name=t -c user.email=t@t add design
  git -C "$r" -c user.name=t -c user.email=t@t commit -q -m seed
}
mklctl() {  # $1 = 폴더 → 가짜 launchctl(LC_FAIL=1 이면 bootstrap 실패)
  cat > "$1/launchctl" <<'SH'
#!/bin/sh
case "$1" in
  bootstrap) [ "${LC_FAIL:-0}" = 1 ] && { echo "bootstrap 실패(가짜)" >&2; exit 1; }
             basename "$3" .plist >> "$LC_STATE"; exit 0;;
  bootout) echo bootout >> "$LC_LOG"
           l="${2##*/}"; sed "/$l/d" "$LC_STATE" > "$LC_STATE.tmp" 2>/dev/null; mv "$LC_STATE.tmp" "$LC_STATE" 2>/dev/null; exit 0;;
  list) while IFS= read -r l; do [ -n "$l" ] && echo "0 0 $l"; done < "$LC_STATE"; exit 0;;
  print) grep -q "${2##*/}" "$LC_STATE" 2>/dev/null && exit 0; exit 113;;   # r1464: 적재 중이면 rc0 · 없으면 rc113
esac
exit 1
SH
  chmod +x "$1/launchctl"
}
# 시험마다 같은 이름의 환경을 새로 건다 — 남은 값이 다음 칸을 오염시키지 않게
scenario() {  # $1 = 이름 → SC 이름의 폴더들 + SC_ROOT/SC_LIVE/SC_LC
  SC="$1"; SC_ROOT="$TMP/$1/root"; SC_LIVE="$TMP/$1/live"; SC_LC="$TMP/$1/lc"; SC_STATE="$TMP/$1/state"
  mkdir -p "$SC_LC"; : > "$SC_STATE"; mklctl "$SC_LC"
  export FT_ROOT="$SC_ROOT" FT_TEAMS_MD="$SC_ROOT/design/TEAMS.md" FT_TEAMSET_MD="$SC_ROOT/design/TEAMSET.md"
  export FT_TEAM_ATTACH_SANDBOX=1 FT_TICK_PLIST_DIR="$SC_ROOT/LaunchAgents"
  export FT_TICK_LAUNCHCTL="$SC_LC/launchctl" LC_STATE="$SC_STATE" LC_LOG="$TMP/$1/launchctl.log" LC_FAIL=0
  export FT_TICK_TEAM_TSV="$SC_ROOT/.fable-team/bin/team-tick-env.tsv"
}
run() {  # run [bin] [팀] [인자…] → out · rc
  local b="${1:-$SC_LIVE/bin}"; shift
  out="$(bash "$b/ft-team-attach.sh" "$@" 2>&1)"; rc=$?
}
plist_path() { printf '%s/LaunchAgents/com.byz.ft-tick-zzsandbox.plist' "$SC_ROOT"; }
has() { case "$1" in *"$2"*) return 0;; *) return 1;; esac; }

# ── R1 설치본 꼴에서 --apply --own-tick 완주 · 표 쓰기 0 ────────────────────
scenario r1; mkroot "$SC_ROOT"; mklive "$SC_LIVE" || bad "R1 설치본 꼴 bin 사본 실패"
tsv_before="$(sha "$SC_ROOT/.fable-team/bin/team-tick-env.tsv")"
run "$SC_LIVE/bin" --apply zzsandbox --own-tick
{ [ "$rc" = 0 ] && [ -f "$(plist_path)" ] && grep -q "com.byz.ft-tick-zzsandbox" "$(plist_path)" \
  && [ "$(grep -c 'com.byz.ft-tick-zzsandbox' "$SC_STATE")" = 1 ] \
  && [ "$(sha "$SC_ROOT/.fable-team/bin/team-tick-env.tsv")" = "$tsv_before" ]; } \
  && ok "R1 설치본 꼴(kit 없음) --own-tick rc0 · plist 생김 · bootstrap 1 · 표 바이트 그대로" || bad "R1 rc=$rc out=$out"
run "$SC_LIVE/bin" zzsandbox --check
{ [ "$rc" = 0 ] && has "$out" "S6 전용 틱 OK"; } && ok "R1 --check S6 전용 틱 OK" || bad "R1 check rc=$rc out=$out"

# ── R2 bin 에 템플릿 없음 → REJECT · 모든 쓰기 0 ────────────────────────────
scenario r2; mkroot "$SC_ROOT"; mklive "$SC_LIVE" || bad "R2 bin 사본 실패"
rm -f "$SC_LIVE/bin/ft-tick-team.plist"
teamset_before="$(sha "$SC_ROOT/design/TEAMSET.md")"
run "$SC_LIVE/bin" --apply zzsandbox --own-tick
{ [ "$rc" = 1 ] && has "$out" "팀 틱 템플릿 없음" \
  && [ "$(sha "$SC_ROOT/design/TEAMSET.md")" = "$teamset_before" ] \
  && [ ! -f "$SC_ROOT/.fable-team/seats-zzsandbox.json" ] && [ ! -f "$SC_ROOT/.fable-team/state/zzsandbox-tick/HEADLINE.md" ] \
  && [ ! -f "$(plist_path)" ] && [ ! -s "$SC_STATE" ]; } \
  && ok "R2 템플릿 없음 → rc1 · TEAMSET·seats·HEADLINE·plist 쓰기 0" || bad "R2 rc=$rc out=$out"

# ── R3 틱 표에 팀 행 없음 → REJECT(팩 PR 안내) · 모든 쓰기 0 ────────────────
scenario r3; mkroot "$SC_ROOT"; mklive "$SC_LIVE" || bad "R3 bin 사본 실패"
printf '# 팀 행 없음\n' > "$SC_ROOT/.fable-team/bin/team-tick-env.tsv"
teamset_before="$(sha "$SC_ROOT/design/TEAMSET.md")"
run "$SC_LIVE/bin" --apply zzsandbox --own-tick
{ [ "$rc" = 1 ] && has "$out" "팀 틱 행 없음" && has "$out" "team-tick-env.tsv" \
  && [ "$(sha "$SC_ROOT/design/TEAMSET.md")" = "$teamset_before" ] \
  && [ ! -f "$SC_ROOT/.fable-team/seats-zzsandbox.json" ] && [ ! -f "$SC_ROOT/.fable-team/state/zzsandbox-tick/HEADLINE.md" ] \
  && [ ! -f "$(plist_path)" ]; } \
  && ok "R3 표에 팀 행 없음 → rc1(팩 PR 안내) · 쓰기 0" || bad "R3 rc=$rc out=$out"

# ── R4 설치기 bootstrap rc1 · 설치 전 plist 없음 → plist 0 · .failed-<시각> 1 ──
scenario r4; mkroot "$SC_ROOT"; mklive "$SC_LIVE" || bad "R4 bin 사본 실패"
LC_FAIL=1
run "$SC_LIVE/bin" --apply zzsandbox --own-tick
failed_n="$(find "$SC_ROOT/LaunchAgents" -maxdepth 1 -name 'com.byz.ft-tick-zzsandbox.plist.failed-*' | wc -l | tr -d ' ')"
{ [ "$rc" = 1 ] && [ ! -f "$(plist_path)" ] && [ "$failed_n" = 1 ]; } \
  && ok "R4 bootstrap 실패 · 설치 전 plist 없음 → plist 0 · .failed 1 · rc1" || bad "R4 rc=$rc failed=$failed_n out=$out"
LC_FAIL=0

# ── R4b 설치 전 plist 있었음 → 바이트 = 설치 전 (원복) ────────────────────
scenario r4b; mkroot "$SC_ROOT"; mklive "$SC_LIVE" || bad "R4b bin 사본 실패"
printf 'OLD-PLIST\n' > "$(plist_path)"
LC_FAIL=1
run "$SC_LIVE/bin" --apply zzsandbox --own-tick
{ [ "$rc" = 1 ] && [ "$(cat "$(plist_path)")" = "OLD-PLIST" ]; } \
  && ok "R4b 설치기 실패 → plist 바이트 = 설치 전(원복)" || bad "R4b rc=$rc bytes=$(cat "$(plist_path)" 2>/dev/null) out=$out"
LC_FAIL=0

# ── R4c 옛 .bak-r199 실재 → 설치기가 먼저 거절 · plist·백업 바이트 그대로 ──
scenario r4c; mkroot "$SC_ROOT"; mklive "$SC_LIVE" || bad "R4c bin 사본 실패"
printf 'OLD-PLIST\n' > "$(plist_path)"; printf 'OLD-BAK\n' > "$(plist_path).bak-r199"
run "$SC_LIVE/bin" --apply zzsandbox --own-tick
{ [ "$rc" = 1 ] && [ "$(cat "$(plist_path)")" = "OLD-PLIST" ] && [ "$(cat "$(plist_path).bak-r199")" = "OLD-BAK" ]; } \
  && ok "R4c .bak-r199 실재 → 설치기 rc1 · plist·백업 무접촉(백업 읽기 0)" || bad "R4c rc=$rc out=$out"

# ── R4d FT_TICK_TEAM_TSV 없음 + LIVE_BIN 표 → 설치기에 넘긴 표 = tick_table 경로 ──
scenario r4d; mkroot "$SC_ROOT"; mklive "$SC_LIVE" || bad "R4d bin 사본 실패"
mkdir -p "$SC_ROOT/livebin"
printf 'zzsandbox\tseats-zzsandbox.json\t/tmp/ft-tick-state-zzsandbox\t/tmp/ft-tick-zzsandbox.pid\t/tmp/ft-tick-zzsandbox-\tFT_TICK_MAGAZINE\tFT_TICK_FIRE_V2=1\n' > "$SC_ROOT/livebin/team-tick-env.tsv"
printf '%s\n' "$SC_ROOT/livebin" > "$SC_ROOT/.fable-team/LIVE_BIN"
printf '# 루트 자기 표에는 팀 행이 없다\n' > "$SC_ROOT/.fable-team/bin/team-tick-env.tsv"
cat > "$SC_LIVE/bin/ft-tick-install.sh" <<'SH'
#!/bin/sh
printf '%s' "$FT_TICK_TEAM_TSV" > "$FT_FAKE_INST_LOG"
exit 0
SH
chmod +x "$SC_LIVE/bin/ft-tick-install.sh"
export FT_FAKE_INST_LOG="$TMP/r4d/inst-tsv.txt"; : > "$FT_FAKE_INST_LOG"
unset FT_TICK_TEAM_TSV
live_table_before="$(sha "$SC_ROOT/livebin/team-tick-env.tsv")"
run "$SC_LIVE/bin" --apply zzsandbox --own-tick
want="$(cd "$SC_ROOT/livebin" && pwd -P)/team-tick-env.tsv"
{ [ "$rc" = 0 ] && [ "$(cat "$FT_FAKE_INST_LOG")" = "$want" ] \
  && [ "$(sha "$SC_ROOT/livebin/team-tick-env.tsv")" = "$live_table_before" ]; } \
  && ok "R4d 설치기에 넘긴 표 = tick_table(LIVE_BIN 표) · 바이트 그대로" || bad "R4d rc=$rc tsv=$(cat "$FT_FAKE_INST_LOG") out=$out"
export FT_TICK_TEAM_TSV="$SC_ROOT/.fable-team/bin/team-tick-env.tsv"

# ── R5 R1 루트에서 --detach → plist .disabled · bootout 1 (표 쓰기는 지금 길 그대로) ──
R1="$TMP/r1/root"; R1LOG="$TMP/r1/launchctl.log"
export FT_ROOT="$R1" FT_TEAMS_MD="$R1/design/TEAMS.md" FT_TEAMSET_MD="$R1/design/TEAMSET.md"
export FT_TEAM_ATTACH_SANDBOX=1 FT_TICK_PLIST_DIR="$R1/LaunchAgents"
export FT_TICK_LAUNCHCTL="$TMP/r1/lc/launchctl" LC_STATE="$TMP/r1/state" LC_LOG="$R1LOG" LC_FAIL=0
export FT_TICK_TEAM_TSV="$R1/.fable-team/bin/team-tick-env.tsv"
sed -i '' 's/현역/휴면/' "$R1/design/TEAMS.md" 2>/dev/null || sed -i 's/현역/휴면/' "$R1/design/TEAMS.md"
run "$TMP/r1/live/bin" zzsandbox --detach
disabled_n="$(find "$R1/LaunchAgents" -maxdepth 1 -name 'com.byz.ft-tick-zzsandbox.plist.disabled-*' | wc -l | tr -d ' ')"
{ [ "$rc" = 0 ] && [ "$disabled_n" = 1 ] && grep -q bootout "$R1LOG" && ! grep -qx 'com.byz.ft-tick-zzsandbox' "$TMP/r1/state"; } \
  && ok "R5 --detach rc0 · plist .disabled · bootout 1 · launchctl 목록에서 빠짐" || bad "R5 rc=$rc disabled=$disabled_n out=$out"

# ── R6 템플릿 두 벌 바이트 같음(bin · kit/launchd · kit bin) ────────────────
{ cmp -s "$BIN/ft-tick-team.plist" "$REPO/kit/launchd/com.byz.ft-tick-team.plist.template" \
  && cmp -s "$REPO/kit/fable-team/bin/ft-tick-team.plist" "$REPO/kit/launchd/com.byz.ft-tick-team.plist.template"; } \
  && ok "R6 bin·kit bin·kit launchd 템플릿 바이트 같음" || bad "R6 템플릿 세 벌이 다르다"

# ── 변이 3 — 사본에 한 줄 어긋나게 하고 «그 칸이 무너지는지» 를 같은 프로세스에서 본다(자기 재호출 0) ──
mutsrc() {  # $1 = 이름 → $TMP/$1/bin (설치본 꼴 사본)
  local d="$TMP/$1"; mkdir -p "$d"; mklive "$d" || { echo ""; return 1; }; echo "$d/bin"
}
mutate() {  # $1 = 파일 $2 = old $3 = new
  python3 - "$1" "$2" "$3" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
assert sys.argv[2] in t, "변이 앵커 없음"
p.write_text(t.replace(sys.argv[2], sys.argv[3], 1), encoding="utf-8")
PY
}
M1="$(mutsrc mut1)" || bad "변이 1 사본 실패"
if [ -n "$M1" ]; then
  mutate "$M1/ft_team_attach_ops.py" 'template = HERE / "ft-tick-team.plist"' \
    'template = HERE.parent / "kit/launchd/com.byz.ft-tick-team.plist.template"' || bad "변이 1 패치 실패"
  scenario mut1; mkroot "$SC_ROOT"; run "$M1" --apply zzsandbox --own-tick
  { [ "$rc" != 0 ] && has "$out" "팀 틱 템플릿 없음"; } \
    && ok "변이 1(템플릿 경로를 kit 로) → 설치본 꼴에서 무너진다(rc=$rc)" || bad "변이 1 미검출 rc=$rc out=$out"
fi
M2="$(mutsrc mut2)" || bad "변이 2 사본 실패"
if [ -n "$M2" ]; then
  mutate "$M2/ft_team_attach_ops.py" '    pre = own_tick_precheck(root, team) if own_tick else None  # 쓰기 0 — 반쪽 상태 0(r1314)' '    pre = None' \
    && python3 - "$M2/ft_team_attach_ops.py" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
old = "        changed += own_tick_apply(root, team, p, dry, pre)"
new = "        changed += own_tick_apply(root, team, p, dry, own_tick_precheck(root, team) if not dry else None)"
assert old in t
p.write_text(t.replace(old, new, 1), encoding="utf-8")
PY
  [ $? = 0 ] || bad "변이 2 패치 실패"
  scenario mut2; mkroot "$SC_ROOT"; rm -f "$M2/ft-tick-team.plist"
  run "$M2" --apply zzsandbox --own-tick
  { [ "$rc" = 1 ] && { [ -f "$SC_ROOT/.fable-team/seats-zzsandbox.json" ] \
    || [ -f "$SC_ROOT/.fable-team/state/zzsandbox-tick/HEADLINE.md" ] \
    || grep -q '^| zzsandbox |' "$SC_ROOT/design/TEAMSET.md"; }; } \
    && ok "변이 2(사전 확인을 쓰기 뒤로) → 반쪽 상태가 남는다(무너짐)" || bad "변이 2 미검출 rc=$rc out=$out"
fi
M3="$(mutsrc mut3)" || bad "변이 3 사본 실패"
if [ -n "$M3" ]; then
  mutate "$M3/ft_team_attach_ops.py" '        elif plist.is_file() and plist.read_bytes() != before:' '        elif False:' || bad "변이 3 패치 실패"
  scenario mut3; mkroot "$SC_ROOT"; printf 'OLD-PLIST\n' > "$(plist_path)"
  LC_FAIL=1; run "$M3" --apply zzsandbox --own-tick; LC_FAIL=0
  { [ "$rc" = 1 ] && [ "$(cat "$(plist_path)")" != "OLD-PLIST" ]; } \
    && ok "변이 3(plist 원복 생략) → 설치기 실패 뒤 plist 가 바뀐 채 남는다(무너짐)" || bad "변이 3 미검출 rc=$rc out=$out"
fi

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
