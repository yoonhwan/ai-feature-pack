#!/usr/bin/env bash
# r870 ⓕ 변이 — 임시 사본(bin·kit/slack-mirror·tests · 그 안에서 git init·커밋)에서 한 곳씩 깨고 그 시험이 FAIL 하는지 본다(실 파일 수정 0 · 바이트코드 캐시 0).
#   ① (r3) 표 같음 판정(tb.same) 제거 → ⓐ · ⑩ (r3) 옛 «push 생략(같음)» 갈래 되살림(시험은 read_ref 를 경쟁 대역 C 로) → ⓐ2 · ⑪ (r4) «변화 없음» 반환을 '' 로 되돌림 → ⓐ3 · ② 재시도 무한(5회로 대역 — 진짜 무한은 시험이 끝나지 않음) → ⓑ · ③ 훅 건너뜀 제거 → ⓑ·ⓓ · ④ 같은 커밋 재사용 제거 → ⓒ
#   ⑤ 같은 원인 경고 낮춤 제거 → ⓒ · ⑥ _commit 시간 초과 잡기 제거 → ⓗ · ⑦ _has 시간 초과 잡기 제거 → ⓗ2 · ⑧ 크기 비례 상한 제거 → 1-b
#   ⑨ (r2) 생략 조건의 «사본 브랜치가 main 을 품음» 검사 제거 → ⓐ2(DA⑥ r1 반례)
#   --red: 변이 대신 base(origin/main) 의 bin 세 파일로 바꿔 r870 시험 전체를 돌린다(빨강 기준 · FAIL 이 정상)
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
TEST="fable-team/harness/tests/scripts/test_ledger_fill_r870.py"
pt() { (cd "$T" && PYTHONDONTWRITEBYTECODE=1 "$PY" -m pytest -q -p no:cacheprovider "$TEST" -k "$1" >/dev/null 2>&1); }
if [ "${1:-}" = "--red" ]; then
  for f in ft_ledger_fill.py ft_ledger_fill_src.py ft_news_html.py; do
    git -C "$H" show "origin/main:feature-pack/fable-team/harness/bin/$f" > "$B/$f" || { echo "ERROR base $f 못 읽음"; exit 1; }
  done
  (cd "$T" && PYTHONDONTWRITEBYTECODE=1 "$PY" -m pytest -q -p no:cacheprovider "$TEST" 2>&1 | grep -E "^(PASSED|FAILED)|passed|failed")
  exit 0
fi
fail=0
if pt "test_"; then echo "PASS 무변이 기준(전부)"; else echo "ERROR 무변이 기준 FAIL — 변이 판정 무효"; exit 1; fi
mutate() {  # <이름> <시험 -k> <파일> <옛 글자> <새 글자>
  local name="$1" k="$2" f="$B/$3"
  cp "$f" "$f.orig"
  OLD="$4" NEW="$5" "$PY" -c 'import os,sys;p=sys.argv[1];s=open(p,encoding="utf-8").read();o=os.environ["OLD"];assert o in s,"변이 자리 없음: "+o;open(p,"w",encoding="utf-8").write(s.replace(o,os.environ["NEW"],1))' "$f" \
    || { echo "ERROR $name 변이 자리 없음"; fail=1; mv "$f.orig" "$f"; return; }
  find "$T" -name __pycache__ -type d -prune -exec rm -rf {} +
  if pt "$k"; then echo "SURVIVED $name"; fail=1; else echo "KILLED $name"; fi
  mv "$f.orig" "$f"
}
mutate "①같음판정제거(r3 = tb.same)" test_a_ ft_ledger_fill.py '        if tb.same(new, text):' '        if False:'
mutate "⑩옛생략갈래되살림(r3)" test_a2_ ft_ledger_fill.py '        tree = _tree(repo, rel, base, new)
' '        tree = _tree(repo, rel, base, new)
        if push and tree == git(repo, "rev-parse", f"refs/remotes/origin/{br}^{{tree}}").strip() and src.read_ref(repo, ref) == f"refs/remotes/origin/{br}":
            print(f"FILL push 생략(같음) {br} {base[:10]}")
            return 0, ""
'
mutate "⑪변화없음반환빈칸(r4)" test_a3_ ft_ledger_fill.py 'return (1 if errs else 0), base  # r870 r4' 'return (1 if errs else 0), ""  # r870 r4'
mutate "②재시도무한(5회)" test_b_push_cap ft_ledger_fill.py 'for n in (1, 2):' 'for n in range(1, 6):'
mutate "③훅건너뜀제거" "test_b_push_cap or test_d_" ft_ledger_fill.py '"push", "--quiet", "--no-verify", "origin"' '"push", "--quiet", "origin"'
mutate "④같은커밋재사용제거" test_c_ ft_ledger_fill.py 'sha = _pending(st, tree, parents) or _commit(repo, tree, parents)' 'sha = _commit(repo, tree, parents)'
mutate "⑤같은원인경고제거" test_c_ ft_news_html.py '(LOG.warning if getattr(e, "repeat", False) else LOG.error)' 'LOG.error'
mutate "⑥commit시간초과잡기제거" test_h_ ft_ledger_fill.py '    except subprocess.TimeoutExpired as e:
        raise FillError(f"git {a[0]} 시간 초과({src.LOCAL_S:.0f}초)") from e
' ''
mutate "⑦has시간초과잡기제거" test_h2_ ft_ledger_fill_src.py 'except (OSError, subprocess.TimeoutExpired) as e:  # r870' 'except OSError as e:  # r870'
mutate "⑧크기비례상한제거" test_1b_ ft_ledger_fill_src.py '*(f"{rel}indices/완성/" for rel in on_ref.values()), timeout=cap)' '*(f"{rel}indices/완성/" for rel in on_ref.values()))'
exit $fail
