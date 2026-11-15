"""ft2 Slack 듣기 목록 CHANNELS (r1923) — 파일 1곳 = 허용 채널·주 채널(main)·공식 채널(admin)·채널 주인(owner).
줄 = <ID>\\t<이름>\\t<on|off>\\t<main|admin|req|auto>\\t<- | /명부절대경로#_역할키> · 쓰기 = 임시→rename · 허용 set 은 제자리 갱신.
판독 실패 = Corrupt(판정 불가 · 수신 시작 0) · 공식 채널 명령 «등록|삭제 #채널 [팀 X]» 장부 = 같은 폴더 commands.jsonl."""

import json, os, re  # noqa: E401

ROLES, OWNER = ("main", "admin", "req", "auto"), re.compile(r"-|/[^\t#]+#_\w+")
COMMAND = re.compile(r"(등록|삭제)\s+(<#[A-Z0-9]+(?:\|[^>]*)?>|#?[\w.-]+)(?:\s+팀\s+([\w.-]+))?\s*")


class Corrupt(Exception):
    """CHANNELS 판독 불가 — 메시지는 이름만(하드 룰 20)."""


def path_of(root, team):
    return os.path.join(os.path.abspath(str(root)), ".fable-team", "teams", team, "slack", "CHANNELS")


def read(path):  # 줄 목록 · 파일 없음 = None · 칸 4+1·main 1·admin ≤1·값 꼴 아니면 Corrupt
    try:
        with open(path, encoding="utf-8") as handle:
            rows = [line.rstrip("\n").split("\t") for line in handle if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as exc:
        raise Corrupt(type(exc).__name__)
    roles, ids = [r[3] if len(r) > 3 else "" for r in rows], [r[0] for r in rows]
    if [r for r in rows if len(r) != 5 or r[2] not in ("on", "off") or r[3] not in ROLES or not OWNER.fullmatch(r[4])
            or (r[3] == "main" and r[4] != "-")] or roles.count("main") != 1 or roles.count("admin") > 1 or len(set(ids)) != len(ids):
        raise Corrupt("CHANNELS 줄 꼴")
    return rows


def owner_of(root, team, channel):  # 그 채널 owner 칸 · 파일·줄 없음 = "-"(지금 규칙) · 깨짐 = None
    try:
        return next((r[4] for r in read(path_of(root, team)) or [] if r[0] == channel), "-")
    except Corrupt:
        return None


def resolve(owner):  # «명부#역할키» → 지금 좌석(승계를 따라감 · r1861 꼴) · 못 읽음·키 없음 = None
    roster, key = owner.rsplit("#", 1)
    try:
        with open(roster, encoding="utf-8") as handle:
            seat = json.load(handle).get(key)
    except (OSError, ValueError, AttributeError):
        return None
    return str(seat) if seat else None


def team_roster(root, team):  # «팀 X» → 명부#_master · 같은 루트 seats-X.json 또는 roots.tsv 이름 X·X-… 루트 · 못 찾음 None
    found = [os.path.join(os.path.abspath(str(root)), ".fable-team", "seats-%s.json" % team)]
    try:
        with open(os.environ.get("FT2_ROOTS_TSV") or os.path.expanduser("~/.claude/fable-team/roots.tsv"), encoding="utf-8") as handle:
            rows = [line.split("\t") for line in handle if not line.startswith("#")]
    except OSError:
        rows = []
    found += [os.path.join(r[1], ".fable-team", "seats-%s.json" % r[0]) for r in rows
              if len(r) > 1 and (team == r[0] or team.startswith(r[0] + "-"))]
    return next(("%s#_master" % p for p in found if os.path.isabs(p) and resolve(p + "#_master")), None)


def parse(text):  # (동사, 채널 글자, 팀|None) · 명령 꼴 아니면 None
    got = COMMAND.fullmatch(str(text or "").strip())
    return got and got.groups()


def _clean(name):
    return re.sub(r"[^\w.-]", "", str(name or ""))[:80]


def _jsonl(path):
    with open(path, encoding="utf-8") if os.path.exists(path) else open(os.devnull) as handle:
        return [json.loads(line) for line in handle if line.strip()]


class Channels:
    def __init__(self, path, seed=None, log=lambda line: None):
        self.path, self.allowed, self.rows, self.log = path, set(), [], log
        rows = read(path)
        if rows is not None:
            self._set(rows)
            return seed and log("CHANNELS 있음 — --channel 무시")
        ids = [c.strip() for c in str(seed or "").split(",") if c.strip()]
        if not ids:
            raise Corrupt("CHANNELS 없음 · --channel 없음")
        self._write([[c, "", "on", ("main", "admin")[i] if i < 2 else "req", "-"] for i, c in enumerate(ids)])

    def _set(self, rows):  # 허용 = on 줄 · 같은 set 객체(receive 가 쥔 것) 제자리 갱신
        self.rows = rows
        self.allowed.clear()
        self.allowed.update(r[0] for r in rows if r[2] == "on")

    def _write(self, rows):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        with open(self.path + ".tmp", "w", encoding="utf-8") as handle:
            handle.write("".join("\t".join(r) + "\n" for r in rows))
        os.replace(self.path + ".tmp", self.path)
        self._set(rows)

    def row(self, channel):
        return next((r for r in self.rows if r[0] == channel), None)

    def role(self, name):
        return next((r[0] for r in self.rows if r[3] == name), None)

    def explicit(self):  # 참여 진단 대상 = main·admin·req 의 on 줄(R1)
        return [r[0] for r in self.rows if r[2] == "on" and r[3] != "auto"]

    def add_auto(self, channel, name):  # B 발견 — 같은 ID 줄(off 포함)이 있으면 쓰기 0
        return not self.row(channel) and self._write(self.rows + [[channel, _clean(name), "on", "auto", "-"]]) is None

    def drop_auto(self, channel):  # 봇 탈퇴 — auto on 줄만 지움(off 0 · 다시 가입하면 다시 auto)
        row = self.row(channel)
        return bool(row and row[3] == "auto" and row[2] == "on") and self._write([r for r in self.rows if r is not row]) is None

    def snapshot(self, seen):  # R2 A 완전 성공 — auto on 줄 = seen 으로 교체 · 그 밖 줄 손 0 · 반환 = 새로 더한 ID
        keep = [r for r in self.rows if not (r[3] == "auto" and r[2] == "on" and r[0] not in seen)]
        added = [c for c in seen if not self.row(c)]
        rows = keep + [[c, _clean(seen[c]), "on", "auto", "-"] for c in added]
        if rows != self.rows:
            self._write(rows)
        return added

    def _apply(self, verb, channel, name, owner):
        row = self.row(channel)
        if verb == "삭제":
            if not row or row[2] == "off":
                return "등록 없음"
            if row[3] in ("main", "admin"):
                return "거절 — 주 채널·공식 채널은 삭제 0"
            return self._write([r if r is not row else r[:2] + ["off"] + r[3:] for r in self.rows]) or "삭제"
        if row and row[2] == "on":
            return "이미 등록"
        new = [channel, _clean(name) or (row or ["", ""])[1], "on", "req", owner]
        self._write([r for r in self.rows if r is not row] + [new])
        return "등록"

    def command(self, key, text, lookup, post):  # ⑦ ⓐ intent → ⓑ 파일 → ⓒ result → ⓓ 답글 → ⓔ ts · result 있으면 다시 0
        ledger, key = os.path.join(os.path.dirname(self.path), "commands.jsonl"), list(key)
        mine = [r for r in _jsonl(ledger) if r.get("key") == key]
        if any(r["t"] == "result" for r in mine):
            return None
        verb, target, team = parse(text)
        if not mine:
            self._append(ledger, {"t": "intent", "key": key, "cmd": verb, "target": target, "team": team})
        hit, owner = lookup(target), team_roster(os.path.dirname(self.path).rsplit("/.fable-team/", 1)[0], team) if team else "-"
        word = ("거절 — 채널 못 찾음 %s" % _clean(target) if not hit else "거절 — 팀 못 찾음 %s" % _clean(team) if not owner
                else "%s %s %s" % (self._apply(verb, hit[0], hit[1], owner), hit[0], _clean(hit[1])))
        word += " · /invite @탱크 필요" if word.startswith("등록 ") and hit[2] is False else ""
        self._append(ledger, {"t": "result", "key": key, "word": word})
        try:
            self._append(ledger, {"t": "reply", "key": key, "ts": post(word)})
        except Exception as exc:  # 응답 유실·오류 = 결과 불명 1줄 · 자동 재송 0(publish 계약 11)
            self.log("명령 답글 결과 불명 %s" % type(exc).__name__)
            self._append(ledger, {"t": "reply", "key": key, "ts": None, "why": type(exc).__name__})
        return word

    @staticmethod
    def _append(path, row):
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
