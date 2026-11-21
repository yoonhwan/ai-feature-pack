# _press_queue_tail_r2387_lib.sh — r2387 꼬리 시험 공용(source 전용 · ⑪⑫⑬ 과 변이 M5 가 같이 쓴다): pa_init/pa_fix 위에
#   gh «pr list» 대역(목록 = $TLIST · CHO 목록 밖 호출은 그대로 흘림) · press 도구는 queue 만 진짜(착지 판정은 스텁) · 승인 표식 파일 · PR·묶음 도우미 · 음성 경로 목록 심기
#   mkpr(PRF = 바뀌는 파일) · bundle <head> <run> · plist <번호> <head> · listn/qtail/ltail · 실 gh·실 원격·실 mbox 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_pushahead_r2368_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
pa_init "$T"; pa_fix
TLIST="$T/tlist.json"; : > "$TLIST"; export TLIST
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
case "$1 $2" in
  "pr view") cat "$STUB_JSON"; exit 0;;
  "pr list") cat "$TLIST"; exit 0;;
esac
exit 0
EOF
chmod +x "$T/gh-stub"; export FT_GH="$T/gh-stub"
cat > "$FIX/ft-press-evidence.sh" <<EOF
#!/bin/bash
echo "PRESS \$1" >> "\$STUB_LOG"
case "\$1" in queue) exec bash "$BIN/ft-press-evidence.sh" "\$@";; esac
exit 0
EOF
chmod +x "$FIX/ft-press-evidence.sh"
plist() {  # plist <번호> <head> — 목록 1줄(gh 칸 = 번호·head 만) + 승인 표식 파일(이름 = head · DA#54 H3)
  python3 - "$TLIST" "$2" "$1" <<'PY'
import json, sys
json.dump([{"number": int(sys.argv[3]), "headRefOid": sys.argv[2]}], open(sys.argv[1], "w"))
PY
  mkdir -p "$T/state/autonomy-merge-approved"; : > "$T/state/autonomy-merge-approved/$2"
}
mkpr() {  # mkpr <번호> — PR 1개(바뀌는 파일 = PRF, 기본 음성 경로)
  local n="$1" f="${PRF:-worker/pr$1.py}"
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$n" origin/main >/dev/null 2>&1
  mkdir -p "$(dirname "$W/$f")"; printf 'pr%s %s-%s\n' "$n" "$$" "$SECONDS" > "$W/$f"
  git -C "$W" add -A && git -C "$W" commit -q -m "pr $n work"; git -C "$W" push -q -f origin "pr$n:refs/pull/$n/head" >/dev/null 2>&1; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys
print(json.dumps({"headRefOid":sys.argv[1],"headRefName":"pr"+sys.argv[2],"isCrossRepository":False,"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$n" > "$STUB_JSON"
}
bundle() {  # bundle <head> <run> — 지금 main + 그 PR 의 세트에 유효 묶음 1개를 origin 에 심고 로컬로도 받는다(받기는 부르는 쪽 몫 · H1)
  local h="$1" run="$2" m t set d rows c
  m="$(sha "$W" origin/main)"; t="$(git -C "$W" merge-tree --write-tree "$m" "$h" | head -n1)"; set="$(git -C "$W" commit-tree "$t" -p "$m" -m "set $h")"
  d="$T/bun"; mkdir -p "$d"
  printf 'set=%s\nrun_id=%s\nseat=t\nts=0\n' "$set" "$run" > "$d/meta.txt"
  printf '{"axis":"conn","epoch_ms":1,"run_id":"%s"}\n' "$run" > "$d/poller_dom.jsonl"
  printf 'run_id: %s\n\n| 축 | 사실 | 시간 |\n|---|---|---|\n| 아키텍처 문서 | x | 12:00 |\n| 코드 | y | 12:00 |\n| 로그 | z | 12:01 |\n| 화면 | w | 12:02 |\n| turbopack | build 0 · runtime 1 · config 0 · 원문 turbopack.txt | 12:03 |\n' "$run" > "$d/table.md"
  printf '%s\n' 'data: {"result":{"content":[{"type":"text","text":"{\"configErrors\":[],\"sessionErrors\":[{\"url\":\"/realtime\",\"buildError\":null,\"runtimeErrors\":[{\"m\":1}]}]}"}]},"jsonrpc":"2.0","id":1}' > "$d/turbopack.txt"
  rows="$(for f in meta.txt poller_dom.jsonl table.md turbopack.txt; do printf '100644 blob %s\t%s\n' "$(git -C "$W" hash-object -w "$d/$f")" "$f"; done)"
  c="$(git -C "$W" commit-tree "$(printf '%s\n' "$rows" | git -C "$W" mktree)" -p "$set" -m bundle)"
  git -C "$W" push -q origin "$c:refs/press/$set-$run"
  git -C "$W" fetch -q origin '+refs/press/*:refs/press/*'
}
listn() { grep -c '^pr list' "$STUB_LOG" 2>/dev/null || true; }
qqueue() { grep -c '^PRESS queue' "$STUB_LOG" 2>/dev/null || true; }
qtail() { grep -E '^(PR #.* STALE|NEXT )' <<<"$out"; }
mkdir -p "$W/docs/rules"; printf '# 목록\n## 목록\n- `worker/**`\n' > "$W/docs/rules/press_voice_paths.md"
git -C "$W" fetch -q origin; git -C "$W" checkout -q main 2>/dev/null || git -C "$W" checkout -q -b main origin/main
git -C "$W" add -A && git -C "$W" commit -q -m "list"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
