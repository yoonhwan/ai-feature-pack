r"""ft_da_metrics.py — 하네스 카드별 DA 회차 «전» 값을 한 번에 센다 (r983 · 읽기 전용 · 게이트 0 · 외부 호출 0).

출력 = 요약 1줄 + 표 1장.
  `cards=<n> calls_mean=<x> first_approve=<a>/<n> gap_median=<m>min holds=<h>`
    n = since 이후 DA .out(`evidence/<rNNN>-da*/da-*.out`)이 있는 카드 수 — 평균의 분모도 이 수다.
    holds = «## 상태» 의 DA②/DA⑥ … HOLD 사건 수(ft_da_hold_gate.py 의 EVENT 정규식·(단계, rN) 키 규칙 재사용).
    ★holds 와 calls 는 단위가 다르다(C1) — APPROVE·판정 줄 없음 회차도 calls 에 들어간다.★
  표 열 = card · holds · calls · first · gap_med · wall · respawn · scope · revert30
    holds = «## 상태» 반송 사건 · calls = since 이후 .out 수 · first = 첫 .out 의 마지막 `판정:`(없으면 `?`)
    gap_med = 그 카드 .out 사이 간격 중앙값(분) · wall = «## 상태» 첫 시각 → 마지막 시각(시간 · `x` 표기면 `~`)
    respawn = `대기→진행` 줄 수 · scope = `## 구현 범위` 의 `N. ` 항목 수
    revert30 = 착지 뒤 30일 되돌림(완성 이동이 30일 지난 카드만 셈 · `yes`/`no` · 창 전이면 `미도래` ·
               완성 이동 줄은 있는데 시각이 없으면 `확인 불가` · 완성 이동 줄이 없으면 `-`)
  쪼갠 카드 = `- 선행:` 줄이 푸는 카드가 «이름 변형» 이면 그 모카드 칸에 `+` 로 합쳐 보인다(요약은 카드별 1회 — 중복 0).
  미완료(대기·진행) 카드는 빼지 않고 `[미완료]` 표식.

읽기 실패는 0 으로 보이지 않는다(C2) — 카드 폴더 없음·카드 0장이면 `확인 불가` rc3, 개별 카드/파일이 안 읽히면
그 행을 `확인 불가` 로 적고 요약 끝에 `확인 불가 <k>장` + rc3. ★증거 폴더(`evidence/<rNNN>-da*`)가 있는데 못 읽는
경우도 같다(C2 · DA r2 수용 1) — `glob` 이 빈 목록으로 삼키지 않게 폴더를 «직접» 열어 보고, 못 열면 그 카드 = `확인 불가`
+ rc3, 회차 간격 모집단에서도 빼고 `NOTE 읽기실패 <폴더>` 를 남긴다.★ 7초 룰: 파일 읽기만 한다(서브프로세스·git 0).

인자: [<루트>] [--root R] [--team harness] [--since YYYY-MM-DD]
카드 = `<루트>/design[/teams]/<팀>/indices/{대기,진행,완성,아카이브}/*.md` · 시험 env FT_DA_METRICS_NOW(30일 창 «오늘»).
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import statistics as stats
import sys
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

OUT = re.compile(r"^da-(\d{8})-(\d{6})-\d+\.out$")
VS = re.compile(r"^판정:\s*(\[확인 필요\]|HOLD|APPROVE)", re.M)   # 3값 매칭 — `[확인 필요]` 가 `[확인` 으로 잘리지 않는다
TS = re.compile(r"(\d{4}-\d\d-\d\d)(?:[ ]+(\d{1,2}):([0-9x]{2}))?")
SCOPE = re.compile(r"^\d+\.\s", re.M)
PRED = re.compile(r"^- 선행:[ \t]*(.+)$", re.M)
DATED = re.compile(r"^\s*-?\s*\d{4}-\d\d-\d\d")   # 상태 «기록 줄» — 날짜로 시작
UNDATED = re.compile(r"^\s*-\s*[가-힣]{0,4}\s*→\s*[가-힣]{2}\s*(?:·|$)")   # 날짜 없는 전이 기록(설명문·인용은 아님)
FOLDERS = ("대기", "진행", "완성", "아카이브")
WINDOW = 30


def stamp(line: str, timed: bool = True):
    """상태 줄의 첫 시각 → (datetime, 근사여부) · 없으면 None. timed=True 면 `HH:MM` 있는 줄만."""
    m = TS.search(line)
    if not m or (timed and m.group(2) is None):
        return None
    try:
        d = datetime.strptime(m.group(1), "%Y-%m-%d")
    except ValueError:
        return None
    if m.group(2) is None:
        return (d, True)
    approx = "x" in m.group(3)
    try:
        return (d.replace(hour=int(m.group(2)), minute=0 if approx else int(m.group(3))), approx)
    except ValueError:
        return (d, True)


def state_lines(txt: str, gate) -> list[str]:
    """«## 상태» 줄들 — 게이트의 state_span 재사용(절 경계 판정 하나)."""
    lo, hi = gate.state_span(txt)
    return txt[lo:hi].splitlines()


def entry(line: str) -> bool:
    """상태 «기록 줄» 인가 — 설명문(«- 진행→완성 이동은 …»)은 전이가 아니다."""
    return bool(DATED.match(line) or UNDATED.match(line))


def residue(line: str) -> str:
    """전이 줄의 «무엇에서 무엇으로» — 예 `진행→완성`."""
    m = re.search(r"([가-힣]{2})\s*→\s*([가-힣]{2})", line)
    return f"{m.group(1)}→{m.group(2)}" if m else ""


def scope_body(txt: str) -> str:
    m = re.search(r"^##\s*구현 범위[^\n]*\n(.*?)(?=^##\s|\Z)", txt, re.S | re.M)
    return m.group(1) if m else ""


def counter(txt: str, gate) -> dict:
    lines = state_lines(txt, gate)
    logs = [ln for ln in lines if entry(ln)]
    stamped = [(ln, stamp(ln, False)) for ln in logs]   # 이동·되돌림은 «날짜» 만 있어도 센다
    move = [s for ln, s in stamped if residue(ln).endswith("→완성")]
    return {
        "holds": len(gate.scan(lines)["events"]),
        "respawn": sum(1 for ln in logs if residue(ln) == "대기→진행"),
        "moves": [s for s in move if s],
        "move_lines": len(move),
        "reverts": [s for ln, s in stamped if residue(ln).startswith("완성→") and s],
        "wall": [s for ln, s in ((ln, stamp(ln, False)) for ln in logs) if s],
        "scope": len(SCOPE.findall(scope_body(txt))),
    }


def entries(d: str):
    """폴더 안 이름 목록 — 못 읽으면 None(«읽기 실패» 를 «0건» 으로 보이지 않는다 · glob 은 오류를 빈 목록으로 삼킨다)."""
    try:
        return sorted(os.listdir(d))
    except OSError:
        return None


def outs_of(evroot: str, stem: str, since_tag: str):
    """그 카드의 .out → [(시각|None, 판정, 파일명, 경로)] · 시각 오름차순(시각 없는 것은 뒤). 읽기 실패는 None.

    증거 폴더 이름은 카드 번호 꼴(`r961-da6`)과 카드 이름 꼴(`r961-...-da1`) 두 가지가 쓰인다 — 둘 다 본다.
    """
    got = []
    dirs = set(glob.glob(os.path.join(evroot, stem.split("-")[0] + "-da*"))) | set(glob.glob(os.path.join(evroot, stem + "-da*")))
    for d in sorted(dirs):
        names = entries(d)
        if names is None:
            return None          # 증거 폴더가 있는데 못 읽음 = calls 0 이 아니라 «확인 불가»(C2)
        for o in [os.path.join(d, n) for n in names if n.startswith("da-") and n.endswith(".out")]:
            m = OUT.match(os.path.basename(o))
            when = None
            if m:
                if since_tag and m.group(1) < since_tag:
                    continue
                when = datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M%S")
            try:
                with open(o, encoding="utf-8", errors="replace") as f:
                    vs = VS.findall(f.read())
            except OSError:
                return None
            got.append((when, vs[-1] if vs else "?", os.path.basename(o), o))
    got.sort(key=lambda r: (r[0] is None, r[0] or datetime.min))
    return got


def reverts_30(cnt: dict, now: datetime) -> str:
    if not cnt["move_lines"]:
        return "-"
    if not cnt["moves"]:
        return "확인 불가"
    due = [t for t, _ in cnt["moves"] if now - t >= timedelta(days=WINDOW)]
    if not due:
        return "미도래"
    win = timedelta(days=WINDOW)
    return "yes" if any(timedelta(0) < (rv - mv) <= win for mv in due for rv, _ in cnt["reverts"]) else "no"


def wall_of(times: list) -> str:
    if not times:
        return "확인 불가"
    if len(times) < 2:
        return "0.0h"
    lo, hi = min(t for t, _ in times), max(t for t, _ in times)
    return f"{(hi - lo).total_seconds() / 3600:.1f}h" + ("~" if any(a for _, a in times) else "")


def median_gap(outs: list) -> str:
    when = [w for w, *_ in outs if w]
    if len(when) < 2:
        return "-"
    return f"{stats.median([(b - a).total_seconds() / 60 for a, b in zip(when, when[1:])]):.0f}"


def pooled_gaps(evroot: str, since_tag: str) -> list:
    """회차 간격(분) — 증거 폴더 전부의 .out 시각을 폴더 안에서 이어 붙인다(ANALYSIS §1 과 같은 셈)."""
    gaps, unseen = [], []
    for d in sorted(glob.glob(os.path.join(evroot, "r*-da*"))):
        names = entries(d)
        if names is None:
            unseen.append(d)      # 못 읽는 폴더는 모집단에서 빼되 «조용히» 빼지 않는다(NOTE + rc3)
            continue
        when = []
        for n in names:
            m = OUT.match(n) if (n.startswith("da-") and n.endswith(".out")) else None
            if m and not (since_tag and m.group(1) < since_tag):
                when.append(datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M%S"))
        gaps += [(b - a).total_seconds() / 60 for a, b in zip(when, when[1:])]
    return gaps, unseen


def variant(child: str, parent: str) -> bool:
    """쪼갠 카드 이름 꼴 — 부모 이름 + `-rN` 꼬리, 또는 앞 번호에 글자 꼬리(r118 → r118b)."""
    if child.startswith(parent + "-r") and re.fullmatch(r"r\d+", child[len(parent) + 1:]):
        return True
    c = child.split("-")[0]
    return bool(re.fullmatch(r"r\d+[a-z]", c) and parent.split("-")[0] == c.rstrip("abcdefghijklmnopqrstuvwxyz"))


def pred_parent(txt: str, stem: str, stems: set) -> str:
    """쪼갠 카드의 모카드 — `- 선행:` 줄이 푸는 카드 중 «이름이 그 카드의 변형» 인 것만(단순 선행 = 밀린 카드다)."""
    m = PRED.search(txt)
    for tok in re.findall(r"[A-Za-z0-9][A-Za-z0-9_-]+", m.group(1)) if m else []:
        for cand in sorted(s for s in stems if s != stem and (s == tok or s.split("-")[0] == tok)):
            if variant(stem, cand):
                return cand
    return ""


def union(r: dict, kids: list) -> list:
    """모카드 1장의 .out 전부 — 모카드·쪼갠 카드의 증거 폴더를 경로로 합친다(같은 파일 두 번 0)."""
    seen = {o[3]: o for src in [r] + kids for o in src["outs"]}
    return sorted(seen.values(), key=lambda o: (o[0] is None, o[0] or datetime.min))


def own(r: dict, key: str) -> int:
    return len(r["outs"]) if key == "calls" else r["cnt"][key]


def cells(r: dict, kids: list, key: str) -> int:
    """모카드 + 쪼갠 카드 합 — 쪼갠 카드의 증거 폴더·카드 값은 모카드 1장으로 접힌다(C3)."""
    return own(r, key) + sum(own(k, key) for k in kids)


def merged(r: dict, kids: list, key: str) -> str:
    """표 칸 — 쪼갠 카드가 있으면 `2+1` 처럼 보인다(모카드 합 · 요약 합계는 카드별 1회)."""
    return str(own(r, key)) + "".join("+" + str(own(k, key)) for k in kids)


def calls_cell(r: dict, kids: list, mo: list) -> str:
    """호출 칸 — 모카드 1장의 .out 수(쪼갠 카드 증거는 `3+1` 로 보인다) · 시각 없는 .out 이 있으면 `?`."""
    base, extra = own(r, "calls"), len(mo) - own(r, "calls")
    return (f"{base}+{extra}" if extra else str(base)) + ("?" if any(o[0] is None for o in mo) else "")


def mark(r: dict) -> str:
    """표 첫 칸 — 카드 이름 그대로(한 행 = 9열)."""
    tag = "" if r["folder"] in ("완성", "아카이브") else "[미완료] "
    name = r["stem"]
    return tag + name + (f" ↳{r['parent']}" if r["parent"] else "")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("root", nargs="?", default="")
    ap.add_argument("--root", dest="root_opt", default="")
    ap.add_argument("--team", default="harness")
    ap.add_argument("--since", default="")
    a = ap.parse_args()
    root = os.path.abspath(a.root_opt or a.root or os.environ.get("FT_HARNESS_ROOT") or os.getcwd())
    now = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)   # 날짜만 있는 값 = 자정 기준
    if os.environ.get("FT_DA_METRICS_NOW"):
        now = datetime.strptime(os.environ["FT_DA_METRICS_NOW"], "%Y-%m-%d")
    try:
        import ft_da_hold_gate as gate
    except ImportError as e:  # 판정기 없음 = 셈 불가(0 으로 보이지 않는다)
        print(f"확인 불가: ft_da_hold_gate.py 없음 ({e})")
        return 3
    idx = next((p for p in (os.path.join(root, "design", "teams", a.team, "indices"),
                            os.path.join(root, "design", a.team, "indices")) if os.path.isdir(p)), "")
    if not idx:
        print(f"확인 불가: 카드 폴더 없음 design[/teams]/{a.team}/indices ({root})")
        return 3
    ev = os.path.join(os.path.dirname(idx), "evidence")
    cards = []
    for f in FOLDERS:
        d = os.path.join(idx, f)
        try:
            cards += [(f, os.path.join(d, n)) for n in sorted(os.listdir(d)) if n.endswith(".md")]
        except FileNotFoundError:
            continue                      # 폴더가 없는 것은 0장(있는 폴더를 못 읽는 것과 다르다)
        except OSError:
            print(f"확인 불가: 카드 폴더를 못 읽음 {d}")
            return 3
    if not cards:
        print(f"확인 불가: 카드 0장 ({idx})")
        return 3
    since_tag, rows, bad, notes = a.since.replace("-", ""), [], 0, []
    stems = {os.path.basename(p)[:-3] for _, p in cards}
    for folder, path in cards:
        stem = os.path.basename(path)[:-3]
        row = {"folder": folder, "stem": stem, "bad": True, "parent": "", "outs": [], "cnt": None}
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                txt = fh.read()
        except OSError:
            rows.append(row)
            bad += 1
            continue
        dates = re.findall(r"\d{4}-\d\d-\d\d", "\n".join(state_lines(txt, gate)))
        if since_tag and dates and max(dates) < a.since:
            continue                      # 날짜가 «없는» 카드는 빼지 않는다 — 조용히 사라지면 0 으로 보인다
        outs = outs_of(ev, stem, since_tag)
        if outs is None:
            rows.append(row)
            bad += 1
            continue
        row.update(bad=False, cnt=counter(txt, gate), outs=outs, parent=pred_parent(txt, stem, stems))
        notes += [f"NOTE 시각없음 {stem} {b}" for w, _v, b, _p in outs if w is None]
        rows.append(row)

    fold: dict = {}
    for r in rows:
        if r["parent"]:
            fold.setdefault(r["parent"], []).append(r)
    out = []
    for r in sorted(rows, key=lambda x: x["stem"]):
        if r["bad"]:
            out.append("\t".join([mark(r)] + ["확인 불가"] * 8))
            continue
        kids = fold.get(r["stem"], [])
        mo = union(r, kids)
        calls = calls_cell(r, kids, mo)
        out.append("\t".join([mark(r), merged(r, kids, "holds"), calls,
                              mo[0][1] if mo else "-", median_gap(mo),
                              wall_of(r["cnt"]["wall"]), str(r["cnt"]["respawn"]),
                              merged(r, kids, "scope"), reverts_30(r["cnt"], now)]))
    roots = [r for r in rows if not r["bad"] and not r["parent"]]   # 쪼갠 카드는 모카드 1장으로 센다(C3)
    live = [(r, union(r, fold.get(r["stem"], []))) for r in roots]
    live = [(r, mo) for r, mo in live if mo]
    gaps, unseen = pooled_gaps(ev, since_tag)
    calls = [len(mo) for _r, mo in live]
    mean_s = f"{stats.mean(calls):.2f}" if calls else "확인 불가"      # 잰 카드가 0장이면 0 이라고 쓰지 않는다
    gap_s = f"{stats.median(gaps):.0f}min" if gaps else "확인 불가"
    print(f"cards={len(live)} calls_mean={mean_s} "
          f"first_approve={sum(1 for _r, mo in live if mo[0][1].startswith('APPROVE'))}/{len(live)} "
          f"gap_median={gap_s} "
          f"holds={sum(cells(r, fold.get(r['stem'], []), 'holds') for r, _mo in live)}"
          + (f" · 확인 불가 {bad}장" if bad else ""))
    print(f"# cards = since 이후 DA .out 있는 카드 · calls_mean = 그 카드들의 호출 평균 · holds = «## 상태» HOLD 사건 합"
          f" · since={a.since or '전체'} · scope={len(rows)}장")
    print("# card\tholds\tcalls\tfirst\tgap_med\twall\trespawn\tscope\trevert30")
    print("\n".join(out))
    print("\n".join(notes + [f"NOTE 읽기실패 {os.path.basename(d)}" for d in unseen]))
    return 3 if bad or unseen or not live else 0


if __name__ == "__main__":
    sys.exit(main())
