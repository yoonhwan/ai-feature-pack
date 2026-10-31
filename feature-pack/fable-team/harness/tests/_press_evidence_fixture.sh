# _press_evidence_fixture.sh — r1230 시험 공용(source 전용): 임시 origin(bare)+BYZ 꼴 URL(날 값 + url.insteadOf) · cd-dev.yml paths-filter · gh 스텁 · 묶음 도우미
#   부른 시험이 guard_begin 뒤에 source 한다 · 실 gh·실 원격 0
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$BIN/../kit/fable-team/bin"; LAND="$BIN/ft-merge-land.sh"; EVT="$BIN/ft-press-evidence.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T_START=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:600}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/.fable-team" "$T/ev"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_MERGE_DENY_FILE="$T/deny.txt" FT_INSTALL_CHECK="$T/noop"
printf '#!/bin/bash\nexit 0\n' > "$T/noop"; chmod +x "$T/noop"
printf '# 시험 목록(빈)\n' > "$T/deny.txt"; printf '{"_master":"byz-harness-master-claude#9"}\n' > "$T/.fable-team/seats-harness.json"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; exit 2;; esac
body=""; for a in "$@"; do [ -f "$a" ] && body="$(cat "$a")"; done
echo "$* :: $body" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub"
U=git@github.com:SecondWindStudio/byz-agents.git
byz() { git -C "$1" config remote.origin.url "$U"; git -C "$1" config url."$ORIGIN".insteadOf "$U"; }   # 날 URL = BYZ · 실제 전송 = 임시 origin
byz "$W"; REPO="$W"
mkdir -p "$W/.github/workflows"; cat > "$W/.github/workflows/cd-dev.yml" <<'EOF'
name: CD (Dev)
jobs:
  changes:
    steps:
      - uses: dorny/paths-filter@v3
        with:
          filters: |
            gateway:
              - '.github/workflows/cd-dev.yml'
              - 'gateway/**'
              # 주석 줄은 건너뛴다
              - 'worker/**'
              - 'pyproject.toml'
            web:
              - 'clients/web/**'
  gateway:
    needs: [changes]
EOF
printf 'w0\n' > "$W/worker.keep"; mkdir -p "$W/worker"; printf 'l0\n' > "$W/worker/l.py"; cm "$W" "cd-dev"; git -C "$W" push -q origin main
omain() { sha "$ORIGIN" refs/heads/main; }
put() { mkdir -p "$(dirname "$REPO/$1")"; printf '%s\n' "$2" > "$REPO/$1"; }
pushpr() {  # pushpr <PR> <가지> — 지금 HEAD 를 PR ref 로 · 제목 = $TITLE(기본 feat: PR n)
  git -C "$REPO" push -q -f origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$REPO" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":sys.argv[3],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$2" "${TITLE:-feat: PR $1}" > "$STUB_JSON"
}
mkpr() { local n="$1" b="$2"; shift 2; git -C "$REPO" fetch -q origin; git -C "$REPO" checkout -q -B "$b" origin/main; for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$REPO" "pr $n"; pushpr "$n" "$b"; }
adv() { git -C "$REPO" fetch -q origin; git -C "$REPO" checkout -q -B main origin/main; for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$REPO" "main adv"; git -C "$REPO" push -q origin main; git -C "$REPO" fetch -q origin; }
brn() { git -C "$REPO" fetch -q origin; git -C "$REPO" checkout -q -B "$1" origin/main; }
land() { local b="$1" t0=$SECONDS; shift; apv "$@"; : > "$STUB_LOG"; out="$(bash "$b" "$@" --repo "$REPO" 2>&1)"; rc=$?; [ -z "${LAND_T:-}" ] || echo "  land $1 $((SECONDS - t0))s"; }
ev() {  # ev <폴더> <run> [poller 첫 줄] [로그 칸] [turbopack 원문] → poller_dom.jsonl·table.md·turbopack.txt
  local p1="${3:-}" lg="${4:-worker 12:00 줄}" tp="${5:-}"; mkdir -p "$1"
  [ -n "$p1" ] || p1="{\"axis\":\"conn\",\"epoch_ms\":1,\"run_id\":\"$2\"}"
  [ -n "$tp" ] || tp='data: {"result":{"content":[{"type":"text","text":"{\"configErrors\":[],\"sessionErrors\":[{\"url\":\"/realtime\",\"buildError\":null,\"runtimeErrors\":[{\"m\":1}]}]}"}]},"jsonrpc":"2.0","id":1}'
  printf '%s\n{"axis":"dom","epoch_ms":2,"poll":1}\n' "$p1" > "$1/poller_dom.jsonl"
  printf 'run_id: %s\n\n| 축 | 사실 | 시간 |\n|---|---|---|\n| 아키텍처 문서 | 기획 §5 | 12:00 |\n| 코드 | 세트 | 12:00 |\n| 로그 | %s | 12:01 |\n| 화면 | 말풍선 1 | 12:02 |\n' "$2" "$lg" > "$1/table.md"
  printf 'event: message\n%s\n' "$tp" > "$1/turbopack.txt"
}
pk() { ev "$T/ev/$2" "$2" "${@:3}"; out="$(bash "$EVT" pack "$1" --run "$2" --poller "$T/ev/$2/poller_dom.jsonl" --table "$T/ev/$2/table.md" --turbopack "$T/ev/$2/turbopack.txt" --repo "$REPO" 2>&1)"; rc=$?; }
rawpk() {  # rawpk <세트> <run> [빼는 파일] — 칸 검사 없이 묶음 ref 를 origin 에 직접(틀린 묶음 흉내)
  local e="$1" r="$2" d="$T/ev/$2" t c f
  printf 'set=%s\nrun_id=%s\nseat=t\nts=0\n' "$e" "$r" > "$d/meta.txt"
  t="$(for f in meta.txt poller_dom.jsonl table.md turbopack.txt; do [ "$f" = "${3:-}" ] || printf '100644 blob %s\t%s\n' "$(git -C "$REPO" hash-object -w "$d/$f")" "$f"; done | git -C "$REPO" mktree)"
  c="$(git -C "$REPO" commit-tree "$t" -p "$e" -m raw)"; git -C "$REPO" push -q origin "$c:refs/press/$e-$r"
}
unref() { git -C "$ORIGIN" update-ref -d "$1"; }
rejected() { [ "$rc" = 1 ] && [[ "$out" == *"$1"* ]] && [[ "$out" != *"LANDED"* ]] && [ "$(omain)" = "$2" ]; }
chk() { out="$(bash "${CHK_BIN:-$BIN}/ft-press-evidence.sh" check --repo "$REPO" --main "${CHK_MAIN:-$(sha "$REPO" origin/main)}" --head "$1" --landing "${2:-$1}" --pr 99 --title "${3:-feat}" --root "$T" 2>&1)"; rc=$?; }

