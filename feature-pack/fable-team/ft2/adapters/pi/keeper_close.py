"""ft 2.0 keeper — B2 착지 끝 나노 세션 닫기 · B3 승계 끝 옛 좌석 닫기 (r1812 · keeper.py 가 섞어 쓴다).

kill = tmux 세션 1개씩(kill-server 0) · 워크트리·가지·명부 행 삭제 0 · 대상 = launch intent 의 FT2_HOLDER 이고
최신 dispatch holder 와 같고 역할이 nano 인 좌석만(B5 · master·arch·desk·da 등 = 닫기 0).
유휴 = pane 에 Working·스피너 없음 ∧ Pi 세션 jsonl 마지막 줄이 턴 끝(assistant · stopReason stop) · 못 읽음 = 판정 불가.
닫기 영수 = 공개 API CloseNext(probe).receipt 같은 프로세스 · 증거(v1·v2)는 만들지 않는다 → 다음 배정 0(팀장 몫).
B3 = 1.x ft-seat-close(가드 그대로) 1회 · 실패·HELD 는 10분 안 재시도 0.
"""
import glob
import hashlib
import importlib.util
import json
import os
import re
import time

FT2 = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GIT_S, RETRY_S = 25, 600
BUSY = re.compile("Working|[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]")
OK = "접수 성공"
NOCARD, NOLAND = "판정 불가 · 카드 후보 0", "keeper-noland-close.tsv"   # r1841 N1 · 사람·master 가 쓰고 keeper 는 읽기만
APPROVE = re.compile(r"\S+ #\d+")


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_keeper_close_" + name, os.path.join(FT2, "core", name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


projection, close_next = _load("projection"), _load("close_next")


def pane_target(holder):
    """r1822 — pane 대상(capture-pane·send-keys·pane PID) = `=이름:` · `=이름` 은 세션 대상(has-session·kill-session 만)."""
    return "=" + holder + ":"


class Closing:
    def probe(self, seat):
        """tmux 부재 판독기 — rc1 + «can't find session»(서버 없음 포함) = absent · rc0 = alive · 그 밖 = 판정 불가 문자열."""
        rc, _, err = self.call([self.tmux, "has-session", "-t", "=" + seat])
        if rc == 1 and ("can't find session" in err or "no server running" in err):
            return "absent"
        if rc == 0:
            return "alive"
        return "판정 불가 · tmux has-session rc %s %s" % (rc, err)

    def attached(self, seat):
        """r1839 A1·A2 — 사람 화면 수 1회 · 대상 `=이름:` 고정(콜론 없으면 rc0 빈 줄) → free | attached <N> | unknown · <rc> <err>."""
        rc, out, err = self.call([self.tmux, "display-message", "-p", "-t", "=" + seat + ":", "#{session_attached}"])
        n = out.strip()
        if rc == 0 and n.isdigit() and n.isascii():
            n = int(n)
            if n >= 1:
                return "attached %d" % n
            return "free"
        return "unknown · %s %s" % (rc, err)

    def held_attached(self, team, work, holder):
        """kill 직전 가드(keeper_close·keeper_stall 공용) — free 가 아니면 HELD 1줄 · 참 = 닫기 0(영수·재배정 0 · 다음 바퀴에 다시 봄)."""
        why = self.attached(holder)
        if why == "free":
            return False
        text = "사람 화면 attached=%s" % why[9:] if why.startswith("attached ") else "판정 불가 attached(%s)" % why[10:]
        self.log("HELD", team, "%s %s %s · kill 0" % (work, holder, text))
        return True

    def close(self, team, work, attempt, row, dispatched=None):
        """B2 — intent holder 나노(B5) · 착지 조상 · 유휴(pane ∧ Pi 턴 끝) → kill 1 → 부재 확인 → 닫기 영수."""
        launch = os.path.join(projection.runtime_path(self.root, team), "launch")
        intent = self.read_json(os.path.join(launch, "%s@%s.intent" % (work, attempt)))
        holder, gen = intent.get("FT2_HOLDER"), row.get("gen") or 1
        if intent.get("state") != "opened" or not holder:
            return
        if not self.protected_ok(team, work, attempt, holder, dispatched):
            return
        seen = self.landing(team, work)[2]
        if seen == NOCARD:   # r1841 N3·N4 — 카드 후보 0 일 때만 목록을 본다
            seen = self.nocard(team, work, attempt, holder)
            if seen is None:
                return
        seen = seen or self.probe(holder)
        if seen == "alive":
            self.state["open"].setdefault(holder, {"team": team, "since": self.now()})
            if not self.idle(team, work, holder):
                return
            if not self.turn_ended(team, work, holder, intent):
                return
            if self.held_attached(team, work, holder):
                return
            self.call([self.tmux, "kill-session", "-t", "=" + holder])
            seen = self.probe(holder)
            if seen != "absent":
                return self.log("HELD", team, "%s %s 부재 확인 없음(%s)" % (work, holder, seen))
            self.log("CLOSED-SESSION", team, "%s %s" % (work, holder))
        elif seen != "absent":
            return self.log("HELD", team, "%s %s %s" % (work, holder, seen))
        self.state["open"].pop(holder, None)
        self.receipt(team, work, attempt, holder, gen)

    def noland_rows(self, team):
        """N1·N2 목록 → {(work, attempt): [근거, 승인]} · 파일 없음 = {} · 못 읽음·꼴 틀림·중복 = 판정 불가 문자열(sha 포함)."""
        try:
            with open(os.path.join(projection.runtime_path(self.root, team), NOLAND), "rb") as fh:
                raw = fh.read()
            text, rows = raw.decode("utf-8"), {}
        except FileNotFoundError:
            return {}
        except (OSError, UnicodeError) as exc:
            return "판정 불가 · 목록 못 읽음 %s" % type(exc).__name__
        for n, line in [(n, x) for n, x in enumerate(text.splitlines(), 1) if x.strip() and not x.startswith("#")]:
            cells = line.split("\t")
            if len(cells) != 4 or tuple(cells[:2]) in rows:
                return "판정 불가 · 목록 %d줄 %s sha %s" % (n, "중복" if len(cells) == 4 else "꼴 틀림", hashlib.sha256(raw).hexdigest()[:12])
            rows[tuple(cells[:2])] = cells[2:]
        return rows

    def noland(self, team, work, attempt):
        """N2 — 정확히 (work, attempt) 1줄 ∧ 근거 세 낱말 ∧ 승인 `<좌석> #<seq>` = True · 그 밖 False · 판정 불가 = 문자열."""
        rows = self.noland_rows(team)
        if isinstance(rows, str):
            return rows
        ground, ok = rows.get((work, attempt), ("", ""))
        return all(w in ground for w in ("카드 없음", "tmux 0")) and bool(re.search(r"발주문 \S", ground)) and bool(APPROVE.fullmatch(ok))

    def nocard(self, team, work, attempt, holder):
        """N3·N5 — 목록 밖 = NOCARD(지금 그대로) · absent = CLOSED-NOLAND 뒤 "absent"(기존 영수 길) · None = 끝(HELD 했음 · kill 0)."""
        key = "noland|%s|%s@%s" % (team, work, attempt)
        ok = self.noland(team, work, attempt)
        if ok is False:
            return NOCARD
        if ok is not True:   # N5 같은 사유(파일 sha 포함)는 1회만 · held 키는 좌석 이름과 겹치지 않는 noland| 접두
            if self.state["held"].get(key) != ok:
                self.state["held"][key] = ok
                self.log("HELD", team, "%s %s %s · %s" % (work, holder, NOCARD, ok))
            return None
        seen = self.probe(holder)
        if seen == "alive":
            return self.log("HELD", team, "%s %s 목록 있음 · 세션 살아 있음 — 닫기 0" % (work, holder))
        if seen == "absent":
            self.log("CLOSED-NOLAND", team, "%s %s 근거 %s" % (work, holder, self.noland_rows(team).get((work, attempt), ("", ""))[1]))
        return seen

    def idle(self, team, work, holder):
        """pane 에 Working·스피너 없음 = 참 · capture 실패 = 판정 불가(거짓)."""
        rc, pane, _ = self.call([self.tmux, "capture-pane", "-p", "-t", pane_target(holder)])
        if rc != 0:
            return self.log("HELD", team, "%s %s 판정 불가 · capture rc %s" % (work, holder, rc))
        if BUSY.search(pane[-2000:]):
            return self.log("HELD", team, "%s %s Working" % (work, holder))
        return True

    def protected_ok(self, team, work, attempt, holder, dispatched):
        """B5 — intent holder = 최신 dispatch holder ∧ 역할 토큰 nano · 아니면 닫기 0(같은 묶음 다시 보지 않음)."""
        role = holder[len("byz-%s-" % team):].split("-")[0] if holder.startswith("byz-%s-" % team) else ""
        why = "holder 불일치(intent %s · dispatch %s)" % (holder, dispatched) if holder != dispatched else ""
        why = why or ("" if role == "nano" else "보호 역할(%s) — 나노만 닫는다" % (role or "이름 꼴 밖"))
        if why:
            self.state["handled"]["%s|%s@%s" % (team, work, attempt)] = self.stamp()
            return self.log("HELD", team, "%s %s %s · 닫기 0" % (work, holder, why))
        return True

    def turn_ended(self, team, work, holder, intent):
        """Pi 턴 끝 = 좌석 worktree 의 세션 jsonl(좌석 시작 뒤 가장 최근 1개) 마지막 줄이 assistant · stopReason stop."""
        why = self.pi_last_turn(intent)
        if why:
            return self.log("HELD", team, "%s %s 판정 불가 · Pi 턴 끝 근거 없음(%s) · 닫기 0" % (work, holder, why))
        return True

    def pi_last_turn(self, intent):
        """빈 문자열 = 턴 끝 · 그 밖 = 사유 1줄(파일·시각·마지막 줄)."""
        sessions = self.env.get("FT2_PI_SESSIONS") or os.path.expanduser("~/.pi/agent/sessions")
        tree = intent.get("worktree") or ""
        try:
            opened = time.mktime(time.strptime(intent.get("at") or "", "%Y-%m-%dT%H:%M:%S"))
        except ValueError:
            return "intent 시각 없음"
        folder = os.path.join(sessions, "--%s--" % tree.strip("/").replace("/", "-"))
        files = sorted(glob.glob(os.path.join(folder, "*.jsonl")), key=os.path.getmtime) if tree else []
        if not files or os.path.getmtime(files[-1]) < opened:
            return "세션 파일 없음 %s" % folder
        try:
            with open(files[-1], "rb") as fh:
                fh.seek(max(0, os.path.getsize(files[-1]) - 65536))
                last = json.loads([x for x in fh.read().decode("utf-8", "replace").splitlines() if x.strip()][-1])
        except (OSError, ValueError, IndexError) as exc:
            return "세션 파일 판독 불가 %s" % type(exc).__name__
        if not isinstance(last, dict):
            return "마지막 줄 객체 아님"
        message = last.get("message") if isinstance(last.get("message"), dict) else {}
        if last.get("type") == "message" and message.get("role") == "assistant" and message.get("stopReason") == "stop":
            return ""
        return "마지막 줄 %s/%s/%s" % (last.get("type"), message.get("role"), message.get("stopReason"))

    def receipt(self, team, work, attempt, holder, gen, probe=None):
        """닫기 영수 1건 · 증거 () = 다음 배정 0. 영수·켜기 전 유보·재접수 = 다시 보지 않음(handled)."""
        node = close_next.CloseNext(self.root, team, probe=probe or self.probe)
        out = node.receipt(holder, gen, work, "keeper:%s@%s" % (work, attempt), holder, ())
        kind = {OK: "RECEIPT", "접수 거부": "RECEIPT-REFUSED"}.get(out.result)
        if kind is None:
            kind = "RECEIPT-HOLD" if "켜기 전" in out.reason else "RECEIPT-UNSURE"
        self.log(kind, team, "%s %s %s · %s" % (work, holder, out.result, out.reason))
        if kind in ("RECEIPT", "RECEIPT-HOLD") or "재접수" in out.reason:
            self.state["handled"]["%s|%s@%s" % (team, work, attempt)] = self.stamp()
        return out

    def retired(self):
        """B3② — 명부 `_replaced_by` 행 + 세션 생존 → ft-seat-close 1회."""
        for path in sorted(glob.glob(os.path.join(self.root, ".fable-team", "seats*.json"))):
            team = os.path.basename(path)[6:-5]   # r1835 K2 — 명부 팀(seats-<팀>) 또는 좌석 이름 byz-<팀> 이 제외 팀 = 손 0
            for seat, row in sorted(self.read_json(path).items()):
                new = row.get("_replaced_by") if isinstance(row, dict) else None
                if isinstance(new, str) and new and not {team, (seat.split("-") + [""])[1]} & self.skip and self.retire_one(path, seat, new) == "stop":
                    return

    def retire_one(self, path, seat, new):
        name = os.path.basename(path)[:-5]
        if self.probe(seat) != "alive":
            self.state["open"].pop(seat, None)
            return
        team = name[6:] if name.startswith("seats-") else "v65"
        self.state["open"].setdefault(seat, {"team": team, "since": self.now()})
        if self.now() - self.state["held"].get(seat, -RETRY_S) < RETRY_S:
            return
        if not self.close_bin:
            self.log("판정 불가", text="ft-seat-close 경로 없음(FT_SEAT_CLOSE_BIN) — B3 0")
            return "stop"
        argv = ["bash", self.close_bin, seat, "--reason", "retire -> " + new, "--seats", path]
        rc, out, err = self.call(argv, GIT_S)
        first = ((out or err).strip().splitlines() or [""])[0][:160]
        self.log("CLOSED-SEAT" if rc == 0 else "HELD-SEAT", name, "%s rc %s %s" % (seat, rc, first))
        self.state["held"][seat] = self.now()
        if rc == 0:
            self.state["held"].pop(seat)
            self.state["open"].pop(seat, None)
