#!/usr/bin/env bash
# test_nano_evidence_merge_only_r1071.sh — 카드 r1071: 증거 검사가 «세트 HEAD ≠ 지금 HEAD» 여도 그 차이가 main 병합뿐이고 자기 변경이 같으면(ft-approval-equiv EQUIV) 통과 · 일반 커밋·손댄 병합·판정기 없음은 지금처럼 REJECT
# 임시 git 리포(원장 + 나노 워크트리)만 쓴다 — 실 명부·실 워크트리·실 카드 쓰기 0 · 네트워크 0 · 외부 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../bin"; MIR="$HERE/../kit/fable-team/bin"
EV="$SRC/ft-nano-evidence-check.sh"
[ "${FT_EVIDENCE_REENTRY:-0}" = 1 ] && { echo "SKIP 재진입"; exit 0; }   # 자기 재호출 표지
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
nhas(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:400}";; *) ok "$3";; esac; }

bash -n "$EV" && ok "bash -n" || bad "bash -n"
cmp -s "$EV" "$MIR/ft-nano-evidence-check.sh" && ok "미러 cmp 0" || bad "미러 불일치(kit 사본)"
[ "$(wc -l < "$EV")" -le 80 ] && ok "≤80줄" || bad "80줄 초과: $(wc -l < "$EV")"

L="$T/ledger"; D=design/harness/indices/진행
LG() { git -C "$L" -c user.email=t@t -c user.name=t "$@"; }
git init -q -b main "$L"; echo base > "$L/a.txt"; LG add a.txt; LG commit -q -m m0
mkcard() { mkdir -p "$L/$D"; printf '## 완료 조건\n(없음)\n' > "$L/$D/$1.md"; LG add "$D/$1.md"; LG commit -q -m "card $1"; }
mkcard code; mkcard doc; mkcard conf
card() { echo "$L/$D/$1.md"; }
setline() { LG checkout -q -- "$D/$1.md"; printf -- '- %s\n' "$2" >> "$L/$D/$1.md"; }   # setline <카드> <증거 줄>
NW="$T/nano"; LG worktree add -q "$NW" -b nano/x main
NG() { git -C "$NW" -c user.email=t@t -c user.name=t "$@"; }
echo mine > "$NW/own.txt"; NG add own.txt; NG commit -q -m "A 내 변경"; A="$(NG rev-parse HEAD)"
echo 'x = 1' > "$L/src.py"; LG add src.py; LG commit -q -m m1; LG update-ref refs/remotes/origin/main "$(LG rev-parse main)"
NG merge -q --no-edit main >/dev/null 2>&1
echo two > "$L/b.txt"; LG add b.txt; LG commit -q -m m2; LG update-ref refs/remotes/origin/main "$(LG rev-parse main)"
NG merge -q --no-edit main >/dev/null 2>&1
S1="$(NG rev-parse HEAD)"
chk() { bash "${BIN:-$EV}" "$(card "$1")" --repo "$NW" --feat main 2>&1; }

echo "== ⓐ R1 세트 뒤 main 병합 2 · 자기 변경 같음 → 통과 + «main 병합뿐»"
setline code "세트: $A · 시험: bash t.sh rc=0 · 이슈: 0"; out="$(chk code)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "main 병합뿐" "ⓐ rc=0 · OK 에 «main 병합뿐»" && has "$out" "merges=2" "ⓐ merges=2" && has "$out" "세트 ${A:0:9}" "ⓐ OK 에 세트 sha" || bad "ⓐ rc=$rc ← ${out:0:300}"

echo "== ⓑ R2 세트 뒤 일반 커밋 1 → REJECT(지금 문구) + 판정기 사유"
echo v2 >> "$NW/own.txt"; NG add own.txt; NG commit -q -m "내 커밋"; S2="$(NG rev-parse HEAD)"
setline code "세트: $A · 시험: bash t.sh rc=0 · 이슈: 0"; out="$(chk code)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "시험 뒤 커밋이 생김" "ⓑ 지금 REJECT 문구" && has "$out" "판정기:" "ⓑ 판정기 사유 첫 줄" && has "$out" "일반 커밋" "ⓑ 사유 = 일반 커밋" || bad "ⓑ rc=$rc ← ${out:0:300}"
setline code "세트: $S2 · 시험: bash t.sh rc=0 · 이슈: 0"; out="$(chk code)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓑ 세트를 지금 HEAD 로 갱신하면 통과(판정기 호출 0 경로)" || bad "ⓑ' rc=$rc ← ${out:0:300}"

echo "== ⓒ R3 병합 충돌 해결로 자기 파일이 바뀐 병합 → REJECT(NOT-EQUIV)"
NW2="$T/nano2"; LG worktree add -q "$NW2" -b nano/y main~2
N2() { git -C "$NW2" -c user.email=t@t -c user.name=t "$@"; }
echo nano-side > "$NW2/a.txt"; N2 add a.txt; N2 commit -q -m "A2 내 변경"; A2="$(N2 rev-parse HEAD)"
echo main-side > "$L/a.txt"; LG add a.txt; LG commit -q -m m3; LG update-ref refs/remotes/origin/main "$(LG rev-parse main)"
N2 merge -q --no-edit main >/dev/null 2>&1; echo custom-resolution > "$NW2/a.txt"; N2 add a.txt; N2 commit -q -m "충돌 해소(손댐)" 2>/dev/null || N2 commit -q -m "충돌 해소(손댐)"
setline conf "세트: $A2 · 시험: bash t.sh rc=0 · 이슈: 0"; out="$(bash "${BIN:-$EV}" "$(card conf)" --repo "$NW2" --feat main 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "판정기:" "ⓒ REJECT + 판정기 사유" && nhas "$out" "main 병합뿐" "ⓒ OK 줄 없음" || bad "ⓒ rc=$rc ← ${out:0:300}"

echo "== ⓓ R4 세트 == HEAD → 판정기 호출 0 (가짜 판정기 호출 기록)"
SD="$T/stub"; mkdir -p "$SD"; cp "$EV" "$SD/ft-nano-evidence-check.sh"
printf '#!/usr/bin/env bash\necho called >> "%s"\necho "EQUIV approve=%s head=%s merges=2 files=1 mode=merge overlap=0 base=x"\nexit 0\n' "$T/stub.called" x y > "$SD/ft-approval-equiv.sh"
setline code "세트: $S2 · 시험: bash t.sh rc=0 · 이슈: 0"; out="$(BIN="$SD/ft-nano-evidence-check.sh" bash "$SD/ft-nano-evidence-check.sh" "$(card code)" --repo "$NW" --feat main 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓓ rc=0" || bad "ⓓ rc=$rc ← ${out:0:300}"
[ -f "$T/stub.called" ] && bad "ⓓ 판정기가 불렸다(같은 세트면 호출 0)" || ok "ⓓ 판정기 호출 0"
setline code "세트: $A · 시험: bash t.sh rc=0 · 이슈: 0"
out="$(BIN="$SD/ft-nano-evidence-check.sh" bash "$SD/ft-nano-evidence-check.sh" "$(card code)" --repo "$NW" --feat main 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$T/stub.called" ] && has "$out" "merges=2" "ⓓ' 다를 때는 판정기 1회 · merges=2 를 OK 줄에" || bad "ⓓ' rc=$rc called=$([ -f "$T/stub.called" ] && echo y || echo n) ← ${out:0:300}"

echo "== ⓔ R5 문서 전용 + 세트 뒤 main 병합(병합으로 코드 경로 유입) → 통과(scope 는 세트까지)"
NW3="$T/nano3"; LG worktree add -q "$NW3" -b nano/doc main~2
N3() { git -C "$NW3" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$NW3/design"; echo doc > "$NW3/design/x.md"; N3 add design/x.md; N3 commit -q -m "D 문서만"; DC="$(N3 rev-parse HEAD)"
N3 merge -q --no-edit main >/dev/null 2>&1
setline doc "세트: $DC · 시험: 없음(문서) — 문서 카드 · 이슈: 0"; out="$(bash "${BIN:-$EV}" "$(card doc)" --repo "$NW3" --feat main 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "main 병합뿐" "ⓔ rc=0 · 병합뿐" || bad "ⓔ rc=$rc ← ${out:0:300}"

echo "== ⓕ R6 --ancestor-of 경로 → 지금 동작"
setline code "세트: $A · 시험: bash t.sh rc=0 · 이슈: 0"; out="$(bash "${BIN:-$EV}" "$(card code)" --repo "$NW" --feat main --ancestor-of HEAD 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && nhas "$out" "main 병합뿐" "ⓕ 조상이면 통과 · 병합 판정 문구 없음" || bad "ⓕ rc=$rc ← ${out:0:300}"
out="$(bash "${BIN:-$EV}" "$(card code)" --repo "$NW2" --feat main --ancestor-of HEAD 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "의 조상이 아니다" "ⓕ' 조상 아니면 REJECT(지금 동작)" || bad "ⓕ' rc=$rc ← ${out:0:300}"

echo "== ⓖ 판정기 파일 없음 → REJECT(조용한 통과 0)"
NJ="$T/nojudge"; mkdir -p "$NJ"; cp "$EV" "$NJ/ft-nano-evidence-check.sh"
setline code "세트: $A · 시험: bash t.sh rc=0 · 이슈: 0"; out="$(bash "$NJ/ft-nano-evidence-check.sh" "$(card code)" --repo "$NW" --feat main 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "동일성 판정기 없음" "ⓖ 판정기 없음 REJECT" || bad "ⓖ rc=$rc ← ${out:0:300}"

echo "== 변이 대조 — 이 검사가 없으면 해당 케이스가 뒤집힌다"
py() { python3 - "$@" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 문자열 없음"
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
# 변이 파일은 변이 대상 스크립트와 «같은 디렉토리» 에 판정기가 있어야 한다(스크립트는 자기 dirname 에서 판정기를 찾는다)
cp "$SRC/ft-approval-equiv.sh" "$SRC/ft_approval_equiv.py" "$T/"
# 변이 ①: 판정기 호출 끔(= 옛 «글자 그대로 같아야 통과» 동작)
py "$EV" "$T/m1.sh" 'EQUIV="$(bash "$EQ" "$set_head" "$head_now" --repo "$REPO" 2>&1)" ||' 'false ||' && ok "변이① 생성" || bad "변이① 생성 실패"
setline code "세트: $A · 시험: bash t.sh rc=0 · 이슈: 0"; out="$(BIN="$T/m1.sh" bash "$T/m1.sh" "$(card code)" --repo "$NW" --feat main 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "시험 뒤 커밋이 생김" "변이①(판정기 끔) → ⓐ 가 REJECT 로 뒤집힘 = 시험이 잡는다" || bad "변이① rc=$rc ← ${out:0:200}"
# 변이 ②: 판정기 rc 를 무시(rc1 도 통과)
py "$EV" "$T/m2.sh" '2>&1)" || { echo' '2>&1)" || true || { echo' && ok "변이② 생성" || bad "변이② 생성 실패"
setline conf "세트: $A2 · 시험: bash t.sh rc=0 · 이슈: 0"; out="$(BIN="$T/m2.sh" bash "$T/m2.sh" "$(card conf)" --repo "$NW2" --feat main 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "변이②(판정기 rc 무시) → ⓒ 가 통과로 뒤집힘 = 시험이 잡는다" || bad "변이② rc=$rc ← ${out:0:200}"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAIL $fail"; exit 1
