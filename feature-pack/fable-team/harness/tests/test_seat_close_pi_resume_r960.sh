#!/usr/bin/env bash
# test_seat_close_pi_resume_r960.sh — r960 ⓒⓓⓕ: pi 좌석(agent=pi)은 재개 기록을 pi 세션 파일에서 만들고, 없으면 «산출 커밋 보존» 사유로 살아 있어도 닫는다.
# 임시 git 리포 + 가짜 tmux(PATH 앞) + 가짜 HOME(~/.pi/agent/sessions) + 실제 ft-seat-retire/close 만 쓴다 — 실제 리포·명부·tmux·pi 세션은 건드리지 않는다.
# 축 ⓒ agent=pi · 살아 있는 좌석 · pane cwd 의 pi 세션 파일 1개 → RETIRED 경로 RESUME ok(engine=pi · jsonl=세션 파일) · CLOSED-ROLE rc 0 · 명부 닫힘
#    ⓒ2 세션 파일이 좌석 프로세스 시작 «전» → 그 파일은 이 좌석 것이 아니다(NORECORD)
#    ⓓ agent=pi 세션 파일 0 → NORECORD «pi 세션 없음 — 산출 커밋 보존» 인데도 닫기 진행(rc 0) · claude 좌석 같은 상황은 HELD rc 3(동작 불변)
#    ⓥ r4 DA 반례: agent=claude · 세션 없음 · 재개 기록 경로에 «pi 세션 없음» 글자 → HELD rc 3 · kill 0 · role 불변(판정은 출력 글자가 아니라 명부 agent 칸)
#    ⓦ r4: 명부에 agent 칸 없음 → pi 수용 0 = HELD rc 3 · kill 0(조용한 수용 0)
#    ⓕ 변이: pi 갈래 끔 → ⓒ FAIL · 수용 조건을 출력 글자로 되돌림 → ⓥ FAIL · ⓖ 키트 짝 cmp0 · bash -n · 줄 수 상한 · 600/300·외부 호출 0
#    ⓡ r2 HOLD1: pi 세션 파일 0 → 수용한 NORECORD 원문 줄(`NORECORD <좌석> <사유>`)이 출력된다(변이 «수용 뒤 출력 생략» → FAIL)
#    ⓢ r2 HOLD2: 머리 줄 `session` + 뒤 줄 `model_change.modelId` → 재개 기록 ok · model = 마지막 model_change(변이 «첫 줄만» → FAIL)
#    ⓦr5-1 두 명부 불일치 = 판정 아님(REJECT rc 1 · 명부 쓰기 0 · kill 0 · 반대로 두어도 같음) · ⓦr5-2 --seats 는 확정이 이김(FT_SEATS_JSON·루트 안 본다) · ⓦr5-3 자식(ft-seat-retire)에 확정 경로를 항상 넘긴다 · ⓦr5-4 재개 기록 경로를 입구에서 1번만(lineage_ok 과 자식이 같은 값) · ⓦr5-5 회귀 꼴(pi=NORECORD 줄 1 · claude=HELD rc 3 · kill 0)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
J() { jq -r "$2" "$1"; }

echo "== ⓖ 키트 짝 cmp0 · bash -n · 줄 수 상한"
for f in ft-seat-retire.sh ft-seat-close.sh ft_roster_lib.py; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "cmp $f (bin == kit)" || bad "cmp $f 다름"
  case "$f" in *.sh) bash -n "$KIT/$f" && ok "bash -n $f" || bad "bash -n $f";; esac
done
chk "ft-seat-retire.sh ≤ 200줄" "$([ "$(wc -l < "$BIN/ft-seat-retire.sh")" -le 200 ] && echo yes || echo no)" yes
chk "ft-seat-close.sh ≤ 120줄" "$([ "$(wc -l < "$BIN/ft-seat-close.sh")" -le 120 ] && echo yes || echo no)" yes

mkdir -p "$T/bin" "$T/home"
cp "$BIN/ft-seat-close.sh" "$BIN/ft-seat-retire.sh" "$BIN/ft_seat_bind.py" "$BIN/ft_roster_lib.py" "$BIN/ft-harness-root.sh" "$T/bin/"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cat > "$T/bin/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  has-session) [ "${FAKE_SESSION:-1}" = 1 ];;                                  # 살아 있는 좌석인가
  display) printf '%s %s\n' "${FAKE_PANE_PID:-1}" "${FAKE_PANE_CWD:-/tmp}" ;;  # ft_roster_lib.pi_seat_resume 의 결속 조회
  show-options) exit 0;;                                                       # @zc_v65_active 없음
  list-sessions) printf '%s\n' ${FAKE_SESSIONS:-} ;;                            # ⓦr5-4 lineage_ok 의 같은 계보 더 큰 번호 생존
  set-option|kill-session) exit 0;;
  display-message) echo caller#0;;
esac
EOF
chmod +x "$T/bin/"*
REPO="$T/repo"; mkdir -p "$REPO/.fable-team"
git -C "$REPO" init -q -b main
export TMUX_LOG="$T/tmux.log" FT_ROOT="$T/root" ZC_RESUME_DIR="$T/resume" FT_PI_SESSIONS="$T/home/.pi/agent/sessions"
mkdir -p "$FT_ROOT" "$ZC_RESUME_DIR" "$FT_PI_SESSIONS/enc"
export HOME="$T/home"
SESS="$FT_PI_SESSIONS/enc/2026-10-26T10-00-00-000Z_aaaa.jsonl"
PDIR="$T/worktree"; mkdir -p "$PDIR"
NOW="$(date -u +%Y-%m-%dT%H:%M:%S)"
pifile() {  # pifile <시각 문자열> [cwd] — pi 세션 파일 1개(첫 줄 type=session) · 나머지 줄은 안 읽힌다
  printf '{"type":"session","version":3,"id":"aaaa-1111","timestamp":"%s","cwd":"%s"}\n{"type":"session_info","name":"pi#0"}\n' "${1:-$NOW}" "${2:-$PDIR}" > "$SESS"; }
seats_pi() { printf '{"_master":"M#1","M#1":{"role":"master","tick":"t"},"%s":{"role":"nano","agent":"%s","model":"m","tick":null,"index":"x.md"}}\n' "${1:-pi#0}" "${2:-pi}" > "$REPO/.fable-team/seats.json"; }
run() { ( cd "$REPO" && env PATH="$T/bin:$PATH" TMUX_LOG="$TMUX_LOG" FT_ROOT="$FT_ROOT" ZC_RESUME_DIR="$ZC_RESUME_DIR" FT_PI_SESSIONS="$FT_PI_SESSIONS" HOME="$HOME" FT_SEAT_RETIRE_BIN="${RT_BIN:-$T/bin/ft-seat-retire.sh}" \
  FAKE_SESSION="${FAKE_SESSION:-1}" FAKE_PANE_PID="$$" FAKE_PANE_CWD="${FAKE_PANE_CWD:-$PDIR}" ZC_RESUME_DIR="${RDIR:-$ZC_RESUME_DIR}" FT_SEATS_JSON="${SEATS_ENV:-}" "$@" 2>&1 ); }
close() { run bash "$T/bin/${CLOSE_BIN:-ft-seat-close.sh}" "$@"; }
retire_rec() { run bash "$T/bin/${RETIRE_BIN:-ft-seat-retire.sh}" "$1" --record-only --verdict 2400 --seats "$REPO/.fable-team/seats.json"; }

echo "== ⓒ pi 좌석 · 살아 있음 · pane cwd 의 pi 세션 파일 1개 → RESUME ok + 닫힘 rc 0"
seats_pi pi#0 pi; pifile "$NOW"; : > "$TMUX_LOG"
out="$(retire_rec 'pi#0')"; rc=$?
chk "ⓒretire rc 0 · RESUME ok" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1-2)" "0 RESUME ok"
chk "ⓒ기록 engine=pi · jsonl=세션 파일" "$(J "$ZC_RESUME_DIR/pi#0.json" '[.engine,.jsonl]|join(" ")')" "pi $SESS"
chk "ⓒ기록 cwd= pane cwd · uuid" "$(J "$ZC_RESUME_DIR/pi#0.json" '[.cwd,.uuid]|join(" ")')" "$PDIR aaaa-1111"
out="$(close 'pi#0' --reason "r960 pi 닫기 시험" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓒclose rc 0 · CLOSED-ROLE record 경로" "$rc $(printf '%s' "$out" | grep -o "record=[^ ]*")" "0 record=$ZC_RESUME_DIR/pi#0.json"
chk "ⓒ명부 닫힘(stop-ready · _closed.verdict)" "$(J "$REPO/.fable-team/seats.json" '.["pi#0"]|[.role,._closed.verdict]|join(",")')" "stop-ready,2400"

echo "== ⓒ2 세션 파일이 좌석 프로세스 시작 «전» → 이 좌석 세션 아님(NORECORD)"
seats_pi pi#2 pi; pifile "2020-01-01T00:00:00"
out="$(retire_rec 'pi#2')"; rc=$?
chk "ⓒ2 rc 0 · NORECORD" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1)" "0 NORECORD"
has "$out" "pi 세션 없음 — 산출 커밋 보존" "  └ 사유에 «pi 세션 없음 — 산출 커밋 보존»"
chk "ⓒ2 기록 파일 0" "$([ -f "$ZC_RESUME_DIR/pi#2.json" ] && echo yes || echo no)" no

echo "== ⓓ agent=pi · 세션 파일 0 → NORECORD 인데도 닫기 진행 / claude 는 HELD rc 3(불변)"
seats_pi pi#3 pi; rm -f "$SESS"; : > "$TMUX_LOG"
out="$(close 'pi#3' --reason "r960 pi 세션 없음" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓓpi rc 0 · CLOSED-ROLE record=NORECORD" "$rc $(printf '%s' "$out" | grep -o 'record=[^ ]*')" "0 record=NORECORD"
chk "ⓓpi 명부 닫힘" "$(J "$REPO/.fable-team/seats.json" '.["pi#3"].role')" stop-ready
seats_pi cl#4 claude; : > "$TMUX_LOG"
out="$(close 'cl#4' --reason "r960 claude 세션 없음" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓓclaude rc 3 · HELD(동작 불변)" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1)" "3 HELD"
chk "ⓓclaude 명부 안 닫힘 · kill 0" "$(J "$REPO/.fable-team/seats.json" '.["cl#4"].role') $(grep -c '^kill-session' "$TMUX_LOG" || true)" "nano 0"

echo "== ⓕ 변이 — pi 갈래를 끄면 ⓒ 가 무너지는가 · claude NORECORD 수용으로 넓히면 ⓓ 의 claude 칸이 무너지는가"
mutate() {  # mutate <원본> <사본> <표지> <바꿀 글> [sub] — 표지 줄을 바꾸거나(sub 없이) 표지 글자만 바꾼 사본
  python3 - "$1" "$2" "$3" "$4" "${5:-line}" <<'PY'
import sys
src, dst, mark, repl, mode = sys.argv[1:6]
txt = open(src, encoding="utf-8").read()
out, hit = [], 0
if mode == "sub":
    hit = txt.count(mark); txt = txt.replace(mark, repl)
else:
    for ln in txt.splitlines():
        if mark in ln: out.append(repl); hit += 1
        else: out.append(ln)
    txt = "\n".join(out) + "\n"
open(dst, "w", encoding="utf-8").write(txt)
print(hit)
PY
}
n="$(mutate "$T/bin/ft-seat-retire.sh" "$T/bin/ft-seat-retire.mut.sh" "# r960-mut:pi" "    pass")"
chk "변이 표지 r960-mut:pi 1줄" "$n" 1
seats_pi pi#5 pi; pifile "$NOW"; rm -f "$ZC_RESUME_DIR/pi#5.json"; RT_BIN="$T/bin/ft-seat-retire.mut.sh"
out="$(close 'pi#5' --reason "변이" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓕ pi 갈래 끔 → 재개 기록 파일 0(ⓒ FAIL)" "$([ -f "$ZC_RESUME_DIR/pi#5.json" ] && echo yes || echo no)" no
chk "ⓕ 그래도 명부 agent=pi → NORECORD 줄 1 + 닫힘(계약 ①)" "$rc $(printf '%s\n' "$out" | grep -c '^NORECORD ')" "0 1"
RT_BIN=""
n="$(mutate "$T/bin/ft-seat-close.sh" "$T/bin/ft-seat-close.mut.sh" '[ "$AGENT" = pi ] && RK=NORECORD || held' 'RK=NORECORD' sub)"
chk "변이 표지 agent 칸 판정 1줄" "$n" 1
seats_pi cl#6 claude; rm -f "$SESS"; mkdir -p "$T/pi 세션 없음/resume"; printf '{}\n' > "$T/pi 세션 없음/resume/cl#6.json"; CLOSE_BIN=ft-seat-close.mut.sh
out="$(RDIR="$T/pi 세션 없음/resume" close 'cl#6' --reason "변이" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓕ «판정을 출력 글자로 되돌림» → rc 0 (ⓥ FAIL)" "$rc" 0
CLOSE_BIN=""

echo "== ⓡ r2 DA HOLD1 — pi 세션 파일 0: 수용한 NORECORD 원문 줄(좌석·사유)이 출력된다(조용한 통과 0)"
seats_pi pi#7 pi; rm -f "$SESS"
out="$(close 'pi#7' --reason "r960 NORECORD 줄" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
nl="$(printf '%s\n' "$out" | grep '^NORECORD ' | head -1)"
chk "ⓡ rc 0 · CLOSED-ROLE record=NORECORD" "$rc $(printf '%s' "$out" | grep -o 'record=[^ ]*')" "0 record=NORECORD"
chk "ⓡ NORECORD 줄 1개" "$(printf '%s\n' "$out" | grep -c '^NORECORD ')" 1
has "$nl" "NORECORD pi#7 " "  └ NORECORD 줄에 좌석 이름"
has "$nl" "pi 세션 없음 — 산출 커밋 보존" "  └ NORECORD 줄에 산출 보존 사유"

echo "== ⓢ r2 DA HOLD2 — 머리 줄 session + 뒤 줄 model_change.modelId → 재개 기록 ok · model = 마지막 model_change"
pifile_mc() { printf '{"type":"session","version":3,"id":"aaaa-1111","timestamp":"%s","cwd":"%s"}\n{"type":"model_change","id":"b","modelId":"first/model"}\n{"type":"message","id":"c","message":{"role":"user"}}\n{"type":"model_change","id":"d","modelId":"opengateway/deepseek/last-model"}\n' "$NOW" "$PDIR" > "$SESS"; }
pifile_mc
printf '{"_master":"M#1","M#1":{"role":"master","tick":"t"},"pi#8":{"role":"nano","agent":"pi","tick":null,"index":"x.md"}}\n' > "$REPO/.fable-team/seats.json"
out="$(retire_rec 'pi#8')"; rc=$?
chk "ⓢ retire rc 0 · RESUME ok" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1-2)" "0 RESUME ok"
chk "ⓢ model = 마지막 model_change.modelId" "$(J "$ZC_RESUME_DIR/pi#8.json" '.model')" "opengateway/deepseek/last-model"
out="$(close 'pi#8' --reason "r960 model_change" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓢ close rc 0 · 기록 경로 출력" "$rc $(printf '%s' "$out" | grep -o "record=[^ ]*")" "0 record=$ZC_RESUME_DIR/pi#8.json"

n="$(mutate "$T/bin/ft-seat-close.sh" "$T/bin/ft-seat-close.mut2.sh" 'elif [ "$REC" = NORECORD ]; then printf' '  :')"
chk "변이 표지 finish NORECORD 줄 1줄" "$n" 1
seats_pi pi#9 pi; rm -f "$SESS"; CLOSE_BIN=ft-seat-close.mut2.sh
out="$(close 'pi#9' --reason "변이" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"
chk "ⓡ 변이 «수용 뒤 출력 생략» → NORECORD 줄 0 (ⓡ FAIL)" "$(printf '%s\n' "$out" | grep -c '^NORECORD ')" 0
CLOSE_BIN=""
cp "$T/bin/ft_roster_lib.py" "$T/bin/ft_roster_lib.py.orig"
n="$(mutate "$T/bin/ft_roster_lib.py.orig" "$T/bin/ft_roster_lib.py" "# r960-mut:firstline" '    use = model if isinstance(model, str) and model else best[2].get("modelId")')"
chk "변이 표지 r960-mut:firstline 1줄" "$n" 1
pifile_mc
printf '{"_master":"M#1","M#1":{"role":"master","tick":"t"},"pi#10":{"role":"nano","agent":"pi","tick":null,"index":"x.md"}}\n' > "$REPO/.fable-team/seats.json"
out="$(retire_rec 'pi#10')"; rc=$?
has "$out" "model 못 읽음" "ⓢ 변이 «첫 줄만» → model 못 읽음(ⓢ FAIL)"
chk "ⓢ 변이 기록 파일 0" "$([ -f "$ZC_RESUME_DIR/pi#10.json" ] && echo yes || echo no)" no
cp "$T/bin/ft_roster_lib.py.orig" "$T/bin/ft_roster_lib.py"

echo "== ⓣ r3 DA HOLD — 죽은 pi 좌석(세션 파일·기존 기록 없음) → CLOSED-DEAD + NORECORD 줄 1"
seats_pi pi#dead pi; rm -f "$SESS"
out="$(FAKE_SESSION=0 close 'pi#dead' --reason "r3 죽은 pi" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓣ rc 0 · 첫 줄 CLOSED-DEAD" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1-2)" "0 CLOSED-DEAD pi#dead"
chk "ⓣ NORECORD 줄 1개" "$(printf '%s\n' "$out" | grep -c '^NORECORD ')" 1
has "$out" "NORECORD pi#dead pi 세션 없음 — 산출 커밋 보존" "  └ NORECORD 줄에 좌석·사유"
chk "ⓣ 명부 닫힘(stop-ready · _closed.dead)" "$(J "$REPO/.fable-team/seats.json" '.["pi#dead"]|[.role,._closed.dead]|join(",")')" "stop-ready,true"

echo "== ⓤ 갈래 묶음(살아 있음 · 죽음 · HELD) × (세션 파일 있음 · 없음) → 각각 재개 기록 경로 또는 NORECORD 줄"
rec_or_norec() { printf '%s\n' "$1" | grep -qE '^(NORECORD |RESUME ok )|record=/[^ ]+' && echo yes || echo no; }
seats_pi pi#u1 pi; pifile "$NOW"
out="$(close 'pi#u1' --reason "ⓤ 살아있음+파일" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓤ 살아있음+세션파일 → 재개 기록 경로" "$rc $(rec_or_norec "$out")" "0 yes"
seats_pi pi#u2 pi; rm -f "$SESS"
out="$(close 'pi#u2' --reason "ⓤ 살아있음+없음" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"
chk "ⓤ 살아있음+세션없음 → NORECORD 줄 1" "$(rec_or_norec "$out") $(printf '%s\n' "$out" | grep -c '^NORECORD ')" "yes 1"
seats_pi pi#u3 pi; pifile "$NOW"
out="$(FAKE_SESSION=0 close 'pi#u3' --reason "ⓤ 죽음+파일" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"
chk "ⓤ 죽음+세션파일 → 재개 기록 경로(RESUME ok 줄1)" "$(rec_or_norec "$out") $(printf '%s\n' "$out" | grep -c '^RESUME ok ')" "yes 1"
seats_pi pi#u4 pi; rm -f "$SESS"
out="$(FAKE_SESSION=0 close 'pi#u4' --reason "ⓤ 죽음+없음" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"
chk "ⓤ 죽음+세션없음 → NORECORD 줄 1" "$(rec_or_norec "$out") $(printf '%s\n' "$out" | grep -c '^NORECORD ')" "yes 1"
seats_pi cl#u5 claude
out="$(close 'cl#u5' --reason "ⓤ HELD" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓤ HELD(claude 기록 없음) rc 3 · NORECORD 줄 1" "$rc $(printf '%s\n' "$out" | grep -c '^NORECORD ')" "3 1"

n="$(mutate "$T/bin/ft-seat-close.sh" "$T/bin/ft-seat-close.mut3.sh" 'vlog dead; [ "$CELLS" = - ]' '  vlog dead; echo "CLOSED-DEAD $SEAT record=$RK handoff=$CELLS"; exit 0')"
chk "변이 표지 죽은 갈래 finish 앞 exit 1줄" "$n" 1
seats_pi pi#deadm pi; rm -f "$SESS"; CLOSE_BIN=ft-seat-close.mut3.sh
out="$(FAKE_SESSION=0 close 'pi#deadm' --reason "변이" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"
chk "ⓣ 변이 «죽은 갈래 exit 를 함수 앞에» → NORECORD 줄 0 (ⓣ FAIL)" "$(printf '%s\n' "$out" | grep -c '^NORECORD ')" 0
CLOSE_BIN=""

echo "== ⓥ r4 DA 반례 — agent=claude · 세션 없음 · 재개 기록 «경로» 에 «pi 세션 없음» 글자 → HELD rc 3 · kill 0 · role 불변"
seats_pi cl#v claude; rm -f "$SESS"; mkdir -p "$T/pi 세션 없음/resume"; printf '{}\n' > "$T/pi 세션 없음/resume/cl#v.json"; : > "$TMUX_LOG"
out="$(RDIR="$T/pi 세션 없음/resume" close 'cl#v' --reason "r4 경로 글자" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓥ rc 3 · HELD" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1)" "3 HELD"
has "$out" "pi 세션 없음" "  └ 출력에 «pi 세션 없음» 경로 글자 실재(반례 성립)"
chk "ⓥ 명부 role 불변(nano) · kill 0" "$(J "$REPO/.fable-team/seats.json" '.["cl#v"].role') $(grep -c '^kill-session' "$TMUX_LOG" || true)" "nano 0"

echo "== ⓦ 명부에 agent 칸 없음 → pi 수용 0 = HELD rc 3 · kill 0(조용한 수용 0)"
printf '{"_master":"M#1","M#1":{"role":"master","tick":"t"},"no#w":{"role":"nano","tick":null}}\n' > "$REPO/.fable-team/seats.json"; rm -f "$SESS"; : > "$TMUX_LOG"
out="$(close 'no#w' --reason "r4 agent 칸 없음" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓦ rc 3 · HELD" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1)" "3 HELD"
chk "ⓦ 명부 role 불변(nano) · kill 0" "$(J "$REPO/.fable-team/seats.json" '.["no#w"].role') $(grep -c '^kill-session' "$TMUX_LOG" || true)" "nano 0"

echo "== ⓦr5 — 좌석 사실(명부 경로·행·agent·role·재개 기록 경로)을 입구에서 1회 확정 · 불일치 = 판정 아님(REJECT · 명부 쓰기 0 · kill 0)"
sel() { printf '{"%s":{"role":"%s","agent":"%s","tick":null,"index":"x.md"}}\n' "$1" "$2" "$3" > "$REPO/.fable-team/selected.json"; }
# ⓦr5-1 — 확정(FT_SEATS_JSON) agent=claude ≠ 루트 agent=pi → 어느 행이 사실인지 모른다 = REJECT(닫기·HELD 둘 다 아님)
seats_pi cl#1 pi; sel cl#1 nano claude; rm -f "$SESS"; : > "$TMUX_LOG"
out="$(SEATS_ENV="$REPO/.fable-team/selected.json" close 'cl#1' --reason "r5 불일치" --verdict 2400)"; rc=$?
chk "ⓦr5-1 rc 1 · REJECT" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1)" "1 REJECT"
has "$out" "REJECT cl#1 명부 불일치" "  └ REJECT 줄에 좌석·불일치"
chk "ⓦr5-1 명부 쓰기 0 · kill 0" "$(J "$REPO/.fable-team/seats.json" '.["cl#1"].role') $(grep -c '^kill-session' "$TMUX_LOG" || true)" "nano 0"
seats_pi cl#1r claude; sel cl#1r nano pi   # 반대로 두어도 같다(pi 좌석이면 HELD 로 새지 않는다)
out="$(SEATS_ENV="$REPO/.fable-team/selected.json" close 'cl#1r' --reason "r5 불일치 반대" --verdict 2400)"; rc=$?
chk "ⓦr5-1 반대 배치도 rc 1 · REJECT" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1)" "1 REJECT"
chk "ⓦr5-1 반대 배치 명부 쓰기 0 · kill 0" "$(J "$REPO/.fable-team/seats.json" '.["cl#1r"].role') $(grep -c '^kill-session' "$TMUX_LOG" || true)" "nano 0"
# ⓦr5-2 — --seats 는 확정이 이김: 루트에 그 좌석 없음 · FT_SEATS_JSON 은 다른 agent → --seats 로 닫힌다
printf '{"_master":"M#1","M#1":{"role":"master","tick":"t"}}\n' > "$REPO/.fable-team/seats.json"; sel o#2 nano pi; printf '{"o#2":{"role":"nano","agent":"claude"}}\n' > "$REPO/.fable-team/other.json"; pifile "$NOW"
out="$(SEATS_ENV="$REPO/.fable-team/other.json" close 'o#2' --reason "r5 확정이 이김" --seats "$REPO/.fable-team/selected.json" --verdict 2400)"; rc=$?
chk "ⓦr5-2 --seats 확정 → 정상 닫기 rc 0" "$rc $(printf '%s' "$out" | grep -o '^CLOSED-ROLE o#2' | head -1)" "0 CLOSED-ROLE o#2"
chk "ⓦr5-2 확정 파일만 닫힘(다른 명부 쓰기 0)" "$(J "$REPO/.fable-team/selected.json" '.["o#2"].role') $(J "$REPO/.fable-team/other.json" '.["o#2"].role')" "stop-ready nano"
# ⓦr5-2b — 값이 «같은» 중복 등록은 막지 않고 경고 1줄(중복 등록 정리는 범위 밖)
seats_pi dup#1 pi; printf '{"dup#1":{"role":"nano","agent":"pi","tick":null,"index":"x.md"}}\n' > "$REPO/.fable-team/seats-x.json"; pifile "$NOW"
out="$(SEATS_ENV="$REPO/.fable-team/seats.json" close 'dup#1' --reason "r5 중복 등록" --verdict 2400)"; rc=$?
chk "ⓦr5-2b 같은 값 중복 → 경고 1줄 + 닫힘 rc 0" "$rc $(printf '%s\n' "$out" | grep -c '^WARN dup#1 명부 중복 등록')" "0 1"
rm -f "$REPO/.fable-team/seats-x.json"
# ⓦr5-3 — 자식(ft-seat-retire)에 확정 경로를 «항상» 넘긴다(ARG 없을 때 포함)
cat > "$T/bin/stub-retire.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$T/retire-args.txt"
echo "RESUME ok \$ZC_RESUME_DIR/\$1.json"
EOF
chmod +x "$T/bin/stub-retire.sh"; seats_pi pi#s3 pi; pifile "$NOW"
out="$(RT_BIN="$T/bin/stub-retire.sh" SEATS_ENV="" close 'pi#s3' --reason "r5 자식 인자" --verdict 2400)"; rc=$?
chk "ⓦr5-3 ARG 없이도 rc 0" "$rc $(printf '%s' "$out" | grep -o '^CLOSED-ROLE pi#s3' | head -1)" "0 CLOSED-ROLE pi#s3"
chk "ⓦr5-3 스텁이 받은 --seats = 확정 경로" "$(grep -A1 '^--seats$' "$T/retire-args.txt" | tail -1)" "$REPO/.fable-team/seats.json"
out="$(RT_BIN="$T/bin/stub-retire.sh" close 'pi#s3' --reason "r5 자식 인자2" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"
chk "ⓦr5-3 --seats 로 줘도 같은 경로 1번" "$(grep -c '^--seats$' "$T/retire-args.txt") $(grep -A1 '^--seats$' "$T/retire-args.txt" | tail -1)" "1 $REPO/.fable-team/seats.json"
RT_BIN=""
# ⓦr5-4 — 재개 기록 경로는 입구에서 1번: lineage_ok 이 ZC_RESUME_DIR 규칙의 «그 값»을 본다(kill 판정이 그 파일 실재로 갈린다)
RD5="$T/r5rd"; mkdir -p "$RD5"; seats_pi lg#5 claude; printf '{"engine":"claude"}\n' > "$RD5/lg#5.json"
out="$(RDIR="$RD5" FAKE_SESSIONS="lg#6" close 'lg#5' --reason "r5 경로 한 번" --seats "$REPO/.fable-team/seats.json")"; rc=$?
chk "ⓦr5-4 기록 있음 → kill=ok rc 0" "$rc $(printf '%s' "$out" | grep -o 'kill=[a-z]*')" "0 kill=ok"
RM="$RD5/lg#5.json"; mv "$RM" "$RD5/hold.json"
out="$(RDIR="$RD5" FAKE_SESSIONS="lg#6" close 'lg#5' --reason "r5 경로 한 번2" --seats "$REPO/.fable-team/seats.json")"; rc=$?
chk "ⓦr5-4 기록 없음 → kill=held rc 3(같은 경로를 본다)" "$rc $(printf '%s' "$out" | grep -o 'kill=held')" "3 kill=held"
# ⓦr5-5 — 회귀 꼴: 세션 파일 없음 + pi → NORECORD 1줄 + 닫힘 · claude → HELD rc 3 · kill 0
seats_pi pi#r5 pi; rm -f "$SESS"; : > "$TMUX_LOG"
out="$(close 'pi#r5' --reason "r5 회귀 pi" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓦr5-5 pi rc 0 · NORECORD 줄 1" "$rc $(printf '%s\n' "$out" | grep -c '^NORECORD ')" "0 1"
seats_pi cl#r5 claude; : > "$TMUX_LOG"
out="$(close 'cl#r5' --reason "r5 회귀 claude" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓦr5-5 claude rc 3 HELD · kill 0" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1) $(grep -c '^kill-session' "$TMUX_LOG" || true)" "3 HELD 0"
# 변이 4종 — 각각 ⓦ 하나를 무너뜨린다
cp "$T/bin/ft_roster_lib.py" "$T/bin/ft_roster_lib.py.r5"
CLIB="$T/bin/ft_roster_lib.py"
n="$(mutate "$T/bin/ft_roster_lib.py.r5" "$CLIB" '    cand = [arg] if arg else [env] if env else files' '    cand = files')"
chk "변이 표지 확정 되살림(루트 글롭) 1줄" "$n" 1
seats_pi cl#m1 pi; sel cl#m1 nano claude; rm -f "$SESS"
out="$(SEATS_ENV="$REPO/.fable-team/selected.json" close 'cl#m1' --reason "변이" --verdict 2400)"
chk "ⓦr5-1 변이 «루트 글롭 되살림» → 불일치 REJECT 0 (ⓦr5-1 FAIL)" "$(printf '%s\n' "$out" | grep -c '^REJECT cl#m1 명부 불일치')" 0
cp "$T/bin/ft_roster_lib.py.r5" "$CLIB"
n="$(mutate "$T/bin/ft_roster_lib.py.r5" "$CLIB" '        if (a, r) != (a2, r2):' '        if False and (a, r) != (a2, r2):')"
chk "변이 표지 불일치 무시 1줄" "$n" 1
seats_pi cl#m2 pi; sel cl#m2 nano claude; rm -f "$SESS"
out="$(SEATS_ENV="$REPO/.fable-team/selected.json" close 'cl#m2' --reason "변이" --verdict 2400)"
chk "ⓦr5-1 변이 «불일치 때 확정으로 진행» → 불일치 REJECT 0 (ⓦr5-1 FAIL)" "$(printf '%s\n' "$out" | grep -c '^REJECT cl#m2 명부 불일치')" 0
cp "$T/bin/ft_roster_lib.py.r5" "$CLIB"
n="$(mutate "$T/bin/ft-seat-close.sh" "$T/bin/ft-seat-close.mut4.sh" '${SEATS_FILE:+--seats "$SEATS_FILE"}' '${ARG:+--seats "$ARG"}' sub)"
chk "변이 표지 자식 --seats 조건부 1줄" "$n" 1
seats_pi pi#m3 pi; pifile "$NOW"; CLOSE_BIN=ft-seat-close.mut4.sh
out="$(RT_BIN="$T/bin/stub-retire.sh" SEATS_ENV="" close 'pi#m3' --reason "변이" --verdict 2400)"
chk "ⓦr5-3 변이 «자식에 조건부» → 스텁이 받은 --seats 0 (ⓦr5-3 FAIL)" "$(grep -c '^--seats$' "$T/retire-args.txt" || true)" 0
CLOSE_BIN=""
RD5="$T/r5rd"
mv "$RD5/hold.json" "$RD5/lg#5.json"
n="$(mutate "$T/bin/ft-seat-close.sh" "$T/bin/ft-seat-close.mut5.sh" 's rec="$RECF"' 's rec="$HOME/.claude/state/seat-resume/$SEAT.json"' sub)"
chk "변이 표지 lineage 경로 자체 계산 1줄" "$n" 1
seats_pi lg#5 claude; CLOSE_BIN=ft-seat-close.mut5.sh
out="$(RDIR="$RD5" FAKE_SESSIONS="lg#6" close 'lg#5' --reason "변이" --seats "$REPO/.fable-team/seats.json")"; rc=$?
chk "ⓦr5-4 변이 «경로 자체 계산» → kill=held (ⓦr5-4 FAIL)" "$rc $(printf '%s' "$out" | grep -o 'kill=held')" "3 kill=held"
CLOSE_BIN=""


NOFIN="$(awk '/^finish\(\)/{f=1} f&&/^}/{f=0;next} !f' "$BIN/ft-seat-close.sh" | grep -v '^[[:space:]]*#')"
chk "finish() 밖 exit 0 = 0" "$(printf '%s\n' "$NOFIN" | grep -c 'exit 0')" 0
chk "finish() 밖 결과 줄 직접 echo = 0" "$(printf '%s\n' "$NOFIN" | grep -cE 'echo "(CLOSED|HELD|FAIL|CLOSE-FAIL)')" 0
chk "finish() 갈래 호출 ≥ 5" "$([ "$(grep -c 'finish [0-9]' "$BIN/ft-seat-close.sh")" -ge 5 ] && echo yes || echo no)" yes
chk "r5 좌석 사실 확정 python 호출 1곳" "$(grep -c 'from ft_roster_lib import seat_facts' "$BIN/ft-seat-close.sh")" 1
chk "r5 본문 인라인 명부 재해석 0(python3 -c 1줄 = facts)" "$(grep -c 'python3 -c' "$BIN/ft-seat-close.sh")" 1
chk "r5 seat_facts 정의 1곳" "$(grep -c 'def seat_facts' "$BIN/ft_roster_lib.py")" 1

echo "== ⓖ 600/300 s · 외부 호출 0 (r960 새 줄)"
NEWL="$(grep 'r960\|pi_seat_resume\|PI_NOREC' "$BIN/ft-seat-retire.sh" "$BIN/ft-seat-close.sh" "$BIN/ft_roster_lib.py")"
hasnt_() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
hasnt_ "$(printf '%s\n' "$NEWL" | grep -nE '(^|[^0-9])(600|300)([^0-9]|$)')" ":" "ⓖ 600/300 숫자 0"
hasnt_ "$(printf '%s\n' "$NEWL" | grep -nE 'curl|wget|https?://|gh |nc ')" ":" "ⓖ 외부 호출 0"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
