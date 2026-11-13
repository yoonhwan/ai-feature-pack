"""r1879 `post --bind` = 새 root thread 를 게시 좌석에 묶고 요청 등록 → 사람 답 = «답 <의도 키>» — 카드 반례 ①~⑥ · 변이 M1~M3.
임시 root · 가짜 post·깨움 · 실 Slack·실 장부·실 명부 0 · sleep 0. 기준판(팩 origin/main = --bind 없음 usage)에서 ① ② ④ ⑤ ⑥ Red."""
import importlib.util, json, os, shutil, sys  # noqa: E401
import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, C, U, SEAT, OTHER = "TFAKE", "C0DESK", "UOPPA", "byz-planner-desk-pi#152", "byz-planner-master-pi#1"
ROOT_TS, HUMAN_TS, BODY = "1800000005.000100", "1800000006.000100", "질문 하나\n\n근거: #1"

def _load(name, base=FT2, tag="base"):
    spec = importlib.util.spec_from_file_location("ft2_r1879_%s_%s" % (tag, name.replace("/", "_")),
                                                  os.path.join(base, name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module

def _mutant(tmp, old, new):  # wiring.py 사본 한 곳만 바꾼다
    base = tmp / "ft2m"
    for part in ("core", "adapters"):
        shutil.copytree(os.path.join(FT2, part), base / part)
    path = base / "adapters" / "slack" / "wiring.py"
    text = path.read_text(encoding="utf-8")
    assert text.count(old) == 1, old
    path.write_text(text.replace(old, new), encoding="utf-8")
    return _load("adapters/slack/wiring", str(base), tmp.name)

def _rows(root, name):
    path = root / ".fable-team" / "teams" / "planner" / "slack" / name
    return [json.loads(ln) for ln in path.read_text(encoding="utf-8").splitlines() if ln.strip()] if path.exists() else []

def _post(root, wiring, post=None, bind=True):
    path = root / ".fable-team" / "teams" / "planner" / "slack" / "receive.jsonl"
    if not path.exists():  # 수신 증거 1행(r1852 채널 근거)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"key": [W, C, "1800000001.000100"], "state": "received"}) + "\n", encoding="utf-8")
    (body := root / "body.txt").write_text(BODY, encoding="utf-8")
    argv = ["post", "--root", str(root), "--team", "planner", "--channel", C, "--seat", SEAT,
            "--body-file", str(body)] + (["--bind"] if bind else [])
    return wiring.main(argv, post=post or (lambda ch, ts, text, meta: ROOT_TS), sleep=lambda s: None)

def _intent(root):
    return [r["command"] for r in _rows(root, "publish.jsonl") if r["command"].startswith("post:")][0]

def _human(root, wiring, monkeypatch):  # 그 thread 의 사람 글을 실제 wire()·SlackRoute 로 접수
    monkeypatch.setenv("FT2_SLACK_WAKE", "%s -c pass" % sys.executable)  # 깨움 대역 — 실 우편함 0
    recv = wiring.receive.SlackReceive(str(root), ack=lambda e: None, allowed_users=(U,), allowed_channels=(C,),
                                       team="planner")
    router, _ = wiring.wire(str(root), receive=recv, bindings=wiring.binding.ThreadBinding(str(root), "planner"),
                            team="planner")
    return router.route({"type": "message", "user": U, "channel": C, "ts": HUMAN_TS, "thread_ts": ROOT_TS,
                         "team": W, "text": "체크"})

def s_answer(root, wiring, monkeypatch):  # ① 반환 = (kind, id, to, 새 업무 깨움 수, issues 접수 수)
    assert _post(root, wiring) == 0
    row = _human(root, wiring, monkeypatch)
    news = [w for w in _rows(root, "wire.jsonl") if w.get("t") == "wake" and "새 업무" in w["head"]]
    issues = wiring.receive.intake.Intake(str(root), "issues").lookup(row["command"])
    return row["kind"], row["id"], row["to"], len(news), int(issues is not None)

def test_1_bind_registers_request_and_human_post_is_answer(tmp_path, monkeypatch, capsys):
    wiring = _load("adapters/slack/wiring")
    kind, rid, to, news, issues = s_answer(tmp_path, wiring, monkeypatch)
    intent = _intent(tmp_path)
    assert (kind, rid, to, news, issues) == ("답 " + intent, intent, SEAT, 0, 0)
    bound = wiring.binding.ThreadBinding(str(tmp_path), "planner").settled()
    assert [(e["key"], e["open"], e["gen"], e["seat"]) for e in bound.values()] == [([W, C, ROOT_TS], True, 1, SEAT)]
    assert [(r["key"], r["id"], r["state"]) for r in _rows(tmp_path, "route.jsonl") if r["t"] == "req"] == \
        [([W, C, ROOT_TS], intent, "open")]
    assert "state=posted ts=%s bound=%s#1 req=%s" % (ROOT_TS, SEAT, intent) in capsys.readouterr().out

def test_2_6_standard_reply_posts_and_completes_intake(tmp_path, monkeypatch, capsys):
    wiring = _load("adapters/slack/wiring")
    command = _human(tmp_path, wiring, monkeypatch)["command"] if _post(tmp_path, wiring) == 0 else None
    (body := tmp_path / "reply.txt").write_text("답 받았습니다", encoding="utf-8")
    argv = ["reply", "--root", str(tmp_path), "--team", "planner", "--thread", ROOT_TS, "--seat", SEAT,
            "--body-file", str(body), "--command", command]
    capsys.readouterr()
    assert wiring.main(argv, post=lambda ch, ts, text, meta: "1800000007.000100", sleep=lambda s: None) == 0  # ②
    assert capsys.readouterr().out.startswith("state=posted ")
    dispatch = _load("core/dispatch")  # ⑥ r1872 설치판 = 그 사람 글 접수 일 완료 1
    rs = dispatch.intake.Intake(str(tmp_path), "planner")
    assert command in (dispatch.record.recover_state(rs._state(), rs.records()).get("done") or {})

def s_plain(root, wiring, monkeypatch):  # ③ 반환 = (binding 수, req 수, kind)
    assert _post(root, wiring, bind=False) == 0
    kind = _human(root, wiring, monkeypatch)["kind"]
    reqs = [r for r in _rows(root, "route.jsonl") if r["t"] == "req"]
    return len(wiring.binding.ThreadBinding(str(root), "planner").settled()), len(reqs), kind

def test_3_without_bind_unchanged(tmp_path, monkeypatch):
    assert s_plain(tmp_path, _load("adapters/slack/wiring"), monkeypatch) == (0, 0, "재개 필요")

def s_lost(root, wiring):  # ④ 반환 = (rc, binding 수, req 수)
    def lost(*a):
        raise wiring.publish.ResponseLost("timeout")
    rc = _post(root, wiring, post=lost)
    return rc, len(wiring.binding.ThreadBinding(str(root), "planner").settled()), len(_rows(root, "route.jsonl"))

def test_4_uncertain_no_bind(tmp_path):
    assert s_lost(tmp_path, _load("adapters/slack/wiring")) == (1, 0, 0)

def test_5_existing_binding_kept_and_one_stderr_line(tmp_path, capsys):
    wiring = _load("adapters/slack/wiring")
    ledger = wiring.binding.ThreadBinding(str(tmp_path), "planner")
    ledger.bind(wiring.binding.thread_key(W, C, ROOT_TS), OTHER)
    assert _post(tmp_path, wiring) == 0
    out, err = capsys.readouterr()
    assert out == "state=posted ts=%s\n" % ROOT_TS and err.count("binding 실패 · 판정 불가") == 1
    assert [e["seat"] for e in ledger.settled().values()] == [OTHER] and _rows(tmp_path, "route.jsonl") == []

@pytest.mark.parametrize("name,old,new", [
    ("M1", 'row["state"] == publish.POSTED and row.get("ts")', 'row.get("state")'),
    ("M2", 'bind = verb == "post" and "--bind" in argv', 'bind = verb == "post"'),
    ("M3", ".register(key, ask)", ""),
])
def test_mutants_caught(tmp_path, monkeypatch, name, old, new):
    wiring = _mutant(tmp_path, old, new)
    root = tmp_path / "root"
    root.mkdir()
    if name == "M1":
        assert s_lost(root, wiring) != (1, 0, 0)
    elif name == "M2":
        assert s_plain(root, wiring, monkeypatch) != (0, 0, "재개 필요")
    else:
        assert s_answer(root, wiring, monkeypatch)[:2] == ("새 업무", None)
