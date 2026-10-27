"""R135b 출력 모양 가림 ft_secret_shapes — 텍스트 → (가린 텍스트, [(종류, 줄 번호)]).
값은 전부 가짜(FAKE…) — 실제 비밀 조회 0 · 시험 출력·단언 메시지에 가짜 값 원문을 다시 쓰지 않는다."""
import importlib.util
import subprocess
import tempfile
import time
from pathlib import Path

import pytest
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

ROOT = Path(__file__).resolve().parents[3]
SHAPES = ROOT / "harness/bin/ft_secret_shapes.py"
KIT_BIN_SHAPES = ROOT / "harness/kit/fable-team/bin/ft_secret_shapes.py"
KIT_HOOKS = ROOT / "harness/kit/fable-team/templates/hooks/ft_secret_shapes.py"
SCOPE = ROOT / "harness/bin/autonomy_scope_secret.py"
KIT_BIN_SCOPE = ROOT / "harness/kit/fable-team/bin/autonomy_scope_secret.py"


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


# ── r977: 비밀 «경계» 한 벌 — 앞뒤 경계는 ASCII 영숫자·_ 아님(하이픈·한글·문장부호는 경계) ──────────
# 위치 4종 × 꼴 5종. base 는 한글 바로 뒤 토큰을 놓쳤고(r949 r3 는 하이픈 뒤 토큰도 놓쳤다).
POS = {"space": "x ", "korean": "토큰은", "paren": "(", "hyphen": "-"}
TOKENS = ["ghp_", "gho_", "github_pat_", "xoxb-", "sk-", "AIza"]  # TOKEN_PREFIX 가 아는 꼴(목록 확장 0)


@pytest.mark.parametrize("prefix", TOKENS)
@pytest.mark.parametrize("pos", list(POS), ids=list(POS))
def test_a_token_prefix_masked_at_all_four_positions(prefix, pos):  # ⓐ 4위치 전부 잡힘(회귀 0 포함)
    src = POS[pos] + prefix + PAD + " end"
    out, hits = S.mask(src)
    assert [h[0] for h in hits] == ["token-prefix"], (pos, prefix, hits)
    assert PAD not in out and prefix not in out


def _load_scope():
    spec = importlib.util.spec_from_file_location("autonomy_scope_secret_t", SCOPE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


SC = _load_scope()
SHAPE_SAMPLES = {  # SECRET_SHAPE 가 아는 꼴(목록 확장 0 — github_pat_ 는 별 카드)
    "ghp": "ghp_" + "A" * 30,
    "xoxb": "xoxb-" + "1" * 12,
    "sk": "sk-" + "A" * 20,
    "AKIA": "AKIA" + "A" * 16,
    "pem": "-----BEGIN RSA PRIVATE KEY-----",
}


@pytest.mark.parametrize("kind", list(SHAPE_SAMPLES), ids=list(SHAPE_SAMPLES))
@pytest.mark.parametrize("pos", list(POS), ids=list(POS))
def test_b_secret_shape_true_at_all_four_positions(kind, pos):  # ⓑ 두 lib 이 같은 경계를 쓴다
    assert SC.SECRET_SHAPE.search(POS[pos] + SHAPE_SAMPLES[kind]), (pos, kind)


def test_b_edge_char_sets_are_equal_between_libs():  # ⓑ 글자 집합 비교 — 한쪽만 고치면 FAIL
    assert S.EDGE_CHARS == SC.EDGE_CHARS
    assert S.EDGE_L == "(?<![" + S.EDGE_CHARS + "])" and SC.EDGE_L == "(?<![" + SC.EDGE_CHARS + "])"
    # r977 r4(오빠 결정 1번): «오른쪽» 경계는 base 와 같다 — 두 lib 다 오른쪽 경계 상수를 두지 않는다
    assert not hasattr(S, "EDGE_R") and not hasattr(SC, "EDGE_R")
    assert "(?P<val>" + S.TOKEN_PREFIX + r"[A-Za-z0-9_.\-]{16,})" in S.RULES[2][1].pattern  # 값 뒤 앞보기 0
    assert "AKIA[0-9A-Z]{16}\\b" in SC.SECRET_SHAPE.pattern  # AKIA 만 base 꼴 `\b`(나머지 꼴은 값 뒤 경계 없음)


@pytest.mark.parametrize("family", ["shapes", "autonomy"])
def test_c_five_copies_byte_identical(family):  # ⓒ 사본 5벌(3 + 2) 같은 커밋 · cmp0
    paths = [SHAPES, KIT_BIN_SHAPES, KIT_HOOKS] if family == "shapes" else [SCOPE, KIT_BIN_SCOPE]
    blobs = {p.read_bytes() for p in paths}
    assert len(blobs) == 1, [str(p) for p in paths]


HARNESS = ROOT / "harness"
CONSUMERS = ["tests/test_secret_scan.sh", "tests/test_secret_output_mask.sh",
             "tests/test_evidence_inject_scan.sh", "tests/test_flag_off_scan.sh"]


@pytest.mark.parametrize("script", CONSUMERS, ids=[Path(x).stem for x in CONSUMERS])
def test_d_consumer_suites_still_pass(script):  # ⓓ 소비자 4종 — 경계 재정의 0(공용 판정 그대로 호출)
    p = subprocess.run(["bash", script], cwd=HARNESS, capture_output=True, text=True, timeout=180)
    assert p.returncode == 0, (p.stdout[-2000:], p.stderr[-2000:])


# ── r977 r2: DA⑥ r1 반례 2건 — 경계를 넓힌 대가로 «새던 입력» 만 되돌린다(경계 글자 집합은 한 벌 그대로) ──────
BASE_SHA = "1545012e"  # 카드 기준값(base · 경계 한 벌 도입 전)
BASE_PATHS = {"shapes": "feature-pack/fable-team/harness/bin/ft_secret_shapes.py",
              "scope": "feature-pack/fable-team/harness/bin/autonomy_scope_secret.py"}
_BASE_CACHE: dict[str, object] = {}


def _base_mod(name):  # base 판 모듈 — 팩 리포 안에서만(설치본에는 base 커밋이 없다 → skip)
    if name in _BASE_CACHE:
        return _BASE_CACHE[name]
    p = subprocess.run(["git", "-C", str(ROOT), "show", BASE_SHA + ":" + BASE_PATHS[name]], capture_output=True, text=True)
    if p.returncode != 0:
        pytest.skip("base " + BASE_SHA + " 없음 — " + BASE_PATHS[name])
    tmp = Path(tempfile.mkdtemp()) / ("base_" + name + ".py")
    tmp.write_text(p.stdout, encoding="utf-8")
    spec = importlib.util.spec_from_file_location("base_" + name + "_t", tmp)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    _BASE_CACHE[name] = mod
    return mod


def _masked_values(src, out):  # mask 출력에서 «가린 값» 을 되짚는다(출력 = 앞조각 + *** + 앞조각 …)
    vals, cur = [], 0
    for k, piece in enumerate(out.split("***")):
        j = src.find(piece, cur)
        if j < 0:
            return vals
        if k and j > cur:
            vals.append(src[cur:j])
        cur = j + len(piece)
    if out.endswith("***") and cur < len(src):
        vals.append(src[cur:])
    return vals


DA_CASE1 = "한ghp_" + "A" * 30 + "_API_TOKEN=" + "B" * 30  # DA⑥ r1 반례 1(더미)
DA_CASE2 = "note-----BEGIN RSA PRIVATE KEY-----"           # DA⑥ r1 반례 2(더미)
SPACE_VARIANT = " ghp_" + "A" * 30 + "_API_TOKEN=" + "B" * 30  # 공백 앞 같은 꼴(카드 §반례 집합 알려진 한계)
DA_R2_1 = "***: SERVICE_CUSTOMER_API_TOKEN=" + "B" * 30  # DA⑥ r2 반례 ① — r3 의 «*** 이름» 이 이름을 값으로 삼켜 값을 놓쳤다
DA_R2_2 = "ghs_" + "A" * 30 + "_"                     # DA⑥ r2 반례 ② — 끝 밑줄 토큰
R4_DIFF_FIRST = "토큰은AIza" + "A1b2" * 8 + "API_TOKEN=" + "B" * 21  # r4 차분 1000건의 첫 위반 입력(arch 시험 칸 1)


def _base_masked_left_in(src, new_out):  # base 가 가린 글자가 현재판 출력에 남았나(④' base ⊆ 현재판)
    return [v for v in _masked_values(src, _base_mod("shapes").mask(src)[0]) if v and v.strip("*") and v in new_out]


def test_f_r2_case1_matches_base():  # ⓕ' DA⑥ r2 반례 ① — base 와 바이트 동일(이름을 값으로 삼키지 않는다)
    assert S.mask(DA_R2_1) == _base_mod("shapes").mask(DA_R2_1)
    out, hits = S.mask(DA_R2_1)
    assert [h[0] for h in hits] == ["named-secret"], hits
    assert out.endswith("SERVICE_CUSTOMER_API_TOKEN=***") and "B" * 8 not in out


def test_i_space_variant_masks_both():  # ⓘ 공백 앞 — base 가 토큰을, 이 판본은 토큰+값 둘 다 가린다(base 가 가린 글자 ⊆ 현재판)
    out, hits = S.mask(SPACE_VARIANT)
    assert out == " ***=***", out
    assert [h[0] for h in hits] == ["named-secret", "token-prefix"], hits
    assert _base_masked_left_in(SPACE_VARIANT, out) == []


def test_i_r4_diff_first_input_masks_both():  # r977 r4b(arch 판단) — 이름=값 먼저 → 토큰 꼴이 이름 꼬리를 삼켜도 값이 남지 않는다
    out, hits = S.mask(R4_DIFF_FIRST)
    assert out == "토큰은***=***", out
    assert [h[0] for h in hits] == ["named-secret", "token-prefix"], hits
    assert "B" * 8 not in out and "AIza" not in out
    assert _base_masked_left_in(R4_DIFF_FIRST, out) == []


def test_j_trailing_underscore_token_is_secret_shape():  # ⓙ DA⑥ r2 반례 ② — 오른쪽 경계 되돌림
    assert SC.SECRET_SHAPE.search(DA_R2_2)
    assert _base_mod("scope").SECRET_SHAPE.search(DA_R2_2)


def test_g_pem_header_with_leading_ascii_is_secret_shape():  # ⓖ 변이 «PEM 을 EDGE 안으로» → FAIL
    assert SC.SECRET_SHAPE.search(DA_CASE2)
    assert SC.reason([(None, [(1, DA_CASE2)], False)], None, None, None) == "추가 줄에 비밀 꼴"


SUBSET_INPUTS = (  # ⓗ base 대조 전수 — 기존 시험 입력 89건(DA⑥ r1 이 확인한 «가림 대조» 입력 그대로)
    [s for s, _k, _e in MASK] + PASS_THROUGH + ORDINARY + [s for s, _k, _f in H4] + R4
    + ["git_sha=0123456789abcdef0123456789", "SECRET_FILE=/run/secrets/abcdefghijklmnopqrstu",
       "API_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxx", "TOKEN=${API_TOKEN_VALUE_LONG_ENOUGH}"]
    + WEBHOOK_MASK + ["set webhook " + HOOK + "<webhook>", "set webhook " + HOOK + "***",
                      "set webhook " + HOOK + "$SLACK_WEBHOOK_PATH", "문서: Slack 은 hooks.slack.com 으로 보낸다",
                      "X_WEBHOOK_NAME=short"]
    + [POS[p] + t + PAD + " end" for p in POS for t in TOKENS] + [DA_CASE1]
)


def test_h_input_set_is_eighty_nine():
    assert len(SUBSET_INPUTS) == 89


def test_h_no_base_masked_value_survives():  # ⓗ base 가 가리던 값이 현재판 출력에 남지 않는다(적게 가림 0) — r4 뒤 «알려진 한계 1건» 만 허용
    base = _base_mod("shapes")
    leaked = []
    for src in SUBSET_INPUTS:
        if "***" in src:  # 이미 가려진 글자가 든 입력은 되짚기(조각 정렬)가 흔들린다 — 대조에서 뺀다
            continue
        out_new, _ = S.mask(src)
        for val in _masked_values(src, base.mask(src)[0]):
            if val and val.strip("*") and val in out_new:
                leaked.append((src[:24], val[:8]))
    assert leaked == []


SHAPE_INPUTS = ([POS[p] + SHAPE_SAMPLES[k] for p in POS for k in SHAPE_SAMPLES]
                + [DA_CASE2, "한-----BEGIN RSA PRIVATE KEY-----", "AKIA" + "A" * 16,
                   "x gh[pousr]_" + "a" * 30, "sk-" + "a" * 20, "xoxb-" + "1" * 12])


def test_h_secret_shape_true_inputs_stay_true():  # ⓗ base True → 현재판 True (PEM 앞 글자 붙음 포함)
    base = _base_mod("scope")
    lost = [s[:24] for s in SHAPE_INPUTS if base.SECRET_SHAPE.search(s) and not SC.SECRET_SHAPE.search(s)]
    assert lost == []
