#!/usr/bin/env bash
# ft-acct-quota.sh [--timeline] [--json] [--provider claude|codex|gemini|all] [--no-net]   (r1432)
#   cliproxy OAuth 계정의 «쿼터·복구 시각»을 한 표로. 중복은 (provider + 계정 id + org) 조합으로 판정한다.
#   ★교훈: account_uuid 가 같아도 org 구독이 다르면 쿼터가 별개다(2026-11-06 실측). uuid 만으로 중복 판정 금지.
#   claude = api.anthropic.com/api/oauth/usage · codex = chatgpt.com/backend-api/wham/usage · gemini = endpoints 없음(파일만 표시)
#   네트워크는 계정당 1회(각 7초 상한). --no-net 이면 파일 값만.
set -uo pipefail
DIR="${FT_AUTH_DIR:-$HOME/.cli-proxy-api}"; MODE=table; PROV=all; NET=1
while [ $# -gt 0 ]; do case "$1" in
  --json) MODE=json; shift;; --timeline) MODE=timeline; shift;; --no-net) NET=0; shift;;
  --provider) PROV="$2"; shift 2;; -*) shift;; *) shift;; esac; done
python3 - "$DIR" "$MODE" "$PROV" "$NET" <<'PY'
import json, glob, os, subprocess, sys, time, datetime
d, mode, prov, net = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
KST = datetime.timezone(datetime.timedelta(hours=9))
def left(epoch=None, iso=None):
    """복구까지 남은 시간 = 3d 5h / 7h 10m / 지남"""
    try:
        t = int(epoch) if epoch else datetime.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()
    except Exception:
        return "-"
    sec = int(t - time.time())
    if sec <= 0: return "복구됨"
    d_, h_ = sec // 86400, (sec % 86400) // 3600
    if d_: return "%dd %dh" % (d_, h_)
    return "%dh %dm" % (h_, (sec % 3600) // 60)


def kst(epoch=None, iso=None):
    try:
        if epoch: return datetime.datetime.fromtimestamp(int(epoch), KST).strftime("%m-%d %H:%M")
        if iso: return datetime.datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone(KST).strftime("%m-%d %H:%M")
    except Exception: return "-"
    return "-"
def curl(url, args, tok, extra=None, timeout="7"):
    cmd = ["curl", "-s", "-m", timeout, url, "-H", "Authorization: Bearer " + tok] + (extra or []) + list(args)
    try: return subprocess.run(cmd, capture_output=True, text=True, timeout=12).stdout
    except Exception: return ""
rows = []
for p in sorted(glob.glob(os.path.join(d, "*.json"))):
    try: o = json.load(open(p))
    except Exception: continue
    kind = o.get("type") or os.path.basename(p).split("-")[0]
    if kind not in ("claude", "codex", "antigravity", "gemini"): continue
    name = os.path.basename(p)
    r = dict(file=name, provider=kind, email=o.get("email") or "-", disabled=bool(o.get("disabled")),
             plan=o.get("plan_type") or "", org="", tier="", u5=None, w=None, r5="-", rw="-", l5="-", lw="-", note="")
    if kind == "claude":
        r["key"] = (o.get("account_uuid") or "", o.get("organization_uuid") or "")
        H = ["-H", "anthropic-version: 2023-06-01", "-H", "anthropic-beta: oauth-2025-04-20"]
        if net:
            tok = o.get("access_token") or ""
            pr = curl("https://api.anthropic.com/api/oauth/profile", H, tok)
            try: org = (json.loads(pr).get("organization") or {})
            except Exception: org = {}
            r["org"] = (o.get("organization_name") or org.get("organization_name") or "-")[:26]
            r["tier"] = (org.get("rate_limit_tier") or "-").replace("default_claude_", "")
            us = curl("https://api.anthropic.com/api/oauth/usage", H, tok)
            try: u = json.loads(us)
            except Exception: u = {}
            fh = u.get("five_hour") or {}; sw = u.get("seven_day") or {}
            r["u5"] = fh.get("utilization"); r["w"] = sw.get("utilization")
            r["r5"] = kst(iso=fh.get("resets_at")); r["rw"] = kst(iso=sw.get("resets_at"))
            r["l5"] = left(iso=fh.get("resets_at")); r["lw"] = left(iso=sw.get("resets_at"))
        r["org"] = r["org"] or (o.get("organization_name") or "-")[:26]
    elif kind == "codex":
        r["key"] = (o.get("account_id") or "",)   # plan 은 키에 넣지 않는다(같은 계정의 pro/plus/prolite 는 중복슬롯)
        r["plan"] = o.get("plan_type") or "-"
        if net:
            tok = o.get("access_token") or ""; aid = o.get("account_id") or ""
            js = curl("https://chatgpt.com/backend-api/wham/usage", ["-H", "User-Agent: codex-cli/0.166.0"],
                      tok, ["-H", "chatgpt-account-id: " + aid])
            try: u = json.loads(js)
            except Exception: u = {}
            rl = u.get("rate_limit") or {}
            pw = rl.get("primary_window") or {}
            r["w"] = pw.get("used_percent"); r["rw"] = kst(epoch=pw.get("reset_at")); r["lw"] = left(epoch=pw.get("reset_at"))
            r["note"] = "limit_reached" if rl.get("limit_reached") else ""
    else:
        r["key"] = (o.get("email") or name, "gemini")
        r["note"] = "usage endpoint 없음"
    rows.append(r)
if prov != "all": rows = [x for x in rows if x["provider"] == prov]
# 중복 = (provider + key) 동일
seen = {}
for x in rows: seen.setdefault((x["provider"],) + tuple(x["key"]), []).append(x)
RANK = {"pro": 0, "plus": 1, "prolite": 2, "": 3}
for k, v in seen.items():
    if len(v) > 1:
        v.sort(key=lambda x: (x["disabled"], RANK.get(x["plan"], 3)))
        for x in v[1:]:
            x["note"] = (x["note"] + " 중복슬롯(유지=" + v[0]["file"].split("-")[-1] + ")").strip()
if mode == "json":
    print(json.dumps(rows, ensure_ascii=False, indent=1)); sys.exit(0)
if mode == "timeline":
    tl = []
    for x in rows:
        if x["r5"] != "-" and (x["u5"] or 0) >= 100: tl.append((x["r5"], x["l5"], x["provider"], x["email"], x["tier"] or x["plan"]))
        if x["rw"] != "-" and (x["w"] or 0) >= 100: tl.append((x["rw"], x["lw"], x["provider"], x["email"], x["tier"] or x["plan"]))
    print("%-13s %-11s %-8s %-30s %-10s" % ("복구시각", "남은", "provider", "email", "tier/plan"))
    for r, lf, p, e, t in sorted(tl):
        print("%-13s %-11s %-8s %-30s %-10s" % (r, lf, p, e[:30], t))
    sys.exit(0)
print("파일 %d · 활성 %d · 비활성 %d" % (len(rows), sum(1 for x in rows if not x["disabled"]), sum(1 for x in rows if x["disabled"])))
print("%-8s %-28s %-9s %5s %5s %-12s %-11s %-12s %-11s %s" % (
    "provider","email","tier/plan","5h","주간","5h 리셋","남은","주간 리셋","남은","비고"))
print("-" * 152)
for x in rows:
    print("%-8s %-28s %-9s %5s %5s %-12s %-11s %-12s %-11s %s" % (
        x["provider"], (x["email"] or "")[:28], (x["tier"] or x["plan"] or "-")[:9],
        "-" if x["u5"] is None else "%.0f%%" % x["u5"],
        "-" if x["w"] is None else "%.0f%%" % x["w"],
        x["r5"], x["l5"], x["rw"], x["lw"],
        ("DISABLED " if x["disabled"] else "") + x["note"]))
PY
