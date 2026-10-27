#!/usr/bin/env python3
"""ft_secret_triage — 비밀 기록 원장(secret-scan.log)의 «파일:줄» 행을 읽기 전용으로 점검해 3값으로 가른다 (r1002 · 값 0).

ⓐ 실값 = 가림 함수가 값을 가렸고 예시 표식이 없음 · ⓑ 이름만 = 비밀 «이름» 꼴은 있으나 값 자리가 비었거나 ***·<…> 자리표시
· ⓒ 예시·가짜 = 시험 폴더 경로이거나 example·dummy·fake·xxx 낱말 · 그 밖/못 읽음/시간 초과 = 판정 불가.
출력은 종류·파일·줄·3값 뿐 — 값·값 일부·길이를 어디에도 쓰지 않는다. 원장·세션 기록 파일 쓰기 0(읽기 전용).
같은 파일의 행은 파일을 한 번만 통과해 나눠 쓴다(행 상한은 파일 상한과 같다 — 한 행이 7초를 넘으면 그 파일 행 전부 판정 불가).
사용: ft_secret_triage.py [--log PATH] [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--out MD]
rc: 0 정상 · 2 usage · 4 표 파일 쓰기 실패
"""
from __future__ import annotations

import os
import re
import signal
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ft_secret_shapes import mask  # noqa: E402  가림 함수 재사용 — 값은 여기서만 만진다(출력 0)
from ft_secret_targets import NAME  # noqa: E402  비밀 «이름» 판정 한 벌 재사용

REAL, MNAME, EXAMPLE, UNKNOWN = "실값", "이름만", "예시·가짜", "판정 불가"
VERDICTS = (REAL, MNAME, EXAMPLE, UNKNOWN)
TS = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")
REC = re.compile(r"^(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\t(?P<path>.+):(?P<no>\d+) (?P<kind>\S.*)$")  # kind 에는 띄어쓰기가 들어간다(plan:이유 …) — 앞에서부터 잡고 뒤는 통째로
TEST_DIR = re.compile(r"/(?:tests?|fixtures?|testdata|__fixtures__|stubs?|samples?|mocks?)/")
EX_WORD = re.compile(r"(?<![A-Za-z0-9_])(?:examples?|dummy|fake|sample|placeholder|redacted|changeme|x{3,})(?![A-Za-z0-9_])", re.I)
SLOT = re.compile(r"[\"']?(?P<name>[A-Za-z_][A-Za-z0-9_]*)[\"']?\s*[=:]\s*[\"']?(?P<val>[^\s,;&}\]\"']*)")
EMPTY = re.compile(r"^(?:\*{2,}|<[^<>]*>|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|x{3,}|(?:redacted|changeme|placeholder|dummy|fake|example|none|null)?)$", re.I)
FIXED, CAP, ROW = 5.0, 70.0, 7.0  # 고정비 · 전체 상한 · 행 상한(초) — 넘으면 «판정 불가» 줄(조용한 생략 0)
LOG_DEF = "~/.fable-team/state/secret-scan.log"


class _Timeout(Exception):
    pass


def _fire(_sig: int, _frm: object) -> None:
    raise _Timeout()


def verdict(path: str, line: str) -> str:
    if TEST_DIR.search(path) or EX_WORD.search(line):
        return EXAMPLE
    if mask(line)[1]:  # 가림 함수가 값을 가렸다 = 실값(예시 표식 없는 줄에서만)
        return REAL
    for m in SLOT.finditer(line):
        if NAME.search(m.group("name")) and EMPTY.match(m.group("val")):
            return MNAME  # 이름 꼴은 있고 값 자리가 비었거나 자리표시
    return UNKNOWN


def rows_of(text: str, since: str, until: str) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for n, raw in enumerate(text.splitlines(), 1):
        if not raw.strip():
            continue
        ts = raw.split("\t", 1)[0]
        if TS.match(ts) and (ts[:10] < since or ts[:10] > until):
            continue  # 날짜 범위 밖 — 세지 않는다
        m = REC.match(raw)
        if not m:
            out.append({"ts": ts, "path": "(원장)", "line": str(n), "kind": "?",  # 원문을 표에 옮기지 않는다(값 0)
                        "verdict": UNKNOWN, "why": "탭 깨진 행"})
            continue
        out.append({"ts": m["ts"], "path": m["path"], "line": m["no"], "kind": m["kind"]})
    return out


def collect(path: str, nos: list[int], budget: float) -> dict[int, str]:
    want, got = set(nos), {}
    signal.setitimer(signal.ITIMER_REAL, budget)
    try:
        with open(path, errors="replace") as f:
            for i, ln in enumerate(f, 1):
                if i in want:
                    got[i] = ln
                    if len(got) == len(want):
                        break
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
    return got


def classify(rows: list[dict[str, str]], row_secs: float, total: float) -> None:
    by_file: dict[str, list[int]] = {}
    for r in rows:
        if r["line"].isdigit():
            by_file.setdefault(r["path"], []).append(int(r["line"]))
    start = time.monotonic()
    for path, nos in by_file.items():
        left = total - (time.monotonic() - start)
        got: dict[int, str] = {}
        why = "전체 상한 초과" if left <= 0 else ""
        if not why:
            try:
                got = collect(path, nos, min(row_secs, left))
            except _Timeout:
                why = f"행 {row_secs:g}초 초과"
            except FileNotFoundError:
                why = "파일 없음"
            except PermissionError:
                why = "읽기 권한 없음"
            except OSError:
                why = "읽기 실패"
        for r in rows:
            if r["path"] != path or not r["line"].isdigit():
                continue
            no = int(r["line"])
            if why:
                r["verdict"], r["why"] = UNKNOWN, why
            elif no not in got:
                r["verdict"], r["why"] = UNKNOWN, "줄 번호가 파일 길이 넘음"
            else:
                r["verdict"] = verdict(path, got[no])


def table(rows: list[dict[str, str]], log: str, since: str, until: str) -> str:
    kinds = sorted({r["kind"] for r in rows})
    cnt = {k: {v: 0 for v in VERDICTS} for k in kinds}
    for r in rows:
        cnt[r["kind"]][r["verdict"]] += 1
    tot = {v: sum(cnt[k][v] for k in kinds) for v in VERDICTS}
    out = [f"# 비밀 기록 점검 표 — r1002 ({time.strftime('%F %T')} · 값 0 · 읽기 전용)", "",
           f"- 원장: `{log}`", f"- 범위: {since} ~ {until} · 행 {len(rows)}", "", "## 종류 × 3값", "",
           "| 종류 | " + " | ".join(VERDICTS) + " | 합계 |",
           "| --- | " + " | ".join("---" for _ in VERDICTS) + " | --- |"]
    for k in kinds:
        out.append(f"| {k} | " + " | ".join(str(cnt[k][v]) for v in VERDICTS) + f" | {sum(cnt[k].values())} |")
    out.append("| **합계** | " + " | ".join(str(tot[v]) for v in VERDICTS) + f" | {len(rows)} |")
    out += ["", "## 행별 판정 (값 0)", "", "| 파일 | 줄 | 종류 | 3값 |", "| --- | --- | --- | --- |"]
    for r in rows:
        out.append(f"| {r['path']} | {r['line']} | {r['kind']} | {r['verdict']} |")
    out += ["", "## 실값 목록 (교체 대상 후보 · 파일:줄만)", ""]
    real = [f"- `{r['path']}:{r['line']}` {r['kind']}" for r in rows if r["verdict"] == REAL]
    out += real or ["- 없음"]
    out += ["", "## 판정 불가 (이유)", ""]
    unk: dict[str, int] = {}
    for r in rows:
        if r["verdict"] == UNKNOWN:
            unk[r.get("why", "?")] = unk.get(r.get("why", "?"), 0) + 1
    out += [f"- {k}: {v}건" for k, v in sorted(unk.items())] or ["- 없음"]
    return "\n".join(out) + "\n"


def main(argv: list[str]) -> int:
    log, since, until, out = os.path.expanduser(LOG_DEF), "", "", ""
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--log", "--since", "--until", "--out") and i + 1 < len(argv):
            log = os.path.expanduser(argv[i + 1]) if a == "--log" else log
            since = argv[i + 1] if a == "--since" else since
            until = argv[i + 1] if a == "--until" else until
            out = argv[i + 1] if a == "--out" else out
            i += 2
            continue
        print("usage: ft_secret_triage.py [--log PATH] [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--out MD]", file=sys.stderr)
        return 2
    since, until = since or "0000-01-01", until or "9999-12-31"
    try:
        with open(log, errors="replace") as f:
            text = f.read()
    except OSError:
        print(f"WARN ft-secret-triage: 원장 없음 — 행 0 으로 본다 ({log})", file=sys.stderr)
        text = ""
    rows = rows_of(text, since, until)
    try:
        row_secs = float(os.environ.get("FT_SECRET_TRIAGE_ROW_SECS") or ROW)
        env_total = os.environ.get("FT_SECRET_TRIAGE_TOTAL_SECS")
        total = float(env_total) if env_total else min(FIXED + row_secs * len(rows), CAP)
    except ValueError:
        print("ERROR ft-secret-triage: 상한 값이 숫자가 아님", file=sys.stderr)
        return 2
    signal.signal(signal.SIGALRM, _fire)
    classify(rows, row_secs, total)
    if out:
        try:
            os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
            with open(out, "w") as f:
                f.write(table(rows, log, since, until))
        except OSError as e:
            print(f"ERROR ft-secret-triage: 표 파일 쓰기 실패 ({out} · {e.__class__.__name__})", file=sys.stderr)
            return 4
    n = {v: sum(1 for r in rows if r["verdict"] == v) for v in VERDICTS}
    print(f"triage={len(rows)} real={n[REAL]} name={n[MNAME]} example={n[EXAMPLE]} unknown={n[UNKNOWN]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
