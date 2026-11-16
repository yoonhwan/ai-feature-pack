"""r2088 keeper 증거 줄 없음 안내 — 원장 done · nano/<work> OPEN PR 1개 · 카드 ref 마지막 세트 줄 D2 꼴 아님 → 받는 곳 첫 값에 묶음 없이 1통/일
(카드 r2088 반례 ⑥ ⑥a ⑥b ⑥c ⑥d ⑥e ⑦ ⑦' · 변이 M3 키 날짜 삭제 → ⑥c · M4 지문 메모리만 → ⑥b · M5 notify() 묶음 → ⑥d).
대역 = r1812 World(임시 BYZ·팩 리포·가짜 tmux·쪽지 STUB·주입 시계) + 가짜 gh(FT2_GH · 가지별 출력) · 실 원장·우편함·Slack·sleep 0."""
import importlib.util, json  # noqa: E401
from pathlib import Path
FT2 = Path(__file__).resolve().parents[1]
_S = importlib.util.spec_from_file_location("r2088_kw", str(FT2 / "tests" / "keeper_world_r1812.py"))
kw = importlib.util.module_from_spec(_S)
_S.loader.exec_module(kw)
TEAM, _git, _lines, _put, ID = kw.TEAM, kw._git, kw._lines, kw._put, ["-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"]
GH = '#!/bin/sh\nprintf "%s\\n" "$*" >> "$FAKE_GH.log"\nf="$FAKE_GH.out-$(echo "$*" | sed "s/.*--head nano.\\([^ ]*\\).*/\\1/")"\n[ -f "$f" ] || f="$FAKE_GH.out"\ncat "$f"\nexit "$(cat "$FAKE_GH.rc" 2>/dev/null || echo 0)"\n'
SET = "- 세트: %s · 시험: pytest t.py rc=0 · 이슈: 0" % ("cd" * 20)
def world(tmp, mp):
    w = kw.World(tmp, mp, FT2)
    _put(tmp / "bin" / "gh", GH), (tmp / "bin" / "gh").chmod(0o755), _put(str(tmp / "gh") + ".out", "[]")
    w.env.update(FT2_GH=str(tmp / "bin" / "gh"), FAKE_GH=str(tmp / "gh"))
    return w
def done(w, work, team=TEAM, n=1, rc=0, text="- 2026-11-16 — 진행", card=True):
    """원장 done · intent worktree = 팩 nano/<work> 가지(커밋 1) · gh OPEN PR n개 · 카드(두 ref) «## 상태» 끝 = text."""
    w.work(work, done=True, team=team)
    path, base = w.tmp / "wt" / work, w.pack_sha()
    _git(w.tmp / "pack", "fetch", "-q", "origin"), _git(w.tmp / "pack", "worktree", "add", "-q", "-b", "nano/" + work, str(path), base)
    head = (_git(path, *ID, "commit", "-q", "--allow-empty", "-m", "n"), _git(path, "rev-parse", "HEAD"))[1]
    _put(str(w.tmp / "gh") + ".out-" + work, json.dumps([{"number": 7, "headRefOid": head}] * n)), _put(str(w.tmp / "gh") + ".rc", str(rc))
    folder = "design/harness" if team == TEAM else "design/teams/" + team
    [w.commit("byz", {"%s/indices/진행/%s-x.md" % (folder, work): "# 인덱스: %s\n\n## 상태\n%s\n" % (work, text)}, ref) for ref in ("main", "ops/main-base") if card]
    _git(w.root, "fetch", "-q", "origin")
    return head
def notice(w, work, team=TEAM, k=None):   # 한 바퀴 = 잠금 안 state.json 읽기·쓰기 → evidence_notice 1회
    m = w.K
    k = k or m.Keeper(str(w.root), env=w.env, now=lambda: w.t)
    return k, k.locked(lambda: m.endings.evidence_notice(k, team, work))
def mail(w, word="증거 줄 없음"):
    return [x for x in _lines(str(w.mbox) + ".log") if x.startswith("send ") and word in x]
def test_6_sends_once_day_restart_next_day(tmp_path, monkeypatch):   # ⑥ N1·N2·N3 · ⑥a · ⑥b(M4) · ⑥c(M3)
    w = world(tmp_path, monkeypatch)
    head = done(w, "r9801")
    w.enable(), w.round()   # N1 = done 갈래 자리에서 1회(실 바퀴)
    body = "[줄 보완] ft2 keeper r9801 카드 증거 줄 없음 · PR #7 head %s — D2 좌석이 `bash ft-card-evidence.sh --card r9801 --set %s --pr 7 --test \"<나노 보고 시험 줄> rc=0\"` 1회(keeper 카드 쓰기 0)" % (head[:10], head)
    assert mail(w) == ["send M-harness ft2-keeper " + body], _lines(str(w.mbox) + ".log")
    refs = _git(w.root, "ls-remote", "origin")
    k, _ = notice(w, "r9801")
    assert len(mail(w)) == 1   # ⑥a 같은 날 다음 바퀴 0통
    notice(w, "r9801", k=k)
    assert len(mail(w)) == 1   # ⑥b 재기동 = 새 keeper(state.json 다시 읽기) 0통
    w.t += 86400
    notice(w, "r9801")
    assert len(mail(w)) == 2 and _git(w.root, "ls-remote", "origin") == refs   # ⑥c D+1 1통 · N3 카드 ref·git 쓰기 0
def test_6d_stand_in_gets_full_line(tmp_path, monkeypatch):   # ⑥d 팀 _master 빈칸 → harness _master 에 묶음 0 · 명령 안 잘림(M5)
    w = world(tmp_path, monkeypatch)
    _put(w.root / ".fable-team" / "seats-planner.json", {"_master": ""})
    head = done(w, "r9802", team="planner")
    k, _ = notice(w, "r9802", team="planner")
    got = mail(w)
    assert len(got) == 1 and got[0].startswith("send M-harness ") and got[0].endswith("--set %s --pr 7 --test \"<나노 보고 시험 줄> rc=0\"` 1회(keeper 카드 쓰기 0)" % head), got
    assert not k.state.get("undelivered"), k.state
def test_6e_set_line_present(tmp_path, monkeypatch):   # ⑥e 마지막 세트 줄 D2 꼴 → 0통 · 판정 불가 0
    w = world(tmp_path, monkeypatch)
    done(w, "r9803", text="- 세트: (빈 양식)\n" + SET)
    k, _ = notice(w, "r9803")
    assert not mail(w) and not [x for x in k.lines if "판정 불가" in x], k.lines
def test_7_unreadable_and_pr_count(tmp_path, monkeypatch):   # ⑦ gh 실패 · 카드 없음 → 0통 + 판정 불가 1줄 · ⑦' OPEN 0·2개 → 0통 · 판정 줄 0
    w = world(tmp_path, monkeypatch)
    for work, kv, bad in (("r9804", {"rc": 1}, 1), ("r9805", {"card": False}, 1), ("r9806", {"n": 0}, 0), ("r9807", {"n": 2}, 0)):
        done(w, work, **kv)
        k, _ = notice(w, work)
        assert not mail(w) and len([x for x in k.lines if x.startswith("판정 불가 harness %s" % work)]) == bad, (work, k.lines)
