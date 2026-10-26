#!/usr/bin/env bash
# test_seat_handover_r939.sh — r939: 승계는 «스스로 등록한 곧 끝나는 일»(DA·설치·격리 사본)을 죽이지 않고 후계에게 넘긴다 · 감시 루프·미등록은 지금처럼 reap.
#   ★판정 = 등록 장부(state/bg-finite.tsv) 만★ — 명령줄 글자·env 짐작 0 (DA⑥ r1 반례: «허용 목록 글자 흉내»·«인자 속 while»)
#   ⓐ 등록 DA + 미등록 bash watcher.sh(안이 루프) + 미등록 `timeout 999999 bash watcher.sh` → retire A→B: DA 만 넘김 · 둘 다 reap · 장부 좌석 칸 = B
#   ⓑ 등록 DA 의 pgid 안 자식 → 같이 넘김 · 미등록 «install.sh 라는 글자» 부모 아래 루프 → reap
#   ⓒ `ft-da-codex.sh --prompt review while loop` 꼴 등록 DA(명령줄에 while·install.sh 글자) → 넘김 (글자 판정 0)
#   ⓓ B 가 다시 retire B→C → 같은 DA 넘김 · 장부 좌석 = C / 그 좌석 닫기(후계 없음) → 그 DA reap · 장부 줄 지움
#   ⓔ 등록 줄 두 개 차례로 → 장부에 둘 다 남음(덮어쓰기 0) · 상한 지난 줄 1 + 신선한 줄 1 + 죽은 pid 줄 1 → leak-reap: 상한 지난 것만 보고 · 죽은 줄 지움
#   ⓕ `--handover B --defer-press` + press 점유 → DA 넘김(미룸 0) · 그 뒤 digest 에서 reap 0
#   ⓖ 도구 끝남(trap EXIT) → 자기 줄 지워짐 · kill -9 로 끝남(trap 0) → 다음 leak-reap 이 죽은 pid 줄 지움
#   r3: ⓗ press 미룸 뒤 --handover → 미룬 등록 DA 넘김(digest 가 안 죽임) · ⓘ register 상한 4200 으로 잘림 · ⓙ leak-reap lstart 다른 pid 줄 지움·보고 0 · ⓚ 상한 지난 등록 줄 = reap(넘김 0)
#   변이 8(사본에서만 · 원본/변이를 같은 조건으로 돌려 기대값이 갈리는지 본다): 글자 판정 복귀 → ⓐ · 좌석 칸 갱신 끔 → ⓓ · 장부 덮어쓰기 → ⓔ · 넘김 앞단 끔 → ⓕ · digest 넘김 건너뜀 끔 → ⓗ · 상한 자름 끔 → ⓘ · lstart 비교 끔 → ⓙ · 만료도 넘김 → ⓚ
# 실프로세스 픽스처 = 표식 r939fx-<pid> 를 argv 에 단 ppid 1 고아(좌석 이름 가짜 · tmux 세션 없음 → env FT_SEAT 경로) — trap 이 정리. 상태 폴더·장부는 전부 임시.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R939_BIN:-$HERE/../../harness/bin}"
REAP="$BIN/ft-seat-reap.sh"; RETIRE="$BIN/ft-seat-retire.sh"; LEAK="$BIN/ft-leak-reap.sh"; BGF="$BIN/ft-bg-finite.sh"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; MK="r939fx-$$"
A="r939a-$$#0"; B="r939b-$$#1"; C="r939c-$$#2"
cleanup() { local p; for p in $(pgrep -f "$MK" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done; }
trap 'cleanup; rm -rf "$T0"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있음: «$2» ← ${1:0:500}";; *) ok "$3";; esac; }
alive() { kill -0 "$1" 2>/dev/null && echo alive || echo dead; }
killtag() { local p; for p in $(pgrep -f -- "$1" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done; sleep 0.2; }
fresh() { cleanup; sleep 0.2; rm -f "$TMP/bg-finite.tsv"* "$TMP/defer/"* "$TMP/permits/device.json"; }   # 앞 절 픽스처 잔여물 정리(넘김·미룸 판정이 옛 프로세스를 보지 않게)
rows() { FT_BG_FINITE_LEDGER="$TMP/bg-finite.tsv" bash "$BGF" rows; }
seats() {   # seats <좌석>… — 그 좌석들만 담은 명부 픽스처
  local n="$#" out="{" sep=""
  for n in "$@"; do out="$out$sep\"$n\": {\"role\": \"tester\", \"agent\": \"claude\", \"model\": \"m\", \"tick\": null}"; sep=", "; done
  printf '%s}\n' "$out" > "$TMP/seats.json"
}

mkdir -p "$TMP/da" "$TMP/inst" "$TMP/gu" "$TMP/resume" "$TMP/permits" "$TMP/defer"
mkdir -p "$TMP/gu/install.sh"   # «install.sh 라는 글자» 를 폴더 이름으로 쓴 미등록 부모(글자 판정 반례)
cat > "$TMP/da/ft-da-codex.sh" <<'EOF'
sleep 60
EOF
cat > "$TMP/da/fork.sh" <<'EOF'
sleep 60 &
sleep 60
EOF
cat > "$TMP/inst/install-body.sh" <<'EOF'
sleep 60
EOF
cat > "$TMP/gu/watcher.sh" <<'EOF'
while true; do sleep 1; done
EOF
cat > "$TMP/gu/loop.sh" <<'EOF'
while true; do sleep 1; done
EOF
chmod +x "$TMP/da/"*.sh "$TMP/inst/"*.sh "$TMP/gu/"*.sh
export ZC_RESUME_DIR="$TMP/resume" FT_SUCCESSOR_DIR="$TMP/succ" FT_PERMIT_DIR="$TMP/permits" FT_REAP_DEFER_DIR="$TMP/defer"
export FT_BG_FINITE_LEDGER="$TMP/bg-finite.tsv"
export FT_PRESS_RUNNER_RE="r939-never-$$"   # 이 머신의 실 press 가 픽스처 판정에 섞이지 않게
TMO="$(command -v timeout 2>/dev/null || true)"
BASH_X="$(command -v bash)"

cat > "$TMP/setsid.py" <<'EOF'
import os, sys
os.setsid()          # macOS 에 setsid(1) 이 없다 — 자기 세션·프로세스 그룹으로 띄운다(tmux pane·launchd 와 같은 꼴)
os.execvp(sys.argv[1], sys.argv[1:])
EOF
spawn() {  # spawn <표식> <env…|""> <명령…> — ppid 1 고아 1개 · pid 출력
  local tag="$1" envs="$2"; shift 2
  ( cd "$TMP" || exit; env FT_SEAT="$A" $envs nohup python3 "$TMP/setsid.py" "$@" >/dev/null 2>&1 & )
  sleep 0.6
  pgrep -f -- "$tag" | while read -r p; do [ "$(ps -o ppid= -p "$p" | tr -d ' ')" = 1 ] && echo "$p"; done | tail -1
}
reg() {  # reg <좌석> <상한초> <pid> [명령] — 장부 등록(도구가 하는 일을 대역으로)
  FT_BG_FINITE_LEDGER="$TMP/bg-finite.tsv" bash "$BGF" register "$1" "$2" "$3" "${4:-dae}" >/dev/null 2>&1
}
ret() { bash "$RETIRE" "$1" "$2" --seats "$TMP/seats.json" 2>&1; }   # retire <구> <후계> · stdout+stderr

chk "ⓐ픽스처 전제 = ft-bg-finite.sh 있음" "$([ -x "$BGF" ] && echo yes)" yes
PROBE="$(spawn "p-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "p-$MK")"
ENVOK=0; [ -n "$PROBE" ] && ps -E -ww -o command= -p "$PROBE" | grep -q "FT_SEAT=$A" && ENVOK=1; kill "$PROBE" 2>/dev/null
[ "$ENVOK" = 1 ] || { echo "SKIP 이 머신은 $BASH_X 의 env 를 ps 로 못 읽음 — ② 고아 픽스처 불가"; exit 0; }
for f in "$REAP" "$RETIRE" "$LEAK" "$BGF"; do bash -n "$f" && ok "bash -n $(basename "$f")" || bad "bash -n $f"; done

echo "== ⓐ 등록 DA 만 넘김 · 미등록(루프·timeout 루프)은 reap · 장부 좌석 칸 = B"
fresh
seats "$A"
DA="$(spawn "da-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "da-$MK")"
WA="$(spawn "wa-$MK" "" "$BASH_X" "$TMP/gu/watcher.sh" --tag "wa-$MK")"
if [ -n "$TMO" ]; then TL="$(spawn "tl-$MK" "" "$TMO" 999999 "$BASH_X" "$TMP/gu/watcher.sh" --tag "tl-$MK")"; else TL=""; fi
reg "$A" 4200 "$DA" "bash ft-da-codex.sh --cwd $TMP"
chk "ⓐ픽스처(등록 DA · 미등록 루프 · timeout 루프)" "$([ -n "$DA" ] && [ -n "$WA" ] && { [ -z "$TMO" ] || [ -n "$TL" ]; } && echo ok)" ok
out="$(ret "$A" "$B")"; rc=$?
chk "ⓐretire rc 0" "$rc" 0
has "$out" "reap-handover pid=$DA cmd=" "ⓐ등록 DA 넘김 줄"
has "$out" " to=$B" "ⓐ넘김 대상 = 후계"
hasnt "$out" "reap-handover pid=$WA" "ⓐ미등록 루프는 넘기지 않음"
chk "ⓐDA 생존 · 미등록 루프 정지" "$(alive "$DA") $(alive "$WA")" "alive dead"
[ -z "$TMO" ] || chk "ⓐtimeout 999999 루프 정지(글자·시간 판정 0)" "$(alive "$TL")" dead
chk "ⓐ끝 줄 = 미등록 루프만 stopped · handed=1 left=0" "$(grep -oE 'stopped=[0-9]+ handed=[0-9]+ left=[0-9]+' <<< "$out" | tail -1)" "stopped=$([ -n "$TMO" ] && echo 2 || echo 1) handed=1 left=0"
chk "ⓐ장부 좌석 칸 = B · 상태 handed" "$(rows | awk -F'\t' -v p="$DA" '$2==p{print $1, $6}')" "$B handed"
kill "$DA" 2>/dev/null

echo "== ⓑ 등록 DA 의 pgid 자식도 같이 넘김 · 미등록 «install.sh 글자» 부모 아래 루프는 reap"
fresh
seats "$A"
FK="$(spawn "fk-$MK" "" "$BASH_X" "$TMP/da/fork.sh" --tag "fk-$MK")"
reg "$A" 4200 "$FK" "bash ft-da-codex.sh --cwd $TMP"
KID="$(pgrep -P "$FK" | head -1)"
IM="$(spawn "im-$MK" "" "$BASH_X" "$TMP/gu/install.sh/../loop.sh" --tag "im-$MK")"
chk "ⓑ픽스처(등록 부모 · 자식 · 미등록 루프)" "$([ -n "$FK" ] && [ -n "$KID" ] && [ -n "$IM" ] && echo ok)" ok
out="$(ret "$A" "$B")"
chk "ⓑ등록 부모·자식 생존 · 미등록 루프 정지" "$(alive "$FK") $(alive "$KID") $(alive "$IM")" "alive alive dead"
has "$out" "reap-handover pid=$FK" "ⓑ등록 뿌리 넘김 줄"
chk "ⓑ끝 줄 handed=1(자식으로 부풀리지 않음)" "$(grep -oE 'handed=[0-9]+' <<< "$out" | tail -1)" "handed=1"
kill "$FK" "$KID" 2>/dev/null

echo "== ⓒ 명령줄에 while·install.sh «글자» 가 있어도 등록된 DA 는 넘김(글자 판정 0)"
fresh
seats "$A"
LC="$(spawn "lc-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --prompt "review while loop install.sh" --tag "lc-$MK")"
reg "$A" 4200 "$LC" "bash ft-da-codex.sh --prompt review while loop install.sh"
out="$(ret "$A" "$B")"
has "$out" "reap-handover pid=$LC" "ⓒ글자 있는 등록 DA 넘김"
chk "ⓒ생존" "$(alive "$LC")" alive
kill "$LC" 2>/dev/null

echo "== ⓓ 장부 좌석 칸이 후계로 → 다음 승계도 넘김 · 그 좌석 닫기는 이 작업을 reap 하고 장부 줄을 지움"
fresh
seats "$A" "$B"
DA2="$(spawn "d2-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "d2-$MK")"
reg "$A" 4200 "$DA2" "bash ft-da-codex.sh"
out="$(ret "$A" "$B")"
chk "ⓓ1차 넘김 → 장부 좌석 B" "$(rows | awk -F'\t' -v p="$DA2" '$2==p{print $1}')" "$B"
seats "$B"; out="$(ret "$B" "$C")"
has "$out" "reap-handover pid=$DA2" "ⓓB→C 재넘김(장부로 후계가 본다)"
chk "ⓓ장부 좌석 = C" "$(rows | awk -F'\t' -v p="$DA2" '$2==p{print $1}')" "$C"
chk "ⓓ재넘김 뒤 생존" "$(alive "$DA2")" alive
out="$(bash "$REAP" "$C" --orphans-only 2>&1)"   # 그 좌석 «닫기»(후계 없음)
chk "ⓓ닫기 = 그 작업 reap · 장부 줄 0" "$(alive "$DA2") [$(rows | awk -F'\t' -v p="$DA2" '$2==p' | wc -l | tr -d ' ')]" "dead [0]"
hasnt "$out" "reap-handover" "ⓓ닫기엔 넘김 줄 0"

echo "== ⓔ 장부 = 덮어쓰기 0(줄 2개) · leak-reap 은 상한 지난 줄만 보고하고 죽은 줄은 지움"
fresh
S1="$(spawn "e1-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "e1-$MK")"
S2="$(spawn "e2-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "e2-$MK")"
reg "$A" 0 "$S1" "old job"          # 상한 지난 줄(상한 0초 = 등록 즉시 만료)
reg "$A" 4200 "$S2" "fresh job"     # 신선한 줄
GD="$(spawn "e3-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "e3-$MK")"
reg "$A" 4200 "$GD" "dead job"      # 곧 죽일 pid 줄
kill -9 "$GD" 2>/dev/null; sleep 0.2
chk "ⓔ장부 줄 3개(덮어쓰기 0)" "$(rows | wc -l | tr -d ' ')" 3
LC_ALL=C ps -o pid=,ppid=,lstart=,time=,command= -p "$S1","$S2" | sed 's/^ *//' > "$TMP/snap"   # 살아 있는 두 줄만(죽은 줄은 표에 없다)
out="$(FT_PS_SNAPSHOT="$TMP/snap" bash "$LEAK" --dry-run 2>&1)"; rc=$?
chk "ⓔ상한 지난 줄 1개만 보고" "$(grep -c 'handover-stale' <<< "$out")" 1
has "$out" "handover-stale pid=$S1" "ⓔ보고 pid = 상한 지난 줄"
has "$out" "죽이지 않음" "ⓔ죽이지 않음 표시"
hasnt "$out" "handover-stale pid=$S2" "ⓔ신선한 줄 보고 0"
chk "ⓔ죽은 pid 줄은 지움 · 신선한 줄·상한 지난 줄은 남김 · 살아 있음" "$(rows | wc -l | tr -d ' ') $(rows | grep -c "$GD") $(alive "$S1") $rc" "2 0 alive 0"
chk "ⓔ상한 지난 줄 상태 = stale" "$(rows | awk -F'\t' -v p="$S1" '$2==p{print $6}')" stale
kill "$S1" "$S2" 2>/dev/null

echo "== ⓕ press 점유 중에도 넘김이 먼저 — 미룸 0 · 그 뒤 digest 에서 reap 0"
fresh
seats "$A"
DF1="$(spawn "f1-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "f1-$MK")"
reg "$A" 4200 "$DF1" "bash ft-da-codex.sh"
printf '{"held":true,"member":"r939"}\n' > "$TMP/permits/device.json"
out="$(bash "$REAP" "$A" --orphans-only --defer-press --handover "$B" 2>&1)"
has "$out" "reap-handover pid=$DF1" "ⓕpress 점유 중에도 넘김 줄"
chk "ⓕ미룸 0 · deferred=0 · 생존" "$(grep -c 'reap-defer' <<< "$out") $(grep -oE 'deferred=[0-9]+' <<< "$out" | tail -1) $(alive "$DF1")" "0 deferred=0 alive"
rm -f "$TMP/permits/device.json"
out="$(bash "$REAP" "$A" --orphans-only --defer-press 2>&1)"   # press 끝난 뒤 다음 정리(digest)
chk "ⓕ그 뒤 reap 0(넘긴 작업은 살아 있다)" "$(alive "$DF1") $(grep -c "reap-kill pid=$DF1" <<< "$out")" "alive 0"
kill "$DF1" 2>/dev/null

echo "== ⓖ trap EXIT = 자기 줄 지움 · kill -9(trap 0) → 다음 leak-reap 이 죽은 줄 지움"
fresh
printf '#!/usr/bin/env bash\nset -uo pipefail\nbash "%s" register "${FT_SEAT:--}" 4200 "$$" "stub tool" >/dev/null\ntrap '"'"'bash "%s" unregister $$ >/dev/null 2>&1'"'"' EXIT\nsleep "${1:-0}"\n' "$BGF" "$BGF" > "$TMP/stub-tool.sh"
chmod +x "$TMP/stub-tool.sh"
FT_SEAT="$A" bash "$TMP/stub-tool.sh" 0; sleep 0.2
chk "ⓖtrap EXIT → 자기 줄 지워짐" "$(rows | wc -l | tr -d ' ')" 0
FT_SEAT="$A" bash "$TMP/stub-tool.sh" 60 & ST=$!
sleep 1; chk "ⓖstub 등록됨" "$(rows | wc -l | tr -d ' ')" 1
kill -9 "$ST" 2>/dev/null; sleep 0.2
chk "ⓖkill -9 → 줄 남음(trap 0)" "$(rows | wc -l | tr -d ' ')" 1
LC_ALL=C ps -o pid=,ppid=,lstart=,time=,command= -p $$ | sed 's/^ *//' > "$TMP/snap2"
bash "$LEAK" --dry-run > "$TMP/g_out.txt" 2>&1; FT_PS_SNAPSHOT="$TMP/snap2" bash "$LEAK" --dry-run >/dev/null 2>&1
chk "ⓖ다음 leak-reap 이 죽은 줄 지움" "$(rows | wc -l | tr -d ' ')" 0

echo "== ⓗ r3 — press 미룸 «뒤» 에 --handover 가 오면 미룬 등록 DA 는 넘김(digest 가 ⑤미룸으로 죽이지 않는다)"
fresh
seats "$A"
DH="$(spawn "h1-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "h1-$MK")"
reg "$A" 4200 "$DH" "bash ft-da-codex.sh"
printf '{"held":true,"member":"r939"}\n' > "$TMP/permits/device.json"
out="$(bash "$REAP" "$A" --orphans-only --defer-press 2>&1)"   # 승계 아닌 정리가 press 점유로 먼저 «미룬다»
chk "ⓗ전제: 미룸 1 · 생존" "$(grep -c "reap-defer pid=$DH" <<< "$out") $(alive "$DH")" "1 alive"
rm -f "$TMP/permits/device.json"
out="$(bash "$REAP" "$A" --orphans-only --defer-press --handover "$B" 2>&1)"   # press 끝난 뒤 승계
has "$out" "reap-handover pid=$DH" "ⓗ미룬 등록 DA 도 넘김 줄"
chk "ⓗhanded=1 · 생존 · reap-kill 0 · 장부 좌석 = B" "$(grep -oE 'handed=[0-9]+' <<< "$out" | tail -1) $(alive "$DH") $(grep -c "reap-kill pid=$DH" <<< "$out") $(rows | awk -F'\t' -v p="$DH" '$2==p{print $1}')" "handed=1 alive 0 $B"
kill "$DH" 2>/dev/null

echo "== ⓘ r3 — register 상한초는 4200(70분)으로 잘린다(더 크거나 정수 아님)"
fresh
IS="$(spawn "i1-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "i1-$MK")"
o1="$(FT_BG_FINITE_LEDGER="$TMP/bg-finite.tsv" bash "$BGF" register "$A" 999999 "$IS" big 2>&1)"
has "$o1" "WARN 상한초 «999999» → 4200" "ⓘ잘림 stderr 1줄"
d1="$(rows | awk -F'\t' -v p="$IS" -v n="$(date +%s)" '$2==p{print $5-n}')"
chk "ⓘ상한 = 지금 + ≤4200" "$([ "${d1:-0}" -gt 4100 ] && [ "${d1:-0}" -le 4200 ] && echo ok)" ok
o2="$(FT_BG_FINITE_LEDGER="$TMP/bg-finite.tsv" bash "$BGF" register "$A" abc "$IS" nan 2>&1)"
has "$o2" "WARN 상한초 «abc» → 4200" "ⓘ정수 아님 → 4200"
LONG9="$(printf '9%.0s' $(seq 1 4301))"   # astra r2 반례: 4301자리 → int() 한도 ValueError
for v in "--1" "-1" "+5" "1e3" "" "$LONG9"; do   # astra r1 반례: «--1» 이 ValueError 로 죽던 입력들 — 전부 rc0 · 경고 1줄 · 4200
  o3="$(FT_BG_FINITE_LEDGER="$TMP/bg-finite.tsv" bash "$BGF" register "$A" "$v" "$IS" edge 2>&1)"; rc3=$?
  d3="$(rows | awk -F'\t' -v p="$IS" -v n="$(date +%s)" '$2==p{print $5-n}')"
  chk "ⓘ입력 «${v:0:12}» → rc0 · 경고 1줄 · 4200 이하" "$rc3 $(grep -c "WARN 상한초" <<< "$o3") $([ "${d3:-0}" -gt 4100 ] && [ "${d3:-0}" -le 4200 ] && echo ok)" "0 1 ok"
done
kill "$IS" 2>/dev/null

echo "== ⓙ r3 — leak-reap: pid 재사용(lstart 다름) 줄은 보고 0 · 줄 지움 / TZ 가 달라도 같은 프로세스는 보고"
fresh
JS="$(spawn "j1-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "j1-$MK")"
reg "$A" 0 "$JS" "old job"
TZ=Asia/Seoul LC_ALL=C ps -o pid=,ppid=,lstart=,time=,command= -p "$JS" | sed 's/^ *//' > "$TMP/snapj"
out="$(TZ=Asia/Seoul FT_PS_SNAPSHOT="$TMP/snapj" bash "$LEAK" --dry-run 2>&1)"
has "$out" "handover-stale pid=$JS" "ⓙ통제: 같은 lstart(UTC 장부 vs 지역 시각 표) → 보고"
python3 - "$TMP/bg-finite.tsv" <<'PY'
import sys
p = sys.argv[1]; ls = open(p, encoding="utf-8").read().splitlines()
out = []
for ln in ls:
    f = ln.split("\t"); f[3] = "Mon Jan 1 00:00:00 2001"; out.append("\t".join(f))
open(p, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
out="$(TZ=Asia/Seoul FT_PS_SNAPSHOT="$TMP/snapj" bash "$LEAK" --dry-run 2>&1)"
hasnt "$out" "handover-stale pid=$JS" "ⓙpid 재사용 줄 보고 0"
chk "ⓙ재사용 줄 지움 · 프로세스 생존" "$(rows | grep -c .) $(alive "$JS")" "0 alive"
kill "$JS" 2>/dev/null

echo "== ⓚ r3 — 상한 지난 등록 줄은 넘기지 않고 reap(env 가 남의 좌석이어도) · 신선한 줄은 넘김"
fresh
seats "$A"
KE="$(spawn "k1-$MK" "FT_SEAT=zzz-$$" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "k1-$MK")"   # env 짐작으로는 이 좌석 것이 아님
KF="$(spawn "k2-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "k2-$MK")"
reg "$A" 0 "$KE" "expired job"
reg "$A" 4200 "$KF" "fresh job"
out="$(ret "$A" "$B")"
has "$out" "reap-expired pid=$KE" "ⓚ만료 줄 → reap-expired"
hasnt "$out" "reap-handover pid=$KE" "ⓚ만료 줄은 넘기지 않음"
has "$out" "reap-handover pid=$KF" "ⓚ신선한 줄은 넘김"
chk "ⓚ만료 정지 · 신선 생존 · 장부에 만료 줄 0" "$(alive "$KE") $(alive "$KF") $(rows | awk -F'\t' -v p="$KE" '$2==p' | wc -l | tr -d ' ')" "dead alive 0"
kill "$KF" 2>/dev/null

echo "== 정적 — 도구 3종이 «자기 등록 + trap EXIT» 를 갖는다"
for f in "$BIN/install.sh ../install.sh" "$BIN/../../kit/fable-team/bin/ft-da-codex.sh"; do :; done
DAC="$BIN/../kit/fable-team/bin/ft-da-codex.sh"; INS="$BIN/../install.sh"; SCR="$BIN/ft-scratch-repo.sh"
chk "정적 ft-da-codex.sh register+trap" "$(grep -c 'ft-bg-finite.sh" register\|ft-bg-finite.sh" unregister' "$DAC")" 2
chk "정적 install.sh register+trap" "$(grep -c 'ft-bg-finite.sh" register\|ft-bg-finite.sh" unregister' "$INS")" 2
chk "정적 ft-scratch-repo.sh register+trap" "$(grep -c 'ft-bg-finite.sh" register\|ft-bg-finite.sh" unregister' "$SCR")" 2
chk "정적 reap 은 글자 허용 목록을 안 쓴다" "$(grep -c 'FINITE_SHELL\|LOOPRE\|def finite(' "$REAP")" 0
chk "정적 닫기 3종(seat-close·nano-close) --handover 0" "$(grep -c -- '--handover' "$BIN/ft-seat-close.sh" "$BIN/ft-nano-close.sh" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')" 0

echo "== 변이 8종(사본에서만) — 고침이 빠지면 그 시험만 빨강이어야 한다 · 각 줄 = «원본 변이» 두 값(같은 조건 · 갈려야 한다)"
mut() {  # mut <이름> <파일> <바꿀 글자> <새 글자>
  rm -rf "$TMP/bin-$1"; mkdir -p "$TMP/bin-$1"; cp -R "$BIN"/. "$TMP/bin-$1/"
  python3 - "$TMP/bin-$1/$2" "$3" "$4" <<'PY' || bad "변이 앵커 불일치 $1 (MUTATE-MISS)"
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if old not in s:
    print("MUTATE-MISS"); sys.exit(3)
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
sp() { spawn "$1-$MK" "${2:-}" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "$1-$MK"; }   # sp <표식> [env]
# 시나리오 함수 — 인자 = bin 폴더 · 출력 한 토큰
scen_letter() { fresh; local m; m="$(spawn "m1-$MK" "" "$BASH_X" "$TMP/gu/install.sh/../loop.sh" --tag "m1-$MK")"   # 미등록 + 명령줄에 install.sh 글자
  bash "$1/ft-seat-reap.sh" "$A" --orphans-only --handover "$B" >/dev/null 2>&1; alive "$m"; killtag "m1-$MK"; }
scen_seat() { fresh; seats "$A"; local m o; m="$(sp m2)"; reg "$A" 4200 "$m" "bash ft-da-codex.sh"
  bash "$1/ft-seat-reap.sh" "$A" --orphans-only --handover "$B" >/dev/null 2>&1
  o="$(bash "$1/ft-seat-reap.sh" "$B" --orphans-only --handover "$C" 2>&1)"; grep -c "reap-handover pid=$m" <<< "$o"; kill "$m" 2>/dev/null; }
scen_over() { fresh; local a b; a="$(sp m3a)"; b="$(sp m3b)"
  bash "$1/ft-bg-finite.sh" register "$A" 4200 "$a" x >/dev/null 2>&1; bash "$1/ft-bg-finite.sh" register "$A" 4200 "$b" y >/dev/null 2>&1
  rows | wc -l | tr -d ' '; kill "$a" "$b" 2>/dev/null; }
scen_front() { fresh; seats "$A"; local m o; m="$(sp m4)"; reg "$A" 4200 "$m" "bash ft-da-codex.sh"
  printf '{"held":true,"member":"r939"}\n' > "$TMP/permits/device.json"
  o="$(bash "$1/ft-seat-reap.sh" "$A" --orphans-only --defer-press --handover "$B" 2>&1)"; rm -f "$TMP/permits/device.json"
  grep -c 'reap-handover pid=' <<< "$o"; kill "$m" 2>/dev/null; }
scen_digest() { fresh; seats "$A"; local m; m="$(sp m5)"; reg "$A" 4200 "$m" "bash ft-da-codex.sh"
  printf '{"held":true,"member":"r939"}\n' > "$TMP/permits/device.json"
  bash "$1/ft-seat-reap.sh" "$A" --orphans-only --defer-press >/dev/null 2>&1; rm -f "$TMP/permits/device.json"
  bash "$1/ft-seat-reap.sh" "$A" --orphans-only --defer-press --handover "$B" >/dev/null 2>&1; alive "$m"; kill "$m" 2>/dev/null; }
scen_clamp() { fresh; local m d; m="$(sp m6)"
  bash "$1/ft-bg-finite.sh" register "$A" 999999 "$m" x >/dev/null 2>&1
  d="$(rows | awk -F'\t' -v n="$(date +%s)" '{print $5-n}')"; [ "${d:-0}" -le 4200 ] && echo cap || echo big; kill "$m" 2>/dev/null; }
scen_lstart() { fresh; local m; m="$(sp m7)"; reg "$A" 0 "$m" "old job"
  python3 - "$TMP/bg-finite.tsv" <<'PY2'
import sys
p = sys.argv[1]; out = []
for ln in open(p, encoding="utf-8").read().splitlines():
    f = ln.split("\t"); f[3] = "Mon Jan 1 00:00:00 2001"; out.append("\t".join(f))
open(p, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY2
  LC_ALL=C ps -o pid=,ppid=,lstart=,time=,command= -p "$m" | sed 's/^ *//' > "$TMP/snapm"
  FT_PS_SNAPSHOT="$TMP/snapm" bash "$1/ft-leak-reap.sh" --dry-run 2>&1 | grep -c "handover-stale pid=$m"; kill "$m" 2>/dev/null; }
scen_expire() { fresh; seats "$A"; local m o; m="$(sp m8 "FT_SEAT=zzz-$$")"; reg "$A" 0 "$m" "expired job"
  bash "$1/ft-seat-reap.sh" "$A" --orphans-only --handover "$B" >/dev/null 2>&1; alive "$m"; kill "$m" 2>/dev/null; }

mut letter ft-seat-reap.sh '    kids, stack = {}, [(p, v[0], v[1]) for p, v in list(out.items())]' \
  '    for p, row in t.items():
        if not expired and row[2] == me and ("install.sh" in row[4] or "ft-da-codex.sh" in row[4]): out.setdefault(p, (want or seat, row[4]))
    kids, stack = {}, [(p, v[0], v[1]) for p, v in list(out.items())]'
chk "변이①글자 판정 복귀 → ⓐ빨강: 미등록 install.sh 글자 부모 [원본 변이]" "$(scen_letter "$BIN") $(scen_letter "$TMP/bin-letter")" "dead alive"
mut seat ft-seat-reap.sh '        bgf("handover", HAND, *[str(r["pid"]) for r in roots])' '        pass'
chk "변이②좌석 칸 갱신 끔 → ⓓ빨강: B→C 재넘김 줄 수 [원본 변이]" "$(scen_seat "$BIN") $(scen_seat "$TMP/bin-seat")" "1 0"
mut overwrite ft-bg-finite.sh '        L.rows = [r for r in L.rows if not (r[1] == pid and r[3] == lst)] + [row]' '        L.rows = [row]'
chk "변이③장부 덮어쓰기 → ⓔ빨강: 줄 수 [원본 변이]" "$(scen_over "$BIN") $(scen_over "$TMP/bin-overwrite")" "2 1"
mut front ft-seat-reap.sh 'if HAND and not dry:' 'if False and HAND and not dry:'
chk "변이④넘김 앞단 끔 → ⓕ빨강: press 점유 중 넘김 줄 수 [원본 변이]" "$(scen_front "$BIN") $(scen_front "$TMP/bin-front")" "1 0"
mut digest ft-seat-reap.sh '"handover" if p in handed else ' ''
chk "변이⑤digest 넘김 건너뜀 끔 → ⓗ빨강: 미룬 등록 DA 생존 [원본 변이]" "$(scen_digest "$BIN") $(scen_digest "$TMP/bin-digest")" "alive dead"
scen_edge() { fresh; local m; m="$(sp m9)"; bash "$1/ft-bg-finite.sh" register "$A" "--1" "$m" x >/dev/null 2>&1; echo "rc$?"; kill "$m" 2>/dev/null; }
mut clamp ft-bg-finite.sh ' or int(secs) > CAP_SEC:' ':'
chk "변이⑥상한 자름 끔 → ⓘ빨강: 999999 가 4200 이하인가 [원본 변이]" "$(scen_clamp "$BIN") $(scen_clamp "$TMP/bin-clamp")" "cap big"
mut edge ft-bg-finite.sh 'not re.fullmatch(r"[0-9]{1,6}", secs)' 'not secs.lstrip("-").isdigit()'
chk "변이⑥b 옛 lstrip 판정 복귀 → ⓘ빨강: «--1» 입력 rc [원본 변이]" "$(scen_edge "$BIN") $(scen_edge "$TMP/bin-edge")" "rc0 rc1"
mut lstart ft-leak-reap.sh '        if a != b: dead.append(pid); continue' '        pass'
chk "변이⑦lstart 비교 끔 → ⓙ빨강: 재사용 pid 줄 보고 수 [원본 변이]" "$(scen_lstart "$BIN") $(scen_lstart "$TMP/bin-lstart")" "0 1"
mut expire ft-seat-reap.sh '        if (r["until"] <= now) != expired: continue' '        if expired: continue   # 변이: 상한 지난 줄도 «상한 전» 으로 센다(넘김 집합에 들어감)'
chk "변이⑧만료도 넘김 → ⓚ빨강: 만료 줄 작업 생존(env 가 남의 좌석이라 reap 은 만료 경로뿐) [원본 변이]" "$(scen_expire "$BIN") $(scen_expire "$TMP/bin-expire")" "dead alive"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
