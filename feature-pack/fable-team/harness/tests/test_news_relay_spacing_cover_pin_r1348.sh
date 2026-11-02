#!/usr/bin/env bash
# test_news_relay_spacing_cover_pin_r1348.sh — r1348(Issue #6171): 뉴스 발행 정지 원인 셋.
#   (A) desk relay 하루 12통을 «자정 뒤 2시간» 에 다 써 19시간 0통 → relay 사이 간격 ≥ 120분(N1·N2·N3·N4) + relay 가 «QUEUED seq=» 를 낸 뒤 시간 초과면 보낸 것으로 셈(N10)
#   (B) planner 회차 안에서 초안 표지(회차 시작 origin/main)와 검증 렌더(그때의 origin/main)가 달라 exit 3 → 회차 시작 sha 고정(N5·N6·N9)
#   (C) 초안이 원장 사본 안 untracked → 사본 checkout 막힘 · 로그에만 남던 것 → planner [긴급] 1통 · 자동 정리 0(N7·N8)
# 구성: ⓐ 현재 판 N1~N10 ⓑ 기준판(base 3d81b7bd 의 kit bin)에서 N1·N5·N7·N8·N10 이 «빨간지» ⓒ 변이 4(간격 검사·회차 고정·[긴급] 통지·PINNED_FROM 비교 제거)
# 픽스처 = mktemp 격리: 임시 FT_ROOT · 가짜 mbox(호출을 파일에 적음) · 가상 시각(FT_DESK_NOW) · 로컬 bare origin + 워크트리 1개(같은 refs 공유) · 가짜 «다른 좌석 fetch» 훅.
# 네트워크 0 · 실 슬랙 0 · 실 mbox 0 · 자기 재호출 0 · 고정 sleep 0(느린 mbox 대역 1건만 시간 상한 시험) · 실행 1회 timeout 70 · ulimit -u (하드 룰 22).
set -uo pipefail
[ -z "${R1348_TEST_RUNNING:-}" ] || { echo "재진입 금지(R1348_TEST_RUNNING)"; exit 2; }
export R1348_TEST_RUNNING=1
_n="$(ps -u "$(id -un)" -o pid= 2>/dev/null | wc -l | tr -d ' ')"; ulimit -u "$((_n + 400))" 2>/dev/null || true
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
KIT="$HARNESS/kit/fable-team/bin"
TOP="$(git -C "$HARNESS" rev-parse --show-toplevel)"; KITREL="${KIT#"$TOP"/}"
BASESHA=3d81b7bd   # 이 카드 이전 팩 main(고정 sha · «이동하는 origin/main» 아님)
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }
yes() { [ "$2" = yes ] && ok "$1" || bad "$1 (조건 불충족 :: ${3:-})"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음 «$2» ← ${1:0:300}";; esac; }
not() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨 «$2» ← ${1:0:300}";; *) ok "$3";; esac; }
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }
STAGE0=$SECONDS; STAGES=""; stage() { STAGES="$STAGES $1=$((SECONDS - STAGE0))s"; STAGE0=$SECONDS; }

# ── 도구 사본: 기준판 · 변이 4 ────────────────────────────────────────────────
BASE="$T/base"; mkdir -p "$BASE"
git -C "$TOP" archive "$BASESHA" "$KITREL" | tar -x -C "$BASE" || bad "기준판 사본 못 뜸($BASESHA)"
BASEBIN="$BASE/$KITREL"
mut() {  # <이름> <파일> <원문> <바꿈> → 변이 bin 폴더(.py 만 사본 · 문자열 1곳 치환 — BSD sed 의 \n 차이를 피해 python)
  mkdir -p "$T/mut-$1"; cp "$KIT"/*.py "$T/mut-$1/"
  python3 - "$T/mut-$1/$2" "$3" "$4" <<'PY' || bad "변이 $1 사본이 안 만들어졌다(원문이 1번 나오지 않음)"
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    raise SystemExit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
}
mut m1 ft_news_desk.py 'if why := gap_hold(state, now):' 'if why := "":'
mut m2 ft_news_ledger_round.py '    base = os.environ.get(FROM_ENV)' '    return ""
    base = os.environ.get(FROM_ENV)'
mut m3 ft_news_ledger_round.py '    state = root / ".fable-team" / "state"
    stamp, key' '    return False
    state = root / ".fable-team" / "state"
    stamp, key'
mut m4 ft_goal_table.py '(os.environ.get(PINNED_FROM) or os.environ.get("FT_TEAMS_REF") or "origin/main")' '(os.environ.get("FT_TEAMS_REF") or "origin/main")'
stage 사본

# ── (A) desk 간격 구동기 ──────────────────────────────────────────────────────
cat > "$T/mbox-stub.sh" <<'SH'
#!/bin/sh
echo "$FT_DESK_NOW $1" >> "$DESK_LOG"
case "${STUB_MODE:-}" in
  slow) echo "QUEUED seq=7 to=$2"; exec sleep 6;;
  fail) echo "boom" >&2; exit 1;;
esac
echo "QUEUED seq=1 to=$2"
SH
echo '{"_desk": "byz-planner-desk-claude#9", "byz-planner-desk-claude#9": {"role": "desk"}}' > "$T/seats-desk.json"
cat > "$T/desk.py" <<'PY'
import os, sys
from datetime import datetime, timedelta
sys.path.insert(0, sys.argv[1])
import ft_news_desk as D
scen, state = sys.argv[2], sys.argv[3]
log = os.environ["DESK_LOG"]
CUR = {"text": ""}
D.build = lambda root, now: CUR["text"]          # 전문 조립은 이 시험 밖 — 틱마다 칸 값만 바꾼다
START = datetime(2026, 11, 2, 0, 0)
def text(cells):
    return "# 뉴스 전문 — 00:00\n\n## 칸\n\n" + "\n".join(f"- {k}: {v}" for k, v in sorted(cells.items())) + "\n"
def tick(minute, cells):
    now = START + timedelta(minutes=minute)
    os.environ["FT_DESK_NOW"] = f"{now:%Y-%m-%d %H:%M}"
    CUR["text"] = text(cells)
    return D.tick()
def relays():
    try:
        rows = [ln.split() for ln in open(log, encoding="utf-8").read().splitlines()]
    except OSError:
        return []
    return [datetime.strptime(f"{a} {b}", "%Y-%m-%d %H:%M") for a, b, _ in rows]
def read(name):
    try:
        return open(os.path.join(state, name), encoding="utf-8").read().strip()
    except OSError:
        return "-"
if scen == "n1":
    for i in range(30):
        tick(i * 10, {"c": i})
    r = relays()
    gaps = [(b - a).total_seconds() / 60 for a, b in zip(r, r[1:])]
    print(f"relays={len(r)}"); print(f"mingap={min(gaps) if gaps else 999:.0f}")
elif scen == "n2":
    tick(0, {"a": 1, "b": 1}); tick(30, {"a": 2, "b": 1}); tick(60, {"a": 2, "b": 2})
    mid = len(relays()); tick(120, {"a": 2, "b": 2})
    print(f"relays_mid={mid}"); print(f"relays={len(relays())}")
    brief = open(os.path.join(state, "20261102-0200.brief.txt"), encoding="utf-8").read() if os.path.exists(os.path.join(state, "20261102-0200.brief.txt")) else ""
    print(f"has_a={'- a: 2' in brief}"); print(f"has_b={'- b: 2' in brief}")
elif scen == "n3":
    tick(0, {"x": 1}); before = read("relay-last.txt"); n0 = len(relays())
    tick(130, {"x": 1})
    print(f"last_same={before == read('relay-last.txt')}"); print(f"relays={len(relays())}"); print(f"n0={n0}")
elif scen == "n4":
    tick(0, {"x": 1}); last, cnt = read("relay-last.txt"), read("relay-count-20261102.txt")
    os.environ["STUB_MODE"] = "fail"
    rc = tick(130, {"x": 2})
    print(f"rc={rc}"); print(f"last_same={last == read('relay-last.txt')}"); print(f"count_same={cnt == read('relay-count-20261102.txt')}")
elif scen == "n10":
    os.environ["STUB_MODE"] = "slow"
    rc1 = tick(0, {"x": 1}); rc2 = tick(10, {"x": 1})
    print(f"rc1={rc1}"); print(f"rc2={rc2}"); print(f"relays={len(relays())}")
    print(f"count={read('relay-count-20261102.txt')}"); print(f"last_exists={read('relay-last.txt') != '-'}")
PY
desk() {  # <bin> <시나리오> [VAR=val …] → OUT(키=값 줄들) · RC
  local bin="$1" scen="$2"; shift 2
  local d="$T/desk-$scen-$RANDOM"; mkdir -p "$d/root/.fable-team"; : > "$d/mbox.log"
  OUT="$(cd / && env FT_ROOT="$d/root" FT_DESK_SEATS="$T/seats-desk.json" FT_MBOX="$T/mbox-stub.sh" DESK_LOG="$d/mbox.log" \
    FT_DESK_STATE="$d/state" "$@" timeout 70 python3 "$T/desk.py" "$bin" "$scen" "$d/state" 2>"$d/err")"; RC=$?
  ERR="$(cat "$d/err")"
}

echo "== (A) desk relay 간격"
desk "$KIT" n1
eq "N1 30틱(300분) 안 relay 3통 이하" "$([ "$(val "$OUT" relays)" -le 3 ] && echo yes || echo no)" "yes"
eq "N1 relay 사이 최소 간격 ≥ 120분" "$([ "$(val "$OUT" mingap)" -ge 120 ] && echo yes || echo no)" "yes"
desk "$KIT" n2
eq "N2 30·60분 틱 relay 0(누적 1통)" "$(val "$OUT" relays_mid)" "1"
eq "N2 120분 틱 relay 1통 더(누적 2통)" "$(val "$OUT" relays)" "2"
eq "N2 둘째 relay 요약에 a 칸 실림" "$(val "$OUT" has_a)" "True"
eq "N2 둘째 relay 요약에 b 칸 실림" "$(val "$OUT" has_b)" "True"
desk "$KIT" n3
eq "N3 바뀐 칸 0 → relay 0(누적 그대로)" "$(val "$OUT" relays)" "$(val "$OUT" n0)"
eq "N3 relay-last.txt 불변" "$(val "$OUT" last_same)" "True"
desk "$KIT" n4
eq "N4 relay rc≠0 → tick rc≠0" "$([ "$(val "$OUT" rc)" != 0 ] && echo yes || echo no)" "yes"
has "$ERR" "판정 불가 relay" "N4 «판정 불가 relay» 1줄"
eq "N4 relay-last.txt 불변" "$(val "$OUT" last_same)" "True"
eq "N4 하루 수 불변" "$(val "$OUT" count_same)" "True"
desk "$KIT" n10 FT_DESK_TOOL_TIMEOUT=1 FT_DESK_RELAY_GAP_MIN=0
eq "N10 QUEUED 뒤 시간 초과 → 첫 틱 rc0(보낸 것으로 셈)" "$(val "$OUT" rc1)" "0"
eq "N10 둘째 틱(같은 내용) rc0" "$(val "$OUT" rc2)" "0"
eq "N10 같은 내용 재발송 0(relay 1통)" "$(val "$OUT" relays)" "1"
eq "N10 하루 수 1 · relay-last 갱신" "$(val "$OUT" count)/$(val "$OUT" last_exists)" "1/True"
stage A

echo "== (B)(C) planner 회차 — 격리 git 픽스처"
GIT="git -c user.name=t -c user.email=t@t"
OR="$T/origin.git"; CL="$T/clone"; WT="$T/ledgerwt"
git init -q --bare -b main "$OR"; git clone -q "$OR" "$CL" 2>/dev/null; mkdir -p "$CL/design/planner"
printf '| 팀 | 폴더 | 좌석 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | planner#1 | 현역 |\n' > "$CL/design/TEAMS.md"
{ printf '# 자율 골 A6 (시험 픽스처)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n'; for g in k1 k2 k3 k4 k5 k6; do printf '| %s | 팀x | 착지 sha |\n' "$g"; done; } > "$CL/design/planner/AUTONOMY-GOAL-A6-20261018.md"
ledger() { printf '# 원장\n\n> 마지막 갱신: 2026-11-02 12:00 · planner#1\n\n## 메인 골 6줄 — 지금 상태\n\n| 골(오빠 원문) | 지금 상태 | 닫히려면 남은 것 |\n|---|---|---|\n'; for i in 1 2 3 4 5 6; do printf '| 원장 글자 %s | 상태%s 진행 | 남은%s |\n' "$i" "$i" "$i"; done; printf '\n## 1. 하는 일\n\n| 항목 | 값 |\n|---|---|\n| 알파 | %s |\n' "$1"; }
ledger v1 > "$CL/design/planner/PLAN-oppa-ledger.md"
$GIT -C "$CL" add -A; $GIT -C "$CL" commit -qm v1; $GIT -C "$CL" push -q origin HEAD:main
V1="$($GIT -C "$CL" rev-parse HEAD)"
ledger v2 > "$CL/design/planner/PLAN-oppa-ledger.md"; $GIT -C "$CL" commit -qam v2; $GIT -C "$CL" push -q origin HEAD:main
$GIT -C "$CL" fetch -q origin; $GIT -C "$CL" worktree add -q --detach "$WT" origin/main
# 가짜 «다른 좌석 fetch» — 검증 렌더 전에 origin/main 을 새 커밋으로 옮긴다(공유 refs 라 워크트리 WT 도 같이 옮겨진다)
cat > "$T/hook.sh" <<EOF
set -e
D="$T/other"; [ -d "\$D" ] || git clone -q "$OR" "\$D" 2>/dev/null
echo "x\$RANDOM" >> "\$D/design/planner/note.md"; git -C "\$D" add -A; git -C "\$D" -c user.name=t -c user.email=t@t commit -qm moved; git -C "\$D" push -q origin HEAD:main
git -C "$CL" fetch -q origin
EOF
echo true > "$T/noop.sh"
cat > "$T/round.py" <<'PY'
import logging, os, subprocess, sys
sys.path.insert(0, sys.argv[1])
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
import ft_news_ledger as L
real = L.goal_gate.goal_block
def hooked(state_dir):
    out = real(state_dir)
    subprocess.run(["bash", os.environ["HOOK"]], check=True)   # 초안 렌더 «뒤» · 검증 렌더 «앞»
    return out
L.goal_gate.goal_block = hooked
raise SystemExit(L.run())
PY
cat > "$T/render.py" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import ft_news_ledger_round as R
import ft_goal_table as gt
if len(sys.argv) > 2 and sys.argv[2] == "pin":
    R.pin_round_ref(__import__("pathlib").Path(os.environ["FT_LEDGER_REPO"]))
print("HEAD=" + gt.render().splitlines()[0])
PY
echo 'printf "%s\n" "$*" >> "$MBOX_LOG"' > "$T/mbox-plain.sh"
echo 'echo "ERROR ledger 사본 checkout 실패: error: The following untracked working tree files would be overwritten by checkout:"; exit 1' > "$T/sync-fail.sh"
mkroot() {  # <이름> → $T/<이름> = 격리 루트(명부·무장 표식·기준선 V1)
  local r="$T/$1"; mkdir -p "$r/.fable-team/state/news-ledger" "$r/news"
  echo '{"_master":"byz-planner-master-claude#9","_desk":"d#1"}' > "$r/.fable-team/seats-planner.json"
  : > "$r/.fable-team/state/goal-gate.armed"; echo "$V1" > "$r/.fable-team/state/news-ledger/last.sha"; : > "$r/mbox.log"
}
round() {  # <bin> <루트이름> [VAR=val …] → OUT · RC
  local bin="$1" name="$2"; shift 2
  OUT="$(cd / && env HOOK="$T/hook.sh" FT_ROOT="$T/$name" FT_LEDGER_REPO="$WT" FT_GOAL_REPO="$WT" FT_LEDGER_PATH=design/planner/PLAN-oppa-ledger.md \
    FT_LEDGER_SYNCED=1 FT_NEWS_MODE=draft FT_NEWS_DIR="$T/$name/news" FT_NEWS_STATUS_INTERVAL=0 FT_NEWS_NOW="2026-11-02 12:05" FT_NOW="2026-11-02 12:05" \
    FT_MBOX="$T/mbox-plain.sh" MBOX_LOG="$T/$name/mbox.log" FT_NEWS_PUBLISH=/bin/false "$@" timeout 70 python3 "$T/round.py" "$bin" 2>&1)"; RC=$?
}
drafts() { find "$T/$1/news" -name 'NEWS-*.md' 2>/dev/null | wc -l | tr -d ' '; }
cover_sha() { local f; f="$(find "$T/$1/news" -name 'NEWS-*.md' | head -1)"; [ -n "$f" ] && head -1 "$f" | sed -n 's/.*골표 \([0-9a-f]\{10\}\)·.*/\1/p'; }
pinned_sha() { printf '%s\n' "$OUT" | sed -n 's/.*회차 ref 고정 origin\/main → \([0-9a-f]\{10\}\).*/\1/p' | head -1; }

# ── N5 · N7(새 설정) · N9
mkroot cur5; round "$KIT" cur5
eq "N5 한 회차에 origin/main 이 옮겨져도 rc0" "$RC" "0"
not "$OUT" "표지 sha10" "N5 «표지 sha10 … 다르다» 0"
eq "N5 초안 파일 생김" "$(drafts cur5)" "1"
eq "N5 초안 표지 sha10 = 회차 시작 sha" "$(cover_sha cur5)" "$(pinned_sha)"
eq "N7 초안 = FT_NEWS_DIR(사본 밖) · 사본 «??» 0" "$(git -C "$WT" status --porcelain | grep -c '^??' || true)" "0"
render9() {  # <bin> <루트이름> → OUT — 회차 고정 뒤 골 표 렌더(머리 · 번호 표식)
  OUT="$(cd / && env FT_ROOT="$T/$2" FT_MBOX="$T/mbox-plain.sh" MBOX_LOG="$T/$2/mbox.log" FT_NOW="2026-11-02 12:05" FT_LEDGER_REPO="$WT" FT_GOAL_REPO="$WT" \
    FT_LEDGER_PATH=design/planner/PLAN-oppa-ledger.md timeout 70 python3 "$T/render.py" "$1" pin 2>&1)"; RC=$?
}
mkroot cur9; render9 "$KIT" cur9
has "$OUT" "HEAD=★골 표 A6 (origin/main@" "N9 머리 출처 표지 = origin/main@<sha10>"
eq "N9 고정 sha 렌더 = 정본 렌더 → 번호 표식 쓰기 1" "$([ -s "$T/cur9/.fable-team/state/goal-numbering.tsv" ] && echo 1 || echo 0)" "1"
not "$OUT" "INFO 시안 렌더" "N9 시안 렌더 INFO 0"
stage B

# ── N6 · N8 · N7(옛 설정 재현)
mkdir -p "$T/noref"; git -C "$T/noref" init -q -b main; mkdir -p "$T/noref/design/planner"; cp "$CL/design/TEAMS.md" "$T/noref/design/"; cp "$CL/design/planner/"*.md "$T/noref/design/planner/"; $GIT -C "$T/noref" add -A; $GIT -C "$T/noref" commit -qm x
mkroot n6; OUT="$(cd / && env FT_ROOT="$T/n6" FT_LEDGER_REPO="$T/noref" FT_GOAL_REPO="$T/noref" FT_LEDGER_PATH=design/planner/PLAN-oppa-ledger.md FT_LEDGER_SYNCED=1 FT_NEWS_MODE=draft FT_NEWS_DIR="$T/n6/news" FT_NEWS_STATUS_INTERVAL=0 FT_NEWS_NOW="2026-11-02 12:05" FT_NOW="2026-11-02 12:05" FT_MBOX="$T/mbox-plain.sh" MBOX_LOG="$T/n6/mbox.log" HOOK="$T/noop.sh" timeout 70 python3 "$T/round.py" "$KIT" 2>&1)"; RC=$?
eq "N6 rev-parse 실패 → rc≠0" "$([ "$RC" != 0 ] && echo yes || echo no)" "yes"
eq "N6 ERROR «회차 시작 ref 고정 실패» 1줄" "$(printf '%s\n' "$OUT" | grep -c '^ERROR .*회차 시작 ref 고정 실패')" "1"
eq "N6 초안 0 · 발행 0" "$(drafts n6)/$([ -s "$T/n6/mbox.log" ] && echo mail || echo none)" "0/none"
touch "$WT/design/planner/NEWS-old-draft-p1.md"     # 사본 안 untracked 충돌 파일(남의 파일일 수 있다)
SNAP="$(git -C "$WT" status --porcelain)"
mkroot n8; round "$KIT" n8 HOOK="$T/noop.sh" FT_LEDGER_SYNCED=0 FT_LEDGER_SYNC="$T/sync-fail.sh" FT_LEDGER_SYNC_MIN=0
has "$OUT" "원장 사본 갱신 안 됨" "N8 ERROR 줄(지금 그대로)"
eq "N8 planner [긴급] 1통" "$(grep -c '\[긴급\] 뉴스 원장 사본 checkout 막힘' "$T/n8/mbox.log")" "1"
round "$KIT" n8 HOOK="$T/noop.sh" FT_LEDGER_SYNCED=0 FT_LEDGER_SYNC="$T/sync-fail.sh" FT_LEDGER_SYNC_MIN=0
eq "N8 같은 사유 10분 안 둘째 회차 = 통지 0(누적 1통)" "$(grep -c '\[긴급\] 뉴스 원장 사본 checkout 막힘' "$T/n8/mbox.log")" "1"
eq "N8 파일 이동·삭제 0(untracked 그대로)" "$([ "$(git -C "$WT" status --porcelain)" = "$SNAP" ] && [ -f "$WT/design/planner/NEWS-old-draft-p1.md" ] && echo same || echo changed)" "same"
rm -f "$WT/design/planner/NEWS-old-draft-p1.md"
# N7 옛 설정(= 기준값): 초안 폴더가 사본 안이면 사본 git status 에 «??» — 이 카드의 plist 설정(사본 밖)이 이를 없앤다
mkroot old7; round "$KIT" old7 HOOK="$T/noop.sh" FT_NEWS_DIR="$WT/design/planner/news"
eq "N7 기준값 재현: 옛 설정(FT_NEWS_DIR 사본 안) = 사본 «??» ≥ 1" "$([ "$(git -C "$WT" status --porcelain | grep -c '^??')" -ge 1 ] && echo yes || echo no)" "yes"
mv "$WT/design/planner/news" "$T/old7-moved"
stage C

echo "== ⓑ 기준판($BASESHA) — 같은 시험이 «빨갛다»"
desk "$BASEBIN" n1
eq "기준판 N1 = 첫 틱들에 12통(상한)" "$(val "$OUT" relays)" "12"
eq "기준판 N1 최소 간격 10분" "$(val "$OUT" mingap)" "10"
mkroot base5; round "$BASEBIN" base5
eq "기준판 N5 = exit 3" "$RC" "3"
has "$OUT" "표지 sha10" "기준판 N5 «표지 sha10 … 다르다» 재현"
eq "기준판 N5 초안 0" "$(drafts base5)" "0"
desk "$BASEBIN" n10 FT_DESK_TOOL_TIMEOUT=1 FT_DESK_RELAY_GAP_MIN=0
eq "기준판 N10 = «판정 불가 relay»(rc1) + 다음 틱 재발송(relay 2통)" "$(val "$OUT" rc1)/$(val "$OUT" relays)" "1/2"
mkroot base8; touch "$WT/design/planner/NEWS-old-draft-p1.md"
round "$BASEBIN" base8 HOOK="$T/noop.sh" FT_LEDGER_SYNCED=0 FT_LEDGER_SYNC="$T/sync-fail.sh" FT_LEDGER_SYNC_MIN=0
eq "기준판 N8 = [긴급] 0(ERROR 줄만)" "$(grep -c '\[긴급\] 뉴스 원장 사본 checkout 막힘' "$T/base8/mbox.log" || true)" "0"
rm -f "$WT/design/planner/NEWS-old-draft-p1.md"
stage 기준판

echo "== ⓒ 변이 4 — 각 변이가 대응 시험을 깬다"
desk "$T/mut-m1" n1
eq "변이1 간격 검사 제거 → N1 FAIL(relay 12통)" "$(val "$OUT" relays)" "12"
mkroot mut5; round "$T/mut-m2" mut5
eq "변이2 회차 고정 제거 → N5 FAIL(exit 3 · 표지 불일치)" "$RC" "3"
mkroot mut8; touch "$WT/design/planner/NEWS-old-draft-p1.md"
round "$T/mut-m3" mut8 HOOK="$T/noop.sh" FT_LEDGER_SYNCED=0 FT_LEDGER_SYNC="$T/sync-fail.sh" FT_LEDGER_SYNC_MIN=0
eq "변이3 [긴급] 통지 제거 → N8 FAIL(통지 0)" "$(grep -c '\[긴급\] 뉴스 원장 사본 checkout 막힘' "$T/mut8/mbox.log" || true)" "0"
rm -f "$WT/design/planner/NEWS-old-draft-p1.md"
mkroot mut9; render9 "$T/mut-m4" mut9
eq "변이4 PINNED_FROM 비교 제거 → N9 FAIL(번호 표식 0)" "$([ -s "$T/cur9/.fable-team/state/goal-numbering.tsv" ] && [ ! -s "$T/mut9/.fable-team/state/goal-numbering.tsv" ] && echo 0 || echo 1)" "0"
stage 변이

echo "단계별 초:$STAGES (한 회차 합계 $SECONDS 초)"
echo "RESULT fail=$fail"
[ "$fail" = 0 ]
