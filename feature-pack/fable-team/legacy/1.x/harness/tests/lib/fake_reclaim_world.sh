#!/usr/bin/env bash
# fake_reclaim_world.sh — ft-resource-reclaim.sh 시험 공용 «가짜 세계» (가짜 tmux·pgrep·ps·nano-close·seat-status·mbox·문지기 + setup·run·addnano·swapworld).
# test_resource_reclaim.sh · test_resource_reclaim_preventive.sh 가 source 한다(R332 H5 — 한 파일 5분 상한 때문에 분할). 호출 쪽이 T·BIN·ok/bad/eq/has/hasnt 를 먼저 정의한다.
# ── 가짜 도구 (한 번만 만들고 상태 파일만 시험마다 바꾼다) ──
F="$T/fake"; H="$T/home"; ST="$T/st"; mkdir -p "$F" "$H/.claude/state/seat-resume" "$T/cards"
cat > "$F/tmux" <<EOF
#!/bin/bash
S="$ST/sessions"
case "\$1" in
  list-sessions) case "\$3" in *session_activity*) awk '{print \$1"|"\$2"|"\$3}' "\$S";; *) awk '{print \$1"|"\$3}' "\$S";; esac;;
  list-panes) if [ "\$2" = -a ]; then awk '{print \$1" "\$4}' "\$S"; else n="\${3#=}"; awk -v n="\$n" '\$1==n{print \$4}' "\$S"; fi;;
  show-options) n="\${@: -2:1}"; n="\${n#=}"; n="\${n%:}"; [ -f "$ST/active.\${n//#/_}" ] && echo 1;;
  kill-session) n="\${3#=}"; echo "\$n" >> "$ST/kill.log"; [ -f "$ST/kill.slow" ] && sleep 1; grep -v "^\$n " "\$S" > "\$S.new"; mv "\$S.new" "\$S";;
  *) exit 0;;
esac
EOF
cat > "$F/pgrep" <<EOF
#!/bin/bash
[ "\$1" = -P ] && awk -v p="\$2" '\$1==p{print \$2; f=1}END{exit !f}' "$ST/kids"
EOF
cat > "$F/ps" <<EOF
#!/bin/bash
case "\$*" in *ppid=*) exec /bin/ps "\$@";; *) k="\${@: -1}"; awk -v p="\$k" '\$1==p{sub(/^[0-9]+ /,""); print}' "$ST/cmds";; esac
EOF
printf '#!/bin/bash\necho called >> "%s/mktemp.calls"\nexec /usr/bin/mktemp "$@"\n' "$ST" > "$F/mktemp"
cat > "$F/seat-status.sh" <<EOF
#!/bin/bash
k="\${2//#/_}"
if [ -f "$ST/protectflip.req" ] && [ "\$2" = 'byz-t-role-claude#1' ] && [ ! -f "$ST/protect-flip" ]; then
  pc=\$(cat "$ST/protectc" 2>/dev/null || echo 0); echo \$((pc+1)) > "$ST/protectc"
fi
if [ -f "$ST/protectflip.req" ] && [ "\$2" = 'byz-t-role-claude#1' ] && [ ! -f "$ST/protect-flip" ] && [ "\$(cat "$ST/protectc")" -ge 2 ]; then
  python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["_master"]="byz-t-role-claude#1";json.dump(d,open(p,"w"))' "$ST/seats.json"; touch "$ST/protect-flip"
fi
if [ -f "$ST/flip.\$k" ]; then c=\$(cat "$ST/flipc.\$k" 2>/dev/null || echo 0); echo \$((c+1)) > "$ST/flipc.\$k"; [ "\$c" -ge "\$(cat "$ST/flip.\$k")" ] && { echo "WORKING - - - jsonl"; exit 0; }; fi
[ -f "$ST/turn.\$k" ] && cat "$ST/turn.\$k" || echo "IDLE 2026-10-15T00:00:00Z 1 1 jsonl"
EOF
cat > "$F/nano-close.sh" <<EOF
#!/bin/bash
echo "\$*" >> "$ST/nc.log"
k="\${1//#/_}"
if [ -f "$ST/nc.reject.\$k" ]; then echo "REJECT \$1"; echo "  - ⑤cherry 미반입"; exit 1; fi
grep -v "^\$1 " "$ST/sessions" > "$ST/sessions.new"; mv "$ST/sessions.new" "$ST/sessions"; echo "CLOSED \$1"
EOF
cat > "$F/mbox.sh" <<EOF
#!/bin/bash
case "\$1" in
  send) echo "\$*" >> "$ST/mbox.log"; echo "QUEUED";;
  peek) k="\${2//#/_}"
    if [ -f "$ST/pendflip.\$k" ]; then c=\$(cat "$ST/pendflipc.\$k" 2>/dev/null || echo 0); echo \$((c+1)) > "$ST/pendflipc.\$k"; [ "\$c" -ge 1 ] && { echo "pending=1 scanned=1"; exit 0; }; fi
    echo "pending=\$( [ -f "$ST/pend.\$k" ] && cat "$ST/pend.\$k" || echo 0 ) scanned=1";;
esac
EOF
cat > "$F/gate.sh" <<EOF
#!/bin/bash
[ -f "$ST/disk.mode" ] && { echo "REJECT resource disk=1GiB limit=30GiB"; exit 3; }
n=\$(grep -c . "$ST/sessions"); l=\${FT_TEST_LIMIT:-6}
[ "\$n" -gt "\$l" ] && { echo "REJECT resource agents=\$n limit=\$l"; exit 3; }
echo "OK disk=99GiB agents=\$n"
EOF
chmod +x "$F"/*

NOW=$(date +%s)
mkseat() { # 이름 idle분 attached pane_pid
  printf '%s %s %s %s\n' "$1" "$((NOW - $2*60))" "$3" "$4" >> "$ST/sessions"; }
mkrecord() { # 이름 pane_pid child_pid
  local u="uuid-$RANDOM$RANDOM" d="$T/cwd"; mkdir -p "$d"; : > "$T/$u.jsonl"
  python3 -c 'import json,sys;json.dump({"name":sys.argv[1],"engine":"claude","uuid":sys.argv[2],"jsonl":sys.argv[3],"cwd":sys.argv[4],"model":"claude-sonnet-5-5[1m]","pid":sys.argv[5]},open(sys.argv[6],"w"))' \
    "$1" "$u" "$T/$u.jsonl" "$d" "$3" "$H/.claude/state/seat-resume/$1.json"
  echo "$2 $3" >> "$ST/kids"; }
# r500: 착지 판정용 가짜 팩 리포(main = origin/main · 나노 a~h 가지 = main 조상 → ancestor 착지) — 기존 시험의 «병합 끝 나노» 가 그대로 착지로 읽힌다
P="$T/pack"; mkdir -p "$P"; git -C "$P" init -q -b main; git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
git -C "$P" update-ref refs/remotes/origin/main HEAD; for c in a b c d e f g h; do git -C "$P" branch "nano/$c"; done
SWAP_LOW="total = 1000.00M  used = 100.00M  free = 900.00M  (encrypted)"   # 압력 아님(10%) — 시험 기본값(실 sysctl 을 읽지 않는다)

setup() {   # 시험마다 새 세계
  NOW=$(date +%s)   # r921: 세계를 만드는 시점 기준 — 파일 로드 시각에 고정하면 시험이 길어질수록 idle 분이 흘러 «닫히면 안 되는 좌석» 이 닫힌다(«5» ≠ «3» 로 헛빨강)
  rm -rf "$ST" "$T/root"; mkdir -p "$ST" "$T/root/.fable-team/state"; rm -f "$H/.claude/state/seat-resume/"*.json
  : > "$ST/sessions"; : > "$ST/kids"; : > "$ST/cmds"; cp /dev/null "$F/mailbox.jsonl"
  local c
  for c in a b c d e; do echo "card $c" > "$T/cards/$c.md"; done
  # 나노 5 (a: 가장 오래 쉼·닫힘 후보 / b: attached / c: WORKING / d: pending / e: 닫을 수 있으나 need 밖)
  mkseat "byz-t-nano-a#0" 120 0 90001; mkseat "byz-t-nano-b#0" 110 1 90002; mkseat "byz-t-nano-c#0" 105 0 90003
  mkseat "byz-t-nano-d#0" 100 0 90004; mkseat "byz-t-nano-e#0" 60 0 90005
  echo "WORKING - - - jsonl" > "$ST/turn.byz-t-nano-c_0"; echo 2 > "$ST/pend.byz-t-nano-d_0"
  # 직전 세대: role(기록 O·닫힘 후보) · erole(기록 없음) · vrole(V65 active) · srole(라이브 서버)
  mkseat "byz-t-role-claude#1" 100 0 91001; mkseat "byz-t-role-claude#2" 3 0 91002; mkrecord "byz-t-role-claude#1" 91001 4101
  mkseat "byz-t-erole-claude#1" 99 0 91003; mkseat "byz-t-erole-claude#2" 3 0 91004
  mkseat "byz-t-vrole-claude#1" 98 0 91005; mkseat "byz-t-vrole-claude#2" 3 0 91006; mkrecord "byz-t-vrole-claude#1" 91005 4102; touch "$ST/active.byz-t-vrole-claude_1"
  mkseat "byz-t-srole-claude#1" 97 0 91007; mkseat "byz-t-srole-claude#2" 3 0 91008; mkrecord "byz-t-srole-claude#1" 91007 4103; echo "4103 uvicorn app:main --port 38301" >> "$ST/cmds"
  # 명부 밖(다른 프로젝트) 직전 세대 — 재개 기록은 유효하나 BYZ 명부에 행이 없다 (DA⑥ H1)
  mkseat "other-proj-claude#1" 150 0 93001; mkseat "other-proj-claude#2" 3 0 93002; mkrecord "other-proj-claude#1" 93001 4104
  # 범위 밖: codex DA · 상위 오케(master·planner)
  mkseat "byz-t-da-codex#0" 300 0 92001; mkseat "byz-t-master-claude#1" 200 0 92002; mkseat "byz-t-planner-claude#1" 200 0 92003
  python3 - "$ST/seats.json" "$T/cards" <<'PY'
import json, sys
d = {"_master": "byz-t-master-claude#1", "_hil_route": "byz-t-planner-claude#1"}
for k in "abcde": d[f"byz-t-nano-{k}#0"] = {"role": "nano", "agent": "claude", "index": f"{sys.argv[2]}/{k}.md"}
d["byz-t-da-codex#0"] = {"role": "da", "agent": "codex"}
for b in ("role", "erole", "vrole", "srole"):
    for g in (1, 2): d[f"byz-t-{b}-claude#{g}"] = {"role": b, "agent": "claude"}
json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY
  for c in a b c d e; do echo "{\"seq\": $((10000+$(printf %d "'$c"))), \"from\": \"byz-t-nano-$c#0\", \"to\": \"x\", \"body\": \"완료\"}" >> "$F/mailbox.jsonl"; done
  : > "$ST/kill.log"; : > "$ST/nc.log"; : > "$ST/mbox.log"
}

run() {   # run <스크립트> [도구 인자…] — 가짜를 env/PATH 로 주입(추가 env 는 `VAR=값 run …` 으로)
  local s="$1"; shift
  PATH="$F:$PATH" HOME="$H" TOKEN_SENTINEL=sk-ant-SECRET-xyz FT_RES_ROOT="$T/root" FT_SEATS_JSON="$ST/seats.json" FT_SEAT_STATUS="$F/seat-status.sh" FT_NANO_CLOSE="$F/nano-close.sh" \
    FT_MBOX_SH="$F/mbox.sh" ZC_RESUME_DIR="$H/.claude/state/seat-resume" FT_PRESS_PERMIT_DIR="$T/permits" FT_RECLAIM_LOCK_TRIES=10 \
    FT_PACK_ROOT="${FT_PACK_ROOT:-$P}" FT_LANDED_CHECK="${FT_LANDED_CHECK:-$BIN/ft-landed-check.sh}" FT_SWAPUSAGE="${FT_SWAPUSAGE-$SWAP_LOW}" bash "$s" "$@" 2>&1
}
printf '#!/bin/bash\n[ -f "%s/rej.hard" ] && { cat "%s/rej.text"; exit 3; }\n[ -f "%s/rej.once" ] && [ ! -s "%s/kill.log" ] && [ ! -s "%s/nc.log" ] && { cat "%s/rej.text"; exit 3; }\necho "OK disk=99GiB"\n' "$ST" "$ST" "$ST" "$ST" "$ST" "$ST" > "$F/gate-res.sh"
printf '#!/bin/bash\necho "! bash /tmp/h777"\n' > "$F/hil.sh"; chmod +x "$F/gate-res.sh" "$F/hil.sh"
addnano() {   # 이름 idle분 카드경로 — 명부 행·보고 seq·카드 파일·세션을 한 번에 (setup 직후에 부른다)
  mkdir -p "$(dirname "$3")"; echo "card" > "$3"; mkseat "$1" "$2" 0 "9${RANDOM}"
  python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d[sys.argv[2]]={"role":"nano","agent":"claude","index":sys.argv[3]};json.dump(d,open(p,"w"),ensure_ascii=False)' "$ST/seats.json" "$1" "$3"
  echo "{\"seq\": $((20000+RANDOM)), \"from\": \"$1\", \"to\": \"x\", \"body\": \"완료\"}" >> "$F/mailbox.jsonl"
}
swapworld() { setup
  addnano "byz-t-nano-f#0" 6 "$T/cards2/indices/완성/f.md"; addnano "byz-t-nano-g#0" 3 "$T/cards2/indices/완성/g.md"; addnano "byz-t-nano-h#0" 6 "$T/cards2/indices/진행/h.md"
  : > "$ST/rej.text"; }
SWAP_REJ="REJECT resource swap=13000MiB limit=12288MiB"
