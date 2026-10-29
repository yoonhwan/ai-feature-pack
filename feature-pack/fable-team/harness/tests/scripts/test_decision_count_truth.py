"""R337 ft-decision-count — 「결정 인터뷰 N건」 = 머리 질문 표식 있는 미닫힘만 · 통보 머리 0 · planner 계보가 «#N 회신/답…» 으로 참조한 쪽지는 닫힘 · 24시간 넘은 질문은 «묵은» 칸.
임시 FT_ROOT·가짜 인박스·가짜 mailbox 로그만(실 mailbox 0). 임시 루트는 test_decision_count.make_env 그대로."""
import json
import time

import pytest
from test_decision_count import ME, NOW, make_env, put, row, run


@pytest.fixture
def env(tmp_path):
    return make_env(tmp_path)


G, C, L = "byz-graphics-master-claude#3", "byz-cfo-master-claude#1", "byz-loom-master-claude#1"


def sent(e, rows):
    """planner·남의 좌석이 보낸 쪽지 로그(mailbox.log.jsonl) — 자동 닫힘의 출처."""
    comm = e["root"] / ".fable-team/comm"
    comm.mkdir(parents=True, exist_ok=True)
    (comm / "mailbox.log.jsonl").write_text("".join(json.dumps({"seq": str(9000 + i), "ts": NOW.isoformat(), "to": t, "from": f, "body": b}, ensure_ascii=False) + "\n"
                                                    for i, (f, t, b) in enumerate(rows)), encoding="utf-8")


def sample():
    """표본 10건: 새 질문 3 · planner 회신으로 닫힌 질문 1 · 25시간 지난 질문 1 · 통보 5(물음표·선택지가 있어도 통보 머리면 0)."""
    return [row(1, "②", G, ago=30, body="[결정] PR #11 승인? ①예 ②아니오"),
            row(2, "②", C, ago=60, body="[HIL] DDL 적용 승인 요청"),
            row(3, "미상", "ft-stall-scan", ago=10, body="[긴급] 정지 해제할까요?"),
            row(4, "②", G, ago=120, body="[결정] 범위 상향 여부"),
            row(5, "③", C, ago=1500, body="[결정] 옛 질문?"),
            row(6, "②", G, ago=20, body="[완료] PR #9 LANDED · 다음 승인?"),
            row(7, "③", C, ago=25, body="[정지 레디] 다음 일 있나요?"),
            row(8, "②", L, ago=15, body="[수령] #3 값 받음"),
            row(9, "③", C, ago=12, body="[회신 #118550] ①K4b ②K4c"),
            row(10, "②", L, ago=5, body="[오디오 끝] tester rc=0")]


ANSWERS = [("byz-planner-master-claude#49", G, "[회신 #4] 승인 — 범위 상향"),  # 같은 계보(옛 세대)의 답 = 닫힘
           ("byz-planner-desk-claude#23", G, "[회신 #1] desk 가 대신 답"),  # 남의 좌석 참조 = 닫힘 아님
           (G, ME, "#2 확인 — cfo 질문 봤음")]


def test_a_sample_counts_only_open_question_heads(env):
    put(env, sample())
    sent(env, ANSWERS)
    r = run(env)
    assert r.returncode == 0, r.stderr
    assert r.stdout.startswith("결정 인터뷰 3건 · 스크립트 0건 · 팀 대기 2건(가장 오래 byz-cfo-master-claude#1 60분) · 묵은 1건"), r.stdout


def test_b_detail_has_reason_word_and_keeps_stale_visible(env):
    put(env, sample())
    sent(env, ANSWERS)
    d = run(env, "--detail").stdout.splitlines()
    assert d[1].startswith("  #2 ") and " 질문표식 " in d[1] and d[2].startswith("  #1 ") and " 질문표식 " in d[2], d
    rest = "\n".join(d[3:])
    assert "#5 " in rest and " 묵음 " in rest and "#7 " in rest and " 통보 " in rest and "#10 " in rest, d


def test_c_rest_notice_from_live_seat_is_not_team_wait(env):
    put(env, [row(1, "미상", G, ago=1000, body="[완료·휴식] arch 휴식 중 · 다음 일 요청?"),
              row(2, "④", C, ago=900, body="[완료·휴식 유지 #77] 그대로")])
    out = run(env).stdout
    assert out.startswith("결정 인터뷰 0건") and "팀 대기 0건" in out and "가장 오래" not in out, out


def test_c2_dead_seat_question_is_memo_not_n(env):
    put(env, [row(1, "②", "byz-old-master-claude#7", ago=100), row(2, "②", C, ago=50)])
    out = run(env).stdout
    assert out.startswith("결정 인터뷰 1건") and "(옛 좌석 미닫힘 1)" in out, out


def test_d_missing_autonomy_queue_file_is_zero_without_memo(env):
    put(env, [])
    out = run(env).stdout
    assert out.startswith("결정 인터뷰 0건") and "AUTONOMY-QUEUE" not in out, out


def test_e_missing_body_of_open_row_is_counted_not_guessed(env):
    """r738: 본문 파일이 사라진 열린 행은 셈을 멈추지 않고 «본문 없음» 으로 세고 경고 1줄(seq·경로)만 남긴다 — 그 밖의 읽기 실패은 그대로 rc4(tests/test_decision_count_missing_body_r738.sh ⓓ)."""
    put(env, [row(1, "②", G)])
    (env["root"] / ".fable-team/comm/bodies/1.txt").unlink()
    r = run(env)
    assert r.returncode == 0 and "본문 없음 1건" in r.stdout and "쪽지 본문 없음 1건(첫 #1 · 끝 #1)" in r.stderr, r.stdout + r.stderr
    assert r.stdout.startswith("결정 인터뷰 0건"), r.stdout  # 본문을 못 읽은 행은 질문으로 «지어내지» 않는다


def test_f_budget_with_big_sent_log_and_900_rows(env):
    put(env, [row(i, "미상", f"byz-t{i % 9}-master-claude#1", ago=i, body="[결정] x?" if i % 3 else "[완료] y") for i in range(1, 901)])
    sent(env, [(f"byz-t{i % 9}-master-claude#1", ME, "[보고] " + "가" * 300) for i in range(30000)]
         + [("byz-planner-master-claude#50", G, f"[회신 #{i}] 답") for i in range(1, 300)])
    (env["root"] / "live.txt").write_text("".join(f"byz-t{i}-master-claude#1\n" for i in range(9)))
    t0 = time.time()
    r = run(env)
    assert r.returncode == 0 and time.time() - t0 <= 2.5, (time.time() - t0, r.stderr)
    assert r.stdout.startswith("결정 인터뷰 400건"), r.stdout  # 질문 600(3 의 배수 아닌 i) − 회신 닫힘 200(1..299 중 질문) = 400
