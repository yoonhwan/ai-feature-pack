#!/usr/bin/env bash
# h-mini-audio-push.sh — D9 사전 점검 스크립트(mini-audio-check.sh)를 mini 의 /tmp 에 «파일 1개» 올리고, mini 터미널에서 칠 한 줄을 안내한다.
# 오빠가 이 맥에서 치는 줄(! bash /tmp/h<N>). 원격 쓰기 = mini:/tmp/aifp-mini-audio-check.sh 1개뿐(설치·설정 변경 0) — 오빠 D13(mini 오디오) 범위.
# 녹음·소리는 이 스크립트가 하지 않는다(ssh 로는 마이크 권한 팝업을 못 눌러서). mini 앞에서 안내된 한 줄을 오빠가 친다.
# 되돌리기: mini 에서 rm /tmp/aifp-mini-audio-check.sh (시험 스크립트는 끝나면 스스로 임시 녹음 파일을 지운다)
# rc: 0 올림 완료 · 2 사전점검 실패
set -uo pipefail
SRC=/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan/docs/multihost/h-plans/mini-audio-check.sh
KEY="$HOME/.ssh/id_ed25519_aifp_op"
DST=/tmp/aifp-mini-audio-check.sh
say() { printf '[h-mini-audio] %s\n' "$*"; }
die() { printf '[h-mini-audio] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }

[ -f "$SRC" ] || die 2 "시험 스크립트가 없다: $SRC"
[ -f "$KEY" ] || die 2 "전용 키가 없다: $KEY"
bash -n "$SRC" || die 2 "시험 스크립트 문법 오류"
command -v timeout >/dev/null 2>&1 || die 2 "timeout 명령이 없다"

say "1/2 mini 로 파일 1개 올림 → $DST"
timeout 12 ssh -o BatchMode=yes -o ConnectTimeout=5 -o IdentitiesOnly=yes -i "$KEY" byz@100.71.41.107 "cat > $DST && chmod 700 $DST && wc -c < $DST" < "$SRC" 2>&1 | sed 's/^/        올린 바이트: /' || die 2 "올리기 실패"

say "2/2 끝 — 이제 오빠 손 1회 (mini 화면 앞의 터미널에서 한 줄)"
cat <<EOF
        ▶ mini 터미널에서:  bash $DST
          · 소리가 mini 스피커에서 약 1초 납니다(시스템 «Ping» 음).
          · 처음이면 «터미널이 마이크에 접근하려 합니다» 팝업이 뜹니다 → 허용. (거부하거나 팝업이 안 뜨면 무음으로 나오고, 그건 «권한 미확인»입니다)
          · 결과 줄: «신호 들어옴(평균 … dB) → MIC_OK 후보» 또는 «신호가 없다…». 그 한 줄(또는 전체)을 저에게 알려 주세요.
        되돌리기: mini 에서  rm $DST
EOF
exit 0
