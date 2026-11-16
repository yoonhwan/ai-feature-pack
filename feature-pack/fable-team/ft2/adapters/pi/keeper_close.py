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
NOLINE = "착지 줄 없음"
APPROVE = re.compile(r"\S+ #\d+")


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_keeper_close_" + name, os.path.join(FT2, "core", name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


projection, close_next = _load("projection"), _load("close_next")
_spec = importlib.util.spec_from_file_location("ft2_keeper_verdict", os.path.join(os.path.dirname(os.path.abspath(__file__)), "keeper_verdict.py"))
verdicts = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(verdicts)   # r1865 판정 닫기 목록 · 원장·우편 로그 읽기 전용 대조
keeper_next = importlib.util.module_from_spec(importlib.util.spec_from_file_location("ft2_keeper_next", os.path.join(os.path.dirname(os.path.abspath(__file__)), "keeper_next.py")))
keeper_next.__spec__.loader.exec_module(keeper_next)   # r1871 다음 카드(영수 1회는 그 안에서)
endings = importlib.util.module_from_spec(importlib.util.spec_from_file_location("ft2_keeper_close_endings", os.path.join(os.path.dirname(os.path.abspath(__file__)), "keeper_endings.py")))
endings.__spec__.loader.exec_module(endings)   # r1960 끝 판정 · intent 대체
settle = importlib.util.module_from_spec(importlib.util.spec_from_file_location("ft2_keeper_close_settle", os.path.join(os.path.dirname(os.path.abspath(__file__)), "keeper_settle.py")))
settle.__spec__.loader.exec_module(settle)   # r2055 A13 pane 일함 근거(kill 직전 가드·2차 판독 같은 꼴)


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
        """kill 직전 가드(keeper_close·keeper_endings·keeper_stall 공용) — r1976 attached N = NOTE 1줄 뒤 닫기 계속(오빠 지시) · unknown = HELD 1줄 · 참 = 닫기 0."""
        why = self.attached(holder)
        if why.startswith("attached "):
            self.log("NOTE", team, "%s 사람 화면 attached=%s — 오빠 지시로 닫음 · %s" % (holder, why[9:], work))
        if why == "free" or why.startswith("attached "):
            return False
        self.unknown_seat(team, work, "-", holder, "attached-unknown", "판정 불가 attached(%s) · kill 0" % why[10:])   # r2055 HELD 폐지 · UNKNOWN = [긴급]
        return True

    def land_ready(self, team, work, attempt, dispatched):
        """카드 ② — 착지한 일의 complete 전 좌석 한 판독(A13) · 세션 없음·holder 없음·worktree 없음 = 참(기존 길 · close 가 판정)."""
        intent = endings.intent(self, team, work, attempt, dispatched)
        holder = intent.get("FT2_HOLDER")
        if not holder or not os.path.isdir(intent.get("worktree") or "") or self.probe(holder) != "alive":
            return True
        return self.look(team, work, attempt, holder, *self.pi_turn(intent), wait="landed-wait", idle_s=settle.DONE_IDLE) == "REST"

    def close(self, team, work, attempt, row, dispatched=None):
        """B2 — intent holder 나노(B5) · 착지 조상 · 유휴(pane ∧ Pi 턴 끝) → kill 1 → 부재 확인 → 닫기 영수."""
        intent = endings.intent(self, team, work, attempt, dispatched)   # r1960 ③ 그 attempt 없으면 같은 holder 최신 opened
        holder, gen = intent.get("FT2_HOLDER"), row.get("gen") or 1
        if not holder:   # r2055 HELD 폐지 → UNKNOWN + [긴급]
            return self.unknown_seat(team, work, attempt, dispatched, "intent-none", "intent 없음(attempt %s)" % attempt) and None
        if not self.protected_ok(team, work, attempt, holder, dispatched):
            return
        seen = tail = self.landing(team, work)[2]
        seen = NOCARD if (seen or "").startswith(NOCARD + " · ") else seen   # r2055 resolve_card 본문 단계 실패 = 카드 후보 0 가족(목록·판정·끝 길 그대로) · 꼬리는 tail
        if seen == NOCARD:   # r1841 N3·N4 — 카드 후보 0 일 때만 목록을 본다
            seen = self.nocard(team, work, attempt, holder)
            if seen is None:
                return
        verdict = None
        if seen in (NOLINE, NOCARD):   # r1865 — 착지 줄 없음·카드 후보 0 만 판정 목록을 본다(착지·noland 길 손 0)
            verdict = verdicts.gate(self, projection.runtime_path(self.root, team), team, work, attempt, holder)
            if verdict is False:
                return
        ending = None if verdict or seen not in (NOLINE, NOCARD) else endings.ending(self, team, work, holder)   # r1960 ② complete 0 · r1972 empty = holder 줄 때만
        noland = seen == "absent"   # r1841 CLOSED-NOLAND 뒤 = 기존 영수 길(settle 0)
        landed_close = not (verdict or ending or noland) and not seen   # A1·A2 — 착지 줄이 참인 닫기 길만 DONE_IDLE(그 밖 = PARK_IDLE)
        seen = "" if verdict or ending or noland else seen
        wide = self.wide_landed(team, work, intent, bool(row.get("done"))) if seen else ""   # r2055 A7 착지 근거 넓힘
        ending, seen = (("landed", wide), "") if wide else (ending, seen)
        if seen:   # r2055 착지 밖 = settle 한 길(PARKED·WORKING·UNKNOWN · HELD 폐지)
            if self.settle_nano(team, work, attempt, holder, row, tail if seen == NOCARD else seen) == "PARKED" and not self.halt:
                self.state["open"].pop(holder, None)
                self.receipt(team, work, attempt, holder, gen)   # 증거 () = 다음 배정 0
            return
        seen = "absent" if noland else self.probe(holder)
        done_idle = settle.DONE_IDLE   # A2 — 착지 닫기 길만 짧은 문턱(카드 ft2-done-seat-short-idle)
        if seen == "alive" and self.halt:   # r2055 정지 중 = «예정» 줄만
            return self.verdict(team, work, holder, "예정 LANDED", "close", "정지 중 kill 0") and None
        if seen == "alive":
            self.state["open"].setdefault(holder, {"team": team, "since": self.now()})
            if self.look(team, work, attempt, holder, *self.pi_turn(intent), wait="landed-wait", idle_s=done_idle if landed_close else settle.PARK_IDLE) != "REST":   # A6·A13 닫기 = 끝남 ∧ 한 판독 쉼
                return
            if not self.turn_ended(team, work, holder, intent):
                return
            if not self.idle(team, work, holder, attempt):   # kill 직전 가드
                return
            if self.held_attached(team, work, holder):
                return
            self.call([self.tmux, "kill-session", "-t", "=" + holder])
            seen = self.probe(holder)
            if seen != "absent":
                return self.unknown_seat(team, work, attempt, holder, "kill-failed", "부재 확인 없음(%s)" % seen) and None
            self.log("CLOSED-ENDING" if ending else "CLOSED-VERDICT" if verdict else "CLOSED-SESSION", team, " ".join(filter(None, (work, holder, verdict) + tuple(ending or ()) + ((self.parked_tail(holder) or None,)))))   # A8 미읽음 마감 꼬리
        elif seen != "absent":
            return self.unknown_seat(team, work, attempt, holder, "tmux-error", seen) and None
        self.state["open"].pop(holder, None)
        self.receipt(team, work, attempt, holder, gen) if ending else keeper_next.close(self, team, work, attempt, holder, gen)   # r1960 끝 = 증거 () · 다음 배정 0

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
                self.state.setdefault("verdict", {}).pop("%s|%s|%s" % (team, work, holder), None)   # r1841 ⑥ 목록 내용 바뀜 = 판정 줄 다시 1줄
                self.unknown_seat(team, work, attempt, holder, "noland-list", "%s · %s" % (NOCARD, ok))
            return None
        seen = self.probe(holder)
        if seen == "alive":
            return self.verdict(team, work, holder, "WORKING", "noland-alive", "목록 있음 · 세션 살아 있음 — 닫기 0") and None
        if seen == "absent":
            self.log("CLOSED-NOLAND", team, "%s %s 근거 %s" % (work, holder, self.noland_rows(team).get((work, attempt), ("", ""))[1]))
        return seen

    def idle(self, team, work, holder, attempt="-"):
        """kill 직전 가드(판정 아님 · 마지막 확인 1회 · A13) — pane 끝 12줄 Working 없음 = 참 · 1차 판독이 쉼인데 Working = UNKNOWN tmuxc-mismatch ·
        2차 판독 뒤 Working = WORKING spinner · capture 실패 = UNKNOWN capture-error(거짓)."""
        rc, pane, _ = self.call([self.tmux, "capture-pane", "-p", "-t", pane_target(holder)])
        if rc != 0:
            return self.unknown_seat(team, work, attempt, holder, "capture-error", "판정 불가 · capture rc %s" % rc) and None
        if settle.working(pane):
            if (self.cache.get("@round") or {}).get("first", {}).get(holder):
                return self.unknown_seat(team, work, attempt, holder, "tmuxc-mismatch", "1차 쉼 · kill 직전 pane Working · kill 0") and None
            return self.verdict(team, work, holder, "WORKING", "spinner", "Working") and None
        return True

    def protected_ok(self, team, work, attempt, holder, dispatched):
        """B5 — intent holder = 최신 dispatch holder ∧ 역할 토큰 nano · 아니면 닫기 0(같은 묶음 다시 보지 않음)."""
        role = holder[len("byz-%s-" % team):].split("-")[0] if holder.startswith("byz-%s-" % team) else ""
        why = "holder 불일치(intent %s · dispatch %s)" % (holder, dispatched) if holder != dispatched else ""
        why = why or ("" if role == "nano" else "보호 역할(%s) — 나노만 닫는다" % (role or "이름 꼴 밖"))
        if why:
            self.state["handled"]["%s|%s@%s" % (team, work, attempt)] = self.stamp()
            if holder != dispatched:   # r2055 UNKNOWN = [긴급]
                return self.unknown_seat(team, work, attempt, holder, "holder-mismatch", "%s · 닫기 0" % why) and None
            return self.verdict(team, work, holder, "WORKING", "protected", "%s · 닫기 0" % why) and None
        return True

    def turn_ended(self, team, work, holder, intent):
        """Pi 턴 끝 = 좌석 worktree 의 세션 jsonl(좌석 시작 뒤 가장 최근 1개) 마지막 줄이 assistant · stopReason stop."""
        why = self.pi_last_turn(intent)
        if why:
            return self.verdict(team, work, holder, "WORKING", "turn-open", "판정 불가 · Pi 턴 끝 근거 없음(%s) · 닫기 0" % why) and None
        return True

    def pi_last_turn(self, intent):
        """빈 문자열 = 턴 끝 · 그 밖 = 사유 1줄(파일·시각·마지막 줄) · r2135 L1 장기 좌석 holder = 좌석 jsonl(seat_log) 마지막 줄."""
        holder = intent.get("FT2_HOLDER") or ""
        if settle.long_seat(holder):   # r2135 L1
            log = self.seat_log(holder)
            return self.last_line(log) if log else "세션 파일 없음 좌석 %s" % holder
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
        return self.last_line(files[-1])

    def last_line(self, path):
        """세션 jsonl 마지막 줄 → 빈 문자열(assistant · stopReason stop) 또는 사유 1줄."""
        try:
            with open(path, "rb") as fh:
                fh.seek(max(0, os.path.getsize(path) - 65536))
                last = json.loads([x for x in fh.read().decode("utf-8", "replace").splitlines() if x.strip()][-1])
        except (OSError, ValueError, IndexError) as exc:
            return "세션 파일 판독 불가 %s" % type(exc).__name__
        if not isinstance(last, dict):
            return "마지막 줄 객체 아님"
        message = last.get("message") if isinstance(last.get("message"), dict) else {}
        if last.get("type") == "message" and message.get("role") == "assistant" and message.get("stopReason") == "stop":
            return ""
        return "마지막 줄 %s/%s/%s" % (last.get("type"), message.get("role"), message.get("stopReason"))

    def receipt(self, team, work, attempt, holder, gen, probe=None, next_work=None, next_holder=None, evidence=(), mark=True):
        """닫기 영수 1건 · 증거 () = 다음 배정 0. 영수·켜기 전 유보·재접수 = 다시 보지 않음(handled)."""
        node = close_next.CloseNext(self.root, team, probe=probe or self.probe)
        out = node.receipt(holder, gen, work, "keeper:%s@%s" % (work, attempt), next_holder or holder, tuple(evidence), next_work=next_work)
        kind = {OK: "RECEIPT", "접수 거부": "RECEIPT-REFUSED"}.get(out.result)
        if kind is None:
            kind = "RECEIPT-HOLD" if "켜기 전" in out.reason else "RECEIPT-UNSURE"
        self.log(kind, team, "%s %s %s · %s" % (work, holder, out.result, out.reason))
        if mark and (kind in ("RECEIPT", "RECEIPT-HOLD") or "재접수" in out.reason):
            self.state["handled"]["%s|%s@%s" % (team, work, attempt)] = self.stamp()
        return out

    def retired(self):
        """B3② — 명부 `_replaced_by` 행 + 세션 생존(r1898 바퀴당 list-sessions 1회) → ft-seat-close 1회."""
        alive = self.alive_sessions()
        if alive is None:
            return
        known = {h for t in self.teams() for _, h in (endings.latest(self, t) or {}).values()}   # r2055 S1 최신 dispatch holder = 명부 안
        held, loose = set(known), set()   # r2055 R3 명부 나노 · 승계 0 · 최신 dispatch holder 아님 = outsiders 판정(좌석당 1줄)
        for path, rows in self.rosters():   # r2055 S1 keeper roots(BYZ root · 팩) 전부의 명부
            team = os.path.basename(path)[6:-5]   # r1835 K2 — 명부 팀(seats-<팀>) 또는 좌석 이름 byz-<팀> 이 제외 팀 = 손 0
            known |= set(rows) | {v for v in rows.values() if isinstance(v, str)}
            for seat, row in sorted(rows.items()):
                new = row.get("_replaced_by") if isinstance(row, dict) else None
                ok = isinstance(row, dict) and not {team, (seat.split("-") + [""])[1]} & self.skip
                if not ok:
                    continue
                if not (isinstance(new, str) and new) and seat not in self.closed_seats():   # S2 (바) 승계 안 된 장기 좌석 = WORKING · kill 0
                    self.verdict(team, "-", seat, "WORKING", "long-seat") if seat in alive and self.seat_kind(seat, row) != "nano" else None
                    loose |= {seat} if seat in alive and self.seat_kind(seat, row) == "nano" and seat not in held else set()
                    continue
                if self.retire_one(path, seat, new, alive, self.seat_kind(seat, row) == "nano") == "stop":
                    return
        self.outsiders(alive, known - loose)   # r2055 S1·S3 명부 밖·이름 lint 실패 = UNKNOWN [긴급] · kill 0

    def alive_sessions(self):
        """r1898 — 살아 있는 세션 이름 집합 · 서버 없음 = 빈 집합 · 그 밖(넘침·다른 rc) = 판정 불가 1줄 + None."""
        rc, out, err = self.call([self.tmux, "list-sessions", "-F", "#{session_name}"])
        if rc == 0:
            return set(out.splitlines())
        if rc == 1 and "no server running" in err:
            return set()
        return self.log("판정 불가", text="tmux list-sessions rc %s %s — 이 바퀴 B3 0" % (rc, err))

    def retire_one(self, path, seat, new, alive, nano=None):
        name = os.path.basename(path)[:-5]
        if seat not in alive:
            self.state["open"].pop(seat, None)
            return
        team = name[6:] if name.startswith("seats-") else "v65"
        nano = (seat.split("-") + ["", ""])[2] == "nano" if nano is None else nano   # hil.md 나노 표준승인 = 보존 조건(keep-last-2) 면제 · S2 = 장기 좌석만 · 종류 = 명부 role(S1)
        if new and not nano and not self.ready_seen(new, seat):   # S2 (마) 끝남 근거 = _replaced_by ∧ 후계 [레디] 영수 · ready 0 = 닫기 0
            return self.verdict(team, "-", seat, "WORKING", "ready-wait", "후계 %s [레디] 0" % new) and None
        keep = "" if nano else self.keep_gate(seat, new, alive)   # S2 닫기 자격(hil.md 보존) · 걸림 = 정상 보존(kill 0 · [긴급] 0)
        if keep:
            return self.verdict(team, "-", seat, "WORKING", keep) and None
        if self.look(team, "-", "-", seat, *self.seat_turn(seat)) != "REST" or not self.idle(team, "-", seat):   # A13 한 판독 쉼 · kill 직전 가드
            return
        if self.halt:   # r2055 정지 중 = «예정» 줄만
            return self.verdict(team, "-", seat, "예정 LANDED", "succession", "정지 중 닫기 0") and None
        self.state["open"].setdefault(seat, {"team": team, "since": self.now()})
        if self.now() - self.state["held"].get(seat, -RETRY_S) < RETRY_S:
            return
        if not self.close_bin:
            self.log("판정 불가", text="ft-seat-close 경로 없음(FT_SEAT_CLOSE_BIN) — B3 0")
            return "stop"
        argv = ["bash", self.close_bin, seat, "--reason", "retire -> " + (new or "close-receipt"), "--seats", path]
        rc, out, err = self.call(argv, GIT_S)
        first = ((out or err).strip().splitlines() or [""])[0][:160]
        self.log("CLOSED-SEAT" if rc == 0 else "HELD-SEAT", name, "%s rc %s %s" % (seat, rc, first))
        self.state["held"][seat] = self.now()
        if rc == 0:
            self.state["held"].pop(seat)
            self.state["open"].pop(seat, None)
            alive.discard(seat)   # r1898 DA R1 — 다른 명부의 같은 좌석 행 = 닫힌 것으로 본다(두 번째 close·허위 HELD 0)
