"""r546 판정 기록기 — 4 훅 × 30 명령 × 자율 off/on = 240 판정(rc·종류·stderr 첫 줄)을 한 줄씩 낸다.
`bash tests/test_hook_cmd_split_shared_r546.sh` 의 ⓑ(바꾼 뒤 == 바꾸기 전)가 이 출력을 픽스처와 바이트 대조한다.
픽스처 = 임시 루트(진짜 git 리포 + byz-agents origin + .claude/skills/byz-keys + .fable-team) · 외부 호출 0 · 실 상태·실 settings 쓰기 0 ·
자율 모드는 임시 스텁(`mode.txt`)으로만 — 실 `ft-autonomy.sh`·실 `~/.claude` 를 건드리지 않는다.
★실행 자리 = «설치 꼴 임시 폴더»★ — 훅 4 + `merge_cmd.py` 를 한 폴더에 복사해 돌린다(홈 설치 뒤와 같은 배치 · 키트 templates 폴더에는 모듈이 없다).
usage: python3 tests/lib/r546_verdicts.py <kit_hooks_dir> <templates_hooks_dir>
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HOOKS = [("op-vault-develop-gate.sh", "kit"), ("tracked-bin-call-gate.sh", "kit"),
         ("autonomy-merge-guard.sh", "tpl"), ("autonomy-state-guard.sh", "tpl")]


def fixture():
    t = tempfile.mkdtemp(prefix="r546fix.")
    os.makedirs(os.path.join(t, ".claude/skills/byz-keys"))
    os.makedirs(os.path.join(t, ".fable-team/state"))
    os.makedirs(os.path.join(t, "harness/bin"))
    subprocess.run(["git", "-C", t, "init", "-q"], check=True)
    subprocess.run(["git", "-C", t, "remote", "add", "origin", "https://github.com/x/byz-agents.git"], check=True)
    for n in ("ft-nano-spawn", "ft-nano-close", "ft-role-spawn", "ft-successor-open", "ft-resource-gate", "ft-resource-reclaim"):
        with open(os.path.join(t, "harness/bin", n + ".sh"), "w", encoding="utf-8") as f:
            f.write("#!/bin/bash\n")
    with open(os.path.join(t, "stub-autonomy.sh"), "w", encoding="utf-8") as f:
        f.write('#!/bin/bash\ncat "$(dirname "$0")/mode.txt" 2>/dev/null || echo off\n')
    with open(os.path.join(t, "mode.txt"), "w", encoding="utf-8") as f:
        f.write("off\n")
    return t


def run_hook(path, cmd, t, mode):
    with open(os.path.join(t, "mode.txt"), "w", encoding="utf-8") as f:
        f.write(mode + "\n")
    env = {k: v for k, v in os.environ.items() if k not in ("TMUX", "FT_ALLOW_TRACKED_BIN", "CLAUDE_PROJECT_DIR")}
    env.update(FT_ROOT=t, FT_AUTONOMY_STATE_DIR=os.path.join(t, ".fable-team/state"),
               FT_AUTONOMY_SH=os.path.join(t, "stub-autonomy.sh"),
               FT_AUTONOMY_HOOK_LOG=os.path.join(t, "hook.log"), FT_AUTONOMY_LEVEL="each",
               FT_BIN=os.path.join(t, "harness/bin"))
    payload = json.dumps({"tool_name": "Bash", "cwd": t, "tool_input": {"command": cmd}}, ensure_ascii=False)
    p = subprocess.run(["bash", path], input=payload, capture_output=True, text=True, env=env, cwd=t, timeout=60)
    kind = "reject2" if p.returncode == 2 else ("deny" if 'permissionDecision": "deny"' in p.stdout else "allow")
    err = (p.stderr.strip().splitlines() or [""])[0].replace(t, "<T>")
    return p.returncode, kind, err


def rows(kit, tpl):
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "..", "fixtures", "r546_hook_cmd_split", "commands.json"), encoding="utf-8") as f:
        cmds = json.load(f)
    t = fixture()
    ih = os.path.join(t, "hooks")  # 설치 뒤 홈 훅 폴더 꼴
    os.makedirs(ih)
    for name, _ in HOOKS:
        shutil.copy(os.path.join(kit if name in ("op-vault-develop-gate.sh", "tracked-bin-call-gate.sh") else tpl, name), ih)
    shutil.copy(os.path.join(kit, "merge_cmd.py"), ih)
    out = []
    for mode in ("off", "on"):
        for name, _ in HOOKS:
            path = os.path.join(ih, name)
            for i, c in enumerate(cmds):
                rc, kind, err = run_hook(path, c, t, mode)
                out.append(f"{name}\t{mode}\t{i:02d}\t{rc}\t{kind}\t{err}")
    return out, len(cmds)


def main():
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    out, n = rows(os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2]))
    if len(out) != 4 * n * 2:
        print(f"행 수 이상: {len(out)} != {4 * n * 2}", file=sys.stderr)
        return 3
    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
