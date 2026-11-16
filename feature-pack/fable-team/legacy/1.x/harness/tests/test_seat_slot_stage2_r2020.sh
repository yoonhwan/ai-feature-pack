#!/usr/bin/env bash
# test_seat_slot_stage2_r2020.sh — r2020(r1641 단계 2): 석 칸 새 꼴 이름(<프로젝트>-<팀>-<역할>-<K>-<에이전트>#N)을 소비자가 같은 좌석으로 읽는다.
#   ⓖ 옛 꼴 → <역할>-0- 승계 = 1석 교대(문지기 --succession) · retire 뒤 _da = 새 이름 · _replaced_by 사슬로 옛 쪽지가 새 이름 recv 에
#   ⓗ _da-1 = reclaim 보호 · inbox-watch 현역 · board_roster 현역 · 석 0 승계가 _da-1 불변 | ⓘ 새 꼴 → 옛 꼴 역행 REJECT 1줄 · 옛→옛 그대로
#   ⓚ seat() 세 사본 · ⓛ seat-live agent·slot · 입력 = 이름·tmp 명부·가짜 tmux 스텁만 · 실 좌석·명부·우편함 0 · sleep 0
#   변이 = R2020_H(사본 harness 폴더)로 같은 시험을 사본에 돌린다(M4·M5·M6).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="${R2020_H:-$HERE/..}"; SK="${R2020_SK:-$H/../skill/scripts}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { [ "$2" = "$3" ] && ok "$1" || bad "$1 (got=[$2] want=[$3])"; }
export FT_ALLOW_TRACKED_BIN=1 FT_NAME_LINT="$H/bin/ft-name-lint.sh"
O='byz-t-da-codex#9'; N='byz-t-da-0-codex#10'; S1='byz-t-da-1-codex#0'
FK="$T/fake"; mkdir -p "$FK"
printf '#!/usr/bin/env bash\ncase "$1" in has-session) [ "$3" = "=${LIVE_OLD:-@}" ] && exit 0; exit 1;; esac\ncase "$*" in *"${FAKE_ALIVE_NAME:-@@none@@}"*) exit 0;; esac\nexit 1\n' > "$FK/tmux"
printf '#!/usr/bin/env bash\necho "tmuxc $*" >> "$LOG"; exit 0\n' > "$FK/tmuxc"; chmod +x "$FK/tmux" "$FK/tmuxc"

# ⓚ 우편함 seat() — skill·kit·comm/mbox_keep 세 사본
cat > "$T/probe.py" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("m", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(" ".join("1" if m.seat(n) else "0" for n in sys.argv[2:]))
PY
for f in "$SK/ft-mbox.py" "$H/kit/fable-team/bin/ft-mbox.py" "$H/comm/mbox_keep.py"; do
  chk "ⓚ $(basename "$f") 새 꼴 True · x·01 False · 옛 꼴·nano 불변" "$(python3 "$T/probe.py" "$f" "$S1" 'byz-t-arch-0-pi#3' 'byz-t-da-x-codex#0' 'byz-t-da-01-codex#0' "$O" 'byz-t-nano-r2020-x#0' 'byz-tool#0' 2>&1)" "1 1 0 0 1 1 0"
done

# ⓛ 좌석 현황 — 석 칸 agent·slot · 옛 꼴 석 0 · nano 불변
mkdir -p "$T/sl/seats" "$T/sl/comm"; echo '{"_da": "'"$O"'"}' > "$T/sl/seats/seats-t.json"
printf '#!/usr/bin/env bash\ncase "$1" in list-sessions) case "$*" in *session_created*) f="%%s\\t1700000000\\t0\\n";; *) f="%%s\\n";; esac; printf "$f" "%s" "%s" "byz-t-nano-r2020-x#0";; list-panes) ;; *) exit 9;; esac\n' "$S1" "$O" > "$T/sl/tmux"; chmod +x "$T/sl/tmux"
FT_SEATS_DIR="$T/sl/seats" FT_STATE_DIR="$T/sl/state" FT_TMUX="$T/sl/tmux" FT_MBOX_DIR="$T/sl/comm" bash "$H/bin/ft-seat-live.sh" > "$T/sl/out" 2>&1
r() { jq -r --arg s "$1" '.rows[]|select(.session==$s)|"\(.agent) \(.slot)"' "$T/sl/state/seats.live.json" 2>/dev/null; }
chk "ⓛ 새 꼴 agent=codex 석=1 · 옛 꼴 석 0 · nano null" "$(r "$S1") | $(r "$O") | $(r 'byz-t-nano-r2020-x#0')" "codex 1 | codex 0 | null null"

# ⓖ·ⓘ 승계 문턱 — 문지기 스텁(받은 인자만 적고 rc1)
BIN="$T/bin"; mkdir -p "$BIN"; cp -R "$H/kit/fable-team/bin/." "$BIN/"; cp "$H/bin/ft-successor-open.sh" "$BIN/"
printf '#!/usr/bin/env bash\necho "GATE $*" >> "$LOG"; echo "REJECT stub gate"; exit 1\n' > "$BIN/ft-resource-gate.sh"
printf 'import sys\nsys.exit(0)\n' > "$BIN/ft_teamset.py"
RES="$T/res"; REPO="$T/repo"; mkdir -p "$RES/.fable-team" "$REPO"; git -C "$REPO" init -q; printf '골 1\n본문\n' > "$T/body"
so() {   # so <구> <후계>
  : > "$T/log"; printf '{"_da": "%s", "_da-1": "%s", "%s": {"agent": "codex"}}\n' "$1" "$S1" "$1" > "$RES/.fable-team/seats-t.json"
  env HOME="$T/home" PATH="$FK:$PATH" LOG="$T/log" LIVE_OLD="$1" FT_RES_ROOT="$RES" FT_TEAMSET_MD="$T/ts.md" FT_RECLAIM=0 FT_NAME_LINT="$BIN/ft-name-lint.sh" \
    bash "$BIN/ft-successor-open.sh" "$1" "$REPO" --name "$2" --agent codex --model m --body-file "$T/body" > "$T/so" 2>&1; echo "rc=$? $(head -1 "$T/log")"
}
chk "ⓖ 옛 꼴 → -0- #N+1 = 1석 교대" "$(so "$O" "$N")" "rc=1 GATE check --succession"
chk "ⓖ 옛 꼴 → -0- #N+3 = 일반 문턱" "$(so "$O" 'byz-t-da-0-codex#12')" "rc=1 GATE check"
chk "ⓖ 새 꼴 석 1 → 석 1 #N+1 = 1석 교대" "$(so "$S1" 'byz-t-da-1-codex#1')" "rc=1 GATE check --succession"
o="$(so "$S1" 'byz-t-da-codex#1')"; chk "ⓘ 새 꼴 → 옛 꼴 역행 = REJECT 1줄 · 문지기 0" "$o $(grep -c '^REJECT 석 칸 역행' "$T/so")" "rc=1  1"
chk "ⓘ 옛 꼴 → 옛 꼴 = 그대로(문지기까지)" "$(so "$O" 'byz-t-da-codex#10')" "rc=1 GATE check --succession"

# ⓖ retire — _da = 새 이름 · _da-1 불변 · 옛 행 _replaced_by
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/reap.sh"
RR="$T/rr"; mkdir -p "$RR/.fable-team"; git -C "$RR" init -q; RF="$RR/.fable-team/seats-t.json"
printf '{"_da": "%s", "_da-1": "%s", "%s": {"role": "da", "agent": "codex", "model": "m", "tick": null}, "%s": {"role": "da", "agent": "codex", "model": "m", "tick": null}, "%s": {"role": "da", "agent": "codex", "model": "m", "tick": null, "_replaces": ["%s"]}}\n' "$O" "$S1" "$O" "$S1" "$N" "$O" > "$RF"
(cd "$RR" && HOME="$T/home" PATH="$FK:$PATH" FT_SEAT_REAP_BIN="$T/reap.sh" env -u FT_SEATS_JSON bash "$H/bin/ft-seat-retire.sh" "$O" "$N" > "$T/ret" 2>&1)
chk "ⓖ retire 뒤 _da=새 · _da-1 불변 · 옛 행 _replaced_by" "$(jq -r --arg o "$O" '"\(._da) \(."_da-1") \(.[$o]._replaced_by)"' "$RF")" "$N $S1 $N"

# ⓖ 우편함 사슬 — 옛 이름 쪽지가 새 이름 recv 에 보임
C="$T/mb/.fable-team/comm"; mkdir -p "$C" "$T/mb/seats"; cp "$H/comm"/mbox*.py "$C/"; cp "$RF" "$T/mb/seats/seats-t.json"; echo '{}' > "$T/mb/seats/seats.json"
printf '{"seq": 1, "ts": "2026-11-16T00:00:00", "to": "%s", "from": "x#1", "body": "옛 이름 쪽지"}\n' "$O" > "$C/mailbox.jsonl"
FT_SEATS_JSON="$T/mb/seats/seats.json" FT_MBOX_DIR="$C" python3 "$C/mbox.py" recv "$N" > "$T/mb/out" 2>&1
chk "ⓖ 새 이름 recv 에 옛 쪽지 1건" "$(grep -c '^READ \[' "$T/mb/out")" 1

# ⓗ 둘째 석 — board_roster · reclaim 보호 · inbox-watch 현역
B="$(python3 -c 'import json,sys; sys.path.insert(0, sys.argv[1]); import ft_board_roster as b
d = json.load(open(sys.argv[2])); d.pop(sys.argv[3]); a, u = b.select(d, set(k for k in d if not k.startswith("_")) | {sys.argv[4]}, None); print(" ".join(a), len(u))' "$H/bin" "$RF" "$O" "$S1" 2>&1)"
chk "ⓗ board_roster 현역 = 석 0 · 석 1 둘 다(확인 불가 0)" "$B" "$N $S1 0"
python3 - "$H/bin/ft-resource-reclaim.sh" > "$T/protect.py" <<'PY'
import re, sys; print(re.search(r"python3 -c '\n(import json,sys\n.*?)' \"\$r\"", open(sys.argv[1], encoding="utf-8").read(), re.S).group(1))
PY
chk "ⓗ reclaim 보호 집합에 석 1" "$(python3 "$T/protect.py" "$RF" 2>&1 | cut -f1 | tr ' ' '\n' | grep -cxF "$S1")" 1
W="$T/w/.fable-team"; mkdir -p "$W/state/inbox"; cp -R "$H/comm" "$W/comm"; : > "$W/comm/mailbox.jsonl"; cp "$RF" "$W/seats-t.json"
FT_ROOT="$T/w" FT_MBOX_DIR="$W/comm" FT_SEATS_JSON="$W/seats-t.json" FT_INBOX_WATCH_POLL=0.1 timeout 2 bash "$H/bin/ft-inbox-watch.sh" "$S1" > "$T/w/out" 2>&1
chk "ⓗ inbox-watch 석 1 좌석 = 현역(감시 유지 rc124 · ValueError 0)" "$? $(grep -c ValueError "$T/w/out")" "124 0"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
