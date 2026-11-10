import sys
root = sys.argv[1]
def edit(p, reps):
    s = open(root + "/" + p, encoding="utf-8").read()
    for a, b in reps:
        assert s.count(a) == 1, (p, a, s.count(a)); s = s.replace(a, b)
    open(root + "/" + p, "w", encoding="utf-8").write(s)
MUT_PY = '''import glob, os, sys
d, t, r = sys.argv[1], sys.argv[2], sys.argv[3]
hit = [p for p in sorted(glob.glob(os.path.join(d, "mbox*.py"))) if t in open(p, encoding="utf-8").read()]
assert len(hit) == 1, "변이 대상 없음/중복: %s %s" % (t, hit)
s = open(hit[0], encoding="utf-8").read()
open(hit[0], "w", encoding="utf-8").write(s.replace(t, r, 1))'''
edit("tests/harness/test_mbox_inbox_notify_reply_rate.sh", [
 ('"$REPO/tools/comm-canonical/mbox_doorbell.sh" "$REPO/tools/comm-canonical/mbox.py" "$C/"', '"$REPO/tools/comm-canonical/mbox_doorbell.sh" "$REPO/tools/comm-canonical/"mbox*.py "$C/"'),
 ('import mbox\nfx = "fx5#1"', 'import mbox, mbox_ops\nfx = "fx5#1"'),
 ('orig = mbox._reply_exempt\nmbox._reply_exempt = lambda', 'orig = mbox_ops._reply_exempt\nmbox_ops._reply_exempt = lambda'),
 ('"$REPO/tools/comm-canonical/mbox_doorbell.sh" "$MC/"; cp "$BIN"', '"$REPO/tools/comm-canonical/mbox_doorbell.sh" "$REPO/tools/comm-canonical/"mbox*.py "$MC/"; cp "$BIN"'),
 ('''  python3 - "$REPO/tools/comm-canonical/mbox.py" "$MC/mbox.py" "$2" "$3" <<'PYEOF'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert sys.argv[3] in s, "변이 대상 없음"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1))
PYEOF''', '''  python3 - "$MC" "$2" "$3" <<'PYEOF'
''' + MUT_PY + '''
PYEOF'''),
])
edit("tests/harness/test_inbox.sh", [
 ('"$REPO/tools/comm-canonical/mbox_doorbell.sh" "$REPO/tools/comm-canonical/mbox.py" "$C/"', '"$REPO/tools/comm-canonical/mbox_doorbell.sh" "$REPO/tools/comm-canonical/"mbox*.py "$C/"'),
])
edit("tests/harness/test_mbox_reply_exempt_cap.sh", [
 ('import mbox\n', 'import mbox, mbox_guard\n'),
 ('    mbox.time = types.SimpleNamespace', '    mbox_guard.time = types.SimpleNamespace'),
 ('    mbox.time.time = lambda', '    mbox_guard.time.time = lambda'),
 ('cp "$py" "$c/mbox.py"', 'cp "$(dirname "$py")"/mbox*.py "$c/"'),
 ('''mut() {  # <원문> <대체> → $T/mut.py
  python3 - "$SRC" "$T/mut.py" "$1" "$2" <<'PYEOF'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert sys.argv[3] in s, "변이 대상 없음: " + sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1))
PYEOF
}''', '''mut() {  # <원문> <대체> → $T/mut/mbox.py (모듈 전부 복사 뒤 대상 글자가 든 모듈 하나만 변이)
  mkdir -p "$T/mut"; cp "$(dirname "$SRC")"/mbox*.py "$T/mut/"
  python3 - "$T/mut" "$1" "$2" <<'PYEOF'
''' + MUT_PY + '''
PYEOF
}'''),
 ('r="$(run "$T/mut.py" a', 'r="$(run "$T/mut/mbox.py" a'),
 ('r="$(run "$T/mut.py" cap', 'r="$(run "$T/mut/mbox.py" cap'),
])
print("patched")
