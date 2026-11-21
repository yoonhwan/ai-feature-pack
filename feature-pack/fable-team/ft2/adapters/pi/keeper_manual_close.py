"""ft 2.0 keeper — 사람·팀장이 부르는 닫기 한 명령 (r2401 · 카드 K1~K4 · 사전 DA#56 APPROVE-DESIGN r3).

    python3 core/cli.py keeper --root R --close-seat <석> --verdict <N> --approve "<planner 좌석> #<seq>" --reason "<10자 이상>"

차례 = K1 대상(이름 꼴 ∧ 팀 2.0 전환 ∧ launch intent) → K4 잠금(7초 대기) → K2 승인 대조(원장 행·우편·planner 꼴·자율 모드·긍정 판독·정지)
      → K3 손(attached → pane Working → dirty → 재개 기록 → kill → park) → 끝 줄 «CLOSED-MANUAL …». 실패한 단계에서 멈추고 rc 로 알린다.
승인 판정은 새로 쓰지 않는다 — r1865 `keeper_verdict.approved`(planner 원장 행 + 우편 로그) 한 곳 그대로. 여기서 더하는 것은 글자 판독 1개(ⓔ)뿐이다:
원장 행에 «수동 닫기» 가 있고 거절 낱말이 없고 우편 첫 줄 머리가 «[수동 닫기 승인]» — approved 가 "" 를 돌려줘도 여기서 거절한다(덜 닫는 쪽).
재개 기록 = r2281 `keeper_close_old.resume` 그대로(source 칸만 ft2-manual-close · retired_by = 승인 좌석). park = core 공개 동사(cli park) 1회.
부르는 손 = planner master·desk 뿐(hil.md 19행 표준승인 그대로 · 이 파일은 새 권한을 만들지 않는다). 정지(ALL_STOP) 중 = 기록·kill·park 0.
"""
import importlib.util
import json
import os
import re
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(os.path.dirname(HERE))
LOCK_S = 7.0                                   # K4 — keeper 바퀴 잠금 대기(하드 룰 12: 7초 1회 · 재시도 0)
STALE_S = 600                                  # keeper.STALE_S 와 같은 값(죽은 바퀴 잠금 = 지우고 다시)
MIN_REASON = 10                                # K1 — 사유 ≥ 10자
SEAT = re.compile(r"byz-([a-z0-9]+)-nano-[A-Za-z0-9._-]+#[0-9]+")
PLANNER = re.compile(r"byz-planner-(master|desk)-")
MANUAL, HEAD = "수동 닫기", "[수동 닫기 승인]"     # K2 ⓔ — 원장 행 낱말 · 우편 첫 줄 머리
REFUSE = ("아니오", "거절", "보류", "반려", "철회")   # K2 ⓔ — 거절 낱말(이유 글에 섞여도 거절 = 덜 닫는 쪽)
AUTO = re.compile(r"A[0-9]+")                  # K2 ⓒ 자율 ON = 원장 행의 자율 사건 번호
PARK = "idle-done"                              # K3 ⑥ core 공개 동사(cli park)의 쉼 사유 낱말 — core 는 idle-done·launch-failed 만 받는다(dispatch.park · 어긴 사유 = 접수 거부)
                                                #   그래서 «manual-close: 판정 <N> <사유>» 는 core 에 넘기지 않고 CLOSED-MANUAL·PARK-FAILED 줄에 남긴다(core 무수정 = 카드 «park 는 core 공개 동사 그대로»).
OPPA = re.compile(r"오빠[\s«»\"'“”]*네[\s«»\"'“”]*[0-9]{10}\.[0-9]{6}")   # K2 ⓒ 자율 OFF = «오빠 네 <Slack ts>» 한 덩어리(«오빠» 와 ts 따로 = 승인 아님)
MODE = ("on", "off", "tamper")


def _load(path, alias):
    spec = importlib.util.spec_from_file_location(alias, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


verdict_mod = _load(os.path.join(HERE, "keeper_verdict.py"), "ft2_manual_verdict")
close_old_mod = _load(os.path.join(HERE, "keeper_close_old.py"), "ft2_manual_close_old")
settle = _load(os.path.join(HERE, "keeper_settle.py"), "ft2_manual_settle")
endings = _load(os.path.join(HERE, "keeper_endings.py"), "ft2_manual_endings")
cli = _load(os.path.join(FT2, "core", "cli.py"), "ft2_manual_cli")


def team_of(seat):
    """K1 — byz-<팀>-nano-<stem>#N 이면 그 팀 · 아니면 ""(그 밖 이름 = 대상 아님)."""
    m = SEAT.fullmatch(seat or "")
    return m.group(1) if m else ""


def switched(k, team):
    """K1 — 그 팀이 2.0 으로 전환됐나(state/ft20-switch/<팀>.json · ft-index-move·ft-nano-spawn 이 세우는 표식)."""
    return os.path.isfile(os.path.join(k.root, ".fable-team", "state", "ft20-switch", team + ".json"))


def target(k, seat):
    """K1 — (팀, work, attempt, intent, "") · 아니면 ("", "", "", {}, 사유). intent = FT2_HOLDER 가 이 석인 가장 늦은 1개."""
    team = team_of(seat)
    if not team:
        return "", "", "", {}, "이름 꼴 아님(byz-<팀>-nano-<stem>#N)"
    if not switched(k, team):
        return "", "", "", {}, "팀 %s 2.0 전환 아님(keeper 자동 닫기 몫)" % team
    got = [(str(it.get("at") or ""), work, attempt, it) for work, attempt, it in endings.intents(k, team)
           if isinstance(it, dict) and it.get("FT2_HOLDER") == seat]
    if not got:
        return "", "", "", {}, "intent 없음(손으로 연 좌석 = planner 수동 닫기 몫)"
    _, work, attempt, intent = max(got, key=lambda x: (x[0], x[1], x[2]))
    return team, work, attempt, intent, ""


def lock(k, wait=LOCK_S):
    """K4 — keeper 바퀴 잠금을 wait 초까지 기다려 잡는다 → 잠금 경로 · 못 잡음 = None(그때는 손 0)."""
    os.makedirs(k.dir, exist_ok=True)
    path = os.path.join(k.dir, "keeper.lock")
    end = time.monotonic() + max(0.0, wait)
    while True:
        try:
            os.close(os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644))
            return path
        except FileExistsError:
            try:
                if time.time() - os.path.getmtime(path) > STALE_S:   # 죽은 바퀴 잠금 = keeper.locked 와 같은 규칙으로 지우고 다시
                    os.unlink(path)
                    continue
            except OSError:
                continue
            if time.monotonic() >= end:
                return None
            time.sleep(0.1)


def autonomy(k):
    """K2 ⓒ — 1.x bin/ft-autonomy.sh mode 1회(7초) → on|off|tamper · 못 읽음·그 밖 값 = ""(REJECT)."""
    path = os.path.join(k.root, ".fable-team", "bin", "ft-autonomy.sh")
    if not os.path.isfile(path):
        path = os.path.join(os.path.dirname(FT2), "legacy", "1.x", "harness", "bin", "ft-autonomy.sh")
    rc, out, _ = k.call(["bash", path, "mode"])
    word = (out or "").strip()
    return word if rc == 0 and word in MODE else ""


def row_text(k, n):
    """그 판정 번호의 planner 원장 행 글자(keeper_verdict.ledger 와 같은 원장·같은 grep·같은 정규식 — 판정은 바꾸지 않고 글자만 읽는다) → (글, 사유)."""
    tbl = os.path.join(k.root, ".fable-team", "state", "directive-roots.tsv")
    try:
        with open(tbl, encoding="utf-8") as fh:
            table = [x.rstrip("\n").split("\t") for x in fh if not x.startswith("#") and len(x.split("\t")) >= 4]
    except (OSError, UnicodeError) as exc:
        if not isinstance(exc, FileNotFoundError):
            return "", "원장 못 읽음 · directive-roots"
        table = []
    r = next((x for x in table if x[0] == "planner"), None) or next((x for x in table if x[0] == "*"), ["*", ".", "origin/main"])
    rc, out, err = k.call(["git", "-C", os.path.join(k.root, r[1]), "grep", "-I", "-E", "-e", r"^- \*\*%s\*\*" % n,
                           "-e", r"^\|[[:space:]]*%s[[:space:]]*\|" % n, r[2], "--", verdict_mod.MD_GLOB], verdict_mod.GIT_S)
    if rc not in (0, 1):
        return "", "원장 못 읽음 · git grep rc %s %s" % (rc, err[:80])
    hits = {}
    for path, _, body in (x[len(r[2]) + 1:].partition(":") for x in out.splitlines()):
        row, num = verdict_mod.MD_ROW.match(body), re.search(r"planner-(\d+)-", path)
        if row and num and (row.group(1) or row.group(2)) == n:
            rest = body[row.end():]
            hits.setdefault(int(num.group(1)), []).append(rest.strip() if row.group(1) else "|".join(rest.split("|")[1:]).strip(" |"))
    rows = hits[max(hits)] if hits else []
    return (rows[0], "") if len(rows) == 1 else ("", "판정 %s 원장 행 %d개" % (n, len(rows)))


def mail_text(k, seq):
    """그 seq 우편 1통의 본문(keeper_verdict.mailbox 와 같은 로그·같은 꼴) · 없음·중복·못 읽음 = ""."""
    path = os.path.join(k.root, ".fable-team", "comm", "mailbox.log.jsonl")
    try:
        with open(path, encoding="utf-8") as fh:
            found = [rec for rec in (json.loads(x) for x in fh if seq in x) if isinstance(rec, dict) and str(rec.get("seq")) == seq]
    except (OSError, ValueError):
        return ""
    return str(found[0].get("body") or "") if len(found) == 1 else ""


def positive(k, n, seq, body):
    """K2 ⓔ — 긍정 승인 판독 1개: 원장 행 «수동 닫기» ∧ 거절 낱말 0(행·본문) ∧ 우편 첫 줄 머리 «[수동 닫기 승인]» → "" · 아니면 사유."""
    mail = mail_text(k, seq)
    head = mail.strip().splitlines()[0].strip() if mail.strip() else ""
    if MANUAL not in body:
        return "긍정 판독 · 원장 행에 «%s» 없음" % MANUAL
    if not head.startswith(HEAD):
        return "긍정 판독 · 우편 첫 줄 머리가 «%s» 아님" % HEAD
    bad = [w for w in REFUSE if w in body or w in mail]
    return "긍정 판독 · 거절 낱말 «%s»" % bad[0] if bad else ""


def approval(k, seat, work, n, seat_ok, seq):
    """K2 — (사유, 갈래) · ("", "") = 승인 맞음. 갈래 = «승인»(rc 2) | «정지 중»(rc 2). 순서 = ⓐ ⓑ ⓒ ⓔ ⓓ."""
    why = verdict_mod.approved(k, n, seat, seat_ok, seq, work)
    if why:
        return "승인 " + why, "승인"
    if not PLANNER.match(seat_ok):
        return "승인 승인 좌석 %s 는 byz-planner-master·desk 아님(hil.md 19행)" % seat_ok, "승인"
    body, why = row_text(k, n)
    if why:
        return "승인 " + why, "승인"
    mode = autonomy(k)
    if not mode:
        return "승인 자율 모드 판독 실패", "승인"
    if mode == "on" and not AUTO.search(body):
        return "승인 자율 ON · 원장 행에 자율 사건 번호 A<N> 없음", "승인"
    if mode != "on" and not OPPA.search(body):
        return "승인 자율 %s · 원장 행에 «오빠 네 <Slack ts>» 없음" % mode.upper(), "승인"
    why = positive(k, n, seq, body)
    if why:
        return "승인 " + why, "승인"
    if k.stopped():
        return "ALL_STOP 정지 중 · kill 0(푸는 손 = 오빠)", "정지 중"
    return "", ""


def parked(k, team, work, seat, n, reason):
    """K3 ⑥ — 이 석이 최신 dispatch holder 이고 일이 done 이 아니면 cli park 1회 → («done»|«none», 0) · 실패 = ("", 7)."""
    latest = endings.latest(k, team)
    attempt, holder = ((latest or {}).get(work) or (None, None))
    if latest is None or holder != seat or not attempt:
        return "none", 0
    proj = k.proj_of(team) or {}
    works = (proj.get("works") or {}) if proj.get("result") == "접수 성공" else {}
    if (works.get(work) or {}).get("done"):
        return "none", 0
    why = "manual-close: 판정 %s %s" % (n, reason)
    out, rc = cli.run(["park", "--work", work, "--attempt", attempt, "--reason", PARK, "--root", k.root, "--team", team])
    if rc != 0:
        k.log("PARK-FAILED", team, "%s 판정 %s 사유 «%s» · park 거절 %s %s · 세션은 이미 닫힘 · 손으로: python3 core/cli.py park --work %s --attempt %s --reason %s --root %s --team %s"
              % (seat, n, why, out.get("result"), str(out.get("reason", ""))[:60], work, attempt, PARK, k.root, team))
        return "", 7
    k.state.get("open", {}).pop(seat, None)
    return "done", 0


def hands(k, team, work, attempt, intent, seat, n, seat_ok, seq, reason):
    """K3 — ①attached ②pane Working ③dirty ④재개 기록 ⑤kill ⑥park ⑦끝 줄. 실패한 단계에서 멈춘다(뒤 단계 0)."""
    seen = k.attached(seat)
    if seen != "free":                                     # ① 사람 화면(못 읽음 = 덜 닫는 쪽)
        return k.log("REJECT attached", team, "%s 판정 %s · %s · 손 0" % (seat, n, seen)) or 4
    rc, pane, _ = k.call([k.tmux, "capture-pane", "-p", "-t", "=" + seat + ":"])
    if rc == 0 and settle.working(pane):                   # ② 일하는 중 = 못 닫는다(알려진 한계 1)
        return k.log("REJECT busy", team, "%s 판정 %s · pane Working · 손 0" % (seat, n)) or 4
    tree = str(intent.get("worktree") or "")
    rc, dirty, _ = k.git(tree, "status", "--porcelain") if tree else (1, "", "")
    if rc != 0 or dirty.strip():                           # ③ 이 명령은 커밋하지 않는다
        return k.log("REJECT dirty — [wip] 커밋 먼저", team, "%s 판정 %s · %s · 기록 0 · kill 0"
                     % (seat, n, "worktree 판독 실패" if rc != 0 else "미커밋 변경 있음")) or 8
    why = k.close_old.resume(seat, seat_ok, intent, source="ft2-manual-close")   # ④ 재개 기록 먼저(r2281 그대로)
    if why:
        return k.log("REJECT 재개 기록", team, "%s 판정 %s · %s · 기록 0 · kill 0" % (seat, n, why)) or 5
    k.call([k.tmux, "kill-session", "-t", "=" + seat])      # ⑤ 세션만 닫기 → 부재 확인
    after = k.probe(seat)
    if after != "absent":
        return k.log("REJECT kill", team, "%s 판정 %s · 부재 확인 없음(%s)" % (seat, n, after)) or 6
    park, rc = parked(k, team, work, seat, n, reason)       # ⑥ 소유가 남는 자리 = core park 1회
    if rc:
        return rc
    return k.log("CLOSED-MANUAL", team, "%s 판정 %s %s #%s park=%s reason=%s" % (seat, n, seat_ok, seq, park, reason)) or 0


def run(k, seat, verdict, approve, reason, wait=LOCK_S):
    """K1 → K4 → K2 → K3 · 반환 = rc(0·2·3·4·5·6·7·8). 줄은 k.log 로 남기고 부르는 쪽(keeper.main)이 그대로 찍는다."""
    hit = verdict_mod.APPROVE.fullmatch((approve or "").strip())
    if not (verdict.isdigit() and hit and len(reason or "") >= MIN_REASON):
        return k.log("REJECT 인자", "", "--verdict <N> --approve \"<planner 좌석> #<seq>\" --reason <10자 이상> 꼴 아님 · 손 0") or 2
    n, (seat_ok, seq) = verdict, hit.groups()
    team, work, attempt, intent, why = target(k, seat)
    if why:
        return k.log("REJECT 대상 아님", "", "%s · %s · 손 0" % (seat, why)) or 2
    path = lock(k, wait)
    if path is None:
        return k.log("BUSY", team, "keeper 바퀴 중 — 다시 부르세요 · %s 판정 %s · 손 0" % (seat, n)) or 3
    try:
        why, kind = approval(k, seat, work, n, seat_ok, seq)
        if why:
            return k.log("REJECT " + kind, team, "%s 판정 %s · %s · 기록 0 · kill 0" % (seat, n, why)) or 2
        return hands(k, team, work, attempt, intent, seat, n, seat_ok, seq, reason)
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
