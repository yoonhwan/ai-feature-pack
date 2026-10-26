"""ops_intake_common — #howto-talk-ops 접수 도구 공용 (경로·스키마·마스킹·쪽지·시각).

경로는 전부 env 로 옮길 수 있다(시험 = 임시 HOME). 기본값은 mini 기준 `~/.fable-team/ops-intake/`.
비밀 마스킹은 하네스 정본 규칙(`ft_secret_shapes.mask`)을 그대로 부른다 — 규칙 복제 0.
규칙 모듈을 못 찾으면 «판정 불가 = 차단»(IntakeError rc2) — 조용히 통과하지 않는다.
개인정보(전화·이메일)만 이 파일에 정규식 2줄로 더한다(하네스 스캔에 없는 축).
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

KINDS = frozenset({"bug", "feature", "question", "other"})
REQUIRED = ("slack_channel", "thread_ts", "user_id", "kind", "product", "title", "symptom")
OPTIONAL = ("urgency", "repro", "expect", "attachments")
MAX_LEN = {"slack_channel": 32, "thread_ts": 32, "user_id": 32, "product": 60, "urgency": 40, "title": 200, "symptom": 3000, "repro": 3000, "expect": 2000}
CHANNEL_RX = re.compile(r"^[CG][A-Z0-9]{6,}$")
TS_RX = re.compile(r"^\d{6,}\.\d{4,}$")
USER_RX = re.compile(r"^U[A-Z0-9]{4,}$")
EMAIL_RX = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
PHONE_RX = re.compile(r"(?<!\d)0\d{1,2}[-. ]?\d{3,4}[-. ]?\d{4}(?!\d)")
SECRET_MODULE = "ft_secret_shapes.py"


class IntakeError(RuntimeError):
    """rc 를 함께 나르는 오류 — 문구에 값(비밀·원문)은 쓰지 않는다."""

    def __init__(self, msg: str, rc: int = 2) -> None:
        super().__init__(msg)
        self.rc = rc


def env_path(name: str, default: str) -> str:
    return os.environ.get(name) or default


def home() -> Path:
    return Path(os.path.expanduser("~"))


def ops_root() -> Path:
    return Path(env_path("OPS_INTAKE_ROOT", str(home() / ".fable-team" / "ops-intake")))


def sub(name: str) -> Path:
    p = ops_root() / name
    p.mkdir(parents=True, exist_ok=True)
    return p


def now_epoch() -> int:
    """FT_NOW(정수 초 또는 ISO8601) 고정 — 시험이 시계를 흔들지 않게."""
    raw = os.environ.get("FT_NOW", "").strip()
    if not raw:
        return int(datetime.now(timezone.utc).timestamp())
    if raw.isdigit():
        return int(raw)
    return int(datetime.fromisoformat(raw.replace("Z", "+00:00")).timestamp())


def now_iso() -> str:
    return datetime.fromtimestamp(now_epoch(), timezone.utc).astimezone().isoformat(timespec="seconds")


def read_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, path)


def _secret_dirs() -> list[Path]:
    here = Path(__file__).resolve().parent
    cands = [env_path("OPS_INTAKE_SECRET_DIR", "")]
    if os.environ.get("FT_BIN"):
        cands.append(os.environ["FT_BIN"])
    cands += [str(here), str(here.parent.parent / "bin")]  # 키트 이웃 · 하네스 bin
    return [Path(c) for c in cands if c]


def masker():
    """ft_secret_shapes.mask 를 돌려준다. 없으면 IntakeError(차단)."""
    for d in _secret_dirs():
        if (d / SECRET_MODULE).is_file():
            if str(d) not in sys.path:
                sys.path.insert(0, str(d))
            try:
                from ft_secret_shapes import mask  # 정본 규칙 — 복제 0
                return mask
            except Exception as e:  # 모듈이 깨졌으면 판정 불가
                raise IntakeError(f"비밀 규칙 모듈 적재 실패: {type(e).__name__} · 판정 불가", 2) from e
    raise IntakeError("비밀 규칙 모듈 없음(ft_secret_shapes.py) · 판정 불가 · 카드 0", 2)


def mask_text(text: str) -> tuple[str, list[str]]:
    """(가린 글, 종류별 건수 목록). 비밀은 ***, 개인정보는 자리표시자."""
    if not text:
        return "", []
    masked, hits = masker()(text)
    kinds = [k for k, _ln in hits]
    for kind, rx, ph in (("email", EMAIL_RX, "<이메일>"), ("phone", PHONE_RX, "<전화번호>")):
        masked, n = rx.subn(ph, masked)
        kinds += [kind] * n
    return masked, kinds


def kind_summary(kinds: list[str]) -> str:
    """«토큰 1 · 전화번호 1» 꼴 — 값 0, 종류·개수만."""
    if not kinds:
        return "0건"
    counts: dict[str, int] = {}
    for k in kinds:
        counts[k] = counts.get(k, 0) + 1
    return " · ".join(f"{k} {n}" for k, n in sorted(counts.items()))


def validate(doc: object) -> dict:
    """스키마 엄격 검사 — 모르는 칸도 거부한다(오타가 조용히 사라지지 않게)."""
    if not isinstance(doc, dict):
        raise IntakeError("스키마 위반: 최상위가 객체 아님")
    unknown = sorted(set(doc) - set(REQUIRED) - set(OPTIONAL))
    if unknown:
        raise IntakeError(f"스키마 위반: 모르는 칸 {','.join(unknown)}")
    missing = [k for k in REQUIRED if not str(doc.get(k, "")).strip()]
    if missing:
        raise IntakeError(f"스키마 위반: 빠진 칸 {','.join(missing)}")
    for k in REQUIRED + tuple(x for x in OPTIONAL if x in doc):
        v = doc[k]
        if k == "attachments":
            if not isinstance(v, list) or not all(isinstance(a, str) and a.strip() for a in v):
                raise IntakeError("스키마 위반: attachments 는 문자열 목록")
            continue
        if not isinstance(v, str):
            raise IntakeError(f"스키마 위반: {k} 는 문자열")
        if len(v) > MAX_LEN.get(k, 3000):
            raise IntakeError(f"스키마 위반: {k} 길이 초과")
    if doc["kind"] not in KINDS:
        raise IntakeError("스키마 위반: kind 는 bug|feature|question|other")
    for key, rx in (("slack_channel", CHANNEL_RX), ("thread_ts", TS_RX), ("user_id", USER_RX)):
        if not rx.match(doc[key]):
            raise IntakeError(f"스키마 위반: {key} 꼴 아님")
    return doc


def mbox_py():
    """ft-mbox.py 를 모듈로 부른다(잠금·형식 복제 0)."""
    path = env_path("OPS_MBOX_PY", str(home() / ".claude/skills/fable-team/scripts/ft-mbox.py"))
    if not Path(path).is_file():
        raise IntakeError(f"ft-mbox.py 없음: {path} · 쪽지 0", 2)
    import importlib.util
    spec = importlib.util.spec_from_file_location("ops_ft_mbox", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def mbox_send(to: str, frm: str, body: str) -> str:
    sh = env_path("OPS_MBOX_SH", str(home() / ".claude/skills/fable-team/scripts/ft-mbox.sh"))
    if not Path(sh).is_file():
        raise IntakeError(f"ft-mbox.sh 없음: {sh} · 쪽지 0", 2)
    r = subprocess.run(["bash", sh, "send", to, frm, body], capture_output=True, text=True, timeout=30)
    out = (r.stdout + r.stderr).strip()
    if r.returncode != 0 or "QUEUED" not in r.stdout:
        raise IntakeError(f"쪽지 발신 실패 rc={r.returncode} {out[-160:]}", 5)
    return out


def mbox_rows(to: str) -> list[dict]:
    m = mbox_py()
    rows = m._locked(m.CANON, lambda: [r for r in m._load(m.CANON) if r.get("to") == to])
    return list(rows)


def mbox_ack(seqs: list) -> int:
    m = mbox_py()

    def op() -> int:
        keep = [r for r in m._load(m.CANON) if r.get("seq") not in set(seqs)]
        gone = len(m._load(m.CANON)) - len(keep)
        if gone:
            m._save(m.CANON, keep)
        return gone

    return int(m._locked(m.CANON, op))


def tmp_file(suffix: str = ".card") -> Path:
    """state/tmp 아래 임시 파일 — 쓰고 나면 반드시 지운다(원본 보존 0)."""
    d = sub("state") / "tmp"
    d.mkdir(parents=True, exist_ok=True)
    fd, path = tempfile.mkstemp(prefix="intake-", suffix=suffix, dir=str(d))
    os.close(fd)
    return Path(path)
