#!/usr/bin/env bash
# test_mbox_drop_seq_stderr_r1748.sh — r1748: ring 포화로 쪽지를 버릴 때 보낸 쪽 stderr DROPPED 첫 줄 끝에
# « · 버린 seq #a,#b» 를 붙인다(10개 넘으면 최근 10개 + «앞 N개 생략») · 세 사본(comm · kit · skill) 같은 줄.
#   ① ring=3 · 일반 3통 · 4번째 send → DROPPED 줄에 «버린 seq #<첫 seq>»
#   ② 한 번에 2통 밀림(ring 10 으로 4통 쌓은 뒤 ring 3 send) → «#a,#b» · 원장 seqs= 와 같은 순서
#   ③ 버린 seq 12개(함수 직접 호출 · 세 사본) → 최근 10개 + «앞 2개 생략»
#   ④ kit · skill ft-mbox.py 로 ① → comm 과 같은 DROPPED 줄
#   ⑤ 버림 0 send → stderr 0 · QUEUED 줄 기준 꼴 바이트 같음 · r1651·r1663 시험 rc0
# 변이(사본에만): M1 mbox_ops seq 칸 지움 → ① FAIL · M2 kit 사본만 옛 문구 → ④ FAIL (원본 대조 1회씩)
# 정본 .py 를 임시 폴더에 복사해 돈다 — 실 우편함·실 doorbell 0 · sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; KIT="$REPO/harness/kit/fable-team/bin/ft-mbox.py"; SKILL="$REPO/skill/scripts/ft-mbox.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
FROM="byz-x-da-codex#2"

new_env() {   # 격리 루트 · 빈 큐 · 세 사본 · MUT 변이(사본에만)
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$ENVROOT/seats"; cp "$SRC"/mbox*.py "$C/"; cp "$KIT" "$C/kit.py"; cp "$SKILL" "$C/skill.py"
  cp "$REPO/harness/bin/ft-name-lint.sh" "$C/"
  : > "$Q"; : > "$ENVROOT/errs"
  printf '{"_master": "byz-x-master-claude#1"}\n' > "$ENVROOT/seats/seats.json"
  if [ -n "${MUT:-}" ]; then "$MUT"; fi
}
send() {   # send <comm|kit|skill> <ring> <to> <body> — 발신 가드는 관심 밖 → --force · doorbell 0(tmux 없음)
  local prog="$C/mbox.py"; [ "$1" = kit ] && prog="$C/kit.py"; [ "$1" = skill ] && prog="$C/skill.py"
  FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" FT_MBOX_RING="$2" TMUX= PATH="$T/bin:$PATH" \
    python3 "$prog" send "$3" "$FROM" "$4" --force >"$ENVROOT/out" 2>"$ENVROOT/err"; RC=$?
  cat "$ENVROOT/err" >> "$ENVROOT/errs"
}
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' > "$T/bin/tmux"; chmod +x "$T/bin/tmux"   # tmux 스텁
qseq() { sed -n 's/^QUEUED seq=\([0-9]*\) .*/\1/p' "$ENVROOT/out"; }
drop_line() { grep '^DROPPED ' "$ENVROOT/err" | head -1; }

# ── 변이(사본에만)
mut_m1() { sed -i '' 's/mbox_drops\.drop_seq_tail(seqs)/""/' "$C/mbox_ops.py"; ! grep -q 'drop_seq_tail(seqs)' "$C/mbox_ops.py"; }
mut_m2() { sed -i '' 's/, _drop_seq_tail(seqs), /, "", /' "$C/kit.py"; ! grep -q ', _drop_seq_tail(seqs), ' "$C/kit.py"; }

case1() {   # case1 <comm|kit|skill> — 결과 줄은 $LINE1 에
  new_env; local s1
  send "$1" 3 R1 "쪽지 1"; s1="$(qseq)"
  send "$1" 3 R1 "쪽지 2"; send "$1" 3 R1 "쪽지 3"; send "$1" 3 R1 "쪽지 4"
  LINE1="$(drop_line)"
  case "$LINE1" in *"쌓아뒀다. · 버린 seq #$s1") return 0;; esac
  echo "  got: $LINE1"; return 1
}
c1() { if case1 comm; then ok "① ring=3 4번째 send → DROPPED 줄 끝 «버린 seq #첫seq»"; return 0; fi; bad "①"; return 1; }

c2() {
  new_env; local a b i logseqs
  send comm 10 R2 "쪽지 1"; a="$(qseq)"; send comm 10 R2 "쪽지 2"; b="$(qseq)"
  for i in 3 4; do send comm 10 R2 "쪽지 $i"; done
  send comm 3 R2 "쪽지 5"
  logseqs="$(sed -n 's/.* seqs=//p' "$C/mailbox.drops.log" | tail -1)"
  case "$(drop_line)" in *" · 버린 seq #$a,#$b")
    if [ "$logseqs" = "$a,$b" ]; then ok "② 한 번에 2통 → «#$a,#${b}» · 원장 seqs=$logseqs 같은 순서"; return 0; fi;; esac
  bad "② line=$(drop_line) log=$logseqs"; return 1
}

c3() {
  new_env; local want=" · 버린 seq #3,#4,#5,#6,#7,#8,#9,#10,#11,#12 (앞 2개 생략)" got k s
  got="$(cd "$C" && python3 -c 'import mbox_drops; print(mbox_drops.drop_seq_tail(list(range(1,13))))')"
  [ "$got" = "$want" ] || { bad "③ comm got=«${got}»"; return 1; }
  for k in kit skill; do
    s="$(cd "$C" && python3 -c "import importlib.util as u; sp=u.spec_from_file_location('m','$k.py'); m=u.module_from_spec(sp); sp.loader.exec_module(m); print(m._drop_seq_tail(list(range(1,13))))")"
    [ "$s" = "$want" ] || { bad "③ $k got=«${s}»"; return 1; }
  done
  ok "③ 버린 seq 12개 → 최근 10개 + «앞 2개 생략»(세 사본 같은 꼴)"; return 0
}

c4() {
  # seq 번호는 사본마다 발급 바닥이 달라(1601·1602) «#S» 로 맞춘다 · 번호 자체는 case1 이 자기 첫 seq 로 본다
  local ref k krc; case1 comm >/dev/null; ref="${LINE1%#*}#S"
  for k in kit skill; do
    case1 "$k" >/dev/null; krc=$?
    { [ "$krc" = 0 ] && [ "${LINE1%#*}#S" = "$ref" ]; } || { bad "④ $k rc=$krc «${LINE1}» ≠ comm «${ref}»"; return 1; }
  done
  ok "④ kit · skill 경로 DROPPED 줄 = comm 줄(seq 번호 밖 바이트 같음)"; return 0
}

c5() {
  new_env; local s want t
  send comm 3 R5 "쪽지 하나"; s="$(qseq)"
  want="QUEUED seq=$s to=R5 pending=1 file=$Q bytes=$(printf '%s' "쪽지 하나" | wc -c | tr -d ' ')"
  # stderr 0 = 이 시험 환경의 desk 판정기 부재 WARN(설치 순서 · 기준판도 같다) 1줄만 빼고 0
  { [ "$RC" = 0 ] && [ -z "$(grep -v '^WARN desk 경로 판정기 없음' "$ENVROOT/err")" ] && [ "$(cat "$ENVROOT/out")" = "$want" ]; } \
    || { bad "⑤ rc=$RC err=$(cat "$ENVROOT/err") out=$(cat "$ENVROOT/out")"; return 1; }
  for t in test_mbox_ring_keep_real_reports_r1651 test_mbox_drops_seen_window_r1663; do
    bash "$HERE/$t.sh" >/dev/null 2>&1 || { bad "⑤ $t rc≠0"; return 1; }
  done
  ok "⑤ 버림 0 → stderr 0 · QUEUED 꼴 그대로 · r1651·r1663 rc0"; return 0
}

for c in c1 c2 c3 c4 c5; do s=$SECONDS; $c; echo "  ($c $((SECONDS-s))s)"; done

# ── 변이 대조: 변이 사본 = FAIL · 원본 = PASS (반대 결과)
mut_check() {   # mut_check <변이> <사례함수>
  local mrc orc
  ( MUT="$1"; "$2" ) >/dev/null 2>&1; mrc=$?
  ( MUT=""; "$2" ) >/dev/null 2>&1; orc=$?
  if [ "$mrc" != 0 ] && [ "$orc" = 0 ]; then ok "변이 $1 → $2 FAIL · 원본 PASS"; else bad "변이 $1 mut_rc=$mrc orig_rc=$orc"; fi
}
mut_check mut_m1 c1
mut_check mut_m2 c4

echo "결과: fail=$fail"; [ "$fail" = 0 ]
