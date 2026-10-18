"""ft_key_rotate_steps.py — 묶음 흐름의 단계 부품 (R206c): 의도→호출→조회 확인 래퍼 · 조회 호출 · plan 읽기 · 로컬/확인/보관함/외부 단계 · 파괴 직전 재조회.
외부 단계(1Password·SM·Cloud Run 호출)는 호출자(byz-keys)가 plan JSON 으로 준다 — 이 도구는 기록·확인 계약만. 값은 stdin·메모리로만."""

import json
import os
import re
import subprocess

import ft_key_rotate_io as fio
import ft_key_rotate_journal as jr
from ft_key_rotate_journal import NOT_RUN, OK, UNCONFIRMED, UNKNOWN
from ft_key_rotate_lines import read_value
from ft_key_rotate_table import KEYS

VAULT = {"op-main": "kskill", "op-develop": "develop"}  # op 묶음 → 새 토큰 권한 확인 보관함
RESERVED = ("verify", "old-key", "vault", "local")
RES_OF = {"present": OK, "absent": NOT_RUN, "unknown": UNKNOWN, "skip": UNCONFIRMED}  # 불명은 다음 단계를 막는다
_ID, _VER = re.compile(r"\bid=([\w.:/-]{1,80})"), re.compile(r"\bver=([\w.:/-]{1,40})")


class Refused(Exception):
    """호출 전 거절 — 서버에 아무것도 안 갔다(미실행 확정)."""


def fields(b):
    return [k for k in KEYS if KEYS[k][3] == b]


def _try(argv, value=None, env=None):
    """7초 · 시간초과·실행 실패만 1회 재시도(7초 룰). stdout/stderr 는 호출자가 토큰만 읽는다."""
    for _ in (0, 1):
        try:
            return subprocess.run(argv, input=value, capture_output=True, text=True, timeout=7, env=env)
        except (subprocess.TimeoutExpired, OSError):
            pass
    return None


def probe_cmd(argv):
    """조회 argv → (present|absent|unknown, id, ver, detail). rc0=있음 · rc1=없음 · 그 밖·응답 없음=불명."""
    r = _try(argv)
    if r is None:
        return "unknown", None, None, "조회 응답 없음"
    i, v = _ID.search(r.stdout), _VER.search(r.stdout)
    st = "present" if r.returncode == 0 else "absent" if r.returncode == 1 else "unknown"
    return st, i and i.group(1), v and v.group(1), "rc=%d" % r.returncode


def load_plan(path, b):
    if not path:
        return []
    with open(path, encoding="utf-8") as f:
        steps = json.load(f).get("steps") or []
    seen = set()
    for s in steps:
        n = s.get("name", "")
        if not re.match(r"^[a-z][a-z0-9-]{0,29}$", n) or n in RESERVED or n in seen:
            raise ValueError("plan 단계 이름 오류: %r" % n)
        seen.add(n)
        for k in ("call", "probe", "guard"):
            if s.get(k) is not None and not (isinstance(s[k], list) and all(isinstance(a, str) for a in s[k])):
                raise ValueError("plan %s.%s 는 문자열 목록이어야 함" % (n, k))
        if not s.get("probe"):
            raise ValueError("plan %s: probe(조회) 필수 — 조회 없는 단계는 확인할 수 없다" % n)
        if s.get("stdin") and s["stdin"] not in fields(b):
            raise ValueError("plan %s: stdin 은 이 묶음의 ENV 이름이어야 함" % n)
        if s.get("destroy") and not (s.get("guard") and s.get("target_of")):
            raise ValueError("plan %s: destroy 단계는 guard·target_of 필수" % n)
    return steps


def run_step(b, att, step, call, probe, ops=False, pre=True, fpv=None):
    """의도 기록 → 호출 → 조회로 확인 → 결과 기록. 호출 예외(응답 유실 포함)는 조회가 정한다 — 조회도 못 하면 불명."""
    before = probe()[2] if pre else None
    flag = "1" if ops else None
    jr.append(b, att=att, step=step, phase="intent", before=before, fp=fpv, ops=flag)
    try:
        call()
    except Refused as e:
        jr.append(b, att=att, step=step, phase="result", res=NOT_RUN, detail=str(e), ops=flag)
        return NOT_RUN
    except Exception:  # noqa: BLE001 — 서버 반영 여부 모름: 아래 조회가 정한다
        pass
    st, i, v, d = probe()
    res = RES_OF[st]
    jr.append(b, att=att, step=step, phase="result", res=res, id=i, after=v, detail=d, ops=flag)
    return res


def _guard(b, spec):
    """파괴 직전: 기록 불명·미완료 소비자면 거절 · 고정 대상 ID 와 현재 참조를 다시 조회."""
    es = jr.current(b)[1]
    if any(jr.step_state(es, e["step"])["res"] == UNKNOWN for e in es if e["phase"] in ("intent", "result") and e["step"] != spec["name"]):
        raise Refused("기록 불명 — 파괴 0")
    if b in VAULT and (jr.step_state(es, "consumers") or {}).get("res") != OK:
        raise Refused("소비자 미완료 — 파괴 0")
    tgt = (jr.last(es, spec["target_of"]) or {}).get("id")
    if not tgt:
        raise Refused("대상 ID 없음 — 파괴 0")
    if probe_cmd([a.replace("{id}", tgt) for a in spec["guard"]])[0] != "present":
        raise Refused("재조회 불일치 — 파괴 0")
    return tgt


def ext_step(b, spec, values):
    def call():
        tgt = _guard(b, spec) if spec.get("destroy") else ""
        if spec.get("call"):
            val = values.get(spec["stdin"]) if spec.get("stdin") else None
            if spec.get("stdin") and val is None:
                raise Refused("새 값 없음(재개 값 출처 필요)")
            r = _try([a.replace("{id}", tgt) for a in spec["call"]], val)
            if r is None or r.returncode != 0:
                raise RuntimeError("호출 실패")

    return call, lambda: probe_cmd([a.replace("{id}", "") for a in spec["probe"]]), bool(spec.get("ops"))


def local_step(key, files, edits, values, box):
    def call():
        if not edits:
            raise Refused("새 값 없음(클립보드 재복사 필요)")
        try:
            box["backups"] = fio.apply_edits(key, edits, True)
        except Exception as e:  # noqa: BLE001 — 원래 REJECT 문구를 호출자가 그대로 올린다
            box["err"] = e
            raise

    def probe():
        new = values.get(key)
        hit = [read_value(p, key) is not None and new is not None and jr.fp(read_value(p, key)) == jr.fp(new) for p in files]
        b0 = fio.latest_backup(files[0], key)
        d = "백업 " + os.path.basename(b0).split(".bak-keyrotate-")[-1] if b0 else None
        return ("present" if all(hit) else "absent" if not any(hit) else "unknown"), None, None, d

    return call, probe, False


def verify_step(b, chk, paid, box):
    def probe():
        st, label = chk(rep(b), "now", paid)
        box["verify"] = (st, label)
        m = re.search(r"http=\d+", label)
        k = {"ALIVE": "present", "DEAD": "absent", "SKIP-CHECK": "skip", "UNVERIFIED": "skip"}.get(st, "unknown")
        return k, None, None, st + (" " + m.group(0) if m else "")

    return (lambda: None), probe, False


def vault_step(b, values):
    """계약 예외(arch#68 · DA⑥ HOLD 2): op CLI 서비스 계정 인증은 OP_SERVICE_ACCOUNT_TOKEN env 로만 받는다(stdin·argv 경로 없음) →
    새 토큰을 `op vault get` 자식 1개의 env 로만 넘긴다. 조건: env 는 사본(dict(os.environ, …)) · 부모 os.environ 불변 · 다른 자식 env 에 0 · 출력·journal·argv 에 값 0(시험이 확인)."""

    def probe():
        tok = values.get(rep(b))
        if tok is None:
            return "unknown", None, None, "새 토큰 없음"
        r = _try(["op", "vault", "get", VAULT[b]], env=dict(os.environ, OP_SERVICE_ACCOUNT_TOKEN=tok))
        return ("unknown" if r is None else "present" if r.returncode == 0 else "absent"), None, None, "vault=%s" % VAULT[b]

    return (lambda: None), probe, False


def rep(b):
    return fields(b)[-1]
