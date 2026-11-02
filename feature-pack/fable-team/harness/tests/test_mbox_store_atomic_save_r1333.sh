#!/usr/bin/env bash
# test_mbox_store_atomic_save_r1333.sh — 쪽지 큐 _save 원자 바꿔 끼우기(r1333 · 계약 A1~A4 · 반례 C1~C4 · 변이 W1~W3).
# 시나리오: 쓰는 프로세스(_save 반복)와 잠금 없이 읽는 프로세스가 동시에 돌 때 읽기가 반쪽 파일을 보면 FAIL.
# 정본 comm 을 임시 폴더에 복사해 돈다 — 실 큐 0 · 네트워크 0 · 자기 재호출 0 · 고정 sleep 0 · 반복은 수(시간 아님).
# W1(제자리 쓰기) = 기준판(origin/main)과 같은 꼴이다. cwd 무관(절대 경로만).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/.."
SRC="${R1333_COMM_SRC:-$REPO/comm}"   # 기준판 대조용 덮어쓰기(origin/main 사본 폴더)
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }

cat > "$T/drv.py" <<'PY'
import json, os, stat, sys
cdir, mode, qdir = sys.argv[1], sys.argv[2], sys.argv[3]
N, W, R = 400, 300, 600
sys.path.insert(0, cdir)
import mbox_store as s
BODY = "한글 본문 쪽지 " * 90
def rows(n=N): return [{"seq": i, "body": BODY + str(i)} for i in range(1, n + 1)]
def tmps(): return [x for x in os.listdir(qdir) if x.startswith(".mailbox.jsonl.tmp")]
p = os.path.join(qdir, "mailbox.jsonl")
if mode == "seed":
    s._save(qdir, rows())
elif mode == "writer":
    for _ in range(W): s._save(qdir, rows())
elif mode == "reader":
    badn = 0
    for _ in range(R):
        cnt = 0
        try:
            for ln in open(p, encoding="utf-8"):
                if ln.strip(): cnt += 1
        except UnicodeDecodeError:
            badn += 1; continue
        if cnt != N: badn += 1
    print("BAD", badn); sys.exit(1 if badn else 0)
elif mode in ("c2-0644", "c2-0600"):
    want = int(mode[3:], 8)
    s._save(qdir, rows(3)); os.chmod(p, want); s._save(qdir, rows(5))
    st = os.lstat(p)
    good = stat.S_ISREG(st.st_mode) and (st.st_mode & 0o777) == want and not tmps()
    print("OK" if good else "BAD mode=%o reg=%s tmps=%s" % (st.st_mode & 0o777, stat.S_ISREG(st.st_mode), tmps()))
    sys.exit(0 if good else 1)
elif mode == "c3":
    s._save(qdir, rows(4)); before = open(p, "rb").read()
    real, calls = json.dumps, [0]
    def boom(*a, **k):
        calls[0] += 1
        if calls[0] == 3: raise RuntimeError("r1333 injected")
        return real(*a, **k)
    json.dumps = boom
    raised = False
    try: s._save(qdir, rows(6))
    except RuntimeError: raised = True
    finally: json.dumps = real
    good = raised and open(p, "rb").read() == before and not tmps()
    print("OK" if good else "BAD raised=%s same=%s tmps=%s" % (raised, open(p, "rb").read() == before, tmps()))
    sys.exit(0 if good else 1)
elif mode == "c4":
    s._save(qdir, rows(2))
    st = os.lstat(p)
    good = stat.S_ISREG(st.st_mode) and (st.st_mode & 0o777) == 0o644 and not tmps()
    print("OK" if good else "BAD mode=%o" % (st.st_mode & 0o777)); sys.exit(0 if good else 1)
PY

# suite <comm 폴더> <꼬리표> — C1~C4 를 돌려 실패 수를 SUITE_FAILS 에 둔다.
suite() {
  local cd="$1" tag="$2" q t0 f=0 r
  q="$(mktemp -d "$T/q.XXXXXX")"; t0=$SECONDS
  python3 "$T/drv.py" "$cd" seed "$q" || f=$((f+1))
  python3 "$T/drv.py" "$cd" writer "$q" & local wp=$!
  python3 "$T/drv.py" "$cd" reader "$q" > "$T/reader.out" 2>&1; r=$?
  wait "$wp" || f=$((f+1))
  [ "$r" -eq 0 ] && echo "  [$tag] C1 ok" || { echo "  [$tag] C1 $(cat "$T/reader.out")"; f=$((f+1)); }
  echo "  [$tag] C1 ${SECONDS}-${t0} 초 ($((SECONDS-t0))s)" >/dev/null
  for m in c2-0644 c2-0600 c3 c4; do
    q="$(mktemp -d "$T/q.XXXXXX")"
    if python3 "$T/drv.py" "$cd" "$m" "$q" > "$T/o.out" 2>&1; then echo "  [$tag] $m ok"
    else echo "  [$tag] $m $(tail -1 "$T/o.out")"; f=$((f+1)); fi
  done
  echo "  [$tag] 단계 합계 $((SECONDS-t0))초"
  SUITE_FAILS=$f
}

# 변이 사본 만들기 — mutate <꼬리표> <python 치환 식>
mutant() {
  local d="$T/m-$1"; mkdir -p "$d"; cp "$SRC"/*.py "$d"/
  python3 - "$d/mbox_store.py" "$1" <<'PY'
import re, sys
p, w = sys.argv[1], sys.argv[2]
t = open(p, encoding="utf-8").read()
if w == "W1":   # 제자리 쓰기(기준판 꼴)
    new = ('def _save(d, rows):\n    rows.sort(key=lambda r: r["seq"])\n'
           '    with open(_mbox(d), "w", encoding="utf-8") as f:\n        for r in rows:\n'
           '            f.write(json.dumps(r, ensure_ascii=False) + "\\n")\n\n\n')
    t2 = re.sub(r"def _save\(d, rows\):.*?(?=def _locked)", lambda m: new, t, flags=re.S)
elif w == "W2": t2 = t.replace("        os.chmod(tmp, mode)\n", "")
elif w == "W3": t2 = t.replace("if os.path.exists(tmp): os.unlink(tmp)", "pass")
assert t2 != t, "mutation not applied"
open(p, "w", encoding="utf-8").write(t2)
PY
}

echo "== green (현재 판)"; suite "$SRC" green
[ "$SUITE_FAILS" -eq 0 ] && ok "green C1~C4 전부 통과" || bad "green 실패 $SUITE_FAILS"
for w in W1 W2 W3; do
  echo "== 변이 $w"; mutant "$w"; suite "$T/m-$w" "$w"
  [ "$SUITE_FAILS" -ge 1 ] && ok "$w 가 시험에 잡힘(FAIL $SUITE_FAILS)" || bad "$w 가 안 잡힘"
done
echo "총 ${SECONDS}초 · 실패 $fail"
[ "$fail" -eq 0 ]
