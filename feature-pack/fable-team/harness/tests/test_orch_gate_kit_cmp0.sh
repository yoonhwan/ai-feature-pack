#!/bin/bash
# 시험(r695): orchestration-gate 키트 훅 — TOP 모델 오케의 설치 복사 허용 꼴은 정확히 하나
# 명령 1개 «cp [-p] <절대 원본> <절대 목적지 파일>» ∧ 원본 = 일반 파일 ∧ 팩 kit/ ∧ origin/main cmp0 → 0
# 그 밖의 cp/install 은 부모판 그대로(마지막 인자 코드면 2) + 폴더 목적지면 원본 이름도 코드 검사.
# 사용: test_orch_gate_kit_cmp0.sh [훅 경로]  (기본 = 키트 훅 · 변이 사본 시험용 인자)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${1:-$ROOT/harness/kit/fable-team/templates/hooks/orchestration-gate.sh}"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT

# 가짜 팩(FT_PACK_ROOT 픽스처): kit/ 파일들 + kit 밖 파일을 커밋하고 origin/main 참조를 건다
PACK="$TMP/pack"; mkdir -p "$PACK/kit/m" "$PACK/kit/slack-mirror" "$PACK/scripts"
FETCH="$PACK/kit/slack-mirror/byz_slack_file_fetch.py"
echo 'print("fetch")' > "$FETCH"
echo 'print(1)' > "$PACK/kit/m/a.py"; echo 'print(2)' > "$PACK/kit/m/b.py"
echo 'print(1)' > "$PACK/kit/m/dirty.py"; echo 'x=1' > "$PACK/scripts/s.py"
git -C "$PACK" init -q && git -C "$PACK" add -A && git -C "$PACK" -c user.name=t -c user.email=t@t commit -qm init
git -C "$PACK" update-ref refs/remotes/origin/main HEAD
echo 'print("바꿈")' > "$PACK/kit/m/dirty.py"                     # 작업 트리만 바뀜 → origin/main 과 다름
echo 'evil()' > "$TMP/evil.py"
ln -s "$TMP/evil.py" "$PACK/kit/m/link.py"                         # kit 안 심링크 → 밖
ln -s a.py "$PACK/kit/m/kitlink.py"                                 # kit 안 상대 심링크 → kit 파일(cmp 같음)
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT/kit"; cp "$PACK/kit/m/a.py" "$NOGIT/kit/a.py"
DEST="$TMP/dest"; mkdir -p "$DEST" "$DEST/dir.py" "$TMP/payload"
echo old > "$DEST/exists.py"; ln -s "$TMP/evil.py" "$DEST/lnk.py"

transcript() { local f="$TMP/tr-$1.jsonl"; printf '{"type":"assistant","message":{"model":"%s"}}\n' "$1" > "$f"; echo "$f"; }
bash_json() {  # bash_json <command> <model>
  python3 - "$1" "$(transcript "$2")" "$TMP" <<'PY'
import json, sys
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]},
                  "session_id": "s-kit", "transcript_path": sys.argv[2], "cwd": sys.argv[3]}))
PY
}
rc() {  # rc <pack root> <command> [model] -> 셔뱅 인터프리터(/bin/bash)로 훅 직접 실행한 exit code
  bash_json "$2" "${3:-claude-fable-5-1}" | env -u TMUX_PANE -u TMUX TMPDIR="$TMP" FT_PACK_ROOT="$1" /bin/bash "$HOOK" >/dev/null 2>&1
  echo $?
}
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "ok   $1 → $3"; else fail=$((fail+1)); echo "FAIL $1 → 기대 $2 · 실제 $3"; fi; }

/bin/bash -n "$HOOK" && check "bash -n (셔뱅 /bin/bash)" 0 0 || check "bash -n (셔뱅 /bin/bash)" 0 1

echo "--- ⓑ 허용 꼴 (명령 1개 · cp [-p] · 절대 kit 원본 cmp0 · 절대 목적지 파일) ---"
check "r692 file_fetch 설치 복사(픽스처)"  0 "$(rc "$PACK" "cp $FETCH $DEST/byz_slack_file_fetch.py")"
check "cp -p kit → 코드 경로"             0 "$(rc "$PACK" "cp -p $PACK/kit/m/a.py $DEST/a.py")"
check "목적지 = 있는 일반 파일"            0 "$(rc "$PACK" "cp $PACK/kit/m/a.py $DEST/exists.py")"

echo "--- ⓒ 막아야 하는 칸 (2) ---"
check "원본 kit 밖(/tmp)"                 2 "$(rc "$PACK" "cp $TMP/evil.py $DEST/a.py")"
check "원본 팩 안 kit 밖(scripts/)"       2 "$(rc "$PACK" "cp $PACK/scripts/s.py $DEST/s.py")"
check "원본 kit 안 · origin/main 과 다름" 2 "$(rc "$PACK" "cp $PACK/kit/m/dirty.py $DEST/dirty.py")"
check "원본 kit 안 심링크 → 밖"           2 "$(rc "$PACK" "cp $PACK/kit/m/link.py $DEST/link.py")"
check "H2① 원본 kit 안 상대 심링크(같은 바이트)" 2 "$(rc "$PACK" "cp $PACK/kit/m/kitlink.py $DEST/k.py")"
check "H2① cp -P kit 상대 심링크"         2 "$(rc "$PACK" "cp -P $PACK/kit/m/kitlink.py $DEST/k.py")"
check "H2② cd X && cp (상대 원본)"        2 "$(rc "$PACK" "cd $PACK && cp kit/m/a.py $DEST/a.py")"
check "H2③ 앞 명령 && cp kit"             2 "$(rc "$PACK" "true && cp $PACK/kit/m/a.py $DEST/a.py")"
check "H2④ cp -t 폴더 kit"                2 "$(rc "$PACK" "cp -t $DEST $PACK/kit/m/a.py")"
check "H2④ --target-directory= kit"       2 "$(rc "$PACK" "cp --target-directory=$DEST $PACK/kit/m/a.py")"
check "cp kit ; 뒤 명령"                  2 "$(rc "$PACK" "cp $PACK/kit/m/a.py $DEST/a.py; true")"
check "cp kit && cmp (명령 2개)"          2 "$(rc "$PACK" "cp $PACK/kit/m/a.py $DEST/a.py && cmp $PACK/kit/m/a.py $DEST/a.py")"
check "목적지 안 \$(…) 치환"               2 "$(rc "$PACK" "cp $PACK/kit/m/a.py $DEST/a\$(true).py")"
check "원본 \$HOME 변수"                   2 "$(rc "$PACK" "cp \$HOME/kit/a.py $DEST/a.py")"
check "상대 원본(cwd 기준)"               2 "$(rc "$PACK" "cp pack/kit/m/a.py $DEST/a.py")"
check "목적지 = 심링크"                   2 "$(rc "$PACK" "cp $PACK/kit/m/a.py $DEST/lnk.py")"
check "목적지 = 끝 / 폴더(kit 1개)"       2 "$(rc "$PACK" "cp $PACK/kit/m/a.py $DEST/")"
check "목적지 = 있는 폴더(kit 1개)"       2 "$(rc "$PACK" "cp $PACK/kit/m/a.py $DEST")"
check "cp kit 2개 → 폴더/"                2 "$(rc "$PACK" "cp $PACK/kit/m/a.py $PACK/kit/m/b.py $DEST/")"
check "여러 원본 중 하나 kit 밖 → 폴더/"  2 "$(rc "$PACK" "cp $PACK/kit/m/a.py $TMP/evil.py $DEST/")"
check "단일 kit 밖 원본 → 있는 폴더"      2 "$(rc "$PACK" "cp $TMP/evil.py $DEST")"
check "H1 cp -R 폴더 → 있는 폴더.py"      2 "$(rc "$PACK" "cp -R $TMP/payload $DEST/dir.py")"
check "install -m 0755 kit(허용 꼴 밖)"   2 "$(rc "$PACK" "install -m 0755 $PACK/kit/m/a.py $DEST/a.py")"
check "없는 원본(glob 미전개)"            2 "$(rc "$PACK" "cp $PACK/kit/m/*.py $DEST/a.py")"
check "git 실패(팩 루트가 git 아님)"      2 "$(rc "$NOGIT" "cp $NOGIT/kit/a.py $DEST/a.py")"
check "mv kit → 코드 경로"                2 "$(rc "$PACK" "mv $PACK/kit/m/a.py $DEST/a.py")"
check "rsync kit → 코드 경로"             2 "$(rc "$PACK" "rsync $PACK/kit/m/a.py $DEST/a.py")"
check "sed -i 코드"                       2 "$(rc "$PACK" "sed -i s/1/2/ $DEST/a.py")"
check "> 리다이렉트 코드"                 2 "$(rc "$PACK" "cat $PACK/kit/m/a.py > $DEST/a.py")"
check "tee 코드"                          2 "$(rc "$PACK" "cat $PACK/kit/m/a.py | tee $DEST/a.py")"
check "dd of= 코드(회귀)"                 2 "$(rc "$PACK" "dd if=$PACK/kit/m/a.py of=$DEST/a.py")"

echo "--- ⓓ 워커 모델·문서 경로 그대로 ---"
check "Sonnet 5.5 kit 밖 cp (워커 면제)"  0 "$(rc "$PACK" "cp $TMP/evil.py $DEST/a.py" 'claude-sonnet-5-5[1m]')"
check "Opus 5.5 kit 밖 cp (워커 면제)"    0 "$(rc "$PACK" "cp $TMP/evil.py $DEST/a.py" 'claude-opus-5-5[1m]')"
check "TOP 문서 경로 cp(.md)"             0 "$(rc "$PACK" "cp $TMP/evil.py $DEST/a.md")"
check "TOP 단일 비코드 원본 → 폴더"       0 "$(rc "$PACK" "cp $TMP/notes.txt $DEST/")"

echo "--- ⓔ Sonnet 5 대조 (TOP) ---"
check "Sonnet 5 허용 꼴"                  0 "$(rc "$PACK" "cp $PACK/kit/m/a.py $DEST/a.py" 'claude-sonnet-5[1m]')"
check "Sonnet 5 kit 밖 cp"                2 "$(rc "$PACK" "cp $TMP/evil.py $DEST/a.py" 'claude-sonnet-5[1m]')"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
