#!/usr/bin/env bash
# r892 ⓕ 변이(r3) — 임시 사본(bin·kit/slack-mirror·tests · 그 안에서 git init·커밋)에서 한 곳씩 깨고 그 시험이 FAIL 하는지 본다(실 파일 수정 0 · 바이트코드 캐시 0).
#   ① git 판 대신 디스크 훑기 되살림(하네스 카드 = $FT_HARNESS_ROOT 폴더 glob) → ⓙ(옮기는 중 카드 수) · ② 리포 하위 폴더 prefix 제거 → ⓛ(하위 폴더 하네스 루트)
#   (r1·r2 디스크 훑기 변이 ①~⑨ 는 그 코드가 삭제돼 없어짐 — mutation.txt·mutation-r2.txt 는 그 판의 기록)
#   --red: 변이 대신 base(origin/main) 의 bin 두 파일로 r892 시험 전체(빨강 기준 · FAIL 이 정상)
#   --red-r2: r2 판(b664c187 · 디스크 묶음 훑기)의 bin 두 파일로 r892 시험 전체(ⓙ 가 FAIL 이 정상)
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
TEST="fable-team/harness/tests/scripts/test_ledger_fill_disk_cards_r892.py"
pt() { (cd "$T" && PYTHONDONTWRITEBYTECODE=1 "$PY" -m pytest -q -p no:cacheprovider "$TEST" -k "$1" >/dev/null 2>&1); }
if [ "${1:-}" = "--red" ] || [ "${1:-}" = "--red-r2" ]; then
  ref=origin/main; [ "$1" = "--red-r2" ] && ref=b664c187
  for f in ft_ledger_fill_src.py ft_ledger_fill_tables.py; do
    git -C "$H" show "$ref:feature-pack/fable-team/harness/bin/$f" > "$B/$f" || { echo "ERROR $ref $f 못 읽음"; exit 1; }
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
mutate "①디스크훑기되살림" test_j_cards_moving ft_ledger_fill_src.py '        out.update(_ref_cards(*_harness_ref(hrels), since))' '        d = lambda rel, st: sorted((Path(os.environ["FT_HARNESS_ROOT"]) / rel.split("/", 1)[1] / "indices" / st).glob("*.md"))  # noqa: E731
        out.update({t: {"진행": [(p.stem, p.stem) for p in d(rel, "진행")], "대기": len(d(rel, "대기")), "착지": []} for t, rel in hrels.items()})'
mutate "②하위폴더prefix제거" test_l_subfolder ft_ledger_fill_src.py '{t: prefix + re.sub(' '{t: re.sub('
exit $fail
