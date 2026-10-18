#!/usr/bin/env bash
# test_board.sh — ft-board.py(collect·render --term|--slack·snapshot·prune) 시험 (판정 421·496).
# 전부 mktemp 임시 FT_ROOT(가짜 seats-*.json 5팀 · 카드 폴더 · 가짜 verdicts.jsonl) + 스텁 env(FT_BOARD_GH·TMUX·INBOX·SEAT_STATUS).
# 실제 gh·tmux·슬랙 호출 0 · 라이브 .fable-team 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || bad "$1 (없음: $3)"; }
lacks() { printf '%s' "$2" | grep -qF -- "$3" && bad "$1 (있으면 안 됨: $3)" || ok "$1"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

export FT_ROOT="$T/root" FT_BOARD_NOW="2026-10-09T10:00:00" FT_BOARD_GH_TTL=0 FT_BOARD_GH_REFRESH=1
export FT_VERDICT_BIN="$BIN/ft-verdict.sh"
export FT_BOARD_TMUX="bash $T/tmux.sh" FT_BOARD_GH="cat $T/gh.json" FT_BOARD_INBOX="bash $T/inbox.sh" FT_BOARD_SEAT_STATUS="$T/status.sh"
FB="$FT_ROOT/.fable-team"; mkdir -p "$FB/comm" "$FB/state"
board() { python3 "$BIN/ft-board.py" "$@"; }

python3 - "$T" <<'PY'
import json, os, sys, datetime as dt
from pathlib import Path
T = Path(sys.argv[1]); R = T / "root"; FB = R / ".fable-team"
def ts(s): return dt.datetime.fromisoformat(s).timestamp()
def card(team, folder, name, title, when):
    p = R / team / folder / f"{name}.md"; p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(f"# 인덱스: {title}\n본문\n", encoding="utf-8"); os.utime(p, (ts(when), ts(when)))
def seats(name, body): (FB / f"seats-{name}.json").write_text(json.dumps(body, ensure_ascii=False), encoding="utf-8")
seats("alpha", {"_label": "알파", "_master": "alpha-master#1", "_arch": "alpha-arch#1", "_cards": "alpha", "_tree": "alpha/NEWS.md",
    "alpha-master#1": {"role": "master"}, "alpha-nano#0": {"role": "nano", "index": "alpha/진행/c-prog.md"},
    "alpha-dead#0": {"role": "nano", "index": "alpha/진행/c-prog.md"},
    "alpha-old#0": {"role": "nano", "index": "alpha/진행/c-prog.md", "_replaced_by": "alpha-nano#0"}})
seats("beta", {"_label": "베타", "_master": "beta-master#1"})
seats("delta", {"_label": "델타", "_cards": "delta", "_tree": "delta/NEWS.md"})
seats("eps", {"_label": "엡실론", "_cards": "eps"})
seats("planner", {"_label": "플래너", "_master": "plan-master#1"})
for n, t, w in (("A", "완성A", "2026-10-09T08:00:00"), ("B", "완성B", "2026-10-01T08:00:00"), ("old-done", "옛완성", "2026-09-20T08:00:00")):
    card("alpha", "완성", n, t, w)
card("alpha", "대기", "c-wait1", "대기카드1", "2026-10-02T08:00:00"); card("alpha", "대기", "c-wait2", "대기카드2", "2026-10-02T08:00:00")
card("alpha", "진행", "c-prog", "진행카드", "2026-10-08T08:00:00")
card("alpha", "진행", "dupcard", "중복카드", "2026-10-08T08:00:00"); card("alpha", "완성", "dupcard", "중복카드", "2026-10-08T09:00:00")
(R / "alpha" / "NEWS.md").write_text("# 주석\n축 하나\n  [idx:A] 완성A\n  [idx:c-prog] 진행카드\n  [idx:c-wait1] 대기카드1\n  [idx:A] 완성A\n"
    "[✅] 손 상태 축\n  [idx:ghost] 없는카드\n", encoding="utf-8")
card("delta", "완성", "A", "완성A", "2026-10-09T08:00:00"); card("delta", "완성", "B", "완성B", "2026-10-01T08:00:00")
(R / "delta" / "NEWS.md").write_text("축\n  [idx:A] 완성A\n", encoding="utf-8")
card("eps", "완성", "E1", "엡실론완성", "2026-10-03T08:00:00"); card("eps", "완성", "E3", "답장 포함 완성", "2026-10-09T09:30:00"); card("eps", "대기", "qq", "Q3 질문", "2026-10-02T08:00:00"); card("eps", "진행", "E2", "엡실론진행", "2026-10-08T08:00:00")
led = [{"ev": "new", "n": 501, "ts": "2026-10-09T09:00:00", "title": "오늘 새 판정", "teams": ["alpha"], "seq_out": [], "oppa_todo": "오빠 결정 필요"},
       {"ev": "new", "n": 502, "ts": "2026-10-09T09:10:00", "title": "오늘 끝난 판정", "teams": ["delta"], "seq_out": [], "oppa_todo": ""},
       {"ev": "done", "n": 502, "ts": "2026-10-09T09:20:00", "note": ""},
       {"ev": "new", "n": 400, "ts": "2026-10-01T09:00:00", "title": "옛 열린 판정", "teams": ["eps"], "seq_out": [], "oppa_todo": ""}]
(FB / "state" / "verdicts.jsonl").write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in led), encoding="utf-8")
mail = [{"seq": 9001, "ts": "2026-10-09T09:30:00", "to": "alpha-master#1", "from": "x#1", "body": "b"},
        {"seq": 9002, "ts": "2026-10-09T09:40:00", "to": "alpha-master#1", "from": "x#1", "body": "b"}]
(FB / "comm" / "mailbox.jsonl").write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in mail), encoding="utf-8")
PY
printf '#!/bin/sh\necho x >> %s/tmux.calls\ncat %s/alive.txt\n' "$T" "$T" > "$T/tmux.sh"
printf 'alpha-master#1\nalpha-arch#1\nalpha-nano#0\nalpha-old#0\nplan-master#1\n' > "$T/alive.txt"
cat > "$T/status.sh" <<'EOF'
#!/bin/sh
echo '{"state":"WORKING","turn_end":null,"duration_ms":null,"reported":null,"source":"jsonl"}'
EOF
printf '#!/bin/sh\n[ "$1" = "alpha-master#1" ] && echo "[③] g1 seq=9001 미닫힘=9001 from=x#1 원문=p | 첫줄" || echo EMPTY\n' > "$T/inbox.sh"
GH7='[{"number":7,"title":"열린 이슈","labels":[{"name":"hil:needed"}],"updatedAt":"x","state":"%s"},{"number":8,"title":"다른 이슈","labels":[],"updatedAt":"x","state":"OPEN"}]'
printf "$GH7" OPEN > "$T/gh.json"

TERM_OUT="$(board render --term)"; rc=$?; eq "render --term rc" "$rc" 0
SLACK="$(board render --slack)"; eq "render --slack rc" "$?" 0
FULL="$(board render --term --full)"; ENVFULL="$(FT_NEWS_FULL=1 board render --term)"; eq "FT_NEWS_FULL=1 = --full" "$ENVFULL" "$FULL"

# ⓪ 팀 수 = 명부 수 · 열 값 · 결정 자리
eq "⓪ 팀 수 = 명부 수" "$(printf '%s\n' "$TERM_OUT" | grep -c '^- .* | 지금: ')" "$(ls "$FB"/seats*.json | wc -l | tr -d ' ')"
has "⓪ 베타(_cards 없음) = 카드 폴더 미지정" "$TERM_OUT" "- 베타 | 지금: 카드 폴더 미지정"
has "⓪ 알파 진행·큐·오빠 할 일" "$TERM_OUT" "- 알파 | 지금: 진행 1(진행카드 · alpha-nano#0 작업중) | 큐: 대기 2(대기카드1) | 오빠 할 일 1 | 결정 자리: plan-master#1"
# 렌더 순서 ⓪→④
pos() { printf '%s\n' "$TERM_OUT" | grep -n "^$1" | head -1 | cut -d: -f1; }
[ "$(pos ⓪)" -lt "$(pos ①)" ] && [ "$(pos ①)" -lt "$(pos ②)" ] && [ "$(pos ②)" -lt "$(pos ③)" ] && [ "$(pos ③)" -lt "$(pos ④)" ] && ok "렌더 순서 ⓪→④" || bad "렌더 순서"
# 옛 좌석 0
for s in alpha-dead alpha-old; do lacks "옛 좌석 $s 어느 칸에도 없음(term full)" "$FULL" "$s"; lacks "옛 좌석 $s 없음(slack)" "$SLACK" "$s"; done
has "현역 좌석은 보임" "$TERM_OUT" "🔄 진행카드 ← alpha-nano#0 작업중"
# ✅ 소실 0: 오늘 완성 카드 · 오늘 done 판정이 요약 렌더에도 보임
has "세션 트리 오늘 완성(마지막 1개 제목)" "$TERM_OUT" "오늘 완성 1(마지막: 완성A)"
has "오늘 done 판정 표시" "$TERM_OUT" "502 · 오늘 끝난 판정 · done · delta"
lacks "옛 열린 판정은 오늘 판정표가 아님" "$(printf '%s\n' "$TERM_OUT" | sed -n '/^④/,$p')" "옛 열린 판정"
# ① 판정 496 반례 — delta: 완성 A·B · 트리 idx A 만
DELTA="$(printf '%s\n' "$TERM_OUT" | sed -n '/^델타/,/^엡실론/p')"
has "496-① 기본: 축 완성(누적) 1(최근: 완성A)" "$DELTA" "✅ 완성(누적) 1(최근: 완성A)"
has "496-① 기본: 축 미연결 완성(누적) 1(최근: 완성B)" "$(printf '%s\n' "$DELTA" | sed -n '/축 미연결/,$p')" "✅ 완성(누적) 1(최근: 완성B)"
DELTA_F="$(printf '%s\n' "$FULL" | sed -n '/^델타/,/^엡실론/p')"
eq "496-① full: ✅ 줄 A" "$(printf '%s\n' "$DELTA_F" | grep -c '✅ 완성A$')" 1
eq "496-① full: ✅ 줄 B" "$(printf '%s\n' "$DELTA_F" | grep -c '✅ 완성B$')" 1
eq "496-① 기본: ✅ 카드 줄은 접힘" "$(printf '%s\n' "$DELTA" | grep -c '✅ 완성[AB]$')" 0
echo "--- 496 반례(델타) 기본 render --term ---"; printf '%s\n' "$DELTA"; echo "--- 496 반례(델타) --full render --term ---"; printf '%s\n' "$DELTA_F"
# ② 같은 idx 두 축 → 첫 축만 셈 · ③ 폴더 중복 · 손 상태 글자
has "496-② 중복 링크 표시" "$TERM_OUT" "(중복 링크 — 첫 위치: 축 하나)"
has "496-③ 폴더 중복 1장 + 경고" "$TERM_OUT" "⚠폴더 중복(완성,진행)"
has "손 상태 글자 제거 + (카드 미연결)" "$TERM_OUT" "■ 손 상태 축 (카드 미연결)"
lacks "손 상태 글자 [✅] 안 읽음" "$TERM_OUT" "[✅]"
has "T−C = 카드 없음" "$TERM_OUT" "❌ 없는카드 ⚠카드 없음"
# ④ _tree 없는 팀 = 전부 미연결
EPS="$(printf '%s\n' "$TERM_OUT" | sed -n '/^엡실론/,/^플래너/p')"
has "496-④ _tree 없음 표시" "$EPS" "엡실론 — 완성 트리 미지정"
has "496-④ 카드 전부 축 미연결" "$EPS" "■ 축 미연결"
# ⑤ 최근(누적 mtime 최대)과 오늘 완성이 따로
has "496-⑤ 알파 미연결 최근 = mtime 최대" "$TERM_OUT" "✅ 완성(누적) 2(최근: 완성B) · 🔄 진행 0 · ⏳ 대기 1 · ⚠중복 1"
# 불변식: Σ축 + 미연결 = |C 상태| · 전 카드 소실 0(full)
board collect > "$T/dict.json"
python3 - "$T/dict.json" "$FULL" <<'PY' > "$T/inv.txt"; eq "불변식 종료코드" "$?" 0
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8")); full = sys.argv[2]
for t in d["teams"]:
    for st in ("완성", "진행", "대기", "중복"):
        want = sum(1 for s in t["states"].values() if s == st)
        got = sum(ax["counts"][st] for ax in t["axes"])
        assert want == got, (t["key"], st, want, got)
    print(f"INVARIANT {t['key']}: " + " ".join(f"{st} Σ축+미연결={sum(ax['counts'][st] for ax in t['axes'])}/|C|={sum(1 for s in t['states'].values() if s == st)}" for st in ("완성", "진행", "대기", "중복")))
    for ax in t["axes"]:
        for e in ax["entries"]:
            assert e["k"] != "card" or e["text"] in full, (t["key"], e["text"])
PY
cat "$T/inv.txt"; has "불변식 단언(알파)" "$(cat "$T/inv.txt")" "INVARIANT alpha: 완성 Σ축+미연결=3/|C|=3"
# ⑥ collect 1회당 tmux 1 · render 2종은 재조회 0
rm -f "$T/tmux.calls"
python3 - "$BIN" <<'PY'; eq "tmux 호출 수 (collect 1회 = 1, render 2종 뒤 증가 0)" "$(wc -l < "$T/tmux.calls" | tr -d ' ')" 1
import sys; sys.path.insert(0, sys.argv[1])
from ft_board_collect import collect
from ft_board_render import render
d = collect(); render(d, "term"); render(d, "slack"); render(d, "term", True)
PY
# 슬랙: 첫 줄 · 결정 자리 1줄 · 답장 요구 0
eq "슬랙 첫 줄" "$(printf '%s\n' "$SLACK" | head -1)" "[상태] 메인팀 보드 10:00"
eq "슬랙 결정 자리 줄 1개" "$(printf '%s\n' "$SLACK" | grep -c '^결정 자리:')" 1
printf '%s' "$SLACK" | python3 -c 'import re,sys; r=re.compile(r"답해\s*주|답장|회신해\s*주|답을\s*(주|달)|댓글|번호(나|로)?\s*답|이\s*스레드에\s*(답|한\s*줄)|reply|확인해\s*주|(?<![A-Za-z0-9])Q\d+(?!\d)", re.I); sys.exit(1 if r.search(sys.stdin.read()) else 0)'; eq "슬랙 답장 요구 정규식 0" "$?" 0
# 결정 자리: planner 세션 없음 → 확인 불가(대체 이름 0)
printf 'alpha-master#1\nalpha-arch#1\nalpha-nano#0\n' > "$T/alive.txt"
NOPLAN="$(board render --term)"; has "496-⓪ planner 없음 → 확인 불가" "$NOPLAN" "결정 자리: 확인 불가(plan-master#1 tmux 세션 없음)"
lacks "대체 이름 0" "$NOPLAN" "결정 자리: alpha"
printf 'alpha-master#1\nalpha-arch#1\nalpha-nano#0\nalpha-old#0\nplan-master#1\n' > "$T/alive.txt"
# 미보고 n 과 수신 대기 n 이 따로
has "수신 대기 2 · 미보고 1 따로 + 가장 오래된 30분" "$TERM_OUT" "- 알파: 수신 대기 2 · 미보고 1 · 가장 오래된 30분"
has "Issue hil:needed 먼저" "$(printf '%s\n' "$TERM_OUT" | grep -A1 '^열린 Issue')" "- #7 열린 이슈 [hil:needed]"
# 필터 경계 = 슬랙 최종 출력 하나: 걸린 «부분 문자열»만 〔문구 생략〕 (줄·계수·상태 기호 그대로 · raise 0)
has "슬랙: 대기 카드 제목 Q3 → 부분 치환" "$SLACK" "- 엡실론: 〔문구 생략〕 질문"
has "슬랙: 완성 카드 제목 답장 → 축 최근 부분 치환 · 계수 그대로" "$SLACK" "✅ 완성(누적) 2(최근: 〔문구 생략〕 포함 완성)"
printf '%s\n' "$SLACK" | tail -1 | grep -qE '^문구 생략 [0-9]+곳$' && ok "슬랙: 끝 줄 문구 생략 n곳" || bad "슬랙 끝 줄"
lacks "슬랙: 원문 Q3 제목 없음" "$SLACK" "Q3 질문"; lacks "슬랙: 원문 답장 제목 없음" "$SLACK" "답장 포함"
has "term: 원문 Q3 제목 그대로" "$TERM_OUT" "Q3 질문"; has "term: 원문 답장 제목 그대로" "$TERM_OUT" "답장 포함 완성"
lacks "term 에는 생략 표시 0" "$TERM_OUT" "문구 생략"
python3 - "$BIN" <<'PY'; eq "필드 전부(결정 자리·좌석·팀·Issue·oppa_todo·라벨) 금지어 → rc 0 · REPLY_ASK 0 · 끝 줄 n곳" "$?" 0
import re, sys; sys.path.insert(0, sys.argv[1])
from ft_board_collect import collect
from ft_board_render import REPLY_ASK, render
# 결정 자리 사유 단독 — DA 재현 입력: 치환 1곳
out = render({"teams": [], "issues": [], "verdicts": [], "decision": "확인 불가(byz-planner-Q3 tmux 세션 없음)"}, "slack")
assert "Q3" not in out and out.count("〔문구 생략〕") == 1 and out.splitlines()[-1] == "문구 생략 1곳", out
assert not REPLY_ASK.search(out)
# 입력 문자열이 닿는 모든 칸에 금지어 주입
d = collect()
d["decision"] = "확인 불가(reply-planner tmux 세션 없음)"
alpha = next(t for t in d["teams"] if t["key"] == "alpha")
alpha["leads"][0]["name"] = "byz-답장-master#1"; alpha["label"] = "Q9팀"; alpha["oppa_todo"] = [501]
next(v for v in d["verdicts"] if v["n"] == 501).update(teams=["reply-team"], oppa_todo="답을 주세요 Q7", title="확인해 주세요")
d["issues"][0]["title"] = "reply 이슈"
alpha["progress"]["c-prog"]["seats"][0]["name"] = "reply-cleanup"
out = render(d, "slack")
assert not REPLY_ASK.search(out), [l for l in out.splitlines() if REPLY_ASK.search(l)]
assert re.fullmatch(r"문구 생략 \d+곳", out.splitlines()[-1]) and "- #7 〔문구 생략〕 이슈 [hil:needed]" in out, out
assert "- 판정 501 · 〔문구 생략〕세요 → 〔문구 생략〕세요 〔문구 생략〕" in out and "reply-cleanup" not in out
assert render(d, "term").count("Q9팀") >= 1  # term 은 원문
PY
# 설정된 파일이 없으면 raise
mv "$FT_ROOT/delta/NEWS.md" "$T/NEWS.bak"; board render --term >/dev/null 2>"$T/e.err"; rc=$?
[ "$rc" -ne 0 ] && has "_tree 파일 없음 = raise" "$(cat "$T/e.err")" "_tree 파일 없음" || bad "_tree 없음이 통과"; mv "$T/NEWS.bak" "$FT_ROOT/delta/NEWS.md"

# snapshot: 1회 → 카드 1장 진행→완성 → 2회
S1="$(board snapshot)"; eq "snapshot 1 rc" "$?" 0; eq "첫 스냅샷 changes 빈 배열" "$(printf '%s' "$S1" | jq -c .changes)" "[]"
H1="$(printf '%s' "$S1" | jq -r '.snap | split("→")[1]')"; ls "$FB/state/board/2026-10-09/" | grep -q "^100000-$H1.json$" && ok "스냅샷 파일명 HHMMSS-hash8" || bad "스냅샷 파일명"
mv "$FT_ROOT/alpha/진행/c-prog.md" "$FT_ROOT/alpha/완성/c-prog.md"
S2="$(FT_BOARD_NOW=2026-10-09T10:05:00 board snapshot)"; eq "snapshot 2 rc" "$?" 0
echo "SNAPSHOT-2 $S2"
eq "카드만 바뀐 changes 1건" "$(printf '%s' "$S2" | jq -c .changes)" '["카드 alpha/c-prog 진행→완성"]'
H2="$(printf '%s' "$S2" | jq -r '.snap | split("→")[1]')"; eq "snap 전→후 id" "$(printf '%s' "$S2" | jq -r .snap)" "${H1}→${H2}"
eq "판정 변화 0 인데 changes 비지 않음" "$(printf '%s' "$S2" | jq '[.changes[]|select(startswith("판정"))]|length')" 0
# Issue 만 open→closed
printf "$GH7" CLOSED > "$T/gh.json"
S3="$(FT_BOARD_NOW=2026-10-09T10:10:00 board snapshot)"; eq "Issue 만 바뀜 changes 1건" "$(printf '%s' "$S3" | jq -c .changes)" '["Issue #7 open→closed"]'
# 같은 입력 2회 → 둘 다 rc 0 · changes 빈 배열 · 같은 hash8
S4="$(FT_BOARD_NOW=2026-10-09T10:15:00 board snapshot)"; r4=$?; S5="$(FT_BOARD_NOW=2026-10-09T10:16:00 board snapshot)"; r5=$?
eq "같은 입력 rc" "$r4$r5" 00; eq "같은 입력 changes 빈 배열" "$(printf '%s' "$S5" | jq -c .changes)" "[]"
eq "같은 입력 같은 hash8" "$(printf '%s' "$S4" | jq -r '.snap|split("→")[1]')" "$(printf '%s' "$S5" | jq -r '.snap|split("→")[1]')"
# 쓰기 불가 → rc≠0 · stdout 빈 값
chmod 500 "$FB/state/board/2026-10-09"
OUT="$(FT_BOARD_NOW=2026-10-09T10:30:00 board snapshot 2>"$T/w.err")"; rc=$?
[ "$rc" -ne 0 ] && [ -z "$OUT" ] && ok "쓰기 불가 rc≠0 · stdout 빈 값" || bad "쓰기 불가 (rc=$rc out='$OUT')"
chmod 700 "$FB/state/board/2026-10-09"
# 날짜 바뀜 → prev_day_last
LAST="$(ls "$FB/state/board/2026-10-09" | sort | tail -1 | sed 's/^[0-9]*-//; s/\.json$//')"
S6="$(FT_BOARD_NOW=2026-10-10T09:00:00 board snapshot)"; eq "날짜 바뀜 prev_day_last" "$(printf '%s' "$S6" | jq -r .prev_day_last)" "$LAST"
# prune
eq "prune 30일 안 = 삭제 0" "$(FT_BOARD_NOW=2026-10-10T09:00:00 board prune --days 30)" "[]"
eq "prune 0일 = 전날 폴더 삭제" "$(FT_BOARD_NOW=2026-10-10T09:00:00 board prune --days 0)" '["2026-10-09"]'
# 카드 제목 = 첫 5줄 안 첫 H1 (R52) — zeta 팀 대기 카드 5종(id 순서 = 큐 순서)
mkdir -p "$FT_ROOT/zeta/대기"
printf '<!-- ledger: design/zeta/GOAL-zeta.md -->\n# 인덱스: 진짜 제목\n본문\n' > "$FT_ROOT/zeta/대기/z1-comment-first.md"
printf '\n<!-- ledger: x -->\n# 제목\n본문\n' > "$FT_ROOT/zeta/대기/z2-blank-comment.md"
printf '## 골 원문 절\n본문\n# 인덱스: X\n' > "$FT_ROOT/zeta/대기/z3-section-first.md"
printf '본문만\n## 절\n<!-- c -->\n\n끝\n' > "$FT_ROOT/zeta/대기/z4-no-h1.md"
printf '# 인덱스: 기존 형식\n본문\n' > "$FT_ROOT/zeta/대기/z5-legacy.md"
printf '{"_label":"제타","_cards":"zeta"}' > "$FB/seats-zeta.json"
ZETA="$(board collect | jq -r '.teams[]|select(.key=="zeta")|.queue[]|"\(.idx)\t\(.title)"')"
echo "--- 시험 ①~④ 픽스처 렌더 제목 ---"; printf '%s\n' "$ZETA" | head -4
eq "제목 ① 주석 첫 줄 → 둘째 줄 H1" "$(printf '%s\n' "$ZETA" | sed -n 1p)" "$(printf 'z1-comment-first\t진짜 제목')"
eq "제목 ② 빈 줄+주석 → H1" "$(printf '%s\n' "$ZETA" | sed -n 2p)" "$(printf 'z2-blank-comment\t제목')"
eq "제목 ③ ## 절 건너뛰고 H1" "$(printf '%s\n' "$ZETA" | sed -n 3p)" "$(printf 'z3-section-first\tX')"
eq "제목 ④ 첫 5줄 H1 없음 → (제목 없음)" "$(printf '%s\n' "$ZETA" | sed -n 4p)" "$(printf 'z4-no-h1\tz4-no-h1 (제목 없음)')"
eq "제목 ⑤ 기존 첫 줄 형식 그대로" "$(printf '%s\n' "$ZETA" | sed -n 5p)" "$(printf 'z5-legacy\t기존 형식')"
lacks "제목 ⑥ 슬랙 렌더에 <!-- 0" "$(board render --slack)" "<!--"
lacks "제목 ⑥ term full 렌더에 <!-- 0" "$(board render --term --full)" "<!--"
rm -rf "$FT_ROOT/zeta" "$FB/seats-zeta.json"
# 팀 추가 = 명부 파일 1개 (코드 0)
printf '{"_label":"감마"}' > "$FB/seats-gamma.json"
has "팀 추가 = 명부 1개만으로 나타남" "$(board render --term)" "- 감마 | 지금: 카드 폴더 미지정"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
