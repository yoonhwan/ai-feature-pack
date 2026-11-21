#!/usr/bin/env bash
# test_stall_human_wait_r2380.sh — r2380 K2·K2b·K3·K4: 정체 감시가 6시간 넘은 «오빠 대기» 를 «사람 대기 점검» 으로 세고(팀 master 1통), 줄이 풀려 지워지면 desk 에 «사람 대기 풀림» 1통을 보낸다.
#   본문 = tests/scripts/test_stall_human_wait_r2380.py (반례 ⑥~⑲ + ③b = 15 시험)
#   + 기준판(팩 origin/main) Red 대조: ⑥·⑧·⑫·⑬·⑮·⑯·⑰·⑱·③b FAIL · ⑦⑨⑩⑪⑭⑲ PASS
#   + 변이 M4b·M5~M13(사본 bin 한 곳 치환 → 그 시험이 FAIL → 복구 · 실 파일 무변경)
#   + 짝 사본(harness/bin ↔ kit) 바이트·실행 비트 동일 · 새 시험 모드 644
#   + 회귀 = 정체 감시 기존 시험 py STEPS=1(기본) · STEPS=0 이면 회귀 건너뜀
# 격리: 임시 리포(bare origin + 체크아웃)·가짜 명부·tmux·mbox·lint — 네트워크 0 · 실 루트 0 · 실 좌석 깨우기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; SC="$HERE/scripts"
PACK="$(git -C "$HERE" rev-parse --show-toplevel)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; t0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
lap() { echo "단계 $1 $((SECONDS-t0))초"; t0=$SECONDS; }
run_py() {  # $1=bin $2=시험 파일 [$3=-k]
  (ulimit -u 2000; cd "$SC" && R2380_BIN="$1" R2380_BASE_BIN="${BASE:-}" timeout 70 python3.11 -m pytest -q -p no:cacheprovider "$2" ${3:+-k "$3"} >"$T/py.log" 2>&1)
}

# ① 신판 green (반례 ⑥~⑲ · ③b)
run_py "$KIT" test_stall_human_wait_r2380.py; ck "신판 ⑥~⑲·③b $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?; lap 신판

# ② 기준판(팩 origin/main) — 새 갈래가 없으니 점검·풀림 시험은 FAIL, «지금 그대로» 시험은 PASS
mkdir -p "$T/base"; git -C "$PACK" archive origin/main feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin | tar -x -C "$T/base" 2>/dev/null
BASE="$T/base/feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin"
if [ -f "$BASE/ft_stall_scan.py" ]; then   # 한 번에 돌려 실패 목록만 본다(15회 재실행 0)
  (ulimit -u 2000; cd "$SC" && R2380_BIN="$BASE" R2380_BASE_BIN= timeout 140 python3.11 -m pytest -q -p no:cacheprovider --tb=no -rf test_stall_human_wait_r2380.py >"$T/base.log" 2>&1)
  got="$(grep -E '^FAILED' "$T/base.log" | sed -E 's/^FAILED [^ ]*::test_([a-z0-9]+)_.*/\1/' | sort | tr '\n' ' ')"
  want="$(printf '%s\n' c06 c08 c12 c13 c15 c16 c17 c18 c20 | sort | tr '\n' ' ')"
  [ "$got" = "$want" ]; ck "기준판 Red = c06 c08 c12 c13 c15 c16 c17 c18 c20 (실측: $got)" $?
  grep -qE '[0-9]+ passed' "$T/base.log"; ck "기준판 «그대로» 시험 PASS $(grep -Eo '[0-9]+ passed' "$T/base.log")" $?
else echo "WARN 기준판 없음(origin/main 에 팩 없음) — 대조 건너뜀"; fi
lap 기준판

# ③ 변이 — 사본 bin 한 곳을 무력화하면 그 시험이 FAIL 해야 한다(실 파일 치환 0 · 사본만)
cp -Rp "$KIT" "$T/bin"
sha_before="$(shasum "$TRK/ft_stall_detect.py" "$KIT/ft_stall_detect.py" "$KIT/ft_stall_scan.py" | awk '{print $1}' | tr '\n' ' ')"
mutate() {  # $1 이름 $2 파일 $3 원문(고정 문자열 · 1곳) $4 바꿀 글 $5 -k 시험
  cp -p "$KIT/$2" "$T/bin/$2"
  python3 -I - "$T/bin/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  run_py "$T/bin" test_stall_human_wait_r2380.py "$5"; [ $? -ne 0 ]; ck "변이 $1 → $5 FAIL" $?
  cp -p "$KIT/$2" "$T/bin/$2"
}
mutate "M4b detect 가 lint 스위치를 안 지움" ft_stall_detect.py '{k: x for k, x in os.environ.items() if k not in LINT_ENV_DROP}' 'os.environ' c20
mutate "M5 human 갈래 지움" ft_stall_detect.py '        ts = human_line(line)
        if ts is not None:
            return confirm_at(text), i, ts' '        ts = human_line(line)
        if False:
            return confirm_at(text), i, ts' c06
mutate "M6 나이 비교를 0 으로" ft_stall_scan.py 'if h["age"] < HUMAN_ALERT_S:' 'if h["age"] < 0:' c07
mutate "M7 같은 사건 1회 기록 지움" ft_stall_scan.py '                if key in self.human_rec:
                    continue' '                if False:
                    continue' c08
mutate "M8 blocked 보다 human 먼저" ft_stall_detect.py '        if any(_prereq(ln.removeprefix("- 선행:").strip(), stems, n).startswith("blocked:")' '        if False and any(_prereq(ln.removeprefix("- 선행:").strip(), stems, n).startswith("blocked:")' c09
mutate "M9 확인 줄 무시" ft_stall_detect.py 'cands = [x for x in (at, stamp) if x is not None]' 'cands = [x for x in (at,) if x is not None]' c10
mutate "M10 풀림 1통 지움" ft_stall_scan.py '            self.human_done.append({"key": key, "team": team, "card": card, "ts": str(rec.get("ts") or "")})' '            _ = 0' c12
mutate "M11 git 실패 = 경보로" ft_stall_detect.py '    if rc != 0:
        return None, f"git log rc={rc} {err[-40:]}"' '    if rc != 0:
        return 0.0, ""' c17
mutate "M12 트리 못 읽음 = 줄 없음" ft_stall_scan.py '                self.human_unread += 1' '                self.human_unread += 1
                seen[t["team"]] = {}' c15
mutate "M13 기록을 6시간 창에 지움" ft_stall_scan.py 'rec = raw.get("records") if isinstance(raw.get("records"), dict) else {}' 'rec = {k: v for k, v in (raw.get("records") or {}).items() if isinstance(v, dict) and isinstance(v.get("at"), (int, float)) and self.now - float(v["at"]) <= 6 * 3600}' c16
sha_after="$(shasum "$TRK/ft_stall_detect.py" "$KIT/ft_stall_detect.py" "$KIT/ft_stall_scan.py" | awk '{print $1}' | tr '\n' ' ')"
[ "$sha_before" = "$sha_after" ]; ck "변이 뒤 실 파일 무변경(사본만)" $?; lap 변이

# ④ 짝 사본·모드
for n in ft_stall_detect.py ft_stall_scan.py; do
  cmp -s "$TRK/$n" "$KIT/$n" && [ "$(stat -f %Lp "$TRK/$n")" = "$(stat -f %Lp "$KIT/$n")" ]; ck "짝 사본 $n" $?
done
for f in "$HERE/test_stall_human_wait_r2380.sh" "$SC/test_stall_human_wait_r2380.py"; do
  [ "$(stat -f %Lp "$f")" = 644 ]; ck "새 시험 모드 644 $(basename "$f")" $?
done
lap 짝

# ⑤ 회귀 — 정체 감시 기존 시험(신판 rc 0)
if [ "${STEPS:-1}" != 0 ]; then
  # r2380 이전부터 실패/멈춤인 시험은 넣지 않는다(실측 = test_stall_scan_heartbeat_desk_r1143 1 FAIL · test_stall_lead_alert_cron_r1152 3 FAIL · test_stall_scan_headline_age 70초 멈춤 — 기준판 bin 으로도 같은 값)
  for t in test_ft_stall_scan.py test_ft_stall_scan_off_roster.py test_stall_waiting_cards_ref_tree_r1330.py; do
    run_py "$KIT" "$t"; RC=$?; LAST="$(grep -Eo '[0-9]+ passed' "$T/py.log")"
    ck "회귀 $t $LAST" $RC
  done
  lap 회귀
fi
echo "FAIL=$fail"; [ "$fail" = 0 ]
