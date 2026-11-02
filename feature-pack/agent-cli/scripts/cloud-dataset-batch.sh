#!/usr/bin/env bash
# cloud-dataset-batch.sh — Claude cloud session credits($250)로 학습·라벨링 데이터를 대량 생성해 회수(ccxt)까지
#
# 왜 cloud session 인가:
#   cloud session credits(iguana_necktie)는 «Anthropic 인프라에서 도는 cloud session» 에서만 차감된다.
#   로컬 CLI·cliproxy 경유 호출로는 차감 0. 그래서 데이터 생성 물량을 크레딧으로 태우려면 cloud session 이 유일한 경로다.
#   (근거: ~/.headroom/USAGE_CREDITS_PLAYBOOK.md §13-5·§13-8)
#
# 구조 (repo·코드 불필요):
#   1) 빈 작업폴더에서 cloud session 생성 (ccx) — "This folder is not a git repository, so the cloud session starts empty"
#   2) 완료까지 teleport 회수(ccxt)를 폴링하면서 화면에서 마커 사이 JSONL 만 추출
#   3) out/<run>/data.jsonl 로 적재 + credits 델타 원장 기록
#
# Usage:
#   bash scripts/cloud-dataset-batch.sh --lang ko,ja,th --task lexicon --count 200 --batch 20 --parallel 3
#   bash scripts/cloud-dataset-batch.sh --task label --spec my-spec.jsonl --out ~/data/label-01
#   bash scripts/cloud-dataset-batch.sh --task doc --lang ko --count 4 --batch 4 --parallel 1 --budget 1   # 소량 시험
#
#   --task lexicon|parallel|label|qa|doc|free   데이터 템플릿 (기본 lexicon · doc = 긴 글 소진용)
#   --lang ko,ja,th                         대상 언어(콤마). 각 배치는 이 목록을 돌아가며 쓴다
#   --count N                               총 레코드 수 (기본 100)
#   --batch N                               세션 1개가 만들 레코드 수 (기본 25, 최대 60)
#   --parallel N                            동시 cloud session 수 (기본 2, 최대 4)
#   --out DIR                               출력 디렉터리 (기본 ./cloud-dataset-<ts>)
#   --account <email 일부>                  크레딧 계정 (기본 CC_CREDIT_ACCOUNT 또는 yoonhwan.ai@gmail.com)
#   --budget USD                            크레딧 지출 상한. 초과하면 새 배치를 시작하지 않는다 (기본 5)
#   --max-wait 초                            배치 1개 대기 상한 (기본 600)
#   --spec FILE                             잡 목록 JSONL 직접 지정 ([{"lang":..,"task":..,"topic":..}])
#   --labels a,b,c                          --task label 의 폐쇄 라벨 집합 (기본 work,tech,legal,daily,billing,other)
#   --dry-run                               프롬프트·계획만 출력 (크레딧 0)
#   --keep-tmux                             끝나도 tmux 세션/작업폴더를 남긴다(디버그)
#
# 전제: claude ≥2.1.310 · ~/.headroom/claude-credit.sh (ccx/ccxt/_ccx_inject) · tmux · python3
#       cloud 생성은 §13-7 전제(프로필 레이아웃 + macOS Keychain 그림자 제거)를 _ccx_inject 가 처리한다.
set -uo pipefail
exec </dev/null

CREDIT_LIB="$HOME/.headroom/claude-credit.sh"
TASK="lexicon"; LANGS="ko"; COUNT=100; BATCH=25; PARALLEL=2
OUT=""; ACCOUNT="${CC_CREDIT_ACCOUNT:-yoonhwan.ai@gmail.com}"
BUDGET=5; MAX_WAIT=600; SPEC=""; DRY=0; KEEP=0
LABELS="work,tech,legal,daily,billing,other"
PANE_W=600; PANE_H=60

while [ $# -gt 0 ]; do
  case "$1" in
    --task) TASK="${2:?}"; shift 2;;
    --lang) LANGS="${2:?}"; shift 2;;
    --count) COUNT="${2:?}"; shift 2;;
    --batch) BATCH="${2:?}"; shift 2;;
    --parallel) PARALLEL="${2:?}"; shift 2;;
    --out) OUT="${2:?}"; shift 2;;
    --account) ACCOUNT="${2:?}"; shift 2;;
    --budget) BUDGET="${2:?}"; shift 2;;
    --max-wait) MAX_WAIT="${2:?}"; shift 2;;
    --spec) SPEC="${2:?}"; shift 2;;
    --labels) LABELS="${2:?}"; shift 2;;
    --dry-run) DRY=1; shift;;
    --keep-tmux) KEEP=1; shift;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown option: $1 (--help)" >&2; exit 2;;
  esac
done

[ "$BATCH" -le 60 ] || BATCH=60
[ "$PARALLEL" -le 4 ] || PARALLEL=4
[ -f "$CREDIT_LIB" ] || { echo "claude-credit.sh 없음: $CREDIT_LIB" >&2; exit 1; }
for c in tmux claude python3; do command -v "$c" >/dev/null 2>&1 || { echo "PATH에 '$c' 없음" >&2; exit 1; }; done
TS="$(date +%Y%m%d-%H%M%S)"
[ -n "$OUT" ] || OUT="$PWD/cloud-dataset-$TS"
RUN="$OUT/run-$TS"
mkdir -p "$RUN"

# ── 크레딧 조회 (★ /api/oauth/usage 는 60초 미만 반복 금지 — 429 실측 · 실패 시 25초 뒤 1회 재시도) ──
cred_used_once() {
  python3 - <<'PY' "$ACCOUNT" 2>/dev/null
import glob, json, os, subprocess, sys
acct = sys.argv[1]
fs = sorted(glob.glob(os.path.expanduser(f"~/.cli-proxy-api/claude-*{acct}*.json")))
if not fs: print(""); raise SystemExit
d = json.load(open(fs[0]))
out = subprocess.run(['curl','-s','-m','20','https://api.anthropic.com/api/oauth/usage',
      '-H','Authorization: Bearer '+d['access_token'],
      '-H','anthropic-beta: oauth-2025-04-20','-H','anthropic-version: 2023-06-01'],
      capture_output=True, text=True).stdout
try: ig = json.loads(out).get('iguana_necktie') or {}
except Exception: print(""); raise SystemExit
print(ig.get('used_dollars'))
PY
}
cred_used() {   # 429 등으로 비면 25초 뒤 1회 재시도
  local v; v=$(cred_used_once)
  if [ -z "$v" ]; then sleep 25; v=$(cred_used_once); fi
  printf '%s' "$v"
}

# ── 잡 계획 생성 (spec 없으면 lang × task 로 count 만큼 잘라 만든다) ──
python3 - "$RUN" "$SPEC" "$TASK" "$LANGS" "$COUNT" "$BATCH" <<'PY'
import json, os, sys
run, spec, task, langs, count, batch = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]), int(sys.argv[6])
jobs = []
if spec and os.path.isfile(spec):
    for ln in open(spec):
        ln = ln.strip()
        if ln: jobs.append(json.loads(ln))
    for j in jobs: j.setdefault("task", task)
else:
    L = [x.strip() for x in langs.split(",") if x.strip()] or ["ko"]
    for i in range(count):
        jobs.append({"task": task, "lang": L[i % len(L)]})
batches, cur = [], []
for j in jobs:
    cur.append(j)
    if len(cur) >= batch: batches.append(cur); cur = []
if cur: batches.append(cur)
for i, b in enumerate(batches, 1):
    json.dump({"idx": i, "records": len(b), "jobs": b}, open(os.path.join(run, f"plan-{i:03d}.json"), "w"), ensure_ascii=False)
print(f"PLAN batches={len(batches)} records={len(jobs)}")
PY

PROMPT_DIR="$RUN/prompts"; mkdir -p "$PROMPT_DIR"
python3 - "$RUN" "$PROMPT_DIR" "$LABELS" <<'PY'
import glob, json, os, sys
run, pdir, labels = sys.argv[1], sys.argv[2], sys.argv[3]
LSET = [x.strip() for x in labels.split(",") if x.strip()]
labels_rule = ""
if not LSET: LSET = ["other"]
TPL = {
 "lexicon": ("linguistic lexicon entries", '{"id":"<lang>-0001","lang":"<lang>","lemma":"...","pos":"noun|verb|adj|adv|phrase","ipa":"...","gloss_en":"...","example":"...","example_gloss_en":"...","register":"formal|neutral|colloquial"}'),
 "parallel": ("bilingual parallel corpus pairs", '{"id":"<lang>-0001","src_lang":"<lang>","tgt_lang":"en","src":"...","tgt":"...","domain":"daily|business|tech|legal","note":"..."}'),
 "label": ("classification labels for given texts", '{"id":"<lang>-0001","lang":"<lang>","text":"...","label":"<one of the label set below>","rationale":"..."}'),
 "qa": ("question-answer pairs for language learning", '{"id":"<lang>-0001","lang":"<lang>","question":"...","answer":"...","level":"A1|A2|B1|B2","topic":"..."}'),
 "doc": ("long-form document sections", '{"id":"<lang>-0001","lang":"<lang>","title":"...","section":"...","text":"..."}'),
 "free": ("free-form records", '{"id":"<lang>-0001","lang":"<lang>","text":"..."}'),
}
for f in sorted(glob.glob(os.path.join(run, "plan-*.json"))):
    p = json.load(open(f)); jobs = p["jobs"]
    task = jobs[0].get("task", "lexicon")
    kind, schema = TPL.get(task, TPL["free"])
    line_lim = 520 if task == "doc" else 260
    if task == "label":
        schema = schema.replace("<one of the label set below>", "|".join(LSET))
        labels_rule = "\n- label 값은 **반드시** 다음 중 하나만 그대로 써라(변형·번역 금지): " + ", ".join(LSET)
    langs = sorted({j.get("lang", "ko") for j in jobs})
    topics = [j.get("topic", "") for j in jobs if j.get("topic")]
    topic_line = ("주제: " + ", ".join(topics[:12])) if topics else "주제: 일상·업무·기술에서 고르게"
    body = f"""너는 다국어 언어 데이터 큐레이터다. 아래 조건으로 {kind} 를 정확히 {p['records']}건 생성해라.

- 언어: {", ".join(langs)}
- {topic_line}
- 각 레코드는 한 줄짜리 JSON 객체(JSONL)이고, 아래 스키마의 키만 쓴다:
  {schema}
- 서로 중복되지 않게, 실제로 쓰이는 표현으로 채운다. 값에 개행·탭을 넣지 않는다.{labels_rule}
- 한 줄은 {line_lim}자 이내로 유지한다(개행 금지).
- 파일을 만들지 말고, 최종 답변 텍스트에 아래 마커 블록 하나만 출력한다. 설명·인사·요약 금지.

<<<DATASET
(여기에 JSONL {p['records']}줄)
DATASET>>>
"""
    open(os.path.join(pdir, f"prompt-{p['idx']:03d}.txt"), "w").write(body)
print("PROMPTS", len(glob.glob(os.path.join(pdir, "prompt-*.txt"))))
PY

if [ "$DRY" = 1 ]; then
  echo "── DRY RUN (크레딧 0) ──"
  echo "run: $RUN"; echo "account: $ACCOUNT"; echo "budget: \$$BUDGET"; echo "batches:"; ls "$RUN"/plan-*.json | sed 's/^/  /'
  echo "── 예시 프롬프트(plan-001) ──"; cat "$PROMPT_DIR"/prompt-001.txt
  exit 0
fi

# 화면 → JSONL. ★함정: pane 에는 «우리 프롬프트 에코» 가 같이 찍혀서 마커가 즉시 발견된다(2026-10-24 실측 → 0건 오판).
#   → 마커 블록을 전부 찾아 그 중 **파싱되는 레코드가 가장 많은 블록**을 쓴다(프롬프트 에코 블록은 0건이라 자동 배제).
extract_pane() {   # $1=pane파일 $2=out $3=sid $4=idx  → 레코드 1개 이상이면 rc=0
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, re, sys
pane, out, sid, idx = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try: raw = open(pane, encoding="utf-8", errors="replace").read()
except FileNotFoundError: print(f"[{idx}] pane 없음"); sys.exit(4)
blocks = re.findall(r"<<<DATASET(.*?)DATASET>>>", raw, re.S)

def parse(body):
    recs, bad = [], 0
    for ln in body.splitlines():
        s = ln.strip()
        s = re.sub(r'^[⏺⎿│>❯\-\s]+', '', s).strip()      # pane 렌더 장식 제거
        if not s: continue
        start = s.find("{")
        if start < 0: continue
        s = s[start:]
        ok = False
        for cut in (s.rfind("}") + 1, len(s)):
            if cut <= 0: continue
            try: recs.append(json.loads(s[:cut])); ok = True; break
            except Exception: pass
        if not ok: bad += 1
    return recs, bad

best, bestbad = [], 0
for b in blocks:
    r, bad = parse(b)
    if len(r) > len(best): best, bestbad = r, bad
if not best:
    print(f"[{idx}] 대기 — 마커 블록 {len(blocks)}개 · 파싱 레코드 0"); sys.exit(4)
with open(out, "w", encoding="utf-8") as f:
    for r in best:
        f.write(json.dumps({"session_id": sid, **r}, ensure_ascii=False) + "\n")
print(f"[{idx}] 추출 {len(best)}건 (깨진 줄 {bestbad}) → {out}")
sys.exit(0)
PY
}

# ── 배치 1개 실행: cloud 생성 → 회수 폴링 → 화면에서 마커 추출 ──
run_batch() {
  local idx="$1" prompt_file="$2" out_jsonl="$3"
  local tag="cdb-$TS-$idx" work="$RUN/work-$idx" sid="" log="$RUN/batch-$idx.log"
  mkdir -p "$work"
  echo "[$idx] 프롬프트 $(wc -c <"$prompt_file") bytes · work=$work" | tee -a "$log"
  local created
  created=$(cd "$work" && bash -lc "source '$CREDIT_LIB'; CC_CREDIT_ACCOUNT='$ACCOUNT' ccx \"\$(cat '$prompt_file')\"" 2>&1)
  echo "$created" >> "$log"
  sid=$(printf '%s' "$created" | grep -o 'session_[A-Za-z0-9]\+' | head -1)
  if [ -z "$sid" ]; then
    echo "[$idx] ✗ 생성 실패 — 원문:" | tee -a "$log"; printf '%s\n' "$created" | tail -6 | tee -a "$log"
    return 1
  fi
  echo "[$idx] 세션 $sid" | tee -a "$log"

  local waited=0 cap=""
  while [ "$waited" -lt "$MAX_WAIT" ]; do
    sleep 25; waited=$((waited + 25))
    tmux kill-session -t "$tag" 2>/dev/null
    tmux new-session -d -s "$tag" -x "$PANE_W" -y "$PANE_H" \
      "cd '$work' && bash -lc 'source \"$CREDIT_LIB\"; CC_CREDIT_ACCOUNT=\"$ACCOUNT\" ccxt $sid'; echo ---EXIT---; sleep 1800"
    sleep 14
    cap=$(tmux capture-pane -p -t "$tag" -S -20000 2>/dev/null)
    printf '%s' "$cap" > "$RUN/pane-$idx.txt"
    if extract_pane "$RUN/pane-$idx.txt" "$out_jsonl" "$sid" "$idx" >> "$log" 2>&1; then
      echo "[$idx] 완료 (${waited}s)" | tee -a "$log"; break
    fi
    echo "[$idx] 대기 ${waited}s …" | tee -a "$log"
  done
  local rc=0
  [ -s "$out_jsonl" ] || { echo "[$idx] ✗ 추출 실패(max-wait $MAX_WAIT) — pane-$idx.txt 확인" | tee -a "$log"; rc=4; }
  [ "$KEEP" = 1 ] || { tmux kill-session -t "$tag" 2>/dev/null; rm -rf "$work"; }
  return $rc
}

echo "══ cloud-dataset-batch $(date '+%F %T') ══"
echo "task=$TASK lang=$LANGS count=$COUNT batch=$BATCH parallel=$PARALLEL budget=\$$BUDGET account=$ACCOUNT"
BEFORE=$(cred_used); echo "credits before: ${BEFORE:-조회실패}/250"
printf 'session_id\tbatch\trecords\tfile\n' > "$RUN/index.tsv"

START_TS=$(date +%s); LAST_CRED_TS=$START_TS
running=0; failed=0
for pf in "$PROMPT_DIR"/prompt-*.txt; do
  idx=$(basename "$pf" .txt | sed 's/prompt-//')
  out="$RUN/data-$idx.jsonl"
  # 예산 가드 (60초 이상 간격으로만 조회)
  now=$(date +%s)
  if [ $((now - LAST_CRED_TS)) -ge 60 ] && [ -n "$BEFORE" ]; then
    CUR=$(cred_used); LAST_CRED_TS=$now
    if [ -n "$CUR" ]; then
      SPENT=$(python3 -c "print(round($CUR-$BEFORE,4))" 2>/dev/null || echo 0)
      echo "credits used so far: \$$SPENT / budget \$$BUDGET"
      if python3 -c "import sys; sys.exit(0 if $SPENT >= $BUDGET else 1)"; then
        echo "⛔ 예산 도달 — 남은 배치 중단"; break
      fi
    fi
  fi
  while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$PARALLEL" ]; do sleep 5; done
  ( run_batch "$idx" "$pf" "$out" && printf '%s\t%s\t%s\t%s\n' \
      "$(grep -o 'session_[A-Za-z0-9]\+' "$RUN/batch-$idx.log" | head -1)" "$idx" \
      "$(wc -l <"$out" | tr -d ' ')" "$out" >> "$RUN/index.tsv" ) &
  running=$((running + 1))
done
wait
AFTER=$(cred_used)
echo
echo "══ 결과 ══"
# 병합: 배치마다 id 가 0001 부터 다시 시작하므로 **중복 제거 + id 재부여**(lang 별 일련번호)
python3 - "$RUN" "$OUT" <<'PY'
import glob, json, sys, collections
run, out = sys.argv[1], sys.argv[2]
recs, seen, dup = [], set(), 0
for f in sorted(glob.glob(f"{run}/data-*.jsonl")):
    for ln in open(f, encoding="utf-8"):
        ln = ln.strip()
        if not ln: continue
        try: r = json.loads(ln)
        except Exception: continue
        key = (r.get("lang"), (r.get("lemma") or r.get("src") or r.get("text") or r.get("question") or "").strip().lower())
        if key in seen: dup += 1; continue
        seen.add(key); recs.append(r)
seq = collections.Counter()
for r in recs:
    lang = (r.get("lang") or r.get("src_lang") or "xx")
    seq[lang] += 1
    r["id_original"] = r.get("id")
    r["id"] = f"{lang}-{seq[lang]:05d}"
with open(f"{out}/data.jsonl", "w", encoding="utf-8") as f:
    for r in recs: f.write(json.dumps(r, ensure_ascii=False) + "\n")
print(f"레코드: {len(recs)}건 (중복 제거 {dup}건) → {out}/data.jsonl")
print("언어별:", dict(collections.Counter(r.get('lang') or r.get('src_lang') for r in recs)))
if recs and "label" in recs[0]:
    print("라벨 분포:", dict(collections.Counter(r.get("label") for r in recs)))
PY
echo "원장  : $RUN/index.tsv"
echo "로그  : $RUN/batch-*.log · pane-*.txt$( [ "$KEEP" = 1 ] && echo " · work-*/" )"
python3 - "$BEFORE" "$AFTER" "$OUT" <<'PY'
import json, sys, datetime
b, a, out = sys.argv[1], sys.argv[2], sys.argv[3]
spent = None
try: spent = round(float(a) - float(b), 4)
except Exception: pass
print(f"credits: {b or '?'} → {a or '?'} ({'Δ $'+format(spent,'.4f') if spent is not None else '조회실패 — /api/oauth/usage 60초 간격 제한(429), ccxc 로 나중에 확인'})")
if spent is not None:
    json.dump({"ts": datetime.datetime.now().isoformat(timespec="seconds"), "credits_before": b,
               "credits_after": a, "spent_usd": spent}, open(f"{out}/ledger.json", "w"), indent=1)
PY
echo "다음: jq -c . \"$OUT/data.jsonl\" | head   # 검수 후 학습 파이프라인에 연결"
