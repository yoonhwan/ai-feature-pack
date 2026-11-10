# mbox_retire_check.py — 승계에서 retire 가 빠진 상태를 기계가 잡는다 (r1319 · 지시 24 · 판정 3220·3221).
#   왜: retire 가 rc4(미표시 쪽지)로 거절되면 «다시 돌려라» 는 기계 신호가 없었고, 부팅 보고 lint 는 실제 보고 머리 꼴
#   («[HIL] 부팅 끝: …» · «골좌표: … · [부팅 보고] arch#204»)에서 아예 안 돌아 desk#97 의 retire 누락이 조용히 지나갔다(사람 답 13분 지연).
#   C0 검사 집합 = retire 가 고치는 집합: 같은 폴더 seats*.json 최상위 `_*` 칸 값 == 구 이름(정확히 같음 · 목록·부분 문자열·메모 글자 0).
#   C0b 명부 고르기 = retire 와 같은 규칙(그 좌석 키를 가진 파일 1개) → mbox_teamfile.teamfile → 없으면 판정 불가.
#   C0c 승계 판정 = me 행 `_replaces` 가 비어 있지 않음 · 또는 _closed 아닌 X#N-1 이 me 앞으로 [인계] 를 보낸 기록.
#   C1 [레디] 는 retire 먼저 · C2 남은 `_*` 칸 REJECT · C3 부팅 보고 판정(앞 3줄 조각) · C4 lint 승계 검사 · C7 닫기 retire 먼저.
#   판정 불가 = rc 2 (하드 룰 20 — 명부를 못 읽으면 조용한 통과가 아니라 거절). CANON 은 mbox.py 가 묶는다.
import glob, json, os, re, sys
import mbox_teamfile
CANON = None   # mbox.py 가 묶는다
UNKNOWN, REJECT = 2, 3
HAND = re.compile(r"^\[인계\] (\S+) -> (\S+) ")   # mbox_handover.handover_body 머리와 같은 꼴
BOOT_HEAD = ("[부팅", "부팅 보고", "부팅 끝", "부팅 완료", "부팅:")
LEAD = re.compile(r"^\[[^\]]*(?:->|→)[^\]]*\]|^\[HIL[^\]]*\]|^\[정리\]")   # 조각 앞 발신·HIL·정리 머리를 뗀다
_SENT = []

def roster_dir(seats_dir=None):   # 명부 폴더 = FT_SEATS_JSON 의 폴더 · 없으면 mbox.sh 규칙(정본 우편함 옆 seats.json)
    if seats_dir:
        return seats_dir
    sj = os.environ.get("FT_SEATS_JSON") or os.path.join(os.path.dirname(CANON or "."), "seats.json")
    return os.path.dirname(sj) or "."

def _load(f):
    try:
        with open(f, encoding="utf-8") as fh:
            v = json.load(fh)
    except (OSError, ValueError):
        return None
    return v if isinstance(v, dict) else None

def docs(d):   # (파일 → 명부, 못 읽은 파일) — 폴더 전체를 한 번에 본다(retire 의 scan_cells 와 같은 집합)
    out, bad = {}, set()
    for f in sorted(glob.glob(d + "/seats*.json")):
        v = _load(f)
        if v is None:
            bad.add(f)
        else:
            out[f] = v
    return out, bad

def pick(d, seat):   # C0b → (파일, 명부, 행, 사유) · 사유 "" 통과 · "NOROW …" 행 없음(승계 아님) · "UNKNOWN …" 판정 불가
    ds, bad = docs(d)
    cand = [f for f, v in ds.items() if isinstance(v.get(seat), dict)]
    if len(cand) > 1:
        return "", {}, None, "UNKNOWN 명부 후보 %d개 (키 %s)" % (len(cand), seat)
    if cand:
        return cand[0], ds[cand[0]], ds[cand[0]][seat], ""
    auth = mbox_teamfile.teamfile(d, seat, ds, bad)[0]
    if auth in bad:
        return auth, {}, None, "UNKNOWN 명부 읽기 실패 " + os.path.basename(auth)
    if not auth:
        return "", {}, None, "NOROW 명부 없음 (키 %s · %s)" % (seat, d)
    v = ds.get(auth) or {}
    return auth, v, v.get(seat) if isinstance(v.get(seat), dict) else None, ""

def leftover(d, old):   # C0 → (남은 «파일:칸» 목록, 판정 불가 사유) — retire 가 바꾸는 칸은 «전 명부의 최상위 `_*` 문자열 == old»
    ds, bad = docs(d)
    if bad:
        return None, "명부 JSON 손상 " + " ".join(sorted(os.path.basename(f) for f in bad))
    return [os.path.basename(f) + ":" + k for f, v in ds.items() for k, val in v.items()
            if k.startswith("_") and isinstance(val, str) and val == old], ""

def _sent():   # 보낸 행 사본(회전본 포함 · 한 프로세스 한 번) — [인계] 기록 판정의 유일한 출처
    if not _SENT:
        base = CANON or os.path.dirname(os.path.abspath(__file__))
        for p in sorted(glob.glob(os.path.join(base, "mailbox.log.jsonl*"))):
            try:
                for ln in open(p, encoding="utf-8"):
                    try:
                        _SENT.append(json.loads(ln))
                    except ValueError:
                        pass
            except OSError:
                pass
        _SENT.sort(key=lambda r: r.get("seq", 0))
    return _SENT

def handover_target(h):   # [인계] 머리의 후계 이름 — 형식 밖(손으로 쓴 문장형)이면 ""
    m = HAND.match((h or {}).get("body", ""))
    return m.group(2) if m else ""

def last_handover(sent, seat):
    hs = [r for r in sent if r.get("from") == seat and HAND.match(r.get("body", ""))]
    return hs[-1] if hs else None

def succession(d, seat, sent):   # C0c → (승계인가|None 판정 불가, 사유) — «X#N-1 행이 있음» 만으로는 승계 아님(DA ② X2)
    f, doc, row, why = pick(d, seat)
    if why.startswith("UNKNOWN"):
        return None, why[8:]
    if isinstance(row, dict) and row.get("_replaces"):
        return True, ""
    m = re.match(r"^(.+)#(\d+)$", seat or "")
    prev = m.group(1) + "#" + str(int(m.group(2)) - 1) if m and int(m.group(2)) >= 1 else ""
    if prev and handover_target(last_handover(sent, prev)) == seat:
        pf, pdoc, prow, pwhy = pick(d, prev)
        if not pwhy and (prow is None or not prow.get("_closed")):
            return True, ""
    return False, ""

def retire_cmd(old, new):   # C5 한 줄 명령 — 문구마다 같은 꼴로 붙인다
    return "bash mbox.sh handover %s %s && bash ft-seat-retire.sh %s %s" % (old, new, old, new)

def ready_gate(new, old, to=""):   # C1·C2 → None 통과 · (rc, 문구) 거절 — [인계] 대상이 new 일 때만 승계로 본다
    if to and to != new:
        return None
    d = roster_dir()
    f, doc, row, why = pick(d, old)
    if why:
        return UNKNOWN, "%s — %s 은퇴 여부 판정 불가(%s)" % (why[6:].strip() or why, old, os.path.basename(f) or d)
    if not isinstance(row, dict):
        return UNKNOWN, "%s 명부 행 없음 — 은퇴 여부 판정 불가" % old
    if row.get("_replaced_by") != new:
        return REJECT, "REJECT %s 는 아직 %s 로 은퇴 안 됨(retire 먼저) — 후계 pane 에서: %s" % (old, new, retire_cmd(old, new))
    left, why = leftover(d, old)
    if why:
        return UNKNOWN, why
    if left:
        return REJECT, "REJECT %s 에 구 이름 남음 %d개(%s) — retire 다시 (같은 폴더 `_*` 칸은 retire 만 고친다)" % (
            old, len(left), " ".join(left[:3]))
    return None

def close_gate(seat):   # C7 → None 통과 · (rc, 문구) 거절 — [인계] 는 보냈는데 retire 를 안 돌린 채 닫으려 할 때
    d = roster_dir()
    h = last_handover(_sent(), seat)
    to = handover_target(h)
    if not to:
        return None   # [인계] 없음(기존 검사 몫) · 형식 밖 [인계]
    f, doc, row, why = pick(d, to)
    if why or not isinstance(row, dict):
        return None   # 후계 행 없음 = 면제(개설 실패·승계 취소 · DA ② X3)
    fs, doc2, row2, why2 = pick(d, seat)
    if why2:
        return UNKNOWN, why2[6:].strip() or why2
    if not isinstance(row2, dict):
        return UNKNOWN, "%s 명부 행 없음 — 닫기 근거 판정 불가" % seat
    if not row2.get("_replaced_by"):
        return REJECT, "REJECT %s 는 %s 로 은퇴 안 됨(retire 먼저) — %s" % (seat, to, retire_cmd(seat, to))
    return None

def _head_ok(piece, me):   # 조각 머리 뒤 40자 안에 보낸 좌석 이름 또는 그 «#N» — 남의 부팅 보고를 언급한 쪽지(DA ② X1)
    num = "#" + me.rpartition("#")[2] if "#" in (me or "") else ""
    for h in BOOT_HEAD:
        if piece.startswith(h):
            tail = piece[len(h):][:40]
            if (me and me in tail) or (num and num in tail):
                return True
    return False

def is_boot_report(body, me):   # C3 — 옛 첫 줄 판정(그대로) 또는 앞 3줄 « · » 조각의 머리 판정
    lines = (body or "").split("\n")[:3]
    first = lines[0].strip() if lines else ""
    head, _, rest = first.partition("]")
    if rest and ("->" in head or "→" in head):
        first = rest.strip()
    if first.startswith("[") and "]" in first:
        first = first[:first.index("]") + 1]
    if (first.startswith("[") and first.endswith("]") and "부팅 보고" in first) or first.startswith("부팅 보고"):
        return True
    return any(_head_ok(LEAD.sub("", p.strip()).strip(), me) for ln in lines for p in ln.split(" · "))

def boot_gate(seats_dir, me, body, sent=None):   # C4 → None 통과 · (rc, 문구) 거절 — 승계 좌석이면 retire 칸 + C0 검사
    d = roster_dir(seats_dir)
    succ, why = succession(d, me, _sent() if sent is None else sent)
    if succ is None:
        return UNKNOWN, why
    if not succ:
        return None
    f, doc, row, pwhy = pick(d, me)
    if pwhy.startswith("UNKNOWN"):
        return UNKNOWN, pwhy[8:]
    n = re.match(r"^(.+)#(\d+)$", me or "")
    prev = n.group(1) + "#" + str(int(n.group(2)) - 1) if n and int(n.group(2)) >= 1 else ""
    cands = list(dict.fromkeys(([prev] if isinstance(doc.get(prev), dict) else []) + list((row or {}).get("_replaces") or [])))
    want = "retire=" + (cands[0] if cands else "<구>") + "->" + me + " rc=0"
    m = re.search(r"retire=([^\s>→]+?)\s*(?:->|→)\s*([^\s·,;]+)\s+rc=0", body)
    if not m:
        return REJECT, "REJECT 부팅 보고 반송 — retire 칸 없음: " + want + " (ft-seat-retire.sh <구> <후계> 를 먼저 실행해 출력 복붙)"
    old, new = m.group(1), m.group(2)
    if old not in cands or new != me:
        return REJECT, "REJECT 부팅 보고 반송 — retire 칸 불일치(%s->%s): %s" % (old, new, want)
    fo, do, ro, whyo = pick(d, old)
    if whyo.startswith("UNKNOWN"):
        return UNKNOWN, whyo[8:]
    if not isinstance(ro, dict) or ro.get("_replaced_by") != me:
        return REJECT, "REJECT 부팅 보고 반송 — retire 칸은 있는데 명부 미반영 — ft-seat-retire.sh " + old + " " + me + " 실행 뒤 다시"
    left, why = leftover(d, old)
    if why:
        return UNKNOWN, why
    if left:
        return REJECT, "REJECT 부팅 보고 반송 — retire 뒤에도 구 이름 %s 남음 %d개(%s)" % (old, len(left), " ".join(left[:3]))
    return None
