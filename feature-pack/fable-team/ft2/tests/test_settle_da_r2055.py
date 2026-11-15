"""r2055 DA#11 보정 — DA 재현 6건(R1~R4 · /private/tmp/da-r2055-5285/test_review.py 꼴 그대로) + 카드 A13 반례 ㉑(가)~(라) · ㉒(가)~(바).
A13 판독 = 기본 실행 배선(keeper 함수 교체 0) — 가짜 tmuxc(clean · rc 파일) · 가짜 tmux(raw pane_pid · capture · session_path) · 가짜 ps(PATH) 로
실제 호출부가 1차 / 2차 / kill 직전 가드 분기를 밟는다. 기대 = BYZ 카드 d43fc79b ㉑㉒ 문구. 실 tmux·실 명부·Slack 0 · sleep 0(시계 = 주입 w.t).
"""
import importlib.util
import json
import os
import sys
from pathlib import Path

_spec = importlib.util.spec_from_file_location("r2055_settle_cases", str(Path(__file__).with_name("test_settle_one_path_r2055.py")))
t = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(t)
kw = t.kw


# ── DA#11 재현 6건(R1~R4) ──────────────────────────────────────────────

def test_recent_done_must_stay_working(tmp_path, monkeypatch):   # R1 jsonl 1분 전 = WORKING · kill 0
    w = t.world(tmp_path, monkeypatch)
    w.card('r9561', stage='완성')
    t.nano(w, 'r9561', done=True, branch='feature/other', age=60)
    lines = t.rnd(w)
    assert not w.tmux('kill-session'), {'kills': w.tmux('kill-session'), 'lines': lines}
    assert t.has(lines, 'WORKING harness r9561'), lines


def test_resume_uuid_must_be_verified(tmp_path, monkeypatch):   # R2 없는 대화 uuid 만 = 검증된 재개 기록 아님
    w = t.world(tmp_path, monkeypatch)
    seat = 'byz-harness-arch-pi#10'
    kw._put(w.tmp / 'resume' / (seat + '.json'), {'name': seat, 'uuid': 'nonexistent-session', 'engine': 'pi', 'cwd': str(w.root)})
    k = w.keeper()
    assert k.keep_gate(seat, 'byz-harness-arch-pi#11', {seat, 'byz-harness-arch-pi#11'}) == 'keep-last-2'


def test_renamed_successor_requires_reverse_binding(tmp_path, monkeypatch):   # R2 이름 바뀐 후계 = 양방향 결속일 때만
    w = t.world(tmp_path, monkeypatch)
    seat, new = 'byz-harness-arch-pi#10', 'byz-harness-arch-claude#0'
    kw._put(w.tmp / 'resume' / (seat + '.json'), {'name': seat, 'uuid': 'u-1', 'engine': 'pi', 'cwd': str(w.root)})
    k = w.keeper()
    assert k.keep_gate(seat, new, {seat, new}), 'close eligible without _replaces evidence'


def test_unknown_nano_under_stop_has_verdict(tmp_path, monkeypatch):   # R3 정지 중 명부 밖 나노 꼴 = UNKNOWN roster-outside
    w = t.world(tmp_path, monkeypatch)
    seat = 'byz-harness-nano-unregistered#0'
    kw._put(w.state / 'ALL_STOP.json', {})
    d = json.loads(w.tm.read_text(encoding='utf-8'))
    d['alive'] = [seat]
    kw._put(w.tm, d)
    code = kw.TMUX.replace('__PY__', sys.executable)
    pos = code.index('if a[0] == "kill-session"')
    kw._put(w.tmp / 'bin/tmux', code[:pos] + t.LS + code[pos:])
    lines = t.rnd(w)
    assert t.has(lines, 'UNKNOWN', seat, 'roster-outside'), lines


def test_cross_team_end_uses_resolved_card(tmp_path, monkeypatch):   # R4 팀 밖 카드 끝 표식 = resolve_card
    w = t.world(tmp_path, monkeypatch)
    work = 'v65-conn-9-x'
    path = 'design/teams/v65/indices/진행/' + work + '.md'
    for ref in ('main', 'ops/main-base'):
        w.commit('byz', {path: '# 인덱스\n## 상태\n- 중단: 사람 결정\n'}, ref)
    t.nano(w, work, body='카드 ' + path)
    k = w.keeper()
    k.fresh(str(w.root))
    cards = k.resolve_card('harness', work)
    ending = k.close.__func__.__globals__['endings']._card_end(k, 'harness', work)
    assert ending and ending[0] == 'suspended', {'resolved': cards, 'ending': ending}


def test_attached_unknown_alerts(tmp_path, monkeypatch):   # R3 attached 조회 실패 UNKNOWN = [긴급] 전송
    w = t.world(tmp_path, monkeypatch)
    k = w.keeper()
    k.unknown = 0
    k.attached = lambda seat: 'unknown · 1 tmux failure'
    assert k.held_attached('harness', 'r9551', 'byz-harness-nano-r9551#0')
    assert t.sent(w), 'UNKNOWN verdict without required alert'


# ── A13 기본 실행 배선(가짜 실행 파일) ─────────────────────────────────

def world(tmp, mp):
    w = t.world(tmp, mp)   # 가짜 ps = keeper_world PATH(psbin)
    ps(w)
    return w


def ps(w, cpu=0.0, rc=None):
    """가짜 ps 표 = 사슬(pane 100 → npm → node → pi) · 끝 pid %cpu · rc = 실패."""
    kw._put(str(w.tm) + ".ps", "".join("%d %d %.1f %s\n" % (p, pp, cpu if c is None else c, n) for p, pp, c, n in t.CHAIN))
    kw._put(str(w.tm) + ".ps_rc", str(rc)) if rc else None


def tm(w, **kv):
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    for key, val in kv.items():
        d[key] = dict(d.get(key, {}), **val) if isinstance(val, dict) else val
    kw._put(w.tm, d)


def seat(w, work, cmd="pi", session=True, **kv):
    """나노 1석 + raw pane_pid(cmd · None = 실패) · session=False = pi 세션 파일 지움."""
    holder = t.nano(w, work, **kv)
    tm(w, pid={holder: "100\t" + cmd if cmd else ""})   # "" = pane_pid 판독 실패
    if not session:
        for f in (Path(w.env["FT2_PI_SESSIONS"]) / ("--%s--" % str(w.tmp / "wt" / work).strip("/").replace("/", "-"))).glob("*.jsonl"):
            f.unlink()
    return holder


def go(w, dt=0):
    w.t += dt
    return w.round()


def urgent(w, code):
    return [x for x in t.sent(w) if "[긴급] UNKNOWN" in x and code in x]


def test_r21_ga_first_pass_no_capture(tmp_path, monkeypatch):   # ㉑(가) clean rc0 · 그 세션 없음 · pane_pid·ps 정상 → capture 0 으로 판정
    w = world(tmp_path, monkeypatch)
    seat(w, "r9601", pane="✻ done\n⠋ Working (2s)\n❯ ")
    kw._put(str(w.tm) + ".clean", "")
    ps(w, cpu=0.5)
    lines = go(w) + go(w, dt=30)
    assert t.has(lines, "WORKING harness r9601", "cpu-busy") and not t.has(lines, "판독 2차"), lines
    assert not w.tmux("capture-pane") and not w.tmux("kill-session"), w.tmux("capture-pane")


def test_r21_na_no_tmuxc_pane_working(tmp_path, monkeypatch):   # ㉑(나) tmuxc 실행 파일 없음 → 2차 · pane Working = WORKING
    w = world(tmp_path, monkeypatch)
    w.env["FT2_TMUXC"] = str(tmp_path / "bin" / "tmuxc-none")
    seat(w, "r9602", pane="✻ done\n⠋ Working (2s)\n❯ ")
    lines = go(w) + go(w, dt=30)
    assert t.has(lines, "WORKING harness r9602", "pane-working", "판독 2차(tmuxc 없음·실패)") and not w.tmux("kill-session"), lines


def test_r21_na_tmuxc_rc1_rest_parks(tmp_path, monkeypatch):   # ㉑(나) tmuxc rc 1 → 2차 · 쉼 ×2 ∧ jsonl 무활동 ≥ PARK_IDLE ∧ 안전 = PARKED · 꼬리 «판독 2차»
    w = world(tmp_path, monkeypatch)
    kw._put(str(w.tm) + ".tmuxc_rc", "1")
    seat(w, "r9603")
    lines = go(w)
    assert t.has(lines, "WORKING harness r9603", "pane-pending", "판독 2차") and not w.tmux("kill-session"), lines
    lines = go(w, dt=30)
    assert t.has(lines, "PARKED harness r9603", "idle-done", "판독 2차(tmuxc 없음·실패)") and len(w.tmux("kill-session")) == 1, lines


def test_r21_da_ghost_input_is_rest(tmp_path, monkeypatch):   # ㉑(다) 입력줄 `❯ Working on it` 만 = 쉼(고스트 근거 0)
    w = world(tmp_path, monkeypatch)
    kw._put(str(w.tm) + ".tmuxc_rc", "1")
    seat(w, "r9604", pane="✻ Brewed for 3s\n❯ Working on it")
    lines = go(w) + go(w, dt=30)
    assert t.has(lines, "PARKED harness r9604", "판독 2차") and not t.has(lines, "pane-working") and len(w.tmux("kill-session")) == 1, lines


def test_r21_ra_shell_only_one_capture(tmp_path, monkeypatch):   # ㉑(라) clean 이 그 세션을 냄 · clean · push · 무활동 ≥ PARK_IDLE → PARKED · capture = 가드 1회
    w = world(tmp_path, monkeypatch)
    seat(w, "r9605", cmd="zsh")
    lines = go(w)
    assert t.has(lines, "PARKED harness r9605", "shell-only") and not t.has(lines, "판독 2차"), lines
    assert len(w.tmux("capture-pane")) == 1 and len(w.tmux("kill-session")) == 1, w.tmux("capture-pane")


def test_r22_ga_ps_fail_not_working(tmp_path, monkeypatch):   # ㉒(가) ps rc≠0 · 끝난 나노 · 무활동 2시간 → 2차 쉼 ×2 → PARKED · WORKING cpu-unknown 0
    w = world(tmp_path, monkeypatch)
    kw._put(str(w.tm) + ".clean", "")
    ps(w, rc=1)
    seat(w, "r9606")
    lines = go(w) + go(w, dt=30) + go(w, dt=3600)
    assert t.has(lines, "PARKED harness r9606", "판독 2차(ps 판독 실패)") and not t.has(lines, "cpu-unknown"), lines


def test_r22_na_pane_pid_fail_not_working(tmp_path, monkeypatch):   # ㉒(나) pane_pid 판독 실패 → 같은 길
    w = world(tmp_path, monkeypatch)
    seat(w, "r9607", cmd=None)
    lines = go(w) + go(w, dt=30) + go(w, dt=3600)
    assert t.has(lines, "PARKED harness r9607", "판독 2차(pane_pid 판독 실패)") and not t.has(lines, "cpu-unknown"), lines


def test_r22_da_pi_no_session_unknown(tmp_path, monkeypatch):   # ㉒(다) pi 프로세스 · 세션 파일 없음 · CPU 0.0 → UNKNOWN session-none [긴급] 1 · kill 0
    w = world(tmp_path, monkeypatch)
    kw._put(str(w.tm) + ".clean", "")
    seat(w, "r9608", session=False)
    lines = go(w) + go(w, dt=30) + go(w, dt=7200)
    assert t.has(lines, "UNKNOWN harness r9608", "session-none") and not t.has(lines, "jsonl-active"), lines
    assert len(urgent(w, "session-none")) == 1 and not w.tmux("kill-session"), t.sent(w)


def test_r22_ra_shell_no_session_unknown(tmp_path, monkeypatch):   # ㉒(라) shell-only · 세션 파일 없음 → UNKNOWN session-none [긴급] · kill 0
    w = world(tmp_path, monkeypatch)
    seat(w, "r9609", cmd="zsh", session=False)
    lines = go(w) + go(w, dt=30) + go(w, dt=7200)
    assert t.has(lines, "UNKNOWN harness r9609", "session-none") and not t.has(lines, "PARKED harness r9609"), lines
    assert len(urgent(w, "session-none")) == 1 and not w.tmux("kill-session"), t.sent(w)


def test_r22_ma_ps_and_capture_fail(tmp_path, monkeypatch):   # ㉒(마) ps 실패 ∧ capture 실패 → UNKNOWN probe-fail [긴급] · kill 0
    w = world(tmp_path, monkeypatch)
    ps(w, rc=1)
    seat(w, "r9610")
    tm(w, cap_rc=1)
    lines = go(w) + go(w, dt=30)
    assert t.has(lines, "UNKNOWN harness r9610", "probe-fail") and not t.has(lines, "WORKING harness r9610"), lines
    assert len(urgent(w, "probe-fail")) == 1 and not w.tmux("kill-session"), t.sent(w)


def test_r22_ba_shared_folder_retired_seat(tmp_path, monkeypatch):   # ㉒(바) 보존 조건 밖 #9 = session-none [긴급] 1 · #10 = keep-last-2 [긴급] 0 · kill 0
    w = world(tmp_path, monkeypatch)
    b = "byz-harness-arch-pi#"
    roster = {"_master": "M-harness", b + "9": {"role": "stop-ready", "_replaced_by": b + "10"},
              b + "10": {"role": "stop-ready", "_replaced_by": b + "11"}, b + "11": {"role": "stop-ready"}}
    kw._put(w.root / ".fable-team" / "seats-harness.json", roster)
    (w.tmp / "comm").mkdir(exist_ok=True)
    with open(w.tmp / "comm" / "mailbox.log.jsonl", "w", encoding="utf-8") as fh:
        for new, old in ((10, 9), (11, 10)):
            fh.write(json.dumps({"from": b + str(new), "to": b + str(old), "body": "[레디] %s%d <- %s%d · 항목 1" % (b, new, b, old)}, ensure_ascii=False) + "\n")
    names = [b + str(n) for n in (9, 10, 11)]
    tm(w, alive=names, path={x: "/seats/shared" for x in names}, pid={x: "100\tpi" for x in names}, pane={x: "✻ done\n❯ " for x in names})
    log = Path(w.env["FT2_PI_SESSIONS"]) / "--seats-shared--" / "s.jsonl"
    kw._put(log, '{"type": "session"}\n'), os.utime(log, (w.t - 60, w.t - 60))   # #11 jsonl 1분 전 증가(같은 폴더)
    i = kw.TMUX.replace("__PY__", sys.executable)
    kw._put(w.tmp / "bin" / "tmux", i[:i.index('if a[0] == "kill-session"')] + t.LS + i[i.index('if a[0] == "kill-session"'):])
    lines = go(w) + go(w, dt=30)
    assert t.has(lines, "UNKNOWN harness - %s9 session-none" % b) and not t.has(lines, "WORKING harness - %s9 " % b), lines
    assert t.has(lines, "WORKING harness - %s10 keep-last-2" % b), lines
    assert len(urgent(w, b + "9")) == 1 and not urgent(w, b + "10 ") and not w.tmux("kill-session"), t.sent(w)
    assert not kw._lines(str(w.close) + ".log"), "닫기 0"


# ── DA#11 두 번째 HOLD 잔여 2건(#308570 · a370 test_remaining.py 단정 그대로) ──

def _known_nano(w, stop):
    seat = 'byz-harness-nano-unassigned#0'
    kw._put(w.state / 'ALL_STOP.json', {}) if stop else None
    kw._put(w.root / '.fable-team/seats-harness.json', {'_master': 'M-harness', seat: {'role': 'nano'}})
    d = json.loads(w.tm.read_text(encoding='utf-8'))
    d['alive'] = [seat]
    kw._put(w.tm, d)
    code = kw.TMUX.replace('__PY__', sys.executable)
    pos = code.index('if a[0] == "kill-session"')
    kw._put(w.tmp / 'bin/tmux', code[:pos] + t.LS + code[pos:])
    lines = t.rnd(w)
    return [ln for ln in lines if seat in ln and ln.startswith(('UNKNOWN ', 'WORKING ', 'LANDED ', 'PARKED ', '예정 '))], lines


def test_r23_known_nano_without_dispatch_under_stop(tmp_path, monkeypatch):   # ㉓ R3 명부 나노 · dispatch 0 · 정지 중 → 판정 줄 있음 · kill 0
    w = t.world(tmp_path, monkeypatch)
    verdicts, lines = _known_nano(w, stop=True)
    assert verdicts, lines
    assert not w.tmux('kill-session')


def test_r23_known_nano_without_dispatch_one_verdict(tmp_path, monkeypatch):   # ㉓ 보탬 정지 아님 바퀴 = 그 좌석 판정 정확히 1줄 · kill 0
    w = t.world(tmp_path, monkeypatch)
    verdicts, lines = _known_nano(w, stop=False)
    assert len(verdicts) == 1, lines
    assert not w.tmux('kill-session')


def test_r24_mapped_card_end_must_share_resolver(tmp_path, monkeypatch):   # ㉔ R4 짝 표 매핑 카드가 팀 폴더 동명 카드보다 먼저
    w = t.world(tmp_path, monkeypatch)
    work = 'r9666'
    w.card(work, stage='진행')
    path = 'design/teams/v65/indices/진행/' + work + '.md'
    for ref in ('main', 'ops/main-base'):
        w.commit('byz', {path: '# 인덱스\n## 상태\n- 중단: 사람 결정\n'}, ref)
    t.nano(w, work, body='카드 ' + path)
    kw._put(w.root / '.fable-team/teams/harness/runtime/cards.tsv', work + '\t' + path + '\n')
    k = w.keeper()
    k.fresh(str(w.root))
    resolved = k.resolve_card('harness', work)
    ending = k.close.__func__.__globals__['endings']._card_end(k, 'harness', work)
    assert resolved[1] == [path], resolved
    assert ending and ending[0] == 'suspended', {'resolved': resolved, 'ending': ending}
