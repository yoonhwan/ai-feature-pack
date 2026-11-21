# _merge_boot_smoke_fixture.sh — r2384 시험 공용(source 전용 · 100644): ft-merge-land 기동 smoke 시험 틀(_merge_ddl_fixture.sh 위)
#   기준판(부르는 자리만 뺀 land) · 변이 M7·M8 · 같은 내용 사본 SAME · 가짜 python = 리포 공용 루트 .venv/bin/python(rc 0·1·멈춤 · 호출 수 기록 · env 이름 기록)
#   부르는 쪽이 먼저 guard_begin 과 _merge_ddl_fixture.sh 를 연다 · pretest·finish 는 부르는 쪽
CALL='; phs boot; BOOTG="$(fm_boot_smoke "$REPO" "$S" "$(land_left)")" || { BOOTR=1; phs; rej "$BOOTG"; }; phs; [ "$BOOTG" = "기동 smoke 대상 밖" ] || { BOOTR=1; printf '"'"'%s\n'"'"' "$BOOTG"; }'
BASE="$(mutf base ft-merge-land.sh "$CALL" '')"                                                             # 기준판 = 부르는 자리만 뺀 land
M7="$(mutf m7 ft-merge-land.sh ' || { BOOTR=1; phs; rej "$BOOTG"; }' '')"                                      # 착지가 smoke rc 를 안 봄
M8="$(mutf m8 ft-merge-lib.sh '{ echo "기동 smoke 대상 밖"; return 0; }' '{ echo "기동 smoke 대상 밖"; return 1; }')"   # 스크립트 없음을 REJECT 로
SAME="$(mutf same ft-merge-land.sh "$CALL" "$CALL")"                                                        # ⑱ 대조용 같은 내용 사본(기준판과 같은 폴더 꼴)
pretest; tick 사전
mkdir -p "$W/.venv/bin"; printf '.venv/\n' >> "$W/.git/info/exclude"; PYLOG="$T/py.log"; : > "$PYLOG"
cat > "$W/.venv/bin/python" <<EOF
#!/bin/bash
echo "CALL \$* pwd=\$PWD pp=\$PYTHONPATH tree=\$([ -f "\$PYTHONPATH/scripts/ci/boot_smoke.py" ] && [ -f "\$PYTHONPATH/worker/main.py" ] && [ -f "\$PYTHONPATH/scripts/rag/r.py" ] && echo ok) canary=\${FT_BOOT_CANARY:-} env=\$(env | cut -d= -f1 | grep -v -x -E 'PATH|HOME|PYTHONPATH|PWD|SHLVL|_|OLDPWD' | tr '\n' ,)" >> "$PYLOG"
case "\$(cat "$T/py-mode")" in
  ok) echo "import banner"; echo "BOOT OK worker gateway"; exit 0;;
  fail) echo "worker.main ImportError: boom"; exit 1;;
  hang) exec sleep 8;;
esac
EOF
chmod +x "$W/.venv/bin/python"; export FT_BOOT_CANARY=leak
mode() { printf '%s\n' "$1" > "$T/py-mode"; : > "$PYLOG"; }
calls() { grep -c '^CALL ' "$PYLOG"; }
bootsec() { printf '%s\n' "$out" | sed -n 's/^LAND-PHASE .* boot=\([0-9]*\).*/\1/p'; }
BOOTPY="scripts/ci/boot_smoke.py=print(1)"; WPY="worker/main.py=app=1"
