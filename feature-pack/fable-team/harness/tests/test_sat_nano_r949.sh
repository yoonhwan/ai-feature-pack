#!/usr/bin/env bash
# ft-sat-nano «열 때의 문» 시험 (r949) — 원격 대역 = rt.rcall 바꿔치기(호출 목록 기록) + R_PRE 실스크립트는 이 맥 bash 로 free% 대역만.
#   실 mini 0 · 실 tmux 0 · 상태 폴더 = 임시 · FT_NOW 고정
#   ⓐ 상한 · ⓑ 메모리 · ⓒ 이름 · ⓓ 명부·원장 · ⓔ 비밀 · ⓕ 표식 · ⓖ 기존 시험 · ⓗ 변이(칸 이름 단언)
#   ⓘ 비밀 위치(공백 앞·괄호 안 · r4: «한글 바로 뒤» 는 r977 범위라 이 카드 시험에 없다) · ⓙ 측정 시간 초과(3초 상한 · rc=124)
#   ⓚ 공용 lib 미수정(diff 0줄) · ⓛ 측정 3조건(값을 쓰려면 rc0∧시간∧파싱 셋 다) · ⓜ 원장 줄 종류·줄 수 · ⓝ base 가 잡던 반례 그대로
#   실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE /bin/bash tests/test_sat_nano_r949.sh
set -uo pipefail
HARNESS="$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$HARNESS/bin"; KIT="$HARNESS/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_NOW="2026-10-26T09:00:00Z"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

cat >"$T/cell.py" <<'PY'
import contextlib, io, json, os, subprocess, sys, time
bd, cell, st, tmp = sys.argv[1:5]
os.environ["SAT_STATE_DIR"] = st
os.makedirs(st, exist_ok=True)
sys.path.insert(0, bd)
import ft_sat_nano as m
rt, gate = m.rt, m.gate
ID = "$1 100 /tmp/s.sock /home/x"
TOKEN = "ghp_" + "Ab3" * 12
DSN = "postgres://u:" + "pw9" * 4 + "@db.example/x"


def fake(free="50", free_rc="0", rpre=None):
    calls = []
    def f(dl, script, *a, **k):
        calls.append(script)
        if script == m.R_PRE:
            if rpre is not None:
                return rpre
            head = "tmuxc=ok\npi=ok\nperl=ok\nsess_rc=1\nfree_rc=%s\n" % free_rc
            return 0, (head + "free_raw=%s\ndir=absent\n" % free).encode(), ""
        if script == m.R_OPEN_BG:
            return 0, b"running\n1 x\n", ""
        if script == m.R_LOOKUP:
            return 0, ("has=0\ndrc=0\nident=%s\ndirmatch=1\n" % ID).encode(), ""
        return 0, {m.R_WRITE: b"", m.R_POLL: b"alive=1\ndone=\nsess_rc=0\n", m.R_IDENT: (ID + "\n").encode(),
                   m.R_PIDS: b"1\n", m.R_SEND: b"SENDOK\n", m.R_KILL: m.KILL_OK.encode() + b"\n"}[script], ""
    rt.rcall = f
    return calls


def run(*argv):
    o, e = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(o), contextlib.redirect_stderr(e):
        rc = m.main(list(argv))
    return rc, o.getvalue() + e.getvalue()


def card(name, body="요약하라.\n"):
    p = os.path.join(tmp, name)
    with open(p, "w", encoding="utf-8") as f:
        f.write(body)
    return p


def rows():
    return gate.roster_rows()


def ledger():
    try:
        return open(os.path.join(st, "ledger.tsv"), encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        return []


def fld(line):
    """원장 1줄 = 시각 · 종류 · slug · 이름 · free · warn · 결과(사유) — r949 r4 7칸."""
    return (line.split("\t") + [""] * 7)[:7]


def real_pre(pathdir):
    """R_PRE 실스크립트(시험 대상 모듈의 것)를 이 맥 bash 로 돌린 결과 — (rc, out, err) 를 fake(rpre=…) 에 그대로 넣는다.
    스크립트를 «시험 대상 모듈» 에서 생성하므로 R_PRE 를 건드리는 변이가 이 칸에 잡힌다."""
    rp = os.path.join(tmp, "rpre-cell.sh")
    with open(rp, "w", encoding="utf-8") as f:
        f.write(m.R_PRE)
    pr = subprocess.run(["/bin/bash", rp, "", "none-sess", "nodir"], capture_output=True, timeout=10,
                        env={"HOME": tmp, "PATH": pathdir + ":/usr/bin:/bin", "FAKE_FREE": "41"})
    return pr.returncode, pr.stdout, pr.stderr.decode("utf-8", "replace")


def opened():
    return rt.read_rows("opened.tsv")


def seed_open(n):
    json.dump({"rows": [{"slug": "s%d" % i, "name": "byz-satnano-nano-s%d#0" % i, "run": "s%d" % i, "status": "OPEN",
                         "sock": "/tmp/s.sock", "opened_at": "t", "closed_at": "", "by": gate.MARK} for i in range(n)]},
              open(os.path.join(st, "roster.json"), "w"))  # noqa: SIM115


def c_cap():
    seed_open(3)
    calls = fake()
    rc, out = run("open", card("c.md"), "--run", "cap4")
    good = (rc == 8 and "상한 3 · 대기 1번째" in out and "명부 열림 3/3" in out and calls == []
            and len(rows()) == 3 and opened() == [] and fld(ledger()[-1])[1] == "reject" and fld(ledger()[-1])[6] == "cap")
    return good, "rc=%s calls=%d rows=%d out=%s" % (rc, len(calls), len(rows()), out.strip()[-160:])


def reset():
    for f in ("roster.json", "opened.tsv", "ledger.tsv"):
        try:
            os.remove(os.path.join(st, f))
        except FileNotFoundError:
            pass


def c_mem():
    res = []
    # ⓑ1 free 24% = 문이 아니라 경고 — WARN 1줄 + open 줄 free·warn 칸 + 열고 진행(rc0 · 명부 1행)
    reset()
    calls = fake("24")
    rc, out = run("open", card("m.md"), "--run", "mem24")
    lg, f = ledger(), (fld(ledger()[0]) if ledger() else [""] * 7)
    res.append(rc == 0 and calls[0] == m.R_PRE and "WARN mini free 24% < 25%" in out and "열고 진행" in out
               and len(rows()) == 1 and len(lg) == 1 and f[1] == "open" and f[4] == "24" and f[5] == "free<25")
    # ⓑ2 free 칸이 비었거나 글자 = 조용한 통과 0 — WARN 「측정 불가」 1줄 + 원장 free=? + 열고 진행
    for raw in ("", "abc"):
        reset()
        fake(raw)
        rc, out = run("open", card("m.md"), "--run", "memx")
        lg, f = ledger(), (fld(ledger()[0]) if ledger() else [""] * 7)
        res.append(rc == 0 and "WARN mini free 측정 불가" in out and "열고 진행" in out
                   and len(rows()) == 1 and len(lg) == 1 and f[4] == "?" and f[5] == "measure:parse")
    # ⓑ3 25% = 경고 0 · open 줄 1(warn 칸 빈칸)
    reset()
    fake("25")
    rc, out = run("open", card("m.md"), "--run", "mem25")
    lg = ledger()
    res.append(rc == 0 and "WARN" not in out and len(rows()) == 1 and len(lg) == 1
               and fld(lg[0])[4] == "25" and fld(lg[0])[5] == "")
    return all(res), "res=%s" % res


def c_name():
    calls = fake()
    rc, out = run("open", card("R949 My_Card.md"))
    nm = rows()[0]["name"] if rows() else ""
    lint = os.popen("bash %s/ft-name-lint.sh '%s'" % (bd, nm)).read().strip()
    res = [rc == 0, nm == "byz-satnano-nano-r949-my-card#0", lint == "PASS " + nm]
    for bad_name in ("sat-x#1", "Byz-satnano-nano-a#0", "other-tool-nano#0", "byz-satnano-nano-a#1e"):
        calls = fake()
        r2, o2 = run("open", card("n.md"), "--run", "nm", "--name", bad_name)
        res.append(r2 == 2 and calls == [] and "명부 규칙 밖" in o2)
    return all(res), "res=%s name=%s lint=%s" % (res, nm, lint)


def c_roster():
    fake()
    rc1, _ = run("open", card("d.md"), "--run", "dd")
    r = rows()
    first = (rc1 == 0 and len(r) == 1 and r[0]["status"] == "OPEN" and r[0]["slug"] == "dd"
             and r[0]["name"] == "byz-satnano-nano-dd#0" and r[0]["sock"] == "/tmp/s.sock"
             and r[0]["opened_at"] == os.environ["FT_NOW"] and r[0]["by"] == gate.MARK
             and len(ledger()) == 1 and fld(ledger()[0])[1] == "open")
    rc2, _ = run("close", "byz-satnano-nano-dd#0")
    r, lg = rows(), ledger()
    second = (rc2 == 0 and len(r) == 1 and r[0]["status"] == "CLOSED" and r[0]["closed_at"] == os.environ["FT_NOW"]
              and len(lg) == 2 and fld(lg[1])[1] == "close"
              and [fld(lg[1])[0], fld(lg[1])[2], fld(lg[1])[3], fld(lg[1])[6]]
              == [os.environ["FT_NOW"], "dd", "byz-satnano-nano-dd#0", "close mini:~/Project/satellite-nano/dd"])
    rc3, out = run("roster")
    third = rc3 == 0 and "명부 열림 0/3" in out and "byz-satnano-nano-dd#0\tCLOSED" in out
    return first and second and third, "first=%s second=%s third=%s lg=%s" % (first, second, third, lg)


def c_secret():
    res = []
    for body, kind in (("토큰 %s 로 올려라\n" % TOKEN, "token-prefix"), ("DSN=%s\n" % DSN, "url-cred"),
                       ("-----BEGIN RSA " + "PRIVATE KEY-----\nMIIx\n", "key-shape")):
        calls = fake()
        rc, out = run("open", card("s.md", body), "--run", "sec")
        lg = "\n".join(ledger())
        res.append(rc == 2 and calls == [] and rows() == [] and kind in lg.splitlines()[-1]
                   and TOKEN not in lg + out and DSN not in lg + out)
    fake()
    run("open", card("ok.md"), "--run", "sect")
    calls = fake()
    rc, out = run("task", "byz-satnano-nano-sect#0", card("t.md", "접속 %s\n" % DSN))
    lg = "\n".join(ledger())
    res.append(rc == 2 and m.R_SEND not in calls and calls == [] and "secret:url-cred" in lg and DSN not in lg + out)
    return all(res), "res=%s" % res


def c_secpos():
    """ⓘ — 공용 판정이 비밀로 보는 입력은 공백 앞·괄호 안 어느 자리에서도 원격 0 + 거절 줄.
    «한글 바로 뒤»(토큰은ghp_…)는 공용 판정이 못 보는 자리 = 별 카드 r977 범위라 여기서 단언하지 않는다(r949 r4)."""
    res = []
    toks = ("ghs_" + "a" * 36, "ghp_" + "b" * 36, "xoxb-" + "1" * 20, "sk-" + "c" * 24)
    for tk in toks:
        for w in ("앞 공백 %s 끝", "(%s)"):
            reset()
            calls = fake()
            rc, out = run("open", card("p.md", w % tk + "\n"), "--run", "pos")
            lg = "\n".join(ledger())
            res.append(rc == 2 and calls == [] and rows() == [] and "secret:" in lg and tk not in lg + out)
    return all(res), "res=%s" % res


def c_mtimeout():
    """ⓙ — 측정 대역이 자도 7초 상한을 먹지 않고(3초 상한) · 사전점검이 rc=124 로 와도 경고 + 진행."""
    res = []
    t0 = time.time()
    pr = subprocess.run(["/bin/bash", os.environ["RPRE_FILE"], "", "none-sess", "nodir"], capture_output=True, timeout=7,
                        env={"HOME": tmp, "PATH": os.environ["SLOW_DIR"] + ":/usr/bin:/bin", "FAKE_FREE": "41"})
    el = time.time() - t0
    raw = [ln for ln in pr.stdout.decode("utf-8", "replace").splitlines() if ln.startswith("free_raw=")]
    frc = [int(ln.split("=", 1)[1] or 0) for ln in pr.stdout.decode("utf-8", "replace").splitlines() if ln.startswith("free_rc=")]
    # 3초 상한(perl alarm)이 자는 대역을 잘랐다 = rc 124(SIGTERM) 또는 142(SIGALRM) — 어느 쪽이든 «0 이 아님» 이 사실이다
    res.append(pr.returncode == 0 and raw == ["free_raw="] and frc and frc[0] != 0 and el < 6.0)
    reset()
    calls = fake(rpre=(124, b"tmuxc=ok\npi=ok\nperl=ok\nsess_rc=1\ndir=absent\n", "시간 초과 7.0초"))
    rc, out = run("open", card("to.md"), "--run", "tmo")
    lg, f = ledger(), (fld(ledger()[0]) if ledger() else [""] * 7)
    res.append(rc == 0 and calls[0] == m.R_PRE and "WARN mini free 측정 불가(시간 초과)" in out
               and len(rows()) == 1 and len(lg) == 1 and f[4] == "?" and f[5] == "measure:timeout")
    return all(res), "res=%s raw=%s frc=%s el=%.1fs" % (res, raw, frc, el)


def c_measure():
    """ⓛ — 값은 (a) ssh rc0∧시간 안 (b) 측정 rc0 (c) 숫자 파싱 셋 다 맞을 때만 · 아니면 「측정 불가」 1줄 + free=? + 진행."""
    res = []
    # ① 셋 다 맞음 = 값 41 · WARN 0
    reset(); fake("41")
    rc, out = run("open", card("l.md"), "--run", "m1")
    f = fld(ledger()[0]) if ledger() else [""] * 7
    res.append(rc == 0 and "WARN" not in out and len(ledger()) == 1 and f[4] == "41" and f[5] == "")
    # ② 출력은 정상인데 측정 명령 exit 1 = 값으로 안 쓴다 — R_PRE 실스크립트 결과를 그대로 넣는다
    reset(); fake(rpre=real_pre(os.environ["FRC_DIR"]))
    rc, out = run("open", card("l.md"), "--run", "m2")
    f = fld(ledger()[0]) if ledger() else [""] * 7
    res.append(rc == 0 and "WARN mini free 측정 불가(rc 1)" in out and len(ledger()) == 1
               and f[4] == "?" and f[5] == "measure:rc1")
    # ③ 시간 초과 = ssh 7초 상한(rc124) 과 측정 3초 상한(rc124) 두 갈래
    for kw in ({"rpre": (124, b"tmuxc=ok\npi=ok\nperl=ok\nsess_rc=1\ndir=absent\n", "")}, {"free_rc": "124"}):
        reset(); fake("41", **kw)
        rc, out = run("open", card("l.md"), "--run", "m3")
        f = fld(ledger()[0]) if ledger() else [""] * 7
        res.append(rc == 0 and "측정 불가(시간 초과)" in out and len(ledger()) == 1
                   and f[4] == "?" and f[5] == "measure:timeout")
    return all(res), "res=%s" % res


def c_ledger():
    """ⓜ — 원장 줄 종류는 open·close·reject 셋뿐 · 열고 닫으면 정확히 2줄(경고가 있어도) · 거절 = reject 1 + open 0."""
    res = []
    # free=24 로 열고 닫기 → 2줄(open warn=free<25 · close) · 명부 CLOSED 1행
    reset(); fake("24")
    rc1, _ = run("open", card("g.md"), "--run", "gg")
    rc2, _ = run("close", "byz-satnano-nano-gg#0")
    lg = ledger()
    res.append(rc1 == 0 and rc2 == 0 and len(lg) == 2
               and [fld(x)[1] for x in lg] == ["open", "close"] and fld(lg[0])[5] == "free<25"
               and len(rows()) == 1 and rows()[0]["status"] == "CLOSED")
    # 정상 41% 로 열고 닫기 → 2줄
    reset(); fake("41")
    run("open", card("g.md"), "--run", "gh")
    run("close", "byz-satnano-nano-gh#0")
    lg = ledger()
    res.append(len(lg) == 2 and [fld(x)[1] for x in lg] == ["open", "close"])
    # 비밀 입력 거절 → reject 1줄 · open 0 · 명부 0행
    reset(); fake()
    rc, _ = run("open", card("s.md", "토큰 ghp_" + "b" * 36 + "\n"), "--run", "gs")
    lg = ledger()
    res.append(rc == 2 and len(lg) == 1 and fld(lg[0])[1] == "reject" and fld(lg[0])[6].startswith("secret:")
               and rows() == [])
    return all(res), "res=%s lg=%s" % (res, ledger())


def c_base_repro():
    """ⓝ — r1·r2 반례 중 «base 1545012e 의 공용 판정이 잡는 것» 은 그대로 잡힌다(lib 수정 0 의 결과)."""
    res = []
    for body in ("앞 공백 ghs_" + "a" * 36 + " 끝\n", "x-github_pat_" + "d" * 30 + "\n"):
        reset(); calls = fake()
        rc, out = run("open", card("b.md", body), "--run", "bp")
        lg = "\n".join(ledger())
        res.append(rc == 2 and calls == [] and rows() == [] and "reject" in lg and "secret:" in lg
                   and body.strip() not in lg + out)
    return all(res), "res=%s" % res


def c_mark():
    res = []
    with open(os.path.join(st, "opened.tsv"), "w") as f:
        f.write("byz-satnano-nano-u#0\tu\tProject/satellite-nano/u\tts\t$1\t100\t/home/x\t/tmp/s.sock\n")
    calls = fake()
    rc, out = run("close", "byz-satnano-nano-u#0")
    res.append(rc == 6 and calls == [] and len(opened()) == 1 and "표식" in out)
    json.dump({"rows": [{"slug": "u", "name": "byz-satnano-nano-u#0", "run": "u", "status": "OPEN", "by": "other-tool"}]},
              open(os.path.join(st, "roster.json"), "w"))  # noqa: SIM115
    rc, out = run("close", "byz-satnano-nano-u#0")
    res.append(rc == 6 and calls == [] and len(opened()) == 1)
    fake()
    run("open", card("k.md"), "--run", "kk")
    rc, _ = run("close", "byz-satnano-nano-kk#0")
    res.append(rc == 0)
    return all(res), "res=%s" % res


good, why = globals()["c_" + cell]()
print(("OK " if good else "NO ") + why.replace("\n", " | "))
PY

cell() { # cell <bin 폴더> <칸> → 0 = 통과
  local d="$T/st-$2-$RANDOM" o
  o="$(python3 "$T/cell.py" "$1" "$2" "$d" "$T" 2>&1 | tail -1)"; LAST="$o"
  case "$o" in "OK "*) return 0;; esac; return 1
}
check() { if cell "$BIN" "$2"; then ok "$1"; else bad "$1 — $LAST"; fi; }

# 공통 대역 — memory_pressure 세 종(정상 · exit 1 · 8초 자는 것) + R_PRE 실스크립트(ⓑ'·ⓙ·ⓛ② 공용)
#   frc = exit 1 대역 + 가짜 tmuxc·pi·tmux(세션 없음 rc1) — R_PRE 실스크립트가 사전점검을 끝까지 통과하게
mkdir -p "$T/fb" "$T/frc" "$T/slow"
printf '#!/bin/sh\necho "System-wide memory free percentage: ${FAKE_FREE}%%"\n' >"$T/fb/memory_pressure"; chmod 755 "$T/fb/memory_pressure"
printf '#!/bin/sh\necho "System-wide memory free percentage: 41%%"\nexit 1\n' >"$T/frc/memory_pressure"; chmod 755 "$T/frc/memory_pressure"
printf '#!/bin/sh\necho "no server running on /tmp/x" >&2\nexit 1\n' >"$T/frc/tmux"; chmod 755 "$T/frc/tmux"
printf '#!/bin/sh\nexit 0\n' >"$T/frc/tmuxc"; chmod 755 "$T/frc/tmuxc"; cp "$T/frc/tmuxc" "$T/frc/pi"
printf '#!/bin/sh\nsleep 8\necho "System-wide memory free percentage: 41%%"\n' >"$T/slow/memory_pressure"; chmod 755 "$T/slow/memory_pressure"
python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import ft_sat_nano as m; print(m.R_PRE)' "$BIN" >"$T/rpre.sh"
export RPRE_FILE="$T/rpre.sh" SLOW_DIR="$T/slow" FRC_DIR="$T/frc"

check "ⓐ 명부 OPEN 3 → 4번째 open rc8 «상한 3 · 대기 1번째» · 판 출력 · 원격 0 · 명부 행 0 · 원장 reject(cap)" cap
check "ⓑ free 24% → WARN 1줄 + 열고 진행(rc0) · open 줄 free=24 warn=free<25 · 빈칸·글자 → 「측정 불가(파싱)」 + free=? · 25% = 경고 0" mem
check "ⓒ 이름 자동 byz-satnano-nano-<slug>#0 · ft-name-lint PASS · --name lint 불통 4종 rc2 원격 0" name
check "ⓓ open → 명부 OPEN 1행 + 원장 open 1줄 · close → CLOSED + close 1줄 · roster 표" roster
check "ⓔ 카드 토큰·DSN·키 / task DSN → rc2 · 원격 0 · 원장 = 종류만(값 0)" secret
check "ⓕ 명부 표식 없음·남의 표식 → close rc6 · 원격 0 · 기록 유지 · 표식 있는 줄은 rc0" mark
check "ⓘ ghs_/ghp_/xoxb-/sk- 더미 × (공백 앞 · 괄호 안) → rc2 · 원격 0 · 원장 종류만(한글 바로 뒤 = r977 범위라 뺀다)" secpos
check "ⓙ 측정 대역 8초 → 3초 상한에서 잘려 free_raw 빈칸·free_rc=124(7초 상한 소모 0) · rc=124 사전점검 → WARN 「측정 불가(시간 초과)」+ free=? + 열고 진행" mtimeout
check "ⓛ ssh rc0∧시간 안 + 측정 rc0 + 숫자 셋 다일 때만 값(41) · exit 1 → 「측정 불가(rc 1)」+ free=? · 시간 초과 두 갈래 → 「측정 불가(시간 초과)」" measure
check "ⓜ 원장 = open 1 + close 1(경고 있어도 2줄) · 정상도 2줄 · 비밀 거절 = reject 1 + open 0 · 명부 CLOSED 1행" ledger
check "ⓝ base 1545012e 가 잡던 반례(ghs_ 공백 앞 · -github_pat_ 하이픈 뒤) → rc2 · 원격 0 · 거절 줄" base_repro

# ⓑ' R_PRE 실스크립트의 free_raw·free_rc 칸 — 이 맥 bash + memory_pressure 대역(24% · 없음 · exit 1)
pre_free() {
  HOME="$T" PATH="$1" FAKE_FREE=24 /bin/bash "$T/rpre.sh" "" none-sess nodir 2>/dev/null | sed -n 's/^free_raw=//p'; }
pre_rc() {
  HOME="$T" PATH="$1" /bin/bash "$T/rpre.sh" "" none-sess nodir 2>/dev/null | sed -n 's/^free_rc=//p'; }
mkdir -p "$T/nb"; ln -s "$(command -v sed)" "$T/nb/sed"   # 도구 없음 = sed 만 있는 PATH
f1="$(pre_free "$T/fb:/usr/bin:/bin")"; f2="$(pre_free "$T/nb")"; f2x="$(HOME="$T" PATH="$T/nb" /bin/bash "$T/rpre.sh" "" a b 2>/dev/null | grep -c '^free_raw=$')"
r1="$(pre_rc "$T/frc:/usr/bin:/bin")"
[ "$f1" = 24 ] && [ -z "$f2" ] && [ "$f2x" = 1 ] && [ "$r1" = 1 ] \
  && ok "ⓑ' R_PRE 실스크립트: 대역 24% → free_raw 24 · 도구 없음 → 빈칸 · exit 1 → free_rc=1(값으로 안 쓴다)" \
  || bad "ⓑ' free_raw='$f1' / 없음='$f2' / exit1 rc='$r1'"

# ⓖ 기존 시험
for t in test_sat_nano_r902.sh test_satellite_rosters.sh; do
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u FT_NOW /bin/bash "$HARNESS/tests/$t" >"$T/g-$t.log" 2>&1; o="$(tail -1 "$T/g-$t.log")"
  [ "$o" = "ALL PASS" ] && ok "ⓖ $t ALL PASS (/bin/bash $BASH_VERSION)" || bad "ⓖ $t: $o — $(grep '^FAIL' "$T/g-$t.log" | head -3 | tr '\n' ' ')"
done

# ⓗ 변이 — 검사를 끈 사본에서 «그 칸»이 빨강이어야 한다
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
mut() { mutf "$1" ft_sat_gate.py "$2" "$3"; }
mutg() { mutf "$1" ft_sat_gate.py "$(printf '%b' "$2")" "$(printf '%b' "$3")"; }
mcheck() { # mcheck <변이 이름> <칸> <사본>
  [ -n "$3" ] || { bad "ⓗ 변이 $1 사본이 안 만들어졌다"; return; }
  if cell "$3" "$2"; then bad "ⓗ 변이 $1 → 칸 $2 가 안 빨갛다(시험이 헛돈다)"; else ok "ⓗ 변이 $1 → 칸 $2 빨강 = 감지"; fi
}
mcheck "상한 검사 끔" cap "$(mut cap '    if n >= mx:' '    if False:')"
mcheck "WARN 줄 끔" mem "$(mut free '    if v < lo:' '    if False:')"
mcheck "비밀 검사 끔" secret "$(mut sec '    if kinds:' '    if False:')"
mcheck "표식 검사 끔" mark "$(mut mark '    if r is None or r.get("by") != MARK:' '    if False:')"
mcheck "공용 SECRET_SHAPE 끔" secpos "$(mut sec2 '    if SECRET_SHAPE.search(text):' '    if False:')"
mcheck "원장 경고를 독립 줄로 되살림" ledger "$(mutg warnline '    if v < lo:\n        say(f"  WARN mini free {v}% < {lo}% — 열고 진행")' '    if v < lo:\n        say(f"  WARN mini free {v}% < {lo}% — 열고 진행")\n        ledger_add("warn-free", slug_, name, str(v), "", "-")')"
mcheck "측정 rc 버림(free_rc=0 고정)" measure "$(mutf mrc ft_sat_nano.py 'echo "free_rc=$mrc"' 'echo "free_rc=0"')"
mcheck "ssh 시간 초과 갈래 끝" mtimeout "$(mutg sstmo '    if ssh_rc != "0":' '    if False:')"

# ⓚ 공용 lib 미수정 — base 1545012e 대비 5사본 diff 0줄 + 공용 시험 전건 PASS
LIBS="feature-pack/fable-team/harness/bin/ft_secret_shapes.py feature-pack/fable-team/harness/kit/fable-team/bin/ft_secret_shapes.py feature-pack/fable-team/harness/kit/fable-team/templates/hooks/ft_secret_shapes.py feature-pack/fable-team/harness/bin/autonomy_scope_secret.py feature-pack/fable-team/harness/kit/fable-team/bin/autonomy_scope_secret.py"
nd="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$HARNESS" diff 1545012e HEAD --stat -- $LIBS 2>/dev/null | wc -l | tr -d ' ')"
[ "$nd" = 0 ] && ok "ⓚ 공용 비밀 lib 5사본 base 1545012e 대비 diff 0줄" || bad "ⓚ 공용 lib 가 base 와 다르다(diff $nd줄) — 별 카드 r977 범위"
PYT=""
for p in python3.11 python3.12 python3.13 python3; do
  command -v "$p" >/dev/null 2>&1 && "$p" -c 'import pytest' >/dev/null 2>&1 && { PYT="$p"; break; }
done
if [ -n "$PYT" ]; then
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE "$PYT" -m pytest -q "$HARNESS/tests/scripts/test_ft_secret_shapes.py" >"$T/pytest.log" 2>&1 \
    && ok "ⓚ test_ft_secret_shapes.py 전건 PASS ($(tail -1 "$T/pytest.log"))" \
    || bad "ⓚ test_ft_secret_shapes.py: $(tail -3 "$T/pytest.log" | tr '\n' ' ')"
else
  ok "ⓚ test_ft_secret_shapes.py — 이 맥에 pytest 없음(건너뜀 · 사본 동일는 위 diff 0줄로 갈음)"
fi

# 정적 — 짝 사본 cmp0 · bash 3.2 문법
for f in ft_sat_nano.py ft_sat_gate.py ft_sat_rt.py ft-sat-nano.sh; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "정적 kit 사본 cmp0 $f" || bad "정적 kit 사본 불일치 $f"
done
/bin/bash -n "$0" && ok "정적 /bin/bash -n" || bad "정적 /bin/bash -n"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
