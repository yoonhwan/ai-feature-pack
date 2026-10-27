#!/usr/bin/env bash
# test_secret_followup_r1027.sh — ft_secret_followup.py 셋 답(시각·지문·삭제 계획) · 값 0 (r1027 · 계약 C1~C4)
# 격리: 임시 HOME(합성 session jsonl · 합성 점검 표 · 합성 키 장부) + 가짜 볼트 2(하나는 읽기 실패) + 가짜 gcloud(프로젝트 2 · 하나는 권한 오류) + 가짜 tmux.
#   실 기록·실 볼트·실 SM·실 tmux 읽기 0 · 쓰기 0. 변이 4종은 mktemp 사본에서만(새 칸만: FT_TEST_ONLY=r2).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/test_only.sh"                              # r1026: FT_TEST_ONLY 로 «그 칸만»
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$HERE/.."
BIND="${FT_FOLLOWUP_UNDER_TEST:-$HARNESS/bin}"        # 변이 사본을 넣어 이 시험 자체를 다시 돌린다
PY="$BIND/ft_secret_followup.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"; chmod -R u+rwX "$T" 2>/dev/null' EXIT
export HOME="$T/home"
mkdir -p "$HOME"
V1='ZQ7xREALvalue0123456789'; V2='ghp_ZQ7xREALvalue0123456789'; V3='ZQ7xREALpassword99'
O1='ZQ7xOLDkeyAAAAAAAAAAAAAA'; O2='ZQ7xOLDkeyBBBBBBBBBBBBBB'

# ── 합성 기록: 살아 있는 세션 폴더(가짜 tmux pane cwd 와 같은 이름) + 닫힌 세션 폴더
DIR="$T/proj/my-worktree"; OTHER="$T/proj/old-worktree"
ENC="$(printf '%s' "$DIR" | tr '/' '-')"; ENC2="$(printf '%s' "$OTHER" | tr '/' '-')"
mkdir -p "$HOME/.claude/projects/$ENC" "$HOME/.claude/projects/$ENC2"
LIVEJ="$HOME/.claude/projects/$ENC/live.jsonl"; DEADJ="$HOME/.claude/projects/$ENC2/closed.jsonl"
printf '{"timestamp":"2026-10-20T03:00:00Z","stdout":"API_TOKEN=%s ok"}\n' "$V1" > "$LIVEJ"
printf '{"type":"assistant","timestamp":"2026-11-01T09:00:00Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"curl -H x"}}]}}\n' >> "$LIVEJ"
printf '{"note":"no timestamp line"}\n' >> "$LIVEJ"  # 줄 시각 없음 → mtime(최근) = 교체 뒤
printf '{"note":"PGPASSWORD=%s"}\n' "$V3" > "$DEADJ"
printf '{"out":"%s"}\n' "$V2" >> "$DEADJ"
touch -t 202001010000 "$DEADJ"                       # 최근 쓰기 아님

# ── 가짜 tmux(살아 있는 pane cwd 1개) · 가짜 출처(볼트 2 — develop 정상 · BYZ 읽기 실패)
printf '#!/usr/bin/env bash\necho "sess1\t%s"\n' "$DIR" > "$T/tmux"; chmod +x "$T/tmux"
printf '{"vaults":{"develop":{"GH_TOKEN":"%s","OLD_A":"%s"}},"fail":{"BYZ":"PERMISSION_DENIED: vault read failed"}}' \
  "$V1" "$O1" > "$T/vaults.json"

# ── 가짜 gcloud: p1 정상(SEC_LIVE=V2 · SEC_OLD=무관) · p2deny 는 권한 오류
cat > "$T/gcloud" <<EOF
#!/usr/bin/env bash
a="\$*"
case "\$a" in
  *"projects list"*) printf 'p1\np2deny\n' ;;
  *"secrets list"*p2deny*) echo "ERROR: (gcloud.secrets.list) PERMISSION_DENIED: caller does not have secretmanager.secrets.list" >&2; exit 1 ;;
  *"secrets list"*p1*) printf 'SEC_LIVE\nSEC_OLD\n' ;;
  *"versions access"*SEC_LIVE*) printf '%s' "$V2" ;;
  *"versions access"*SEC_OLD*) printf 'zzz-unrelated-value' ;;
  *) echo "unexpected \$a" >&2; exit 1 ;;
esac
EOF
chmod +x "$T/gcloud"

# ── 합성 점검 표(r1002 꼴) + 합성 키 장부(마지막 교체 2026-10-25 12:00:00)
cat > "$T/TRIAGE.md" <<EOF
| 파일 | 줄 | 종류 | 3값 |
| --- | --- | --- | --- |
| $LIVEJ | 1 | named-secret | 실값 |
| $LIVEJ | 2 | named-secret | 실값 |
| $LIVEJ | 3 | named-secret | 실값 |
| $DEADJ | 1 | pgpassword | 실값 |
| $DEADJ | 2 | token-prefix | 실값 |
| $DEADJ | 9 | named-secret | 실값 |
EOF
{ printf '| ENV(표준) | 옛 이름 | 제공사 | 로컬 | 1Password(develop) | SM dev | SM prod | Cloud Run | 코드 | 사용처 | 마지막 교체 | 상태 |\n'
  printf '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n'
  for n in GH_TOKEN OLD_A; do
    printf '| %s | — | gh | 있음 | 있음 | — | — | — | ENV 1 | 미조사 | 교체 2026-10-25 12:00:00 | 정상 |\n' "$n"
  done
} > "$T/keys.md"
NOROT="$T/keys-norot.md"; grep -v '교체 2026' "$T/keys.md" > "$NOROT"

fail=0; out=""; err=""; rc=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:200} err=${err:0:200}"; fail=$((fail+1)); fi; }
run() { out="$(FT_FOLLOWUP_TMUX="$T/tmux" FT_FOLLOWUP_VAULTS_JSON="$T/vaults.json" FT_FOLLOWUP_GCLOUD="$T/gcloud" \
  python3 "$PY" "$@" 2>"$T/e")"; rc=$?; err="$(cat "$T/e")"; }
novalue() { ! grep -q -e ZQ7x "$@" \
  && ! grep -q -e "$(printf '%s' "$V1" | shasum -a 256 | cut -c1-8)" -e "$(printf '%s' "$V3" | shasum -a 256 | cut -c1-8)" "$@"; }

python3 -m py_compile "$PY" "$BIND/ft_secret_followup_plan.py"; ck "py_compile (도구·짝)" $?
[ "$(wc -l < "$PY")" -le 200 ] && [ "$(wc -l < "$BIND/ft_secret_followup_plan.py")" -le 200 ]; ck "200줄 상한(도구·짝)" $?

ft_only base && {   # ── 기존 칸(① 시각 · ② 이름 · ③ 계획) — FT_TEST_ONLY 가 있으면 그 칸만 돈다
# C1 — 시각 전/뒤 셈 · 뒤인 행의 도구 이름 · 줄 시각 없음 = mtime
run --triage "$T/TRIAGE.md" --keys-log "$T/keys.md" --report "$T/rep.md" --plan "$T/plan.md"
[ "$rc" = 0 ] && [ "$(grep -c . <<<"$out")" = 1 ]; ck "rc0 · 표준출력 1줄" $?
grep -q 'followup=6 front=3 back=2 same=0 unknown=1' <<<"$out"; ck "C1 합계 front=3 back=2 unknown=1(줄 번호 초과)" $?
grep -q '교체 시각: 2026-10-25 12:00:00' "$T/rep.md"; ck "C1 교체 시각을 원장에서 읽음" $?
grep -q 'live.jsonl:2.*assistant · Bash() curl' "$T/rep.md"; ck "C1 교체 뒤 행 = 도구·명령 첫 낱말" $?
grep -q 'live.jsonl:3.*(mtime)' "$T/rep.md"; ck "C1 줄 시각 없음 → mtime 대체 표시" $?
grep -q 'unknown=1' <<<"$out"; ck "C1 못 읽는 줄 = 판정 불가(조용한 생략 0)" $?

# C2 — 옛 키 판정 · 삭제 계획(③)
grep -q '| OP develop · OLD_A | 옛 키(일치 0) | 0 |' "$T/rep.md"; ck "C2 옛 키(일치 0)" $?
grep -q '되돌림 없음 — 지운 기록은 복구 0' "$T/plan.md"; ck "C3 머리 줄 «되돌림 없음»" $?
grep -q "다음 닫힘 뒤 (살아 있는 세션 기록)" "$T/plan.md" && grep -q "rm -f '$LIVEJ'" "$T/plan.md"; ck "C3 살아 있는 세션 기록 = 다음 닫힘 뒤 칸" $?
grep -q "## 삭제 명령 (실행 0 · 글자만)" "$T/plan.md" && grep -q "rm -f '$DEADJ'" "$T/plan.md"; ck "C3 닫힌 세션 = 삭제 명령 칸" $?
[ -f "$LIVEJ" ] && [ -f "$DEADJ" ]; ck "C3 실행 0 (파일 그대로)" $?
grep -q 'live_files=1' <<<"$out"; ck "C3 살아 있는 파일 1" $?

# C1 — 교체 시각을 못 찾으면 판정 불가 1줄로 끝
run --triage "$T/TRIAGE.md" --keys-log "$NOROT" --report "$T/rep3.md"
grep -q '판정 불가 — 교체 시각 없음' "$T/rep3.md" && grep -q 'front=0 back=0' <<<"$out"; ck "C1 교체 시각 없음 = 판정 불가 1줄" $?

# usage · 쓰기 실패
python3 "$PY" --triage "$T/TRIAGE.md" >/dev/null 2>&1; rc=$?; [ "$rc" = 2 ]; ck "usage 없으면 rc=2" $?
mkdir -p "$T/ro"; chmod 500 "$T/ro"
python3 "$PY" --triage "$T/TRIAGE.md" --keys-log "$T/keys.md" --report "$T/ro/x/y.md" >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ]; ck "보고 파일 못 쓰면 rc=4" $?
chmod 700 "$T/ro"
}

ft_only sm && {   # ── 새 칸(r1): 출처 둘(1Password 토큰 닿는 볼트 전부 + GCP SM 닿는 프로젝트 전부) · 대조 못 한 곳 오류 1줄
run --triage "$T/TRIAGE.md" --keys-log "$T/keys.md" --report "$T/rep.md" --plan "$T/plan.md"
grep -q '머리 줄: \*\*일치 2\*\* (OP develop · GH_TOKEN, SM p1/SEC_LIVE) · \*\*대조 못 한 곳 2\*\* · \*\*대조한 키 4\*\*' "$T/rep.md"
ck "R1 머리 줄 = 일치 2 · 대조 못 한 곳 2 · 대조한 키 4" $?
grep -q '| SM p1/SEC_LIVE | 살아 있음(일치) | 1 |' "$T/rep.md"; ck "R1 SM 값과 기록 값 일치 1" $?
grep -q '| OP develop · GH_TOKEN | 살아 있음(일치) | 1 |' "$T/rep.md"; ck "R1 볼트 값과 기록 값 일치 1" $?
grep -q 'SM p1/SEC_OLD | 옛 키(일치 0)' "$T/rep.md"; ck "R1 SM 옛 키(일치 0)" $?
grep -q '1Password 볼트 BYZ · PERMISSION_DENIED: vault read failed' "$T/rep.md"; ck "R1 볼트 읽기 실패 = 오류 원문 1줄" $?
grep -q 'GCP 프로젝트 p2deny · ERROR: (gcloud.secrets.list) PERMISSION_DENIED' "$T/rep.md"; ck "R1 프로젝트 권한 오류 = 오류 원문 1줄" $?
grep -q 'live_keys=2 keys=4 missed=2' <<<"$out"; ck "R1 표준출력 요약(일치 2 · 키 4 · 못 한 곳 2)" $?
novalue "$T/rep.md" "$T/plan.md" "$T/e" <<<"$out"; ck "R1 새 칸 출력에도 값·해시 8자 0" $?

# R1 — SM 목록 자체가 실패하면 «대조 못 한 곳» 1줄 · 볼트 키는 그대로 대조
printf '#!/usr/bin/env bash\necho "ERROR: (gcloud.projects.list) PERMISSION_DENIED: denied" >&2\nexit 1\n' > "$T/gcloud-bad"
chmod +x "$T/gcloud-bad"
out="$(FT_FOLLOWUP_TMUX="$T/tmux" FT_FOLLOWUP_VAULTS_JSON="$T/vaults.json" FT_FOLLOWUP_GCLOUD="$T/gcloud-bad" \
  python3 "$PY" --triage "$T/TRIAGE.md" --keys-log "$T/keys.md" --report "$T/rep4.md" 2>"$T/e4")"; rc=$?
grep -q 'GCP 프로젝트 목록 · ERROR: (gcloud.projects.list) PERMISSION_DENIED' "$T/rep4.md" \
  && grep -q '대조 못 한 곳 2' "$T/rep4.md" && grep -q '대조한 키 2' "$T/rep4.md"; ck "R1 SM 목록 실패 = 못 한 곳 1줄 · 볼트 키 2는 대조" $?
novalue "$T/rep4.md" "$T/e4" <<<"$out"; ck "R1 SM 실패 출력에도 값 0" $?
}


ft_only r2 && {   # ── 새 칸(DA r1 동작 3): R1 대입문 앞붙은 명령 · R2 같은 줄 2값 · R3 SDK 7초 상한
DIR3="$T/proj/r2-wt"; ENC3="$(printf '%s' "$DIR3" | tr '/' '-')"; mkdir -p "$HOME/.claude/projects/$ENC3"
R2J="$HOME/.claude/projects/$ENC3/r2.jsonl"
printf '{"type":"assistant","timestamp":"2026-11-01T10:00:00Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"API_TOKEN=%s curl -s"}}]}}\n' "$V1" > "$R2J"
printf '{"type":"assistant","timestamp":"2026-11-01T10:05:00Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"API_TOKEN=%s"}}]}}\n' "$V3" >> "$R2J"
printf '{"timestamp":"2026-11-01T10:10:00Z","stdout":"API_TOKEN=%s OLD_TOKEN=%s"}\n' "$V1" "$O1" >> "$R2J"
printf '| 파일 | 줄 | 종류 | 3값 |\n| --- | --- | --- | --- |\n| %s | 1 | named-secret | 실값 |\n| %s | 2 | named-secret | 실값 |\n| %s | 3 | named-secret | 실값 |\n' \
  "$R2J" "$R2J" "$R2J" > "$T/TRIAGE2.md"
run --triage "$T/TRIAGE2.md" --keys-log "$T/keys.md" --report "$T/rep-r2.md"
grep -q 'r2.jsonl:1.*assistant · Bash() curl' "$T/rep-r2.md"; ck "R1 대입문 앞붙은 명령 → 첫 명령 이름만(curl)" $?
grep -q 'r2.jsonl:2.*명령 이름 판정 불가' "$T/rep-r2.md"; ck "R1 명령 이름에 = 남으면 «판정 불가»" $?
novalue "$T/rep-r2.md" "$T/e" <<<"$out"; ck "R1 도구 칸에 값 글자·앞 8자 0" $?
grep -q '머리 줄: \*\*일치 2\*\* (OP develop · GH_TOKEN, OP develop · OLD_A)' "$T/rep-r2.md"; ck "R2 같은 줄 값 2개 → 일치 2" $?
grep -q '| OP develop · OLD_A | 살아 있음(일치) | 1 |' "$T/rep-r2.md"; ck "R2 둘째 값도 따로 셈" $?
grep -q 'live_keys=2' <<<"$out"; ck "R2 표준출력 요약 live_keys=2" $?

# R3 — 가짜 SDK 항목 읽기가 상한보다 느림 → 그 볼트만 «대조 못 한 곳 · 시간 초과» 1줄(고정 sleep 0 · 상한만 낮춤)
mkdir -p "$T/fakesdk"
cat > "$T/fakesdk/onepassword.py" <<'PYEOF'
import asyncio
class _O:
    def __init__(self, i, t):
        self.id, self.title = i, t
class _F:
    def __init__(self, v):
        self.value, self.purpose = v, ""
class _Full:
    fields = [_F("zzz-slow-unrelated")]
class Client:
    @staticmethod
    async def authenticate(**kw):
        return Client()
    class vaults:
        @staticmethod
        async def list():
            return [_O("v1", "SLOW")]
    class items:
        @staticmethod
        async def list(vid):
            return [_O("i1", "ITEM")]
        @staticmethod
        async def get(vid, iid):
            await asyncio.sleep(3.0)
            return _Full()
PYEOF
out="$(PYTHONPATH="$T/fakesdk" OP_SERVICE_ACCOUNT_TOKEN_DEVELOP=x FT_FOLLOWUP_SDK_SECS=1.0 \
  FT_FOLLOWUP_TMUX="$T/tmux" FT_FOLLOWUP_GCLOUD="$T/gcloud" \
  python3 "$PY" --triage "$T/TRIAGE.md" --keys-log "$T/keys.md" --report "$T/rep-r3.md" 2>"$T/e3")"; rc=$?
grep -q '1Password 볼트 SLOW · 시간 초과' "$T/rep-r3.md"; ck "R3 SDK 호출 7초 상한 → 대조 못 한 곳 1줄" $?
grep -q '대조한 키 2' "$T/rep-r3.md" && grep -q 'missed=2' <<<"$out"; ck "R3 그 볼트 키는 대조 0 · 못 한 곳 2(볼트+프로젝트)" $?
novalue "$T/rep-r3.md" "$T/e3" <<<"$out"; ck "R3 출력에 값 0" $?
}


ft_only r3 && {   # ── 새 칸(r3 · DA r2 동작 2): R6 같은 제목 2항목 · R5 파일 도구 경로
# R6 — 같은 제목 DUP 2항목(첫째 값이 기록과 같음) → 일치 1 · 표에 DUP 2줄
printf '{"vaults":{"develop":[["DUP","%s"],["DUP","zzz-other-item"]]}}' "$V1" > "$T/vaults-dup.json"
printf '{"timestamp":"2026-11-02T10:00:00Z","stdout":"API_TOKEN=%s"}\n' "$V1" > "$T/dup.jsonl"
printf '| %s | 1 | named-secret | 실값 |\n' "$T/dup.jsonl" > "$T/TRIAGE3.md"
out="$(FT_FOLLOWUP_TMUX="$T/tmux" FT_FOLLOWUP_VAULTS_JSON="$T/vaults-dup.json" FT_FOLLOWUP_GCLOUD="$T/gcloud" \
  python3 "$PY" --triage "$T/TRIAGE3.md" --keys-log "$T/keys.md" --report "$T/rep-r6.md" 2>"$T/e6")"; rc=$?
grep -q '머리 줄: \*\*일치 1\*\* (OP develop · DUP)' "$T/rep-r6.md"; ck "R6 같은 제목 2항목 → 일치 1" $?
[ "$(grep -c '| OP develop · DUP |' "$T/rep-r6.md")" = 2 ]; ck "R6 같은 제목 2줄을 둘 다 센다" $?
grep -q '| OP develop · DUP | 살아 있음(일치) | 1 |' "$T/rep-r6.md" && grep -q '| OP develop · DUP | 옛 키(일치 0) | 0 |' "$T/rep-r6.md"
ck "R6 항목마다 따로 판정(앞 항목이 덮이지 않음)" $?
grep -q '대조한 키 4' "$T/rep-r6.md"; ck "R6 대조한 키 4(같은 제목 2 + SM 2)" $?
novalue "$T/rep-r6.md" "$T/e6" <<<"$out"; ck "R6 출력에 값 0" $?

# R5 — Read 처럼 file_path 를 쓰는 도구: 도구 칸에 경로 0 (경로 안에 합성 값이 있어도)
printf '{"type":"assistant","timestamp":"2026-11-02T10:05:00Z","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"%s/%s.txt"}}]}}\n' \
  "$T" "$V2" > "$T/path.jsonl"
printf '| %s | 1 | named-secret | 실값 |\n' "$T/path.jsonl" > "$T/TRIAGE4.md"
out="$(FT_FOLLOWUP_TMUX="$T/tmux" FT_FOLLOWUP_VAULTS_JSON="$T/vaults.json" FT_FOLLOWUP_GCLOUD="$T/gcloud" \
  python3 "$PY" --triage "$T/TRIAGE4.md" --keys-log "$T/keys.md" --report "$T/rep-r5.md" --plan "$T/plan-r5.md" 2>"$T/e5")"; rc=$?
grep -q 'assistant · Read()' "$T/rep-r5.md"; ck "R5 파일 도구 = 도구 이름만(경로 0)" $?
! grep -q '\.txt' "$T/rep-r5.md"; ck "R5 도구 칸에 경로 글자 0" $?
novalue "$T/rep-r5.md" "$T/plan-r5.md" "$T/e5" <<<"$out"; ck "R5 보고·계획·stdout·stderr 에 값 0" $?
}

# 짝 사본 cmp0
KIT="$HARNESS/kit/fable-team/bin"
if [ "$BIND" = "$HARNESS/bin" ]; then
  cmp -s "$PY" "$KIT/ft_secret_followup.py" && cmp -s "$BIND/ft_secret_followup_plan.py" "$KIT/ft_secret_followup_plan.py"
  ck "kit 짝 cmp0 (도구·짝)" $?
fi

# 변이 6종(새 칸만: FT_TEST_ONLY=r2,r3 · DA r1 동작 3 + DA r2 동작 2 + 값 출력 되살림) → 이 시험이 FAIL 로 잡아야 한다
mut() {  # mut <이름> <patch 코드> [대상 파일(기본 ft_secret_followup.py)]
  local d="$T/mut-$1"; mkdir -p "$d"
  cp -p "$BIND"/ft_secret_followup*.py "$BIND"/ft_secret_*.py "$d/"   # 의존 모듈까지(못 읽는 사본으로 «우연히» FAIL 하지 않게)
  python3 - "$d/${3:-ft_secret_followup.py}" "$2" <<'EOF' || { echo "FAIL 변이 $1 패치가 원본에 안 붙음"; fail=$((fail+1)); return 1; }
import sys
p, code = sys.argv[1], sys.argv[2]
s = open(p).read()
for pair in code.split("\n#---\n"):
    a, b = pair.split("\n>>>\n")
    assert a in s, a[:60]
    s = s.replace(a, b)
open(p, "w").write(s)
EOF
}
LEAK='            r["hits"] = sorted({u for u, _d, lvs in keys for v in vals if any(_sha(v) == _sha(lv) for lv in lvs)})
>>>
            r["hits"] = sorted({u for u, _d, lvs in keys for v in vals if any(_sha(v) == _sha(lv) for lv in lvs)})
            r["leak"] = " ".join(v[:12] for v in vals)
#---
    rep, pln = texts(rows, rot, rot_why, keys, miss, live)
>>>
    rep, pln = texts(rows, rot, rot_why, keys, miss, live)
    rep += "LEAK " + " ".join(r.get("leak", "") for r in rows) + "\n"'
ASSIGN='            return x if re.fullmatch(r"[A-Za-z][\w.-]*", x) else "명령 이름 판정 불가"
>>>
            return x'
FIRST='            r["hits"] = sorted({u for u, _d, lvs in keys for v in vals if any(_sha(v) == _sha(lv) for lv in lvs)})
>>>
            r["hits"] = sorted({next((n for n, lvs in keys.items() for v in vals if any(_sha(v) == _sha(lv) for lv in lvs)), "")} - {""})'
NOCAP='            return await asyncio.wait_for(make(), SDK_S)
>>>
            return await make()'
TITLE='                    keys.append((f"OP {v.title}/{it.id}", f"OP {v.title} · {it.title}", vals))
>>>
                    keys = [k for k in keys if k[1] != f"OP {v.title} · {it.title}"] + [(f"OP {v.title}/{it.title}", f"OP {v.title} · {it.title}", vals)]
#---
            keys = [(f"OP {v}/{i}", f"OP {v} · {n}", vals)
                    for v, items in raw["vaults"].items() for i, (n, vals) in enumerate(_pairs(items))]
>>>
            keys = list({f"OP {v} · {n}": (f"OP {v}/{n}", f"OP {v} · {n}", vals)
                         for v, items in raw["vaults"].items() for n, vals in _pairs(items)}.values())
'
PATHON='                w = word(v["input"].get("command") or "")
>>>
                w = word(v["input"].get("command") or "") or os.path.basename(str(v["input"].get("file_path") or ""))'
want_mut() { [ "${FT_FOLLOWUP_MUT:-}" = 1 ] && return 0; [ -n "${FT_TEST_ONLY:-}" ] && ft_only mut; }  # 기본 실행에서는 변이를 돌리지 않는다(부하 30 에서 70초 안)
if [ -z "${FT_FOLLOWUP_UNDER_TEST:-}" ] && want_mut; then
  for name in leak assign first nocap title path; do
    cells=r2; [ "$name" = title ] || [ "$name" = path ] && cells=r3   # 변이는 그 칸만(하드 룰 22)
    case "$name" in
      leak) mut leak "$LEAK" ;;
      assign) mut assign "$ASSIGN" ;;
      first) mut first "$FIRST" ;;
      nocap) mut nocap "$NOCAP" ft_secret_followup_plan.py ;;
      title) mut title "$TITLE" ft_secret_followup_plan.py ;;
      path) mut path "$PATHON" ;;
    esac
    FT_FOLLOWUP_UNDER_TEST="$T/mut-$name" FT_TEST_ONLY="$cells" bash "${BASH_SOURCE[0]:-$0}" >"$T/m-$name.log" 2>&1
    [ $? -ne 0 ]; ck "변이 $name → 이 시험이 FAIL 로 잡음" $?
  done
fi

want_mut || echo "SKIP 변이 6종 — FT_FOLLOWUP_MUT=1 (또는 FT_TEST_ONLY=mut) 회차에서 돈다"
ft_only_report || fail=$((fail+1))
echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (secret-followup r1027)"; exit 0; }
echo "FAILED $fail"; exit 1
