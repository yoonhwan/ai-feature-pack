"""ft_key_rotate_bundle.py — 묶음 단위 교체 흐름 (R206c): 시도 열기 · 단계 진행(불명이면 정지) · 재개 · 중단 · 옛 키 단계 · 끝 판정.
단계 부품(의도→호출→조회 확인 · plan · 외부 단계)은 ft_key_rotate_steps.py · 기록은 ft_key_rotate_journal.py. 값은 stdin·메모리로만."""

import re

import ft_key_rotate_io as fio
import ft_key_rotate_journal as jr
from ft_key_rotate_journal import DEAD_EVID, NOT_RUN, OK, UNCONFIRMED, UNKNOWN
from ft_key_rotate_lines import read_value, swap_line
from ft_key_rotate_steps import RES_OF, VAULT, ext_step, fields, local_step, run_step, vault_step, verify_step
from ft_key_rotate_table import KEYS

DONE = jr.CLOSED + (UNCONFIRMED,)


def opt(rest, name, flag=False):
    """rest 에서 --name [값] 을 빼서 값(flag 면 bool)을 돌려준다."""
    if name not in rest:
        return False if flag else None
    i = rest.index(name)
    if not flag and i + 1 >= len(rest):
        raise ValueError("%s 값 없음" % name)
    v = True if flag else rest[i + 1]
    del rest[i : i + (1 if flag else 2)]
    return v


def order(b, names):
    op = ["vault", "consumers"] if b in VAULT else []
    ext = [n for n in names if not (b in VAULT and n == "consumers")]
    return ["local:%s" % k for k in fields(b)] + ext + ["verify"] + op + ["old-key"]


def journal_plan(es):
    p = [e for e in es if e["phase"] == "plan"]
    return [] if not p or p[0].get("detail") == "-" else p[0]["detail"].split(",")


def begin(key, plan, allow_open):
    """시도 열기 -> (묶음, 시도 번호, 새 시도?). 같은 묶음의 열린 시도·다른 묶음의 열린 시도를 거절한다(다른 묶음은 안전한 중단 확인 또는 범위 값 1줄일 때만)."""
    b = KEYS[key][3]
    att, es = jr.current(b)
    st, names = jr.summarize(es), [s["name"] for s in plan]
    if jr.is_open(st):
        if not st.startswith("진행") or jr.last(es, "local:%s" % key) or journal_plan(es) != names:
            raise ValueError("%s 열린 시도(%s) — --resume %s 또는 --abandon %s" % (b, st, b, b))
        return b, att, False
    for o in (x for x in jr.bundles() if x != b):
        oes = jr.current(o)[1]
        if jr.blocks_others(oes, all((jr.last(oes, "local:%s" % k) or {}).get("res") == OK for k in fields(o))):
            if not allow_open:
                raise ValueError('%s 열린 시도(%s) — 먼저 끝내거나 --abandon(운영 반영 0 확인) · 범위 허용 = --allow-open "<planner 범위 1줄>"' % (o, jr.summarize(oes)))
            jr.append(b, att=att + 1, phase="note", detail="범위 허용 " + allow_open)
    jr.append(b, att=att + 1, phase="plan", detail=",".join(names) or "-")
    return b, att + 1, True


def mark_dead_old(b, att, key, chk):
    """새 시도 시작 때 옛 키가 이미 401·403 이면 증거(코드·시각)만 기록 — 폐기 확정이 아니라 «이미 폐기(증거)» 로 옛 키 단계를 따로 닫는다."""
    if len(fields(b)) != 1 or b in VAULT:
        return
    st, label = chk(key, "now", False)
    m = re.search(r"http=(401|403)", label)
    if st == "DEAD" and m:
        jr.append(b, att=att, step="old-key", phase="result", res=DEAD_EVID, detail="http=%s t=%s" % (m.group(1), jr.now()))


def rotate_local(b, att, key, files, edits, new, box):
    """로컬 교체 단계 — 실패는 원래 REJECT 문구 그대로 올린다. 변경 0(롤백)이고 이 시도에 다른 로컬 완료가 없으면 시도를 닫는다."""
    call, probe, _ = local_step(key, files, edits, {key: new}, box)
    res = run_step(b, att, "local:%s" % key, call, probe, fpv=jr.fp(new))
    if res == OK:
        return
    if res == NOT_RUN and not any((jr.last(jr.current(b)[1], "local:%s" % k) or {}).get("res") == OK for k in fields(b)):
        jr.append(b, att=att, phase="end", res="롤백(변경 0)")
    raise box.get("err") or RuntimeError("로컬 교체 결과 %s — --resume %s" % (res, b))


def values_of(b, es):
    """신뢰 저장소(로컬 활성 줄)에서 지문이 기록과 같은 값만 메모리로 — 완료 단계의 줄이 바뀌었으면 REJECT(조용히 다른 값 0)."""
    vals = {}
    for k in fields(b):
        intent, done = jr.last(es, "local:%s" % k, "intent"), jr.step_state(es, "local:%s" % k)
        if not intent or not done or done["res"] not in (OK, UNKNOWN):
            continue
        cur = read_value(fio.file_paths(KEYS[k][0])[0], k)
        if cur is not None and jr.fp(cur) == intent.get("fp"):
            vals[k] = cur
        elif done["res"] == OK:
            raise ValueError("%s 활성 줄 지문이 기록과 다름 — 조용히 다른 값 0" % k)
    return vals


def _handler(n, b, vals, specs, chk, paid, box):
    if n.startswith("local:"):
        k = n[6:]
        files = fio.file_paths(KEYS[k][0])
        return local_step(k, files, [(p, swap_line(p, k, vals[k])) for p in files], vals, box)
    if n == "verify":
        return verify_step(b, chk, paid, box)
    return vault_step(b, vals) if n == "vault" else ext_step(b, specs[n], vals)


def drive(b, att, vals, plan, chk, paid, say, box):
    """필수 단계를 순서대로 — 닫힌 단계는 건너뛰고 불명은 조회로 먼저 확정한다. 닫히지 않은 단계에서 멈춘다(다음 단계 0). -> ok | wait | value | 불명 | 미실행."""
    specs = {s["name"]: s for s in plan}
    for n in order(b, [s["name"] for s in plan]):
        es = jr.current(b)[1]
        last = jr.step_state(es, n)
        if n == "old-key":
            break
        if last and last["res"] in DONE:
            continue
        if n.startswith("local:") and n[6:] not in vals:
            return "value" if jr.last(es, n, "intent") else "wait"
        if n == "consumers" and n not in specs:
            jr.append(b, att=att, step=n, phase="result", res=UNCONFIRMED, detail="소비자 확인 plan 없음")
            say("STEP consumers %s" % UNCONFIRMED)
            continue
        call, probe, ops = _handler(n, b, vals, specs, chk, paid, box)
        if last and last["res"] == UNKNOWN:
            st, i, v, _d = probe()
            if st == "unknown":
                say("STEP %s 불명 — 조회로 확정 못 함(다음 단계 0)" % n)
                return UNKNOWN
            jr.append(b, att=att, step=n, phase="result", res=RES_OF[st], id=i, after=v, detail="확정=조회", ops="1" if ops else None)
            say("STEP %s %s (확정=조회)" % (n, RES_OF[st]))
            if st == "present":
                continue
        res = run_step(b, att, n, call, probe, ops, pre=n not in ("verify", "vault"), fpv=jr.fp(vals[n[6:]]) if n.startswith("local:") else None)
        say("STEP %s %s" % (n, res))
        if res not in DONE:
            return res
    return "ok"


def maybe_end(b, att):
    es = jr.current(b)[1]
    names = order(b, journal_plan(es))
    last = [jr.step_state(es, n) for n in names]
    if any(e is None or e["res"] not in DONE for e in last):
        return
    un = [n for n, e in zip(names, last) if e["res"] == UNCONFIRMED]
    jr.append(b, att=att, phase="end", res=("미확인(%s)" % ",".join(un).replace("consumers", "소비자")) if un else OK)


def record_old_key(b, st, label):
    """check-old 결과 기록 — DEAD 는 증거만(401·403 · op rc) · SKIP/UNVERIFIED/그 밖 DEAD 는 미확인 · 살아 있음·확인 실패는 메모만."""
    att, es = jr.current(b)
    if not jr.summarize(es).startswith("진행"):
        return
    m = re.search(r"(http|rc)=(\d+)", label)
    code = (m.group(1), m.group(2)) if m else ("", "")
    if st == "DEAD" and (code[0] == "rc" or code[1] in ("401", "403")):
        jr.append(b, att=att, step="old-key", phase="result", res=DEAD_EVID, detail="%s=%s t=%s" % (code + (jr.now(),)))
    elif st in ("DEAD", "SKIP-CHECK", "UNVERIFIED"):
        jr.append(b, att=att, step="old-key", phase="result", res=UNCONFIRMED, detail=st + (" %s=%s" % code if m else ""))
    else:
        jr.append(b, att=att, phase="note", detail="옛 키 %s" % st)
    maybe_end(b, att)


def resume(b, plan, chk, paid, clip, field, say):
    """--resume — 값 출처 = 로컬 활성 줄(지문 대조) 또는 재복사 클립보드(지문 동일 확인). 지문이 다르면 REJECT. -> drive 결과."""
    att, es = jr.current(b)
    if not jr.is_open(jr.summarize(es)):
        raise ValueError("%s 열린 시도 없음" % b)
    if [s["name"] for s in plan] != journal_plan(es):
        raise ValueError("--plan 단계가 기록과 다름(기록: %s)" % (",".join(journal_plan(es)) or "-"))
    vals = values_of(b, es)
    if clip is not None:
        pend = [k for k in fields(b) if k not in vals and jr.last(es, "local:%s" % k, "intent")]
        k = field or (pend[0] if len(pend) == 1 else None)
        want = (jr.last(es, "local:%s" % k, "intent") or {}).get("fp") if k else None
        if not want or jr.fp(clip) != want:
            raise ValueError("클립보드 지문이 기록과 다름(또는 대상 필드 불명: --field <ENV>) — 조용히 다른 값 0")
        vals[k] = clip
    jr.append(b, att=att, phase="resume")
    res = drive(b, att, vals, plan, chk, paid, say, {})
    if res == "ok":
        maybe_end(b, att)
    return res


def abandon(b, reason, owner, when, say):
    """--abandon — 완료 표식 0. 중단 상태·담당·재개 조건·남은 복사본 표를 남긴다."""
    att, es = jr.current(b)
    if not jr.is_open(jr.summarize(es)):
        raise ValueError("%s 열린 시도 없음" % b)
    if not (reason and owner and when):
        raise ValueError("--reason · --owner · --when 셋 다 필요(담당·재개 조건 없이 중단 0)")
    jr.append(b, att=att, phase="abandon", detail=reason, owner=owner, cond=when)
    es = jr.current(b)[1]
    say("ABANDONED %s %s owner=%s 재개조건=%s\n%s" % (b, jr.summarize(es), owner, when, "\n".join(jr.abandon_table(es))))
    say("NOTE 완료 표식 0 · 다른 묶음 열기: %s" % ("가능(운영 반영 0 확인)" if jr.safe_abandon(es) else "운영 반영 가능성 — --allow-open 범위 값 1줄 필요"))


def final_line(b):
    return "BUNDLE %s %s" % (b, jr.summarize(jr.current(b)[1]))

