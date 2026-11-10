#!/usr/bin/env bash
# ft-sheet-verify.sh — 현황판 검증 1회 실행 (PLAN-status-sheet r4 §5 · S3). ft-board-publish.sh --sheet 성공 뒤 1회 부른다.
#   LLM = 단일 요청 1회(도구 0 · 7초 + 재시도 1 · 폴백 0) → stdout JSON {unconfirmed, term_candidates, question_lint}.
#   쪽지 발신·메모 쓰기·상한·락은 이 래퍼가 한다(LLM 문장 0 · 결정·판정·시트 글자 수정·원장 쓰기 0).
#   ft-sheet-verify.sh [--print-cmd]   rc: 0(실행·skip·검증 실패 전부 — 발행 rc 를 바꾸지 않는다) | 2 도구·설정 없음
# env: FT_ROOT · FT_BOARD_BIN(시트 렌더러 · 시험은 스텁) · FT_MBOX · FT_SHEET_VERIFY_CMD(시험 스텁 · 기본 = 아래 claude 인자)
#      FT_SHEET_NOTES(보정 메모) · FT_SHEET_VERIFY_LEDGER(발송 원장) · FT_SHEET_VERIFY_HEAD(③ 칸 머리 1줄) · FT_SHEET_VERIFY_NOW(시험)
#      FT_SHEET_VERIFY_LIMIT(일일 상한 · 기본 24 · 낮추기만) · FT_SHEET_VERIFY_TIMEOUT(요청 1회 초 · 기본 7 = 외부 호출 7초 룰 · 낮추기만)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ROOT:-}"   # r385b: 리포 공용 루트 = env → ft_repo_root(옛 설치 꼴 · cwd) → ERROR
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 2
ST="$ROOT/.fable-team/state"
BOARD="${FT_BOARD_BIN:-$HERE/ft-board.py}"
MBOX="${FT_MBOX:-$ROOT/.fable-team/comm/mbox.sh}"
LED="${FT_SHEET_VERIFY_LEDGER:-$ST/sheet-verify-sent.jsonl}"
NOTES="${FT_SHEET_NOTES:-$ST/sheet-notes.md}"
HEADF="${FT_SHEET_VERIFY_HEAD:-$ST/sheet-verify-head.txt}"
NOW="${FT_SHEET_VERIFY_NOW:-$(date +%Y-%m-%dT%H:%M:%S)}"; DAY="${NOW:0:10}"
LIMIT="${FT_SHEET_VERIFY_LIMIT:-24}"; TMO="${FT_SHEET_VERIFY_TIMEOUT:-7}"
FROM="byz-planner-pm-sheet"; MAX_MD=40960
# 도구 목록 «빈 값» = Bash·Write·Edit·MCP 가 존재하지 않는다(허용 목록 아님) · --restricted = user/project settings 무시
if [ -n "${FT_SHEET_VERIFY_CMD:-}" ]; then CMD=("$FT_SHEET_VERIFY_CMD")
else CMD=(claude -p --model claude-sonnet-4-6 --restricted --tools "" --strict-mcp-config --mcp-config "$ST/mcp-empty.json" --max-turns 1); fi
[ "${1:-}" = "--print-cmd" ] && { printf '%q ' "${CMD[@]}"; echo; exit 0; }
log() { echo "ft-sheet-verify: $*" >&2; }
# env 는 «양의 정수»만 받고(그 밖 = 기본값 + 로그 1줄) 낮추기만 된다 — 7초 룰(요청 1회 ≤7초)·일일 상한 24 는 올릴 수 없다(DA⑥ H1·H2 · 2차)
posint() { local v="$2"; if [[ "$v" =~ ^[0-9]+$ ]]; then v=$((10#$v)); [ "$v" -gt 0 ] && { echo "$v"; return; }; fi; log "$1='$2' 양의 정수 아님 — 기본 $3"; echo "$3"; }
TMO="$(posint FT_SHEET_VERIFY_TIMEOUT "$TMO" 7)"; LIMIT="$(posint FT_SHEET_VERIFY_LIMIT "$LIMIT" 24)"
[ "$TMO" -gt 7 ] && { log "FT_SHEET_VERIFY_TIMEOUT=$TMO — 상한 7 고정"; TMO=7; }
[ "$LIMIT" -gt 24 ] && { log "FT_SHEET_VERIFY_LIMIT=$LIMIT — 상한 24 고정"; LIMIT=24; }
command -v timeout >/dev/null || { log "timeout 명령 없음 (폴백 0)"; exit 2; }
[ -z "${FT_SHEET_VERIFY_CMD:-}" ] && [ ! -f "$ST/mcp-empty.json" ] && { log "mcp-empty.json 없음 $ST (폴백 0)"; exit 2; }
mkdir -p "$ST"

# 단일 실행(flock 대체 — macOS 기본 없음): mkdir 락 + 죽은 pid 회수 · 겹침 = rc 0 + 로그 1줄
LOCK="$ST/sheet-verify.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  if kill -0 "$(cat "$LOCK/pid" 2>/dev/null)" 2>/dev/null; then log "다른 검증 실행 중 — skip"; exit 0; fi
  rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || { log "다른 검증 실행 중 — skip"; exit 0; }
fi
echo $$ > "$LOCK/pid"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP" "$LOCK"' EXIT

REV="$("$BOARD" render --sheet --rev | python3 -c 'import json,sys; print(json.load(sys.stdin)["publish"])')" || { log "render --sheet --rev 실패 — 검증 0"; exit 0; }
# 원장·머리·쪽지·메모 쓰기는 이 python 한 곳 — 인자: 모드(pre|post) …
py() { python3 - "$@" <<'PY'
import json, os, re, subprocess, sys, tempfile
mode, rev, day, now, led, head, notes, root, here, mbox, frm = sys.argv[1:12]
rows = [json.loads(x) for x in open(led, encoding="utf-8") if x.strip()] if os.path.isfile(led) else []
def append(r):
    open(led, "a", encoding="utf-8").write(json.dumps(r, ensure_ascii=False) + "\n")
def write_head(text):
    open(head, "w", encoding="utf-8").write(f"검증 {now[11:16]} · {text}\n")
if mode == "pre":  # 같은 발행 rev 1회 · 일일 상한(오늘 행 수)
    today = sum(1 for r in rows if str(r["ts"])[:10] == day)
    print("SKIP-REV" if any(r["rev"] == rev for r in rows) else f"SKIP-LIMIT {today}" if today >= int(sys.argv[12]) else "RUN")
elif mode == "fail":  # 검증 실패 — 머리 1줄 + 실행 표식(같은 rev 재호출 0)
    write_head(f"검증 실패({sys.argv[12]})"); append({"rev": rev, "cell": "-", "seat": "-", "ts": now, "ok": False})
else:  # post — LLM JSON 을 읽어 집행
    sys.path.insert(0, here)
    import ft_board_sheet_notes as sn
    try:
        d = json.load(open(sys.argv[12], encoding="utf-8")); assert isinstance(d, dict)
    except Exception:
        write_head("검증 실패(JSON)"); append({"rev": rev, "cell": "-", "seat": "-", "ts": now, "ok": False}); sys.exit(0)
    md = open(sys.argv[13], encoding="utf-8").read()
    unconf = {m[1]: m[2] for m in re.finditer(r"^- (([①-⑩]) .+?): 소유자 미확인\(", md, re.M)}  # 시트에 실재하는 미확인 칸만 — LLM 이 칸을 지어내지 못한다
    cmds = {"③": "[정지 레디]·[완료] 머리 쪽지(mbox.sh send)", "⑤": "ft-gh-as-tank.sh label --apply"}
    seats = {}
    for f in sorted(os.listdir(os.path.join(root, ".fable-team"))):
        if re.fullmatch(r"seats(-.+)?\.json", f):
            j = json.load(open(os.path.join(root, ".fable-team", f), encoding="utf-8"))
            if j.get("_master"): seats[j.get("_label") or f[6:-5]] = j["_master"]
    valid = [c for c in d.get("unconfirmed", []) if c in unconf]
    done_today = {r["cell"] for r in rows if str(r["ts"])[:10] == day and r["seat"] != "-"}
    sent = 0
    for c in valid:
        seat, cmd = seats.get(c.split(" ", 1)[1]), cmds.get(unconf[c])
        if c in done_today or not seat or not cmd: continue
        body = f"[요청] {c} 사실 0 — {cmd} 으로 남겨 주세요"
        r = subprocess.run([mbox, "send", seat, frm, body], capture_output=True, text=True)
        if r.returncode != 0:
            print(f"ft-sheet-verify: 쪽지 실패 {seat} rc={r.returncode} — 원장 기록 0(다음 실행 재시도)", file=sys.stderr); continue
        append({"rev": rev, "cell": c, "seat": seat, "ts": now}); sent += 1
    have = open(notes, encoding="utf-8").read().splitlines() if os.path.isfile(notes) else []
    added = 0
    for it in list(d.get("term_candidates", [])) + list(d.get("question_lint", [])):
        if not isinstance(it, dict): continue
        cl = lambda k: re.sub(r"[|\n\r]+", " ", str(it.get(k, ""))).strip()  # noqa: E731
        line = f"{cl('id')}.{cl('field')} | {cl('wrong')} | {cl('suggest')}"
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as t: t.write(line + "\n")
        good = sn.lint_notes(__import__("pathlib").Path(root), __import__("pathlib").Path(t.name))  # S1 lint 통과분만
        os.unlink(t.name)
        if good and good[0][0] and line not in have:
            open(notes, "a", encoding="utf-8").write(line + "\n"); have.append(line); added += 1
    append({"rev": rev, "cell": "-", "seat": "-", "ts": now, "ok": True})
    write_head(f"미확인 {len(valid)} · 메모 {added} · 요청 {sent}")
PY
}
ARGS=("$REV" "$DAY" "$NOW" "$LED" "$HEADF" "$NOTES" "$ROOT" "$HERE" "$MBOX" "$FROM")
PRE="$(py pre "${ARGS[@]}" "$LIMIT")" || { log "원장 읽기 실패 — 검증 0"; exit 0; }
case "$PRE" in
  SKIP-REV)   log "같은 발행 rev $REV — 검증 0"; exit 0 ;;
  SKIP-LIMIT*) log "일일 상한 ${PRE#SKIP-LIMIT } ≥ $LIMIT — 검증 0(상한 완화 0)"; exit 0 ;;
esac
"$BOARD" render --sheet > "$TMP/sheet.md" || { log "render --sheet 실패 — 검증 0"; exit 0; }
[ "$(wc -c < "$TMP/sheet.md")" -le "$MAX_MD" ] || { log "시트 md 40KB 초과 — 검증 실패"; py fail "${ARGS[@]}" "시트 40KB 초과"; exit 0; }
{ cat "$HERE/ft-sheet-verify.prompt.md"; printf '\n--- 시트 md ---\n'; cat "$TMP/sheet.md"; } > "$TMP/in.txt"

OUT=""; rc=1  # 단일 요청 1회 = timeout 7 + 재시도 1 (실패 = 폴백 0 · 이 발행 검증 skip)
for _ in 1 2; do
  OUT="$(timeout "$TMO" "${CMD[@]}" < "$TMP/in.txt" 2>"$TMP/llm.err")"; rc=$?
  [ "$rc" -eq 0 ] && [ -n "$OUT" ] && break; OUT=""
done
if [ -z "$OUT" ]; then
  why="rc=$rc"; [ "$rc" -eq 124 ] && why="timeout"
  log "검증 실패($why) rev=$REV — 이 발행 검증 skip"; py fail "${ARGS[@]}" "$why"; exit 0
fi
printf '%s' "$OUT" > "$TMP/out.json"
py post "${ARGS[@]}" "$TMP/out.json" "$TMP/sheet.md"; exit 0
