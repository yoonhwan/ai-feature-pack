#!/usr/bin/env bash
# test_roster_backup_cap_r2043.sh — r2043: 명부 백업 <원본>.bak-<종류>-<ts> 가 (원본·종류)별 상한(FT_BAK_CAP 50~100 · 기본 50)을 넘지 않는다.
# 반례 ①~⑤(카드 동결 · ⑥ 회귀 = 기존 시험 기준판 대조는 카드 보고) · 모든 쓰기 = mktemp 임시 루트 · 실 명부·실 루트 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R2043_BIN:-$HERE/../../harness/bin}"; RETIRE="$BIN/ft-seat-retire.sh"
TMP="$(mktemp -d)"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$TMP/reap-stub.sh"; export FT_SEAT_REAP_BIN="$TMP/reap-stub.sh"
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok
unset FT_BAK_CAP
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
cnt() { ls -d "$1".bak-"$2"-* 2>/dev/null | wc -l | tr -d ' '; }
ts_of() { printf '20250101%06d' "$1"; }   # i → 14자리 ts(i 클수록 최근)
mkbaks() { local f="$1" k="$2" n="$3" i; for ((i=n-1; i>=0; i--)); do echo "b$i" > "$f.bak-$k-$(ts_of "$i")"; done; }   # 최근 것부터 만든다(mtime ≠ ts 순서)
seats() { mkdir -p "$1"; printf '%s' '{"_master": "M#1", "M#1": {"role": "master", "agent": "claude", "model": "m1", "tick": "ft-master-tick"}}' > "$1/seats-x.json"; }
retire() { bash "$RETIRE" 'M#1' 'M#2' --seats "$1/seats-x.json"; }
capsh() { ( . "$BIN/ft-team-lib.sh"; ft_bak_cap "$@" ); }
cappy() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from ft_roster_lib import bak_cap; bak_cap(sys.argv[2], sys.argv[3])' "$BIN" "$@"; }

# ① 60개 + 은퇴 1회 → 50 · 남은 것 = 최근 50(새 백업 포함 · 가장 오래된 11개 지움)
D="$TMP/c1"; seats "$D"; mkbaks "$D/seats-x.json" retire 60
out="$(retire "$D" 2>/dev/null)"; rc=$?
chk "①rc0 · RETIRED" "$rc ${out%% *}" "0 RETIRED"
chk "①개수 50" "$(cnt "$D/seats-x.json" retire)" 50
chk "①가장 오래된 남은 것 = i11(i0~i10 11개 지움)" "$(ls "$D"/seats-x.json.bak-retire-* | sort | head -1 | sed 's/.*-//')" "$(ts_of 11)"
chk "①새 백업 남음(2025 아닌 ts 1개)" "$(ls "$D"/seats-x.json.bak-retire-* | grep -vc 'retire-2025')" 1

# ② FT_BAK_CAP=80 · 90개 → 80 / FT_BAK_CAP=10(범위 밖) · 60개 → 50 / 비정수 → 50
D="$TMP/c2"; mkdir -p "$D"; echo '{}' > "$D/s.json"; mkbaks "$D/s.json" close 90
FT_BAK_CAP=80 capsh "$D/s.json" close 2>/dev/null
chk "②CAP=80 · 90 → 80" "$(cnt "$D/s.json" close)" 80
D="$TMP/c2b"; mkdir -p "$D"; echo '{}' > "$D/s.json"; mkbaks "$D/s.json" close 60
FT_BAK_CAP=10 capsh "$D/s.json" close 2>/dev/null
chk "②CAP=10(범위 밖) · 60 → 50" "$(cnt "$D/s.json" close)" 50
D="$TMP/c2c"; mkdir -p "$D"; echo '{}' > "$D/s.json"; mkbaks "$D/s.json" close 60
FT_BAK_CAP=abc capsh "$D/s.json" close 2>/dev/null
chk "②CAP=abc · 60 → 50" "$(cnt "$D/s.json" close)" 50

# ③ 대상 꼴 밖 = 손 0(다른 원본 · 다른 종류 · 설치 백업 · 원본 · 꼴 밖 꼬리 · 폴더 · 심링크)
D="$TMP/c3"; mkdir -p "$D"; echo '{"a":1}' > "$D/seats-x.json"; echo '{}' > "$D/seats-y.json"
mkbaks "$D/seats-x.json" retire 60; mkbaks "$D/seats-y.json" retire 60; mkbaks "$D/seats-x.json" close 60
echo inst > "$D/seats-x.json.bak-r2043"; echo odd > "$D/seats-x.json.bak-retire-foo"; echo odd > "$D/seats-x.json.bak-retire-2019x"
mkdir "$D/seats-x.json.bak-retire-20000101000000"; ln -s "$D/seats-y.json" "$D/seats-x.json.bak-retire-20000101000001"
before="$(cd "$D" && ls -A | grep -v '^seats-x\.json\.bak-retire-2025' | while read -r f; do printf '%s %s\n' "$f" "$( [ -f "$f" ] && cksum < "$f" || echo dir)"; done)"
capsh "$D/seats-x.json" retire 2>/dev/null
after="$(cd "$D" && ls -A | grep -v '^seats-x\.json\.bak-retire-2025' | while read -r f; do printf '%s %s\n' "$f" "$( [ -f "$f" ] && cksum < "$f" || echo dir)"; done)"
chk "③대상 x·retire 60 → 50" "$(ls "$D"/seats-x.json.bak-retire-2025* | wc -l | tr -d ' ')" 50
chk "③꼴 밖·남의 파일 이름·내용 불변" "$([ "$before" = "$after" ] && echo same || echo changed)" same
chk "③심링크·폴더 그대로" "$([ -L "$D/seats-x.json.bak-retire-20000101000001" ] && [ -d "$D/seats-x.json.bak-retire-20000101000000" ] && echo yes)" yes

# ④ 지우기 실패(os.remove 스텁 · 한 파일 PermissionError) → WARN 1줄 · 은퇴 rc0 · RETIRED 줄 = 실패 없는 실행과 같음
mkdir -p "$TMP/stub"; cat > "$TMP/stub/sitecustomize.py" <<PY
import os
_rm = os.remove
def _stub(p, *a, **k):
    if str(p).endswith("$(ts_of 3)"): raise PermissionError(13, "Permission denied")
    return _rm(p, *a, **k)
os.remove = _stub
PY
DA="$TMP/c4a"; seats "$DA"; mkbaks "$DA/seats-x.json" retire 60
DB="$TMP/c4b"; seats "$DB"; mkbaks "$DB/seats-x.json" retire 60
oa="$(retire "$DA" 2>"$TMP/ea")"; ra=$?
ob="$(PYTHONPATH="$TMP/stub" retire "$DB" 2>"$TMP/eb")"; rb=$?
chk "④rc 같음(0)" "$ra $rb" "0 0"
chk "④RETIRED 줄 같음(경로 치환)" "$(printf '%s' "${ob%%$'\n'*}" | sed "s|$DB|D|")" "$(printf '%s' "${oa%%$'\n'*}" | sed "s|$DA|D|")"
chk "④WARN 1줄(실패 쪽만)" "$(grep -c '^WARN 백업 상한' "$TMP/eb") $(grep -c '^WARN 백업 상한' "$TMP/ea")" "1 0"
chk "④실패 파일 남음 · 나머지 정리(51)" "$(cnt "$DB/seats-x.json" retire)" 51

# ⑤ 같은 목록 → 셸·Python 남긴 집합 같음(ts 길이 섞임 · 꼴 밖 섞임)
for s in sh py; do D="$TMP/c5$s"; mkdir -p "$D"; echo '{}' > "$D/k.json"; mkbaks "$D/k.json" rename 70
  for i in 1 2 3; do echo m > "$D/k.json.bak-rename-2026010$i-000000"; done; echo m > "$D/k.json.bak-rename-x1"; done
capsh "$TMP/c5sh/k.json" rename 2>/dev/null; cappy "$TMP/c5py/k.json" rename 2>/dev/null
chk "⑤셸 = Python 집합" "$(cd "$TMP/c5sh" && ls | cksum)" "$(cd "$TMP/c5py" && ls | cksum)"
chk "⑤남은 rename 꼴 = 50(+꼴 밖 1)" "$(ls "$TMP/c5py" | grep -c '^k.json.bak-rename-[0-9]')" 50

# ⓧ 생성 자리 호출(ⓧ1~ⓧ3) — 백업 만드는 줄마다 같은 종류 bak_cap
for pair in "ft-seat-close.sh:close:2" "ft-seat-close.sh:reopen:2" "ft-seat-retire.sh:retire:1" "ft_roster_lib.py:retire:1" "ft-tick-team.sh:retarget:1" "ft_team_rename.py:rename:1" "ft_key_rotate_io.py:keyrotate:1"; do
  IFS=: read -r f k n <<< "$pair"
  chk "ⓧ$f bak-$k 생성 ${n}곳 = bak_cap 호출" "$(grep -c "bak_cap(.*\"${k}" "$BIN/$f")" "$n"
done

echo "SUMMARY fail=$fail"
exit "$fail"
