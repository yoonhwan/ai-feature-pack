# r2060 — 손으로 쓴 «[인계]» 판정 + 묶음에서 빼는 표식(handover-drop). mbox_handover.py 는 355줄이라 키우지 않고 여기에 둔다.
#   check <보내는 이> <받는 이> (본문 = stdin) : 첫 비어 있지 않은 줄 머리 [인계] ∧ 기계 꼴 아님 ∧ 받는 이 = 후계 → rc 3 + 안내 1줄(A1·A2)
#   drop <구> <후계> <seq> <판정 번호>        : 보낸 기록의 손 [인계] 1통을 표식에 적는다(A4·A5·A6) · `_handovers` 가 dropped() 로 읽는다(A7)
#   CANON·state 는 mbox.py 를 같은 자리에서 불러 묶는다 — mbox.sh 가 부르는 «$DIR/mbox.py» 와 같은 우편함(사전 DA 연결 지점 1).
import json, os, re, subprocess, sys, time

_WARNED = set()   # 깨진 표식 stderr = 파일마다 1줄(ready 한 번에 _handovers 가 여러 번 불린다)
VERDICT_SH = r'''r="$(git -C "$2" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"; [ -n "$r" ] || exit 9
. "$1/ft-verdict-row.sh" 2>/dev/null && . "$1/ft-team-lib.sh" 2>/dev/null || exit 8
ref="${FT_TEAMS_REF:-origin/main}"; vc="$(ft_team_cands_ref "$r" planner "$ref" 2>/dev/null)" || exit 9
re="$(fv_row_re "$3")" && [ -n "$re" ] || exit 9
while IFS= read -r c; do [ -n "$c" ] || continue; git -C "$r" grep -q -E "$re" "$ref" -- "${c#"$r"/}/VERDICTS-planner-*.md" 2>/dev/null
  case $? in 0) exit 0;; 1) ;; *) exit 9;; esac; done <<< "$vc"
exit 1'''   # ft-seat-close.sh r1481 과 같은 도우미·같은 조회(fv_row_re · ft_team_cands_ref · fetch 0)


def _H():
    import mbox_handover
    return mbox_handover


def _state():   # r1692 successor 와 같은 규칙: FT_MBOX_STATE_DIR › CANON/../state
    return os.environ.get("FT_MBOX_STATE_DIR") or os.path.join(_H().CANON, "..", "state")


def _mfile(old):
    return os.path.join(_state(), "handover-drop", old + ".json")


def _marks(old):   # 표식 줄 목록 · 파일 없음 = [] · 깨짐·꼴 틀림 = None
    try:
        with open(_mfile(old), encoding="utf-8") as f:
            d = json.load(f)
    except FileNotFoundError:
        return []
    except (OSError, ValueError):
        return None
    drops = d.get("drops") if isinstance(d, dict) else None
    ok = isinstance(drops, list) and all(isinstance(x, dict) and isinstance(x.get("seq"), int) for x in drops)
    return drops if ok else None


def dropped(old, new):   # A7 — 표식의 seq 중 to = 후계 · 깨짐 = 빈 집합 + 판정 불가 1줄(ready·close 는 지금처럼 형식 불명)
    if not old or "/" in old or old in (".", ".."):
        return set()
    m = _marks(old)
    if m is None:
        if old not in _WARNED:
            _WARNED.add(old); sys.stderr.write("판정 불가 handover-drop 표식 %s\n" % _mfile(old))
        return set()
    return {x["seq"] for x in m if x.get("to") == new}


def is_successor(frm, to):   # A2 — ⓐ 이름에서 #<숫자> 를 뗀 앞부분이 같음 ⓑ 명부 사슬에 받는 이 · 명부 조회 실패 = ⓐ 만
    if frm == to:
        return False
    if re.sub(r"#\d+$", "", frm) == re.sub(r"#\d+$", "", to):
        return True
    try:
        import mbox_lineage
        return to in mbox_lineage.chain(frm) or to == mbox_lineage.retired_to(frm)
    except (Exception, SystemExit):
        return False


def is_hand(body):   # 머리 [인계] ∧ 기계 꼴 아님(items = None) · 목록 파일 판정 불가 = 손이라 단정하지 않음(지금처럼 보냄)
    H = _H()
    if H._head(body) != "[인계]":
        return False
    try:
        return H.items({"body": body}) is None
    except SystemExit:
        return False


def check(frm, to, body):
    if is_hand(body) and is_successor(frm, to):
        sys.stderr.write("REJECT 손 [인계] 거절 — bash mbox.sh handover %s %s [«손 항목»…]\n" % (frm, to)); return 3
    return 0


def _verdict_ok(v):   # A5 — 0 실재 · 1 없음 · 그 밖 = 판정 불가
    b = os.environ.get("FT_BIN") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin")
    root = os.path.dirname(os.path.dirname(os.path.abspath(_H().CANON)))
    try:
        return subprocess.run(["bash", "-c", VERDICT_SH, "verdict", b, root, str(v)], capture_output=True, timeout=7).returncode
    except (OSError, subprocess.SubprocessError):
        return 9


def drop(old, new, seq, v):
    H = _H()
    hit = [r for r in H._sent() if r.get("seq") == seq]
    r = hit[-1] if hit else None
    if not r or r.get("from") != old or r.get("to") != new or H._head(r.get("body")) != "[인계]":
        sys.stderr.write("REJECT handover-drop #%d — %s -> %s 가 보낸 [인계] 기록 없음\n" % (seq, old, new)); return 3
    if H.items(r) is not None:
        sys.stderr.write("REJECT handover-drop #%d 기계 [인계] 는 뺄 수 없음 — ready 로 받음\n" % seq); return 3
    vr = _verdict_ok(v)
    if vr != 0:
        why = "원장(VERDICTS-planner-*.md)에 없음" if vr == 1 else ("도우미 없음" if vr == 8 else "원장 확인 불가")
        sys.stderr.write("REJECT handover-drop 판정 %d %s(%s) — 표식 0\n" % (v, why, os.environ.get("FT_TEAMS_REF") or "origin/main")); return 1
    m = _marks(old)
    if m is None:
        sys.stderr.write("REJECT 판정 불가 handover-drop 표식 %s — 표식 0\n" % _mfile(old)); return 1
    if any(x["seq"] == seq and x.get("to") == new for x in m):
        print("NOOP %s -> %s #%d 이미 뺌" % (old, new, seq)); return 0
    p = _mfile(old)
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p + ".tmp", "w", encoding="utf-8") as f:
            json.dump({"drops": m + [{"seq": seq, "to": new, "verdict": v, "at": int(time.time())}]}, f, ensure_ascii=False)
        os.replace(p + ".tmp", p)
    except OSError as e:
        sys.stderr.write("REJECT handover-drop 표식 쓰기 실패 %s %s\n" % (p, type(e).__name__)); return 1
    print("DROPPED %s -> %s #%d verdict=%d" % (old, new, seq, v)); return 0


def _bind():   # mbox.py 를 «이 파일 옆» 경로(abspath)로 불러 CANON 을 묶는다 — mbox.sh 의 $DIR/mbox.py 와 같은 결정
    import importlib.util
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mbox.py")
    spec = importlib.util.spec_from_file_location("mbox", p)
    m = importlib.util.module_from_spec(spec); sys.modules["mbox"] = m; spec.loader.exec_module(m)


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) == 3 and a[0] == "check":
        _bind(); sys.exit(check(a[1], a[2], sys.stdin.read()))
    if len(a) == 5 and a[0] == "drop" and a[3].isdigit() and a[4].isdigit():
        _bind(); sys.exit(drop(a[1], a[2], int(a[3]), int(a[4])))
    sys.stderr.write("usage: mbox_handover_hand.py check <보내는 이> <받는 이> < 본문 | drop <구> <후계> <seq> <판정 번호>\n"); sys.exit(2)
