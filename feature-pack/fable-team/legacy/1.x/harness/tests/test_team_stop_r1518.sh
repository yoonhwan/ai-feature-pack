#!/usr/bin/env bash
# test_team_stop_r1518.sh — ft-team-stop.sh (r1518 · DESIGN-r1498 §2 S0~S5 · §3 가드) 반례 11행(§6 1~7·9·10·11·13) + 가드 7 + 정적 검사.
#   격리: 임시 git 리포(bare origin = origin/main 대역) + 격리 tmux 소켓(tests/lib/tmux_isolate.sh · 진짜 tmux · 실 서버 0) + 가짜 명부 seats-t1.json
#         + 가짜 jsonl(seat-resume 기록) + 가짜 mbox·ft-hil·ft-pm-watchd · 실 좌석·실 명부·실 launchd·실 우편함 0 · sleep 0(FT_STOP_GAP=0)
#   A 깨끗한 팀(나노 2 · 역할 1 · 팀장 1 · 클론 1) → h 1장 · S2→S3→S4→S5 순 · 머리 closed=4 held=0 clones=1 · CLOSEOUT 커밋·push(§6-1·5·9)
#   B 가드 팀 → 좌석마다 «멈춤 <좌석> <가드> <값>» 1줄 · 깨끗한 나노만 h · S4 멈춤(§6-10·11·13 · Working 3값 · 미착지·미커밋·미읽음·열린 h)
#   C --verdict 없음 → 표준승인 밖 역할 = kill권한 멈춤 · 계보 더 큰 번호 생존 = h(--verdict 0) · 클론 표준승인 안/밖(§6-4·6)
#   D 명부 깨짐 = 전체 멈춤 · E S0 push 실패 = 전체 멈춤 h 0 · F --confirm 잔존 → 닫힘 + [종료] 1통 + 멱등(§6-7) · G 정적(삭제·크론·착지 0 · §6-2·3·11)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -u
export LC_ALL=C FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; S="$BIN/ft-team-stop.sh"
. "$HERE/lib/tmux_isolate.sh"; tmux_isolate_begin
fail=0; npass=0; out=""; rc=0; SECONDS=0; TT=()
ok()  { npass=$((npass+1)); }
bad() { echo "FAIL $1 :: rc=$rc out=${out:0:600}"; fail=$((fail+1)); }
has() { case "$out" in *"$1"*) ok;; *) bad "$2 — 없음: «$1»";; esac; }
hasnt() { case "$out" in *"$1"*) bad "$2 — 있으면 안 됨: «$1»";; *) ok;; esac; }
eq()  { [ "$1" = "$2" ] && ok || bad "$3 — 기대 «$2» 실제 «$1»"; }
lap() { TT+=("$1=${SECONDS}s"); }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'tmux_isolate_end; rm -rf "$T"' EXIT
[ -f "$S" ] || { echo "FAIL ft-team-stop.sh 없음: $S"; exit 1; }
bash -n "$S" && ok || bad "bash -n"
L="$(wc -l < "$S" | tr -d ' ')"; [ "$L" -le 200 ] && ok || bad "200줄 상한 — $L"

# ---------- 가짜 도구 ----------
FAKE="$T/fake"; REC="$T/rec"; mkdir -p "$FAKE" "$REC" "$T/la" "$T/sr" "$T/hil" "$T/peek"
cat > "$FAKE/mbox.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  peek) f="$FT_PEEK/$2"; [ -f "$f" ] && cat "$f" || echo "pending=0"; exit 0;;
  send) printf '%s\n' "$*" >> "$FT_REC/mbox.log"; echo "QUEUED seq=4243 to=$2"; exit 0;;
esac; exit 2
EOF
cat > "$FAKE/hil.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$2" >> "$FT_REC/hil.log"; echo "! bash $HIL_DIR/h$(grep -c . "$FT_REC/hil.log")"
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE/pmw.sh"
chmod +x "$FAKE"/*.sh
export FT_REC="$REC" FT_PEEK="$T/peek" FT_MBOX_SH="$FAKE/mbox.sh" FT_HIL="$FAKE/hil.sh" FT_PM_WATCHD="$FAKE/pmw.sh"
export FT_LAUNCHAGENTS="$T/la" ZC_RESUME_DIR="$T/sr" HIL_DIR="$T/hil" FT_STOP_GAP=0 FT_STOP_ME='byz-t1-nano-stop#0'
export FT_STOP_REPORT_TO='byz-planner-master-pi#245'
unset FT_TEAM_STOP_IN

# ---------- 픽스처 ----------
g() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -q -m "$2"; }
mkrepo() {  # <루트> — bare origin + clone(main ↔ origin/main) · 골·진행 카드 a.md(origin) · .serena 추적
  local r="$1"; git init -q --bare -b main "$r.origin.git"; git clone -q "$r.origin.git" "$r" 2>/dev/null
  git -C "$r" config user.name t; git -C "$r" config user.email t@t
  mkdir -p "$r/design/teams/t1/indices/진행" "$r/.serena" "$r/.fable-team"
  printf '# GOAL t1\n\n## 골 원문\n\n골 첫 줄\n골 둘째 줄\n골 셋째 줄\n' > "$r/design/teams/t1/GOAL-t1.md"
  echo a > "$r/design/teams/t1/indices/진행/a.md"; echo 'name: x' > "$r/.serena/project.yml"
  printf '.worktrees/\n.fable-team/\n' > "$r/.gitignore"; g "$r" base; git -C "$r" push -q -u origin main 2>/dev/null
  echo z > "$r/design/teams/t1/indices/진행/z-worktree-only.md"   # §6-9: 작업 트리에만 있는 카드는 CLOSEOUT 에 0
}
wt() { git -C "$1" worktree add -q -b "nano/$2" "$1/.worktrees/$2" origin/main 2>/dev/null; }
seats() {  # <루트> <json 본문(행들)>
  printf '{"_name":"T","_master":"byz-t1-master-claude#4","_cards":"design/teams/t1/indices","_cards_wt":"wtm",\n %s}\n' "$2" > "$1/.fable-team/seats-t1.json"; }
row() { printf '"%s":{"role":"%s","agent":"claude","model":"m"%s}' "$1" "$2" "${3:+,\"worktree\":\"$3\"}"; }
now_iso() { python3 -c 'import datetime,sys;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=int(sys.argv[1]))).isoformat())' "$1"; }
jl_idle() {  # <좌석> — claude 꼴: assistant 뒤 system/turn_duration
  local j="$T/jl/${1//[^A-Za-z0-9]/_}.jsonl"; mkdir -p "$T/jl"
  { echo '{"type":"user"}'; echo "{\"type\":\"assistant\",\"timestamp\":\"$(now_iso 20)\"}"; echo '{"type":"system","subtype":"turn_duration"}'; } > "$j"
  printf '{"jsonl":"%s"}\n' "$j" > "$T/sr/$1.json"; }
jl_work() {  # <좌석> — 130초 전 assistant · 그 뒤 턴 종료 없음(앞 턴의 종료만 있음)
  local j="$T/jl/${1//[^A-Za-z0-9]/_}.jsonl"; mkdir -p "$T/jl"
  { echo '{"type":"system","subtype":"turn_duration"}'; echo "{\"type\":\"assistant\",\"timestamp\":\"$(now_iso 130)\"}"; echo '{"type":"user"}'; } > "$j"
  printf '{"jsonl":"%s"}\n' "$j" > "$T/sr/$1.json"; }
idle() { tmux new-session -d -s "$1" sh -c 'read x'; }        # pane 자손 0
busy() { tmux new-session -d -s "$1" sh -c 'cat; :'; }        # pane 자손 1(cat)
run() { out="$(cd "$1" && FT_REPO_ROOT="$1" bash "$S" t1 "${@:2}" 2>&1)"; rc=$?; }
hplan() { tail -1 "$REC/hil.log" 2>/dev/null; }
lnum() { grep -n -- "$2" "$1" | head -1 | cut -d: -f1; }

# ---------- A 깨끗한 팀 (나노 2 · 역할 1 · 팀장 1 · 클론 1) ----------
R="$T/ra"; mkrepo "$R"; wt "$R" wtm; wt "$R" n1; wt "$R" n2
seats "$R" "$(row 'byz-t1-master-claude#4' master wtm),$(row 'byz-t1-nano-a#0' nano n1),$(row 'byz-t1-nano-b#0' nano n2),$(row 'byz-t1-arch-claude#7' arch)"
for s in 'byz-t1-master-claude#4' 'byz-t1-nano-a#0' 'byz-t1-arch-claude#7'; do idle "$s"; jl_idle "$s"; done
idle 'byz-t1-x#1'   # 명부에 없음 = 클론(나노 b 는 세션 없음 = Working 건너뜀)
: > "$REC/hil.log"; run "$R" --verdict 4138 --recv 12
eq "$rc" 0 "A rc"; eq "$(grep -c . "$REC/hil.log")" 1 "A h 1장(§6-5)"
has "h 1장 closed=4 held=0 clones=1" "A 요약"; hasnt "멈춤" "A 멈춤 0"
H="$(hplan)"; has "S1 세션 cron = 기계 근거 없음" "A §6-2 cron 1줄"
grep -q '^# ft-hil-expect: closed=4 held=0 clones=1$' "$H" && ok || bad "A h 머리 expect"
grep -q -- '--stop-if-owned' "$H" && ok || bad "A §6-3 ft-pm-watchd 줄 h 안"
bash -n "$H" && ok || bad "A h 문법"
a2="$(lnum "$H" '# S2')"; a3="$(lnum "$H" '# S3')"; a4="$(lnum "$H" '# S4')"; a5="$(lnum "$H" '# S5')"
[ -n "$a2" ] && [ "$a2" -lt "$a3" ] && [ "$a3" -lt "$a4" ] && [ "$a4" -lt "$a5" ] && ok || bad "A 순서 S2→S3→S4→S5 ($a2 $a3 $a4 $a5)"
eq "$(grep -c '# S3 나노' "$H")" 2 "A 나노 2"; grep -F "ft-seat-close.sh' 'byz-t1-arch-claude#7'" "$H" | grep -q -- '--verdict 4138' && ok || bad "A 역할 --verdict"
grep -q -- '--recv 12 --suspended' "$H" && ok || bad "A 나노 --recv·--suspended"
CO="design/teams/t1/CLOSEOUT-t1-$(date +%Y%m%d).md"
git -C "$R" fetch -q origin; git -C "$R" cat-file -e "origin/main:$CO" 2>/dev/null && ok || bad "A §6-1 CLOSEOUT origin 에 push"
c="$(git -C "$R" show "origin/main:$CO" 2>/dev/null)"
case "$c" in *"골 첫 줄"*"indices/진행/a.md"*"ft-team-boot.sh t1"*) ok;; *) bad "A CLOSEOUT 골·카드·다시 여는 법";; esac
case "$c" in *z-worktree-only*) bad "A §6-9 작업 트리 사본 카드가 CLOSEOUT 에";; *) ok;; esac
lap A

# ---------- F --confirm (A 의 plan) ----------
run "$R" --confirm "$H"; eq "$rc" 1 "F 잔존 rc"; has "S5 잔존 세션 byz-t1-nano-a#0" "F §6-7 잔존 세션"; has "S5 잔존 명부" "F 명부 잔존"
tmux_isolate_clean_sessions
python3 - "$R/.fable-team/seats-t1.json" <<'P'
import json,sys
d=json.load(open(sys.argv[1]))
for k,v in d.items():
    if isinstance(v,dict): v["role"]="stop-ready"
json.dump(d,open(sys.argv[1],"w"))
P
run "$R" --confirm "$H"; eq "$rc" 0 "F 확인 rc"; has "S5 확인 t1 닫힘" "F 닫힘"
grep -qF '[종료] t1' "$REC/mbox.log" && ok || bad "F [종료] 1통"
git -C "$R" fetch -q origin; eq "$(git -C "$R" show "origin/main:$CO" | grep -c 'S5 확인')" 1 "F 닫힘 1줄 push"
run "$R" --confirm "$H"; eq "$rc" 0 "F 재실행 rc"; eq "$(grep -c 'S5 확인' "$R/$CO")" 1 "F 멱등(줄 1)"
lap F

# ---------- B 가드 팀 ----------
R="$T/rb"; mkrepo "$R"; wt "$R" wtm; wt "$R" ok; wt "$R" unl; wt "$R" dirty
echo x > "$R/.worktrees/unl/u.txt"; g "$R/.worktrees/unl" unlanded
echo 'name: y' > "$R/.worktrees/dirty/.serena/project.yml"   # §6-10 spawn 이 tracked .serena 수정
seats "$R" "$(row 'byz-t1-master-claude#4' master wtm),$(row 'byz-t1-nano-ok#0' nano ok),$(row 'byz-t1-nano-work#0' nano),$(row 'byz-t1-nano-unk#0' nano),$(row 'byz-t1-nano-tail#0' nano),$(row 'byz-t1-nano-unl#0' nano unl),$(row 'byz-t1-nano-dirty#0' nano dirty),$(row 'byz-t1-nano-mail#0' nano),$(row 'byz-t1-nano-hil#0' nano)"
idle 'byz-t1-master-claude#4'; jl_idle 'byz-t1-master-claude#4'
busy 'byz-t1-nano-work#0'; jl_work 'byz-t1-nano-work#0'      # §6-13 130초 · 자손 1 · 턴 종료 없음
idle 'byz-t1-nano-unk#0'                                     # 기록 없음 = UNKNOWN
busy 'byz-t1-nano-tail#0'; jl_idle 'byz-t1-nano-tail#0'      # 턴 종료 뒤 자손 1 = UNKNOWN
printf 'pending=2 first\nseq=77 from=x\n' > "$T/peek/byz-t1-nano-mail#0"
printf '# plan\n# ft-hil-request seat=byz-t1-other#9 byz-t1-nano-hil#0\n' > "$T/hil/p900.sh"
printf '#!/usr/bin/env bash\n# ft-hil-entry plan=%s\n' "$T/hil/p900.sh" > "$T/hil/h900"
: > "$REC/hil.log"; run "$R" --verdict 4138 --recv 12
eq "$rc" 3 "B rc 3(판정 불가 섞임)"; eq "$(grep -c . "$REC/hil.log")" 1 "B h 1장"
has "멈춤 byz-t1-nano-work#0 Working 13" "B WORKING 130초(§6-13)"
has "멈춤 byz-t1-nano-unk#0 Working 판정 불가 jsonl 없음" "B UNKNOWN 기록 없음"
has "멈춤 byz-t1-nano-tail#0 Working 판정 불가 턴 종료 뒤 자손 1" "B UNKNOWN 자손"
has "멈춤 byz-t1-nano-unl#0 미착지 1 커밋 · 브랜치 nano/unl" "B 미착지(§6-11)"
has "멈춤 byz-t1-nano-dirty#0 미커밋 1 .serena/project.yml" "B 미커밋(§6-10)"
has "멈춤 byz-t1-nano-mail#0 미읽음 2 · 첫 seq 77" "B 미읽음"
has "멈춤 byz-t1-nano-hil#0 열린 h h900 실행 전" "B 열린 h"
has "멈춤 S4 하위 7 석 미닫힘" "B S4 멈춤"; hasnt "멈춤 byz-t1-nano-ok#0" "B 깨끗한 나노 통과"
H="$(hplan)"; eq "$(grep -c '# S3 나노' "$H")" 1 "B h 나노 1"; grep -q '# S4' "$H" && bad "B 팀장 h 밖" || ok
grep -qF "'byz-t1-nano-ok#0' --result" "$H" && ok || bad "B 깨끗한 나노 h 안"
grep -q '^# ft-hil-expect: closed=1 held=7 clones=0$' "$H" && ok || bad "B expect held=7"
eq "$(grep -c '^멈춤 byz-' <<< "$out")" 7 "B 좌석 멈춤 줄 = 좌석당 1"
sed -n '/^set -u/,$p' "$H" > "$T/b.h"; tmux_isolate_clean_sessions; lap B

# ---------- C --verdict 없음 · 표준승인 · 클론 ----------
R="$T/rc"; mkrepo "$R"; wt "$R" wtm
seats "$R" "$(row 'byz-t1-master-claude#4' master wtm),$(row 'byz-t1-arch-claude#7' arch),$(row 'byz-t1-da-codex#2' da),$(row 'byz-t1-nano-old#0' stop-ready)"
idle 'byz-t1-master-claude#4'; jl_idle 'byz-t1-master-claude#4'
idle 'byz-t1-da-codex#2'; jl_idle 'byz-t1-da-codex#2'; idle 'byz-t1-da-codex#3'   # 계보 더 큰 번호 생존 = 표준승인(hil.md:9)
idle 'byz-t1-nano-old#0'                                                          # §6-6 은퇴 행 세션 = 클론
: > "$REC/hil.log"; run "$R"
eq "$rc" 0 "C rc"; has "멈춤 byz-t1-arch-claude#7 kill권한 표준승인 밖 · --verdict 필요" "C kill권한"
has "멈춤 byz-t1-master-claude#4 kill권한" "C 팀장 kill권한"; hasnt "멈춤 byz-t1-da-codex#2" "C 표준승인 안 = 통과"
has "S2 클론 byz-t1-da-codex#3 (표준승인 밖" "C 클론 밖"; has "S2 클론 byz-t1-nano-old#0" "C 은퇴 세션 클론"
H="$(hplan)"; grep -qF "ft-seat-close.sh' 'byz-t1-da-codex#2' --reason" "$H" && ok || bad "C 표준승인 역할 h 안"
grep -qE -- '--verdict [0-9]' "$H" && bad "C --verdict 0" || ok
tmux_isolate_clean_sessions; idle 'byz-t1-x#1'; idle 'byz-t1-x#2'; seats "$R" "$(row 'byz-t1-master-claude#4' master wtm)"
run "$R"; has "S2 클론 byz-t1-x#1 (표준승인 안" "C §6-4 클론 표준승인 안"; has "S2 클론 byz-t1-x#2 (표준승인 밖" "C 클론 밖 2"
tmux_isolate_clean_sessions; lap C

# ---------- D 명부 깨짐 · E S0 push 실패 ----------
R="$T/rd"; mkrepo "$R"; wt "$R" wtm; echo '{"_master": ' > "$R/.fable-team/seats-t1.json"
: > "$REC/hil.log"; run "$R"; eq "$rc" 1 "D rc"; has "명부 판정 불가" "D 명부 판정 불가"; eq "$(grep -c . "$REC/hil.log")" 0 "D h 0"
R="$T/re"; mkrepo "$R"; wt "$R" wtm; seats "$R" "$(row 'byz-t1-master-claude#4' master wtm)"
git -C "$R" remote set-url origin "$T/없음.git"
run "$R" --verdict 4138; eq "$rc" 1 "E rc"; has "멈춤 S0 정본 미착지" "E §6-1 S0 실패 = 전체 멈춤"; eq "$(grep -c . "$REC/hil.log")" 0 "E h 0"
FT_TEAM_STOP_IN=1 run "$R"; has "멈춤 재진입" "E 재진입 가드"
lap DE

# ---------- G 정적 (스크립트 + 만든 h) ----------
for f in "$S" "$H"; do
  n="$(grep -cE 'branch -[dD]|worktree (remove|prune)|rm -rf|CronCreate|launchctl (bootstrap|load)|ft-merge-land|gh pr merge|crontab' "$f")"
  eq "$n" 0 "G 삭제·크론·착지 명령 0 ${f##*/}"; done
lap G

echo "${TT[*]} total=${SECONDS}s"
echo "PASS $npass · FAIL $fail"
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
