"""ft 2.0 holder 읽기 공용 (r1960 이 auto_opened 만 먼저 둔다 · 나머지 = r1962 · DA#10 r1962 #301672 · 쓰기 0).

auto_opened = 자동 개설 판정 — 지금 tmux 세션의 #{session_id}·#{session_created} 가 launch 개설 영수(intent tmux_sid·tmux_created)와
같은 생애 ∧ intent worktree == pane cwd 일 때만 참 · 영수 없음(이름만 같은 옛 intent·1.x spawn)·판독 실패 = 거짓(닫기 0).
"""
import os

FMT = "#{session_id}\t#{session_created}\t#{pane_current_path}"


def auto_opened(call, tmux, seat, intent):
    """(참·거짓, 사유) · call(argv) → (rc, stdout, stderr) · 대상 `=이름:`(pane) 고정."""
    sid, created, tree = (str(intent.get(n) or "") for n in ("tmux_sid", "tmux_created", "worktree"))
    if not (sid and created):
        return False, "개설 영수 없음 · 손 0"
    rc, out, err = call([tmux, "display-message", "-p", "-t", "=%s:" % seat, FMT])   # 대상 한 낱말(tmux-target lint 판독 꼴)
    got = out.strip("\n").split("\t") if rc == 0 else []
    if len(got) != 3:
        return False, "판정 불가 · tmux display rc %s %s" % (rc, err)
    if got[:2] != [sid, created]:
        return False, "개설 영수 생애 다름(%s/%s ≠ %s/%s) · 손 0" % (got[0], got[1], sid, created)
    if not tree or os.path.realpath(got[2]) != os.path.realpath(tree):
        return False, "pane cwd ≠ intent worktree · 손 0"
    return True, ""
