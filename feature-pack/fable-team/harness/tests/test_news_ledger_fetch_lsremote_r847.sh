#!/bin/bash
# test_news_ledger_fetch_lsremote_r847.sh — r847: 뉴스 원장 ref fetch(ft_news_ledger.fetch_if_stale) + 원장 사본 sync(ft-ledger-repo-sync.sh)
# ⓐ 마지막 fetch 성공 60초 전(r706 전용 표식) → fetch 0 · 표식 깨짐 = WARN + fetch 1
# ⓑ ls-remote 원격 main == 사본 origin/main → fetch 0 + «fetch 생략(ls-remote 같음)» · 다르면 fetch 1 · ls-remote 실패 = fetch 로 진행 + 로그 1줄(판정 불가 0)
# ⓒ fetch 25초 → 성공(30초 상한) · 35초(TERM 무시) → 30초에서 TERM→1초 KILL · 재시도 1(출력 0) · 총 70초 안 · 남은 자식 0 · 출력 있는 실패 = 재시도 0
# ⓓ ft-ledger-repo-sync.sh: 같으면 fetch 0 · 25초 fetch 성공(30초) · 공용 fm_fetch/fm_t7 7초 그대로
# ⓔ 같은 실패 이유 연속 = «판정 불가» 줄 1통 · 성공 1회 뒤 다시 실패 = 새 1통 · 키 = 상태 1파일
# r2(DA r1 반례): ② ls-remote·로컬 ref 6초 + TERM 무시 fetch = 총 ≤ 70.0초 ③ 셸 fetch stdout 오류 = 시도 1 · 오류 = 첫 줄
# r3(DA r2 재설계): 경고 = 실패 구간당 1통 — pid 바뀌는 같은 장애 3틱 = 1통 · 사유 바뀜 = 1통 · 실패→성공→실패 = 2통 · 게시 실패 틱 = 다음 틱 다시 1통
# ⓖ 변이: 표식→FETCH_HEAD 본문 읽기 → ⓐ FAIL · ls-remote 생략 삭제 → ⓑ FAIL · 30→10.5초 → ⓒ 25초 FAIL · 구간 판정 삭제 → ⓔ FAIL
#   유예 빼기 삭제 → ② FAIL · 셸 재시도 = rc 만 → ③ FAIL · 구간 판정 = 출력 글자 비교 → pid 칸 FAIL
# r4(DA r3 재설계): ⓗ 받기 실패 = 지도 0 · 30분 창 안 첫 틱 1통 ⓘ fetch-last 000 = 1통·ERROR 1 ⓙ 444 뒤 성공·재실패 = 둘째 구간 1통 ⓚ 상태 폴더 555 = rc 1
#   변이: os.replace → write_text → ⓘ·ⓙ FAIL · ⓗ 게시 막음 삭제 → ⓗ FAIL · 30분 대기 우회 삭제 → ⓗ FAIL
# r5(DA r4 반례): ⓛ 첨부 대기 + 받기 실패 2틱 = 첨부 시도 0 · 회복 틱 첨부 1(실제 retry_attach · Slack 경계만 대역) · 변이: 실패 분기 앞 재시도 → ⓛ FAIL
# 픽스처 = 임시 bare 원격 + 원장 사본 + PATH git 래퍼(ls-remote·fetch 지연·실패 주입 · TERM 무시) · 실 원격·실 뉴스 발행·실 상태 0
# R847_BIN = 시험할 bin 폴더(기본 harness/bin · 빨강 기준판 대조용)
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HB="${R847_BIN:-$HERE/../bin}"
PY="${PYTHON:-python3.11}"
T="$(mktemp -d)"
MARK="35.0347"  # 남은 자식 판별용 sleep 인자
trap 'pkill -9 -f "sleep $MARK" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
REAL_GIT="$(command -v git)"

mkdir -p "$T/bin" "$T/root/.fable-team"
cat > "$T/bin/git" <<EOF
#!/bin/bash
case " \$* " in
  *" ls-remote "*) echo x >> "$T/ls.cnt"
    [ "\${FAKE_LS:-}" = fail ] && { echo "fatal: ls-remote 주입 실패" >&2; exit 128; }
    [ -n "\${FAKE_LS_SLEEP:-}" ] && sleep "\$FAKE_LS_SLEEP" ;;
  *" rev-parse --verify -q refs/remotes/origin/main "*) [ -n "\${FAKE_REV_SLEEP:-}" ] && sleep "\$FAKE_REV_SLEEP" ;;
  *" fetch "*) echo x >> "$T/fetch.cnt"
    [ -n "\${FAKE_IGNORE_TERM:-}" ] && trap '' TERM
    [ -n "\${FAKE_SLEEP:-}" ] && { sleep "\$FAKE_SLEEP" & wait \$!; }
    [ -n "\${FAKE_FAIL_STDOUT:-}" ] && { echo "fatal: \$FAKE_FAIL_STDOUT"; exit 1; }
    [ -n "\${FAKE_FAIL:-}" ] && { echo "fatal: \$FAKE_FAIL" >&2; exit 1; } ;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/bin/git"
export PATH="$T/bin:$PATH" FT_ROOT="$T/root" FT_NEWS_FETCH_STAMP="$T/fetch.stamp" FT_NEWS_FETCH_LAST="$T/fetch.last" FT_MBOX="$T/no-mbox.sh"
unset FT_LEDGER_FETCH FT_LEDGER_SYNC_ERROR FT_LEDGER_SYNC_KEY FT_LEDGER_SYNC_REPEAT FT_NEWS_FETCH_TIMEOUT FT_NEWS_FETCH_BUDGET FT_NEWS_FETCH_MIN
cnt() { [ -f "$T/$1.cnt" ] && grep -c . "$T/$1.cnt" || echo 0; }
reset() { rm -f "$T"/*.cnt "$T/fetch.stamp" "$T/fetch.last"; unset FAKE_LS FAKE_SLEEP FAKE_FAIL FAKE_IGNORE_TERM FAKE_LS_SLEEP FAKE_REV_SLEEP FAKE_FAIL_STDOUT; }

REL="design/teams/planner/PLAN-oppa-ledger.md"
g init -q --bare "$T/origin.git"
g clone -q "$T/origin.git" "$T/w" 2>/dev/null
mkdir -p "$T/w/$(dirname "$REL")"; echo "원장 A" > "$T/w/$REL"
g -C "$T/w" add -A && g -C "$T/w" commit -qm one && g -C "$T/w" push -q origin HEAD:main
g clone -q "$T/origin.git" "$T/C" 2>/dev/null
git -C "$T/C" checkout -q --detach origin/main
push_other() { echo "$1" >> "$T/w/other.txt"; g -C "$T/w" add -A; g -C "$T/w" commit -qm "$1"; g -C "$T/w" push -q origin HEAD:main; }

# fetch_if_stale 1회 — stdout 1줄 = "ret=<반환>" · 로그는 $T/py.log
fis() {  # fis <bin>
  PYTHONPATH="$1" "$PY" - "$T/C" > "$T/py.out" 2> "$T/py.log" <<'PY'
import logging, sys, time
from pathlib import Path
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
import ft_news_ledger as nl
t0 = time.monotonic()
print("ret=" + nl.fetch_if_stale(Path(sys.argv[1])))
print(f"elapsed={time.monotonic() - t0:.3f}")
PY
}

chk_a() {  # ⓐ
  local B="$1"; reset; push_other a1
  printf '%s\n' "$(( $(date +%s) - 60 ))" > "$T/fetch.stamp"
  printf '%s\t\tbranch main of x\n' "$(git -C "$T/C" rev-parse HEAD)" > "$(git -C "$T/C" rev-parse --path-format=absolute --git-common-dir)/FETCH_HEAD"
  fis "$B"
  [ "$(cnt fetch)" = 0 ] && [ "$(cnt ls)" = 0 ] && grep -qx 'ret=' "$T/py.out" || return 1
  echo "x" > "$T/fetch.stamp"; fis "$B"
  [ "$(cnt fetch)" = 1 ] && grep -q 'WARNING fetch 표식 깨짐' "$T/py.log" && ! grep -q ValueError "$T/py.log"
}
chk_b() {  # ⓑ
  local B="$1"; reset; "$REAL_GIT" -C "$T/C" fetch -q origin main  # 시험 준비 = 진짜 git(래퍼 카운터 밖)
  fis "$B"; [ "$(cnt ls)" = 1 ] && [ "$(cnt fetch)" = 0 ] && grep -q 'fetch 생략(ls-remote 같음)' "$T/py.log" || return 1
  reset; push_other b1; fis "$B"
  [ "$(cnt fetch)" = 1 ] && [ "$(git -C "$T/C" rev-parse origin/main)" = "$(git -C "$T/w" rev-parse HEAD)" ] || return 1
  reset; push_other b2; export FAKE_LS=fail; fis "$B"
  [ "$(cnt fetch)" = 1 ] && grep -qx 'ret=' "$T/py.out" && [ "$(grep -c 'ls-remote 실패 — fetch 로 진행' "$T/py.log")" = 1 ]
}
chk_c25() {  # ⓒ 25초 지연 = 성공
  local B="$1" t0; reset; push_other c1; export FAKE_SLEEP=25; t0=$SECONDS; fis "$B"
  [ "$(cnt fetch)" = 1 ] && grep -qx 'ret=' "$T/py.out" && [ $((SECONDS - t0)) -ge 24 ]
}
chk_c35() {  # ⓒ 35초 · TERM 무시 = 30초 상한 · KILL · 재시도 1 · 70초 안 · 남은 자식 0
  local B="$1" t0 el; reset; push_other c2; export FAKE_SLEEP="$MARK" FAKE_IGNORE_TERM=1; t0=$SECONDS; fis "$B"; el=$((SECONDS - t0))
  echo "  (35초 칸 경과 ${el}초 · 시도 $(cnt fetch))"
  [ "$(cnt fetch)" = 2 ] && [ "$el" -ge 60 ] && [ "$el" -le 70 ] && grep -q '^ret=원장 ref fetch 실패 — fetch 실행 실패: 시도 상한 ' "$T/py.out" \
    && ! pgrep -f "sleep $MARK" >/dev/null || return 1
  reset; export FAKE_FAIL=offline; fis "$B"
  [ "$(cnt fetch)" = 1 ] && grep -q '^ret=원장 ref fetch 실패 — fatal: offline' "$T/py.out"
}
chk_t70() {  # r2 반례 2 — ls-remote·로컬 ref 각 6초 + fetch 부모·자식 TERM 무시 → 총 ≤ 70.0초 · 시도 2 · 남은 자식 0
  local B="$1"; reset; push_other t70; export FAKE_LS_SLEEP=6 FAKE_REV_SLEEP=6 FAKE_SLEEP="$MARK" FAKE_IGNORE_TERM=1; fis "$B"
  echo "  (총 마감 칸 $(grep '^elapsed=' "$T/py.out") · 시도 $(cnt fetch))"
  [ "$(cnt fetch)" = 2 ] && "$PY" -c "import sys; sys.exit(0 if float(sys.argv[1]) <= 70.0 else 1)" "$(sed -n 's/^elapsed=//p' "$T/py.out")" \
    && ! pgrep -f "sleep $MARK" >/dev/null
}
chk_s() {  # r2 반례 3 — sync 스크립트 fetch 가 stdout 에 오류 + rc1 → 시도 1 · 오류 = 그 출력 첫 줄
  local B="$1" out rc; reset; push_other s1; export FAKE_FAIL_STDOUT="stdout 오류 주입"
  out="$(bash "$B/ft-ledger-repo-sync.sh" "$T/C" 2>/dev/null)"; rc=$?
  echo "  (셸 칸 rc=$rc 시도 $(cnt fetch) · $out)"
  [ "$rc" = 4 ] && [ "$(cnt fetch)" = 1 ] && [ "$out" = "ERROR ledger 사본 fetch 실패: fatal: stdout 오류 주입" ]
}

SYNC="$HB/ft-ledger-repo-sync.sh"
chk_d() {  # ⓓ
  local B="$1" out rc; reset; "$REAL_GIT" -C "$T/C" fetch -q origin main; git -C "$T/C" checkout -q --detach origin/main
  out="$(bash "$B/ft-ledger-repo-sync.sh" "$T/C" 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && [ "${out% *}" = "SYNC up-to-date" ] && [ "$(cnt fetch)" = 0 ] && [ "$(cnt ls)" = 1 ] || { echo "  ⓓ1 rc=$rc out=$out"; return 1; }
  reset; push_other d1; export FAKE_SLEEP=25
  out="$(bash "$B/ft-ledger-repo-sync.sh" "$T/C" 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && [ "$(git -C "$T/C" rev-parse HEAD)" = "$(git -C "$T/w" rev-parse HEAD)" ] && [ "$(cnt fetch)" = 1 ] || { echo "  ⓓ2 rc=$rc out=$out"; return 1; }
  grep -q '"$tb" 7 "$@"' "$B/ft-merge-lib.sh" && grep -q '^fm_fetch() { fm_t7 git -c gc.auto=0' "$B/ft-merge-lib.sh"
}

e_run() {  # e_run <bin> — E_SEQ([[HH:MM, 실패 문구|""], …]) 틱을 _run 으로 돌려 «판정 불가» 줄·키 파일을 $T/e.out 에
  local B="$1"; reset; "$REAL_GIT" -C "$T/C" fetch -q origin main
  PYTHONPATH="$B" "$PY" - "$T" "$REL" > "$T/e.out" 2> "$T/e.log" <<'PY'
import json, logging, os, subprocess, sys
from datetime import datetime, timedelta
from pathlib import Path
T, REL = Path(sys.argv[1]), sys.argv[2]
import ft_news_html as fh, ft_news_ledger as fl, ft_news_publish as fp
live, root = T / "C", T / "root"
state = root / ".fable-team" / "state" / "news-ledger"
state.mkdir(parents=True, exist_ok=True)
git = lambda *a: subprocess.run(["git", "-C", str(live), *a], check=True, capture_output=True, text=True).stdout.strip()
cur = git("rev-parse", "origin/main")
(state / "last.sha").write_text(cur + "\n", encoding="utf-8")
(state / "last.blob").write_text(("0" * 40 if os.environ.get("E_STALE_BLOB") else git("rev-parse", f"{cur}:{REL}")) + "\n", encoding="utf-8")  # E_STALE_BLOB = 블롭 바뀜 흉내(지도 낼 조건)
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
if os.environ.get("E_LAST_INIT"):  # 상태 1칸 초기값(ⓘ)
    Path(os.environ["FT_NEWS_FETCH_LAST"]).write_text(os.environ["E_LAST_INIT"] + "\n", encoding="utf-8")
lines, made = [], []
fh.build = lambda *a: {"goals": [], "live": []}
fh.run_files = lambda d, out, now: (made.append(now), (out / "a.html", out / "a.txt"))[1]
fh.publish_files = lambda h, s, now: (0, {"ts": "1", "link": "http://x/1"})
pub_rc = [0]  # 이 틱 게시 결과(E_SEQ 셋째 칸 · 기본 0)
fp.publish_line = lambda text, now: (lines.append(text), pub_rc[0])[1]
attempts = []  # ⓛ 첨부 재시도 시각(HH:MM)
if os.environ.get("E_ATTACH"):  # ⓛ(r5) 실제 retry_attach 경로 — Slack 경계(_target·_find_posted·_link·post_root·upload_file)만 대역
    import magazine_slack
    from types import SimpleNamespace
    fp._target = lambda *a: SimpleNamespace(channel="TEMP")
    fp._find_posted = lambda *a: ""
    fp._link = lambda *a: "http://x/map-0855"
    fp.post_root = lambda *a: "map-0855"
    def upload(t, ts, html_p, *a, **k):
        if ts is None:  # 08:55 지도 글 첫 첨부 = 실패 주입(rc3 → 첨부 대기 기록)
            raise fp.MirrorError("첨부 실패 주입")
        attempts.append(os.environ["FT_NEWS_NOW"][11:])
    magazine_slack.upload_file = upload
    os.environ["FT_NEWS_DIR"] = str(T)  # 대기 기록 자리(_paths) 푸는 데 필요 · 아래 update 와 같은 값
    (T / "map-0855.html").write_text("<html>08:55 지도</html>", encoding="utf-8")
    seed_rc = fp.publish_html(T / "map-0855.html", "08:55 요약", datetime(2026, 10, 24, 8, 55))[0]
    print("SEED", seed_rc, (root / ".fable-team/state/news-publish/pending-attach.json").is_file())
else:
    fp.retry_attach = lambda now: None
fh._canon_sha = lambda: ""
os.environ.update(FT_NEWS_MODE="html", FT_LEDGER_REPO=str(live), FT_LEDGER_PATH=REL, FT_NEWS_DIR=str(T), FT_NEWS_REPEAT_MIN="30", FT_NEWS_STATUS_INTERVAL="0")

def push(tag):
    w = T / "w"
    (w / "other.txt").open("a", encoding="utf-8").write(tag + "\n")
    for a in (["add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", tag], ["push", "-q", "origin", "HEAD:main"]):
        subprocess.run(["git", "-C", str(w), *a], check=True, capture_output=True)

def tick(hhmm, msg):
    at = "08:00"
    if os.environ.get("E_AT_RECENT"):  # 마지막 게시 5분 전 = 30분 반복 대기 창 안(ⓗ)
        at = (datetime.strptime(hhmm, "%H:%M") - timedelta(minutes=5)).strftime("%H:%M")
    (state / "html.json").write_text(json.dumps({"at": f"2026-10-24 {at}", "map_at": "2026-10-24 08:00", "link": "http://x/0"}), encoding="utf-8")
    Path(os.environ["FT_NEWS_FETCH_STAMP"]).unlink(missing_ok=True)  # 매 틱 받기 시도(300초 건너뛰기 밖)
    for k in ("FT_LEDGER_SYNC_ERROR", "FT_LEDGER_SYNC_KEY", "FT_LEDGER_SYNC_REPEAT", "FT_NEWS_HEAD"):
        os.environ.pop(k, None)
    os.environ["FT_NEWS_NOW"] = f"2026-10-24 {hhmm}"
    if msg:
        os.environ["FAKE_FAIL"] = msg
    else:
        os.environ.pop("FAKE_FAIL", None)
    push(hhmm)  # 원격이 한 걸음 앞(원장 블롭은 그대로 = 변화 0 경로)
    return fl._run(root, state)

for item in json.loads(os.environ["E_SEQ"]):  # [[HH:MM, 실패 문구 | "" = 성공, (게시 rc), (틱 전 fetch-last 권한 8진수)], …]
    hhmm, msg = item[0], item[1]
    pub_rc[0] = item[2] if len(item) > 2 else 0
    if len(item) > 3:
        os.chmod(os.environ["FT_NEWS_FETCH_LAST"], int(item[3], 8))
    rc = tick(hhmm, msg)
    print(hhmm, rc, json.dumps([l for l in lines if l.startswith(f"[뉴스 {hhmm}]")], ensure_ascii=False))
bad = [l for l in lines if "판정 불가" in l]
print("UNJUDGEABLE", " ".join(l[4:9] for l in bad))  # «[뉴스 HH:MM] 판정 불가 …» 의 HH:MM
print("MAPS", len(made))
print("ATTACH", " ".join(attempts))
print("PENDING", (root / ".fable-team/state/news-publish/pending-attach.json").is_file())
last_f = Path(os.environ["FT_NEWS_FETCH_LAST"])
print("LAST", last_f.read_text(encoding="utf-8").strip() if last_f.exists() else "-")
PY
}
chk_e() {  # ⓔ(r3) 실패 구간당 «판정 불가» 1통 · 성공→실패 전이 = 새 1통 · 상태 = fetch-last 1칸
  E_SEQ='[["09:00","offline"],["09:31","offline"],["10:02","offline"],["10:33",""],["11:04","offline"],["11:35","offline"]]' e_run "$1"
  grep -qx 'UNJUDGEABLE 09:00 11:04' "$T/e.out" \
    && grep -q '^10:33 .*변화 없음' "$T/e.out" && ! grep -qE '^(09:31|10:02|11:35) .*변화 없음' "$T/e.out" && grep -qx 'LAST fail' "$T/e.out"
}
chk_e2() {  # r1 반례 — 사유가 바뀌어도(앞 160자 같고 끝만 다름 · 완전히 다른 사유) 같은 실패 구간 = 1통
  local P; P="$(printf 'x%.0s' $(seq 170))"
  E_SEQ="[[\"09:00\",\"$P DNS 실패\"],[\"09:31\",\"$P 접속 실패\"],[\"10:02\",\"전혀 다른 사유\"]]" e_run "$1"
  grep -qx 'UNJUDGEABLE 09:00' "$T/e.out"
}
chk_h() {  # ⓗ(r4) 받기 실패 ∧ 블롭 바뀜 흉내 ∧ 30분 창 안 → 지도 0 · 구간 첫 틱 «판정 불가» 1통 · 2·3틱 게시 0
  E_STALE_BLOB=1 E_AT_RECENT=1 E_SEQ='[["09:00","offline"],["09:31","offline"],["10:02","offline"]]' e_run "$1"
  grep -qx 'UNJUDGEABLE 09:00' "$T/e.out" && grep -qx 'MAPS 0' "$T/e.out" \
    && grep -q "^09:00 (0, '원장 ref fetch 실패')" "$T/e.out" && [ "$(grep -c '^[0-9:]* (0, .* \[\]$' "$T/e.out")" = 2 ]
}
chk_i() {  # ⓘ(r4 · DA r3 반례 1) fetch-last=ok · 권한 000 · offline 3틱 → 1통 · ERROR(못 읽음) 1줄 · 뒤에 파일 읽힘
  E_LAST_INIT=ok E_SEQ='[["09:00","offline",0,"000"],["09:31","offline"],["10:02","offline"]]' e_run "$1"
  grep -qx 'UNJUDGEABLE 09:00' "$T/e.out" && [ "$(grep -c '^ERROR fetch 마지막 결과 못 읽음' "$T/e.log")" = 1 ] && grep -qx 'LAST fail' "$T/e.out"
}
chk_j() {  # ⓙ(r4 · DA r3 반례 2) 실패 1통 → 권한 444 → 성공 → 재실패 2틱 → 둘째 구간 1통(합 2통)
  E_SEQ='[["09:00","offline"],["09:31","",0,"444"],["10:02","offline"],["10:33","offline"]]' e_run "$1"
  grep -qx 'UNJUDGEABLE 09:00 10:02' "$T/e.out"
}
chk_k() {  # ⓚ(r4) 상태 폴더 쓰기 불가(555) → tick rc 1 · 사유 «상태 파일 fetch-last 쓰기 실패» · ERROR 줄 · 조용한 rc0 0
  local r; mkdir -p "$T/sd"; chmod 555 "$T/sd"
  FT_NEWS_FETCH_LAST="$T/sd/fetch-last" E_SEQ='[["09:00",""],["09:31","offline"]]' e_run "$1"; r=$?
  chmod 755 "$T/sd"
  grep -qE "^09:00 \(1, [\"']상태 파일 fetch-last 쓰기 실패" "$T/e.out" && grep -qE "^09:31 \(1, [\"']상태 파일 fetch-last 쓰기 실패" "$T/e.out" \
    && grep -q '^ERROR 상태 파일 fetch-last 쓰기 실패' "$T/e.log" && [ "$r" = 0 ]
}
chk_l() {  # ⓛ(r5 · DA r4 반례) 08:55 지도 첨부 실패(rc3) → 대기 기록 · 09:00·09:01 offline = 첨부 시도 0 · 09:01 게시 0 · 09:02 받기 성공 = 첨부 1 · 대기 기록 비움
  E_ATTACH=1 E_AT_RECENT=1 E_SEQ='[["09:00","offline"],["09:01","offline"],["09:02",""]]' e_run "$1"
  grep -qx 'SEED 3 True' "$T/e.out" && grep -qx 'UNJUDGEABLE 09:00' "$T/e.out" && grep -q '^09:01 (0, .* \[\]$' "$T/e.out" \
    && grep -qx 'ATTACH 09:02' "$T/e.out" && grep -qx 'PENDING False' "$T/e.out"
}
chk_pid() {  # r2 DA 반례 — pid 가 틱마다 바뀌는 같은 장애 3틱 = «판정 불가» 1통
  E_SEQ='[["09:00","lock held by pid 4101"],["09:31","lock held by pid 4177"],["10:02","lock held by pid 4230"]]' e_run "$1"
  grep -qx 'UNJUDGEABLE 09:00' "$T/e.out"
}
chk_pub() {  # 게시 실패 틱 = 알림으로 치지 않음 → 다음 틱 다시 1통 · 그 뒤 0
  E_SEQ='[["09:00","offline",1],["09:31","offline"],["10:02","offline"]]' e_run "$1"
  grep -qx 'UNJUDGEABLE 09:00 09:31' "$T/e.out" && grep -qx 'LAST fail' "$T/e.out"
}

run_all() {  # run_all <bin> <접두>
  local B="$1" p="$2"
  chk_a "$B" && ok "${p}ⓐ 표식 60초 전 = fetch 0 · 표식 깨짐 = WARN + fetch 1 · ValueError 0" || bad "${p}ⓐ fetch=$(cnt fetch) ls=$(cnt ls) $(tr '\n' ' ' < "$T/py.out") $(tail -2 "$T/py.log" | tr '\n' ' ')"
  chk_b "$B" && ok "${p}ⓑ ls-remote 같음 = fetch 0 · 다름 = fetch 1 · 묻기 실패 = fetch 로 진행 + 로그 1줄" || bad "${p}ⓑ fetch=$(cnt fetch) ls=$(cnt ls) $(tr '\n' ' ' < "$T/py.out") $(tail -2 "$T/py.log" | tr '\n' ' ')"
  chk_c25 "$B" && ok "${p}ⓒ 25초 fetch = 성공(30초 상한)" || bad "${p}ⓒ 25초 fetch=$(cnt fetch) $(tr '\n' ' ' < "$T/py.out")"
}

run_all "$HB" ""
chk_c35 "$HB" && ok "ⓒ 35초·TERM 무시 = 30초 TERM→KILL · 재시도 1 · 70초 안 · 남은 자식 0 · 출력 있는 실패 = 재시도 0" || bad "ⓒ 35초 fetch=$(cnt fetch) $(tr '\n' ' ' < "$T/py.out")"
chk_d "$HB" && ok "ⓓ sync: ls-remote 같음 = fetch 0 · 25초 fetch 성공 · 공용 fm_t7 7초 그대로" || bad "ⓓ sync"
chk_e "$HB" && ok "ⓔ 실패 구간당 «판정 불가» 1통 · 실패→성공→실패 = 2통 · fetch-last = fail" || bad "ⓔ $(tr '\n' ' ' < "$T/e.out") $(tail -3 "$T/e.log" | tr '\n' ' ')"
chk_e2 "$HB" && ok "r3 사유가 바뀌어도 같은 실패 구간 = 1통(r1 반례)" || bad "r3 사유 $(grep UNJUDGEABLE "$T/e.out") $(tail -3 "$T/e.log" | tr '\n' ' ')"
chk_pid "$HB" && ok "r3 pid 바뀌는 같은 장애 3틱 = 1통(r2 DA 반례)" || bad "r3 pid $(grep UNJUDGEABLE "$T/e.out") $(tail -3 "$T/e.log" | tr '\n' ' ')"
chk_pub "$HB" && ok "r3 게시 실패 틱 → 다음 틱 다시 1통 · 그 뒤 0" || bad "r3 게시 실패 $(grep -E 'UNJUDGEABLE|LAST' "$T/e.out" | tr '\n' ' ')"
chk_h "$HB" && ok "ⓗ 받기 실패 ∧ 블롭 바뀜 = 지도 0 · 30분 창 안 첫 틱도 «판정 불가» 1통 · 2·3틱 게시 0" || bad "ⓗ $(tr '\n' ' ' < "$T/e.out")"
chk_i "$HB" && ok "ⓘ fetch-last 000 · offline 3틱 = 1통 · ERROR 1줄 · 뒤에 읽힘(DA r3 반례 1)" || bad "ⓘ $(grep -E 'UNJUDGEABLE|LAST' "$T/e.out" | tr '\n' ' ') err=$(grep -c '^ERROR fetch 마지막' "$T/e.log")"
chk_j "$HB" && ok "ⓙ 실패 1통 → 444 → 성공 → 재실패 2틱 = 둘째 구간 1통(DA r3 반례 2)" || bad "ⓙ $(grep -E 'UNJUDGEABLE|LAST' "$T/e.out" | tr '\n' ' ')"
chk_k "$HB" && ok "ⓚ 상태 폴더 555 = tick rc 1 · «상태 파일 fetch-last 쓰기 실패» · ERROR 줄" || bad "ⓚ $(tr '\n' ' ' < "$T/e.out" | cut -c1-300)"
chk_l "$HB" && ok "ⓛ 첨부 대기 + 받기 실패 2틱 = 첨부 시도 0 · 회복 틱 첨부 1 · 대기 기록 비움(DA r4 반례 · 실제 retry_attach)" || bad "ⓛ $(grep -vE '^(ft-news-publish|INFO)' "$T/e.out" | tr '\n' ' ' | cut -c1-400)"
chk_t70 "$HB" && ok "r2② ls-remote·로컬 ref 각 6초 + TERM 무시 fetch = 총 ≤ 70.0초 · 시도 2 · 남은 자식 0" || bad "r2② $(tr '\n' ' ' < "$T/py.out")"
chk_s "$HB" && ok "r2③ 셸 fetch stdout 오류 = 시도 1 · 오류 = 출력 첫 줄" || bad "r2③ 셸"

# ⓖ 변이 — 사본 bin 에 한 군데씩 되돌림 · 해당 칸이 FAIL 이어야 «조건의 몫»
mutate() {  # mutate <이름> <old> <new> [파일=ft_news_ledger.py] → 변이 bin 경로(적용 실패 = 빈 값)
  local M="$T/mut-$1"; rm -rf "$M"; cp -R "$HB" "$M"
  "$PY" - "$M/${4:-ft_news_ledger.py}" "$2" "$3" <<'PY' && echo "$M"
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
}
M="$(mutate body '    last = _last_fetch()
' '    last = _mut_head(repo)
' )" && printf '\n\ndef _mut_head(repo):\n    try:\n        c = subprocess.run(["git", "-C", str(repo), "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True).stdout.strip()\n        return float((Path(c) / "FETCH_HEAD").read_text(encoding="utf-8").strip())\n    except (OSError, ValueError):\n        return None\n' >> "$M/ft_news_ledger.py"
[ -n "$M" ] && { chk_a "$M" && bad "ⓖ 변이(표식→FETCH_HEAD 본문) 인데 ⓐ PASS" || ok "ⓖ 표식→FETCH_HEAD 본문 읽기 → ⓐ FAIL"; } || bad "ⓖ 변이 적용 실패(body)"
M="$(mutate lsremote '    if _remote_same(repo, t_start):' '    if False:')"
[ -n "$M" ] && { chk_b "$M" && bad "ⓖ 변이(ls-remote 생략 삭제) 인데 ⓑ PASS" || ok "ⓖ ls-remote 생략 삭제 → ⓑ FAIL"; } || bad "ⓖ 변이 적용 실패(lsremote)"
M="$(mutate cap 'FETCH_TIMEOUT_S = 30.0' 'FETCH_TIMEOUT_S = 10.5')"
[ -n "$M" ] && { chk_c25 "$M" && bad "ⓖ 변이(30→10.5초) 인데 ⓒ 25초 PASS" || ok "ⓖ 30→10.5초 → ⓒ 25초 FAIL"; } || bad "ⓖ 변이 적용 실패(cap)"
M="$(mutate key '    repeat = fail_announced()' '    repeat = False')"
[ -n "$M" ] && { chk_e "$M" && bad "ⓖ 변이(구간 판정 삭제) 인데 ⓔ PASS" || ok "ⓖ 구간 판정 삭제 → ⓔ FAIL"; } || bad "ⓖ 변이 적용 실패(key)"
M="$(mutate text '    return _read_last() == "fail"' '    return _read_last() == "fail " + os.environ.get("FT_LEDGER_SYNC_ERROR", "")')"
[ -n "$M" ] && "$PY" - "$M/ft_news_ledger.py" <<'PY' || M=""
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old, new = '    _write_last("fail")', '    _write_last("fail " + os.environ.get("FT_LEDGER_SYNC_ERROR", ""))'
sys.exit(1) if s.count(old) != 1 else open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
[ -n "$M" ] && { chk_pid "$M" && bad "ⓖ 변이(구간 판정 = 출력 글자 비교) 인데 pid 칸 PASS" || ok "ⓖ 구간 판정 = 출력 글자 비교 → pid 칸 FAIL"; } || bad "ⓖ 변이 적용 실패(text)"
M="$(mutate atomic '        tmp.write_text(value + "\n", encoding="utf-8")
        os.replace(tmp, f)' '        f.write_text(value + "\n", encoding="utf-8")')"
[ -n "$M" ] && { chk_i "$M" && bad "ⓖ 변이(os.replace → write_text) 인데 ⓘ PASS" || ok "ⓖ os.replace → write_text → ⓘ FAIL"; } || bad "ⓖ 변이 적용 실패(atomic)"
[ -n "$M" ] && { chk_j "$M" && bad "ⓖ 변이(os.replace → write_text) 인데 ⓙ PASS" || ok "ⓖ os.replace → write_text → ⓙ FAIL"; }
M="$(mutate nomap '    if warn:  # r847 r4 ⓗ' '    if False:  # r847 r4 ⓗ' ft_news_html.py)"
[ -n "$M" ] && { chk_h "$M" && bad "ⓖ 변이(ⓗ 게시 막음 삭제) 인데 ⓗ PASS" || ok "ⓖ ⓗ 게시 막음 삭제 → ⓗ FAIL"; } || bad "ⓖ 변이 적용 실패(nomap)"
M="$(mutate wait30 '        rc = publish_line(zero_change_line(now, last, warn), now)  # r4: 30분 반복 대기 없이 구간 첫 틱 1통' '        if since("at") < timedelta(minutes=30):
            return 0, "원장 ref fetch 실패"
        rc = publish_line(zero_change_line(now, last, warn), now)' ft_news_html.py)"
[ -n "$M" ] && { chk_h "$M" && bad "ⓖ 변이(30분 대기 우회 삭제) 인데 ⓗ PASS" || ok "ⓖ 30분 대기 우회 삭제 → ⓗ «첫 실패 1통» FAIL"; } || bad "ⓖ 변이 적용 실패(wait30)"
M="$(mutate attach '    since = lambda k:' '    retry_attach(now)
    since = lambda k:' ft_news_html.py)"
[ -n "$M" ] && { chk_l "$M" && bad "ⓖ 변이(retry_attach 실패 분기 앞) 인데 ⓛ PASS" || ok "ⓖ retry_attach 를 실패 분기 앞으로 → ⓛ FAIL($(grep '^ATTACH' "$T/e.out"))"; } || bad "ⓖ 변이 적용 실패(attach)"
M="$(mutate grace '    return min(per, budget - spent - KILL_GRACE_S - STAGE_SLACK_S)' '    return min(per, budget - spent)')"
[ -n "$M" ] && { chk_t70 "$M" && bad "ⓖ 변이(유예 빼기 삭제) 인데 r2② PASS" || ok "ⓖ 유예 빼기 삭제 → r2② FAIL"; } || bad "ⓖ 변이 적용 실패(grace)"
M="$(mutate shretry '    if [ -s "$FO" ] || [ -s "$FE" ]; then break; fi' '    if false; then break; fi' ft-ledger-repo-sync.sh)"
[ -n "$M" ] && { chk_s "$M" && bad "ⓖ 변이(셸 재시도 = rc 만) 인데 r2③ PASS" || ok "ⓖ 셸 재시도 조건 = rc 만 → r2③ FAIL"; } || bad "ⓖ 변이 적용 실패(shretry)"

pgrep -f "sleep $MARK" >/dev/null && bad "남은 자식(sleep $MARK) 있음" || ok "남은 자식 0"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
