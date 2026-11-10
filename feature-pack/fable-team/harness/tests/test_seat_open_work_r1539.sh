#!/usr/bin/env bash
# test_seat_open_work_r1539.sh — r1539: «받을 일 0» 인 좌석은 후계를 열지 않는다(후계 0 · 팀장 1줄 · ft-successor-open rc6 · close-check [인계] 면제).
#   판정 도구 ft-seat-open-work.py 단독 사례 ⓐ~ⓖ + r1541 «진행/ 폴더만 없음» 사례 ⓐ'~ⓔ' + 게이트 문구·크론 줄 ⓗⓘ + rc6 실측(가짜 tmux·tmuxc·pgrep) + close-check ⓙ + 변이 M1~M5 · RM1·RM2.
# 격리만: 임시 루트·임시 우편함·가짜 센서(fake_resource_env) — 실 tmux 열기 0 · 실 우편함 0 · 실 명부 쓰기 0 · kill 0 · 고정 sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
TOOL="$REPO/bin/ft-seat-open-work.py"; KITTOOL="$REPO/kit/fable-team/bin/ft-seat-open-work.py"
SO="$REPO/kit/fable-team/bin/ft-successor-open.sh"; SO_BIN="$REPO/bin/ft-successor-open.sh"
SKILL="$(cd "$REPO/../skill" && pwd)"; GOV="$SKILL/references/main-team-governance.md"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ── 1) 문법 ──────────────────────────────────────────────────────────────
for f in "$TOOL" "$KITTOOL"; do python3 -m py_compile "$f" && ok "python3 -m py_compile $f" || bad "compile $f"; done
for f in "$SO" "$SO_BIN" "$REPO/bin/ft-role-spawn.sh" "$REPO/kit/fable-team/bin/ft-role-spawn.sh"; do bash -n "$f" && ok "bash -n $(basename "$f")" || bad "bash -n $f"; done
for f in "$SKILL/templates/hooks/context-distill-gate.sh" "$REPO/kit/fable-team/templates/hooks/context-distill-gate.sh"; do bash -n "$f" && ok "bash -n context-distill-gate.sh" || bad "bash -n $f"; done
[ "$(wc -l < "$TOOL")" -le 120 ] && ok "판정 도구 $(wc -l < "$TOOL")줄 ≤ 120" || bad "판정 도구 $(wc -l < "$TOOL")줄 > 120"

# ── 2) 판정 도구 단독 사례 (임시 루트 1개를 매번 새로 만든다) ─────────────
SEAT='byz-harness-nano-x#0'; MASTER='byz-harness-master-pi#171'
new_root() {   # new_root [카드폴더없음]  → R 에 design/*/indices/진행 · 우편함 · 명부를 세운다
  R="$T/r.$RANDOM$RANDOM"; mkdir -p "$R/.fable-team/comm/receipts" "$R/.fable-team/state/card-assign"
  [ "${1:-}" = nocard ] || mkdir -p "$R/design/harness/indices/진행"
  printf '{ "%s": {"role": "nano"}, "%s": {"role": "master"}, "_master": "%s" }\n' "$SEAT" "$MASTER" "$MASTER" > "$R/.fable-team/seats-harness.json"
  printf '{}\n' > "$R/.fable-team/state/card-assign/c1.json"
  : > "$R/.fable-team/comm/mailbox.jsonl"
}
mail_row() { printf '{"seq": %s, "ts": "2026-11-10T00:00:00", "to": "%s", "from": "byz-harness-master-pi#171", "body": "%s"}\n' "$1" "$2" "$3" >> "$R/.fable-team/comm/mailbox.jsonl"; }
run_tool() { OUT="$(python3 "$TOOL" "$@" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"; }

# ⓐ 받을 일 0 — «일 아님» 꼴 3건만 남는다 → rc0 · 이유=쪽지0(일 아님 3)·배정0·진행0 · LEADER
new_root
mail_row 1 "$SEAT" '[알림] 곧 점검'; mail_row 2 "$SEAT" '[처리 1줄] 확인함'; mail_row 3 "$SEAT" '머리 없음 · 다음 일 없음'
run_tool "$SEAT" --root "$R"
{ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 0 이유=쪽지0(일 아님 3)·배정0·진행0$' \
  && printf '%s' "$OUT" | grep -qx "LEADER $MASTER"; } && ok "ⓐ 받을 일 0 → rc0 · 이유 · LEADER" || bad "ⓐ rc=$RC out=$OUT err=$ERR"

# ⓑ 미처리 쪽지 중 발주 1 → rc1(기존 승계)
new_root; mail_row 4 "$SEAT" '[발주] 새 카드 #1'
run_tool "$SEAT" --root "$R"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=쪽지 일 1$'; } && ok "ⓑ 발주 1 → rc1" || bad "ⓑ rc=$RC out=$OUT"

# ⓒ «일 아님» 꼴 = 목록에 든 머리·«다음 일 없음»·READ 인용만 — 목록 밖 꼴은 일로 센다
new_root
for b in '[다음 없음] 좌석 닫기' '[정리] 심박' 'READ [m->s] #9 — 본문' '[처리함] ok'; do mail_row 10 "$SEAT" "$b"; done
run_tool "$SEAT" --root "$R"; A_RC="$RC"
mail_row 11 "$SEAT" '그냥 잡담입니다'; run_tool "$SEAT" --root "$R"; B_RC="$RC"
{ [ "$A_RC" = 0 ] && [ "$B_RC" = 1 ]; } && ok "ⓒ 일 아님 4꼴 → 0 · 목록 밖 1건 → 있음" || bad "ⓒ a=$A_RC b=$B_RC out=$OUT"

# ⓓ 진행 카드 «- 배정: 좌석 <같은 계보 #3>» 1장 → rc1 (ⓖ 계보 단위도 같이 잰다)
new_root; printf -- '- 배정: 좌석 byz-harness-nano-x#3\n' > "$R/design/harness/indices/진행/c7.md"
run_tool "$SEAT" --root "$R"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=배정 1 (c7.md)$'; } && ok "ⓓⓖ 계보 다른 번호 배정 → rc1" || bad "ⓓ rc=$RC out=$OUT"

# ⓓ-2 card-assign «seat» 1장 → rc1
new_root; printf '{ "seat": "byz-harness-nano-x#9", "state": "working" }\n' > "$R/.fable-team/state/card-assign/c9.json"
run_tool "$SEAT" --root "$R"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '카드 배정 1 (c9.json)'; } && ok "ⓓ card-assign seat 계보 일치 → rc1" || bad "ⓓ2 rc=$RC out=$OUT"

# ⓔ 팀장 좌석 + 팀 진행 카드 1장 → rc1 (다른 팀 카드는 안 센다)
new_root; printf '# 카드\n' > "$R/design/harness/indices/진행/c8.md"
run_tool "$MASTER" --root "$R"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '팀 진행 1'; } && ok "ⓔ 팀장 좌석 팀 진행 1 → rc1" || bad "ⓔ rc=$RC out=$OUT"
run_tool "$SEAT" --root "$R"   # 일반 좌석은 같은 카드를 안 센다
{ [ "$RC" = 0 ]; } && ok "ⓔ 일반 좌석은 팀 카드를 안 센다 → rc0" || bad "ⓔ-2 rc=$RC out=$OUT"

# ⓕ 판정 불가 3종 = 카드 폴더 없음 · card-assign json 깨짐 · 우편함 json 깨짐 → rc3 + stderr 1줄
new_root nocard; run_tool "$SEAT" --root "$R"
{ [ "$RC" = 3 ] && printf '%s' "$ERR" | grep -q '^받을 일 판정 불가 카드 폴더 없음' && printf '%s' "$OUT" | grep -q '^OPEN-WORK 불가'; } && ok "ⓕ-1 카드 폴더 없음 → rc3" || bad "ⓕ1 rc=$RC err=$ERR"
new_root; printf 'not json\n' > "$R/.fable-team/state/card-assign/bad.json"; run_tool "$SEAT" --root "$R"
{ [ "$RC" = 3 ] && printf '%s' "$ERR" | grep -q '받을 일 판정 불가 카드·배정'; } && ok "ⓕ-2 card-assign 깨짐 → rc3" || bad "ⓕ2 rc=$RC err=$ERR"
new_root; printf 'not json\n' >> "$R/.fable-team/comm/mailbox.jsonl"; run_tool "$SEAT" --root "$R"
{ [ "$RC" = 3 ] && printf '%s' "$ERR" | grep -q '받을 일 판정 불가 쪽지'; } && ok "ⓕ-3 우편함 깨짐 → rc3" || bad "ⓕ3 rc=$RC err=$ERR"
run_tool "$SEAT" --bogus 1 >/dev/null 2>&1
{ [ "$RC" = 2 ]; } && ok "ⓕ-4 모르는 인자 → usage rc2" || bad "ⓕ4 rc=$RC"

# ── 2b) DA HOLD 반례 R1·R2 (RED→GREEN) ────────────────────────────────────
# R1 실제 영수 파일 이름 = receipts/<좌석#번호>.jsonl(번호 있음) — 계보 키 하나만 보면 미표시 발주를 놓친다
new_root
printf '{"seq": 41, "from": "byz-harness-master-pi#171", "ts": "2026-11-10T00:00:00", "body": "[발주] 카드 r1539", "body_full": ""}\n' \
  > "$R/.fable-team/comm/receipts/$SEAT.jsonl"
run_tool "$SEAT" --root "$R"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=쪽지 일 1$'; } && ok "R1 receipts/<좌석#번호>.jsonl 미표시 발주 → rc1" || bad "R1 rc=$RC out=$OUT"
printf '{"seq": 41, "mark": "처리함", "ts": "2026-11-10T00:01:00"}\n' >> "$R/.fable-team/comm/receipts/$SEAT.jsonl"
run_tool "$SEAT" --root "$R"
{ [ "$RC" = 0 ]; } && ok "R1 «처리함» 표시된 영수는 안 센다 → rc0" || bad "R1-2 rc=$RC out=$OUT"

# R2 진행 카드가 design/teams/<팀>/indices/진행 에도 있다(harness 밖 팀) — design/* 만 보면 배정을 놓친다
new_root; mkdir -p "$R/design/teams/ops/indices/진행"
printf -- '- 배정: 좌석 byz-harness-nano-x#3\n' > "$R/design/teams/ops/indices/진행/ops-card.md"
run_tool "$SEAT" --root "$R"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=배정 1 (ops-card.md)$'; } && ok "R2 design/teams/<팀>/indices/진행 배정 → rc1" || bad "R2 rc=$RC out=$OUT"

# ── 2c) r1541 «진행/ 폴더만 없음» 은 진행 카드 0 (판정 불가 아님) ──
# git 은 빈 폴더를 안 남긴다 — 진행 카드 0 인 팀은 늘 진행/ 가 없다. indices/ 자체가 없을 때만 rc3.
ARCH='byz-planner-arch-claude#44'; PM='byz-planner-master-x#1'
pnew() {   # pnew <teams|design|none> [진행] — planner 팀 indices/ 꼴 · none = 팀 indices/ 자체 없음
  P="$T/p.$RANDOM$RANDOM"; KIND="${1:-teams}"; SUB=planner; [ "$KIND" = teams ] && SUB=teams/planner
  mkdir -p "$P/.fable-team/comm/receipts" "$P/.fable-team/state/card-assign" "$P/design/harness/indices/대기"
  printf '{ "_master": "%s", "%s": {"role": "master"}, "%s": {"role": "arch"} }\n' "$PM" "$PM" "$ARCH" > "$P/.fable-team/seats-planner.json"
  : > "$P/.fable-team/comm/mailbox.jsonl"
  [ "$KIND" = none ] || mkdir -p "$P/design/$SUB/indices/대기" "$P/design/$SUB/indices/완성"
  [ "${2:-}" = 진행 ] && mkdir -p "$P/design/$SUB/indices/진행"
  return 0
}
pmail() { printf '{"seq": %s, "ts": "2026-11-10T00:00:00", "to": "%s", "from": "%s", "body": "%s"}\n' "$1" "$ARCH" "$PM" "$2" >> "$P/.fable-team/comm/mailbox.jsonl"; }

# ⓐ 팀장 좌석 · 팀 indices/ 있음(대기·완성만) · 진행/ 없음 · 쪽지 일 0 · 배정 0 → rc0 · LEADER
pnew teams; run_tool "$ARCH" --root "$P"
{ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 0 이유=쪽지0(일 아님 0)·배정0·진행0$' \
  && printf '%s' "$OUT" | grep -qx "LEADER $PM"; } && ok "ⓐ' 팀 진행/ 없음 = 진행 0 · 판정 계속 rc0 · LEADER" || bad "ⓐ' rc=$RC out=$OUT err=$ERR"

# ⓑ 같은 팀 · 진행/ 없음 · 쪽지 일 1 → rc1
pnew teams; pmail 51 '[발주] planner 카드'; run_tool "$ARCH" --root "$P"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=쪽지 일 1$'; } && ok "ⓑ' 진행/ 없음 + 쪽지 일 1 → rc1(기존 승계)" || bad "ⓑ' rc=$RC out=$OUT"

# ⓒ 팀 indices/ 자체가 없다 → 지금처럼 rc3(판정 불가)
pnew none; run_tool "$ARCH" --root "$P"
{ [ "$RC" = 3 ] && printf '%s' "$ERR" | grep -q '^받을 일 판정 불가 팀 카드 폴더 없음' && printf '%s' "$OUT" | grep -q '^OPEN-WORK 불가'; } && ok "ⓒ' 팀 indices/ 자체 없음 → rc3 그대로" || bad "ⓒ' rc=$RC out=$OUT err=$ERR"

# ⓓ 리포 전체에 진행/ 0 · indices/ 는 있다 → 배정 0 으로 판정 계속(:59~62)
pnew teams; run_tool "$SEAT" --root "$P"
{ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 0 이유=쪽지0(일 아님 0)·배정0·진행0$'; } && ok "ⓓ' 리포 전체 진행/ 0 · indices/ 있음 → rc0 판정 계속" || bad "ⓓ' rc=$RC out=$OUT err=$ERR"

# ⓔ design/<팀>/indices/ 꼴도 ⓐ 와 같다(대기 카드는 안 센다)
pnew design; printf '# 대기 카드\n' > "$P/design/planner/indices/대기/wait.md"; run_tool "$ARCH" --root "$P"
{ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 0 이유=쪽지0(일 아님 0)·배정0·진행0$'; } && ok "ⓔ' design/<팀>/ 꼴 · 대기 카드 0 → rc0" || bad "ⓔ' rc=$RC out=$OUT err=$ERR"
pnew teams 진행; printf '# 카드\n' > "$P/design/teams/planner/indices/진행/run.md"; run_tool "$ARCH" --root "$P"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=팀 진행 1$'; } && ok "ⓔ' 진행/ 가 있고 카드 1장이면 그대로 rc1" || bad "ⓔ-2 rc=$RC out=$OUT"

# ── 3) 게이트 문구 ⓗ · 크론 줄 ⓘ ─────────────────────────────────────────
SENT='받을 일 0 이면 후계 0 — 좌석 닫기 대기 + 팀장에 «[다음 없음]» 1줄'
n=0; for f in "$SKILL/templates/hooks/context-distill-gate.sh" "$REPO/kit/fable-team/templates/hooks/context-distill-gate.sh"; do grep -qF "$SENT" "$f" && n=$((n+1)) || true; done
[ "$n" -ge 2 ] && ok "ⓗ 게이트 문구 사본 ${n}개(팩 2사본 · 세 번째는 설치 몫)" || bad "ⓗ 게이트 문구 사본 ${n}개"
grep -qF '받을 일 0 = 후계 대신 «[다음 없음]» 1줄(r1539)' "$GOV" && ok "ⓗ governance S17 블록 문구" || bad "ⓗ S17 블록 문구 없음"
blk="$(sed -n '/S17-BOOT-BEGIN/,/S17-BOOT-END/p' "$GOV")"
{ ! printf '%s' "$blk" | grep -q '15분' && ! printf '%s' "$blk" | grep -q 'CronCreate'; } && ok "ⓘ S17 블록에 15분·CronCreate 0" || bad "ⓘ S17 블록 잔존"
rows="$(sed -n '/^| R5 |/p;/^| R6 |/p' "$GOV")"
{ ! printf '%s' "$rows" | grep -q '15분' && ! printf '%s' "$rows" | grep -q 'CronCreate'; } && ok "ⓘ R5·R6 행에 15분·CronCreate 0" || bad "ⓘ R5·R6 잔존"
{ ! grep -q '15분\|CronCreate' "$REPO/bin/ft-role-spawn.sh" && ! grep -q '15분\|CronCreate' "$REPO/kit/fable-team/bin/ft-role-spawn.sh"; } && ok "ⓘ ft-role-spawn 사본 2종에 15분·CronCreate 0" || bad "ⓘ role-spawn 잔존"

# ── 3b) 승계 블록 길이 관문 (r1551) — 길이만 본다 · 뜻 유지(ⓑ)는 arch 수용 때 사람 대조 ──
# ft-successor-open.sh:185-191 과 «같은 방식»: 표식 사이를 자르고 양끝 개행만 strip 한 뒤 python len ≤ 300.
# 블록이 300자를 넘으면 desk 밖 모든 좌석의 승계가 rc1 로 막힌다(r1539 → 376자 사고 · mbox 739자 절단 안).
blk() {   # blk <표식태그> <파일> → 길이 출력 · ≤300 rc0 · >300 rc1 · 표식 이상 rc2
  python3 - "$1" "$2" <<'PY'
import sys
tag, path = sys.argv[1:3]
t = open(path, encoding="utf-8").read()
beg, end = f"<!-- {tag}-BEGIN -->", f"<!-- {tag}-END -->"
if t.count(beg) != 1 or t.count(end) != 1:
    print("표식 없음/여러 개"); sys.exit(2)
b = t.split(beg, 1)[1].split(end, 1)[0].strip("\n")
print(len(b)); sys.exit(1 if len(b) > 300 else 0)
PY
}
runblk() { BOUT="$(blk "$1" "$2")"; BRC=$?; }
runblk S17-BOOT "$GOV"
{ [ "$BRC" = 0 ] && [ "$BOUT" -le 300 ]; } && ok "ⓛ S17-BOOT 블록 ${BOUT}자 ≤ 300 — 승계 관문 통과" || bad "ⓛ S17-BOOT ${BOUT}자 rc=$BRC"
runblk S11-DESK "$GOV"
{ [ "$BRC" = 0 ] && [ "$BOUT" -le 300 ]; } && ok "ⓛ S11-DESK 블록 ${BOUT}자 ≤ 300 — 같은 관문" || bad "ⓛ2 S11-DESK ${BOUT}자 rc=$BRC"
# 변이 M1·M2 = 사본 2장(S17 블록만 바꿈 · 실 파일 무변경)
read -r -d '' OLD <<'EOF' || true
목적 0 = 진행 카드를 완성하고 닫는다 → 1 = 카드 서빙 → 2 = 배분·질문·결정(부딪히면 0→1→2).
크론 0 — 주기 크론을 만들지 않는다(오빠 11-08 · #274576). 깨우는 것은 쪽지와 발주뿐 · [정리] 첫 줄 = `카드 대기 N · 진행 N · 유휴 좌석 N · 다음 수: <카드> → <좌석>` · 둘째 줄 골좌표.
배정표 <데이터 루트>/.fable-team/state/team-main/<팀>/ASSIGN.md 매 루프 다시 쓴다 · 후계는 이 절을 읽는다 · STATE.md = 틱 렌더(읽기만) · 보고 칸 cron=0 · launchd=<상태> · 받을 일 0 이면 후계 대신 닫기 대기 + 팀장에 «[다음 없음]» 1줄(r1539).
EOF
printf '%s\n' "$OLD" > "$T/m1.body"
python3 - "$GOV" "$T" "$T/m1.body" <<'PY'
import sys
src, T, bodyf = sys.argv[1:4]
t = open(src, encoding="utf-8").read()
beg, end = "<!-- S17-BOOT-BEGIN -->", "<!-- S17-BOOT-END -->"
head, tail = t.split(beg, 1)[0], t.split(end, 1)[1]
cur = t.split(beg, 1)[1].split(end, 1)[0].strip("\n")
def put(name, body):
    open(f"{T}/gov.{name}.md", "w", encoding="utf-8").write(f"{head}{beg}\n{body}\n{end}{tail}")
put("m1", open(bodyf, encoding="utf-8").read().rstrip("\n"))
put("m2", cur + "가" * 30)
PY
runblk S17-BOOT "$T/gov.m1.md"
{ [ "$BRC" = 1 ] && [ "$BOUT" = 376 ]; } && ok "M1 셋째 줄을 r1539 원문으로 되돌림 → ${BOUT}자 검출(ⓛ 빨강)" || bad "M1 미검출 ${BOUT}자 rc=$BRC"
runblk S17-BOOT "$T/gov.m2.md"
{ [ "$BRC" = 1 ] && [ "$BOUT" = 328 ]; } && ok "M2 블록에 30자 덧붙임 → ${BOUT}자 검출(ⓛ 빨강)" || bad "M2 미검출 ${BOUT}자 rc=$BRC"

# ── 4) ft-successor-open rc6 실측 (받을 일 0 → 열기 0 · 팀장 1통 · rc6) ────
FAKE="$T/fakebin"; W="$T/wt"; LOG="$T/calls.log"; SENTF="$T/sent.txt"; BODY="$T/body.txt"
mkdir -p "$FAKE" "$W"; git -C "$W" init -q
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문\n' > "$BODY"
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux 'case "$1" in has-session) exit 1;; list-panes) echo 4242;; display-message) echo "$WT";; esac; exit 0'
mkstub tmuxc 'echo "tmuxc $*" >> "$LOG"; exit 0'
mkstub pgrep 'echo 5555; exit 0'
mkstub send 'echo "send $*" >> "$LOG"; echo "QUEUED seq=777"; exit 0'
mkstub reach 'exit 0'
mkstub mbox 'echo "mbox $1 $2" >> "$LOG"; [ "$1" = send ] && printf "%s" "$4" > "$SENTF"; echo "QUEUED seq=901 doorbell=sent"; exit 0'
: > "$FAKE/mbox_doorbell.sh"
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok; RES="$FT_RES_ROOT"
mkdir -p "$RES/design" "$RES/.fable-team/state"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/harness/` | byz-harness-master-pi | 현역 |\n' > "$RES/design/TEAMS.md"
printf '{ "byz-harness-nano-x#0": {"role": "nano"}, "byz-harness-master-pi#171": {"role": "master"}, "_master": "byz-harness-master-pi#171" }\n' > "$RES/.fable-team/seats-harness.json"
printf '2026-11-10T00:00:00\toff\tinstall\tinit\n' > "$RES/.fable-team/state/all-stop.log"
printf '| 팀 | 오케 | arch 상시 |\n|---|---|---|\n| harness | byz-harness-master-pi | — |\n' > "$T/teamset.md"
printf '<!-- S17-BOOT-BEGIN -->\n목적 0 = 진행 카드를 완성하고 닫는다.\n<!-- S17-BOOT-END -->\n' > "$T/gov.md"
wt_setup() {   # wt_setup [발주 1건]  → 워크트리 안에 판정 입력을 세운다(받을 일 0 기본)
  rm -rf "$W/design" "$W/.fable-team"; mkdir -p "$W/design/harness/indices/진행" "$W/.fable-team/comm/receipts" "$W/.fable-team/state/card-assign"
  printf '{ "byz-harness-nano-x#0": {"role": "nano"}, "byz-harness-master-pi#171": {"role": "master"}, "_master": "byz-harness-master-pi#171" }\n' > "$W/.fable-team/seats-harness.json"
  : > "$W/.fable-team/comm/mailbox.jsonl"
  [ "${1:-}" = work ] && printf '{"seq": 1, "to": "byz-harness-nano-x#0", "from": "m", "body": "[발주] 카드"}\n' >> "$W/.fable-team/comm/mailbox.jsonl"
}
run_so() {   # run_so [work]  → SO 를 한 번 돌린다(출력 $T/so.out · rc $SO_RC)
  wt_setup "${1:-}"; rm -f "$LOG" "$SENTF"; : > "$LOG"
  env HOME="$T/home" PATH="$FAKE:$PATH" WT="$W" LOG="$LOG" SENTF="$SENTF" FT_ROOT="$RES" FT_RES_ROOT="$RES" \
      SENSORS="$T/sensors/fake-sensors" FT_TEAMSET_MD="$T/teamset.md" FT_GOV_MD="$T/gov.md" FT_SO_POLL=0 FT_SO_WAIT_MAX=2 \
      FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" \
      bash "$SO" 'byz-harness-nano-x#0' "$W" --name 'byz-harness-nano-x#1' --agent claude --model 'claude-sonnet-5-5' --ctx 1m --body-file "$BODY" > "$T/so.out" 2>&1
  SO_RC=$?
}
run_so
{ [ "$SO_RC" = 6 ] && grep -q '^OPEN-WORK-0 byz-harness-nano-x#0 — 후계 0(받을 일 0)' "$T/so.out" \
  && [ ! -s "$LOG" ] || ! grep -q '^tmuxc' "$LOG"; } && ok "ⓐ' 받을 일 0 → ft-successor-open rc6 · 열기 0" || bad "ⓐ' rc=$SO_RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$T/so.out")"
{ [ -f "$SENTF" ] && grep -q '^\[다음 없음\] byz-harness-nano-x#0 · 이유=쪽지0' "$SENTF" && grep -q '닫기=R400 --verdict 대기' "$SENTF" \
  && grep -q "^mbox send byz-harness-master-pi#171" "$LOG"; } && ok "ⓐ' 팀장에 «[다음 없음]» 1통" || bad "ⓐ' 팀장 통지 — sent=$(cat "$SENTF" 2>/dev/null) log=$(tr '\n' ' ' < "$LOG")"
LS="$W/.fable-team/state/successor/byz-harness-nano-x#0.json"
[ ! -f "$LS" ] && ok "ⓐ' 도달 파일 0(retire 0)" || bad "ⓐ' 도달 파일 생김 $LS"
run_so work
{ [ "$SO_RC" != 6 ] && grep -q '^tmuxc open' "$LOG"; } && ok "ⓑ' 받을 일 1 → 기존 승계 그대로(rc=$SO_RC)" || bad "ⓑ' rc=$SO_RC log=$(tr '\n' ' ' < "$LOG")"

# ── 5) ⓙ close-check [인계] 면제 ─────────────────────────────────────────
CE="$T/ce"; C="$CE/.fable-team/comm"; mkdir -p "$C" "$CE/.fable-team/state" "$CE/design/harness/indices/진행" "$CE/seats"
git -C "$CE" init -q; cp "$REPO/comm"/mbox*.py "$REPO/comm"/mbox*.sh "$C/"
printf '{ "byz-harness-nano-x#0": {"role": "stop-ready", "_replaced_by": "byz-harness-nano-x#1"}, "byz-harness-nano-x#1": {"role": "nano"} }\n' > "$CE/seats/seats-harness.json"
ce() { OUT="$(cd "$CE" && env -u FT_PLANNER_HEAD_MODE PATH="$T/fakebin:$PATH" FT_SEATS_JSON="$CE/seats/seats-harness.json" FT_MBOX_DIR="$C" \
        FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_SEAT_OPEN_WORK="${1:-$TOOL}" HOME="$T/home" bash "$C/mbox.sh" "${@:2}" 2>&1)"; RC=$?; }
: > "$C/mailbox.jsonl"; ce "$TOOL" close-check 'byz-harness-nano-x#0'
{ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '받을 일 0 · \[인계\] 면제'; } && ok "ⓙ 받을 일 0 → [인계] 면제 rc0" || bad "ⓙ-1 rc=$RC out=$OUT"
printf '{"seq": 5, "to": "byz-harness-nano-x#0", "from": "m", "body": "[발주] 카드"}\n' > "$C/mailbox.jsonl"
ce "$TOOL" close-check 'byz-harness-nano-x#0'
{ [ "$RC" = 3 ] && printf '%s' "$OUT" | grep -q '\[인계\] 없음'; } && ok "ⓙ 받을 일 있음 → [인계] 없음 REJECT rc3" || bad "ⓙ-2 rc=$RC out=$OUT"

mkdir -p "$CE/design/teams/ops/indices/진행"; : > "$C/mailbox.jsonl"
printf -- '- 배정: 좌석 byz-harness-nano-x#3\n' > "$CE/design/teams/ops/indices/진행/ops-card.md"
ce "$TOOL" close-check 'byz-harness-nano-x#0'
{ [ "$RC" = 3 ] && printf '%s' "$OUT" | grep -q '\[인계\] 없음'; } && ok "ⓙ R2 팀 카드 배정 1 → [인계] 없음 REJECT rc3(면제 0)" || bad "ⓙ-3 rc=$RC out=$OUT"

# ── 6) 변이 M1~M5 (사본을 고쳐 그 사례가 빨강이 되는지) ──────────────────
mut() {   # mut <원본> <치환 전> <치환 후>  → $MUT 경로에 고친 사본
  MUT="$T/mut.$(basename "$1")"; python3 - "$1" "$MUT" "$2" "$3" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert s.count(a) >= 1, "변이 대상 없음: " + a
open(dst, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
}
mut "$TOOL" '    if work:' '    if True:'; MO="$MUT"; new_root; run_tool "$SEAT" --root "$R" --mbox-dir 2>/dev/null
OUT="$(python3 "$MO" "$SEAT" --root "$R" 2>/dev/null)"; RC=$?
{ [ "$RC" = 1 ]; } && ok "M1 «늘 있음» 변이 검출(ⓐ 가 빨강)" || bad "M1 변이 미검출 rc=$RC"
mut "$TOOL" '        return 3, "카드 폴더 없음 design/*/indices · design/teams/*/indices", ""' '        return 0, "쪽지0(일 아님 0)·배정0·진행0", "-"'; MO="$MUT"
new_root nocard; OUT="$(python3 "$MO" "$SEAT" --root "$R" 2>/dev/null)"; RC=$?
{ [ "$RC" = 0 ]; } && ok "M2 «판정 불가를 0 으로» 변이 검출(ⓕ1 이 빨강)" || bad "M2 변이 미검출 rc=$RC"
mut "$TOOL" '    first = (b.lstrip().splitlines() or [""])[0]' '    return True'; MO="$MUT"
new_root; mail_row 21 "$SEAT" '그냥 잡담'; OUT="$(python3 "$MO" "$SEAT" --root "$R" 2>/dev/null)"; RC=$?
{ [ "$RC" = 0 ]; } && ok "M3 «목록 밖도 일 아님» 변이 검출(ⓑ·ⓒ 가 빨강)" || bad "M3 변이 미검출 rc=$RC"
mut "$TOOL" 'if rk(m.group(1)) == key]' 'if m.group(1) == seat]'; MO="$MUT"
new_root; printf -- '- 배정: 좌석 byz-harness-nano-x#3\n' > "$R/design/harness/indices/진행/c7.md"
OUT="$(python3 "$MO" "$SEAT" --root "$R" 2>/dev/null)"; RC=$?
{ [ "$RC" = 0 ]; } && ok "M4 «계보 대신 정확한 이름» 변이 검출(ⓖ 가 빨강)" || bad "M4 변이 미검출 rc=$RC"
mut "$C/mbox_handover.py" 'if _open_work(seat) is False:' 'if True:'; MH="$MUT"; cp "$MH" "$C/mbox_handover_mut.py"
printf '{"seq": 6, "to": "byz-harness-nano-x#0", "from": "m", "body": "[발주] 카드"}\n' > "$C/mailbox.jsonl"
kept=0; cp "$C/mbox_handover.py" "$C/.keep"; cp "$C/mbox_handover_mut.py" "$C/mbox_handover.py"
ce "$TOOL" close-check 'byz-harness-nano-x#0'; [ "$RC" = 0 ] && kept=1
cp "$C/.keep" "$C/mbox_handover.py"; rm -f "$C/.keep" "$C/mbox_handover_mut.py"
{ [ "$kept" = 1 ]; } && ok "M5 «면제를 늘 적용» 변이 검출(ⓙ2 가 빨강)" || bad "M5 변이 미검출 rc=$RC out=$OUT"
# r1541 변이 2종(카드 M1·M2) — 옛 동작·더 너그러운 동작이 사례를 빨강으로 만드는지
mut "$TOOL" 'if not tidx:' 'if not tdir:'; MO="$MUT"   # 진행/ 없음 = rc3(옛 동작)
pnew teams; OUT="$(python3 "$MO" "$ARCH" --root "$P" 2>/dev/null)"; RC=$?
{ [ "$RC" = 3 ]; } && ok "RM1 «진행/ 없음 = rc3» 옛 동작 변이 검출(ⓐ' 가 빨강)" || bad "RM1 변이 미검출 rc=$RC"
mut "$TOOL" 'if not tidx:' 'if False:'; MO="$MUT"   # indices/ 없음도 0 으로
pnew none; OUT="$(python3 "$MO" "$ARCH" --root "$P" 2>/dev/null)"; RC=$?
{ [ "$RC" = 0 ]; } && ok "RM2 «indices/ 없음도 0» 변이 검출(ⓒ' 가 빨강)" || bad "RM2 변이 미검출 rc=$RC"

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
