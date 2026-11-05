#!/usr/bin/env python3
"""ft_issues_daily.py — r1115 매일 00:10 «이슈 일일 표» (읽기 전용 · 쓰기 0 · 쪽지 2통).

왜 있나: 골 6 «매일 00시 이슈 정리·중복 묶기» 의 00시가 한 번도 «장치» 가 된 적이 없다 — 세션 크론은 승계·재부팅에 사라졌고
야간 검토는 1회성이었다. 이 파일은 launchd 1개(com.byz.ft-issues-daily · 00:10)가 부르는 «읽기 전용» 표 생성기다.
라벨·배정·닫기·코멘트 쓰기 0 · 좌석 열기 0 · press 0. 결정은 사람(planner·issues master)이 아침에 한다.

산출 = <FT_ROOT>/design/teams/issues/daily/TABLE-daily-<YYYYMMDD>.md 1장 + mbox 2통(본문 다름 — FANOUT 가드).
  ① 머리(건수 · 합 검산 · 어제 차이)   ② 정리(24h 열림/닫힘 · 7일+ 정체 · 중복 후보)
  ③ 분류(작성 경로 4종 = ft-issue-classify 재사용)   ④ 우선순위 후보 ⓐⓒⓑⓓⓔ
  ⑤ 팀 배정 후보   ⑥ 닫기 후보(8항 코멘트 확인 · 실행 0)
전부 «후보» 다 — 판정 낱말(확정·승인)을 쓰지 않는다. 쓰기는 사람이 한다.

실패 = «판정 불가» 표 + rc≠0 (하드 룰 20 — 빈 표로 숨김 0) · gh·분류 호출 = 회당 7초 + 재시도 1 (하드 룰 12).
전팀 정지(ft-all-stop.sh check rc≠0)·자원 동결(RESOURCE_FREEZE) 표식이면 «건너뜀(사유)» 표 1장 + 쪽지 1통(빈 표 0).

env: FT_ROOT(리포 공용 루트) · FT_NOW(시험 시계 초) · FT_GH(gh 대역) · FT_MBOX_SH · FT_ISSUES_DAILY_DIR(표 폴더)
     FT_ISSUES_DAILY_TIMEOUT_S(기본 7) · FT_ISSUES_DAILY_CLASSIFY(cmd) · FT_ALLSTOP · FT_ISSUES_DAILY_NO_SEND=1
rc: 0 정상 · 5 판정 불가 · 2 usage
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
SENDER = "ft-issues-daily"
DAY = 86400.0
LABEL_APPROVED = "approved"
LABEL_PP = "status:proposal-pending"
LABEL_NT = "needs-triage"
STALE_DAYS = 7


class Unjudgeable(RuntimeError):
    """판정 불가 — 표에 «판정 불가» 로 적고 rc≠0 (조용한 0 금지 · 하드 룰 20)."""


# ── 자리·시계 (정본 순서 = ft-penalty.root ①FT_ROOT ②옛 설치 꼴 ③cwd git 공용 루트) ──
def _common(path: Path) -> Path | None:
    try:
        out = subprocess.run(
            ["git", "-C", str(path), "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, timeout=7,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    line = out.stdout.strip()
    return Path(line).parent if out.returncode == 0 and line else None


def root() -> Path:
    root_env = os.environ.get("FT_ROOT")
    if root_env:
        return Path(root_env)
    if HERE.name == "bin" and HERE.parent.name == ".fable-team":
        return _common(HERE) or HERE.parent.parent
    common = _common(Path.cwd())
    if common and (common / ".fable-team").is_dir():
        return common
    sys.exit("ERROR 리포 공용 루트를 못 풂 — FT_ROOT 없음 · cwd 가 .fable-team/ 있는 git 리포 아님")


def now() -> float:
    return float(os.environ.get("FT_NOW") or time.time())


def limit_s() -> int:
    try:
        return max(1, int(os.environ.get("FT_ISSUES_DAILY_TIMEOUT_S") or 7))
    except ValueError:
        return 7


# ── 외부 호출: 회당 7초 상한 + 재시도 1 (하드 룰 12 · 실패 처리 한 곳) ──
def _timeout_bin() -> str:
    for cand in ("timeout", "gtimeout"):
        found = shutil.which(cand)
        if found:
            return found
    raise Unjudgeable("timeout(coreutils) 없음 — 7초 상한을 걸 수 없다")


def run(argv: list[str], what: str, limit: int | None = None) -> bytes:
    lim = str(limit or limit_s())
    last = ""
    for _ in (1, 2):
        try:
            proc = subprocess.run([_timeout_bin(), lim] + argv, capture_output=True)
        except OSError as exc:
            raise Unjudgeable(f"{what} 실행 실패 — {exc}")
        if proc.returncode == 0:
            return proc.stdout
        if proc.returncode == 124:
            last = f"{lim}초 초과"
        else:
            err = proc.stderr.decode("utf-8", "replace")
            last = next((ln for ln in err.splitlines() if ln.strip()), "") or f"rc={proc.returncode}"
    raise Unjudgeable(f"{what} 실패(2회) — {last}")


# ── 입력 ──
def gh_open(gh: str) -> tuple[bytes, list[dict]]:
    raw = run([gh, "issue", "list", "--state", "open", "--limit", "1000",
               "--json", "number,title,labels,createdAt,updatedAt,body,comments"], "gh issue list")
    try:
        data = json.loads(raw.decode("utf-8", "replace"))
    except ValueError as exc:
        raise Unjudgeable(f"gh issue list JSON 파싱 실패 — {exc}")
    if not isinstance(data, list):
        raise Unjudgeable("gh issue list 결과가 배열이 아니다")
    return raw, [norm_issue(d) for d in data if isinstance(d, dict)]


def gh_closed_24h(gh: str, now_ts: float, date_arg: str) -> list[int] | None:
    """닫힌(24h) — 실패하면 None(그 칸만 «판정 불가» · 표 전체는 살린다)."""
    since = datetime.fromtimestamp(now_ts - DAY, timezone.utc).strftime("%Y-%m-%d")
    try:
        raw = run([gh, "issue", "list", "--state", "closed", "--limit", "200",
                   "--search", f"closed:>={since}", "--json", "number,closedAt"], "gh issue list --state closed")
        data = json.loads(raw.decode("utf-8", "replace"))
    except (Unjudgeable, ValueError):
        return None
    if not isinstance(data, list):
        return None
    out = []
    for row in data:
        if not isinstance(row, dict):
            continue
        stamp = _epoch(row.get("closedAt"))
        if stamp is not None and now_ts - stamp < DAY:
            out.append(int(row.get("number") or 0))
    return sorted(n for n in out if n)


def _epoch(text: object) -> float | None:
    if not isinstance(text, str) or not text.strip():
        return None
    try:
        return datetime.fromisoformat(text.strip().replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def norm_issue(raw: dict) -> dict:
    labels = []
    for lab in raw.get("labels") or []:
        name = (lab.get("name") if isinstance(lab, dict) else str(lab)) or ""
        if name:
            labels.append(name)
    comments = []
    for cm in raw.get("comments") or []:
        if isinstance(cm, dict) and isinstance(cm.get("body"), str):
            comments.append(cm["body"])
    return {
        "n": int(raw.get("number") or 0),
        "title": re.sub(r"\s+", " ", str(raw.get("title") or "")).strip(),
        "labels": labels,
        "created": _epoch(raw.get("createdAt")),
        "updated": _epoch(raw.get("updatedAt")),
        "body": str(raw.get("body") or ""),
        "comments": comments,
    }


# ── 칸 계산 ──
def bucket(issue: dict) -> str:
    """한 이슈 = 한 칸 (합 검산이 닫히게 순서 고정): 라벨 없음 → approved → proposal-pending → needs-triage → 그 밖."""
    labels = issue["labels"]
    if not labels:
        return "none"
    if LABEL_APPROVED in labels:
        return "approved"
    if LABEL_PP in labels:
        return "pp"
    if LABEL_NT in labels:
        return "nt"
    return "other"


def norm_title(title: str) -> str:
    text = re.sub(r"\[[^\]]*\]", " ", title.lower())          # [v65] 같은 머리꼬리 제거
    text = re.sub(r"[^0-9a-z가-힣]+", "", text)
    return text


def duplicates(issues: list[dict]) -> list[list[int]]:
    groups: dict[str, list[int]] = {}
    for it in issues:
        key = norm_title(it["title"])
        if key:
            groups.setdefault(key, []).append(it["n"])
    return [sorted(ns) for ns in groups.values() if len(ns) > 1]


def priority_axis(issue: dict, stale: bool) -> str:
    """ⓐ 오빠 지시·priority → ⓒ proposal-pending → ⓑ bug+재현 → ⓓ 7일+ 정체 → ⓔ 나머지.
    ⓒ 를 ⓑ 앞에 두는 이유: proposal-pending 은 «게이트 앞» 이라 어느 목록에도 안 실려 묻힌다(판정 2776 · #3807)."""
    labels = issue["labels"]
    if any(lab.startswith("priority:") or lab in ("from:oppa", "from:member") for lab in labels):
        return "ⓐ"
    if LABEL_PP in labels:
        return "ⓒ"
    if "type:bug" in labels and re.search(r"재현", issue["body"] or ""):
        return "ⓑ"
    if stale:
        return "ⓓ"
    return "ⓔ"


TEAM_HINTS = (
    ("v65", ("v65",)),
    ("issues", ("이슈", "issue")),
    ("planner", ("플래너", "planner", "판정")),
    ("knowledge", ("매거진", "magazine", "지식")),
    ("harness", ("하네스", "launchd", "ft-", "biolark")),
)


def team_hint(issue: dict) -> tuple[str, str]:
    """⑤ 팀 배정 후보 — team:* 라벨이 없을 때만. 라벨 쓰기 0 · 결정 = planner/issues master."""
    for lab in issue["labels"]:
        if lab.startswith("team:"):
            return "", ""
    hay = f"{issue['title']}\n{issue['body'][:2000]}".lower()
    for team, words in TEAM_HINTS:
        for word in words:
            if word.lower() in hay:
                return team, f"제목·본문 키워드 «{word}»"
    return "", ""


CLOSE_ITEMS = ("닫는 사건", "PR", "재현 PASS", "정리", "기록")
_LINE = r"^\s*[-*]?\s*(\[[ xX]\]\s*)?{k}\s*[:：]\s*[^<\s]"


def _has_item(comments: list[str], key: str) -> bool:
    rx = re.compile(_LINE.format(k=re.escape(key)))
    return any(rx.search(ln) for body in comments for ln in body.splitlines())


def _pick_last(comments: list[str], key: str) -> str:
    rx = re.compile(_LINE.format(k=re.escape(key)))
    found = [ln.strip() for body in comments for ln in body.splitlines() if rx.search(ln)]
    if not found:
        return ""
    tail = re.sub(r"^\s*[-*]?\s*(\[[ xX]\]\s*)?" + re.escape(key) + r"\s*[:：]\s*", "", found[-1])
    return tail.strip()


def close_candidate(issue: dict) -> tuple[bool, str]:
    """⑥ 닫기 후보 = 8항이 «코멘트로» 다 있는 것 (실행 0 · 여기서 닫지 않는다).
    실행 판정 정본 = ft-issue-close-check.sh (design/harness/ISSUE-TRANSITIONS.md §3) — 이 칸은 «후보» 만 고른다."""
    comments = issue["comments"]
    if not comments:
        return False, ""
    missing = [k for k in CLOSE_ITEMS if not _has_item(comments, k)]
    if missing:
        return False, f"빠진 항목: {','.join(missing)}"
    canon = [_pick_last(comments, "정본"), _pick_last(comments, "정본 영향 없음")]
    if not (_has_item(comments, "정본") or _has_item(comments, "정본 영향 없음")):
        return False, "빠진 항목: 정본"
    if not any(canon):
        return False, "정본 칸이 빈 줄"
    cause = _pick_last(comments, "원인 확정")
    if not re.match(r"^[Yy]\s*[—–-]+\s*\S", cause):
        return False, f"원인 확정={cause or '없음'}"
    hold = _pick_last(comments, "같은 증상 보류")
    if not re.match(r"^0\s*$", hold):
        return False, f"같은 증상 보류={hold or '없음'}"
    return True, "8항 코멘트 확인"


def classify(issues_raw: bytes, root_dir: Path) -> dict | None:
    """③ 작성 경로 4종 — ft-issue-classify.sh --from-json 재사용(규칙 재작성 0). 실패 = None(그 칸 «판정 불가»)."""
    script = Path(os.environ.get("FT_ISSUES_DAILY_CLASSIFY") or HERE / "ft-issue-classify.sh")
    if not script.is_file() or not shutil.which("jq"):
        return None
    tmp = None
    try:
        with tempfile.NamedTemporaryFile("wb", suffix=".json", delete=False) as fh:
            fh.write(issues_raw)
            tmp = Path(fh.name)
        proc = subprocess.run([_timeout_bin(), "20", "bash", str(script), "--from-json", str(tmp)],
                              capture_output=True, text=True)
        if proc.returncode != 0:
            return None
        line = next((ln for ln in reversed(proc.stdout.splitlines()) if ln.startswith("SUMMARY ")), "")
    except (OSError, subprocess.SubprocessError):
        return None
    finally:
        if tmp is not None:
            tmp.unlink(missing_ok=True)
    if not line:
        return None
    return {m.group(1): int(m.group(2)) for m in re.finditer(r"(①|②|③|④|미분류)=(\d+)", line)}


# ── 정지·동결 표식 ──
def guard(root_dir: Path) -> str:
    state = root_dir / ".fable-team/state"
    if (state / "RESOURCE_FREEZE").exists():
        return "자원 동결 표식(RESOURCE_FREEZE)"
    allstop = os.environ.get("FT_ALLSTOP") or str(HERE / "ft-all-stop.sh")
    if not Path(allstop).is_file():
        return ""
    proc = subprocess.run([_timeout_bin(), "20", "bash", allstop, "check"], capture_output=True)
    if proc.returncode != 0:
        return "전팀 정지(ALL_STOP)"
    return ""


# ── 표 ──
def table_path(root_dir: Path, date: str) -> Path:
    base = Path(os.environ.get("FT_ISSUES_DAILY_DIR") or root_dir / "design/teams/issues/daily")
    return base / f"TABLE-daily-{date}.md"


def read_yesterday(root_dir: Path, date: str) -> dict | None:
    prev = (datetime.strptime(date, "%Y%m%d") - timedelta(days=1)).strftime("%Y%m%d")
    path = table_path(root_dir, prev)
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    head = re.search(r"열린 총수:\s*(\d+)", text)
    return {"date": prev, "open": int(head.group(1)) if head else None}


def build(issues: list[dict], closed24: list[int] | None, cls: dict | None, yday: dict | None,
          now_ts: float, date: str) -> tuple[str, dict]:
    stamp = datetime.fromtimestamp(now_ts).strftime("%Y-%m-%d %H:%M")
    counts = {"approved": 0, "pp": 0, "nt": 0, "none": 0, "other": 0}
    for it in issues:
        counts[bucket(it)] += 1
    total = len(issues)
    new24 = sorted(it["n"] for it in issues if it["created"] is not None and now_ts - it["created"] < DAY)
    stale = [it for it in issues if it["updated"] is not None and now_ts - it["updated"] >= STALE_DAYS * DAY]
    stale.sort(key=lambda it: it["updated"] or 0)
    dups = duplicates(issues)
    stale_ids = {id(it) for it in stale}
    axes: dict[str, list[dict]] = {"ⓐ": [], "ⓑ": [], "ⓒ": [], "ⓓ": [], "ⓔ": []}
    for it in issues:
        axes[priority_axis(it, id(it) in stale_ids)].append(it)
    team_rows = [it for it in issues if team_hint(it)[0]]
    close_rows = [(it, why) for it, why in ((it, close_candidate(it)[1]) for it in issues) if close_candidate(it)[0]]
    type_labeled = sum(1 for it in issues if any(lab.startswith("type:") for lab in it["labels"]))
    team_labeled = sum(1 for it in issues if any(lab.startswith("team:") for lab in it["labels"]))
    neither = sum(1 for it in issues
                  if not any(lab.startswith(("type:", "team:")) for lab in it["labels"]))

    line: list[str] = []
    add = line.append
    add(f"# 이슈 일일 표 — {stamp} (일일 장치 · launchd com.byz.ft-issues-daily · 00:10)")
    add("")
    add("장치가 쓴 표다. 라벨·배정·닫기·코멘트 쓰기 0 — 결정은 사람(planner · issues master)이 한다.")
    add(f"스냅샷: 열린 이슈 {total}건 · 닫힌(24h) {len(closed24) if closed24 is not None else '판정 불가'}건")
    add("")
    add("## ① 머리")
    add("")
    add(f"- 열린 총수: {total}")
    add(f"- 상태별: approved {counts['approved']} · status:proposal-pending {counts['pp']}"
        f" · needs-triage {counts['nt']} · 라벨 없음 {counts['none']} · 그 밖 {counts['other']}")
    add(f"- 합: {counts['approved']}+{counts['pp']}+{counts['nt']}+{counts['none']}+{counts['other']} = {total}"
        " (한 이슈 = 한 칸 · approved → proposal-pending → needs-triage → 라벨 없음 → 그 밖 순서 첫 일치)")
    if yday and yday.get("open") is not None:
        delta = total - int(yday["open"])
        add(f"- 어제 대비: +{len(new24)} −{len(closed24) if closed24 is not None else 0}"
            f" · 열린 총수 {yday['open']}→{total} ({delta:+d}) · 어제 표 TABLE-daily-{yday['date']}.md")
    else:
        add("- 어제 대비: 차이: 첫 표")
    add("")
    add("## ② 정리")
    add("")
    add(f"- 새로 열린(24h): {len(new24)}건{' ' + short_nums(new24) if new24 else ''}")
    if closed24 is None:
        add("- 닫힌(24h): 판정 불가 (gh issue list --state closed 실패)")
    else:
        add(f"- 닫힌(24h): {len(closed24)}건{' ' + short_nums(closed24) if closed24 else ''}")
    add(f"- 7일+ 정체(갱신일 기준): {len(stale)}건"
        + (" " + " ".join(f"#{it['n']}({(now_ts - (it['updated'] or now_ts)) / DAY:.0f}일)" for it in stale[:20])
           if stale else ""))
    if dups:
        add(f"- 중복 후보(제목 정규화 같음): {sum(len(g) * (len(g) - 1) // 2 for g in dups)}쌍 "
            + " · ".join(" ≈ ".join(f"#{n}" for n in g[:3]) for g in dups[:10]))
    else:
        add("- 중복 후보(제목 정규화 같음): 0쌍")
    add("")
    add("## ③ 분류")
    add("")
    if cls is None:
        add("- 작성 경로: 판정 불가 (ft-issue-classify 실패)")
    else:
        add(f"- 작성 경로: ① 기획 세션 {cls.get('①', 0)} · ② 세션 에이전트 {cls.get('②', 0)}"
            f" · ③ 오빠 GitHub {cls.get('③', 0)} · ④ 사내 멤버 {cls.get('④', 0)} · 미분류 {cls.get('미분류', 0)}")
    add(f"- 라벨: type:* {type_labeled}건 · team:* {team_labeled}건 · 둘 다 없음 {neither}건")
    add("")
    add("## ④ 우선순위 후보 (규칙 고정 · 쓰기 0 · 결정 = planner)")
    add("")
    add("축 순서 ⓐ → ⓒ → ⓑ → ⓓ → ⓔ · ⓒ(proposal-pending)를 ⓑ 앞에 두는 이유 = 게이트 앞이라 어느 목록에도 안 실려 묻힌다(판정 2776).")
    add("")
    add("| # | 축 | 제목 | 근거 |")
    add("|---|---|---|---|")
    for axis in ("ⓐ", "ⓒ", "ⓑ", "ⓓ", "ⓔ"):
        for it in axes[axis]:
            add(f"| #{it['n']} | {axis} | {cell(it['title'])} | {axis_why(it, axis, stale)} |")
    if total == 0:
        add("| — | — | 열린 이슈 0 | — |")
    add("")
    add("축별: " + " · ".join(f"{a} {len(axes[a])}" for a in ("ⓐ", "ⓑ", "ⓒ", "ⓓ", "ⓔ")))
    add("")
    add("## ⑤ 팀 배정 후보 (team:* 라벨 없는 것만 · 배정 쓰기 0)")
    add("")
    if team_rows:
        add("| # | 팀 후보 | 근거 |")
        add("|---|---|---|")
        for it in team_rows:
            team, why = team_hint(it)
            add(f"| #{it['n']} | {team}(후보) | {cell(why)} |")
    else:
        add("- 없음 (team:* 없는 이슈에 키워드 근거 0 — 에이전트·planner 가 직접 분류)")
    add("")
    add("## ⑥ 닫기 후보 (8항 코멘트 확인 · 실행 0 · 번호만)")
    add("")
    if close_rows:
        for it, _why in close_rows:
            add(f"- #{it['n']} {cell(it['title'])}")
    else:
        add("- 없음")
    add("")
    add("## 장치가 하지 않은 것")
    add("")
    add("- 라벨 부여·배정·닫기·코멘트 쓰기 0 · 좌석 열기 0 · press 0")
    add("- 카드 대조 = ft-issue-card-audit.sh --tick (이 표 밖 · ref 읽기라 표 시간 상한에 안 넣는다)")
    add("- 닫기 8항 실제 판정 = ft-issue-close-check.sh <#> (정본 design/harness/ISSUE-TRANSITIONS.md §3)")
    counts_out = dict(counts, total=total, stale=len(stale), dups=len(dups),
                      close=len(close_rows), team=len(team_rows), new24=len(new24),
                      closed24=len(closed24) if closed24 is not None else -1)
    return "\n".join(line) + "\n", counts_out


def cell(text: str) -> str:
    return re.sub(r"\s+", " ", text).replace("|", "/")[:70] or "—"


def short_nums(nums: list[int]) -> str:
    return " ".join(f"#{n}" for n in nums[:20]) + (" …" if len(nums) > 20 else "")


def axis_why(issue: dict, axis: str, stale: list[dict]) -> str:
    if axis == "ⓐ":
        hit = [lab for lab in issue["labels"] if lab.startswith("priority:") or lab in ("from:oppa", "from:member")]
        return f"라벨 {','.join(hit)}"
    if axis == "ⓒ":
        return f"라벨 {LABEL_PP} (게이트 앞)"
    if axis == "ⓑ":
        return "라벨 type:bug + 본문 재현"
    if axis == "ⓓ":
        return "갱신 7일+"
    return "위 축 아님"


def skip_table(why: str, date: str, now_ts: float) -> tuple[str, dict]:
    stamp = datetime.fromtimestamp(now_ts).strftime("%Y-%m-%d %H:%M")
    body = "\n".join([
        f"# 이슈 일일 표 — {stamp} (일일 장치 · launchd com.byz.ft-issues-daily · 00:10)",
        "",
        f"## 건너뜀 — {why}",
        "",
        "- 이 회차는 표를 만들지 않았다(빈 표 아님 · 사유를 적는다).",
        "- 해제 뒤 다음 00:10 회차가 표를 쓴다 · 급하면 `ft-issues-daily.sh --date <YYYYMMDD>` 를 손으로 1회.",
        "",
    ])
    return body, {"skipped": why}


def unjudgeable_table(why: str, date: str, now_ts: float) -> tuple[str, dict]:
    stamp = datetime.fromtimestamp(now_ts).strftime("%Y-%m-%d %H:%M")
    body = "\n".join([
        f"# 이슈 일일 표 — {stamp} (일일 장치 · launchd com.byz.ft-issues-daily · 00:10)",
        "",
        "## 판정 불가",
        "",
        f"- 원인: {why}",
        "- 열린 이슈를 못 읽어 표를 만들지 못했다 — 0건으로 적지 않는다(하드 룰 20).",
        "- 다음 회차 = 내일 00:10 · 급하면 `ft-issues-daily.sh --date <YYYYMMDD>` 를 손으로 1회.",
        "",
    ])
    return body, {"unjudgeable": why}


# ── 쪽지 ──
def roster_master(root_dir: Path, team: str) -> str:
    path = root_dir / ".fable-team" / ("seats.json" if team == "v65" else f"seats-{team}.json")
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return ""
    if not isinstance(doc, dict):
        return ""
    master = doc.get("_master")
    if isinstance(master, str) and master.strip():
        return master.strip()
    best, best_n = "", -1
    for name, row in doc.items():
        if name.startswith("_") or not isinstance(row, dict):
            continue
        if row.get("role") != "master" or row.get("_replaced_by"):
            continue
        tail = name.rsplit("#", 1)[-1]
        num = int(tail) if tail.isdigit() else 0
        if num > best_n:
            best, best_n = name, num
    return best


def mail(mbox: str, to: str, body: str) -> int:
    if not to:
        print(f"WARN {SENDER}: 받는 좌석을 못 찾음 — 쪽지 0 ({body.splitlines()[0][:60]})", file=sys.stderr)
        return 1
    argv = ["bash", mbox, "send", to, SENDER, body, "--urgent"]
    try:
        proc = subprocess.run([_timeout_bin(), "30"] + argv, capture_output=True, text=True)
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"WARN {SENDER}: 쪽지 실패 {to} — {exc}", file=sys.stderr)
        return 1
    if proc.returncode != 0:
        tail = next((ln for ln in proc.stderr.splitlines() if ln.strip()), f"rc={proc.returncode}")
        print(f"WARN {SENDER}: 쪽지 실패 {to} — {tail}", file=sys.stderr)
    return proc.returncode


def planner_body(date: str, note: str, counts: dict) -> str:
    if "skipped" in counts or "unjudgeable" in counts:
        why = counts.get("skipped") or counts.get("unjudgeable")
        return (f"[{'건너뜀' if 'skipped' in counts else '판정 불가'}] 00시 이슈 표 {date} — {why}\n"
                f"표: design/teams/issues/daily/TABLE-daily-{date}.md\n"
                "다음: 사유 해제 뒤 다음 00:10 회차 · 급하면 ft-issues-daily.sh 손 1회")
    return (f"[완료] 00시 이슈 표 {date} — 열린 {counts['total']}"
            f"(approved {counts['approved']} · proposal-pending {counts['pp']} · 라벨 없음 {counts['none']})"
            f" · 7일+ {counts['stale']} · 중복 후보 {counts['dups']} · 닫기 후보 {counts['close']} · 팀 후보 {counts['team']}\n"
            "골좌표: A6 이슈 관리 ⑥ «00시 정리 첫 실행 RESULT 1회» — 이 표 1장이 그 RESULT\n"
            f"표: design/teams/issues/daily/TABLE-daily-{date}.md{note}")


def issues_body(date: str, counts: dict) -> str:
    if "skipped" in counts or "unjudgeable" in counts:
        why = counts.get("skipped") or counts.get("unjudgeable")
        return (f"[{'건너뜀' if 'skipped' in counts else '판정 불가'}] 00시 이슈 표 {date} — {why}\n"
                f"표: design/teams/issues/daily/TABLE-daily-{date}.md · 집행 0")
    return (f"[완료] 00시 이슈 표 {date} — 열린 {counts['total']} · 닫기 후보 {counts['close']}"
            f" · 팀 후보 {counts['team']} · 7일+ {counts['stale']}\n"
            "집행 3줄: 1) 닫기 후보는 ft-issue-close-check.sh <#> 실행 뒤 닫기 2) 팀 후보는 team:* 라벨 부여 3) 7일+ 정체는 우선순위 재판정\n"
            f"표: design/teams/issues/daily/TABLE-daily-{date}.md (열 이름·규칙 = GUIDE-issues.md §일일 표)")


# ── main ──
def main(argv: list[str]) -> int:
    dry = False
    date = None
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--dry-run":
            dry = True
            i += 1
        elif arg == "--date" and i + 1 < len(argv):
            date = argv[i + 1]
            i += 2
        else:
            print("usage: ft-issues-daily.sh [--dry-run] [--date YYYYMMDD]", file=sys.stderr)
            return 2
    now_ts = now()
    date = date or datetime.fromtimestamp(now_ts).strftime("%Y%m%d")
    if not re.fullmatch(r"\d{8}", date):
        print(f"usage: --date 는 YYYYMMDD 8자리 (받은 값 {date})", file=sys.stderr)
        return 2
    root_dir = root()
    target = table_path(root_dir, date)
    gh = os.environ.get("FT_GH") or "gh"
    mbox = os.environ.get("FT_MBOX_SH") or str(root_dir / ".fable-team/comm/mbox.sh")
    send_planned = not dry and os.environ.get("FT_ISSUES_DAILY_NO_SEND") != "1"

    why = guard(root_dir)
    rc = 0
    counts: dict = {}
    if why:
        text, counts = skip_table(why, date, now_ts)
    else:
        try:
            raw, issues = gh_open(gh)
        except Unjudgeable as exc:
            text, counts = unjudgeable_table(str(exc), date, now_ts)
            rc = 5
        else:
            closed24 = gh_closed_24h(gh, now_ts, date)
            cls = classify(raw, root_dir)
            text, counts = build(issues, closed24, cls, read_yesterday(root_dir, date), now_ts, date)

    if dry:
        sys.stdout.write(text)
        print(f"DRY 표={target} 쪽지 0 · 판정={'정상' if rc == 0 else '판정 불가'}", file=sys.stderr)
        return rc
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
    except OSError as exc:
        print(f"ERROR {SENDER}: 표 쓰기 실패 {target} — {exc}", file=sys.stderr)
        return 1
    print(f"TABLE {target}")
    if rc != 0:
        print(f"ERROR {SENDER}: 판정 불가 — {counts.get('unjudgeable', '')}", file=sys.stderr)
    if send_planned:
        body_args = [k for k in counts if k in ("skipped", "unjudgeable")]
        targets = [("planner", planner_body(date, "", counts))]
        if not body_args:   # R6·R7: 건너뜀·판정 불가 = 쪽지 «1통» (planner) · FANOUT 가드도 2통 본문이 다를 때만 통과
            targets.append(("issues", issues_body(date, counts)))
        bad = 0
        for team, body in targets:
            bad += mail(mbox, roster_master(root_dir, team), body) != 0
        print(f"MAIL sent={len(targets) - bad} failed={bad}")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
