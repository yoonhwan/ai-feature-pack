#!/usr/bin/env bash
# test_live_root_protect_r2242.sh — r2242 LIVE_ROOT worktree 보호 반례 ①~⑦.
#   ①② ft_data_root 오류 글(/bin/bash · LANG=ko_KR.UTF-8 · set -u) · ③④⑦ ft-disk-reclaim.sh LIVE_ROOT hold · ⑤ git 잠금 · ⑥ 불변.
# 모든 입력은 mktemp 안(${TMPDIR:-/tmp} 그대로 · /tmp · /private/tmp 두 경로로 돌린다): 임시 리포 1개(가짜 origin) + worktree 3 · 가짜 lsof · tmux.
#   실 BYZ · 실 worktree · 실 tmux 0 · sleep 0. env FT_HARNESS_ROOT_LIB · FT_DISK_RECLAIM_BIN = 다른 사본 대조용.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LIB="${FT_HARNESS_ROOT_LIB:-$HERE/../bin/ft-harness-root.sh}"
TOOL="${FT_DISK_RECLAIM_BIN:-$HERE/../bin/ft-disk-reclaim.sh}"
W="$(mktemp -d "${TMPDIR:-/tmp}/r2242.XXXXXX")"; W="$(printf '%s' "$W" | tr -s /)"; W="${W%/}"; trap 'git -C "$W/rA" worktree unlock "$W/wts/lk" 2>/dev/null; rm -rf "$W"' EXIT
fail=0; T0=$SECONDS
chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }
echo "INFO W=$W"

# ①② ft_data_root — FT_ROOT 갈래(29행) · 공용 루트 갈래(35행)
mkdir -p "$W/fr/.fable-team"; git init -q "$W/cr" && mkdir -p "$W/cr/.fable-team"
RPC="$(cd "$W/cr" && pwd -P)"; rp() { if [ "$1" = cr ]; then echo "$RPC"; else echo "$W/fr"; fi; }   # 공용 루트 갈래 = git 이 주는 실경로
dr() {   # <LIVE_ROOT 값> <갈래 fr|cr> → stderr 파일 $W/err · rc 출력
  printf '%s\n' "$1" > "$W/$2/.fable-team/LIVE_ROOT"
  if [ "$2" = fr ]; then (cd "$W" && LANG=ko_KR.UTF-8 LC_ALL=ko_KR.UTF-8 FT_ROOT="$W/fr" /bin/bash -c 'set -u; . "$1"; ft_data_root /x' _ "$LIB" >/dev/null 2>"$W/err"); echo $?
  else (cd "$W/cr" && unset FT_ROOT && LANG=ko_KR.UTF-8 LC_ALL=ko_KR.UTF-8 /bin/bash -c 'set -u; . "$1"; ft_data_root /x' _ "$LIB" >/dev/null 2>"$W/err"); echo $?; fi; }
n() { grep -cF -- "$1" "$W/err" | tr -d ' '; }
for b in fr cr; do
  rc="$(dr "$W/gone" "$b")"
  chk "①$b rc1" "$rc" 1
  chk "①$b «LIVE_ROOT 폴더 없음» 1줄" "$(n 'ERROR LIVE_ROOT 폴더 없음: ')" 1
  chk "①$b 경로 · 파일 · 안내 글" "$(n "«$W/gone» ($(rp "$b")/.fable-team/LIVE_ROOT) — worktree 가 지워졌는지 확인")" 1
  chk "①$b unbound 0" "$(n unbound)" 0
  chk "①$b stderr 1줄" "$(wc -l < "$W/err" | tr -d ' ')" 1
  rc="$(dr abc "$b")"
  chk "②$b rc1" "$rc" 1
  chk "②$b 지금 글 그대로" "$(n 'ERROR LIVE_ROOT 가 절대경로 폴더가 아님: «abc»')" 1
  chk "②$b «폴더 없음» 0 · unbound 0" "$(n '폴더 없음')$(n unbound)" 00
  mkdir -p "$W/live-$b"; rc="$(dr "$W/live-$b" "$b")"
  chk "⑥$b 폴더 있음 = rc0 · stderr 0" "$rc/$(wc -c < "$W/err" | tr -d ' ')" 0/0
done
T1=$SECONDS

# ③④⑥⑦ 정리 도구 — 리포 rA · worktree live(LIVE_ROOT) · other · lk(잠금)
FK="$W/fake"; mkdir -p "$FK/bin" "$W/tr" "$W/cc"
printf '#!/bin/bash\necho p1; exit 0\n' > "$FK/bin/lsof"; printf '#!/bin/bash\nexit 0\n' > "$FK/bin/tmux"; chmod +x "$FK/bin/"*
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig"
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
git init -q --bare "$W/oA" && git clone -q "$W/oA" "$W/rA" 2>/dev/null && echo f > "$W/rA/f" && git -C "$W/rA" add f \
  && git -C "$W/rA" commit -qm c1 && git -C "$W/rA" push -q origin main
RA="$W/rA"; WT="$W/wts"; for x in live other lk; do git -C "$RA" worktree add -q --detach "$WT/$x" main 2>/dev/null; done
OLD="$(date -v-3d +%Y%m%d%H%M)"; for i in "$RA"/.git/worktrees/*; do touch -t "$OLD" "$i/index"; done
mkdir -p "$RA/.fable-team"; LRF="$RA/.fable-team/LIVE_ROOT"
export PATH="$FK/bin:$PATH" FT_RECLAIM_TMP_ROOT="$W/tr" FT_RECLAIM_CACHE_ROOT="$W/cc" FT_RECLAIM_REPOS="$RA" FT_RECLAIM_INFO="" FT_RECLAIM_DF_PATH=/
wpath() { git -C "$RA" worktree list --porcelain | sed -n 's/^worktree //p' | grep "/wts/$1\$"; }
PL="$(wpath live)"; PO="$(wpath other)"; PM="$(git -C "$RA" worktree list --porcelain | sed -n '1s/^worktree //p')"
plan() { rm -rf "$W/$1"; mkdir -p "$W/$1"; bash "$TOOL" plan "$W/$1" >/dev/null 2>"$W/$1.err"; echo $?; }
row() { awk -F'\t' -v k="$2" -v p="$3" '$1==k && $3==p{print $4}' "$W/$1/candidates.tsv"; }
cnt() { awk -F'\t' -v k="$2" -v p="$3" '$1==k && $3==p' "$W/$1/candidates.tsv" | wc -l | tr -d ' '; }

rm -f "$LRF"; chk "⑥LIVE_ROOT 파일 없음 plan rc0" "$(plan p0)" 0
chk "⑥LIVE_ROOT 파일 없음 = live 후보 줄 1(지금 판정)" "$(cnt p0 worktree "$PL")" 1
printf '%s\n' "$WT/live" > "$LRF"
chk "③plan rc0" "$(plan p1)" 0
chk "③live = hold LIVE_ROOT" "$(row p1 hold "$PL")" LIVE_ROOT
chk "③live 후보 줄 0" "$(cnt p1 worktree "$PL")" 0
chk "⑥other 후보 줄 1" "$(cnt p1 worktree "$PO")" 1
chk "⑥live 줄 밖 candidates.tsv 같음" "$(grep -vF "$PL" "$W/p0/candidates.tsv" | cmp -s - <(grep -vF "$PL" "$W/p1/candidates.tsv") && echo same || echo diff)" same
chk "⑥주 worktree hold 그대로" "$(row p1 hold "$PM")" "주 worktree"
printf '%s\n' "$W/no-such" > "$LRF"; plan p2 >/dev/null
chk "⑥LIVE_ROOT stat 실패 = 갈래 건너뜀(live 후보)" "$(cnt p2 worktree "$PL")" 1
printf 'abc\n' > "$LRF"; plan p3 >/dev/null
chk "⑥LIVE_ROOT 상대경로 = 갈래 건너뜀(live 후보)" "$(cnt p3 worktree "$PL")" 1
T2=$SECONDS

# ④ 손으로 목록에 넣고 apply → SKIP LIVE_ROOT · 폴더 남음
printf '%s\n' "$WT/live" > "$LRF"; mkdir -p "$W/ap"; printf 'worktree\t1\t%s\trepo=%s\n' "$PL" "$RA" > "$W/ap/candidates.tsv"
bash "$TOOL" apply "$W/ap/candidates.tsv" >/dev/null 2>&1
chk "④apply SKIP LIVE_ROOT" "$(grep -c "^SKIP	worktree	$PL	LIVE_ROOT\$" "$W/ap/deleted.log" | tr -d ' ')" 1
chk "④DELETED 0" "$(grep -c '^DELETED' "$W/ap/deleted.log" | tr -d ' ')" 0
chk "④live 폴더 남음" "$([ -d "$WT/live" ] && echo yes || echo no)" yes

# ⑤ 잠근 worktree + git worktree remove(--force 0) → 거절 · 폴더 남음
git -C "$RA" worktree lock --reason "LIVE_ROOT r2242" "$WT/lk"
git -C "$RA" worktree remove "$WT/lk" >/dev/null 2>&1; rc=$?
chk "⑤remove 거절 rc≠0" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
chk "⑤lk 폴더 남음" "$([ -d "$WT/lk" ] && echo yes || echo no)" yes
chk "⑤worktree list 에 locked" "$(git -C "$RA" worktree list --porcelain | grep -c '^locked LIVE_ROOT r2242$' | tr -d ' ')" 1
T3=$SECONDS

# ⑦ 대소문자만 다른 값 · 심링크 경로 값 → hold LIVE_ROOT
UP="$(printf '%s' "$WT/live" | sed 's#/wts/live$#/WTS/LIVE#')"
if ! python3 -c "import os,sys; sys.exit(0 if os.path.samefile(sys.argv[1], sys.argv[2]) else 1)" "${UP%/LIVE}/OTHER" "$WT/other" 2>/dev/null; then
  echo "판정 불가 대소문자 구분 볼륨 ($UP)"
else
  echo "PASS ⑦같은 폴더 다른 대소문자 stat 됨"
  printf '%s\n' "$UP" > "$LRF"; plan p7a >/dev/null
  chk "⑦대소문자 = hold LIVE_ROOT" "$(row p7a hold "$PL")" LIVE_ROOT
  chk "⑦대소문자 후보 줄 0" "$(cnt p7a worktree "$PL")" 0
fi
case "$PL" in /private/tmp/*) ALT="/tmp${PL#/private/tmp}" ;; /tmp/*) ALT="/private$PL" ;; *) ln -s "$WT" "$W/lnk"; ALT="$W/lnk/live" ;; esac
chk "⑦심링크 다른 경로 글자 다름" "$([ "$ALT" != "$PL" ] && echo yes || echo no)" yes
printf '%s\n' "$ALT" > "$LRF"; plan p7b >/dev/null
chk "⑦심링크($ALT) = hold LIVE_ROOT" "$(row p7b hold "$PL")" LIVE_ROOT
chk "⑦심링크 후보 줄 0" "$(cnt p7b worktree "$PL")" 0
T4=$SECONDS
echo "TIME ①②=$((T1-T0))s ③⑥=$((T2-T1))s ④⑤=$((T3-T2))s ⑦=$((T4-T3))s"
echo "RESULT fail=$fail"; exit $(( fail > 0 ))
