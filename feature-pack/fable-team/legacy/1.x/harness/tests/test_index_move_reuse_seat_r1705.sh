#!/usr/bin/env bash
# test_index_move_reuse_seat_r1705.sh — r1705: 재사용(대기→진행 --seat) 때 그 좌석 명부 index 가 «지금 카드» 로 바뀐다(옛 값 = index_prev).
#   ① 좌석 N(index=A) · B 대기→진행 --seat N → N.index=진행/B · index_prev=[A] (기준판 = index A 그대로)
#   ② ① 뒤 명부에서 N 의 index 이름 = B(첫 카드 A 아님) → 완성 이동(B)이 닫을 좌석이 N · A 완성 이동은 N 을 못 찾는다(명부 기준)
#   ③ (② 의 반대) A 를 완성 이동해도 N 은 index 로 안 잡힌다  ④ role≠nano 좌석 → 명부 손 0 · INFO 1줄 · 이동 rc0
#   ⑤ 같은 이동 두 번 → 두 번째 손 0 · index_prev 중복 0  ⑥ 명부 경로가 없음(FT_SEATS_JSON 없는 경로) → 이동은 되고 손 0 INFO · 쓰기 실패면 REJECT·원본 보존
#   ⑦ aifp 꼴 루트(seats-aifp.json · aifp-ft-nano- 좌석) → ①과 같은 결과
#   변이(사본 · 변이마다 원본 대조): W1 index 갱신 삭제 → ① FAIL · W2 role 검사 삭제 → ④ FAIL · W3 멱등 검사 삭제 → ⑤ FAIL
# 임시 루트(TEAMS.md·명부·대기 카드)만 · 실 명부·라이브 bin 쓰기 0 · sleep 0
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:0:300}"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
RT="$T/rt"; mkdir -p "$RT"; cp "$BIN"/* "$RT/" 2>/dev/null; printf '#!/bin/sh\nexit 0\n' > "$RT/ft-index-lint.sh"   # lint 는 이 카드 범위 밖 — 시험 격리용 스텁
TOOL="$RT/ft-index-move.sh"
mkroot() {  # mkroot <이름> <팀> <좌석 접두>
  local d="$T/$1" t="$2" pfx="$3"
  mkdir -p "$d/design/$t/indices/대기" "$d/design/$t/indices/진행" "$d/design/$t/indices/완성" "$d/.fable-team"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| %s | `design/%s/` | byz-%s-master-pi#1 | 현역 |\n' "$t" "$t" "$t" > "$d/design/TEAMS.md"
  git -C "$d" init -q -b main; git -C "$d" add -A; git -C "$d" commit -qm init
  card "$d" "$t" A; card "$d" "$t" B
  printf '%s' "$d"
}
card() { printf '# 인덱스: %s\n\n## 골 원문 (항상 이 3줄)\n한 줄\n두 줄\n세 줄\n\n## 상태\n- 대기\n' "$3" > "$1/design/$2/indices/대기/$3.md"; }
roster() {  # roster <루트> <팀> <좌석> <role> <index>
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json, sys
root, team, seat, role, idx = sys.argv[1:6]
p = "%s/.fable-team/seats-%s.json" % (root, team)
doc = {"_master": "byz-%s-master-pi#1" % team, seat: {"role": role, "agent": "pi", "index": idx}}
json.dump(doc, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
}
rown() { python3 - "$1" "$2" <<'PY'
import json, sys
try: d = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError): print("ERR"); raise SystemExit(0)
r = d.get(sys.argv[2]) or {}
print("%s|%s" % (r.get("index", ""), ",".join(r.get("index_prev") or [])))
PY
}
mv_() { OUT="$( cd "$1" && FT_SEATS_JSON="${2:-}" bash "$TOOL" "$3" 진행 --seat "$4" 2>&1 )"; RC=$?; }
H="design/harness/indices"; A="$H/대기/A.md"; B="$H/대기/B.md"
# ① 재사용 = 명부 index 가 새 카드로
R1="$(mkroot h harness byz-harness-nano-x)"; S1='byz-harness-nano-x#0'
roster "$R1" harness "$S1" nano "$H/대기/A.md"
mv_ "$R1" "$R1/.fable-team/seats-harness.json" "$A" "$S1"
[ "$RC" = 0 ] && [ "$(rown "$R1/.fable-team/seats-harness.json" "$S1")" = "$H/진행/A.md|$H/대기/A.md" ] && ok "① 첫 이동(A) = index 진행/A · index_prev=[대기/A]" || bad "①A" "rc=$RC $(rown "$R1/.fable-team/seats-harness.json" "$S1") :: $OUT"
mv_ "$R1" "$R1/.fable-team/seats-harness.json" "$B" "$S1"
[ "$RC" = 0 ] && [ "$(rown "$R1/.fable-team/seats-harness.json" "$S1")" = "$H/진행/B.md|$H/대기/A.md,$H/진행/A.md" ] && ok "① 재사용(B) → index 진행/B · index_prev=[대기/A, 진행/A]" || bad "①" "rc=$RC $(rown "$R1/.fable-team/seats-harness.json" "$S1") :: $OUT"
# ②③ 명부 기준 — 완성 이동이 닫을 좌석은 «index 이름» 카드(B) 하나뿐이다
[ "$(basename "$(rown "$R1/.fable-team/seats-harness.json" "$S1" | cut -d'|' -f1)" .md)" = B ] \
  && ok "② 명부 index 이름 = B → B 완성 이동이 이 좌석을 닫는다" || bad "②" "$(rown "$R1/.fable-team/seats-harness.json" "$S1")"
[ "$(basename "$(rown "$R1/.fable-team/seats-harness.json" "$S1" | cut -d'|' -f1)" .md)" != A ] \
  && ok "③ A 완성 이동은 이 좌석을 못 찾는다(첫 카드 아님)" || bad "③" "$(rown "$R1/.fable-team/seats-harness.json" "$S1")"
# ④ role≠nano → 명부 손 0 · INFO
R4="$(mkroot h2 harness byz-harness-master)"; S4='byz-harness-master-pi#1'
roster "$R4" harness "$S4" master "$H/대기/A.md"
mv_ "$R4" "$R4/.fable-team/seats-harness.json" "$A" "$S4"
[ "$RC" = 0 ] && [ "$(rown "$R4/.fable-team/seats-harness.json" "$S4")" = "$H/대기/A.md|" ] && case "$OUT" in *"명부 index 손 0"*) true;; *) false;; esac \
  && ok "④ role=master → 명부 손 0 · INFO 1줄 · 이동 rc0" || bad "④" "rc=$RC $(rown "$R4/.fable-team/seats-harness.json" "$S4") :: $OUT"
# ⑤ 멱등
mv_ "$R1" "$R1/.fable-team/seats-harness.json" "$B" "$S1"; O1="$(rown "$R1/.fable-team/seats-harness.json" "$S1")"
[ "$O1" = "$H/진행/B.md|$H/대기/A.md,$H/진행/A.md" ] && ok "⑤ 같은 카드 재이동 → index·index_prev 그대로(중복 0)" || bad "⑤" "$O1"
# ⑥ 명부를 «명시» 했는데 없다 → REJECT rc≠0 · 쓰기 0(카드 ⑥ · 하드 룰 20) · 팀을 못 풀어 명부가 아예 없을 때만 INFO 손 0
R6="$(mkroot h3 harness byz-harness-nano-y)"; S6='byz-harness-nano-y#0'
mv_ "$R6" "$T/없는명부.json" "$A" "$S6"
[ "$RC" != 0 ] && case "$OUT" in *"REJECT 명부 없음"*) true;; *) false;; esac && [ ! -f "$T/없는명부.json" ] \
  && ok "⑥ 명시한 명부 없음 → REJECT rc≠0 · 명부 파일 0" || bad "⑥" "rc=$RC :: $OUT"
# ⑦ aifp 꼴 루트
R7="$(mkroot aifp aifp aifp-ft-nano)"; S7='aifp-ft-nano-r1675-x#0'; H7='design/aifp/indices'
roster "$R7" aifp "$S7" nano "$H7/대기/A.md"
mv_ "$R7" "$R7/.fable-team/seats-aifp.json" "$H7/대기/B.md" "$S7"
[ "$RC" = 0 ] && [ "$(rown "$R7/.fable-team/seats-aifp.json" "$S7")" = "$H7/진행/B.md|$H7/대기/A.md" ] && ok "⑦ aifp 루트도 같은 결과" || bad "⑦" "rc=$RC $(rown "$R7/.fable-team/seats-aifp.json" "$S7") :: $OUT"
# ⑧(ⓒ) 명부 꼴(indent 2 + 끝 줄바꿈) 보존 — 옮긴 뒤 diff = index·index_prev 줄만
R8b="$(mkroot h6 harness byz-harness-nano-w)"; S8b='byz-harness-nano-w#0'
python3 - "$R8b/.fable-team/seats-harness.json" "$S8b" "$H/대기/A.md" <<'PY'
import json, sys
p, seat, idx = sys.argv[1:4]
doc = {"_master": "byz-harness-master-pi#1", seat: {"role": "nano", "agent": "pi", "index": idx, "tick": None}}
open(p, "w", encoding="utf-8").write(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
PY
cp "$R8b/.fable-team/seats-harness.json" "$T/ro-before.json"
mv_ "$R8b" "$R8b/.fable-team/seats-harness.json" "$B" "$S8b"
python3 - "$T/ro-before.json" "$R8b/.fable-team/seats-harness.json" "$S8b" <<'PY'
import json, sys
a, b, seat = sys.argv[1:4]
def load(p):
    d = json.load(open(p, encoding="utf-8")); r = d.get(seat) or {}
    for k in ("index", "index_prev"): r.pop(k, None)
    return d
raw = open(b, encoding="utf-8").read()
ok = load(a) == load(b) and '"index"' in raw and raw.endswith("\n") and raw.split("\n")[1].startswith("  ")
raise SystemExit(0 if ok else 1)
PY
_p8=$?   # python 검사 결과를 «바로» 잡는다(전에는 $? 가 앞 [ ] 결과라 헛 PASS)
[ "$RC" = 0 ] && [ "$_p8" = 0 ] && ok "⑧ 명부 꼴 보존(indent 2 · 끝 줄바꿈) · 다른 키 변화 0" || bad "⑧" "rc=$RC py=$_p8"
# 변이 W1~W3 (사본 · 원본 대조)
mut() { R="$T/m-$1"; rm -rf "$R"; mkdir -p "$R"; cp "$BIN"/* "$R/" 2>/dev/null; printf '#!/bin/sh\nexit 0\n' > "$R/ft-index-lint.sh"; python3 - "$R/ft-index-move.sh" "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text(); k = sys.argv[2]
def sub(o, n):
    global s
    assert s.count(o) == 1, o[:50]
    s = s.replace(o, n, 1)
if k == "W1":   # index 갱신 삭제
    sub('  seat_index_follow "$SEAT" "$NEW"', '  :')
elif k == "W2":  # role 검사 뒤집기
    sub('row.get("role") != "nano"', 'row.get("role") == "nano"')
elif k == "W4":  # indent 삭제(1줄로 다시 씀) → ⑧ 꼴 깨짐
    sub('ensure_ascii=False, indent=2) + "\\n"); os.replace(tmp, p)', 'ensure_ascii=False) + "\\n"); os.replace(tmp, p)')
elif k == "W3":  # 멱등·중복 방지 둘 다 삭제(그래야 두 번째 이동이 index_prev 를 또 쌓는다)
    sub('if old == rel: print("INFO 명부 index 그대로 — %s" % rel); sys.exit(0)', 'pass')
    sub('if old and old not in prev: row["index_prev"] = prev + [old]', 'if old: row["index_prev"] = prev + [old]')
p.write_text(s)
PY
}
mutx() { OUT="$( cd "$1" && FT_SEATS_JSON="$1/.fable-team/seats-$5.json" bash "$T/m-$2/ft-index-move.sh" "$3" 진행 --seat "$4" 2>&1 )"; RC=$?; }
R8="$(mkroot h4 harness byz-harness-nano-z)"; S8='byz-harness-nano-z#0'
roster "$R8" harness "$S8" nano "$H/대기/A.md"; mut W1; mutx "$R8" W1 "$A" "$S8" harness
[ "$(rown "$R8/.fable-team/seats-harness.json" "$S8")" = "$H/대기/A.md|" ] && ok "W1 index 갱신 삭제 → ① 안 바뀜(변이 잡힘)" || bad "W1" "$(rown "$R8/.fable-team/seats-harness.json" "$S8")"
R9="$(mkroot h5 harness byz-harness-master2)"; S9='byz-harness-master-pi#9'
roster "$R9" harness "$S9" master "$H/대기/A.md"; mut W2; mutx "$R9" W2 "$A" "$S9" harness
case "$(rown "$R9/.fable-team/seats-harness.json" "$S9")" in "$H/진행/A.md|"*) ok "W2 role 검사 삭제 → ④ 가 명부를 바꿈(변이 잡힘)";; *) bad "W2" "$(rown "$R9/.fable-team/seats-harness.json" "$S9")";; esac
card "$R8" harness C; roster "$R8" harness "$S8" nano "$H/진행/C.md"   # 명부가 이미 그 카드 = 재실행 꼴
mv_ "$R8" "$R8/.fable-team/seats-harness.json" "$H/대기/C.md" "$S8"; ONCE="$(rown "$R8/.fable-team/seats-harness.json" "$S8")"
[ "$RC" = 0 ] && [ "$ONCE" = "$H/진행/C.md|" ] && ok "⑤b 멱등 원본 대조: 명부가 이미 그 카드 → 손 0" || bad "⑤b" "rc=$RC $ONCE"
card "$R8" harness C2; roster "$R8" harness "$S8" nano "$H/진행/C2.md"; ONCE2="$(rown "$R8/.fable-team/seats-harness.json" "$S8")"
mut W3; mutx "$R8" W3 "$H/대기/C2.md" "$S8" harness
[ "$(rown "$R8/.fable-team/seats-harness.json" "$S8")" != "$ONCE2" ] && ok "W3 멱등 검사 삭제 → index_prev 가 또 쌓임(변이 잡힘)" || bad "W3" "$ONCE2"
R8c="$(mkroot h7 harness byz-harness-nano-v)"; S8c='byz-harness-nano-v#0'
python3 - "$R8c/.fable-team/seats-harness.json" "$S8c" "$H/대기/A.md" <<'PY'
import json, sys
p, seat, idx = sys.argv[1:4]
open(p, "w", encoding="utf-8").write(json.dumps({"_master": "m#1", seat: {"role": "nano", "index": idx}}, ensure_ascii=False, indent=2) + "\n")
PY
mut W4; mutx "$R8c" W4 "$B" "$S8c" harness
diff "$T/ro-before.json" "$R8c/.fable-team/seats-harness.json" >/dev/null 2>&1; D4=$?
[ "$(awk 'END{print NR}' "$R8c/.fable-team/seats-harness.json")" = 1 ] && ok "W4 indent 삭제 → ⑧ 꼴 깨짐(1줄 · 변이 잡힘)" || bad "W4" "$(head -c 80 "$R8c/.fable-team/seats-harness.json")"
cmp -s "$BIN/ft-index-move.sh" "$BIN/../kit/fable-team/bin/ft-index-move.sh" && ok "bin·kit cmp0" || bad "bin·kit 다름" ""
echo "단계 합계 ${SECONDS}s"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
