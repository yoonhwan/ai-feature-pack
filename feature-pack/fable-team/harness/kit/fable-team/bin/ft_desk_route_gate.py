#!/usr/bin/env python3
# ft_desk_route_gate.py — desk 창구 고정 판정기(r660 · 판정 1125). ★규칙은 이 파일 하나뿐★ — 두 쪽지 길(키트 ft-mbox.py · 우편함 comm/mbox.sh)이 같은 파일을 부른다(두 벌 금지).
#   usage: ft_desk_route_gate.py --to T --from F --body-file P --seats-dir D --comm C
#   exit 0 = 통과(stdout `OK`) · 3 = REJECT(stdout `REJECT <사람 말>`) · 2 = usage
# 규칙(명부 seats-planner.json `_desk` = desk · `_master` = planner 팀장):
#   ⓐ desk → planner 팀 밖        = REJECT («desk 는 planner 에게만 보내요»)
#   ⓑ planner 팀 밖 → desk        = REJECT («desk 에는 planner 가 보내요»)
#   ⓒ 그 밖(planner↔팀 · 팀끼리 · desk↔planner · desk 계보 인계) = 통과
#   예외 4: 머리 [HIL] · «[h<N> 결과]» 1줄 ∧ planner 가 그 팀에 보낸 쪽지(mailbox.log)에 h<N> · 도구 발신(ft-* · #N 없음) · slack-*(오빠 슬랙)
#   ⓓ 명부 없음·깨짐·`_desk`·`_master` 칸 없음 = 판정 0(통과 + stderr WARN 1줄 — 조용히 막지 않는다)
#   [긴급] 은 desk→팀 방향 예외가 아니다(긴급도 planner 로 · 카드 §2) — 팀→desk 도 같은 표를 쓴다(예외 4 밖).
import argparse
import glob
import json
import os
import re
import sys

DESK_HEADS = ("[HIL]", "[HIL·")
# relay 두 길이 «기계가 붙이는» 꼬리줄(상세(전문): <경로> (<n> B)) — 보낸 사람이 쓴 줄이 아니므로 «1줄» 판정에서 뺀다.
TRAILER = re.compile(r"^상세\(전문\): .* \([0-9]+ B\)$")


def warn(msg):
    sys.stderr.write("WARN %s\n" % msg)


def load(p):
    try:
        with open(p, encoding="utf-8") as f:
            v = json.load(f)
    except Exception:
        return None
    return v if isinstance(v, dict) else None


def docs(d):
    out = {}
    for f in sorted(glob.glob(os.path.join(d, "seats*.json"))):
        v = load(f)
        if v is not None:
            out[os.path.basename(f)] = v
    return out


def team(n):
    """좌석 이름 → 팀 글자(`byz-planner-master-claude#94` → planner). 이름 규약만 본다(명부 회전에 안 흔들린다)."""
    m = re.match(r"^(?:byz|ft)-([a-z0-9]+)-", n or "")
    return m.group(1) if m else ""


def base(n):
    return re.sub(r"#[0-9]+$", "", n or "")


def fteam(fname):
    """seats-harness.json → harness · seats.json → v65(정본 v65 명부 이름 규약)."""
    b = fname[6:-5] if fname != "seats.json" else "v65"
    return b or "v65"


def team_of(seat, ds):
    """명부 실재 우선, 없으면 이름 규약(옛 이름·회전 좌석도 같은 팀으로 읽는다)."""
    for f, v in ds.items():
        if isinstance(v.get(seat), dict):
            return fteam(f)
    for f, v in ds.items():
        for k, val in v.items():
            if k.startswith("_") and val == seat:
                return fteam(f)
    return team(seat)


def tool_sender(frm):
    return frm.startswith("ft-") and "#" not in frm


def slack_sender(frm):
    return frm.startswith("slack-") or frm.startswith("slack_")


def lines(body):
    return [ln for ln in body.splitlines() if ln.strip() and not TRAILER.match(ln.strip())]


def head_of(body):
    ls = lines(body)
    return ls[0].strip() if ls else ""


def planner_gave(comm, hn, seat, planner):
    """planner(같은 팀 접두) → 그 팀 쪽지 기록에 h<N> 이 있나 — 덧붙이기 전용 보낸 로그 2벌(현행·회전본)만 본다."""
    pteam, steam = team(planner), team(seat)
    pat = re.compile(r"(?<![A-Za-z0-9])h%s(?![0-9])" % re.escape(hn))
    for f in (os.path.join(comm, "mailbox.log.jsonl"), os.path.join(comm, "mailbox.log.jsonl.1")):
        try:
            fh = open(f, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                if not isinstance(r, dict):
                    continue
                if team(r.get("from", "")) == pteam and team(r.get("to", "")) == steam and pat.search(r.get("body", "")):
                    return True
    return False


def verdict(to, frm, body, seats_dir, comm):
    """통과면 None, 막으면 사람 말 한 줄."""
    ds = docs(seats_dir)
    pj = ds.get("seats-planner.json")
    if pj is None:
        warn("desk 경로 판정 0 — seats-planner.json 없음/깨짐(%s) · 이 문은 통과시킨다" % seats_dir)
        return None
    planner = (pj.get("_master") or "").strip()
    desk = (pj.get("_desk") or "").strip()
    if not desk or not planner:
        warn("desk 경로 판정 0 — seats-planner.json 에 _desk·_master 칸이 없다(%s)" % seats_dir)
        return None
    if base(to) != base(desk) and base(frm) != base(desk):
        return None                                     # desk 무관 쪽지 = 판정 0
    hand = head_of(body)
    if hand.startswith(DESK_HEADS) or tool_sender(frm) or slack_sender(frm):
        return None                                     # 예외 1·3·4
    if base(to) == base(desk) and base(frm) == base(desk):
        return None                                     # 예외 2: desk 계보 인계(desk 37 → desk 38)
    pteam = team(planner) or "planner"

    def planner_side(n):
        return team(n) == pteam or isinstance(pj.get(n), dict)

    if base(frm) == base(desk):                         # ⓐ desk → …
        if planner_side(to):
            return None
        return "desk 는 planner 에게만 보내요 — 팀 일은 planner 가 나눠요 (받는 사람: %s)" % to
    if planner_side(frm):                               # ⓑ … → desk (desk 아닌 쪽이 planner 면 통과)
        return None
    m = re.match(r"^\[h([0-9]+)\s*결과\]", hand)
    if m and len(lines(body)) == 1 and planner_gave(comm, m.group(1), frm, planner):
        return None
    return "desk 에는 planner 가 보내요 — planner 에게 보내 주세요 (보내는 사람: %s)" % frm


def main():
    ap = argparse.ArgumentParser(add_help=False)
    for k in ("--to", "--body-file", "--seats-dir", "--comm"):
        ap.add_argument(k, required=True)
    ap.add_argument("--from", dest="frm", required=True)
    try:
        a = ap.parse_args()
    except SystemExit:
        sys.stderr.write("usage: ft_desk_route_gate.py --to T --from F --body-file P --seats-dir D --comm C\n")
        return 2
    try:
        with open(a.body_file, encoding="utf-8", errors="replace") as f:
            body = f.read()
    except OSError as e:
        sys.stderr.write("REJECT 쪽지 본문을 읽지 못했다(%s) — desk 경로 판정 불가\n" % e)
        return 3
    why = verdict(a.to, a.frm, body, a.seats_dir, a.comm)
    if why:
        sys.stdout.write("REJECT %s\n" % why)
        return 3
    sys.stdout.write("OK\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
