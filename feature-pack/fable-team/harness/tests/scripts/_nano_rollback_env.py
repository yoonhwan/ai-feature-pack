"""R81 시험 공용 — ft-nano-spawn-undo.sh 용 격리 리포 + 가짜 tmux(호출 기록·경합 주입). 실 tmux·실 슬랙·실 명부 접촉 0."""
import json
import os
import re
import shutil
import stat
import subprocess
import time

from ft_git_helpers import BIN, commit, git, init_repo, nano_prefix

PREFIX = nano_prefix()  # r687: 도구 기본 접두(r655 byz-v65-nano-) — spawn 이 찾는 좌석 이름과 같은 값
SEAT = f"{PREFIX}slug#0"
TMUX = """#!/bin/bash
echo "$*" >> "$R81_DIR/tmux.log"
case "$1" in
  list-panes) [ -e "$R81_DIR/session" ] && echo "$R81_SEAT|%1|$(cat "$R81_DIR/session")" ;;
  display-message) echo "$R81_WT" ;;
  set-option) [[ "$*" == *" -u "* ]] && [ -e "$R81_DIR/race" ] && echo '{"seq":9,"to":"'"$R81_SEAT"'","from":"x"}' >> "$R81_DIR/comm/mailbox.jsonl" ;;
esac
exit 0
"""


def exe(path, body):
    path.write_text(body if body.startswith("#!") else "#!/bin/bash\n" + body)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def make_env(tmp):
    """통과 조건 ⓐ~ⓗ 가 전부 충족된 상태 — 시험이 «하나씩» 깬다."""
    repo = init_repo(tmp / "repo", "feat/root")
    (repo / ".fable-team").mkdir()
    (repo / ".fable-team/seats.json").write_text("{}\n")
    card = repo / "design/v65/indices/대기/slug.md"
    card.parent.mkdir(parents=True)
    card.write_text("# 카드\n\n## 상태\n- 대기\n")
    (repo / ".serena").mkdir()
    (repo / ".serena/project.yml").write_text('project_name: "BYZ-Agents"\n')  # spawn 이 워크트리에서 sed 로 바꾸는 추적 파일
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "card")
    wt = repo / ".worktrees/v65-slug"
    git(repo, "worktree", "add", str(wt), "-b", "nano/slug", "feat/root")
    short = git(repo, "rev-parse", "--short", "feat/root").strip()
    (wt / ".worktree-info.json").write_text(json.dumps({"branch": "nano/slug", "base_sha": short}))
    (wt / ".serena/project.yml").write_text('project_name: "v65-slug"\n')  # 허용 목록 — 미커밋 수정이어도 통과
    comm, sh, home, state = tmp / "comm", tmp / "shim", tmp / "home", tmp / "state"
    for d in (comm, sh, home):
        d.mkdir()
    (comm / "mailbox.log.jsonl").write_text("")
    (comm / "mailbox.jsonl").write_text("")
    exe(sh / "tmux", TMUX)
    (tmp / "session").write_text(str(int(time.time()) - 10))
    return {"tmp": tmp, "repo": repo, "card": card, "wt": wt, "comm": comm, "sh": sh, "home": home, "state": state,
            "seats": repo / ".fable-team/seats.json", "ledger": tmp / "ledger.md"}


def tmux_log(env):
    p = env["tmp"] / "tmux.log"
    return p.read_text() if p.exists() else ""


def jsonl(env, *recs):
    """좌석명이 박힌 세션 jsonl — 사용자 턴은 recs 로 준다."""
    d = env["home"] / ".claude/projects" / re.sub(r"[^A-Za-z0-9]", "-", str(env["wt"]))
    d.mkdir(parents=True, exist_ok=True)
    rows = [{"type": "custom-title", "customTitle": SEAT}, *recs]
    (d / "s.jsonl").write_text("\n".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) for r in rows) + "\n")


def undo_env(env, **extra):
    """undo 실행 env — HIL_DIR 은 언제나 임시 폴더(r684: 시험이 진짜 /tmp/h<N> 번호표를 쓰지 않게)."""
    hil = env["tmp"] / "hil"
    hil.mkdir(exist_ok=True)
    return {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", "HOME": str(env["home"]), "R81_DIR": str(env["tmp"]),
            "R81_SEAT": SEAT, "R81_WT": str(env["wt"]), "FT_SEATS_JSON": str(env["seats"]), "FT_NANO_PREFIX": PREFIX,
            "FT_UNDO_STATE": str(env["state"]), "FT_MBOX_DIR": str(env["comm"]), "FT_NANO_LEDGER": str(env["ledger"]),
            "HIL_DIR": str(hil), **extra}


def undo(env, *args, seat=SEAT, **extra):
    e = undo_env(env, **extra)
    return subprocess.run(["bash", str(BIN / "ft-nano-spawn-undo.sh"), seat, *args], capture_output=True, text=True, cwd=env["repo"], env=e)


def owned(env):
    return f"%1:{(env['tmp'] / 'session').read_text().strip()}"


def roll(env, **extra):
    return undo(env, "--owned", owned(env), "--card", str(env["card"]), **extra)


def commit_in_wt(env):
    commit(env["wt"], {"w.txt": "x"}, "nano work")


def roster(e):
    e["seats"].write_text(f'{{"{SEAT}": {{"role": "nano"}}}}\n')


def _inprog(e):
    (e["card"].parents[1] / "진행").mkdir()
    (e["card"].parents[1] / "진행/slug.md").write_text("x")


def log_row(e, who="from"):
    (e["comm"] / "mailbox.log.jsonl").write_text(f'{{"seq":1,"{who}":"{SEAT}"}}\n')


BREAKS = {
    "a_roster_row": roster, "c_card_in_progress": _inprog, "d_consumed_mail_to": lambda e: log_row(e, "to"),
    "d_consumed_mail_from": log_row, "d_no_log_file": lambda e: (e["comm"] / "mailbox.log.jsonl").unlink(),
    "e_branch_commit": commit_in_wt, "f_dirty_file": lambda e: (e["wt"] / "x.py").write_text("x"),
    "g_user_turn": lambda e: jsonl(e, {"type": "user", "message": {"role": "user", "content": "hi"}}),
    "g_no_jsonl_old_session": lambda e: (e["tmp"] / "session").write_text("1700000000"),
    "g_text_block_turn": lambda e: jsonl(e, {"type": "user", "message": {"content": [{"type": "text", "text": "hi"}]}}),
    "c_not_in_waiting_dir": lambda e: shutil.move(str(e["card"]), str(e["card"].parents[1] / "slug.md")),
}
