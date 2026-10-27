#!/usr/bin/env bash
# test_r948_live_all_project.sh — r948: 카드 리포 착지 카드의 라이브 전수(--all) 대조가 «어느 프로젝트» 를 넘기는가 + --all 거짓 PENDING 3종.
#   사건(master 쪽지 169653): r937 의 --all 갈래가 --project 를 안 넘겨 검사기가 팩 리포(LIVE_BIN 없음)를 프로젝트로 봤다 → 일괄 143장 ERROR rc3.
#   사건(master 쪽지 169670): --all 이 처음 쓰이며 드러난 검사기 대응 오류 — templates/scope-*.tsv 를 «scope-» 뗀 이름으로 찾음 ·
#     iap-tunnel 인스턴스 라벨(-18703·-18712)을 정확 라벨로 찾음 · ft-head-lag 는 launchd 설치 대상이 아닌데 NOTLOADED.
#   임시 리포(팩 꼴·카드 꼴)·임시 HOME·가짜 launchctl/ps·가짜 검사기(받은 인자 기록)만 — 실 라이브·실 launchd·실 원격 0.
#   SRC=<bin 폴더> 로 변이 판을 같은 시험으로 돌린다(끝의 «변이» 절이 스스로 만든다).
#   r959 ④: ⓑ 의 기대를 «--range A..B --project <카드 리포 공용 루트>» 로 고쳤다 — 팩 착지 카드의 plist-env 렌더에도 프로젝트 루트가 필요하다(r426 rc3).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${SRC:-$(cd "$HERE/../bin" && pwd -P)}"; KIT="$(cd "$HERE/../kit" && pwd -P)"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:600}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$T/home"; mkdir -p "$HOME/Library/LaunchAgents"
unset FT_HARNESS_ROOT FT_INSTALL_CHECK FT_INSTALL_PENDING_DIR FT_LANDED_MARKER FT_LAND_REF
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
mkbin() { mkdir -p "$2"; cp -p "$1"/ft-team-lib.sh "$1"/ft-harness-root.sh "$1"/ft-index-move-install.sh "$1"/ft-live-install-check.sh \
  "$1"/ft_live_install_check.py "$1"/ft_plist_env.py "$1"/ft_git_capped.py "$2/"; }

# ── 팩 리포(키트 꼴) · 카드 리포(BYZ 꼴 · 워크트리 1개)
PR="$T/pack"; KD="$PR/feature-pack/fable-team/harness"; mkdir -p "$KD/kit/fable-team/bin"
printf '#!/bin/bash\necho v1\n' > "$KD/kit/fable-team/bin/x.sh"; chmod 755 "$KD/kit/fable-team/bin/x.sh"
printf 'LIVE-MAP.tsv\tskip\t-\t지도\nfable-team/bin/*\tbin\t$FT_BIN\tm\n' > "$KD/kit/LIVE-MAP.tsv"
g "$PR" init -q -b main; g "$PR" add -A; g "$PR" commit -qm p0; P0="$(g "$PR" rev-parse HEAD)"
echo v2 >> "$KD/kit/fable-team/bin/x.sh"; g "$PR" commit -qam p1; P1="$(g "$PR" rev-parse HEAD)"; g "$PR" update-ref refs/remotes/origin/main "$P1"
CR="$T/byz"; IDX="$CR/design/harness/indices/진행"; mkdir -p "$IDX"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$CR/design/TEAMS.md"
printf '# 인덱스: k\n- 설치: 있음\n- 실사건: 이동 · 증거 mbox #169653\n## 상태\n- x\n' > "$IDX/k.md"
g "$CR" init -q -b main; g "$CR" add -A; g "$CR" commit -qm c0; C0="$(g "$CR" rev-parse HEAD)"
g "$CR" worktree add -q "$CR/.worktrees/w" -b w 2>/dev/null
FAKE="$T/fake-chk.sh"; ARGS="$T/args.log"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\necho "OK n=0 skip=0"\n' "$ARGS" > "$FAKE"; chmod 755 "$FAKE"
gate() { : > "$ARGS"; out="$(FT_INSTALL_CHECK="$FAKE" FT_INSTALL_PENDING_DIR="$T/pd" FT_HARNESS_ROOT="$KD" bash "$1/ft-index-move-install.sh" "$2" --landed "$3" 2>&1)"; rc=$?; got="$(cat "$ARGS")"; }

t_a() { gate "$1" "$IDX/k.md" "$C0"; [ "$rc" = 0 ] && [ "$got" = "--all --project $CR" ]; }
# r959 ④: 팩 리포 착지 sha 의 --range 갈래도 --project 를 넘는다(plist-env 렌더가 프로젝트 루트를 못 받아 r426 카드가 rc3 로 막혔다) — r948 당시 «--project 추가 0» 기대를 고침
t_b() { gate "$1" "$IDX/k.md" "$P0..$P1"; [ "$rc" = 0 ] && [ "$got" = "--range $P0..$P1 --project $CR" ]; }
t_c() { gate "$1" "$CR/.worktrees/w/design/harness/indices/진행/k.md" "$C0"; [ "$rc" = 0 ] && [ "$got" = "--all --project $CR" ]; }

# ── 검사기 픽스처: 키트 리포(templates·plist 템플릿 실물 복사) + 라이브(FT_BIN·templates) + 가짜 launchctl(목록·라벨 조회)
R="$T/kitrepo"; K=k; mkdir -p "$R/$K/fable-team/templates" "$R/$K/iap-tunnels" "$R/$K/launchd"
cp "$KIT/LIVE-MAP.tsv" "$R/$K/LIVE-MAP.tsv"
printf 'a\tb\n' > "$R/$K/fable-team/templates/scope-classes-pack.tsv"; printf 'c\td\n' > "$R/$K/fable-team/templates/scope-ddl-record.tsv"
cp "$KIT/iap-tunnels/com.byz.iap-tunnel.plist.template" "$R/$K/iap-tunnels/"
cp "$KIT/launchd/com.byz.ft-head-lag.plist.template" "$KIT/launchd/com.byz.ft-idle-wake.plist.template" "$R/$K/launchd/"
g "$R" init -q -b main; g "$R" add -A; g "$R" commit -qm k0; g "$R" update-ref refs/remotes/origin/main HEAD
export FT_BIN="$T/live/bin"; mkdir -p "$FT_BIN" "$T/live/templates"
cp -p "$R/$K"/fable-team/templates/scope-*.tsv "$T/live/templates/"
cat > "$T/fake-launchctl" <<'EOF'
#!/bin/bash
[ "$1" = list ] || exit 64
[ -n "${STUB_LIST_FAIL:-}" ] && exit 5
if [ -z "${2:-}" ]; then echo "PID	Status	Label"; for l in ${STUB_LOADED:-}; do printf -- '-\t0\t%s\n' "$l"; done; exit 0; fi
case " ${STUB_LOADED:-} " in *" $2 "*) printf '{\n\t"Label" = "%s";\n\t"LastExitStatus" = 0;\n};\n' "$2"; exit 0;; esac
exit 113
EOF
printf '#!/bin/bash\necho "Thu Oct 15 10:00:00 2026"\n' > "$T/fake-ps"; chmod +x "$T/fake-launchctl" "$T/fake-ps"
export FT_LAUNCHCTL="$T/fake-launchctl" FT_PS="$T/fake-ps"
chk() { out="$(cd "$T" && bash "$1/ft-live-install-check.sh" --all --repo "$R" --kit "$K" --project "$T/noproj" 2>&1)"; rc=$?; }
mkdir -p "$T/noproj"

t_f() { STUB_LOADED="com.byz.iap-tunnel-18703 com.byz.iap-tunnel-18712 com.byz.ft-idle-wake" chk "$1"
  [ "$rc" = 0 ] && [[ "$out" == "OK n="* ]] && [[ "$out" != *"templates/scope-"* ]]; }
t_g() { STUB_LOADED="com.byz.iap-tunnel-18703 com.byz.iap-tunnel-18712 com.byz.ft-idle-wake" chk "$1"; [ "$rc" = 0 ] && [[ "$out" != *"iap-tunnel"* ]]; }
t_g0() { STUB_LOADED="com.byz.iap-tunnel-x1 com.byz.iap-tunnel-llm com.byz.iap-tunnelx com.byz.ft-idle-wake" chk "$1"
  [ "$rc" = 1 ] && [[ "$out" == *"NOTLOADED com.byz.iap-tunnel · com.byz.iap-tunnel-<숫자> (적재 0)"* ]]; }
t_ge() { STUB_LOADED="com.byz.iap-tunnel com.byz.ft-idle-wake" chk "$1"; [ "$rc" = 0 ] && [[ "$out" != *"iap-tunnel"* ]]; }   # r948 r2: 정확 라벨만 적재 = LOADED
t_g3() { STUB_LIST_FAIL=1 STUB_LOADED="" chk "$1"; [ "$rc" = 3 ] && [[ "$out" == *"launchctl list 실패"* ]]; }
t_h() { STUB_LOADED="com.byz.iap-tunnel-18703" chk "$1"
  [ "$rc" = 1 ] && [[ "$out" != *"ft-head-lag"* ]] && [[ "$out" == *"NOTLOADED com.byz.ft-idle-wake"* ]]; }

run_all() {   # $1 = bin 폴더 · 결과 = 이름별 0/1 줄
  for t in t_a t_b t_c t_f t_g t_g0 t_ge t_g3 t_h; do "$t" "$1"; echo "$t $?"; done; }
BIN="$T/bin"; mkbin "$SRC" "$BIN"
res="$(run_all "$BIN")"
r() { printf '%s\n' "$res" | awk -v k="$1" '$1==k{print $2}'; }
ck "ⓐ 카드 리포에만 있는 sha → 검사기 인자 «--all --project <카드 리포 공용 루트>»" "$(r t_a)"
ck "ⓑ 팩 리포 sha → 인자 «--range A..B --project <카드 리포 공용 루트>»(r959 ④)" "$(r t_b)"
ck "ⓒ 카드가 워크트리 안 → --project = 리포 공용 루트(워크트리 경로 아님)" "$(r t_c)"
ck "ⓕ templates/scope-*.tsv 원래 이름 그대로 설치 → MISSING 0 · OK" "$(r t_f)"
ck "ⓖ «접두-숫자» 라벨 2개 적재 → LOADED(iap-tunnel 줄 0)" "$(r t_g)"
ck "ⓖ 숫자 아닌 접미(-x1·-llm·붙은 x)만 적재 → NOTLOADED" "$(r t_g0)"
ck "ⓖ 정확 라벨(com.byz.iap-tunnel)만 적재 → LOADED(iap-tunnel 줄 0)" "$(r t_ge)"
ck "ⓖ launchctl 목록 실패 → ERROR rc3(NOTLOADED 로 숨김 0)" "$(r t_g3)"
ck "ⓗ ft-head-lag = 지도 skip(줄 0) · ft-idle-wake 는 NOTLOADED 그대로(실제 어긋남 숨김 0)" "$(r t_h)"

# ── 변이: 각 고침을 되돌린 판 → 그 시험이 FAIL 해야 한다
mut() { local name="$1" file="$2" from="$3" to="$4" want="$5" mb="$T/m-$1"; mkbin "$SRC" "$mb"
  python3 - "$mb/$file" "$from" "$to" <<'PY' || { ck "변이 $name: 치환 자리 없음" 1; return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert a in s
open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
  local mr; mr="$(run_all "$mb" | awk -v k="$want" '$1==k{print $2}')"
  rc=$mr; out="$name"; [ "$mr" != 0 ] && ck "변이 $name → $want FAIL" 0 || ck "변이 $name → $want FAIL" 1; }
mut project-off ft-index-move-install.sh 'CARG=(--all --project "$CROOT")' 'CARG=(--all)' t_a
mut worktree-path ft-index-move-install.sh 'CROOT="$(dirname "$CROOT")"' 'CROOT="$WT"' t_c
mut name-strip ft_live_install_check.py '    pre = pre[: pre.rfind("/") + 1]' '    pass' t_f
mut exact-label ft_live_install_check.py '    if not inst:' '    if True:' t_g
mut exact-off ft_live_install_check.py 're.escape(prefix[:-1]) + r"(?:-\d+)?"' 're.escape(prefix) + r"\d+"' t_ge
# 지도 변이는 픽스처 리포의 지도에서(실 키트 무변경)
grep -v '^launchd/com.byz.ft-head-lag' "$R/$K/LIVE-MAP.tsv" > "$T/map2"; cp "$T/map2" "$R/$K/LIVE-MAP.tsv"
g "$R" commit -qam map-mut; g "$R" update-ref refs/remotes/origin/main HEAD
t_h "$BIN"; mr=$?; [ "$mr" != 0 ] && ck "변이 head-lag skip 행 삭제 → ⓗ FAIL" 0 || ck "변이 head-lag skip 행 삭제 → ⓗ FAIL" 1
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
