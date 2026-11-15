# merge_fixture.sh — R230 시험 공용: 임시 origin(bare)+clone 저장소 (source 전용 · 실 저장소·실 gh·실 원격 0)
# GIT_DIR·GIT_WORK_TREE 류는 걸지 않는다(BOOT 25) — 전부 `git -C`.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

mkrepo() {  # mkrepo <임시 폴더> → ORIGIN(bare) · W(작업 clone · main) · M0(첫 커밋)
  ORIGIN="$1/origin.git"; W="$1/w"
  git init -q --bare -b main "$ORIGIN"
  git clone -q "$ORIGIN" "$W" 2>/dev/null
  git -C "$W" symbolic-ref HEAD refs/heads/main
  git -C "$W" config user.name t; git -C "$W" config user.email t@t; git -C "$W" config commit.gpgsign false
  printf 'l1\nl2\nl3\n' > "$W/a.txt"; printf 'b1\n' > "$W/b.txt"
  cm "$W" base
  git -C "$W" push -q origin main; git -C "$W" fetch -q origin
  M0="$(git -C "$W" rev-parse HEAD)"
}
cm() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }   # cm <repo> <msg> — 전부 add 후 커밋
sha() { git -C "$1" rev-parse "$2"; }
# R336: 착지는 모든 모드에서 오빠 승인 파일이 필요 — 시험용 승인 기록(실전은 오빠 `!` 한 줄). NOAP=1 이면 승인 안 함(승인 없음 시험용)
apv() { local s=""; while [ $# -gt 0 ]; do [ "$1" = --approve-sha ] && [ $# -ge 2 ] && s="$2"; shift; done; [ -n "$s" ] && [ -z "${NOAP:-}" ] && bash "$BIN/ft-autonomy.sh" approve-merge "$s" >/dev/null 2>&1; return 0; }
# r1746: ghremote <작업 리포> <bare> <owner/name> — 원격 URL 을 github 꼴(git@github.com:<owner/name>.git)로 · 실제 전송은 가짜 ssh 로 로컬 bare
#   (원장 루트 FT_ROOT 가 대상과 다른 git 리포면 «다른 리포» = owner/name 필요 — 로컬 경로 원격은 REJECT 가 맞다)
ghremote() {
  local s="$(dirname "$2")/ssh-stub-$(basename "$2")"
  printf '#!/bin/bash\nexec bash -c "$(printf "%%s" "${!#}" | sed -E "s|'"'"'[^'"'"']*'"'"'|'"'"'%s'"'"'|")"\n' "$2" > "$s"; chmod +x "$s"
  git -C "$1" remote set-url origin "git@github.com:$3.git"; export GIT_SSH_COMMAND="$s"
}
