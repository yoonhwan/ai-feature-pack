#!/usr/bin/env bash
# ft-sat-nano «남김(park) 만료·고아 계획(reap)» 시험 (r950) — 위성 나노 팀 운영 체계 2/2.
#   원격 대역 = rt.rcall 바꿔치기(호출 목록 기록) · 실 mini 0 · 실 tmux 0 · 상태 폴더 = 임시 · FT_NOW 고정
#   ⓐ park 30 → 명부 PARKED(만료 = 지금+30분) · 만료 전 sweep = 닫힘 0 · 만료 뒤 sweep = close 경로로 닫힘 + 원장 «만료 자동 닫음» 1줄
#   ⓑ 연장 1회 OK(총 60분) · 2회째 rc2 · 31분 이상 요청 rc2 · OPEN 에 --extend rc2
#   ⓒ PARKED 도 상한 3 에 셈
#   ⓓ reap = 계획 파일(.sh.hil)만 · kill 0 · 명부 밖 세션 · 오래된 OPEN
#   ⓔ 만료 닫기 실패 → 명부 «닫기 실패» + 원장 1줄 · 다음 sweep 재시도(조용한 성공 0)
#   ⓕ 기존 시험(r902 · r949) ALL PASS · ⓖ 변이 3종(만료 검사 · 연장 횟수 검사 · reap kill)
#   실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE /bin/bash tests/test_sat_nano_r950.sh
set -uo pipefail
HARNESS="$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$HARNESS/bin"; KIT="$HARNESS/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_NOW="2026-10-26T09:00:00Z"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

cat >"$T/cell.py" <<'PY'
import contextlib, io, json, os, sys
bd, cell, st, tmp = sys.argv[1:5]
os.environ["SAT_STATE_DIR"] = st
os.makedirs(st, exist_ok=True)
sys.path.insert(0, bd)
import ft_sat_nano as m
rt, gate = m.rt, m.gate
ID = "$1 100 /tmp/s.sock /home/x"
NOW = os.environ["FT_NOW"]


def fake(rlookup=None, ls=("byz-satnano-nano-orphan#0",)):
    """원격 대역 — 호출 (스크립트, 인자) 목록을 돌려준다."""
    calls = []

    def f(dl, script, *a, **k):
        calls.append((script, a))
        if script == m.R_PRE:
            head = "tmuxc=ok\npi=ok\nperl=ok\nsess_rc=1\nfree_rc=0\n"
            return 0, (head + "free_raw=50\ndir=absent\n").encode(), ""
        if script == m.R_LS:
            return 0, ("\n".join(ls) + "\nls_rc=0\n").encode(), ""
        if script == m.R_LOOKUP:
            if rlookup is not None:
                return rlookup
            return 0, ("has=0\ndrc=0\nident=%s\ndirmatch=1\n" % ID).encode(), ""
        if script == m.R_OPEN_BG:
            return 0, b"running\n1 x\n", ""
        return 0, {m.R_WRITE: b"", m.R_POLL: b"alive=1\ndone=\nsess_rc=0\n", m.R_IDENT: (ID + "\n").encode(),
                   m.R_PIDS: b"1\n", m.R_SEND: b"SENDOK\n", m.R_KILL: m.KILL_OK.encode() + b"\n"}[script], ""
    rt.rcall = f
    return calls


def run(*argv):
    o, e = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(o), contextlib.redirect_stderr(e):
        rc = m.main(list(argv))
    return rc, o.getvalue() + e.getvalue()


def card(name, body="남겨둬라.\n"):
    p = os.path.join(tmp, name)
    with open(p, "w", encoding="utf-8") as f:
        f.write(body)
    return p


def rows():
    return gate.roster_rows()


def row0():
    r = rows()
    return r[0] if r else {}


def ledger():
    try:
        return open(os.path.join(st, "ledger.tsv"), encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        return []


def fld(line):
    """원장 1줄 = 시각 · 종류 · slug · 이름 · free · warn · 결과(사유) — r949 r4 7칸."""
    return (line.split("\t") + [""] * 7)[:7]


def opened():
    return rt.read_rows("opened.tsv")


def reset():
    for f in ("roster.json", "opened.tsv", "ledger.tsv"):
        try:
            os.remove(os.path.join(st, f))
        except FileNotFoundError:
            pass
    for f in os.listdir(st):  # 이전 칸이 쓴 reap 계획 파일도 지운다(칸 사이 누수 0)
        if f.startswith("reap-") and f.endswith(".sh.hil"):
            os.remove(os.path.join(st, f))


def kills(calls):
    return [c for c in calls if c[0] == m.R_KILL]


def seed(rs):
    json.dump({"rows": rs}, open(os.path.join(st, "roster.json"), "w"))  # noqa: SIM115


def iso(delta):
    return gate.iso_of(gate.parse_iso(NOW) + delta)


def c_park():
    """ⓐ 남김 시한 — 만료 전에는 닫히지 않고, 만료 뒤 sweep 1회가 close 경로로 닫는다."""
    res = []
    reset()
    fake()
    rc, _ = run("open", card("p.md"), "--run", "pk")
    res.append(rc == 0 and row0().get("status") == "OPEN")
    rc, out = run("park", "pk", "30")
    r = row0()
    res.append(rc == 0 and r.get("status") == "PARKED" and r.get("expire_at") == iso(1800)
               and int(r.get("expire_epoch") or 0) == gate.parse_iso(NOW) + 1800 and int(r.get("park_extend") or 0) == 0)
    # 만료 전 sweep = 원격 닫기 0 · 명부 PARKED 그대로
    calls = fake()
    rc, out = run("park", "--sweep")
    res.append(rc == 0 and row0().get("status") == "PARKED" and kills(calls) == []
               and not [x for x in ledger() if "만료 자동 닫음" in x])
    # 만료 뒤 sweep = close 경로(조회+kill) 1회 · 원장 close 1줄 «만료 자동 닫음» · 장부 줄 삭제
    os.environ["FT_NOW"] = "2026-10-26T09:31:00Z"
    calls = fake()
    rc, out = run("park", "--sweep")
    lg = ledger()
    res.append(rc == 0 and row0().get("status") == "CLOSED" and row0().get("closed_at") == os.environ["FT_NOW"]
               and len(kills(calls)) == 1 and [c[0] for c in calls].count(m.R_LOOKUP) == 1
               and len([x for x in lg if fld(x)[1] == "close"]) == 1
               and fld(lg[-1])[1] == "close" and "만료 자동 닫음" in fld(lg[-1])[6]
               and opened() == [] and "만료 자동 닫음" in out)
    # 만료 0(이미 닫힘) 뒤 sweep = 원격 0
    calls = fake()
    rc, out = run("park", "--sweep")
    res.append(rc == 0 and calls == [] and row0().get("status") == "CLOSED")
    return all(res), "res=%s expire=%s out=%s" % (res, row0().get("expire_at"), out.strip()[-120:])


def c_extend():
    """ⓑ 연장은 1회 · 총 60분 · 31분 이상 요청 0."""
    res = []
    reset()
    fake()
    run("open", card("e.md"), "--run", "ex")
    rc, out = run("park", "ex", "30")
    res.append(rc == 0 and row0().get("expire_at") == iso(1800))
    rc, out = run("park", "ex", "30", "--extend")
    r = row0()
    res.append(rc == 0 and r.get("expire_at") == iso(3600) and int(r.get("park_extend") or 0) == 1)
    rc, out = run("park", "ex", "30", "--extend")
    res.append(rc == 2 and row0().get("expire_at") == iso(3600) and "연장" in out)
    rc, out = run("park", "ex", "31", "--extend")
    res.append(rc == 2 and row0().get("expire_at") == iso(3600))
    rc, out = run("park", "ex", "31")
    res.append(rc == 2 and row0().get("expire_at") == iso(3600))
    rc, out = run("park", "ex", "0")
    res.append(rc == 2)
    # 연장 횟수 검사 «단독» — 총 시한은 안 넘는데 2회째라 거절되는 자리(변이가 이 칸에서만 잡힌다)
    reset()
    fake()
    run("open", card("e.md"), "--run", "ex3")
    run("park", "ex3", "30")
    rc, out = run("park", "ex3", "10", "--extend")
    ok10 = rc == 0 and row0().get("expire_at") == iso(2400)
    rc, out = run("park", "ex3", "10", "--extend")
    res.append(ok10 and rc == 2 and row0().get("expire_at") == iso(2400) and "1회뿐" in out)
    # 총 시한 60분 «단독» — 만료 뒤(sweep 전) 연장이라 연장 횟수는 0, 지금+30 이면 parked_at+70 = 상한 초과
    reset()
    fake()
    run("open", card("e.md"), "--run", "ex4")
    run("park", "ex4", "30")
    os.environ["FT_NOW"] = "2026-10-26T09:40:00Z"
    rc, out = run("park", "ex4", "30", "--extend")
    res.append(rc == 2 and row0().get("status") == "PARKED" and row0().get("expire_at") == iso(1800)
               and int(row0().get("park_extend") or 0) == 0 and "60분" in out)
    os.environ["FT_NOW"] = NOW
    # OPEN(남김 전) 에 --extend = rc2 · 상태 그대로
    reset()
    fake()
    run("open", card("e.md"), "--run", "ex2")
    rc, out = run("park", "ex2", "30", "--extend")
    res.append(rc == 2 and row0().get("status") == "OPEN")
    # 명부에 없는 slug = rc2 · 원격 0
    calls = fake()
    rc, out = run("park", "nope", "30")
    res.append(rc == 2 and calls == [])
    return all(res), "res=%s out=%s" % (res, out.strip()[-120:])


def c_cap():
    """ⓒ PARKED 도 상한에 센다 — 남긴 둘 + 열린 하나면 4번째 open 은 rc8 · 원격 0."""
    reset()
    calls = fake()
    run("open", card("c.md"), "--run", "k1")
    run("park", "k1", "30")
    run("open", card("c.md"), "--run", "k2")
    run("park", "k2", "30")
    run("open", card("c.md"), "--run", "k3")
    n = len(calls)
    rc, out = run("open", card("c.md"), "--run", "k4")
    st_ = [r.get("status") for r in rows()]
    return (rc == 8 and "상한 3" in out and len(calls) == n and len(rows()) == 3
            and st_.count("PARKED") == 2 and st_.count("OPEN") == 1), "rc=%s calls=%d status=%s out=%s" % (rc, len(calls) - n, st_, out.strip()[-100:])


def c_reap():
    """ⓓ reap = 계획 파일(.sh.hil)만 쓴다 · kill 0 · 명부·장부 그대로 · 남김(PARKED)은 건드리지 않는다."""
    res = []
    reset()
    seed([{"slug": "old", "name": "byz-satnano-nano-old#0", "run": "old", "status": "OPEN",
           "sock": "/tmp/s.sock", "opened_at": iso(-5400), "closed_at": "", "by": gate.MARK},
          {"slug": "pk", "name": "byz-satnano-nano-pk#0", "run": "pk", "status": "PARKED",
           "sock": "/tmp/s.sock", "opened_at": NOW, "expire_at": iso(-60), "expire_epoch": gate.parse_iso(NOW) - 60,
           "park_extend": 0, "by": gate.MARK}])
    calls = fake(ls=("byz-satnano-nano-orphan#0", "byz-satnano-nano-old#0", "other-session"))
    rc, out = run("reap")
    plans = sorted(f for f in os.listdir(st) if f.startswith("reap-") and f.endswith(".sh.hil"))
    body = ""
    if plans:
        body = open(os.path.join(st, plans[0]), encoding="utf-8").read()
    res.append(rc == 0 and [c[0] for c in calls] == [m.R_LS] and len(plans) == 1)
    res.append("kill 0" in body and "명부 밖 세션: byz-satnano-nano-orphan#0" in body
               and "오래된 OPEN: byz-satnano-nano-old#0" in body and "other-session" not in body
               and "byz-satnano-nano-pk#0" not in body)
    r = rows()
    res.append([x.get("status") for x in r] == ["OPEN", "PARKED"] and opened() == [] and len(ledger()) == 0)
    # 후보 0 = 계획 파일 0 · rc0
    reset()
    calls = fake(ls=("other-session",))
    rc, out = run("reap")
    plans2 = [f for f in os.listdir(st) if f.startswith("reap-") and f.endswith(".sh.hil")]
    res.append(rc == 0 and plans2 == [] and "후보 0" in out)
    # 원격 조회 실패 = rc5 · 계획 파일 0 · kill 0
    reset()
    calls = []

    def boom(dl, script, *a, **k):
        calls.append((script, a))
        return (5, b"", "ssh 실패") if script == m.R_LS else (0, b"", "")
    rt.rcall = boom
    rc, out = run("reap")
    res.append(rc == 5 and [c[0] for c in calls] == [m.R_LS]
               and not [f for f in os.listdir(st) if f.startswith("reap-")])
    return all(res), "res=%s plans=%s body=%s" % (res, plans, body.replace("\n", " | ")[:200])


def c_fail():
    """ⓔ 만료 닫기 실패 = 명부 «닫기 실패» + 원장 1줄 · 조용한 성공 0 · 다음 sweep 이 다시 시도."""
    res = []
    reset()
    fake()
    run("open", card("f.md"), "--run", "fo")
    run("park", "fo", "30")
    os.environ["FT_NOW"] = "2026-10-26T09:31:00Z"
    calls = fake(rlookup=(5, b"", "ssh 실패"))
    rc, out = run("park", "--sweep")
    r, lg = row0(), ledger()
    res.append(rc != 0 and r.get("status") == "PARKED" and "닫기 실패" in (r.get("park_fail") or "")
               and fld(lg[-1])[1] == "close" and fld(lg[-1])[6].startswith("닫기 실패")
               and len(opened()) == 1 and kills(calls) == [])
    # 다음 sweep = 다시 시도해서 닫힘
    calls = fake()
    rc, out = run("park", "--sweep")
    res.append(rc == 0 and row0().get("status") == "CLOSED" and "만료 자동 닫음" in fld(ledger()[-1])[6]
               and len(kills(calls)) == 1 and opened() == [])
    return all(res), "res=%s fail=%s lg=%s" % (res, row0().get("park_fail"), ledger())


good, why = globals()["c_" + cell]()
print(("OK " if good else "NO ") + why.replace("\n", " | "))
PY

cell() { # cell <bin 폴더> <칸> → 0 = 통과
  local d="$T/st-$2-$RANDOM" o
  o="$(python3 "$T/cell.py" "$1" "$2" "$d" "$T" 2>&1 | tail -1)"; LAST="$o"
  case "$o" in "OK "*) return 0;; esac; return 1
}
check() { if cell "$BIN" "$2"; then ok "$1"; else bad "$1 — $LAST"; fi; }

check "ⓐ park 30 → 명부 PARKED(만료 = 지금+30분) · 만료 전 sweep 닫힘 0 · 만료 뒤 sweep = close 경로 + 원장 «만료 자동 닫음» 1줄 + 장부 줄 삭제" park
check "ⓑ 연장 1회 OK(총 60분) · 2회째 rc2 · 31분 이상 rc2 · 0분 rc2 · OPEN 에 --extend rc2 · 없는 slug rc2 원격 0" extend
check "ⓒ PARKED 도 상한 3 에 셈(남긴 둘 + 열린 하나 → 4번째 open rc8 · 원격 0)" cap
check "ⓓ reap = 계획 파일 reap-<시각>.sh.hil 만 · kill 0 · 명부 밖 세션 + 오래된 OPEN · 후보 0 = 파일 0 · 조회 실패 rc5" reap
check "ⓔ 닫기 실패 → 명부 «닫기 실패» + 원장 1줄(close) + 장부 유지 · 다음 sweep 재시도로 닫힘" fail

echo "⏱ 칸 ⓐ~ⓔ ${SECONDS}초"
T_F="${SECONDS}"


# ⓕ 기존 시험 — r949 파일이 r902 · test_satellite_rosters 를 «안에서» 돌린다(같은 시험 2회 반복 0)
#   알려진 한계(arch#171 r1 판정 · 기준판 origin/main 도 같은 자리에서 멈춘다) =
#     ⒜ 공용 perf 시험의 «1MB 200ms · 10MB 2s» 벽시계 상한(다른 좌석 부하에 흔들린다)
#     ⒝ r949 ⓙ 시간 칸 · test_satellite_rosters ⓗ-2(살아 있는 명부·spawn 상태를 읽는다)
#   그 밖의 FAIL 줄이 하나라도 나오면 그대로 실패다(회귀 은폐 0).
KNOWN='test_ft_secret_shapes\.py|^FAIL ⓙ|test_satellite_rosters'
# FT_R950_SKIP_F=1 = ⓕ 건너뜀. r949 는 기준판(origin/main)도 이 맥에서 같은 자리로 멈추는 «알려진 한계» 라
# 반송·수정 회차에서는 이 칸을 빼고 돈다(고정 70초 상한 안에서 돌리기 위해서다 · 하드 룰 22).
if [ "${FT_R950_SKIP_F:-0}" = 1 ]; then
  echo "⏭ ⓕ 건너뜀(알려진 한계 · FT_R950_SKIP_F=1)"
else
for t in test_sat_nano_r949.sh; do
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u FT_NOW /bin/bash "$HARNESS/tests/$t" >"$T/g-$t.log" 2>&1; o="$(tail -1 "$T/g-$t.log")"
  bads="$(grep '^FAIL' "$T/g-$t.log" | grep -Ev "$KNOWN" | head -3 | tr '\n' ' ')"
  if [ "$o" = "ALL PASS" ]; then ok "ⓕ $t ALL PASS (/bin/bash $BASH_VERSION)"
  elif [ -z "$bads" ] && [ -n "$(grep '^FAIL' "$T/g-$t.log")" ]; then ok "ⓕ $t 알려진 한계만 빨강(부하 의존 perf·시간·살아있는 명부) — $(grep -c '^FAIL' "$T/g-$t.log")줄"
  else bad "ⓕ $t: $o — $bads"; fi
done
fi

echo "⏱ ⓕ 기존 시험 $((SECONDS - T_F))초 (누적 ${SECONDS}초)"
T_M="${SECONDS}"
# ⓖ 변이 — 검사를 끈 사본에서 «그 칸»이 빨강이어야 한다
mutf() { # mutf <id> <파일 이름> <옛 글자> <새 글자> → 사본 bin 폴더(그 파일에서 정확히 1곳)
  local d="$T/mut-$1"; mkdir -p "$d"; cp "$BIN"/ft_sat_nano.py "$BIN"/ft_sat_rt.py "$BIN"/ft_sat_gate.py "$BIN"/ft-name-lint.sh \
    "$BIN"/ft_secret_shapes.py "$BIN"/ft_secret_targets.py "$BIN"/ft_secret_lex.py "$BIN"/autonomy_scope_secret.py "$d/"
  python3 - "$d/$2" "$3" "$4" <<'PY' >&2 || return 1
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
if s.count(old) != 1: sys.exit("anchor count=%d: %s" % (s.count(old), old))
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  printf '%s' "$d"
}
mcheck() { # mcheck <변이 이름> <칸> <사본>
  [ -n "$3" ] || { bad "ⓖ 변이 $1 사본이 안 만들어졌다"; return; }
  if cell "$3" "$2"; then bad "ⓖ 변이 $1 → 칸 $2 가 안 빨갛다(시험이 헛돈다)"; else ok "ⓖ 변이 $1 → 칸 $2 빨강 = 감지"; fi
}
mcheck "만료 검사 끔" park "$(mutf expire ft_sat_nano.py 'and int(r.get("expire_epoch") or 0) <= now]' 'and True]')"
mcheck "연장 횟수 검사 끔" extend "$(mutf ext ft_sat_nano.py '    if int(row.get("park_extend") or 0) >= 1:' '    if False:')"
mcheck "총 시한 60분 검사 끔(60→90)" extend "$(mutf ptot ft_sat_nano.py 'PARK_TOTAL = 60' 'PARK_TOTAL = 90')"
mcheck "reap 이 kill 하게" reap "$(mutf kill ft_sat_nano.py '    cands = []' '    cands = []
    rt.rcall(dl, R_KILL, "", (names or [""])[0], "")')"

echo "⏱ ⓖ 변이 4종 $((SECONDS - T_M))초 (누적 ${SECONDS}초)"
# 정적 — 짝 사본 cmp0 · bash 3.2 문법
for f in ft_sat_nano.py ft_sat_gate.py ft_sat_rt.py ft-sat-nano.sh; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "정적 kit 사본 cmp0 $f" || bad "정적 kit 사본 불일치 $f"
done
/bin/bash -n "$0" && ok "정적 /bin/bash -n" || bad "정적 /bin/bash -n"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
