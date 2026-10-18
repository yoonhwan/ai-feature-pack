#!/usr/bin/env python3
"""ft_spawn_queue.py — 나노 상한에 걸린 spawn 카드의 팀별 순번 큐 (r-teamset-standard · 판정 2170 · DA r1 ⑦).

  add    --root R --prefix P --card C [--from F]   `QUEUED <팀> 순번=<n>` (같은 카드는 중복 0 · 카드는 절대경로로 적는다)
  stuck  --root R --prefix P                    확인 필요 항목(카드 없음·명부 행 없음) 출력
  notify --root R --prefix P --mbox M --to MASTER   맨 앞 카드를 현역 master 에 쪽지(같은 카드 10분 1번 · 쪽지 실패 = WARN · 큐 유지)
큐 항목은 «spawn 성공(카드가 진행/ 에 있고 그 팀 명부 행 index 가 그 카드)» 확인 때까지 남는다 — 카드 경로가 사라진 것만으로 지우지 않는다(확인 필요로 남김).
큐 파일 `.fable-team/state/spawn-queue-<팀>.tsv` · 알림 표식 `…<팀>.notified` · 팀 접두는 ft_teamset.team_of.
"""
import argparse
import contextlib
import io
import json
import os
import subprocess
import time
from pathlib import Path

from ft_teamset import team_of


def paths(root, prefix):
    base = Path(root) / ".fable-team" / "state" / f"spawn-queue-{team_of(prefix)}"
    return base.with_suffix(".tsv"), base.with_suffix(".notified")


def roster_indexes(root, prefix):
    """그 팀 명부 행들의 index(카드 경로) 모음 — spawn 성공 근거(명부 등록)."""
    team = team_of(prefix)
    f = Path(root) / ".fable-team" / ("seats.json" if team == "v65" else f"seats-{team}.json")
    try:
        d = json.loads(f.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise SystemExit(f"ERROR 명부 읽기 실패 {f.name}: {e}")
    return [v["index"] for v in d.values() if isinstance(v, dict) and isinstance(v.get("index"), str)]


def split_entries(q, root, prefix):
    """(대기 중, 확인 필요) — 완료 = 카드가 진행/ 에 있고 그 팀 명부 행의 index 가 그 카드(spawn 성공)일 때만 큐에서 지운다.
    카드가 어디에도 없거나(옮겨졌는데 명부 행 없음 포함) 진행/ 인데 명부 행이 없으면 «확인 필요» 로 남긴다(소실 0)."""
    lines = [ln for ln in (q.read_text(encoding="utf-8").splitlines() if q.exists() else []) if ln]
    idx, pending, stuck, keep = roster_indexes(root, prefix), [], [], []
    for ln in lines:
        card = ln.split("\t")[0]
        if Path(card).exists():
            pending.append(ln)
            keep.append(ln)
            continue
        moved = card.replace("/대기/", "/진행/")
        if moved != card and Path(moved).exists() and any(moved.endswith(i) or i == moved for i in idx):
            continue  # spawn 성공 — 완료
        stuck.append(ln)
        keep.append(ln)
    if keep != lines:
        q.write_text("".join(f"{x}\n" for x in keep), encoding="utf-8")
    return pending, stuck


def live_entries(q, root, prefix):
    pending, stuck = split_entries(q, root, prefix)
    return pending + stuck


def add(a):
    q, _ = paths(a.root, a.prefix)
    q.parent.mkdir(parents=True, exist_ok=True)
    lines, card = live_entries(q, a.root, a.prefix), str(Path(a.card).resolve())
    for i, ln in enumerate(lines, 1):
        if ln.split("\t")[0] == card:
            return print(f"QUEUED {team_of(a.prefix)} 순번={i} (이미 대기 중)")
    lines.append(f"{card}\t{a.sender}")
    q.write_text("".join(f"{x}\n" for x in lines), encoding="utf-8")
    print(f"QUEUED {team_of(a.prefix)} 순번={len(lines)}")


def notify(a):
    q, stamp = paths(a.root, a.prefix)
    lines, _ = split_entries(q, a.root, a.prefix)
    if not lines:
        return
    card = lines[0].split("\t")[0]
    last = stamp.read_text(encoding="utf-8").split("\t") if stamp.exists() else ["", "0"]
    if last[0] == card and time.time() - float(last[1] or 0) < 600:
        return
    msg = (f"[큐 알림] {team_of(a.prefix)} 나노 빈 석 있음 — 대기 카드 {card} 를 지금 spawn "
           f"(ft-nano-spawn.sh <카드> --from <내 좌석>) · 대기 {len(lines)}")
    r = subprocess.run(["bash", a.mbox, "send", a.to, "ft-teamset-check", msg], capture_output=True, text=True, timeout=30)
    if r.returncode:
        return print(f"WARN 큐 알림 쪽지 실패 rc={r.returncode}")
    stamp.write_text(f"{card}\t{time.time()}", encoding="utf-8")
    print(f"큐 알림 {card.rsplit('/', 1)[-1]}")


def stuck_cards(root, prefix):
    q, _ = paths(root, prefix)
    return [ln.split("\t")[0] for ln in split_entries(q, root, prefix)[1]]


def stuck(a):
    print("\n".join(stuck_cards(a.root, a.prefix)))


def notify_master(root, prefix, free, master):
    """빈 석 있음 ∧ 큐 비지 않음 → 현역 master 에 멱등 쪽지(같은 카드 10분 1번). 호출 쪽(ft_teamset)이 master 형식·소속·라이브를 먼저 검증한다."""
    if free <= 0 or os.environ.get("FT_TEAMSET_NOTIFY", "1") == "0":
        return ""
    mbox = os.environ.get("FT_TEAMSET_MBOX") or str(Path(root) / ".fable-team/comm/mbox.sh")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        notify(argparse.Namespace(root=root, prefix=prefix, mbox=mbox, to=master))
    return buf.getvalue().strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["add", "notify", "stuck"])
    ap.add_argument("--root", required=True)
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--card")
    ap.add_argument("--from", dest="sender", default="?")
    ap.add_argument("--mbox")
    ap.add_argument("--to")
    a = ap.parse_args()
    if a.cmd == "add" and not a.card:
        ap.error("--card 필수")
    if a.cmd == "notify" and not (a.mbox and a.to):
        ap.error("--mbox --to 필수")
    {"add": add, "notify": notify, "stuck": stuck}[a.cmd](a)


if __name__ == "__main__":
    main()
