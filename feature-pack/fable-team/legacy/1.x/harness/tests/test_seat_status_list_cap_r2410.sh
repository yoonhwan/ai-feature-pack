#!/bin/bash
# r2410 ①~⑧ + 변이 M1~M5 — ft-seat-status list 좌석당 상한(K1 · 7초) + 전체 예산(K2 · env 준 호출만).
#   기대: 끊긴 좌석·읽지 않은 좌석도 행 1개(UNKNOWN · - · stderr 에 이름) · 행 수 = 좌석 수 · rc 0 · 느린 좌석 0 이면 바이트 그대로.
# 입력은 전부 가짜다: 가짜 tmux(list-sessions = 좌석 목록) · 가짜 ft_seat_pi.py(느린 좌석 = 표식 프로세스 r2410-stall) · 임시 명부 · 사본 bin.
# 기준판(② Red) = 고정 sha 42f98b9936 에서 꺼낸 ft-seat-status.sh · 변이 = 사본에서만 · 원본 대조 = 같은 입력의 ①(·④·⑦) 판.
# 실 tmux·실 좌석·네트워크·origin/main 읽기 0 · sleep 은 가짜 멈춤 안에서만(사설 대기 0.1~0.2초 폴링).
# usage: bash test_seat_status_list_cap_r2410.sh   (rc 0 = 전건 통과 · 사례별 초를 찍는다)
set -u
T0=$SECONDS
HERE="$(cd "$(dirname "$0")" && pwd)"
H="$(dirname "$HERE")"
BIN="$H/bin"; KIT="$H/kit/fable-team/bin"; SH="ft-seat-status.sh"
BASE_SHA=42f98b9936
BASE_PATH=feature-pack/fable-team/legacy/1.x/harness/bin/ft-seat-status.sh
W="$(mktemp -d "${TMPDIR:-/tmp}/r2410-seat-cap.XXXXXX")"
LOGS="$W/logs"; mkdir -p "$LOGS"
trap 'rm -rf "$W"' EXIT
ok=0; bad=0
check() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "OK   $1 ($2)"; else bad=$((bad+1)); echo "FAIL $1 (기대 $3 · 실제 $2)"; fi; }
lines() { wc -l < "$1" | tr -d ' '; }
RC=0

# ─ 월드: 사본 bin(+대역 ft_seat_pi.py) · 가짜 tmux · 임시 명부 · 표식 멈춤 프로세스 ─
world() {  # $1=폴더 · $2=1 이면 자리에 기준판
  local w="$1"
  mkdir -p "$w/bin" "$w/home" "$w/fakebin" "$w/repo/.fable-team"
  cp "$BIN"/ft_seat_*.py "$w/bin/" || return 1
  if [ "${2:-0}" = 1 ]; then cp "$W/base/$SH" "$w/bin/$SH"; else cp "$BIN/$SH" "$w/bin/$SH"; fi
  cat > "$w/bin/ft_seat_pi.py" <<'PY'
import os, subprocess, sys
mode, seat = sys.argv[1], sys.argv[3]
if seat in os.environ.get("R2410_SLOW", "").split(","):
    subprocess.call([os.environ["R2410_STALL"], os.environ.get("R2410_DELAY", "30")])
print("IDLE\t42" if mode == "--row" else "IDLE")
PY
  cat > "$w/fakebin/tmux" <<'SH'
#!/bin/bash
[ "$1" = list-sessions ] && printf '%s\n' $R2410_SEATS && exit 0
exit 1
SH
  printf '#!/bin/bash\nsleep "$1"\n' > "$w/fakebin/r2410-stall"
  chmod +x "$w/fakebin/tmux" "$w/fakebin/r2410-stall"
  printf '{"ft-a":{"agent":"pi"},"ft-b":{"agent":"pi"},"ft-c":{"agent":"pi"},"ft-d":{"agent":"pi"},"ft-e":{"agent":"pi"}}' \
    > "$w/repo/.fable-team/seats.json"
}

run1() {  # $1=스크립트 $2=월드 $3=바깥 timeout(초) $4=stdout $5=stderr · 나머지 = env 대입(NAME=VAL) → RC (124 = 바깥에서 끊김)
  local sc="$1" w="$2" tout="$3" o="$4" e="$5"; shift 5
  RC=$(python3 - "$tout" "$sc" "$o" "$e" "$w" "$@" <<'PY'
import os, signal, subprocess, sys
tout, sc, o, e, w = float(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
env = {k: v for k, v in os.environ.items()
       if k not in ("FT_SEAT_ROW_CAP", "FT_SEAT_LIST_BUDGET", "FT_SEAT_STATUS_TRACE")}
env.update({"HOME": w + "/home", "PATH": w + "/fakebin:" + os.environ.get("PATH", ""),
            "FT_ROOTS_TSV": w + "/none.tsv", "FT_SEATS_JSON": w + "/repo/.fable-team/seats.json",
            "R2410_STALL": w + "/fakebin/r2410-stall"})
for kv in sys.argv[6:]:
    k, _, v = kv.partition("=")
    env[k] = v
args = env.pop("R2410_ARGS", "list").split()
with open(o, "w") as fo, open(e, "w") as fe:
    p = subprocess.Popen(["bash", sc] + args, env=env, cwd=w, text=True,
                         stdin=subprocess.DEVNULL, stdout=fo, stderr=fe, start_new_session=True)
    try:
        print(p.wait(timeout=tout))          # scan.sh 의 timeout 끊김 흉내 = 프로세스 묶음째
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGTERM)
        try:
            p.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL); p.wait()
        print(124)
PY
)
}

swap() {  # $1=파일 $2=옛 글자 $3=새 글자 (정확히 1곳 · 아니면 rc 1)
  python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(p, encoding="utf-8").read()
if t.count(old) != 1:
    sys.exit("swap: %d 곳" % t.count(old))
open(p, "w", encoding="utf-8").write(t.replace(old, new))
PY
}

# ─ 사례 ─
c1() {   # ① ③ ⑧
  local w="$W/c1" s3="ft-a ft-b ft-c" t sec
  world "$w" || exit 9
  run1 "$w/bin/$SH" "$w" 12 "$w/out" "$w/err" R2410_SEATS="$s3" "R2410_SLOW="
  cp "$w/out" "$w/plain"
  t=$SECONDS
  run1 "$w/bin/$SH" "$w" 12 "$w/out" "$w/err" R2410_SEATS="$s3" R2410_SLOW=ft-b R2410_DELAY=30 \
    FT_SEAT_ROW_CAP=2 FT_SEAT_STATUS_TRACE="$w/trace.tsv"
  sec=$((SECONDS - t))
  check "① rc" "$RC" 0
  check "① 행 수 = 좌석 수" "$(lines "$w/out")" 3
  check "① 둘째 행 = UNKNOWN -" "$(awk '$1=="ft-b"{print $2" "$3}' "$w/out")" "UNKNOWN -"
  check "① stderr CAP-SEAT 1줄" "$(cat "$w/err")" "CAP-SEAT ft-b s=2 agent=pi"
  check "① 전체 10초 안" "$([ "$sec" -le 10 ] && echo yes || echo no)" yes
  check "① 첫째 행 = 느린 좌석 없는 판" "$(sed -n 1p "$w/out")" "$(sed -n 1p "$w/plain")"
  check "① 셋째 행 = 느린 좌석 없는 판" "$(sed -n 3p "$w/out")" "$(sed -n 3p "$w/plain")"
  check "⑧ START·END 6줄" "$(lines "$w/trace.tsv")" 6
  check "⑧ 둘째 좌석 END 초 ≥ 2" "$(awk -F'\t' '$2=="END"&&$3=="ft-b"&&$4+0>=2{print "ok"; exit}' "$w/trace.tsv")" ok
  sleep 0.4
  check "③ 남은 표식 프로세스 0" "$(ps -axo command= | grep -F "$w/fakebin/r2410-stall" | grep -vc grep)" 0
}

c2() {   # ② 기준판 Red
  local w="$W/c2"
  world "$w" 1 || exit 9
  run1 "$w/bin/$SH" "$w" 8 "$w/out" "$w/err" R2410_SEATS="ft-a ft-b ft-c" R2410_SLOW=ft-b \
    R2410_DELAY=30 FT_SEAT_ROW_CAP=2
  check "② 기준판 바깥 timeout rc" "$RC" 124
  check "② 기준판 stdout 0줄" "$(lines "$w/out")" 0
}

c3b() {  # ③ TERM 을 무시하는 자식 — 상한 컷은 KILL 까지 가야 남는 프로세스 0
  local w="$W/c3b"
  world "$w" || exit 9
  printf '#!/bin/bash\ntrap "" TERM\nsleep "$1"\n' > "$w/fakebin/r2410-stall"   # 자식이 TERM 을 무시(상속)
  run1 "$w/bin/$SH" "$w" 12 "$w/out" "$w/err" R2410_SEATS="ft-a ft-b ft-c" R2410_SLOW=ft-b \
    R2410_DELAY=30 FT_SEAT_ROW_CAP=2
  check "③b 끊긴 행 = UNKNOWN -" "$(awk '$1=="ft-b"{print $2" "$3}' "$w/out")" "UNKNOWN -"
  sleep 0.5
  check "③b TERM 무시 자식 잔여 0" "$(ps -axo command= | grep -F "$w/fakebin/r2410-stall" | grep -vc grep)" 0
}

cH2() {  # 공용 경로 사고 — mktemp 실패 시 ROW_DIR = TMPDIR · 거기에 rm -rf 를 부르면 안 된다
  local w="$W/cH2" toks
  world "$w" || exit 9
  printf '#!/bin/bash\nexit 1\n' > "$w/fakebin/mktemp"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$R2410_RMLOG"\nexit 0\n' > "$w/fakebin/rm"
  chmod +x "$w/fakebin/mktemp" "$w/fakebin/rm"
  run1 "$w/bin/$SH" "$w" 12 "$w/out" "$w/err" R2410_SEATS="ft-a ft-b ft-c" "R2410_RMLOG=$w/rm.log"
  check "H2 rc" "$RC" 0
  check "H2 행 수(대지 퇴화 판에서도)" "$(lines "$w/out")" 3
  check "H2 rm 기록 있음(대지 경로를 실제로 지나갔나)" "$([ -s "$w/rm.log" ] && echo yes || echo no)" yes
  toks=$(awk '{for (i = 2; i <= NF; i++) if ($i !~ /ft-seat-row/) print $i}' "$w/rm.log" | wc -l | tr -d ' ')
  check "H2 공용 경로(폴더 이해) rm 인자 0" "$toks" 0
}

c4a() {  # ④ 첫 구 — 예산 5 · 좌석 5 · 좌석마다 2초 (부하에 민감하니 혼자 돈다)
  local w="$W/c4a" t sec
  world "$w" || exit 9
  t=$SECONDS
  run1 "$w/bin/$SH" "$w" 15 "$w/out" "$w/err" R2410_SEATS="ft-a ft-b ft-c ft-d ft-e" \
    R2410_SLOW="ft-a,ft-b,ft-c,ft-d,ft-e" R2410_DELAY=2 FT_SEAT_LIST_BUDGET=5 FT_SEAT_ROW_CAP=7
  sec=$((SECONDS - t))
  check "④ rc" "$RC" 0
  check "④ 행 수" "$(lines "$w/out")" 5
  check "④ 첫째 정상" "$(awk '$1=="ft-a"{print $2" "$3}' "$w/out")" "IDLE 42"
  check "④ 둘째 정상" "$(awk '$1=="ft-b"{print $2" "$3}' "$w/out")" "IDLE 42"
  check "④ 셋째 CAP-SEAT s=1" "$(grep -c '^CAP-SEAT ft-c s=1 agent=pi$' "$w/err")" 1
  check "④ 예산 컷 1줄" "$(grep -c '^BUDGET-CUT 남은 2 첫 ft-d$' "$w/err")" 1
  check "④ UNKNOWN 행 3" "$(awk '$2=="UNKNOWN"' "$w/out" | wc -l | tr -d ' ')" 3
  check "④ 전체 9초 안" "$([ "$sec" -le 9 ] && echo yes || echo no)" yes
}

c4b() {  # ④ 둘째 구 — 같은 입력 · 예산 env 없음
  local w="$W/c4b"
  world "$w" || exit 9
  run1 "$w/bin/$SH" "$w" 15 "$w/out" "$w/err" R2410_SEATS="ft-a ft-b ft-c ft-d ft-e" \
    R2410_SLOW="ft-a,ft-b,ft-c,ft-d,ft-e" R2410_DELAY=2
  check "④b 행 수" "$(lines "$w/out")" 5
  check "④b 정상 행 5" "$(grep -c 'IDLE' "$w/out")" 5
  check "④b stderr 0줄" "$(lines "$w/err")" 0
}

c5a() { run5 "$W/c5a" FT_SEAT_ROW_CAP=0 "상한 0"; }      # ⑤ 상한 0 → 7초
c5b() { run5 "$W/c5b" FT_SEAT_ROW_CAP=abc "상한 abc"; }   # ⑤ 상한 abc → 7초
run5() {  # $1=폴더 $2=상한 env $3=이름 · 멈춤 9초 → 7초 상한에서 끊긴다
  local w="$1" name="$3"
  world "$w" || exit 9
  run1 "$w/bin/$SH" "$w" 15 "$w/out" "$w/err" R2410_SEATS="ft-a ft-b ft-c" R2410_SLOW=ft-b \
    R2410_DELAY=9 "$2"
  check "⑤ $name → CAP-SEAT s=7" "$(grep -c '^CAP-SEAT ft-b s=7 agent=pi$' "$w/err")" 1
  check "⑤ $name UNKNOWN 1행" "$(awk '$2=="UNKNOWN"' "$w/out" | wc -l | tr -d ' ')" 1
}

c5c() {  # ⑤ 예산 abc → WARN 1줄 · 행은 예산 없는 판과 같음
  local w="$W/c5c"
  world "$w" || exit 9
  run1 "$w/bin/$SH" "$w" 12 "$w/warn.out" "$w/err" R2410_SEATS="ft-a ft-b ft-c" R2410_SLOW=ft-b \
    R2410_DELAY=3 FT_SEAT_LIST_BUDGET=abc
  run1 "$w/bin/$SH" "$w" 12 "$w/out2" "$w/err2" R2410_SEATS="ft-a ft-b ft-c" R2410_SLOW=ft-b R2410_DELAY=3
  check "⑤ 예산 abc WARN 1줄" "$(cat "$w/err")" "WARN FT_SEAT_LIST_BUDGET 값 무시"
  check "⑤ 예산 abc 행 = 예산 없는 판" "$(cmp -s "$w/warn.out" "$w/out2" && echo same)" same
}

c6() {   # ⑥ 느린 좌석 0 · env 0 → 바이트 = 기준판 · stderr 0줄
  local w="$W/c6" b="$W/c6b"
  world "$w" || exit 9
  world "$b" 1 || exit 9
  run1 "$w/bin/$SH" "$w" 12 "$w/out" "$w/err" R2410_SEATS="ft-a ft-b ft-c"
  run1 "$b/bin/$SH" "$b" 12 "$b/out" "$b/err" R2410_SEATS="ft-a ft-b ft-c"
  check "⑥ stdout = 기준판 바이트" "$(cmp -s "$w/out" "$b/out" && echo same)" same
  check "⑥ stderr 0줄" "$(lines "$w/err")" 0
  run1 "$w/bin/$SH" "$w" 12 "$w/j.out" "$w/j.err" R2410_SEATS="ft-a ft-b ft-c" R2410_ARGS="list --json"
  run1 "$b/bin/$SH" "$b" 12 "$b/j.out" "$b/j.err" R2410_SEATS="ft-a ft-b ft-c" R2410_ARGS="list --json"
  check "⑥ --json = 기준판 바이트" "$(cmp -s "$w/j.out" "$b/j.out" && echo same)" same
}

c7() {   # ⑦ ① 입력 + --json
  local w="$W/c7"
  world "$w" || exit 9
  run1 "$w/bin/$SH" "$w" 12 "$w/out" "$w/err" R2410_SEATS="ft-a ft-b ft-c" R2410_SLOW=ft-b \
    R2410_DELAY=30 FT_SEAT_ROW_CAP=2 R2410_ARGS="list --json"
  check "⑦ rc" "$RC" 0
  check "⑦ 배열 3 · 둘째 UNKNOWN · age null" \
    "$(python3 -c 'import json,sys;r=json.load(open(sys.argv[1]));print(len(r), r[1]["pane"], r[1]["jsonl_age"], r[1]["agent"], r[1]["replaced"])' "$w/out" 2>&1)" \
    "3 UNKNOWN None pi False"
}

# ─ 변이 (사본에서만 · 대조 = 같은 입력의 ① ④a ⑦ 원본 판이 통과한 것) ─
MW=""
m_run() {  # $1=이름 $2=옛 글자 $3=새 글자 · 나머지 = env 대입
  local name="$1" old="$2" new="$3"
  MW="$W/$name"
  world "$MW" || exit 9
  swap "$MW/bin/$SH" "$old" "$new" || { echo "FAIL $name swap (정확히 1곳 아님)"; return 0; }
  shift 3
  run1 "$MW/bin/$SH" "$MW" 6 "$MW/out" "$MW/err" R2410_SEATS="ft-a ft-b ft-c" R2410_SLOW=ft-b R2410_DELAY=30 "$@"
}
m1() {  # K1 상한 감싸기 뺌 → ① FAIL(전체 초)
  m_run m1 '  [ "$cap" -ge 1 ] && { row_of_capped "$1" "$cap"; return 0; }' '' FT_SEAT_ROW_CAP=2
  check "M1 ① 상한 없이 6초에 끊김" "$RC" 124
}
m2() {  # K1 끊긴 좌석 행을 IDLE 로 → ① FAIL(둘째 행)
  m_run m2 '    unknown_row "$s"
  fi' '    printf "%s\tIDLE\t-\t%s\t0\n" "$s" "${agent:--}"
  fi' FT_SEAT_ROW_CAP=2
  check "M2 ① 둘째 행 = IDLE" "$(awk '$1=="ft-b"{print $2}' "$MW/out")" "IDLE"
}
m3() {  # K1 CAP-SEAT 줄 뺌 → ① FAIL(stderr 구)
  m_run m3 "    printf 'CAP-SEAT %s s=%s agent=%s\\n' \"\$s\" \"\$cap\" \"\${agent:--}\" >&2
" '' FT_SEAT_ROW_CAP=2
  check "M3 ① stderr CAP-SEAT 0줄" "$(grep -c '^CAP-SEAT' "$MW/err")" 0
}
m4() {  # K2 예산 검사 뺌 → ④ FAIL(3석 2초 · 예산 3 = 원본이면 셋째가 BUDGET-CUT)
  m_run m4 '      if [ "$el" -ge $(( budget * 100 )) ]; then' '      if false; then' \
    R2410_SEATS="ft-a ft-b ft-c" R2410_SLOW="ft-a,ft-b,ft-c" R2410_DELAY=2 FT_SEAT_LIST_BUDGET=3
  check "M4 ④ 예산 컷 0줄" "$(grep -c '^BUDGET-CUT' "$MW/err")" 0
}
m5() {  # K3 끊긴 좌석 행 생략 → ⑦ FAIL(배열 길이)
  local w="$W/m5"
  world "$w" || exit 9
  swap "$w/bin/$SH" '    printf '"'"'CAP-SEAT %s s=%s agent=%s\n'"'"' "$s" "$cap" "${agent:--}" >&2
    unknown_row "$s"' '    printf '"'"'CAP-SEAT %s s=%s agent=%s\n'"'"' "$s" "$cap" "${agent:--}" >&2' || return 0
  run1 "$w/bin/$SH" "$w" 12 "$w/out" "$w/err" R2410_SEATS="ft-a ft-b ft-c" R2410_SLOW=ft-b \
    R2410_DELAY=30 FT_SEAT_ROW_CAP=2 R2410_ARGS="list --json"
  check "M5 ⑦ 배열 길이" "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$w/out" 2>&1)" 2
}

# ─ 실행: 사례마다 서브셸 · 겹침 4개까지 · 사례별 초를 찍는다 ─
wave() {  # $@=사례 이름들
  local n t=$SECONDS
  for n in "$@"; do ( "$n" ) > "$LOGS/$n.log" 2>&1 & done
  wait
  for n in "$@"; do
    cat "$LOGS/$n.log"
    ok=$((ok + $(grep -c '^OK' "$LOGS/$n.log")))
    bad=$((bad + $(grep -c '^FAIL' "$LOGS/$n.log")))
    [ -s "$LOGS/$n.log" ] || { bad=$((bad+1)); echo "FAIL $n (출력 0 · 비정상 종료)"; }
  done
  echo "-- [$*] $((SECONDS - t))초"
}

# 기준판 확보(고정 sha · origin/main 읽기 0)
mkdir -p "$W/base"
if ! git -C "$H" show "$BASE_SHA:$BASE_PATH" > "$W/base/$SH" 2>"$W/base.err"; then
  echo "FAIL 기준판 꺼내기 sha=$BASE_SHA"; cat "$W/base.err"; exit 1
fi
check "bin = kit 바이트 같음" "$(cmp -s "$BIN/$SH" "$KIT/$SH" && echo same)" same

wave c1 c2 c6 c7
wave c4a
wave c3b c4b c5a c5b
wave c5c cH2 m2 m3
wave m1 m4 m5

echo "== 통과 $ok · 실패 $bad · 전체 $((SECONDS - T0))초"
[ "$bad" -eq 0 ] || exit 1
exit 0
