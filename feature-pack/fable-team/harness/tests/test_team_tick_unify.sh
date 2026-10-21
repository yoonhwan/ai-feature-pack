#!/usr/bin/env bash
# test_team_tick_unify.sh — R199: 팀 틱 5개를 공용 ft-tick.sh + 팀 env 로 통일(ft-tick-install.sh --team · team-tick-env.tsv).
#   ⓐ팀 plist 기존 키 이름·값 전부 보존(FT_TICK_SEAT_STATUS 만 공용 bin 으로) · ProgramArguments[1] = 공용 ft-tick.sh · 새 키 = 표 값
#   ⓑSTATE_DIR·PIDFILE·STAMP_PREFIX 팀마다 다름(메인 기본값과도) — 변이(표에서 팀 하나가 다른 팀 STATE_DIR 를 씀)는 이 단언이 잡는다
#   ⓒ전역 감시(매거진·예약표·드리프트·raised·sweep·뉴스 원장·자율 끝 기록) 팀 틱 실행 0 · 메인 env(스위치 없음)는 실행(양성 대조)
#   ⓓ팀 명부로 --once --dry-run 에 idle-long·dead-seat 줄 · 깨움 대상 = 그 팀 명부 좌석만 · 명부 파일 불변(후계 이전 쓰기 0 = heir_of/retarget_seat 이식 불요 판정)
#   ⓔFT_TICK_FIRE_V2=1 은 팀 사본의 busy 감지(스피너 ↓ N tokens)를 켠다 · 미설정은 옛 동작  ⓕ키트 두 사본 동일
# 모든 쓰기는 mktemp scratch 안 — 실 plist·실 launchctl·실 /tmp 기본 경로 0. tmux·mbox·도구는 가짜.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
KIT="$REPO/harness/bin"; INST="$REPO/harness/kit/fable-team/bin"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
TEAMS="feature loom ops cfo"
TSV="${R199_TSV:-$KIT/team-tick-env.tsv}"

# ⓕ 키트 두 사본 동일
for f in ft-tick.sh ft-tick-install.sh team-tick-env.tsv; do chk "ⓕ 키트 두 사본 동일 $f" "$(cmp -s "$KIT/$f" "$INST/$f" && echo same || echo differ)" same; done
bash -n "$KIT/ft-tick.sh" && bash -n "$KIT/ft-tick-install.sh" && ok "bash -n" || bad "bash -n"

# ── 팀별 «지금 plist» 가짜(키 15개 + LANG·PATH) · 구판 팀 폴더 ft-seat-status.sh ──
mkdir -p "$TMP/live" "$TMP/plists" "$TMP/root/.fable-team"
cp "$KIT/ft-tick.sh" "$KIT/ft-seat-status.sh" "$TMP/live/"
python3 - "$TMP" "$TEAMS" <<'PY'
import plistlib, sys, os
tmp, teams = sys.argv[1], sys.argv[2].split()
for t in teams:
    b = f"{tmp}/bin-{t}"; os.makedirs(b, exist_ok=True)
    open(f"{b}/ft-tick.sh", "w").write("old\n"); open(f"{b}/ft-seat-status.sh", "w").write("old\n"); open(f"{b}/ft-goal-tick-{t}.sh", "w").write("g\n")
    env = {"FT_MBOX_DIR": f"{tmp}/comm", "FT_TICK_GOAL_INTERVAL": "240", "FT_TICK_GOAL_TICK": f"{b}/ft-goal-tick-{t}.sh",
           "FT_TICK_MASTER_INTERVAL": "900", "FT_TICK_MASTER_MIN_GAP": "840", "FT_TICK_MASTER_MSG": f"[cron-tick · 뉴스] {t} 팀 문구 $HOME `x` \"q\"",
           "FT_TICK_MBOX": f"{tmp}/comm/mbox.sh", "FT_TICK_PIDFILE": f"/tmp/ft-tick-{t}.pid", "FT_TICK_PM_INTERVAL": "600",
           "FT_TICK_PM_MSG": f"[cron-tick] {t} pm 문구", "FT_TICK_SEATS": f"{tmp}/root/.fable-team/seats-{t}.json",
           "FT_TICK_SEAT_STATUS": f"{b}/ft-seat-status.sh", "FT_TICK_STALL_INTERVAL": "300", "FT_TICK_STALL_MIN": "15",
           "FT_TICK_STAMP_PREFIX": f"/tmp/ft-tick-{t}-", "LANG": "ko_KR.UTF-8", "PATH": "/usr/bin:/bin"}
    d = {"Label": f"com.byz.ft-tick-{t}", "ProgramArguments": ["/opt/homebrew/bin/bash", f"{b}/ft-tick.sh"], "WorkingDirectory": f"{tmp}/root",
         "EnvironmentVariables": env, "KeepAlive": True, "RunAtLoad": True, "StandardOutPath": f"/tmp/ft-tick-{t}.log", "StandardErrorPath": f"/tmp/ft-tick-{t}.log"}
    plistlib.dump(d, open(f"{tmp}/plists/com.byz.ft-tick-{t}.plist", "wb"))
PY
cp "$TMP/plists/com.byz.ft-tick-ops.plist" "$TMP/ops-from.plist"
inst() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY FT_TICK_TEAM_TSV="$TSV" FT_TICK_PLIST_DIR="$TMP/plists" bash "$KIT/ft-tick-install.sh" --script "$TMP/live/ft-tick.sh" "$@"; }
envof() { python3 -c 'import plistlib,sys;print(plistlib.load(open(sys.argv[1],"rb"))["EnvironmentVariables"].get(sys.argv[2],"<none>"))' "$1" "$2"; }

# ⓐ 보존
for t in $TEAMS; do
  inst --team "$t" --dry-run > "$TMP/new-$t.plist" 2>/dev/null; rc=$?
  chk "ⓐ $t dry-run rc" "$rc" 0
  r="$(python3 - "$TMP/plists/com.byz.ft-tick-$t.plist" "$TMP/new-$t.plist" "$TMP/live/ft-tick.sh" <<'PY'
import plistlib, sys
o = plistlib.load(open(sys.argv[1], "rb")); n = plistlib.load(open(sys.argv[2], "rb"))
oe, ne = o["EnvironmentVariables"], n["EnvironmentVariables"]
lost = [k for k in oe if k not in ne]; chg = sorted(k for k in oe if k in ne and oe[k] != ne[k])
print("lost=%s changed=%s pa1=%s" % (lost, chg, "live" if n["ProgramArguments"][1] == sys.argv[3] else n["ProgramArguments"][1]))
PY
)"
  chk "ⓐ $t 기존 키 보존 · 바뀐 키 = SEAT_STATUS 뿐 · ProgramArguments[1] = 공용" "$r" "lost=[] changed=['FT_TICK_SEAT_STATUS'] pa1=live"
  chk "ⓐ $t SEAT_STATUS = 공용 bin" "$(envof "$TMP/new-$t.plist" FT_TICK_SEAT_STATUS)" "$TMP/live/ft-seat-status.sh"
  chk "ⓐ $t FIRE_V2 · STATE_DIR" "$(envof "$TMP/new-$t.plist" FT_TICK_FIRE_V2) $(envof "$TMP/new-$t.plist" FT_TICK_STATE_DIR)" "1 /tmp/ft-tick-state-$t"
done
chk "ⓐ dry-run: 실 plist 불변" "$(cmp -s "$TMP/ops-from.plist" "$TMP/plists/com.byz.ft-tick-ops.plist" && echo same || echo changed)" same
# 표와 plist 값이 어긋나면 거부(사람 확인) · 공용 bin 에 seat-status 없으면 거부 · 팀 표에 없으면 거부 · 원본 plist 없으면 거부(chatbot)
python3 - "$TMP/plists/com.byz.ft-tick-loom.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb")); d["EnvironmentVariables"]["FT_TICK_PIDFILE"] = "/tmp/other.pid"; plistlib.dump(d, open(sys.argv[1], "wb"))
PY
chk "ⓐ 표≠plist(PIDFILE) → 거부 rc" "$(inst --team loom --dry-run >/dev/null 2>&1; echo $?)" 1
cp "$TMP/ops-from.plist" "$TMP/plists/com.byz.ft-tick-ops.plist"
mkdir -p "$TMP/live-noss"; cp "$KIT/ft-tick.sh" "$TMP/live-noss/"
chk "ⓐ 공용 bin 에 seat-status 없음 → 거부 rc" "$(env FT_TICK_TEAM_TSV="$TSV" FT_TICK_PLIST_DIR="$TMP/plists" bash "$KIT/ft-tick-install.sh" --team ops --script "$TMP/live-noss/ft-tick.sh" --dry-run >/dev/null 2>&1; echo $?)" 1
chk "ⓐ 표에 없는 팀 → 거부 rc" "$(inst --team nope --dry-run >/dev/null 2>&1; echo $?)" 1
chk "ⓐ chatbot: 원본 plist 없음 → 거부 rc" "$(inst --team chatbot --dry-run >/dev/null 2>&1; echo $?)" 1
inst --team chatbot --from "$TMP/ops-from.plist" --dry-run > "$TMP/new-chatbot.plist" 2>/dev/null
chk "ⓐ chatbot --from: 좌석표·라벨·로그" "$(envof "$TMP/new-chatbot.plist" FT_TICK_SEATS | sed 's|.*/||') $(python3 -c 'import plistlib,sys;d=plistlib.load(open(sys.argv[1],"rb"));print(d["Label"],d["StandardOutPath"])' "$TMP/new-chatbot.plist")" "seats-chatbot.json com.byz.ft-tick-chatbot /tmp/ft-tick-chatbot.log"

# ⓖ DA⑥ r1 H1: own 모드 plist 의 STATE_DIR 이 표와 다르면 거부(없으면 추가) · H2: --script 기본 = 메인 plist · 워크트리·키트 원본 경로 거부
cp "$TMP/plists/com.byz.ft-tick-ops.plist" "$TMP/ops-keep.plist"
python3 - "$TMP/plists/com.byz.ft-tick-ops.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb")); d["EnvironmentVariables"]["FT_TICK_STATE_DIR"] = "/tmp/other-state"; plistlib.dump(d, open(sys.argv[1], "wb"))
PY
chk "ⓖ H1 표≠plist(STATE_DIR) → 거부 rc" "$(inst --team ops --dry-run >/dev/null 2>&1; echo $?)" 1
cp "$TMP/ops-keep.plist" "$TMP/plists/com.byz.ft-tick-ops.plist"
chk "ⓖ H1 plist 에 STATE_DIR 없음 → 추가(rc 0 · 표 값)" "$(inst --team ops --dry-run 2>/dev/null > "$TMP/h1.plist"; echo $? $(envof "$TMP/h1.plist" FT_TICK_STATE_DIR))" "0 /tmp/ft-tick-state-ops"
instd() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY FT_TICK_TEAM_TSV="$TSV" FT_TICK_PLIST_DIR="$TMP/plists" bash "${INSTALLER:-$KIT/ft-tick-install.sh}" "$@"; }
chk "ⓖ H2 메인 plist 없음 + --script 생략 → 거부 rc" "$(instd --team ops --dry-run >/dev/null 2>&1; echo $?)" 1
python3 - "$TMP/plists/com.byz.ft-tick.plist" "$TMP/live/ft-tick.sh" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick", "ProgramArguments": ["/opt/homebrew/bin/bash", sys.argv[2]]}, open(sys.argv[1], "wb"))
PY
instd --team ops --dry-run > "$TMP/h2.plist" 2>/dev/null; rc=$?
chk "ⓖ H2 --script 생략 → 메인 plist 의 스크립트" "$rc $(python3 -c 'import plistlib,sys;print(plistlib.load(open(sys.argv[1],"rb"))["ProgramArguments"][1])' "$TMP/h2.plist")" "0 $TMP/live/ft-tick.sh"
for bad_dir in "$TMP/wt/.worktrees/x/.fable-team/bin" "$TMP/wt/harness/bin" "$TMP/wt/harness/kit/fable-team/bin"; do  # 키트 원본 = 팩 배치(r385 · 옛 scripts/fable-team-bin 은 없음)
  mkdir -p "$bad_dir"; cp "$KIT/ft-tick.sh" "$KIT/ft-seat-status.sh" "$bad_dir/"
  chk "ⓖ H2 --script ${bad_dir#$TMP/} → 거부 rc" "$(instd --team ops --script "$bad_dir/ft-tick.sh" --dry-run >/dev/null 2>&1; echo $?)" 1
done
LIVEWT="$TMP/wt/.worktrees/v6-realtime-live/.fable-team/bin"; mkdir -p "$LIVEWT"; cp "$KIT/ft-tick.sh" "$KIT/ft-seat-status.sh" "$LIVEWT/"
chk "ⓖ H2 라이브 .worktrees/v6-realtime-live/.fable-team/bin 은 허용 rc" "$(instd --team ops --script "$LIVEWT/ft-tick.sh" --dry-run >/dev/null 2>&1; echo $?)" 0
# r3 DA⑥ r2 재현: 허용 패턴(라이브 bin)을 `..` 로 흉내 낸 키트 원본 경로 → 명시 --script·메인 plist 기본값 둘 다 거부
mkdir -p "$TMP/x/.worktrees/harness-foo/scripts/fable-team-bin"; cp "$KIT/ft-tick.sh" "$KIT/ft-seat-status.sh" "$TMP/x/.worktrees/harness-foo/scripts/fable-team-bin/"
DOTS="$LIVEWT/../../../harness-foo/scripts/fable-team-bin/ft-tick.sh"
chk "ⓖ r3 H2 '..' 로 허용 패턴 흉내(--script) → 거부 rc" "$(instd --team ops --script "$DOTS" --dry-run >/dev/null 2>&1; echo $?)" 1
chk "ⓖ r3 H2 '..' 흉내 + REJECT 출력 · plist 출력 0" "$(instd --team ops --script "$DOTS" --dry-run 2>/dev/null | grep -c '^REJECT')" 1
python3 - "$TMP/plists/com.byz.ft-tick.plist" "$DOTS" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick", "ProgramArguments": ["/opt/homebrew/bin/bash", sys.argv[2]]}, open(sys.argv[1], "wb"))
PY
chk "ⓖ r3 H2 '..' 흉내(메인 plist 기본값) → 거부 rc" "$(instd --team ops --dry-run >/dev/null 2>&1; echo $?)" 1
chk "ⓖ r3 정규화 값이 plist 에 들어간다(허용 경로 '..' 우회 아닌 것)" "$(instd --team ops --script "$LIVEWT/../bin/ft-tick.sh" --dry-run 2>/dev/null > "$TMP/r3.plist"; python3 -c 'import plistlib,sys;print(plistlib.load(open(sys.argv[1],"rb"))["ProgramArguments"][1])' "$TMP/r3.plist")" "$LIVEWT/ft-tick.sh"
python3 - "$TMP/plists/com.byz.ft-tick.plist" "$TMP/live/ft-tick.sh" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick", "ProgramArguments": ["/opt/homebrew/bin/bash", sys.argv[2]]}, open(sys.argv[1], "wb"))
PY
# 변이: 기본 선택을 옛 동작(메인 plist 를 못 읽음)으로 바꾸면 «메인 plist 의 스크립트» 단언이 FAIL
mkdir -p "$TMP/mut"; sed 's|MAINPL="\$PDIR/com.byz.ft-tick.plist"|MAINPL=/nonexistent.plist|' "$KIT/ft-tick-install.sh" > "$TMP/mut/ft-tick-install.sh"
chk "ⓖ 변이(기본 선택 = 옛 동작)를 잡는다 rc" "$(INSTALLER="$TMP/mut/ft-tick-install.sh" instd --team ops --dry-run >/dev/null 2>&1; echo $?)" 1
rm -f "$TMP/plists/com.byz.ft-tick.plist"

# 설치(가짜 launchctl): 백업 → 쓰기 → 재실행 멱등
printf '#!/bin/bash\necho "$*" >> "$LCTL_LOG"\n' > "$TMP/launchctl"; chmod +x "$TMP/launchctl"; export LCTL_LOG="$TMP/lctl.log"
chk "설치 rc" "$(FT_TICK_LAUNCHCTL="$TMP/launchctl" inst --team ops >/dev/null 2>&1; echo $?)" 0
chk "설치: 백업 = 원본 · plist 갱신" "$(cmp -s "$TMP/ops-from.plist" "$TMP/plists/com.byz.ft-tick-ops.plist.bak-r199" && echo bak-ok) $(envof "$TMP/plists/com.byz.ft-tick-ops.plist" FT_TICK_FIRE_V2)" "bak-ok 1"
chk "설치: bootout·bootstrap 2줄" "$(wc -l < "$LCTL_LOG" | tr -d ' ')" 2
chk "설치 재실행(멱등) rc · launchctl 추가 0" "$(FT_TICK_LAUNCHCTL="$TMP/launchctl" inst --team ops >/dev/null 2>&1; echo $?) $(wc -l < "$LCTL_LOG" | tr -d ' ')" "0 2"
plutil -lint "$TMP/plists/com.byz.ft-tick-ops.plist" >/dev/null && ok "설치 plist lint" || bad "설치 plist lint"

# ⓑ 팀별 값 유일 — 표 검사 함수(변이 사본으로도 돌려 «잡는지» 확인)
dups() {  # $1=표 → 겹치는 (열 이름=값) 목록(메인 기본값 포함)
  awk -F'\t' 'BEGIN{m["3"]="/tmp/ft-tick-state"; m["4"]="/tmp/ft-tick.pid"; m["5"]="/tmp/ft-tick-"; for(c=3;c<=5;c++) seen[c","m[c]]=1}
    !/^#/ && NF==7 { for(c=3;c<=5;c++){ k=c","$c; if(k in seen) print "c" c "=" $c; seen[k]=1 } }' "$1" | tr '\n' ' '
}
chk "ⓑ 표: STATE_DIR·PIDFILE·STAMP_PREFIX 팀마다 다름(메인 기본값과도)" "$(dups "$TSV")" ""
sed 's|/tmp/ft-tick-state-ops|/tmp/ft-tick-state-cfo|' "$TSV" > "$TMP/mutant.tsv"
chk "ⓑ 변이(ops 가 cfo STATE_DIR 를 씀)를 잡는다" "$(dups "$TMP/mutant.tsv")" "c3=/tmp/ft-tick-state-cfo "

# ── 틱 실행 시험 공통: 라이브 bin 꼴 scratch · 가짜 tmux·mbox·도구 ──
mkdir -p "$TMP/repo/.fable-team/bin"; LIVE="$TMP/repo/.fable-team/bin/ft-tick.sh"; cp "$KIT/ft-tick.sh" "$LIVE"
for n in ft-launchd-check ft-magazine-check ft-news-ledger; do printf '#!/bin/bash\necho %s >> "$MARK"\n' "$n" > "$TMP/repo/.fable-team/bin/$n.sh"; done
printf '#!/bin/bash\nprintf "DRIFT 1 file\\nDIFF scripts/x\\n"; exit 1\n' > "$TMP/drift-stub.sh"
printf '#!/bin/bash\necho sweep >> "$MARK"\n' > "$TMP/sweep-stub.sh"; chmod +x "$TMP/sweep-stub.sh"
printf 'import os\nopen(os.environ["MARK"],"a").write("raised\\n")\n' > "$TMP/raised-stub.py"
printf '#!/bin/bash\ncase "$1" in expire) echo autonomy-expire >> "$MARK";; mode) echo off;; esac\n' > "$TMP/autonomy-stub.sh"
printf '#!/bin/bash\ncase "$1" in turn) echo "IDLE 2026-10-14T00:00:00 0 no jsonl";; esac\n' > "$TMP/seatstatus-stub.sh"
printf '#!/bin/bash\n[ "$1" = peek ] && echo "pending=0"; exit 0\n' > "$TMP/mbox-stub.sh"
printf '#!/bin/bash\necho "ALIVE seat=$1 fg=2.1.302 body=1"\n' > "$TMP/alive-stub.sh"   # R346: 이 시험은 문구·발사를 본다 — 에이전트 판정은 ALIVE 고정 대역(판정기 시험 = test_agent_alive_fg_judge.sh)
printf '#!/bin/bash\ncase "$1" in record) exit 1;; esac\nexit 0\n' > "$TMP/resume-stub.sh"
tmux() { case "$1" in list-panes) printf '%s\n' "$FAKE_PANES";; capture-pane) printf '%b' "${FAKE_SCREEN:-}";; send-keys) [ "${4:-}" = -l ] && printf '%s' "$5" > "$FAKE_SENT_DIR/p${3#%}";; esac; return 0; }
export -f tmux
export FAKE_PANES=$'T-M#1 %1\nT-N#1 %2\nOTHER-N#1 %3'
rost() { printf '{"_master":"T-M#1","_hil_route":"PLAN#1","T-M#1":{"role":"master","agent":"claude","model":"m","tick":"ft-master-tick"},"T-N#1":{"role":"nano","agent":"claude","model":"m","tick":null},"T-DEAD#0":{"role":"nano","agent":"claude","model":"m","tick":null}}' > "$1"; }
rost "$TMP/seats-t.json"
BASE=("FT_TICK_SEATS=$TMP/seats-t.json" "FT_TICK_MBOX=$TMP/mbox-stub.sh" "FT_TICK_AGENT_ALIVE=$TMP/alive-stub.sh" "FT_TICK_SEAT_STATUS=$TMP/seatstatus-stub.sh" "FT_TICK_GOAL_TICK=$TMP/none"
  "FT_TICK_DRIFT_BIN=$TMP/drift-stub.sh" "FT_TICK_WT_SWEEP_BIN=$TMP/sweep-stub.sh" "FT_TICK_RAISED_BIN=$TMP/raised-stub.py" "FT_TICK_AUTONOMY_BIN=$TMP/autonomy-stub.sh"
  "FT_TICK_RESUME_ATTEMPT=$TMP/resume-stub.sh" "FT_TICK_API_OUTAGE=0" "FT_TICK_HIL=0" "FT_TICK_IDLE_STALL_MIN=10")
runtick() {  # runtick <이름> <KEY=VAL...> — 마지막 인자들이 BASE 를 덮는다. 인자 --once [--dry-run] 는 RT_FLAGS
  local n="$1"; shift; mkdir -p "$TMP/$n/sent" "$TMP/$n/state"
  ( cd "$TMP/repo" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY "${BASE[@]}" \
      FT_TICK_STATE_DIR="$TMP/$n/state" FT_TICK_STAMP_PREFIX="$TMP/$n/p-" FT_TICK_PIDFILE="$TMP/$n/pid" MARK="$TMP/$n/mark" FAKE_SENT_DIR="$TMP/$n/sent" "$@" \
      bash "$LIVE" ${RT_FLAGS:---once} > "$TMP/$n/out" 2>&1 )
}
team_env() {  # 설치기가 만든 팀 plist 의 «끌 스위치»만 KEY=VAL 로 (경로·문구 키는 scratch 값을 쓰려고 제외)
  python3 -c 'import plistlib,sys
e=plistlib.load(open(sys.argv[1],"rb"))["EnvironmentVariables"]
print(*(k+"="+v for k,v in e.items() if k in ("FT_TICK_MAGAZINE","FT_TICK_LAUNCHD","FT_TICK_DRIFT","FT_TICK_RAISED","FT_TICK_WT_SWEEP","FT_TICK_NEWS_LEDGER","FT_TICK_NEWS_WATCH","FT_TICK_AUTONOMY")),sep="\n")' "$1"
}
TEAM_OFF=(); while IFS= read -r l; do [ -z "$l" ] || TEAM_OFF+=("$l"); done < <(team_env "$TMP/new-ops.plist")
chk "ⓒ 팀 plist 가 끄는 스위치 8개" "${#TEAM_OFF[@]}" 8

# ⓒ 메인 env(스위치 없음 · 라이브 bin 꼴) = 양성 대조, 팀 env = 실행 0
runtick c-main FT_TICK_IDLE_ENABLED=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0
chk "ⓒ 양성 대조(메인 env): 전역 감시 6종이 돈다" "$(sort -u "$TMP/c-main/mark" 2>/dev/null | tr '\n' ' ')" "autonomy-expire ft-launchd-check ft-magazine-check ft-news-ledger raised sweep "
runtick c-team FT_TICK_IDLE_ENABLED=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 "${TEAM_OFF[@]}"
chk "ⓒ 팀 env: 전역 감시 실행 0" "$(sort -u "$TMP/c-team/mark" 2>/dev/null | tr '\n' ' ')" ""
chk "ⓒ 팀 env: drift 알림 0" "$(grep -c 'drift:' "$TMP/c-team/out")" 0

# ⓓ 팀 명부로 --once --dry-run
cp "$TMP/seats-t.json" "$TMP/seats-t.before"
RT_FLAGS="--once --dry-run" runtick d "${TEAM_OFF[@]}" FT_TICK_TURN_FIXTURE_DIR= FT_TICK_RESUME_ATTEMPT="$TMP/resume-stub.sh"
# r687: r615(747d3789) 뒤 나노는 누적 정지 대상 아님 · 죽은 나노는 «dead-seat-nano» 줄로 따로(재개·죽음 목록 0) — 기대를 그 규칙으로, 나노 제외를 명시 단언
chk "ⓓ idle-long 줄(그 팀 좌석만 · master 는 planner 앞)" "$(grep 'kind=idle-long ' "$TMP/d/out" | awk '{print $3,$5}' | tr '\n' ' ')" "seat=T-M#1 to=PLAN#1 "
chk "ⓓ idle-long 나노(T-N#1) 0 — r615 나노 제외" "$(grep 'kind=idle-long ' "$TMP/d/out" | grep -c 'seat=T-N#1')" 0
chk "ⓓ dead-seat 줄" "$(grep -c 'kind=dead-seat ' "$TMP/d/out")" 1
chk "ⓓ 죽은 나노(T-DEAD#0) = dead-seat-nano 1줄 · 죽음 셈 0" "$(grep -c 'kind=dead-seat-nano seat=T-DEAD#0' "$TMP/d/out")|$(grep -o 'kind=dead-seat mode=[a-z]* dead=[0-9]*' "$TMP/d/out" | sed 's/.*dead=//')" "1|0"
chk "ⓓ 다른 팀 좌석(OTHER-N#1) 언급 0" "$(grep -c 'OTHER-N#1' "$TMP/d/out")" 0
chk "ⓓ 명부 파일 불변(후계 이전 쓰기 0)" "$(cmp -s "$TMP/seats-t.json" "$TMP/seats-t.before" && echo same || echo changed)" same

# ⓔ FIRE_V2 — 스피너 «↓ N tokens» 만 있는 창: V2=1 은 busy 로 건너뛰고, 미설정은 옛 동작(보냄)
export FAKE_SCREEN='✻ Cogitating… (12s · ↓ 120 tokens)\n\n❯ \n'
printf '{"_master":"T-M#1","T-M#1":{"role":"master","tick":"ft-master-tick"}}' > "$TMP/seats-m.json"
for v in off on; do
  extra=(FT_TICK_IDLE_ENABLED=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 "FT_TICK_SEATS=$TMP/seats-m.json" "${TEAM_OFF[@]}" FT_TICK_MASTER_MSG=팀문구 FT_TICK_MASTER_MIN_GAP=0 FT_TICK_MASTER_INTERVAL=0)
  [ "$v" = on ] && extra+=(FT_TICK_FIRE_V2=1)
  runtick "e-$v" "${extra[@]}"
done
chk "ⓔ FIRE_V2 미설정: 스피너만 있는 창엔 옛 동작(발사)" "$(cat "$TMP/e-off/sent/p1" 2>/dev/null)" "팀문구"
chk "ⓔ FIRE_V2=1: 같은 창을 busy 로 건너뜀(발사 0)" "$(cat "$TMP/e-on/sent/p1" 2>/dev/null)|$(grep -c 'pane busy' "$TMP/e-on/out")" "|1"
unset FAKE_SCREEN

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
