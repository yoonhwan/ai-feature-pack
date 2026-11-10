#!/usr/bin/env bash
# test_install_check_hr_worktree.sh — r961: 설치 검사 키트 경로를 HARNESS_ROOT «자기» 체크아웃 최상위 기준으로 계산한다.
#   사건(PR 332·333 2회): 라이브 HARNESS_ROOT = 팩 리포 안 착지 워크트리(.worktrees/land-r938/…) 일 때
#   키트 상대 경로를 «공용 루트 기준» 으로 만들면 앞에 .worktrees/land-r938/ 이 붙는다 → 그 경로는 커밋에 없다 →
#   ft-live-install-check 의 `git show <ref>:<지도>` 가 ERROR → ft-merge-land INSTALL 단계가 매번 실패(손 설치).
#   ⓐ(빨강 먼저) HARNESS_ROOT = 같은 리포의 추가 워크트리 안 harness · --repo = 공용 루트 → 고친 판 = OK n=1
#   ⓑ HARNESS_ROOT = 공용 체크아웃 안 → 결과 줄이 워크트리 판과 «같다»(바이트 불변)
#   ⓒ HARNESS_ROOT = 다른 리포(팩 밖) → 지금처럼 «밖» ERROR rc3 (조용한 통과 0)
#   ⓓ 범위 밖 삭제만·빈 범위는 rc0 (회귀 0)
#   ⓕ(r2 · DA⑥ r1 반례) HARNESS_ROOT = «공용 루트 밖» 에 등록한 같은 리포의 워크트리 → 종전 판은 «밖» ERROR rc3,
#      고친 판 = OK n=1 rc0 («같은 리포» = git-common-dir 가 같음 — 디렉터리 포함 관계가 아니다)
#   ⓖ(r2) 다른 리포 클론(같은 내용) HARNESS_ROOT → 공용 git 폴더가 다르므로 «밖» ERROR rc3 (조용한 통과 0)
#   ⓗ(r5 · DA⑥ 반례) 독립 리포 둘 · git 폴더 이름 «metadata» vs «metadata »(끝 공백 1) → «밖» ERROR rc3 (조용한 통과 0)
#      (.strip() 이 경로 끝 공백을 지워 두 리포가 «같은 리포» 로 보였다 — 경로 값은 끝 개행 1개만 뗀다)
#   ⓘ(r5) 같은 리포 두 워크트리(공백 없는 이름) → 지금처럼 OK n=1 rc0 (ⓐⓕ 회귀)
#   ⓙ(r5 변이) .strip() 되살림 → ⓗ FAIL (= 이 시험이 빈 말이 아님)
# mktemp 만 쓴다 — 실 HOME·실 리포·쪽지 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HR="$(cd -- "$HERE/.." && pwd -P)"   # 팩 harness/ (실 키트 · 여기선 이름만 빌린다)
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
unset FT_HARNESS_ROOT FT_ROOT FT_BIN

H="$T/home"; LB="$H/.claude/fable-team/live/9.9.9/bin"; mkdir -p "$LB"
FX="$T/fx"; HRD="$FX/feature-pack/fable-team/harness"; KB="$HRD/kit/fable-team/bin"; mkdir -p "$KB" "$FX/docs"
git -C "$FX" init -q -b main
gc() { git -C "$FX" -c user.name=t -c user.email=t@t "$@"; }
printf '%s\n' "LIVE-MAP.tsv"$'\t'"skip"$'\t'"-"$'\t'"지도 자신" > "$HRD/kit/LIVE-MAP.tsv"
printf '%s\n' "fable-team/bin/k.sh"$'\t'"bin"$'\t'"\$FT_BIN"$'\t'"bash $HRD/install.sh --apply" >> "$HRD/kit/LIVE-MAP.tsv"
echo a > "$FX/docs/a.md"; echo v1 > "$KB/k.sh"
gc add -A; gc commit -qm c0; C0="$(git -C "$FX" rev-parse HEAD)"
echo v2 > "$KB/k.sh"; gc add -A; gc commit -qm c1; C1="$(git -C "$FX" rev-parse HEAD)"
cp -p "$KB/k.sh" "$LB/k.sh"   # 라이브 = tip 과 같은 바이트 (대조 OK 기대)
gc worktree add -q "$FX/.worktrees/land-x" "$C1" 2>/dev/null || bad "픽스처 워크트리 생성 실패"
HRW="$FX/.worktrees/land-x/feature-pack/fable-team/harness"   # 라이브 HARNESS_ROOT 꼴 (같은 리포의 다른 워크트리)
[ -d "$HRW/kit/fable-team" ] && ok "픽스처: 워크트리 안 harness/kit 실재" || bad "픽스처: 워크트리 안 harness/kit 없음"
chk() { local hr="$1"; shift; (cd "$FX" && env HOME="$H" FT_BIN="$LB" FT_HARNESS_ROOT="$hr" bash "$HR/kit/fable-team/bin/ft-live-install-check.sh" "$@" 2>&1); }

# ⓐ 빨강 먼저 — 착지 워크트리 HARNESS_ROOT + 공용 루트 --repo
out="$(chk "$HRW" --range $C0..$C1 --ref $C1 --repo "$FX")"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "OK n=1 skip=0" ] && ok "ⓐ 워크트리 HARNESS_ROOT → OK n=1 rc0" || bad "ⓐ rc=$rc «${out:0:300}»"
case "$out" in *".worktrees/land-x"*) bad "ⓐ 출력에 워크트리 접두가 남음 «${out:0:200}»";; *) ok "ⓐ 대조 경로에 .worktrees 접두 0";; esac

# ⓑ 공용 체크아웃 HARNESS_ROOT → 결과 줄이 ⓐ 와 바이트 같다
out2="$(chk "$HRD" --range $C0..$C1 --ref $C1 --repo "$FX")"; rc2=$?
[ "$rc2" = 0 ] && [ "$out2" = "$out" ] && ok "ⓑ 공용 체크아웃 판 결과 = 워크트리 판 (바이트 같음)" || bad "ⓑ rc=$rc2 «${out2:0:200}» ≠ ⓐ «${out:0:200}»"

# ⓒ 다른 리포(팩 밖) → 지금처럼 «밖» ERROR rc3
OTHER="$T/other"; mkdir -p "$OTHER/feature-pack/fable-team/harness/kit/fable-team"
git -C "$OTHER" init -q -b main; echo x > "$OTHER/feature-pack/fable-team/harness/kit/fable-team/x.sh"
git -C "$OTHER" -c user.name=t -c user.email=t@t add -A
git -C "$OTHER" -c user.name=t -c user.email=t@t commit -qm o0
out3="$(chk "$OTHER/feature-pack/fable-team/harness" --range $C0..$C1 --ref $C1 --repo "$FX")"; rc3=$?
[ "$rc3" = 3 ] && case "$out3" in "ERROR "*"밖"*) ok "ⓒ 다른 리포 HARNESS_ROOT → ERROR rc3 («밖»)" ;; *) bad "ⓒ 문구 다름 «${out3:0:200}»";; esac || bad "ⓒ rc=$rc3 «${out3:0:200}»"

# ⓓ 빈 범위(C1..C1) = OK n=0 rc0 (회귀 0)
out4="$(chk "$HRW" --range $C1..$C1 --ref $C1 --repo "$FX")"; rc4=$?
[ "$rc4" = 0 ] && [ "$out4" = "OK n=0 skip=0" ] && ok "ⓓ 빈 범위 → OK n=0 rc0" || bad "ⓓ rc=$rc4 «${out4:0:200}»"

# ⓔ git 리포 밖 HARNESS_ROOT(폴백 경로) → 옛 기준(repo)으로 «밖» 판정 유지 · 조용한 통과 0
NG="$T/nogit"; mkdir -p "$NG/feature-pack/fable-team/harness/kit/fable-team/bin"
cp -p "$HRD/kit/LIVE-MAP.tsv" "$NG/feature-pack/fable-team/harness/kit/LIVE-MAP.tsv"
cp -p "$KB/k.sh" "$NG/feature-pack/fable-team/harness/kit/fable-team/bin/k.sh"
out5="$(chk "$NG/feature-pack/fable-team/harness" --range $C0..$C1 --ref $C1 --repo "$FX")"; rc5=$?
[ "$rc5" = 3 ] && case "$out5" in "ERROR "*"밖"*) ok "ⓔ git 밖 HARNESS_ROOT → 폴백 «밖» rc3" ;; *) bad "ⓔ 문구 다름 «${out5:0:200}»";; esac || bad "ⓔ rc=$rc5 «${out5:0:200}»"

# ⓕ(r2) 공용 루트 «밖» 에 등록한 같은 리포의 워크트리 — 포함 관계는 끊겼지만 공용 git 폴더가 같다 → OK n=1 rc0
OUTS="$T/outside-wt"
gc worktree add -q "$OUTS" "$C1" 2>/dev/null || bad "픽스처: 공용 루트 밖 워크트리 생성 실패"
HRF="$OUTS/feature-pack/fable-team/harness"
cdir() { ( cd "$1" && cd "$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" && pwd -P ); }  # 절대·실제 경로
if [ "$(cdir "$HRF")" = "$(cdir "$FX")" ]
then ok "픽스처: ⓕ 공용 루트 밖 워크트리 · git-common-dir 같음"; else bad "픽스처: ⓕ git-common-dir 다름"; fi
out6="$(chk "$HRF" --range $C0..$C1 --ref $C1 --repo "$FX")"; rc6=$?
[ "$rc6" = 0 ] && [ "$out6" = "OK n=1 skip=0" ] && ok "ⓕ 공용 루트 밖 등록 워크트리 HARNESS_ROOT → OK n=1 rc0" || bad "ⓕ rc=$rc6 «${out6:0:300}»"
case "$out6" in *"outside-wt"*) bad "ⓕ 출력에 워크트리 접두가 남음 «${out6:0:200}»";; *) ok "ⓕ 대조 경로에 outside-wt 접두 0";; esac

# ⓖ(r2) 내용이 같은 «다른 리포» 클론 → 공용 git 폴더가 다르므로 «밖» ERROR rc3
CL="$T/clone"
git clone -q "$FX" "$CL" 2>/dev/null || bad "ⓖ 픽스처: 클론 실패"
[ -d "$CL/feature-pack/fable-team/harness/kit/fable-team" ] && ok "ⓖ 픽스처: 클론 안 harness/kit 실재" || bad "ⓖ 픽스처: 클론 안 harness/kit 없음"
out7="$(chk "$CL/feature-pack/fable-team/harness" --range $C0..$C1 --ref $C1 --repo "$FX")"; rc7=$?
[ "$rc7" = 3 ] && case "$out7" in "ERROR "*"밖"*) ok "ⓖ 같은 내용 다른 리포 클론 → ERROR rc3 («밖»)" ;; *) bad "ⓖ 문구 다름 «${out7:0:200}»";; esac || bad "ⓖ rc=$rc7 «${out7:0:200}»"

# ⓗ(r5) 독립 리포 둘 · git 폴더 이름 «metadata» vs «metadata »(끝 공백 1) → «밖» ERROR rc3
SA="$T/sepa"; SBH="$T/sepb/feature-pack/fable-team/harness"
mkdir -p "$SA/feature-pack/fable-team/harness/kit/fable-team/bin" "$SBH/kit/fable-team/bin"
git -C "$SA" init -q -b main --separate-git-dir="$T/metadata" 2>/dev/null || bad "ⓗ 픽스처: pack-a init 실패"
git -C "$T/sepb" init -q -b main --separate-git-dir="$T/metadata " 2>/dev/null || bad "ⓗ 픽스처: pack-b init 실패"  # 끝 공백 1 — 이웃 폴더 이름만 다름
if [ "$(git -C "$SA" rev-parse --git-common-dir 2>/dev/null)" != "$(git -C "$T/sepb" rev-parse --git-common-dir 2>/dev/null)" ]
then ok "ⓗ 픽스처: 두 리포 git 폴더 이름만 다름(끝 공백 1)"; else bad "ⓗ 픽스처: git 폴더 이름이 같아짐"; fi
for d in "$SA" "$T/sepb"; do
  printf '%s\n' "LIVE-MAP.tsv"$'\t'"skip"$'\t'"-"$'\t'"지도 자신" > "$d/feature-pack/fable-team/harness/kit/LIVE-MAP.tsv"
  printf '%s\n' "fable-team/bin/k.sh"$'\t'"bin"$'\t'"\$FT_BIN"$'\t'"bash $d/install.sh --apply" >> "$d/feature-pack/fable-team/harness/kit/LIVE-MAP.tsv"
  echo v1 > "$d/feature-pack/fable-team/harness/kit/fable-team/bin/k.sh"
done
gca() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
gca "$SA" add -A; gca "$SA" commit -qm a0; CA0="$(git -C "$SA" rev-parse HEAD)"
echo v2 > "$SA/feature-pack/fable-team/harness/kit/fable-team/bin/k.sh"; gca "$SA" add -A; gca "$SA" commit -qm a1; CA1="$(git -C "$SA" rev-parse HEAD)"
echo v2 > "$T/sepb/feature-pack/fable-team/harness/kit/fable-team/bin/k.sh"; gca "$T/sepb" add -A; gca "$T/sepb" commit -qm b0 2>/dev/null
cp -p "$SA/feature-pack/fable-team/harness/kit/fable-team/bin/k.sh" "$LB/k.sh"   # 라이브 = pack-a tip 바이트 (조용한 통과 시 OK n=1 이 나오는 조건)
out8="$(chk "$SBH" --range $CA0..$CA1 --ref $CA1 --repo "$SA")"; rc8=$?
[ "$rc8" = 3 ] && case "$out8" in "ERROR "*"밖"*) ok "ⓗ 끝 공백 git 폴더 두 리포 → ERROR rc3 («밖»)" ;; *) bad "ⓗ 문구 다름 «${out8:0:200}»";; esac || bad "ⓗ rc=$rc8 «${out8:0:200}» (조용한 통과)"
cp -p "$KB/k.sh" "$LB/k.sh"                                          # 라이브 원복 (ⓐⓕ 조건 되돌림)

# ⓘ(r5) 같은 리포 두 워크트리(공백 없는 이름) → OK n=1 rc0
WT2="$T/wt2"; gc worktree add -q "$WT2" "$C1" 2>/dev/null || bad "ⓘ 픽스처: 두 번째 워크트리 실패"
out9="$(chk "$WT2/feature-pack/fable-team/harness" --range $C0..$C1 --ref $C1 --repo "$FX")"; rc9=$?
[ "$rc9" = 0 ] && [ "$out9" = "OK n=1 skip=0" ] && ok "ⓘ 같은 리포 두 워크트리(공백 없는 이름) → OK n=1 rc0" || bad "ⓘ rc=$rc9 «${out9:0:200}»"

# ⓙ(r5) 변이: .strip() 되살림 → ⓗ FAIL (시험이 빈 말이 아님)
MUT="$T/mutbin"; mkdir -p "$MUT"
cp -p "$HR/kit/fable-team/bin/"*.py "$HR/kit/fable-team/bin/"*.sh "$MUT/"   # 짝 모듈(ft_plist_env 등)도 함께 — 변이 판이 import 로 죽지 않게
sed 's/^    out = r\.stdout\[.*$/    out = r.stdout.strip()/' "$HR/kit/fable-team/bin/ft_live_install_check.py" > "$MUT/ft_live_install_check.py"
if grep -qx '    out = r.stdout.strip()' "$MUT/ft_live_install_check.py"
then ok "ⓙ 픽스처: 변이 적용(.strip() 되살림)"; else bad "ⓙ 픽스처: 변이 sed 안 먹힘"; fi
chk_m() { local hr="$1"; shift; (cd "$FX" && env HOME="$H" FT_BIN="$LB" FT_HARNESS_ROOT="$hr" bash "$MUT/ft-live-install-check.sh" "$@" 2>&1); }
outm="$(chk_m "$SBH" --range $CA0..$CA1 --ref $CA1 --repo "$SA")"; rcm=$?
[ "$rcm" != 3 ] && ok "ⓙ 변이 .strip() → ⓗ FAIL(rc=$rcm = 조용한 통과 재현)" || bad "ⓙ 변이가 안 먹힘(rc=3 그대로)"

# ⓚ(r6) git 폴더 이름 특수문자 5꼴 — «다른 이름 두 리포» rc3 · «같은 리포 두 워크트리» rc0
#   (text=True 의 universal newlines 가 CR 을 LF 로 바꾸는 자리 — DA⑥ r6 반례)
KC="$T/kchars"; mkdir -p "$KC"
kc() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
kseed() {
  mkdir -p "$1/feature-pack/fable-team/harness/kit/fable-team/bin"
  printf '%s\n' "LIVE-MAP.tsv"$'\t'"skip"$'\t'"-"$'\t'"지도 자신" > "$1/feature-pack/fable-team/harness/kit/LIVE-MAP.tsv"
  printf '%s\n' "fable-team/bin/k.sh"$'\t'"bin"$'\t'"\$FT_BIN"$'\t'"bash x --apply" >> "$1/feature-pack/fable-team/harness/kit/LIVE-MAP.tsv"
  echo v1 > "$1/feature-pack/fable-team/harness/kit/fable-team/bin/k.sh"
  kc "$1" add -A; kc "$1" commit -qm k0
  echo v2 > "$1/feature-pack/fable-team/harness/kit/fable-team/bin/k.sh"
  kc "$1" add -A; kc "$1" commit -qm k1
}
kcase() {  # $1 = 이름표 · $2·$3 = git 폴더 이름(서로 다름)
  local lab="$1" na="$2" nb="$3" d A B K0 K1 o rc
  d="$KC/$1"; A="$d/a"; B="$d/b"; mkdir -p "$A" "$B"
  git -C "$A" init -q -b main --separate-git-dir="$d/$na" 2>/dev/null || bad "ⓚ[$lab] 픽스처: A init 실패"
  git -C "$B" init -q -b main --separate-git-dir="$d/$nb" 2>/dev/null || bad "ⓚ[$lab] 픽스처: B init 실패"
  kseed "$A"; kseed "$B"
  K0="$(git -C "$A" rev-parse HEAD^)"; K1="$(git -C "$A" rev-parse HEAD)"
  cp -p "$A/feature-pack/fable-team/harness/kit/fable-team/bin/k.sh" "$LB/k.sh"   # 라이브 = A tip
  o="$(chk "$B/feature-pack/fable-team/harness" --range $K0..$K1 --ref $K1 --repo "$A")"; rc=$?
  [ "$rc" = 3 ] && case "$o" in "ERROR "*"밖"*) ok "ⓚ[$lab] 서로 다른 git 폴더 이름 두 리포 → ERROR rc3 («밖»)" ;; *) bad "ⓚ[$lab] 문구 다름 «${o:0:150}»";; esac || bad "ⓚ[$lab] 이름이 다른데 rc=$rc «${o:0:150}» (조용한 통과)"
  kc "$A" worktree add -q "$d/wt" "$K1" 2>/dev/null || bad "ⓚ[$lab] 픽스처: 워크트리 실패"
  o="$(chk "$d/wt/feature-pack/fable-team/harness" --range $K0..$K1 --ref $K1 --repo "$A")"; rc=$?
  [ "$rc" = 0 ] && [ "$o" = "OK n=1 skip=0" ] && ok "ⓚ[$lab] 같은 리포 두 워크트리 → OK n=1 rc0" || bad "ⓚ[$lab] 같은 리포 판 rc=$rc «${o:0:150}»"
}
kcase "끝공백" "meta" "meta "
kcase "CR" $'meta\rdata' $'meta\ndata'
kcase "LF" $'meta\ndata' $'meta\rdata'
kcase "탭" "meta" $'meta\t'
kcase "한글" $'메타\rdata' $'메타\ndata'
cp -p "$KB/k.sh" "$LB/k.sh"   # 라이브 원복

# ⓛ(r6) 변이: text=True 되살림 → ⓚ[CR] FAIL (시험이 빈 말이 아님)
MUT2="$T/mut2"; mkdir -p "$MUT2"
cp -p "$HR/kit/fable-team/bin/"*.py "$HR/kit/fable-team/bin/"*.sh "$MUT2/"
python3 - "$HR/kit/fable-team/bin/ft_live_install_check.py" "$MUT2/ft_live_install_check.py" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
src = src.replace("capture_output=True,\n", "capture_output=True, text=True,\n")
src = src.replace('out = r.stdout[:-1] if r.stdout.endswith(b"\\n") else r.stdout',
                  'out = r.stdout[:-1] if r.stdout.endswith("\\n") else r.stdout')
open(sys.argv[2], "w", encoding="utf-8").write(src)
PY
if grep -q 'capture_output=True, text=True,' "$MUT2/ft_live_install_check.py" && ! grep -q 'endswith(b"' "$MUT2/ft_live_install_check.py"
then ok "ⓛ 픽스처: 변이 적용(text=True 되살림)"; else bad "ⓛ 픽스처: 변이 안 먹힘"; fi
chk_m2() { local hr="$1"; shift; (cd "$FX" && env HOME="$H" FT_BIN="$LB" FT_HARNESS_ROOT="$hr" bash "$MUT2/ft-live-install-check.sh" "$@" 2>&1); }
DC="$KC/CR"; KD0="$(git -C "$DC/a" rev-parse HEAD^)"; KD1="$(git -C "$DC/a" rev-parse HEAD)"
cp -p "$DC/a/feature-pack/fable-team/harness/kit/fable-team/bin/k.sh" "$LB/k.sh"
ortho="$(chk_m2 "$DC/b/feature-pack/fable-team/harness" --range $KD0..$KD1 --ref $KD1 --repo "$DC/a")"; rct=$?
[ "$rct" != 3 ] && ok "ⓛ 변이 text=True → ⓚ[CR] FAIL(rc=$rct = 조용한 통과 재현)" || bad "ⓛ 변이가 안 먹힘(rc=3 그대로)"
cp -p "$KB/k.sh" "$LB/k.sh"

echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "FAIL $fail" ) =="
[ $fail = 0 ]
