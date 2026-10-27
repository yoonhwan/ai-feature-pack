#!/usr/bin/env bash
# test_secret_followup_r1027.sh — ft_secret_followup.py 셋 답(시각·지문·삭제 계획) · 값 0 (r1027 · 계약 C1~C4)
# 격리: 임시 HOME(합성 session jsonl · 합성 점검 표 · 합성 키 장부 · 가짜 볼트 JSON · 가짜 tmux) — 실 기록·실 볼트·실 tmux 읽기 0 · 쓰기 0.
# 변이 «값 출력 되살림» 은 mktemp 사본에서만 — 이 시험이 FAIL 로 잡는지 본다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
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
printf '{"type":"assistant","timestamp":"2026-11-01T09:00:00Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"curl -H x"}}]}}\n' > "$LIVEJ".tmp
cat "$LIVEJ".tmp >> "$LIVEJ"; rm -f "$LIVEJ".tmp
printf '{"note":"PGPASSWORD=%s"}\n' "$V3" > "$DEADJ"
printf '{"out":"%s"}\n' "$V2" >> "$DEADJ"
printf '{"note":"no timestamp line"}\n' >> "$LIVEJ"  # 줄 시각 없음 → mtime(최근) = 교체 뒤
touch -t 202001010000 "$DEADJ"                       # 최근 쓰기 아님

# ── 가짜 tmux (살아 있는 pane cwd 1개) · 가짜 볼트(살아 있는 키 1 · 옛 키 2)
printf '#!/usr/bin/env bash\necho "sess1\t%s"\n' "$DIR" > "$T/tmux"; chmod +x "$T/tmux"
printf '{"GH_TOKEN":"%s","OLD_A":"%s","OLD_B":"%s"}' "$V1" "$O1" "$O2" > "$T/vault.json"

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
  for n in GH_TOKEN OLD_A OLD_B; do
    printf '| %s | — | gh | 있음 | 있음 | — | — | — | ENV 1 | 미조사 | 교체 2026-10-25 12:00:00 | 정상 |\n' "$n"
  done
} > "$T/keys.md"
NOROT="$T/keys-norot.md"; grep -v '교체 2026' "$T/keys.md" > "$NOROT"

fail=0; out=""; err=""; rc=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:200} err=${err:0:200}"; fail=$((fail+1)); fi; }
run() { out="$(python3 "$PY" "$@" 2>"$T/e")"; rc=$?; err="$(cat "$T/e")"; }
novalue() { ! grep -q -e ZQ7x "$@" \
  && ! grep -q -e "$(printf '%s' "$V1" | shasum -a 256 | cut -c1-8)" -e "$(printf '%s' "$V3" | shasum -a 256 | cut -c1-8)" "$@"; }

python3 -m py_compile "$PY" "$BIND/ft_secret_followup_plan.py"; ck "py_compile (도구·짝)" $?
[ "$(wc -l < "$PY")" -le 200 ] && [ "$(wc -l < "$BIND/ft_secret_followup_plan.py")" -le 200 ]; ck "200줄 상한(도구·짝)" $?

# C1 — 시각 전/뒤 셈 · 뒤인 행의 도구 이름 · 줄 시각 없음 = mtime
FT_FOLLOWUP_TMUX="$T/tmux" FT_FOLLOWUP_VAULT_JSON="$T/vault.json" \
  run --triage "$T/TRIAGE.md" --keys-log "$T/keys.md" --report "$T/rep.md" --plan "$T/plan.md"
[ "$rc" = 0 ] && [ "$(grep -c . <<<"$out")" = 1 ]; ck "rc0 · 표준출력 1줄" $?
grep -q 'followup=6 front=3 back=2 same=0 unknown=1' <<<"$out"; ck "C1 합계 front=3 back=2 unknown=1(줄 번호 초과)" $?
grep -q '교체 시각: 2026-10-25 12:00:00' "$T/rep.md"; ck "C1 교체 시각을 원장에서 읽음" $?
grep -q 'live.jsonl:2.*assistant · Bash() curl' "$T/rep.md"; ck "C1 교체 뒤 행 = 도구·명령 첫 낱말" $?
grep -q 'live.jsonl:3.*(mtime)' "$T/rep.md"; ck "C1 줄 시각 없음 → mtime 대체 표시" $?
grep -q '줄 번호가 파일 길이 넘음' <<<"$(cat "$T/rep.md")$(cat "$T/e")" || grep -q 'unknown=1' <<<"$out"; ck "C1 못 읽는 줄 = 판정 불가(조용한 생략 0)" $?

# C2 — 살아 있는 키 일치 1 · 옛 키 2 · 볼트 실패 = 판정 불가
grep -q '| GH_TOKEN | 살아 있음(일치) | 1 |' "$T/rep.md"; ck "C2 살아 있는 키 = 일치 1줄" $?
grep -q '| OLD_A | 옛 키(일치 0) | 0 |' "$T/rep.md" && grep -q '| OLD_B | 옛 키(일치 0) | 0 |' "$T/rep.md"; ck "C2 옛 키 2" $?
grep -q '일치 키 1 · 옛 키 2 (볼트 키 3)' "$T/rep.md"; ck "C2 합계 1/2/3" $?
env -u OP_SERVICE_ACCOUNT_TOKEN_DEVELOP -u FT_FOLLOWUP_VAULT_JSON python3 "$PY" --triage "$T/TRIAGE.md" \
  --keys-log "$T/keys.md" --report "$T/rep2.md" >"$T/o2" 2>&1
grep -q '판정 불가 — 볼트 토큰' "$T/rep2.md" && grep -q 'live_keys=0 keys=0' "$T/o2"; ck "C2 볼트 읽기 실패 = 판정 불가 1줄 · 비교 0" $?

# C3 — 삭제 계획: 되돌림 없음 머리 줄 · 살아 있는 세션 = «다음 닫힘 뒤» · 실행 0
grep -q '되돌림 없음 — 지운 기록은 복구 0' "$T/plan.md"; ck "C3 머리 줄 «되돌림 없음»" $?
grep -q "다음 닫힘 뒤 (살아 있는 세션 기록)" "$T/plan.md" && grep -q "rm -f '$LIVEJ'" "$T/plan.md"; ck "C3 살아 있는 세션 기록 = 다음 닫힘 뒤 칸" $?
grep -q "## 삭제 명령 (실행 0 · 글자만)" "$T/plan.md" && grep -q "rm -f '$DEADJ'" "$T/plan.md"; ck "C3 닫힌 세션 = 삭제 명령 칸" $?
[ -f "$LIVEJ" ] && [ -f "$DEADJ" ]; ck "C3 실행 0 (파일 그대로)" $?
grep -q 'live_files=1' <<<"$out"; ck "C3 살아 있는 파일 1" $?

# C1 — 교체 시각을 못 찾으면 판정 불가 1줄로 끝
FT_FOLLOWUP_TMUX="$T/tmux" FT_FOLLOWUP_VAULT_JSON="$T/vault.json" \
  run --triage "$T/TRIAGE.md" --keys-log "$NOROT" --report "$T/rep3.md"
grep -q '판정 불가 — 교체 시각 없음' "$T/rep3.md" && grep -q 'front=0 back=0' <<<"$out"; ck "C1 교체 시각 없음 = 판정 불가 1줄" $?

# C4 — 출력(보고·계획·stdout·stderr) 어디에도 값·해시 8자 0
novalue "$T/rep.md" "$T/plan.md" "$T/e" <<<"$out"; ck "C4 값·해시 8자 0 (보고·계획·stdout·stderr)" $?

# usage · 쓰기 실패
python3 "$PY" --triage "$T/TRIAGE.md" >/dev/null 2>&1; rc=$?; [ "$rc" = 2 ]; ck "usage 없으면 rc=2" $?
mkdir -p "$T/ro"; chmod 500 "$T/ro"
python3 "$PY" --triage "$T/TRIAGE.md" --keys-log "$T/keys.md" --report "$T/ro/x/y.md" >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ]; ck "보고 파일 못 쓰면 rc=4" $?
chmod 700 "$T/ro"

# 짝 사본 cmp0
KIT="$HARNESS/kit/fable-team/bin"
if [ "$BIND" = "$HARNESS/bin" ]; then
  cmp -s "$PY" "$KIT/ft_secret_followup.py" && cmp -s "$BIND/ft_secret_followup_plan.py" "$KIT/ft_secret_followup_plan.py"
  ck "kit 짝 cmp0 (도구·짝)" $?
fi

# 변이 — «값 출력 되살림»(보고에 값 첫 4자) → 이 시험이 FAIL 로 잡아야 한다
mut() {  # mut <이름> <patch 코드> — 코드는 «A >>\n B» 쌍, 여러 쌍은 줄 «#---» 로 잇는다
  local d="$T/mut-$1"; mkdir -p "$d"
  cp -p "$BIND"/ft_secret_followup*.py "$BIND"/ft_secret_*.py "$d/"   # 의존 모듈까지(못 읽는 사본으로 «우연히» FAIL 하지 않게)
  python3 - "$d/ft_secret_followup.py" "$2" <<'EOF'
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
LEAK='            r["hit"] = next((n for n, lvs in keys.items() for v in vals if any(_sha(v) == _sha(lv) for lv in lvs)), "")
>>>
            r["hit"] = next((n for n, lvs in keys.items() for v in vals if any(_sha(v) == _sha(lv) for lv in lvs)), "")
            r["leak"] = " ".join(v[:12] for v in vals)
#---
    rep, pln = texts(rows, rot, rot_why, keys, key_why, live)
>>>
    rep, pln = texts(rows, rot, rot_why, keys, key_why, live)
    rep += "LEAK " + " ".join(r.get("leak", "") for r in rows) + "\n"'
if [ -z "${FT_FOLLOWUP_UNDER_TEST:-}" ]; then
  mut leak "$LEAK"
  FT_FOLLOWUP_UNDER_TEST="$T/mut-leak" bash "${BASH_SOURCE[0]:-$0}" >"$T/m-leak.log" 2>&1
  [ $? -ne 0 ]; ck "변이 «값 출력 되살림» → 이 시험이 FAIL 로 잡음" $?
fi

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (secret-followup r1027)"; exit 0; }
echo "FAILED $fail"; exit 1
