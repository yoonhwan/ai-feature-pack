"""ft-board render — collect() dict 한 장에서 --term / --slack 두 꼴을 낸다 (판정 421·496). 재조회 0 · 슬랙 발행 0(문자열만 stdout).

순서(두 꼴 공통): ⓪ 팀 요약 → ① 완성 트리 → ② 세션 트리 → ③ 큐 → ④ 오늘 판정표 → ⑤ 오빠가 정할 것.
슬랙 꼴: 첫 줄 `[상태] 메인팀 보드 <HH:MM>` + `결정 자리:` 한 줄 · 답장 요구 문구 0.
DA I1·arch r2: 필터 경계는 «최종 슬랙 출력 문자열» 하나 — 고정 줄(머리 줄 · `결정 자리:` 접두 · 칸 제목)을 뺀 모든 줄에서
걸린 «부분 문자열»만 `〔문구 생략〕` 로 바꾼다(id·계수·상태 기호 소실 0) · 끝 줄 `문구 생략 n곳`(치환 횟수) · 필드별 필터 없음.
치환 뒤에도 남으면 고정 문구 결함 — 그때만 raise. term 꼴은 원문 그대로.
"""
import re
from datetime import datetime

import ft_board_env as env
from ft_board_decide import decide_lines
from ft_board_render_tree import tree_lines
from ft_board_seat import summary_cols

CAP = 10
TEAM_CAP = 5
# 슬랙 공유판 §4-r2 A·A-r3 와 같은 검사 — 같은 사실을 두 곳에서 다르게 세지 않는다
REPLY_ASK = re.compile(r"답해\s*주|답장|회신해\s*주|답을\s*(주|달)|댓글|번호(나|로)?\s*답|이\s*스레드에\s*(답|한\s*줄)|reply|확인해\s*주"
                       r"|(?<![A-Za-z0-9])Q\d+(?!\d)", re.IGNORECASE)


def _cap(lines: list[str], full: bool, n: int = CAP) -> list[str]:
    return lines if full or len(lines) <= n else lines[:n] + [f"… 외 {len(lines) - n}"]


def _seats_text(p: dict) -> str:
    return " · ".join(f"{s['name']} {s['state']}" for s in p["seats"]) if p["seats"] else "좌석 없음"


def summary_lines(d: dict, slack: bool) -> list[str]:
    out = []
    for t in d["teams"]:
        if not t["cards_dir"]:
            now_s, queue_s = "카드 폴더 미지정", "-"
        else:
            first = next(iter(t["progress"].items()), None)
            now_s = f"진행 {t['counts']['진행']}" + (f"({first[1]['title']} · {_seats_text(first[1])})" if first else "")
            queue_s = f"대기 {t['counts']['대기']}" + (f"({t['queue'][0]['title']})" if t["queue"] else "")
        row = f"- {t['label']} | 지금: {now_s} | 큐: {queue_s} | 오빠 할 일 {len(t['oppa_todo'])}"
        out.append((row if slack else f"{row} | 결정 자리: {d['decision']}") + summary_cols(t))
    return out


def session_lines(d: dict, full: bool) -> list[str]:
    out = []
    for t in d["teams"]:
        items = [f"{x['role']} {x['name']} {x['state']}" for x in t["leads"]]
        for idx, p in t["progress"].items():
            items.append(f"🔄 {p['title']} ← {_seats_text(p)}")
        items = _cap(items, full, TEAM_CAP)
        done = t["done_today"]
        tail = (f"대기 {t['counts']['대기']} · 오늘 완성 {done['n']}" + (f"(마지막: {done['last']})" if done["last"] else "")
                if t["cards_dir"] else "카드 폴더 미지정")
        items.append(tail)
        out.append(t['label'])
        out += [f"{'└─' if i == len(items) - 1 else '├─'} {x}" for i, x in enumerate(items)]
    return out


def _minutes(ts: str, now: datetime) -> str:
    p = datetime.fromisoformat(ts)
    p = p.astimezone().replace(tzinfo=None) if p.tzinfo else p
    return f"{int((now - p).total_seconds() // 60)}분"


def queue_lines(d: dict, full: bool, now: datetime) -> list[str]:
    oppa = [f"- 판정 {v['n']} · {v['title']} → {v['oppa_todo']}" for v in d["verdicts"] if v["state"] == "open" and v["oppa_todo"]]
    opened = [i for i in d["issues"] if i["state"] == "open"]
    opened.sort(key=lambda i: ("hil:needed" not in i["labels"], -i["number"]))
    issues = [f"- #{i['number']} {i['title']}" + (" [hil:needed]" if "hil:needed" in i["labels"] else "") for i in opened]
    waits = [f"- {t['label']}: " + " · ".join(q["title"] for q in t["queue"]) for t in d["teams"] if t["queue"]]
    inbox = [f"- {t['label']}: 수신 대기 {t['pending']} · 미보고 {t['unreported']}"
             + (f" · 가장 오래된 {_minutes(t['oldest_ts'], now) if t['oldest_ts'] else '시각 확인 불가'}" if t["unreported"] else "")
             for t in d["teams"] if t.get("pending") is not None]
    out = []
    for head, rows in (("오빠 손 대기", oppa), ("열린 Issue", issues), ("팀별 대기 상위 5", waits), ("수신 대기 · 미보고", inbox)):
        out += [f"{head} {len(rows)}"] + _cap(rows, full)
    return out


def verdict_lines(d: dict, full: bool) -> list[str]:
    rows = [f"{v['n']} · {v['title']} · {v['state']} · {','.join(v['teams'])}" for v in d["verdicts"] if v["today"]]
    return _cap(rows, full) if rows else ["오늘 판정 없음"]


def sections(d: dict, full: bool, slack: bool, now: datetime) -> list[tuple[str, list[str]]]:
    return [("⓪ 팀 요약", summary_lines(d, slack)), ("① 완성 트리", tree_lines(d, full)),
            ("② 세션 트리", session_lines(d, full)), ("③ 큐", queue_lines(d, full, now)),
            ("④ 오늘 판정표", verdict_lines(d, full)), ("⑤ 오빠가 정할 것", decide_lines(d, now))]


def _escape(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


OMIT = "〔문구 생략〕"


def _scrub(line: str) -> tuple[str, int]:
    return REPLY_ASK.subn(OMIT, line)


def render(d: dict, mode: str, full: bool = False) -> str:
    now, slack = env.now(), mode == "slack"
    secs = sections(d, full, slack, now)
    hhmm = now.strftime("%H:%M")
    if not slack:
        return "\n".join([f"메인팀 보드 {hhmm}"] + [x for title, lines in secs for x in (f"\n{title}", *lines)])
    # 필터 경계 = 슬랙 «최종 출력» 하나 — 고정 줄(머리 줄·칸 제목)만 빼고 모든 줄을 부분 치환한다(필드별 필터 0)
    dec, n = _scrub(_escape(d["decision"]))
    out, total = [f"[상태] 메인팀 보드 {hhmm}", f"결정 자리: {dec}"], n
    for title, lines in secs:
        out.append(f"\n*{title}*")
        for x in lines:
            y, k = _scrub(_escape(x))
            out.append(y)
            total += k
    if total:
        out.append(f"\n문구 생략 {total}곳")
    m = REPLY_ASK.search("\n".join(out))
    if m:  # 치환 뒤에도 남았다면 코드가 만든 고정 문구 결함
        raise ValueError(f"슬랙 렌더 거부 — 고정 문구에 답장 요구 '{m.group(0)}' 가 남았다(코드 결함)")
    return "\n".join(out)
