#!/usr/bin/env python3
# ft_desk_route_gate.py — desk 창구 고정 판정기(r660 · 판정 1125 · DA⑥ r1 고침). ★규칙은 이 파일 하나뿐★ — 두 쪽지 길(키트 ft-mbox.py · 우편함 mbox_ops.py)이 같은 파일을 부른다.
#   usage: ft_desk_route_gate.py --to T --from F --body-file P --seats-dir D --comm C [--attach <relay 전문 파일>]
#   exit 0 = 통과(stdout `OK`) · 3 = REJECT(stdout `REJECT <사람 말>`) · 2 = usage
# 「누가 desk·planner 인가」는 명부 하나로만 정한다(DA⑥ r1 ⓐ) — 이름 접두로 planner 팀 전체를 허용하는 길 0.
#   planner = seats-planner.json `_master` 의 «계보 번호»(같은 베이스 이름 #N 전부 — 회전 대비)
#   desk    = `_desk` 현역(계보 번호 전부) + 이름 규약 `^(byz|ft)-planner-desk-` 전부(에이전트 베이스가 바뀌어도 desk)
# 규칙:
#   ⓐ desk → planner·팀 master 밖 = REJECT («desk 는 팀 master 또는 planner 에게만 보내요») — ★[HIL]·[긴급] 도 예외 아님★
#        r1708: 팀 master = 어느 명부(seats*.json)든 `_master` 칸의 «계보 번호»(같은 베이스 이름 #N 전부) · 나노·arch·tester·이름만 맞는 좌석은 그대로 REJECT
#   ⓑ planner 밖 → desk          = REJECT («desk 에는 planner 가 보내요») — 예외 2개만, «방향 한정»:
#        ① 머리 [HIL] ② «[h<N> 결과]» ∧ 판정 재료 «전체»(요약 + relay 전문)가 1줄 ∧ `_master` 계보가 그 팀 좌석에 보낸 쪽지(회전 로그 전부 · 오늘)에 정확히 h<N>
#        ③ r1935: 어느 명부든 `_da` 계보 ∧ 첫 줄 «[판정] APPROVE» ∧ 본문에 «세트: <40hex>» 1개 ∧ 판정문 .md 경로 1개(all-of · HOLD·다른 머리는 REJECT)
#   ⓒ desk↔desk(계보 인계) · planner↔desk · 도구 발신(ft-* · # 없음 · r1851 Slack 수신기 정확 이름 ft2-slack-listen) · slack-*(오빠) = 통과
#   ⓓ 명부 없음·깨짐·`_desk`/`_master` 칸 없음 = 판정 0(통과 + stderr WARN 1줄 — 조용히 막지 않는다 · 카드 ⓕ)
# relay 두 길이 «기계가 붙이는» 꼬리줄(상세(전문): <경로> (<n> B))은 보낸 사람이 쓴 줄이 아니므로 «1줄» 판정에서만 뺀다 — 전문 내용은 --attach 로 «판정 재료»에 들어온다.
import argparse
import glob
import json
import os
import re
import sys
import time

DESK_NAME = re.compile(r"^(?:byz|ft)-planner-desk-")
TEAM = re.compile(r"^(?:byz|ft)-([a-z0-9]+)-")
TRAILER = re.compile(r"^상세\(전문\): .* \([0-9]+ B\)$")
HIL_HEADS = ("[HIL]", "[HIL·")
H_RESULT = re.compile(r"^\[h([0-9]+)\s*결과\]")
DA_APPROVE = re.compile(r"^\[판정\]\s*APPROVE(?![A-Za-z0-9_-])")  # r1935 — APPROVE-DESIGN 같은 다른 머리는 아님
SET_LINE = re.compile(r"세트:\s*[0-9a-f]{40}(?![0-9A-Za-z])")
MD_PATH = re.compile(r"[^\s()<>«»\[\]'\"`]+\.md(?![^\s()<>«»\[\]'\"`])")  # 토큰 끝 = .md(.md.txt·.md.bak 아님)
SENT_LOGS = ("mailbox.log.jsonl", "mailbox.log.jsonl.1", "mailbox.log.jsonl.2", "mailbox.log.jsonl.3")  # SENT_LOG_KEEP=3


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


def base(n):
    return re.sub(r"#[0-9]+$", "", n or "")


def team(n):
    m = TEAM.match(n or "")
    return m.group(1) if m else ""


def kept_lines(text):
    """판정 재료의 «보낸 사람이 쓴» 줄 — 기계 꼬리줄과 빈 줄은 뺀다."""
    return [ln for ln in text.splitlines() if ln.strip() and not TRAILER.match(ln.strip())]


def planner_gave(comm, hn, seat, planner_base):
    """`_master` 계보가 «그 팀 좌석»에 보낸 쪽지(회전 로그 전부 · 오늘)에 h<N> 이 정확히 있나(경계 = 비단어 문자)."""
    pat = re.compile(r"(?<![A-Za-z0-9])h%s(?![A-Za-z0-9])" % hn)
    st, today = team(seat), time.strftime("%Y-%m-%d")
    for name in SENT_LOGS:
        try:
            fh = open(os.path.join(comm, name), encoding="utf-8", errors="replace")
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
                if base(r.get("from", "")) != planner_base:
                    continue
                if not str(r.get("ts", "")).startswith(today):
                    continue
                to = r.get("to", "")
                if base(to) != base(seat) and not (st and team(to) == st):
                    continue
                if pat.search(r.get("body", "")):
                    return True
    return False


def common_seats_dir(seats_dir):
    """r2004 — roots.tsv(FT_ROOTS_TSV) 에서 경로 칸 = 이 루트인 행의 사람우편함 칸(절대경로)의 부모 · 없음·«.»·읽기 실패 = None."""
    here = os.path.realpath(os.path.dirname(os.path.abspath(seats_dir)))
    try:
        with open(os.environ.get("FT_ROOTS_TSV") or os.path.expanduser("~/.claude/fable-team/roots.tsv"), encoding="utf-8") as f:
            rows = [ln.rstrip("\n").split("\t") for ln in f if not ln.startswith("#")]
    except (OSError, ValueError):
        return None
    for r in rows:
        if len(r) >= 5 and r[1].strip() and os.path.realpath(r[1].strip()) == here and os.path.isabs(r[4].strip()):
            return os.path.dirname(r[4].strip().rstrip("/"))
    return None


def verdict(to, frm, body, attach, seats_dir, comm):
    """통과면 None, 막으면 사람 말 한 줄."""
    ds = docs(seats_dir)
    pj, why = ds.get("seats-planner.json"), ""
    if not os.path.isfile(os.path.join(seats_dir, "seats-planner.json")):  # r2004 명부 없는 루트 = 공용 루트 명부(+ 지금 폴더 명부)
        cd = common_seats_dir(seats_dir)
        cds = docs(cd) if cd else {}
        pj = cds.get("seats-planner.json")
        if pj is None:
            why = " · roots.tsv 사람우편함 없음"
        else:
            ds = {**{"common:" + k: v for k, v in cds.items()}, **ds}
    if pj is None:
        warn("desk 경로 판정 0 — seats-planner.json 없음/깨짐(%s) · 이 문은 통과시킨다%s" % (seats_dir, why))
        return None
    planner, desk = (pj.get("_master") or "").strip(), (pj.get("_desk") or "").strip()
    if not desk or not planner:
        warn("desk 경로 판정 0 — seats-planner.json 에 _desk·_master 칸이 없다(%s)" % seats_dir)
        return None
    pbase = base(planner)
    masters = {base(v["_master"].strip()) for v in ds.values() if isinstance(v.get("_master"), str) and v["_master"].strip()}  # r1708 팀 master 계보
    das = {base(v["_da"].strip()) for v in ds.values() if isinstance(v.get("_da"), str) and v["_da"].strip()}  # r1935 DA 계보

    def is_planner(n):
        return base(n) == pbase

    def is_desk(n):
        return base(n) == base(desk) or bool(DESK_NAME.match(n or ""))

    if not (is_desk(to) or is_desk(frm)):
        return None                                          # desk 무관 = 판정 0
    if (frm.startswith("ft-") and "#" not in frm) or frm == "ft2-slack-listen" or frm.startswith("slack-") or frm.startswith("slack_"):
        return None                                          # 도구 발신 · 오빠 슬랙
    if is_desk(frm) and is_desk(to):
        return None                                          # desk 계보 인계(desk 37 → desk 38)
    head = (kept_lines(body) or [""])[0].strip()
    if is_desk(frm):                                         # ⓐ desk → …
        if is_planner(to) or base(to) in masters:
            return None
        return "desk 는 팀 master 또는 planner 에게만 보내요 — 팀 좌석 일은 그 팀 master 가 나눠요 (받는 사람: %s · [HIL]·[긴급] 도 같아요)" % to
    if is_planner(frm):
        return None                                          # planner → desk(정상 방향)
    text = body if not attach else body + "\n" + attach       # ⓑ 팀 → desk: 예외 2개(방향 한정)
    if head.startswith(HIL_HEADS):
        return None
    m = H_RESULT.match(head)
    if m and len(kept_lines(text)) == 1 and planner_gave(comm, m.group(1), frm, pbase):
        return None
    if base(frm) in das and DA_APPROVE.match(head) and len(SET_LINE.findall(body)) == 1 and len(MD_PATH.findall(body)) == 1:
        return None                                          # ③ r1935 DA APPROVE → desk 직송
    return "desk 에는 planner 가 보내요 — planner 에게 보내 주세요 (보내는 사람: %s · 예외 = [HIL] 또는 planner 가 시킨 h 결과 1줄)" % frm


def main():
    ap = argparse.ArgumentParser(add_help=False)
    for k in ("--to", "--body-file", "--seats-dir", "--comm"):
        ap.add_argument(k, required=True)
    ap.add_argument("--from", dest="frm", required=True)
    ap.add_argument("--attach", default="")
    try:
        a = ap.parse_args()
    except SystemExit:
        sys.stderr.write("usage: ft_desk_route_gate.py --to T --from F --body-file P --seats-dir D --comm C [--attach F]\n")
        return 2
    try:
        with open(a.body_file, encoding="utf-8", errors="replace") as f:
            body = f.read()
        attach = ""
        if a.attach:
            with open(a.attach, encoding="utf-8", errors="replace") as f:
                attach = f.read()
    except OSError as e:
        sys.stdout.write("REJECT 쪽지 본문·전문을 읽지 못했다(%s) — desk 경로 판정 불가\n" % e)
        return 3
    why = verdict(a.to, a.frm, body, attach, a.seats_dir, a.comm)
    if why:
        sys.stdout.write("REJECT %s\n" % why)
        return 3
    sys.stdout.write("OK\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
