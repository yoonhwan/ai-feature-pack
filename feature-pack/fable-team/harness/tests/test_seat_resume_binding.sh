#!/usr/bin/env bash
# test_seat_resume_binding.sh — R364 1단계: tmuxc 를 안 거친 «raw spawn» 좌석(claude 가 pane 프로세스 자체 · --name 없음)의 재개 기록 결속.
#   결속 판정기 하나 = ft_seat_bind.py · 소유 = 세션 파일 tmux 칸(<세션>:@window.%pane) 전부 == 지금 그 좌석 pane ∧ pid ∧ 시작시각 ≤ 파일 mtime ∧ 실행 주체 claude.
#   ⓐ세션 파일 두 꼴(u·d) ⓑ후보 정확히 1개 ⓒ소유 규칙(칸 부재만 legacy-name) ⓓ(d) 꼴 은퇴 → RESUME ok ⓔ남의 pane 파일 = 기록 0 ⓕ복제 0
#   ⓘ같은 세션 다른 pane ⓙ같은 이름 재생성 ⓚpid 재사용 ⓛ칸 깨짐 ⓜ칸 부재 legacy ⓝ번들 사본 cmp0 ⓞ공백 cwd ⓟrecord-only 명부 0 REJECT · 닫기 직전 재비교(--expect).
# 모든 쓰기는 mktemp scratch 안 — 가짜 tmux/pgrep/ps(PATH 앞 스텁) · 임시 HOME · 실 tmux·실 세션 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit"; COMM="$HERE/../../harness/comm"
RETIRE="$BIN/ft-seat-retire.sh"; BIND="$BIN/ft_seat_bind.py"; ZC="$KIT/zombie-clean/zombie-clean.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }

FK="$TMP/fake"; mkdir -p "$FK"
cat > "$FK/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  display)   # pane pid + 식별(<세션>:@window.%pane) · FAKE_PANE_ID 로 식별만 바꾼다 · FAKE_FLIP=1 이면 둘째 호출부터 다른 pane(기록 직전 재확인)
    [ -n "${FAKE_PANE_PID:-}" ] || exit 1
    n="${4#=}"; n="${n%:}"; id="${FAKE_PANE_ID:-$n:@1.%1}"
    if [ -n "${FAKE_FLIP:-}" ]; then c="$(cat "$FAKE_FLIP" 2>/dev/null || echo 0)"; echo $((c+1)) > "$FAKE_FLIP"; [ "$c" -ge 1 ] && id="$n:@9.%9"; fi
    printf '%s\t%s\n' "$FAKE_PANE_PID" "$id"; exit 0;;
  has-session) for a in ${FAKE_ALIVE:-}; do [ "=$a" = "$3" ] && exit 0; done; exit 1;;
esac
exit 1
EOF
cat > "$FK/pgrep" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-P" ] && { [ -n "${FAKE_PGREP_RC:-}" ] && { [ -n "${FAKE_PGREP_OUT:-}" ] && echo "$FAKE_PGREP_OUT"; exit "$FAKE_PGREP_RC"; }   # FAKE_PGREP_RC=N · 부분 출력 FAKE_PGREP_OUT
  for p in ${FAKE_CHILDREN:-}; do echo "$p"; done; exit 0; }
exit 1
EOF
cat > "$FK/ps" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = -o ]; then
  case "$2" in
    lstart=) echo "${FAKE_LSTART:-Mon Jan  1 00:00:00 2001}"; exit "${FAKE_LSTART_RC:-0}";;   # *_RC≠0 = 출력은 나가도 조회 오류
    comm=) echo "${FAKE_COMM:-/u/.local/bin/claude}"; exit "${FAKE_COMM_RC:-0}";;
  esac
  [ -n "${FAKE_ARGV:-}" ] && { echo "$FAKE_ARGV"; exit 0; }
fi
exit 1
EOF
chmod +x "$FK/tmux" "$FK/pgrep" "$FK/ps"

UU=11111111-2222-3333-4444-555555555555; WORK="$TMP/work"; mkdir -p "$WORK"
enc() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
SEAT='M#1'; NEW='M#2'; GOOD="$SEAT:@1.%1"
home() { local h="$TMP/h-$1" w="${2:-$WORK}"; mkdir -p "$h/.claude/sessions" "$h/.claude/projects/$(enc "$w")"; : > "$h/.claude/projects/$(enc "$w")/$UU.jsonl"; echo "$h"; }
# sfile <home> <pid> <name> <nameSource> <tmux칸 | 빈값=칸 부재(옛 claude)> [cwd]
sfile() {
  local t=""; [ -n "${5:-}" ] && t=",\"tmux\":\"$5\""
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s","name":"%s","nameSource":"%s"%s}' "$2" "$UU" "${6:-$WORK}" "$3" "$4" "$t" > "$1/.claude/sessions/$2.json"
}
seats() { printf '{"M#1": {"role": "master", "agent": "claude", "model": "m1", "tick": "t"}}' > "$1"; }
retire() { local s="$TMP/seats-$RANDOM.json"; seats "$s"; HOME="$1" PATH="$FK:$PATH" bash "$RETIRE" "$SEAT" "$NEW" --seats "$s"; }   # <home> · env FAKE_*
rec() { echo "$1/.claude/state/seat-resume/$SEAT.json"; }
second() { sed -n 2p <<< "$1"; }
norecord() { # <라벨> <출력> <사유 부분 문자열> <home>
  chk "$1 → NORECORD" "$(second "$2" | cut -d' ' -f1-2)" "NORECORD $SEAT"
  chk "$1 사유 «$3»" "$(second "$2" | grep -c -- "$3")" 1
  chk "$1 기록 파일 0" "$([ -e "$(rec "$4")" ] && echo yes || echo no)" no
}

# ⓐ(u) 정상 꼴 — 셸(100) 밑 claude(7001) · name=좌석 · nameSource=user · 칸=<좌석>:@1.%1 (기준선)
H="$(home u)"; sfile "$H" 7001 "$SEAT" user "$GOOD"
out="$(FAKE_PANE_PID=100 FAKE_CHILDREN="7000 7001" retire "$H")"
chk "ⓐ(u) 정상 꼴 RESUME ok" "$(second "$out")" "RESUME ok $(rec "$H")"
chk "ⓐ(u) 기록 pid=7001 · binding.source=tmux-col · session_name 칸 없음" "$(jq -r '[(.pid|tostring),.binding.source,(has("session_name")|tostring)]|join(",")' "$(rec "$H")" 2>/dev/null)" "7001,tmux-col,false"
chk "ⓐ binding 5칸(session·window·pane·pid·lstart)+source" "$(jq -r '.binding|[.session,.window,.pane,(.pid|tostring),.lstart]|join("|")' "$(rec "$H")" 2>/dev/null)" "M#1|@1|%1|7001|Mon Jan  1 00:00:00 2001"

# ⓓ(d) raw 꼴 — claude 가 pane pid(100) «자신» · name=wt-18 · derived · 칸=<좌석>:@1.%1 · 직계 자식에 세션 파일 없음(mcp 자식 7100)
H="$(home d)"; sfile "$H" 100 wt-18 derived "$GOOD"
out="$(FAKE_PANE_PID=100 FAKE_CHILDREN="7100" retire "$H")"
chk "ⓓ(d) raw 꼴 은퇴 → RESUME ok (세션 이름 wt-18 ≠ 좌석)" "$(second "$out")" "RESUME ok $(rec "$H")"
chk "ⓓ(d) 기록 pid=100 · uuid · model(명부 m1) · session_name=wt-18" "$(jq -r '[(.pid|tostring),.uuid,.model,.session_name]|join(",")' "$(rec "$H")" 2>/dev/null)" "100,$UU,m1,wt-18"

# ⓜ 칸 «부재» 만 legacy-name 후퇴 — name==좌석 ∧ pid 실재 → 기록 + source 기록 · name≠좌석 → 소유 불일치
H="$(home legacy)"; sfile "$H" 100 "$SEAT" user ""
out="$(FAKE_PANE_PID=100 FAKE_CHILDREN="" retire "$H")"
chk "ⓜ 칸 부재 + name==좌석 → RESUME ok" "$(second "$out" | cut -d' ' -f1-2)" "RESUME ok"
chk "ⓜ binding.source = legacy-name" "$(jq -r '.binding.source' "$(rec "$H")" 2>/dev/null)" legacy-name
H="$(home legacy-no)"; sfile "$H" 100 wt-18 derived ""
out="$(FAKE_PANE_PID=100 FAKE_CHILDREN="" retire "$H")"; norecord "ⓒ 칸 부재 + name≠좌석" "$out" "소유 불일치" "$H"

# ⓛ 칸이 «있는데» 형식 깨짐 → NORECORD (name==좌석 이어도 후퇴 0)
H="$(home broken)"; sfile "$H" 100 "$SEAT" user "garbage-no-pane"
out="$(FAKE_PANE_PID=100 FAKE_CHILDREN="" retire "$H")"; norecord "ⓛ 칸 형식 깨짐(name==좌석)" "$out" "형식 깨짐" "$H"
H="$(home broken2)"; sfile "$H" 100 "$SEAT" user "$SEAT"
out="$(FAKE_PANE_PID=100 FAKE_CHILDREN="" retire "$H")"; norecord "ⓛ 칸에 window·pane 없음" "$out" "형식 깨짐" "$H"

# ⓑ 후보 정확히 1개 — 후보 2(pane 자신 + 직계 자식 둘 다 세션 파일) = NORECORD · 0 = NORECORD · 사유가 서로 다름
H="$(home two)"; sfile "$H" 100 wt-18 derived "$GOOD"; sfile "$H" 7001 "$SEAT" user "$GOOD"
out="$(FAKE_PANE_PID=100 FAKE_CHILDREN="7001" retire "$H")"; norecord "ⓑ 후보 2개" "$out" "세션 파일 2개" "$H"
H="$(home zero)"
out="$(FAKE_PANE_PID=100 FAKE_CHILDREN="7001" retire "$H")"; norecord "ⓑ 후보 0개" "$out" "세션 파일 0개" "$H"
H="$(home notmux)"; sfile "$H" 100 wt-18 derived "$GOOD"
out="$(FAKE_PANE_PID="" retire "$H")"; norecord "ⓑ tmux 세션 없음" "$out" "tmux 세션 없음" "$H"

# ⓔ 남의 pane 세션 파일 — 칸이 다른 세션이면 name==좌석 이어도 기록 0 (이름 언급 ≠ 소유 · DA H2)
H="$(home foreign-child)"; sfile "$H" 7001 "$SEAT" user "OTHER#3:@9.%9"
out="$(FAKE_PANE_PID=100 FAKE_CHILDREN="7001" retire "$H")"; norecord "ⓔ 셸 밑 자식 칸=남의 세션" "$out" "소유 불일치" "$H"
H="$(home foreign-root)"; sfile "$H" 100 "$SEAT" user "OTHER#3:@9.%9"
out="$(FAKE_PANE_PID=100 FAKE_CHILDREN="" retire "$H")"; norecord "ⓔ pane pid 자신 칸=남의 세션" "$out" "소유 불일치" "$H"
H="$(home pidmis)"; printf '{"pid":9999,"sessionId":"%s","cwd":"%s","name":"wt-18","tmux":"%s"}' "$UU" "$WORK" "$GOOD" > "$H/.claude/sessions/100.json"
out="$(FAKE_PANE_PID=100 FAKE_CHILDREN="" retire "$H")"; norecord "ⓔ 파일 pid ≠ 후보 pid" "$out" "소유 불일치" "$H"

# ⓘ 같은 세션 다른 pane 의 파일(@1.%9 ≠ 지금 @1.%1) · ⓙ 같은 이름 재생성 세션(window·pane id 다름)
H="$(home otherpane)"; sfile "$H" 100 wt-18 derived "$SEAT:@1.%9"
out="$(FAKE_PANE_PID=100 FAKE_CHILDREN="" retire "$H")"; norecord "ⓘ 같은 세션 다른 pane" "$out" "소유 불일치" "$H"
H="$(home recreated)"; sfile "$H" 100 wt-18 derived "$GOOD"
out="$(FAKE_PANE_PID=100 FAKE_PANE_ID="$SEAT:@2.%7" FAKE_CHILDREN="" retire "$H")"; norecord "ⓙ 같은 이름 재생성(pane id 다름)" "$out" "소유 불일치" "$H"

# ⓚ pid 재사용 — 프로세스 시작시각(lstart)이 세션 파일 mtime 보다 늦으면 시간 모순 · 실행 주체가 claude 아니면 NORECORD
H="$(home reuse)"; sfile "$H" 100 wt-18 derived "$GOOD"
out="$(FAKE_PANE_PID=100 FAKE_LSTART="Mon Jan  1 00:00:00 2090" FAKE_CHILDREN="" retire "$H")"; norecord "ⓚ lstart > mtime" "$out" "시간 모순" "$H"
H="$(home notclaude)"; sfile "$H" 100 wt-18 derived "$GOOD"
out="$(FAKE_PANE_PID=100 FAKE_COMM=/bin/zsh FAKE_CHILDREN="" retire "$H")"; norecord "ⓚ 실행 주체 claude 아님" "$out" "claude 아님" "$H"

# 기록 직전 재확인 — 결속 뒤 pane 이 바뀌면(둘째 조회부터 다른 pane) 기록 0
H="$(home flip)"; sfile "$H" 100 wt-18 derived "$GOOD"; rm -f "$TMP/flip.cnt"
out="$(FAKE_PANE_PID=100 FAKE_FLIP="$TMP/flip.cnt" FAKE_CHILDREN="" retire "$H")"; norecord "재확인: 기록 직전 pane 교체" "$out" "재확인 불일치" "$H"

# ⓞ 공백 포함 cwd — 기록 cwd 보존 · 판정기 JSON 1줄이 jq 로 읽힘
W2="$TMP/work space"; mkdir -p "$W2"
H="$(home space "$W2")"; sfile "$H" 100 wt-18 derived "$GOOD" "$W2"
out="$(FAKE_PANE_PID=100 FAKE_CHILDREN="" retire "$H")"
chk "ⓞ 공백 cwd 은퇴 → RESUME ok" "$(second "$out" | cut -d' ' -f1-2)" "RESUME ok"
chk "ⓞ 기록 cwd·jsonl 공백 보존" "$(jq -r '[.cwd,.jsonl]|join("|")' "$(rec "$H")" 2>/dev/null)" "$W2|$H/.claude/projects/$(enc "$W2")/$UU.jsonl"
j="$(HOME="$H" PATH="$FK:$PATH" FAKE_PANE_PID=100 FAKE_CHILDREN="" python3 "$BIND" "$SEAT")"; rcj=$?
chk "ⓞ 판정기 CLI rc 0 · JSON 1줄 · cwd" "$rcj|$(printf '%s' "$j" | wc -l | tr -d ' ')|$(jq -r .cwd <<< "$j")" "0|0|$W2"
HOME="$H" PATH="$FK:$PATH" FAKE_PANE_PID="" python3 "$BIND" "$SEAT" > /dev/null; chk "ⓞ 판정기 CLI tmux 없음 rc 1" "$?" 1
python3 "$BIND" > /dev/null 2>&1; chk "ⓞ 판정기 CLI usage rc 2" "$?" 2

# 닫기 직전 재비교(--expect) — 같은 pane·pid·시작시각만 rc 0 · pane 교체·pid 재사용·binding 없는 옛 기록 = rc 1
H="$(home expect)"; sfile "$H" 100 wt-18 derived "$GOOD"; FAKE_PANE_PID=100 FAKE_CHILDREN="" retire "$H" > /dev/null; R="$(rec "$H")"
ex() { HOME="$H" PATH="$FK:$PATH" FAKE_PANE_PID=100 FAKE_CHILDREN="" "$@" python3 "$BIND" "$SEAT" --expect "${EXP:-$R}" > /dev/null; echo $?; }
chk "--expect 같은 pane·pid·lstart → rc 0" "$(ex env)" 0
chk "--expect pane 교체 → rc 1" "$(ex env FAKE_PANE_ID="$SEAT:@2.%7")" 1
chk "--expect pid 재사용(lstart 다름) → rc 1" "$(ex env FAKE_LSTART="Tue Feb  2 00:00:00 2010")" 1
jq 'del(.binding)' "$R" > "$TMP/nobind.json"; chk "--expect binding 없는 옛 기록 → rc 1" "$(EXP="$TMP/nobind.json" ex env)" 1
chk "--expect 후보에 pid 없음(자식 다른 pid) → rc 1" "$(HOME="$H" PATH="$FK:$PATH" FAKE_PANE_PID=555 FAKE_CHILDREN="" python3 "$BIND" "$SEAT" --expect "$R" > /dev/null; echo $?)" 1

# zombie-clean resume_record_pid_live — 같은 판정기(같은 폴더 고정 경로) · 없으면 닫지 않는다(rc 2)
zc_live() { # <판정기 폴더 복사 여부 yes|no> <env…>
  local d="$TMP/zc-$RANDOM"; mkdir -p "$d/rd"; cp "$R" "$d/rd/$SEAT.json"
  [ "$1" = yes ] && cp "$BIND" "$d/ft_seat_bind.py"; shift
  { echo 'ZC_FROM_LIVE=0'; sed -n '/^resume_record_file() {/,/^}/p;/^resume_record_pid_live() {/,/^}/p' "$ZC"; echo 'resume_record_pid_live "$1"'; } > "$d/fn.sh"
  env HOME="$H" ZC_RESUME_DIR="$d/rd" PATH="$FK:$PATH" FAKE_PANE_PID=100 FAKE_CHILDREN="" "$@" bash "$d/fn.sh" "$SEAT" 2>/dev/null; echo $?
}
chk "zombie-clean pid_live 같은 결속 → 살아 있음(rc 0)" "$(zc_live yes env)" 0
chk "zombie-clean pid_live pane 교체 → rc≠0" "$([ "$(zc_live yes env FAKE_PANE_ID="$SEAT:@2.%7")" != 0 ] && echo nonzero || echo zero)" nonzero
chk "zombie-clean pid_live 판정기 없음 → rc 2 (옛 판정 후퇴 0)" "$(zc_live no env)" 2

# DA⑥ r1 H1 — 조회 «오류»를 후보 부재/성공으로 바꾸지 않는다: pgrep rc 3분기(0 목록 · 1 무일치 · 그 밖 오류) · PID 토큰 검증 · lstart·comm rc 검사 · bind·expect 공유
H="$(home h1)"; sfile "$H" 100 wt-18 derived "$GOOD"; FAKE_PANE_PID=100 FAKE_CHILDREN="" retire "$H" > /dev/null; R1="$(rec "$H")"
cli() { HOME="$H" PATH="$FK:$PATH" FAKE_PANE_PID=100 FAKE_CHILDREN="" "$@" python3 "$BIND" "$SEAT"; }
cli_ex() { HOME="$H" PATH="$FK:$PATH" FAKE_PANE_PID=100 FAKE_CHILDREN="" "$@" python3 "$BIND" "$SEAT" --expect "$R1"; }
h1() { # <라벨> <env…> — bind·expect 둘 다 rc 2 · binding 0 · 사유에 «조회 불가·오류» 계열
  local lb="$1" o rc; shift; o="$(cli "$@" 2>/dev/null)"; rc=$?
  chk "H1 $lb → bind rc 2" "$rc" 2; chk "H1 $lb → binding 0" "$(jq -r 'has("binding")' <<< "$o" 2>/dev/null)" false
  cli_ex "$@" > /dev/null 2>&1; chk "H1 $lb → expect rc 2 (성공 0)" "$?" 2
}
h1 "pgrep rc2 · 빈 출력(pane 자신 유효)" env FAKE_PGREP_RC=2
h1 "pgrep rc2 · 부분 출력" env FAKE_PGREP_RC=2 FAKE_PGREP_OUT=7001
h1 "pgrep rc0 · 숫자 아닌 토큰" env FAKE_PGREP_RC=0 FAKE_PGREP_OUT=abc
h1 "ps comm rc≠0" env FAKE_COMM_RC=2
h1 "ps lstart rc≠0" env FAKE_LSTART_RC=2
chk "H1 pgrep rc1(정상 무일치) + pane 자신 후보 → 정상 결속 rc 0" "$(cli env FAKE_PGREP_RC=1 > /dev/null 2>&1; echo $?)" 0
H2="$(home h1b)"; sfile "$H2" 100 wt-18 derived "$GOOD"
s2="$TMP/seats-h1b.json"; seats "$s2"; out="$(HOME="$H2" PATH="$FK:$PATH" FAKE_PANE_PID=100 FAKE_PGREP_RC=2 bash "$RETIRE" "$SEAT" "$NEW" --seats "$s2")"
chk "H1 retire: pgrep 오류 → NORECORD «조회 불가» (기록 0)" "$(second "$out" | cut -d' ' -f1-3):$([ -e "$(rec "$H2")" ] && echo yes || echo no)" "NORECORD M#1 조회:no"
# ⓒ 주의 — retire 가 판정기 없이(번들 누락) 부팅되면 ImportError 가 아니라 명시 rc 2 ERROR 1줄
NB="$TMP/nobind"; mkdir -p "$NB"; cp "$RETIRE" "$NB/ft-seat-retire.sh"; s3="$TMP/seats-nb.json"; seats "$s3"
out="$(HOME="$H2" PATH="$FK:$PATH" FAKE_PANE_PID=100 bash "$NB/ft-seat-retire.sh" "$SEAT" "$NEW" --seats "$s3" 2>&1)"; rc=$?
chk "retire 판정기 없음 → rc 2 · ERROR 1줄(ImportError 아님)" "$rc|${out%% *}|$(grep -c Traceback <<< "$out")" "2|ERROR|0"

# ⓟ record-only 은퇴 자격 보존 — 명부 0(AIRAG 꼴)이면 결속이 맞아도 REJECT · 기록 0 (자동 면제 0)
R0="$TMP/repo"; mkdir -p "$R0/.fable-team"; git -C "$R0" init -q; H="$(home rec0)"; sfile "$H" 100 wt-18 derived "$GOOD"
out="$(cd "$R0" && env -u FT_SEATS_JSON HOME="$H" PATH="$FK:$PATH" FAKE_PANE_PID=100 FAKE_CHILDREN="" bash "$RETIRE" "$SEAT" --record-only)"; rc=$?
chk "ⓟ 명부 0 · record-only → REJECT rc 1" "${out%% *}:$rc" "REJECT:1"
chk "ⓟ 기록 파일 0" "$([ -e "$(rec "$H")" ] && echo yes || echo no)" no

# ⓕ 복제 0 · ⓝ 번들 사본 cmp0 — 결속은 ft_seat_bind.py 하나 · retire 에 pgrep 결속 0 · 사본 4곳 동일
chk "ⓕ ft-seat-retire.sh 에 pgrep -P 0" "$(grep -c 'pgrep.*-P' "$RETIRE")" 0
chk "ⓕ ft-seat-retire.sh 가 ft_seat_bind 를 부른다" "$([ "$(grep -c 'ft_seat_bind' "$RETIRE")" -gt 0 ] && echo yes || echo no)" yes
chk "ⓕ zombie-clean resume_record_pid_live 에 pgrep -P 0" "$(sed -n '/^resume_record_pid_live() {/,/^}/p' "$ZC" | grep -c 'pgrep.*-P')" 0
for c in "$KIT/fable-team/bin/ft_seat_bind.py" "$COMM/ft_seat_bind.py" "$KIT/zombie-clean/ft_seat_bind.py"; do
  chk "ⓝ 번들 사본 cmp0 $(basename "$(dirname "$c")")" "$(cmp -s "$BIND" "$c" && echo same || echo no)" same
done
chk "ⓝ ft-seat-retire.sh 키트 사본 cmp0" "$(cmp -s "$RETIRE" "$KIT/fable-team/bin/ft-seat-retire.sh" && echo same || echo no)" same
chk "ⓝ 판정기 bash 아님 · python3 문법 OK" "$(python3 -m py_compile "$BIND" && echo ok)" ok
n_big="$(grep -cE 'TIMEOUT_S *= *[0-9]{3,}|timeout *= *[0-9]{3,}' "$BIND")"; chk "ⓗ ft_seat_bind.py 큰 timeout 0 (7초 룰)" "${n_big:-0}" 0
chk "ⓗ ft_seat_bind.py ≤ 200줄" "$([ "$(wc -l < "$BIND")" -le 200 ] && echo yes || echo no)" yes

echo "---"; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL $fail"
exit "$fail"
