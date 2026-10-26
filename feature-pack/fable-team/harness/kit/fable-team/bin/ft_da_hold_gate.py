#!/usr/bin/env python3
"""ft_da_hold_gate.py <카드> [--entry <②|⑥> <rN> [--record --order-file F]] [--closing] [--lint] [--root R] [--seats F|--seats-dir D] [--comm D|--mailbox F] [--resume-dir D]
같은 카드 DA 보류(HOLD) 사건 셈 — 판정 2282 · 설계 DESIGN-da-hold2-redesign-research-loop §7·§8·§9 (판정기 하나 · 외부 호출 0).
  사건 = «## 상태» 줄 전체에서 `DA②|DA⑥ … HOLD`(사이 40자 · 다른 단계 기호·발주·CLOSE·APPROVE 없음) → 키 (단계, 라운드 · `rN` 이 사이에 없으면 r1). 같은 키는 몇 줄이든 1 사건.
    `DA`+`HOLD` 가 있는데 단계 기호가 없는 줄(`DA r1 HOLD`)은 UNPARSED rc3.
  해제 = 카드 줄 `- 재설계 해제: #<seq>` 의 mbox 쪽지: 머리 `[재설계 해제 <카드>.md]` ∧ `해제=1` ∧ `새 범위` ∧ `DESIGN r<N>` ∧ from ∈ 명부 `_master`·`_hil_route` 현역 «정확 일치» 또는 같은 계보 직전 세대
         (베이스 이름 같음 · 번호 작음 · seat-resume/<이름>.json 실재) ∧ to 도 `_arch` 계보 같은 규칙 · 같은 seq 2번째부터 DUP.
  입장 기록 = 가드가 입장을 허용하는 순간(--entry --record) 카드 상태 끝에 `- DA 입장: <단계>r<N> · 발주서 <경로> · 해제 #<seq|없음> · <시각>` 1줄(유일한 쓰기 · 실패 = 입장 REJECT) · 같은 (단계, rN) 입장 줄이 이미 있으면 DUP-ENTRY.
  소진 = 해제 줄 «뒤» 의 `DA 입장` 줄(해제 하나당 1 · 입장 줄 없는 라운드의 CLOSE·HOLD 판정 줄도 소진) · arch 의 `발주` 줄은 입장 전제일 뿐 소진 아님.
  입장(§10) = 사건 < 2 또는 미소진 유효 해제 ≥ 1 — 사건은 «이력», 해제는 «입장권»(사건 2 이상이면 미소진 해제 1건 = 입장 1회 · 사건 수를 더 깎지 않는다).
    budget_left = 사건<2 ? 2−사건 : 미소진 유효 해제 수 · rc3 ⇔ budget_left ≤ 0.
출력 첫 줄 `HOLD events=<n> reviews=<m> releases=<유효>/<소진> budget_left=<b>` | `UNPARSED <줄>` | `NO-ORDER-LINE <단계> r<N>` | `DUP-ENTRY <단계>r<N>` | `ENTRY-WRITE-FAIL …` (+ 해제 줄들 RELEASE-OK·INVALID·DUP).
rc 0 = 통과 · 3 = 막음 · 2 = 인자·파일 오류. --closing = 완성 이동 검사(사건 ≥ 2 인데 유효 해제 0 이면 막음) · --lint = ft-index-lint 용 `INFO`/`BAD` 줄(항상 rc 0).
  착지(r456 · --closing 만) = 카드 «## 상태» `- 착지: <sha>`(또는 --landed · 둘 다면 일치) ∧ sha 가 착지 ref 조상(env FT_LAND_REF · 기본 origin/main) ∧ --da 판정문(§N 절)에
    «닫힘 — <카드 stem> — main `<같은 sha>`» 행 → 첫 줄 `LANDED-CLOSE sha=<sha> da=<--da>` rc0. 하나라도 빠지면 기존 판정 불변 + `LANDED-INVALID <사유>` 줄.
  r937: 착지 리포는 ft-team-lib.sh 의 ft_landed_repo(bash · 리포 판정 단일 출처)가 정한다 — sha 가 카드 리포에 없고 팩(하네스 코드 루트) 리포에 있으면 그 리포 ·
    판정문 행 «닫힘 — <카드> — main(팩) `<40hex>`» = 팩 리포 표식 · 표식과 실제가 어긋나면 `LANDED-INVALID marker-mismatch` · 어느 리포에도 없으면 `LANDED-INVALID not-found`.
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ft_git_capped import run as _run_capped, run_cmd as _run_cmd  # noqa: E402  (r937 r3 · git 조회 실행기 단일 출처)

EVENT = re.compile(r"DA([②⑥])((?:(?![②⑥]|DA|발주|CLOSE|APPROVE).){0,40}?)HOLD")
BARE = re.compile(r"(?<![A-Za-z])DA(?![②⑥A-Za-z\-]).{0,40}?HOLD")
ORDER = re.compile(r"DA([②⑥])\s*r(\d+)\s*발주")
CLOSEV = re.compile(r"DA([②⑥])\s*r(\d+)\s*CLOSE")
ENTRY = re.compile(r"^- DA 입장:\s*([②⑥])r(\d+)")
SEAT = re.compile(r"^(.*)#(\d+)$")
LANDED_LOOKUPS = 3   # landed_repo 의 bash 쪽 git 조회 수: 팩 루트 · 카드 리포 rev-parse · 팩 리포 rev-parse
LANDED = re.compile(r"^- 착지:\s*`?([0-9a-f]{7,40})\b")


def root_of(card: str) -> str:
    if os.environ.get("FT_ROOT"):
        return os.environ["FT_ROOT"]
    rc, out = git_capped(os.path.dirname(card), "rev-parse", "--path-format=absolute", "--git-common-dir")
    return re.sub(r"/\.git$", "", out.strip()) if rc == 0 else ""


def state_span(txt: str) -> tuple[int, int]:
    m = re.search(r"^##\s*상태[^\n]*\n(.*?)(?=^##\s|\Z)", txt, re.S | re.M)
    return (m.start(1), m.end(1)) if m else (len(txt), len(txt))


def find_record(seq: str, paths: list[str]) -> dict | None:
    for p in paths:
        if not os.path.isfile(p):
            continue
        for ln in open(p, encoding="utf-8", errors="replace"):
            if f'"seq": {seq},' in ln[:40]:
                try:
                    return json.loads(ln)
                except ValueError:
                    return None
    return None


def lineage(name: str, current: str | None, resume_dir: str) -> str:
    """현역 이름과 같거나 같은 계보 직전 세대(은퇴 기록 실재)면 라벨, 아니면 ""."""
    if not name or not current:
        return ""
    if name == current:
        return "현역"
    a, b = SEAT.match(name), SEAT.match(current)
    if a and b and a.group(1) == b.group(1) and int(a.group(2)) < int(b.group(2)) and os.path.isfile(os.path.join(resume_dir, name + ".json")):
        return f"계보 #{a.group(2)}→#{b.group(2)}"
    return ""


def release_check(seq: str, card: str, seats: dict | None, mbox: list[str], resume_dir: str) -> tuple[str, str]:
    """(어긋난 조건 | "", 발신 라벨)"""
    if not seats:
        return "명부 읽기 실패", ""
    rec = find_record(seq, mbox)
    if not rec:
        return "쪽지 없음", ""
    body = rec.get("body", "")
    if not body.split("\n", 1)[0].strip().startswith(f"[재설계 해제 {os.path.basename(card)}]"):
        return "머리 불일치", ""
    if "해제=1" not in body or not re.search(r"새 범위\s*[:：]?\s*\S", body) or not re.search(r"DESIGN r\d+", body):
        return "해제=1·새 범위·DESIGN r<N> 중 빠짐", ""
    frm = rec.get("from", "")
    lab = lineage(frm, seats.get("_master"), resume_dir) or lineage(frm, seats.get("_hil_route"), resume_dir)
    if not lab:
        return "from 이 명부 _master·_hil_route 현역·계보 직전 세대 아님", ""
    if not lineage(rec.get("to", ""), seats.get("_arch"), resume_dir):
        return "to 가 명부 _arch 현역·계보 아님", ""
    return "", f"from={frm}({lab})"


def scan(lines: list[str]) -> dict:
    s: dict = {"events": set(), "reviews": 0, "rels": [], "cons": [], "orders": set(), "entries": set(), "bad": []}
    for i, ln in enumerate(lines):
        t = ln.strip()
        m = re.match(r"^- 재설계 해제:\s*#(\d+)", t)
        if m:
            s["rels"].append((i, m.group(1)))
        e = ENTRY.match(t)
        if e:
            s["entries"].add((e.group(1), e.group(2)))
            s["cons"].append((i, (e.group(1), e.group(2)), "entry"))
            continue
        if re.search(r"DA[②⑥]\s*(?:r\d+)?\s*(?:발주|CLOSE|HOLD|APPROVE)", t):
            s["reviews"] += 1
        s["orders"].update((o.group(1), o.group(2)) for o in ORDER.finditer(t))
        hits = []
        for h in EVENT.finditer(t):
            r = re.search(r"r(\d+)", h.group(2))
            hits.append((h.group(1), r.group(1) if r else "1"))
        s["events"].update(hits)
        s["cons"] += [(i, k, "verdict") for k in hits] + [(i, (c.group(1), c.group(2)), "verdict") for c in CLOSEV.finditer(t)]
        if not hits and BARE.search(t):
            s["bad"].append(t)
    return s


def record_entry(card: str, key: tuple[str, str], order: str, seq: str) -> str:
    """입장 줄을 «## 상태» 끝에 쓴다. 실패 사유 또는 ""."""
    try:
        txt = open(card, encoding="utf-8").read()
        _, end = state_span(txt)
        stamp = datetime.datetime.now().isoformat(timespec="seconds")
        line = f"- DA 입장: {key[0]}r{key[1]} · 발주서 {order} · 해제 #{seq} · {stamp}\n"
        rest = txt[end:]
        open(card, "w", encoding="utf-8").write(txt[:end].rstrip("\n") + "\n" + line + ("\n" + rest.lstrip("\n") if rest.strip() else ""))
        return ""
    except OSError as e:
        return str(e)


def da_section(path: str, sec: str) -> str:
    """판정문 본문 — sec(§N) 가 있으면 `## ` 헤더에 §N 정확 일치(뒤가 숫자 아님)인 절만(ft-index-move 와 같은 규칙)."""
    txt = open(path, encoding="utf-8", errors="replace").read()
    if not sec:
        return txt
    pat = re.compile(r"^## .*" + re.escape(sec) + (r"(?!\d)" if sec.startswith("§") else ""))
    out, on = [], False
    for ln in txt.splitlines():
        if ln.startswith("## "):
            on = bool(pat.match(ln))
        if on:
            out.append(ln)
    return "\n".join(out)


def git_capped(repo: str, *args: str) -> tuple[int, str]:
    """(rc, stdout) — git 조회 1회 = 7초 상한 + 재시도 1 + 자식까지 정리 (r937 r3 · 실행기 = ft_git_capped.py · 시간 초과 = rc 124 · 실행 실패 = rc 128).
    T2: 0 = 있음 · 1 = «없음» · 그 밖은 «조회 실패» — 부르는 쪽이 없음으로 읽지 않는다."""
    rc, out = _run_capped(repo, args)
    return rc, out.decode("utf-8", "replace")


def landed_repo(sha: str, card_repo: str, marker: str) -> tuple[str, str, str]:
    """(리포 절대경로, full sha, LANDED-INVALID 사유) — 리포 판정 단일 출처 = ft-team-lib.sh 의 ft_landed_repo(bash · r937 ⓐ).
    팩 리포 = ft-harness-root.sh 가 푸는 하네스 코드 루트의 리포(못 풀면 빈 값 = 카드 리포만 본다) · 7초 상한 · 쓰기 0."""
    lib = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ft-team-lib.sh")
    script = ('d="$(dirname "$1")"; . "$1" || exit 9; hr=""; [ -f "$d/ft-harness-root.sh" ] && hr="$(. "$d/ft-harness-root.sh" && ft_harness_root "$d" 2>/dev/null)"'
              '; pk=""; if [ -n "$hr" ]; then pk="$(ft_git_capped 7 "$hr" rev-parse --show-toplevel)" || { printf "REJECT 팩 리포(%s) 루트 조회 실패(rc=%s) — 통과 0\\n" "$hr" "$?"; exit 1; }; fi'
              '; ft_landed_repo "$2" "$3" "$pk" "$4"')
    # 바깥 상한 = 안쪽 상한의 합 + 여유(하드 룰 12: min(고정비 + 7초×배수, 70)) — 안쪽 조회 1개 최악 ≈ 15초(7+0.5+7+정리) × 조회 3회(팩 루트·카드·팩).
    # 바깥이 안쪽보다 먼저 끊는 일 0 · 끊더라도 run_cmd 가 그룹에 SIGTERM → 안쪽 실행기가 자기 git 그룹까지 정리한다.
    outer = min(2 + 15 * LANDED_LOOKUPS, 70)
    rc, raw = _run_cmd(["bash", "-c", script, "x", lib, sha, card_repo, marker], outer)
    if rc == 124:
        return "", "", "LANDED-INVALID lookup-failed 리포 판정 시간 초과(%d초) — 통과 0" % outer
    if rc == 128:
        return "", "", "LANDED-INVALID resolve-failed bash 실행 실패"
    lines = raw.decode("utf-8", "replace").strip().splitlines()
    out = lines[-1] if lines else ""
    if rc != 0 or out.startswith("REJECT"):
        why = ("lookup-failed" if "조회 실패" in out else "not-found" if "못 찾음" in out
               else "marker-mismatch" if "표식" in out else "resolve-failed")
        return "", "", f"LANDED-INVALID {why} " + out.replace("REJECT ", "")
    repo, _, full = out.partition("\t")
    return repo, full, ""


def landed_check(card: str, lines: list[str], root: str, landed: str, da: str) -> tuple[str, str]:
    """(LANDED-CLOSE 첫 줄 | "", LANDED-INVALID 사유 | "") — 착지 주장(카드 줄·--landed)이 없으면 둘 다 ""."""
    claims = [m.group(1) for m in (LANDED.match(ln.strip()) for ln in lines) if m]
    if not claims and not landed:
        return "", ""
    stem = os.path.splitext(os.path.basename(card))[0]
    path = ""
    sec_txt = ""
    if da:
        path, _, sec = da.partition("#")
        path = path if os.path.isfile(path) or not root else os.path.join(root, path)
        if os.path.isfile(path):
            sec_txt = da_section(path, sec)
    # 표식 = 이 카드의 «닫힘 — <카드> — main|main(팩) `<40hex>`» 행 — 리포 선택자(main(팩) = 팩 리포 · r937)
    m = re.search(r"닫힘\s*—\s*" + re.escape(stem) + r"\s*—\s*main\s*(\(\s*팩\s*\))?\s*`?([0-9a-f]{40})\b", sec_txt)
    marker = "" if not m else "닫힘 — %s — main%s `%s`" % (stem, "(팩)" if m.group(1) else "", m.group(2))
    repo, sha, why = landed_repo(landed or claims[0], root, marker)
    if why:
        return "", why
    if landed and claims:
        for c in claims:
            if landed_repo(c, root, marker)[1] != sha:
                return "", "LANDED-INVALID mismatch 카드 착지 줄 ≠ --landed"
    ref = os.environ.get("FT_LAND_REF") or "origin/main"
    rrc, _ = git_capped(repo, "rev-parse", "--verify", "-q", ref + "^{commit}")
    if rrc > 1:
        return "", "LANDED-INVALID lookup-failed %s ref(%s) 조회 실패 rc=%s (통과 0)" % (repo, ref, rrc)
    if rrc != 0:   # 착지 ref 가 없다 = 그 리포에 랜딩 자체가 없다(«없음» 이지 조회 실패가 아니다)
        return "", "LANDED-INVALID not-ancestor " + sha
    arc, _ = git_capped(repo, "merge-base", "--is-ancestor", sha, ref)
    if arc > 1:
        return "", "LANDED-INVALID lookup-failed %s merge-base rc=%s (시간 초과 포함 · 통과 0)" % (repo, arc)
    if arc != 0:
        return "", "LANDED-INVALID not-ancestor " + sha
    if not da:
        return "", "LANDED-INVALID no-da (--da <판정문#§N> 없음)"
    if not os.path.isfile(path):
        return "", "LANDED-INVALID da-missing " + path
    if not m or m.group(2) != sha:
        return "", f"LANDED-INVALID no-da-row «닫힘 — {stem} — main `{sha[:10]}…`» 없음 ({da})"
    return f"LANDED-CLOSE sha={sha} da={da}", ""


def lint(txt: str, events: int) -> None:
    lines = txt.splitlines()
    if events >= 2 and not any(re.match(r"^- (재설계|리서치):", ln) for ln in lines):
        print("INFO DA 보류 2회 이상인데 «- 재설계:»·«- 리서치:» 줄 없음 (3번째 DA 발주는 쪽지 가드가 막는다 · BOOT 40)")
    viol = False
    for ln in lines:
        viol = True if ln.startswith("- 리서치 위반:") else False if ln.startswith("- 리서치:") else viol
        if viol and ln.startswith("- 리서치 채택:"):
            print("BAD 「- 리서치 채택:」 앞에 「- 리서치 위반:」 이 있다 — 위반 산출은 채택 불가(재질문 또는 새 워커 「- 리서치:」 줄 뒤에 채택)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("card")
    ap.add_argument("--entry", nargs=2, metavar=("STAGE", "ROUND"))
    for k in ("--closing", "--lint", "--record"):
        ap.add_argument(k, action="store_true")
    for k in ("--root", "--seats", "--seats-dir", "--comm", "--mailbox", "--order-file", "--resume-dir", "--landed", "--da"):
        ap.add_argument(k, default="")
    a = ap.parse_args()
    if not os.path.isfile(a.card):
        print("ERROR 카드 없음 " + a.card)
        return 2
    card = os.path.abspath(a.card)
    root = a.root or root_of(card)
    t = re.search(r"design/(?:teams/)?([a-z0-9]+)/indices/", card)
    team_file = "seats.json" if (not t or t.group(1) == "v65") else f"seats-{t.group(1)}.json"
    try:
        seats = json.load(open(a.seats or os.path.join(a.seats_dir or os.path.join(root, ".fable-team"), team_file), encoding="utf-8"))
    except (OSError, ValueError):
        seats = None
    comm = a.comm or os.path.join(root, ".fable-team", "comm")
    mbox = [a.mailbox] if a.mailbox else [os.path.join(comm, "mailbox.log.jsonl"), os.path.join(comm, "mailbox.jsonl")]
    resume = a.resume_dir or os.environ.get("FT_SEAT_RESUME_DIR") or os.path.expanduser("~/.claude/state/seat-resume")
    txt = open(card, encoding="utf-8").read()
    lo, hi = state_span(txt)
    s = scan(txt[lo:hi].splitlines())
    ekey = (a.entry[0], re.sub(r"\D", "", a.entry[1]) or "1") if a.entry else None
    notes, valid, seen = [], [], set()
    for i, seq in s["rels"]:
        why, lab = ("DUP", "") if seq in seen else release_check(seq, card, seats, mbox, resume)
        seen.add(seq)
        if not why:
            valid.append((i, seq))
            notes.append(f"RELEASE-OK #{seq} {lab}")
        else:
            notes.append(f"RELEASE-DUP #{seq}" if why == "DUP" else f"RELEASE-INVALID #{seq} {why}")
    cons = sorted(c for c in s["cons"] if c[2] == "entry" or c[1] not in s["entries"])
    used: dict[str, int] = {}
    for i, seq in valid:
        j = next((j for j, c in enumerate(cons) if c[0] > i and j not in used.values()), None)
        if j is not None:
            used[seq] = j
    free = [seq for _, seq in valid if seq not in used]
    budget = 2 - len(s["events"]) if len(s["events"]) < 2 else len(free)  # §10: 사건은 이력 · 해제는 입장권
    summary = f"HOLD events={len(s['events'])} reviews={s['reviews']} releases={len(valid)}/{len(used)} budget_left={budget}"
    if a.lint:
        lint(txt, len(s["events"]))
        return 0
    land_bad = ""
    if a.closing:  # r456: 착지 증거(조상 sha ∧ 판정문 행)는 완성 이동에서만 세 번째 통과 근거 — 입장(--entry)은 불변
        land_ok, land_bad = landed_check(card, txt[lo:hi].splitlines(), root, a.landed, a.da)
        if land_ok:
            print(land_ok)
            print(summary)
            return 0
        notes += [land_bad] if land_bad else []
    head = ""
    if s["bad"]:
        head = "UNPARSED " + s["bad"][0][:120]
    elif ekey and ekey in s["entries"]:
        head = f"DUP-ENTRY {ekey[0]}r{ekey[1]}"
    elif ekey and ekey not in s["orders"]:
        head = f"NO-ORDER-LINE DA{ekey[0]} r{ekey[1]}"
    if head:
        print(head)
        print(summary)
        if land_bad:
            print(land_bad)
        return 3
    blocked = (len(s["events"]) >= 2 and not valid) if a.closing else budget <= 0
    if ekey and not blocked and a.record:
        err = record_entry(card, ekey, a.order_file or "본문", free[0] if len(s["events"]) >= 2 and free else "없음")
        if err:
            print("ENTRY-WRITE-FAIL " + err[:100])
            print(summary)
            return 3
    print(summary)
    for n in notes:
        print(n)
    return 3 if blocked else 0


if __name__ == "__main__":
    sys.exit(main())
