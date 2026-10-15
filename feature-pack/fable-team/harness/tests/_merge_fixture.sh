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
