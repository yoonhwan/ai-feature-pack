#!/usr/bin/env bash
# test_land_notify_self_mute_r2302.sh — r2302: 카드 0장 착지에서 수신(팀 _master) = 발신(FT_SEAT)이면 착지 쪽지 0 · INFO «자기 앞» 1줄
#   계약: A1 자기 앞 0 · A2 다른 좌석 앞 그대로 · A3 카드 있는 착지 그대로 · A4 정확 글자 대조 · 장부·nano-record notify 그대로 · bin·kit cmp0
#   격리: 임시 bare origin + clone · 가짜 gh·가짜 mbox(send 줄 기록) · bin 사본(ft-nano-record = 호출 기록 대역) — 실 우편함·실 PR·실 명부 0
#   변이 M1~M3 = bin 사본의 ft-merge-lib.sh 만 바꿈(원본 0) · 변이마다 잡혀야 PASS
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/bin"; KIT="$SRC/../kit/fable-team/bin"; BIN="$SRC"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:600}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state"
export FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_MERGE_DENY_FILE="$T/deny.txt"
export FT_ROOT="$W" MBOX_LOG="$T/mbox.log" FT_MBOX="$T/mbox.sh" NREC_LOG="$T/nrec.log"
unset FT_SEAT FT_REPO_ROOT FT_SEATS_JSON FM_CARD_ONLY
printf '# 시험 목록(빈)\n' > "$T/deny.txt"; : > "$MBOX_LOG"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; exit 2;; esac
echo "$*" >> "$STUB_LOG"
EOF
cat > "$T/mbox.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MBOX_LOG"
echo "QUEUED fake"
EOF
chmod +x "$T/gh-stub" "$T/mbox.sh"
mkbin() {  # mkbin <폴더> [sed 식] — bin 사본 · ft-nano-record = 호출 기록 대역 · sed 식이 있으면 사본 lib 만 변이
  cp -R "$SRC" "$1"; printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$NREC_LOG"\n' > "$1/ft-nano-record.sh"
  [ -z "${2:-}" ] || { sed -i.bak -e "$2" "$1/ft-merge-lib.sh" && rm -f "$1/ft-merge-lib.sh.bak"; ! cmp -s "$1/ft-merge-lib.sh" "$SRC/ft-merge-lib.sh"; }
}
put() { mkdir -p "$(dirname "$W/$1")"; printf '%b\n' "$2" > "$W/$1"; }
mkpr() {  # mkpr <PR번호> <가지> <제목> <경로=내용>...
  local n="$1" b="$2" ttl="$3"; shift 3
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "$b" origin/main
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "pr $n"
  git -C "$W" push -q -f origin "$b:refs/pull/$n/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":sys.argv[3],"body":"","state":"OPEN","baseRefName":"main"},ensure_ascii=False))' \
    "$PRSHA" "$b" "$ttl" > "$STUB_JSON"
}
land() {  # land <bin 폴더> <PR> <FT_SEAT(빈 값 = 없음)>
  local ls0=$SECONDS
  apv --approve-sha "$PRSHA"; : > "$STUB_LOG"; : > "$MBOX_LOG"; : > "$NREC_LOG"
  if [ -n "$3" ]; then out="$(FT_SEAT="$3" bash "$1/ft-merge-land.sh" "$2" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
  else out="$(bash "$1/ft-merge-land.sh" "$2" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?; fi
  echo "land pr=$2 $((SECONDS - ls0))초"
}
sends() { grep -c '^send ' "$MBOX_LOG" || true; }
PM='byz-planner-master-pi#9'
t0=$SECONDS

# ── 사전: 픽스처(팀 표 · planner 카드 1장 · 명부) · bin·kit cmp0 ──
cmp -s "$SRC/ft-merge-lib.sh" "$KIT/ft-merge-lib.sh"; ck "⑥ 짝 사본 bin·kit cmp0(ft-merge-lib)" $?
put "design/TEAMS.md" '| 팀 | 폴더 | x | y |
|---|---|---|---|
| harness | `design/harness/` | h | 현역 |
| planner | `design/planner/` | p | 현역 |'
put "design/planner/indices/진행/r3200-pl-card.md" "# 인덱스: r3200-pl-card"
cm "$W" "base cards"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
printf '.fable-team/\n' >> "$W/.git/info/exclude"
mkdir -p "$W/.fable-team"
printf '{"_master":"%s"}\n' "$PM" > "$W/.fable-team/seats-planner.json"
printf '{"_master":"team-harness-master#9"}\n' > "$W/.fable-team/seats-harness.json"
LEDGER="$W/.fable-team/state/land-record-turn.jsonl"
mkbin "$T/b0"

# ── ① A1: 카드 0장 ∧ 수신 = 발신 → send 0 · INFO «자기 앞» 1줄(pr·sha 글자) · rc 0 ──
mkpr 11 code11 "chore: 코드만" "bin/q11.sh=echo q11"
land "$T/b0" 11 "$PM"
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=11 "* ]] && [ "$(sends)" = 0 ] \
  && [ "$(printf '%s\n' "$out" | grep -c "^INFO 착지 쪽지 생략 — 자기 앞(카드 0 · $PM) · \[착지\] pr=11 sha=[0-9a-f]")" = 1 ]
ck "①a 카드 0(토큰 0) · FT_SEAT = planner _master → send 0 · INFO 자기 앞 1줄 · rc 0" $?
# ── ④ A4: 같은 착지에서 장부 1줄(cards:[]) · nano-record notify 1회 ──
python3 - "$LEDGER" <<'EOF'
import json,sys
r=[json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()]
r=[d for d in r if d.get("pr")==11]
sys.exit(0 if len(r)==1 and r[0].get("cards")==[] else 1)
EOF
lrc=$?; [ "$lrc" = 0 ] && [ "$(grep -c '^notify --pr 11 ' "$NREC_LOG")" = 1 ]
ck "④ ①a 에서도 장부 1줄(cards:[]) · nano-record notify 1회" $?
mkpr 12 docs/r3100-only "docs: r3100 카드" "design/harness/indices/대기/r3100-new-card.md=# 인덱스: r3100-new-card"
land "$T/b0" 12 "$PM"
[ "$rc" = 0 ] && [ "$(sends)" = 0 ] \
  && [ "$(printf '%s\n' "$out" | grep -c "^INFO 착지 쪽지 생략 — 자기 앞(카드 0 · $PM) · \[착지\] pr=12 sha=[0-9a-f]* 카드 없음 · 카드 파일만")" = 1 ]
ck "①b 카드 파일만(FM_CARD_ONLY=1) · FT_SEAT = planner _master → send 0 · INFO 자기 앞 1줄 · rc 0" $?

# ── ② A2: 카드 0장 · 수신 ≠ 발신(같은 팀 다른 좌석) → send 1줄 그대로 ──
mkpr 13 code13 "chore: 코드만 둘" "bin/q13.sh=echo q13"
land "$T/b0" 13 'byz-harness-nano-r2302#0'
[ "$rc" = 0 ] && [ "$(sends)" = 1 ] && grep -qE '^send team-harness-master#9 byz-harness-nano-r2302#0 \[착지\] pr=13 ' "$MBOX_LOG"
ck "② 카드 0 · FT_SEAT ≠ harness _master → send 1줄(기준판과 같음)" $?

# ── ③ A3: 카드 1장(planner) · FT_SEAT = planner _master → send 1줄 그대로 ──
mkpr 14 doc14 "docs: r3200 고침" "design/x/t14.md=T14"
land "$T/b0" 14 "$PM"
[ "$rc" = 0 ] && [ "$(sends)" = 1 ] && grep -qE "^send $PM $PM \[착지\] pr=14 sha=[0-9a-f]+ 카드 r3200 " "$MBOX_LOG"
ck "③ 카드 1장 · 수신 = 발신 → send 1줄(기준판과 같음)" $?

# ── ③b: FT_SEAT 없음 · 카드 0 → «팀 못 정함» INFO 그대로 · send 0 ──
mkpr 15 code15 "chore: 코드만 셋" "bin/q15.sh=echo q15"
land "$T/b0" 15 ""
[ "$rc" = 0 ] && [ "$(sends)" = 0 ] && printf '%s\n' "$out" | grep -q '^INFO 착지 쪽지 생략 — 팀 못 정함$' \
  && ! printf '%s\n' "$out" | grep -q '자기 앞'
ck "③b FT_SEAT 없음 → INFO 팀 못 정함 그대로 · send 0" $?

# ── ③c: FT_SEAT = _master + «0»(접두만 같음) → 정확 대조라 send 1줄 ──
mkpr 16 code16 "chore: 코드만 넷" "bin/q16.sh=echo q16"
land "$T/b0" 16 "${PM}0"
[ "$rc" = 0 ] && [ "$(sends)" = 1 ] && grep -qF "send $PM ${PM}0 [착지] pr=16 " "$MBOX_LOG"
ck "③c FT_SEAT = _master+0 → send 1줄(정확 글자 대조)" $?

# ── 변이(사본 lib 만) · 원본 대조 = 위 ①a·③·② ──
mkbin "$T/m1" '/r2302-mut:self/d'; mrc=$?
mkpr 21 code21 "chore: 변이1" "bin/q21.sh=echo q21"; land "$T/m1" 21 "$PM"
[ "$mrc" = 0 ] && [ "$(sends)" = 1 ]
ck "M1 대조 줄 지움 → ① 잡힘(send 1줄 · 원본 0)" $?
mkbin "$T/m2" 's/\[ \$# -eq 0 \] && \[ "\$m" = "\$from" \]/[ "$m" = "$from" ]/'; mrc=$?
mkpr 22 doc22 "docs: r3200 변이2" "design/x/t22.md=T22"; land "$T/m2" 22 "$PM"
[ "$mrc" = 0 ] && [ "$(sends)" = 0 ]
ck "M2 «카드 0» 조건 지움 → ③ 잡힘(send 0 · 원본 1)" $?
mkbin "$T/m3" 's/\[ "\$m" = "\$from" \]/[ "$(printf %s "$m" | cut -d- -f2)" = "$(printf %s "$from" | cut -d- -f2)" ]/'; mrc=$?
mkpr 23 code23 "chore: 변이3" "bin/q23.sh=echo q23"; land "$T/m3" 23 'byz-harness-nano-r2302#0'
[ "$mrc" = 0 ] && [ "$(sends)" = 0 ]
ck "M3 정확 대조 → 팀 대조 → ② 잡힘(send 0 · 원본 1)" $?

{ [ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; }; ck "격리: 원격 = 임시 bare 1개" $?
echo "단계 초: 전체 $((SECONDS - t0))초"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
