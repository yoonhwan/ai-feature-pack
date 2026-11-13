#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record.py — r1717 착지 뒤 «정리 기록 차례» 의 판정 쪽(읽기만) + 공용 함수. 동사 due · settle (전체 동사 = ft-nano-record.sh 머리).
장부 = <루트>/.fable-team/state/land-record-turn.jsonl — ft-merge-lib.sh fm_land_turn 이 착지마다 1줄 · settle 이 덧줄(같은 pr 은 뒤 줄이 이긴다).
판정 4단계(R1): ㉮ 착지 사실(장부 줄) ㉯ 필수 기록 3줄(ⓢ 세트 · ⓛ 착지 <Q> · ⓒ 그 좌석 완료) ㉰ 잔여 없음 ㉱ 닫기 요청 전달 — 착지 줄 하나로 «끝» 을 내지 않는다.
카드 = 카드 ref 판(ft-team-lib.sh ft_card_ref · 닫기 도구와 같은 한 규칙). fetch 는 URL 로 개인 ref 에 받고 바로 지운다(remote-tracking·작업 트리·가지 손 0 · 객체만).
rc 0 = 전부 판정 · 1 = REJECT · 2 = usage · 3 = 판정 불가 1건 이상. env: FT_ROOT · FT_SEATS_JSON · FT_INBOX_ROOT · FT_MBOX · FT_CARD_REF(시험)."""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENV = {**os.environ, "LC_ALL": "C"}
CARD_RX = re.compile(r"(design/(?:teams/([^/]+)|([^/]+))/indices)/[^/]+(?:/\d{4}-\d{2})?/([^/]+)\.md$")
SET_RX = re.compile(r"세트:\s*([0-9a-f]{40})")
LAND_RX = re.compile(r"^\s*-\s*착지:\s*([0-9a-f]{7,40})\b")
DONE_RX = re.compile(r"^\s*-\s*완료:\s*(\S+)\s*·")
STAGES = ("진행", "완성", "대기")


class Unjudged(Exception):
    """판정 불가 — git·tmux·명부·fetch 실패(하드 룰 20 · 쓰기 0)."""


class Reject(Exception):
    """조건 불충족 — rc 1 · 쓰기 0."""


def run(cmd, cap=7.0, env=None, inp=None, raw=False):   # → (rc|None, stdout, stderr) · 시간 초과·실행 불가 = rc None
    try:
        p = subprocess.run(cmd, capture_output=True, input=inp, timeout=max(0.5, cap), env=env or ENV)
    except subprocess.TimeoutExpired:
        return None, b"" if raw else "", "시간 초과"
    except OSError as e:
        return None, b"" if raw else "", str(e)
    return p.returncode, p.stdout if raw else p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")


def need(cmd, what, ok=(0,), **kw):
    rc, out, _err = run(cmd, **kw)
    if rc is None or rc not in ok:
        raise Unjudged(f"{what} rc={'-' if rc is None else rc}")
    return rc, out


def left_free(text, master=""):   # A15 — 잔여 판정 «한 곳»: «없음» 이거나 전부 <종류>=<팀장> 꼴(명시적인 팀장 인계)
    t = (text or "").strip()
    who = "팀장|master" + ("|" + re.escape(master) if master else "")
    return t in ("", "없음") or all(re.fullmatch(rf"[^=\s]+=({who})", w) for w in t.split())


def check_test(test):   # A6 ④·A12 — --test 는 `rc=0` 으로 끝나고 쪽지 견본의 `<…>` 자리표시가 남아 있지 않다
    if not re.search(r"\brc=0\s*$", test):
        raise Reject("시험 rc≠0 — 통과한 시험만 세트 줄에 적는다")
    if re.search(r"<[^<>]*>", test):
        raise Reject("--test 자리표시 그대로 — 실제로 돌린 시험 명령을 적는다")


def section(text):   # → (줄들, 상태 절 머리 줄 번호|None, 절 끝 번호) · 머리 꼴 = ft-nano-close _lp_card_set 과 같다
    lines = text.split("\n")
    st = next((n for n, ln in enumerate(lines) if re.fullmatch(r"##\s*상태\s*", ln)), None)
    if st is None:
        return lines, None, None
    return lines, st, next((n for n in range(st + 1, len(lines)) if re.match(r"##\s", lines[n])), len(lines))


def marks(sec, seat, q):   # 상태 절 → ⓢ 마지막 세트 줄 · ⓛ 그 Q 의 착지 줄 · ⓒ 그 좌석·그 Q 의 마지막 완료 줄 (없으면 "")
    s = [ln for ln in sec if SET_RX.search(ln)]
    la = [ln for ln in sec for m in [LAND_RX.match(ln)] if m and q.startswith(m.group(1))]
    c = [ln for ln in sec for m in [DONE_RX.match(ln)] if m and m.group(1) == seat and f"착지 {q[:10]}" in ln]
    return {"s": s[-1] if s else "", "l": la[-1] if la else "", "c": c[-1] if c else ""}


def left_of(done_line):   # 완료 줄의 «남은 일» 칸(없으면 "")
    m = re.search(r"남은 일:\s*(.*?)\s*(?:·\s*차례\s*#\S*\s*)?$", done_line or "")
    return m.group(1) if m else ""


def rec_of(m):   # A11 기록 지문 = ⓢ + ⓛ + ⓒ 줄을 이은 글의 sha256 앞 12자
    return hashlib.sha256("\n".join(m[k].strip() for k in "slc").encode()).hexdigest()[:12]


def seq_dropped(ctx, seq):   # r1820 B3 — 전달 기록 seq 가 mailbox.drops.log 의 seqs= 에 있나(숫자 토큰 정확 비교) · 원장 없음 = 아니오 · 판독 실패 = Unjudged
    try:
        raw = (ctx.comm / "mailbox.drops.log").read_text(encoding="utf-8") if seq else ""
    except FileNotFoundError:
        return False
    except (OSError, UnicodeDecodeError) as e:
        raise Unjudged(f"우편함 버림 원장 읽기 rc=1 — {type(e).__name__}") from e
    return any(str(seq) in m.group(1).split(",") for m in re.finditer(r"(?:^|\s)seqs=(\S*)", raw))


class Ctx:
    def __init__(self, root=None):
        r = (str(root) if root else "") or os.environ.get("FT_ROOT") or os.environ.get("FT_REPO_ROOT") or "."
        rc, out, _e = run(["git", "-C", r, "rev-parse", "--path-format=absolute", "--git-common-dir"])
        c = out.strip()
        if rc != 0 and r == ".":
            raise Unjudged(f"루트 git rev-parse rc={'-' if rc is None else rc}")
        self.root = Path((c[:-5] if c.endswith("/.git") else c) if rc == 0 and c else r)
        self.state = self.root / ".fable-team" / "state"
        self.comm = Path(os.environ.get("FT_INBOX_ROOT") or self.root / ".fable-team" / "comm")
        self.fetch, self._tips, self._live = True, {}, None

    def store(self):   # 보낸·전달·거절 기록(없으면 빈 꼴 · 읽기만)
        try:
            d = json.loads((self.state / "land-record-notified.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            d = {}
        return {k: d.get(k) if isinstance(d.get(k), dict) else {} for k in ("sent", "close", "left", "refused", "rejrec", "done", "tips")}

    def ledger(self):   # 장부 → 착지 항목들(같은 pr 은 뒤 줄이 이긴다 · settle 덧줄 반영)
        ents = {}
        try:
            raw = (self.state / "land-record-turn.jsonl").read_text(encoding="utf-8")
        except OSError:
            return []
        for ln in raw.splitlines():
            try:
                d = json.loads(ln)
            except ValueError:
                continue
            if not isinstance(d, dict):
                continue
            if re.fullmatch(r"[0-9a-f]{40}", str(d.get("landed") or "")):
                ents[(d.get("pr"), d["landed"])] = {**d, "cards": list(d.get("cards") or []), "nocard": ""}
            elif d.get("settle"):
                for e in [e for k, e in ents.items() if k[0] == d.get("pr")][-1:]:
                    e["cards"], e["nocard"] = list(d.get("cards") or []), str(d.get("why") or "")
        return list(ents.values())

    def seats(self, team):   # 팀 명부(착지 쪽지와 같은 규칙: FT_SEATS_JSON › seats.json(v65) › seats-<팀>.json)
        p = os.environ.get("FT_SEATS_JSON") or self.root / ".fable-team" / ("seats.json" if team == "v65" else f"seats-{team}.json")
        try:
            d = json.loads(Path(p).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            raise Unjudged(f"명부 읽기({team}) rc=1") from None
        if not isinstance(d, dict):
            raise Unjudged(f"명부 꼴({team}) rc=1")
        return d

    def live(self):   # 살아 있는 tmux 세션 이름(실행당 1회)
        if self._live is None:
            rc, out, err = run(["tmux", "list-sessions", "-F", "#{session_name}"])
            if rc != 0 and "no server running" not in err:
                raise Unjudged(f"tmux list-sessions rc={'-' if rc is None else rc}")
            self._live = set(out.split("\n")) if rc == 0 else set()
        return self._live

    def tip(self, team):   # 카드 ref 끝 — fetch=True 면 URL 로 개인 ref 에 받아 sha 만 쥐고 지운다(팀당 1회 · 7초)
        if team not in self._tips:
            root = str(self.root)
            _, out = need(["bash", "-c", '. "$1" >/dev/null 2>&1 && ft_card_ref "$2" "$3"', "_", str(HERE / "ft-team-lib.sh"), root, team], "카드 ref")
            ref = (out.strip().splitlines() or [""])[-1]
            rem, _, br = ref.partition("/")
            rc, url, _e = run(["git", "-C", root, "remote", "get-url", rem]) if br else (1, "", "")
            url, priv = (url.strip() if rc == 0 else ""), f"refs/ft-record/{os.getpid()}"
            if self.fetch and url:
                need(["git", "-c", "gc.auto=0", "-C", root, "fetch", "-q", "--no-write-fetch-head", url, f"+refs/heads/{br}:{priv}"], f"카드 ref fetch {ref}")
            name = priv if self.fetch and url else (f"refs/remotes/{ref}" if url else ref)
            _, sha = need(["git", "-C", root, "rev-parse", "--verify", "-q", name + "^{commit}"], f"카드 ref 읽기 {ref}")
            if name == priv:
                run(["git", "-C", root, "update-ref", "-d", priv])
            else:   # fetch 0 판 — landed·done 이 마지막에 본 원격 끝(tips)이 remote-tracking 보다 앞서 있으면 그쪽(자기가 보낸 줄을 낡은 판으로 판정하지 않는다)
                own = str(self.store()["tips"].get(team) or "")
                sha = own if own and run(["git", "-C", root, "merge-base", "--is-ancestor", sha.strip(), own])[0] == 0 else sha
            self._tips[team] = {"ref": ref, "url": url, "br": br, "sha": sha.strip(), "files": {}}
        return self._tips[team]

    def card(self, team, iroot, stem):   # → (ref 안 경로, 본문 bytes) · 단계 순서 진행 › 완성 › 대기 › 그 밖(아카이브)
        t = self.tip(team)
        if iroot not in t["files"]:
            _, out = need(["git", "-C", str(self.root), "ls-tree", "-r", "--name-only", "-z", t["sha"], "--", iroot], "git ls-tree 카드")
            t["files"][iroot] = out.split("\0")
        hits = sorted((p for p in t["files"][iroot] if p.rsplit("/", 1)[-1] == stem + ".md"),
                      key=lambda p: (STAGES.index(p.split("/")[-2]) if p.split("/")[-2] in STAGES else 9, p))
        if not hits:
            raise Unjudged(f"카드 ref 에 카드 없음({t['ref']}) rc=1")
        _, raw = need(["git", "-C", str(self.root), "cat-file", "blob", f"{t['sha']}:{hits[0]}"], "git cat-file 카드", raw=True)
        return hits[0], raw
