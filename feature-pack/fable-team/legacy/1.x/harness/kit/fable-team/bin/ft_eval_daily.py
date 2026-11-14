#!/usr/bin/env python3
"""ft_eval_daily.py — 매일 10:00 «오빠와 함께 볼 평가 1건» (r1446).

오빠 지시 2026-11-06 «매일 평가해보자 오전 10시쯤 나랑 하나씩».
  큐(state/eval/queue.md)에서 아직 안 본 항목 1개를 꺼내 → state/eval/daily-<날짜>.md 1장 →
  desk 좌석에 mbox 1통. 오늘 파일이 이미 있으면 SKIP(멱등 · 하루 1건).
  자동 수정·자동 승격·삭제 0. 측정은 실제로 읽은 값만(못 읽으면 «판정 불가» 1줄).

큐 형식: 한 줄 = 한 항목
  - [ ] 항목 제목 :: 확인 방법 1줄
  - [x] 이미 본 항목(날짜 붙음)
산출: daily-<날짜>.md = 항목 + 자동 실측(4~6줄) + «오빠께 물을 것 1개».
종료: 0 정상 · 1 큐 없음/쓰기 실패 · 2 usage · 3 판정 불가
"""
from __future__ import annotations

import datetime as dt
import json
import os
import subprocess
import sys
from pathlib import Path

H = Path.home()


def ft_root() -> Path:
    env = os.environ.get("FT_ROOT")
    if env:
        p = Path(env)
        # DA 3R 반례 1: plist 는 FT_ROOT=<프로젝트 루트> 를 준다 — 여기서 .fable-team 을 강제한다.
        if p.name != ".fable-team" and (p / ".fable-team").is_dir():
            p = p / ".fable-team"
        return p
    cwd = Path.cwd()
    for p in [cwd, *cwd.parents]:
        if (p / ".fable-team").is_dir():
            return p / ".fable-team"
    print("REJECT .fable-team 없음 — FT_ROOT 를 지정하라")
    sys.exit(2)


SEED_QUEUE = """# 매일 평가 큐 (한 줄 = 한 항목 · 하루 1건 · 오빠와 함께)
# 형식: - [ ] 제목 :: 확인 방법
- [ ] 좌석 기억이 실제로 실리는가 :: 새 좌석 부팅 프롬프트에 SNAPSHOT 줄이 보이는지
- [ ] 팀장 틱이 승격/폐기를 하는가 :: state/evolution/resolved-<오늘>.jsonl 에 promote ≥1 · discard ≥1(팀 무관)
- [ ] 하루 1회 진화 게이트가 도는가 :: evolution/last-run 이 오늘 날짜인지
- [ ] 팀 자동 발견이 새 팀을 잡는가 :: SYNC-TEAMS 발견 수 = team/*.jsonl 수인지
- [ ] 상시 로드가 다시 비대해지지 않았나 :: CLAUDE.md ≤12KB · rules ≤8KB · BOOT ≤2KB
- [ ] 100항목 밀어내기가 유실 없이 도는가 :: archive.jsonl 줄 수 = 밀려난 수인지
- [ ] 실험 기억이 TTL 로 정리되는가 :: 만료된 experiment 가 목록에서 빠졌는지
- [ ] 주입 스캔 오탐이 좌석을 막지 않는가 :: 정상 교훈 add 가 rc0 인지
- [ ] DA 반례 추세가 줄고 있나 :: 라운드별 반례 수(8 → 4 → ?)
- [ ] 좌석 생성 4경로가 모두 snapshot 을 지시하나 :: grep 4파일
- [ ] 데몬 실패가 조용히 묻히지 않나 :: state/*.log 의 «판정 불가» 건수
- [ ] 다음 개선 후보 1건 고르기 :: evolve LATEST 의 학습 후보 중 1개
"""


def load_queue(q: Path) -> list[tuple[int, str, str]]:
    items = []
    for i, line in enumerate(q.read_text(encoding="utf-8").splitlines(), 1):
        s = line.strip()
        if not s.startswith("- ["):
            continue
        done = s[3:4].lower() == "x"
        body = s.split("]", 1)[1].strip()
        title, _, how = body.partition("::")
        items.append((i, title.strip(), (how.strip() if how else ""), done))
    return items  # type: ignore[return-value]


def measure(root: Path) -> list[str]:
    """그날 실제로 읽은 값만. 하나라도 못 읽으면 그 줄에 «판정 불가»."""
    out = []
    ev = root / "state" / "evolution"
    lr = ev / "last-run"
    today = dt.date.today().strftime("%Y%m%d")
    out.append("진화 게이트 last-run = %s" % (lr.read_text(encoding="utf-8").strip() if lr.is_file() else "없음(판정 불가)"))
    out.append("오늘 게이트 실행 = %s" % ("O" if (lr.is_file() and lr.read_text(encoding="utf-8").strip() == today) else "X"))
    lat = ev / "LATEST"
    if lat.is_file():
        head = lat.read_text(encoding="utf-8").strip().splitlines()[0]
        cand = ev / head.split()[-1] if head else None
        if cand and cand.is_file():
            txt = cand.read_text(encoding="utf-8")
            learn = txt.split("## 학습 후보", 1)[1].split("##", 1)[0] if "## 학습 후보" in txt else ""
            scrap = txt.split("## 폐기 후보", 1)[1] if "## 폐기 후보" in txt else ""
            out.append("후보 = 학습 %d · 폐기 %d" % (learn.count("- "), scrap.count("- ")))
        else:
            out.append("후보 = 판정 불가(LATEST 대상 없음)")
    else:
        out.append("후보 = 판정 불가(LATEST 없음)")
    out.append("승격/폐기 판단 = %s" % resolved_verdict(ev / ("resolved-%s.jsonl" % today)))
    tdir = root / "state" / "lessons" / "team"
    files = sorted(f for f in tdir.glob("*.jsonl") if ".archive" not in f.name) if tdir.is_dir() else []
    filled = [f.stem for f in files if f.stat().st_size > 0]
    out.append("팀 기억 = %d팀 파일 · 교훈 있는 팀 %d (%s)" % (len(files), len(filled), ",".join(filled) if filled else "없음"))
    sdir = root / "state" / "lessons" / "seat"
    seats = [f for f in sdir.glob("*.jsonl") if ".archive" not in f.name] if sdir.is_dir() else []
    out.append("좌석 기억 = %d파일" % len(seats))
    # 승격 후보(좌석 3회·2좌석+) — ft-lessons suggest 를 그대로 쓴다(로직 중복 0)
    ls = root / "bin" / "ft-lessons.sh"
    if ls.is_file():
        try:
            r = subprocess.run(["bash", str(ls), "suggest"], capture_output=True, text=True, timeout=7,
                               env={**os.environ, "FT_ROOT": str(root)})
            line = [l for l in (r.stdout or "").splitlines() if l.startswith("SUGGEST")]
            out.append("승격 후보 = %s" % (line[0] if line else "판정 불가"))
        except Exception:
            out.append("승격 후보 = 판정 불가(ft-lessons suggest 실패)")
    cl = H / ".claude" / "CLAUDE.md"
    rules = sorted((H / ".claude" / "rules").glob("*.md"))
    out.append("상시 로드 = CLAUDE.md %sB(≤12,288) · rules %sB(≤8,192)"
               % (cl.stat().st_size if cl.is_file() else "?", sum(r.stat().st_size for r in rules) or "?"))
    return out


def resolved_verdict(f: Path) -> str:
    """r1467: 팀장 resolve 기록(ft-lessons resolve)으로 기계 판정 — promote ≥1 · discard ≥1(팀 무관)이면 통과."""
    n = {"promote": 0, "discard": 0}
    try:
        rows = f.read_text(encoding="utf-8").splitlines() if f.is_file() else []
        for line in filter(str.strip, rows):
            v = json.loads(line).get("verdict")
            if v in n:
                n[v] += 1
    except (OSError, ValueError, AttributeError) as e:
        return "판정 불가(%s · %s)" % (type(e).__name__, f.name)
    ok = n["promote"] >= 1 and n["discard"] >= 1
    return "오늘 resolved promote %d · discard %d → %s" % (n["promote"], n["discard"], "통과" if ok else "고칠 것 후보")


def resolve_desk(root: Path) -> str:
    """오빠 화면 좌석(desk)을 명부에서 찾는다 — 이름을 코드에 박지 않는다(과적합 방지 r1450).
    우선순위: seats-*.json 키 중 «-desk-» 를 포함하는 현역(_replaced_by 없음) 1개."""
    best = ""
    for f in sorted(root.glob("seats-*.json")):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(d, dict):
            continue
        for k, v in d.items():
            if "-desk-" in k and not (isinstance(v, dict) and v.get("_replaced_by")):
                best = k
    return best


def cmd_run(argv: list[str]) -> int:
    dry = "--dry-run" in argv
    root = ft_root()
    # DA 3R 반례 4: 동시 실행 락 — 날짜 검사·쓰기·송신을 한 임계구역에 둔다(중복 발송 0)
    lock_fh = None
    if not dry:
        lock_dir = root / "state" / "eval"
        try:
            lock_dir.mkdir(parents=True, exist_ok=True)
            lock_fh = open(lock_dir / ".eval.lock", "a+", encoding="utf-8")
            import fcntl
            fcntl.flock(lock_fh, fcntl.LOCK_EX)
        except Exception:
            lock_fh = None  # 락 실패해도 멈추지 않는다(아래 날짜 검사는 유지)
    edir = root / "state" / "eval"
    q = edir / "queue.md"
    today = dt.date.today().strftime("%Y%m%d")
    day = edir / ("daily-%s.md" % today)
    if day.is_file() and not dry:
        print("EVAL SKIP date=%s 이미 오늘 1건 만들었다(파일 변경 0)" % today)
        if lock_fh:
            lock_fh.close()
        return 0
    if not q.is_file():
        if dry:
            print("EVAL dry-run queue=없음(생성 예정 %d항목) 파일 변경 0" % len([l for l in SEED_QUEUE.splitlines() if l.startswith("- [")]))
            return 0
        edir.mkdir(parents=True, exist_ok=True)
        q.write_text(SEED_QUEUE, encoding="utf-8")
    items = load_queue(q)
    todo = [x for x in items if not x[3]]
    if not todo:  # 큐 소진 → 첫 항목부터 다시(순환 · 새 항목은 사람이 추가)
        print("EVAL 큐 소진 — 처음부터 순환(새 항목은 %s 에 추가)" % q)
        todo = items[:1]
    idx, title, how, _ = todo[0]
    meas = measure(root)
    body = [
        "# 오늘의 평가 1건 — %s" % dt.date.today().strftime("%Y-%m-%d"),
        "",
        "## 항목",
        "- **%s**" % title,
        "- 확인 방법: %s" % (how or "(없음)"),
        "",
        "## 자동 실측 (읽은 값만)",
    ] + ["- " + m for m in meas] + [
        "",
        "## 오빠께 물을 것 (1개)",
        "- %s — 지금 상태를 «통과 / 고칠 것 / 보류» 중 하나로 정해 주세요." % title,
        "",
        "> 답이 오면 큐에서 이 항목을 `- [x] %s` 로 바꾸고, 고칠 것이면 카드 1장으로 만든다." % title,
    ]
    text = "\n".join(body) + "\n"
    if dry:
        print("EVAL dry-run date=%s 항목=%s (파일 변경 0)" % (today, title))
        return 0
    edir.mkdir(parents=True, exist_ok=True)
    day.write_text(text, encoding="utf-8")
    lines = q.read_text(encoding="utf-8").splitlines()
    lines[idx - 1] = lines[idx - 1].replace("- [ ]", "- [x]", 1)
    q.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("EVAL date=%s 항목=%s → %s (큐 %d/%d)" % (today, title, day.name, len([x for x in items if not x[3]]) - 1, len(items)))
    # desk 1통 (오빠 화면). 실패해도 파일은 남는다.
    desk = os.environ.get("FT_EVAL_DESK") or resolve_desk(root) or ""
    me = os.environ.get("FT_EVAL_FROM", "ft-eval-daily")
    mbox = root / "bin" / "ft-mbox.sh"
    if mbox.is_file() and desk and os.environ.get("FT_EVAL_NO_SEND") != "1":
        msg = ("[평가] 오늘의 1건 — %s\n확인: %s\n%s\n파일 %s\n오빠 답: 통과 / 고칠 것 / 보류 중 하나"
               % (title, how or "-", " · ".join(meas[:3]), day))
        try:
            r = subprocess.run(["bash", str(mbox), "send", desk, me, msg], capture_output=True, text=True, timeout=7)
            print("EVAL mbox to=%s rc=%d" % (desk, r.returncode))
        except Exception as e:  # 쪽지 실패는 파일을 덮지 않는다(하드 룰 20)
            print("EVAL mbox 판정 불가(%s) — 파일은 남았다" % type(e).__name__)
    elif not desk:
        print("EVAL mbox 생략 — desk 좌석을 명부에서 못 찾았다(FT_EVAL_DESK 로 지정)")
    if lock_fh:
        lock_fh.close()
    return 0


def main() -> int:
    argv = sys.argv[1:]
    if argv and argv[0] in ("-h", "--help"):
        print("usage: ft-eval-daily.sh [--dry-run]")
        return 0
    unknown = [a for a in argv if a not in ("--dry-run",)]
    if unknown:
        print("REJECT 모르는 인자: %s" % unknown[0])
        return 2
    return cmd_run(argv)


if __name__ == "__main__":
    sys.exit(main())
