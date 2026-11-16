#!/usr/bin/env bash
# test_seat_retire_ft2_pi_other_seat_r2100.sh — r2100: ft2 pi 좌석 worktree 에 생긴 «산 남의 좌석» 세션(그 좌석 tmux env
#   TMUXC_PI_SESSION_ID 로 증명)은 창 뒤 late 로 세지 않는다 → 같은 worktree 후계로의 은퇴 = rc0 RESUME ok.
#   ① 방 사건 꼴 은퇴 rc0 · RESUME ok · 기록 = 첫 세션   ② 결속 값 = 남의 세션 파일을 지운 판과 같음   ③ 은퇴 뒤 ft_seat_bind --expect rc0
#   ④ 주인 없는 late → REJECT 세션 바뀜   ⑤ 증명 1 + 주인 없음 1 → ④ 와 같음   ⑥ 죽은 주인 · 이름만 같음 · 좌석 자신 env = 증거 아님
#   ⑦ list-sessions 실패 = REJECT RuntimeError · env 조회 «can't find session» = 그 세션만 건너뜀   ⑧ late 0 = tmux 추가 호출 0
#   ⑨ 기록 경로 NORECORD 세션 바뀜 · tmuxc 결속 그대로   ⑩ 창 안 0 · 2 · pane cwd ≠ worktree = 사유 그대로   변이 M1~M5(사본에서만)
# 모든 쓰기는 mktemp 안(가짜 tmux·ps·HOME·명부·intent·세션 파일) — 실 명부·실 tmux·실 pi 세션 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
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
for f in ft_seat_pi.py ft_seat_pi_ft2.py; do cmp -s "$BIN/$f" "$KIT/$f" && ok "cmp $f" || bad "cmp $f 다름"; done

FILES="ft-seat-retire.sh ft_seat_bind.py ft_roster_lib.py ft_seat_pi.py ft_seat_pi_ft2.py ft_seat_pi_turn.py ft_seat_codex.py"
TM="$T/tm"; PS="$T/psess"; F2="$T/ft2root"; L="$F2/.fable-team/teams/room/runtime/launch"
mkdir -p "$T/bin" "$T/fake" "$T/home" "$T/resume" "$TM" "$PS" "$L" "$T/wt"
for f in $FILES; do cp "$BIN/$f" "$T/bin/"; done
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -u ] && shift
echo "$*" >> "$TM/calls"
s=""; for a in "$@"; do case "$a" in =*) s="${a#=}";; esac; done
live() { cut -f1 "$TM/panes" | grep -qxF "$1" && [ ! -f "$TM/gone-$1" ]; }
case "$1" in
  list-panes) cat "$TM/panes";;
  list-sessions) [ -f "$TM/lsfail" ] && { echo "error connecting to /x" >&2; exit 1; }; cut -f1 "$TM/panes";;
  has-session) live "$s" || { echo "can't find session: $s" >&2; exit 1; };;
  show-environment) live "$s" || { echo "can't find session: $s" >&2; exit 1; }; [ -f "$TM/env-$s" ] || exit 0; v="${!#}"
    case "$v" in =*) cat "$TM/env-$s";; *) grep "^$v=" "$TM/env-$s" || { echo "unknown variable: $v" >&2; exit 1; };; esac;;
  *) exit 0;;
esac
EOF
cat > "$T/fake/ps" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = -p ] && [ -f "$TM/comm-$2" ]; then case "$4" in pid=) echo "$2";; comm=) cat "$TM/comm-$2";; esac; exit 0; fi
exec /bin/ps "$@"
EOF
chmod +x "$T/fake/"* "$T/bin/"*.sh
AT="$(python3 -c 'import datetime as d; print((d.datetime.now()-d.timedelta(hours=3)).strftime("%Y-%m-%dT%H:%M:%S"))')"   # intent.at = 로컬 시각
z() { python3 -c 'import datetime as d,sys; t=d.datetime.fromisoformat(sys.argv[1]).astimezone(d.timezone.utc)+d.timedelta(seconds=int(sys.argv[2])); print(t.strftime("%Y-%m-%dT%H:%M:%S.123Z"))' "$AT" "$1"; }
pane() { printf '%s\t%s\t%s\t0\n' "$1" "$2" "$3" >> "$TM/panes"; echo pi > "$TM/comm-$2"; }   # <좌석> <pid> <cwd>
seat() { local w="$T/wt/$3"; mkdir -p "$w"; pane "$1" "$2" "${4:-$w}"   # <좌석> <pid> <work> [pane cwd] — ft2 갈래(env 에 TMUXC_PI_SESSION_ID 없음)
  printf 'FT2_ATTEMPT=a1\nFT2_HOLDER=%s\nFT2_ROOT=%s\nFT2_TEAM=room\nFT2_WORK=%s\n' "$1" "$F2" "$3" > "$TM/env-$1"
  printf '{"FT2_ATTEMPT":"a1","FT2_HOLDER":"%s","FT2_WORK":"%s","at":"%s","state":"opened","worktree":"%s"}\n' "$1" "$3" "$AT" "$w" > "$L/$3@a1.intent"; }
owner() { mkdir -p "$T/wt/o-$1"; pane "$1" "$2" "$T/wt/$3"; printf 'TMUXC_PI_SESSION_ID=%s\n' "$4" > "$TM/env-$1"; }   # <좌석> <pid> <work(같은 worktree)> <sid>
sess() { local w="$T/wt/$1"; local d="$PS/--$(printf '%s' "${w#/}" | tr / -)--"; mkdir -p "$d"   # <work> <uuid> <intent.at 뒤 초> <session_info 이름>
  printf '{"type":"session","version":3,"id":"%s","timestamp":"%s","cwd":"%s"}\n{"type":"model_change","id":"b","modelId":"og/m1"}\n{"type":"session_info","name":"%s"}\n' "$2" "$(z "$3")" "$w" "$4" > "$d/$(z "$3" | tr : -)_$2.jsonl"; echo "$d/$(z "$3" | tr : -)_$2.jsonl"; }
A='byz-room-arch-pi#39'; B='byz-room-arch-pi#40'
seat "$A" 5101 wa; SA="$(sess wa sa 0 "$A")"; SB="$(sess wa sb 7592 "$B")"; owner "$B" 5102 wa sb
seat "$A.4" 5141 w4; sess w4 s4 0 "$A.4" >/dev/null; sess w4 x4 600 "$B" >/dev/null                         # ④ 주인 없음
seat "$A.5" 5151 w5; sess w5 s5 0 x >/dev/null; sess w5 b5 600 "$B.5" >/dev/null; sess w5 x5 900 x >/dev/null; owner "$B.5" 5152 w5 b5   # ⑤
seat "$A.6" 5161 w6; sess w6 s6 0 x >/dev/null; sess w6 b6 600 "$B.6" >/dev/null; printf 'TMUXC_PI_SESSION_ID=b6\n' > "$TM/env-$B.6"   # ⑥ B.6 = 명부·env 파일만(tmux 목록 0)
seat "$A.7" 5171 w7; sess w7 s7 0 x >/dev/null; sess w7 b7 600 "$B.7" >/dev/null; owner "$B.7" 5172 w7 b7   # ⑦
seat "$A.8" 5181 w8; sess w8 s8 0 x >/dev/null                                                              # ⑧ late 0
seat "$A.9" 5191 w9; sess w9 s9 0 x >/dev/null; sess w9 x9 600 x >/dev/null                                 # ⑨ ④ 꼴 기록 경로
D='byz-room-tester-pi#3'; mkdir -p "$T/wt/wd"; pane "$D" 5199 "$T/wt/wd"; printf 'TMUXC_PI_SESSION_ID=sd\n' > "$TM/env-$D"; SD="$(sess wd sd 0 "$D")"
seat "$A.a" 5201 wa0                                                                                      # ⑩ 창 안 0
seat "$A.b" 5211 wb2; sess wb2 sb2 0 x >/dev/null; sess wb2 bb 30 "$B.b" >/dev/null; owner "$B.b" 5212 wb2 bb   # ⑩ 창 안 2(하나는 남의 것)
mkdir -p "$T/wt/elsewhere"; seat "$A.c" 5221 wc "$T/wt/elsewhere"; sess wc sc 0 x >/dev/null                # ⑩ pane cwd ≠ worktree
R="$T/repo"; mkdir -p "$R/.fable-team"; git -C "$R" init -q; S="$R/.fable-team/seats.json"
python3 - "$S" "$A" "$B" "$A.4" "$A.5" "$A.6" "$B.6" "$A.7" "$A.9" "$D" <<'PY'
import json, sys
rows = {n: {"role": "nano", "agent": "pi", "model": "og/m1", "tick": None} for n in sys.argv[2:]}
rows[sys.argv[9]]["_replaced_by"] = "byz-room-arch-pi#90"
json.dump(dict(_master="byz-room-master-pi#49", **rows), open(sys.argv[1], "w"), ensure_ascii=False)
PY
E_() { (cd "$R" && PATH="$T/fake:$PATH" TM="$TM" FT_TMUX="$T/fake/tmux" HOME="$T/home" ZC_RESUME_DIR="$T/resume" FT_PI_SESSIONS="$PS" \
  FT_SEAT_REAP_BIN="$T/bin/ft-seat-reap.sh" FT_SEAT_QUIESCE_BIN="$T/bin/ft-seat-quiesce.sh" "$@" 2>&1); }
ret() { rm -f "$T/resume/"*; E_ bash "${BD:-$T/bin}/ft-seat-retire.sh" "$@" --seats "$S"; }
fp() { md5 -q "$S" 2>/dev/null || md5sum "$S" | cut -d' ' -f1; }
rej() { local h o r; h="$(fp)"; o="$(ret "$1" "$1-next")"; r=$?   # <구> → «rc REJECT줄수 명부바뀜 기록수 첫줄»
  [ "$(fp)" = "$h" ] && h=same || h=changed; echo "$r $h rec=$(ls "$T/resume" | wc -l | tr -d ' ') [$(grep '^REJECT' <<< "$o" | head -1)]"; }
loc() { E_ python3 -c 'import json,sys; sys.path.insert(0,sys.argv[1]); import ft_seat_pi as p; r=p.locate(sys.argv[2],source=True); print(json.dumps([r[0],r[1]["id"],r[2],r[3],r[4]]))' "${BD:-$T/bin}" "$1" | tail -1; }
c1() { local s; s="$(cp "$S" "$T/S1"; o="$(ret "$A" "$B")"; r=$?
  echo "$r $(grep -c "^RETIRED $A -> $B" <<< "$o") $(grep -A1 "^RETIRED $A -> $B" <<< "$o" | sed -n 2p | grep -c "^RESUME ok $T/resume/$A.json")" \
    "$(jq -r --arg sa "$SA" '[(.jsonl==$sa),.uuid,.binding.source]|map(tostring)|join(",")' "$T/resume/$A.json" 2>/dev/null)" \
    "$(jq -r --arg a "$A" '.[$a]._replaced_by' "$S")")"; echo "$s"; }
c3() { E_ python3 "${BD:-$T/bin}/ft_seat_bind.py" "$A" --expect "$T/resume/$A.json" >/dev/null; echo "expect=$?"; cp "$T/S1" "$S"; }
W1="0 1 1 true,sa,ft2-intent $B"; W3="expect=0"
WR="1 same rec=0 [REJECT Pi 결속 판정 불가 · 세션 바뀜]"

echo "== 반례 ①~③ (P1)"
c2() { local v1 v2; v1="$(loc "$A")"; mv "$SB" "$T/sb.away"; v2="$(loc "$A")"; mv "$T/sb.away" "$SB"
  [ -n "$v1" ] && [ "$v1" = "$v2" ] && echo same || echo "diff [$v1] [$v2]"; }
chk "② A 결속 값 = sb 파일 지운 판과 같음(경로·id·pid·cwd·source)" "$(c2)" same
chk "① 방 사건 꼴 은퇴 → rc0 · RETIRED · 다음 줄 RESUME ok · 기록 = sa · ft2-intent · _replaced_by" "$(c1)" "$W1"
chk "③ 은퇴 뒤 ft_seat_bind --expect rc0" "$(c3)" "$W3"

echo "== 반례 ④~⑥ (P2)"
chk "④ 주인 없는 late → REJECT 세션 바뀜 · 명부 쓰기 0 · 기록 0" "$(rej "$A.4")" "$WR"
chk "⑤ late = 증명 1 + 주인 없음 1 → ④ 와 같음" "$(rej "$A.5")" "$WR"
chk "⑥ 주인 B.6 = 명부·이름뿐(tmux 목록 0) → ④ 와 같음" "$(rej "$A.6")" "$WR"
c6() { E_ python3 -c 'import sys; sys.path.insert(0,sys.argv[1]); import ft_seat_pi_ft2 as f; print(sorted(f.owners(sys.argv[2],sys.argv[3])))' "${BD:-$T/bin}" "$D" "$T/fake/tmux" | tail -1; }
W6="['b5', 'b7', 'bb', 'sb']"
chk "⑥ 좌석 자신의 env(sd) 는 증거 아님 · 산 남의 세션 env 만" "$(c6)" "$W6"

echo "== 반례 ⑦ ⑧ (P3)"
c7a() { touch "$TM/lsfail"; local o; o="$(rej "$A.7")"; rm -f "$TM/lsfail"; echo "$o"; }
W7A="1 same rec=0 [REJECT Pi 결속 판정 불가 · RuntimeError]"
chk "⑦ list-sessions rc1 → REJECT RuntimeError(«세션 바뀜» 0)" "$(c7a)" "$W7A"
c7b() { touch "$TM/gone-$B.7"; local o; o="$(rej "$A.7")"; rm -f "$TM/gone-$B.7"; echo "$o"; }
chk "⑦ B.7 env 조회 «can't find session» → B.7 만 건너뜀 → 세션 바뀜" "$(c7b)" "$WR"
c8() { : > "$TM/calls"; loc "$A.8" >/dev/null; tr '\n' '|' < "$TM/calls"; }
W8="show-environment -t =$A.8|list-panes -a -F #{session_name}	#{pane_pid}	#{pane_current_path}	#{pane_dead}|"   # 기준판 bin 으로 뜬 줄
chk "⑧ late 0 → tmux 호출 줄 = 기준판(list-sessions 0)" "$(c8)" "$W8"

echo "== 반례 ⑨ ⑩ (P4)"
c9() { local o; o="$(ret "$A.9" --record-only --verdict 2100)"; echo "$? $(grep -cxF "NORECORD $A.9 Pi 결속 판정 불가 · 세션 바뀜" <<< "$o") rec=$(ls "$T/resume" | wc -l | tr -d ' ')"; }
chk "⑨ 기록 경로 → NORECORD 세션 바뀜 · 기록 0" "$(c9)" "0 1 rec=0"
c9b() { E_ python3 -c 'import json,sys; sys.path.insert(0,sys.argv[1]); import ft_seat_pi as p; d=p.binding(sys.argv[2]); print(d["name_source"], json.dumps(d["binding"]))' "${BD:-$T/bin}" "$D" | tail -1; }
chk "⑨ tmuxc 좌석 결속 바이트 그대로" "$(c9b)" "session_info {\"source\": \"pi-session\", \"session\": \"$D\", \"uuid\": \"sd\", \"jsonl\": \"$SD\", \"pid\": 5199}"
c10() { E_ python3 "${BD:-$T/bin}/ft_seat_pi.py" "$1" | tail -1; }
chk "⑩ 창 안 0 → 후보 0개" "$(c10 "$A.a")" "판정 불가 Pi: Pi session 후보 0개"
chk "⑩ 창 안 2(하나는 남의 것) → 후보 2개" "$(c10 "$A.b")" "판정 불가 Pi: Pi session 후보 2개"
chk "⑩ pane cwd ≠ worktree → 사유 그대로" "$(c10 "$A.c")" "판정 불가 Pi: Pi pane cwd ≠ intent worktree"

echo "== 변이 M1~M5 (사본에서만 · 변이마다 원본 1회 더)"
mut() { local d="$T/m$1"; mkdir -p "$d"; for f in $FILES; do cp "$BIN/$f" "$d/"; done
  python3 - "$d/$2" "$3" "$4" <<'PY'
import sys
p, mark, repl = sys.argv[1:4]
t = open(p, encoding="utf-8").read(); print(t.count(mark)); open(p, "w", encoding="utf-8").write(t.replace(mark, repl))
PY
}
chk "M1 표지 1(남의 세션 빼기 끔)" "$(mut 1 ft_seat_pi_ft2.py 'late = set(late) - owners(*owner)' 'late = late')" 1
diff_ "M1 → ② FAIL" "$(BD="$T/m1" c2)" same; diff_ "M1 → ① FAIL" "$(BD="$T/m1" c1)" "$W1"; diff_ "M1 → ③ FAIL" "$(BD="$T/m1" c3)" "$W3"
chk "M1 원본 ①" "$(c1)" "$W1"; chk "M1 원본 ③" "$(c3)" "$W3"
chk "M2 표지 1(주인 확인 없이 late 전부 뺌)" "$(mut 2 ft_seat_pi_ft2.py 'set(late) - owners(*owner)' 'set()')" 1
diff_ "M2 → ④ FAIL" "$(BD="$T/m2" rej "$A.4")" "$WR"; diff_ "M2 → ⑤ FAIL" "$(BD="$T/m2" rej "$A.5")" "$WR"; diff_ "M2 → ⑥ FAIL" "$(BD="$T/m2" rej "$A.6")" "$WR"
chk "M2 원본 ④⑤⑥" "$(rej "$A.4")$(rej "$A.5")$(rej "$A.6")" "$WR$WR$WR"
chk "M3 표지 1(좌석 자신의 env 도 증거)" "$(mut 3 ft_seat_pi_ft2.py 'name and name != seat' 'name')" 1
diff_ "M3 → ⑥ FAIL" "$(BD="$T/m3" c6)" "$W6"; chk "M3 원본 ⑥" "$(c6)" "$W6"
chk "M4 표지 1(조회 실패를 증거 없음으로 삼킴)" "$(mut 4 ft_seat_pi_ft2.py 'raise RuntimeError(f"tmux list-sessions' 'return set(); (f"tmux list-sessions')" 1
diff_ "M4 → ⑦ 첫 칸 FAIL" "$(BD="$T/m4" c7a)" "$W7A"; chk "M4 원본 ⑦" "$(c7a)" "$W7A"
chk "M5 표지 1(late 0 에도 list-sessions)" "$(mut 5 ft_seat_pi_ft2.py '    if late and owner:' '    if owner:')" 1
diff_ "M5 → ⑧ FAIL" "$(BD="$T/m5" c8)" "$W8"; chk "M5 원본 ⑧" "$(c8)" "$W8"
for f in $FILES; do cmp -s "$BIN/$f" "$T/bin/$f" || bad "본 파일 사본 바뀜 $f"; done

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
