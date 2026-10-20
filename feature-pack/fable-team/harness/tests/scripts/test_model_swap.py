"""r497 — 역할 좌석 모델 한도 → 대체 모델 후계 자동 교대 (`ft_model_swap.py`) + R146 모델별 복구 시험 ⓐ~ⓘ.

임시 루트 + 임시 projects 폴더 + 가짜 tmux·successor-open·mbox + 고정 시계(--now)만 — 실제 tmux·mbox·~/.claude 조회 0 · 외부 호출 0.
"""

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

HARNESS = Path(__file__).resolve().parents[3] / "harness"
BIN = HARNESS / "bin"
KIT = HARNESS / "kit" / "fable-team" / "bin"
SWAP, OUTAGE = BIN / "ft_model_swap.py", BIN / "ft_api_outage.py"
N = 1_760_400_000
ARCH, MASTER, PLANNER = "byz-x-arch-claude#7", "byz-x-master-claude#3", "byz-planner-master-claude#1"
GOAL = ["골 1줄째 원문", "골 2줄째 원문", "골 3줄째 원문"]
WT = "/tmp/fake-wt-x"


def _iso(epoch: int) -> str:
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def _limit(model: str = "claude-fable-5-1", extra: str = "") -> str:  # arch 104 꼬리 문구 꼴 그대로
    return ("API Error: Server is temporarily limiting requests (not your usage limit) · All credentials for model "
            f"{model} are cooling down via provider claude (last error: rate_limit_error: limited){extra}")


def _err(uid: str, at: int, text: str) -> list[dict[str, object]]:
    return [{"type": "user", "uuid": uid + "-u", "timestamp": _iso(at - 5), "cwd": WT, "message": {"role": "user", "content": "go"}},
            {"type": "assistant", "uuid": uid, "timestamp": _iso(at), "cwd": WT, "isApiErrorMessage": True, "error": "rate_limit",
             "message": {"model": "<synthetic>", "content": [{"type": "text", "text": text}]}},
            {"type": "system", "subtype": "turn_duration", "timestamp": _iso(at), "durationMs": 0}]


def _ok(uid: str, at: int, model: str) -> list[dict[str, object]]:
    return [{"type": "assistant", "uuid": uid, "timestamp": _iso(at), "cwd": WT, "message": {"model": model, "content": [{"type": "text", "text": "ok"}]}}]


class Fx:
    def __init__(self, tmp: Path, reach: bool = True):
        self.tmp, self.root = tmp, tmp / "r"
        self.ft = self.root / ".fable-team"
        (self.ft / "comm" / "bodies").mkdir(parents=True)
        (self.ft / "state" / "successor").mkdir(parents=True)
        self.seats: dict[str, object] = {"_master": MASTER, "_hil_route": PLANNER, "_arch": ARCH, "_da": "byz-x-da-codex#2",
                                         MASTER: {"role": "master", "agent": "claude", "model": "claude-sonnet-5-5"},
                                         ARCH: {"role": "arch", "agent": "claude", "model": "claude-fable-5-1[1m]"},
                                         "byz-x-nano-a#0": {"role": "nano", "agent": "claude", "model": "claude-opus-5-5[1m]"},
                                         "byz-x-nano-b#0": {"role": "nano", "agent": "claude", "model": "claude-sonnet-5-5[1m]"},
                                         "byz-x-da-codex#2": {"role": "da", "agent": "codex", "model": "gpt-6.1-sol"},
                                         "byz-x-nano-oc#0": {"role": "nano", "agent": "opencode", "model": "deepseek"}}
        self.sessions = [MASTER, ARCH, "byz-x-nano-a#0", "byz-x-nano-b#0", "byz-x-da-codex#2", "byz-x-nano-oc#0"]
        if reach:
            _ = (self.ft / "state" / "successor" / "byz-x-arch-claude#6.json").write_text(json.dumps(
                {"successor": ARCH, "seq": 9001, "reached_at": "2026-10-20T00:27:28+0900", "rc": 0, "model": "claude-fable-5-1[1m]"}), encoding="utf-8")
            _ = (self.ft / "comm" / "bodies" / "9001.txt").write_text("\n".join([*GOAL, "인계서: design/x/BRIEF.md"]) + "\n", encoding="utf-8")
        self.jdir = tmp / "projects" / re.sub(r"[^A-Za-z0-9]", "-", WT)  # ~/.claude/projects/<pane cwd 인코딩> 꼴
        self.argv, self.log = tmp / "so.argv", tmp / "mbox.log"
        self.jdir.mkdir(parents=True)
        self._fake("tmux", f'case "$1" in list-sessions) cat "{tmp}/sessions";; list-panes) cat "{tmp}/panes";; esac')
        self._fake("so", f'printf "%s\\n" "$@" > "{self.argv}.tmp" && mv "{self.argv}.tmp" "{self.argv}"')
        self._fake("mbox", f'echo "$2|$3|$4" >> "{self.log}"')

    def _fake(self, name: str, body: str) -> None:
        p = self.tmp / name
        _ = p.write_text(f"#!/bin/bash\n{body}\n", encoding="utf-8")
        p.chmod(0o755)

    def add(self, seat: str, recs: list[dict[str, object]], name: str = "") -> Path:
        p = self.jdir / f"{name or seat}.jsonl"
        head = [] if p.exists() else [{"type": "agent-name", "agentName": seat}]  # 좌석명 레코드 = 파일 머리(Claude Code 꼴 · 공백 없는 JSON)
        with p.open("a", encoding="utf-8") as fh:
            fh.writelines(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for r in [*head, *recs])
        return p

    def run(self, now: int = N, *extra: str) -> subprocess.CompletedProcess[str]:
        _ = (self.ft / "seats-x.json").write_text(json.dumps(self.seats), encoding="utf-8")
        _ = (self.tmp / "sessions").write_text("\n".join(self.sessions) + "\n", encoding="utf-8")
        _ = (self.tmp / "panes").write_text("".join(f"{s}\t{WT}\n" for s in self.sessions), encoding="utf-8")
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        env.update(TZ="UTC", FT_TMUX=str(self.tmp / "tmux"), FT_CLAUDE_PROJECTS=str(self.tmp / "projects"), FT_SUCCESSOR_OPEN=str(self.tmp / "so"))
        cmd = [sys.executable, "-I", str(SWAP), "--root", str(self.root), "--mbox", str(self.tmp / "mbox"), "--now", str(now), *extra]
        return subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=30)

    def args(self) -> list[str]:
        for _ in range(100):  # 분리 실행 — 가짜 successor-open 이 argv 를 쓸 때까지
            if self.argv.exists():
                return self.argv.read_text(encoding="utf-8").splitlines()
            time.sleep(0.05)
        return []

    def mail(self) -> list[list[str]]:
        return [ln.split("|", 2) for ln in self.log.read_text(encoding="utf-8").splitlines()] if self.log.exists() else []


def test_a_fable_limit_four_minutes_swaps_to_opus_with_goal_lines(tmp_path):  # ⓐ
    fx = Fx(tmp_path)
    fx.add(ARCH, _err("e1", N - 240, _limit()))
    r = fx.run()
    assert r.returncode == 0, r.stderr
    assert f"PLAN swap {ARCH} -> byz-x-arch-claude#8 model claude-fable-5-1 -> claude-opus-5-5[1m]" in r.stdout
    argv = fx.args()
    assert argv[:2] == [ARCH, WT] and argv[2:13] == ["--name", "byz-x-arch-claude#8", "--agent", "claude", "--model", "claude-opus-5-5[1m]",
                                                       "--ctx", "1m", "--effort", "high", "--body-file"], argv
    body = Path(argv[13]).read_text(encoding="utf-8").splitlines()
    assert body[:3] == GOAL and body[3].startswith("[승계 자동 · 모델 한도]") and "인계서: design/x/BRIEF.md" in body[4]
    mail = fx.mail()
    assert sorted(m[0] for m in mail) == sorted([MASTER, PLANNER]) and all(m[2].startswith(f"[자동 교대] {ARCH} -> byz-x-arch-claude#8") for m in mail)
    assert not any("cooling down" in m[2] for m in mail)  # 쪽지 본문에 오류 원문 0


def test_b_one_minute_old_limit_waits(tmp_path):  # ⓑ
    fx = Fx(tmp_path)
    fx.add(ARCH, _err("e1", N - 60, _limit()))
    r = fx.run()
    assert r.returncode == 0 and f"WAIT {ARCH} 정지 1분" in r.stdout and not fx.argv.exists() and fx.mail() == []


def test_b2_jsonl_lookup_newest_recent_file_only(tmp_path):  # 좌석 jsonl 찾기 = pane cwd 폴더 · 최근 2일 · 머리의 좌석명 · 최신 1개
    fx = Fx(tmp_path)
    old = fx.add(ARCH, _err("e-old", N - 240, _limit()), name="old")
    os.utime(old, (time.time() - 3 * 86400, time.time() - 3 * 86400))  # 3일 전 파일 = 후보 아님
    assert "PLAN" not in fx.run().stdout and "WAIT" not in fx.run().stdout
    fx.add(ARCH, _err("e-mid", N - 240, _limit()), name="mid")
    os.utime(fx.jdir / "mid.jsonl", (time.time() - 100, time.time() - 100))
    fx.add(ARCH, _ok("n1", N - 30, "claude-sonnet-5-5"), name="new")  # 최신 파일 = 정상 턴 → 이 좌석은 안 멈춤
    r = fx.run()
    assert r.returncode == 0 and "PLAN" not in r.stdout and "WAIT" not in r.stdout and not fx.argv.exists()


def test_c_retry_after_phrase_waits_with_eta(tmp_path):  # ⓒ
    fx = Fx(tmp_path)
    fx.add(ARCH, _err("e1", N - 210, _limit(extra=" retry after 60s")))
    r = fx.run()
    eta = time.strftime("%H:%M", time.gmtime(N - 150))
    assert r.returncode == 0 and f"WAIT {ARCH} 해제 예상 {eta}" in r.stdout and not fx.argv.exists()


def test_d_same_model_normal_elsewhere_is_recovered(tmp_path):  # ⓓ
    fx = Fx(tmp_path)
    fx.add(ARCH, _err("e1", N - 240, _limit()))
    fx.add(MASTER, _ok("m1", N - 100, "claude-fable-5-1"))
    r = fx.run()
    assert r.returncode == 0 and f"RECOVERED {ARCH}" in r.stdout and not fx.argv.exists()


def test_e_nano_codex_opencode_rows_are_skipped(tmp_path):  # ⓔ
    fx = Fx(tmp_path)
    for seat in ("byz-x-nano-a#0", "byz-x-da-codex#2", "byz-x-nano-oc#0"):
        fx.add(seat, _err(seat, N - 600, _limit()))
    r = fx.run()
    for seat in ("byz-x-nano-a#0", "byz-x-da-codex#2", "byz-x-nano-oc#0"):
        assert f"SKIP {seat} 역할 좌석 아님" in r.stdout
    assert "PLAN" not in r.stdout and not fx.argv.exists()


def test_f_same_uuid_rerun_is_noop_and_name_skips_live_session(tmp_path):  # ⓕ
    fx = Fx(tmp_path)
    fx.sessions.append("byz-x-arch-claude#8")  # 후계 이름이 tmux 에 이미 있으면 그 다음 번호
    fx.add(ARCH, _err("e1", N - 240, _limit()))
    assert "-> byz-x-arch-claude#9 model" in fx.run().stdout and fx.args()
    fx.argv.unlink()
    r = fx.run(N + 60)
    assert f"NOOP {ARCH} 이미 교대" in r.stdout and "PLAN" not in r.stdout
    time.sleep(0.3)
    assert not fx.argv.exists() and len(fx.mail()) == 2


def test_g_limited_fallback_moves_to_next_then_hil_once(tmp_path):  # ⓖ
    fx = Fx(tmp_path)
    fx.add(ARCH, _err("e1", N - 240, _limit()))
    fx.add("byz-x-nano-a#0", _err("o1", N - 300, _limit("claude-opus-5-5")))
    assert "model claude-fable-5-1 -> claude-sonnet-5-5[1m]" in fx.run(N, "--dry-run").stdout
    fx.add("byz-x-nano-b#0", _err("s1", N - 300, _limit("claude-sonnet-5-5")))
    for now in (N, N + 60):
        r = fx.run(now)
        assert r.returncode == 0 and f"HIL {ARCH} 대체 모델 없음" in r.stdout
    assert not fx.argv.exists()
    hil = [m for m in fx.mail() if m[2].startswith("[HIL]")]
    assert len(hil) == 1 and hil[0][0] == PLANNER


def test_i_no_goal_source_is_hil_and_no_swap(tmp_path):  # ⓘ
    fx = Fx(tmp_path, reach=False)
    fx.add(ARCH, _err("e1", N - 240, _limit()))
    r = fx.run()
    assert r.returncode == 0 and f"HIL {ARCH} 골 원문 출처 없음" in r.stdout and "PLAN" not in r.stdout
    assert not fx.argv.exists() and [m[0] for m in fx.mail()] == [PLANNER]


def _outage(fx: Fx, now: int, swap_state: Path | None = None) -> subprocess.CompletedProcess[str]:
    stdin = "".join(f"{p.stem}\t{p}\n" for p in sorted(fx.jdir.glob("*.jsonl")))
    env = {**{k: v for k, v in os.environ.items() if not k.startswith("GIT_")}, "TZ": "UTC"}
    cmd = [sys.executable, "-I", str(OUTAGE), "--state", str(fx.tmp / "ao" / "s.json"), "--mbox", str(fx.tmp / "mbox"), "--notify", PLANNER,
           "--now", str(now), *(["--swap-state", str(swap_state)] if swap_state else [])]
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, env=env, timeout=30)


def _outage_fx(tmp: Path) -> Fx:
    fx = Fx(tmp)
    fx.add(ARCH, _ok("a0", N - 900, "claude-fable-5-1"))
    fx.add(MASTER, _ok("m0", N - 900, "claude-opus-5-5"))
    assert _outage(fx, N - 800).returncode == 0  # 기준선
    fx.add(ARCH, _err("fe", N - 120, _limit()))
    assert _outage(fx, N - 60).returncode == 0 and len(fx.mail()) == 1  # [API 장애 시작]
    return fx


def test_h_outage_recovery_is_per_model(tmp_path):  # ⓗ — 다른 모델 정상은 복구 아님 · 같은 모델 정상 1 → 끝 + [재개]
    fx = _outage_fx(tmp_path)
    fx.add(MASTER, _ok("m1", N - 30, "claude-opus-5-5"))
    assert _outage(fx, N).returncode == 0
    assert [m for m in fx.mail() if "끝" in m[2] or m[0] == ARCH] == []
    fx.add(MASTER, _ok("m2", N + 30, "claude-fable-5-1"))
    assert _outage(fx, N + 60).returncode == 0
    assert len([m for m in fx.mail() if m[2].startswith("[API 장애 끝")]) == 1
    assert [m[2][:4] for m in fx.mail() if m[0] == ARCH] == ["[재개]"]


def test_h_swapped_seat_gets_no_resume(tmp_path):  # ⓗ — 교대된 좌석(swap 상태 uuid) [재개] 0
    fx = _outage_fx(tmp_path)
    st = tmp_path / "swap.json"
    _ = st.write_text(json.dumps({"swapped": ["fe"], "last": {}, "hil": []}), encoding="utf-8")
    fx.add(MASTER, _ok("m2", N + 30, "claude-fable-5-1"))
    r = _outage(fx, N + 60, st)
    assert r.returncode == 0 and f"SKIP 재개 {ARCH} — 교대됨" in r.stdout
    assert [m for m in fx.mail() if m[0] == ARCH] == []


def test_tick_dry_run_lists_model_swap_kind(tmp_path):  # ft-tick 호출부 · 팀 명부 틱은 건너뜀
    out = {}
    for name in ("seats.json", "seats-cfo.json"):
        seats = tmp_path / name
        _ = seats.write_text(json.dumps({"_master": "t-m#1", "t-m#1": {"role": "master", "tick": None}}), encoding="utf-8")
        env = {**{k: v for k, v in os.environ.items() if not k.startswith("GIT_")}, "FT_TICK_SEATS": str(seats), "FT_TICK_WT_SWEEP": "0",
               "FT_TICK_HIL": "0", "FT_TICK_DRIFT": "0", "FT_TICK_NEWS_LEDGER": "0", "FT_TICK_IDLE_ENABLED": "0",
               "FT_TICK_STATE_DIR": str(tmp_path / "st"), "FT_TICK_MBOX": str(tmp_path / "mbox.sh")}
        out[name] = subprocess.run(["bash", str(BIN / "ft-tick.sh"), "--once", "--dry-run"], capture_output=True, text=True, env=env, timeout=60).stdout
    assert "DRY kind=model-swap" in out["seats.json"] and "DRY kind=model-swap" not in out["seats-cfo.json"]


def test_kit_copies_identical_and_size():
    for name in ("ft_model_swap.py", "model-fallback.tsv", "ft_api_outage.py", "ft_api_outage_util.py", "ft-tick.sh"):
        assert (KIT / name).read_bytes() == (BIN / name).read_bytes(), name
    assert len(SWAP.read_text(encoding="utf-8").splitlines()) <= 180
