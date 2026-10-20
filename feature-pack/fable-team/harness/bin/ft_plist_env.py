#!/usr/bin/env python3
"""ft_plist_env.py — 설치기가 관리하는 launchd plist 를 키트 템플릿에서 렌더한다 (r426 · 미러 FT_ROOT 없이 7시간 47분 정지 사건).
관리 대상 = MANAGED(라벨 → 키트 harness/kit/ 기준 템플릿). 값: __ROOT__ = 프로젝트 루트 · __INBOX_BIN__ = <LIVE_BIN>/ft-inbox.sh ·
__MAILBOX__ = <루트>/.fable-team/comm/mailbox.log.jsonl · __HOME__ · 나머지(__PY__·__PROJECT__·__SEAT__·__CHANNEL__·__MENTION__·__REPO__)는
설치된 plist 에서 그대로 옮긴다(머신별 설정 보존 — 처음 설치는 slack-mirror/install.sh 소관).
사용: ft_plist_env.py list                                              → «라벨<TAB>템플릿» 줄
      ft_plist_env.py render <라벨> <템플릿> <설치 plist> <루트> <LIVE_BIN> <HOME> → stdout 렌더본
r538: ft_plist_env.py bin-list <키트 harness/kit>                       → __FT_BIN__ 템플릿 «라벨<TAB>템플릿» 줄
      ft_plist_env.py render-bin <템플릿> <루트> [<설치 plist>] [--need-exist] → stdout 렌더본(__FT_BIN__ = <루트>/.fable-team/bin · 판 붙은 live 경로 0)
            · 설치 plist 를 주면 그 plist 에 ProgramArguments + 템플릿의 WorkingDirectory 만 렌더본 것으로 바꾼 본문(머신별 env·주기 보존 · 같으면 원문 그대로)
r544: bin-list 는 «루트 bin 을 부르는» 템플릿 전부 — __FT_BIN__ 템플릿 + __BYZ_ROOT__/.fable-team/bin/ 템플릿(secret-scan·weekly-review 꼴 · 실행 경로만 루트 · 주기·로그는 템플릿 값)
      render-bin 은 템플릿에 WorkingDirectory 가 있으면 그것도 옮긴다 — 설치본에 그 키가 없어 launchd cwd=/ 에서 돌던 사건(리포 공용 루트 못 풂)
종료: 0 · 2 usage · 3 ERROR(루트·LIVE_BIN·설치값 없음 · 자리표시 잔재 · plist 해석 실패 — 조용한 통과 0 · #0 RULE). 쓰기 0."""
import os
import plistlib
import re
import sys
from xml.parsers.expat import ExpatError
from xml.sax.saxutils import escape

MANAGED = {"com.hermes.byz-mbox-slack-mirror": "slack-mirror/com.hermes.byz-mbox-slack-mirror.plist.template"}
FLAGS = {"__PROJECT__": "--project", "__SEAT__": "--seat", "__CHANNEL__": "--channel", "__MENTION__": "--mention", "__REPO__": "--repo"}


class RenderError(Exception):
    pass


def plist_path(home, label):
    return os.path.join(home, "Library", "LaunchAgents", label + ".plist")


def load(path):
    try:
        with open(path, "rb") as fh:
            return plistlib.load(fh)
    except (OSError, ValueError, ExpatError) as e:
        raise RenderError("plist 해석 실패: %s (%s)" % (path, e))


def installed_values(path):
    """설치된 plist 의 ProgramArguments 에서 머신별 값을 옮긴다 — 하나라도 없으면 RenderError."""
    args = load(path).get("ProgramArguments") or []
    if not args:
        raise RenderError("설치된 plist 에 ProgramArguments 없음: %s" % path)
    vals = {"__PY__": args[0]}
    for key, flag in FLAGS.items():
        i = args.index(flag) if flag in args else -1
        if i < 0 or i + 1 >= len(args):
            raise RenderError("설치된 plist 에 %s 값 없음: %s" % (flag, path))
        vals[key] = args[i + 1]
    return vals


def render(template, installed, root, live_bin, home):
    """템플릿 본문 → 렌더본 문자열. 렌더본의 EnvironmentVariables.FT_ROOT = root 까지 확인한다."""
    if not os.path.isdir(os.path.join(root, ".fable-team")):
        raise RenderError("프로젝트 루트 없음(.fable-team 없음): %s" % root)
    if not os.path.isdir(os.path.join(root, ".git")):  # r457: 워크트리(.git 파일)·git 밖 = launchd 가 볼 루트가 아니다
        why = "워크트리" if os.path.isfile(os.path.join(root, ".git")) else ".git 없음"
        raise RenderError("루트가 git 공용 루트 아님(%s): %s" % (why, root))
    inbox = os.path.join(live_bin, "ft-inbox.sh")
    if not os.path.isabs(live_bin) or not os.path.isfile(inbox):
        raise RenderError("LIVE_BIN 에 ft-inbox.sh 없음: %s" % inbox)
    vals = installed_values(installed)
    vals.update({"__ROOT__": root, "__HOME__": home, "__INBOX_BIN__": inbox,
                 "__MAILBOX__": os.path.join(root, ".fable-team", "comm", "mailbox.log.jsonl")})
    out = template
    for key, val in vals.items():
        out = out.replace(key, escape(val))
    left = sorted(set(re.findall(r"__[A-Z_]+__", out)))
    if left:
        raise RenderError("자리표시 잔재: %s" % " ".join(left))
    try:
        env = plistlib.loads(out.encode("utf-8")).get("EnvironmentVariables") or {}
    except (ValueError, ExpatError) as e:
        raise RenderError("렌더본 plist 해석 실패: %s" % e)
    if env.get("FT_ROOT") != root:
        raise RenderError("렌더본 FT_ROOT(%r) ≠ 루트 — 템플릿에 FT_ROOT 키가 있어야 한다" % env.get("FT_ROOT"))
    return out


ROOTBIN = "__BYZ_ROOT__/.fable-team/bin/"  # r544: 루트 bin 을 직접 부르는 템플릿 표식(__FT_BIN__ 없이 실행 경로만 루트인 꼴 — secret-scan·weekly-review)


def bin_list(kit):
    """r538: <키트>/*/*.plist.template 중 루트 bin 을 부르는 것 → [(라벨, 템플릿 경로)] (라벨 = 파일 이름 · 템플릿 Label 과 다르면 RenderError).
    r544: __FT_BIN__ 뿐 아니라 __BYZ_ROOT__/.fable-team/bin/ 실행 경로 템플릿도 포함(__HOME__·__REPO__ 를 쓰는 magazine 류는 실행 경로가 루트 bin 이 아니라 제외)."""
    out = []
    for sub in sorted(os.listdir(kit)):
        d = os.path.join(kit, sub)
        for name in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if not name.endswith(".plist.template"):
                continue
            with open(os.path.join(d, name), encoding="utf-8") as fh:
                body = fh.read()
            if "__FT_BIN__" not in body and ROOTBIN not in body:
                continue
            label = name[: -len(".plist.template")]
            m = re.search(r"<key>Label</key>\s*<string>([^<]+)</string>", body)
            if not m or m.group(1) != label:
                raise RenderError("템플릿 Label(%s) ≠ 파일 이름(%s)" % (m and m.group(1), label))
            out.append((label, os.path.join(d, name)))
    return out


def render_bin(template, root, need_exist=False):
    """r538: __FT_BIN__ 템플릿 → 렌더본. __FT_BIN__ = <루트>/.fable-team/bin(판 없는 루트 shim · LIVE_BIN 을 따라감) · __BYZ_ROOT__ = 루트.
    need_exist = 렌더본이 부르는 루트 bin 도구가 실재해야 한다(apply · shim 단계 뒤)."""
    if not os.path.isdir(os.path.join(root, ".git")):
        raise RenderError("루트가 git 공용 루트 아님: %s" % root)
    rbin = os.path.join(root, ".fable-team", "bin")
    out = template.replace("__FT_BIN__", escape(rbin)).replace("__BYZ_ROOT__", escape(root))
    left = sorted(set(re.findall(r"__[A-Z_]+__", out)))
    if left:
        raise RenderError("자리표시 잔재: %s" % " ".join(left))
    try:
        args = [a for a in plistlib.loads(out.encode("utf-8")).get("ProgramArguments") or [] if isinstance(a, str)]
    except (ValueError, ExpatError) as e:
        raise RenderError("렌더본 plist 해석 실패: %s" % e)
    tools = [a for a in args if a.startswith(rbin + "/")]
    if not tools:
        raise RenderError("렌더본 ProgramArguments 에 루트 bin 경로 없음: %s" % rbin)
    miss = [a for a in tools if need_exist and not os.path.isfile(a)]
    if miss:
        raise RenderError("루트 bin 도구 없음: %s" % " ".join(miss))
    return out


def sync_args(rendered, installed):
    """r538: 설치 plist 의 ProgramArguments 만 렌더본 것으로 — 나머지(머신별 env·주기)는 설치본 그대로(손으로 둔 FT_STALL_PENALTY_AUTO=0 등 보존).
    r544: 템플릿에 WorkingDirectory 가 있으면 그것도 옮긴다(설치본에 없어 launchd cwd=/ 로 돌던 사건) — 템플릿에 없으면 설치본 값 그대로(지어내지 않음).
    이미 같으면 설치본 원문 그대로 돌려준다(쓰기 0)."""
    want = plistlib.loads(rendered.encode("utf-8"))
    d = load(installed)
    keep_wd = "WorkingDirectory" in want
    if d.get("ProgramArguments") == want["ProgramArguments"] and (not keep_wd or d.get("WorkingDirectory") == want["WorkingDirectory"]):
        with open(installed, encoding="utf-8") as fh:
            return fh.read()
    d["ProgramArguments"] = want["ProgramArguments"]
    if keep_wd:
        d["WorkingDirectory"] = want["WorkingDirectory"]
    return plistlib.dumps(d, sort_keys=False).decode("utf-8")


def main(argv):
    if argv == ["list"]:
        print("\n".join("%s\t%s" % kv for kv in sorted(MANAGED.items())))
        return 0
    try:
        if len(argv) == 2 and argv[0] == "bin-list":
            print("\n".join("%s\t%s" % kv for kv in bin_list(argv[1])))
            return 0
        pos = [a for a in argv[1:] if a != "--need-exist"]
        if argv[:1] == ["render-bin"] and len(pos) in (2, 3) and argv.count("--need-exist") <= 1:
            with open(pos[0], encoding="utf-8") as fh:
                out = render_bin(fh.read(), pos[1], "--need-exist" in argv)
            sys.stdout.write(sync_args(out, pos[2]) if len(pos) == 3 else out)
            return 0
    except (RenderError, OSError) as e:
        print("ERROR %s" % e)
        return 3
    if len(argv) != 7 or argv[0] != "render":
        print("usage: ft_plist_env.py list | bin-list <키트> | render-bin <템플릿> <루트> [<설치 plist>] [--need-exist]"
              " | render <라벨> <템플릿> <설치 plist> <루트> <LIVE_BIN> <HOME>", file=sys.stderr)
        return 2
    label, tpl, installed, root, live_bin, home = argv[1:]
    try:
        if label not in MANAGED:
            raise RenderError("관리 대상 라벨 아님: %s" % label)
        with open(tpl, encoding="utf-8") as fh:
            sys.stdout.write(render(fh.read(), installed, root, live_bin, home))
    except (RenderError, OSError) as e:
        print("ERROR %s" % e)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
