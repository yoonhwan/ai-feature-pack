#!/usr/bin/env bash
# r851 ⓗ 변이 — 임시 사본(bin·kit/slack-mirror·tests · 그 안에서 git init·커밋)에서 한 곳씩 깨고 그 시험이 FAIL 하는지 본다(실 파일 수정 0 · 바이트코드 캐시 0).
#   ① 결론 문단 보호 삭제 → ⓐ · ② 신선도 게이트 삭제 → ⓒ · ③ 15개 상한 되살림 → ⓓ · ④ 발행 성공 조건 삭제 → ⓔ · ⑤ push 대상 main(r2) → ⓐ
#   r3(DA⑥ r1 반례): ⓡ1 브랜치 이름 검사 삭제 · ⓡ2 quotepath 끄기 삭제 · ⓡ3 뉴스 사본 브랜치 받기 삭제 · ⓡ4 표 블록 한정 삭제 · ⓡ5 정확 일치 → 포함 비교 · ⓡ6 모양 검사(+넓은 잡기) 삭제
#   r4(DA⑥ r2 반례 · 원천 단위 거부): ⓡ7 불일치 = 원천 전체 오류 → 불일치 줄 버림 · ⓡ7' 원천 오류 때 last-ok 기록 되살림
#   r5(DA⑥ r3 반례 · 쪽지함 꼬리 첫 줄 경계): ⓡ9 앞 1바이트 검사 삭제(무조건 첫 줄 버림)
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
B="$T/fable-team/harness/bin"
TEST="fable-team/harness/tests/scripts/test_ledger_fill_r851.py"
fail=0
pt() { (cd "$T" && PYTHONDONTWRITEBYTECODE=1 "$PY" -m pytest -q -p no:cacheprovider "$TEST" -k "$1" >/dev/null 2>&1); }
if pt "test_"; then echo "PASS 무변이 기준(전부)"; else echo "ERROR 무변이 기준 FAIL — 변이 판정 무효"; exit 1; fi
mutate() {  # <이름> <시험 -k> <파일> <옛 글자> <새 글자> [<파일> <옛> <새> …]
  local name="$1" k="$2"; shift 2
  local files=() f
  while [ $# -ge 3 ]; do
    f="$B/$1"; [ -f "$f.orig" ] || { cp "$f" "$f.orig"; files+=("$f"); }
    OLD="$2" NEW="$3" "$PY" -c 'import os,sys;p=sys.argv[1];s=open(p,encoding="utf-8").read();o=os.environ["OLD"];assert o in s,"변이 자리 없음: "+o;open(p,"w",encoding="utf-8").write(s.replace(o,os.environ["NEW"],1))' "$f" \
      || { echo "ERROR $name 변이 자리 없음"; fail=1; for f in "${files[@]}"; do mv "$f.orig" "$f"; done; return; }
    shift 3
  done
  find "$T" -name __pycache__ -type d -prune -exec rm -rf {} +
  if pt "$k"; then echo "SURVIVED $name"; fail=1; else echo "KILLED $name"; fi
  for f in "${files[@]}"; do mv "$f.orig" "$f"; done
}
mutate "①결론보호삭제" test_a_ ft_ledger_fill_tables.py 'return lines[:span[0]] + new + tail + lines[span[1]:]' \
  'return [ln for ln in lines[:span[0]] if not ln.startswith("**결론")] + new + tail + lines[span[1]:]'
mutate "②신선도게이트삭제" test_c_freshness ft_ledger_fill.py 'if mins is not None and mins <= int(os.environ.get("FT_LEDGER_FRESH_MIN", "60")):' 'if True:'
mutate "③15개상한되살림" test_d_ ft_ledger_fill_src.py 'return git(repo, "log", "--format=%h %s", f"{base}..{ref}").splitlines()' \
  'return git(repo, "log", "--format=%h %s", "-n", "15", f"{base}..{ref}").splitlines()'
mutate "④발행성공조건삭제" test_e_ ft_ledger_fill_tables.py 'if seen.get(k) and published_at and seen[k] < published_at:' 'if seen.get(k):'
mutate "⑤push대상을main으로(r2)" test_a_ ft_ledger_fill.py 'f"{sha}:refs/heads/{br}"' 'f"{sha}:refs/heads/main"'
mutate "ⓡ1브랜치이름검사삭제" test_r1_ ft_ledger_fill_src.py 'if not _BRANCH.fullmatch(name) or ".." in name or name.endswith((".lock", ".")):' 'if False:'
mutate "ⓡ2quotepath끄기삭제" test_r2_quotepath ft_ledger_fill_src.py 'GIT = ("git", "-c", "core.quotepath=off")' 'GIT = ("git",)'
mutate "ⓡ3뉴스사본브랜치받기삭제" test_r3_ ft_news_ledger.py '"fetch", "--quiet", "origin", "main", LEDGER_REFSPEC]' '"fetch", "--quiet", "origin", "main"]'
mutate "ⓡ4표블록한정삭제" test_r4_memo ft_ledger_fill.py 'tb._replace_table(ls, "## 3. 팀 작업", tb.team_work(s["cards"], s["notes"]))' \
  'tb._replace(ls, "## 3. 팀 작업", tb.team_work(s["cards"], s["notes"]))'
mutate "ⓡ5정확일치를포함비교로" test_r5_ ft_ledger_fill_tables.py 'if c.get("지금 상태", "").split("—", 1)[0].strip() not in CLOSED:' \
  'if not any(w in c.get("지금 상태", "") for w in CLOSED):'
mutate "ⓡ6모양검사삭제" test_r6_ \
  ft_ledger_fill_src.py 'raise FillError(f"질문 장부 모양 틀림: {p} (최상위·«open»·항목은 객체여야 함)")' 'pass' \
  ft_ledger_fill.py 'except Exception as e:  # noqa: BLE001 — 조용한 0 아님' 'except FillError as e:  # noqa: BLE001 — 조용한 0 아님'
mutate "ⓡ7불일치줄버림(걸러내기되살림)" test_r7 ft_ledger_fill_src.py \
  'raise FillError(f"{name} 꼴 틀림 — 줄 {at}: {str(raw)[:60]!r} (원천 전체 갱신 0 · 걸러내기 0)")' 'continue'
mutate "ⓡ7'원천오류때last-ok기록되살림" test_r7_ ft_ledger_fill.py '    if not errs:  # 표 하나라도 실패' '    if True:  # 표 하나라도 실패'
mutate "ⓡ9앞1바이트검사삭제(무조건첫줄버림)" test_r9 ft_ledger_fill_src.py 'cut = f.read(1) != b"\n"' 'cut = True'
exit "$fail"
