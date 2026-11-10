#!/usr/bin/env bash
# red-70s.sh — r958 ⓐ : «지금 판» 게이트가 커밋 수에 비례해 git 을 부르므로 70초 상한을 넘겨 REJECT 되는 실사건 재현.
#   임시 리포(«+» 커밋 300 · design/ 만) + 가짜 느린 git(호출마다 0.08초 — 이 맥 실측 git 1회 0.02~0.05초에 여유를 곱한 값) ·
#   바깥 상한 70초 = ft-nano-close.sh ⑤ 가 r938 에서 걸던 값(nf_cap 상한 70). 실 좌석·실 워크트리·Redis·press 접촉 0.
set -uo pipefail
KIT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../bin" && pwd)"
OLD="${OLD_GATE:-}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
[ -n "$OLD" ] || { git -C "$KIT" show origin/main:feature-pack/fable-team/harness/bin/ft-nano-cherry-gate.sh > "$T/old.sh" 2>/dev/null || git -C "$KIT" show HEAD:feature-pack/fable-team/harness/bin/ft-nano-cherry-gate.sh > "$T/old.sh"; OLD="$T/old.sh"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
R="$T/r"; git init -q -b main "$R"
mkdir -p "$R/app" "$R/design"; printf 'x\n' > "$R/app/main.py"; printf 'd\n' > "$R/design/base.md"
git -C "$R" add -A; git -C "$R" commit -qm base
git -C "$R" checkout -q -b nano/x
for i in $(seq 1 300); do printf 'd%s\n' "$i" > "$R/design/c$i.md"; git -C "$R" add -A; git -C "$R" commit -qm "nano $i"; done
git -C "$R" checkout -q main; printf 'feat\n' > "$R/app/main.py"; git -C "$R" add -A; git -C "$R" commit -qm "feat touch"
REAL_GIT="$(command -v git)"; mkdir -p "$T/bin"
printf '#!/bin/bash\necho "$*" >> "$FT_GIT_LOG"\nsleep "${SLOW:-0.08}"\nexec "$REAL_GIT" "$@"\n' > "$T/bin/git"; chmod 755 "$T/bin/git"
capped() {  # <초> <태그> <게이트> — 바깥 상한 초처럼 (nf_bound 와 같은 껍데기: 실제 시간 초과만 rc 124)
  python3 - "$1" "$2" "$3" "$R" "$T" "$OLD" <<'PY'
import subprocess, sys, time
cap, tag, gate, repo, tmp, old = sys.argv[1:7]
cmd = ["bash", gate, "main", "nano/x", "--repo", repo]
log = tmp + "/calls-" + tag
env = {"PATH": tmp + "/bin:/usr/bin:/bin:/usr/sbin:/sbin", "FT_GIT_LOG": log, "REAL_GIT": subprocess.run(["bash","-lc","command -v git"],capture_output=True,text=True).stdout.strip(), "HOME": tmp}
t0 = time.time()
p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True, env=env)
try:
    out = p.communicate(timeout=float(cap))[0].decode("utf-8", "replace"); rc = p.returncode
except subprocess.TimeoutExpired:
    p.kill(); out = ""; rc = 124
took = time.time() - t0
n = sum(1 for _ in open(log)) if __import__("os").path.exists(log) else 0
print("gate=%s rc=%d took=%.1fs 외부 호출=%d회 (커밋 300)" % (tag, rc, took, n))
if rc == 124:
    print("REJECT ⑤cherry 게이트 시간 초과 %ds/70s · 배수 300 — 다시: 같은 명령(일시 부하면) · 계속이면 arch 에 cherry 게이트·70s 보고 (실사건과 같은 꼴)" % int(took))
print(out.strip()[:400])
PY
}
echo "== ⓐ-1 지금 판(origin/main ft-nano-cherry-gate.sh) · 바깥 상한 70초"
capped 70 old "$OLD"
echo
echo "== ⓐ-2 새 판(현재 ft-nano-cherry-gate.sh) · 같은 리포 · 같은 느린 git"
capped 70 new "$KIT/ft-nano-cherry-gate.sh"
