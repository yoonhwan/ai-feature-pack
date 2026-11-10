"""ft_news_publish — 다듬은 뉴스(POLISHED)를 «바뀐 것만» Slack 채널에 새 글로 발행 + 처리 기록 (R118b · 오빠 판정 1428·1430). 쓰는 쪽은 ft-news-publish.sh(ft_news_ledger.py 가 부른다).

publish = 직전 발행본과 «머리 시각만 지운 꼴» 이 같으면 발행 0 · 다르면 채널 «최상위 새 글» 1개(오빠 판정 1438 — 스레드·답글·update·첨부 0). 올리기 전 그날 봇 글 중 본문이 같은 글이 있으면 채택(첫 줄만 보면 머리 시각이 같은 새 판이 사라져 통째 비교)(응답 유실 뒤 재실행이 두 번 올리지 않는다). 본문 UTF-8 3500B 초과 = raise.
성공 줄 = «ft-news-publish: 발행 완료 ts=<ts> channel=<C…> permalink=<링크|->» (R217 · 호출한 쪽이 stdout 으로 받는다 — 파일 인계 0) · 같은 내용 = «같은 내용 — 발행 0» 줄.
HTML 모드(r478 · publish_html) = 한 줄+요약 2줄 글 1개에 팀 지도 HTML 첨부(채널 최상위 · 스레드 0) · 첨부 실패 = 글만 + rc3 + 다음 틱 retry_attach · 변화 0 = publish_line 한 줄.
처리 기록(state/news-publish/processed.tsv) = «초안 이름 → POLISHED 이름 | 같은 내용 · 발행 0» 1줄. 대체는 «명시 기록» 으로만 — X 를 기록할 때 X 보다 이른 «기록 없는» 초안 W 마다 «W<TAB>대체<TAB>X» 1줄을 같이 남긴다.
근거: 초안은 R118a 생성기가 매번 전 팀을 새로 모은 «전체 상태 스냅샷» 이라 더 새로 다듬은 판이 이전 판을 내용상 대체한다. 시각만으로 대체를 추정하지 않는다(기록이 없으면 대체 아님).
env: FT_ROOT · FT_NEWS_DIR(기본 <planner 팀 폴더>/news · TEAMS.md 폴더 칸) · FT_THREAD_POST(기본 ~/.hermes/scripts/byz_thread_post.py · target() 재사용) · FT_NEWS_POST_ARGS(--slack-base/--token-file/--channel) · FT_HERMES_SCRIPTS(magazine_slack·mirror_lib 설치 폴더 · 기본 ~/.hermes/scripts) · FT_NEWS_NOW("YYYY-MM-DD HH:MM" · 시험) · FT_NEWS_WORKSPACE_URL(글 주소 조립용 · 없으면 chat.getPermalink)
"""
import argparse
import html
import json
import logging
import os
import re
import shlex
import sys
from datetime import datetime
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_HERMES = Path(os.environ.get("FT_HERMES_SCRIPTS") or "~/.hermes/scripts").expanduser()  # 설치본 — 라이브 bin 은 옆 키트 폴더가 없어 여기서 찾는다
_KIT = _HERE.parent / "kit" / "slack-mirror"  # 리포 안 키트(설치본이 없는 시험·개발 판 · 팩 배치 harness/bin → harness/kit · r509)
sys.path[:0] = [str(p) for p in (_HERE, _HERMES, _KIT) if p.is_dir()]  # 실재하는 것만 · 우선순위 = bin 옆 → 설치본 → 키트
import ft_board_env as env  # noqa: E402
from ft_team_lib import team_in  # noqa: E402
from ft_news_post import goal_gate  # noqa: E402 — 문 모듈 누락(설치 순서)도 같은 판별(H1④)

try:
    from magazine_slack import permalink, post_root  # noqa: E402
    from mirror_lib import MirrorError, paged  # noqa: E402
    from root_readback_guard import Post, fail, readback  # noqa: E402 — r1004 되읽기 가드(설치본·키트 같은 폴더)
except ImportError as e:
    raise ImportError(f"magazine_slack·mirror_lib·root_readback_guard 를 못 찾음 — 찾은 곳: {_HERMES} (FT_HERMES_SCRIPTS) · {_KIT} ({e})") from e

LOG = logging.getLogger("ft_news_publish")
STAMP = re.compile(r"-(\d{8}-\d{4})\.md$")
CLOCK = re.compile(r"\d{2}:\d{2}")
NUMBER = re.compile(r"#\d+|판정\s*\d+")
STALE_MIN = 30
SAME = "같은 내용 · 발행 0"
MAX_BYTES = 3500  # Slack 글 길이 한도는 «바이트» — 보드 뿌리 글과 같은 UTF-8 3500B(msg_too_long 실측 10-12) · 넘으면 raise


def norm(text: str) -> str:
    """비교 키 — 첫 줄의 HH:MM 만 지우고 줄 끝 공백을 정리한다."""
    lines = text.splitlines()
    if lines:
        lines[0] = CLOCK.sub("", lines[0])
    return "\n".join(ln.rstrip() for ln in lines).strip()


def _now() -> datetime:
    v = os.environ.get("FT_NEWS_NOW")
    return datetime.strptime(v, "%Y-%m-%d %H:%M") if v else datetime.now()


def _paths() -> tuple[Path, Path]:
    """(뉴스 폴더, 상태 폴더)."""
    root = env.ft_root()
    return Path(os.environ.get("FT_NEWS_DIR") or team_in(root, "planner") / "news"), root / ".fable-team" / "state" / "news-publish"


def _stamp(name: str) -> str:
    m = STAMP.search(name)
    return m[1] if m else ""


def _processed(state: Path) -> list[str]:
    f = state / "processed.tsv"
    return [ln.split("\t")[0] for ln in f.read_text(encoding="utf-8").splitlines() if ln] if f.exists() else []


def _record(state: Path, news: Path, draft: str | None, result: str) -> None:
    """draft 한 줄 + draft 보다 이른 «기록 없는» 초안마다 대체 줄(대체 줄이 먼저 · 마지막 줄이 draft 자신)."""
    if not draft:
        LOG.warning("처리 기록 건너뜀 — %s 이전 시각의 DRAFT 가 없음", result)
        return
    done = set(_processed(state))
    if draft in done:
        return
    older = sorted(p.name for p in news.glob("DRAFT-*.md") if _stamp(p.name) < _stamp(draft) and p.name not in done)
    state.mkdir(parents=True, exist_ok=True)
    with (state / "processed.tsv").open("a", encoding="utf-8") as f:
        f.writelines(f"{w}\t대체\t{draft}\n" for w in older)
        f.write(f"{draft}\t{result}\n")


def _pick_draft(news: Path, polished_name: str) -> str | None:
    """이 POLISHED 시각 이하 DRAFT 중 가장 새 것."""
    cands = sorted(p.name for p in news.glob("DRAFT-*.md") if _stamp(p.name) <= _stamp(polished_name))
    return cands[-1] if cands else None


def _warn_numbers_outside_footnote(body: str) -> None:
    lines = body.rstrip().splitlines()
    while lines and lines[-1].lstrip().startswith("|"):
        lines.pop()
    if found := NUMBER.findall("\n".join(lines)):
        LOG.warning("각주 표 밖 번호 %d건(%s) — 번호는 맨 끝 각주 표에만 둔다(발행은 막지 않음)", len(found), ", ".join(found[:3]))


def _target(day: str, polished: Path):
    """토큰·채널·주소 = byz_thread_post.target() 읽기 재사용(FT_NEWS_POST_ARGS 로 --slack-base/--token-file/--channel 덮어쓰기)."""
    tool = Path(os.environ.get("FT_THREAD_POST") or Path.home() / ".hermes" / "scripts" / "byz_thread_post.py")
    if not tool.is_file():
        raise MirrorError(f"게시 도구 없음 {tool} (#0 RULE · 폴백 0)")
    sys.path.insert(0, str(tool.parent))
    import byz_thread_post as tp  # noqa: E402
    from thread_post_args import parse  # noqa: E402
    return tp.target(parse(["update", "--key", f"board:{day}", "--text-file", str(polished), *shlex.split(os.environ.get("FT_NEWS_POST_ARGS", ""))]))


def _find_posted(t, body: str, oldest: float) -> str | None:
    """그날 채널 최상위 봇 글(답글 달린 글은 thread_ts==ts) 중 본문이 «통째로» 같은 글의 ts(가장 이른 것). 첫 줄만 보면 머리 시각이 같고 내용만 바뀐 새 판이 «이미 올라감» 으로 오인돼 사라진다."""
    msgs = paged(t.base, t.token, "conversations.history", {"channel": t.channel, "oldest": f"{oldest:.6f}", "limit": 200})
    hits = [m for m in msgs if m.get("bot_id") and (not m.get("thread_ts") or m.get("thread_ts") == m.get("ts")) and html.unescape(str(m.get("text", ""))).strip() == body.strip()]
    return min((str(m["ts"]) for m in hits), default=None)


def _post_new(day: str, polished: Path, body: str):
    """(ts, 대상) — 채널 최상위 새 글 1개(스레드·답글·update·첨부 0). 올리기 «전» 그날 봇 글 중 본문이 같은 글이 있으면 올리지 않고 그 ts 를 채택.
    채택한 글도 되읽기 가드를 건다(r1004 — 표 글이 남아 있는 걸 «이미 올라감» 으로 통과시키지 않는다)."""
    if len(body.encode("utf-8")) > MAX_BYTES:
        raise MirrorError(f"뉴스 본문 {len(body.encode('utf-8'))}B > {MAX_BYTES}B — Slack 길이 한도(바이트) 초과, 자르지 않고 발행 0")
    t = _target(day, polished)
    oldest = datetime.strptime(day, "%Y-%m-%d").timestamp()
    if found := _find_posted(t, body, oldest):
        LOG.info("이미 올라간 글 채택 ts=%s — 다시 올리지 않음", found)
        readback(Post(t.base, t.token, t.channel, found, f"news:{day}"))  # r1004 — 채택 뒤에도 검사
        return found, t
    ts = post_root(t, body)
    readback(Post(t.base, t.token, t.channel, ts, f"news:{day}"))  # r1004 — 게시 직후 되읽기(표·«…»·결론 아닌 첫 줄이면 지운다)
    return ts, t


def _link(t, ts: str) -> str | None:
    """글 주소 — FT_NEWS_WORKSPACE_URL(예 https://x.slack.com)이 있으면 ts·채널로 조립(외부 호출 0) · 없으면 chat.getPermalink 1회(7초+재시도 1). 실패 = None(발행은 이미 끝난 일 · R217)."""
    if base := os.environ.get("FT_NEWS_WORKSPACE_URL", "").rstrip("/"):
        return f"{base}/archives/{t.channel}/p{ts.replace('.', '')}"
    try:
        return permalink(t, ts)
    except (MirrorError, KeyError) as e:
        LOG.warning("글 주소 조회 실패 ts=%s: %s — 요약 쪽지는 ts·채널로 대신한다", ts, e)
        return None


def publish(polished: Path, draft: str | None = None, at: datetime | None = None) -> int:
    """at = 첫 시도 시각 — 판 묶음을 자정 넘어 다시 낼 때 날짜 기준(상태 폴더·published·조회 창·스레드 키)을 첫 시도에 고정한다."""
    news, state = _paths()
    day, body = (at or _now()).strftime("%Y-%m-%d"), polished.read_text(encoding="utf-8")
    if not body.strip():
        LOG.error("POLISHED 가 비었다: %s — 발행 0", polished)
        return 2
    if why := goal_gate.problem(body, state.parent):  # R362 — 골 표 문(무장 표식이 있을 때만 막는다 · 아니면 WOULD-REJECT 로그) · 기록·발행 앞
        if goal_gate.refuse(state.parent, polished.name, why):
            LOG.error("REJECT 골 표 없음 — %s · 발행 0", why)
            return 3
    _warn_numbers_outside_footnote(body)
    draft = draft or _pick_draft(news, polished.name)
    pub = state / day / "published.txt"
    if pub.exists() and norm(body) == norm(pub.read_text(encoding="utf-8")):
        _record(state, news, draft, SAME)
        goal_gate.mark_done(state.parent, body)  # 올라간 뒤 기록 저장만 끊겼던 판의 영수증 복구(R362 H3)
        print("ft-news-publish: 같은 내용 — 발행 0")
        return 0
    try:
        ts, t = _post_new(day, polished, body)
    except MirrorError as e:  # 실패 = 기록 0 → 다시 실행하면 같은 걸 다시 시도(올라갔는데 응답만 유실이면 첫 줄 조회가 채택)
        LOG.error("뉴스 발행 실패: %s", e)
        return 1
    pub.parent.mkdir(parents=True, exist_ok=True)
    pub.write_text(body, encoding="utf-8")
    _record(state, news, draft, polished.name)
    goal_gate.mark_done(state.parent, body)  # 후속 판 번호를 영수증에 — «기록 저장 뒤»(그 앞에서 끊기면 재시도가 중복 게시 0 + 기록 복구) · 같은 판번호 재발행 거절
    print(f"ft-news-publish: 발행 완료 ts={ts} channel={t.channel} permalink={_link(t, ts) or '-'}")
    return 0


def html_post_text(summary: str, now: datetime) -> str:
    """HTML 모드 글(r478) = «[뉴스 HH:MM] <FT_NEWS_HEAD · 기본 팀 지도> — 요약 1줄» + 요약 2줄. 고정 문구는 이 한 곳."""
    lines = [ln.strip() for ln in summary.splitlines() if ln.strip()]
    return "\n".join([f"[뉴스 {now:%H:%M}] {os.environ.get('FT_NEWS_HEAD') or '팀 지도'} — {lines[0]}", *lines[1:3]])


def _posted_ts(t, ts: str, day: str) -> str:
    """게시 뒤 그 글 번호 — 못 얻었으면 되읽기 실패로 본다(올렸는데 조회 0 = 읽을 수 없는 글 · 조용한 성공 0)."""
    if not ts:
        raise fail(f"news:{day}", "뉴스 지도 글 번호 없음 — 되읽기 실패 · 확인 필요(올린 글 조회 0)")
    return ts


def publish_html(html_p: Path, summary: str, now: datetime) -> tuple[int, dict | None]:
    """(rc, 영수증 {ts, channel, permalink}) — 채널 최상위 글 1개에 HTML 첨부(files.completeUploadExternal initial_comment · 스레드 0).
    그날 같은 글이 이미 있으면 채택(응답 유실 재실행 중복 0). 첨부 실패 = 글만 올리고 «미첨부» 끝줄 · rc3 · 다음 틱 retry_attach 가 그 글 스레드에 첨부.
    글도 못 올림 = (1, None)."""
    day, text = f"{now:%Y-%m-%d}", html_post_text(summary, now)
    if len(text.encode("utf-8")) > MAX_BYTES:
        LOG.error("뉴스 글 %dB > %dB — 발행 0", len(text.encode("utf-8")), MAX_BYTES)
        return 1, None
    rc = 0
    try:
        t, oldest = _target(day, html_p), datetime.strptime(day, "%Y-%m-%d").timestamp()
        if not (ts := _find_posted(t, text, oldest)):
            from magazine_slack import upload_file  # HTML 모드만 — 옛 판 경로는 설치본 magazine_slack 판에 묶이지 않는다
            try:
                upload_file(t, None, html_p, html_p.name, "text/html", data=html_p.read_bytes(), comment=text)
                ts = _find_posted(t, text, oldest) or ""
            except MirrorError as e:
                LOG.error("HTML 첨부 실패: %s — 글만 올리고 다음 틱이 첨부 재시도", e)
                rc, ts = 3, post_root(t, text + "\n(지도 HTML 미첨부 — 다음 틱 재시도)")
                state = _paths()[1]
                state.mkdir(parents=True, exist_ok=True)
                (state / "pending-attach.json").write_text(json.dumps({"day": day, "ts": ts, "html": str(html_p)}), encoding="utf-8")
        ts = _posted_ts(t, ts, day)  # r1004 — 게시 뒤 글 번호를 못 얻으면 되읽기 실패(조용한 통과 0)
        readback(Post(t.base, t.token, t.channel, ts, f"news:{day}"))  # r1004 — HTML 모드 글도 게시 직후 되읽기(채택한 글 포함)
    except MirrorError as e:
        LOG.error("뉴스 지도 발행 실패: %s", e)
        return 1, None
    link = _link(t, ts) if ts else None
    print(f"ft-news-publish: 발행 완료 ts={ts or '-'} channel={t.channel} permalink={link or '-'}" + (" 미첨부" if rc else ""))
    return rc, {"ts": ts, "channel": t.channel, "permalink": link}


def retry_attach(now: datetime) -> None:
    """미첨부로 올라간 지도 글(pending-attach.json)에 HTML 을 그 글 스레드로 다시 첨부 — 실패는 ERROR 로그 + 다음 틱 다시(뉴스는 막지 않는다)."""
    f = _paths()[1] / "pending-attach.json"
    if not f.is_file():
        return
    p = json.loads(f.read_text(encoding="utf-8"))
    html_p = Path(p["html"])
    if not html_p.is_file():
        LOG.error("미첨부 지도 파일 없음 %s — 재시도 끝(글 ts=%s)", html_p, p["ts"])
        f.unlink()
        return
    from magazine_slack import upload_file
    try:
        upload_file(_target(p["day"], html_p), p["ts"], html_p, html_p.name, "text/html")
    except MirrorError as e:
        LOG.error("지도 첨부 재시도 실패(다음 틱 다시): %s", e)
        return
    f.unlink()
    print(f"ft-news-publish: 미첨부 지도 첨부 완료 ts={p['ts']} ({now:%H:%M})")


def publish_line(text: str, now: datetime) -> int:
    """HTML 모드 «변화 없음» 한 줄 — 채널 최상위 새 글 1."""
    day = f"{now:%Y-%m-%d}"
    f = _paths()[1] / day / "line.txt"
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(text, encoding="utf-8")
    try:
        t = _target(day, f)
        ts = post_root(t, text)
        readback(Post(t.base, t.token, t.channel, ts, f"news:{day}"))  # r1004 — 한 줄 글도 같은 가드
    except MirrorError as e:
        LOG.error("뉴스 한 줄 발행 실패: %s", e)
        return 1
    print(f"ft-news-publish: 발행 완료 ts={ts} channel={t.channel} permalink=-")
    return 0


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    pp = sub.add_parser("publish")
    pp.add_argument("polished")
    pp.add_argument("--draft", help="DRAFT 파일 이름 — 없으면 POLISHED 시각 이하 가장 새 DRAFT")
    pp.add_argument("--at", type=lambda s: datetime.strptime(s, "%Y-%m-%d %H:%M"), help="첫 시도 시각 \"YYYY-MM-DD HH:MM\" — 날짜 기준을 고정(자정 넘은 재시도)")
    a = p.parse_args(argv)
    return publish(Path(a.polished), a.draft, a.at)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    raise SystemExit(main(sys.argv[1:]))
