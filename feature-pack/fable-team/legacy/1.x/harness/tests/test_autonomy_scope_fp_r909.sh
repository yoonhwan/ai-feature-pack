#!/usr/bin/env bash
# test_autonomy_scope_fp_r909.sh — r909: 범위 분류기 오탐 다섯 칸 (칸1 셸 set 문맥 · 칸2 credential 시험 파일 경로 · 칸3 .env.example 이름만 · 칸4 echo 이름표 변수 · 칸5 원문 없음)
# 임시 origin(bare)+clone · gh·실 원격·실 Redis 0 · 변이는 사본($T/mut)에서만 고친다
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
CLS="$BIN/autonomy_scope_classify.py"; JUDGE="$BIN/ft_secret_judge.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope"; export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"
echo m1 > "$W/m1.txt"; cm "$W" m1; git -C "$W" push -q origin main; git -C "$W" fetch -q origin; BASE="$M0"   # main 을 한 칸 전진 → BASE 가지는 main 조상 아님
printf 'MULTI="first\nlast"\nOK_KEY=\n' > "$W/.env.example"; mkdir -p "$W/ci"; printf 'jobs:\n  b:\n    steps:\n      - run: |\n          set\n' > "$W/ci/y5.yml"; cm "$W" m2; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
MBASE="$(git -C "$W" rev-parse main)"   # main 위에서 «한 줄만» 바꾸는 가지의 시작점(칸 3 반례)
mkf() {  # mkf <가지> <시작점> <경로> <줄…> — 파일 하나 쓰고 커밋 → SHA
  local br="$1" from="$2" p="$3"; shift 3
  git -C "$W" checkout -q -B "$br" "$from"; mkdir -p "$W/$(dirname "$p")"
  printf '%s\n' "$@" > "$W/$p"; cm "$W" "$br"; SHA="$(sha "$W" HEAD)"
}
cls() { out="$(python3 "$CLS" classify "$1" --repo "$W" --scope S1 2>&1)"; rc=$?; }
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }

python3 -I -m py_compile "$CLS"; ck "py_compile classify" $?
# 칸 1 ⓐ — .py 바뀐 줄의 set( 는 셸 set 이 아니다(ccu 3394·3410 오탐)
mkf a1 "$BASE" app/gpu.py 'tags = set(tags)' '_x = (' '    set(LIVE_GPUS)' ')'
cls "$SHA"; want "ⓐ .py set(tags)·set(LIVE_GPUS) → FORBID secret 0" 0 "CLASS code"
mkf a2 "$BASE" design/util.py 'def f(xs):' '    return set(xs)'
cls "$SHA"; want "ⓐ design/*.py(확장자 .py = code) set( → FORBID secret 0" 0 "CLASS code"
# 칸 1 ⓑ — 셸 문맥의 «set 단독» 은 지금처럼 FORBID
mkf b1 "$BASE" scripts/s.sh '#!/bin/sh' 'set'
cls "$SHA"; want "ⓑ .sh 의 set 단독 → FORBID secret" 3 "FORBID kind=secret"
mkf b2 "$BASE" docs/envdump.md '```bash' 'set' '```'
cls "$SHA"; want "ⓑ 문서 bash 울타리 안 set 단독 → FORBID secret" 3 "FORBID kind=secret"
printf 'set\n' > "$T/plan-set.txt"; out="$(python3 "$JUDGE" --plan "$T/plan-set.txt" 2>&1)"; rc=$?
want "ⓑ h 계획(set 단독) → reject rc1" 1 "reject"
# 칸 1 ⓒ — set -euo pipefail 통과 · set -x 는 plan 판정 그대로 · 문서 비셸 울타리는 판정 밖
mkf c1 "$BASE" scripts/strict.sh '#!/bin/sh' 'set -euo pipefail' 'echo hi'
cls "$SHA"; want "ⓒ .sh set -euo pipefail → FORBID 0" 0 "CLASS code"
mkf c2 "$BASE" scripts/trace.sh '#!/bin/sh' 'set -x' 'echo hi'
cls "$SHA"; want "ⓒ .sh set -x → FORBID secret(값 추적 출력)" 3 "FORBID kind=secret 추가 줄: set -x"
mkf c3 "$BASE" docs/hint.md '```python' 'x = set(tags)' '```'
cls "$SHA"; want "ⓒ 문서 python 울타리 안 set( → FORBID secret 0" 0 "CLASS docs"
mkf c4 "$BASE" docs/demo.md '```python' 'import os' 'os.system("set")' '```'
cls "$SHA"; want "r5 반례 문서 python 울타리의 os.system(\"set\") → FORBID secret(리터럴 안 set 은 판정)" 3 "FORBID kind=secret"
mkf c5 "$BASE" docs/demo2.md '```ts' 'const v = set(tags)' 'run("set")' '```'
cls "$SHA"; want "r5 문서 ts 울타리 — set( 는 가리고 run(\"set\") 리터럴은 판정 → FORBID secret" 3 "FORBID kind=secret"
mkf c6 "$BASE" docs/demo3.md '```text' 'set' '```'
cls "$SHA"; want "r5 문서 비코드 언어(text) 울타리의 set 단독 → FORBID secret(기준판 동작)" 3 "FORBID kind=secret"
# 칸 2 ⓓ — 시험 파일 경로는 credential 낱말 금지 밖(room 3395)
mkf d1 "$BASE" clients/web/__tests__/auth/credential-cookie-lifecycle.test.ts 'export const c = 1'
cls "$SHA"; want "ⓓ __tests__/*.test.ts credential → key FORBID 0" 0 "CLASS code"
mkf d2 "$BASE" tests/test_credential_x.py 'x = 1'
cls "$SHA"; want "ⓓ tests/test_credential_x.py → key FORBID 0" 0 "CLASS code"
# 칸 2 ⓔ — 시험 아닌 경로·시험 폴더 안 .env 는 그대로 FORBID
mkf e1 "$BASE" shared/credential_store.py 'x = 1'
cls "$SHA"; want "ⓔ shared/credential_store.py(시험 아님) → FORBID key" 3 "FORBID kind=key"
mkf e2 "$BASE" tests/.env 'API_KEY=FAKE'
cls "$SHA"; want "ⓔ tests/.env(경로 금지 규칙이 먼저) → FORBID key" 3 "FORBID kind=key"
# 칸 1+2 ⓕ — 시험 파일 «내용» 의 비밀 값 검사는 경로 예외와 무관
mkf f1 "$BASE" tests/test_leak.py '-----BEGIN RSA PRIVATE KEY-----'
cls "$SHA"; want "ⓕ 시험 파일 내용의 키 원문 → FORBID secret" 3 "FORBID kind=secret"
# 칸 3 ⓖ — .env.example 은 «이름만» 추가하면 통과 · 실값은 FORBID
mkf g1 "$BASE" .env.example '# 견본' 'NEW_KEY=' 'OTHER_KEY=<your-key>'
cls "$SHA"; want "ⓖ .env.example 이름만(빈 칸·자리표) → FORBID key 0" 0 "CLASS code"
mkf g2 "$BASE" .env.example 'NEW_KEY=abc123'
cls "$SHA"; want "ⓖ .env.example 실값 → FORBID key" 3 "FORBID kind=key"
mkf g3 "$BASE" .env.sample 'NEW_KEY=<x>'
cls "$SHA"; want "ⓖ .env.sample 이름만 → FORBID key 0" 0 "CLASS code"
mkf g4 "$BASE" .env.template 'NEW_KEY='
cls "$SHA"; want "ⓖ .env.template 이름만 → FORBID key 0" 0 "CLASS code"
# 칸 4 ⓗ — r4(arch 143 · 판정 3회 보류): 칸4 는 범위에서 뺐다 = 기준판 동작. 이름표 echo 도 FORBID 유지(범위 밖 · 별 카드 후보)
mkf h1 "$BASE" scripts/meta.sh '#!/bin/sh' 'OP_SECRET_ITEM_NAME=op://develop/toss/item' 'echo "$OP_SECRET_ITEM_NAME"'
cls "$SHA"; want "ⓗ echo \$OP_SECRET_ITEM_NAME → FORBID secret 유지(칸4 범위 밖)" 3 "FORBID kind=secret"
mkf h2 "$BASE" scripts/value.sh '#!/bin/sh' 'echo "$TOSS_SECRET_KEY"'
cls "$SHA"; want "ⓗ echo \$TOSS_SECRET_KEY → FORBID secret" 3 "FORBID kind=secret"
mkf h3 "$BASE" scripts/mixed.sh '#!/bin/sh' 'OP_SECRET_ITEM_NAME=op://develop/toss/item' 'printf "%s" "$OP_SECRET_ITEM_NAME $TOSS_SECRET_KEY"'
cls "$SHA"; want "ⓗ 이름표+실값 섞임 → FORBID secret" 3 "FORBID kind=secret"
# 칸 5(카드 증거 줄 틀 문장 · graphics) — 재현 원문 없음 → 시험 칸 없음(납품 보고에 «원문 필요»)

# DA⑥ r1 반례 4묶음(기대 = FORBID · r2 에서 좁힌 결과)
# ① 반례 1 — 셔뱅 있는 확장자 없는 파일 · yaml run: 블록 · 코드 문자열 리터럴 속 set
mkf i1 "$BASE" tools/env.dump '#!/bin/sh' 'set'
cls "$SHA"; want "반례1 ⓐ 확장자 없는 셔뱅 파일의 set 단독 → FORBID secret" 3 "FORBID kind=secret"
mkf i2 "$BASE" ci/pipeline.yml 'jobs:' '  build:' '    steps:' '      - run: |' '          set'
cls "$SHA"; want "반례1 ⓑ yaml run: 블록 안 set 단독 → FORBID secret" 3 "FORBID kind=secret"
mkf i3 "$BASE" app/run.py 'import os' 'os.system("set")'
cls "$SHA"; want "반례1 ⓒ .py 문자열 리터럴 속 set → FORBID secret" 3 "FORBID kind=secret"
mkf i4 "$BASE" pkg/pack.py '#!/bin/sh' 'set(tags)'
cls "$SHA"; want "반례1 ⓓ .py 라도 셔뱅 있으면 셸 문맥(set( 도 판정) → FORBID secret" 3 "FORBID kind=secret"
# ② 반례 2 — 시험 경로 예외는 코드 파일 이름뿐 · 값 파일(.json·secrets/)은 예외 0
mkf j1 "$BASE" tests/credential.json '{"api_key": "REALVALUE123"}'
cls "$SHA"; want "반례2 ⓓ tests/credential.json 실값 → FORBID key" 3 "FORBID kind=key"
mkf j2 "$BASE" tests/secrets/credential.json '{"k": "v"}'
cls "$SHA"; want "반례2 ⓔ tests/secrets/credential.json → FORBID key(secrets/ 규칙 넓힘)" 3 "FORBID kind=key"
mkf j3 "$BASE" tests/credential_test.json '{"k": "v"}'
cls "$SHA"; want "반례2 ⓕ 시험 꼴 이름이라도 .json 이면 FORBID key" 3 "FORBID kind=key"
mkf j4 "$BASE" tests/secrets/credential.test.py 'x = 1'
cls "$SHA"; want "반례2 ⓖ 시험 꼴 이름이라도 secrets/ 경로면 FORBID key" 3 "FORBID kind=key"
# ③ 반례 3 — .env.example 의 여러 줄 따옴표 값 «안» 에 끼어든 줄 = 값의 일부
mkf k1 "$MBASE" .env.example 'MULTI="first' '#둘째줄' 'last"' 'OK_KEY='
cls "$SHA"; want "반례3 ⓗ 따옴표 값 «안» 에 끼어든 줄 하나(추가 줄 = 그 #줄뿐) → FORBID key" 3 "FORBID kind=key"
mkf k2 "$BASE" .env.example 'MULTI="first' 'last"'
cls "$SHA"; want "반례3 ⓘ 여러 줄 따옴표에 실값 → FORBID key" 3 "FORBID kind=key"
mkf k3 "$BASE" .env.example 'MULTI="<your-' 'key>"' 'OK_KEY='
cls "$SHA"; want "반례3 ⓙ 여러 줄 따옴표(시작 줄 파싱 실패)는 자리표뿐이어도 → FORBID key(닫힌 쪽)" 3 "FORBID kind=key"
# ④ 반례 4 — r4: 칸4 는 기준판 동작(echo/printf 로 비밀 낱말 변수 출력 = FORBID). DA r2·r3 반례 전 꼴 + 원래 오탐 사례 전부 FORBID
mkf l1 "$BASE" scripts/id.sh '#!/bin/sh' 'API_SECRET_ID=abc' 'printf "%s\n" "$API_SECRET_ID"'
cls "$SHA"; want "반례4 ⓚ _ID 는 이름표 목록 밖 → FORBID secret" 3 "FORBID kind=secret"
mkf l2 "$BASE" scripts/nodef.sh '#!/bin/sh' 'echo "$OP_SECRET_ITEM_NAME"'
cls "$SHA"; want "반례4 ⓛ 대입 없는 이름표 변수(다른 파일·환경에서 옴) → FORBID secret" 3 "FORBID kind=secret"
mkf l3 "$BASE" scripts/meta_assigned.sh '#!/bin/sh' 'OP_SECRET_ITEM_NAME=$TOSS_SECRET_KEY' 'echo "$OP_SECRET_ITEM_NAME"'
cls "$SHA"; want "반례4 ⓜ 이름표 변수에 값(\$…)이 들어간 대입 → FORBID secret" 3 "FORBID kind=secret"
mkf l4 "$BASE" scripts/meta_q.sh '#!/bin/sh' 'OP_SECRET_ITEM_NAME="$TOSS_SECRET_KEY"' 'echo "$OP_SECRET_ITEM_NAME"'
cls "$SHA"; want "반례4 ⓝ 따옴표 대입(\$ 포함) → FORBID secret" 3 "FORBID kind=secret"
mkf l5 "$BASE" scripts/meta_hop.sh '#!/bin/sh' 'A=$TOSS_SECRET_KEY' 'OP_SECRET_ITEM_NAME=$A' 'echo "$OP_SECRET_ITEM_NAME"'
cls "$SHA"; want "반례4 ⓞ 다단계 파생 → FORBID secret" 3 "FORBID kind=secret"
mkf l6 "$BASE" scripts/meta_ind.sh '#!/bin/sh' 'OP_SECRET_ITEM_NAME=TOSS_SECRET_KEY' 'echo "$OP_SECRET_ITEM_NAME ${!OP_SECRET_ITEM_NAME}"'
cls "$SHA"; want "반례4 ⓟ \${!X} 간접 확장 → FORBID secret" 3 "FORBID kind=secret"
mkf l7 "$BASE" scripts/meta_eval.sh '#!/bin/sh' 'OP_SECRET_ITEM_NAME=abc' 'eval "Z=\$TOSS_SECRET_KEY"' 'echo "$OP_SECRET_ITEM_NAME"'
cls "$SHA"; want "반례4 ⓠ eval 이 있는 글 → FORBID secret" 3 "FORBID kind=secret"
mkf l8 "$BASE" scripts/meta_src.sh '#!/bin/sh' 'OP_SECRET_ITEM_NAME=abc' 'source ./other.sh' 'echo "$OP_SECRET_ITEM_NAME"'
cls "$SHA"; want "반례4 ⓡ 다른 파일 source 가 있는 글 → FORBID secret" 3 "FORBID kind=secret"
# (cat "$X_FILE" · DEFERRED 파생 echo · 다단계 파생(마지막 이름에 비밀 낱말 없음)은 기준판도 통과 — 칸4 범위 밖 · 시험 칸 없음 · arch 143 에 보고)
mkf l10 "$BASE" scripts/dup.sh '#!/bin/sh' 'OP_SECRET_ITEM_NAME=a' 'OP_SECRET_ITEM_NAME=b' 'echo "$OP_SECRET_ITEM_NAME"'
cls "$SHA"; want "반례4 ⓣ 대입이 둘 이상 → FORBID secret(하나뿐일 때만 양성)" 3 "FORBID kind=secret"
mkf l11 "$BASE" scripts/cmt.sh '#!/bin/sh' '# OP_SECRET_ITEM_NAME=$TOSS_SECRET_KEY' 'OP_SECRET_ITEM_NAME=op://develop/toss/item' 'echo "$OP_SECRET_ITEM_NAME"'
cls "$SHA"; want "ⓤ 주석 줄 대입 + 이름표 echo → FORBID secret 유지" 3 "FORBID kind=secret"
mkf l12 "$BASE" scripts/file_name.sh '#!/bin/sh' 'API_SECRET_FILE=/tmp/x' 'echo "$API_SECRET_FILE"'
cls "$SHA"; want "반례4 ⓥ _FILE 은 이름표 밖 → FORBID secret" 3 "FORBID kind=secret"
# ⑤ r3 반례 — 자료 확장자 통째 제외 삭제 · YAML 여러 꼴 · 셔뱅 있는 문서 · dotenv 줄별
mkf m1 "$BASE" ci/task.txt 'printf "%s" "$TOSS_SECRET_KEY"'
cls "$SHA"; want "r3 반례1 .txt 자료 확장자에 printf 비밀 → FORBID secret" 3 "FORBID kind=secret"
mkf m2 "$BASE" ci/y1.yml 'steps:' '  - run: |-' '      set'
cls "$SHA"; want "r3 반례2 yaml run: |- 블록 안 set → FORBID secret" 3 "FORBID kind=secret"
mkf m2b "$BASE" ci/y1b.yml 'steps:' '  - run: >-' '      set'
cls "$SHA"; want "r3 반례2 yaml run: >- 블록 안 set → FORBID secret" 3 "FORBID kind=secret"
mkf m2c "$BASE" ci/y1c.yml 'steps:' '  - run: | # c' '      set'
cls "$SHA"; want "r3 반례2 yaml run: | # c 블록 안 set → FORBID secret" 3 "FORBID kind=secret"
mkf m3 "$BASE" ci/y2.yml 'x:' '  "run": "set"'
cls "$SHA"; want "r3 반례2 yaml \"run\": \"set\" → FORBID secret" 3 "FORBID kind=secret"
mkf m4 "$BASE" ci/y3.yml 'x:' '  script:' '    - set'
cls "$SHA"; want "r3 반례2 yaml script: 목록 - set → FORBID secret" 3 "FORBID kind=secret"
mkf m5 "$BASE" ci/y4.yml 'x:' '  script: [set]'
cls "$SHA"; want "r3 반례2 yaml script: [set] → FORBID secret" 3 "FORBID kind=secret"
mkf m6 "$BASE" tools/dump.md '#!/bin/sh' 'set'
cls "$SHA"; want "r3 반례3 .md 라도 셔뱅 있으면 셸 문맥 → FORBID secret" 3 "FORBID kind=secret"
git -C "$W" checkout -q -B m8 "$MBASE"; printf '%s\n' '# 주석만 추가' >> "$W/ci/y5.yml"; cm "$W" m8; SHA="$(sha "$W" HEAD)"
cls "$SHA"; want "r3 새 오탐 yaml 기존 set 블록은 두고 주석 줄만 추가 → FORBID secret 0" 0 "CLASS code"
mkf n1 "$MBASE" .env.example 'API_KEY=real' 'API_KEY=<placeholder>'
cls "$SHA"; want "r3 반례4 dotenv 같은 키 실값 + 자리표 → 줄별 판정 FORBID key" 3 "FORBID kind=key"
mkf n2 "$MBASE" .env.example "KEY=\"''\""
cls "$SHA"; want "r3 반례4 KEY=\"''\" 는 빈 값 아님 → FORBID key" 3 "FORBID kind=key"
mkf n3 "$MBASE" .env.example 'KEY="" # 주석' 'K2=<x>'
cls "$SHA"; want "r3 dotenv 따옴표 뒤 # 주석은 허용 → FORBID key 0" 0 "CLASS code"

# 변이 — 사본에서만 고친다(원본 무변경)
MUT="$T/mut"
mut() { rm -rf "$MUT"; mkdir -p "$MUT"; cp "$BIN"/autonomy_scope_*.py "$BIN"/ft_secret_*.py "$MUT"/; }
mutcls() { out="$(python3 "$MUT/autonomy_scope_classify.py" classify "$1" --repo "$W" --scope S1 2>&1)"; rc=$?; }
mut; python3 - "$MUT/autonomy_scope_secret.py" <<'EOF'
import sys; p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = 'c if m or c == "\\n" else " "'   # r1195: 코드 파일 «리터럴 밖 가림» 이 set( 가림을 흡수했다
assert old in t
open(p, "w", encoding="utf-8").write(t.replace(old, "c"))
EOF
mutcls "$(git -C "$W" rev-parse a1)"; want "변이: 칸1 좁힘 끔(리터럴 밖 가림 끔) → ⓐ 빨강(FORBID secret)" 3 "FORBID kind=secret"
mut; python3 - "$MUT/autonomy_scope_secret.py" <<'EOF'
import sys; p = sys.argv[1]; t = open(p, encoding="utf-8").read()
assert 'if full and full.split("\\n", 1)[0].startswith("#!"):' in t
open(p, "w", encoding="utf-8").write(t.replace('if full and full.split("\\n", 1)[0].startswith("#!"):', 'if False:'))
EOF
mutcls "$(git -C "$W" rev-parse i4)"; want "변이: 셔뱅 문맥 판정 끔 → 반례1 ⓓ 빨강(셸 판정 밖)" 0 "CLASS code"
mut; python3 - "$MUT/autonomy_scope_rules.py" <<'EOF'
import sys; p = sys.argv[1]; t = open(p, encoding="utf-8").read()
assert "if lineno in inside:" in t
open(p, "w", encoding="utf-8").write(t.replace("if lineno in inside:", "if False:"))
EOF
mutcls "$(git -C "$W" rev-parse k1)"; want "변이: 칸3 따옴표 값 안 판정 끔 → 반례3 ⓗ 빨강(key 0)" 0 "CLASS code"
mut; python3 - "$MUT/autonomy_scope_rules.py" <<'EOF'
import sys; p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "if v is None or (v and not ENV_PLACEHOLDER.match(v)):"
assert old in t
open(p, "w", encoding="utf-8").write(t.replace(old, "if v is None:"))
EOF
mutcls "$(git -C "$W" rev-parse g2)"; want "변이: 칸3 줄별 값 검사 끔 → ⓖ 실값 빨강(key 0)" 0 "CLASS code"
mut; python3 - "$MUT/autonomy_scope_secret.py" <<'EOF'
import sys; p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "    return text   # 그 밖 = 판정한다(닫힌 쪽)"
assert old in t
open(p, "w", encoding="utf-8").write(t.replace(old, "    if ext in ('.txt', '.json', '.sql'):\n        return ''\n" + old))
EOF
mutcls "$(git -C "$W" rev-parse m1)"; want "변이: 자료 확장자 제외 복귀 → r3 반례1 빨강" 0 "CLASS code"
mut; python3 - "$MUT/autonomy_scope_secret.py" <<'EOF'
import sys; p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "        return yaml_added(items)       # 기준판 동작 + 추가 줄만"
assert old in t
open(p, "w", encoding="utf-8").write(t.replace(old, "        return ''"))
EOF
mutcls "$(git -C "$W" rev-parse m4)"; want "변이: YAML 판정 끔 → r3 반례2 빨강" 0 "CLASS code"
mut; python3 - "$MUT/autonomy_scope_secret.py" <<'EOF'
import sys; p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "for n, t in items if n in ctx)"
assert old in t
open(p, "w", encoding="utf-8").write(t.replace(old, "for n, t in items if n in ctx and n not in shield)"))
EOF
mutcls "$(git -C "$W" rev-parse c4)"; want "변이: 문서 코드 울타리 통째 제외 복귀 → r5 반례 빨강" 0 "CLASS docs"
mut; python3 - "$MUT/autonomy_scope_rules.py" <<'EOF'
import sys; p = sys.argv[1]; lines = open(p, encoding="utf-8").read().split("\n")
open(p, "w", encoding="utf-8").write("\n".join(x for x in lines if '"test-file"' not in x))
EOF
mutcls "$(git -C "$W" rev-parse d1)"; want "변이: 시험 경로 제외 끔 → ⓓ 빨강(FORBID key)" 3 "FORBID kind=key"
mut; python3 - "$MUT/autonomy_scope_rules.py" <<'EOF'
import sys; p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = next(x for x in t.split("\n") if '"test-file"' in x)
assert "\\.(?:py|ts|tsx|js|sh)$" in old
broad = '    ("code", "test-file", r"(^|/)(?:__tests__|tests?)/|\\.(?:test|spec)\\.[cm]?[jt]sx?$|(^|/)test_[^/]*\\.py$|(^|/)[^/]*_test\\.py$"),'
open(p, "w", encoding="utf-8").write(t.replace(old, broad))
EOF
mutcls "$(git -C "$W" rev-parse j1)"; want "변이: 시험 경로 줄을 r1 의 넓은 꼴로 → 반례2 ⓓ 빨강(tests/credential.json 통과)" 0 "CLASS code"
rm -rf "$MUT"

# 짝 사본 cmp0
for f in autonomy_scope_classify.py autonomy_scope_rules.py autonomy_scope_secret.py ft_secret_targets.py; do
  cmp -s "$BIN/$f" "$KIT/$f" || { echo "DIFF $f"; fail=$((fail+1)); }
done
cmp -s "$BIN/ft_secret_targets.py" "$KIT/../templates/hooks/ft_secret_targets.py" && cmp -s "$BIN/ft_secret_targets.py" "$KIT/ft_secret_targets.py" || { echo "DIFF templates/hooks/ft_secret_targets.py"; fail=$((fail+1)); }
ck "칸 파일 4개 kit 사본 + hooks 템플릿 cmp0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
