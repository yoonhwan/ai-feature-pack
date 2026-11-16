#!/usr/bin/env bash
# test_mbox_seat_qa_scope_r1658.sh — r1658: 우편함 seat() 가 ft-name-lint.sh 의 qa 꼬리 규칙(r1650)을 따른다.
#   ⓐ True 이름 · ⓑ False 이름 · ⓒ 8개 이름마다 seat() = lint rc0 · ⓓ qa 범위 좌석 [HIL] = HUMAN · 머리 없음 = NORMAL
#   ⓔ 세 사본(skill·kit·comm/mbox_keep) seat() 본문 같음 · M1~M3 변이(사본에만) → 해당 칸 빨강
#   byz-harness-da-astra#0 = lint REJECT(r1650 · astra 는 모델) → ⓒ 계약대로 False 로 본다.
#   입력 = 이름 문자열·kind() 행 dict 뿐 · 실 우편함 0 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$HERE/.."; P="$H/.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
cp "$H/bin/ft-name-lint.sh" "$T/lint.sh"; export FT_NAME_LINT="$T/lint.sh"
cp "$H/comm/mbox_keep.py" "$T/keep.py"; cp "$H/kit/fable-team/bin/ft-mbox.py" "$T/kit.py"; cp "$P/skill/scripts/ft-mbox.py" "$T/skill.py"
YES="byz-harness-qa-pi#3 byz-harness-qa-ft20-pi#3 byz-harness-nano-r1658-x#0"
NO="byz-harness-qa-a-b-pi#1 byz-harness-qa-ft20#1 byz-harness-arch-ft20-pi#1 byz-tool#0 byz-harness-da-astra#0"
cat > "$T/probe.py" <<'PY'
import importlib.util, sys
def load(p):
    s = importlib.util.spec_from_file_location("m_" + p.rsplit("/", 1)[-1][:-3], p)
    m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
m = load(sys.argv[1])
if sys.argv[2] == "kind":
    f = "byz-harness-qa-ft20-pi#3"; to = "byz-harness-master-pi#1"
    hil = m.kind({"from": f, "to": to, "body": "[HIL] 결정 필요"}); plain = m.kind({"from": f, "to": to, "body": "그냥 쪽지"})
    print(f"{hil == m.HUMAN} {plain == m.NORMAL}")
else:
    print(" ".join("1" if m.seat(n) else "0" for n in sys.argv[2:]))
PY
seats() { env -u FT_SEAT_MBOX_DIR python3 "$T/probe.py" "$@" 2>&1; }   # seats <파일> <이름…> → "1 0 …"
lintv() { local n o=""; for n in "$@"; do bash "$T/lint.sh" "$n" >/dev/null 2>&1 && o="$o 1" || o="$o 0"; done; echo "${o# }"; }
rep() { local v="$1" n="$2" o="" i; for ((i = 0; i < n; i++)); do o="$o $v"; done; echo "${o# }"; }
for f in keep kit skill; do
  # shellcheck disable=SC2086
  a="$(seats "$T/$f.py" $YES)"; [ "$a" = "$(rep 1 3)" ] && ok "ⓐ $f True 3" || bad "ⓐ $f got=[$a]"
  # shellcheck disable=SC2086
  b="$(seats "$T/$f.py" $NO)"; [ "$b" = "$(rep 0 5)" ] && ok "ⓑ $f False 5" || bad "ⓑ $f got=[$b]"
  # shellcheck disable=SC2086
  [ "$a $b" = "$(lintv $YES $NO)" ] && ok "ⓒ $f = lint rc0" || bad "ⓒ $f seat=[$a $b] lint=[$(lintv $YES $NO)]"
  d="$(seats "$T/$f.py" kind)"; [ "$d" = "True True" ] && ok "ⓓ $f [HIL]=HUMAN · 머리 없음=NORMAL" || bad "ⓓ $f got=[$d]"
done
body() { sed -n '/^def seat(/,/^def kind(/p' "$1"; }
cmp -s <(body "$T/keep.py") <(body "$T/kit.py") && cmp -s <(body "$T/keep.py") <(body "$T/skill.py") \
  && ok "ⓔ 세 사본 seat() 본문 같음" || bad "ⓔ seat() 사본 다름"
mut() {   # mut <칸> <sed> <이름> <기대 이전값> — 변이 사본에서 그 이름 판정이 뒤집히면 PASS
  cp "$T/keep.py" "$T/mut.py"; sed -i.o "$2" "$T/mut.py"
  if cmp -s "$T/keep.py" "$T/mut.py"; then bad "$1 변이 적용 안 됨"; return; fi
  [ "$(seats "$T/mut.py" "$3")" != "$4" ] && ok "$1 빨강 확인 ($3)" || bad "$1 변이가 안 잡힘"
}
mut "M1 qa 갈래 삭제 → ⓐ 둘째" '/^    tail = last if role == "qa"/d' byz-harness-qa-ft20-pi#3 1
mut "M2 범위 토큰 수 제한 삭제 → ⓑ 첫째" 's/ and "-" not in rng//' byz-harness-qa-a-b-pi#1 0
mut "M3 qa 조건 모든 역할 → ⓑ 셋째" 's/if role == "qa" and rng/if rng/' byz-harness-arch-ft20-pi#1 0
[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; }; echo "FAILED $fail"; exit 1
