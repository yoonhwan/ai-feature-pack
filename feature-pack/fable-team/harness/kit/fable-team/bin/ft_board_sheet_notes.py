"""시트 입력 ② 사건 원장(sheet-events) 창 읽기 + ③ 보정 메모 lint (PLAN §2-1 · §3 · tail-read).

보정 메모 한 줄 = `<원장 행 id>.<필드> | <무엇이 틀렸나> | <제안>` — 행 id 실재 ∧ 그 행에 그 필드 실재해야 통과(무관 필드 REJECT).
id 꼴: `verdict#<n>` · `index-ledger#<ts>` · `sheet-events#<key>` · `issue#<번호>`. 메모는 자동 소비 0 — 시트 맨 아래 «미적용» 절로만 렌더된다.
"""
import json
import re
from pathlib import Path

CHUNK = 65536


def _jsonl(p: Path):
    return [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()] if p.is_file() else []


def tail_rows(path: Path, cutoff: str) -> list[dict]:
    """파일 끝에서 역방향으로 읽다가 창 밖(ts < cutoff) 첫 행에서 멈춘다 — 누적 크기와 무관."""
    rows: list[dict] = []
    if not path.is_file():
        return rows
    with path.open("rb") as f:
        f.seek(0, 2)
        pos, buf, done = f.tell(), b"", False
        while pos > 0 and not done:
            step = min(CHUNK, pos)
            pos -= step
            f.seek(pos)
            lines = (f.read(step) + buf).split(b"\n")
            buf, lines = (lines[0], lines[1:]) if pos > 0 else (b"", lines)
            for ln in reversed(lines):
                if not ln.strip():
                    continue
                r = json.loads(ln)
                if str(r["ts"]) < cutoff:
                    done = True
                    break
                rows.append(r)
    return rows[::-1]


def row_fields(root: Path, ident: str) -> set | None:
    """행 id → 그 행(들)의 필드 이름 집합. 실재하지 않으면 None."""
    st = root / ".fable-team" / "state"
    kind, _, val = ident.partition("#")
    rows: list[dict] = []
    if kind == "verdict" and val.isdigit():
        rows = [r for r in _jsonl(st / "verdicts.jsonl") if r.get("n") == int(val)]
    elif kind == "index-ledger":
        rows = [r for p in sorted(st.glob("index-ledger.*.jsonl")) for r in _jsonl(p) if r.get("ts") == val]
    elif kind == "sheet-events":
        rows = [r for r in _jsonl(st / "sheet-events.jsonl") if r.get("key") == val]
    elif kind == "issue" and val.isdigit():
        rows = [r for r in (json.loads((st / "board" / "gh-cache.json").read_text(encoding="utf-8")) if (st / "board" / "gh-cache.json").is_file() else []) if r.get("number") == int(val)]
    return {k for r in rows for k in r} if rows else None


def lint_notes(root: Path, path: Path) -> list[tuple[bool, str, str]]:
    """[(통과?, 줄, 사유)] — 빈 줄·`#` 주석은 건너뛴다."""
    out = []
    for ln in (path.read_text(encoding="utf-8").splitlines() if path.is_file() else []):
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        cols = [c.strip() for c in ln.split("|")]
        m = re.fullmatch(r"(.+)\.([^.\s]+)", cols[0])
        if len(cols) != 3 or not m or not all(cols[1:]):
            out.append((False, ln, "꼴 아님(<행 id>.<필드> | 틀린 것 | 제안)"))
            continue
        fields = row_fields(root, m[1])
        if fields is None:
            out.append((False, ln, f"원장 행 없음: {m[1]}"))
        elif m[2] not in fields:
            out.append((False, ln, f"그 행에 필드 없음: {m[2]}"))
        else:
            out.append((True, ln, ""))
    return out
