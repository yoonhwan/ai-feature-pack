#!/usr/bin/env bash
# test_r988_root_bin_migrate.sh — r988: ft-root-bin-migrate.sh (라이브 plist·팀 env 의 v6 시작 경로를 «값 단위» 로 공용 루트로 · 세트 d2cb5dc5 그대로)
#   ⓜ dry-run: 위 표 꼴 픽스처(plist 9 · env 11) → MIGRATE/REPORT 칸 수 일치 · ★파일 바이트 불변★
#   ⓝ apply: «이전» 칸만 값이 바뀐다 · «보고만»(사람 글·비대상 라벨) 칸 바이트 불변 · .bak-r962 생성 · 재실행은 바꿀 것 0(멱등)
#   ⓞ 새 값 실재 0(루트 bin 에 그 스크립트 없음) → 그 파일 바이트 불변 + rc≠0 · 다른 파일은 진행
#   변이 9 «값 부분 일치로 이전» → ⓝ FAIL(사람 글 바뀜) · 변이 10 «.bak 없이 쓰기» → ⓝ FAIL(백업 0)
# 실 ~/Library/LaunchAgents 0 · 실 launchctl 0 — 임시 폴더만 쓴다(--launchagents·--teams-dir·--root·--from-wt).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; KBIN="$REPO/harness/kit/fable-team/bin"; KBIN_BIN="$REPO/harness/bin"
TOOL="$KBIN/ft-root-bin-migrate.sh"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail + 1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }

bash -n "$TOOL" && ok "bash -n ft-root-bin-migrate.sh" || bad "bash -n ft-root-bin-migrate.sh"
chk "kit·bin 짝 cmp0" "$(cmp -s "$TOOL" "$KBIN_BIN/ft-root-bin-migrate.sh" && echo same || echo differ)" same
unset FT_ROOT FT_MBOX_DIR FT_HARNESS_ROOT

# ── 픽스처: 공용 루트 R · v6 워크트리 V · 라벨 9종 plist · 팀 env 11 ──
build() {  # build <기저 폴더> <루트 bin 에 만들 파일들…>
  local base="$1"; shift
  local R="$base/root" V="$base/root/.worktrees/v6-realtime-live"
  mkdir -p "$R/.fable-team/bin" "$R/.fable-team/comm" "$V/.fable-team/bin" "$base/launchagents"
  local s; for s in "$@"; do : > "$R/.fable-team/bin/$s"; done
  python3 - "$base" "$R" "$V" <<'PY'
import os, plistlib, sys
base, R, V = sys.argv[1:4]
LA = os.path.join(base, "launchagents")
V6B = V + "/.fable-team/bin"
def dump(n, d): plistlib.dump(d, open(os.path.join(LA, n + ".plist"), "wb"))
dump("com.byz.ft-resource-watch", {"Label": "com.byz.ft-resource-watch",
     "ProgramArguments": ["/opt/homebrew/bin/bash", V6B + "/ft-resource-watch.sh"]})                 # MIGRATE 1
dump("com.byz.ft-tick", {"Label": "com.byz.ft-tick", "WorkingDirectory": V})                         # MIGRATE 1
dump("com.byz.ft-weekly-review", {"Label": "com.byz.ft-weekly-review",
     "EnvironmentVariables": {"FT_LIVE_BIN": V6B, "FT_PLANNER_REPO": V}})                            # MIGRATE 2
dump("com.hermes.byz-slack-talk-inbound", {"Label": "com.hermes.byz-slack-talk-inbound",
     "ProgramArguments": ["a"] * 12 + [V6B + "/ft-inbox.sh"]})                                       # MIGRATE 1 (인덱스 12)
dump("com.hermes.byz-slack-mbox-inbound", {"Label": "com.hermes.byz-slack-mbox-inbound",
     "ProgramArguments": ["a"] * 11 + [V6B + "/ft-inbox.sh"]})                                       # MIGRATE 1 (인덱스 11)
dump("com.byz.ft-tick-cfo", {"Label": "com.byz.ft-tick-cfo",
     "EnvironmentVariables": {"FT_TICK_MASTER_MSG": "본문에 " + V6B + "/ft-inbox.sh 가 있다"}})        # REPORT(사람 글)
dump("com.byz.serena-ensure", {"Label": "com.byz.serena-ensure",
     "ProgramArguments": ["a", "b", "c", V]})                                                         # REPORT(비대상 라벨)
dump("dev.byz.v6-rate-limit-resume", {"Label": "dev.byz.v6-rate-limit-resume", "WorkingDirectory": V})  # REPORT(비대상)
dump("dev.byz.v6-rate-limit-resume-once-20260628-1803",
     {"Label": "dev.byz.v6-rate-limit-resume-once-20260628-1803", "WorkingDirectory": V})             # REPORT(비대상)
for t in "ccu chatbot feature cfo graphics issues kk knowledge ops harness planner".split():
    d = os.path.join(R, ".fable-team", "bin-" + t); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, t + "-env.sh"), "w").write(
        "# " + t + " env — 주석 줄의 v6 글자는 그대로\n" + "export FT_BIN=" + V6B + "\n" + "export FT_OTHER=" + V + "\n")
PY
}
F1="$TMP/f1"; build "$F1" ft-resource-watch.sh ft-inbox.sh ft-tick.sh ft-seat-status.sh
R="$F1/root"; V="$R/.worktrees/v6-realtime-live"; LA="$F1/launchagents"; TEAMS="$R/.fable-team"
run() { env -u FT_ROOT -u FT_MBOX_DIR bash "$1" --root "$R" --from-wt "$V" --launchagents "$LA" --teams-dir "$TEAMS" "${@:2}" 2>&1; echo "rc=$?"; }
rc()    { printf '%s\n' "$1" | sed -n 's/^rc=//p'; }
cnt()   { printf '%s\n' "$1" | awk -F'\t' -v k="$2" '$1==k' | wc -l | tr -d ' '; }
cell()  { printf '%s\n' "$1" | awk -F'\t' -v k="$2" -v f="$3" -v n="$4" '$1==k && $2==f {print $n}'; }
pk()    { python3 -c 'import plistlib,sys
node = plistlib.load(open(sys.argv[1],"rb"))
for k in sys.argv[2].split("/"): node = node[int(k)] if isinstance(node, list) else node[k]
print(node)' "$1" "$2" 2>/dev/null; }
baks()  { ls "$LA"/*.bak-r962 "$TEAMS"/bin-*/*.bak-r962 2>/dev/null | wc -l | tr -d ' '; }
shaall() { shasum -a 256 "$LA"/*.plist "$TEAMS"/bin-*/*-env.sh | awk '{print $1}' | sort | shasum -a 256 | awk '{print $1}'; }

# ── ⓜ dry-run: 표 칸 수 일치 · 파일 바이트 불변 ──
before="$(shaall)"
o="$(run "$TOOL")"
chk "ⓜ dry-run rc" "$(rc "$o")" 0
chk "ⓜ MIGRATE = plist 6 + env 11" "$(cnt "$o" MIGRATE)" 17
chk "ⓜ REPORT = 4 (사람 글 1 · 비대상 라벨 3)" "$(cnt "$o" REPORT)" 4
chk "ⓜ ERROR 0" "$(cnt "$o" ERROR)" 0
chk "ⓜ SUM 칸" "$(printf '%s\n' "$o" | grep -c '^SUM	mode=dry-run	plist_migrate=6 plist_report=4 plist_error=0 env_migrate=11 env_report=0 env_error=0')" 1
chk "ⓜ plist 값 줄(ft-tick WorkingDirectory)" "$(cell "$o" MIGRATE "$LA/com.byz.ft-tick.plist" 5)" "$R"
chk "ⓜ bin 파일 값 줄(resource-watch)" "$(cell "$o" MIGRATE "$LA/com.byz.ft-resource-watch.plist" 5)" "$R/.fable-team/bin/ft-resource-watch.sh"
chk "ⓜ 비대상 라벨은 REPORT(파일명·내부 Label 병기)" "$(printf '%s\n' "$o" | grep -c "^REPORT	$LA/com.byz.serena-ensure.plist	Label	비관리 Label(파일명=com.byz.serena-ensure · Label=com.byz.serena-ensure)")" 1
chk "ⓜ dry-run 파일 바이트 불변" "$(shaall)" "$before"
chk "ⓜ dry-run .bak 0" "$(baks)" 0

# ── ⓝ apply: «이전» 칸만 바뀜 · 보고만 불변 · .bak · 멱등 ──
cp -a "$LA" "$TMP/before-LA"; cp -a "$TEAMS" "$TMP/before-TEAMS"
o="$(run "$TOOL" --apply)"
chk "ⓝ apply rc" "$(rc "$o")" 0
chk "ⓝ apply MIGRATE = 17" "$(cnt "$o" MIGRATE)" 17
chk "ⓝ ft-tick WorkingDirectory = 공용 루트" "$(pk "$LA/com.byz.ft-tick.plist" WorkingDirectory)" "$R"
chk "ⓝ resource-watch ProgramArguments[1] = 공용 bin" "$(pk "$LA/com.byz.ft-resource-watch.plist" ProgramArguments/1)" "$R/.fable-team/bin/ft-resource-watch.sh"
chk "ⓝ weekly-review FT_LIVE_BIN = 공용 bin" "$(pk "$LA/com.byz.ft-weekly-review.plist" EnvironmentVariables/FT_LIVE_BIN)" "$R/.fable-team/bin"
chk "ⓝ weekly-review FT_PLANNER_REPO = 공용 루트" "$(pk "$LA/com.byz.ft-weekly-review.plist" EnvironmentVariables/FT_PLANNER_REPO)" "$R"
chk "ⓝ slack-talk ProgramArguments[12] = 공용 bin" "$(pk "$LA/com.hermes.byz-slack-talk-inbound.plist" ProgramArguments/12)" "$R/.fable-team/bin/ft-inbox.sh"
chk "ⓝ slack-mbox ProgramArguments[11] = 공용 bin" "$(pk "$LA/com.hermes.byz-slack-mbox-inbound.plist" ProgramArguments/11)" "$R/.fable-team/bin/ft-inbox.sh"
chk "ⓝ 보고만(사람 글) 바이트 불변" "$(cmp -s "$LA/com.byz.ft-tick-cfo.plist" "$TMP/before-LA/com.byz.ft-tick-cfo.plist" && echo same || echo differ)" same
chk "ⓝ 보고만(비대상 serena) 바이트 불변" "$(cmp -s "$LA/com.byz.serena-ensure.plist" "$TMP/before-LA/com.byz.serena-ensure.plist" && echo same || echo differ)" same
chk "ⓝ 보고만(비대상 dev 2) 바이트 불변" "$(cmp -s "$LA/dev.byz.v6-rate-limit-resume.plist" "$TMP/before-LA/dev.byz.v6-rate-limit-resume.plist" && cmp -s "$LA/dev.byz.v6-rate-limit-resume-once-20260628-1803.plist" "$TMP/before-LA/dev.byz.v6-rate-limit-resume-once-20260628-1803.plist" && echo same || echo differ)" same
chk "ⓝ env FT_BIN = 공용 bin (전 11)" "$(grep -l "^export FT_BIN=$R/.fable-team/bin$" "$TEAMS"/bin-*/*-env.sh | wc -l | tr -d ' ')" 11
chk "ⓝ env 다른 줄 불변(FT_OTHER 는 v6 그대로)" "$(grep -l "^export FT_OTHER=$V$" "$TEAMS"/bin-*/*-env.sh | wc -l | tr -d ' ')" 11
chk "ⓝ env 주석 줄 불변" "$(grep -c '주석 줄의 v6 글자는 그대로' "$TEAMS/bin-ops/ops-env.sh")" 1
chk "ⓝ .bak-r962 = plist 5 + env 11" "$(baks)" 16
chk "ⓝ 값 바뀐 plist lint" "$(plutil -lint "$LA/com.byz.ft-tick.plist" >/dev/null 2>&1 && echo ok || echo bad)" ok
o="$(run "$TOOL" --apply)"
chk "ⓝ 재실행 rc·MIGRATE 0(멱등)" "$(rc "$o")/$(cnt "$o" MIGRATE)" "0/0"
chk "ⓝ 재실행 .bak 16 그대로" "$(baks)" 16

# ── 변이 9: «값 부분 일치로 이전» → 사람 글이 바뀐다(ⓝ FAIL) ──
python3 - "$TOOL" "$TMP/mut-partial.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = '    if v == V: return "migrate", R'
new = '    if V in v: return "migrate", R   # 변이: 부분 일치'
assert src.count(old) == 1, "값 판정 줄 1곳: %d" % src.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new, 1))
PY
chk "변 9 사본이 실제로 바뀌었다" "$(cmp -s "$TOOL" "$TMP/mut-partial.sh" && echo same || echo changed)" changed
F2="$TMP/f2"; build "$F2" ft-resource-watch.sh ft-inbox.sh ft-tick.sh ft-seat-status.sh
R="$F2/root"; V="$R/.worktrees/v6-realtime-live"; LA="$F2/launchagents"; TEAMS="$R/.fable-team"
cp -a "$LA/com.byz.ft-tick-cfo.plist" "$TMP/cfo-before.plist"
o="$(run "$TMP/mut-partial.sh" --apply)"
chk "변 9 «값 부분 일치로 이전» → ⓝ FAIL(사람 글 바뀜)" "$(cmp -s "$LA/com.byz.ft-tick-cfo.plist" "$TMP/cfo-before.plist" && echo caught || echo leaked)" leaked

# ── 변이 10: «.bak 없이 쓰기» → 백업 0(ⓝ FAIL) ──
python3 - "$TOOL" "$TMP/mut-nobak.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = '        os.replace(tmp, bak)'
new = '        os.remove(tmp)   # 변이: .bak 없이 쓰기'
assert src.count(old) == 1, "백업 줄 1곳: %d" % src.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new, 1))
PY
chk "변 10 사본이 실제로 바뀌었다" "$(cmp -s "$TOOL" "$TMP/mut-nobak.sh" && echo same || echo changed)" changed
F3="$TMP/f3"; build "$F3" ft-resource-watch.sh ft-inbox.sh ft-tick.sh ft-seat-status.sh
R="$F3/root"; V="$R/.worktrees/v6-realtime-live"; LA="$F3/launchagents"; TEAMS="$R/.fable-team"
o="$(run "$TMP/mut-nobak.sh" --apply)"
chk "변 10 «.bak 없이 쓰기» → ⓝ FAIL(.bak 0)" "$(baks)/$(pk "$LA/com.byz.ft-tick.plist" WorkingDirectory)" "0/$R"

# ── ⓞ 새 값 실재 0 → 그 파일 불변 + rc≠0 · 다른 파일은 진행 ──
F4="$TMP/f4"; build "$F4" ft-inbox.sh ft-tick.sh ft-seat-status.sh      # ft-resource-watch.sh 없음
R="$F4/root"; V="$R/.worktrees/v6-realtime-live"; LA="$F4/launchagents"; TEAMS="$R/.fable-team"
cp -a "$LA/com.byz.ft-resource-watch.plist" "$TMP/rw-before.plist"
o="$(run "$TOOL" --apply)"
chk "ⓞ 새 값 없음 → rc≠0" "$(rc "$o")" 1
chk "ⓞ ERROR 1줄(그 칸)" "$(cnt "$o" ERROR)" 1
chk "ⓞ 그 파일 바이트 불변" "$(cmp -s "$LA/com.byz.ft-resource-watch.plist" "$TMP/rw-before.plist" && echo same || echo differ)" same
chk "ⓞ 다른 파일은 진행(ft-tick)" "$(pk "$LA/com.byz.ft-tick.plist" WorkingDirectory)" "$R"
chk "ⓞ env 도 진행(11)" "$(grep -l "^export FT_BIN=$R/.fable-team/bin$" "$TEAMS"/bin-*/*-env.sh | wc -l | tr -d ' ')" 11
chk "ⓞ 그 파일 .bak 0(안 건드렸다)" "$([ -e "$LA/com.byz.ft-resource-watch.plist.bak-r962" ] && echo yes || echo no)" no

# ── 공용 루트 해석 = 기존 함수(ft_repo_root) — --root 없이 git 공용 루트에서 ──
G="$TMP/grepo"; mkdir -p "$G/.fable-team/bin" "$G/.fable-team/comm"; git -C "$G" init -q -b main
git -C "$G" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
cp "$TOOL" "$G/.fable-team/bin/"; cp "$KBIN/ft-harness-root.sh" "$G/.fable-team/bin/"
mkdir -p "$TMP/gla"; python3 - "$TMP/gla" "$G" <<'PY'
import os, plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick", "WorkingDirectory": sys.argv[2] + "/.worktrees/v6-realtime-live"},
              open(os.path.join(sys.argv[1], "com.byz.ft-tick.plist"), "wb"))
PY
o="$( cd "$G" && env -u FT_ROOT -u FT_MBOX_DIR bash "$G/.fable-team/bin/ft-root-bin-migrate.sh" --launchagents "$TMP/gla" --teams-dir "$G/.fable-team" 2>&1; echo "rc=$?")"
chk "루트 해석(기존 함수) rc" "$(rc "$o")" 0              # 새 값 = G(<공용 루트>) 가 실재하므로 ERROR 0
chk "루트 해석(기존 함수) = git 공용 루트" "$(cell "$o" MIGRATE "$TMP/gla/com.byz.ft-tick.plist" 5)" "$G"

# ══ ⓠ~ⓣ r5: 내부 Label 정본 · 제자리 치환 · env 바이트 보존 (REWORK-r962-r5 · 리서치 §2-3·§3-1·§3-2) ══
# ── ⓠ 관리 라벨 정본 = plist 내부 Label(파일명 0) ──
Q="$TMP/q"; QR="$Q/root"; QV="$QR/.worktrees/v6-realtime-live"; QLA="$Q/launchagents"
mkdir -p "$QR/.fable-team/bin" "$QV/.fable-team/bin" "$QLA"
python3 - "$QLA" "$QV" <<'PY'
import os, plistlib, sys
LA, V = sys.argv[1:3]
plistlib.dump({"Label": "dev.example.unmanaged", "WorkingDirectory": V}, open(os.path.join(LA, "com.byz.ft-tick-renamed.plist"), "wb"))
plistlib.dump({"WorkingDirectory": V}, open(os.path.join(LA, "com.byz.ft-nolabel.plist"), "wb"))
plistlib.dump({"Label": "com.byz.ft-weekly-review", "WorkingDirectory": V}, open(os.path.join(LA, "com.byz.ft-alias.plist"), "wb"))
PY
cp -a "$QLA" "$TMP/q-before"
o="$(run "$TOOL" --apply --root "$QR" --from-wt "$QV" --launchagents "$QLA" --teams-dir "$QR/.fable-team")"
chk "ⓠ 비관리 Label(파일명은 관리) → 그 파일은 이전 0(이전은 alias 1건뿐)" "$(cnt "$o" MIGRATE)" 1
chk "ⓠ 비관리 Label → REPORT 병기(파일명·Label 둘 다)" "$(printf '%s\n' "$o" | grep -c "^REPORT	$QLA/com.byz.ft-tick-renamed.plist	Label	비관리 Label(파일명=com.byz.ft-tick-renamed · Label=dev.example.unmanaged)")" 1
chk "ⓠ 비관리 Label → 그 파일 바이트 불변" "$(cmp -s "$QLA/com.byz.ft-tick-renamed.plist" "$TMP/q-before/com.byz.ft-tick-renamed.plist" && echo same || echo differ)" same
chk "ⓠ Label 없음 → ERROR 1줄" "$(printf '%s\n' "$o" | grep -c "^ERROR	$QLA/com.byz.ft-nolabel.plist	Label")" 1
chk "ⓠ Label 없음 → 그 파일 바이트 불변" "$(cmp -s "$QLA/com.byz.ft-nolabel.plist" "$TMP/q-before/com.byz.ft-nolabel.plist" && echo same || echo differ)" same
chk "ⓠ 파일명≠Label(둘 다 관리) → 이전한다" "$(pk "$QLA/com.byz.ft-alias.plist" WorkingDirectory)" "$QR"
chk "ⓠ 파일명≠Label → REPORT 병기 1줄" "$(printf '%s\n' "$o" | grep -c "^REPORT	$QLA/com.byz.ft-alias.plist	Label")" 1
chk "ⓠ ERROR 가 있으면 rc≠0" "$(rc "$o")" 1
chk "ⓠ RELOAD_NEEDED = 내부 Label(weekly-review)" "$(printf '%s\n' "$o" | grep -c '^RELOAD_NEEDED.*com.byz.ft-weekly-review')" 1
chk "ⓠ RELOAD_NEEDED 에 파일명(alias) 0" "$(printf '%s\n' "$o" | grep -c '^RELOAD_NEEDED.*ft-alias')" 0

# ── ⓠ2 plistlib 이 못 읽는 옛 꼴(주석 안 `--` = XML 위반 · 라이브에 실제 3건) — Label 만은 텍스트에서 읽고 쓰기 0 ──
Q3="$TMP/q3"; Q3R="$Q3/root"; Q3V="$Q3R/.worktrees/v6-realtime-live"
mkdir -p "$Q3R/.fable-team/bin" "$Q3V/.fable-team/bin" "$Q3/launchagents"
python3 - "$Q3/launchagents/com.byz.ft-legacy.plist" "$Q3V" <<'PY2'
import sys
xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<!-- 주석에 --unlock-only 같은 -- 가 있다 -->\n<plist version="1.0">\n<dict>\n'
       '    <key>Label</key><string>com.byz.ft-legacy</string>\n'
       '    <key>WorkingDirectory</key><string>' + sys.argv[2] + '</string>\n'
       '</dict>\n</plist>\n')
open(sys.argv[1], "w", encoding="utf-8").write(xml)
PY2
cp -a "$Q3/launchagents/com.byz.ft-legacy.plist" "$TMP/q3-before.plist"
o="$(run "$TOOL" --apply --root "$Q3R" --from-wt "$Q3V" --launchagents "$Q3/launchagents" --teams-dir "$Q3R/.fable-team")"
chk "ⓠ2 못 읽는 옛 꼴 → REPORT(Label 병기)·ERROR 0" "$(printf '%s\n' "$o" | grep -c "^REPORT.$Q3/launchagents/com.byz.ft-legacy.plist.Label.plistlib 로 못 읽음")" 1
chk "ⓠ2 ERROR 0 · rc 0" "$(cnt "$o" ERROR)/$(rc "$o")" "0/0"
chk "ⓠ2 그 파일 바이트 불변" "$(cmp -s "$Q3/launchagents/com.byz.ft-legacy.plist" "$TMP/q3-before.plist" && echo same || echo differ)" same

# ── 변이 11: «파일명 판정 되살림» → ⓠ FAIL(비관리 라벨 plist 가 이전된다) ──
python3 - "$TOOL" "$TMP/mut-fname.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = '    managed = bool(LABEL_RE.match(label))   # 하네스 관리 라벨만 «이전» — 그 밖 라벨은 보고만(계약 ③)'
new = '    label = os.path.basename(path)[:-6]   # 변이: 파일명 판정\n    managed = bool(LABEL_RE.match(label))'
assert src.count(old) == 1, "managed 판정 줄 1곳: %d" % src.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new, 1))
PY
chk "변 11 사본이 실제로 바뀌었다" "$(cmp -s "$TOOL" "$TMP/mut-fname.sh" && echo same || echo changed)" changed
Q2="$TMP/q2"; Q2R="$Q2/root"; Q2V="$Q2R/.worktrees/v6-realtime-live"
mkdir -p "$Q2R/.fable-team/bin" "$Q2V/.fable-team/bin" "$Q2/launchagents"
python3 - "$Q2/launchagents" "$Q2V" <<'PY'
import os, plistlib, sys
plistlib.dump({"Label": "dev.example.unmanaged", "WorkingDirectory": sys.argv[2]},
              open(os.path.join(sys.argv[1], "com.byz.ft-tick-renamed.plist"), "wb"))
PY
cp -a "$Q2/launchagents/com.byz.ft-tick-renamed.plist" "$TMP/q2-before.plist"
run "$TMP/mut-fname.sh" --apply --root "$Q2R" --from-wt "$Q2V" --launchagents "$Q2/launchagents" --teams-dir "$Q2R/.fable-team" >/dev/null
chk "변 11 «파일명 판정 되살림» → ⓠ FAIL(비관리 라벨이 이전됨)" "$(cmp -s "$Q2/launchagents/com.byz.ft-tick-renamed.plist" "$TMP/q2-before.plist" && echo caught || echo leaked)" leaked

# ── ⓡ env = bytes · CRLF 보존 ──
E="$TMP/e"; ER="$E/root"; EV="$ER/.worktrees/v6-realtime-live"; EB="$ER/.fable-team/bin"; E6="$EV/.fable-team/bin"
mkdir -p "$EB" "$E6" "$ER/.fable-team/bin-ops" "$E/launchagents"
python3 - "$ER/.fable-team/bin-ops/ops-env.sh" "$E6" "$EV" <<'PY'
import sys
open(sys.argv[1], "wb").write(b"# keep-this-comment\r\nexport FT_BIN=" + sys.argv[2].encode() + b"\r\nexport FT_OTHER=" + sys.argv[3].encode() + b"\r\n")
PY
o="$(run "$TOOL" --apply --root "$ER" --from-wt "$EV" --launchagents "$E/launchagents" --teams-dir "$ER/.fable-team")"
chk "ⓡ env MIGRATE 1" "$(cnt "$o" MIGRATE)" 1
chk "ⓡ 바꾼 줄만 · CRLF·주석 바이트 보존" "$(python3 -c 'import sys;print(repr(open(sys.argv[1],"rb").read()))' "$ER/.fable-team/bin-ops/ops-env.sh")" "$(python3 -c 'import sys;print(repr(b"# keep-this-comment\r\nexport FT_BIN=" + sys.argv[1].encode() + b"\r\nexport FT_OTHER=" + sys.argv[2].encode() + b"\r\n"))' "$EB" "$EV")"
chk "ⓡ CRLF 3줄 유지" "$(python3 -c 'import sys;print(open(sys.argv[1],"rb").read().count(b"\r\n"))' "$ER/.fable-team/bin-ops/ops-env.sh")" 3
python3 - "$TOOL" "$TMP/mut-textmode.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = '        try: data = open(f, "rb").read()'
new = '        try: data = open(f, encoding="utf-8").read().encode()   # 변이: text mode 읽기(universal newline)'
assert src.count(old) == 1, "env 읽기 줄 1곳: %d" % src.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new, 1))
PY
chk "변 12 사본이 실제로 바뀌었다" "$(cmp -s "$TOOL" "$TMP/mut-textmode.sh" && echo same || echo changed)" changed
E2="$TMP/e2"; E2R="$E2/root"; E2V="$E2R/.worktrees/v6-realtime-live"; E26="$E2V/.fable-team/bin"
mkdir -p "$E2R/.fable-team/bin" "$E26" "$E2R/.fable-team/bin-ops" "$E2/launchagents"
python3 - "$E2R/.fable-team/bin-ops/ops-env.sh" "$E26" <<'PY'
import sys
open(sys.argv[1], "wb").write(b"# keep-this-comment\r\nexport FT_BIN=" + sys.argv[2].encode() + b"\r\n")
PY
run "$TMP/mut-textmode.sh" --apply --root "$E2R" --from-wt "$E2V" --launchagents "$E2/launchagents" --teams-dir "$E2R/.fable-team" >/dev/null
chk "변 12 «text mode 읽기» → ⓡ FAIL(CRLF 소실)" "$(python3 -c 'import sys;print(open(sys.argv[1],"rb").read().count(b"\r\n"))' "$E2R/.fable-team/bin-ops/ops-env.sh")" 0

# ── ⓢ plist 주석·들여쓰기 보존 · 값만 제자리 치환 · escape ──
S="$TMP/s"; SR="$S/ro&ot"; SV="$SR/.worktrees/v6-realtime-live"
mkdir -p "$SR/.fable-team/bin" "$SV/.fable-team/bin" "$S/launchagents"
python3 - "$S/launchagents/com.byz.ft-tick.plist" "$SV" <<'PY'
import sys
xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<!-- KEEP_COMMENT -->\n<plist version="1.0">\n<dict>\n'
       '    <key>Label</key>\n    <string>com.byz.ft-tick</string>\n'
       '    <key>WorkingDirectory</key>\n    <string>' + sys.argv[2].replace("&", "&amp;") + '</string>\n'
       '</dict>\n</plist>\n')
open(sys.argv[1], "w", encoding="utf-8").write(xml)
PY
cp -a "$S/launchagents/com.byz.ft-tick.plist" "$TMP/s-before.plist"
o="$(run "$TOOL" --apply --root "$SR" --from-wt "$SV" --launchagents "$S/launchagents" --teams-dir "$SR/.fable-team")"
chk "ⓢ apply rc" "$(rc "$o")" 0
chk "ⓢ 주석 보존" "$(grep -c '<!-- KEEP_COMMENT -->' "$S/launchagents/com.byz.ft-tick.plist")" 1
chk "ⓢ 값 줄만 바뀜(diff 2줄 = 값 한 줄)" "$(diff "$TMP/s-before.plist" "$S/launchagents/com.byz.ft-tick.plist" | grep -c '^[<>]')" 2
chk "ⓢ 파일 안 값 = &amp; 로 이스케이프" "$(grep -c 'ro&amp;ot' "$S/launchagents/com.byz.ft-tick.plist")" 1
chk "ⓢ 재해석 값 = 실제 경로" "$(pk "$S/launchagents/com.byz.ft-tick.plist" WorkingDirectory)" "$SR"
chk "ⓢ 재해석 dict 는 바꼈 key 만 다르다" "$(python3 -c 'import plistlib,sys
a = plistlib.load(open(sys.argv[1],"rb")); b = plistlib.load(open(sys.argv[2],"rb"))
print(sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k)))' "$TMP/s-before.plist" "$S/launchagents/com.byz.ft-tick.plist")" "['WorkingDirectory']"
chk "ⓢ plutil -lint" "$(plutil -lint "$S/launchagents/com.byz.ft-tick.plist" >/dev/null 2>&1 && echo ok || echo bad)" ok
python3 - "$TOOL" "$TMP/mut-dumps.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = ('    out = raw\n'
       '    for s, e, nb in sorted(edits, reverse=True):\n'
       '        out = out[:s] + nb + out[e:]')
new = ('    for p, old, new in rows: set_path(d, p, new)\n'
       '    out = plistlib.dumps(d, fmt=plistlib.FMT_XML)   # 변이: 전체 재직렬화(plistlib dumps)')
assert src.count(old) == 1, "제자리 치환 줄 1곳: %d" % src.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new, 1))
PY
chk "변 13 사본이 실제로 바뀌었다" "$(cmp -s "$TOOL" "$TMP/mut-dumps.sh" && echo same || echo changed)" changed
S2="$TMP/s2"; S2R="$S2/root"; S2V="$S2R/.worktrees/v6-realtime-live"
mkdir -p "$S2R/.fable-team/bin" "$S2V/.fable-team/bin" "$S2/launchagents"
python3 - "$S2/launchagents/com.byz.ft-tick.plist" "$S2V" <<'PY'
import sys
xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<!-- KEEP_COMMENT -->\n<plist version="1.0">\n<dict>\n'
       '    <key>Label</key>\n    <string>com.byz.ft-tick</string>\n'
       '    <key>WorkingDirectory</key>\n    <string>' + sys.argv[2].replace("&", "&amp;") + '</string>\n'
       '</dict>\n</plist>\n')
open(sys.argv[1], "w", encoding="utf-8").write(xml)
PY
run "$TMP/mut-dumps.sh" --apply --root "$S2R" --from-wt "$S2V" --launchagents "$S2/launchagents" --teams-dir "$S2R/.fable-team" >/dev/null
chk "변 13 «plistlib dumps 되살림» → ⓢ FAIL(주석 소실)" "$(grep -c '<!-- KEEP_COMMENT -->' "$S2/launchagents/com.byz.ft-tick.plist")" 0

# ── ⓣ 같은 값이 두 key에 → 대상 key 만 바뀜(위치 기반 — 전역 replace 0) ──
T="$TMP/t"; TR="$T/root"; TV="$TR/.worktrees/v6-realtime-live"
mkdir -p "$TR/.fable-team/bin" "$TV/.fable-team/bin" "$T/launchagents"
python3 - "$T/launchagents/com.byz.ft-tick.plist" "$TV" <<'PY'
import plistlib, sys
V = sys.argv[2]
plistlib.dump({"Label": "com.byz.ft-tick", "WorkingDirectory": V,
               "EnvironmentVariables": {"FT_KEEP": V + "/sub"}}, open(sys.argv[1], "wb"))
PY
o="$(run "$TOOL" --apply --root "$TR" --from-wt "$TV" --launchagents "$T/launchagents" --teams-dir "$TR/.fable-team")"
chk "ⓣ 대상 key 만 바뀜" "$(pk "$T/launchagents/com.byz.ft-tick.plist" WorkingDirectory)" "$TR"
chk "ⓣ 같은 값을 품은 다른 key 는 불변" "$(pk "$T/launchagents/com.byz.ft-tick.plist" EnvironmentVariables/FT_KEEP)" "$TV/sub"
chk "ⓣ 다른 key 는 REPORT(이전 0)" "$(cell "$o" REPORT "$T/launchagents/com.byz.ft-tick.plist" 4)" "$TV/sub"

# ══ ⓤ~ⓦ r988 r1: 주석 속 태그 · 불완전 백업 재사용 0 · 복원 쓰기 0 (DA⑥ r1 수용 3) ══
mt() { python3 -c 'import os,sys;print(os.stat(sys.argv[1]).st_mtime_ns)' "$1" 2>/dev/null; }
sz() { stat -f %z "$1" 2>/dev/null; }

# ── ⓤ 관리 plist 의 key 와 값 사이 주석 속 <string> 태그는 «값» 이 아니다 ──
U="$TMP/u"; UR="$U/root"; UV="$UR/.worktrees/v6-realtime-live"
mkdir -p "$UR/.fable-team/bin" "$UV/.fable-team/bin" "$U/launchagents"
python3 - "$U/launchagents/com.byz.ft-tick.plist" "$UV" <<'PY'
import sys
xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n'
       '    <key>Label</key>\n    <string>com.byz.ft-tick</string>\n'
       '    <key>WorkingDirectory</key>\n'
       '    <!-- <string>example</string> -->\n'
       '    <string>' + sys.argv[2] + '</string>\n'
       '    <key>EnvironmentVariables</key>\n    <dict>\n'
       '        <key>NOTE</key>\n        <!-- <string>note-example</string>\n             <string>second</string> -->\n'
       '        <string>plain note</string>\n'
       '    </dict>\n</dict>\n</plist>\n')
open(sys.argv[1], "w", encoding="utf-8").write(xml)
PY
o="$(run "$TOOL" --apply --root "$UR" --from-wt "$UV" --launchagents "$U/launchagents" --teams-dir "$UR/.fable-team")"
chk "ⓤ 주석 속 태그 → 치환 성공 · 주석 바이트 보존(2줄) · 다른 값 그대로" \
  "$(rc "$o")|$(pk "$U/launchagents/com.byz.ft-tick.plist" WorkingDirectory)|$(grep -c '<!-- <string>' "$U/launchagents/com.byz.ft-tick.plist")|$(pk "$U/launchagents/com.byz.ft-tick.plist" EnvironmentVariables/NOTE)" \
  "0|$UR|2|plain note"

# ── ⓥ 불완전 백업이 남아 있으면 «재사용 0» — 원본을 건드리지 않는다(DA⑤) ──
V5="$TMP/v5"; V5R="$V5/root"; V5V="$V5R/.worktrees/v6-realtime-live"
mkdir -p "$V5R/.fable-team/bin" "$V5V/.fable-team/bin" "$V5/launchagents"
python3 - "$V5/launchagents/com.byz.ft-tick.plist" "$V5V" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick", "WorkingDirectory": sys.argv[2]}, open(sys.argv[1], "wb"))
PY
python3 - "$TOOL" "$TMP/mut-bakfail.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = ('        with open(tmp, "wb") as fh:\n'
       '            fh.write(src); fh.flush(); os.fsync(fh.fileno())\n'
       '        if open(tmp, "rb").read() != src: raise OSError("백업 대조 불일치")\n'
       '        os.replace(tmp, bak)')
new = ('        with open(bak, "wb") as fh: fh.write(src[:16])   # 주입: 1회차 백업 쓰기 실패(ENOSPC) → 불완전 백업\n'
       '        raise OSError("주입: ENOSPC")')
assert src.count(old) == 1, "백업 쓰기 줄 1곳: %d" % src.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new, 1))
PY
cp -a "$V5/launchagents/com.byz.ft-tick.plist" "$TMP/v5-before.plist"
o1="$(run "$TMP/mut-bakfail.sh" --apply --root "$V5R" --from-wt "$V5V" --launchagents "$V5/launchagents" --teams-dir "$V5R/.fable-team")"
o2="$(run "$TOOL" --apply --root "$V5R" --from-wt "$V5V" --launchagents "$V5/launchagents" --teams-dir "$V5R/.fable-team")"
chk "ⓥ 불완전 백업 → 2회차 재사용 0 · 원본 바이트 불변 · 백업 덮어쓰기 0" \
  "$(rc "$o2")|$(cmp -s "$V5/launchagents/com.byz.ft-tick.plist" "$TMP/v5-before.plist" && echo same || echo differ)|$(sz "$V5/launchagents/com.byz.ft-tick.plist.bak-r962")|$(printf '%s\n' "$o2" | grep -c '^ERROR.*백업 불일치')" \
  "1|same|16|1"
chk "ⓥ 1회차(백업 쓰기 실패)도 원본 그대로 · rc≠0" \
  "$(rc "$o1")|$(cmp -s "$V5/launchagents/com.byz.ft-tick.plist" "$TMP/v5-before.plist" && echo same || echo differ)" "1|same"

# ── ⓦ plutil 실패 = 복원 쓰기 0 — 원본을 «열지 않는다»(바이트·mtime 불변) (DA⑤) ──
W="$TMP/w"; WR="$W/root"; WV="$WR/.worktrees/v6-realtime-live"
mkdir -p "$WR/.fable-team/bin" "$WV/.fable-team/bin" "$W/launchagents"
python3 - "$W/launchagents/com.byz.ft-tick.plist" "$WV" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick", "WorkingDirectory": sys.argv[2]}, open(sys.argv[1], "wb"))
PY
python3 - "$TOOL" "$TMP/mut-plutilfail.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = 'def plutil_lint(path):\n    if not shutil.which("plutil"): return None'
new = 'def plutil_lint(path):\n    return 1   # 주입: plutil -lint 실패\n    if not shutil.which("plutil"): return None'
assert src.count(old) == 1, "plutil_lint 첫 줄 1곳: %d" % src.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new, 1))
PY
cp -a "$W/launchagents/com.byz.ft-tick.plist" "$TMP/w-before.plist"
mt0="$(mt "$W/launchagents/com.byz.ft-tick.plist")"
o="$(run "$TMP/mut-plutilfail.sh" --apply --root "$WR" --from-wt "$WV" --launchagents "$W/launchagents" --teams-dir "$WR/.fable-team")"
chk "ⓦ plutil 실패 → 원본 바이트·mtime 불변(복원 쓰기 0) · rc≠0 · «.bak 복원» 문구 0" \
  "$(rc "$o")|$(cmp -s "$W/launchagents/com.byz.ft-tick.plist" "$TMP/w-before.plist" && echo same || echo differ)|$( [ "$(mt "$W/launchagents/com.byz.ft-tick.plist")" = "$mt0" ] && echo same || echo changed)|$(printf '%s\n' "$o" | grep -c '쓰기 0(원본 그대로)')|$(printf '%s\n' "$o" | grep -c '\.bak 복원')" \
  "1|same|same|1|0"

# ── 변이 14: «백업 대조 끔» → ⓥ FAIL(불완전 백업을 재사용해 원본이 바뀐다) ──
python3 - "$TOOL" "$TMP/mut-nocmp.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = '        return bak if same else None          # 기존 백업이 원본과 바이트 다르다 = 보고만 아님, 쓰기 0'
new = '        return bak   # 변이: 백업 대조 끔'
assert src.count(old) == 1, "백업 대조 줄 1곳: %d" % src.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new, 1))
PY
chk "변 14 사본이 실제로 바뀌었다" "$(cmp -s "$TOOL" "$TMP/mut-nocmp.sh" && echo same || echo changed)" changed
F6="$TMP/f6"; F6R="$F6/root"; F6V="$F6R/.worktrees/v6-realtime-live"
mkdir -p "$F6R/.fable-team/bin" "$F6V/.fable-team/bin" "$F6/launchagents"
python3 - "$F6/launchagents/com.byz.ft-tick.plist" "$F6V" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick", "WorkingDirectory": sys.argv[2]}, open(sys.argv[1], "wb"))
PY
head -c 16 "$F6/launchagents/com.byz.ft-tick.plist" > "$F6/launchagents/com.byz.ft-tick.plist.bak-r962"   # 불완전 백업
cp -a "$F6/launchagents/com.byz.ft-tick.plist" "$TMP/f6-before.plist"
run "$TMP/mut-nocmp.sh" --apply --root "$F6R" --from-wt "$F6V" --launchagents "$F6/launchagents" --teams-dir "$F6R/.fable-team" >/dev/null
chk "변 14 «백업 대조 끔» → ⓥ FAIL(불완전 백업 재사용해 원본이 바뀜)" \
  "$(cmp -s "$F6/launchagents/com.byz.ft-tick.plist" "$TMP/f6-before.plist" && echo caught || echo leaked)" leaked

# ── 변이 15: «원본 wb 되살림» → ⓦ FAIL(원본을 다시 열어 mtime 이 바뀐다) ──
python3 - "$TOOL" "$TMP/mut-restorewb.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = ('def plutil_lint(path):\n    if not shutil.which("plutil"): return None')
new = ('def plutil_lint(path):\n    return 1   # 주입: plutil -lint 실패\n    if not shutil.which("plutil"): return None')
assert src.count(old) == 1
src = src.replace(old, new, 1)
old2 = ('    if r not in (None, 0):\n'
        '        try: os.remove(tmp)\n'
        '        except OSError: pass\n'
        '        return "plutil -lint rc=%s → 쓰기 0(원본 그대로)" % r      # r1(DA⑤): 복원 쓰기 0 — 원본을 열지 않는다')
new2 = ('    if r not in (None, 0):\n'
        '        os.remove(tmp); open(path, "wb").write(open(bak, "rb").read())   # 변이: 원본 wb 되살림\n'
        '        return "plutil -lint rc=%s → .bak 복원" % r')
assert src.count(old2) == 1, "복원 자리 1곳: %d" % src.count(old2)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old2, new2, 1))
PY
chk "변 15 사본이 실제로 바뀌었다" "$(cmp -s "$TOOL" "$TMP/mut-restorewb.sh" && echo same || echo changed)" changed
W2="$TMP/w2"; W2R="$W2/root"; W2V="$W2R/.worktrees/v6-realtime-live"
mkdir -p "$W2R/.fable-team/bin" "$W2V/.fable-team/bin" "$W2/launchagents"
python3 - "$W2/launchagents/com.byz.ft-tick.plist" "$W2V" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick", "WorkingDirectory": sys.argv[2]}, open(sys.argv[1], "wb"))
PY
mt1="$(mt "$W2/launchagents/com.byz.ft-tick.plist")"
run "$TMP/mut-restorewb.sh" --apply --root "$W2R" --from-wt "$W2V" --launchagents "$W2/launchagents" --teams-dir "$W2R/.fable-team" >/dev/null
chk "변 15 «원본 wb 되살림» → ⓦ FAIL(원본을 다시 열어 mtime 이 바뀐다)" \
  "$( [ "$(mt "$W2/launchagents/com.byz.ft-tick.plist")" = "$mt1" ] && echo caught || echo leaked)" leaked

echo "fail=$fail"
[ "$fail" = 0 ] && echo "ALL PASS"
exit "$fail"
