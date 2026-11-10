#!/usr/bin/env bash
# ft-child-watch.sh [--dry-run] | --table | --kill <좌석> | --kill-orphans   (r1113 · 판정 2769·2770 · 오빠 «node 정리 절대로 놓치면 안되는작업»)
#   틱(ft-stall-scan 이 부름 · FT_CHILD_WATCH_EVERY_SEC 540초에 1회): ft-seat-quiesce.sh --survey 표 1장 → 명부 좌석마다 경보 2종 + 고아.
#   ① [자식] <좌석> 유휴 <m>분 · 자식 <MB> · <top3> — 유휴 ≥ FT_CHILD_IDLE_MIN(20) ∧ 자식 RSS 합 ≥ FT_CHILD_RSS_MB(300) → 하네스 master 1통
#      자율 ON(ft-autonomy.sh scope-status «[범위 승인 S…» · 시험 FT_CHILD_AUTONOMY=on|off) = 같은 틱에 --mode done 까지 · OFF = 경보만
#      작업 중 신호(좌석 나무에 도구 셸 `sh -c …` 실행 중 = survey S 줄 9번째 칸)가 있으면 ON 이어도 경보만 · --kill 도 REJECT
#   ② [유휴 나노] <좌석> 유휴 <m>분 · 카드 <상태> — 역할 nano(pi 포함) ∧ 유휴 ≥ FT_NANO_IDLE_MIN(30) ∧ 카드 «## 상태» 마지막 줄이 끝남 → 그 팀 _master 1통(닫기 = master · 이 도구 kill 0)
#   고아 [고아] N개 · MB — ppid 1 무거운 프로세스(launchd 밖) · 자율 ON = --orphans 까지
#   같은 좌석·같은 종류 경보 = 하루 1회(장부 state/child-watch.sent) · 유휴 = tmux window_activity(마지막 출력) 기준 분
#   --table = 조회 표(좌석·역할·유휴·자식MB·무거운MB·top3 + 고아 · 신호 0 · 발신 0) · planner·desk 가 본다
#   --kill <좌석> = 한 명령 강제 정리(--mode done · 자율 무관) — 유휴 < FT_CHILD_IDLE_MIN(쓰는 중) 이면 REJECT rc 1(안 죽임) · --kill-orphans = 고아만
#   출력 끝 줄 `child-watch seats=<n> child=<n> nano=<n> orphans=<n> quiesced=<n>` · 표 state/child-watch.tsv · 장부 state/child-watch.log
#   rc 0 · 1 = REJECT · 2 = usage · 20 = 판정 불가(조사 실패 1줄 · 조치 0)
set -uo pipefail
USAGE="usage: $0 [--dry-run] | --table | --kill <좌석> | --kill-orphans"
OP=tick; DRY=0; TARGET=""
case "${1:-}" in "") ;; --dry-run) DRY=1;; --table) OP=table;; --kill) OP=kill; TARGET="${2:-}"; [ -n "$TARGET" ] || { echo "$USAGE" >&2; exit 2; };; --kill-orphans) OP=orphans;; *) echo "$USAGE" >&2; exit 2;; esac
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(. "$HERE/ft-harness-root.sh" && ft_data_root "$HERE" 2>/dev/null)" || { echo "CHILD-WATCH-UNKNOWN 판정 불가 — 데이터 루트를 못 풂(FT_ROOT)"; exit 20; }
exec python3 - "$OP" "$DRY" "$TARGET" "$ROOT" "$HERE" <<'PY'
import glob, json, os, re, subprocess, sys, time
op, dry, target, root, here = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4], sys.argv[5]
E = os.environ
SD = E.get("FT_CHILD_STATE_DIR") or os.path.join(root, ".fable-team/state")
Q = E.get("FT_SEAT_QUIESCE_BIN") or os.path.join(here, "ft-seat-quiesce.sh")
MBOX = E.get("FT_CHILD_MBOX_SH") or os.path.join(root, ".fable-team/comm/mbox.sh")   # FT_MBOX_SH 를 안 읽는다 — 부르는 틱(stall-scan)의 시험 스텁에 섞이지 않게
IDLE, RSS, NIDLE = float(E.get("FT_CHILD_IDLE_MIN") or 20), float(E.get("FT_CHILD_RSS_MB") or 300), float(E.get("FT_NANO_IDLE_MIN") or 30)
FROM, TODAY = "ft-child-watch", time.strftime("%Y-%m-%d")
DONE_RE = re.compile(r"완료·휴식|\[완료\]|정지 레디|^-?\s*세트: [0-9a-f]{40}")
def sh(cmd, t=60):
    try: r = subprocess.run(cmd, capture_output=True, text=True, timeout=t); return r.returncode, r.stdout
    except (OSError, subprocess.SubprocessError) as e: return 99, str(e)
def unknown(why): print(f"CHILD-WATCH-UNKNOWN 판정 불가 — {why} (조치 0)"); sys.exit(20)
def survey():   # ({좌석: S행}, [P행 고아])
    rc, out = sh(["bash", Q, "--survey"])
    if rc != 0: unknown(f"ft-seat-quiesce --survey rc={rc}: {out.strip().splitlines()[-1:] or ''}")
    seats, orph = {}, []
    for ln in out.splitlines():
        f = ln.split("\t")
        if f[0] == "S" and len(f) == 9: seats[f[1]] = dict(idle=int(f[2]) if f[2].isdigit() else None, mb=int(f[3]), heavy=int(f[4]), n=int(f[5]), age=int(f[6]), top=f[7], busy=int(f[8]))
        elif f[0] == "P" and len(f) == 9 and f[1] == "-": orph.append(dict(pid=f[2], name=f[3], mb=int(f[4])))
    return seats, orph
def roster():   # {좌석: (행, 그 명부 _master)} · 하네스 master
    rows, hm = {}, None
    for p in sorted(glob.glob(os.path.join(root, ".fable-team/seats*.json"))):
        try: d = json.load(open(p, encoding="utf-8"))
        except (OSError, ValueError): print(f"ft-child-watch: WARN 명부 못 읽음 {p}", file=sys.stderr); continue
        if not isinstance(d, dict): continue
        m = d.get("_master") if isinstance(d.get("_master"), str) else None
        if os.path.basename(p) == "seats-harness.json": hm = m
        for k, v in d.items():
            if not k.startswith("_") and isinstance(v, dict): rows[k] = (v, m)
    return rows, E.get("FT_CHILD_ALERT_TO") or hm
def card_state(row):   # (끝남?, 마지막 상태 줄 앞 40자)
    ix = row.get("index") if isinstance(row.get("index"), str) else ""
    if not ix: return False, "카드 없음"
    p = ix if os.path.isabs(ix) else os.path.join(root, ix)
    if not os.path.exists(p):
        alt = [p.replace("/진행/", f"/{d}/") for d in ("완성", "아카이브")]
        return (True, "완성 폴더") if any(os.path.exists(a) for a in alt) else (False, "카드 못 찾음")
    sec, last = False, ""
    for ln in open(p, encoding="utf-8", errors="replace"):
        if ln.startswith("## "): sec = ln.strip() == "## 상태"
        elif sec and ln.strip(): last = ln.strip()
    return bool(DONE_RE.search(last)), last[:40] or "상태 줄 없음"
def autonomy():
    v = E.get("FT_CHILD_AUTONOMY")
    if v in ("on", "off"): return v == "on"
    rc, out = sh(["bash", os.path.join(here, "ft-autonomy.sh"), "scope-status"], 7)
    return rc == 0 and bool(re.match(r"\[범위 승인 \S+ · ", out.strip()))
def sent_keys():
    p = os.path.join(SD, "child-watch.sent")
    try: return {l.strip() for l in open(p, encoding="utf-8") if l.startswith(TODAY)}
    except OSError: return set()
def mark(key):
    with open(os.path.join(SD, "child-watch.sent"), "a", encoding="utf-8") as f: f.write(key + "\n")
def send(to, body):
    if not to: print(f"ft-child-watch: WARN 받을 master 없음 — {body}", file=sys.stderr); return False
    rc, out = sh(["bash", MBOX, "send", to, FROM, body], 20)
    if rc != 0: print(f"ft-child-watch: WARN 발신 실패 rc={rc} to={to}: {out.strip()[-120:]}", file=sys.stderr)
    return rc == 0
def quiesce(*a):
    rc, out = sh(["bash", Q, *a, "--reason", "child-watch"])
    return rc, next((l for l in out.splitlines() if l.startswith(("QUIESCED", "QUIESCE-"))), out.strip()[-120:])
def table(seats, orph, rows, acts):
    head = "좌석\t역할\t유휴분\t자식MB\t무거운MB\t자식수\ttop3\t조치"
    lines = [head] + [f"{s}\t{(rows.get(s) or ({},))[0].get('role', '-')}\t{v['idle'] if v['idle'] is not None else '?'}\t{v['mb']}\t{v['heavy']}\t{v['n']}\t{v['top']}\t{acts.get(s, '-')}"
                      for s, v in sorted(seats.items(), key=lambda x: -x[1]["mb"])]
    lines += [f"(고아)\t-\t-\t{o['mb']}\t{o['mb']}\t1\t{o['name']}:{o['pid']}\t{acts.get('-', '-')}" for o in orph]
    return lines
def main():
    os.makedirs(SD, exist_ok=True)
    stamp, every = os.path.join(SD, "child-watch.stamp"), float(E.get("FT_CHILD_WATCH_EVERY_SEC") or 540)
    if op == "tick" and not dry and os.path.exists(stamp) and time.time() - os.path.getmtime(stamp) < every:
        print("child-watch skip=주기"); return 0
    seats, orph = survey(); rows, hmaster = roster()
    if op == "table": print("\n".join(table(seats, orph, rows, {}))); return 0
    if op == "orphans": rc, ln = quiesce("--orphans"); print(ln); return 1 if rc == 1 else rc
    if op == "kill":
        v = seats.get(target)
        if not v: print(f"REJECT {target} — tmux 세션 없음(조회 표 --table 로 확인)"); return 1
        if v["idle"] is None or v["idle"] < IDLE: print(f"REJECT {target} — 쓰는 중(유휴 {v['idle']}분 < {int(IDLE)}분) · 안 죽임"); return 1
        if v["busy"]: print(f"REJECT {target} — 쓰는 중(도구 셸 {v['busy']}개 실행 중 · 출력 없이 계산 중) · 안 죽임"); return 1
        rc, ln = quiesce(target, "--mode", "done"); print(ln); return 1 if rc == 1 else rc
    on, sk, acts, n = autonomy(), sent_keys(), {}, dict(child=0, nano=0, orphans=0, quiesced=0)
    for s, v in sorted(seats.items()):
        if s not in rows or v["idle"] is None: continue
        row, tm = rows[s]
        if v["idle"] >= IDLE and v["mb"] >= RSS and f"{TODAY}\tchild\t{s}" not in sk:
            act = "경보만(자율 OFF)" if not on else f"경보만(작업 중 신호 · 도구 셸 {v['busy']}개)" if v["busy"] else ""   # DA① 추가 — 유휴(출력 없음)만으로 자동 종료하지 않는다
            if on and not v["busy"] and not dry: rc, ln = quiesce(s, "--mode", "done"); act = ln; n["quiesced"] += rc == 0
            acts[s] = act; n["child"] += 1
            if not dry and send(hmaster, f"[자식] {s} 유휴 {v['idle']}분 · 자식 {v['mb']}MB · {v['top']} · 조치: {act}"): mark(f"{TODAY}\tchild\t{s}")
        if "nano" in str(row.get("role", "")) and v["idle"] >= NIDLE and f"{TODAY}\tnano\t{s}" not in sk:
            fin, st = card_state(row)
            if fin:
                n["nano"] += 1; acts[s] = (acts.get(s, "") + " · " if s in acts else "") + "닫기 경보"
                if not dry and send(tm, f"[유휴 나노] {s} 유휴 {v['idle']}분 · 카드 {st} · 닫기는 master(ft-nano-close) — 이 경보는 kill 0"): mark(f"{TODAY}\tnano\t{s}")
    if orph and f"{TODAY}\torphans\t-" not in sk:
        act = "경보만(자율 OFF)"
        if on and not dry: rc, act = quiesce("--orphans"); n["quiesced"] += rc == 0
        acts["-"] = act; n["orphans"] = len(orph)
        if not dry and send(hmaster, f"[고아] {len(orph)}개 · {sum(o['mb'] for o in orph)}MB · {','.join(o['name'] for o in orph)[:80]} · 조치: {act}"): mark(f"{TODAY}\torphans\t-")
    summ = f"child-watch seats={len(seats)} child={n['child']} nano={n['nano']} orphans={n['orphans']} quiesced={n['quiesced']}" + (" dry-run" if dry else "") + f" autonomy={'on' if on else 'off'}"
    if not dry:
        open(os.path.join(SD, "child-watch.tsv"), "w", encoding="utf-8").write("\n".join(table(seats, orph, rows, acts)) + "\n")
        with open(os.path.join(SD, "child-watch.log"), "a", encoding="utf-8") as f: f.write(time.strftime("%Y-%m-%dT%H:%M:%S ") + summ + "\n")
        open(stamp, "w").close()
    for s, a in sorted(acts.items()): print(f"child-watch act {s} {a}")
    print(summ); return 0
sys.exit(main())
PY
