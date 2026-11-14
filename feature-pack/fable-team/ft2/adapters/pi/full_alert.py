"""ft2 꽉 참 = 크리티컬 알림 (r1886) — 상한 4곳의 꽉 참·정상 결과마다 observe(값, 한계) · 서명 = (상한 · 팀) · 값 ≥ 한계 처음 = «★크리티컬★» 1통 · 값 < 한계 + 열린 서명 = «풀림» 1통 · 받는 곳 = 팀 master + harness master(r1927 · desk 0 = DESK_ROUTE · 같은 좌석 1통) · 남은 일 꽉 참 첫 낱말 = «[긴급]» · 열린 시각 = <서명>@at · 쪽지 = FT2_FULL_ALERT_WAKE(기본 <root>/.fable-team/comm/mbox.sh) send."""
import importlib.util, json, os, re, shlex, subprocess, time  # noqa: E401
_spec = importlib.util.spec_from_file_location("ft2_full_alert_projection", os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "core", "projection.py"))
_spec.loader.exec_module(projection := importlib.util.module_from_spec(_spec))
FIX = {"남은 일": "팀장이 끝난 일 complete 로 남은 일 줄이기", "나노 정원": "끝난 나노 닫기 · FT2_TEAM_NANO_MAX 확인", "keeper 바퀴": "keeper 로그 단계별 초에서 느린 단계 쪼개기", "journal": "journal 회수(checkpoint) · 총량 한계 확인"}
def _read(path, cell=None):   # 못 읽음 = {} · cell = 명부 칸 1개(없음 = None)
    try:
        return (lambda data: data.get(cell) if cell else dict(data))(json.load(open(path, encoding="utf-8")))
    except (OSError, ValueError, AttributeError, TypeError):
        return None if cell else {}
def _send(argv, to, body, log):   # 7초 + 재시도 1 · 실패 = rc 기록 1줄(조용한 유실 0)
    for _ in range(2):
        try:
            if (rc := subprocess.run(argv + ["send", to, "ft2-full-alert", body], capture_output=True, timeout=7).returncode) == 0:
                return 0
        except (OSError, subprocess.SubprocessError) as exc:
            rc = type(exc).__name__
    with open(log, "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"to": to, "rc": rc, "head": body[:120]}, ensure_ascii=False) + "\n")
    return rc
def observe(root, cap, team, value, limit, blocked=""):   # 값 None = 판정 불가 = 관측 0 · 반환 = 받는 곳별 rc(보낼 것 없음 = None)
    state, sig = os.path.join(root := os.path.abspath(str(root)), ".fable-team", "state", "ft2-full-alert"), "%s|%s" % (cap, team)
    opened, full = _read(state + ".json"), value is not None and value >= limit
    if value is None or full == (sig in opened):
        return None
    body = ("[긴급] " * (cap == "남은 일") + "★크리티컬★ 꽉 참 %s %s %s/%s · 막힌 것 %s · 풀기 = %s" % (cap, team, value, limit, blocked or "-", FIX.get(cap, "-")) if full
            else "풀림 %s %s %s/%s · 꽉 참 때 값 %s" % (cap, team, value, limit, opened.pop(sig, opened.pop(sig + "@at", None))))
    os.makedirs(os.path.dirname(state), exist_ok=True)
    with open(state + ".tmp", "w", encoding="utf-8") as fh:   # 서명 기억 먼저(보내기 실패여도 재알림 폭주 0)
        json.dump(dict(opened, **({sig: str(value), sig + "@at": "%.6f" % time.time()} if full else {})), fh, ensure_ascii=False)
    os.replace(state + ".tmp", state + ".json")
    argv = shlex.split(os.environ.get("FT2_FULL_ALERT_WAKE") or "bash " + shlex.quote(os.path.join(root, ".fable-team", "comm", "mbox.sh")))
    return [_send(argv, to, body, state + ".jsonl") if to else "받는 곳 없음" for to in dict.fromkeys(_read(os.path.join(root, ".fable-team", "seats-%s.json" % t), "_master") for t in (team, "harness"))]
def remaining(root, team, result, blocked=""):   # ⓐ 접수 성공·용량 부족 → 남은 일(용량 판정과 같은 장부 · 상한 = Intake 기본 8)
    proj = projection.project(root, team) if result in ("접수 성공", "용량 부족") else {}
    return observe(root, "남은 일", team, proj["remaining"], 8, blocked) if proj.get("result") == "접수 성공" else None
def journal(root, team, out, blocked=""):   # ⓓ 쓰기 결과 → 필요 총량(거절 = 쓴 양 + 필요 · 성공 = 쓴 양)
    j, got = projection.journal.Journal(projection.runtime_path(root, team)), out.get("result") == "용량 부족" and re.search(r"필요 (\d+) > 한계 (\d+)", str(out.get("reason")))
    value, limit = (j.usage() + int(got[1]), int(got[2])) if got else (j.usage(), j._limit(True))
    return observe(root, "journal", team, value, limit, blocked) if got or out.get("result") == "접수 성공" else None
