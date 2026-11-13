#!/usr/bin/env bash
# test_seat_close_ft2_pi_r1855.sh — r1855: ft2 launch 로 연 pi 나노(명부 밖)도 판정 닫기 재개 기록이 그 세션 파일 «정확히 1개» 로 결속된다.
#   ① 명부 행 0 · 가짜 tmux env(FT2_*) · intent · 세션 파일 1개 → --record-only --verdict = RESUME ok · binding.source ft2-intent · ft_seat_bind --expect rc0
#   ② 시간 창 안 세션 파일 2개 → 판정 불가 REJECT rc1 · 기록 0      ③ intent holder ≠ 좌석 → claude 탐색 그대로(NORECORD tmux 세션 없음)
#   ④ tmuxc 좌석(TMUXC_PI_SESSION_ID) → v3 결속 바이트 그대로       ⑤ 창 안 1개 + intent.at+180초 새 세션 → NORECORD … 세션 바뀜 · 기록 0
#   변이 M1~M5(사본에서만) = 각각 ②③④①⑤ FAIL · bin == kit cmp
# 모든 쓰기는 mktemp 안(가짜 tmux·ps·HOME·명부·intent·세션 파일) — 실 명부·실 장부·실 pane·실 pi 세션 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
diff_() { if [ "$2" != "$3" ]; then ok "$1"; else bad "$1 (변이가 살아남음: [$2])"; fi; }

echo "== bin == kit cmp"
for f in ft_seat_pi.py ft_seat_pi_ft2.py ft_roster_lib.py ft-seat-retire.sh ft_seat_bind.py; do cmp -s "$BIN/$f" "$KIT/$f" && ok "cmp $f" || bad "cmp $f 다름"; done

FILES="ft-seat-retire.sh ft_seat_bind.py ft_roster_lib.py ft_seat_pi.py ft_seat_pi_ft2.py ft_seat_pi_turn.py ft_seat_codex.py"
TM="$T/tm"; PS="$T/psess"; F2="$T/ft2root"; L="$F2/.fable-team/teams/harness/runtime/launch"
mkdir -p "$T/bin" "$T/fake" "$T/home" "$T/resume" "$TM" "$PS" "$L" "$T/wt"
for f in $FILES; do cp "$BIN/$f" "$T/bin/" 2>/dev/null; done   # 기준판엔 ft_seat_pi_ft2.py 없음(Red)
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -u ] && shift
s=""; for a in "$@"; do case "$a" in =*) s="${a#=}";; esac; done
case "$1" in
  list-panes) cat "$TM/panes";;
  has-session) grep -qF "$s	" "$TM/panes" || { echo "can't find session: $s" >&2; exit 1; };;
  show-environment) [ -f "$TM/env-$s" ] || exit 1; v="${!#}"
    case "$v" in =*) cat "$TM/env-$s";; *) grep "^$v=" "$TM/env-$s" || { echo "unknown variable: $v" >&2; exit 1; };; esac;;
  *) exit 0;;
esac
EOF
cat > "$T/fake/ps" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = -p ] && [ -f "$TM/comm-$2" ]; then case "$4" in pid=) echo "$2";; comm=) cat "$TM/comm-$2";; esac; exit 0; fi
exec /bin/ps "$@"
EOF
chmod +x "$T/fake/"*
AT="$(python3 -c 'import datetime as d; print((d.datetime.now()-d.timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%S"))')"   # intent.at = 로컬 시각
z() { python3 -c 'import datetime as d,sys; t=d.datetime.fromisoformat(sys.argv[1]).astimezone(d.timezone.utc)+d.timedelta(seconds=int(sys.argv[2])); print(t.strftime("%Y-%m-%dT%H:%M:%S.123Z"))' "$AT" "$1"; }
pane() { mkdir -p "$T/wt/$1"; printf '%s\t%s\t%s\t0\n' "$1" "$2" "$T/wt/$1" >> "$TM/panes"; echo pi > "$TM/comm-$2"; }   # <좌석> <pid>
seat() { pane "$1" "$2"   # <좌석> <pid> <work> <intent holder> — ft2 launch 꼴(명부 행 0)
  printf 'FT2_ATTEMPT=a1\nFT2_HOLDER=%s\nFT2_ROOT=%s\nFT2_TEAM=harness\nFT2_WORK=%s\n' "$1" "$F2" "$3" > "$TM/env-$1"
  printf '{"FT2_ATTEMPT":"a1","FT2_HOLDER":"%s","FT2_WORK":"%s","at":"%s","state":"opened","worktree":"%s"}\n' "$4" "$3" "$AT" "$T/wt/$1" > "$L/$3@a1.intent"; }
sess() { mkdir -p "$PS/e-$2"   # <좌석> <uuid> <intent.at 뒤 초>
  printf '{"type":"session","version":3,"id":"%s","timestamp":"%s","cwd":"%s"}\n{"type":"model_change","id":"b","modelId":"og/m1"}\n{"type":"session_info","name":"%s"}\n' "$2" "$(z "$3")" "$T/wt/$1" "$1" > "$PS/e-$2/$2.jsonl"; }
A='byz-harness-nano-r9001-a#0'; B='byz-harness-nano-r9002-b#0'; C='byz-harness-nano-r9003-c#0'; D='byz-harness-nano-tmuxc-pi#1'; E='byz-harness-nano-r9005-e#0'
seat "$A" 4101 r9001 "$A"; sess "$A" sa 1
seat "$B" 4102 r9002 "$B"; sess "$B" sb1 1; sess "$B" sb2 30
seat "$C" 4103 r9003 'byz-harness-nano-other#0'; sess "$C" sc 1
pane "$D" 4104; printf 'TMUXC_PI_SESSION_ID=sd\n' > "$TM/env-$D"; sess "$D" sd 1
seat "$E" 4105 r9005 "$E"; sess "$E" se1 1; sess "$E" se2 180
R="$T/repo"; mkdir -p "$R/.fable-team"; git -C "$R" init -q; S="$R/.fable-team/seats.json"
printf '{"_master":"byz-harness-master-pi#238","%s":{"role":"nano","agent":"pi","model":"og/m1","tick":null}}\n' "$D" > "$S"
E_() { (cd "$R" && env PATH="$T/fake:$PATH" TM="$TM" FT_TMUX="$T/fake/tmux" HOME="$T/home" ZC_RESUME_DIR="$T/resume" FT_PI_SESSIONS="$PS" "$@" 2>&1); }
run() { rm -f "$T/resume/"*; E_ bash "${BD:-$T/bin}/ft-seat-retire.sh" "$1" --record-only --verdict 4164 --seats "$S"; }
c1() { o="$(run "$A")"; r=$?; E_ python3 "${BD:-$T/bin}/ft_seat_bind.py" "$A" --expect "$T/resume/$A.json" >/dev/null; x=$?
  echo "$r $(grep -c "^RESUME ok $T/resume/$A.json" <<< "$o") $(jq -r '[.binding.source,.engine,.uuid]|join(",")' "$T/resume/$A.json" 2>/dev/null) expect=$x"; }
c2() { o="$(run "$B")"; r=$?; echo "$r $(grep -c 'Pi 결속 판정 불가' <<< "$o") rec=$(ls "$T/resume" | wc -l | tr -d ' ')"; }
c3() { o="$(run "$C")"; r=$?; echo "$r [${o%%$'\n'*}] rec=$(ls "$T/resume" | wc -l | tr -d ' ')"; }
WANT4="{\"source\": \"pi-session\", \"session\": \"$D\", \"uuid\": \"sd\", \"jsonl\": \"$PS/e-sd/sd.jsonl\", \"pid\": 4104}"
c4() { o="$(run "$D")"; r=$?; b="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["binding"]))' "$T/resume/$D.json" 2>/dev/null)"
  p="$(E_ python3 -c 'import json,sys; sys.path.insert(0,sys.argv[1]); import ft_seat_pi as p; d=p.binding(sys.argv[2]); print(d["name_source"], json.dumps(d["binding"]))' "${BD:-$T/bin}" "$D" | tail -1)"
  echo "$r [$b] [$p]"; }
c5() { o="$(run "$E")"; r=$?; echo "$r $(grep -cxF "NORECORD $E Pi 결속 판정 불가 · 세션 바뀜" <<< "$o") rec=$(ls "$T/resume" | wc -l | tr -d ' ')"; }
W1="0 1 ft2-intent,pi,sa expect=0"; W2="1 1 rec=0"; W3="0 [NORECORD $C tmux 세션 없음] rec=0"; W4="0 [$WANT4] [session_info $WANT4]"; W5="0 1 rec=0"

echo "== 반례 ①~⑤"
chk "① 명부 밖 ft2 pi 나노 → RESUME ok · ft2-intent · expect rc0" "$(c1)" "$W1"
chk "② 시간 창 안 세션 파일 2개 → 판정 불가 rc1 · 기록 0" "$(c2)" "$W2"
chk "③ intent holder ≠ 좌석 → claude 탐색 그대로" "$(c3)" "$W3"
chk "④ tmuxc 좌석 → v3 결속 바이트 그대로" "$(c4)" "$W4"
chk "⑤ intent.at+180초 새 세션 → NORECORD 세션 바뀜 · 기록 0" "$(c5)" "$W5"

echo "== 변이 M1~M5 (사본에서만)"
mut() { local d="$T/m$1"; mkdir -p "$d"; for f in $FILES; do cp "$BIN/$f" "$d/" 2>/dev/null; done
  python3 - "$d/$2" "$3" "$4" <<'PY'
import sys
p, mark, repl = sys.argv[1:4]
t = open(p, encoding="utf-8").read(); print(t.count(mark)); open(p, "w", encoding="utf-8").write(t.replace(mark, repl))
PY
}
chk "M1 표지 1(시간 창 대신 가장 새 파일)" "$(mut 1 ft_seat_pi_ft2.py '    if len(hits) != 1:' '    hits = sorted(hits)[-1:]
    if len(hits) != 1:')" 1
diff_ "M1 → ② FAIL" "$(BD="$T/m1" c2)" "$W2"
chk "M2 표지 1(intent holder 검사 빼기)" "$(mut 2 ft_seat_pi_ft2.py 'intent.get("FT2_HOLDER") != seat' 'False')" 1
diff_ "M2 → ③ FAIL" "$(BD="$T/m2" c3)" "$W3"
chk "M3 표지 1(env 있어도 2.0 갈래 먼저)" "$(mut 3 ft_seat_pi.py 'if "TMUXC_PI_SESSION_ID" not in env:' 'if True:')" 1
diff_ "M3 → ④ FAIL" "$(BD="$T/m3" c4)" "$W4"
chk "M4 표지 1(pi_seat_resume 이 source 를 pi-session 으로 다시 만듦)" "$(mut 4 ft_roster_lib.py 'binding=b["binding"]' 'binding=dict(b["binding"], source="pi-session")')" 1
diff_ "M4 → ① FAIL" "$(BD="$T/m4" c1)" "$W1"
chk "M5 표지 1(세션 바뀜 검사 빼기)" "$(mut 5 ft_seat_pi_ft2.py '    if late:' '    if False:')" 1
diff_ "M5 → ⑤ FAIL" "$(BD="$T/m5" c5)" "$W5"
for f in $FILES; do [ -f "$BIN/$f" ] || continue; cmp -s "$BIN/$f" "$T/bin/$f" || bad "본 파일 사본 바뀜 $f"; done

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
