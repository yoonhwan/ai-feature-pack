"""R135b 출력 모양 가림 ft_secret_shapes — 텍스트 → (가린 텍스트, [(종류, 줄 번호)]).
값은 전부 가짜(FAKE…) — 실제 비밀 조회 0 · 시험 출력·단언 메시지에 가짜 값 원문을 다시 쓰지 않는다."""
import importlib.util
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
SHAPES = ROOT / "harness/bin/ft_secret_shapes.py"
KIT_HOOKS = ROOT / "harness/kit/fable-team/templates/hooks/ft_secret_shapes.py"


def _load():
    import sys

    sys.path.insert(0, str(SHAPES.parent))  # ft_secret_targets 를 import 하므로 같은 폴더를 먼저 둔다
    spec = importlib.util.spec_from_file_location("ft_secret_shapes_t", SHAPES)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S = _load()
PAD = "A1b2C3d4E5f6G7h8I9j0K1l2M3n4"  # 가짜 꼬리(28자)

MASK = [  # (입력, 기대 종류, 가린 뒤 남아야 하는 앞부분)
    ("conn postgres://u:FAKEPW1234@h/db ok", "url-cred", "postgres://u:***@h/db"),
    ("PGPASSWORD=FAKEabc123 psql", "pgpassword", "PGPASSWORD=***"),
    ("tok ghp_FAKE" + PAD, "token-prefix", "tok ***"),
    ("tok gho_FAKE" + PAD, "token-prefix", "tok ***"),
    ("tok github_pat_FAKE" + PAD, "token-prefix", "tok ***"),
    ("key sk-FAKE" + PAD, "token-prefix", "key ***"),
    ("slack xoxb-FAKE" + PAD, "token-prefix", "slack ***"),
    ("slack xoxp-FAKE" + PAD, "token-prefix", "slack ***"),
    ("g AIzaFAKE" + PAD, "token-prefix", "g ***"),
    ("g ya29.FAKE" + PAD, "token-prefix", "g ***"),
    ("jwt eyJFAKE.FAKE.FAKE end", "jwt", "jwt *** end"),
    ("API_TOKEN=" + PAD + "xyz", "named-secret", "API_TOKEN=***"),
]


@pytest.mark.parametrize("src,kind,expect", MASK)
def test_masks_shape(src, kind, expect):
    out, hits = S.mask(src)
    assert expect in out
    assert [h[0] for h in hits] == [kind]
    assert "FAKEPW" not in out and "FAKEabc" not in out and PAD not in out
    assert "eyJFAKE.FAKE.FAKE" not in out


PASS_THROUGH = [  # ⓐ 자리표시자 — 변경 0 · 적중 0
    "postgres://u:***@h/db",
    "postgres://u:<password>@h/db",
    "postgres://u:$PGPASSWORD@h/db",
    "PGPASSWORD=$PGPASSWORD psql",
    "PGPASSWORD=*** psql",
    "export API_TOKEN=${API_TOKEN}",
    "API_TOKEN=<token>",
    "API_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxx",
    "API_TOKEN=***",
    "token ghp_" + "x" * 36,
    "token ghp_***",
]
ORDINARY = [  # ⓑ 평범한 출력 20개 — 변경 0
    "d83ed530f9 [feature] 세션만 닫는 좌석 명부 stop-ready 표기 — ft-seat-close.sh (R297)",
    "commit d83ed530f9029693f22f4bbfc16a7bb668ec92fd",
    "Author: Morpheus <m@example.com>",
    "============================= 12 passed in 0.31s =============================",
    "tests/scripts/test_x.py::test_a PASSED                                  [ 50%]",
    "grep: scripts/x.sh:42:    API_TOKEN_NAME",
    "ft_secret_targets.py:9:NAME = re.compile(r\"PASSWORD|PASS|TOKEN|SECRET|DSN|KEY\", re.I)",
    "uuid 3f2b8c1e-9a4d-4e7b-8c21-5d6f7a8b9c0d",
    "sha256 d64777274c4b371a",
    "data:image/png;base64,iVBORw0KGgo",
    "export PATH=/usr/local/bin:/usr/bin",
    "TOKEN_NAMES = ['a', 'b']",
    "https://example.com/docs/guide",
    "ssh://git@github.com/org/repo.git",
    "postgres://u@h/db",
    "KEY_COUNT=5",
    "PASSWORD_FILE=/run/secrets/db_password_file_path_value",
    "total 48",
    "-rw-r--r--  1 u  staff  8455 10 17 04:51 scripts/fable-team-bin/ft_secret_judge.py",
    "Ran 20 tests",
]


@pytest.mark.parametrize("src", PASS_THROUGH + ORDINARY)
def test_unchanged(src):
    out, hits = S.mask(src)
    assert out == src and hits == []


def test_ordinary_set_is_twenty():
    assert len(ORDINARY) == 20


def test_line_numbers_and_multi_hits():
    src = "ok\nPGPASSWORD=FAKEabc123\nok\npostgres://u:FAKEPW1234@h/db\n"
    out, hits = S.mask(src)
    assert hits == [("pgpassword", 2), ("url-cred", 4)]
    assert out.endswith("\n") and out.count("\n") == src.count("\n")


def test_hits_carry_no_value():
    _, hits = S.mask("a postgres://u:FAKEPW1234@h/db b")
    assert all(isinstance(k, str) and isinstance(n, int) for k, n in hits)
    assert "FAKEPW" not in repr(hits)


def test_empty_and_non_text():
    assert S.mask("") == ("", [])


def test_one_mb_under_200ms():
    line = "d83ed530f9 [feature] 세션 정리 ghp 12 passed in 0.3s api_key_name aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
    big = (line * (1_048_576 // len(line.encode()) + 1))[:1_048_576]
    best = min(_timed(big) for _ in range(3))
    assert best < 0.2, best


def _timed(text):
    t = time.perf_counter()
    S.mask(text)
    return time.perf_counter() - t


@pytest.mark.parametrize("adversarial", ["a." * 524288, "a" * 1048576, "API_" * 262144, "KEY" * 349525], ids=["scheme-dots", "one-long-token", "name-repeat", "keyword-repeat"])
def test_adversarial_one_mb_under_200ms(adversarial):  # H2 — 역추적 폭주 0 (제곱 시간 금지)
    assert min(_timed(adversarial) for _ in range(3)) < 0.2


WORST = {  # r3 H2 — 규칙별 최악 입력(한 덩어리 1MB): 덩어리 안 모든 위치에서 매칭을 다시 시작하면 제곱 시간
    "jwt-dash": "eyJaaaa-" * 131072,
    "url-ab": "ab" * 524288,
    "url-jwt": "eyJaaaa-" * 131072,
    "named-eq": "API_TOKEN=" * 104857,
    "named-underscore-eq": "a_" * 524288 + "=",
    "named-spaced": ("A" * 40 + " = ") * 20000,
}


@pytest.mark.parametrize("adversarial", WORST.values(), ids=WORST.keys())
def test_worst_case_one_mb_under_200ms(adversarial):
    assert min(_timed(adversarial) for _ in range(3)) < 0.2


LONG_NAME = "PRODUCTION_CUSTOMER_COMMUNICATION_INTEGRATION_API_TOKEN"  # 55자 — 길이 상한이 있으면 가림 누락(H4)
H4 = [  # (입력, 기대 종류, 새면 안 되는 가짜 값)
    ("a" * 33 + "://u:FAKEPW1234@h/db", "url-cred", "FAKEPW"),
    (LONG_NAME + "=" + PAD + "xyz", "named-secret", PAD),
    ("SERVICE_" + "A" * 41 + "_TOKEN=" + PAD + "xyz", "named-secret", PAD),
]


@pytest.mark.parametrize("src,kind,fake", H4, ids=["scheme-33", "name-55", "name-service-long"])
def test_long_scheme_and_name_still_masked(src, kind, fake):  # r2 회귀(H4) — 길이 상한 제거 뒤에도 가린다
    out, hits = S.mask(src)
    assert [h[0] for h in hits] == [kind] and fake not in out


R4 = [  # DA⑥ r3 H4 — 앞 이름이 비밀 이름이 아니어도 뒤의 진짜 이름·값을 가린다(이름+구분자만 소비 · 값은 앞보기)
    "context: SERVICE_CUSTOMER_API_TOKEN=" + PAD + "xyz",
    "a: b: c: API_TOKEN=" + PAD + "xyz",
    "export api_token='" + PAD + "xyz' rest",
    "A=1 B: x API2_TOKEN: " + PAD + "xyz",
    "context: github_token=" + PAD + "xyz",
    "note: Password: " + PAD + "xyz",
]


@pytest.mark.parametrize("src", R4, ids=["service-after-context", "chain", "lower-quoted", "digit-name", "lower-github", "password-colon"])
def test_named_after_non_secret_name_is_masked(src):
    out, hits = S.mask(src)
    assert [h[0] for h in hits] == ["named-secret"] and PAD not in out


@pytest.mark.parametrize("src", ["git_sha=0123456789abcdef0123456789", "SECRET_FILE=/run/secrets/abcdefghijklmnopqrstu", "API_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxx", "TOKEN=${API_TOKEN_VALUE_LONG_ENOUGH}"], ids=["sha", "path", "xxx", "var"])
def test_named_lookahead_leaves_non_secrets(src):
    assert S.mask(src) == (src, [])


R4_WORST = {  # r4 — 앞보기 named-secret 도 1MB 적대 입력 200ms 이하
    "named-eq-repeat": "API_TOKEN=" * 104857,
    "named-ctx-repeat": "context: " * 116508,
    "named-a-colon": ("a: " + "A" * 25 + " ") * 36000,
    "named-x-eq-y": "x=" + "y" * 1048576,
}


@pytest.mark.parametrize("adversarial", R4_WORST.values(), ids=R4_WORST.keys())
def test_named_lookahead_worst_one_mb_under_200ms(adversarial):
    assert min(_timed(adversarial) for _ in range(3)) < 0.2


def test_named_keyword_not_in_name_is_untouched():  # 이름에 NAME 낱말이 없으면 20자+ 값이어도 비밀 아님
    src = "git_sha=0123456789abcdef0123456789"
    assert S.mask(src) == (src, [])


def test_ten_mb_with_one_secret_masks_under_2s():  # H1 — 큰 출력도 전체를 보고 가린다(앞부분만 보기 = 가림 구멍)
    line = "d83ed530f9 [feature] 세션 정리 12 passed in 0.3s\n"
    big = line * (10_485_760 // len(line.encode())) + "conn postgres://u:FAKEPW1234@h/db ok\n"
    t = time.perf_counter()
    out, hits = S.mask(big)
    assert time.perf_counter() - t < 2.0
    assert [h[0] for h in hits] == ["url-cred"] and "FAKEPW" not in out


HOOK = "https://hooks.slack.com/services/"
WEBHOOK_MASK = [  # R307 범위 2 — Slack webhook 주소 경로는 값이다(이름 없이 주소만 찍혀도 가린다)
    "SLACK_WEBHOOK_URL=" + HOOK + "TFAKE/BFAKE/FAKEfake1234",
    "slack_webhook_url: " + HOOK + "T/B/x",
    "curl -X POST " + HOOK + "TFAKE/BFAKE/FAKEfake1234 -d @p.json",
]


@pytest.mark.parametrize("src", WEBHOOK_MASK)
def test_slack_webhook_path_is_masked(src):
    out, hits = S.mask(src)
    assert HOOK + "***" in out and "FAKE" not in out and "/T/B/x" not in out
    assert [h[0] for h in hits] == ["slack-webhook"]


@pytest.mark.parametrize("src", [
    "set webhook " + HOOK + "<webhook>",
    "set webhook " + HOOK + "***",
    "set webhook " + HOOK + "$SLACK_WEBHOOK_PATH",
    "문서: Slack 은 hooks.slack.com 으로 보낸다",
    "X_WEBHOOK_NAME=short",
])
def test_slack_webhook_docs_and_placeholders_unchanged(src):
    assert S.mask(src) == (src, [])


@pytest.mark.parametrize("src", [  # DA⑥ r1 H1(대소문자) · H2(%인코딩) — 값 조각이 하나도 남으면 안 된다
    "HTTPS://hooks.slack.com/services/TFAKE/BFAKE/FAKEfake1234",
    "https://HOOKS.SLACK.COM/services/TFAKE/BFAKE/FAKEfake1234",
    "https://hooks.slack.com/services/TFAKE%41/BFAKE/FAKE%2Bfake1234",
])
def test_slack_webhook_case_and_percent_forms_fully_masked(src):
    out, hits = S.mask(src)
    assert out.endswith("/***") and "FAKE" not in out and "fake" not in out
    assert [h[0] for h in hits] == ["slack-webhook"]


def test_slack_webhook_doc_placeholder_with_angle_brackets_unchanged():  # DA⑥ r1 H3
    src = "set " + HOOK + "T<team>/B<channel>/<secret>"
    assert S.mask(src) == (src, [])


def test_webhook_id_named_secret_is_masked():  # NAME 에 WEBHOOK 이 들어가 NAMED 도 20자+ 값을 가린다
    out, hits = S.mask("X_WEBHOOK_ID=" + PAD)
    assert out == "X_WEBHOOK_ID=***" and [h[0] for h in hits] == ["named-secret"]


def test_kit_copy_is_byte_identical():
    assert KIT_HOOKS.read_bytes() == SHAPES.read_bytes()
