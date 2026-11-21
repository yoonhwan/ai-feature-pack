#!/usr/bin/env bash
# r2386_fixture.sh — r2386(라이브 bin 드리프트 검사 «대조 방식 묶음») 시험 세계. source 해서 쓴다.
#   세계: $REPO(git 리포 · kit/bin 4파일 · 커밋 2시간 전 = PENDING 창 밖) + $LIVE(라이브 설치 꼴 사본) · mktemp 만 · 실 라이브·네트워크 0
#   계측: PATH 앞 shim(git·grep·awk)이 불린 이름을 SHIMLOG 에 적는다 — «프로세스 수 = 비용» 을 세는 자리(카드 원인 1줄).
#   SUT = 지금 판(R2386_BIN 으로 바꿔 끼울 수 있다 — 변이 사본용) · OLD = 기준판(tests/fixtures/drift_check_pre_r2386.sh · 카드 착지 전 사본)
set -uo pipefail
RF_HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$RF_HERE/../../../harness/kit/fable-team/bin"
SUT="${R2386_BIN:-$SRC/ft-live-bin-drift-check.sh}"
OLD="$RF_HERE/../fixtures/drift_check_pre_r2386.sh"
MIRROR="$RF_HERE/../../../harness/bin/ft-live-bin-drift-check.sh"   # 같은 바이트여야 하는 다른 사본(카드 K5 · 배포 꼴 두 곳)
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
G="git -c user.email=t@t -c user.name=t"
REPO="$T/repo"; LIVE="$T/live"; KP=kit/bin; FILES=4
fail=0; MSG=""; LAST_OUT=""; LAST_RC=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1 — $MSG"; fail=$((fail + 1)); }
now() { python3 -c 'import time; print("%.3f" % time.time())'; }
loadavg() { sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}'; }

mkshim() { # $1=도구 이름 → $SHIM/$1 이 이름을 SHIMLOG 에 적고 진짜 도구로 넘긴다
  local real; real="$(command -v "$1")"; mkdir -p "$SHIM"
  printf '#!/bin/bash\nprintf "%%s %%s\\n" "%s" "$*" >> "$SHIMLOG"\nexec %s "$@"\n' "$1" "$real" > "$SHIM/$1"; chmod 755 "$SHIM/$1"
}
SHIM="$T/shim"; mkshim git; mkshim grep; mkshim awk

drift() { local s="$1"; shift; bash "$s" --bin "$LIVE" --repo "$REPO" --ref main --path "$KP" "$@" 2>&1; }
fresh_live() { rm -rf "$LIVE"; mkdir -p "$LIVE"; local f; for f in "$REPO/$KP"/*; do cp -p "$f" "$LIVE/"; done; }

# counts 는 «값» 만 stdout 으로 내고(명령 치환 = 서브셸이라 전역이 안 살아남는다) 출력·rc 는 파일에 남긴다 → reload 로 읽는다
reload() { LAST_OUT="$(cat "$T/last.out" 2>/dev/null)"; LAST_RC="$(cat "$T/last.rc" 2>/dev/null || echo 0)"; }
counts() { # counts <스크립트> — shim 으로 한 판 돌려 «hash=<n> grep=<n> awk=<n>» · 출력·rc = $T/last.out·$T/last.rc
  local log="$T/ct.$RANDOM" o r; : > "$log"
  o="$(SHIMLOG="$log" PATH="$SHIM:$PATH" drift "$@" 2>&1)"; r=$?
  printf '%s' "$o" > "$T/last.out"; printf '%s' "$r" > "$T/last.rc"
  printf 'hash=%s grep=%s awk=%s' \
    "$(grep -c '^git .*hash-object' "$log" 2>/dev/null; :)" "$(grep -c '^grep ' "$log" 2>/dev/null; :)" "$(grep -c '^awk ' "$log" 2>/dev/null; :)"
}
has()   { case "$1" in *"$2"*) return 0;; *) return 1;; esac; }
pair() { # pair <설명> — 새 판과 기준판의 rc·출력이 «같은가»(K4 출력 그대로 · K5 다른 길 그대로). LAST_* = 새 판
  local d="$1" o1 o2 r1 r2
  o1="$(drift "$SUT")"; r1=$?; o2="$(drift "$OLD")"; r2=$?
  LAST_OUT="$o1"; LAST_RC="$r1"
  if [ "$r1" = "$r2" ] && [ "$o1" = "$o2" ]; then ok "$d — rc=$r1 · 출력 같음"
  else MSG="rc ${r1}≠${r2} · 차이: $(diff <(printf '%s\n' "$o1") <(printf '%s\n' "$o2") | head -4 | tr '\n' ' ')"; bad "$d — 새 판·기준판 다름"; fi
}

mkworld() { # 4파일 키트 꼴 리포 · 커밋 = 2시간 전(PENDING 창 15분 밖 → 손 편집은 그대로 DIFF)
  git init -q -b main "$REPO"; mkdir -p "$REPO/$KP"
  printf '#!/bin/sh\necho A\n' > "$REPO/$KP/a.sh"; chmod 755 "$REPO/$KP/a.sh"
  printf 'b\n' > "$REPO/$KP/b.sh"; chmod 644 "$REPO/$KP/b.sh"
  printf 'space name\n' > "$REPO/$KP/my tool.sh"; chmod 755 "$REPO/$KP/my tool.sh"   # 공백 이름(DA F1)
  printf 'crlf\r\n' > "$REPO/$KP/c.sh"; chmod 755 "$REPO/$KP/c.sh"
  git -C "$REPO" add -A
  GIT_COMMITTER_DATE="$(($(date +%s) - 7200)) +0000" GIT_AUTHOR_DATE="$(($(date +%s) - 7200)) +0000" $G -C "$REPO" commit -q -m c1
  fresh_live
}
mkworld
