#!/usr/bin/env bash
# ft-disk-census.sh [--json | --plan | --hil]  — 디스크 점유 원인 귀속표(읽기 전용 · 삭제 0): 워크트리·임시 사본마다 «종류 · 가지 · 만든 좌석 · 좌석 살아 있음 · 착지 · 미커밋 · 정리 경로» 한 줄 + 합계 표.
#   카드 r-disk-drop-worktree-scratch-census §구현 범위 1. 지우는 일은 하지 않는다 — 정리 경로 칸은 «어느 표준 도구가 맡는가» 의 표식일 뿐.
#   종류: nano(.worktrees/ · 가지 nano/*) · other(.worktrees/ · 그 밖 가지) · detached-worktrees(.worktrees/ · detached) · tmp-repo(repo-* · ft-scratch-repo 계열) · scratchpad-direct(…/scratchpad/… 좌석이 직접 만든 사본) · tmp-other
#   착지 4단(앞이 참이면 멈춤): ①cherry 이전 «조상» = ancestor · ②`git cherry main <가지>` 가 «+» 0 = cherry · ③main 의 완성 카드 «세트: <40hex>» == 가지 tip(카드 뒤 미착지 커밋이 붙으면 아님) = card — 판정은 ft-landed-check.sh 한 곳 · ④main 커밋 메시지에 카드 ID(<키>) = grep(★약한 증거 — 계획 대상 아님★)
#   정리 경로: plan:nano-close(나노 · 좌석 없음 · 착지 ①~③ · 미커밋 0) · keep:live-seat · keep:dirty · HIL:unlanded · HIL:weak-landed · HIL:other-branch · HIL:detached · HIL:no-info(.worktree-info.json 의 branch 가 nano/* 아님) · HIL:tmux-unknown(tmux 목록 실패 = fail-closed) · owner:done-note(등록 사본) · HIL:unregistered(repo-* 인데 등록 안 됨) · register(scratchpad 직접 사본) · HIL:tmp-other
#   --plan = 표를 만든 뒤 route=plan:nano-close 인 나노마다 `ft-nano-close.sh <좌석> --plan-only <워크트리>` 로 정리 계획(<wt-clean>/<좌석>.sh)만 만든다(이미 .sh/.sh.hil 이 있으면 건드리지 않음 · 새 삭제 권한 0 — 실행은 기존 ft-wt-sweep.sh 몫).
#     좌석 이름은 워크트리 접두로 정한다: v65-<키> → ft-v65-temp-<키>#0 · <팀>-<키> → byz-<팀>-nano-<키>#0(`.fable-team/bin-<팀>/<팀>-env.sh` 가 있을 때만 — 없으면 PLAN_SKIP). env FT_WT_CLEAN_DIR 로 계획 폴더 지정.
#     --plan 은 같은 턴에 둘을 더 한다 ⓐscratchpad 직접 사본(등록 안 됨)을 `.fable-team/state/scratch-repos.tsv` 에 «사후 등록»(주인 = 세션 폴더가 가리키는 살아 있는 좌석 · 없으면 `scratchpad-of:<폴더>` · 시각 = 디렉터리 생성 시각 — 그 뒤 기존 ft-scratch-repo --sweep 규칙(주인 세션 없음 ∧ 24h)이 처리 · cwd 를 쥔 프로세스가 있으면 등록 안 함)
#       ⓑ주인 세션이 살아 있는 등록 사본 중 `ft-scratch-repo.sh --judged` rc 0(판정 끝남)인 것은 주인에게 쪽지 «--done 하라» 1통(사본마다 1회 · 중복 방지 `.fable-team/state/census-notified.tsv` · 자동 삭제 0). env FT_MBOX · FT_CENSUS_FROM(발신 이름)
#   --hil = 읽기 전용 묶음 표 — ⓐ사람 확인 대기(.sh.hil) 정리 계획을 사유(`<계획>.log` 마지막 줄)별로 묶음 ⓑ표준 경로 밖 목록(다른 가지 워크트리 · detached · ~/.claude/projects 크기). planner [HIL] 1통의 본문 재료 — 삭제 0.
#   env: FT_RES_ROOT(리포 루트) · FT_CENSUS_MAIN(착지 기준 ref · 기본 origin/main 있으면 그것 없으면 main) · FT_CENSUS_GB_PER_WT(워크트리 1개 추정 GiB · 기본 1.5 — du 전체 스캔 금지) · FT_TMUX_BIN · FT_CENSUS_OUT(결과 JSON 캐시 · 기본 <루트>/.fable-team/state/disk-census.last.json)
#   부하: nice 10 · 워크트리당 git 조회 ≈ 3~5회 · du 기본 0(R323 · 크기 = FT_CENSUS_GB_PER_WT 상수 × 개수 · FT_CENSUS_DU=1 일 때만 사본 표본 3개 du).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_RES_ROOT:-$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "ERROR 리포 루트를 못 찾음(FT_RES_ROOT)" >&2; exit 4; }
case "${1:-}" in ""|--json|--plan|--hil) ;; *) echo "usage: $0 [--json | --plan | --hil]" >&2; exit 2;; esac
export FT_ROOT="$ROOT" FT_MODE="${1:-text}" FT_SELF="$HERE/ft-disk-census.sh"
exec nice -n 10 python3 -I - <<'PY'
import json, os, re, subprocess, sys

ROOT = os.environ["FT_ROOT"]
MODE = os.environ["FT_MODE"]
GB = float(os.environ.get("FT_CENSUS_GB_PER_WT", "1.5"))
TMUX = os.environ.get("FT_TMUX_BIN", "tmux")
OUT = os.environ.get("FT_CENSUS_OUT", os.path.join(ROOT, ".fable-team/state/disk-census.last.json"))
TSV = os.path.join(ROOT, ".fable-team/state/scratch-repos.tsv")


def git(*a, cwd=ROOT):
    r = subprocess.run(["git", "-C", cwd, *a], capture_output=True, text=True)
    return r.returncode, r.stdout


def pick_main():
    m = os.environ.get("FT_CENSUS_MAIN")
    if m:
        return m
    return "origin/main" if git("rev-parse", "--verify", "-q", "origin/main")[0] == 0 else "main"


MAIN = pick_main()


def sessions():
    try:
        r = subprocess.run([TMUX, "list-sessions", "-F", "#{session_name}"], capture_output=True, text=True)
    except OSError:
        return None
    return r.stdout.split() if r.returncode == 0 else None


SESS = sessions()


def worktrees():
    out, cur = [], {}
    for line in git("worktree", "list", "--porcelain")[1].splitlines() + [""]:
        if not line:
            if cur:
                out.append(cur)
            cur = {}
            continue
        k, _, v = line.partition(" ")
        cur[k] = v
    return out


def registry():
    reg = {}
    try:
        for line in open(TSV, encoding="utf-8").read().splitlines():
            p = line.split("\t")
            if len(p) >= 2:
                reg[os.path.realpath(p[0])] = p[1]   # git 은 실경로(/private/var)로 보고하고 등록부는 $TMPDIR(/var) 로 적는다
    except OSError:
        pass
    return reg


def cards_on_main():
    _, names = git("ls-tree", "-r", "--name-only", MAIN, "--", "design")
    return [n for n in names.splitlines() if re.fullmatch(r"design/[^/]+/indices/완성/[^/]+\.md", n)]


CARDS = cards_on_main()


def landed(branch, key):
    """착지 판정은 공용 ft-landed-check.sh 한 곳(생성·실행 시점과 같은 판정) — 출력 1단어."""
    r = subprocess.run(["bash", os.path.join(os.path.dirname(os.path.abspath(os.environ["FT_SELF"])), "ft-landed-check.sh"), ROOT, MAIN, branch, key], capture_output=True, text=True)
    w = (r.stdout.strip().splitlines() or ["no"])[-1]
    return w if w in ("ancestor", "cherry", "card", "grep", "no") else "no"


def dirty_count(wt):
    rc, st = git("status", "--porcelain", cwd=wt)
    if rc != 0:
        return -1
    # ' D '(작업 트리에서만 지워진 줄 = 지우다 만 껍데기)·.serena/project.yml 은 실작업물이 아니다 — ft-nano-close 계획 가드와 같은 기준
    return sum(1 for l in st.splitlines() if not l.endswith(".serena/project.yml") and not l.startswith(" D "))


def du_gb(path):
    if os.environ.get("FT_CENSUS_DU") != "1":   # R323: du 전체 스캔 금지 — 기본은 상수 추정(켜려면 FT_CENSUS_DU=1)
        return None
    try:
        r = subprocess.run(["du", "-sk", path], capture_output=True, text=True, timeout=20)
        return int(r.stdout.split()[0]) / 1048576
    except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
        return None


def live_for(key):
    if SESS is None:
        return None
    pat = re.compile(rf"(^|-)nano-{re.escape(key)}(-r\d+)?#\d+$|^ft-v65-temp-{re.escape(key)}(-r\d+)?#\d+$")
    return any(pat.search(s) for s in SESS)


def scratch_owner(p):
    """scratchpad 경로 …/claude-501/<인코딩된 cwd>/<uuid>/scratchpad/… 의 세션 폴더 → 좌석 이름 (살아 있는 세션 우선 · 없으면 scratchpad-of:<워크트리 이름>)."""
    m = re.search(r"--worktrees-([^/]+)/[^/]+/scratchpad/", p)
    if not m:
        return "?"
    wtname = m.group(1)
    key = wtname.split("-", 1)[1] if "-" in wtname else wtname
    for s in SESS or []:
        if s.startswith(f"byz-{wtname}-") or re.search(rf"-nano-{re.escape(key)}(-r\d+)?#\d+$", s):
            return s
    return f"scratchpad-of:{wtname}"


def classify(w, reg):
    p = w["worktree"]
    br = w.get("branch", "").replace("refs/heads/", "") or None
    inside = p.startswith(os.path.join(ROOT, ".worktrees") + "/")
    row = {"path": p, "kind": "tmp-other", "branch": br, "creator": "?", "live": False, "landed": "n/a", "dirty": 0, "route": "HIL:tmp-other"}
    if inside:
        row["kind"] = "detached-worktrees" if br is None else ("nano" if br.startswith("nano/") else "other")
    elif os.path.basename(p).startswith("repo-"):
        row["kind"] = "tmp-repo"
    elif "/scratchpad/" in p:
        row["kind"] = "scratchpad-direct"
    return row


def fill(row, reg):
    k, p, br = row["kind"], row["path"], row["branch"]
    if k in ("nano", "other"):
        row["dirty"] = dirty_count(p)
    if k == "nano":
        key = re.sub(r"-r\d+$", "", br[len("nano/"):])
        row["creator"] = f"nano-{key}"
        row["live"] = live_for(key)
        row["landed"] = landed(br, key)
        weak = row["landed"] == "grep"
        strong = row["landed"] in ("ancestor", "cherry", "card")
        if row["live"] is None:
            row["route"] = "HIL:tmux-unknown"
        elif row["live"]:
            row["route"] = "keep:live-seat"
        elif row["dirty"] != 0:
            row["route"] = "keep:dirty"
        elif strong:
            # 계획 가드 ③ 과 같은 기준 — .worktree-info.json 의 branch 가 nano/* 가 아니면 계획이 skipped 로 멈춘다(계획을 만들지 않고 목록에만)
            try:
                info_br = json.load(open(os.path.join(p, ".worktree-info.json"), encoding="utf-8")).get("branch", "")
            except (OSError, ValueError):
                info_br = ""
            row["route"] = "plan:nano-close" if info_br.startswith("nano/") else "HIL:no-info"
        else:
            row["route"] = "HIL:weak-landed" if weak else "HIL:unlanded"
    elif k == "other":
        row["route"] = "HIL:other-branch"
    elif k == "detached-worktrees":
        row["route"] = "HIL:detached"
    elif k == "tmp-repo":
        owner = reg.get(os.path.realpath(p))
        row["creator"] = owner or "(등록 안 됨)"
        if owner and SESS is not None:
            row["live"] = owner in SESS
        row["route"] = "owner:done-note" if owner else "HIL:unregistered"
    elif k == "scratchpad-direct":
        row["creator"] = scratch_owner(p)
        row["route"] = "register" if os.path.realpath(p) not in reg else "owner:done-note"
    return row


def gb_of(rows):
    est = {}
    for kind in {r["kind"] for r in rows}:
        grp = [r for r in rows if r["kind"] == kind]
        if kind in ("tmp-repo", "scratchpad-direct", "tmp-other"):
            sizes = [s for s in (du_gb(r["path"]) for r in grp[:3]) if s is not None]
            est[kind] = (sum(sizes) / len(sizes)) if sizes else GB
        else:
            est[kind] = GB
    return est


def print_table(rows, summary):
    for r in rows:
        print("\t".join(str(x) for x in (os.path.relpath(r["path"], ROOT) if r["path"].startswith(ROOT) else r["path"], r["kind"], r["branch"] or "-", r["creator"], "live" if r["live"] else ("?" if r["live"] is None else "-"), r["landed"], r["dirty"], r["route"])))
    print(f"\n합계 (기준 {MAIN} · 워크트리 {len(rows)} · 크기는 추정 — 표본/상수 × 개수)")
    for s in summary:
        print(f"{s['kind']:20s} {s['route']:18s} {s['count']:4d}개  ≈{s['gb']:.1f} GiB")


def seat_for(row):
    """워크트리 접두 → 좌석 이름 (없으면 None + 사유)."""
    base = os.path.basename(row["path"])
    key = re.sub(r"-r\d+$", "", row["branch"][len("nano/"):])
    if base.startswith("v65-"):
        return f"ft-v65-temp-{key}#0", ""
    team = base.split("-", 1)[0]
    if os.path.isfile(os.path.join(ROOT, ".fable-team", f"bin-{team}", f"{team}-env.sh")):
        return f"byz-{team}-nano-{key}#0", ""
    return None, f"팀 env 없음(.fable-team/bin-{team}/{team}-env.sh)"


def make_plans(rows):
    wtc = os.environ.get("FT_WT_CLEAN_DIR") or os.path.join(ROOT, ".fable-team/state/wt-clean")
    close = os.path.join(os.path.dirname(os.path.abspath(os.environ.get("FT_SELF", sys.argv[0]))), "ft-nano-close.sh")
    made = skip = 0
    for r in rows:
        if r["route"] != "plan:nano-close":
            continue
        seat, why = seat_for(r)
        if seat is None:
            skip += 1
            print(f"PLAN_SKIP {r['path']} — {why}")
            continue
        if any(os.path.exists(os.path.join(wtc, f"{seat}.sh{x}")) for x in ("", ".hil")):
            skip += 1
            print(f"PLAN_SKIP {r['path']} — 계획 이미 있음({seat})")
            continue
        p = subprocess.run(["bash", close, seat, "--plan-only", r["path"]], capture_output=True, text=True, cwd=ROOT)
        last = (p.stdout.strip().splitlines() or [""])[-1]
        if p.returncode == 0 and last.startswith("PLANNED "):
            made += 1
            print(last)
        else:
            skip += 1
            print(f"PLAN_SKIP {r['path']} — rc={p.returncode} {last or p.stderr.strip()[:120]}")
    print(f"계획 생성 {made} · 건너뜀 {skip}")


def cwd_holders(path):
    r = subprocess.run(["lsof", "-w", "-d", "cwd", "-Fn"], capture_output=True, text=True)
    return sum(1 for l in r.stdout.splitlines() if l.startswith("n" + path))


def register_scratchpad(rows, reg):
    n = 0
    for r in rows:
        if r["route"] != "register":
            continue
        p = os.path.realpath(r["path"])
        if cwd_holders(p):
            print(f"REGISTER_SKIP {p} — cwd 를 쥔 프로세스가 있다")
            continue
        try:
            born = int(os.stat(p).st_birthtime)
        except (OSError, AttributeError):
            born = int(os.stat(p).st_mtime)
        os.makedirs(os.path.dirname(TSV), exist_ok=True)
        with open(TSV, "a", encoding="utf-8") as f:
            f.write(f"{p}\t{r['creator']}\t{born}\n")
        n += 1
        print(f"REGISTERED {p} owner={r['creator']}")
    print(f"scratchpad 사후 등록 {n}")


def notify_owners(rows, reg):
    done = os.path.join(ROOT, ".fable-team/state/census-notified.tsv")
    try:
        seen = set(open(done, encoding="utf-8").read().split())
    except OSError:
        seen = set()
    scratch = os.path.join(os.path.dirname(os.path.abspath(os.environ["FT_SELF"])), "ft-scratch-repo.sh")
    mbox = os.environ.get("FT_MBOX") or os.path.join(ROOT, ".fable-team/comm/mbox.sh")
    frm = os.environ.get("FT_CENSUS_FROM", "ft-disk-census")
    by_owner = {}
    for r in rows:
        if r["route"] != "owner:done-note" or r["kind"] != "tmp-repo" or not r["live"]:
            continue
        p = os.path.realpath(r["path"])
        if p in seen:
            continue
        if subprocess.run(["bash", scratch, "--judged", p], capture_output=True, text=True, cwd=ROOT).returncode == 0:
            by_owner.setdefault(r["creator"], []).append(p)
    sent = 0
    for owner, paths in by_owner.items():
        body = "[임시 사본 정리 요청] 판정 끝난 사본 %d개 — 쓸 일 없으면 좌석 손으로 지워 주세요(자동 삭제 0): %s" % (len(paths), " ; ".join(f"bash ft-scratch-repo.sh --done {x}" for x in paths))
        p = subprocess.run(["bash", mbox, "send", owner, frm, body], capture_output=True, text=True, cwd=ROOT)
        if p.returncode != 0:
            print(f"NOTE_FAIL {owner} rc={p.returncode} {p.stdout.strip()[:100]}")
            continue
        sent += 1
        with open(done, "a", encoding="utf-8") as f:
            f.write("".join(x + "\n" for x in paths))
        print(f"NOTE {owner} {len(paths)}개")
    print(f"주인 쪽지 {sent}")


def hil_tables(rows):
    wtc = os.environ.get("FT_WT_CLEAN_DIR") or os.path.join(ROOT, ".fable-team/state/wt-clean")
    plans = sorted(f for f in os.listdir(wtc) if f.endswith(".sh.hil")) if os.path.isdir(wtc) else []
    buckets = {}
    for f in plans:
        why = "(사유 로그 없음)"
        try:
            # 실제 생산자(ft-wt-sweep · close _wt_clean_run)는 <seat>.sh.log 에 쓰고 계획을 <seat>.sh.hil 로 옮긴다
            lp = os.path.join(wtc, f[: -len(".hil")] + ".log")
            if not os.path.exists(lp):
                lp = os.path.join(wtc, f + ".log")
            lines = [ln for ln in open(lp, encoding="utf-8").read().splitlines() if ln.strip()]
            if lines:
                why = re.sub(r"^skipped:", "", lines[-1])
        except OSError:
            pass
        buckets.setdefault(re.sub(r"\d+", "N", why)[:100], []).append(f[: -len(".sh.hil")])
    print(f"HIL 대기 계획 {len(plans)}건 — 사유별 묶음")
    for why, seats in sorted(buckets.items(), key=lambda kv: -len(kv[1])):
        print(f"  {len(seats):3d}건  {why}  예: {', '.join(seats[:2])}")
    print("\n표준 경로 밖 목록(삭제 0 · planner [HIL] 1통 재료)")
    for k in ("HIL:other-branch", "HIL:detached", "HIL:unlanded", "HIL:weak-landed", "HIL:tmp-other", "HIL:unregistered", "HIL:no-info"):
        grp = [r for r in rows if r["route"] == k]
        if grp:
            print(f"  {k}: {len(grp)}개")
            for r in grp[:50]:
                print(f"    {os.path.relpath(r['path'], ROOT) if r['path'].startswith(ROOT) else r['path']}\t{r['branch'] or '-'}")
    hist = os.path.expanduser("~/.claude/projects")
    sz = du_gb(hist) if os.path.isdir(hist) else None
    print(f"\n대화 기록 {hist}: {'%.1f GiB' % sz if sz is not None else '크기 미측정(du 금지 R323)'} (재개에 쓰임 — 삭제 대상 아님 · 범위 밖)")


def main():
    reg = registry()
    wts = [w for w in worktrees() if w.get("worktree") != ROOT and not w.get("bare")]
    rows = [fill(classify(w, reg), reg) for w in wts]
    est = gb_of(rows)
    summ = {}
    for r in rows:
        s = summ.setdefault((r["kind"], r["route"]), {"kind": r["kind"], "route": r["route"], "count": 0, "gb": 0.0})
        s["count"] += 1
        s["gb"] = round(s["gb"] + est[r["kind"]], 2)
    summary = sorted(summ.values(), key=lambda s: (s["kind"], s["route"]))
    result = {"main": MAIN, "rows": rows, "summary": summary}
    try:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with open(OUT, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False)
    except OSError as e:
        print(f"WARN 캐시 저장 실패: {e}", file=sys.stderr)
    if MODE == "--plan":
        print_table(rows, summary)
        make_plans(rows)
        register_scratchpad(rows, reg)
        notify_owners(rows, reg)
        return
    if MODE == "--hil":
        hil_tables(rows)
        return
    if MODE == "--json":
        print(json.dumps(result, ensure_ascii=False))
        return
    print_table(rows, summary)


main()
PY
