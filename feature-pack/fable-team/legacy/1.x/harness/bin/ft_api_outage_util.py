"""ft_api_outage_util.py — ft_api_outage.py 의 형제 모듈: 오류 문구 분류·해제 근거 파싱 + 수신자 공용 notify 잠금 (R146).

잠금 = 수신자별 공용 notify 상태의 «읽기 → 발신 → 성공 기록» 을 한 프로세스만 하게 하는 fcntl.flock 1개(macOS 에 flock 명령 없음).
대기 상한은 7초 룰 — 넘으면 yield False(건너뛰기 아님: 호출 쪽이 ERROR 1줄 + 발신 0 + 다음 틱 재시도).
"""
import fcntl
import glob
import json
import re
import subprocess
import sys
import time
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path

CAUSES = (("rate_limit", "rate_limit|limit reached|temporarily limiting requests|are cooling down"), ("oauth_not_allowed", "OAuth authentication is currently not allowed"),
          ("subscription_disabled", "disabled Claude subscription access"))
Rec = dict[str, object]
RETRY = r"retry[\s_-]*after\s*(\d+)\s*(min\w*|m\b|s\w*)?"


TAIL = 1 << 20
PS_MAX_S = 2.0  # r1086 ① 직기 — ps 1회 상한(넘으면 ② 지금 길 · 7초 룰 안쪽)
SESSION_ID = re.compile(r"--session-id[= ]([0-9a-fA-F-]{8,})")  # r1086 ① 직기 — claude argv 의 기록 파일 이름


def epoch(rec: Rec) -> int:
    return int(datetime.fromisoformat(str(rec["timestamp"]).replace("Z", "+00:00")).timestamp())


def records(path: str) -> list[Rec]:
    """좌석 jsonl 꼬리 1MB → 시각 있는 레코드(r497 에서 ft_api_outage.py 로부터 옮김 · 200줄 한도)."""
    with open(path, "rb") as fh:
        size = fh.seek(0, 2)
        _ = fh.seek(max(0, size - TAIL))
        raw = fh.read().split(b"\n")
    out: list[Rec] = []
    for line in raw[1:] if size > TAIL else raw:
        try:
            rec = json.loads(line)
            _ = epoch(rec)
        except (ValueError, KeyError, TypeError):
            continue
        out.append(rec)
    return out


def is_error(rec: Rec) -> bool:
    return rec.get("type") == "assistant" and rec.get("isApiErrorMessage") is True


def is_logged_out(rec: Rec) -> bool:
    """r849 — 로그인 풀린 좌석의 0초 실패 턴 기록(합성 오류 assistant · error=authentication_failed 또는 «Not logged in»). 429·overloaded 등 다른 API 오류는 아니다(r838 몫)."""
    msg = rec.get("message")
    synthetic = bool(rec.get("type") == "assistant" and isinstance(msg, dict) and msg.get("model") == "<synthetic>")  # pyright: ignore[reportUnknownMemberType]
    return (synthetic and rec.get("error") == "authentication_failed") or (is_error(rec) and "Not logged in" in text_of(rec))


LOGGEDOUT_MAX_MS = 5000  # r849 재설계 r3 — «0초 실패 턴» 의 소요 시간 상한(실측 142ms) · 넘으면 «일한 턴» 이라 로그아웃으로 보지 않는다(DA⑥ r3 반례 1: 120초 턴 오판)


def is_quick_turn(duration_ms: object) -> bool:
    """r849 r3 — turn_duration 의 durationMs 가 «0초 실패» 범위인가(정수 ms 규칙). 숫자가 아니면 False — 모르면 로그아웃 아님 쪽으로
    판정한다(일하는 좌석을 안 깨우는 쪽이 이 카드의 목적 · 반대쪽은 0초 실패 턴을 정상으로 읽어 깨우기가 되풀이된다)."""
    return isinstance(duration_ms, int) and 0 <= duration_ms <= LOGGEDOUT_MAX_MS


def is_normal(rec: Rec) -> bool:
    """정상 턴 = 모델 응답 하나뿐(r838 r3 · ft_api_outage·ft_model_swap 모두 이 함수만) — 오류·요약·메타·사이드체인·model 없음/<synthetic> = 아님."""
    msg = rec.get("message")
    return (rec.get("type") == "assistant" and isinstance(msg, dict) and msg.get("model") not in (None, "", "<synthetic>")  # pyright: ignore[reportUnknownMemberType]
            and not any(rec.get(k) for k in ("isApiErrorMessage", "isCompactSummary", "isMeta", "isSidechain")))


def hhmm(epoch: int) -> str:
    return time.strftime("%H:%M", time.localtime(epoch))


def text_of(rec: Rec) -> str:
    msg = rec.get("message")
    parts = msg.get("content") if isinstance(msg, dict) else None  # pyright: ignore[reportUnknownMemberType]
    body = " ".join(str(p.get("text", "")) for p in parts if isinstance(p, dict)) if isinstance(parts, list) else ""  # pyright: ignore[reportUnknownVariableType,reportUnknownMemberType,reportUnknownArgumentType]
    return f"{body} {rec.get('error', '')}"


def cause_of(rec: Rec) -> str:
    return next((n for n, pat in CAUSES if re.search(pat, text_of(rec))), "기타")


def reset_of(rec: Rec, ts: int) -> str:
    """문구의 해제 근거 → «HH:MM (문구: resets 3am, retry after 120s)» · 근거 없으면 빈 문자열."""
    text, basis, eta = text_of(rec), [], ""
    if m := re.search(r"resets?\s*(?:at\s*)?(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)", text, re.I):
        eta = m.group(1).strip()
        basis.append(f"resets {eta}")
    if m := re.search(RETRY, text, re.I):
        mins = (m.group(2) or "s").lower().startswith("m")
        basis.append(f"retry after {m.group(1)}{'min' if mins else 's'}")
        eta = eta or hhmm(ts + int(m.group(1)) * (60 if mins else 1))
    return f"{eta} (문구: {', '.join(basis)})" if basis else ""


def eta_of(rec: Rec, ts: int) -> int:
    """`retry after N` 근거가 있으면 해제 예상 epoch · 없으면 0(r497 — «3분 안 해제면 기다림» 판정용)."""
    if m := re.search(RETRY, text_of(rec), re.I):
        return ts + int(m.group(1)) * (60 if (m.group(2) or "s").lower().startswith("m") else 1)
    return 0


def base_model(model: str) -> str:
    """`claude-fable-5-1[1m]` → `claude-fable-5-1` (창 꼬리 `[…]` 떼고 비교 · r497)."""
    return re.sub(r"\[[^\]]*\]$", "", model.strip())


def model_of(rec: Rec) -> str:
    """오류 문구 `for model <id>` → 바탕 id · 정상 레코드는 message.model · 모르면 ''(r497 모델별 복구)."""
    if m := re.search(r"for model ([A-Za-z0-9._\[\]-]+)", text_of(rec)):
        return base_model(m.group(1))
    msg = rec.get("message")
    got = msg.get("model") if isinstance(msg, dict) else None  # pyright: ignore[reportUnknownMemberType,reportUnknownVariableType]
    return base_model(got) if isinstance(got, str) and got != "<synthetic>" else ""


def fallback_table(path: Path) -> dict[str, str]:
    """r497 model-fallback.tsv 2열 `<바탕 id>\\t<다음 모델 전체 id>` — 바탕 id 는 `[1m]` 떼고 비교."""
    rows = [ln.split("\t") for ln in path.read_text(encoding="utf-8").splitlines() if ln.strip() and not ln.startswith("#")]
    return {base_model(r[0]): r[1].strip() for r in rows if len(r) >= 2}


def goal_source(ft: Path, base: str) -> tuple[list[str], str] | None:
    """r497 계보 최신 도달 파일(state/successor/<베이스>#*.json · reached_at) 의 seq → 발주 본문 첫 3줄(골 원문) + 인계서 줄 · 없으면 None."""
    reach: list[tuple[str, float, str]] = []
    for p in (ft / "state" / "successor").glob(glob.escape(base) + "#*.json"):
        try:
            j = json.loads(p.read_text(encoding="utf-8"))
            reach.append((str(j.get("reached_at", "")), p.stat().st_mtime, str(j.get("seq", ""))))
        except (ValueError, OSError, AttributeError):
            continue
    if not reach or not (seq := max(reach)[2]).isdigit():
        return None
    body = ft / "comm" / "bodies" / f"{seq}.txt"
    lines = body.read_text(encoding="utf-8").splitlines() if body.is_file() else []
    if len([ln for ln in lines[:3] if ln.strip()]) < 3:
        return None
    return lines[:3], next((ln.strip() for ln in lines[3:] if "인계서" in ln), "")


def read_table(path: Path) -> dict[str, object] | None:
    """r497 명부 1개 — 못 읽으면 WARN 1줄 + None(조용한 생략 0)."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError) as exc:
        print(f"WARN model_swap: 명부 못 읽음 {path.name} ({exc})", file=sys.stderr)
        return None


def list_panes(tmux: str) -> list[tuple[str, str]]:
    """tmux pane 전부 → [(세션 이름, pane cwd)] 1회(상한 7초 · 넘으면 TimeoutExpired 그대로) — 실패 rc = [] (find_jsonls 옛 동작 그대로)."""
    r = subprocess.run([tmux, "list-panes", "-a", "-F", "#{session_name}\t#{pane_current_path}"], capture_output=True, text=True, timeout=7)
    return [(s, cwd) for s, cwd in (ln.split("\t", 1) for ln in (r.stdout if r.returncode == 0 else "").splitlines() if "\t" in ln)]


def _cap(ceiling: float, deadline: float | None) -> float:
    """외부 명령 1회 상한 — 마감(monotonic)이 있으면 남은 시간 안으로 줄인다(최소 0.1초)."""
    return ceiling if deadline is None else max(0.1, min(ceiling, deadline - time.monotonic()))


def ps_tree(deadline: float | None = None) -> dict[int, list[tuple[int, str]]] | None:
    """r1086 ① ps 1회 → {ppid: [(pid, command)]} · 실패·시간 초과 = None(① 끔 · 전 좌석 ② = 지금과 같은 동작)."""
    try:
        r = subprocess.run(["ps", "-axo", "pid=,ppid=,command="], capture_output=True, text=True, timeout=_cap(PS_MAX_S, deadline))
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    tree: dict[int, list[tuple[int, str]]] = {}
    for ln in r.stdout.splitlines():
        parts = ln.split(None, 2)
        if len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit():
            tree.setdefault(int(parts[1]), []).append((int(parts[0]), parts[2]))
    return tree


def pane_pids(tmux: str, deadline: float | None = None) -> dict[str, int]:
    """r1086 세션 이름 → pane pid 1회(상한 7초) · 실패·시간 초과 = {}(① 끔).
    list-sessions 를 쓰는 까닭: pane 목록 1회 계약(r850)이 list-panes 를 세므로 여기서 또 부르지 않는다 — 결과는 «세션의 지금 pane»."""
    try:
        r = subprocess.run([tmux, "list-sessions", "-F", "#{session_name}\t#{pane_pid}"], capture_output=True, text=True, timeout=_cap(7.0, deadline))
    except (OSError, subprocess.SubprocessError):
        return {}
    out: dict[str, int] = {}
    for ln in (r.stdout if r.returncode == 0 else "").splitlines():
        s, _, pid = ln.partition("\t")
        if s and pid.strip().isdigit():
            out.setdefault(s, int(pid.strip()))
    return out


def pinned_jsonl(pid: int, cwd: str, tree: dict[int, list[tuple[int, str]]], projects: Path) -> tuple[str, bool]:
    """r1086 ① 짚기 — pane pid 자손 중 «실행 파일 끝이 /claude 이고 argv 에 --session-id U» 인 줄 → <projects>/<cwd 인코딩>/U.jsonl 이 있으면 그 경로.
    돌려주는 것 = (경로, pane 자손에 claude 가 있었나). claude 가 없으면 그 좌석은 ② 에서 뺀다(파일 머리 읽기 0 · pi·opencode 나노)."""
    stack, seen, has_claude = [pid], {pid}, False
    while stack:
        for child, cmd in tree.get(stack.pop(), []):
            if child in seen:
                continue
            seen.add(child)
            if (cmd.split(None, 1)[0] if cmd.strip() else "").rsplit("/", 1)[-1] != "claude":
                stack.append(child)
                continue
            has_claude = True
            if m := SESSION_ID.search(cmd):
                cand = projects / re.sub(r"[^A-Za-z0-9]", "-", cwd) / f"{m.group(1)}.jsonl"
                if cand.is_file():
                    return str(cand), True
    return "", has_claude


def find_jsonls(seats: list[str], tmux: str, projects: Path, days: int = 2, panes: list[tuple[str, str]] | None = None,
                deadline: float | None = None) -> dict[str, str]:
    """r497 좌석들 → 최신 jsonl 을 «한 번에». ft-seat-status.sh jsonl 은 좌석마다 폴더 jsonl 전부(5989개)의 머리 1MB 를 읽어
    부하 30 에서 1회 10초(실측) — 여기선 폴더 = tmux pane cwd 인코딩(같은 규칙) · 후보 = 최근 days 일 수정 파일만 · 파일 머리 1번 읽어 전 좌석 대조.
    panes = 이미 읽은 list_panes() 값(r850 — cwd 재탐색과 pane 목록 1회를 나눠 쓴다) · None 이면 여기서 읽는다.
    r1086 찾는 순서 둘 — ① 짚기: pane 자손 claude 의 argv --session-id = 파일 이름이라 바로 짚는다(파일 머리 읽기 0).
    ② 지금 길(머리 읽기)은 ① 에서 못 짚은 «claude 좌석» 에만 · pane 자손에 claude 가 없는 좌석(pi 나노)은 못 찾음 그대로.
    deadline = time.monotonic() 기준 마감(있으면) — 넘기면 그 뒤 좌석은 못 찾음으로 남는다(호출자 «시간 초과» 그대로)."""
    cwd_of: dict[str, str] = {}
    groups: dict[Path, list[str]] = {}
    for s, cwd in list_panes(tmux) if panes is None else panes:
        if s in seats and s not in cwd_of:
            cwd_of[s] = cwd
            groups.setdefault(projects / re.sub(r"[^A-Za-z0-9]", "-", cwd), []).append(s)
    out: dict[str, str] = {}
    nonclaude: set[str] = set()
    if (tree := ps_tree(deadline)) is not None:  # ① 짚기 — ps 1회(실패·시간 초과면 통째로 ②)
        pids = pane_pids(tmux, deadline)
        for s, cwd in cwd_of.items():
            if s in out or (pid := pids.get(s)) is None:
                continue
            path, has_claude = pinned_jsonl(pid, cwd, tree, projects)
            if path:
                out[s] = path
            elif not has_claude:
                nonclaude.add(s)
    for d, group in groups.items():
        group = [s for s in group if s not in nonclaude and s not in out]
        if not group:  # ② 에 볼 좌석이 없다 — 폴더 훑기(수만 파일 stat) 부터 안 한다
            continue
        try:
            files = sorted(((p.stat().st_mtime, p) for p in d.glob("*.jsonl")), reverse=True)
        except OSError:
            continue
        for _, p in (f for f in files if time.time() - f[0] < days * 86400):
            if not (left := [s for s in group if s not in out]):
                break
            if deadline is not None and time.monotonic() > deadline:  # 마감 넘김 — 이 뒤 좌석은 못 찾음(반쯤 읽은 값 안 씀)
                return out
            try:
                with p.open("rb") as fh:
                    head = fh.read(1 << 20)
            except OSError:  # 읽는 사이 지워진 파일
                continue
            out.update({s: str(p) for s in left if f'"agentName":"{s}"'.encode() in head or f'"customTitle":"{s}"'.encode() in head})
    return out


def jsonl_cwd(path: str) -> str:
    """r497 좌석 jsonl 의 마지막 `cwd`(후계 워크트리) · 없으면 ''."""
    return next((str(r["cwd"]) for r in reversed(records(path)) if isinstance(r.get("cwd"), str)), "") if path else ""


def next_name(names: set[str], base: str) -> str:
    """r497 후계 이름 = 베이스#(명부 키·tmux 세션 중 최대 번호 + 1)."""
    nums = [int(m.group(1)) for n in names if (m := re.fullmatch(re.escape(base) + r"#(\d+)", n))]
    return f"{base}#{max(nums, default=0) + 1}"


@contextmanager
def locked(path: Path, timeout: float = 7.0) -> Iterator[bool]:
    """path 에 배타 잠금 — 얻으면 True · timeout 초 안에 못 얻으면 False(잠금 없음)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as fh:
        end, got = time.monotonic() + timeout, False
        while not got:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)  # GUARD:flock
                got = True
            except BlockingIOError:
                if time.monotonic() >= end:
                    break
                time.sleep(0.05)
        try:
            yield got
        finally:
            if got:
                fcntl.flock(fh, fcntl.LOCK_UN)
