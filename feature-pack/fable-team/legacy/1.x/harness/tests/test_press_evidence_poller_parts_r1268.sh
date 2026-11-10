#!/usr/bin/env bash
# test_press_evidence_poller_parts_r1268.sh — r1268: 큰 poller_dom.jsonl(> 45 MB) = gzip 조각(poller_dom.jsonl.gz.001 …) + meta 3줄 · 판정은 조각을 풀어 이으며 줄 단위 검사 + sha256·바이트 수 대조
#   반례 R1~R7(카드 동결 집합) · 변이 3(조각 sha256 대조 끔 → R3 FAIL · 조각 수 대조 끔 → R4 FAIL · 조각 갈래 끔 → R1 FAIL)
#   문턱은 FT_PRESS_POLLER_PART_MB=1 (시험 전용) + 3 MB 픽스처 · 임시 origin(bare) · 네트워크 0 · 자기 재호출은 real_state_guard 재진입 표지 하나뿐 · 고정 sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_press_evidence_fixture.sh"

VER="$BIN/press_evidence_verify.py"   # 문턱은 pack 호출에만 FT_PRESS_POLLER_PART_MB 로 넘긴다
mkdir -p "$T/py"
cat > "$T/py/big.py" <<'PY'
# big.py <파일> <run_id> <MB> — 줄마다 JSON(axis·epoch_ms·run_id) + 눌리지 않는 무작위 16진 칸 · 줄 수천
import json, os, sys
n = int(float(sys.argv[3]) * 1024 * 1024 / 2050)
with open(sys.argv[1], "w", encoding="utf-8") as f:
    for i in range(n):
        f.write(json.dumps({"axis": "dom", "epoch_ms": i + 1, "run_id": sys.argv[2], "x": os.urandom(1000).hex()}) + "\n")
PY
cat > "$T/py/mut.py" <<'PY'
# mut.py <리포> <세트> <run> <모드> <원격 이름> — 묶음 트리를 고쳐 같은 ref 로 원격에 강제 push (모드: flip 마지막 조각 끝 1바이트 · zerosha meta sha 0 · plus1 meta 조각 수 +1 · droplast 마지막 조각 뺌 · badrow 5번째 줄 run_id 바꾼 새 gzip 2조각 + meta 맞춤)
import gzip, hashlib, subprocess, sys
repo, e, run, mode, remote = sys.argv[1:6]
ref = "refs/press/%s-%s" % (e, run)
def g(*a, inp=None): return subprocess.run(["git", "-C", repo, *a], input=inp, capture_output=True, check=True).stdout
ents = {l.split(b"\t")[1].decode(): g("cat-file", "blob", l.split()[2].decode()) for l in g("ls-tree", ref).splitlines()}
parts = sorted(n for n in ents if ".gz." in n)
meta = dict(r.split("=", 1) for r in ents["meta.txt"].decode().splitlines() if "=" in r)
def setmeta(**kv): meta.update({k: str(v) for k, v in kv.items()}); ents["meta.txt"] = "".join("%s=%s\n" % kv for kv in meta.items()).encode()
if mode == "flip": b = bytearray(ents[parts[-1]]); b[-1] ^= 0xFF; ents[parts[-1]] = bytes(b)
elif mode == "zerosha": setmeta(poller_sha256="0" * 64)
elif mode == "plus1": setmeta(poller_parts=len(parts) + 1)
elif mode == "droplast": del ents[parts[-1]]
elif mode == "badrow":
    raw = gzip.decompress(b"".join(ents[p] for p in parts)).split(b"\n")
    raw[4] = raw[4].replace(("\"run_id\": \"%s\"" % run).encode(), b"\"run_id\": \"other\"")
    body = b"\n".join(raw); z = gzip.compress(body, mtime=0); h = len(z) // 2
    for p in parts: del ents[p]
    ents["poller_dom.jsonl.gz.001"], ents["poller_dom.jsonl.gz.002"] = z[:h], z[h:]
    setmeta(poller_sha256=hashlib.sha256(body).hexdigest(), poller_bytes=len(body), poller_parts=2)
else: sys.exit("모드 모름")
t = g("mktree", inp="".join("100644 blob %s\t%s\n" % (g("hash-object", "-w", "--stdin", inp=ents[n]).decode().strip(), n) for n in sorted(ents)).encode()).decode().strip()
c = g("commit-tree", t, "-p", e, "-m", "tweak").decode().strip()
g("push", "-q", "-f", remote, "%s:%s" % (c, ref))
PY

pkbig() {  # pkbig <세트> <run> <MB> [문턱 MB(기본 1)] → out · rc (원격 ref 는 pack 이 만든다)
  ev "$T/ev/$2" "$2"; python3 "$T/py/big.py" "$T/ev/$2/poller_dom.jsonl" "$2" "$3"
  out="$(FT_PRESS_POLLER_PART_MB="${4:-1}" bash "$EVT" pack "$1" --run "$2" --poller "$T/ev/$2/poller_dom.jsonl" --table "$T/ev/$2/table.md" --turbopack "$T/ev/$2/turbopack.txt" --repo "$REPO" 2>&1)"; rc=$?
}
dep() { out="$(python3 "${1:-$VER}" deploy --commit "$2" --repo "$REPO" 2>&1)"; rc=$?; }   # dep [도구] <커밋>
mutate() {  # mutate <이름> <파일> <바꿀 문자열> <새 문자열> → MD = 변이 복사본 폴더
  local d="$T/mut-$1" f; mkdir -p "$d"; for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done; rm -f "$d/$2" "$d/press_evidence_verify.py"; cp "$BIN/press_evidence_verify.py" "$d/"   # verify 는 실파일 사본(python 이 자기 폴더의 조각 도구를 읽도록)
  python3 - "$BIN/$2" "$d/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 대상 없음 $2"; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read(); assert sys.argv[3] in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1))
PY
  MD="$d"
}

# ===== 사전: 문법 · 짝 사본 · 모드 =====
python3 -m py_compile "$BIN/press_evidence_parts.py" "$VER" "$BIN/press_evidence_land.py"; ck "py_compile 3파일" $?
for f in press_evidence_verify.py press_evidence_land.py press_evidence_parts.py; do cmp -s "$BIN/$f" "$KIT/$f" || { echo "  짝 다름 $f"; false; }; done; ck "짝 사본 bin·kit cmp0 (3파일)" $?
[ ! -x "$BIN/press_evidence_parts.py" ] && [ ! -x "$HERE/test_press_evidence_poller_parts_r1268.sh" ]; ck "새 파일 실행 비트 0(100644)" $?
out="$(python3 -c "import sys;sys.path.insert(0,'$BIN');import press_evidence_verify as v;print(v.push_sec(), v.push_sec(3), v.push_sec(20))")"; [ "$out" = "16.0 30.0 70.0" ]; ck "push 상한 = min(9 + 7 × 조각 수, 70)" $?
echo "단계 초: 사전 $((SECONDS - T_START))s"

# ===== R1: 3 MB poller · 문턱 1 MB → 조각 N≥2 · meta 3줄 · 트리에 poller_dom.jsonl 0 · PACKED parts=N =====
mkpr 1 b1 "clients/web/a.ts=x"; A1="$PRSHA"; pkbig "$A1" r1 3
N="$(printf '%s\n' "$out" | sed -n 's/.* parts=\([0-9]*\)$/\1/p')"
[ "$rc" = 0 ] && [[ "$out" == "PACKED ref=refs/press/$A1-r1 commit="* ]] && [ "${N:-0}" -ge 2 ]; ck "R1 pack rc0 · PACKED … parts=N(N≥2)" $?
R="refs/press/$A1-r1"; TREE="$(git -C "$ORIGIN" ls-tree --name-only "$R" | tr '\n' ' ')"
[[ "$TREE" != *"poller_dom.jsonl "* ]] && [[ "$TREE" == *"poller_dom.jsonl.gz.001 "* ]] && [[ "$TREE" == *"poller_dom.jsonl.gz.$(printf %03d "$N") "* ]] && [[ "$TREE" == *"meta.txt "* ]]; ck "R1 트리 = meta·조각 001…N·table·turbopack · 평문 poller 0" $?
ORIG="$T/ev/r1/poller_dom.jsonl"; META="$(git -C "$ORIGIN" show "$R:meta.txt")"
[[ "$META" == *"poller_sha256=$(shasum -a 256 < "$ORIG" | cut -d' ' -f1)"* ]] && [[ "$META" == *"poller_bytes=$(wc -c < "$ORIG" | tr -d ' ')"* ]] && [[ "$META" == *"poller_parts=$N"* ]]; ck "R1 meta 3줄 = 원본 sha256·바이트 수·조각 수" $?
for i in $(seq 1 "$N"); do git -C "$ORIGIN" cat-file blob "$R:poller_dom.jsonl.gz.$(printf %03d "$i")"; done | gunzip | cmp -s - "$ORIG"; ck "R1 조각을 이어 풀면 원본과 바이트 같음(한 줄도 안 빠짐)" $?
echo "단계 초: R1 $((SECONDS - T_START))s"
# ===== R2·R7: 같은 묶음 verify 통과 · land 가 착지 게이트 «press 증거 OK» =====
dep "$VER" "$A1"; [ "$rc" = 0 ] && [[ "$out" == "press 증거 OK 세트 ${A1:0:10} run r1 · ref $R · turbopack build 0 runtime 1 config 0 · 배포 ${A1:0:10}" ]]; ck "R2 verify deploy → 통과 · OK 줄 그대로" $?
land "$LAND" 1 --approve-sha "$A1"; [ "$rc" = 0 ] && [[ "$out" == *"press 증거 OK 세트 ${A1:0:10} run r1 · ref $R"* ]] && [[ "$out" == *"LANDED pr=1 "* ]]; ck "R7 land → 착지 게이트 «press 증거 OK» · LANDED" $?
echo "단계 초: R2·R7 $((SECONDS - T_START))s"

# ===== R3~R5: 틀린 묶음 → 거절(조용한 통과 0) — 한 세트에 한 묶음씩 켜서 «통과 묶음에 가려짐» 0 =====
tw() {  # tw <PR> <가지> <run> <모드> → 새 세트에 큰 묶음 pack 뒤 그 묶음을 고쳐 원격에 · 세트 = TS
  mkpr "$1" "$2" "clients/web/t$1.ts=x"; TS="$PRSHA"; pkbig "$TS" "$3" 3; [ "$rc" = 0 ] || { echo "FAIL tw pack rc=$rc $out"; exit 1; }
  python3 "$T/py/mut.py" "$REPO" "$TS" "$3" "$4" origin || { echo "FAIL mut.py $4"; exit 1; }
}
tw 3 b3 r3a flip; dep "$VER" "$TS"; [ "$rc" = 1 ] && [[ "$out" == *"press 증거 없음/틀림: poller 조각 풀기 실패"* ]]; ck "R3 조각 끝 바이트 바뀜 → 거절 «풀기 실패»(조용한 통과 0)" $?
tw 4 b4 r3b zerosha; dep "$VER" "$TS"; [ "$rc" = 1 ] && [[ "$out" == *"press 증거 없음/틀림: poller 조각 sha256 ≠ meta"* ]]; ck "R3 meta sha256 다름 → 거절 «sha256 ≠ meta»" $?
Z="$TS"
tw 5 b5 r4 plus1; dep "$VER" "$TS"; [ "$rc" = 1 ] && [[ "$out" == *"press 증거 없음/틀림: poller 조각 수 ≠ meta(조각 "* ]]; ck "R4 meta parts = 조각 수 +1 → 거절 «조각 수 ≠ meta»" $?
P1="$TS"
tw 6 b6 r4d droplast; dep "$VER" "$TS"; [ "$rc" = 1 ] && [[ "$out" == *"press 증거 없음/틀림: poller 조각 수 ≠ meta(조각 "* ]]; ck "R4 조각 1개 빠짐 → 거절 «조각 수 ≠ meta»" $?
tw 7 b7 r5 badrow; dep "$VER" "$TS"; [ "$rc" = 1 ] && [[ "$out" == *"press 증거 없음/틀림: poller 5줄 run_id other ≠ 묶음 r5"* ]]; ck "R5 조각 안 5번째 줄 run_id 다름 → 거절(평문과 같은 문구)" $?
echo "단계 초: R3~R5 $((SECONDS - T_START))s"

# ===== R6: 문턱 아래 poller = 평문 1파일(지금 꼴) · 옛 묶음 verify 통과 =====
mkpr 8 b8 "clients/web/s.ts=x"; A8="$PRSHA"; pkbig "$A8" r6 0.5
TREE="$(git -C "$ORIGIN" ls-tree --name-only "refs/press/$A8-r6" | tr '\n' ' ')"
[ "$rc" = 0 ] && [[ "$out" == "PACKED ref=refs/press/$A8-r6 commit="* ]] && [[ "$out" != *"parts="* ]] && [[ "$TREE" == *"poller_dom.jsonl "* ]] && [[ "$TREE" != *".gz."* ]] \
  && ! git -C "$ORIGIN" show "refs/press/$A8-r6:meta.txt" | grep -q poller_; ck "R6 0.5 MB · 문턱 1 MB → 평문 1파일 · meta 3줄 0" $?
dep "$VER" "$A8"; [ "$rc" = 0 ] && [[ "$out" == *"press 증거 OK 세트 ${A8:0:10} run r6"* ]]; ck "R6 평문 묶음 verify 통과" $?
mkpr 9 b9 "clients/web/o.ts=x"; A9="$PRSHA"; pk "$A9" r6o; dep "$VER" "$A9"
[ "$rc" = 0 ] && [[ "$out" == *"press 증거 OK 세트 ${A9:0:10} run r6o"* ]] && [[ "$(git -C "$ORIGIN" ls-tree --name-only "refs/press/$A9-r6o" | grep -c gz)" = 0 ]]; ck "R6 옛 꼴(기본 문턱 · 평문) 묶음 verify 통과" $?
echo "단계 초: R6 $((SECONDS - T_START))s"

# ===== 변이 3 =====
mutate m1 press_evidence_parts.py 'if (h.hexdigest(), n) != want[:2]:' 'if False:'; dep "$MD/press_evidence_verify.py" "$Z"; [ "$rc" = 0 ]; ck "ⓜ변이 1(조각 sha256 대조 끔) → R3(sha) 통과 = 계약 깨짐 재현" $?
mutate m2 press_evidence_parts.py 'if len(names) != want[2] or [' 'if False and ['; dep "$MD/press_evidence_verify.py" "$P1"; [ "$rc" = 0 ]; ck "ⓜ변이 2(조각 수 대조 끔) → R4(+1) 통과 = 계약 깨짐 재현" $?
mutate m3 press_evidence_land.py 'big = os.path.getsize(a.poller) > lim' 'big = False'
mkpr 10 b10 "clients/web/m3.ts=x"; M10="$PRSHA"; ev "$T/ev/m3" m3; python3 "$T/py/big.py" "$T/ev/m3/poller_dom.jsonl" m3 3
out="$(FT_PRESS_POLLER_PART_MB=1 bash "$MD/ft-press-evidence.sh" pack "$M10" --run m3 --poller "$T/ev/m3/poller_dom.jsonl" --table "$T/ev/m3/table.md" --turbopack "$T/ev/m3/turbopack.txt" --repo "$REPO" 2>&1)"; rc=$?
TREE="$(git -C "$ORIGIN" ls-tree --name-only "refs/press/$M10-m3" | tr '\n' ' ')"; [ "$rc" = 0 ] && [[ "$out" != *"parts="* ]] && [[ "$TREE" == *"poller_dom.jsonl "* ]] && [[ "$TREE" != *".gz."* ]]; ck "ⓜ변이 3(조각 갈래 끔 · 늘 평문) → 트리에 큰 평문 poller = R1 계약 깨짐 재현" $?
echo "단계 초: 변이 $((SECONDS - T_START))s"

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]] && ! grep -q BADVERB "$STUB_LOG"; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
