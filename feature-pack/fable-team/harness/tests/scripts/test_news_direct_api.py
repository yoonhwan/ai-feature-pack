"""r563 — 뉴스 «지도 만들기» 모델 호출 = HTTP 직접(CLI 기동 0) ⓐ~ⓚ + 원장/골 = origin/main ref · 자율 = 데이터 루트 · 골 0줄 = 발행 0.
가짜 HTTP 서버 1(로컬 · 지연·오류 주입) · 실 모델·실 슬랙 0 · 키는 가짜 값.
실행: python3 -m pytest tests/scripts/test_news_direct_api.py -q
"""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_ft_news_html import BIN, CONTENT, DATA, NOW, oc  # noqa: E402,F401 — 가짜 opencode 픽스처 재사용

import ft_news_html as fh  # noqa: E402
import ft_news_html_render as fr  # noqa: E402
import ft_news_ledger as nl  # noqa: E402


class FakeLLM:
    """OpenAI 호환 chat completions 대역 — 스트림 SSE · 첫 바이트 지연(부하 모사) · 5xx 주입. 요청 기록 = self.reqs."""

    def __init__(self, reply: dict, delay: float = 0.0, slow_match: str = "", slow: float = 0.0, code: int = 200) -> None:
        self.reqs: list[dict] = []
        self.reply, self.delay, self.slow_match, self.slow, self.code = reply, delay, slow_match, slow, code
        outer = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a: object) -> None:
                pass

            def do_POST(self) -> None:
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                outer.reqs.append({"path": self.path, "auth": self.headers.get("Authorization", ""), "body": body})
                prompt = body["messages"][-1]["content"]
                time.sleep(outer.slow if outer.slow_match and outer.slow_match in prompt else outer.delay)
                if outer.code != 200:
                    self.send_response(outer.code)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                text = json.dumps(outer.reply, ensure_ascii=False)
                for i in range(0, len(text), 400):
                    ev = {"choices": [{"delta": {"content": text[i:i + 400]}}]}
                    self.wfile.write(f"data: {json.dumps(ev, ensure_ascii=False)}\n\n".encode())
                    self.wfile.flush()
                self.wfile.write(b"data: [DONE]\n\n")

        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.srv.server_port}/api/v1"

    def prompts(self) -> list[str]:
        return [r["body"]["messages"][-1]["content"] for r in self.reqs]


@pytest.fixture
def llm(tmp_path, monkeypatch):
    """가짜 모델 서버 + 가짜 키 파일(zshrc 꼴) — 실 ~/.zshrc 를 읽지 않는다."""
    srv = FakeLLM(CONTENT)
    keyfile = tmp_path / "zshrc"
    keyfile.write_text("# 옛 키\nexport OPENROUTER_API_KEY='옛값'\nexport OPENROUTER_API_KEY=sk-or-fake-r563\n", encoding="utf-8")
    for k, v in {"FT_NEWS_HTTP_BASE": srv.base, "FT_NEWS_KEY_FILE": str(keyfile), "FT_NEWS_STARTUP_LOG": str(tmp_path / "startup.tsv")}.items():
        monkeypatch.setenv(k, v)
    for k in ("OPENROUTER_API_KEY", "FT_NEWS_VIA", "FT_NEWS_MODEL", "FT_NEWS_EFFORT", "FT_NEWS_DEPT"):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("FT_NEWS_MODEL", "openrouter/anthropic/claude-haiku-5.5")
    yield srv
    srv.srv.shutdown()


def _part(prompt: str) -> str:
    schema = prompt.split("출력 스키마:")[1].splitlines()[0]
    return next(p for p in fr.PARTS if f'"{fr.PARTS[p][0][0]}":' in schema)


# ── ⓐ 지금 판 = opencode CLI(서버 안 씀 · FAIL) → 고친 판 = 갈래 4개 HTTP 병렬 · 첫 출력 기록 ──

def test_a_live_path_never_touches_http_server_and_fixed_edition_does(tmp_path, llm, monkeypatch):
    monkeypatch.setenv("FT_OPENCODE", str(tmp_path / "없는-opencode"))  # 옛 경로로 내려가면 즉시 실패
    html_p, sum_p = fh.run_files(DATA, tmp_path / "out", NOW)
    assert html_p.is_file()
    assert sorted(_part(p) for p in llm.prompts()) == sorted(fr.PARTS)  # 갈래 4개가 서버에 왔다
    body = llm.reqs[0]["body"]
    assert body["model"] == "anthropic/claude-haiku-5.5" and body["stream"] is True  # 접두 뒤 = 모델 · 스트림 켬
    assert body["max_tokens"] == 2048  # 무제한(모델 65536) 요구 = 크레딧 초과 402 실측 → 출력 여유 2048
    assert llm.reqs[0]["auth"] == "Bearer sk-or-fake-r563" and llm.reqs[0]["path"].endswith("/chat/completions")
    rows = Path(fh.os.environ["FT_NEWS_STARTUP_LOG"]).read_text(encoding="utf-8").splitlines()
    assert len(rows) == 4 and all(float(r.rsplit("\t", 1)[-1]) < 7 for r in rows)  # 갈래마다 첫 출력까지 초


# ── ⓑ 첫 바이트 7초 초과 = 그 갈래 1회 재시도 · 둘 다 실패 = 지도 실패(발행 0) ──

def test_b_first_byte_over_cap_retries_once_then_map_fails(tmp_path, llm, monkeypatch):
    monkeypatch.setenv("FT_OPENCODE", str(tmp_path / "없는-opencode"))
    monkeypatch.setattr(fr, "UNIT_S", 0.5)  # teams 상한 = 2초(다른 갈래는 그보다 짧다)
    llm.slow_match, llm.slow = '"team_notes":', 3.0
    with pytest.raises(fr.NewsHtmlError, match="teams 상한"):
        fh.run_files(DATA, tmp_path / "o", NOW)
    assert not (tmp_path / "o").exists()  # 나머지 갈래가 끝나도 지도·발행 0
    assert sum(_part(p) == "teams" for p in llm.prompts()) == 2  # 첫 출력 전 실패만 1회 재시도


# ── ⓒ 시도당 상한 = 7초 룰(고정비 0) · 총 마감 70 그대로 · 600·300 0 ──

def test_c_http_cap_has_no_cli_fixed_cost(tmp_path, llm, monkeypatch):
    small = fr.build_prompt({"teams": ["팀"]}, "teams")
    assert fr.cap_s(small, "teams", fixed=0) == 7 * 4 and fr.cap_s(small, "teams") == 3.5 + 7 * 4
    seen = []
    real = fr.cap_s
    monkeypatch.setattr(fr, "cap_s", lambda prompt, part, fixed=3.5: (seen.append(fixed), real(prompt, part, fixed))[1])
    fh.run_files(DATA, tmp_path / "o", NOW)
    assert seen and set(seen) == {0.0}  # HTTP 경로는 CLI 기동 고정비 0
    assert fr.DEADLINE_S == 70


# ── ⓓ 키 없음·접두 다름 = ERROR(조용한 CLI 대체 0) · 키 값은 로그에 0 ──

def test_d_missing_key_and_unknown_provider_fail_loud(tmp_path, llm, monkeypatch, capsys):
    (tmp_path / "zshrc").write_text("export OTHER=1\n", encoding="utf-8")
    with pytest.raises(fr.NewsHtmlError, match="OPENROUTER_API_KEY 없음"):
        fh.run_files(DATA, tmp_path / "o", NOW)
    assert not (tmp_path / "o").exists() and "sk-or-fake-r563" not in capsys.readouterr().err
    monkeypatch.setenv("OPENROUTER_API_KEY", "sk-or-env-value")
    monkeypatch.setenv("FT_NEWS_MODEL", "cerebras/llama-x")
    with pytest.raises(fr.NewsHtmlError, match="cerebras"):
        fh.run_files(DATA, tmp_path / "o", NOW)
    assert "sk-or-env-value" not in capsys.readouterr().err


# ── ⓔ FT_NEWS_VIA=opencode = 지금 판 CLI 경로(되돌림 손잡이) ──

def test_e_via_opencode_is_the_old_cli_path(tmp_path, oc, monkeypatch, llm):  # noqa: F811
    reply, log = oc
    monkeypatch.setenv("FT_NEWS_VIA", "opencode")
    fh.run_files(DATA, tmp_path / "o", NOW)
    assert len(log.read_text(encoding="utf-8").splitlines()) == 4 and llm.reqs == []


# ── ⓕ 원장 사본 동기화 = 2분 안에 성공했으면 건너뜀 + INFO ──

def test_f_sync_skipped_within_120s(tmp_path, monkeypatch, caplog):
    script = tmp_path / "sync.sh"
    script.write_text(f'#!/usr/bin/env bash\necho "$1" >> "{tmp_path}/calls"\necho "SYNC up-to-date"\n', encoding="utf-8")
    (tmp_path / "root" / ".fable-team").mkdir(parents=True)
    monkeypatch.setenv("FT_ROOT", str(tmp_path / "root"))
    monkeypatch.setenv("FT_LEDGER_REPO", str(tmp_path / "repo"))
    monkeypatch.setenv("FT_LEDGER_SYNC", str(script))
    monkeypatch.setenv("FT_LEDGER_SYNC_STAMP", str(tmp_path / "stamp"))
    monkeypatch.setenv("FT_LEDGER_SYNC_MIN", "120")
    caplog.set_level("INFO", logger="ft_news_ledger")
    assert nl.sync_repo() == ""  # 틱 1 = 실행
    monkeypatch.setenv("FT_LEDGER_SYNCED", "0")  # 다음 틱(새 프로세스)
    assert nl.sync_repo() == ""  # 2분 안 → 건너뜀
    assert (tmp_path / "calls").read_text(encoding="utf-8").splitlines() == [str(tmp_path / "repo")]
    assert any("건너뜀" in r.message for r in caplog.records)
    (tmp_path / "stamp").write_text(f"{time.time() - 121:.0f}\n", encoding="utf-8")  # 121초 지남 → 다시 실행
    monkeypatch.setenv("FT_LEDGER_SYNCED", "0")
    assert nl.sync_repo() == ""
    assert len((tmp_path / "calls").read_text(encoding="utf-8").splitlines()) == 2


# ── ⓖ 지도 실패 틱마다 «직전 판 유지» INFO 1줄 ──

def test_g_failed_tick_logs_keep_previous_issue(tmp_path, oc, monkeypatch, caplog):  # noqa: F811
    oc[0].write_text("JSON 아님", encoding="utf-8")
    monkeypatch.setattr(fh, "build", lambda *a: DATA)
    state = tmp_path / "state"
    state.mkdir()
    (state / "html.json").write_text(json.dumps({"map_at": "2026-10-19 08:55", "link": "https://x/prior"}), encoding="utf-8")
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-19 09:15")
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_NEWS_DIR", str(tmp_path / "news"))
    caplog.set_level("INFO", logger="ft_news_html")
    assert fh.tick(tmp_path, state, tmp_path, "x.md", tmp_path / "news", "a", "b")[0] == 1
    keep = [r.message for r in caplog.records if "직전 판 유지" in r.message]
    assert keep == ["직전 판 유지 2026-10-19 08:55(https://x/prior)"]


# ── ⓘ 원장 = 사본 HEAD 아니라 origin/main ref ──

def _git(repo: Path, *a: str) -> str:
    import subprocess
    return subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *a], check=True, capture_output=True, text=True).stdout.strip()


def _stale_copy(tmp_path: Path) -> tuple[Path, Path, str, str, str]:
    """사본 체크아웃(HEAD) = 옛 판 · origin/main ref = 새 판 인 임시 리포 + 루트(FT_ROOT)."""
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(repo, "init", "-q")
    (repo / "design").mkdir()
    (repo / "design" / "TEAMS.md").write_text("| 팀 | 폴더 | 팀장 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | planner#9 | 현역 |\n", encoding="utf-8")
    rel = "design/planner/PLAN-oppa-ledger.md"
    (repo / rel).parent.mkdir(parents=True)
    (repo / rel).write_text("**지금 전체 상태**: 옛 판\n", encoding="utf-8")
    _git(repo, "add", ".")
    _git(repo, "commit", "-qm", "옛 원장")
    old = _git(repo, "rev-parse", "HEAD")
    _git(repo, "checkout", "-q", "--detach", old)  # 사본 체크아웃 = 옛 판(낡음)
    (repo / rel).write_text("**지금 전체 상태**: 새 판\n", encoding="utf-8")
    _git(repo, "add", ".")
    _git(repo, "commit", "-qm", "새 원장")
    new = _git(repo, "rev-parse", "HEAD")
    _git(repo, "update-ref", "refs/remotes/origin/main", new)
    _git(repo, "checkout", "-q", "--detach", old)  # HEAD 는 다시 옛 판
    root = tmp_path / "root"
    (root / ".fable-team").mkdir(parents=True)
    (root / ".fable-team" / "LIVE_BIN").write_text("", encoding="utf-8")
    return repo, root, rel, old, new


def test_i_ledger_read_from_origin_main_not_checkout_head(tmp_path, monkeypatch):
    repo, root, rel, old, new = _stale_copy(tmp_path)
    for k, v in {"FT_ROOT": root, "FT_LEDGER_REPO": repo, "FT_LEDGER_PATH": rel, "FT_NEWS_FETCH_MIN": "0"}.items():
        monkeypatch.setenv(k, str(v))
    monkeypatch.setattr(fh, "live_teams", lambda r: [{"team": "t", "live": 0, "working": 0, "unknown": 0}])
    monkeypatch.setattr(fh, "goals", lambda: [{"n": i, "goal": f"골 {i}", "team": f"t{i}", "state": "지금"} for i in range(1, 7)])
    monkeypatch.setattr(fh, "autonomy", lambda r: "ON")
    monkeypatch.setattr(fh, "teams", lambda r: [])
    monkeypatch.setattr(fh, "urgent", lambda r, n: [])
    monkeypatch.setattr(fh, "commits", lambda r, b: [])
    _root, _repo, got_rel, base, cur = fh._ledger_args()
    assert _git(repo, "log", "-1", "--format=%H", "--", rel) == old  # 지금 판이 보던 자리 = 옛 판(재현)
    assert cur == new and base == ""  # 고친 판 = origin/main ref
    assert "새 판" in json.dumps(fh.build(root, repo, got_rel, base, cur, NOW), ensure_ascii=False)


# ── ⓙ 자율 = FT_ROOT(공용) 아니라 데이터 루트(LIVE_ROOT) ──

def test_j_autonomy_reads_data_root_not_common_root(tmp_path, monkeypatch):
    common, data = tmp_path / "common", tmp_path / "data"
    (common / ".fable-team").mkdir(parents=True)
    data.mkdir()
    (common / ".fable-team" / "LIVE_ROOT").write_text(f"{data}\n", encoding="utf-8")
    (data / "auto.txt").write_text("on\n", encoding="utf-8")
    here = tmp_path / "bin"
    here.mkdir()
    (here / "ft-autonomy.sh").write_text('#!/usr/bin/env bash\ncat "$FT_ROOT/auto.txt" 2>/dev/null || echo off\n', encoding="utf-8")
    monkeypatch.setattr(fh, "HERE", here)
    assert fh.autonomy(data) == "ON"  # 데이터 루트 직접 = ON
    assert fh.autonomy(common) == "ON"  # 공용 루트로 불러도 LIVE_ROOT 를 넘긴다(지금 판 = OFF)


# ── ⓚ 골 표 0줄 = 지도 실패(발행 0 · 조용한 «정상» 0) ──

def test_k_zero_goals_fails_instead_of_publishing(tmp_path, oc, monkeypatch):  # noqa: F811
    monkeypatch.setattr(fh, "goals", lambda: [])
    monkeypatch.setattr(fh, "live_teams", lambda r: [{"team": "t", "live": 0, "working": 0, "unknown": 0}])
    monkeypatch.setattr(fh, "autonomy", lambda r: "ON")
    with pytest.raises(RuntimeError, match="골 표 0줄"):
        fh.build(tmp_path, tmp_path, "x.md", "", "a", NOW)
    monkeypatch.setattr(fh, "build", lambda *a: (_ for _ in ()).throw(RuntimeError("골 표 0줄")))
    state = tmp_path / "state"
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-19 09:15")
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_NEWS_DIR", str(tmp_path / "news"))
    assert fh.tick(tmp_path, state, tmp_path, "x.md", tmp_path / "news", "a", "b") == (1, "지도 만들기 실패")


def test_i_html_mode_tick_receives_ref_issue(tmp_path, monkeypatch):
    """FT_NEWS_MODE=html = ft_news_ledger 가 ft_news_html.tick 을 실제로 부르고 그 판이 origin/main ref."""
    repo, root, rel, old, new = _stale_copy(tmp_path)
    noop = tmp_path / "fetch.sh"
    noop.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    for k, v in {"FT_ROOT": root, "FT_LEDGER_REPO": repo, "FT_LEDGER_PATH": rel, "FT_NEWS_FETCH_MIN": "0", "FT_NEWS_MODE": "html",
                 "FT_LEDGER_FETCH": str(noop), "FT_NEWS_DIR": str(tmp_path / "news")}.items():
        monkeypatch.setenv(k, str(v))
    seen = []
    monkeypatch.setattr(fh, "tick", lambda *a: (seen.append(a), (0, "지도 발행"))[1])
    state = tmp_path / "state"
    state.mkdir()
    assert nl._run(root, state) == (0, "지도 발행")
    assert len(seen) == 1 and seen[0][6] == new  # (root, state, repo, rel, news, base, cur) 의 cur = ref 판


# ── r575 — opengateway(pi 딥식) 공급자 1줄 + 키 = pi 설정 · ⓐ~ⓓ 가짜 서버 · ⓔ 실 1회는 evidence/r575 ──

OG_MODEL = "opengateway/deepseek/deepseek-v4.1-flash-ultrafast"


def _og(tmp_path, monkeypatch, srv, pi_body: str | None) -> Path:
    """opengateway 시험판 — 가짜 서버 주소 · pi 설정 대역(FT_NEWS_PI_MODELS) · env 키·모델 초기화."""
    pi = tmp_path / "models.json"
    if pi_body is not None:
        pi.write_text(pi_body, encoding="utf-8")
    for k in ("OPENROUTER_API_KEY", "OPENGATEWAY_API_KEY", "FT_NEWS_VIA", "FT_NEWS_EFFORT"):
        monkeypatch.delenv(k, raising=False)
    for k, v in {"FT_NEWS_HTTP_BASE": srv.base, "FT_NEWS_PI_MODELS": str(pi), "FT_NEWS_STARTUP_LOG": str(tmp_path / "startup.tsv"),
                 "FT_OPENCODE": str(tmp_path / "없는-opencode"), "FT_NEWS_MODEL": OG_MODEL}.items():
        monkeypatch.setenv(k, v)
    return pi


def test_r575_a_opengateway_provider_row_routes_to_pi_key(tmp_path, llm, monkeypatch):
    """ⓐ 고친 판 = 접두 opengateway → 주소 /chat/completions · 모델 = 접두 뒤 · Authorization = pi 설정 키(글자 그대로 꼴)."""
    _og(tmp_path, monkeypatch, llm, '{"providers":{"opengateway":{"apiKey":"apik-pi-literal"}}}')
    fh.run_files(DATA, tmp_path / "out", NOW)
    first = llm.reqs[0]
    assert first["path"].endswith("/chat/completions") and first["auth"] == "Bearer apik-pi-literal"
    assert first["body"]["model"] == "deepseek/deepseek-v4.1-flash-ultrafast"  # 접두(fh_news) 뒤 = 모델
    assert sorted(_part(p) for p in llm.prompts()) == sorted(fr.PARTS)


def test_r575_a2_pi_key_command_form_runs_and_env_form_reads(tmp_path, llm, monkeypatch):
    """ⓐ₂ pi 설정 꼴 3가지 — `!명령` = 그 stdout · `$NAME` = 그 env · 값은 로그 0."""
    _og(tmp_path, monkeypatch, llm, '{"providers":{"opengateway":{"apiKey":"!echo apik-from-command"}}}')
    assert fr.api_key("OPENGATEWAY_API_KEY") == "apik-from-command"
    _og(tmp_path, monkeypatch, llm, '{"providers":{"opengateway":{"apiKey":"${OG_TEST_KEY}"}}}')
    monkeypatch.setenv("OG_TEST_KEY", "apik-from-env-name")
    assert fr.api_key("OPENGATEWAY_API_KEY") == "apik-from-env-name"


def test_r575_b_missing_pi_key_or_file_fails_loud_and_prints_no_key(tmp_path, llm, monkeypatch, capsys):
    """ⓑ pi 설정에 키 없음·파일 없음 = «키 없음» ERROR(조용한 대체 0) · 키 값 글자 0."""
    for body in (None, '{"providers":{"opengateway":{"apiKey":"   "}}}', '{"providers":{"other":{"apiKey":"x"}}}'):
        _og(tmp_path, monkeypatch, llm, body)
        with pytest.raises(fr.NewsHtmlError, match="키 없음: OPENGATEWAY_API_KEY"):
            fh.run_files(DATA, tmp_path / f"o{len(llm.reqs)}", NOW)
        assert llm.reqs == []  # 서버에 닿기 전에 실패
        assert "apik-pi" not in capsys.readouterr().err


def test_r575_c_env_key_wins_over_pi_file(tmp_path, llm, monkeypatch):
    """ⓒ env OPENGATEWAY_API_KEY 가 pi 설정보다 이김(시험 대역 손잡이)."""
    _og(tmp_path, monkeypatch, llm, '{"providers":{"opengateway":{"apiKey":"apik-pi-literal"}}}')
    monkeypatch.setenv("OPENGATEWAY_API_KEY", "apik-env-wins")
    assert fr.api_key("OPENGATEWAY_API_KEY") == "apik-env-wins"


def test_r575_d_openrouter_path_unchanged(tmp_path, llm, monkeypatch):
    """ⓓ openrouter 경로 그대로 — 공급자 표 1줄 추가가 옛 길을 건드리지 않는다(키 = zshrc 마지막 활성 줄)."""
    monkeypatch.setenv("FT_NEWS_MODEL", "openrouter/anthropic/claude-haiku-5.5")
    monkeypatch.setenv("FT_NEWS_PI_MODELS", str(tmp_path / "없는-models.json"))  # pi 설정 없어도 openrouter 는 돈다
    fh.run_files(DATA, tmp_path / "o", NOW)
    assert llm.reqs[0]["auth"] == "Bearer sk-or-fake-r563"
    assert fr.HTTP_BASE["openrouter"] == "https://openrouter.ai/api/v1" and len(fr.HTTP_BASE) == 2
