#!/usr/bin/env bash
# test_nano_record_seats_cache_r2129.sh — r2129 명부 실행당 캐시(Ctx.seats): 사례 ①②④⑤ + ③ 해당 없음 근거 + 짝 사본·줄 수 + 변이 M1·M2(변이마다 원본 대조) + 기준판 ① Red.
#   세계 = _nano_record_r1717_fixture.sh + 카드 20장(ROOT 10 · 외부 리포 EXT 10 · 같은 카드 ref) + 명부 10개(seats-harness · seats-t1~t9) + 합성 장부 500줄
#   명부 읽기 셈 = 시험 감싸개가 pathlib.Path.read_text 를 감싸 seats*.json 실제 경로를 기록(제품에 시험 전용 문 0) · 판 수 = 장부 읽기 횟수 - 1
#   실 장부·실 명부·실 우편함·실 tmux·네트워크 0 · sleep 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
BASE_SHA=30b81a49cdd42d67b5c1ca088d61fef5022a7013   # 기준판 = 이 카드 전 팩 origin/main
EXT="$T/ext"; RLOG="$T/reads.log"; NFILE=11   # 명부 실제 경로 수 = ROOT 10 + EXT 1
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
roster() {  # roster <파일> <팀장> ["<좌석>|nano|<stem>"…] — ROOT 의 다른 팀 명부 1개(카드 루트 = harness) · 살아 있는 세션에 좌석 더함
  local f="$1"; shift
  python3 - "$ROOT/.fable-team/$f" "$IDX" "$@" <<'PY'
import json, sys
p, idx, m, rows = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
d = {"_master": m, "_cards": idx, m: {"role": "master"}}
for r in rows:
    s, role, stem = r.split("|")
    d[s] = {"role": role, "agent": "pi", "index": f".worktrees/ops/{idx}/진행/{stem}.md"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
  local r; for r in "$@"; do case "$r" in *"|"*) printf '%s\n' "${r%%|*}" >> "$FAKE_SESS";; esac; done
}
build() {  # 합성 세계 1회(사례는 읽기만 · notify 사례는 상태를 되돌린다)
  fresh; land 7; local i j
  for i in $(seq 1 20); do cardf "k$i"; done; cpush
  git clone -q "$CREM" "$EXT" 2>/dev/null; mkdir -p "$EXT/.fable-team/state"; cp "$STATE/directive-roots.tsv" "$EXT/.fable-team/state/"
  seats "$(NN k1)|nano|k1" "$(NN k2)|nano|k2" "$(NN k11)|nano|k11"
  for j in 1 2 3 4 6 7 8 9; do roster "seats-t$j.json" "byz-t$j-master-pi#1"; done
  roster seats-t5.json "byz-t5-master-pi#1" "byz-t5-nano-k5#0|nano|k5" "byz-t5-nano-k15#0|nano|k15"
  cp "$ROOT/.fable-team/seats-harness.json" "$EXT/.fable-team/"
  python3 - "$STATE/land-record-turn.jsonl" "$PACK" "$Q" "$PH" "$ROOT/$IDX/진행" "$EXT/$IDX/진행" <<'PY'
import json, sys
p, repo, q, ph, rd, ed = sys.argv[1:7]
with open(p, "w", encoding="utf-8") as f:
    for n in range(500):
        k = n % 20 + 1
        card = f"{rd if k <= 10 else ed}/k{k}.md"
        f.write(json.dumps({"pr": 1000 + n, "repo": repo, "target": "main", "landed": q, "pr_head": ph, "by": "", "cards": [card], "ts": "t"}, ensure_ascii=False) + "\n")
PY
  cp -R "$ROOT/.fable-team" "$T/snap"
}
restore() {  # restore [<장부 앞 줄 수>] — 명부·장부·보낸 기록·우편함 seq 를 build 직후로
  rm -rf "$ROOT/.fable-team"; cp -R "$T/snap" "$ROOT/.fable-team"; : > "$MBOX_LOG"; : > "$TMUX_LOG"
  [ -z "${1:-}" ] || { head -n "$1" "$T/snap/state/land-record-turn.jsonl" > "$STATE/land-record-turn.jsonl"; }
}
WRAP='import os, pathlib, runpy, sys
b, log = sys.argv[1], sys.argv[2]
orig = pathlib.Path.read_text
def rt(self, *a, **k):
    if (self.name.startswith("seats") and self.name.endswith(".json")) or self.name == "land-record-turn.jsonl":
        with open(log, "a", encoding="utf-8") as f:
            f.write(os.path.realpath(self) + "\n")
    return orig(self, *a, **k)
pathlib.Path.read_text = rt
sys.path.insert(0, b)
if sys.argv[3] == "py":
    exec(sys.argv[4])
else:
    m = "ft_nano_record_notify.py" if sys.argv[3] == "notify" else "ft_nano_record_due.py"
    sys.argv = [f"{b}/{m}"] + sys.argv[3:]
    runpy.run_path(sys.argv[0], run_name="__main__")'
cnt() { : > "$RLOG"; OUT="$(cd "$T" && python3 -c "$WRAP" "$1" "$RLOG" "${@:2}" 2>&1)"; RC=$?; }   # cnt <bin> due|notify|py … → OUT·RC · RLOG = 읽은 실제 경로
nseat() { grep -c '/seats[^/]*\.json$' "$RLOG" || true; }   # 명부 읽기 총수
maxseat() { grep '/seats[^/]*\.json$' "$RLOG" | sort | uniq -c | sort -rn | awk 'NR==1{print $1+0;f=1} END{if(!f)print 0}'; }   # 한 파일 최다 읽기
npass() { echo $(( $(grep -c '/land-record-turn\.jsonl$' "$RLOG" || true) - 1 )); }   # due 판 수
c1() {  # ① 500줄 · 명부 10개 · 외부 리포 카드 → 실제 경로마다 1회(--no-fetch 1판 · fetch 2판 · sub Ctx 공유)
  cnt "$BIN" due --no-fetch; t "① rc 0|3" inc " 0 3 " " $RC "; t "① 외부 리포 명부 읽음(sub Ctx)" inc "$(cat "$RLOG")" "$EXT/.fable-team/seats-harness.json"
  t "① --no-fetch 파일마다 ≤1회 (최다=$(maxseat))" [ "$(maxseat)" -le 1 ]; t "① --no-fetch 총 ≤$NFILE (총=$(nseat))" [ "$(nseat)" -le "$NFILE" ]
  cnt "$BIN" due; t "① fetch 판 2개 (판=$(npass))" [ "$(npass)" = 2 ]
  t "① 두 판 파일마다 ≤1회 (최다=$(maxseat))" [ "$(maxseat)" -le 1 ]; t "① 두 판 총 ≤$NFILE (총=$(nseat))" [ "$(nseat)" -le "$NFILE" ]
  return $E
}
c2() {  # ② 깨진 명부 seats-bad.json → 건너뜀 1줄 · 그 파일 읽기 1회 · 다른 판정 그대로 · ②-b FT_SEATS_JSON = 깨진 파일 · 팀 둘 → 오류 글 팀마다 원문 · 읽기 1회
  local o0 bad="$ROOT/.fable-team/seats-bad.json"; cnt "$BIN" due --no-fetch; o0="$OUT"
  printf '{bad' > "$bad"; cnt "$BIN" due --no-fetch; rm -f "$bad"
  t "② 건너뜀 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '^명부 seats-bad.json 판정 불가 — 건너뜀$')" = 1 ]
  t "② 깨진 파일 읽기 1회" [ "$(grep -c '/seats-bad\.json$' "$RLOG")" = 1 ]
  t "② 다른 판정 그대로" [ "$(printf '%s\n' "$OUT" | grep -v '^명부 seats-bad.json 판정 불가')" = "$o0" ]
  printf '{bad' > "$T/seats-envbad.json"
  FT_SEATS_JSON="$T/seats-envbad.json" cnt "$BIN" py 'from ft_nano_record import Ctx, Unjudged
c = Ctx()
for team in ("harness", "planner", "harness"):
    try:
        c.seats(team)
    except Unjudged as u:
        print(u)'
  t "②-b 오류 글 팀마다 원문" [ "$OUT" = "$(printf '명부 읽기(harness) rc=1\n명부 읽기(planner) rc=1\n명부 읽기(harness) rc=1')" ]
  t "②-b 파일 읽기 1회" [ "$(grep -c '/seats-envbad\.json$' "$RLOG")" = 1 ]
  return $E
}
c4() {  # ④ ①·② 입력 due --no-fetch 출력·rc = 기준판과 바이트 같음
  local o r a bad="$ROOT/.fable-team/seats-bad.json"
  for a in --no-fetch; do
    cnt "$BASEBIN" due $a; o="$OUT"; r="$RC"; cnt "$BIN" due $a; t "④ ① due ${a:-fetch} 같음" [ "$OUT/$RC" = "$o/$r" ]
    printf '{bad' > "$bad"; cnt "$BASEBIN" due $a; o="$OUT"; r="$RC"; cnt "$BIN" due $a; rm -f "$bad"; t "④ ② due ${a:-fetch} 같음" [ "$OUT/$RC" = "$o/$r" ]
  done
  return $E
}
c5() {  # ⑤ notify(가짜 mbox · 가짜 tmux · 장부 앞 60줄 = 시험 시간 상한) → 출력·rc·보낸 쪽지(seq·받는 이·보낸 이·본문 · 본문의 bin 경로만 맞춤) = 기준판과 같음
  local o r m; restore 60; cnt "$BASEBIN" notify --no-fetch; o="$OUT"; r="$RC"; m="$(cat "$MBOX_LOG")"; m="${m//$BASEBIN/$BIN}"
  restore 60; cnt "$BIN" notify --no-fetch; t "⑤ 쪽지 1통 이상 (수=$(grep -c . "$MBOX_LOG"))" [ "$(grep -c . "$MBOX_LOG")" -ge 1 ]
  t "⑤ 보낸 쪽지 같음" [ "$(cat "$MBOX_LOG")" = "$m" ]; t "⑤ 출력·rc 같음" [ "$OUT/$RC" = "$o/$r" ]; restore
  return $E
}
step "사전: 문법 · 짝 사본 · 줄 수 · ③ 해당 없음 근거"
for f in ft_nano_record.py ft_nano_record_repo.py; do
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
  [ "$(wc -l < "$SRC/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음 $f"
done
# ③ N2 해당 없음 — landed·settle·done·refused 길에 명부 파일 쓰기 0(쓰기 = write_atomic·open(w)·write_text 의 대상에 seats 0)
grep -nE '(write_atomic|write_text|open\().*seats' "$SRC"/ft_nano_record*.py >/dev/null && bad "③ 명부 쓰기 길 있음 — N2 다시 볼 것" || ok "③ 명부 쓰기 길 0 (N2 해당 없음)"
world
BASEBIN="$T/base/bin"; mkdir -p "$T/base"
git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$T/base" 2>/dev/null && [ -f "$BASEBIN/ft-nano-record.sh" ] || { bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; BASEBIN=""; }
step "세계: 카드 20 · 명부 10 · 장부 500줄"
build
step "사례 ①②"
run "① 명부 실제 경로마다 1회" c1; run "② 깨진 명부 1회 · 오류 글 원문" c2
if [ -n "$BASEBIN" ]; then
  step "사례 ④⑤ (기준판 대조)"; run "④ due 출력·rc 기준판과 같음" c4; run "⑤ notify 쪽지 기준판과 같음" c5
fi
step "변이 M1~M2 (+원본 대조)"
mutbin m1 ft_nano_record.py 'if p in self._seats else' 'if False else'; mutcase M1 c1 1
mutbin m2 ft_nano_record.py 'self._seats.setdefault(p, d)' '(d if d is Unjudged else self._seats.setdefault(p, d))'; mutcase M2 c2 2
step "기준판 ① Red (팩 $BASE_SHA)"
if [ -n "$BASEBIN" ]; then
  ( BIN="$BASEBIN"; TOOL="$BIN/ft-nano-record.sh"; c1 base ) > "$T/red.out" 2>&1 && bad "기준판에서 ① 통과함" || ok "기준판 ① FAIL(기대 Red) ::$(grep -m3 '^  x ' "$T/red.out" | sed 's/ :: .*//' | tr '\n' ' ')"
fi
finish
