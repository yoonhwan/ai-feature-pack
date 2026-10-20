#!/usr/bin/env bash
# test_folder_cleanup_noise_plan.sh — r576: 흔적만 남은 옛 작업 폴더 정리 계획(plans/folder-cleanup-20261020-noise.sh) 시험 ⓐ~ⓖ
# 픽스처 = 임시 bare origin + 임시 리포 + 임시 워크트리 6벌 · 가짜 lsof/tmux(PATH 앞) · 실제 홈·BYZ 리포·실 워크트리·실 tmux 는 건드리지 않는다. GIT_* 환경 변수는 쓰지 않는다.
# 축 ⓐ serena 1줄만 → «지금 판(h34 틀)» = SKIP 미커밋(FAIL 기록) · 새 계획 = 보관 tar + 되돌리기 + REMOVED
#     ⓑ serena + « D» 다수 → tar 에 deleted.txt + 되돌리기 + REMOVED ⓒ 추적 안 된 파일 → SKIP «추적 안 된 파일» ⓓ « M» 다른 파일 → SKIP «흔적 아닌 변경»
#     ⓔ 원격 보관 없음 → SKIP ⓕ 프로세스 cwd → SKIP cwd ⓖ tmux 좌석 cwd → SKIP 좌석 · 모든 경우 가지 수 변화 0 · 계획 본문에 force 문자열 0 · dry-run 은 지우기 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLAN="$HERE/../plans/folder-cleanup-20261020-noise.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — 기대 «$3» 없음 ← ${2:0:400}";; esac; }

[ -f "$PLAN" ] || { echo "FAIL 계획 파일 없음: $PLAN"; exit 1; }
bash -n "$PLAN" && ok "bash -n 계획" || bad "bash -n 계획"

# ---- 픽스처: bare origin + 리포 + .serena/project.yml 추적
git init -q --bare "$T/origin.git"
git init -q -b main "$T/root"
git -C "$T/root" config user.email t@t; git -C "$T/root" config user.name t
mkdir -p "$T/root/.serena"
printf 'name: fixture\n' > "$T/root/.serena/project.yml"
printf 'keep\n' > "$T/root/other.txt"
printf 'gone1\n' > "$T/root/d1.txt"
printf 'gone2\n' > "$T/root/d2.txt"
git -C "$T/root" add -A && git -C "$T/root" commit -qm init
git -C "$T/root" remote add origin "$T/origin.git"
git -C "$T/root" push -q origin main
git -C "$T/origin.git" symbolic-ref HEAD refs/heads/main

wt() {  # wt <이름> → 원격에 올라간 워크트리 만들고 경로를 찍는다
  local n="$1" p="$T/root/.worktrees/$1"
  git -C "$T/root" worktree add -q "$p" -b "nano/fx-$n" origin/main
  git -C "$T/root" push -q origin "nano/fx-$n"
  echo "$p"
}
A="$(wt a)"; B="$(wt b)"; C="$(wt c)"; D="$(wt d)"; E="$(wt e)"; F="$(wt f)"; G="$(wt g)"
printf 'name: drift\n' >> "$A/.serena/project.yml"
printf 'name: drift\n' >> "$B/.serena/project.yml"; rm -f "$B/d1.txt" "$B/d2.txt"
printf 'x\n' > "$C/newfile.txt"
printf 'edit\n' >> "$D/other.txt"
printf 'name: drift\n' >> "$F/.serena/project.yml"
printf 'name: drift\n' >> "$G/.serena/project.yml"
git -C "$E" commit -q --allow-empty -m local-only   # 원격 밖 커밋

# 가짜 lsof/tmux — FAKE_* 파일에 적힌 경로만 «사용 중» 이라고 답한다
mkdir -p "$T/fake"
cat > "$T/fake/lsof" <<'EOF'
#!/usr/bin/env bash
if [ -s "${FAKE_LSOF:-/dev/null}" ]; then while IFS= read -r p; do printf 'p1\nn%s\n' "$p"; done < "$FAKE_LSOF"; else exit 1; fi
EOF
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
if [ -s "${FAKE_TMUX:-/dev/null}" ]; then cat "$FAKE_TMUX"; else exit 1; fi
EOF
chmod +x "$T/fake/lsof" "$T/fake/tmux"
export PATH="$T/fake:$PATH"

run() {  # run <케이스> <경로들...> -- <계획 인자...> → LIST 파일 만들고 계획 실행 (stdout+log 를 $T/out-<케이스>.txt 로)
  local c="$1"; shift
  local extra=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do extra+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  local paths=("${extra[@]}")
  : > "$T/list-$c.tsv"; for p in "${paths[@]}"; do printf '%s\n' "$p" >> "$T/list-$c.tsv"; done
  local rest=("$@")
  bash "$PLAN" --root "$T/root" --list "$T/list-$c.tsv" --archive-dir "$T/arch" --log "$T/log-$c.txt" ${rest[@]+"${rest[@]}"} > "$T/out-$c.txt" 2>&1
  echo "rc=$?"
}
branches() { git -C "$T/root" branch --format='%(refname:short)' | sort; }
B0="$(branches)"

# ---- ⓐ 지금 판(h34 틀) = SKIP «미커밋» — 실패 기록
cat > "$T/h34-now.sh" <<'EOF'
#!/bin/bash
set -u
ROOT="$1"; LIST="$2"; ok=0; skip=0
git -C "$ROOT" fetch -q origin
while IFS= read -r wt; do
  [ -d "$wt" ] || { echo "SKIP 없음 $wt"; skip=$((skip+1)); continue; }
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then echo "SKIP 미커밋 $wt"; skip=$((skip+1)); continue; fi
  git -C "$ROOT" worktree remove "$wt" >/dev/null 2>&1 && ok=$((ok+1))
done < "$LIST"
echo "RESULT removed=$ok skip=$skip"
EOF
printf '%s\n' "$A" > "$T/list-now.tsv"
NOW="$(bash "$T/h34-now.sh" "$T/root" "$T/list-now.tsv" 2>&1)"
has "ⓐ 지금 판(h34 틀) = SKIP 미커밋" "$NOW" "SKIP 미커밋"
[ -d "$A" ] && ok "ⓐ 지금 판 = 폴더 그대로" || bad "ⓐ 지금 판이 폴더를 지웠다"

# ---- ⓐ 새 계획 = 보관 tar + 되돌리기 + REMOVED
r="$(run a "$A")"
has "ⓐ 새 계획 rc" "$r" "rc=0"
has "ⓐ REMOVED" "$(cat "$T/out-a.txt")" "REMOVED $A"
[ -f "$T/arch/a.tar.gz" ] && ok "ⓐ 보관 tar 1" || bad "ⓐ 보관 tar 없음"
tl="$(tar -tzf "$T/arch/a.tar.gz" 2>/dev/null)"
has "ⓐ tar 에 흔적 패치" "$tl" "trace.patch"
has "ⓐ tar 에 삭제 목록" "$tl" "deleted.txt"
has "ⓐ tar 에 정보" "$tl" "meta.txt"
has "ⓐ tar 안 패치에 serena 1줄" "$(tar -xzOf "$T/arch/a.tar.gz" ./trace.patch 2>/dev/null)" ".serena/project.yml"
has "ⓐ RESULT removed=1" "$(cat "$T/out-a.txt")" "removed=1"
has "ⓐ RESULT tar=1" "$(cat "$T/out-a.txt")" "tar=1"
has "ⓐ df 줄" "$(cat "$T/out-a.txt")" "/"
[ -d "$A" ] && bad "ⓐ 폴더가 남았다" || ok "ⓐ 폴더 없음"
git -C "$T/origin.git" rev-parse -q --verify "refs/heads/nano/fx-a" >/dev/null && ok "ⓐ 가지 그대로" || bad "ⓐ 가지가 사라졌다"

# ---- ⓑ serena + « D» 다수 = tar 에 삭제 목록 + 되돌리기 + REMOVED
r="$(run b "$B")"
has "ⓑ rc" "$r" "rc=0"
has "ⓑ REMOVED" "$(cat "$T/out-b.txt")" "REMOVED $B"
has "ⓑ 삭제 목록 2줄" "$(tar -xzOf "$T/arch/b.tar.gz" ./deleted.txt 2>/dev/null | wc -l | tr -d ' ')" "2"
[ -d "$B" ] && bad "ⓑ 폴더가 남았다" || ok "ⓑ 폴더 없음"

# ---- ⓒ 추적 안 된 파일 = SKIP · 폴더 그대로 · tar 0
r="$(run c "$C")"
has "ⓒ SKIP 추적 안 된 파일" "$(cat "$T/out-c.txt")" "SKIP [추적 안 된 파일] $C"
[ -d "$C" ] && ok "ⓒ 폴더 그대로" || bad "ⓒ 폴더가 지워졌다"
[ -f "$T/arch/c.tar.gz" ] && bad "ⓒ tar 를 만들었다" || ok "ⓒ tar 0"

# ---- ⓓ 흔적 아닌 변경 = SKIP
r="$(run d "$D")"
has "ⓓ SKIP 흔적 아닌 변경" "$(cat "$T/out-d.txt")" "SKIP [흔적 아닌 변경] $D"
[ -d "$D" ] && ok "ⓓ 폴더 그대로" || bad "ⓓ 폴더가 지워졌다"

# ---- ⓔ 원격 보관 없음 = SKIP
r="$(run e "$E")"
has "ⓔ SKIP 원격 보관 없음" "$(cat "$T/out-e.txt")" "SKIP [원격 보관 없음] $E"
[ -d "$E" ] && ok "ⓔ 폴더 그대로" || bad "ⓔ 폴더가 지워졌다"

# ---- ⓕ 프로세스 cwd = SKIP cwd · ⓖ tmux 좌석 cwd = SKIP 좌석
printf '%s\n' "$F" > "$T/fake-lsof.txt"
export FAKE_LSOF="$T/fake-lsof.txt"
r="$(run f "$F")"
has "ⓕ SKIP cwd 사용 중" "$(cat "$T/out-f.txt")" "SKIP [cwd 사용 중] $F"
[ -d "$F" ] && ok "ⓕ 폴더 그대로" || bad "ⓕ 폴더가 지워졌다"
unset FAKE_LSOF; printf '%s\n' "$G" > "$T/fake-tmux.txt"; export FAKE_TMUX="$T/fake-tmux.txt"
r="$(run g "$G")"
has "ⓖ SKIP 좌석 cwd" "$(cat "$T/out-g.txt")" "SKIP [좌석 cwd] $G"
[ -d "$G" ] && ok "ⓖ 폴더 그대로" || bad "ⓖ 폴더가 지워졌다"

unset FAKE_TMUX
# ---- dry-run = 재확인만 · 지우기 0 · tar 0
r="$(run dry "$F" -- --dry-run)"
has "dry-run rc" "$r" "rc=0"
has "dry-run WOULD-REMOVE" "$(cat "$T/out-dry.txt")" "WOULD-REMOVE $F"
[ -d "$F" ] && ok "dry-run 폴더 그대로" || bad "dry-run 이 폴더를 지웠다"
[ -f "$T/arch/f.tar.gz" ] && bad "dry-run 이 tar 를 만들었다" || ok "dry-run tar 0"

# ---- ⓖ 가지 수 변화 0 (지운 a·b 가지도 남아 있다)
B1="$(branches)"
[ "$B0" = "$B1" ] && ok "ⓖ 가지 수 변화 0" || bad "ⓖ 가지가 변했다: $(diff <(printf '%s\n' "$B0") <(printf '%s\n' "$B1") | tr '\n' ' ')"
# ---- 강제 옵션 문자열 0
if grep -q -e '--force' -e 'worktree remove .*-f' "$PLAN"; then bad "계획 본문에 강제 옵션 문자열"; else ok "계획 본문 강제 옵션 0"; fi

echo "== rc=$fail"
[ "$fail" = 0 ] || exit 1
echo "ALL PASS"
