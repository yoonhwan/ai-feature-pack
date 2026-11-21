#!/usr/bin/env bash
# test_approval_equiv_in_main_r2359.sh — r2359: 승인 세트의 변경이 «세트가 품은 main» 에 이미 다 들어갔으면 NOT-EQUIV 사유를 «이미 main 에 있음 · 착지할 것 0 · PR 닫기(재승인 0)» 로 낸다(판정 rc 그대로) · 사유 경로 utf-8 · 크리티컬 다음 손 = PR 닫기.
#   K1 이미 main 판별 ① main 이 A 와 같은 글(PR 10272 꼴) ② 한 파일만 반영 = 옛 글 ③ 손 편집 병합(트리만 같음) = 옛 글 ④ rebase 길 ⑤ in_main git rc128 · 7초 넘김 = 옛 글(판별 0 · rc 그대로)
#   K2 rc 그대로 ⑥ --many 줄도 같은 사유 · rc1   K3 사유 경로 글자 ⑦ NOT-EQUIV 사유 경로 «대기» utf-8 ⑧ EQUIV names= «대기» utf-8 · 그 밖 바이트 = 기준판
#   K4 다음 손 ⑨ ft-merge-land 사건 «이미 main 에 있음» → 다음 손 «착지할 것 0 · PR 닫기(재승인 0)» · «다시 승인» 0 ⑩ «자기 변경이 승인 때와 다름» → «지금 head sha 로 다시 승인» 그대로
#   K5 다른 길 그대로 ⑪ ASCII 경로 꼴(일반 커밋 · 규칙 3 · 승인 줄기+main 병합 아님) + ERROR → 출력 바이트·rc = 기준판과 같음
#   K1 세트가 품은 main ⑫ ① 뒤 main 이 더 감(m ≠ mx) → 그래도 «이미 main 에 있음 <mx 10자>»
#   변이 M1~M6 (사본에서만 · 변이마다 원본 BIN 대조): M1 ① in_main 부름 지움 · M2 ③ merge-tree 비교 지움 · M3 ④ rebased 쪽 부름 지움 · M4 ⑦⑧ shown 그대로 · M5 ⑨ LAND_NEXT 새 줄을 맨 뒤로 · M6 ⑫ mx 대신 m
#   ★⑪ 꼴 바꿈 근거★ «병합 커밋 없음» 은 sc == ac 조기 반환(check() 첫머리) 뒤라 도달 0 · «충돌» 갈래는 da != ds 로 규칙 3 에 먼저 걸려 손으로 만들기 어렵다 → 같은 ASCII 꼴 두 가지(규칙 3 · 승인 줄기+main 병합 아님)로 잡는다.
#   격리: 임시 git 리포(한글 폴더 카드 경로 · refs/remotes/origin/* 가짜 ref) · 가짜 comm·mbox·명부 · 실 PR·실 main·실 우편함 0 · sleep 0 · 시험 1개 70초.
#   기준판 Red(FT_TEST_BASE_BIN=<팩 origin/main bin 사본>) = ① · ④ · ⑥ · ⑦ · ⑨ · ⑫
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CRITICAL_OFF FT_CRITICAL_NOW FT_CRITICAL_DEDUPE_S FT_CRITICAL_STATE_DIR FT_MBOX_DIR FT_MBOX FT_ROOT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
EQP="${FT_TEST_EQUIV:-$BIN/ft_approval_equiv.py}"; NOTIFY="${FT_TEST_NOTIFY:-$BIN/ft-critical-notify.sh}"; BASE="${FT_TEST_BASE_BIN:-}"   # BASE = 고치기 전 판(팩 origin/main bin 사본) — 주면 기준판 대조도 돈다
OVR=""   # 변이 사본 폴더 — 있으면 그쪽 파일을 쓴다(사본에서만)
eqp() { if [ -n "$OVR" ] && [ -f "$OVR/ft_approval_equiv.py" ]; then printf '%s' "$OVR/ft_approval_equiv.py"; else printf '%s' "$EQP"; fi; }
nfn() { if [ -n "$OVR" ] && [ -f "$OVR/ft-critical-notify.sh" ]; then printf '%s' "$OVR/ft-critical-notify.sh"; else printf '%s' "$NOTIFY"; fi; }
withbin() { local d="$1"; shift; local o="$OVR"; OVR="$d"; "$@"; local r=$?; OVR="$o"; return $r; }   # withbin <bin 폴더> <함수…>
fail=0; rc=0; out=""; t0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
tc() { if "$2"; then ck "$1" 0; else ck "$1" 1; fi; }
basefail() {   # basefail <이름> <사례 함수> — 기준판(고치기 전)에서 그 사례가 FAIL 이어야 한다(못 가르는 시험 방지)
  [ -n "$BASE" ] || { echo "SKIP $1 기준판 대조(FT_TEST_BASE_BIN 없음)"; return 0; }
  if withbin "$BASE" "$2"; then ck "$1 — 기준판에서 PASS(고치기 전에도 통과 = 못 가름)" 1; else ck "$1 기준판 Red(정상)" 0; fi; }
has() { grep -qF -- "$1" <<<"$out"; }
exc() { ! grep -qF -- "$1" <<<"$out"; }
T0="$(mktemp -d)"; T="$(cd -- "$T0" && pwd -P)"; trap 'rm -rf "$T0"' EXIT
W="$T/w"; g() { git -C "$W" -c user.email=t@t -c user.name=t "$@"; }
C="design/teams/x/indices/대기/C.md"; E="design/teams/x/indices/대기/E.md"
w() { local f="$1"; shift; mkdir -p "$W/$(dirname "$f")"; printf '%s\n' "$@" > "$W/$f"; }   # w <경로> <줄…>
ci() { g add -A; g commit -qm "$1"; }
eqv() { out="$(python3 -I "$(eqp)" "$W" "$1" "$2" origin main 2>&1)"; rc=$?; }
many() { out="$(printf '%s\n' "$1" | python3 -I "$(eqp)" --many "$W" "$2" origin main 2>&1)"; rc=$?; }
rmref() { g update-ref refs/remotes/origin/main "$1"; }
mrg() { g checkout -q -B "$1" "$2"; g merge -q --no-edit "$3" >/dev/null 2>&1; g rev-parse HEAD; }   # mrg <새 가지> <시작> <병합할 가지> → sha
om() { g commit-tree "$(g rev-parse "$1^{tree}")" -p "$2" -m "$4" ${3:+-p "$3"}; }   # om <트리 출처> <첫 부모> [<둘째 부모>] <메시지> → sha
# ── 픽스처: base B(코드 5줄 · 대기 카드 C·E) → 승인 A(feat = B + 카드 2파일에 같은 글 «- 증거: a») · main 변형 가지들
git -c init.defaultBranch=main init -q "$W"; mkdir -p "$W/design/teams/x/indices/대기"
w code.txt L1 L2 L3 L4 L5; w "$C" '- 상태: 대기' '- 증거: 0' '- 다음: x' '- 근거: r' '- 끝: y'; w "$E" '- 증거: 0'; ci base; B="$(g rev-parse HEAD)"
g checkout -qb feat; w "$C" '- 상태: 대기' '- 증거: 0' '- 다음: x' '- 근거: r' '- 끝: y' '- 증거: a'; w "$E" '- 증거: 0' '- 증거: a'; ci A; A="$(g rev-parse HEAD)"
g checkout -q -B m1 "$B"; w "$C" '- 상태: 대기' '- 증거: 0' '- 다음: x' '- 근거: r' '- 끝: y' '- 증거: a'; w "$E" '- 증거: 0' '- 증거: a'; ci M1; M1="$(g rev-parse HEAD)"
g checkout -q -B m2 "$B"; w "$C" '- 상태: 대기' '- 증거: 0' '- 다음: x' '- 근거: r' '- 끝: y' '- 증거: a'; ci M2; M2="$(g rev-parse HEAD)"
g checkout -q -B mb "$B"; w code.txt L1 L2 L3 L4 M5; ci MB; MB="$(g rev-parse HEAD)"
g checkout -q -B m7 "$B"; w "$C" '- 상태: 대기' '- 증거: b' '- 다음: x' '- 근거: r' '- 끝: y'; w "$E" '- 증거: 0' '- 증거: a'; ci M7; M7="$(g rev-parse HEAD)"
g checkout -q -B m8 "$B"; w "$C" '- 상태: 대기' '- 증거: 0' '- 다음: y' '- 근거: r' '- 끝: y'; ci M8; M8="$(g rev-parse HEAD)"
g checkout -q -B m12 "$M1"; w docs/other.md o; ci M12; M12="$(g rev-parse HEAD)"
g checkout -q -B a11 "$B"; w code.txt L1 X2 L3 L4 L5; ci A11; A11="$(g rev-parse HEAD)"
g checkout -q -B m11 "$B"; w code.txt L1 L2 L3 L4 M5; ci M11; M11="$(g rev-parse HEAD)"
S1="$(mrg s1 "$A" m1)"; S2="$(mrg s2 "$A" m2)"; S7="$(mrg s7 "$A" m7)"; S8="$(mrg s8 "$A" m8)"; SM="$(mrg sm "$A" m8)"
S3="$(om "$MB" "$A" "$MB" '손 편집 병합')"   # ③ 트리 = main 트리 · 부모 = A + main
S4="$(om "$M1" "$M1" "" 'rebase')"
S11="$(om "$M11" "$A11" "$M11" '손 편집 병합(ASCII)')"   # ⑪b 규칙 3 자리(ASCII 경로 · 트리 = main · main 에 A 변경 0)"   # ④ A 를 main 위로 rebase 한 꼴(트리 = main 트리 · 부모 = main)
g checkout -q -B s9 "$A"; w notes.txt n; ci 일반커밋; S9="$(g rev-parse HEAD)"   # ⑪ 일반 커밋
t1=$SECONDS

# ① 이미 main(=세트가 품은 main) — 기준판 Red
c1() { rmref "$M1"; eqv "$A" "$S1"; [ "$rc" = 1 ] && has "이미 main 에 있음(S 트리 == 세트가 품은 main $(g rev-parse --short=10 "$M1")" && has "착지할 것 0 · PR 닫기(재승인 0)" && exc "자기 변경이 승인 때와 다름"; }
# ② 한 파일만 반영 = 옛 글
c2() { rmref "$M2"; eqv "$A" "$S2"; [ "$rc" = 1 ] && has "자기 변경이 승인 때와 다름" && exc "이미 main 에 있음"; }
# ③ 손 편집 병합(트리 == main · main 에는 A 변경 0) = 옛 글 (M2 가 살아 있으면 «이미 main» 으로 샌다)
c3() { rmref "$MB"; eqv "$A" "$S3"; [ "$rc" = 1 ] && has "자기 변경이 승인 때와 다름" && exc "이미 main 에 있음"; }
# ④ rebase 길 = «이미 main» (기준판 Red)
c4() { rmref "$M1"; eqv "$A" "$S4"; [ "$rc" = 1 ] && has "이미 main 에 있음" && has "착지할 것 0"; }
# ⑤ in_main 의 git 실패(rc128) · 7초 넘김 = 판별 0 · 옛 글 · rc 그대로
c5a() { rmref "$M1"; local o; o="$out"; out="$(PATH="$T/shim:$PATH" python3 -I "$(eqp)" "$W" "$A" "$S1" origin main 2>&1)"; rc=$?; [ "$rc" = 1 ] && has "자기 변경이 승인 때와 다름" && exc "이미 main 에 있음"; }
c5b() { rmref "$M1"; out="$(python3 -I - "$(eqp)" "$W" "$A" "$S1" <<'PY' 2>&1
import importlib.util, subprocess, sys
spec = importlib.util.spec_from_file_location("eq", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
real = subprocess.run
def fake(*a, **k):
    if "merge-tree" in a[0]: raise subprocess.TimeoutExpired(a[0], 7)
    return real(*a, **k)
m.subprocess.run = fake
try: print(m.check(sys.argv[2], sys.argv[3], sys.argv[4], "origin", "main"))
except m.No as e: print("NOT-EQUIV %s" % e); sys.exit(1)
PY
)"; rc=$?; [ "$rc" = 1 ] && has "자기 변경이 승인 때와 다름" && exc "이미 main 에 있음"; }
# ⑥ --many 줄도 같은 사유 · rc1 (기준판 Red)
c6() { rmref "$M1"; many "$A" "$S1"; [ "$rc" = 1 ] && has "$A NOT-EQUIV 이미 main 에 있음"; }
# ⑦ NOT-EQUIV 사유 경로 = utf-8 «대기» (기준판 Red)
c7() { rmref "$M7"; eqv "$A" "$S7"; [ "$rc" = 1 ] && has "자기 변경이 승인 때와 다름" && has "indices/대기/" && exc "ë"; }
# ⑧ EQUIV names= «대기» utf-8 · 그 밖 바이트 = 기준판
c8() { rmref "$M8"; eqv "$A" "$S8"; [ "$rc" = 0 ] && has "names=design/teams/x/indices/대기/C.md" && has "overlap=1" && exc "ë"; }
c8b() { local mine="$out" bo; rmref "$M8"; if [ -n "$BASE" ]; then withbin "$BASE" eqv "$A" "$S8"; bo="$out"; else withbin "$BIN" eqv "$A" "$S8"; bo="$out"; fi
  [ "$(sed 's/ names=.*$//' <<<"$mine")" = "$(sed 's/ names=.*$//' <<<"$bo")" ]; }
tc "① main 이 같은 글 → «이미 main 에 있음» rc1" c1
tc "② 1파일만 반영 → 옛 글 rc1" c2
tc "③ 손 편집 병합 → 옛 글 rc1" c3
tc "④ rebase 길 → «이미 main 에 있음» rc1" c4
mkdir -p "$T/shim"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" != merge-tree ] || exit 128; done\nexec "%s" "$@"\n' "$(command -v git)" > "$T/shim/git"
chmod +x "$T/shim/git"
tc "⑤a in_main git rc128 → 옛 글 rc1" c5a
tc "⑤b in_main merge-tree 7초 넘김 → 옛 글 rc1" c5b
tc "⑥ --many 줄도 «이미 main 에 있음» rc1" c6
tc "⑦ 사유 경로 utf-8 «대기»" c7
tc "⑧ EQUIV names= utf-8 «대기» · overlap=1" c8
tc "⑧b EQUIV 그 밖 바이트 = 기준판" c8b
t2=$SECONDS
# ── ⑨⑩ ft-critical-notify: LAND_NEXT 첫 줄 = «이미 main 에 있음» → PR 닫기(재승인 0)
NT="$T/nt"; mkdir -p "$NT/root/.fable-team/comm" "$NT/repo"
printf '{"_desk":"byz-planner-desk-pi#9","_master":"byz-planner-master-pi#360"}\n' > "$NT/root/.fable-team/seats-planner.json"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$MLOG"\necho "seq=1"\n' > "$NT/mbox.sh"
printf '#!/usr/bin/env bash\ncat "$FAKE_OUT"\nexit 1\n' > "$NT/fake-land.sh"; chmod +x "$NT/mbox.sh" "$NT/fake-land.sh"
git -c init.defaultBranch=main init -q "$NT/repo"; git -C "$NT/repo" remote add origin https://github.com/o/n.git
wrap() { FAKE_OUT="$NT/out" MLOG="$NT/mlog" FT_CRITICAL_DEDUPE_S=0 FT_MBOX_DIR="$NT/root/.fable-team/comm" FT_MBOX="$NT/mbox.sh" bash "$(nfn)" --wrap ft-merge-land "$NT/fake-land.sh" 77 --repo "$NT/repo" >/dev/null 2>"$NT/err"; }
c9() { rm -f "$NT/mlog"; printf '%s\n' 'REJECT main 자동 병합 C=d94a4149 · PR head(019f380d) != 승인 sha(abc12345) — 승인 뒤 head 가 움직였고 동일승인 대조(병합·rebase 두 경로)도 실패:NOT-EQUIV 이미 main 에 있음(S 트리 == 세트가 품은 main 0a7923001b · 승인 세트 + mx == mx) — 착지할 것 0 · PR 닫기(재승인 0) (착지 0)' > "$NT/out"
  wrap; out="$(cat "$NT/mlog" 2>/dev/null)"; rc=0; has "다음 손: 착지할 것 0 · PR 닫기(재승인 0)" && exc "다시 승인"; }
c10() { rm -f "$NT/mlog"; printf '%s\n' 'REJECT PR head(019f380d) != 승인 sha(abc12345) — 동일승인 대조(병합·rebase 두 경로)도 실패:NOT-EQUIV 자기 변경이 승인 때와 다름(main 대비 diff 불일치: a.md) (착지 0)' > "$NT/out"
  wrap; out="$(cat "$NT/mlog" 2>/dev/null)"; rc=0; has "다음 손: 지금 head sha 로 다시 승인" && exc "PR 닫기"; }
tc "⑨ «이미 main 에 있음» → 다음 손 «착지할 것 0 · PR 닫기(재승인 0)» · «다시 승인» 0" c9
tc "⑩ «자기 변경이 승인 때와 다름» → «지금 head sha 로 다시 승인» 그대로" c10
# ── ⑪ ASCII 꼴 + ERROR = 출력 바이트·rc 그대로 (기준판 대조)
c11() { local o="" r="" f s; for f in a b c; do case "$f" in a) rmref "$M8"; set -- "$A" "$S9";; b) rmref "$M11"; set -- "$A11" "$S11";; c) rmref "$B"; set -- "$A" "$SM";; esac; eqv "$1" "$2"; o="$o$rc|$out
"; done
  rmref "$M8"; eqv 0123456789abcdef0123456789abcdef01234567 "$S1"; o="$o$rc|$out"; out="$o"; [ "${o%%|*}" = 1 ] && has "ERROR" && has "일반 커밋 1 개" && has "자기 변경이 승인 때와 다름" && has "승인 줄기 + main"; }
c11b() { local o="" r="" f; for f in a b c; do case "$f" in a) rmref "$M8"; set -- "$A" "$S9";; b) rmref "$M11"; set -- "$A11" "$S11";; c) rmref "$B"; set -- "$A" "$SM";; esac
    withbin "$BASE" eqv "$1" "$2"; o="$o$rc|$out
"; done
  withbin "$BASE" eqv 0123456789abcdef0123456789abcdef01234567 "$S1"; o="$o$rc|$out"; c11 >/dev/null; [ "$o" = "$out" ]; }
tc "⑪ ASCII 꼴(일반 커밋 · 규칙 3 · 승인 줄기+main 아님) + ERROR" c11
[ -n "$BASE" ] && { tc "⑪b ⑪ 출력 바이트 = 기준판" c11b; } || echo "SKIP ⑪b 기준판 대조(FT_TEST_BASE_BIN 없음)"
# ── ⑫ m ≠ mx (main 이 한 칸 더 감) — 그래도 «이미 main» · mx 10자
c12() { rmref "$M12"; eqv "$A" "$S1"; [ "$rc" = 1 ] && has "이미 main 에 있음" && has "$(g rev-parse --short=10 "$M1")" && exc "$(g rev-parse --short=10 "$M12")"; }
tc "⑫ main 이 더 가도(m≠mx) «이미 main 에 있음» = mx 기준" c12
t3=$SECONDS
# ── 기준판 Red (① · ④ · ⑥ · ⑦ · ⑫ 는 고치기 전 판에서 이 사례가 FAIL 이어야 한다)
basefail "①" c1; basefail "④" c4; basefail "⑥" c6; basefail "⑦" c7; basefail "⑫" c12; basefail "⑨" c9
# ── 변이 M1~M6 (사본에서만) + 변이마다 원본 대조
MUT="$T/mut"; mkdir -p "$MUT"
mutfile() {   # mutfile <파일 이름> <찾기> <바꾸기> — 사본에 1회 치환(앵커 1개 아니면 실패)
  cp "$BIN/$1" "$MUT/$1"
  python3 - "$MUT/$1" "$2" "$3" <<'PY' || return 1
import io, sys
p, a, b = sys.argv[1:4]; s = io.open(p, encoding="utf-8").read()
if s.count(a) != 1: sys.exit("앵커 %d개" % s.count(a))
io.open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
killed() {   # killed <이름> <사례…> — 변이 사본에서 모두 FAIL · 원본으로 같은 사례 모두 PASS
  local name="$1" f; shift
  for f in "$@"; do if withbin "$MUT" "$f"; then ck "$name — 변이 살아남음($f)" 1; return; fi; done
  for f in "$@"; do if ! "$f"; then ck "$name — 원본 대조 FAIL($f)" 1; return; fi; done
  ck "$name → $* FAIL · 원본 대조 PASS" 0
}
M1A='        if in_main(repo, ac, sc, mx):   # r2359 규칙 3 자리'
if mutfile ft_approval_equiv.py "$M1A" '        if False:   # r2359 규칙 3 자리'; then killed "M1 ① in_main 부름 지움" c1; else ck "M1 변이 앵커 없음" 1; fi
if mutfile ft_approval_equiv.py 'return q.returncode == 0 and q.stdout.split()[:1] == [trees[1]]' 'return q.returncode == 0'; then killed "M2 ③ merge-tree 비교 지움" c3; else ck "M2 변이 앵커 없음" 1; fi
if mutfile ft_approval_equiv.py '        if in_main(repo, ac, sc, mx):   # r2359 rebase 자리' '        if False:   # r2359 rebase 자리'; then killed "M3 ④ rebased 쪽 부름 지움" c4; else ck "M3 변이 앵커 없음" 1; fi
if mutfile ft_approval_equiv.py 'return p.encode("latin-1").decode("utf-8", "replace")' 'return p'; then killed "M4 ⑦⑧ shown 그대로" c7 c8; else ck "M4 변이 앵커 없음" 1; fi
if mutfile ft-critical-notify.sh '(r"이미 main 에 있음", "착지할 것 0 · PR 닫기(재승인 0)"), (r"동일승인 대조", "지금 head sha 로 다시 승인"), ' '(r"동일승인 대조", "지금 head sha 로 다시 승인"), (r"이미 main 에 있음", "착지할 것 0 · PR 닫기(재승인 0)"), '; then killed "M5 ⑨ LAND_NEXT 새 줄을 맨 뒤로" c9; else ck "M5 변이 앵커 없음" 1; fi
if mutfile ft_approval_equiv.py '        if in_main(repo, ac, sc, mx):   # r2359 규칙 3 자리' '        if in_main(repo, ac, sc, m):   # r2359 규칙 3 자리'; then killed "M6 ⑫ mx 대신 m" c12; else ck "M6 변이 앵커 없음" 1; fi
t4=$SECONDS
cmp -s "$BIN/ft_approval_equiv.py" "$BIN/../kit/fable-team/bin/ft_approval_equiv.py"; ck "bin == kit ft_approval_equiv.py(설치 = kit 쪽)" $?
cmp -s "$BIN/ft-critical-notify.sh" "$BIN/../kit/fable-team/bin/ft-critical-notify.sh"; ck "bin == kit ft-critical-notify.sh" $?
echo "단계별 초: 픽스처 $((t1 - t0)) · ①~⑧ $((t2 - t1)) · ⑨~⑫ $((t3 - t2)) · 기준판·변이 $((t4 - t3)) · 전체 $((SECONDS - t0))"
echo "fail=$fail"; [ "$fail" = 0 ]
