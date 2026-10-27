#!/usr/bin/env bash
# r1005 변이 — 임시 사본(bin·tests · 그 안에서 git init·커밋)에서 한 곳씩 깨고 그 시험이 FAIL 하는지 본다(실 파일 수정 0 · 바이트코드 캐시 0).
#   ① «모름 = 통과» (참 셈에서 거짓만 빼기) → ⓒ 시험 FAIL · ② 사건 키 삭제(모든 실패 = 새 사건) → V2 FAIL
#   ⑬ ⓖ 예산을 호출마다 새로 재기(공유 t0 되돌림) → 반송 r5 시험 FAIL · ⑫ ⓖ «ls-remote 실패 = 참» 오판 → 반송 r4 세 번째 칸 FAIL(과거 로그 줄 셈) → 반송 r2 시험 FAIL · ⑨ JSON 오류를 기본값으로 되돌림 → 반송 r1 시험 2칸 FAIL · ③ «검증 불가» 를 복구로 읽기(열린 사건 닫기) → r1005 반례 1 시험 FAIL · ④ ⓘ 칸이 가드를 안 부르고 늘 정상 → ⓘ 재호출 시험 FAIL
#   ⑤ 꼬리 쓰기 실패를 삼킴 → r1005 반례 5 시험 FAIL · ⑥ 자체 오류 사건 닫기 삭제(재발 알림 0) → r1005 반례 4 시험 FAIL
#   ⑦ 발행본 읽기 예외를 OSError 로 안 받음 → r1005 반례 2 시험 FAIL · ⑧ 매거진 «~» 펼침 삭제 → r1005 반례 6 시험 FAIL
# 출력: 무변이 기준 PASS 1줄 + 변이마다 KILLED|SURVIVED 1줄 · 기준 PASS 이고 전부 KILLED = rc0
set -uo pipefail
H="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PY="${PYTHON:-python3.11}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/fable-team/harness/kit"
cp -R "$H/bin" "$H/tests" "$T/fable-team/harness/"
cp -R "$H/kit/slack-mirror" "$T/fable-team/harness/kit/"
find "$T" -name __pycache__ -type d -prune -exec rm -rf {} +
git -C "$T" init -q && git -C "$T" add -A && git -C "$T" -c user.name=m -c user.email=m@m commit -qm base || { echo "ERROR 임시 사본 git init 실패"; exit 1; }
TEST="fable-team/harness/tests/scripts/test_news_verify_r1005.py"
fail=0
pt() { (cd "$T" && PYTHONDONTWRITEBYTECODE=1 "$PY" -m pytest -q -p no:cacheprovider "$TEST" -k "$1" >/dev/null 2>&1); }
if pt "test_"; then echo "PASS 무변이 기준(전부)"; else echo "ERROR 무변이 기준 FAIL — 변이 판정 무효"; exit 1; fi
mutate() {  # <이름> <시험 -k> <파일> <옛 글자> <새 글자>
  local name="$1" k="$2" f="$T/fable-team/harness/$3"
  cp "$f" "$f.orig"
  OLD="$4" NEW="$5" "$PY" -c 'import os,sys;p=sys.argv[1];s=open(p,encoding="utf-8").read();o=os.environ["OLD"];assert o in s,"변이 자리 없음: "+o;open(p,"w",encoding="utf-8").write(s.replace(o,os.environ["NEW"],1))' "$f" \
    || { echo "ERROR $name 변이 자리 없음"; mv "$f.orig" "$f"; fail=1; return; }
  if pt "$k"; then echo "SURVIVED $name"; fail=1; else echo "KILLED $name"; fi
  mv "$f.orig" "$f"
}
mutate "① 모름 = 통과" "test_c_" bin/_news_verify.py 'if v == lib.PASS' 'if v != lib.FAIL'
mutate "② 모든 실패 = 새 사건(키 유지 삭제)" "test_v2_one_message" bin/_news_verify_book.py 'fresh = failing - open_cells' 'fresh = failing'
mutate "③ 검증 불가를 복구로 읽기" "test_r2_1_" bin/_news_verify_book.py 'still = {c for c in open_cells if c in failing or c in unknown}' 'still = set()'
mutate "④ ⓘ 칸이 가드를 안 부름(자체 판정)" "test_i_" bin/_news_verify_pub_cells.py 'why = check(text)' 'why = None'
mutate "⑤ 꼬리 쓰기 실패 삼킴" "test_r2_5_" bin/_news_verify.py 'return f"{body}: {type(e).__name__}: {e}"' 'return ""'
mutate "⑥ 자체 오류 사건 닫기 삭제" "test_r2_4_" bin/_news_verify.py '_save(st / "self-error.json", {})  # r1005 반례 4' '# r1005 반례 4'
mutate "⑦ 발행본 읽기 예외 안 받음" "test_r2_2_" bin/_news_verify.py '    except OSError as e:
        self_error(root, st, a.kind, f"발행본 못 읽음' '    except ValueError as e:
        self_error(root, st, a.kind, f"발행본 못 읽음'
mutate "⑨ JSON 오류 → {} (조용한 초기화)" "test_r1_" bin/_news_verify_book.py '        raise StateCorrupt(f"{f.name} — {type(e).__name__}") from e' '        return default'
mutate "⑬ 예산 공유 되돌림(호출마다 t0 새로)" "test_r5_1_" bin/_news_verify_pub_cells.py '        return need("ft_news_ledger", "_git_capped")(ctx.repo, t0, *a)' '        return need("ft_news_ledger", "_git_capped")(ctx.repo, time.monotonic(), *a)'
mutate "⑫ ls-remote 실패를 참으로" "test_r4_3" bin/_news_verify_pub_cells.py '        return UNAVAILABLE, f"ls-remote 실패' '        return PASS, f"ls-remote 실패'
mutate "⑧ 매거진 «~» 펼침 삭제" "test_r2_6_magazine_tilde_out_dir" kit/slack-mirror/magazine_from_news.sh '      HTML="$HOME${HTML#\~}"  # «~» → HOME · «~/x» → HOME/x' '      HTML="$HTML"'
[ "$fail" -eq 0 ] && echo "OK 전부 KILLED" || echo "FAIL 변이 남음"
exit "$fail"
