#!/usr/bin/env bash
# test_goal_receipt_drafted_rebind_r1031.sh — r1031: 초안 모드에서 같은 묶음 id(골표 sha10·run)의 «drafted» 영수증을
#   다음 틱 본문으로 다시 결속해 «같은 id 다른 본문» 거절(발행 0 · 초안 파일 0)을 없앤다 — ft_goal_receipt.begin 1줄.
#   r2(반송 REVORK-r1031-r2-total-rebind): 판 수가 바뀝어도(8→9) begin 이 total 도 이번 판으로 다시 결속한다.
# 칸 = 계약 ①~⑥ (FT_TEST_ONLY 로 그 칸만 · 변이는 그 칸만 — 하드 룰 22).
# 격리: 임시 상태 폴더의 영수증 파일만 쓴다(시험 픽스처) · 실 .fable-team/state·실 redis·실 슬랙 미접촉.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib/test_only.sh"                                    # r1026: FT_TEST_ONLY 로 «그 칸만»
BIN="${FT_RECEIPT_BIN:-$HERE/../kit/fable-team/bin}"          # 변이 사본을 넣어 이 시험 자체를 다시 돌릴 자리
PY="$BIN/ft_goal_receipt.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
OUT="$T/out"; : > "$OUT"
fail=0

cat > "$T/rec.py" <<'PY'
import importlib.util
import json
import os
import sys
import time
import traceback
from pathlib import Path

SHA, RUN = "a1b2c3d4e5", "202610271538"          # 골표 sha10 · run 12자리(실사건 17:20 꼴)
OTHER = "옛 둘째 판 본문"                          # 지난 틱이 검증했던 본문(해시가 다르다)
MSG_SAME_ID = "같은 묶음 id(골표 sha10·run)인데 검증한 판 본문과 다르다"
MSG_COMPLETE = "이미 완료된 묶음이다 — 같은 묶음 id 재발행 거절"
MSG_ALREADY_OUT = "판번호 2/2 가 범위 밖이거나 이미 나간 판이다"
GUARD = 'if rec.get("status") == "drafted"'      # 변이 = 이 줄이 시작하는 블록 전체 삭제
TOTAL_REBIND = 'rec["total"] = len(parts)'       # r2 변이 = 이 줄만 삭제
MODS = {}
FAILS = 0


def mod(path):
    if path not in MODS:
        spec = importlib.util.spec_from_file_location(f"ft_goal_receipt_r1031_{len(MODS)}", path)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        MODS[path] = m
    return MODS[path]


r = mod(os.environ["FT_REC"])


def chk(name, cond, detail=""):
    global FAILS
    if cond:
        print(f"PASS {name}")
    else:
        FAILS += 1
        print(f"FAIL {name}" + (f" — {detail}" if detail else ""))


def parts(b2="다음 틱 본문"):
    return ["1/2 첫 판 본문", f"골표 {SHA}·{RUN} (2/2) {b2}"]


def parts9():                                      # 실사건 꼴 = 9판(묶음 표지 "(n/9)")
    return ["1/9 첫 판 본문"] + [f"골표 {SHA}·{RUN} ({n}/9) 판{n} 본문" for n in range(2, 10)]


def hashes_of(ps):
    return {str(n): r.digest(ps[n - 1]) for n in range(2, len(ps) + 1)}


def drafted_block(lines):                          # GUARD 가 시작하는 if 블록의 (start, end) — 들여쓰기 8칸 연속 줄
    hit = [i for i, ln in enumerate(lines) if GUARD in ln]
    if len(hit) != 1:
        return None
    s, e = hit[0], hit[0] + 1
    while e < len(lines) and lines[e].strip() and lines[e].startswith("        "):
        e += 1
    return s, e


def _rec(state):
    return Path(state) / "goal-bundle" / f"{SHA}-{RUN}.json"


def put(state, status, hashes, done, total=2):
    f = _rec(state)
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps({"sha": SHA, "run": RUN, "total": total, "status": status,
                             "done": done, "hashes": hashes, "reason": ""}), encoding="utf-8")


def get(state):
    f = _rec(state)
    return json.loads(f.read_text(encoding="utf-8")) if f.exists() else {}


def token(module, body):
    return module.TOKEN.search(module.first(body))


def case_a(state):                                 # ① drafted + 다른 본문 → begin 빈 글 · hashes 새 본문 · done·total 그대로
    p = parts()
    for done in ([], [2]):
        put(state, "drafted", {"2": r.digest(OTHER)}, done)
        why = r.begin(Path(state), p)
        rec = get(state)
        chk(f"ⓐ drafted done={done} + 다른 본문 → begin 빈 글(통과)", why == "", why)
        chk(f"ⓐ drafted done={done} 저장된 hashes = 새 본문", rec.get("hashes") == {"2": r.digest(p[1])}, rec.get("hashes"))
        chk(f"ⓐ drafted done={done} total·done 그대로", rec.get("total") == 2 and rec.get("done") == done,
            f"total={rec.get('total')} done={rec.get('done')}")


def case_b(state):                                 # ② pending·partial·failed + 다른 본문 → 지금 거절 문구 그대로(발행 모드 보호)
    p = parts()
    for status, done in (("pending", []), ("partial", [2]), ("failed", [])):
        put(state, status, {"2": r.digest(OTHER)}, done)
        why = r.begin(Path(state), p)
        rec = get(state)
        chk(f"ⓑ {status} + 다른 본문 → 거절 문구 그대로", why == MSG_SAME_ID, why)
        chk(f"ⓑ {status} 영수증 안 바뀜(hashes·status)", rec.get("hashes") == {"2": r.digest(OTHER)} and rec.get("status") == status,
            f"{rec.get('status')} {rec.get('hashes')}")


def case_c(state):                                 # ③ complete → «이미 완료» 거절 · 없음 → 새 영수증
    p = parts()
    put(state, "complete", {"2": r.digest(OTHER)}, [2])
    why = r.begin(Path(state), p)
    chk("ⓒ complete → «이미 완료» 거절 그대로", why == MSG_COMPLETE, why)
    chk("ⓒ complete 영수증 그대로", get(state).get("status") == "complete")
    fresh = Path(state) / "fresh"
    why = r.begin(fresh, p)
    rec = get(fresh)
    chk("ⓒ 영수증 없음 → 새 영수증(빈 글 · pending · done=[])",
        why == "" and rec.get("status") == "pending" and rec.get("done") == [] and rec.get("total") == 2,
        why or f"{rec.get('status')} {rec.get('done')}")
    chk("ⓒ 새 영수증 hashes = 이번 본문", rec.get("hashes") == {"2": r.digest(p[1])}, rec.get("hashes"))


def case_d(state):                                 # ④ 다시 결속 뒤 done 에 있는 번호는 check_part 가 «이미 나간 판» 으로 막음
    p = parts()
    put(state, "drafted", {"2": r.digest(OTHER)}, [2])
    why = r.begin(Path(state), p)
    chk("ⓓ drafted 다시 결속 통과", why == "", why)
    rec = get(state)
    chk("ⓓ done 목록 그대로([2])", rec.get("done") == [2], rec.get("done"))
    blocked = r.check_part(Path(state), p[1], 2, 2, token(r, p[1]))
    chk("ⓓ done 번호는 check_part 가 «이미 나간 판» 으로 막음", blocked == MSG_ALREADY_OUT, blocked)


def case_e(state):                                 # ⑤ 변이 «drafted 다시 결속 블록 삭제» → ⓐ 가 FAIL
    src = Path(os.environ["FT_REC"]).read_text(encoding="utf-8")
    lines = src.splitlines(True)
    blk = drafted_block(lines)
    if not blk or 'rec["hashes"] = hashes' not in "".join(lines[blk[0]:blk[1]]):
        chk("ⓔ 변이 적용(다시 결속 블록 찾기)", False, f"블록 {blk}")
        return
    mut = Path(state).parent / "mut" / "ft_goal_receipt.py"
    mut.parent.mkdir(parents=True, exist_ok=True)
    mut.write_text("".join(ln for i, ln in enumerate(lines) if not blk[0] <= i < blk[1]), encoding="utf-8")
    m = mod(str(mut))
    chk("ⓔ 변이 사본 = 다시 결속 0", GUARD not in mut.read_text(encoding="utf-8"))
    p = parts()
    st = Path(state)
    put(st, "drafted", {"2": m.digest(OTHER)}, [])
    why = m.begin(st, p)
    chk("ⓔ 변이 → ⓐ 시나리오가 FAIL(같은 id 다른 본문 거절)", why == MSG_SAME_ID, why or "빈 글 = 변이 미검출")


def case_f(state):                                 # ⑥ drafted total 8 + 이번 판 9 → begin 통과 · 저장 total 9 · (9/9) 발행 가능
    p = parts9()
    put(state, "drafted", {str(n): r.digest(f"옛 {n} 판") for n in range(2, 9)}, [], total=8)
    why = r.begin(Path(state), p)
    rec = get(state)
    chk("ⓕ drafted total 8 + 이번 판 9 → begin 빈 글(통과)", why == "", why)
    chk("ⓕ 저장 total = 9(이번 판 수)", rec.get("total") == 9, rec.get("total"))
    chk("ⓕ 저장 hashes = 9판 본문", rec.get("hashes") == hashes_of(p), rec.get("hashes"))
    out = r.check_part(Path(state), p[8], 9, 9, token(r, p[8]))
    chk("ⓕ 다시 결속 뒤 (9/9) check_part 빈 글", out == "", out)
    dump = Path(state) / "f-done"
    put(dump, "drafted", {str(n): r.digest(f"옛 {n} 판") for n in range(2, 9)}, [2], total=8)
    why = r.begin(dump, p)
    blocked = r.check_part(dump, p[1], 2, 9, token(r, p[1]))
    chk("ⓕ done 에 2 있음 → begin 통과 · (2/9) 는 «이미 나간 판» 그대로",
        why == "" and blocked == "판번호 2/9 가 범위 밖이거나 이미 나간 판이다", f"{why} / {blocked}")
    chk("ⓕ done 목록 그대로([2])", get(dump).get("done") == [2], get(dump).get("done"))


def case_g(state):                                 # 변이 «total 다시 결속 줄 삭제» → ⓕ 가 FAIL
    lines = Path(os.environ["FT_REC"]).read_text(encoding="utf-8").splitlines(True)
    hit = [i for i, ln in enumerate(lines) if TOTAL_REBIND in ln]
    if len(hit) != 1 or hit[0] == 0 or 'rec["hashes"] = hashes' not in lines[hit[0] - 1]:
        chk("ⓖ 변이 적용(total 다시 결속 줄 찾기)", False, f"줄 {hit}")
        return
    mut = Path(state).parent / "mut-total" / "ft_goal_receipt.py"
    mut.parent.mkdir(parents=True, exist_ok=True)
    mut.write_text("".join(ln for i, ln in enumerate(lines) if i != hit[0]), encoding="utf-8")
    m = mod(str(mut))
    chk("ⓖ 변이 사본 = total 다시 결속 0", TOTAL_REBIND not in mut.read_text(encoding="utf-8"))
    p, st = parts9(), Path(state)
    put(st, "drafted", {str(n): m.digest(f"옛 {n} 판") for n in range(2, 9)}, [], total=8)
    why = m.begin(st, p)
    rec = get(st)
    blocked = m.check_part(st, p[8], 9, 9, m.TOKEN.search(m.first(p[8])))
    chk("ⓖ 변이 → ⓕ 시나리오가 FAIL(저장 total 8 그대로 · (9/9) 총수 불일치)",
        not (why == "" and rec.get("total") == 9 and blocked == ""),
        f"total={rec.get('total')} check_part={blocked!r}")


CASES = {"ⓐ": case_a, "ⓑ": case_b, "ⓒ": case_c, "ⓓ": case_d, "변이-no-rebind": case_e,
         "ⓕ": case_f, "변이-total": case_g}
case, state = sys.argv[1], sys.argv[2]
t0 = time.time()
try:
    CASES[case](state)
except Exception:                                   # 시험 스크립트 자체가 죽으면 «0 FAIL = 통과» 로 새지 않게
    FAILS += 1
    print(f"FAIL {case} — 시험 예외")
    traceback.print_exc()
print(f"#sec {case} {time.time() - t0:.3f}")
sys.exit(min(FAILS, 120))
PY

run_case() {                                        # $1 = 칸 이름 · 판정 줄이 없으면 그것도 FAIL
  local out rc
  out="$(FT_REC="$PY" python3 "$T/rec.py" "$1" "$T/state/$1" 2>&1)"; rc=$?
  printf '%s\n' "$out" >> "$OUT"
  if ! printf '%s\n' "$out" | grep -q '^\(PASS\|FAIL\) '; then
    printf 'FAIL %s — 판정 줄 없음(rc=%s)\n' "$1" "$rc" >> "$OUT"; fail=$((fail + 1)); return
  fi
  fail=$((fail + rc))
}

t_all0="$(python3 -c 'import time;print(time.time())')"
ft_only ⓐ && run_case ⓐ
ft_only ⓑ && run_case ⓑ
ft_only ⓒ && run_case ⓒ
ft_only ⓓ && run_case ⓓ
ft_only 변이-no-rebind && run_case 변이-no-rebind
ft_only ⓕ && run_case ⓕ
ft_only 변이-total && run_case 변이-total
t_all1="$(python3 -c 'import time;print(time.time())')"

sum_line="$(grep '^#sec ' "$OUT" | awk '{printf "%s=%ss ", $2, $3}' | sed 's/ $//')"
printf '%s\n' "# r1031 요약: 단계별 초 ${sum_line} 합=$(python3 -c "print(f'{$t_all1 - $t_all0:.3f}s')")"
grep -v '^#sec ' "$OUT" || true

ft_only_report || { [ "$fail" -eq 0 ] || echo "fail=$fail"; exit 1; }
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "fail=$fail"; fi
exit "$fail"
