"""ft_sat_gate — ft-sat-nano «열 때의 문» (r949 · 위성 나노 팀 운영 체계 1/2).

명부 roster.json(상태 폴더) = 이 도구가 연 세션 표 · 상태 OPENING → OPEN → CLOSED · 표식 by=ft-sat-nano
원장 ledger.tsv(추가 전용) = 시각 · 종류 · slug · 이름 · free · warn · 결과(사유) — 종류는 open·close·reject 셋뿐(r949 r4) · 경고는 open 줄의 칸이다(독립 줄 0) · 비밀은 «종류»만(값 0)
문 4개: 상한 SAT_MAX(기본 3 · OPENING+OPEN 을 센다 · 원격 전) · mini free% 경고 SAT_FREE_MIN(기본 25 · R_PRE 와 같은 ssh 1회 · 값은 ssh rc0 ∧ 측정 rc0 ∧ 숫자 파싱 셋 다 맞을 때만 · 아니면 「측정 불가」 경고 1줄 · 어느 갈래도 열고 진행)
        이름 = ft-name-lint.sh 규칙 그대로(기본 byz-satnano-nano-<slug>#0) · 입력 비밀 = 공용 판정만(ft_secret_shapes.mask + autonomy_scope_secret.SECRET_SHAPE)
명부·원장 쓰기는 rt.ledger 잠금(opened.flock) 안에서만 — 잠금 밖 쓰기 = rc2(코드 결함).
"""
import json
import os
import re
import time

import ft_sat_rt as rt
from ft_sat_rt import Fail

MARK = "ft-sat-nano"
LIVE = ("OPENING", "OPEN")
BIN = os.path.dirname(os.path.abspath(__file__))
NAME_PREFIX = "byz-satnano-nano-"


def say(msg):
    print(f"[sat] {msg}", flush=True)


def stamp():
    """시각 칸 — FT_NOW 는 시험 전용 고정값."""
    v = os.environ.get("FT_NOW", "")
    if v:
        if not re.fullmatch(r"[0-9TZ:+.-]{1,32}", v):
            raise Fail(2, f"설정 오류: FT_NOW={v!r}")
        return v
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


# ── 이름 — 명부 규칙(ft-name-lint) 그대로 ──
def slug(run):
    s = re.sub(r"-+", "-", re.sub(r"[^a-z0-9-]", "-", run.lower())).strip("-")
    return s[:41].rstrip("-")  # 접두 17 + #0 2 → 60 이하


def auto_name(run):
    return f"{NAME_PREFIX}{slug(run)}#0"


def lint_name(name):
    lint = os.path.join(BIN, "ft-name-lint.sh")
    if not os.path.isfile(lint):
        raise Fail(2, f"ft-name-lint.sh 가 없다(원격 0): {lint}")
    rc, out, err = rt.run_child(["bash", lint, name], 7)
    if rc != 0:
        why = out.decode("utf-8", "replace").strip() or err.strip()
        raise Fail(2, f"이름이 명부 규칙 밖이다(원격 0): {why}")


# ── 입력 비밀 — 하네스 공용 판정 하나만 · 값은 다시 쓰지 않는다 (DA⑥ r3 고침 1 · 자기 패턴 0) ──
def secret_kinds(data):
    """공용 판정 두 곳만 «부른다» — ft_secret_shapes.mask(토큰·DSN·이름 붙은 비밀) + autonomy_scope_secret.SECRET_SHAPE(키 원문 모양 · ghs_/AKIA/PEM).
    이 모듈은 자기 패턴·경계 재정의·전처리를 갖지 않는다(r949 r4 · 카드 구현 범위 3 «새로 만들지 않음»).
    공용 판정이 못 보는 입력(한글 바로 뒤 토큰 등)은 별 카드 r977 범위다 — 여기서 보태지 않는다."""
    try:
        from autonomy_scope_secret import SECRET_SHAPE
        from ft_secret_shapes import mask
    except ImportError as e:
        raise Fail(2, f"비밀 검사 모듈을 못 읽었다(원격 0): {type(e).__name__}")
    text = data.decode("utf-8", "replace")
    kinds = {k for k, _ in mask(text)[1]}
    if SECRET_SHAPE.search(text):
        kinds.add("key-shape")
    return sorted(kinds)


def no_secret(data, label, slug_, name):
    kinds = secret_kinds(data)
    if kinds:
        ledger_add("reject", slug_, name, result="secret:" + ",".join(kinds))
        raise Fail(2, f"{label} 에 비밀 꼴 {len(kinds)}종({','.join(kinds)}) — 보내지 않는다 · 원격 0 · 원장에는 종류만")


# ── 원장 — 추가 전용 1줄 ──
def ledger_add(kind, slug_, name, free="-", warn="", result="-"):
    """원장 1줄 — 종류(kind) = open · close · reject 셋뿐(r949 r4 · 사건마다 1줄 · 경고는 독립 줄이 아니라 open 줄의 warn 칸).
    칸 = 시각 · 종류 · slug · 이름 · free · warn · 결과(사유 · 거절이면 secret:<종류들>/cap)."""
    rt.ensure_state()
    rt.append_line(rt.spath("ledger.tsv"), "\t".join(
        [stamp(), kind, slug_ or "-", name or "-", free or "-", warn, result or "-"]))


# ── 명부 ──
def roster_rows():
    try:
        with open(rt.spath("roster.json"), encoding="utf-8") as f:
            d = json.load(f)
    except FileNotFoundError:
        return []
    except Exception as e:
        raise Fail(2, f"명부 읽기 실패(roster.json: {e})")
    rows = d.get("rows") if isinstance(d, dict) else None
    if not isinstance(rows, list) or not all(isinstance(r, dict) for r in rows):
        raise Fail(2, "명부 형식 오류(roster.json: rows 목록이 아니다) — 건드림 0")
    return rows


def _save(rows):
    rt._must_hold()
    tmp = rt.spath("roster.json.tmp")
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"rows": rows}, f, ensure_ascii=False, indent=1)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, rt.spath("roster.json"))
    except Exception as e:
        raise Fail(2, f"기록 실패(roster.json: {e})")


def live(rows):
    return [r for r in rows if r.get("status") in LIVE]


def cap():
    return rt.cfg_int("SAT_MAX", 3, 1, 99)


def board(rows):
    out = [f"명부 열림 {len(live(rows))}/{cap()} · 전체 {len(rows)}행",
           "slug\t이름\t상태\t소켓\t연 시각\t닫은 시각\t표식"]
    keys = ("slug", "name", "status", "sock", "opened_at", "closed_at", "by")
    out += ["\t".join(str(r.get(k) or "-") for k in keys) for r in rows]
    return out


def gate_cap(slug_, name):
    """상한 — 원격 전 · 장부 잠금 안 · 넘으면 rc8(명부 행 0 · 원장 1줄)."""
    rows = roster_rows()
    mx, n = cap(), len(live(rows))
    if n >= mx:
        for ln in board(rows):
            say(f"  {ln}")
        ledger_add("reject", slug_, name, result="cap")
        raise Fail(8, f"상한 {mx} · 대기 {n - mx + 1}번째 — 지금 열림 {n}(위 표) · 원격 0 · 명부 행 0")


def gate_free(raw, free_rc, ssh_rc, slug_, name):
    """mini free% — 문이 아니라 경고다(arch 반송 r2 · 오뻐 10-25 «멈춰있으면 머할건데»).
    값으로 쓰는 조건 셋(r949 r4 · 판정은 이 함수 한 곳 · 원격 줄은 사실만 싣는다):
      (a) ssh 1회 rc 0 ∧ 7초 안  (b) 측정 명령 rc 0  (c) free_raw 가 숫자
    하나라도 아니면 «WARN … 측정 불가(<이유>)» 1줄 + free=? + 열고 진행. 값이 하한 미만이면 «WARN … < 25%» 1줄 + free=N + 열고 진행.
    반환 = (free 칸, warn 칸) — 원장 open 줄에 그대로 들어간다(독립 경고 줄 0)."""
    lo = rt.cfg_int("SAT_FREE_MIN", 25, 0, 99)
    ssh_rc, frc = str(ssh_rc), str(free_rc)
    reason = tag = ""
    if ssh_rc != "0":
        reason, tag = (("시간 초과", "timeout") if ssh_rc in ("124", "142") else (f"ssh rc {ssh_rc}", "ssh"))
    elif frc != "0":
        reason, tag = (("시간 초과", "timeout") if frc in ("124", "142") else (f"rc {frc}", "rc" + re.sub(r"\D", "", frc)))
    elif not re.fullmatch(r"[0-9]{1,3}", raw or ""):
        reason, tag = "파싱", "parse"
    if reason:
        say(f"  WARN mini free 측정 불가({reason}) — 열고 진행")
        return "?", "measure:" + tag
    v = int(raw, 10)
    if v < lo:
        say(f"  WARN mini free {v}% < {lo}% — 열고 진행")
        return str(v), "free<" + str(lo)
    say(f"  mini free {v}% (하한 {lo}%)")
    return str(v), ""


def ledger_open(slug_, name, free, warn, d):
    """열기 줄 1 — 여기서 처음 쓴다(r949 r4 · 거절이면 이 줄이 없다 · 경고는 warn 칸)."""
    ledger_add("open", slug_, name, free, warn, f"mini:~/{d}")


def roster_add(run, name):
    rows = roster_rows()
    rows.append({"slug": slug(run), "name": name, "run": run, "status": "OPENING", "sock": "",
                 "opened_at": stamp(), "closed_at": "", "by": MARK})
    _save(rows)


def _one_live(rows, key, val):
    hit = [r for r in live(rows) if r.get(key) == val]
    return hit[0] if len(hit) == 1 else None


def roster_set(run, **kw):
    rows = roster_rows()
    r = _one_live(rows, "run", run)
    if r is None:
        raise Fail(6, f"명부 손상 — run={run} 열린 줄이 정확히 1개가 아니다 · 건드림 0")
    r.update(kw)
    _save(rows)


def roster_drop(run):
    rows = roster_rows()
    r = _one_live(rows, "run", run)
    if r is not None:
        rows.remove(r)
        _save(rows)


def roster_marked(name):
    """닫기 앞 — 이 도구 표식이 있는 열린 줄만 · 없으면 rc6(닫기 0)."""
    r = _one_live(roster_rows(), "name", name)
    if r is None or r.get("by") != MARK:
        raise Fail(6, f"명부에 이 도구의 표식(by={MARK})이 있는 열린 줄이 없다 — 닫기 0 · 원격 0: {name}")
    return r


def closed(row, decision):
    """닫힘 기록 — 명부 CLOSED + 원장 1줄(결과 경로 = mini 작업 폴더)."""
    rows = roster_rows()
    r = _one_live(rows, "name", row[0])
    if r is not None:
        r.update(status="CLOSED", closed_at=stamp())
        _save(rows)
    ledger_add("close", slug(row[1]), row[0], result=f"{decision} mini:~/{row[2]}")


def cmd_roster(argv):
    if argv:
        raise Fail(2, "usage roster")
    for ln in board(roster_rows()):
        print(ln)
    return 0
