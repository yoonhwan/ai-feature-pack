#!/usr/bin/env python3
"""r1974 — 골 재조정이 앞 회차 행을 «번호» 가 아니라 «같은 골(goal_hash)» 로 찾는다. 반례 ①~④(카드 동결) + 보고서 «번호 이동» 칸.
격리: 순수 함수만(_compare · _report) · git·우편함·state 0 · sleep 0.
변이용: env R1974_SRC = 다른 harness 폴더(bin 을 거기서 import 한다)."""
import os
import sys
from pathlib import Path

H = Path(os.environ.get("R1974_SRC") or Path(__file__).resolve().parent.parent)
sys.path.insert(0, str(H / "bin"))
import ft_goal_readjust as gr  # noqa: E402
import ft_goal_readjust_measure as m  # noqa: E402

FAIL = []


def ck(name, cond, info=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f" :: {str(info)[:400]}"))
    FAIL.extend([] if cond else [name])


def row(n, h, cards=0, ev="-", led="L", age=30.0):
    return {"n": n, "goal12": f"골{h}", "goal_hash": h, "team": "harness", "ledger_row_hash": led, "ledger_row_head": "",
            "ledger_closed": False, "cards_added": cards, "evidence": ev, "row_age_h": age, "unknown": []}


def run(base, now):
    for r in now:
        m._compare(r, base, False, set())
    return {r["goal_hash"]: r for r in now}


# 앞 회차 6골 · a 행은 원장 행이 바뀌어 «움직임» · 나머지 «변화 0»
BASE = [row(i, h, led=("L0" if h == "a" else "L")) for i, h in enumerate("abcdef", 1)]

# ① 맨 위에 2골 추가(번호 1~6 → 3~8) · 옛 6골 그대로
got = run(BASE, [row(1, "x"), row(2, "y")] + [row(i, h) for i, h in enumerate("abcdef", 3)])
ck("① 새 2골 = «확인 불가»", got["x"]["label"] == got["y"]["label"] == "확인 불가", got)
ck("① 옛 a = «움직임»(원장 행 변화를 같은 골과 비교)", got["a"]["label"] == "움직임", got["a"])
ck("① 옛 b~f = «변화 0(30시간)» · 확인 불가 0", all(got[h]["label"] == "변화 0(30시간)" for h in "bcdef"), got)
ck("① 번호 이동 = 1→3 · 6→8 · 새 골은 빈칸", got["a"]["moved"] == "1→3" and got["f"]["moved"] == "6→8" and got["x"]["moved"] == "", got)

# ② 순서만 바꿈
got = run(BASE, [row(i, h) for i, h in enumerate("fedcba", 1)])
ck("② 순서만 바꿈 → 확인 불가 0", all(r["label"] != "확인 불가" for r in got.values()), got)
ck("② 증거 변화 0(같은 골 증거와 비교)", not any(r["evidence_changed"] for r in got.values()), got)

# ③ 골 문구 바뀜(c → c2) · 번호 그대로
got = run(BASE, [row(i, h) for i, h in enumerate(["a", "b", "c2", "d", "e", "f"], 1)])
ck("③ 바뀐 행만 «확인 불가»", got["c2"]["label"] == "확인 불가" and sum(r["label"] == "확인 불가" for r in got.values()) == 1, got)
ck("③ 번호 그대로 = 번호 이동 빈칸", all(r["moved"] == "" for r in got.values()), got)

# ④ 같은 hash 2행 → 번호 같은 쪽(증거가 다르다)
base4 = [row(1, "z", ev="A"), row(2, "z", ev="B")]
r2 = row(2, "z", ev="B")
m._compare(r2, base4, False, set())
ck("④ 같은 hash 2행 → 번호 같은 쪽(증거 B = 변화 0)", not r2["evidence_changed"] and r2["label"] == "변화 0(30시간)", r2)
r3 = row(3, "z", ev="B")
m._compare(r3, base4, False, set())
ck("④ 같은 hash 2행 · 번호 같은 쪽 없음 → «확인 불가»", r3["label"] == "확인 불가", r3)

# 기준 회차(첫 회차) · stale(r702 번호 기준) 은 그대로
r = row(1, "a")
m._compare(r, [], True, set())
ck("첫 회차 = «기준»", r["label"] == "기준", r)
r = row(3, "a")
m._compare(r, BASE, False, {3})
ck("stale 입력 = 이번 번호 기준 «확인 불가»", r["label"] == "확인 불가", r)

# 보고서 «번호 이동» 칸
rows = list(run(BASE, [row(1, "x")] + [row(i, h) for i, h in enumerate("abcdef", 2)]).values())
rec = {"run": "20261114-2", "attempt": 1, "status": "OK", "started": "-", "baseline": None, "baseline_reason": "", "request": "",
       "inputs": {}, "rows": rows, "alarms": [],
       "facts": {"close_candidates": [], "goal_files_outside_canon": [], "unassigned_cards": [], "stale_numbered_cards": [], "open_cards": {}}}
text = gr._report(rec, 0)
ck("보고서 머리에 «번호 이동» 칸", "| 번호 이동 |" in text, text[:600])
ck("보고서 행에 1→2 · 새 골은 «-»", "| 1→2 |" in text and any(ln.startswith("| 1 | 골x") and ln.endswith("| - |") for ln in text.splitlines()), text)

print(f"== r1974: FAIL {len(FAIL)}")
sys.exit(1 if FAIL else 0)
