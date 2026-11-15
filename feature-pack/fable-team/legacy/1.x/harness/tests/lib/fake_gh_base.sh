#!/usr/bin/env bash
# fake_gh_base.sh — source 전용 · r1955: scope-approve·standing-approve 가 --pr 의 base 를 gh 로 읽는다(autonomy_pr_target) — 시험은 실 gh 0
#   fake_gh_base <폴더>  → <폴더>/gh 를 만들고 PATH 앞에 둔다 · `gh pr view … --json baseRefName` = {"baseRefName":"$FAKE_GH_BASE"}(기본 main)
#   FAKE_GH_RC=<n> 이면 출력 0 · rc n(gh 실패) · 호출마다 FAKE_GH_LOG(있으면)에 인자 1줄
fake_gh_base() {
  mkdir -p "$1" && cat > "$1/gh" <<'EOF'
#!/usr/bin/env bash
[ -z "${FAKE_GH_LOG:-}" ] || echo "$*" >> "$FAKE_GH_LOG"
[ -z "${FAKE_GH_RC:-}" ] || exit "$FAKE_GH_RC"
printf '{"baseRefName":"%s"}\n' "${FAKE_GH_BASE-main}"
EOF
  chmod +x "$1/gh" && export PATH="$1:$PATH"
}
