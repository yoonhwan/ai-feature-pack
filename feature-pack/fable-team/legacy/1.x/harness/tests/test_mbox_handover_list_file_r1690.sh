#!/usr/bin/env bash
# test_mbox_handover_list_file_r1690.sh — r1690 [fix]: 승계 [인계] 본문 ≤ 2,000자 · 남은 쪽지 id 는 <state>/handover/ 목록 파일 · 본문엔 «목록: <경로>» 1줄.
#  ⓐ 크기(쪽지 84·질문 3·억제 1) · ⓑ 레디 항목 88 · ⓒ 84통 «인계» 표시 · ⓓ 미받음 재적재(목록 줄 포함) · ⓔ 목록 파일 없음 = REJECT rc 3 1줄·[레디] 0
#  ⓕ 질문 30 = 앞 5 본문·25 목록 «질문» 절 · ⓗ 손 항목 설명 = 목록 «손 항목» 절 · ⓘ 줄여도 넘으면 REJECT rc 3 · 변이 N1~N6(사본) · 격리: 정본 사본 + 가짜 명부 + 임시 우편함 · sleep 0
#  R1690_SRC=<comm 폴더> 로 다른 판(예: 고치기 전)을 돌릴 수 있다 — 본문 바이트 줄(SIZE)은 그때 비교용.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="${R1690_SRC:-$REPO/harness/comm}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
printf '#!/bin/sh\n[ "$1 $2" = "--pending --each" ] && exit 0\nexit 2\n' > "$T/stub/ft-hil.sh"
O=byz-lf-old-pi#1; N=byz-lf-new-pi#2

new_env() {   # new_env [변이함수] — 옛 좌석 현역(handover 가 큐를 끝까지 recv 한다)
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; SD="$ENVROOT/.fable-team/state"
  mkdir -p "$C" "$SD/doorbell-held" "$ENVROOT/seats"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"; printf '{}\n' > "$ENVROOT/seats/seats.json"; : > "$C/mailbox.jsonl"
  python3 - "$ENVROOT/seats/seats-lf.json" "$O" "$N" <<'PY'
import json, sys
p, o, n = sys.argv[1:4]
json.dump({"_master": o, o: {"role": "master"}, n: {"role": "master"}}, open(p, "w", encoding="utf-8"))
PY
  [ -z "${1:-}" ] || "$1" || { bad "변이 $1 적용 실패(사본에 대상 문자열 없음)"; return 2; }
}
retire() { python3 -c 'import json,sys;p,o,n=sys.argv[1:4];json.dump({"_master":n,o:{"role":"stop-ready","_replaced_by":n},n:{"role":"master"}},open(p,"w",encoding="utf-8"))' "$ENVROOT/seats/seats-lf.json" "$O" "$N"; }   # ready 관문 = 옛 좌석 은퇴 먼저
fill() {   # fill <질문 수> <쪽지 수> [억제 seq] — 질문 seq 1..Q · 쪽지 seq Q+1.. (본문 각 300자)
  python3 - "$C/mailbox.jsonl" "$O" "$1" "$2" <<'PY'
import json, sys
p, o, q, m = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
with open(p, "a", encoding="utf-8") as f:
    for s in range(1, q + m + 1):
        r = {"seq": s, "ts": "2026-11-11T00:00:00", "to": o, "from": "slack-oppa" if s <= q else "byz-lf-peer-pi#3",
             "body": ("[HIL] 질문 %d " % s if s <= q else "[회신] 쪽지 %d " % s) + "가" * 300}
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
  [ -z "${3:-}" ] || printf 'held ts=1790000000 reason=held window=1 seat=%s\nseq=%s\n' "$O" "$3" > "$SD/doorbell-held/$O"
}
xenv() { ( unset FT_PLANNER_HEAD_MODE
  export PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats-lf.json" FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$SD"
  export FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/bin/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py" FT_HIL_BIN="$T/stub/ft-hil.sh"
  "$@" ); }
sh_() { OUT="$(cd "$ENVROOT" && xenv timeout 20 bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
py_() { OUT="$(cd "$ENVROOT" && xenv timeout 20 python3 "$C/mbox.py" "$@" 2>&1)"; RC=$?; }
lastbody() { python3 -c 'import json,sys;h=sys.argv[2];print([r for r in (json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()) if r["body"].startswith(h)][-1]["body"])' "$C/mailbox.log.jsonl" "${1:-[인계]}" 2>/dev/null; }
nready() { python3 -c 'import json,sys;print(sum(json.loads(l)["body"].startswith("[레디]") for l in open(sys.argv[1],encoding="utf-8") if l.strip()))' "$C/mailbox.log.jsonl" 2>/dev/null || echo 0; }
listf() { printf '%s\n' "$1" | sed -n 's/^목록: \(.*\) · 남은.*/\1/p'; }
blen() { python3 -c 'import sys;print(len(sys.argv[1]))' "$1"; }
sub() {   # sub <파일> <옛 문자열> <새 문자열> — 사본만 바꾼다 · 못 찾으면 rc 1(변이 무효)
  python3 - "$@" <<'PY'
import sys
p, a, b = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
if a not in s: sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
mut_n1() { sub "$C/mbox_handover.py" '(ids if len(ids) <= INLINE_MAX else []), (ids if len(ids) > INLINE_MAX else [])' 'ids, []'; }
mut_n2() { sub "$C/mbox_handover.py" 'for m in ITEM.finditer(b)] + _list_ids(b)' 'for m in ITEM.finditer(b)]'; }
mut_n3() { sub "$C/mbox.sh" 'FT_MBOX_STATE_DIR="$(_wg_state)" python3 "$DIR/mbox_handover.py" mark-ids)"' "sed -n 's/^항목://p' | tr ' ' '\\n' | sed -n 's/^#\\([0-9][0-9]*\\)\$/\\1/p' | paste -sd, -)\""; }
mut_n4() { sub "$C/mbox_handover.py" 'sys.stderr.write("REJECT 목록 파일 판정 불가 %s\n" % m.group(1))' 'return []'; }

# ⓐ 크기 — 쪽지 84·질문 3·억제 1 → 본문 ≤ 2,000자 · «목록:» 1줄 · 파일 = 쪽지 줄 84 + 억제 1
chk_a() {
  new_env "${1:-}" || return 2; fill 3 84 999
  sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 1
  B="$(lastbody)"; echo "SIZE ⓐ 본문 $(blen "$B")자 $(printf '%s' "$B" | wc -c | tr -d ' ')바이트" >&2
  [ "$(blen "$B")" -le 2000 ] && [ "$(printf '%s\n' "$B" | grep -c '^목록: ')" = 1 ] || return 1
  F="$(listf "$B")"; [ -f "$F" ] || return 1
  [ "$(grep -cE '^#[0-9]+$' "$F")" = 84 ] && [ "$(grep -cx '#999!' "$F")" = 1 ] && case "$B" in *"· 항목 88 "*) ;; *) return 1;; esac
}
chk_a mut_n1 2>/dev/null && bad "N1 변이(쪽지 줄 다시 본문)가 ⓐ 에 안 잡힘" || ok "N1 변이 → ⓐ FAIL 확인"
chk_a && ok "ⓐ 본문 ≤ 2,000자 · 목록 1줄 · 파일 쪽지 84 + 억제 1" || bad "ⓐ rc=$RC :: $OUT :: $B"

# ⓑ 레디 — 후계 recv·ready → «[인계] #<seq> 받음 · 항목 88» + «<id> 받음» 88줄
chk_b() {
  new_env "${1:-}" || return 2; fill 3 84 999; sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 2
  retire; sh_ recv "$N"; sh_ ready "$N" "$O"; [ "$RC" = 0 ] || return 1
  B="$(lastbody '[레디]')"; case "$B" in "[레디] $N <- $O · [인계] #"*" 받음 · 항목 88"$'\n'*) ;; *) return 1;; esac
  [ "$(printf '%s\n' "$B" | grep -cE '^(#[0-9]+|h[0-9]+|bg:[A-Za-z0-9_.-]+) 받음$')" = 88 ] && printf '%s\n' "$B" | grep -qx '#999 받음'
}
chk_b mut_n2 && bad "N2 변이(items 가 목록 안 읽음)가 ⓑ 에 안 잡힘" || ok "N2 변이 → ⓑ FAIL 확인"
chk_b && ok "ⓑ [레디] 항목 88 = 머리 · «받음» 88줄(질문 3·쪽지 84·억제 1)" || bad "ⓑ rc=$RC :: $OUT :: $B"

# ⓒ 표시 — handover 뒤 질문 3 + 쪽지 84 «인계» · 억제 999 는 표시 대상 아님 · 미표시 0
chk_c() {
  new_env "${1:-}" || return 2; fill 3 84 999; sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 1
  case "$OUT" in *"MARKED $O 인계 "*) ;; *) return 1;; esac; case "$OUT" in *",999"*) return 1;; esac
  py_ unmarked "$O"; [ "$RC" = 0 ] && case "$OUT" in "UNMARKED 0"*) true;; *) false;; esac
}
chk_c mut_n3 && bad "N3 변이(표시 목록 = 본문만)가 ⓒ 에 안 잡힘" || ok "N3 변이 → ⓒ FAIL 확인"
chk_c && ok "ⓒ 87통 «인계» 표시 · 억제 999 제외 · 미표시 0" || bad "ⓒ rc=$RC :: $OUT"

# ⓓ 재적재 — 첫 [인계] 의 목록 줄 #10~#19 를 «받음» 에서 뺀 [레디] → 둘째 handover 는 그 10개만(목록 파일)
chk_d() {
  new_env || return 2; fill 3 84 999; sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 2
  H="$(printf '%s\n' "$OUT" | sed -n 's/.*QUEUED seq=\([0-9]*\).*/\1/p' | head -1)"; sh_ recv "$N"
  R="[레디] $N <- $O · [인계] #$H 받음 · 항목 78"; for s in 1 2 3 $(seq 4 9) $(seq 20 87) 999; do R+=$'\n'"#$s 받음"; done
  sh_ send "$O" "$N" "$R"; [ "$RC" = 0 ] || return 2
  sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 1; B="$(lastbody)"
  case "$B" in *"· 항목 10 "*) ;; *) return 1;; esac; F="$(listf "$B")"; [ -f "$F" ] || return 1
  [ "$(printf '%s\n' "$B" | xenv python3 "$C/mbox_handover.py" mark-ids | tr , '\n' | sort -n | paste -sd, -)" = "$(seq 10 19 | paste -sd, -)" ]
}
chk_d && ok "ⓓ 미받음 10개만 둘째 [인계] 목록 파일에 다시 실림" || bad "ⓓ rc=$RC :: $OUT :: $B"

# ⓔ 판정 불가 — 목록 파일을 지운 뒤 ready → REJECT rc 3 1줄 · [레디] 송신 0
chk_e() {
  new_env "${1:-}" || return 2; fill 3 84 999; sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 2
  F="$(listf "$(lastbody)")"; retire; sh_ recv "$N"; rm -f "$F"
  sh_ ready "$N" "$O"; [ "$RC" = 3 ] && [ "$OUT" = "REJECT 목록 파일 판정 불가 $F" ] && [ "$(nready)" = 0 ]
}
chk_e mut_n4 && bad "N4 변이(못 읽음 = 항목 0)가 ⓔ 에 안 잡힘" || ok "N4 변이 → ⓔ FAIL 확인"
chk_e && ok "ⓔ 목록 파일 없음 → REJECT rc 3 1줄 · [레디] 0" || bad "ⓔ rc=$RC :: $OUT"

# ⓕ 질문 30 → 본문 ≤ 2,000자 · 질문 앞 5 본문 · 나머지 25 목록 «질문» 절 · ready 항목 30
chk_f() {
  new_env || return 2; fill 30 0; sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 1
  B="$(lastbody)"; echo "SIZE ⓕ 본문 $(blen "$B")자" >&2; [ "$(blen "$B")" -le 2000 ] || return 1
  [ "$(printf '%s\n' "$B" | sed -n 's/^항목: *//p' | wc -w | tr -d ' ')" = 5 ] && case "$B" in *"질문 25 줄 포함"*) ;; *) return 1;; esac
  F="$(listf "$B")"; [ "$(head -1 "$F")" = "질문 25" ] && [ "$(grep -cE '^#[0-9]+$' "$F")" = 25 ] || return 1
  retire; sh_ recv "$N"; sh_ ready "$N" "$O"; [ "$RC" = 0 ] && case "$(lastbody '[레디]')" in *"· 항목 30"*) true;; *) false;; esac
}
chk_f && ok "ⓕ 질문 30 → 앞 5 본문 · 25 목록 «질문» 절 · [레디] 항목 30" || bad "ⓕ rc=$RC :: $OUT :: $B"

# ⓗ DA R1 반례(da_probe_r1690.sh 꼴) — 빈 우편함 · 손 항목 1개 «background-command »+x2100 → 본문 ≤ 2,000 · bg:x1 본문 · 원문은 목록 «손 항목» 절 · ready 항목 1
LONG="background-command $(printf 'x%.0s' $(seq 2100))"
mut_n5() { sub "$C/mbox_handover.py" 'if len(b) > BODY_MAX:   # r1690 R1ⓑ' 'if False:'; }
mut_n6() { sub "$C/mbox_handover.py" 'if len(b) > BODY_MAX and extra:' 'if False:'; }
chk_h() {
  new_env "${1:-}" || return 2; sh_ handover "$O" "$N" "$LONG"; [ "$RC" = 0 ] || return 1
  B="$(lastbody)"; echo "SIZE ⓗ 본문 $(blen "$B")자" >&2; [ "$(blen "$B")" -le 2000 ] && printf '%s\n' "$B" | grep -q '^- bg:x1 background-command ' || return 1
  F="$(listf "$B")"; [ -f "$F" ] && grep -qx '손 항목 1' "$F" && grep -qxF "bg:x1 $LONG" "$F" || return 1
  retire; sh_ recv "$N"; sh_ ready "$N" "$O"; [ "$RC" = 0 ] && case "$(lastbody '[레디]')" in *"· 항목 1"$'\n'"bg:x1 받음") true;; *) false;; esac
}
chk_h mut_n6 2>/dev/null && bad "N6 변이(손 항목 옮기기 삭제)가 ⓗ 에 안 잡힘" || ok "N6 변이 → ⓗ FAIL 확인"
chk_h && ok "ⓗ 손 항목 2,100자 → 본문 ≤ 2,000 · 원문 목록 «손 항목» 절 · [레디] 항목 1" || bad "ⓗ rc=$RC :: $OUT :: $B"

# ⓗ' formatter 직접 대조(외부 명령 0 · h·bg·recv 대역을 빈 값으로)
chk_hf() {
  new_env || return 2; mkdir -p "$C/receipts"
  ( cd "$C" && FT_MBOX_STATE_DIR="$SD" python3 - "$C" "$O" "$N" "$LONG" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
import mbox_handover as H
H.CANON = sys.argv[1]; H._h_items = lambda: ([], ""); H._bg_items = lambda o: []; H.mbox_lineage.retired_to = lambda o: "x"
b = H.handover_body(sys.argv[2], sys.argv[3], [sys.argv[4]])
print("FORMATTER %d자 items=%s" % (len(b), H.items({"body": b})), file=sys.stderr)
sys.exit(0 if len(b) <= 2000 and H.items({"body": b}) == ["bg:x1"] else 1)
PY
  )
}
chk_hf && ok "ⓗ' formatter 직접 — 본문 ≤ 2,000 · items=[bg:x1]" || bad "ⓗ' formatter 직접 대조"

# ⓘ 줄여도 넘는 꼴 — 손 항목 40개 × 80자 → REJECT rc 3 · QUEUED 0 · 인계 표시 0
chk_i() {
  new_env "${1:-}" || return 2; fill 0 3; local a=(); for k in $(seq 40); do a+=("$(printf 'cmd%02d-' "$k")$(printf 'y%.0s' $(seq 74))"); done
  sh_ handover "$O" "$N" "${a[@]}"; [ "$RC" = 3 ] && case "$OUT" in *"REJECT [인계] 본문 "*"자 > 2000 — 판정 불가"*) true;; *) false;; esac || return 1
  case "$OUT" in *QUEUED*|*MARKED*) return 1;; esac; [ -z "$(lastbody)" ] || return 1
  py_ unmarked "$O"; case "$OUT" in "UNMARKED 3"*) true;; *) false;; esac
}
chk_i mut_n5 && bad "N5 변이(최종 검사 삭제)가 ⓘ 에 안 잡힘" || ok "N5 변이 → ⓘ FAIL 확인"
chk_i && ok "ⓘ 손 항목 40×80자 → REJECT rc 3 · QUEUED 0 · 표시 0" || bad "ⓘ rc=$RC :: $OUT"

for f in "$SRC/mbox_handover.py" "$SRC/mbox.sh"; do case "$f" in *.sh) bash -n "$f" 2>/dev/null && ok "bash -n $(basename "$f")" || bad "bash -n $(basename "$f")";; *) python3 -c 'import sys,py_compile;py_compile.compile(sys.argv[1],doraise=True)' "$f" >/dev/null 2>&1 && ok "py_compile $(basename "$f")" || bad "py_compile $(basename "$f")";; esac; done
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
