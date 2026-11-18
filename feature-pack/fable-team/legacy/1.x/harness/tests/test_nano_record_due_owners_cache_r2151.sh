#!/usr/bin/env bash
# test_nano_record_due_owners_cache_r2151.sh — r2151 due 실행당 캐시 3개: 사례 ①~⑤ · ⑦ + 변이 M1~M4(변이마다 원본 대조) + 기준판 ①②③ Red · ⑦ Green.
#   세계 = _nano_record_r1717_fixture.sh + 카드 20장(ROOT 10 · 외부 리포 EXT 10) + 명부 10개(seats-harness · seats-t1~t9) + 합성 장부 500줄
#   전달 기록 seq 있는 줄 50(k1 #41 = 버림 아님 · k2 #42 = 버림) · 합성 mailbox.drops.log 1개 · 카드 팀 명부 차례 0 인 카드 줄 = 425
#   셈 = 시험 감싸개(제품에 시험 전용 문 0): Ctx.seats 가 돌려준 명부를 items() 를 세는 dict 로 바꿔 줌(나노 목록 만들기)
#        · Path.read_text 중 mailbox.drops.log(버림 원장 읽기) · Path.glob("seats*.json")(명부 파일 목록)
#   실 장부·실 명부·실 우편함·실 tmux·네트워크 0 · sleep 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
BASE_SHA=38cd147635a44dfd278fdbf6a746f3241268b396   # 기준판 = 이 카드 전 팩 origin/main
EXT="$T/ext"; CLOG="$T/count.log"; NDOC=11   # 명부 doc 수 = ROOT 10 + EXT 1
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
roster() {  # roster <파일> <팀장> ["<좌석>|nano|<stem>"…] — ROOT 의 다른 팀 명부 1개 · 살아 있는 세션에 좌석 더함
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
closeset() {  # closeset <stem> <seq|-> — 전달 기록 1칸(rec = 카드 ref 판 지문 · - = seq 칸 없음)
  local rec; rec="$(PYTHONPATH="$BIN" python3 -c 'import sys
from ft_nano_record import marks, rec_of, section
lines, st, en = section(sys.argv[1])
print(rec_of(marks(lines[st + 1:en], sys.argv[2], sys.argv[3])))' "$(ctext "$1")" "$(NN "$1")" "$Q")"
  storeset close "$(NN "$1")|$1|$Q" "{\"rec\": \"$rec\"${2:+$([ "$2" = - ] || printf ', "seq": %s' "$2")}, \"result\": \"x\", \"pr\": 1000}"
}
build() {  # 합성 세계 1회(사례는 읽기만 · 상태를 바꾸는 사례는 restore)
  fresh; land 7; local i j
  for i in 1 2; do cardf "k$i" "$(setl)" "$(landl 7)" "$(donel "$(NN "k$i")")"; done
  for i in $(seq 3 20); do cardf "k$i"; done; cpush
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
  closeset k1 41; closeset k2 42
  echo "2026-11-17T00:00:00 to=$MASTER dropped=2 oldest_seq=7 seqs=7,42" > "$COMM/mailbox.drops.log"
  mkdir -p "$STATE/seat-record"; echo "# 세션 기록" > "$STATE/seat-record/$(NN k2).md"
  cp -R "$ROOT/.fable-team" "$T/snap"
}
restore() { rm -rf "$ROOT/.fable-team"; cp -R "$T/snap" "$ROOT/.fable-team"; : > "$MBOX_LOG"; : > "$TMUX_LOG"; }
WRAP='import atexit, pathlib, runpy, sys
b, log = sys.argv[1], sys.argv[2]
n = {"items": 0, "drops": 0, "glob": 0}
atexit.register(lambda: open(log, "w").write("".join(f"{k} {v}\n" for k, v in n.items())))
rt, gl = pathlib.Path.read_text, pathlib.Path.glob
def read_text(self, *a, **k):
    n["drops"] += self.name == "mailbox.drops.log"
    return rt(self, *a, **k)
def glob(self, pat, *a, **k):
    n["glob"] += pat == "seats*.json"
    return gl(self, pat, *a, **k)
pathlib.Path.read_text, pathlib.Path.glob = read_text, glob
sys.path.insert(0, b)
import ft_nano_record as R
class CD(dict):
    def items(self):
        n["items"] += 1
        return super().items()
memo, seats = {}, R.Ctx.seats
def counted(self, team):
    d = seats(self, team)
    if id(d) not in memo:
        memo[id(d)] = (d, CD(d))
    return memo[id(d)][1]
R.Ctx.seats = counted
m = "ft_nano_record_notify.py" if sys.argv[3] == "notify" else "ft_nano_record_due.py"
sys.argv = [f"{b}/{m}"] + sys.argv[3:]
runpy.run_path(sys.argv[0], run_name="__main__")'
cnt() { : > "$CLOG"; OUT="$(cd "$T" && python3 -c "$WRAP" "$1" "$CLOG" "${@:2}" 2>&1)"; RC=$?; }   # cnt <bin> due|notify … → OUT·RC · CLOG = 셈
nof() { awk -v k="$1" '$1 == k {print $2+0; f=1} END {if (!f) print -1}' "$CLOG"; }   # nof items|drops|glob
nrow() { printf '%s\n' "$OUT" | grep -c -- "$1" || true; }
c1() {  # ① 500줄 · 명부 10개 → nanos 만들기 = 명부 doc 수 이하
  cnt "$BIN" due --no-fetch; t "① rc 0|3" inc " 0 3 " " $RC "; t "① nanos 만들기 ≤$NDOC (셈=$(nof items))" [ "$(nof items)" -ge 0 -a "$(nof items)" -le "$NDOC" ]
  return $E
}
c2() {  # ② seq 있는 줄 50 · drops.log 1개 → 원장 읽기 = due_rows 1회당 1회
  cnt "$BIN" due --no-fetch; t "② 닫기 요청 #41 줄 25" [ "$(nrow '닫기 요청 #41')" = 25 ]; t "② 밀림 줄 25" [ "$(nrow '닫기 요청 밀림')" = 25 ]
  t "② 원장 읽기 1 (셈=$(nof drops))" [ "$(nof drops)" = 1 ]
  return $E
}
c3() {  # ③ 카드 팀 명부 차례 0 인 카드 줄 425 → seats*.json glob = Ctx 마다 1회(ROOT + EXT sub)
  cnt "$BIN" due --no-fetch; t "③ 다른 명부 차례 줄 있음" inc "$OUT" "차례 명부 seats-t5.json 카드=k5"
  t "③ glob 1~2 (셈=$(nof glob))" [ "$(nof glob)" -ge 1 -a "$(nof glob)" -le 2 ]
  return $E
}
c4() {  # ④ ①~③ 입력 + r2129 ④ 입력(깨진 명부) → due --no-fetch 출력·rc = 기준판과 바이트 같음
  local bad="$ROOT/.fable-team/seats-bad.json"
  cnt "$BIN" due --no-fetch; t "④ 세계 출력·rc 같음" [ "$OUT/$RC" = "$(cat "$T/base.o1")" ]
  printf '{bad' > "$bad"; cnt "$BIN" due --no-fetch; rm -f "$bad"; t "④ 깨진 명부 출력·rc 같음" [ "$OUT/$RC" = "$(cat "$T/base.o2")" ]
  return $E
}
c5() {  # ⑤ drops.log UTF-8 아님 = 같은 판정 불가 줄 · 없음 = 버림 아님 · seq 없음 = 원장 읽기 0
  local o d="$COMM/mailbox.drops.log"
  printf 'x seqs=42\n\377\376\n' > "$d"; cnt "$BASEBIN" due --no-fetch; o="$OUT/$RC"; cnt "$BIN" due --no-fetch
  t "⑤ UTF-8 아님 = 판정 불가 줄 50(k1·k2)" [ "$(nrow '우편함 버림 원장 읽기 rc=1 — UnicodeDecodeError')" = 50 ]; t "⑤ UTF-8 아님 출력·rc 기준판과 같음" [ "$OUT/$RC" = "$o" ]
  t "⑤ UTF-8 아님 = 원장 읽기 1 (셈=$(nof drops))" [ "$(nof drops)" = 1 ]
  rm -f "$d"; cnt "$BASEBIN" due --no-fetch; o="$OUT/$RC"; cnt "$BIN" due --no-fetch
  t "⑤ 원장 없음 = 버림 아님(#42 끝 25)" [ "$(nrow '닫기 요청 #42')" = 25 ]; t "⑤ 원장 없음 출력·rc 기준판과 같음" [ "$OUT/$RC" = "$o" ]
  t "⑤ 원장 없음 = 읽기 시도 1 (셈=$(nof drops))" [ "$(nof drops)" = 1 ]
  restore; closeset k1 -; closeset k2 -; cnt "$BIN" due --no-fetch; t "⑤ seq 없음 = 원장 읽기 0 (셈=$(nof drops))" [ "$(nof drops)" = 0 ]
  restore; return $E
}
c7() {  # ⑦ notify 중 갱신 — 같은 rec·같은 key 행 2개(둘 다 밀림) · 발신 대역이 새 seq 를 버림 원장에 적음 → 두 번째 close_request 가 최신 원장으로 재발신 = 발신 2
  restore; python3 - "$T/snap/state/land-record-turn.jsonl" "$STATE/land-record-turn.jsonl" <<'PY'
import sys
rows = [l for l in open(sys.argv[1], encoding="utf-8") if '/k2.md"' in l][:2]
open(sys.argv[2], "w", encoding="utf-8").write("".join(rows))
PY
  FT_MBOX="$T/mbox-trim.sh" cnt "$BIN" notify --no-fetch
  t "⑦ 밀림 2행 재발신 INFO 2" [ "$(nrow '우편함에서 버려짐 → 다시 보냄')" = 2 ]
  t "⑦ 닫기 요청 발신 2 (수=$(nsent '\[완료·닫기 요청\] k2'))" [ "$(nsent '\[완료·닫기 요청\] k2')" = 2 ]
  restore; return $E
}
cat > "$T/mbox-trim.sh" <<'EOF'
#!/usr/bin/env bash
# 발신 대역 — 가짜 우편함으로 보낸 뒤 큐 상한 trim 꼴로 그 seq 를 버림 원장에 적는다(log_drop 꼴)
o="$(bash "$FK/mbox.sh" "$@")"; rc=$?; printf '%s\n' "$o"
n="$(printf '%s' "$o" | sed -n 's/.*seq=\([0-9][0-9]*\).*/\1/p')"
[ -z "$n" ] || echo "2026-11-17T00:00:01 to=$2 dropped=1 oldest_seq=$n seqs=$n" >> "$MBOX_DIR/mailbox.drops.log"
exit "$rc"
EOF
export FK
step "사전: 문법 · 짝 사본 · 줄 수"
for f in ft_nano_record.py ft_nano_record_due.py ft_nano_record_repo.py ft_nano_record_notify.py; do
  python3 -m py_compile "$SRC/$f" 2>/dev/null && ok "문법 $f" || bad "문법 $f"
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
  [ "$(wc -l < "$SRC/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음 $f"
done
world
BASEBIN="$T/base/bin"; mkdir -p "$T/base"
git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$T/base" 2>/dev/null && [ -f "$BASEBIN/ft-nano-record.sh" ] || { bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; BASEBIN=""; }
step "세계: 카드 20 · 명부 10 · 장부 500줄 · seq 줄 50 · drops.log 1"
build
if [ -n "$BASEBIN" ]; then
  cnt "$BASEBIN" due --no-fetch; printf '%s' "$OUT/$RC" > "$T/base.o1"
  printf '{bad' > "$ROOT/.fable-team/seats-bad.json"; cnt "$BASEBIN" due --no-fetch; rm -f "$ROOT/.fable-team/seats-bad.json"; printf '%s' "$OUT/$RC" > "$T/base.o2"
fi
step "사례 ①②③⑦"
run "① nanos 만들기 doc 마다 1회" c1; run "② 버림 원장 due_rows 당 1회" c2; run "③ 명부 파일 목록 Ctx 마다 1회" c3; run "⑦ notify 중 원장 갱신 = 재발신 2" c7
if [ -n "$BASEBIN" ]; then
  step "사례 ④⑤ (기준판 대조)"; run "④ due 출력·rc 기준판과 같음" c4; run "⑤ 원장 꼴 3가지 기준판과 같음" c5
fi
step "변이 M1~M4 (+원본 대조)"
mutbin m1 ft_nano_record_repo.py 'if k not in memo:   # r2151-mut:memo' 'if True:'; mutcase M1 c1 1
mutbin m2 ft_nano_record_repo.py 'snap = shared(ctx).get("drops")   # r2151-mut:snap' 'snap = None'; mutcase M2 c2 2
if [ -n "$BASEBIN" ]; then mutbin m3 ft_nano_record_repo.py ', id(doc)   # r2151-mut:key' ', 0'; mutcase M3 c4 3; fi
mutbin m4 ft_nano_record_repo.py 'shared(ctx).pop("drops", None)   # r2151-mut:scope' 'pass' \
  ft_nano_record_notify.py 'if not seq_dropped(ctx, had.get("seq")):' 'if not __import__("ft_nano_record_repo").dropped(ctx, had.get("seq")):'; mutcase M4 c7 4
step "기준판 ①②③ Red · ⑦ Green (팩 ${BASE_SHA:0:10})"
if [ -n "$BASEBIN" ]; then
  for c in c1 c2 c3; do
    ( BIN="$BASEBIN"; TOOL="$BIN/ft-nano-record.sh"; $c base ) > "$T/red.out" 2>&1 && bad "기준판에서 $c 통과함" || ok "기준판 $c FAIL(기대 Red) ::$(grep -m3 '^  x ' "$T/red.out" | sed 's/ :: .*//' | tr '\n' ' ')"
  done
  ( BIN="$BASEBIN"; TOOL="$BIN/ft-nano-record.sh"; c7 base ) > "$T/green.out" 2>&1 && ok "기준판 ⑦ 통과(기대 Green · 발신 2)" || bad "기준판 ⑦ FAIL" "$(cat "$T/green.out")"
fi
finish
