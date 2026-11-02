#!/usr/bin/env bash
# test_trigger_watch_r1285.sh — r1285 기억·트리거 원장 감시기(ft_trigger_watch.py) 반례 R1~R18·R11b·R11c·R12b·R14b + 변이 17 + kit cmp.
#   bash tests/test_trigger_watch_r1285.sh          # 반례 칸 + 변이 + cmp (부르는 쪽: ulimit -u + timeout 70)
#   bash tests/test_trigger_watch_r1285.sh green    # 반례 칸만
#   bash tests/test_trigger_watch_r1285.sh mut-a|mut-b   # 변이 1~9 · 10~17 따로(각 단독 70초 안)
#   bash tests/test_trigger_watch_r1285.sh mut      # 변이 17만(사본 bin 에 한 줄 어긋나게 → 같은 프로세스에서 그 칸이 FAIL 하는지 · 자기 재호출 0)
# 실 gcloud·실 우편함·실 명부 0: 가짜 로그 조회(FT_TRIGGER_LOG_CMD) · 가짜 mbox.sh · 임시 git 리포 · 가상 시계 파일(FT_TRIGGER_CLOCK_FILE) · 고정 sleep 0 · 자기 재호출 0.
[ "${FT_TEST_TRIGGER_WATCH_RUNNING:-0}" = 1 ] && { echo "SKIP 재진입(이미 도는 시험)"; exit 0; }
export FT_TEST_TRIGGER_WATCH_RUNNING=1
ulimit -u "$(( $(ps -u "$(id -u)" 2>/dev/null | wc -l | tr -d ' ') + 300 ))" 2>/dev/null || true
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
export TZ=Asia/Seoul
MODE="${1:-all}"; ONLY=""
sel() { [ -z "$ONLY" ] || case " $1 " in *" $ONLY "*) return 0;; *) return 1;; esac; }   # 변이 시험이 한 흐름만 돌린다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_TEST_TRIGGER_BIN:-$HERE/../bin}"; KIT="$HERE/../kit/fable-team/bin"; TOOL="$BIN/ft_trigger_watch.py"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$(dirname -- "$T")"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); PH() { echo "PHASE $1 +$(( $(date +%s) - T0 ))s"; }
CFO='byz-cfo-master-claude#3'; PL='byz-planner-master-claude#9'
NOWE="$(python3 -c 'import calendar,time;print(calendar.timegm(time.strptime("2026-11-01T11:00:00","%Y-%m-%dT%H:%M:%S")))')"

cat > "$T/stub.py" <<'EOF'
import json, os, re, sys, time
req = json.load(sys.stdin)
if os.environ.get("STUB_LOG"):
    open(os.environ["STUB_LOG"], "a").write(json.dumps(req) + "\n")
svc = (re.search(r'service_name="([^"]+)"', req["filter"]) or [None, ""])[1]
if os.environ.get("STUB_SLOW_SVC") == svc:
    time.sleep(5)
mode = os.environ.get("STUB_MODE", "")
if mode == "fail":
    print("boom", file=sys.stderr); sys.exit(1)
if mode == "badjson":
    print("not json"); sys.exit(0)
if mode == "notarray":
    print('{"entries": 5}'); sys.exit(0)
adv, cf = float(os.environ.get("STUB_ADV") or 0), os.environ.get("FT_TRIGGER_CLOCK_FILE")
if adv and cf:
    cur = float(open(cf).read()); open(cf, "w").write(str(cur + adv))
fld = "receiveTimestamp" if "receiveTimestamp>=" in req["filter"] else "timestamp"
lo = re.search(fld + r'>="([^"]+)"', req["filter"]).group(1)
ents = sorted((e for e in json.load(open(os.environ["STUB_DATA"])) if e.get("svc", svc) == svc and e[fld] >= lo), key=lambda e: (e[fld], e["insertId"]))
page = int(req["pageToken"][1:]) if req.get("pageToken") else 0   # 토큰 없이는 언제나 첫 쪽(같은 쪽 반복 반례)
out = {"entries": [{k: v for k, v in e.items() if k != "svc"} for e in ents[page * 50:(page + 1) * 50]]}
if (page + 1) * 50 < len(ents):
    out["nextPageToken"] = "p%d" % (page + 1)
print(json.dumps(out))
EOF
cat > "$T/logs.py" <<'EOF'
import json, sys
f, op, a = sys.argv[1], sys.argv[2], sys.argv[3:]
d = json.load(open(f))
if op == "add":    # id receive [timestamp] [svc]
    e = {"insertId": a[0], "receiveTimestamp": a[1], "timestamp": a[2] if len(a) > 2 else a[1]}
    if len(a) > 3: e["svc"] = a[3]
    d.append(e)
elif op == "addn":  # n prefix receive
    d += [{"insertId": "%s%03d" % (a[1], i), "receiveTimestamp": a[2], "timestamp": a[2]} for i in range(int(a[0]))]
json.dump(d, open(f, "w"))
EOF
cat > "$T/hold.py" <<'EOF'
import fcntl, sys
f = open(sys.argv[1], "w"); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[2], "w").write("held"); sys.stdin.readline()
EOF

new_root() {  # 임시 BYZ 꼴 리포(design/triggers) + 루트 표 + 명부(_master) + 가짜 mbox · 시계 = 11-01 11:00Z
  R="$(mktemp -d "$T/r.XXXXXX")"; R="$(cd "$R" && pwd -P)"; mkdir -p "$R/.fable-team/state" "$R/design/triggers"
  : > "$R/idx.rows"; : > "$R/calls.log"; : > "$R/sent.log"; : > "$R/maillog.jsonl"; printf '[]' > "$R/logs.json"; echo "$NOWE" > "$R/clock"
  git -C "$R" init -q -b main
  printf '*\t.\tmain\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"%s"}\n' "$CFO" > "$R/.fable-team/seats-cfo.json"; printf '{"_master":"%s"}\n' "$PL" > "$R/.fable-team/seats-planner.json"
  cat > "$R/mbox.sh" <<'EOF'
#!/usr/bin/env bash
D="$(dirname "$0")"
[ "$2" = "${FAKE_FAIL_TO:-}" ] && { echo "REJECT 가짜 실패"; exit 137; }
printf '%s\n' "$2" >> "$D/sent.log"
python3 -c 'import json,sys;print(json.dumps({"to":sys.argv[1],"body":sys.argv[2]}, ensure_ascii=False))' "$2" "$4" >> "$D/maillog.jsonl"
[ "$2" = "${FAKE_KILL_AFTER_TO:-}" ] && kill -9 "$PPID"
echo "QUEUED seq=1 to=$2"
EOF
}
mkitem() {  # <번호> <이름> [상태] [글자] [서비스] [담당] [noidx]
  local n="$1" nm="$2" st="${3:-열림}" g="${4-[TOUCH_SETTLE] settle failed}" svc="${5:-svc-$1}" tm="${6:-cfo}"
  { printf '# %s\n\n- 번호: %s\n- 상태: %s\n- 담당: %s\n- 조건 출처: prod-dev-log\n- 조건 서비스: %s\n' "$n" "$n" "$st" "$tm" "$svc"
    [ -z "$g" ] || printf -- '- 조건 글자: %s\n' "$g"
    printf -- '- 조건 심각도: ERROR\n- 할 일: 확인 %s\n- 근거: 판정 3045\n\n## 발화\n\n## 닫힘\n' "$n"; } > "$R/design/triggers/$n-$nm.md"
  [ "${7:-}" = noidx ] || printf '| %s | %s | %s | %s | %s | %s | x | — |\n' "$n" "$nm" "$st" "$tm" "$svc" "$g" >> "$R/idx.rows"
}
commit() {
  { printf '# 인덱스\n\n| 번호 | 이름 | 상태 | 담당 | 서비스 | 글자 | 할 일 | 발화 |\n|---|---|---|---|---|---|---|---|\n'; cat "$R/idx.rows"; } > "$R/design/triggers/INDEX.md"
  git -C "$R" add design; GIT_AUTHOR_DATE="2026-11-01T09:00:00+0900" GIT_COMMITTER_DATE="2026-11-01T09:00:00+0900" git -C "$R" -c user.name=t -c user.email=t@t commit -q -m items
}
logs() { python3 "$T/logs.py" "$R/logs.json" "$@"; }
run() {  # run <status|tick> — BUDGET(초 · 기본 63 = 감시기 예산 60) · EXTRA_ENV
  local dl=$(( $(cut -d. -f1 "$R/clock") + ${BUDGET:-63} ))
  OUT="$(env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" FT_TRIGGER_MAILLOG="$R/maillog.jsonl" FT_TRIGGER_LOG_CMD="python3 $T/stub.py" FT_TRIGGER_CLOCK_FILE="$R/clock" \
    FT_TICK_DEADLINE="$dl" STUB_DATA="$R/logs.json" STUB_LOG="$R/calls.log" ${EXTRA_ENV:-} python3 "${TOOL_RUN:-$TOOL}" "$@" 2>&1)"; RC=$?
}
sc() { grep -c -F -x "$1" "$R/sent.log" || true; }   # 받는이별 쪽지 수
calls() { grep -c . "$R/calls.log" || true; }
sd() { echo "$R/.fable-team/state/trigger-watch"; }
has() { case "$OUT" in *"$1"*) return 0;; *) return 1;; esac; }
chk() { if eval "$1"; then ok "$2"; else bad "$2 :: rc=$RC cfo=$(sc "$CFO") pl=$(sc "$PL") calls=$(calls) :: ${OUT:0:${DBG:-300}}"; fi; }

green() {
  if sel "R1 R2 R3 R4"; then
  # R1 열린 항목 1 · 로그 0 → 발화 0 · rc0 · 쪽지 0 · 항목 since 만들어짐
  new_root; mkitem T0001 a; commit; run tick
  chk '[ $RC = 0 ] && has "열린 항목 1 · 발화 0 · 판정 불가 0 · 판본 " && [ "$(sc $CFO)$(sc $PL)" = 00 ] && [ -f "$(sd)/T0001.since" ]' "R1 로그 0 → 발화 0 · rc0 · 쪽지 0"
  # R2 로그 A → 담당 master + planner 1통씩 · rc1 · 표식 2
  logs add A 2026-11-01T10:00:00Z; run tick
  chk '[ $RC = 1 ] && [ "$(sc $CFO)" = 1 ] && [ "$(sc $PL)" = 1 ] && [ "$(ls "$(sd)"/T0001/A.*.sent | wc -l | tr -d " ")" = 2 ] && grep -q "trigger:T0001:A" "$R/maillog.jsonl"' "R2 로그 A → 담당·planner 1통씩 · rc1 · 표식 2"
  # R3 같은 로그만 → 0통
  run tick; chk '[ $RC = 0 ] && [ "$(sc $CFO)$(sc $PL)" = 11 ]' "R3 같은 로그 A → 0통 · rc0"
  # R4 새 로그 B → 새 1통
  logs add B 2026-11-01T10:05:00Z; run tick; chk '[ $RC = 1 ] && [ "$(sc $CFO)$(sc $PL)" = 22 ]' "R4 새 로그 B → 새 1통"
  fi
  if sel "R5"; then
  # R5 조회 rc1 → 판정 불가 · rc3 · since 그대로 → 다음 바퀴 로그 놓침 0
  new_root; mkitem T0001 a; commit; run tick; s0="$(cat "$(sd)/T0001.since")"; logs add A 2026-11-01T10:30:00Z
  EXTRA_ENV="STUB_MODE=fail" run tick
  chk '[ $RC = 3 ] && has "판정 불가 — T0001" && [ "$(cat "$(sd)/T0001.since")" = "$s0" ] && [ "$(sc $CFO)$(sc $PL)" = 00 ]' "R5 조회 rc1 → 판정 불가 1줄 · rc3 · since 그대로"
  run tick; chk '[ $RC = 1 ] && [ "$(sc $CFO)$(sc $PL)" = 11 ]' "R5 다음 바퀴 로그 A → 1통(놓침 0)"
  fi
  if sel "R6"; then
  # R6 닫힌 항목(머리 상태 닫힘) + 맞는 로그 → 0통 · 조회 0
  new_root; mkitem T0001 a 닫힘; commit; logs add A 2026-11-01T10:00:00Z; run tick
  chk '[ $RC = 0 ] && has "열린 항목 0" && [ "$(calls)" = 0 ] && [ "$(sc $CFO)$(sc $PL)" = 00 ]' "R6 닫힌 항목 → 0통 · 조회 0"
  fi
  if sel "R7"; then
  # R7 꼴 틀린 항목(조건 글자 없음) + 정상 항목 → 꼴 틀림 1줄 · 정상은 그대로
  new_root; mkitem T0001 a; mkitem T0002 b 열림 ""; commit; logs add A 2026-11-01T10:00:00Z 2026-11-01T10:00:00Z svc-T0001; run tick
  chk '[ $RC = 1 ] && has "꼴 틀림 T0002 조건 글자" && [ "$(sc $CFO)$(sc $PL)" = 11 ]' "R7 꼴 틀림 1줄 · 정상 항목 판정 그대로"
  fi
  if sel "R8"; then
  # R8 인덱스에 없는 항목 → 인덱스 어긋남 1줄 · 발화 판정은 그대로
  new_root; mkitem T0001 a; mkitem T0003 c 열림 "[TOUCH_SETTLE] settle failed" "" "" noidx; commit; logs add A 2026-11-01T10:00:00Z 2026-11-01T10:00:00Z svc-T0003; run tick
  chk '[ $RC = 1 ] && has "인덱스 어긋남 T0003" && [ "$(sc $CFO)$(sc $PL)" = 11 ]' "R8 인덱스 어긋남 1줄 · 발화는 항목 파일 기준"
  fi
  if sel "R9"; then
  # R9 하루 같은 항목 7번째 새 로그 → 0통 · 상한 1줄
  new_root; mkitem T0001 a; commit; for i in A B C D E F; do logs add $i 2026-11-01T10:0$(( $(printf '%d' "'$i") - 65 )):00Z; run tick; done
  c6="$(sc $CFO)$(sc $PL)"; logs add G 2026-11-01T10:20:00Z; run tick
  chk '[ "$c6" = 66 ] && [ $RC = 0 ] && has "하루 상한 6 — T0001" && [ "$(sc $CFO)$(sc $PL)" = 66 ]' "R9 7번째 새 로그 → 0통 · «하루 상한 6» 1줄"
  fi
  if sel "R10"; then
  # R10 FT_TICK_TRIGGERS — ft-tick 단계: 켜면 DRY 1줄 · 0 이면 0
  mkdir -p "$T/t10"; printf '{"_master":"x"}\n' > "$T/t10/seats.json"; : > "$T/t10/mbox.sh"
  t10() { env FT_TICK_SEATS="$T/t10/seats.json" FT_TICK_MBOX="$T/t10/mbox.sh" FT_TICK_STATE_DIR="$T/t10/state" FT_TICK_STAMP_PREFIX="$T/t10/p-" FT_TICK_SEAT_STATUS="$T/t10/none" FT_ROOT="$T/t10" \
      FT_TICK_AUTONOMY=0 FT_TICK_LEAK_REAP=0 FT_TICK_HIL=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_IDLE_LONG=0 FT_MODEL_SWAP=0 FT_TICK_DRIFT=0 FT_TICK_ACCT=0 \
      FT_TICK_RAISED=0 FT_TICK_RENAMED=0 FT_TICK_QUEUE_FULL=0 FT_TICK_QUEUE=0 FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 FT_TICK_WT_SWEEP=0 \
      FT_TICK_UNPUSHED=0 FT_TICK_WATCH_SAMPLE=0 "$@" bash "${TICK_RUN:-$BIN/ft-tick.sh}" --dry-run 2>&1; }
  on="$(t10 FT_TICK_TRIGGERS=1 | grep -c 'DRY kind=trigger-watch')"; off="$(t10 FT_TICK_TRIGGERS=0 | grep -c 'DRY kind=trigger-watch')"
  [ "$on" = 1 ] && [ "$off" = 0 ] && ok "R10 FT_TICK_TRIGGERS=1 → 단계 1 · 0 → 단계 0" || bad "R10 on=$on off=$off"
  fi
  PH R1-R10
  if sel "R11"; then
  # R11 한 구간 서로 다른 로그 60건(두 쪽) → 60건 전부 seen · 발화 1통 묶음
  new_root; mkitem T0001 a; commit; logs addn 60 X 2026-11-01T10:00:00Z; run tick
  chk '[ $RC = 1 ] && [ "$(python3 -c "import json;print(len(json.load(open(\"$(sd)/T0001.seen\"))))")" = 60 ] && [ "$(sc $CFO)$(sc $PL)" = 11 ] && [ "$(python3 -c "import json;print(json.load(open(\"$(sd)/T0001.day\"))[\"count\"])")" = 60 ]' "R11 60건 두 쪽 → seen 60 · 묶음 1통 · 사건 셈 60"
  fi
  if sel "R11b"; then
  # R11b 같은 timestamp 60건 · 토큰 없이 둘째 쪽 = 첫 쪽 반복 → 토큰으로 60건 다 읽음
  new_root; mkitem T0001 a; commit; logs addn 60 Y 2026-11-01T10:00:00Z; EXTRA_ENV="STUB_ADV=1" run tick
  chk '[ "$(python3 -c "import json;print(len(json.load(open(\"$(sd)/T0001.seen\"))))")" = 60 ]' "R11b 같은 timestamp 60건 → 토큰으로 전부 seen"
  fi
  if sel "R11c"; then
  # R11c 60건 · 조회당 6초 · 예산 11초 → 첫 쪽 뒤 커서 저장 · 다음 바퀴 커서로 나머지 10건 · 같은 50건 재읽기 0
  new_root; mkitem T0001 a; commit; logs addn 60 Z 2026-11-01T10:00:00Z; BUDGET=14 EXTRA_ENV="STUB_ADV=6" run tick; cur1=0; [ -f "$(sd)/T0001.cursor" ] && cur1=1
  : > "$R/calls.log"; BUDGET=14 EXTRA_ENV="STUB_ADV=6" run tick
  chk '[ $cur1 = 1 ] && [ "$(python3 -c "import json;print(len(json.load(open(\"$(sd)/T0001.seen\"))))")" = 60 ] && [ "$(calls)" = 1 ] && grep -q "\"pageToken\": \"p1\"" "$R/calls.log" && [ ! -f "$(sd)/T0001.cursor" ]' "R11c 커서 저장 → 다음 바퀴 토큰으로 이어 읽음 · 재읽기 0"
  fi
  if sel "R12"; then
  # R12 겹침 — A(수집 10:00)로 since 가 올라간 뒤 수집 09:59(시계 차) 로그 B → 겹침 재조회로 1통
  new_root; mkitem T0001 a; commit; logs add A 2026-11-01T10:00:00Z; run tick; logs add B 2026-11-01T09:59:00Z; run tick
  chk '[ $RC = 1 ] && [ "$(sc $CFO)$(sc $PL)" = 22 ]' "R12 since 보다 1분 앞선 늦은 로그 → 겹침으로 1통"
  fi
  if sel "R12b"; then
  # R12b 수집 시각 기준 — 수집 진행 10:20 뒤 timestamp 09:59 로그가 수집 10:21 로 도착 → 발화 1통
  new_root; mkitem T0001 a; commit; logs add A 2026-11-01T10:20:00Z 2026-11-01T10:19:00Z; run tick; logs add B 2026-11-01T10:21:00Z 2026-11-01T09:59:00Z; run tick
  chk '[ $RC = 1 ] && [ "$(sc $CFO)$(sc $PL)" = 22 ]' "R12b 수집 시각 기준 → timestamp 오래된 늦은 로그도 1통"
  fi
  if sel "R13"; then
  # R13 같은 루트 감시기 두 개 — 잠금을 쥔 동안 건너뜀 · 놓은 뒤 1통씩
  new_root; mkitem T0001 a; commit; logs add A 2026-11-01T10:00:00Z; mkdir -p "$(sd)"; mkfifo "$R/fifo"
  python3 "$T/hold.py" "$(sd)/lock" "$R/held" < "$R/fifo" & HP=$!; exec 8> "$R/fifo"
  n=0; while [ ! -f "$R/held" ] && [ $n -lt 3000000 ]; do n=$((n+1)); done
  run tick; hold_out="$OUT"; hold_sent="$(sc $CFO)$(sc $PL)"; exec 8>&-; wait $HP; run tick
  case "$hold_out" in *"건너뜀"*) hs=1;; *) hs=0;; esac
  [ $hs = 1 ] && [ "$hold_sent" = 00 ] && [ "$(sc $CFO)$(sc $PL)" = 11 ] && ok "R13 잠금 중 건너뜀 · 놓은 뒤 수신자당 1통" || bad "R13 hs=$hs hold_sent=$hold_sent now=$(sc $CFO)$(sc $PL)"
  fi
  if sel "R14"; then
  # R14 담당 QUEUED 뒤 planner 발송 실패(rc137) → 다음 바퀴 planner 에만 1통 · 담당 0통
  new_root; mkitem T0001 a; commit; logs add A 2026-11-01T10:00:00Z; EXTRA_ENV="FAKE_FAIL_TO=$PL" run tick; a="$(sc $CFO)$(sc $PL)"; run tick
  chk '[ "$a" = 10 ] && [ "$(sc $CFO)$(sc $PL)" = 11 ]' "R14 planner 발송 실패 → 다음 바퀴 planner 에만 1통"
  fi
  if sel "R14b"; then
  # R14b 담당 QUEUED 직후 .sent 쓰기 전 종료 → 다음 바퀴 수신함 토큰 대조로 담당 재발송 0 · planner 1통
  new_root; mkitem T0001 a; commit; logs add A 2026-11-01T10:00:00Z; EXTRA_ENV="FAKE_KILL_AFTER_TO=$CFO" run tick; k=$RC; run tick
  chk '[ $k = 137 ] && [ "$(sc $CFO)$(sc $PL)" = 11 ]' "R14b .sent 전 종료 → 담당 재발송 0 · planner 1통"
  fi
  if sel "R15"; then
  # R15 머리 열림 + 닫힘 줄 → 조회 0 · 상태 어긋남 1줄
  new_root; mkitem T0001 a; printf -- '- 닫힘: 확인 완료 · 판정 3045\n' >> "$R/design/triggers/T0001-a.md"; commit; logs add A 2026-11-01T10:00:00Z; run tick
  chk '[ "$(calls)" = 0 ] && has "상태 어긋남 T0001" && [ "$(sc $CFO)$(sc $PL)" = 00 ]' "R15 닫힘 줄 있으면 조회 0 · 상태 어긋남 1줄"
  fi
  PH R11-R15
  if sel "R16"; then
  # R16 열린 항목 8 · 조회마다 6초 · 예산 30초 → 4개 처리 후 T0005 부터 · 다음 바퀴 T0005 부터
  new_root; for i in 1 2 3 4 5 6 7 8; do mkitem T000$i i$i; done; commit; BUDGET=33 EXTRA_ENV="STUB_ADV=6" run tick; a="$OUT"; c1="$(calls)"
  : > "$R/calls.log"; BUDGET=33 EXTRA_ENV="STUB_ADV=6" run tick; first="$(head -1 "$R/calls.log" | grep -o 'svc-T[0-9]*')"
  case "$a" in *"예산 소진 — 다음 바퀴 T0005 부터"*) m=1;; *) m=0;; esac
  [ $m = 1 ] && [ "$c1" = 4 ] && [ "$first" = svc-T0005 ] && ok "R16 4개 처리 · «다음 바퀴 T0005 부터» · 다음 바퀴 T0005 부터" || bad "R16 m=$m c1=$c1 first=$first"
  fi
  if sel "R17"; then
  # R17 조회 시간 초과 → rc3 · since·seen 그대로 · 뒤 정상 항목은 계속
  new_root; mkitem T0001 a; mkitem T0002 b; commit; run tick; s0="$(cat "$(sd)/T0001.since")"
  logs add B 2026-11-01T10:10:00Z 2026-11-01T10:10:00Z svc-T0001; logs add C 2026-11-01T10:11:00Z 2026-11-01T10:11:00Z svc-T0002
  EXTRA_ENV="STUB_SLOW_SVC=svc-T0001 FT_TRIGGER_CALL_SEC=0.3" run tick
  chk '[ $RC = 3 ] && has "판정 불가 — T0001 조회 시간 초과" && [ "$(cat "$(sd)/T0001.since")" = "$s0" ] && [ "$(cat "$(sd)/T0001.seen")" = "{}" ] && [ "$(sc $CFO)$(sc $PL)" = 11 ]' "R17 시간 초과 → 판정 불가 · rc3 · since·seen 그대로 · 뒤 항목 발화 계속"
  fi
  if sel "R18"; then
  new_root; mkitem T0001 a; commit; logs add A 2026-11-01T10:00:00Z; EXTRA_ENV="STUB_MODE=badjson" run tick; r18a=$RC; o18a="$OUT"
  EXTRA_ENV="STUB_MODE=notarray" run tick
  chk '[ $r18a = 3 ] && [ $RC = 3 ] && [ "$(sc $CFO)$(sc $PL)" = 00 ] && case "$o18a" in *"JSON 아님"*) true;; *) false;; esac' "R18 잘못된 JSON·배열 아님 → 판정 불가 rc3 · 쪽지 0"
  fi
  PH R16-R18
}

mutant() {  # <번호> <기대 FAIL 줄 머리> <치환 py 식...> — 사본 bin(트리거 파일만 복사 · 나머지는 심링크)에 치환 → green 칸이 FAIL 하는지
  local n="$1" want="$2" d="$T/mut$1"; shift 2; mkdir -p "$d"
  for f in "$BIN"/*.py; do case "$(basename "$f")" in ft_trigger_*) cp "$f" "$d/";; *) ln -sf "$f" "$d/$(basename "$f")";; esac; done
  python3 - "$d" "$@" <<'PY' || { bad "변이 $n — 치환 자리를 못 찾음"; return; }
import sys, os
d = sys.argv[1]
for spec in sys.argv[2:]:
    f, old, new = spec.split("\x1f")
    p = os.path.join(d, f); s = open(p, encoding="utf-8").read()
    if s.count(old) != 1: sys.exit(f"{f}: «{old[:40]}» {s.count(old)}곳")
    open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  local out; out="$( ( ONLY="$want"; TOOL_RUN="$d/ft_trigger_watch.py"; green ) 2>&1 | grep '^FAIL' | head -3 )"
  [ -n "$out" ] && ok "변이 $n → FAIL: ${out:0:90}" || bad "변이 $n → 그 칸이 안 무너짐"
}
S=$'\x1f'
WATCH=ft_trigger_watch.py; ITEMS=ft_trigger_items.py
mutants_a() {
  mutant 1 R3 "$WATCH${S}new = list({e[\"insertId\"]: e for e in got if e[\"insertId\"] not in seen}.values())${S}new = list({e[\"insertId\"]: e for e in got}.values())" "$WATCH${S}            if sent.exists():${S}            if False:" "$WATCH${S}            if intent.exists() and self.in_maillog(to, token):  # 앞 바퀴가 보내다 끊김 — 이미 쪽지가 갔으면 재발송 0${S}            if False:"
  mutant 2 R5 "$WATCH${S}                    run.undecided += 1${S}                    run.undecided += 1; T.wjson(run.sd / f\"{it['num']}.since\", T.fmt_ts(T.now()))"
  mutant 3 R6 "$ITEMS${S}closed=head[\"상태\"] == \"닫힘\" or line${S}closed=line"
  mutant 4 R7 "$ITEMS${S}            notes.append(why)
            continue${S}            raise Undecided(why)"
  mutant 5 R5 "$WATCH${S}                raise T.Undecided(f\"조회 rc={p.returncode} {p.stderr.strip()[:80]}\")${S}                return {\"entries\": []}"
  mutant 6 R17 "$WATCH${S}        raise T.Undecided(\"조회 시간 초과\")${S}        return {\"entries\": []}"
  mutant 7 R18 "$WATCH${S}                raise T.Undecided(\"조회 결과 JSON 아님\")${S}                return {\"entries\": []}"
  mutant 8 R11 "$WATCH${S}            tok = d.get(\"nextPageToken\")${S}            tok = None"
  mutant 9 R12 "$WATCH${S}MIN_LEFT, CAP, OVERLAP, SEEN_S, PAGE = 8, 6, 120, 86400, 50${S}MIN_LEFT, CAP, OVERLAP, SEEN_S, PAGE = 8, 6, 0, 86400, 50"
  PH mutants-1-9
}
mutants_b() {
  mutant 10 R13 "$WATCH${S}            if not got:${S}            if False:"
  mutant 11 R14 "$WATCH${S}            key = re.sub(r\"[^\\w.#-]\", \"_\", to)${S}            key = \"all\""
  mutant 12 R15 "$ITEMS${S}            line = True${S}            line = False"
  mutant 13 R16 "$WATCH${S}nextf.write_text(it[\"num\"] + \"\\n\", encoding=\"utf-8\")${S}pass"
  mutant 14 R11b "$WATCH${S}**({\"pageToken\": tok} if tok else {})${S}**{}"
  mutant 15 R11c "$WATCH${S}            T.wjson(curf, {\"filter\": flt, \"token\": tok, \"maxrecv\": mx})${S}            pass"
  mutant 16 R12b "$WATCH${S}receiveTimestamp>=${S}timestamp>=" "$WATCH${S}T.parse_ts(e[\"receiveTimestamp\"]) for e in d[\"entries\"]${S}T.parse_ts(e[\"timestamp\"]) for e in d[\"entries\"]"
  mutant 17 R14b "$WATCH${S}            if intent.exists() and self.in_maillog(to, token):  # 앞 바퀴가 보내다 끊김 — 이미 쪽지가 갔으면 재발송 0${S}            if False:"
  PH mutants-10-17
}
mutants() { mutants_a; mutants_b; }

case "$MODE" in
  green) green;;
  mut) mutants;;
  mut-a) mutants_a;;
  mut-b) mutants_b;;
  only:*) ONLY="${MODE#only:}"; green;;
  *) green; mutants
     for f in ft_trigger_watch.py ft_trigger_items.py ft_trigger_fetch.py ft-tick.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "bin·kit 같은 판 $f" || bad "bin·kit 다름 $f"; done
     bash -n "$BIN/ft-tick.sh" && ok "bash -n ft-tick.sh" || bad "bash -n ft-tick.sh";;
esac
echo "TOTAL fail=$fail $(( $(date +%s) - T0 ))s"
[ "$fail" = 0 ]
