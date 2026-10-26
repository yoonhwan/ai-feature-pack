#!/usr/bin/env bash
# r907 변이 14종(r6) — 고친 줄 하나씩 끄면 맡은 시험이 빨강이어야 한다(되돌림 = 원본 복사 · cmp 확인).
# 실행: bash harness/evidence/r907/mutation.sh  (cwd = feature-pack/fable-team · PYTHONPATH=harness/bin:harness/kit/fable-team/bin)
set -u
T=harness/tests/scripts/test_r907_news_stale_head.py
mutate() {  # <이름> <파일> <원문> <바꿀 글> <시험 -k>
  local name="$1" f="$2" old="$3" new="$4" k="$5" bak rc
  bak="$(mktemp)"; cp "$f" "$bak"
  python3 - "$f" "$old" "$new" <<'PY' || { echo "$name: 원문 못 찾음"; cp "$bak" "$f"; rm -f "$bak"; return 1; }
import sys
from pathlib import Path
p, old, new = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text(encoding="utf-8")
assert s.count(old) == 1, s.count(old)
p.write_text(s.replace(old, new), encoding="utf-8")
PY
  timeout 400 python3.11 -m pytest "$T" -q -p no:cacheprovider -k "$k" > "/tmp/r907-mut-$$.txt" 2>&1; rc=$?
  cp "$bak" "$f"; rm -f "$bak"
  echo "$name: rc=$rc ($(grep -E 'passed|failed' "/tmp/r907-mut-$$.txt" | tail -1)) · $(grep '^FAILED' "/tmp/r907-mut-$$.txt" | sed 's/.*:://' | tr '\n' ' ')"
  rm -f "/tmp/r907-mut-$$.txt"
}
L=harness/bin/ft_news_ledger.py
H=harness/bin/ft_news_html.py
before="$(shasum "$L" "$H")"
mutate "M1 유한성 검사 끔 → ⓖ" "$L" 'if not math.isfinite(limit) or not limit >= 0:' 'if not limit >= 0:' "test_g_"
mutate "M2 판정 불가 게시 복귀 → ⓗ" "$H" '        return 1, "원장 ref fetch 실패"' '        return 0, "원장 ref fetch 실패"' "test_h_"
mutate "M3 커미터 이메일 판별 끔(채움 커밋도 키) → ⓙ'·ⓦ" "$H" '        if SHA40.fullmatch(sha) and email.strip() != f"{WHO}@byz.local":' '        if SHA40.fullmatch(sha):' "test_j_ or test_i_fill or test_w_fill_is"
mutate "M8 키 모름 base==cur 을 «변화 없음» 으로 복귀 → ⓦ" "$H" 'changed = blob != saved_blob if blob else True' 'changed = blob != saved_blob if blob else base != cur' "test_w_more"
mutate "M9 미래 시각 검사 끔(칸마다 따로 계산하던 옛 꼴) → ⓧ" "$H" '        if (at - now) > timedelta(minutes=1):  # 미래 시각 = 시계 뒤틀림/손상' '        if False:  # 미래 시각 검사 끔' "test_x_ or test_k_broken_or_future"
mutate "M10 ledger _git 시간 상한 끔 → ⓨ" "$L" 'encoding="utf-8", check=False, timeout=GIT_S)  # r907 r5 — 7초 룰(넘으면 RuntimeError' 'encoding="utf-8", check=False, timeout=None)  # r907 r5 — 7초 룰(넘으면 RuntimeError' "test_y_ledger_rev or test_y_run"
mutate "M11 ledger cat-file 시간 상한 끔 → ⓨ" "$L" 'capture_output=True, check=False, timeout=GIT_S).returncode != 0' 'capture_output=True, check=False, timeout=None).returncode != 0' "test_y_ledger_rev"
mutate "M4 최소 간격 끔 → ⓘ·ⓙ'" "$H" '    if not _gap_ok(last, now):  # r907 r2·r3' '    if False:  # r907 r2·r3' "test_i_fill or test_j_unknown"
mutate "M5 map_at 형 검사 끔 → ⓚ'" "$H" '        if k in data and not isinstance(data[k], str):' '        if False:' "test_k_garbage"
mutate "M6 틱 예외 잡기 끔 → ⓝ" "$H" '    except Exception as e:  # noqa: BLE001 — r907 r4: 어떤 예외든 «전파하지 않는다»' '    except ZeroDivisionError as e:  # noqa: BLE001 — r907 r4: 어떤 예외든 «전파하지 않는다»' "test_n_tick"
mutate "M7 run() 을 r3 꼴로(예외 잡기·finally 둘 다 끔 → 정지 감시 건너뜀) → ⓝ" "$L" '        rc, why = 1, "뉴스 틱 예외"
        try:
            rc, why = _run(root, state)
        except Exception as e:  # noqa: BLE001 — r907 r4: 어떤 예외든 정지 감시(check_stale)는 «항상» 부른다 · ERROR 1줄 + rc 1
            _error_once(os.environ.get("FT_NEWS_MODE") == "html", "뉴스 실행 예외 — 게시 중단(정지 감시는 계속)", f"{type(e).__name__}: {e}")
        finally:
            if interval_s() > 0:
                check_stale(root, state, news_now(), why)
        return rc' '        rc, why = _run(root, state)
        if interval_s() > 0:
            check_stale(root, state, news_now(), why)
        return rc' "test_n_run"
mutate "M12 시각 칸 기본값 required=False 복귀 → ⓩ1" "$H" 'since = lambda k, required=True:' 'since = lambda k, required=False:' "test_z1"
mutate "M13 git show 를 알림 try 안으로 복귀 → ⓩ2" "$L" '        ledger_text = _git(repo, "show", f"{cur}:{rel}")  # r907 r6 — try 밖: git 시간 초과·실패는 아래 판정 불가 갈래(게시 0 · 구간당 ERROR 1줄 · check_stale)로 간다
        try:
            notify(root, ledger_text, state)' '        try:
            notify(root, _git(repo, "show", f"{cur}:{rel}"), state)' "test_z2"
mutate "M14 ERROR 구간당 1줄 끔(매 틱 ERROR) → ⓩ2" "$L" '    if html and fail_announced():' '    if False and fail_announced():' "test_z2"
[ "$(shasum "$L" "$H")" = "$before" ] && echo "복원 확인: 두 파일 sha = 변이 전" || echo "복원 실패: sha 다름"
