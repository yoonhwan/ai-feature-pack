import re, sys, os
src, out = sys.argv[1], sys.argv[2]
L = open(src, encoding="utf-8").read().split("\n")
def R(a, b): return L[a-1:b]          # 1-based inclusive
def names_def(lines):
    return {m.group(1) for l in lines for m in [re.match(r"def (\w+)\(", l)] if m}
store_body = R(136, 168) + R(170, 320)
guard_body = R(322, 462)
ops_body = R(463, 623)
sd, gd = names_def(store_body), names_def(guard_body)
def used(body, defs): return sorted(n for n in defs if re.search(r"\b%s\b" % n, "\n".join(body)))
conf = ["# mbox.py 의 env 상수 — 위치와 무관한 값만(정본 자리·CANON 은 mbox.py 가 정한다) · 200줄 규칙 분리."] + R(42, 82)
store = ["# mbox.py 의 우편함 저장 계층(seq·레거시·본문·잠금) · CANON·_ROOT·_SEQCTR·SEQ_FLOOR 는 mbox.py 가 import 뒤 묶는다 · 200줄 규칙 분리.",
         "from mbox_conf import *", "CANON = _ROOT = _SEQCTR = SEQ_FLOOR = None   # mbox.py 가 묶는다"] + store_body
guard = ["# mbox.py 의 발신 가드(fan-out·속도·재발주·회신 면제)와 발신 사본 로그 · CANON·_GUARD 는 mbox.py 가 묶는다 · 200줄 규칙 분리.",
         "from mbox_conf import *", "from mbox_store import " + ", ".join(used(guard_body, sd)),
         "CANON = _GUARD = None   # mbox.py 가 묶는다(_GUARD = CANON/.mbox-guard.json)", "", ""] + guard_body
ops = ["# mbox.py 의 명령(send·relay·recv·peek) · CANON 은 mbox.py 가 묶는다 · 200줄 규칙 분리.",
       "from mbox_conf import *", "from mbox_store import " + ", ".join(used(ops_body, sd)),
       "from mbox_guard import " + ", ".join(used(ops_body, gd)),
       "CANON = None   # mbox.py 가 묶는다", "", ""] + ops_body
entry = R(1, 41) + ["import os, sys; sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))   # 모듈 = 이 파일의 «실제» 폴더 — 링크 폴더를 sys.path 에 넣고 import 해도 찾게(DA r1 Q2) · CANON 은 아래에서 링크 위치(abspath)로 정한다", "from mbox_conf import *"] + R(82, 135) + [""] + R(169, 169) + ["",
 "# 분리 모듈(같은 폴더 — 이 파일이 링크면 «실제» 폴더에서 import 된다).",
 "# ★정본 자리는 이 파일 위치(__file__)로만 정해 묶어 준다★ — 모듈 위치로 정하면 링크 설치(.claude/fable-team/bin)에서 .fable-team 조상이 없어 NO_MAILBOX_ROOT.",
 "import mbox_store, mbox_guard, mbox_ops",
 "for _m in (mbox_store, mbox_guard, mbox_ops):",
 "    _m.CANON = CANON",
 "mbox_store._ROOT, mbox_store._SEQCTR, mbox_store.SEQ_FLOOR = _ROOT, _SEQCTR, SEQ_FLOOR",
 "mbox_guard._GUARD = os.path.join(CANON, \".mbox-guard.json\")",
 "from mbox_store import _load, _save, _check_name, _next_seq          # mbox.<이름> 호환(시험)",
 "from mbox_guard import _guard_log, _reply_exempt, _guard_verdict, _guard_record",
 "from mbox_ops import send, relay, recv, peek", "", ""] + R(624, len(L))
for n, body in [("mbox.py", entry), ("mbox_conf.py", conf), ("mbox_store.py", store), ("mbox_guard.py", guard), ("mbox_ops.py", ops)]:
    open(os.path.join(out, n), "w", encoding="utf-8").write("\n".join(body) + ("" if body[-1] == "" else "\n"))
    print(n, len(body))
