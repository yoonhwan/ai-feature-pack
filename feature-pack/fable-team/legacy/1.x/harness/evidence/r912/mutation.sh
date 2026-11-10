#!/usr/bin/env bash
# r912 r3 변이 — 임시 사본(bin·comm·tests·kit·skill · 그 안에서 git init)에서 한 곳씩 깨고 그 시험이 FAIL 하는지 본다.
#   ① 사람 보존 끔(HUMAN 등급 = 시스템 등급)          → shell ⓐ 빨강
#   ② 넘침 ERROR 끔(if overflow: → False)             → shell ⓑ 빨강
#   ③ 머리 우선 복귀(자동 도구의 [HIL] = 사람)        → shell ⓖ 빨강  (DA⑥ 반례 2 의 재발)
#   ④ kit 자르기 옛 동작(종류 무관 최근 10통)          → shell ⓕ 빨강  (DA⑥ 반례 1 의 재발)
#   ⑤ NOTIFY_WIN 아주 큼(창 = 10^12)                  → py ⓓ' 빨강  (10분 경계 무력화)
#   ⑥ blocked 게이트 끔                               → r838 ⓡ9 빨강(정지 유지 24h = 새 알림 0)
#      ★ⓓ 로는 안 잡힌다★ — r912 창(600초)이 같은 키를 덮어 단독 제거가 관측되지 않는다(설계상 겹침).
#   ⑦ 옛 가드 전체 끔(dry-run·손상·수신자 없음)        → py ⓕ 빨강
#   ⑧ 보낸 시각을 send «앞» 에 저장                       → py ⓘ 빨강  (반송 r4 ② 의 재발: rc3 거절이 «보냄» 으로 남는다)
#   ⑨ 창 안 저장 실패를 무시하고 «안 보냄»             → py ⓙ 빨강  (반송 r4 ③ 의 재발: WARN 은 «그냥 보낸다» 라는데 발신 0)
#   ⑩ 이름 판정을 손 정규식으로 넓힘(세 사본 같이)      → shell ⓚ 빨강  (반송 r4 ① 의 재발: byz-tool#0 이 사람 칸)
# 출력: 무변이 기준 PASS 1줄 + 변이마다 KILLED|SURVIVED 1줄 · 기준 PASS 이고 전부 KILLED = rc0
set -uo pipefail
H="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PY="${PYTHON:-python3.11}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/fable-team/harness"
cp -R "$H/bin" "$H/comm" "$H/tests" "$H/kit" "$T/fable-team/harness/"
cp -R "$H/../skill" "$T/fable-team/"   # 시험 ⓕ·ⓘ 가 skill 자르기 사본도 본다
find "$T" -name __pycache__ -type d -prune -exec rm -rf {} +
git -C "$T" init -q && git -C "$T" add -A && git -C "$T" -c user.name=m -c user.email=m@m commit -qm base || { echo "ERROR 임시 사본 git init 실패"; exit 1; }
H2="$T/fable-team/harness"
shell() { (cd "$H2" && PYTHONDONTWRITEBYTECODE=1 bash tests/test_mbox_keep_human_mail.sh >/dev/null 2>&1); }
py() { (cd "$H2" && PYTHONDONTWRITEBYTECODE=1 "$PY" -m pytest -q -p no:cacheprovider tests/scripts/test_model_swap_notify_coalesce.py -k "$1" >/dev/null 2>&1); }
fail=0
if shell && py "test_"; then echo "PASS 무변이 기준(전부)"; else echo "ERROR 무변이 기준 FAIL — 변이 판정 무효"; exit 1; fi
mutate() {  # <이름> <판정함수> <파일> <옛 글자> <새 글자>
  local name="$1" judge="$2" f="$H2/$3"
  cp "$f" "$f.orig"
  OLD="$4" NEW="$5" "$PY" -c 'import os,sys;p=sys.argv[1];s=open(p,encoding="utf-8").read();o=os.environ["OLD"];assert o in s,"변이 자리 없음: "+o;open(p,"w",encoding="utf-8").write(s.replace(o,os.environ["NEW"],1))' "$f" \
    || { echo "ERROR $name 변이 자리 없음"; fail=1; mv "$f.orig" "$f"; return; }
  find "$T" -name __pycache__ -type d -prune -exec rm -rf {} +
  if $judge; then echo "SURVIVED $name"; fail=1; else echo "KILLED $name"; fi
  mv "$f.orig" "$f"
}
mutate "①사람보존끔" shell comm/mbox_keep.py 'SYS_PLAIN, SYS_HEAD, NORMAL, HUMAN = 0, 1, 2, 3' 'SYS_PLAIN, SYS_HEAD, NORMAL, HUMAN = 0, 0, 0, 0'
mutate "②넘침ERROR끔" shell comm/mbox_ops.py '    if overflow:' '    if False:'
mutate "③머리우선복귀" shell comm/mbox_keep.py '        return SYS_HEAD if head else SYS_PLAIN' '        return HUMAN if head else SYS_PLAIN'
mutate "④kit자르기옛동작" shell kit/fable-team/bin/ft-mbox.py '            k, d, _oldest, ov = trim(rs, MAX_PER_TO)' '            k, d, _oldest, ov = rs[-MAX_PER_TO:], max(0, len(rs) - MAX_PER_TO), None, 0'
r9_judge() { (cd "$H2" && PYTHONDONTWRITEBYTECODE=1 "$PY" -m pytest -q -p no:cacheprovider tests/scripts/test_model_swap_account_outage_r838.py -k test_r9_ >/dev/null 2>&1); }
d2_judge() { py test_d2_; }
d_judge() { py test_d_; }
f_judge() { py test_f_; }
i_judge() { py test_i_; }
j_judge() { py test_j_; }
mutate "⑤NOTIFY_WIN아주큼" d2_judge bin/ft_model_swap_account.py 'NOTIFY_WIN = 10 * 60' 'NOTIFY_WIN = 10 ** 12'
mutate "⑥blocked검사끔" r9_judge bin/ft_model_swap_account.py 'isinstance(blocked, dict) and key in blocked' 'False'
mutate "⑦옛가드끔" f_judge bin/ft_model_swap_account.py 'ok = not (isinstance(blocked, dict) and key in blocked) and not self.mute(key) and isinstance(to, str) and not self.a.dry_run' 'ok = True'
mutate "⑧저장을send앞으로" i_judge bin/ft_model_swap_account.py '        self._pend = (p, st)   # ★저장은 send 뒤★ — 부르는 쪽이 send rc0 이면 notify_sent' '        st[key] = {"last": self.now, "n": 1}; _ = self._notify_save(p, st); return True, tail'
mutate "⑨창안저장실패무시" j_judge bin/ft_model_swap_account.py $'            if self._notify_save(p, st):\n                return False, ""\n            return True, ""' $'            _ = self._notify_save(p, st)\n            return False, ""'
# ⑩ 부터는 세 사본을 «같이» 고친다 — ⓘ(바이트 동일)도 유지해야 변이가 ⓚ 에서만 빨간다
mutate3() {
  local name="$1" judge="$2" rel
  local files=(comm/mbox_keep.py kit/fable-team/bin/ft-mbox.py ../skill/scripts/ft-mbox.py)
  for rel in "${files[@]}"; do cp "$H2/$rel" "$H2/$rel.orig"; done
  OLD='    if head and seat(frm):' NEW='    if head and _re.match(r"^byz-[a-z0-9][a-z0-9-]*#[0-9]+$", frm):' "$PY" -c '
import os, sys
for p in sys.argv[1:]:
    s = open(p, encoding="utf-8").read(); o = os.environ["OLD"]
    assert o in s, "변이 자리 없음: " + p
    open(p, "w", encoding="utf-8").write(s.replace(o, os.environ["NEW"], 1))
' "${files[@]/#/$H2/}" || { echo "ERROR $name 변이 자리 없음"; fail=1; }
  find "$T" -name __pycache__ -type d -prune -exec rm -rf {} +
  if $judge; then echo "SURVIVED $name"; fail=1; else echo "KILLED $name"; fi
  for rel in "${files[@]}"; do mv "$H2/$rel.orig" "$H2/$rel"; done
}
mutate3 "⑩이름판정넓힘" shell
exit $fail
