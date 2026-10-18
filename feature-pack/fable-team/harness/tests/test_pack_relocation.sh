#!/usr/bin/env bash
# test_pack_relocation.sh — 재배치 대조 게이트 (설계 DESIGN-harness-repo-split-and-teams-move-20261018 §9-3 · r384)
# BYZ 기준 sha 의 6경로 ↔ 팩 «이력 병합» 커밋의 harness/ 를 표대로 맞대어
#   ⓐ 행마다 파일 수·sha256 목록 일치 + 표 밖 파일 0  ⓑ 이력 커밋 수 일치  ⓒ HEAD 의 bin·kit·comm·design·evidence = 병합 시점(시험만 치환)
# 사용: bash harness/tests/test_pack_relocation.sh   (env BYZ_REPO · BYZ_SHA · PACK_REV 로 바꿀 수 있다)
#   BYZ 리포가 없으면 ERROR rc2 — 건너뛰고 통과하지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PACK="$(git -C "$HERE" rev-parse --show-toplevel)"
BYZ_REPO="${BYZ_REPO:-$HOME/Project/Agent/BYZ-Work/BYZ-Agents}"
BYZ_SHA="${BYZ_SHA:-711199fd627deb033dd0ab5f54263282a458253d}"
PACK_REV="${PACK_REV:-$(git -C "$PACK" log --format=%H -1 --grep='harness 합류 — BYZ 6경로 이력 병합' HEAD)}"
git -C "$BYZ_REPO" cat-file -e "$BYZ_SHA^{commit}" 2>/dev/null || { echo "ERROR BYZ 리포·sha 없음: $BYZ_REPO $BYZ_SHA"; exit 2; }
[ -n "$PACK_REV" ] || { echo "ERROR 팩 이력 병합 커밋 없음(PACK_REV)"; exit 2; }

python3 - "$BYZ_REPO" "$BYZ_SHA" "$PACK" "$PACK_REV" <<'EOF'
import fnmatch, hashlib, subprocess, sys

byz, byz_sha, pack, rev = sys.argv[1:5]
P = "feature-pack/fable-team/harness/"
# 경로 표: (BYZ 경로 또는 글롭, 팩 harness/ 아래 목적지 접두사)
TABLE = [
    ("scripts/fable-team-bin/", "bin/"),
    ("scripts/harness-install/", "kit/"),
    ("tools/comm-canonical/", "comm/"),
    ("design/teams/harness/", "design/harness/"),
    ("tests/harness/", "tests/"),
    ("tests/scripts/", "tests/scripts/"),
    (".fable-team/state/", "evidence/state-v6/"),
]
SCRIPTS = ["test_mbox*", "test_magazine*", "_magazine_*", "_thread_fakes.py", "_proposal_fakes.py",
           "conftest.py", "fake_resource_env.py"]


def git(repo, *a):
    return subprocess.run(["git", "-C", repo, *a], check=True, capture_output=True).stdout


def listing(repo, ref, path):
    out = git(repo, "ls-tree", "-r", "-z", ref, "--", path).split(b"\0")
    rows = [r.decode().split("\t", 1) for r in out if r]
    return {name: meta.split()[2] for meta, name in rows}


def sha256s(repo, blobs):
    p = subprocess.run(["git", "-C", repo, "cat-file", "--batch"], input="".join(b + "\n" for b in blobs).encode(),
                       check=True, capture_output=True).stdout
    out, i = {}, 0
    for b in blobs:
        head_end = p.index(b"\n", i)
        size = int(p[i:head_end].split()[2])
        out[b] = hashlib.sha256(p[head_end + 1:head_end + 1 + size]).hexdigest()
        i = head_end + 1 + size + 1
    return out


def keep(src, rel):
    if src == "tests/scripts/":
        return "/" not in rel and any(fnmatch.fnmatch(rel, g) for g in SCRIPTS)
    if src == ".fable-team/state/":
        return rel.startswith("v6-")
    return True


fail = 0
pack_all = listing(pack, rev, P)
claimed = set()
for src, dst in TABLE:
    b = {k[len(src):]: v for k, v in listing(byz, byz_sha, src).items() if keep(src, k[len(src):])}
    if dst == "tests/":   # tests/scripts 행은 따로 센다
        p = {k[len(P + dst):]: v for k, v in pack_all.items() if k.startswith(P + dst) and not k.startswith(P + "tests/scripts/")}
    else:
        p = {k[len(P + dst):]: v for k, v in pack_all.items() if k.startswith(P + dst)}
    claimed |= {P + dst + k for k in p}
    hb, hp = sha256s(byz, list(b.values())), sha256s(pack, list(p.values()))
    lb = sorted(f"{hb[v]}  {k}" for k, v in b.items())
    lp = sorted(f"{hp[v]}  {k}" for k, v in p.items())
    ok = lb == lp
    fail += not ok
    print(f"{'PASS' if ok else 'FAIL'} ⓐ {src} → harness/{dst}  byz={len(lb)} pack={len(lp)}")
    if not ok:
        for d in sorted(set(lb) ^ set(lp))[:10]:
            print(f"     diff {d}")
outside = sorted(set(pack_all) - claimed)
print(f"{'PASS' if not outside else 'FAIL'} ⓐ 표 밖 파일 {len(outside)}  (harness/ 전체 {len(pack_all)})")
fail += bool(outside)
for f in outside[:10]:
    print(f"     outside {f}")

nb = len(git(byz, "log", "--format=%H", byz_sha, "--", "scripts/fable-team-bin").split())
np_ = len(git(pack, "log", "--format=%H", rev, "--", P + "bin").split())
print(f"{'PASS' if nb == np_ and np_ >= 1 else 'FAIL'} ⓑ 이력 커밋 수 bin  byz={nb} pack={np_}")
fail += not (nb == np_ and np_ >= 1)

changed = git(pack, "diff", "--name-only", rev, "HEAD", "--", P).decode().split()
frozen = [f for f in changed if not f.startswith((P + "tests/", P + "evidence/relocation-")) and f != P + "install.sh"]
print(f"{'PASS' if not frozen else 'FAIL'} ⓒ 병합 뒤 bin·kit·comm·design·evidence 변경 {len(frozen)} (키트 cmp0)")
fail += bool(frozen)
for f in frozen[:10]:
    print(f"     changed {f}")
print(f"== fail={fail}")
sys.exit(1 if fail else 0)
EOF
