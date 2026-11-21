# _reserve_r2355_fixture.sh — r2355 시험 두 파일 공용(source 전용 · r2320 꼴): 임시 origin+clone · 가짜 gh(+지연) · 게이트·equiv·press 스텁(+지연·rc) · fetch 지연 대역 · 크리티컬 가짜 우편함
#   fx_init <임시폴더> = origin(bare)+clone · $T/state · 스텁 1벌 · fx_fix = BIN 사본 · fx_base = 기준판(origin/main) 사본 · mkpr/land/ln/tailv/…
#   R2355_FAST=1 = 같은 관계 · 짧은 초(변이 시험용 · 시험 1개 70초 상한 · 하드 룰 22) · 실 원격·실 gh·실 mbox 0
export FT_AUTONOMY_LEVEL=each FT_MERGE_LAND_CODE_AUTOMERGE=0 FT_CRITICAL_OFF=1   # 착지 실행은 크리티컬 0(시험 소음 0 · 크리티컬은 ⑨~⑪d 가 직접 부른다)
unset FT_SEAT FT_MBOX FT_MBOX_DIR FT_SEATS_JSON FM_NOTIFY_REPO FT_REPO_ROOT FT_LAND_DEADLINE FT_LAND_TOTAL_S FT_PUSH_FIXED_S GIT_DIR GIT_WORK_TREE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R2355_BIN:-$(cd "$HERE/../bin" && pwd -P)}"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; el=0; PRSHA=""; T0=$SECONDS; APSH=""
F=7; DL=20; SL=10   # 기본 = 카드 반례 숫자(푸시 1단위 PV = F+7 = 14 · 앞 남은 20초 → 상한 6초 · 가짜 10초)
[ -z "${R2355_FAST:-}" ] || { F=1; DL=10; SL=4; }   # 변이 시험 = 같은 규칙 · PV 8 · 상한 2초 · 가짜 5초
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:400}"; fail=$((fail+1)); fi; }
fx_init() {   # fx_init <임시 폴더>
  T="$1"; mkrepo "$T"
  D="$T/data"; W="$T/w"; GB="$T/gb"; STUB_LOG="$T/gh.log"; STUB_JSON="$T/pr.json"
  TSV="$T/state/push-timing.tsv"; PFILE="$T/state/land-phase.tsv"; TBIN="$(command -v timeout || command -v gtimeout)"; REAL_GIT="$(command -v git)"
  mkdir -p "$T/state" "$D/.fable-team/bin" "$T/live" "$GB"; printf 'x\n' > "$T/live/ft-x.sh"; printf '%s\n' "$T/live" > "$D/.fable-team/LIVE_BIN"
  export FT_ROOT="$D" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" FT_INSTALL_CHECK="$T/install-stub" FT_ROOT_SHIM="$T/shim-stub" \
         FT_HEAVY_DIR="$T/heavy" FT_PUSH_TIMING_FILE="$TSV" STUB_LOG STUB_JSON REAL_GIT TBIN
  printf '#!/bin/bash\necho "$*" >> "$STUB_LOG"\ncase "$1 $2" in "pr view") [ -z "${GH_SLEEP:-}" ] || sleep "$GH_SLEEP"; cat "$STUB_JSON"; exit 0;; esac\nexit 0\n' > "$T/gh-stub"
  printf '#!/bin/bash\necho "OK n=1 (r2355 stub)"\n' > "$T/install-stub"
  printf '#!/bin/bash\necho "SHIM r2355 · MOVED 1"\n' > "$T/shim-stub"
  cat > "$GB/git" <<'EOF'
#!/bin/bash
for a in "$@"; do case "$a" in fetch) [ -z "${FETCH_SLEEP:-}" ] || sleep "$FETCH_SLEEP"; break;; esac; done
exec "$REAL_GIT" "$@"
EOF
  chmod +x "$T/gh-stub" "$T/install-stub" "$T/shim-stub" "$GB/git"
  # 크리티컬 가짜 우편함(⑨~⑪d) — MBOX_SLEEP_TO/MBOX_SLEEP_S = 그 받는 이만 느리게 · MBOX_FAIL_TO = 그 받는 이만 실패
  CN="$T/cn"; mkdir -p "$CN/.fable-team/comm"; CNLOG="$T/cn.log"; CNCALLS="$T/cn.calls"
  cat > "$T/mbox.sh" <<'EOF'
#!/usr/bin/env bash
echo x >> "$CNCALLS"
[ "$2" != "${MBOX_SLEEP_TO:-}" ] || sleep "${MBOX_SLEEP_S:-0}"
[ "$2" != "${MBOX_FAIL_TO:-}" ] || exit 4
printf '%s\t%s\t%s\n' "$2" "$3" "$4" >> "$CNLOG"; echo "QUEUED seq=$(( $(grep -c . "$CNLOG") + 500 )) to=$2"
EOF
  chmod +x "$T/mbox.sh"; export CNCALLS CNLOG
}
fx_fix() { FIX="$T/fix"; mkbin "$FIX"; }
mkbin() {   # mkbin <폴더> — BIN 사본 + 스텁(게이트·equiv·press·head-lag) · 착지 알림 = 출력 0(꼬리 소음 0)
  local d="$1"; rm -rf "$d"; cp -R "$BIN" "$d"
  printf '#!/bin/bash\n[ -z "${GATE_SLEEP:-}" ] || sleep "$GATE_SLEEP"\n[ -z "${GATE_RC:-}" ] || exit "$GATE_RC"\nexit 0\n' > "$d/ft-merge-gate.sh"
  printf '#!/bin/bash\n[ -z "${EQUIV_SLEEP:-}" ] || sleep "$EQUIV_SLEEP"\n[ -z "${EQUIV_RC:-}" ] || { echo "equiv 스텁 거절"; exit "$EQUIV_RC"; }\necho "equiv mode=merge overlap=0"\n' > "$d/ft-approval-equiv.sh"
  printf '#!/bin/bash\n[ -z "${PRESS_SLEEP:-}" ] || sleep "$PRESS_SLEEP"\n[ -z "${PRESS_RC:-}" ] || exit "$PRESS_RC"\nexit 0\n' > "$d/ft-press-evidence.sh"
  printf '#!/bin/bash\nexit 0\n' > "$d/ft-head-lag.sh"
  printf 'fm_land_notify_land() { :; }\n' >> "$d/ft-merge-lib.sh"
  chmod +x "$d"/ft-merge-gate.sh "$d"/ft-approval-equiv.sh "$d"/ft-press-evidence.sh "$d"/ft-head-lag.sh
}
fx_base() {   # 기준판(origin/main) 사본 — 「기준판 Red」 대조용 · 못 만들면 BASE=""
  local rp rel; rp="$(git -C "$BIN" rev-parse --show-toplevel 2>/dev/null)" || return 0
  rel="$(cd "$BIN" && pwd -P)"; rel="${rel#"$rp"/}"; [ -n "$rp" ] || return 0
  mkbin "$T/base" || return 0
  git -C "$rp" show "origin/main:$rel/ft-merge-land.sh" > "$T/base/ft-merge-land.sh" 2>/dev/null || return 0
  git -C "$rp" show "origin/main:$rel/ft-critical-notify.sh" > "$T/base/ft-critical-notify.sh" 2>/dev/null || return 0
  BASE="$T/base"
}
mkpr() {   # mkpr <번호> [<객체수>] — 임시 origin 의 refs/pull/<번호>/head + gh pr view JSON · PRSHA = head
  local n="$1" k="${2:-1}" i; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$n" origin/main >/dev/null 2>&1
  printf 'pr%s\n' "$n" > "$W/pr$n.txt"; [ "$k" -lt 2 ] || for i in $(seq 2 "$k"); do printf '%s\n' "$i" > "$W/obj$i.txt"; done
  cm "$W" "pr $n work"; git -C "$W" push -q -f origin "pr$n:refs/pull/$n/head" >/dev/null 2>&1; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,os,sys
d = {"headRefOid":sys.argv[1],"headRefName":"pr"+sys.argv[2],"isCrossRepository":False,"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}
if os.environ.get("NO_HEAD"): d.pop("headRefName")
print(json.dumps(d))' "$PRSHA" "$n" > "$STUB_JSON"   # NO_HEAD=1 = 가지 이름 0(① 의 «PR head fetch 실패» 한 줄)
}
land() {   # land <bin> <번호> <바깥 상한초> [KEY=VAL…] · DL_OFF=<초> = 호출 직전 기준 마감 · APSH = 승인 sha(기본 PR head)
  local b="$1" n="$2" o="$3" s; shift 3
  mkpr "$n"; apv --approve-sha "${APSH:-$PRSHA}"; : > "$STUB_LOG"; rm -f "$PFILE"
  s=$SECONDS
  if [ -n "${DL_OFF:-}" ]; then
    out="$(env "FT_LAND_DEADLINE=$(( $(date +%s) + DL_OFF ))" "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" 2>&1)"
  else
    out="$(env "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" 2>&1)"
  fi
  rc=$?; el=$((SECONDS - s))
}
pushlog() { grep -c '^push$' "$STUB_LOG"; }   # gh 쓰기 호출(코멘트·닫기) — push 0 판정은 GB_LOG·코멘트로 본다
ph() { grep -m1 '^LAND-PHASE ' <<<"$out"; }   # LAND-PHASE 1줄
phv() { sed -n "s/.*[ ]$1=\([^ ]*\).*/\1/p" <<<"$(ph)"; }
tobo() { printf '%s %s\n' "$(pbv 4)" "$(pbv 5)"; }   # push-timing 의 PB·AB 칸
pbv() { [ -f "$TSV" ] || { echo ""; return 0; }; awk -F'\t' -v c="$1" 'END{print $c}' "$TSV"; }
refs() { git -C "$W" for-each-ref --format='%(refname) ' refs/ft-land | tr '\n' ' '; }

# ── 크리티컬 세계(⑨~⑪d) — 가짜 우편함 1벌 · 명부 _desk/_master 를 사례마다 바꾼다 ──
DESK='byz-planner-desk-pi#9'; MAST='byz-planner-master-pi#1'
cr_roster() {   # cr_roster [<desk>] [<master>] — 빈 값 = 그 칸 없음
  python3 -c 'import json,sys
d = {}
if sys.argv[1]: d["_desk"] = sys.argv[1]
if sys.argv[2]: d["_master"] = sys.argv[2]
json.dump(d, open(sys.argv[3], "w"))' "${1:-}" "${2:-}" "$CN/.fable-team/seats-planner.json"; }
cr_init() { rm -rf "$CN" "$T/cnstate"; mkdir -p "$CN/.fable-team/comm" "$T/cnstate"; : > "$CNLOG"; : > "$CNCALLS"; cr_roster "$DESK" "$MAST"; }
cnt() { local n; n="$(grep -c '\[크리티컬\]' "$CNLOG" 2>/dev/null)"; echo "${n:-0}"; }
cwho() { cut -f1 "$CNLOG" 2>/dev/null | tr '\n' ' '; }   # 받은 이 순서
cnote() { local r=$?; rc=$r; out="cnt=$(cnt) who=[$(cwho)] pend=$(grep -c . "$T/cnstate/critical-pending.jsonl" 2>/dev/null)"; return "$r"; }   # 크리티컬 사례의 FAIL 사유
cr() { local b="$1"; shift; FT_MBOX="$T/mbox.sh" FT_MBOX_DIR="$CN/.fable-team/comm" FT_CRITICAL_STATE_DIR="$T/cnstate" FT_CRITICAL_OFF=0 FT_CRITICAL_DEDUPE_S=0 bash "$b/ft-critical-notify.sh" "$@"; }

# ── 반례 사례 k* (①~⑫ · ④b · ④c · ⑪b · ⑪c · ⑪d) — 변이 시험도 같은 함수를 쓴다 ──
RU=$((F + 7))   # push 1단위 PV
k1() {   # ① fetch 가짜 SL초 · 앞 남은 DL초(PV+6) → fetch 상한 DL−PV 로 끊김 · «PR head fetch 실패» 원문 · push 0
  NO_HEAD=1 DL_OFF=$DL land "$1" 101 40 FT_PUSH_FIXED_S=$F FETCH_SLEEP=$SL "PATH=$GB:$PATH"   # 앞 남은 = DL(카드 20초) · PV 14 → fetch 상한 6초
  [ "$rc" = 1 ] && grep -q '^REJECT PR head fetch 실패' <<<"$out" && [ "$el" -lt "$SL" ] && ! grep -q '^LANDED' <<<"$out"; }
k2a() {   # ② 게이트 앞 남은 PV+2초 → 게이트 바깥 상한 2초 · 가짜 SL초 → 끊김 REJECT(«gate 가 상한 …»)
  DL_OFF=$((RU + 5)) land "$1" 102 40 FT_PUSH_FIXED_S=$F FETCH_SLEEP=3 GATE_SLEEP=$SL "PATH=$GB:$PATH"
  [ "$rc" = 1 ] && grep -q '^REJECT push 몫 예약: gate 가 상한' <<<"$out" && ! grep -q '^LANDED' <<<"$out"; }
k2b() {   # ②-b 앞 남은 < PV+1 → gh pr view 시작 0 · REJECT «push 몫 예약: gh pr view 앞 … < 1»(공용 rsv 판정 — 게이트 start 0 은 초 단위 지터로 결정적이지 않아 같은 함수를 view 에서 잰다)
  DL_OFF=$((F + 3)) land "$1" 103 40 FT_PUSH_FIXED_S=$F
  [ "$rc" = 1 ] && grep -q '^REJECT push 몫 예약: gh pr view 앞 남은' <<<"$out" && grep -q ' < 1 (착지 0 · 다음 틱)' <<<"$out"; }
k3() {   # ③ 닫기 대기 장부 2건 · 남은 − PV < 7 → 닫기 재시도 0 + WARN 1줄 · 본 PR 은 계속 · 착지 1
  printf '{"repo":"%s","pr":91,"sha":"%s","ts":1}\n{"repo":"%s","pr":92,"sha":"%s","ts":1}\n' "$(cd "$W" && pwd -P)" "$(printf '0%.0s' $(seq 40))" "$(cd "$W" && pwd -P)" "$(printf '0%.0s' $(seq 40))" > "$T/state/merge-close-pending.jsonl"
  DL_OFF=$((F + 10)) land "$1" 104 40 FT_PUSH_FIXED_S=$F
  [ "$rc" = 0 ] && grep -q '^LANDED' <<<"$out" && [ "$(grep -c '^WARN 닫기 재시도 건너뜀' <<<"$out")" = 1 ] && [ "$(pushlog)" = 0 ] && [ "$(grep -c . "$T/state/merge-close-pending.jsonl")" = 2 ]; }
k4() {   # ④ 앞 단계가 빠름(마감 67) → 상한 = 자기 상한 그대로 · 착지 1 · push-timing 1줄
  rm -f "$TSV"; land "$1" 105 40 FT_PUSH_FIXED_S=$F
  [ "$rc" = 0 ] && grep -q '^LANDED pr=105 ' <<<"$out" && [ "$(grep -c . "$TSV")" = 1 ]; }
k4b() {   # ④b 승인 sha ≠ head → equiv 앞 상한 DL−PV · 가짜 SL초 → 끊김 · 동일승인 대조 실패 원문 · push 0
  APSH="$(sha "$W" "$M0")" DL_OFF=$DL land "$1" 106 40 FT_PUSH_FIXED_S=$F EQUIV_SLEEP=$SL
  APSH=""
  [ "$rc" = 1 ] && grep -q '동일승인 대조(병합·rebase 두 경로)도 실패' <<<"$out" && [ "$el" -lt "$SL" ] && ! grep -q '^LANDED' <<<"$out"; }
k4c() {   # ④c press 앞 상한 DL−PV · 가짜 SL초 → TB rc 124 = «press 증거 검사 Ns 에 끊김»(«press 증거 검사 실패» 글 0) · rc 1 짝은 지금 글 · 음성 경로 0 PR = press 칸 숫자
  DL_OFF=$DL land "$1" 107 40 FT_PUSH_FIXED_S=$F PRESS_SLEEP=$SL
  local ok1=0 ok2=0 ok3=0
  { [ "$rc" = 1 ] && grep -q '^REJECT push 몫 예약: press 증거 검사 [0-9]*s 에 끊김 · 남은 [0-9]*s − push 1단위 ' <<<"$out" && ! grep -q 'press 증거 검사 실패' <<<"$out" && [ "$el" -lt "$SL" ]; } && ok1=1
  DL_OFF=$DL land "$1" 108 40 FT_PUSH_FIXED_S=$F PRESS_RC=1
  { [ "$rc" = 1 ] && grep -q '^REJECT press 증거 검사 실패' <<<"$out"; } && ok2=1
  land "$1" 109 40 FT_PUSH_FIXED_S=$F
  { [ "$rc" = 0 ] && [ "$(phv press)" != "-" ] && [ -n "$(phv press)" ]; } && ok3=1
  [ "$ok1$ok2$ok3" = 111 ]; }
k5() {   # ⑤ 착지 성공 → LAND-PHASE 1줄 · 칸 12(press·etc 포함) · total ≥ 단계 합 · tsv 1줄 · EXIT 사슬(개인 ref 정리) 그대로
  rm -f "$PFILE"; land "$1" 110 40 FT_PUSH_FIXED_S=$F
  local l n su=0 v; l="$(ph)"; n="$(printf '%s\n' "$l" | wc -w | tr -d ' ')"
  for v in close view fetch gate overlap equiv press lint push; do v="$(phv "$v")"; [ "$v" = "-" ] || su=$((su + v)); done
  [ "$rc" = 0 ] && grep -q '^LANDED pr=110 ' <<<"$out" && [ "$n" = 14 ] && grep -q ' press=[0-9-]* ' <<<"$l" && [ "$(phv total)" -ge "$su" ] && [ "$(phv etc)" -ge 0 ] && [ "$(grep -c . "$PFILE")" = 1 ] && [ -z "$(refs)" ]; }
k6() {   # ⑥ REJECT(②-b) → LAND-PHASE 1줄 · 안 간 단계 «-» · tsv 1줄
  rm -f "$PFILE"; DL_OFF=$((F + 3)) land "$1" 111 40 FT_PUSH_FIXED_S=$F
  [ "$rc" = 1 ] && grep -q '^LAND-PHASE pr=111 ' <<<"$out" && [ "$(phv gate)" = "-" ] && [ "$(phv push)" = "-" ] && [ "$(phv lint)" = "-" ] && [ "$(grep -c . "$PFILE")" = 1 ]; }
k7() {   # ⑦ --dry → LAND-PHASE 1줄 · push «-» · tsv 1줄 · 착지·알림 0
  rm -f "$PFILE"; mkpr 112; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"; local s=$SECONDS
  out="$(env FT_PUSH_FIXED_S=$F "$TBIN" 40 bash "$1/ft-merge-land.sh" 112 --approve-sha "$PRSHA" --repo "$W" --dry 2>&1)"; rc=$?; el=$((SECONDS - s))
  [ "$rc" = 0 ] && grep -q '^DRY ALLOW' <<<"$out" && [ "$(phv push)" = "-" ] && [ "$(grep -c . "$PFILE")" = 1 ] && ! grep -q '^LANDED' <<<"$out" && [ "$(pushlog)" = 0 ]; }
k8() {   # ⑧ land-phase.tsv 쓰기 실패(그 자리에 폴더) → WARN 1줄 · 착지 rc 불변
  rm -rf "$PFILE"; mkdir -p "$PFILE"; land "$1" 113 40 FT_PUSH_FIXED_S=$F; local r="$rc"
  rmdir "$PFILE" 2>/dev/null || rm -rf "$PFILE"
  [ "$r" = 0 ] && grep -q '^LANDED pr=113 ' <<<"$out" && [ "$(grep -c '^WARN land-phase 기록 실패' <<<"$out")" = 1 ]; }
k9() {   # ⑨ ft-merge-land 거절 · _desk ≠ _master → 받는 이 2통 · 본문 같음 · 사건 지문 1
  cr_init
  cr "$1" ft-merge-land "o/r PR #7" --event e9 --what "REJECT 충돌 (착지 0)" --next "고친다" --where "o/r#7" >/dev/null 2>&1
  [ "$(cnt)" = 2 ] && [ "$(cwho)" = "$DESK $MAST " ] && [ "$(cut -f3 "$CNLOG" | sort -u | wc -l | tr -d ' ')" = 1 ] && [ "$(python3 -c 'import json,sys;print(len({json.loads(l)["event"] for l in open(sys.argv[1]) if l.strip()}))' "$T/cnstate/critical-sent.jsonl")" = 1 ]; cnote; }
k10() {   # ⑩ _desk = _master → 1통 — pending «받는 이» 칸도 1개(같은 값은 거른다) · 발신 실패 주입으로 그 칸을 남긴다
  cr_init; cr_roster "$DESK" "$DESK"
  MBOX_FAIL_TO="$DESK" cr "$1" ft-merge-land "o/r PR #8" --event e10 --what w --next n >/dev/null 2>&1
  [ "$(cnt)" = 0 ] && [ "$(grep -c . "$T/cnstate/critical-pending.jsonl")" = 1 ] && python3 -c 'import json,sys;r=json.loads(open(sys.argv[1]).read().strip());sys.exit(0 if r.get("to")==[sys.argv[2]] else 1)' "$T/cnstate/critical-pending.jsonl" "$DESK"; cnote; }
k11() {   # ⑪ _master 없음 → desk 1통 + WARN 1줄
  cr_init; cr_roster "$DESK" ""
  local e; e="$(cr "$1" ft-merge-land "o/r PR #9" --event e11 --what w --next n 2>&1 >/dev/null)"
  [ "$(cnt)" = 1 ] && [ "$(grep -c '^WARN ft-critical-notify: seats-planner.json 에 _master 칸 없음' <<<"$e")" = 1 ]; cnote; }
k11b() {   # ⑪b desk 성공 · master 가짜 rc≠0 → pending 1줄 desk «보냄» → 다음 drain = master 1통 · desk 0 → pending 지움
  cr_init; local p="$T/cnstate/critical-pending.jsonl"
  MBOX_FAIL_TO="$MAST" cr "$1" ft-merge-land "o/r PR #10" --event e11b --what w --next n >/dev/null 2>&1
  local a=0 b=0 c=0
  [ "$(cnt)" = 1 ] && [ "$(cwho)" = "$DESK " ] && [ "$(grep -c . "$p")" = 1 ] && python3 -c 'import json,sys;r=json.loads(open(sys.argv[1]).read().strip());sys.exit(0 if r.get("sent")==[sys.argv[2]] else 1)' "$p" "$DESK" && a=1
  cr "$1" --drain >/dev/null 2>&1
  [ "$(cnt)" = 2 ] && [ "$(cwho)" = "$DESK $MAST " ] && [ ! -s "$p" ] && b=1
  [ "$a$b" = 11 ]; cnote; }
k11c() {   # ⑪c ft-nano-close → desk 1통만 · master 0
  cr_init
  cr "$1" ft-nano-close "byz-harness-nano-k#0" --event e11c --what w --next n >/dev/null 2>&1
  [ "$(cnt)" = 1 ] && [ "$(cwho)" = "$DESK " ]; cnote; }
k11d() {   # ⑪d BUDGET=3 · desk 가짜 1.5초(또는 2.2초) → master 몫이 남아 1통 / 몫 < 1 이면 master pending(«보냄» 칸 desk 만) · 규칙 = 받는 이마다 min(7, 남은 몫)
  cr_init; local p="$T/cnstate/critical-pending.jsonl" a=0 b=0 s
  s=$SECONDS
  FT_CRITICAL_BUDGET_S=3 MBOX_SLEEP_TO="$DESK" MBOX_SLEEP_S=1.5 cr "$1" ft-merge-land "o/r PR #11" --event e11d --what w --next n >/dev/null 2>&1
  [ "$(cnt)" = 2 ] && [ "$(cwho)" = "$DESK $MAST " ] && a=1
  cr_init; s=$SECONDS
  FT_CRITICAL_BUDGET_S=3 MBOX_SLEEP_TO="$DESK" MBOX_SLEEP_S=2.2 cr "$1" ft-merge-land "o/r PR #12" --event e11d2 --what w --next n >/dev/null 2>&1
  [ "$(cnt)" = 1 ] && [ "$(cwho)" = "$DESK " ] && [ "$(grep -c . "$p")" = 1 ] && python3 -c 'import json,sys;r=json.loads(open(sys.argv[1]).read().strip());sys.exit(0 if r.get("sent")==[sys.argv[2]] and r.get("to")==[sys.argv[2],sys.argv[3]] else 1)' "$p" "$DESK" "$MAST" && b=1
  [ "$a$b" = 11 ]; cnote; }
k12() {   # ⑫ k4 와 같은 입력 · 총 마감 67 · 객체 수 같음 → push-timing PB·AB·rc 가 기준판과 같음
  [ -n "${BASE:-}" ] || return 0
  rm -f "$TSV"; land "$1" 114 40 FT_PUSH_FIXED_S=$F "FT_PUSH_UNIT_OBJECTS=1"; local pn="$(tobo)" pr="$rc"
  rm -f "$TSV"; land "$BASE" 115 40 FT_PUSH_FIXED_S=$F "FT_PUSH_UNIT_OBJECTS=1"; local bn="$(tobo)" br="$rc"
  [ "$pn" = "$bn" ] && [ "$pr" = "$br" ] && [ -n "$pn" ]; }
