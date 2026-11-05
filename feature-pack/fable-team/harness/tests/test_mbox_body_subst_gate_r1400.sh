#!/usr/bin/env bash
# test_mbox_body_subst_gate_r1400.sh — r1400: ①docker 지우기 차단(block-destructive PATTERN) ②쪽지 본문 명령 치환 차단(mbox-body-subst-gate)
# PreToolUse JSON 만 넣어 종료코드를 본다 — 실제 docker·DB·쪽지 송신 0 (명령은 JSON 문자열일 뿐).
# 반례 G1~G12 + 경계 + 변이(복사본에서 결과가 뒤집혀야 시험이 «잡는 힘»이 있다).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
BD="${BD_HOOK:-$ROOT/harness/kit/fable-team/templates/hooks/block-destructive.sh}"
MBG="${MBG_HOOK:-$ROOT/harness/kit/fable-team/templates/hooks/mbox-body-subst-gate.sh}"
T="$(mktemp -d)"
trap '[ -n "$T" ] && rm -rf "$T"' EXIT
git -C "$T" init -q
mkdir -p "$T/.fable-team/comm"
: > "$T/.fable-team/comm/mbox.sh"
MB="$T/.fable-team/comm/mbox.sh"
cp "$(dirname "$BD")/block-destructive-judge.py" "$(dirname "$BD")/block_destructive_hil.py" "$T/" 2>/dev/null || true
fail=0; nb=0; np=0; nm=0

run() {  # <훅> <명령> [JSON cwd — 기본 임시 리포] → 종료코드 (셔뱅 그대로 /bin/bash)
  python3 -c 'import json,sys
d={"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}
if sys.argv[3]!="-": d["cwd"]=sys.argv[3]
print(json.dumps(d))' "$1" "$2" "${3:-$T}" | /bin/bash "$1" >/dev/null 2>&1
  return $?
}
expect() {  # <id> <훅> <기대 rc> <카운터> <명령>
  local id="$1" hook="$2" want="$3" ctr="$4" cmd="$5" rc
  run "$hook" "$cmd"; rc=$?
  if [ "$rc" = "$want" ]; then echo "PASS [$id] rc=$rc :: ${cmd:0:70}"; eval "$ctr=\$(($ctr+1))"
  else echo "FAIL [$id] want=$want got=$rc :: $cmd"; fail=$((fail+1)); fi
}
rawrun() {  # <훅> <stdin 원문> → 종료코드 (JSON 깨짐 경로)
  printf '%s' "$2" | /bin/bash "$1" >/dev/null 2>&1
  return $?
}
blk() { expect "$1" "$2" 2 nb "$3"; }
pas() { expect "$1" "$2" 0 np "$3"; }
mut() {  # <출력> <바꿀 글자> <새 글자> — 변이 복사본 (적용 안 되면 시험 실패)
  python3 -c 'import sys
t=open(sys.argv[1]).read()
if sys.argv[3] not in t: sys.exit(1)
open(sys.argv[2],"w").write(t.replace(sys.argv[3],sys.argv[4],1))' "$BD" "$1" "$2" "$3" \
    || { echo "FAIL [변이 미적용] $1"; fail=$((fail+1)); }
}
mutg2() {  # <출력> <바꿀 글자1> <새 글자1> <바꿀 글자2> <새 글자2> — 게이트 훅 변이 복사본(두 곳)
  python3 -c 'import sys
t=open(sys.argv[1]).read()
for a,b in ((sys.argv[3],sys.argv[4]),(sys.argv[5],sys.argv[6])):
    if a not in t: sys.exit(1)
    t=t.replace(a,b,1)
open(sys.argv[2],"w").write(t)' "$MBG" "$@" \
    || { echo "FAIL [변이 미적용] $1"; fail=$((fail+1)); }
}
mutg() {  # <출력> <바꿀 글자> <새 글자> — 게이트 훅 변이 복사본
  python3 -c 'import sys
t=open(sys.argv[1]).read()
if sys.argv[3] not in t: sys.exit(1)
open(sys.argv[2],"w").write(t.replace(sys.argv[3],sys.argv[4],1))' "$MBG" "$1" "$2" "$3" \
    || { echo "FAIL [변이 미적용] $1"; fail=$((fail+1)); }
}

# ── G1·G2 docker 지우기 차단 (block-destructive) ─────────────────────────
blk G1 "$BD" 'docker volume prune -f'
blk G2a "$BD" 'docker system prune -af'
blk G2b "$BD" 'docker rm -f abc'
blk G2c "$BD" 'docker rmi img'
blk G2d "$BD" 'docker compose down -v'
blk G2e "$BD" 'docker volume rm v1'
blk G2f "$BD" 'docker container prune'
blk G2g "$BD" 'docker compose -f x.yml down --volumes'
# ── G3 치환 + docker = 두 훅 다 막는다 ──────────────────────────────────
blk G3a "$BD" "bash $MB send A#1 B#1 \"요청: \$(docker volume prune -f)\""
blk G3b "$MBG" "bash $MB send A#1 B#1 \"요청: \$(docker volume prune -f)\""
# ── G6·G7 쪽지 본문 명령 치환 0 (위험 명령이 아니어도) ───────────────────
blk G6 "$MBG" "bash $MB send A#1 B#1 \"날짜 \$(date)\""
blk G7 "$MBG" 'bash '"$MB"' send A#1 B#1 "x `uptime`"'
# ── 경계: 본문 자리 판정 (arg 위치·relay 요약·여러 구간·홑/겹따옴표 밖) ──
blk B1 "$MBG" "bash $MB send A#1 B#1 \"날짜 \$(date)\" --urgent"
blk B2 "$MBG" "bash $MB send A#1 B#1 ok; bash $MB send C#1 D#1 \"날짜 \$(date)\""
blk B3 "$MBG" "bash $MB relay A#1 B#1 /tmp/f \"요약 \$(date)\""
blk B4 "$MBG" "bash $MB send A#1 B#1 \$(date)"
blk B5 "$MBG" $'cat <<EOF\nbash mbox.sh send A#1 B#1 "$(date)"\nEOF'
blk B6 "$MBG" "bash $T/bin/ft-mbox.sh send A#1 B#1 \"x \$(date)\""
# ── G12 사본 DB 예외 밖 (block-destructive) ─────────────────────────────
blk G12a "$BD" 'dropdb t_x prod_db'
blk G12b "$BD" 'psql -c "DROP DATABASE byz"'
blk G12c "$BD" 'dropdb "$DB"'
blk G12d "$BD" 'dropdb --if-exists t_x snap_y byz'
# ── G4 조회는 통과 ─────────────────────────────────────────────────────
pas G4a "$BD" 'docker volume ls'
pas G4b "$BD" 'docker ps -a'
pas G4c "$BD" 'docker compose down'
pas G4d "$BD" 'docker compose up -d'
# ── G5 글자만 있는 본문 (판정 466 글 싱크) ──────────────────────────────
pas G5a "$BD" "bash $MB send A#1 B#1 \"docker volume prune 승인 부탁\""
pas G5b "$MBG" "bash $MB send A#1 B#1 \"docker volume prune 승인 부탁\""
# ── G8 파일 읽기 예외 ──────────────────────────────────────────────────
pas G8a "$MBG" "bash $MB send A#1 B#1 \"\$(cat /tmp/body.txt)\""
pas G8b "$MBG" "bash $MB send A#1 B#1 \"\$(< /tmp/body.txt)\""
pas G8c "$MBG" "bash $MB relay A#1 B#1 /tmp/f \"\$(cat /tmp/f)\""
# ── G9 홑따옴표 = 글자 ────────────────────────────────────────────────
pas G9a "$MBG" "bash $MB send A#1 B#1 'literal \$(x) 글자'"
pas G9b "$MBG" 'bash '"$MB"' send A#1 B#1 '"'"'백틱 `uptime` 글자'"'"''
# ── G10 h 계획 실행 ───────────────────────────────────────────────────
pas G10 "$MBG" 'bash /tmp/h12'
pas G10b "$MBG" "bash $MB recv A#1"
# ── G11 사본 DB(t_·snap_) 지우기만 통과 ────────────────────────────────
pas G11a "$BD" 'docker exec pg dropdb -U postgres t_loom_1'
pas G11b "$BD" 'psql -c "DROP DATABASE IF EXISTS snap_r5"'
pas G11c "$BD" 'dropdb -h h.example.com -p 5432 --if-exists snap_t1'
# ── fail-open: JSON 깨짐 = 허용 · 단 «쪽지 송신 + 치환 글자» 는 막는다 ────
rawrun "$MBG" 'not json' && np=$((np+1)) || { echo "FAIL [F1] want=0"; fail=$((fail+1)); }
rawrun "$MBG" 'not json mbox.sh send A B "$(date)"'; [ $? = 2 ] && nb=$((nb+1)) || { echo "FAIL [F2] want=2"; fail=$((fail+1)); }
pas F3 "$MBG" 'echo "bash mbox.sh send A B \"\$(date)\""'
pas F4 "$MBG" 'grep -n "mbox.sh send" f'

# ── 변이: 결과가 뒤집히면 시험이 잡는다 ────────────────────────────────
mut "$T/m1.sh" '|docker +volume +(rm|prune)|docker +(container +)?rm|docker +(system|container|image|volume|builder) +prune|docker +rmi|docker +compose[^;&|]* +down[^;&|]*(-v|--volumes)' ''                                              # docker PATTERN 삭제
expect M1 "$T/m1.sh" 0 nm 'docker volume prune -f'
mutg "$T/m2.sh" '    return any(k in ("u", "d") and ("`" in t or "$(" in t) for k, t in tok)' '    return False'   # 치환 검사 삭제
expect M2a "$T/m2.sh" 0 nm "bash $MB send A#1 B#1 \"날짜 \$(date)\""
expect M2b "$T/m2.sh" 0 nm 'bash '"$MB"' send A#1 B#1 "x `uptime`"'
mutg "$T/m3.sh" '    if len(tok) == 1 and tok[0][0] == "d" and EXC.match(tok[0][1]):' '    if False and len(tok) == 1:'   # 파일 읽기 예외 삭제
expect M3 "$T/m3.sh" 2 nm "bash $MB send A#1 B#1 \"\$(cat /tmp/body.txt)\""
mutg2 "$T/m4.sh" '    if kinds and all(k == "s" for k in kinds):' '    if False:' '    return any(k in ("u", "d") and ("`" in t or "$(" in t) for k, t in tok)' '    return any("`" in t or "$(" in t for _, t in tok)'   # 홑따옴표 구분 삭제
expect M4 "$T/m4.sh" 2 nm "bash $MB send A#1 B#1 'literal \$(x) 글자'"
mut "$T/m5.sh" 'sys.stdout.write("".join(res))' 'sys.stdout.write(s)'                        # 예외 1 삭제
expect M5 "$T/m5.sh" 2 nm 'docker exec pg dropdb -U postgres t_loom_1'
mut "$T/m6.sh" 'return bool(pos) and all(ok(x) for x in pos)' 'return bool(pos) and any(ok(x) for x in pos)'   # 이름 하나만 접두면 통과
expect M6 "$T/m6.sh" 0 nm 'dropdb t_x prod_db'

echo "SUMMARY blocked=$nb pass=$np mutant=$nm fail=$fail"
[ "$nb" -eq 23 ] && [ "$np" -eq 19 ] && [ "$nm" -eq 7 ] && [ "$fail" -eq 0 ] || { echo "FAIL 표 미달 또는 실패 있음"; exit 1; }
echo "OK"
