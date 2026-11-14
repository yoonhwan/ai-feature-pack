#!/usr/bin/env bash
# ft-seat-close-due.sh [--close <좌석>] — r1671(오빠 결정 3): 판정·산출을 끝낸 DA·arch 좌석의 «닫기 차례» 를 사실에서 다시 계산한다(목록 = 읽기 전용 · 팀장 후보 0).
#   닫기 차례 = 명부 role=da|arch 현역(_closed·_replaced_by·_master 0 · tmux 생존) ∧ IDLE ≥ FT_SEAT_IDLE_CLOSE_MIN(30)분(턴 끝 · 없으면 창 활동) ∧ 조용함 ∧ pane cwd 미커밋 0 ∧ open-work «받을 일 0» ∧ (da) 발주 seq 마다 그 번호(#·요청·발주 + 숫자 경계)와 APPROVE·HOLD·REJECT 를 함께 쓴 뒤 회신.
#   출력 «닫기 차례 <좌석> 갈래=유휴(da|arch) end=<턴 끝 epoch> idle=<분>» · «제외 <좌석> <사유>» · 조회 rc≠0 = «판정 불가 …» rc 3(하드 룰 20). --close <좌석> = 지금 다시 판정 → 차례면 ft-seat-close.sh 표준 경로 1회(--verdict ${FT_SEAT_AUTO_CLOSE_VERDICT:-1699} = 판정 1699 ② 산출 끝난 IDLE arch·DA 표준 경로 + 결정 3) → `CLOSED <좌석> idle=1` rc 0 · NOT-DUE/CLOSE-FAIL rc 1 · 삭제·kill-server 0.
set -uo pipefail; FT_SCD_HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; export FT_SCD_HERE
exec python3 - "$@" <<'PY'
import importlib.util, os, re, subprocess as sp, sys, time; from datetime import datetime; from pathlib import Path; H, E, A = os.environ["FT_SCD_HERE"], os.environ, sys.argv[1:]
sys.path.insert(0, H); from ft_team_lib import rosters, repo_root; s = importlib.util.spec_from_file_location("ft_open_work", H + "/ft-seat-open-work.py"); ow = importlib.util.module_from_spec(s); s.loader.exec_module(ow)
if A and (len(A) != 2 or A[0] != "--close"): print("usage: ft-seat-close-due.sh [--close <좌석>]", file=sys.stderr); sys.exit(2)
class U(Exception): pass   # 조회 실패 = 판정 불가(닫기 0)
DL = time.monotonic() + float(E.get("FT_SEAT_CLOSE_DUE_BUDGET") or 24) - (7 if A else 0)   # 보정 R1 ⓒ — stall_scan 바깥 25초 안 · --close 는 닫기 7초를 뺀 만큼만 판정
def run(cmd, cap=7, cwd=None):   # 외부 호출 1개 = 7초 · 재시도 0 · 시간 초과 = 묶음 정리 + rc None(판정 불가)
    try: p = sp.Popen(cmd, stdout=sp.PIPE, stderr=sp.DEVNULL, text=True, cwd=cwd, start_new_session=True); o = p.communicate(timeout=cap)[0]; return p.returncode, o
    except OSError: return None, ""
    except sp.TimeoutExpired: os.killpg(p.pid, 15); p.wait(); return None, ""
def need(cmd, what):
    if (r := run(cmd))[0] != 0: raise U(f"{what} rc={'-' if r[0] is None else r[0]}")
    return r[1]
def quiet(k):   # ⓔ — ft-nano-close-due.sh quiet() 와 같은 꼴 · 스텁 = 첫 줄 OK|BUSY <사유>
    if E.get("FT_CLOSE_DUE_QUIET"): o = need(["bash", E["FT_CLOSE_DUE_QUIET"], k], "조용함 조회").strip(); return "" if o.startswith("OK") else (o[4:].strip() or "조용하지 않음")
    pid = need(["tmux", "list-panes", "-t", f"={k}:", "-F", "#{pane_pid}"], "tmux list-panes").split()[:1]; kids, todo = {}, [int(pid[0])] if pid and pid[0].isdigit() else []
    for a in (l.split(None, 2) for l in need(["ps", "-A", "-o", "pid=,ppid=,args="], "ps").splitlines()): len(a) == 3 and a[1].isdigit() and kids.setdefault(int(a[1]), []).append((int(a[0]), a[2]))
    while todo:
        for c, cmd in kids.get(todo.pop(), []):
            if os.path.basename(cmd.split()[0]).lstrip("-") in ("zsh", "bash", "sh", "fish") and " -c " in f" {cmd} ": return "도구 셸 실행"
            todo.append(c)
    tail = [l for l in need(["tmux", "capture-pane", "-p", "-t", f"={k}:"], "tmux capture-pane").splitlines() if l.strip()][-14:]
    return "미제출 입력" if any(re.match(r"^[›❯] +[^ ]", l) for l in tail) else "pane 작업 중" if any(re.search(r"esc to interrupt|Working|Thinking|Crunch", l) for l in tail) else ""
def unanswered(k):   # ⓐ 발주 seq 마다 그 뒤 회신 — 우편함 원장(log+큐) · 깨짐 = 판정 불가
    try: rs = ow.rows(MDIR + "/mailbox.log.jsonl") + ow.rows(MDIR + "/mailbox.jsonl")
    except (OSError, ValueError) as e: raise U(f"우편함 {type(e).__name__} rc=1")
    mine = [(int(m.get("seq") or 0), str(m.get("body"))) for m in rs if m.get("from") == k and re.search(r"\b(APPROVE|HOLD|REJECT)", str(m.get("body")))]   # 보정 R1 ⓐ② 판정 낱말 있는 쪽지만
    return [r.get("seq") for r in rs if r.get("to") == k and r.get("from") != k and not ow.is_not_work(r.get("body"))   # ⓐ① 그 발주 번호를 숫자 경계로 가리킨 판정만 소거(받는 이 무관)
            and not any(q > int(r.get("seq") or 0) and re.search(rf"(?<![0-9])(#|요청|발주) ?{r.get('seq')}(?![0-9])", b) for q, b in mine)]
def judge(k, role):   # → (닫기 차례 줄|None, 제외 사유) · 조회 실패 = U
    st = need(["bash", E.get("FT_CLOSE_DUE_SEAT_STATUS") or H + "/ft-seat-status.sh", "turn", k], "ft-seat-status turn").split() + ["", ""]
    if st[0] != "IDLE": return None, f"상태 {st[0] or '-'} (IDLE 아님)"
    cwd, act = (need(["tmux", "display-message", "-p", "-t", f"={k}:", "#{pane_current_path}\t#{window_activity}"], "tmux display-message").strip().split("\t") + [""])[:2]   # 작업 WT = pane «지금» cwd
    try: end = int(datetime.fromisoformat(st[1].replace("Z", "+00:00")).timestamp() if st[1] != "-" else float(act)); idle = int(time.time() - end) // 60   # 턴 끝 없음(codex pane) = 창 마지막 활동
    except ValueError: raise U("턴 끝·창 활동 시각 rc=1")
    if idle < int(E.get("FT_SEAT_IDLE_CLOSE_MIN") or 30): return None, f"유휴 {idle}분 < 문턱"
    if q := quiet(k): return None, q
    if dirty := [l for l in need(["git", "-C", cwd, "status", "--porcelain"], "git status").splitlines() if l.strip() and not l.rstrip().endswith((".serena/project.yml", ".serena/"))]: return None, f"미커밋 {len(dirty)}줄"
    if (rc := (w := run(["python3", H + "/ft-seat-open-work.py", k, "--root", ROOT, "--mbox-dir", MDIR]))[0]) == 1: return None, "받을 일 " + w[1].strip()[:60]
    if rc != 0: raise U(f"ft-seat-open-work rc={'-' if rc is None else rc}")
    if role == "da" and (miss := unanswered(k)): return None, f"미답 발주 #{miss[0]}"
    return f"닫기 차례 {k} 갈래=유휴({role}) end={end} idle={idle}", ""
try: ROOT = E.get("FT_ROOT") or str(repo_root()); MDIR = E.get("FT_MBOX_DIR") or ROOT + "/.fable-team/comm"; docs = [(r["seats_path"], r["doc"]) for r in rosters(Path(ROOT)) if isinstance(r["doc"], dict)]
except Exception as e: print(f"판정 불가 명부 {str(e)[:100]} rc=1"); sys.exit(3)
cands = [(k, v["role"], p) for p, d in docs for k, v in sorted(d.items()) if isinstance(v, dict) and v.get("role") in ("da", "arch") and not v.get("_closed") and not v.get("_replaced_by") and k != d.get("_master")]
rc_t, live = run(["tmux", "list-sessions", "-F", "#{session_name}"]); unk = 0
for k, role, p in [c for c in cands if c[0] == A[1]] or [(A[1], "", "")] if A else cands[int(time.time() // 60) % max(1, len(cands)):] + cands[:int(time.time() // 60) % max(1, len(cands))]:   # 목록 시작 = 분마다 한 칸씩(예산에 늘 잘리는 좌석 0)
    try:
        if DL - time.monotonic() < 7: raise U("예산 — 다음 판")
        if rc_t != 0: raise U(f"tmux list-sessions rc={rc_t}")
        if k not in live.split("\n") or not role: print(f"{'NOT-DUE' if A else '제외'} {k} 현역 da·arch 좌석 아님(명부·tmux)"); continue
        ln, why = judge(k, role)
    except U as e: print(f"판정 불가 {k} {e}"); unk += 1; continue
    if not A or not ln: print(ln or f"{'NOT-DUE' if A else '제외'} {k} {why}"); continue
    crc, o = run(["bash", E.get("FT_SEAT_CLOSE") or H + "/ft-seat-close.sh", k, "--verdict", E.get("FT_SEAT_AUTO_CLOSE_VERDICT") or "1699", "--reason", f"r1671 유휴 자동 닫기 {ln[6:]}", "--seats", str(p)], 7, ROOT)   # 보정 R1 ⓒ — 닫기 1회 7초 · 재시도 0
    if crc is None: print(f"판정 불가 {k} ft-seat-close rc=-"); sys.exit(3)   # 시간 초과 = CLOSED 0 · 다음 판이 사실에서 다시 판정
    print(f"CLOSED {k} idle=1" if (ok := crc == 0 and any(x.startswith("CLOSED") for x in o.splitlines())) else f"CLOSE-FAIL {k} rc={crc} — {(o.strip().splitlines() or [''])[0][:120]}"); sys.exit(0 if ok else 1)
sys.exit(3 if unk else 1 if A else 0)
PY
