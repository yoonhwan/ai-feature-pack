#!/usr/bin/env python3
"""r895 classify.py <raw 폴더> <리포 이름> — 측정 표(worktrees·landed2)를 «지울 후보» 분류로 합친다. 읽기 전용 · 삭제 0.

쓰는 중 판정 = ①모든 프로세스 cwd(lsof -d cwd) ②tmux 모든 pane 의 현재 경로 — 워크트리 경로 안이면 «쓰는 중».
분류(정본 = 전역 CLAUDE.md «파괴·비가역 작업 HIL» 절):
  사라짐(측정 뒤)                  분류 시점에 폴더 없음 — 측정과 분류 사이에 주인이 정리(--done·nano-close) · 후보 아님
  keep:쓰는중                      cwd·pane 이 그 안 → 후보 아님
  밖:미커밋                        실작업물 > 0 → 팀 확인 뒤 오빠 결정
                                   (실작업물 = status --porcelain -uno 중 « D»(작업 트리에서만 지운 줄) 제외 — ft-nano-close r-wt-clean-deletion-only 와 같은 규칙.
                                    실측: 228개가 `.serena/` 지운 흔적 7줄뿐 · Serena 은퇴 10-22)
  밖:미착지                        미착지·못잼 → 지우지 않음(팀 확인)
  안:nano-close                    nano/* · 쓰는 중 아님 · dirty 0 · 조상|변경없음 → 09-25 나노 워크트리 정리(브랜치 보존)
  안후보:nano-close(census 확인)   nano/* · 내용착지(squash) → census 착지 판정 통과 시 위와 같음
  안:scratch-sweep                 TMPDIR repo-* 등록 사본 ∧ detached ∧ 미커밋 0 → 판정 1920 조건(주인 없음 ∧ 24h)까지 겹칠 때만 자동
                                   (정본 = hil.md 판정 1920 «등록한 detached worktree 사본 중 주인 tmux 세션이 없고 24시간 지난 것». 그래서
                                    가지에 붙은 사본(detached 아님)은 안이 아니다 · 미커밋 >0 도 안이 아니다 — DA r1 #1·#2)
  밖:등록 밖 사본                  TMPDIR repo-* 인데 등록부에 줄 없음 → --done·sweep 둘 다 못 지움 · 오빠 결정 1줄
  밖:나노 밖 워크트리              그 밖 가지·detached · 착지 + «가지에 붙은 사본» → 오빠 결정 1줄(비나노 워크트리 제거 = HIL)
출력: <raw>/<리포>-classified.tsv · stdout 합계(분류별 개수·GiB) + scratch-sweep 조건(주인 없음 ∧ 24h) 충족분

--replay: 판정을 다시 재지 않는다 — 이미 잰 <리포>-classified.tsv 의 branch·dirty·land·class 칸을 그대로 넣고
          분류 규칙만 새로 적용한다(lsof·tmux·git status 호출 0). 표 숫자를 raw 로 다시 계산할 때 쓴다.
"""
import csv, os, subprocess, sys

raw, name = sys.argv[1], sys.argv[2]
REPLAY = "--replay" in sys.argv[3:]


def held_paths():
    out = set()
    r = subprocess.run(["lsof", "-a", "-d", "cwd", "-Fn"], capture_output=True, text=True, timeout=30)
    out.update(l[1:] for l in r.stdout.splitlines() if l.startswith("n/"))
    r = subprocess.run(["tmux", "list-panes", "-a", "-F", "#{pane_current_path}"], capture_output=True, text=True, timeout=10)
    if r.returncode != 0:
        sys.exit("ERROR tmux 목록 실패 — 쓰는 중 판정 불가(fail-closed)")
    out.update(l for l in r.stdout.splitlines() if l)
    return {os.path.realpath(p) for p in out}


def in_use(path, held):
    rp = os.path.realpath(path)
    return any(h == rp or h.startswith(rp + "/") for h in held)


def real_dirty(path, dirty):
    if dirty in ("0", "-"):
        return dirty
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")
    try:
        r = subprocess.run(["git", "-C", path, "status", "--porcelain", "-uno"], capture_output=True, text=True, timeout=7, env=env)
    except subprocess.TimeoutExpired:
        return "못잼"
    return str(sum(1 for l in r.stdout.splitlines() if not l.startswith(" D ")))


def registered():
    return {os.path.realpath(r["path"]): r for r in csv.DictReader(open(f"{raw}/scratch-registered.tsv"), delimiter="\t")}


def sweep_ready(path, reg):
    """판정 1920 조건: 등록 ∧ 실재 ∧ 주인 tmux 없음 ∧ 24시간 지남 (detached·미커밋 0 은 분류에서 이미 걸렀다)."""
    g = reg.get(os.path.realpath(path))
    return bool(g) and g.get("exists") == "있음" and g.get("owner_live") == "없음" \
        and g.get("age_h", "").isdigit() and int(g["age_h"]) >= 24


def classify(row, land, held, reg):
    p, br, kib, dirty = row["path"], row["branch"], row["kib"], row["dirty"]
    if kib.startswith("없음"):
        return "밖:등록만 남음(prunable)"
    if not os.path.isdir(p):
        return "사라짐(측정 뒤)"
    if in_use(p, held):
        return "keep:쓰는중"
    if "/T/repo-" in p:
        if os.path.realpath(p) not in reg:
            return "밖:등록 밖 사본"
        if br != "(detached)":       # 가지에 붙은 사본 = sweep 대상 아님(표준승인 밖 · DA r1 #2)
            return "밖:나노 밖 워크트리"
        return "안:scratch-sweep" if dirty in ("0", "-") else "밖:미커밋"   # 미커밋 >0 = 지우지 않음(DA r1 #1)
    if dirty not in ("0", "-"):   # 못잼 포함 → 밖
        return "밖:미커밋"
    if land in ("미착지", "못잼", ""):
        return "밖:미착지"
    if br.startswith("nano/"):
        return "안:nano-close" if land in ("조상", "변경없음") else "안후보:nano-close(census 확인)"
    return "밖:나노 밖 워크트리"


def main():
    reg = registered()
    tot, ready = {}, [0, 0]
    if REPLAY:   # 이미 잰 칸을 그대로 쓴다 — 쓰는 중 판정은 지난 회차의 keep 행을 그대로 옮긴다
        src = f"{raw}/{name}-classified.tsv"
        rows = list(csv.DictReader(open(src), delimiter="\t"))
        held = {os.path.realpath(r["path"]) for r in rows if r["class"].startswith("keep:")}
    else:
        held = held_paths()
        rows = list(csv.DictReader(open(f"{raw}/{name}-worktrees.tsv"), delimiter="\t"))
    land2 = {}
    lp = f"{raw}/{name}-landed2.tsv"
    if os.path.exists(lp):
        land2 = {r["path"]: r["land2"].split("(")[0] for r in csv.DictReader(open(lp), delimiter="\t")}
    with open(f"{raw}/{name}-classified.tsv", "w") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        w.writerow(["path", "branch", "head", "kib", "dirty", "land", "class"])
        for r in rows:
            if REPLAY:   # 스냅샷 그대로 — 쓰는 중·사라짐은 지난 회차 값을 그대로 둔다(라이브 상태가 움직였다고 표 숫자를 바꾸지 않는다)
                land = r["land"]
                c = r["class"] if r["class"].startswith(("keep:", "사라짐")) else classify(r, land, held, reg)
            else:
                land = "조상" if r["landed"] == "조상" else land2.get(r["path"], r["landed"])
                r["dirty"] = real_dirty(r["path"], r["dirty"]) if os.path.isdir(r["path"]) else r["dirty"]
                c = classify(r, land, held, reg)
            w.writerow([r["path"], r["branch"], r["head"], r["kib"], r["dirty"], land, c])
            n, k = tot.get(c, (0, 0))
            kib = int(r["kib"]) if r["kib"].isdigit() else 0
            tot[c] = (n + 1, k + kib)
            if c == "안:scratch-sweep" and sweep_ready(r["path"], reg):
                ready[0], ready[1] = ready[0] + 1, ready[1] + kib
    for c, (n, k) in sorted(tot.items(), key=lambda x: -x[1][1]):
        print(f"{c}\t{n}\t{k / 1048576:.1f} GiB")
    print(f"안:scratch-sweep 조건충족(주인 없음 ∧ 24h)\t{ready[0]}\t{ready[1] / 1048576:.1f} GiB")


main()
