"""r623 r5 라이브 5칸 게이트 (판정 2513) — 격리 redis 에서만 실측.

격리 서버 = BYZ `tests/gateway/_loom_mirror_fixtures.py::isolated_redis_server` 와 같은 꼴:
이 스크립트가 직접 띄운 redis-server · 포트 38301~38399 · `--save ''` `--appendonly no` · INFO process_id == 자기 pid 확인 · 끝에 자기 프로세스만 내림.
dev·운영 redis 0 · 실제 docker·1Password 0(준비 도구의 docker/op 는 이 격리 서버로 보내는 얇은 가짜).

쓰는 법: /usr/bin/python3 live-gate-r5.py <팩 harness 폴더> <결과 파일>
"""
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import time

HARNESS, OUT = sys.argv[1], sys.argv[2]
KEEP = os.path.join(os.path.dirname(os.path.abspath(OUT)), "live-r6")   # e' trace·ps 원문 보존 폴더(결과 파일 옆)
KIT = os.path.join(HARNESS, "kit", "fable-team", "bin")
HOOK = os.path.join(HARNESS, "kit", "fable-team", "templates", "hooks", "block-destructive.sh")
CLI = "/opt/homebrew/bin/redis-cli"
SERVER = shutil.which("redis-server")
PW = "R623live" + secrets.token_hex(12)          # 이 회차만의 비번 — 노출 검사 글자
T = tempfile.mkdtemp(prefix="r623-live-")
lines, cells = [], {}


def say(s=""):
    lines.append(s)
    sys.stderr.write(s.replace(PW, "<비번>") + "\n"); sys.stderr.flush()   # 진행 표시(비번 글자 0)


def sh(args, data=None, env=None):
    p = subprocess.run(args, input=data, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")


def start_server():
    for port in list(range(38301, 38400))[os.getpid() % 99:] + list(range(38301, 38400))[:os.getpid() % 99]:
        proc = subprocess.Popen([SERVER, "--port", str(port), "--bind", "127.0.0.1", "--save", "", "--appendonly", "no"],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(50):
            if proc.poll() is not None:
                break
            rc, out, _ = sh([CLI, "-p", str(port), "INFO", "server"])
            if rc == 0 and "process_id:%d" % proc.pid in out:
                return proc, port
            time.sleep(0.1)
        if proc.poll() is None:
            proc.terminate(); proc.wait(5)
    raise RuntimeError("격리 redis 포트 확보 실패")


def admin(port, *cmd):
    return sh([CLI, "-p", str(port)] + list(cmd))[1].strip()


def tool(port, batch, passfile, extra=(), wrapper_env=None):
    """main() 경로 주입(본체 그대로 · 고정 경로만 바꿈) 또는 래퍼 실행."""
    log = os.path.join(T, "redis-read.log")
    drv = ("import sys; sys.path.insert(0, %r); import ft_redis_read as m; "
           "sys.exit(m.main(sys.argv[1:], hook=%r, log=%r, passfile=%r, cli_candidates=(%r,)))" % (KIT, HOOK, log, passfile, CLI))
    return sh(["/usr/bin/python3", "-c", drv] + list(extra) + ["-p", str(port), batch])


def stat(port, name):
    for ln in admin(port, "INFO", "commandstats").splitlines():
        if ln.startswith("cmdstat_%s:" % name):
            return ln
    return "cmdstat_%s 없음" % name


proc, port = start_server()
try:
    say("# r623 r5 라이브 5칸 게이트 — 격리 redis-server %s · 127.0.0.1:%d · pid %d · 저장 끔" % (admin(port, "INFO", "server").split("redis_version:")[1].split()[0], port, proc.pid))
    say("# 회차 시각 %s · 비번 = 이 회차 무작위(글자 노출 검사용 · 여기 적지 않음)" % time.strftime("%Y-%m-%dT%H:%M:%S"))
    # 준비 = 진짜 준비 도구 ensure(가짜 docker → 이 격리 서버 · 가짜 op → 이 회차 비번) · bash -x 와 SHELLOPTS=xtrace 로 로그 남김
    fb = os.path.join(T, "fb"); os.makedirs(fb)
    with open(os.path.join(fb, "docker"), "w") as f:
        f.write("#!/bin/bash\n[ \"$1\" = inspect ] && { echo true; exit 0; }\nexec %s -p %d\n" % (CLI, port))
    with open(os.path.join(fb, "op"), "w") as f:
        f.write("#!/bin/bash\n[ \"$1\" = read ] && { echo %s; exit 0; }\nexit 0\n" % PW)
    for b in ("docker", "op"):
        os.chmod(os.path.join(fb, b), 0o755)
    good = os.path.join(T, "good.pass")
    penv = dict(os.environ, PATH=fb + ":" + os.environ["PATH"], OP_SERVICE_ACCOUNT_TOKEN_DEVELOP="dev-tok")
    usersh = os.path.join(KIT, "ft-redis-readonly-user.sh")
    uargs = [usersh, "ensure", "--container", "iso", "--pass-file", good, "--hook", HOOK]
    # 공식 꼴(r6) = env -i … /bin/bash -p — 이 스크립트를 BASH_ENV 를 심은 셸에서 돌려도 env -i 가 비운다
    official = ["/usr/bin/env", "-i", "PATH=%s:/usr/bin:/bin" % fb, "HOME=" + os.path.expanduser("~"), "OP_SERVICE_ACCOUNT_TOKEN_DEVELOP=dev-tok"]
    ps_samples = []
    p = subprocess.Popen(official + ["/bin/bash", "-p", "-x"] + uargs, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    while p.poll() is None:
        ps_samples.append(sh(["/bin/ps", "-ww", "-eo", "pid,command"])[1]); time.sleep(0.02)
    ens1 = p.stdout.read().decode(); rc1 = p.returncode
    rc2, ens2, ens2e = sh(official + ["SHELLOPTS=xtrace", "/bin/bash", "-p"] + uargs)
    say("## 준비(진짜 ensure → 격리 서버 · 공식 꼴 env -i … /bin/bash -p) rc=%d(-x) · rc=%d(SHELLOPTS=xtrace) · 부모 셸 BASH_ENV=%s"
        % (rc1, rc2, os.environ.get("BASH_ENV", "없음")))
    acl = [x for x in admin(port, "ACL", "LIST").splitlines() if "ft-readonly" in x][0]
    say("  ACL LIST 원문(비번 해시 가림): " + " ".join("#<해시>" if w.startswith("#") else w for w in acl.split()))
    for ln in (ens2 + ens2e).splitlines():
        if ln.startswith(("확인 원문", "OK ")):
            say("  " + ln.replace(PW, "<비번>"))
    for i in range(3):
        admin(port, "HSET", "room:x", "f%d" % i, "v%d" % i)      # 격리 서버 씨앗 데이터
    batch = os.path.join(T, "batch.txt")
    with open(batch, "w") as f:
        f.write("".join("HSTRLEN room:x f%d\n" % i for i in range(3)))
    outs = []

    # a — 틀린 비번(서버엔 ft-readonly 있음) + 기본 사용자 on nopass
    bad = os.path.join(T, "bad.pass")
    with open(bad, "w") as f:
        f.write("WrongPass0000000000\n")
    admin(port, "CONFIG", "RESETSTAT")
    rc, o, e = tool(port, batch, bad); outs += [o, e]
    hs = stat(port, "hstrlen")
    cells["a"] = rc != 0 and "없음" in hs
    say("## a 틀린 비번 + 기본 사용자 nopass → rc=%d · 서버 %s · %s" % (rc, hs, "PASS" if cells["a"] else "FAIL"))
    say("  기본 사용자: " + [x for x in admin(port, "ACL", "LIST").splitlines() if x.startswith("user default")][0])
    say("  도구 출력: " + (o + e).strip().replace("\n", " ⏎ ")[:300])

    # b — PATH 없는 셸 + 가짜 dirname·python3 를 PATH 앞에 · 래퍼로 정상 실행
    wb = os.path.join(T, "wb"); os.makedirs(wb)
    shutil.copy2(os.path.join(KIT, "ft-redis-read.sh"), wb)
    src = open(os.path.join(KIT, "ft_redis_read.py"), encoding="utf-8").read()
    src = src.replace('HOOK = os.path.join(HOME, ".claude", "hooks", "block-destructive.sh")', "HOOK = %r" % HOOK, 1)
    src = src.replace('LOG = os.path.join(HOME, ".claude", "logs", "redis-read.log")', "LOG = %r" % os.path.join(T, "redis-read.log"), 1)
    src = src.replace('PASSFILE = os.path.join(HOME, ".config", "ft", "redis-readonly.pass")', "PASSFILE = %r" % good, 1)
    with open(os.path.join(wb, "ft_redis_read.py"), "w", encoding="utf-8") as f:
        f.write(src)
    fx = os.path.join(T, "fx"); os.makedirs(fx)
    for b in ("dirname", "python3", "cd", "pwd"):
        with open(os.path.join(fx, b), "w") as f:
            f.write("#!/bin/sh\ntouch %s/hit-%s\nexit 0\n" % (T, b))
        os.chmod(os.path.join(fx, b), 0o755)
    admin(port, "CONFIG", "RESETSTAT")
    rc, o, e = sh(["/usr/bin/env", "-i", "/bin/bash", "-c", "PATH=%s /bin/bash %s/ft-redis-read.sh -p %d %s" % (fx, wb, port, batch)]); outs += [o, e]
    hits = [x for x in os.listdir(T) if x.startswith("hit-")]
    hs = stat(port, "hstrlen")
    cells["b"] = rc == 0 and "calls=3" in hs and not hits and o.split() == ["(integer)", "2"] * 3
    say("## b env -i · PATH=가짜(dirname·python3·cd·pwd) · 래퍼 실행 → rc=%d · 서버 %s · 가짜 호출 %s · %s" % (rc, hs, hits or 0, "PASS" if cells["b"] else "FAIL"))
    say("  출력: " + o.strip().replace("\n", " ⏎ ") + " · stderr: " + e.strip().replace(PW, "<비번>")[:200])
    say("  (래퍼 사본 = 진짜 래퍼 그대로 · 본체 사본은 고정 경로 3줄(HOOK·LOG·PASSFILE)만 시험 값으로 — 실 홈 비번 파일 없음)")

    # c — -n 999 (없는 DB)
    admin(port, "CONFIG", "RESETSTAT")
    rc, o, e = tool(port, batch, good, extra=["-n", "999"]); outs += [o, e]
    hs = stat(port, "hstrlen")
    cells["c"] = rc == 3 and "없음" in hs and "failed: ERR" in e
    say("## c -n 999 → rc=%d · 서버 %s · %s" % (rc, hs, "PASS" if cells["c"] else "FAIL"))
    say("  도구 출력: " + (o + e).strip().replace("\n", " ⏎ ")[:300])

    # d — ft-readonly 로 쓰기 5종을 클라이언트로 직접(도구 빠른 거절 우회)
    env_ro = {"PATH": "/usr/bin:/bin", "REDISCLI_AUTH": PW}
    before = (admin(port, "GET", "k"), admin(port, "HGET", "room:x", "f0"), admin(port, "EXISTS", "room:x"),
              admin(port, "GET", "k2"), admin(port, "CONFIG", "GET", "maxmemory").replace("\n", " "))
    writes = [("값", ["SET", "k", "hacked"]), ("해시", ["HSET", "room:x", "f0", "hacked"]), ("삭제", ["DEL", "room:x"]),
              ("스크립트", ["EVAL", "redis.call('set','k2','x') return 1", "0"]), ("설정", ["CONFIG", "SET", "maxmemory", "1"])]
    nope = 0
    for kind, cmd in writes:
        rc, o, e = sh([CLI, "-p", str(port), "--user", "ft-readonly", "--no-raw"] + cmd, env=env_ro); outs += [o, e]
        nope += "NOPERM" in o
        say("  d %s %s → %s" % (kind, cmd[0], o.strip()))
    after = (admin(port, "GET", "k"), admin(port, "HGET", "room:x", "f0"), admin(port, "EXISTS", "room:x"),
             admin(port, "GET", "k2"), admin(port, "CONFIG", "GET", "maxmemory").replace("\n", " "))
    cells["d"] = nope == 5 and before == after
    say("## d 쓰기 5종 직접 → NOPERM %d/5 · 값 전 %s == 후 %s · %s" % (nope, before, after, "PASS" if cells["d"] else "FAIL"))

    # e — 비번 글자 노출: 도구·준비 도구 출력 · 원장 · ps -ww 표본 · xtrace 로그
    big = os.path.join(T, "big.txt")
    with open(big, "w") as f:
        f.write("HSTRLEN room:x f0\n" * 9000)
    p = subprocess.Popen(["/usr/bin/python3", "-c", "import sys; sys.path.insert(0, %r); import ft_redis_read as m; "
                          "sys.exit(m.main(sys.argv[1:], hook=%r, log=%r, passfile=%r, cli_candidates=(%r,)))"
                          % (KIT, HOOK, os.path.join(T, "redis-read.log"), good, CLI), "-p", str(port), big],
                         stdout=open(os.path.join(T, "e.out"), "wb"), stderr=open(os.path.join(T, "e.err"), "wb"))
    n0 = len(ps_samples)
    while p.poll() is None:                       # 출력은 파일로(파이프가 차서 멈추지 않게)
        ps_samples.append(sh(["/bin/ps", "-ww", "-eo", "pid,command"])[1]); time.sleep(0.01)
    outs += [open(os.path.join(T, x), encoding="utf-8", errors="replace").read() for x in ("e.out", "e.err")]
    seen_cli = sum("redis-cli" in s and "ft-readonly" in s for s in ps_samples[n0:])
    log_txt = open(os.path.join(T, "redis-read.log")).read()
    places = {"도구 출력": "".join(outs), "준비 도구 bash -x 로그": ens1, "준비 도구 SHELLOPTS=xtrace 로그": ens2 + ens2e,
              "원장": log_txt, "ps -ww 표본 %d개" % len(ps_samples): "".join(ps_samples)}
    leak = {k: v.count(PW) for k, v in places.items()}
    xt = "+ set +o xtrace" in ens1      # -x 로 켜진 채 시작했음(SHELLOPTS=xtrace 는 -p 가 무시 — ens2 는 trace 0 이 정상)
    cells["e"] = sum(leak.values()) == 0 and xt and seen_cli > 0 and p.returncode == 0
    say("## e 비번 글자 수 %s · xtrace 켜진 채 시작 확인=%s · 실행 중 ps 에 redis-cli(ft-readonly) 잡힌 표본 %d · 9000줄 rc=%d · %s"
        % (leak, xt, seen_cli, p.returncode, "PASS" if cells["e"] else "FAIL"))
    say("  ps 표본 예: " + next((x.strip() for s in ps_samples[n0:] for x in s.splitlines() if "redis-cli" in x and "ft-readonly" in x), "-")[:200])

    # e' — BASH_ENV 의 DEBUG trap(비번 대입 직전 xtrace 재점화 · DA⑥ r5 재현 꼴 그대로)
    bashenv = os.path.join(T, "bashenv")
    with open(bashenv, "w") as f:
        f.write("trap 'case \"$BASH_COMMAND\" in pw=*) set -x;; esac' DEBUG\n")
    say("## e' BASH_ENV 파일 원문: " + open(bashenv).read().strip())
    benv = dict(penv, BASH_ENV=bashenv)
    ep = {}
    ps0 = len(ps_samples)

    def watched(args, env):
        q = subprocess.Popen(args, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        while q.poll() is None:
            ps_samples.append(sh(["/bin/ps", "-ww", "-eo", "pid,command"])[1]); time.sleep(0.02)
        return q.returncode, q.stdout.read().decode("utf-8", "replace")
    ep["i 그냥 bash(BASH_ENV 심음)"] = watched(["bash"] + uargs, benv)
    ep["ii bash -p 인데 BASH_ENV 남음"] = watched(["/bin/bash", "-p"] + uargs, benv)
    ep["iii 공식 꼴(부모 셸 BASH_ENV 심음)"] = watched(official + ["/bin/bash", "-p"] + uargs, benv)
    want = {"i": 2, "ii": 2, "iii": 0}
    ok_ep = True
    os.makedirs(KEEP, exist_ok=True)
    for k, (rc, txt) in ep.items():
        tag = k.split()[0]
        path = os.path.join(KEEP, "eprime-%s.log" % tag)
        with open(path, "w", encoding="utf-8") as f:       # trace 파일 보존(비번 글자가 있으면 그대로 남는다 — 아래 grep 원문이 판정)
            f.write(txt)
        n = txt.count(PW)
        traced = sum(1 for x in txt.splitlines() if x.startswith("+"))
        good_k = rc == want[tag] and n == 0 and (tag != "iii" or ("OK ft-redis-readonly-user" in txt and traced == 0))
        ok_ep &= good_k
        say("  e' %s → rc=%d(기대 %d) · grep -c <비번> %s = %d · trace 줄 %d · %s" % (k, rc, want[tag], os.path.basename(path), n, traced, "PASS" if good_k else "FAIL"))
        say("     첫 줄: " + (txt.strip().splitlines() or ["-"])[0].replace(PW, "<비번>")[:220])
    pslines = [x.strip() for s in ps_samples[ps0:] for x in s.splitlines() if "readonly-user" in x or "redis-cli" in x]
    with open(os.path.join(KEEP, "eprime-ps.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(pslines) + "\n")
    nps = sum(x.count(PW) for x in pslines)
    cells["e'"] = ok_ep and nps == 0
    say("## e' BASH_ENV DEBUG trap → %s · ps 표본 %d개 중 도구 줄 %d (eprime-ps.txt) · grep -c <비번> = %d" % ("PASS" if cells["e'"] else "FAIL", len(ps_samples) - ps0, len(pslines), nps))
finally:
    proc.terminate(); proc.wait(5)
    say("# 격리 서버 내림: pid %d exit %s" % (proc.pid, proc.returncode))
    shutil.rmtree(T, ignore_errors=True)

ok = sum(cells.values())
say("")
say("| 칸 | 무엇 | 결과 |")
say("|---|---|---|")
for k, what in [("a", "틀린 비번 + 기본 사용자 nopass → 묶음 0 · rc≠0"), ("b", "PATH 없는 셸 · 가짜 dirname/python3 → 정상 · 교체 0"),
                ("c", "-n 999 → rc3 · 묶음 0"), ("d", "쓰기 5종 직접 → 서버 NOPERM · 값 변화 0"), ("e", "출력·원장·ps·xtrace 비번 0"),
                ("e'", "BASH_ENV DEBUG trap 심은 셸 → 직접 호출 rc2 · 공식 꼴 rc0 · 비번 0")]:
    say("| %s | %s | %s |" % (k, what, "PASS" if cells.get(k) else "FAIL"))
say("RESULT %d/6" % ok)
with open(OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print("\n".join(lines))
sys.exit(0 if ok == 6 else 1)
