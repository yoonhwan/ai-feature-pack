#!/usr/bin/env bash
# ft-autonomy-allow-line.sh — r1870: launchd LLM 허용 장부 «한 줄 허용»(r1867 4칸)·기준선 동적 지점 근거 칸을 오빠 질문 없이 쓴다 — ft-autonomy.sh 가 source(단독 실행 금지)
#   allow-line <라벨> <상대경로> <줄번호> --kind allow|baseline --root-dir <폴더> --da <seq> --card <카드 stem>   좌석이 부른다(오빠 `!` 아님)
#   조건(하나라도 거짓 = `REJECT allow-line <사유>` rc2 · 쓰기 0 · 잠금 안): 자율 ON · 활성 범위(scope_load · A = 지금 사건 · until > 지금 · 정지 아님)
#     · 라벨 = 뿌리 표 키(@shim 제외) · allow = 그 줄이 «tmux 로 pi 띄우기» 꼴 · baseline = list-dyncalls 그 줄 행 정확히 1개(결합 sha ≠ -) · 둘 다 LLM 낱말·NET·MODEL·SDK 0
#     · DA 기계 승인 = mailbox.log.jsonl seq 행 1개 ∧ from 역할 마디 da ∧ `ALLOW-RECORD verdict=APPROVE …` 줄 1개 ∧ 인자·지금 바이트(sha16·comb) 일치 ∧ 같은 키 마지막 레코드
#   쓰기 = 원장(autonomy.log) 1행 먼저 → 장부 1줄(allow = launchd-llm-allow.tsv 4칸 · baseline = launchd-dyncall-baseline.tsv 4칸 · 교체 = old 명시 레코드만 그 행 원자 교체)
#   같은 값 이미 있음 = ALREADY rc0 쓰기 0 · 원장 뒤 장부 실패 = «판정 불가» rc3(판정기는 그대로 REJECT) · 되돌림 = 장부 그 줄 삭제(사람 h) · 해제 동사 0
al_rej() { echo "REJECT allow-line $1" >&2; exit 2; }

al_check() {  # <kind> <label> <rel> <n> <dir> <da> <card> → stdout `ALREADY` | `WRITE <sha16> <comb|-> <old|-> <키>` rc0 · 거절 = 사유 1줄 rc2
  python3 - "$@" "$ROOT" "$HERE" <<'PY'
import hashlib, json, os, re, subprocess, sys
kind, label, rel, n, folder, da, card, root, here = sys.argv[1:10]
sys.path.insert(0, here)
from ft_launchd_llm_gate import MODEL, NET, SDK  # noqa: E402 — 판정기 꼴 그대로(ft_launchd_llm_gate.py:13-24)
st, key = os.path.join(root, ".fable-team", "state"), f"{label}/{rel}"
def no(why): print(why); sys.exit(2)
def done(out): print(out); sys.exit(0)
def rows(path):
    try:
        return [x.split("\t") for x in open(path, encoding="utf-8").read().splitlines()] if os.path.exists(path) else []
    except (OSError, UnicodeDecodeError) as exc:
        no(f"장부 판독 불가({type(exc).__name__}) {path}")
tsv = next((p for p in (f"{here}/../kit/launchd-roots.tsv", f"{here}/../../launchd-roots.tsv") if os.path.isfile(p)), "")
keys = {x[0] for x in rows(tsv) if len(x) >= 2 and x[0] and not x[0].startswith(("#", "@"))} if tsv else set()
label in keys or no(f"라벨이 뿌리 표 키 아님: {label}")
try:
    text = open(os.path.join(folder, rel), encoding="utf-8").read().splitlines()[int(n) - 1]
except (OSError, UnicodeDecodeError, IndexError) as exc:
    no(f"줄 판독 불가({type(exc).__name__}) {rel}:{n}")
if re.search(r"claude|codex|opencode|hermes|gemini|llm|aider|ollama", text, re.I) or NET.search(text) or MODEL.search(text) or SDK.match(text):
    no(f"줄에 LLM 낱말·NET·MODEL·SDK 꼴 {rel}:{n}")
h, comb = hashlib.sha256(text.strip().encode()).hexdigest()[:16], "-"
if kind == "allow":
    '"tmux", "new-session"' in text and '"pi"' in text or no(f"tmux 로 pi 띄우기 꼴 아님 {rel}:{n}")
else:
    try:
        p = subprocess.run([sys.executable, f"{here}/ft_launchd_llm_gate.py", "list-dyncalls", "--root-dir", folder, "--root-key", label],
                           capture_output=True, text=True, timeout=25)
    except subprocess.TimeoutExpired:
        no("list-dyncalls 25초 넘음")
    dyn = [r.split("\t") for r in p.stdout.splitlines() if len(r.split("\t")) == 5 and r.split("\t")[4].startswith(f"{key}:{n} ")]
    p.returncode == 0 and len(dyn) == 1 and dyn[0][0] == key and dyn[0][2] != "-" or no(f"동적 지점 행 정확히 1개 아님·결합 불가 {key}:{n} (rc={p.returncode} 행 {len(dyn)})")
    h, comb = dyn[0][1], dyn[0][2]
try:
    mail = [json.loads(x) for x in open(os.path.join(root, ".fable-team", "comm", "mailbox.log.jsonl"), encoding="utf-8") if x.strip()]
except (OSError, UnicodeDecodeError, ValueError) as exc:
    no(f"우편 로그 판독 불가({type(exc).__name__})")
def is_da(r): return "da" in re.sub(r"#\d+$", "", str(r.get("from", ""))).split("-")
def recs(r): return [x for x in str(r.get("body", "")).splitlines() if x.startswith("ALLOW-RECORD ")]
hit = [i for i, r in enumerate(mail) if str(r.get("seq")) == da]
len(hit) == 1 or no(f"DA #{da} 우편 행 {len(hit)}개(정확히 1 필요)")
is_da(mail[hit[0]]) or no(f"DA #{da} from 역할 마디 da 아님({mail[hit[0]].get('from')})")
one = recs(mail[hit[0]])
len(one) == 1 or no(f"DA #{da} ALLOW-RECORD 줄 {len(one)}개(정확히 1 필요)")
m = re.fullmatch(r"ALLOW-RECORD verdict=APPROVE kind=(allow|baseline) label=(\S+) path=(\S+) line=(\d+) card=(\S+) sha16=([0-9a-f]{16})"
                 r"(?: comb=([0-9a-f]{64}))?(?: old=([0-9a-f]{64}))?", one[0]) or no(f"DA #{da} 레코드 꼴 틀림")
mine = (kind, label, rel, n, card)
m.groups()[:5] == mine or no(f"DA #{da} 레코드 kind·label·path·line·card ≠ 인자")
r_h, r_comb, old = m.group(6), m.group(7), m.group(8)
((r_comb is None and old is None) if kind == "allow" else bool(r_comb)) or no(f"DA #{da} 레코드 comb 칸 틀림(allow = 없음 · baseline = 필수)")
r_h == h or no(f"승인 sha16 {r_h} ≠ 지금 {h}")
kind == "allow" or r_comb == comb or no(f"승인 결합 sha ≠ 지금 {comb}")
KEY = re.compile(r"ALLOW-RECORD verdict=\S+ kind=(\S+) label=(\S+) path=(\S+) line=(\S+) card=(\S+)(?: |$)")
last = max((i for i, r in enumerate(mail) if is_da(r) and any((k := KEY.match(x)) and k.groups() == m.groups()[:5] for x in recs(r))), default=-1)
last == hit[0] or no(f"같은 키 DA 레코드가 #{da} 뒤에 있음(#{mail[last].get('seq')})")
if kind == "allow":
    any(len(x) == 4 and x[:3] == [label, key, h] and re.fullmatch(r"\d+\.\d+", x[3].strip()) for x in rows(f"{st}/launchd-llm-allow.tsv")) and done("ALREADY")
    done(f"WRITE {h} - - {key}")
combs = {x[2] for x in rows(f"{st}/launchd-dyncall-baseline.tsv") if len(x) >= 4 and x[0] == key and x[1] == h and x[3].strip()}
comb in combs and done("ALREADY")
if combs:
    old in combs or no(f"같은 키·sha16 에 다른 결합 sha 행 — 교체 레코드(old=지금 행) 아님 {key}")
    done(f"WRITE {h} {comb} {old} {key}")
old is None or no(f"old= 있는데 교체할 행 없음 {key}")
done(f"WRITE {h} {comb} - {key}")
PY
}

cmd_allow_line() {
  live_match || exit 1
  local label="${1:-}" rel="${2:-}" n="${3:-}" kind="" dir="" da="" card="" st="$ROOT/.fable-team/state" out now line h comb old key
  [ $# -ge 3 ] || al_rej "인자 부족 (usage: allow-line <라벨> <상대경로> <줄번호> --kind allow|baseline --root-dir <폴더> --da <seq> --card <stem>)"; shift 3
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || al_rej "$1 값 없음"
    case "$1" in --kind) kind="$2" ;; --root-dir) dir="$2" ;; --da) da="$2" ;; --card) card="$2" ;; *) al_rej "알 수 없는 인자: $1" ;; esac; shift 2
  done
  [[ "$kind" =~ ^(allow|baseline)$ ]] || al_rej "--kind 는 allow|baseline"
  [[ "$n" =~ ^[1-9][0-9]*$ && "$da" =~ ^[0-9]+$ && "$card" =~ ^[A-Za-z0-9._-]+$ ]] || al_rej "줄번호·--da·--card 꼴 틀림"
  [ -n "$label" ] && [ -n "$rel" ] && [ -d "$dir" ] || al_rej "라벨·상대경로 빈 값 또는 --root-dir 폴더 없음"
  case "$label/$rel" in *[[:space:]]*|*..*|*\\*) al_rej "라벨·상대경로에 공백·탭·..·\\ 금지" ;; esac
  lock
  [ "$(mode)" = on ] || al_rej "자율 ON 아님($(mode))"
  scope_load || al_rej "활성 범위 승인 없음"
  now="$(now_epoch)"
  [ "$G_A" = "$(event)" ] || al_rej "범위 승인 $G_S 의 사건 $G_A ≠ 지금 $(event)"
  [ "$G_UNTIL" -gt "$now" ] || al_rej "범위 승인 $G_S 끝남"
  ! scope_stopped "$G_S" || al_rej "범위 승인 $G_S 정지"
  out="$(al_check "$kind" "$label" "$rel" "$n" "$dir" "$da" "$card")" || al_rej "${out:-판정 실패}"
  [ "$out" = ALREADY ] && { unlock; echo "ALREADY allow-line $kind $label $rel:$n"; return 0; }
  read -r _ h comb old key <<<"$out"
  if [ "$old" = - ]; then line="allow-line $kind $label $rel $h $G_A $G_S da=$da $now"
  else line="allow-line baseline-replace $key $h old=$old new=$comb $G_A $G_S da=$da $now"; fi
  printf '%s\n' "$line" >> "$LOG" || al_rej "log 쓰기 실패"
  local b="$st/launchd-dyncall-baseline.tsv" row="$key"$'\t'"$h"$'\t'"$comb"$'\t'"auto $G_A $G_S · DA #$da · $card · $now"
  if [ "$kind" = allow ]; then printf '%s\t%s\t%s\t%s.0\n' "$label" "$key" "$h" "$now" >> "$st/launchd-llm-allow.tsv"
  elif [ "$old" = - ]; then printf '%s\n' "$row" >> "$b"
  else K="$key" H="$h" O="$old" W="$row" awk -F'\t' '$1 == ENVIRON["K"] && $2 == ENVIRON["H"] && $3 == ENVIRON["O"] && !d { print ENVIRON["W"]; d = 1; next } { print } END { exit !d }' "$b" > "$b.tmp.$$" && mv "$b.tmp.$$" "$b"
  fi || { rm -f "$b.tmp.$$"; echo "판정 불가 allow-line 장부 쓰기 실패 — 원장 1행만 남음(판정기는 그대로 REJECT)"; exit 3; }
  unlock; echo "ALLOW-LINE $line"
}
