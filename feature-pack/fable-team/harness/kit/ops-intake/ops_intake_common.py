"""ops_intake_common — #howto-talk-ops 접수 도구 공용 (경로·스키마·마스킹·쪽지·시각).

경로는 전부 env 로 옮길 수 있다(시험 = 임시 HOME). 기본값은 mini 기준 `~/.fable-team/ops-intake/`.
비밀 가림은 하네스 공용 함수(`ft_secret_shapes.mask`) 하나만 부른다 — 규칙 복제 0. 그 모듈의 판본은
sha256 고정값과 대조해 다르면 접수 거절(카드 r6). 공용 규칙표(`post_guard.SECRETS`)는 판정과 «머리표» 가림에만
쓴다(값 꼴은 이 파일에 없다). 가림 자리는 `mask_text()` 하나뿐이다 — write.py·poster.py 는 이 함수만 부른다.
순서 = 따옴표 안 값 → 개인키 BEGIN~END 블록 통째 삭제 → 공용 가림 → 공용 판정 재실행(남으면 원장 rejected + 거절).
규칙 모듈을 못 찾으면 «판정 불가 = 차단»(IntakeError rc2) — 조용히 통과하지 않는다.
개인정보(전화·이메일)만 이 파일에 정규식 2줄로 더한다(하네스 스캔에 없는 축).
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from contextlib import contextmanager
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
# ★판본 고정★ 착지한 공용 가림 함수(팩 origin/main 80a476d0 · r977)의 sha256 — 다르면 접수 거절(카드 r6).
FT_SECRET_SHAPES_SHA256 = "8bdf45744dcc61aa52e7c716c2bed718f85c979703e4623da2153b8779b3f962"
SEP_TAIL = "=:/"  # 규칙표에서 «이름+구분자» 로 끝난 머리표 — 값은 뒤 덩어리
RUN_MIN, RUN_MAX = 2, 4  # 공백으로 쪼갠 값을 붙여 보는 이웃 덩어리 수
# 개인키 머리말 집합 1개 — OPENSSH·RSA·EC·PGP(`PRIVATE KEY BLOCK`) 전부 «PRIVATE KEY» 를 품는다.
PEM_BEGIN = re.compile(r"-----BEGIN [A-Za-z0-9 ]*PRIVATE KEY[A-Za-z0-9 ]*-----")
PEM_END = re.compile(r"-----END [A-Za-z0-9 ]*PRIVATE KEY[A-Za-z0-9 ]*-----")
# «이름=값» 의 값이 따옴표(쌍)로 감싸였을 때 그 경계 — 비밀 꼴이 아니라 구두점 경계다(개행 포함).
QUOTED = re.compile(r"""(?P<pre>[A-Za-z_][A-Za-z0-9_]{1,}\s*[=:]\s*)(?P<q>["'])(?P<val>.*?)(?P=q)""", re.S)
# 제어문자·폭 0 문자 — 검출 전에 지운다(이것들이 끼면 토큰이 쪼개져 검출을 빠져나간다 · DA r3 반례 1)
CTRL_RX = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u00ad\u200b-\u200f\u2028\u2029\ufeff]")


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
    """임시 파일 이름은 프로세스마다 다르다 — 같은 .tmp 를 둘이 쓰면 한쪽이 깨진다(DA r3 반례 3)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(json.dumps(data, ensure_ascii=False, indent=1))
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


@contextmanager
def locked(name: str):
    """한 덩어리를 한 프로세스만 — flock. 한도 확인 → 카드 쓰기 → 원장 → 쪽지 예약을 같이 감싼다."""
    path = sub("state") / f"{name}.lock"
    fh = open(path, "w")
    fcntl.flock(fh, fcntl.LOCK_EX)
    try:
        yield
    finally:
        fcntl.flock(fh, fcntl.LOCK_UN)
        fh.close()


def _secret_dirs() -> list[Path]:
    here = Path(__file__).resolve().parent
    cands = [env_path("OPS_INTAKE_SECRET_DIR", "")]
    if os.environ.get("FT_BIN"):
        cands.append(os.environ["FT_BIN"])
    cands += [str(here), str(here.parent.parent / "bin")]  # 키트 이웃 · 하네스 bin
    return [Path(c) for c in cands if c]


def _ft_mask():
    """정본 1 = 하네스 출력 가림 규칙(ft_secret_shapes.RULES) — 판본 sha256 을 고정값과 대조한다(r6)."""
    for d in _secret_dirs():
        f = d / SECRET_MODULE
        if f.is_file():
            got = hashlib.sha256(f.read_bytes()).hexdigest()
            if got != FT_SECRET_SHAPES_SHA256:
                raise IntakeError(f"공용 가림 함수 판본 다름(sha256 {got[:12]}…) · 판정 불가 · 카드 0", 2)
            if str(d) not in sys.path:
                sys.path.insert(0, str(d))
            try:
                from ft_secret_shapes import mask  # 정본 규칙 — 복제 0
                return mask
            except Exception as e:  # 모듈이 깨졌으면 판정 불가
                raise IntakeError(f"비밀 규칙 모듈 적재 실패: {type(e).__name__} · 판정 불가", 2) from e
    raise IntakeError("비밀 규칙 모듈 없음(ft_secret_shapes.py) · 판정 불가 · 카드 0", 2)


def _pg_secrets() -> dict:
    """정본 2 = 슬랙 게시 검사 규칙(post_guard.SECRETS) — 판정(r5 검출)과 머리표 가림에 그대로 쓴다."""
    here = Path(__file__).resolve().parent
    d = Path(env_path("OPS_SLACK_LIB", str(here.parent / "slack-mirror")))
    if not (d / "post_guard.py").is_file():
        raise IntakeError(f"공용 비밀 꼴 모듈 없음: {d}/post_guard.py · 판정 불가 · 카드 0", 2)
    if str(d) not in sys.path:
        sys.path.insert(0, str(d))
    try:
        import post_guard
        return dict(post_guard.SECRETS)
    except Exception as e:
        raise IntakeError(f"공용 비밀 꼴 적재 실패: {type(e).__name__} · 판정 불가", 2) from e


def normalize(text: str) -> str:
    """★검출·마스킹 «전» 한 번만★ — 제어문자·폭 0 제거 · 탭·개행 → 공백 1개 · 앞뒤 정리(한 칸 = 한 줄).
    정규화 뒤에만 검출하고, 가린 뒤에는 글자를 더 바꾸지 않는다(바꾸면 쪼갠 토큰이 다시 붙는다)."""
    t = text.replace("\r\n", "\n").replace("\r", "\n").replace("\t", " ")
    return " ".join(CTRL_RX.sub("", t).split())


def detect_raw(text: str) -> list[str]:
    """공용 판정 — 공용 규칙 두 정본(ft_secret_shapes.RULES · post_guard.SECRETS)만 본다. 값은 돌려주지 않는다.
    가림 «뒤» 이 함수를 한 번 더 돌려 남는 것이 있으면 접수 거절(카드 r6 · mask_text ⑧)."""
    kinds = [k for k, _ln in _ft_mask()(text)[1]]
    for name, pat in _pg_secrets().items():
        if re.search(pat, text):
            kinds.append(name)
    return kinds


def detect(text: str) -> list[str]:
    """정규화한 글에 대한 공용 판정."""
    return detect_raw(normalize(text))


def mask_quoted_values(text: str) -> tuple[str, list[str]]:
    """«이름=값» 의 값이 따옴표로 감싸여 있으면 그 안을 통째로 가린다 — 값에 개행·공백이 들어가도 경계가 보인다.
    본다 것은 따옴표 «경계» 뿐이다(비밀 꼴 0) · 공용 가림 함수 호출 «전» 1단계(카드 r6)."""
    kinds: list[str] = []

    def sub(m: re.Match[str]) -> str:
        kinds.append("quoted-value")
        return m.group("pre") + m.group("q") + "***" + m.group("q")

    return QUOTED.sub(sub, text), kinds


def drop_pem_blocks(text: str) -> tuple[str, int]:
    """개인키는 BEGIN~END 블록을 «통째» 지운다 — 줄 단위로 남기면 키 본문이 그대로 남는다(DA⑥ r4 반례 2).
    END 가 없으면 BEGIN 부터 끝까지 지운다(안전한 쪽)."""
    keep: list[str] = []
    dropped, inside = 0, False
    for ln in text.split("\n"):
        if inside or PEM_BEGIN.search(ln):
            dropped += 1
            inside = not PEM_END.search(ln)
            continue
        keep.append(ln)
    return "\n".join(keep), dropped


def _mask_shared_heads(text: str) -> tuple[str, list[str]]:
    """공용 게시 검사 규칙표(post_guard.SECRETS)가 잡은 자리를 «머리표 + 바로 뒤 값 덩어리» 로 가린다.
    규칙표는 값 «꼴» 을 모른다(그래서 이 파일에 값 꼴을 만들지 않는다). 이름+구분자에서 끝난 규칙은
    뒤 첫 덩어리를 통째로 *** 로 바꾼다 — 머리표만 가리면 값이 남는다(DA⑥ r4 반례 1)."""
    kinds: list[str] = []
    spans: list[tuple[int, int]] = []
    for name, pat in _pg_secrets().items():
        for m in re.finditer(pat, text):
            kinds.append(name)
            end = m.end()
            if m.group(0)[-1:] in SEP_TAIL:  # 이름+구분자(password= · postgres:// …) — 값은 «뒤» 덩어리
                while end < len(text) and text[end] == " ":
                    end += 1
            while end < len(text) and text[end] != " ":  # 값이 같은 덩어리에 붙어 있으면 덩어리 끝까지
                end += 1
            spans.append((m.start(), end))
    if not spans:
        return text, kinds
    out: list[str] = []
    cur = 0
    for s, e in sorted(spans):
        if e <= cur:
            continue
        out.append(text[cur:max(s, cur)] + "***")
        cur = e
    out.append(text[cur:])
    return "".join(out), kinds


def _mask_split_runs(text: str) -> tuple[str, list[str]]:
    """공백으로 쪼갠 비밀 — 이웃 덩어리를 붙여 보고, 붙여야만 보이면 그 덩어리들을 통째로 가린다.
    정규화가 개행·제어문자를 «한 칸» 으로 바꾸므로 값이 쪼개진 채 남을 수 있다."""
    toks = text.split(" ")
    kinds: list[str] = []
    out: list[str] = []
    i = 0
    while i < len(toks):
        for n in range(RUN_MAX, RUN_MIN - 1, -1):
            if i + n <= len(toks):
                hits = detect_raw("".join(toks[i:i + n]))
                if hits:
                    kinds += hits
                    out.append("***")
                    i += n
                    break
        else:
            out.append(toks[i])
            i += 1
    return " ".join(out), kinds


def record_rejected(kinds: list[str]) -> None:
    """접수 거절 1줄 — 사유 «종류» 만 남는다(값·본문 0). 원장 = state/rejected.jsonl."""
    try:
        path = sub("state") / "rejected.jsonl"
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps({"ts": now_iso(), "reason": "leftover-secret", "kinds": sorted(set(kinds))}, ensure_ascii=False) + "\n")
    except OSError:
        pass  # 원장을 못 써도 거절은 한다(조용한 통과 0)


def mask_text(text: str) -> tuple[str, list[str]]:
    """★가림 호출 자리 하나★ (write.py·poster.py 는 이 함수만 부른다 — common 한 곳).
    (가린 글, 종류 목록) — 비밀은 ***, 개인정보는 자리표시자. 순서는 계약이다(카드 r6):
    ① 따옴표 안 값 통째 → ② 개인키 BEGIN~END 블록 통째 삭제 → ③ 정규화 →
    ④ 공용 규칙표(post_guard.SECRETS) 머리표 가림 → ⑤ 공용 가림 함수(ft_secret_shapes.mask) →
    ⑥ 공백으로 쪼갠 값 창 → ⑦ 개인정보 → ⑧ 공용 판정 재실행, 남으면 원장 rejected + 접수 거절.
    ★비밀 «꼴» 은 이 파일에 없다★ — 개인정보 두 줄만 공용 가림 함수에 없는 축(비밀 아님)이라 남긴다."""
    if not text:
        return "", []
    body, kinds = mask_quoted_values(text)  # ① 따옴표 경계
    body, dropped = drop_pem_blocks(body)  # ② 개인키 블록 통째 삭제
    kinds += ["private-key"] * dropped
    n = normalize(body)  # ③ 정규화 먼저
    n, pg = _mask_shared_heads(n)  # ④ 공용 규칙표 머리표 + 값 덩어리
    masked, hits = _ft_mask()(n)  # ⑤ 공용 가림 함수 하나
    kinds += pg + [k for k, _ln in hits]
    masked, split = _mask_split_runs(masked)  # ⑥ 공백으로 쪼갠 값
    kinds += split
    for kind, rx, ph in (("email", EMAIL_RX, "<이메일>"), ("phone", PHONE_RX, "<전화번호>")):
        masked, cnt = rx.subn(ph, masked)  # ⑦ 개인정보
        kinds += [kind] * cnt
    left = detect_raw(masked) or detect_raw(masked.replace(" ", ""))  # ⑧ 공용 판정 재실행
    if left:
        record_rejected(left)
        raise IntakeError(f"가림 뒤 비밀 잔여({kind_summary(left)}) · 판정 불가 · 카드 0", 2)
    return masked, kinds


def post_kinds(text: str) -> list[str]:
    """게시 직전 판정 — 카드와 «같은» 가림 자리를 거친다. 가리지 못한 잔여도 «비밀 있음» 으로 본다(게시 0)."""
    try:
        return mask_text(text)[1]
    except IntakeError:
        return ["unmasked-leftover"]


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
