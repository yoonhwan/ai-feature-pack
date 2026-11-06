#!/usr/bin/env python3
"""ft_evolve.py — 세대진화(evolve) 스캐폴드. r1434.

무엇: 하루치 로그·쪽지·LESSONS 를 읽어 «학습 후보» 와 «폐기 후보» 를 세는 얇은 게이트.
  새 크론 0 — ft-issues-daily(00:10) 끝에서 `--gate` 로 하루 1회만 돈다. 게이트 표식 = <FT_ROOT>/state/evolution/last-run.
  세대(generation) — xclaw 아카이브 `nanoclaw-deep-analysis.md` 의 «세대 진화 = in-place + gen-{N} 버전 파일» 을 따른다:
  지침을 폴더 복사·이름변경으로 굴리지 않고, 같은 자리에 `gen-<N>.md` 로 세대를 쌓는다(참조가 안 깨진다).
  LLM 호출 0 — 집계는 규칙만. «무엇을 학습/폐기할지» 결정은 사람이 후보 목록을 보고 한다(자동 승격·자동 삭제 없음).
  dry-run = 파일 변경 0(표식도 안 쓴다). apply = candidates-<날짜>.md + last-run 기록.

입력(읽기 전용):
  ~/.claude/logs/boot-read-gate.log       차단(deny) 반복 → 학습 후보(같은 차단 3회+ = 규칙 문구가 안 읽힌다)
  <FT_ROOT>/comm/mailbox.jsonl            최근 1일 쪽지 → 막힘·반송·HIL 키워드 반복 = 학습 후보
  <FT_ROOT>/state/lessons/{seat,team}     최근 교훈 → 팀 승격 후보(같은 태그 3회+)
  <FT_ROOT>/state/*.log                   «판정 불가»·ERROR 반복 = 학습 후보
  <FT_ROOT>/state/**/*.bak-* · *.archive-* 30일 넘은 사본 → 폐기 후보
종료코드: 0 정상 · 2 usage · 1 수집 실패(로그 없음은 실패 아님 — 후보 0 으로 센다)
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

H = Path.home()
LIMIT_DAYS = 30
KEYWORDS = ("막힘", "반송", "REJECT", "판정 불가", "[멈춤]", "HIL")


def ft_root() -> Path:
    env = os.environ.get("FT_ROOT")
    if env:
        return Path(env)
    cwd = Path.cwd()
    for p in [cwd, *cwd.parents]:
        if (p / ".fable-team").is_dir():
            return p / ".fable-team"
    print("REJECT .fable-team 없음 — FT_ROOT 를 지정하라")
    sys.exit(2)


def since_day() -> dt.datetime:
    return dt.datetime.now() - dt.timedelta(days=1)


def read_deny(log: Path) -> list[str]:
    if not log.is_file():
        return []
    counts: dict[str, int] = {}
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines()[-4000:]:
        if " deny " not in line:
            continue
        m = re.search(r"(COMM-GUIDE[\w.-]*|[^\s]+\.md)", line)
        if m:
            counts[m.group(0)] = counts.get(m.group(0), 0) + 1
    return ["%s 차단 %d회" % (k, v) for k, v in sorted(counts.items(), key=lambda x: -x[1]) if v >= 3]


def read_mail(root: Path) -> list[str]:
    mb = root / "comm" / "mailbox.jsonl"
    if not mb.is_file():
        return []
    cutoff = since_day()
    hits: dict[str, int] = {}
    for line in mb.read_text(encoding="utf-8", errors="replace").splitlines()[-3000:]:
        try:
            d = json.loads(line)
        except Exception:
            continue
        ts = str(d.get("ts") or d.get("time") or "")[:19]
        try:
            if dt.datetime.fromisoformat(ts) < cutoff:
                continue
        except Exception:
            continue
        body = str(d.get("body") or "")
        for k in KEYWORDS:
            if k in body:
                hits[k] = hits.get(k, 0) + 1
    return ["쪽지 키워드 %s %d건/1일" % (k, v) for k, v in sorted(hits.items(), key=lambda x: -x[1]) if v >= 3]


def read_lessons(root: Path) -> list[str]:
    out = []
    d = root / "state" / "lessons" / "seat"
    if not d.is_dir():
        return out
    tags: dict[str, int] = {}
    for f in sorted(d.glob("*.md")):
        for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
            for t in KEYWORDS:
                if t in line:
                    tags[t] = tags.get(t, 0) + 1
    for t, n in sorted(tags.items(), key=lambda x: -x[1]):
        if n >= 3:
            out.append("좌석 LESSONS '%s' %d회 → 팀 LESSONS 승격 후보" % (t, n))
    return out


def read_state_logs(root: Path) -> list[str]:
    out = []
    for f in sorted(root.glob("state/*.log"))[:40]:
        try:
            txt = f.read_text(encoding="utf-8", errors="replace")[-20000:]
        except Exception:
            continue
        n = txt.count("판정 불가") + txt.count("ERROR")
        if n >= 3:
            out.append("%s 실패·판정불가 %d회" % (f.name, n))
    return out


def read_stale(root: Path) -> list[str]:
    out = []
    cut = dt.datetime.now().timestamp() - LIMIT_DAYS * 86400
    for p in list(root.glob("state/**/*.bak-*"))[:400] + list(root.glob("state/**/*.archive-*"))[:400]:
        try:
            if p.stat().st_mtime < cut:
                out.append("%s (%d일 경과)" % (p.relative_to(root), int((dt.datetime.now().timestamp() - p.stat().st_mtime) / 86400)))
        except Exception:
            continue
    return out[:40]


def main(argv: list[str]) -> int:
    mode = "dry-run"
    for a in argv:
        if a in ("--dry-run", "--apply", "--gate", "--verbose", "-v"):
            if a == "--apply":
                mode = "apply"
            elif a == "--gate":
                mode = "gate"
        elif a in ("-h", "--help"):
            print("usage: ft-evolve.sh [--dry-run|--apply|--gate] [--verbose]")
            return 0
        else:
            print("REJECT 모르는 인자: %s" % a)
            return 2
    root = ft_root()
    today = dt.date.today().strftime("%Y%m%d")
    stamp = root / "state" / "evolution" / "last-run"
    if mode == "gate" and stamp.is_file() and stamp.read_text(encoding="utf-8").strip() == today:
        print("EVOLVE gate SKIP date=%s 이미 오늘 돌았다(파일 변경 0)" % today)
        return 0
    learn = read_deny(H / ".claude/logs/boot-read-gate.log") + read_mail(root) + read_lessons(root) + read_state_logs(root)
    scrap = read_stale(root)
    files_changed = 0
    if mode in ("apply", "gate"):
        out = root / "state" / "evolution" / ("candidates-%s.md" % today)
        out.parent.mkdir(parents=True, exist_ok=True)
        body = ["# evolve 후보 — %s (ft-evolve %s)" % (today, mode), "", "## 학습 후보 (%d)" % len(learn)]
        body += ["- " + x for x in learn] or ["- 없음"]
        body += ["", "## 폐기 후보 (%d)" % len(scrap)] + (["- " + x for x in scrap] or ["- 없음"])
        out.write_text("\n".join(body) + "\n", encoding="utf-8")
        gens = sorted(out.parent.glob("gen-*.md"))
        gen = len(gens) + 1
        g = out.parent / ("gen-%03d.md" % gen)
        g.write_text("# 세대 %03d — %s\n\n" % (gen, today) + "\n".join(body) + "\n", encoding="utf-8")
        stamp.write_text(today + "\n", encoding="utf-8")
        files_changed = 3
        gen_note = " gen=%03d" % gen
    else:
        gen_note = ""
    print("EVOLVE %s date=%s 학습 후보 %d · 폐기 후보 %d (파일 변경 %d)%s" % (mode, today, len(learn), len(scrap), files_changed, gen_note))
    if "--verbose" in argv or "-v" in argv:
        for x in learn:
            print("  학습: " + x)
        for x in scrap:
            print("  폐기: " + x)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
