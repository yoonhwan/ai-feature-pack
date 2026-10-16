#!/usr/bin/env bash
# test_key_rotate_journal.sh — ft-key-rotate.sh 묶음·journal 시험 (R206c). 임시 HOME · 가짜 .zshrc/.env · PATH 앞 가짜 op/gcloud/curl/pbpaste/pbcopy.
# 계약 표 8행(중간 실패·응답 유실·재개 값 출처·중단·Binance 쌍·OP 자기 교체·이미 죽은 키·파괴 직전) + 값 sentinel 0 + 변이(불명 판정 제거).
# 진짜 1Password·GCP·발급처·홈 파일·클립보드 0 · 네트워크 0.
set -uo pipefail
export LC_ALL=C LANG=C  # 로케일 고정(DA⑥ 관찰 — UTF-8 로케일 좌석에서도 같은 결과)
# 계약 예외(arch#68): 새 OP 토큰은 `op vault get` 자식 1개 env 로만 — 부모 env 불변 · 다른 자식 env 0 · 출력·journal·argv 0 (6b 시험이 확인).
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/fable-team-bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; [ -n "${DEBUG:-}" ] && echo "  RC=${RC:-} OUT=${OUT:-}" | head -30; fi; }

bash -n "$SRC/ft-key-rotate.sh" && ok "bash -n" || bad "bash -n"
python3 -m py_compile "$SRC"/ft_key_rotate*.py && ok "py_compile" || bad "py_compile"
for f in "$SRC"/ft_key_rotate_journal.py "$SRC"/ft_key_rotate_bundle.py "$SRC"/ft_key_rotate_steps.py "$SRC"/ft_key_rotate.py; do
  chk "200줄 이하 $(basename "$f")" '[ "$(wc -l < "$f" | tr -d " ")" -le 200 ]'
done

T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
NEW="NEWVAL_zZ9_0123456789abc"; NEW2="SECONDV_qQ7_9876543210xyz"
Z_KEYS="OP_SERVICE_ACCOUNT_TOKEN OP_SERVICE_ACCOUNT_TOKEN_DEVELOP GH_TOKEN_ORG BINANCE_API_KEY BINANCE_SECRET SLACK_WEBHOOK_URL OPENAI_API_KEY ELEVENLABS_API_KEY LANGSMITH_API_KEY CEREBRAS_API_KEY HUGGING_FACE_TOKEN OPENROUTER_API_KEY PERPLEXITY_API_KEY RUNPOD_API_KEY SEARCHAPI_KEY"
old() { echo "OLDVAL_${1}_0123456789"; }
J() { echo "$T/home/.local/state/ft-key-rotate/$1.jsonl"; }
fpof() { printf '%s' "$1" | shasum -a 256 | cut -c1-6; }

fix() {  # 매 케이스마다 새 픽스처 — 가짜 서버 상태(op.items · sm.versions)와 제어 파일(ctl/)
  chmod -R u+w "$T" 2>/dev/null; rm -rf "$T/home" "$T/root" "$T/bin" "$T/ctl" "$T"/*.argv "$T"/*.stdin "$T"/op.* "$T"/sm.* "$T"/curl.* "$T/plans"
  mkdir -p "$T/home" "$T/root" "$T/bin" "$T/ctl" "$T/plans"
  for k in $Z_KEYS; do echo "export $k=\"$(old $k)\""; done > "$T/home/.zshrc"
  for k in OPENAI_API_KEY ELEVENLABS_API_KEY LANGSMITH_API_KEY PERPLEXITY_API_KEY RUNPOD_API_KEY; do echo "$k=$(old $k)"; done > "$T/root/.env"
  : > "$T/op.items"; : > "$T/sm.versions"; : > "$T/curl.argv"; : > "$T/curl.stdin"; : > "$T/curl.codes"; echo 200 > "$T/curl.code"
  : > "$T/op.argv"; : > "$T/op.stdin"; : > "$T/op.vault"; : > "$T/gcloud.argv"; : > "$T/gcloud.stdin"; : > "$T/destroy.argv"
  printf '#!/bin/sh\ncat "%s/clip"\n' "$T" > "$T/bin/pbpaste"
  printf '#!/bin/sh\ncat > "%s/clip"\n' "$T" > "$T/bin/pbcopy"
  cat > "$T/bin/curl" <<EOF
#!/bin/sh
echo "\$@" >> "$T/curl.argv"; cat >> "$T/curl.stdin"
c=\$(head -1 "$T/curl.codes"); if [ -n "\$c" ]; then sed -i '' 1d "$T/curl.codes"; else c=\$(cat "$T/curl.code"); fi
printf '{}\n%s' "\$c"
EOF
  cat > "$T/bin/op" <<EOF
#!/bin/sh
echo "\$@" >> "$T/op.argv"
case "\$1 \$2" in
  "item create") cat >> "$T/op.stdin"; [ -n "\$OP_SERVICE_ACCOUNT_TOKEN" ] && echo leak >> "$T/op.leak"; m=\$(cat "$T/ctl/op.mode" 2>/dev/null); [ "\$m" = hard ] && exit 1
    echo "uuid-\$(wc -l < "$T/op.items" | tr -d ' ')-x" >> "$T/op.items"; [ "\$m" = lose ] && exit 1; exit 0 ;;
  "vault get") case "\$OP_SERVICE_ACCOUNT_TOKEN" in OLDVAL_*) echo vault=old >> "$T/op.vault" ;; *) echo vault=new >> "$T/op.vault" ;; esac; exit 0 ;;
esac
[ "\$1" = whoami ] && case "\$OP_SERVICE_ACCOUNT_TOKEN" in OLDVAL_*) exit 1 ;; esac
exit 0
EOF
  cat > "$T/bin/gcloud" <<EOF
#!/bin/sh
echo "\$@" >> "$T/gcloud.argv"; cat >> "$T/gcloud.stdin"
case "\$*" in *versions\ add*) [ "\$(cat "$T/ctl/sm.mode" 2>/dev/null)" = hard ] && exit 1; echo "\$(( \$(wc -l < "$T/sm.versions") + 1 ))" >> "$T/sm.versions" ;; esac
exit 0
EOF
  for p in op sm; do  # 조회: rc0=있음(id=·ver=) · rc1=없음 · rc2=조회 불가(ctl/probe.down)
    f="$T/op.items"; [ $p = sm ] && f="$T/sm.versions"
    cat > "$T/bin/probe-$p" <<EOF
#!/bin/sh
[ -e "$T/ctl/probe.down" ] && exit 2
n=\$(wc -l < "$f" | tr -d ' '); if [ "\$n" -gt 0 ]; then echo "id=\$(tail -1 "$f") ver=\$n"; exit 0; fi; echo "ver=0"; exit 1
EOF
  done
  cat > "$T/bin/probe-ref" <<EOF
#!/bin/sh
echo "\$@" >> "$T/destroy.argv"; [ -e "$T/ctl/ref.live" ] && exit 1; exit 0
EOF
  cat > "$T/bin/destroy-it" <<EOF
#!/bin/sh
echo "\$@" >> "$T/destroy.argv.called"
exit 0
EOF
  chmod +x "$T/bin/"*; rm -f "$T/destroy.argv.called"
}
plan() {  # plan <이름> <ENV> [destroy-first]
  local stdin="$2" f="$T/plans/$1.json"
  cat > "$f" <<EOF
{"steps":[
 {"name":"op-item","stdin":"$stdin","call":["op","item","create","--vault","develop","--template","-"],"probe":["probe-op"]},
 {"name":"sm-version","stdin":"$stdin","call":["gcloud","secrets","versions","add","byz-dev-x","--data-file=-"],"probe":["probe-sm"],"ops":true}
]}
EOF
}
run() {  # run <클립보드> <인자…> — OUT · RC
  printf '%s' "$1" > "$T/clip"; shift
  OUT="$(env -u OP_SERVICE_ACCOUNT_TOKEN -u OP_SERVICE_ACCOUNT_TOKEN_DEVELOP -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
    HOME="$T/home" FT_KEY_ROTATE_ENV="$T/root/.env" PATH="$T/bin:$PATH" bash "${TOOL:-$SRC/ft-key-rotate.sh}" "$@" 2>&1)"; RC=$?
}
nolek() { ! grep -rqF -e "$NEW" -e "$NEW2" -e "OLDVAL_" "$T/home/.local" "$T/op.argv" "$T/gcloud.argv" "$T/curl.argv" 2>/dev/null; }

# 1 중간 실패 — ① 로컬 됨 · ② 1Password 실패(서버 미반영·조회로 «없음» 확인) → 멈춘 단계 출력 · 다음 단계 0 · 중단(단계 n)
fix; plan p1 OPENAI_API_KEY; echo hard > "$T/ctl/op.mode"
run "$NEW" OPENAI_API_KEY --plan "$T/plans/p1.json"
chk "1 중간 실패: STEP op-item 미실행 · BUNDLE 중단(단계 op-item) · rc≠0" '[ $RC -ne 0 ] && echo "$OUT" | grep -q "^STEP op-item 미실행" && echo "$OUT" | grep -q "^BUNDLE openai-api-key 중단(단계 op-item)"'
chk "1 이미 된 단계(로컬) 완료 · 다음 단계(SM) 호출 0" 'grep -q "\"step\": \"local:OPENAI_API_KEY\".*\"res\": \"완료\"" "$(J openai-api-key)" && [ ! -s "$T/gcloud.argv" ]'
chk "1 --status 묶음 × 단계 × 상태" 'run "" --status; echo "$OUT" | grep -q "^BUNDLE openai-api-key .*중단(단계 op-item).*local:OPENAI_API_KEY:완료.*op-item:미실행"'
rm -f "$T/ctl/op.mode"; run "" --resume openai-api-key --plan "$T/plans/p1.json"
chk "1 재개: 활성 줄 값으로 op-item·sm-version 완료 + 로컬 재교체 0" '[ $RC -eq 0 ] && echo "$OUT" | grep -q "^STEP op-item 완료" && echo "$OUT" | grep -q "^STEP sm-version 완료" && [ "$(grep -c "item create" "$T/op.argv")" = 2 ] && [ "$(ls "$T"/home/.zshrc.bak-keyrotate-OPENAI_API_KEY-* | wc -l | tr -d " ")" = 1 ] && grep -q "$NEW" "$T/op.stdin" && grep -q "$NEW" "$T/gcloud.stdin"'
chk "1 값 sentinel 0(출력·argv·journal)" 'nolek && ! echo "$OUT" | grep -qF "$NEW"'

# 2 응답 유실 — 서버는 반영 · rc≠0 · 조회도 못 함 → 불명 · 다음 단계 0 → 재개 때 조회로 확정(중복 호출 0)
fix; plan p2 OPENAI_API_KEY; echo lose > "$T/ctl/op.mode"; : > "$T/ctl/probe.down"
run "$NEW" OPENAI_API_KEY --plan "$T/plans/p2.json"
chk "2 응답 유실: BUNDLE 불명(단계 op-item) · SM 호출 0 · 서버엔 항목 1" 'echo "$OUT" | grep -q "^BUNDLE openai-api-key 불명(단계 op-item)" && [ ! -s "$T/gcloud.argv" ] && [ "$(wc -l < "$T/op.items" | tr -d " ")" = 1 ]'
run "" --resume openai-api-key --plan "$T/plans/p2.json"
chk "2 조회 여전히 불가 → 다시 불명 정지(다음 단계 0)" '[ $RC -ne 0 ] && echo "$OUT" | grep -q "^STEP op-item 불명" && [ ! -s "$T/gcloud.argv" ]'
rm -f "$T/ctl/probe.down" "$T/ctl/op.mode"; run "" --resume openai-api-key --plan "$T/plans/p2.json"
chk "2 조회 가능 → 확정=조회 완료 · 1Password 항목 재생성 0 · 그 뒤 SM" '[ $RC -eq 0 ] && echo "$OUT" | grep -q "^STEP op-item 완료 (확정=조회)" && [ "$(grep -c "item create" "$T/op.argv")" = 1 ] && [ -s "$T/gcloud.argv" ]'
# 2' 불명 → 조회로 «없음» 확정 → 미실행 → 같은 단계를 다시 호출
fix; plan p2b OPENAI_API_KEY; echo hard > "$T/ctl/op.mode"; : > "$T/ctl/probe.down"
run "$NEW" OPENAI_API_KEY --plan "$T/plans/p2b.json"; rm -f "$T/ctl/probe.down" "$T/ctl/op.mode"
run "" --resume openai-api-key --plan "$T/plans/p2b.json"
chk "2' 불명 → 조회 없음 확정 → 재호출 완료" '[ $RC -eq 0 ] && echo "$OUT" | grep -q "^STEP op-item 완료" && [ "$(wc -l < "$T/op.items" | tr -d " ")" = 1 ]'

# 변이: 불명 판정 제거(조회 불명 → 완료로 취급) → 응답 유실 꼴에서 다음 단계가 실행돼야 FAIL 로 잡힌다
M="$T/mut"; rm -rf "$M"; mkdir -p "$M"; cp "$SRC"/ft-key-rotate.sh "$SRC"/ft_key_rotate*.py "$M/"
sed -i '' 's/"unknown": UNKNOWN/"unknown": OK/' "$M/ft_key_rotate_steps.py"
grep -q '"unknown": OK' "$M/ft_key_rotate_steps.py" && ok "변이 적용(불명→완료)" || bad "변이 적용(불명→완료)"
fix; plan pm OPENAI_API_KEY; echo lose > "$T/ctl/op.mode"; : > "$T/ctl/probe.down"
TOOL="$M/ft-key-rotate.sh" run "$NEW" OPENAI_API_KEY --plan "$T/plans/pm.json"
chk "변이 잡힘: 불명 판정 없으면 응답 유실 뒤 SM 이 실행됨(원 단언이 FAIL)" '[ -s "$T/gcloud.argv" ]'

# 3 재개 값 출처 — 로컬 활성 줄 지문 대조 · 재복사 클립보드 지문 동일 확인 · 다르면 REJECT(조용히 다른 값 0)
fix; plan p3 OPENAI_API_KEY; echo hard > "$T/ctl/op.mode"
run "$NEW" OPENAI_API_KEY --plan "$T/plans/p3.json"; rm -f "$T/ctl/op.mode"
sed -i '' "s/^export OPENAI_API_KEY=.*/export OPENAI_API_KEY=\"$NEW2\"/" "$T/home/.zshrc"
run "" --resume openai-api-key --plan "$T/plans/p3.json"
chk "3 활성 줄이 기록 지문과 다르면 REJECT · 1Password 호출 추가 0" '[ $RC -eq 1 ] && echo "$OUT" | grep -q "^REJECT .*지문이 기록과 다름" && [ "$(grep -c "item create" "$T/op.argv")" = 1 ]'
fix; plan p3b OPENAI_API_KEY; mkdir -p "$(dirname "$(J x)")"; F="$(J openai-api-key)"; FPN="$(fpof "$NEW")"
printf '%s\n' '{"att":1,"phase":"plan","detail":"-","t":"20261016T000000"}' \
  "{\"att\":1,\"step\":\"local:OPENAI_API_KEY\",\"phase\":\"intent\",\"fp\":\"$FPN\",\"t\":\"20261016T000001\"}" \
  '{"att":1,"step":"local:OPENAI_API_KEY","phase":"result","res":"미실행","t":"20261016T000002"}' > "$F"; chmod 600 "$F"
run "$NEW2" --resume openai-api-key --from-clipboard
chk "3 재복사 값 지문이 다르면 REJECT · 활성 줄 불변" '[ $RC -eq 1 ] && echo "$OUT" | grep -q "^REJECT 클립보드 지문이 기록과 다름" && grep -q "OLDVAL_OPENAI" "$T/home/.zshrc"'
run "$NEW" --resume openai-api-key --from-clipboard
chk "3 재복사 값 지문이 같으면 로컬 교체 완료 후 계속" '[ $RC -eq 0 ] && echo "$OUT" | grep -q "^STEP local:OPENAI_API_KEY 완료" && grep -q "$NEW" "$T/home/.zshrc"'

# 4 중단 — 완료 표식 0 · 중단 + 담당·재개 조건·남은 복사본 · 다른 묶음 열기는 운영 반영 0 확인 또는 범위 값 1줄
fix; plan p4 OPENAI_API_KEY; echo hard > "$T/ctl/op.mode"
run "$NEW" OPENAI_API_KEY --plan "$T/plans/p4.json"
run "" --abandon openai-api-key --reason "발급처 점검" --owner planner
chk "4 --abandon 은 --when 없으면 REJECT(담당·재개 조건 필수)" '[ $RC -eq 1 ] && echo "$OUT" | grep -q "^REJECT"'
run "" --abandon openai-api-key --reason "발급처 점검" --owner planner --when "점검 끝나면 --resume"
chk "4 ABANDONED 줄 + 남은 복사본 표 + 완료 표식 0" '[ $RC -eq 0 ] && echo "$OUT" | grep -q "^ABANDONED openai-api-key 중단(발급처 점검) owner=planner" && echo "$OUT" | grep -q "^COPY local:OPENAI_API_KEY 새 값=지금 활성 줄" && ! grep -q "\"phase\": \"end\"" "$(J openai-api-key)"'
printf '%s' "$NEW2" > "$T/clip"; run "$NEW2" GH_TOKEN_ORG
chk "4 운영 반영 0 인 중단 뒤 다른 묶음 열기 허용" '[ $RC -eq 0 ] && echo "$OUT" | grep -q "^ROTATED GH_TOKEN_ORG"'
fix; plan p4b OPENAI_API_KEY
run "$NEW" OPENAI_API_KEY --plan "$T/plans/p4b.json"; run "" --abandon openai-api-key --reason "중간 점검" --owner planner --when "다음 회차"
chk "4 SM(운영 반영) 완료 뒤 중단 → NOTE 범위 값 필요" 'echo "$OUT" | grep -q "운영 반영 가능성"'
run "$NEW2" GH_TOKEN_ORG
chk "4 운영 반영이 있는 중단 → 다른 묶음 REJECT(쓰기 0)" '[ $RC -eq 1 ] && echo "$OUT" | grep -q "^REJECT openai-api-key 열린 시도" && grep -q "OLDVAL_GH_TOKEN_ORG" "$T/home/.zshrc"'
run "$NEW2" GH_TOKEN_ORG --allow-open "planner 판정 1999 범위: GH 만"
chk "4 --allow-open 범위 값 1줄이면 허용 + journal 에 기록" '[ $RC -eq 0 ] && grep -q "범위 허용 planner 판정 1999" "$(J gh-token-org)"'

# 4b 연속 교체 — plan 없는 평범한 교체(로컬만 바뀜 · 옛 키 폐기는 나중)는 다른 키 교체를 막지 않는다 · 운영 반영이 있는 열린 묶음만 막는다
fix; run "$NEW" OPENAI_API_KEY; run "$NEW2" ELEVENLABS_API_KEY
chk "4b A→B 연속 교체 rc0 (A 는 진행 상태로 남아도 B 를 막지 않음)" '[ $RC -eq 0 ] && echo "$OUT" | grep -q "^ROTATED ELEVENLABS_API_KEY" && grep -q "OLDVAL_GH_TOKEN_ORG" "$T/home/.zshrc"'
run "$NEW" GH_TOKEN_ORG
chk "4b 세 번째도 rc0 · 앞 묶음 상태는 그대로 진행" '[ $RC -eq 0 ] && run "" --status && echo "$OUT" | grep -q "^BUNDLE openai-api-key  *진행"'
fix; plan p4c OPENAI_API_KEY; run "$NEW" OPENAI_API_KEY --plan "$T/plans/p4c.json"; run "$NEW2" GH_TOKEN_ORG
chk "4b 운영 반영(SM 완료)이 있는 열린 묶음은 «진행» 이어도 다른 묶음 REJECT" '[ $RC -eq 1 ] && echo "$OUT" | grep -q "^REJECT openai-api-key 열린 시도" && grep -q "OLDVAL_GH_TOKEN_ORG" "$T/home/.zshrc"'
fix; plan p4d OPENAI_API_KEY; echo hard > "$T/ctl/op.mode"; run "$NEW" OPENAI_API_KEY --plan "$T/plans/p4d.json"; run "$NEW2" GH_TOKEN_ORG
chk "4b 중단(단계 n) 묶음은 다른 묶음 REJECT 유지" '[ $RC -eq 1 ] && echo "$OUT" | grep -q "^REJECT openai-api-key 열린 시도"'
# 변이: 운영 반영 조건 제거 → 4b 마지막 «운영 반영 REJECT» 가 FAIL(통과해 버림)이어야 한다 · A→B 연속 교체는 그대로 통과
M2="$T/mut2"; rm -rf "$M2"; mkdir -p "$M2"; cp "$SRC"/ft-key-rotate.sh "$SRC"/ft_key_rotate*.py "$M2/"
sed -i '' 's/(ops_touched(es) or not st/(not st/' "$M2/ft_key_rotate_journal.py"
grep -q "(not st.startswith" "$M2/ft_key_rotate_journal.py" && ok "변이2 적용(ops_touched 제거)" || bad "변이2 적용"
fix; plan p4e OPENAI_API_KEY; TOOL="$M2/ft-key-rotate.sh" run "$NEW" OPENAI_API_KEY --plan "$T/plans/p4e.json"; TOOL="$M2/ft-key-rotate.sh" run "$NEW2" GH_TOKEN_ORG
chk "변이2 잡힘: ops_touched 없으면 운영 반영 묶음이 다른 묶음을 못 막음(원 단언 FAIL)" '[ $RC -eq 0 ]'

# 5 Binance 쌍 — KEY·SECRET 한 묶음: 둘 다 준비돼야 쌍 서명 확인 1회 → 옛 쌍 폐기 확인까지 묶음 단위 완료
fix; run "$NEW" BINANCE_API_KEY
chk "5 KEY 만: SKIP-CHECK · curl 0 · 묶음 진행(완료 아님)" '[ $RC -eq 0 ] && echo "$OUT" | grep -q "^SKIP-CHECK BINANCE_API_KEY" && [ ! -s "$T/curl.argv" ] && echo "$OUT" | grep -q "^BUNDLE binance 진행" && echo "$OUT" | grep -q "나머지 필드(BINANCE_SECRET)"'
run "$NEW" OPENAI_API_KEY
chk "5 binance 가 열려 있는 동안 다른 묶음 REJECT" '[ $RC -eq 1 ] && echo "$OUT" | grep -q "^REJECT binance 열린 시도"'
run "$NEW2" BINANCE_SECRET
chk "5 SECRET 교체 뒤 쌍 서명 확인 curl 정확히 1회 · ALIVE" '[ $RC -eq 0 ] && [ "$(grep -c -- "-K -" "$T/curl.argv")" = 1 ] && echo "$OUT" | grep -q "^ALIVE BINANCE_SECRET http=200" && echo "$OUT" | grep -q "^STEP verify 완료"'
chk "5 옛 쌍 폐기 확인 전엔 완료 아님" 'echo "$OUT" | grep -q "^BUNDLE binance 진행" && ! grep -q "\"phase\": \"end\"" "$(J binance)"'
echo 401 > "$T/curl.code"; run "" --check-old BINANCE_SECRET
chk "5 옛 쌍 폐기 증거(401) → 묶음 완료" 'echo "$OUT" | grep -q "^BUNDLE binance 완료" && grep -q "이미 폐기(증거)" "$(J binance)"'

# 6 1Password 토큰 자기 교체 — 새 토큰으로 보관함 권한 확인 + 소비자 전환 확인을 먼저 · plan 에 소비자 확인이 없으면 미확인(소비자)
fix; run "$NEW" OP_SERVICE_ACCOUNT_TOKEN_DEVELOP
chk "6 새 토큰으로 보관함 확인(vault=new · 옛 토큰 0) · 소비자 plan 없음 → 미확인" '[ $RC -eq 0 ] && grep -qx "vault=new" "$T/op.vault" && ! grep -q "vault=old" "$T/op.vault" && echo "$OUT" | grep -q "^STEP vault 완료" && echo "$OUT" | grep -q "^STEP consumers 미확인"'
run "" --check-old OP_SERVICE_ACCOUNT_TOKEN_DEVELOP
chk "6 옛 계정 폐기 증거 뒤 끝 상태 = 미확인(소비자)" 'echo "$OUT" | grep -q "^BUNDLE op-develop 미확인(소비자)"'
fix; printf '{"steps":[{"name":"consumers","probe":["probe-ref"]}]}' > "$T/plans/p6.json"; touch "$T/ctl/ref.live"
run "$NEW" OP_SERVICE_ACCOUNT_TOKEN_DEVELOP --plan "$T/plans/p6.json"
chk "6 소비자 전환 조회 실패 → 중단(단계 consumers)" 'echo "$OUT" | grep -q "^STEP consumers 미실행" && echo "$OUT" | grep -q "^BUNDLE op-develop 중단(단계 consumers)"'
rm -f "$T/ctl/ref.live"; run "" --resume op-develop --plan "$T/plans/p6.json"
chk "6 소비자 전환 확인되면 완료(조회로)" 'echo "$OUT" | grep -q "^STEP consumers 완료"'

# 7 이미 죽은 키 — 증거(코드·시각) 기록 · 새 발급·등록·반영만 · 옛 키 단계는 «이미 폐기(증거)» 로 별 종료 · SKIP/UNVERIFIED/403 을 REVOKED 로 자동 처리 0
fix; printf '403\n200\n' > "$T/curl.codes"
run "$NEW" LANGSMITH_API_KEY
chk "7 옛 키 403 → 이미 폐기(증거 http=403 시각) · 새 키 확인 뒤 묶음 완료" '[ $RC -eq 0 ] && grep -q "\"step\": \"old-key\".*\"res\": \"이미 폐기(증거)\".*http=403 t=" "$(J langsmith-api-key)" && echo "$OUT" | grep -q "^BUNDLE langsmith-api-key 완료"'
chk "7 journal 에 REVOKED 단어 0" '! grep -q REVOKED "$(J langsmith-api-key)"'
fix; printf '404\n200\n' > "$T/curl.codes"; run "$NEW" LANGSMITH_API_KEY
chk "7 404 는 증거 아님 → 옛 키 단계 안 닫힘(진행)" '! grep -q "이미 폐기" "$(J langsmith-api-key)" && echo "$OUT" | grep -q "^BUNDLE langsmith-api-key 진행"'
fix; run "$NEW" PERPLEXITY_API_KEY; run "" --check-old PERPLEXITY_API_KEY
chk "7 SKIP-CHECK 는 REVOKED 아님 → 미확인 종료 · 폐기 증거 0" '! grep -q "이미 폐기" "$(J perplexity-api-key)" && echo "$OUT" | grep -q "^BUNDLE perplexity-api-key 미확인" && ! echo "$OUT" | grep -q "^REVOKED"'

# 8 파괴 직전 — 고정 ID 와 현재 참조를 다시 조회 · 미완료 소비자·기록 불명·참조 남음이면 destroy 0
mkd() {  # mkd <파일> <선두에 둘 단계 JSON(옵션)>
  cat > "$T/plans/$1.json" <<EOF
{"steps":[$2
 {"name":"op-item","stdin":"OPENAI_API_KEY","call":["op","item","create","--vault","develop","--template","-"],"probe":["probe-op"]},
 {"name":"old-del","call":["destroy-it","{id}"],"probe":["probe-ref"],"destroy":true,"guard":["probe-ref","{id}"],"target_of":"op-item"}
]}
EOF
}
fix; mkd p8 ""; touch "$T/ctl/ref.live"
run "$NEW" OPENAI_API_KEY --plan "$T/plans/p8.json"
chk "8 현재 참조가 남아 있으면 destroy 호출 0 · 거절 기록" '[ ! -e "$T/destroy.argv.called" ] && echo "$OUT" | grep -q "^STEP old-del 미실행" && grep -q "재조회 불일치" "$(J openai-api-key)"'
fix; mkd p8b '{"name":"old-del0","call":["destroy-it","{id}"],"probe":["probe-ref"],"destroy":true,"guard":["probe-ref","{id}"],"target_of":"op-item"},'
run "$NEW" OPENAI_API_KEY --plan "$T/plans/p8b.json"
chk "8 대상 ID 를 아직 모르면(고정 ID 0) destroy 0" '[ ! -e "$T/destroy.argv.called" ] && grep -q "대상 ID 없음" "$(J openai-api-key)"'
fix; printf '{"steps":[{"name":"old-del","call":["destroy-it","{id}"],"probe":["probe-ref"],"destroy":true,"guard":["probe-ref","{id}"],"target_of":"vault"}]}' > "$T/plans/p8c.json"
run "$NEW" OP_SERVICE_ACCOUNT_TOKEN_DEVELOP --plan "$T/plans/p8c.json"
chk "8 op 묶음에서 소비자 미완료 → destroy 0" '[ ! -e "$T/destroy.argv.called" ]'
fix; mkd p8d ""
run "$NEW" OPENAI_API_KEY --plan "$T/plans/p8d.json"
chk "8 모두 맞으면 고정 ID({id}) 로 destroy 1회 · 값 0" '[ -e "$T/destroy.argv.called" ] && grep -q "^uuid-0-x$" "$T/destroy.argv.called" && echo "$OUT" | grep -q "^STEP old-del 완료" && nolek'

# 6b 계약 예외 조건 — 새 OP 토큰은 vault 확인 자식 1개 env 로만(다른 자식·부모 env 0)
fix; plan p6b OP_SERVICE_ACCOUNT_TOKEN_DEVELOP; run "$NEW" OP_SERVICE_ACCOUNT_TOKEN_DEVELOP --plan "$T/plans/p6b.json"
chk "6b op item 자식 env 에 새 토큰 0 · vault 확인 자식만 새 토큰(1회)" '[ ! -s "$T/op.leak" ] && [ "$(grep -c "vault=new" "$T/op.vault")" = 1 ] && grep -q "item create" "$T/op.argv"'
chk "6b 코드가 부모 환경을 바꾸지 않음(os.environ 대입·putenv 0 · 사본 dict 사용)" '! grep -nE "os\.environ\[[^]]*\] *=|putenv|environ\.update" "$SRC"/ft_key_rotate_steps.py "$SRC"/ft_key_rotate_bundle.py && grep -q "dict(os.environ, OP_SERVICE_ACCOUNT_TOKEN=tok)" "$SRC/ft_key_rotate_steps.py"'
chk "6b 출력·journal·argv 에 값 0" 'nolek'

# 9 결과 전에 프로세스가 죽은 운영 단계(intent 만 있음) = 불명 — 다른 묶음 REJECT · 재개는 조회 먼저(있음=호출 0 · 없음=호출 1 · 조회 불가=불명 정지)
trunc() { n=$(grep -n '"step": "sm-version", "phase": "intent"' "$(J openai-api-key)" | head -1 | cut -d: -f1); head -n "$n" "$(J openai-api-key)" > "$T/j.tmp"; cat "$T/j.tmp" > "$(J openai-api-key)"; }
mk9() { fix; plan p9 OPENAI_API_KEY; run "$NEW" OPENAI_API_KEY --plan "$T/plans/p9.json"; trunc; }
mk9; run "" --status
chk "9 intent-only 운영 단계 → 상태 불명(단계 sm-version)" 'echo "$OUT" | grep -q "^BUNDLE openai-api-key  *불명(단계 sm-version)"'
run "$NEW2" GH_TOKEN_ORG
chk "9 intent-only 운영 단계가 있는 묶음 → 다른 묶음 REJECT(쓰기 0)" '[ $RC -eq 1 ] && echo "$OUT" | grep -q "^REJECT openai-api-key 열린 시도(불명" && grep -q "OLDVAL_GH_TOKEN_ORG" "$T/home/.zshrc"'
run "" --resume openai-api-key --plan "$T/plans/p9.json"
chk "9 재개 + 조회 있음 → 운영 호출 0 · 완료(확정=조회)" '[ $RC -eq 0 ] && echo "$OUT" | grep -q "^STEP sm-version 완료 (확정=조회)" && [ "$(grep -c "versions add" "$T/gcloud.argv")" = 1 ]'
mk9; : > "$T/sm.versions"; run "" --resume openai-api-key --plan "$T/plans/p9.json"
chk "9 재개 + 조회 없음 → 운영 호출 1(재호출)" '[ $RC -eq 0 ] && [ "$(grep -c "versions add" "$T/gcloud.argv")" = 2 ]'
mk9; : > "$T/ctl/probe.down"; run "" --resume openai-api-key --plan "$T/plans/p9.json"
chk "9 재개 + 조회 불가 → 불명 정지 · 운영 호출 추가 0" '[ $RC -ne 0 ] && echo "$OUT" | grep -q "^STEP sm-version 불명" && [ "$(grep -c "versions add" "$T/gcloud.argv")" = 1 ]'
mk9; run "" --abandon openai-api-key --reason "중간 사망" --owner planner --when "다음 회차"
chk "9 중단 표에 intent-only 운영 단계가 «반영 가능» 으로 남음 · 다른 묶음 범위 값 필요" 'echo "$OUT" | grep -q "^COPY sm-version" && echo "$OUT" | grep -q "운영 반영 가능성"'
M3="$T/mut3"; mkdir -p "$M3"; cp "$SRC"/ft-key-rotate.sh "$SRC"/ft_key_rotate*.py "$M3/"
sed -i '' 's/phase="result", res=UNKNOWN)/phase="result", res=NOT_RUN)/' "$M3/ft_key_rotate_journal.py"
grep -q 'phase="result", res=NOT_RUN)' "$M3/ft_key_rotate_journal.py" && ok "변이3 적용(intent-only 불명 처리 제거)" || bad "변이3 적용"
mk9; TOOL="$M3/ft-key-rotate.sh" run "" --resume openai-api-key --plan "$T/plans/p9.json"
chk "변이3 잡힘: intent-only 처리 없으면 조회 있음에도 운영 호출이 다시 나감(원 단언 FAIL)" '[ "$(grep -c "versions add" "$T/gcloud.argv")" = 2 ]'

# 기록 파일 위생: 600 · 값·해시 원문 0(지문 6자리 접두만) · 7초 룰(조회·호출 timeout=7)
fix; run "$NEW" GH_TOKEN_ORG
chk "journal 600 · 값 0 · 지문 접두만" '[ "$(stat -f %Lp "$(J gh-token-org)")" = 600 ] && ! grep -qF "$NEW" "$(J gh-token-org)" && grep -q "\"fp\": \"$(fpof "$NEW")\"" "$(J gh-token-org)" && [ "$(grep -o "\"fp\": \"[0-9a-f]*\"" "$(J gh-token-org)" | head -1 | sed "s/.*: \"//; s/\"//" | wc -c | tr -d " ")" = 7 ]'
chk "외부 호출 timeout=7 + 재시도 1" 'grep -q "timeout=7" "$SRC/ft_key_rotate_steps.py" && grep -q "for _ in (0, 1)" "$SRC/ft_key_rotate_steps.py"'
chk "원본·키트 사본 cmp 0" 'for f in ft-key-rotate.sh ft_key_rotate.py ft_key_rotate_io.py ft_key_rotate_lines.py ft_key_rotate_table.py ft_key_rotate_journal.py ft_key_rotate_bundle.py ft_key_rotate_steps.py; do cmp -s "$SRC/$f" "$SRC/../harness-install/fable-team/bin/$f" || { echo "diff $f"; exit 1; }; done'

echo "---"; [ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILED=$fail"; exit 1; }
