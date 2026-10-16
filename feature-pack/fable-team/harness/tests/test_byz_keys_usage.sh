#!/usr/bin/env bash
# test_byz_keys_usage.sh — keys-usage.sh 시험 (R277 · 사용처 표 + 장부 «사용처» 칸).
# 가짜 gcloud/curl 스텁 + sentinel(SENTINEL_*) — 토큰이 argv·표·장부·출력·임시 파일 어디든 새면 FAIL. 실제 gcloud·curl·네트워크 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
S="$HERE/../../.claude/skills/byz-keys/scripts"
T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || bad "$1 (없음: $3)"; }
lacks() { printf '%s' "$2" | grep -qF -- "$3" && bad "$1 (있으면 안 됨: $3)" || ok "$1"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

mkdir -p "$T/bin" "$T/tmp" "$T/repo/gateway" "$T/repo/tests" "$T/repo/docs" "$T/repo/deploy"
export TMPDIR="$T/tmp"
cat > "$T/bin/gcloud" <<'STUB'
#!/usr/bin/env bash
[ -n "${STUB_AUDIT:-}" ] && printf 'gcloud %s\n' "$*" >> "$STUB_AUDIT"
case "$*" in "auth print-access-token"*) echo "SENTINEL_ACCESS_TOKEN"; exit 0;; esac
exit 1
STUB
cat > "$T/bin/curl" <<'STUB'
#!/usr/bin/env bash
[ -n "${STUB_AUDIT:-}" ] && printf 'curl %s\n' "$*" >> "$STUB_AUDIT"
hdr=$(cat)
[ "$hdr" = "Authorization: Bearer SENTINEL_ACCESS_TOKEN" ] && [ -n "${STUB_AUDIT:-}" ] && echo CURL_AUTH_OK >> "$STUB_AUDIT"
[ -n "${STUB_CURL_FAIL:-}" ] && exit 22
case "${STUB_CURL_MODE:-two}" in
  zero) echo '{}';;
  two) echo '{"timeSeries":[{"resource":{"labels":{"service":"speech.googleapis.com"}},"points":[{"value":{"int64Value":"120"}}]},{"resource":{"labels":{"service":"generativelanguage.googleapis.com"}},"points":[{"value":{"int64Value":"7"}}]}]}';;
esac
STUB
chmod +x "$T/bin/gcloud" "$T/bin/curl"

printf 'import os\nK = os.environ["DEEPGRAM_API_KEY"]\nURL = "https://api.deepgram.com/v1/listen"\n' > "$T/repo/gateway/a.py"
printf 'import os\nK = os.environ["DEEPGRAM_API_KEY"]\n' > "$T/repo/gateway/nohost.py"
printf 'def test_x():\n    assert "DEEPGRAM_API_KEY"\n' > "$T/repo/tests/test_a.py"
printf '# 문서\nDEEPGRAM_API_KEY 는 https://developers.deepgram.com 참고\n' > "$T/repo/docs/x.md"
printf 'secret: byz-dev-deepgram-api-key\n' > "$T/repo/deploy/secret.yaml"
printf 'import os\nG = os.environ["GOOGLE_API_KEY"]\nU = "https://speech.googleapis.com/v1/speech:recognize"\n' > "$T/repo/gateway/g.py"
git -C "$T/repo" init -q && git -C "$T/repo" add -A && git -C "$T/repo" -c user.name=t -c user.email=t@t commit -qm fixture
export PATH="$T/bin:$PATH" BYZ_KEYS_REPO="$T/repo" BYZ_KEYS_NOW=2026-10-16
L="$T/LEDGER.md"
printf '# 키 장부\n\n<!-- keys:begin -->\n| ENV(표준) | 옛 이름 | 제공사·종류·용도 | 로컬 | 1Password(develop) | SM dev | SM prod | Cloud Run 참조 | 코드 읽는 곳 | 사용처 | 마지막 교체 | 상태 |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n<!-- keys:end -->\n' > "$L"
for k in DEEPGRAM_API_KEY GOOGLE_API_KEY; do bash "$S/keys-add.sh" "$k" --ledger "$L" >/dev/null 2>&1; done
export STUB_AUDIT="$T/audit"; : > "$STUB_AUDIT"
sha_of() { python3 -I - "$1" <<'PY'
import hashlib, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
b, e = lines.index("<!-- usage:begin -->"), lines.index("<!-- usage:end -->")
inner = [l for l in lines[b + 1:e] if not l.startswith("- 전환 확인:")]
print(hashlib.sha256(("\n".join(inner) + "\n").encode()).hexdigest()[:12])
PY
}
cell() { grep -F "| $2 |" "$1" | awk -F' [|] ' '{print $10}'; }

echo "== 비밀 아닌 키(DEEPGRAM): 코드 기준 =="
bash "$S/keys-usage.sh" DEEPGRAM_API_KEY --use stt-deepgram --ledger "$L" >"$T/out" 2>"$T/err"; eq "usage rc=0" "$?" 0
TB="$T/usage/DEEPGRAM_API_KEY.md"; tb=$(cat "$TB")
has "머리: ENV" "$tb" "- ENV: DEEPGRAM_API_KEY"
has "머리: 생성(핀 고정)" "$tb" "- 생성: 2026-10-16 00:00 (도구 keys-usage.sh)"
has "머리: 기준 커밋 10자" "$tb" "- 기준 커밋: $(git -C "$T/repo" rev-parse HEAD | cut -c1-10)"
has "머리: 전환 확인 없음" "$tb" "- 전환 확인: 없음"
has "마커 begin" "$tb" "<!-- usage:begin -->"
has "마커 end" "$tb" "<!-- usage:end -->"
has "코드 파일 + 보내는 API" "$tb" "| gateway/a.py | 코드 | DEEPGRAM_API_KEY | api.deepgram.com |"
has "호스트 없는 파일 = 미확인(빈 칸 금지)" "$tb" "| gateway/nohost.py | 코드 | DEEPGRAM_API_KEY | 미확인 |"
has "시험 구분" "$tb" "| tests/test_a.py | 시험 |"
has "문서 구분 + 문서 호스트" "$tb" "| docs/x.md | 문서 | DEEPGRAM_API_KEY | developers.deepgram.com |"
has "SM 이름으로 찾은 파일" "$tb" "| deploy/secret.yaml | 코드 | byz-dev-deepgram-api-key |"
has "(b) 코드 기준 표시" "$tb" "코드의 호출 호스트(감사 기록 없음"
has "(b) 호스트 행(호출 수 미상)" "$tb" "| api.deepgram.com | — |"
dc=$(cell "$L" DEEPGRAM_API_KEY)
has "장부 칸 형식" "$dc" "용도=stt-deepgram · API=api.deepgram.com · 표=usage/DEEPGRAM_API_KEY.md@2026-10-16#"
eq "장부 sha12 = 마커 사이 sha(독립 계산)" "${dc##*#}" "$(sha_of "$TB")"
eq "lint rc=0" "$(bash "$S/keys-lint.sh" "$L" >/dev/null 2>&1; echo $?)" 0
eq "audit: 토큰 호출·curl 0 (코드 기준 키)" "$(grep -c '^curl\|^gcloud' "$STUB_AUDIT")" 0

echo "== 손으로 고친 부분 보존 · 마커 사이 변조는 어긋남 =="
printf '\n## 손 절\nops 메모\n' >> "$TB"
sed -i.bak 's/^- 전환 확인: 없음$/- 전환 확인: 2026-10-16 10:00 · 새 키 · 증거 mbox #1/' "$TB" && rm -f "$TB.bak"
eq "전환 확인·손 절을 고쳐도 sha 불변" "$(sha_of "$TB")" "${dc##*#}"
bash "$S/keys-usage.sh" DEEPGRAM_API_KEY --ledger "$L" >/dev/null 2>&1; eq "재생성 rc=0(용도 칸 보존)" "$?" 0
has "재생성 뒤 전환 확인 줄 보존" "$(cat "$TB")" "- 전환 확인: 2026-10-16 10:00 · 새 키 · 증거 mbox #1"
has "재생성 뒤 손 절 보존" "$(cat "$TB")" "ops 메모"
has "재생성 뒤 용도 보존" "$(cell "$L" DEEPGRAM_API_KEY)" "용도=stt-deepgram"
eq "재생성 뒤 sha = 새 표 sha" "$(cell "$L" DEEPGRAM_API_KEY | sed 's/.*#//')" "$(sha_of "$TB")"
cp "$TB" "$T/tb.keep"; sed -i.bak 's/^- 기준 커밋: .*/- 기준 커밋: 0000000000/' "$TB" && rm -f "$TB.bak"
[ "$(sha_of "$TB")" != "$(cell "$L" DEEPGRAM_API_KEY | sed 's/.*#//')" ] && ok "마커 사이 변조 → sha 어긋남" || bad "마커 사이 변조 → sha 어긋남"

echo "== Google 키: Monitoring =="
: > "$STUB_AUDIT"
bash "$S/keys-usage.sh" GOOGLE_API_KEY --use gemini-stt --display-name byz-gemini-key --ledger "$L" >"$T/out2" 2>"$T/e2"; eq "Google usage rc=0" "$?" 0
gc=$(cell "$L" GOOGLE_API_KEY)
has "API 칸 = 그 키 코드 파일의 호출 호스트(키별 근거)" "$gc" "API=speech.googleapis.com ·"
tg=$(cat "$T/usage/GOOGLE_API_KEY.md")
has "(b) 고정 문구: 프로젝트 합 · 키 분리 불가" "$tg" "기준: 프로젝트 합 · 키 분리 불가"
has "(b) 프로젝트 service 호출 수" "$tg" "| speech.googleapis.com | 120 |"
has "(b) 다른 service 도 합에 포함" "$tg" "| generativelanguage.googleapis.com | 7 |"
has "(a) Google 코드 파일 + 보내는 API" "$tg" "| gateway/g.py | 코드 | GOOGLE_API_KEY | speech.googleapis.com |"
au=$(cat "$STUB_AUDIT")
has "curl: Monitoring URL" "$au" "https://monitoring.googleapis.com/v3/projects/byz-agents-484214/timeSeries"
lacks "curl: credential_id 필터 없음(라벨 없음)" "$au" "credential_id"
has "curl: 헤더는 stdin(@-)" "$au" "-H @-"
has "인증 헤더가 stdin 으로 도달" "$au" "CURL_AUTH_OK"
lacks "argv·audit 에 토큰 0" "$au" "SENTINEL"

echo "== 실패는 raise · 장부·표 불변 =="
rm -f "$T/usage/GOOGLE_API_KEY.md"; cp "$L" "$T/before.md"
STUB_CURL_FAIL=1 bash "$S/keys-usage.sh" GOOGLE_API_KEY --use gemini-stt --ledger "$L" >/dev/null 2>"$T/e3"; eq "Monitoring 실패 rc=2" "$?" 2
has "못 물었다 문구" "$(cat "$T/e3")" "못 물었다"
eq "실패: 장부 불변" "$(cmp -s "$L" "$T/before.md"; echo $?)" 0
eq "실패: 표 미생성(빈 표 금지)" "$([ -e "$T/usage/GOOGLE_API_KEY.md" ] && echo yes || echo no)" no
STUB_CURL_MODE=zero bash "$S/keys-usage.sh" GOOGLE_API_KEY --use gemini-stt --ledger "$L" >/dev/null 2>&1; eq "호출 0 rc=0" "$?" 0
has "호출 0 = 표에 (호출 기록 0) 행" "$(cat "$T/usage/GOOGLE_API_KEY.md")" "| (호출 기록 0) | 0 |"
has "호출 0 이어도 API 칸은 코드 근거" "$(cell "$L" GOOGLE_API_KEY)" "API=speech.googleapis.com"
bash "$S/keys-usage.sh" NOPE_API_KEY --use x --ledger "$L" >/dev/null 2>"$T/e4"; eq "장부에 없는 ENV rc=2" "$?" 2
has "행 없음 문구" "$(cat "$T/e4")" "행 없음"
bash "$S/keys-add.sh" FRESH_API_KEY --ledger "$L" >/dev/null 2>&1
bash "$S/keys-usage.sh" FRESH_API_KEY --ledger "$L" >/dev/null 2>"$T/e5"; eq "--use 없는 첫 조사 rc=2" "$?" 2
bash "$S/keys-usage.sh" FRESH_API_KEY --use "Bad Use" --ledger "$L" >/dev/null 2>&1; eq "kebab 아닌 --use rc=2" "$?" 2

echo "== 실행 경계 =="
bound=$(PYTHONPATH="$S" python3 -B -c '
import keys_collect as kc
good = [["curl", "https://monitoring.googleapis.com/v3/projects/" + kc.PROJECT + "/timeSeries", "-sS", "-H", "@-"], ["gcloud", "auth", "print-access-token"]]
bad = [["curl", "https://example.com/x"], ["curl", "https://monitoring.googleapis.com/v3/projects/other/timeSeries"],
       ["gcloud", "auth", "print-identity-token"], ["gcloud", "services", "api-keys", "get-key-string", "x"],
       ["gcloud", "services", "api-keys", "create"]]
for a in good: kc.check_argv(a)
n = 0
for a in bad:
    try:
        kc.check_argv(a); n += 1
    except kc.KeysError:
        pass
print("bad_passed=%d" % n)')
eq "허용 2종 통과 · 값 동사·다른 URL 5종 거절" "$bound" "bad_passed=0"

echo "== sentinel 0 =="
leak=$(grep -rl 'SENTINEL' "$L" "$T/usage" "$T/out" "$T/out2" "$T/err" "$T/e1" "$T/e2" "$T/e3" "$T/tmp" "$S/__pycache__" 2>/dev/null || true)
eq "sentinel 파일 0" "$leak" ""

echo "---"; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL=$fail"
exit "$fail"
