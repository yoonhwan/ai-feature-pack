#!/usr/bin/env bash
# test_news_relay_spacing_cover_pin_r1348.sh — r1348(Issue #6171): 뉴스 발행 정지 원인 셋.
#   (A) desk relay 하루 12통을 «자정 뒤 2시간» 에 다 써 19시간 0통 → relay 사이 간격 ≥ 120분(N1·N2·N3·N4) + relay 가 «QUEUED seq=» 를 낸 뒤 시간 초과면 보낸 것으로 셈(N10)
#   (B) planner 회차 안에서 초안 표지(회차 시작 origin/main)와 검증 렌더(그때의 origin/main)가 달라 exit 3 → 회차 시작 sha 고정(N5·N6·N9)
#   (C) 초안이 원장 사본 안 untracked → 사본 checkout 막힘 · 로그에만 남던 것 → planner [긴급] 1통 · 자동 정리 0(N7·N8)
# DA ① HOLD(R1~R8) 반영: N11(relay-last 없음·깨짐 → last-sent 시각) N12(기록 시각 = relay 성공 뒤) N13(영수증 = 줄 전체·수신자) N3b(실 mbox 순서: QUEUED 가 늦게 → mailbox.jsonl 확인) N14(정본·원장 gitref 도 같은 sha) N15(run() 뒤 env 복원) · DA ② R5(ref 철자 무관 sha 고정 N14b·c) R8(통지 상한 min(env,7) N8b) N16(골 표 리포 ≠ 원장 리포) N8b(통지 7초)
# 구성: ⓐ 현재 판 N1~N16 ⓑ 기준판(base 3d81b7bd 의 kit bin)에서 N1·N5·N7·N8·N10 이 «빨간지» ⓒ 변이 4(간격 검사·회차 고정·[긴급] 통지·PINNED_FROM 비교 제거)
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
  mkdir -p "$T/mut-$1"; cp -c "$KIT"/*.py "$T/mut-$1/" 2>/dev/null || cp "$KIT"/*.py "$T/mut-$1/"
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
mut m2 ft_goal_gate.py '    block = gt.render()
    spent' '    os.environ["FT_TEAMS_REF"] = os.environ.get("FT_TEAMS_REF_PINNED_FROM", os.environ.get("FT_TEAMS_REF", "origin/main"))
    block = gt.render()
    spent'
mut m3 ft_news_ledger_round.py '    state = root / ".fable-team" / "state"
    stamp, key' '    return False
    state = root / ".fable-team" / "state"
    stamp, key'
mut m4 ft_goal_table.py '    return os.environ[PINNED_FROM] if ref in _pinned_refs() else ref' '    return ref'
mut m5 ft_news_desk_relay.py '        return (state / "last-sent.txt").stat().st_mtime' '        return None'
mut m6 ft_news_desk_relay.py '    t0, first = time.monotonic(), summary' '    return False
    t0, first = time.monotonic(), summary'
mut m7 ft_news_ledger_round.py '    for k, v in snap.items():' '    return
    for k, v in snap.items():'
mut m8 ft_news_ledger_round.py '    v = os.environ.get(key, "")
    if not v.startswith("gitref:"):' '    return
    v = os.environ.get(key, "")
    if not v.startswith("gitref:"):'
mut m9 ft_news_desk_relay.py 'now.timestamp() + max(elapsed, 0.0)' 'now.timestamp()'
mut m10 ft_news_desk_relay.py 'rf"^QUEUED seq=\d+ to={re.escape(seat)}(?:\s|$)", out, re.M)' 'r"QUEUED seq=\d+", out)'
mut m11 ft_news_ledger_round.py '        _explicit_specs(base, sha, repo, goal_sha)' '        pass'
stage 사본

# ── (A) desk 간격 구동기 ──────────────────────────────────────────────────────
cat > "$T/mbox-stub.sh" <<'SH'
#!/bin/sh
echo "$FT_DESK_NOW $1" >> "$DESK_LOG"
case "${STUB_MODE:-}" in
  slow) echo "QUEUED seq=7 to=$2"; exec sleep 6;;
  quote) echo "본문 인용 QUEUED seq=9 to=$2 끝"; exec sleep 6;;
  other) echo "QUEUED seq=9 to=somebody-else pending=1"; exec sleep 6;;
  late) printf '{"seq": "9", "ts": "%s", "to": "%s", "from": "ft-news-desk", "body": "%s"}\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$2" "$5" >> "$FT_DESK_MAILBOX"; exec sleep 6;;
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
elif scen == "n11":
    os.makedirs(state, exist_ok=True)
    sent = os.path.join(state, "last-sent.txt"); open(sent, "w", encoding="utf-8").write(text({"c": 0}))
    os.utime(sent, (START.timestamp(), START.timestamp()))          # 설치 직후: last-sent 만 있고 relay-last 없음(또는 깨짐)
    if os.environ.get("BAD_LAST"):
        open(os.path.join(state, "relay-last.txt"), "w", encoding="utf-8").write(os.environ["BAD_LAST"] + "\n")
    tick(10, {"c": 1}); mid = len(relays()); tick(130, {"c": 2})
    print(f"relays_mid={mid}"); print(f"relays={len(relays())}")
elif scen == "n12":
    import time
    real, off = time.monotonic, [0.0]
    time.monotonic = lambda: real() + off[0]
    def slow_build(root, now):
        off[0] += 120.0                                              # 전문 조립에 2분
        return CUR["text"]
    D.build = slow_build
    tick(0, {"c": 0}); tick(120, {"c": 1}); mid = len(relays()); tick(123, {"c": 2})
    print(f"relays_mid={mid}"); print(f"relays={len(relays())}")
elif scen == "n13":
    rc = tick(0, {"c": 0})
    print(f"rc={rc}"); print(f"relays={len(relays())}"); print(f"last_exists={read('relay-last.txt') != '-'}"); print(f"count={read('relay-count-20261102.txt')}")
elif scen == "n3b":
    rc1 = tick(0, {"c": 0}); rc2 = tick(10, {"c": 0})
    print(f"rc1={rc1}"); print(f"rc2={rc2}"); print(f"relays={len(relays())}"); print(f"count={read('relay-count-20261102.txt')}")
elif scen == "n10":
    os.environ["STUB_MODE"] = "slow"
    rc1 = tick(0, {"x": 1}); rc2 = tick(10, {"x": 1})
    print(f"rc1={rc1}"); print(f"rc2={rc2}"); print(f"relays={len(relays())}")
    print(f"count={read('relay-count-20261102.txt')}"); print(f"last_exists={read('relay-last.txt') != '-'}")
PY
desk() {  # <bin> <시나리오> [VAR=val …] → OUT(키=값 줄들) · RC
  local bin="$1" scen="$2"; shift 2
  local d="$T/desk-$scen-$RANDOM"; mkdir -p "$d/root/.fable-team"; : > "$d/mbox.log"; : > "$d/mailbox.jsonl"
  OUT="$(cd / && env FT_ROOT="$d/root" FT_DESK_SEATS="$T/seats-desk.json" FT_MBOX="$T/mbox-stub.sh" DESK_LOG="$d/mbox.log" \
    FT_DESK_STATE="$d/state" FT_DESK_MAILBOX="$d/mailbox.jsonl" "$@" timeout 70 python3 "$T/desk.py" "$bin" "$scen" "$d/state" 2>"$d/err")"; RC=$?
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
desk "$KIT" n10 FT_DESK_TOOL_TIMEOUT=0.5 FT_DESK_RELAY_GAP_MIN=0
eq "N10 QUEUED 뒤 시간 초과 → 첫 틱 rc0(보낸 것으로 셈)" "$(val "$OUT" rc1)" "0"
eq "N10 둘째 틱(같은 내용) rc0" "$(val "$OUT" rc2)" "0"
eq "N10 같은 내용 재발송 0(relay 1통)" "$(val "$OUT" relays)" "1"
eq "N10 하루 수 1 · relay-last 갱신" "$(val "$OUT" count)/$(val "$OUT" last_exists)" "1/True"
desk "$KIT" n11 FT_DESK_RELAY_GAP_MIN=120
eq "N11 relay-last 없음 + last-sent 있음 → 10분 뒤 relay 0" "$(val "$OUT" relays_mid)" "0"
eq "N11 120분 뒤 relay 1통" "$(val "$OUT" relays)" "1"
for bad in nan inf abc; do desk "$KIT" n11 BAD_LAST=$bad; eq "N11 relay-last='$bad' → last-sent 시각으로 간격 유지(relay 0)" "$(val "$OUT" relays_mid)" "0"; done
desk "$KIT" n12
eq "N12 조립 2분 걸린 relay 뒤 120분 틱 = 간격 118분 → relay 0" "$(val "$OUT" relays_mid)" "1"
eq "N12 123분 틱 relay 1통 더" "$(val "$OUT" relays)" "2"
desk "$KIT" n13 FT_DESK_TOOL_TIMEOUT=0.5 STUB_MODE=quote
eq "N13 본문 인용 «QUEUED seq» → 보낸 것으로 안 셈(rc≠0 · relay-last 0 · 수 0)" "$([ "$(val "$OUT" rc)" != 0 ] && echo yes || echo no)/$(val "$OUT" last_exists)/$(val "$OUT" count)" "yes/False/-"
desk "$KIT" n13 FT_DESK_TOOL_TIMEOUT=0.5 STUB_MODE=other
eq "N13 다른 수신자 영수증 → 보낸 것으로 안 셈" "$([ "$(val "$OUT" rc)" != 0 ] && echo yes || echo no)/$(val "$OUT" last_exists)" "yes/False"
desk "$KIT" n3b FT_DESK_TOOL_TIMEOUT=0.5 FT_DESK_RELAY_GAP_MIN=0 STUB_MODE=late
eq "N3b 실 mbox 순서(QUEUED 가 늦음 → stdout 빔) + mailbox.jsonl 에 있음 → 보낸 것으로 셈" "$(val "$OUT" rc1)/$(val "$OUT" rc2)" "0/0"
eq "N3b 재발송 0(relay 1통) · 하루 수 1" "$(val "$OUT" relays)/$(val "$OUT" count)" "1/1"
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
rc = L.run()
print("ENV_TEAMS=" + os.environ.get("FT_TEAMS_REF", "-") + " ENV_FROM=" + os.environ.get("FT_TEAMS_REF_PINNED_FROM", "-"))
raise SystemExit(rc)
PY
cat > "$T/render.py" <<'PY'
import os, subprocess, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import ft_news_ledger_round as R
import ft_goal_table as gt
modes = sys.argv[2:]
if "pin" in modes:
    print("PIN=" + R.pin_round_ref(Path(os.environ["FT_LEDGER_REPO"]))[:10])
if "hook" in modes:
    subprocess.run(["bash", os.environ["HOOK"]], check=True)   # 고정 «뒤» 에 다른 좌석이 origin/main 을 옮긴다
print("HEAD=" + gt.render().splitlines()[0])
if "negcanon" in modes:   # 고정 중에 ref «이름» 으로 지정한 정본은 정본 렌더가 아니다(R5)
    os.environ["FT_GOAL_A6_MD"] = "gitref:origin/main:design/planner/AUTONOMY-GOAL-A6-20261018.md"
    print("CANON_BY_NAME=" + str(gt._canon_render()))
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
render9() {  # <bin> <루트이름> <모드들> [VAR=val …] → OUT — 회차 고정 뒤 골 표 렌더(머리 · 번호 표식)
  local bin="$1" name="$2" modes="$3"; shift 3
  OUT="$(cd / && env FT_ROOT="$T/$name" FT_MBOX="$T/mbox-plain.sh" MBOX_LOG="$T/$name/mbox.log" FT_NOW="2026-11-02 12:05" FT_LEDGER_REPO="$WT" FT_GOAL_REPO="$WT" HOOK="$T/hook.sh" \
    FT_LEDGER_PATH=design/planner/PLAN-oppa-ledger.md "$@" timeout 70 python3 "$T/render.py" "$bin" $modes 2>&1)"; RC=$?
}
head_sha() { printf '%s\n' "$OUT" | sed -n 's/^HEAD=★골 표 A6 (origin\/main@\([0-9a-f]\{10\}\) .*/\1/p' | head -1; }
out_val() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p" | head -1; }
mkroot cur9; render9 "$KIT" cur9 pin
has "$OUT" "HEAD=★골 표 A6 (origin/main@" "N9 머리 출처 표지 = origin/main@<sha10>"
eq "N9 고정 sha 렌더 = 정본 렌더 → 번호 표식 쓰기 1" "$([ -s "$T/cur9/.fable-team/state/goal-numbering.tsv" ] && echo 1 || echo 0)" "1"
not "$OUT" "INFO 시안 렌더" "N9 시안 렌더 INFO 0"
# N14(R5): 정본·원장을 gitref:origin/main: «이름» 으로 지정해도 고정 sha 로 읽는다 · 고정 중 ref 이름 지정은 정본 렌더가 아니다
SPECS=(FT_GOAL_A6_MD=gitref:origin/main:design/planner/AUTONOMY-GOAL-A6-20261018.md FT_GOAL_A6_LEDGER=gitref:origin/main:design/planner/PLAN-oppa-ledger.md)
mkroot n14; render9 "$KIT" n14 "pin hook negcanon" "${SPECS[@]}"
eq "N14 고정 뒤 origin/main 이 옮겨져도 머리 sha10 = 고정 sha" "$(head_sha)" "$(out_val PIN)"
eq "N14 고정 중 ref «이름» 정본 = 정본 렌더 아님" "$(out_val CANON_BY_NAME)" "False"
SPECS2=(FT_GOAL_A6_MD=gitref:refs/remotes/origin/main:design/planner/AUTONOMY-GOAL-A6-20261018.md FT_GOAL_A6_LEDGER=gitref:remotes/origin/main:design/planner/PLAN-oppa-ledger.md)
mkroot n14b; render9 "$KIT" n14b "pin hook" "${SPECS2[@]}"
eq "N14b ref 철자가 달라도(refs/remotes/origin/main · remotes/origin/main) 머리 sha10 = 고정 sha" "$(head_sha)" "$(out_val PIN)"
mkroot n14c; render9 "$KIT" n14c "pin" FT_GOAL_A6_MD=gitref:no-such-ref:design/planner/AUTONOMY-GOAL-A6-20261018.md
eq "N14c 못 푸는 ref 지정 = rc≠0 · ERROR 1줄(조용한 폴백 0)" "$([ "$RC" != 0 ] && echo 1 || echo 0)/$(printf '%s\n' "$OUT" | grep -c '^RuntimeError: 회차 시작 ref 고정 실패')" "1/1"
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
# N8b(R8): 통지 mbox 호출은 7초 상한 — 걸린 mbox 에도 소요가 상한 안(시험은 상한을 1초로 줄여 건다) · 기본값 = 7
printf '#!/bin/sh\nexec sleep 3\n' > "$T/mbox-sleep.sh"
cat > "$T/notify8.py" <<'PY'
import sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import ft_news_ledger_round as R
t0 = time.monotonic()
R.notify_checkout_blocked(Path(sys.argv[2]), "/x/repo", "ERROR ledger 사본 checkout 실패: untracked would be overwritten")
print(f"ELAPSED={time.monotonic() - t0:.1f}"); print(f"DEFAULT={R.NOTIFY_S}")
import os
for v in ("15", "abc", "nan", "0", "3"):
    os.environ["FT_NEWS_NOTIFY_TIMEOUT"] = v; print(f"CLAMP_{v}={R._notify_timeout():g}")
PY
notify8() { mkroot "$2"; OUT="$(cd / && env FT_MBOX="$T/mbox-sleep.sh" FT_NEWS_NOTIFY_TIMEOUT=0.5 timeout 70 python3 "$T/notify8.py" "$1" "$T/$2" 2>&1)"; RC=$?; }
notify8 "$KIT" n8b
eq "N8b 걸린 mbox → 통지가 상한(0.5초 설정) 안에서 끝남" "$(python3 -c "print('yes' if float('$(out_val ELAPSED)' or 99) < 1.5 else 'no')")" "yes"
eq "N8b 통지 상한 기본값 7초" "$(out_val DEFAULT)" "7"
eq "N8b env 15 → 실제 7 · 숫자 아님·nan·0 → 7 · env 3 → 3" "$(out_val CLAMP_15)/$(out_val CLAMP_abc)/$(out_val CLAMP_nan)/$(out_val CLAMP_0)/$(out_val CLAMP_3)" "7/7/7/7/3"
# N15(R6): run() 뒤 env 복원 — 고정 전 값 그대로(FT_TEAMS_REF 없음 → 없음 · 있음 → 그 값)
mkroot n15a; round "$KIT" n15a HOOK="$T/noop.sh"
eq "N15 run() 뒤 FT_TEAMS_REF·PINNED_FROM 없음(고정 전 그대로)" "$(printf '%s\n' "$OUT" | sed -n 's/^ENV_TEAMS=\(.*\)$/\1/p')" "- ENV_FROM=-"
mkroot n15b; round "$KIT" n15b HOOK="$T/noop.sh" FT_TEAMS_REF=origin/main
eq "N15 원래 FT_TEAMS_REF=origin/main → run() 뒤에도 그 값" "$(printf '%s\n' "$OUT" | sed -n 's/^ENV_TEAMS=\(.*\)$/\1/p')" "origin/main ENV_FROM=-"
# N16(R7): 골 표 리포 ≠ 원장 리포 — 각 리포에서 따로 고정(명단은 원장 리포 sha · 골 표 읽기는 골 표 리포 sha)
other_push() { local D="$T/other"; [ -d "$D" ] || git clone -q "$OR" "$D" 2>/dev/null; echo "y$RANDOM" >> "$D/design/planner/note.md"; $GIT -C "$D" add -A; $GIT -C "$D" commit -qm adv; $GIT -C "$D" push -q origin HEAD:main; }
git clone -q "$OR" "$T/goal-old" 2>/dev/null        # 골 표 리포가 «뒤»(원장 리포가 앞서면 원장 sha 가 골 표 리포에 없다)
other_push; $GIT -C "$CL" fetch -q origin
mkroot n16b; round "$KIT" n16b HOOK="$T/noop.sh" FT_GOAL_REPO="$T/goal-old"
eq "N16b 골 표 리포가 뒤 → rc0 · 초안 1" "$RC/$(drafts n16b)" "0/1"
not "$OUT" "원장 뉴스 실패" "N16b «원장 뉴스 실패» 0"
other_push; git clone -q "$OR" "$T/goal-new" 2>/dev/null   # 골 표 리포가 «앞»(원장 리포는 fetch 안 함 → 골 표 sha 가 원장 리포에 없다)
mkroot n16a; round "$KIT" n16a HOOK="$T/noop.sh" FT_GOAL_REPO="$T/goal-new"
eq "N16a 골 표 리포가 앞 → rc0 · 초안 1" "$RC/$(drafts n16a)" "0/1"
not "$OUT" "원장 뉴스 실패" "N16a «원장 뉴스 실패» 0"
stage C

echo "== ⓑ 기준판($BASESHA) — 같은 시험이 «빨갛다»"
desk "$BASEBIN" n1
eq "기준판 N1 = 첫 틱들에 12통(상한)" "$(val "$OUT" relays)" "12"
eq "기준판 N1 최소 간격 10분" "$(val "$OUT" mingap)" "10"
mkroot base5; round "$BASEBIN" base5
eq "기준판 N5 = exit 3" "$RC" "3"
has "$OUT" "표지 sha10" "기준판 N5 «표지 sha10 … 다르다» 재현"
eq "기준판 N5 초안 0" "$(drafts base5)" "0"
desk "$BASEBIN" n10 FT_DESK_TOOL_TIMEOUT=0.5 FT_DESK_RELAY_GAP_MIN=0
eq "기준판 N10 = «판정 불가 relay»(rc1) + 다음 틱 재발송(relay 2통)" "$(val "$OUT" rc1)/$(val "$OUT" relays)" "1/2"
mkroot base8; touch "$WT/design/planner/NEWS-old-draft-p1.md"
round "$BASEBIN" base8 HOOK="$T/noop.sh" FT_LEDGER_SYNCED=0 FT_LEDGER_SYNC="$T/sync-fail.sh" FT_LEDGER_SYNC_MIN=0
eq "기준판 N8 = [긴급] 0(ERROR 줄만)" "$(grep -c '\[긴급\] 뉴스 원장 사본 checkout 막힘' "$T/base8/mbox.log" || true)" "0"
rm -f "$WT/design/planner/NEWS-old-draft-p1.md"
stage 기준판

echo "== ⓒ 변이 — 각 변이가 대응 시험을 깬다"
desk "$T/mut-m1" n1
eq "변이1 간격 검사 제거 → N1 FAIL(relay 12통)" "$(val "$OUT" relays)" "12"
mkroot mut5; round "$T/mut-m2" mut5
eq "변이2 회차 고정 제거 → N5 FAIL(exit 3 · 표지 불일치)" "$RC" "3"
mkroot mut8; touch "$WT/design/planner/NEWS-old-draft-p1.md"
round "$T/mut-m3" mut8 HOOK="$T/noop.sh" FT_LEDGER_SYNCED=0 FT_LEDGER_SYNC="$T/sync-fail.sh" FT_LEDGER_SYNC_MIN=0
eq "변이3 [긴급] 통지 제거 → N8 FAIL(통지 0)" "$(grep -c '\[긴급\] 뉴스 원장 사본 checkout 막힘' "$T/mut8/mbox.log" || true)" "0"
rm -f "$WT/design/planner/NEWS-old-draft-p1.md"
mkroot mut9; render9 "$T/mut-m4" mut9 pin
eq "변이4 머리 표지를 푼 ref 이름으로 못 바꿈 → N9 FAIL(머리가 sha 그대로)" "$(case "$OUT" in *"HEAD=★골 표 A6 (origin/main@"*) echo 1;; *) echo 0;; esac)" "0"
desk "$T/mut-m5" n11
eq "변이5 last-sent 대체 제거 → N11 FAIL(10분 뒤 relay 1)" "$(val "$OUT" relays_mid)" "1"
desk "$T/mut-m9" n12
eq "변이9 기록 시각에 경과 안 더함 → N12 FAIL(120분 틱 relay)" "$(val "$OUT" relays_mid)" "2"
desk "$T/mut-m10" n13 FT_DESK_TOOL_TIMEOUT=0.5 STUB_MODE=quote
eq "변이10 영수증 줄 전체·수신자 검사 제거 → N13 FAIL(인용을 보낸 것으로 셈 rc0)" "$(val "$OUT" rc)" "0"
desk "$T/mut-m6" n3b FT_DESK_TOOL_TIMEOUT=0.5 FT_DESK_RELAY_GAP_MIN=0 STUB_MODE=late
eq "변이6 mailbox 확인 제거 → N3b FAIL(rc1≠0)" "$([ "$(val "$OUT" rc1)" != 0 ] && echo 1 || echo 0)" "1"
mkroot mut15; round "$T/mut-m7" mut15 HOOK="$T/noop.sh"
eq "변이7 env 복원 제거 → N15 FAIL(고정 sha 가 남음)" "$(printf '%s\n' "$OUT" | sed -n 's/^ENV_TEAMS=\(.*\)$/\1/p' | grep -c '^[0-9a-f]\{40\} ')" "1"
mkroot mut14; render9 "$T/mut-m8" mut14 "pin hook" "${SPECS[@]}"
eq "변이8 gitref 지정 재작성 제거 → N14 FAIL(머리 sha10 ≠ 고정 sha)" "$([ "$(head_sha)" != "$(out_val PIN)" ] && echo 1 || echo 0)" "1"
mkroot mut16; round "$T/mut-m11" mut16 HOOK="$T/noop.sh" FT_GOAL_REPO="$T/goal-old"
eq "변이11 골 표 리포 명시 지정 제거 → N16b FAIL(rc≠0)" "$([ "$RC" != 0 ] && echo 1 || echo 0)" "1"
mut m12 ft_news_ledger_round.py 'timeout=_notify_timeout())' 'timeout=60)'
notify8 "$T/mut-m12" mut8b
eq "변이12 통지 상한 제거 → N8b FAIL(걸린 mbox 를 끝까지 기다림 ≥ 2.5초)" "$(python3 -c "print('yes' if float('$(out_val ELAPSED)' or 0) >= 2.5 else 'no')")" "yes"
mut m13 ft_news_ledger_round.py '    return min(v, float(NOTIFY_S)) if' '    return v if'
notify8 "$T/mut-m13" mut8c
eq "변이13 env 상한 클램프 제거 → N8b FAIL(env 15 가 15 그대로)" "$(out_val CLAMP_15)" "15"
stage 변이

echo "단계별 초:$STAGES (한 회차 합계 $SECONDS 초)"
echo "RESULT fail=$fail"
[ "$fail" = 0 ]
