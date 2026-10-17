#!/usr/bin/env bash
# test_raised_seat.sh — R149(판정 1641): 상향 좌석(Fable 나노·astra DA) 사유 기록 + «▶내릴 것» 경보.
# mktemp 만 쓴다(임시 git 리포 + 가짜 tmux·tmuxc·mbox·형제 도구) — 실제 리포·명부·tmux·mbox 0. 변이 시험은 R149_BIN=<변이 복사본 폴더> 로 같은 시험을 돌린다.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="${R149_BIN:-$REPO/scripts/fable-team-bin}"; KIT="$REPO/scripts/harness-install/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok   # R218: 자원 문지기 센서를 가짜로(실 머신 부하·압력 무관)
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }

for f in ft-nano-spawn.sh ft-role-spawn.sh ft-tick.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; done
if [ -z "${R149_BIN:-}" ]; then for f in ft-nano-spawn.sh ft-role-spawn.sh ft-tick.sh ft_raised.py; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done; fi
RAISED="$BIN/ft_raised.py"

# ── ① is-raised 패턴 표 ──
for m in claude-fable-5-1 gpt-6-astra GPT-6-ASTRA Claude-Fable-5-1 'claude-fable-5-1[1m]'; do python3 "$RAISED" is-raised "$m"; rc_is $? 0 "상향(양성) $m"; done
for m in claude-opus-5-5 'claude-sonnet-5-5[1m]' gpt-6.1-sol gpt-6-luna ''; do python3 "$RAISED" is-raised "$m"; rc_is $? 1 "기본(음성) «${m}»"; done

# ── 임시 리포 + 가짜 도구 ──
R="$T/repo"; B="$T/bin"; SEATS="$R/.fable-team/seats.json"; CARD_REL="design/v65/indices/대기/r149x.md"
mkdir -p "$R/.fable-team" "$R/design/v65/indices/대기" "$R/design/v65/indices/inbox/master" "$R/design/v65/indices/inbox/da" "$B" "$T/sess" "$T/fake"
git -C "$R" init -q -b main && : > "$R/.gitkeep" && git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m init
printf '# 인덱스: r149x\n## 상태\n' > "$R/$CARD_REL"; printf 'x\n' > "$R/design/v65/SEATBELT-README.md"
for f in ft-nano-spawn.sh ft-role-spawn.sh ft-tick.sh ft_raised.py ft-resource-gate.sh ft_teamset.py ft_spawn_queue.py; do cp -p "$BIN/$f" "$B/"; done
for f in ft-index-lint.sh ft-proposal-gate.sh ft-index-move.sh ft-send-verified.sh ft-agent-ready.sh; do printf '#!/bin/bash\nexit 0\n' > "$B/$f"; done
printf '#!/bin/bash\n[ "$1" = key ] && { echo k; exit 0; }\necho "$*" >> "%s/events.log"\n' "$T" > "$B/ft-sheet-events.sh"
printf '#!/bin/bash\necho "tmuxc $*" >> "%s/calls.log"\nif [ "$1" = open ]; then n=""; dry=0; while [ $# -gt 0 ]; do [ "$1" = --name ] && n="$2"; [ "$1" = --dry-run ] && dry=1; shift; done; if [ $dry = 1 ]; then echo "TMUXC-DRY $n"; else : > "%s/sess/$n"; fi; fi\n' "$T" "$T" > "$T/fake/tmuxc"
printf '#!/bin/bash\necho "tmux $*" >> "%s/calls.log"\ncase "$1" in\n has-session) [ -e "%s/sess/${3#=}" ];;\n list-panes) for s in "%s"/sess/*; do [ -e "$s" ] && echo "$(basename "$s")|%%1|1700000000"; done; exit 0;;\n show-option) echo 1;;\n *) exit 0;;\nesac\n' "$T" "$T" "$T" > "$T/fake/tmux"
chmod +x "$B"/*.sh "$T/fake/tmuxc" "$T/fake/tmux"
printf '{"_master":"m#1","m#1":{"role":"master","agent":"claude","tick":null}}\n' > "$SEATS"
SEATS0="$(cat "$SEATS")"
SPAWN() { (cd "$R" && PATH="$T/fake:$PATH" FT_SEATS_JSON="$SEATS" bash "$B/ft-nano-spawn.sh" "$R/$CARD_REL" "$@" 2>&1); }
RSPAWN() { (cd "$R" && PATH="$T/fake:$PATH" bash "$B/ft-role-spawn.sh" "$@" 2>&1); }
row() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));r=d.get(sys.argv[2]);print(json.dumps(r,ensure_ascii=False,sort_keys=True) if r is not None else "NONE")' "$SEATS" "$1"; }
keys() { python3 -c 'import json,sys;print(",".join(json.load(open(sys.argv[1]))[sys.argv[2]].keys()))' "$SEATS" "$1"; }
untouched() { eq "$(cat "$SEATS")" "$SEATS0" "$1: 명부 불변"; [ ! -e "$T/events.log" ] && ok "$1: 사건 원장 불변" || bad "$1: 사건 원장 건드림"; [ ! -d "$R/.worktrees" ] && ok "$1: 워크트리 0" || bad "$1: 워크트리 생김"; [ -z "$(ls "$T/sess")" ] && ok "$1: tmux 세션 0" || bad "$1: 세션 생김"; eq "$(cat "$R/$CARD_REL")" "$(printf '# 인덱스: r149x\n## 상태\n')" "$1: 카드 base_sha 안 씀"; }

# C1: 거절은 «rc=1 · PLAN/TMUXC-DRY 줄 0 · 가짜 tmux/tmuxc 후속 호출 0» 을 즉시 단언한다(DA⑥ HOLD1)
rejected() { local label="$1" want="$2" out="$3" rc="$4"; rc_is "$rc" 1 "$label: 거절 rc"; has "$out" "$want" "$label: 거절 문구"; hasnt "$out" "PLAN seat=" "$label: PLAN 줄 0"; hasnt "$out" "TMUXC-DRY" "$label: TMUXC dry-run 줄 0"; [ ! -s "$T/calls.log" ] && ok "$label: 후속 호출 0" || bad "$label: 후속 호출 있음 — $(head -c 200 "$T/calls.log" 2>/dev/null)"; }
# ── ② dry-run: 상향 모델 + --raise 없음 = REJECT · --raise 있음 = PLAN · 둘 다 부작용 0 ──
: > "$T/calls.log"; o="$(SPAWN --model claude-fable-5-1 --dry-run)"; rc=$?; rejected "nano 사유 없음" "REJECT 상향 모델(claude-fable-5-1)은 --raise" "$o" "$rc"; untouched "REJECT dry-run"
: > "$T/calls.log"; o="$(SPAWN --model claude-fable-5-1 --raise '   ' --dry-run)"; rc=$?; rejected "nano 공백 사유" "REJECT 상향 모델" "$o" "$rc"
: > "$T/calls.log"; o="$(SPAWN --model gpt-6-astra --agent codex --dry-run)"; rc=$?; rejected "astra 사유 없음" "REJECT 상향 모델(gpt-6-astra)" "$o" "$rc"
o="$(SPAWN --model claude-fable-5-1 --raise '풀리지 않는 문제' --dry-run)"; has "$o" "PLAN seat=" "dry-run 상향 + --raise → PLAN"; hasnt "$o" "REJECT 상향" "dry-run 상향 + --raise → 상향 REJECT 0"; untouched "PLAN dry-run"
o="$(SPAWN --dry-run)"; has "$o" "PLAN seat=" "dry-run 기본 모델 → PLAN (--raise 불필요)"; untouched "기본 dry-run"
: > "$T/calls.log"; o="$(RSPAWN master --model claude-fable-5-1 --dry-run)"; rc=$?; rejected "role 사유 없음" "REJECT 상향 모델(claude-fable-5-1)은 --raise" "$o" "$rc"
: > "$T/calls.log"; o="$(RSPAWN master --model claude-fable-5-1 --raise 사유 --dry-run)"; rc=$?; rejected "role --raise-card 없음" "REJECT 상향 모델" "$o" "$rc"
o="$(RSPAWN da --agent codex --model gpt-6-astra --effort low --raise 사유 --raise-card design/v65/indices/진행/c.md --dry-run)"; has "$o" "PLAN seat=" "role dry-run astra + 사유 + 카드 → PLAN"
untouched "role dry-run"

# ── ③ 격리 실전: 실제 경로로 명부 행 저장 ──
o="$(SPAWN --model claude-fable-5-1 --raise '2회 수렴 실패' --from m#1)"; has "$o" "SPAWNED " "실전 상향 spawn → SPAWNED"
S="$(ls "$T/sess" | head -1)"; r="$(row "$S")"
has "$r" '"reason": "2회 수렴 실패"' "행 raised.reason"; has "$r" '"card": "design/v65/indices/진행/r149x.md"' "행 raised.card = 진행/ 카드"; has "$r" '"by": "m#1"' "행 raised.by = --from"
has "$r" '"close_on": "card 가 완성/ 으로 가거나 없어짐 · 또는 좌석 닫기"' "행 raised.close_on"; has "$r" '"at": "20' "행 raised.at ISO"; has "$r" '"model": "claude-fable-5-1"' "행 model"
printf '# 인덱스: r149y\n## 상태\n' > "$R/design/v65/indices/대기/r149y.md"
o="$(cd "$R" && PATH="$T/fake:$PATH" FT_SEATS_JSON="$SEATS" bash "$B/ft-nano-spawn.sh" "$R/design/v65/indices/대기/r149y.md" 2>&1)"; has "$o" "SPAWNED " "실전 기본 모델 spawn → SPAWNED"
S2="$(ls "$T/sess" | grep r149y | head -1)"; eq "$(keys "$S2")" "role,agent,tick,model,index" "기본 모델 행 모양 변화 0 (raised 칸 없음)"
o="$(RSPAWN master --model claude-fable-5-1 --raise '설계 재작성' --raise-card design/v65/indices/진행/r149x.md --from m#1)"; has "$o" "SPAWNED " "실전 상향 role spawn → SPAWNED"
RS="$(ls "$T/sess" | grep master | head -1)"; r="$(row "$RS")"
has "$r" '"card": "design/v65/indices/진행/r149x.md"' "role 행 raised.card = --raise-card"; has "$r" '"index": "design/v65/indices/inbox/master/"' "role 행 index = inbox 의미 보존"

# ── ④ check ──
CK="$T/ck"; mkdir -p "$CK/design/x/indices/진행" "$CK/design/x/indices/완성" "$CK/design/x/indices/대기"
: > "$CK/design/x/indices/진행/a.md"; : > "$CK/design/x/indices/완성/b.md"; : > "$CK/design/x/indices/진행/c.md"; : > "$CK/design/x/indices/완성/d.md"; : > "$CK/design/x/indices/대기/w.md"
mk() { python3 - "$@" <<'PY'
import json, sys
rows = {"_master": "m#1"}
def raised(card, reason="r"): return {"reason": reason, "card": card}
rows["nano-open"] = {"role": "nano", "model": "claude-fable-5-1", "index": "design/x/indices/진행/a.md", "raised": raised("design/x/indices/진행/a.md")}
rows["nano-done"] = {"role": "nano", "model": "claude-fable-5-1", "index": "design/x/indices/진행/b.md", "raised": raised("design/x/indices/진행/b.md", "어려움")}
rows["nano-gone"] = {"role": "nano", "model": "claude-fable-5-1", "index": "x", "raised": raised("design/x/indices/진행/없음.md")}
rows["role-open"] = {"role": "da", "model": "gpt-6-astra", "index": "design/v65/indices/inbox/da/", "raised": raised("design/x/indices/진행/c.md")}
rows["role-done"] = {"role": "da", "model": "gpt-6-astra", "index": "design/v65/indices/inbox/da/", "raised": raised("design/x/indices/진행/d.md", "astra")}
rows["role-plain"] = {"role": "master", "model": "claude-opus-5-5[1m]", "index": "design/v65/indices/inbox/master/"}
rows["retired"] = {"role": "stop-ready", "model": "claude-fable-5-1", "_replaced_by": "z", "raised": raised("design/x/indices/진행/없음2.md")}
rows["nano-wait"] = {"role": "nano", "model": "claude-fable-5-1", "raised": raised("design/x/indices/대기/w.md")}
json.dump(rows, open(sys.argv[1], "w"), ensure_ascii=False)
PY
}
mk "$CK/s.json"
o="$(python3 "$RAISED" check "$CK/s.json" --root "$CK" 2>&1)"; rc=$?; rc_is "$rc" 0 "check 목록 있어도 rc 0"
has "$o" "▶내릴 것 nano-done 모델=claude-fable-5-1 사유=어려움 (카드 완성)" "나노 카드 완성/ → 1줄"; has "$o" "▶내릴 것 nano-gone" "나노 카드 없음 → 1줄"; has "$o" "(카드 없음)" "카드 없음 표기"
has "$o" "▶내릴 것 role-done 모델=gpt-6-astra 사유=astra (카드 완성)" "역할 raised.card 완성/ → 1줄"
hasnt "$o" "nano-open" "나노 카드 진행/ → 0줄"; hasnt "$o" "role-open" "역할 raised.card 진행/ → 0줄"; hasnt "$o" "role-plain" "raised 없는 역할 좌석(index=inbox) → 0줄"
hasnt "$o" "retired" "은퇴 행(_replaced_by) → 0줄"; hasnt "$o" "nano-wait" "카드 대기/ → 0줄"; eq "$(printf '%s\n' "$o" | grep -c '▶내릴 것')" 3 "▶내릴 것 정확히 3줄"
python3 - "$CK/s2.json" <<'PY'
import json, sys
json.dump({"_master": "m#1", "a": {"role": "nano", "raised": {"card": "design/x/indices/진행/a.md"}}, "p": {"role": "master", "index": "design/v65/indices/inbox/master/"}}, open(sys.argv[1], "w"))
PY
o="$(python3 "$RAISED" check "$CK/s2.json" --root "$CK" 2>&1)"; rc=$?; rc_is "$rc" 0 "check 전부 진행/ → rc 0"; eq "$o" "" "check 전부 진행/ → 출력 0"
python3 "$RAISED" check "$CK/s.json" "$CK/s.json" "$CK/./s.json" "$CK/s*.json" --root "$CK" >/dev/null 2>&1
DUP="$T/dup"; mkdir -p "$DUP/design/x/indices/완성"; : > "$DUP/design/x/indices/완성/z.md"
python3 - "$DUP/seats-t.json" <<'PY2'
import json, sys
json.dump({"_master": "m#1", "m#1": {"role": "master", "agent": "claude", "tick": None}, "nano-z": {"role": "nano", "model": "claude-fable-5-1", "raised": {"reason": "r", "card": "design/x/indices/완성/z.md"}}}, open(sys.argv[1], "w"), ensure_ascii=False)
PY2
ln -s seats-t.json "$DUP/link.json"
o="$(python3 "$RAISED" check "$DUP/seats-t.json" "$DUP/seats-*.json" "$DUP/./seats-t.json" "$DUP/link.json" --root "$DUP" 2>&1)"; rc=$?
rc_is "$rc" 0 "C2 같은 명부 여러 경로(글자·glob·./·심링크) → rc 0"; eq "$(printf '%s\n' "$o" | grep -c '▶내릴 것')" 1 "C2 같은 명부 중복 경로 → ▶내릴 것 1행(realpath 중복 제거)"
printf '{broken' > "$CK/bad.json"
o="$(python3 "$RAISED" check "$CK/bad.json" --root "$CK" 2>&1)"; rc=$?; rc_is "$rc" 2 "명부 깨짐 → rc 2"; has "$o" "ft_raised: ERROR" "명부 깨짐 → stderr 1줄"
o="$(python3 "$RAISED" check "$CK/s.json" "$CK/없는.json" --root "$CK" 2>&1)"; rc=$?; rc_is "$rc" 2 "없는 명부 → rc 2"; hasnt "$o" "▶내릴 것" "rc 2 면 목록을 내지 않는다(조용한 부분 성공 0)"
python3 - "$CK/s3.json" <<'PY'
import json, sys
json.dump({"a": {"role": "nano", "raised": {"reason": "x"}}}, open(sys.argv[1], "w"))
PY
python3 "$RAISED" check "$CK/s3.json" --root "$CK" >/dev/null 2>&1; rc_is $? 2 "raised.card 없음 → rc 2 (조용히 통과 0)"
python3 "$RAISED" check "$CK/glob-없음-*.json" --root "$CK" >/dev/null 2>&1; rc_is $? 0 "glob 에 걸리는 파일 없음 → rc 0"

# ── ⑤ tick raised_watch ──
TK="$T/tk"; mkdir -p "$TK"; cp "$CK/s.json" "$TK/seats.json"; python3 - "$TK/seats.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["m#1"] = {"role": "master", "agent": "claude", "tick": None}; json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY
printf '#!/bin/bash\necho "$*" >> "%s/mbox.log"\n' "$T" > "$T/fakembox.sh"; printf '#!/bin/bash\nexit 1\n' > "$T/failmbox.sh"; chmod +x "$T/fakembox.sh" "$T/failmbox.sh"
mkdir -p "$T/fk-sha"; printf '#!/bin/sh\nexit 9\n' > "$T/fk-sha/shasum"; chmod +x "$T/fk-sha/shasum"
TICK() { local st="$1"; shift; (cd "$CK" && git init -q 2>/dev/null; env "$@" FT_TICK_SEATS="$TK/seats.json" FT_TICK_STATE_DIR="$st" FT_TICK_MBOX="${MBOXBIN:-$T/fakembox.sh}" FT_TICK_PIDFILE="$T/tick.pid" FT_TICK_STAMP_PREFIX="$T/stamp-" \
  FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_HIL=0 FT_TICK_API_OUTAGE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_STALL_INTERVAL=99999999999 FT_TICK_GOAL_INTERVAL=99999999999 bash "$B/ft-tick.sh" --once 2>&1); }
sends() { grep -c '\[▶내릴 것\]' "$T/mbox.log" 2>/dev/null || echo 0; }
ST="$T/state"
t1="$(TICK "$ST")"; eq "$(sends)" 1 "1틱: 송신 1"; [ -f "$ST/raised.sig" ] && ok "서명 파일 저장" || bad "서명 파일 없음"
has "$(cat "$T/mbox.log")" "상향 좌석 3건" "송신 본문 3건"; has "$(cat "$T/mbox.log")" "nano-done" "송신 본문 좌석명"
t2="$(TICK "$ST")"; eq "$(sends)" 1 "같은 서명 2틱: 송신 추가 0"
: > "$CK/design/x/indices/진행/a.md"; mv "$CK/design/x/indices/진행/a.md" "$CK/design/x/indices/완성/a.md"
t3="$(TICK "$ST")"; eq "$(sends)" 2 "목록 바뀜(나노 하나 더 완성): 송신 1회 추가"; has "$(tail -1 "$T/mbox.log")" "상향 좌석 4건" "새 본문 4건"
mv "$CK/design/x/indices/완성/a.md" "$CK/design/x/indices/진행/a.md"; rm "$CK/design/x/indices/완성/b.md"
MBOXBIN="$T/failmbox.sh" TICK "$T/state-f" >/dev/null; t4="$(MBOXBIN="$T/failmbox.sh" TICK "$T/state-f")"
has "$t4" "raised_watch: mbox failed" "송신 실패 → stderr 1줄"; [ -f "$T/state-f/raised.sig" ] && bad "송신 실패인데 서명 저장" || ok "송신 실패 → 서명 미저장(다음 틱 재시도)"
b="$(sends)"; c3="$(TICK "$T/state-sha" PATH="$T/fk-sha:$PATH")"
has "$c3" "raised_watch: ERROR signature" "가짜 shasum rc 9 → ERROR 1줄"; eq "$(sends)" "$b" "shasum 실패 → 송신 0"; [ -f "$T/state-sha/raised.sig" ] && bad "shasum 실패인데 서명 저장" || ok "shasum 실패 → 서명 없음"
cp "$TK/seats.json" "$TK/seats.ok"; printf '{broken' > "$TK/seats.json"; c4="$(TICK "$T/state-bad")"; cp "$TK/seats.ok" "$TK/seats.json"
has "$c4" "raised_watch: ERROR check rc=2" "명부 깨짐 → ERROR 1줄"; eq "$(sends)" "$b" "check rc 2 → 송신 0"
rm -f "$CK"/design/x/indices/*/*.md; : > "$CK/design/x/indices/진행/a.md"
for p in nano-done nano-gone role-done; do python3 - "$TK/seats.json" "$p" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d.pop(sys.argv[2]); json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY
done
: > "$CK/design/x/indices/진행/c.md"; : > "$CK/design/x/indices/대기/w.md"
t5="$(TICK "$ST")"; [ -f "$ST/raised.sig" ] && bad "해소 뒤 서명 남음" || ok "목록이 비면 서명 파일 삭제(재발 시 다시 1회)"
b="$(sends)"; t6="$(TICK "$T/state-off" FT_TICK_RAISED=0)"; eq "$(sends)" "$b" "FT_TICK_RAISED=0 → 검사·송신 0"
d="$(cd "$CK" && FT_TICK_SEATS="$TK/seats.json" FT_TICK_STATE_DIR="$T/state-dry" FT_TICK_MBOX="$T/fakembox.sh" bash "$B/ft-tick.sh" --dry-run 2>&1)"
has "$d" "DRY kind=raised bin=" "--dry-run → DRY kind=raised"; eq "$(sends)" "$b" "--dry-run 송신 0"

# C2 tick: FT_TICK_SEATS=seats-t.json 하나 + 같은 폴더 seats-*.json glob 이 같은 명부를 가리켜도 송신 1건
TD="$T/td"; mkdir -p "$TD/design/x/indices/완성"; : > "$TD/design/x/indices/완성/z.md"; cp "$DUP/seats-t.json" "$TD/seats-t.json"
b="$(sends)"; (cd "$TD" && git init -q 2>/dev/null; FT_TICK_SEATS="$TD/seats-t.json" FT_TICK_STATE_DIR="$T/state-dup" FT_TICK_MBOX="$T/fakembox.sh" FT_TICK_PIDFILE="$T/tick.pid" FT_TICK_STAMP_PREFIX="$T/stamp-dup-" FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_HIL=0 FT_TICK_API_OUTAGE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_STALL_INTERVAL=99999999999 FT_TICK_GOAL_INTERVAL=99999999999 bash "$B/ft-tick.sh" --once >/dev/null 2>&1)
eq "$(( $(sends) - b ))" 1 "C2 tick: 명부 하나 + 같은 폴더 glob → 송신 1건"; has "$(tail -1 "$T/mbox.log")" "상향 좌석 1건" "C2 tick: 본문 1건(중복 0)"
echo "--- 증거: 시험 로케일 ${LC_ALL:-기본}"
if [ -z "${R149_SECOND:-}" ] && [ "$fail" -eq 0 ]; then LC_ALL=C.UTF-8 R149_SECOND=1 bash "${BASH_SOURCE[0]:-$0}" | tail -2; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=$((fail+1)); fi
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
