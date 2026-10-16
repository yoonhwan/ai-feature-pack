"""Synthetic scenarios of the operating-plist ProcessType removal script (design arch-20261016-opa-popup-design-r15
§2.4 + errata §2 acceptance conditions 1-12).

Everything is synthetic: fixture plists under a temporary directory, a fake ``launchctl`` that only answers the two
read-only subcommands (and records every call), a fake ``plutil`` where a failure is needed. No operating plist, no
real launchctl, no real op, no token file, no network; test mode refuses the operating paths.
"""

from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import re
import signal
import stat
import subprocess
import sys
import time

import pytest

OPS = Path(__file__).resolve().parents[1] / "ops" / "plist-edit"
SCRIPT_PY = OPS / "plist_edit.py"
SCRIPT_SH = OPS / "plist_edit.sh"
FAKE_LC = Path(__file__).resolve().parent / "_plist_fake_launchctl.py"
PY = sys.executable

SENTINELS = ("SENTINEL_ENV_a91c", "/sentinel/python-c3e8", "/sentinel/out-b27d", "SENTINEL_NESTED_5d20", "Interactive_SENT_77")
PT = "  <key>ProcessType</key>\n  <string>Background</string>\n"
FORBIDDEN_VERBS = re.compile(r"\b(bootout|bootstrap|enable|disable|kickstart|reload)\b")


def plist_text(pt: str = PT, nested: str = "", nl: str = "\n", root_open: str = "<dict>") -> str:
    text = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- sentinel comment: keep me -->
<plist version="1.0">
{root_open}
  <key>Label</key>
  <string>com.airag.consumer</string>
  <key>ProgramArguments</key>
  <array>
    <string>/sentinel/python-c3e8</string>
    <string>-m</string>
    <string>airag_consumer.tick</string>
  </array>
  <key>StartInterval</key>
  <integer>300</integer>
  <key>RunAtLoad</key>
  <true/>
{pt}  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>SENTINEL_ENV_a91c</string>
{nested}  </dict>
  <key>StandardOutPath</key>
  <string>/sentinel/out-b27d/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>/sentinel/out-b27d/launchd.err.log</string>
</dict>
</plist>
"""
    return text.replace("\n", nl)


TOP_KEYS = ["Label", "ProgramArguments", "StartInterval", "RunAtLoad", "EnvironmentVariables", "StandardOutPath",
            "StandardErrorPath"]
NESTED_PT = "    <key>ProcessType</key>\n    <string>SENTINEL_NESTED_5d20</string>\n"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class Lab:
    def __init__(self, root: Path, content: bytes | str | None = None, mode: int = 0o640):
        self.root = root
        self.work = root / "work"
        self.work.mkdir()
        self.home = root / "home"
        self.home.mkdir()
        self.plist = self.work / "consumer.plist"
        self.backup = root / "backup"
        self.state = root / "lcstate"
        self.bin = root / "bin"
        self.bin.mkdir()
        self.launchctl = self.bin / "launchctl"
        self.launchctl.write_text(f'#!/bin/sh\nexec "{PY}" "{FAKE_LC}" "$@"\n', encoding="utf-8")
        self.launchctl.chmod(0o755)
        self.pause_file = root / "paused.txt"
        data = plist_text() if content is None else content
        self.plist.write_bytes(data.encode("utf-8") if isinstance(data, str) else data)
        self.plist.chmod(mode)
        self.original = self.plist.read_bytes()

    def fake_plutil(self, body: str) -> Path:
        path = self.bin / "plutil"
        path.write_text(f"#!/bin/sh\n{body}\n", encoding="utf-8")
        path.chmod(0o755)
        return path

    def argv(self, plutil: Path | None = None) -> list[str]:
        out = ["--selftest", "--plist", str(self.plist), "--backup-dir", str(self.backup), "--launchctl", str(self.launchctl)]
        return out + (["--plutil", str(plutil)] if plutil else [])

    def env(self, **extra: str) -> dict[str, str]:
        return {"PATH": "/usr/bin:/bin", "HOME": str(self.home), "FAKE_LC_STATE": str(self.state),
                "PLIST_EDIT_PAUSE_FILE": str(self.pause_file), **extra}

    def run(self, *, plutil: Path | None = None, extra_args: list[str] | None = None, via: str = "py",
            timeout: float = 60, **env: str) -> subprocess.CompletedProcess:
        args = [*self.argv(plutil), *(extra_args or [])]
        argv = [PY, "-I", str(SCRIPT_PY), *args] if via == "py" else ["bash", str(SCRIPT_SH), "--python", PY, *args]
        return subprocess.run(argv, env=self.env(**env), stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout)

    def calls(self) -> list[str]:
        path = self.state / "calls.txt"
        return path.read_text(encoding="utf-8").splitlines() if path.exists() else []

    def leftovers(self) -> list[str]:
        return sorted(p.name for p in self.work.iterdir() if p.name != self.plist.name)

    def backups(self) -> list[Path]:
        return sorted(self.backup.glob("*")) if self.backup.exists() else []

    def untouched(self) -> bool:
        return self.plist.read_bytes() == self.original and self.leftovers() == []


@pytest.fixture
def lab(tmp_path):
    return Lab(tmp_path)


@pytest.fixture
def mod():
    spec = importlib.util.spec_from_file_location("plist_edit_under_test", SCRIPT_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def combined(done: subprocess.CompletedProcess) -> str:
    return done.stdout + done.stderr


def no_sentinel(text: str) -> None:
    for sentinel in SENTINELS:
        assert sentinel not in text


def top_keys(path: Path) -> list[str]:
    return list(plistlib.loads(path.read_bytes()))


def start_paused(lab: Lab, hook: str, via: str = "py") -> subprocess.Popen:
    args = [*lab.argv()]
    argv = [PY, "-I", str(SCRIPT_PY), *args] if via == "py" else ["bash", str(SCRIPT_SH), "--python", PY, *args]
    proc = subprocess.Popen(argv, env=lab.env(PLIST_EDIT_INJECT=hook), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    deadline = time.time() + 20
    while time.time() < deadline and not lab.pause_file.exists():
        time.sleep(0.05)
    assert lab.pause_file.exists(), "the script never reached the pause point"
    return proc


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


# ===================================================================================== normal run / absent
def test_removes_exactly_the_top_level_entry_and_keeps_every_other_byte(lab):
    done = lab.run()
    assert done.returncode == 0, combined(done)
    assert lab.plist.read_bytes() == plist_text(pt="").encode("utf-8")
    assert top_keys(lab.plist) == TOP_KEYS
    assert lab.leftovers() == []
    assert subprocess.run(["/usr/bin/plutil", "-lint", str(lab.plist)], capture_output=True).returncode == 0
    for word in ("입력: PASS", "전제: PASS", "백업: PASS", "후보 lint: PASS", "후보 검증: PASS", "사후 재검증: PASS"):
        assert word in done.stdout
    for name in TOP_KEYS:
        assert name in done.stdout


def test_a_second_run_finds_nothing_to_do(lab):
    assert lab.run().returncode == 0
    after = lab.plist.read_bytes()
    count = len(lab.backups())
    done = lab.run()
    assert done.returncode == 0 and lab.plist.read_bytes() == after and len(lab.backups()) == count
    assert "이미" in done.stdout


def test_already_without_the_key_changes_nothing_and_writes_no_backup(tmp_path):
    lab = Lab(tmp_path, plist_text(pt=""))
    done = lab.run()
    assert done.returncode == 0, combined(done)
    assert lab.untouched() and not lab.backup.exists()
    no_sentinel(combined(done))


@pytest.mark.parametrize("nl,pt", [("\n", PT), ("\r\n", PT.replace("\n", "\r\n")), ("\n", PT.replace("  ", "\t")),
                                   ("\n", "  <key>ProcessType</key><string>Background</string>\n")],
                         ids=["lf", "crlf", "tabs", "one-line"])
def test_other_bytes_are_untouched_for_any_spacing_style(tmp_path, nl, pt):
    text = plist_text(pt=pt.replace("\r\n", "\n"), nl=nl)
    lab = Lab(tmp_path, text)
    assert lab.run().returncode == 0
    assert lab.plist.read_bytes() == plist_text(pt="", nl=nl).encode("utf-8")


def test_the_key_between_other_keys_inline_leaves_the_neighbours(tmp_path):
    text = plist_text(pt="  <key>StartInterval</key><integer>300</integer><key>ProcessType</key><string>Background</string>\n")
    text = text.replace("  <key>StartInterval</key>\n  <integer>300</integer>\n", "")
    lab = Lab(tmp_path, text)
    assert lab.run().returncode == 0
    document = plistlib.loads(lab.plist.read_bytes())
    assert "ProcessType" not in document and document["StartInterval"] == 300


def test_nested_keys_with_the_same_name_survive(tmp_path):
    lab = Lab(tmp_path, plist_text(nested=NESTED_PT))
    assert lab.run().returncode == 0
    document = plistlib.loads(lab.plist.read_bytes())
    assert "ProcessType" not in document
    assert document["EnvironmentVariables"]["ProcessType"] == "SENTINEL_NESTED_5d20"
    assert lab.plist.read_bytes() == plist_text(pt="", nested=NESTED_PT).encode("utf-8")


def test_a_nested_key_alone_is_not_mistaken_for_the_top_level_entry(tmp_path):
    lab = Lab(tmp_path, plist_text(pt="", nested=NESTED_PT))
    done = lab.run()
    assert done.returncode == 0 and lab.untouched() and not lab.backup.exists()


def test_the_nested_one_is_kept_when_it_comes_before_the_top_level_entry(tmp_path):
    text = plist_text(nested=NESTED_PT)
    reordered = text.replace(PT, "").replace("</dict>\n  <key>StandardOutPath", "</dict>\n" + PT + "  <key>StandardOutPath")
    lab = Lab(tmp_path, reordered)
    assert lab.run().returncode == 0
    document = plistlib.loads(lab.plist.read_bytes())
    assert "ProcessType" not in document and document["EnvironmentVariables"]["ProcessType"] == "SENTINEL_NESTED_5d20"


# ===================================================================================== rejections
def binary_plist() -> bytes:
    return plistlib.dumps({"Label": "com.airag.consumer", "ProcessType": "Background"}, fmt=plistlib.FMT_BINARY)


REJECTED = {
    "other-value": plist_text(pt="  <key>ProcessType</key>\n  <string>Interactive_SENT_77</string>\n"),
    "lowercase": plist_text(pt="  <key>ProcessType</key>\n  <string>background</string>\n"),
    "padded": plist_text(pt="  <key>ProcessType</key>\n  <string> Background </string>\n"),
    "integer": plist_text(pt="  <key>ProcessType</key>\n  <integer>1</integer>\n"),
    "bool": plist_text(pt="  <key>ProcessType</key>\n  <true/>\n"),
    "array": plist_text(pt="  <key>ProcessType</key>\n  <array><string>Background</string></array>\n"),
    "duplicate": plist_text(pt=PT + PT),
    "duplicate-different": plist_text(pt=PT + "  <key>ProcessType</key>\n  <string>Interactive_SENT_77</string>\n"),
    "root-array": plist_text(root_open="<array>").replace("</dict>\n</plist>", "</array>\n</plist>"),
    "garbage": "this is not a plist at all",
    "empty": "",
    "binary": binary_plist(),
}


@pytest.mark.parametrize("name", sorted(REJECTED))
def test_rejected_inputs_edit_nothing(tmp_path, name):
    lab = Lab(tmp_path, REJECTED[name])
    done = lab.run()
    assert done.returncode == 3, combined(done)
    assert lab.untouched() and not lab.backup.exists() and lab.calls() == []
    no_sentinel(combined(done))


def test_a_symlink_is_refused_and_its_target_is_not_replaced(tmp_path):
    lab = Lab(tmp_path)
    target = lab.work / "real.plist"
    target.write_bytes(lab.original)
    lab.plist.unlink()
    lab.plist.symlink_to(target)
    done = lab.run()
    assert done.returncode == 3 and lab.plist.is_symlink() and target.read_bytes() == lab.original
    assert not lab.backup.exists()


def test_a_missing_file_and_a_directory_are_refused(tmp_path):
    lab = Lab(tmp_path)
    lab.plist.unlink()
    assert lab.run().returncode == 3
    lab.plist.mkdir()
    assert lab.run().returncode == 3 and not lab.backup.exists()


# ===================================================================================== launchd state precondition
@pytest.mark.parametrize("env", [{"FAKE_LC_LOADED": "1"}, {"FAKE_LC_ENABLED": "1"}, {"FAKE_LC_NO_ENTRY": "1"},
                                 {"FAKE_LC_LIST_FAIL": "1"}, {"FAKE_LC_DISABLED_FAIL": "1"}, {"FAKE_LC_LIST_GARBAGE": "1"}],
                         ids=["loaded", "not-stopped", "no-entry", "list-fails", "print-disabled-fails", "list-garbage"])
def test_an_unconfirmed_or_wrong_launchd_state_means_no_edit_and_no_backup(lab, env):
    done = lab.run(**env)
    assert done.returncode == 4, combined(done)
    assert lab.untouched() and not lab.backup.exists()
    no_sentinel(combined(done))


def test_a_hanging_launchctl_counts_as_unconfirmed(lab):
    started = time.time()
    done = lab.run(FAKE_LC_SLEEP="3", PLIST_EDIT_CALL_S="0.4")
    assert done.returncode == 4 and lab.untouched() and not lab.backup.exists()
    assert time.time() - started < 10


def test_launchctl_is_only_asked_the_two_read_only_questions_once_each(lab):
    assert lab.run().returncode == 0
    assert lab.calls() == ["list", f"print-disabled gui/{os.getuid()}"]


def test_a_failing_list_is_not_retried(lab):
    assert lab.run(FAKE_LC_LIST_FAIL="1").returncode == 4
    assert lab.calls() == ["list"]


def test_every_external_call_gets_the_seven_second_cap_and_no_stdin(lab, mod, monkeypatch, capsys):
    seen = []
    real_run = subprocess.run

    def spy(argv, **kwargs):
        seen.append((Path(argv[0]).name, kwargs.get("timeout"), kwargs.get("stdin")))
        return real_run(argv, **kwargs)

    monkeypatch.setattr(mod.subprocess, "run", spy)
    for key, value in lab.env().items():
        monkeypatch.setenv(key, value)
    assert mod.main(lab.argv()) == 0
    assert mod.CALL_S == 7.0
    assert [name for name, *_ in seen] == ["launchctl", "launchctl", "plutil"]
    assert all(timeout == 7.0 or (timeout is not None and 6.0 < timeout <= 7.0) for _, timeout, _ in seen)
    assert all(stdin == subprocess.DEVNULL for *_, stdin in seen)


def test_the_call_cap_override_exists_only_in_test_mode(mod, tmp_path, monkeypatch):
    monkeypatch.setenv("PLIST_EDIT_CALL_S", "0.1")
    production = mod.Context(tmp_path / "a", tmp_path / "b", mod.LAUNCHCTL, mod.PLUTIL, False)
    assert production.call_s == 7.0 and production.hook("backup_corrupt") is False
    monkeypatch.setenv("PLIST_EDIT_INJECT", "backup_corrupt")
    assert production.hook("backup_corrupt") is False
    test_mode = mod.Context(tmp_path / "a", tmp_path / "b", "/x", mod.PLUTIL, True)
    assert test_mode.call_s == 0.1 and test_mode.hook("backup_corrupt") is True


def test_the_source_has_no_launchd_changing_verb_and_only_two_read_verbs(mod):
    for path in (SCRIPT_PY, SCRIPT_SH):
        text = path.read_text(encoding="utf-8")
        assert FORBIDDEN_VERBS.search(text) is None, path.name
        assert "input(" not in text and "read -p" not in text
    assert tuple(mod.READ_VERBS) == ("list", "print-disabled")
    with pytest.raises(AssertionError):
        ctx = mod.Context(Path("/x"), Path("/y"), "/z", "/w", True)
        mod.launchctl_read(ctx, "print")


# ===================================================================================== test-mode guards
def test_path_arguments_are_refused_without_the_test_flag(lab):
    done = subprocess.run([PY, "-I", str(SCRIPT_PY), "--plist", str(lab.plist)], env=lab.env(), stdin=subprocess.DEVNULL,
                          capture_output=True, text=True)
    assert done.returncode == 2 and lab.untouched()


@pytest.mark.parametrize("args", [["--selftest"], ["--selftest", "--plist", "x"], ["--bogus"], ["--selftest", "--selftest"]],
                         ids=["bare-selftest", "partial", "unknown", "duplicate"])
def test_incomplete_or_unknown_arguments_exit_two(lab, args):
    done = subprocess.run([PY, "-I", str(SCRIPT_PY), *args], env=lab.env(), stdin=subprocess.DEVNULL, capture_output=True, text=True)
    assert done.returncode == 2 and lab.untouched()


def operating_in(home: Path) -> Path:
    path = home / "Library" / "LaunchAgents" / "com.airag.consumer.plist"
    path.parent.mkdir(parents=True)
    return path


def test_the_operating_plist_path_is_refused_in_test_mode(lab):
    operating = operating_in(lab.home)
    operating.write_bytes(lab.original)
    args = ["--selftest", "--plist", str(operating), "--backup-dir", str(lab.backup), "--launchctl", str(lab.launchctl)]
    done = subprocess.run([PY, "-I", str(SCRIPT_PY), *args], env=lab.env(FAKE_LC_LOADED="1"), stdin=subprocess.DEVNULL,
                          capture_output=True, text=True)
    assert done.returncode == 2
    assert operating.read_bytes() == lab.original and lab.calls() == [] and not lab.backup.exists()


def test_any_file_inside_the_launch_agents_directory_is_refused(lab):
    operating = operating_in(lab.home)
    other = operating.parent / "other.plist"
    other.write_bytes(lab.original)
    args = ["--selftest", "--plist", str(other), "--backup-dir", str(lab.backup), "--launchctl", str(lab.launchctl)]
    done = subprocess.run([PY, "-I", str(SCRIPT_PY), *args], env=lab.env(), stdin=subprocess.DEVNULL, capture_output=True, text=True)
    assert done.returncode == 2 and other.read_bytes() == lab.original


def test_a_symlink_to_the_operating_plist_is_refused(lab):
    operating = operating_in(lab.home)
    operating.write_bytes(lab.original)
    lab.plist.unlink()
    lab.plist.symlink_to(operating)
    assert lab.run().returncode == 2 and operating.read_bytes() == lab.original


def test_the_operating_backup_directory_is_refused(lab):
    operating = lab.home / ".local" / "share" / "airag-plist-backup"
    args = ["--selftest", "--plist", str(lab.plist), "--backup-dir", str(operating), "--launchctl", str(lab.launchctl)]
    done = subprocess.run([PY, "-I", str(SCRIPT_PY), *args], env=lab.env(), stdin=subprocess.DEVNULL, capture_output=True, text=True)
    assert done.returncode == 2 and lab.untouched() and not operating.exists()
    inner = operating / "nested"
    args[3] = str(inner)
    assert subprocess.run([PY, "-I", str(SCRIPT_PY), *args], env=lab.env(), stdin=subprocess.DEVNULL, capture_output=True).returncode == 2


def test_the_real_launchctl_is_refused_in_test_mode(lab):
    link = lab.bin / "lc-link"
    link.symlink_to("/bin/launchctl")
    for tool in ("/bin/launchctl", "launchctl", str(link)):
        args = ["--selftest", "--plist", str(lab.plist), "--backup-dir", str(lab.backup), "--launchctl", tool]
        done = subprocess.run([PY, "-I", str(SCRIPT_PY), *args], env=lab.env(), stdin=subprocess.DEVNULL, capture_output=True)
        assert done.returncode == 2 and lab.untouched() and not lab.backup.exists()


def test_the_real_operating_paths_come_from_the_account_database_not_from_home(mod, lab, monkeypatch):
    import pwd
    account_home = Path(pwd.getpwuid(os.getuid()).pw_dir)
    monkeypatch.setenv("HOME", str(lab.home))
    assert mod.operating_plist() == account_home / "Library" / "LaunchAgents" / "com.airag.consumer.plist"
    assert mod.operating_backup_dir() == account_home / ".local" / "share" / "airag-plist-backup"
    monkeypatch.setenv("FAKE_LC_STATE", str(lab.state))
    bad = ["--selftest", "--plist", str(mod.operating_plist()), "--backup-dir", str(lab.backup), "--launchctl", str(lab.launchctl)]
    with pytest.raises(mod.Refuse) as caught:
        mod.build_context(bad)
    assert caught.value.code == 2
    bad = ["--selftest", "--plist", str(lab.plist), "--backup-dir", str(mod.operating_backup_dir()), "--launchctl", str(lab.launchctl)]
    with pytest.raises(mod.Refuse):
        mod.build_context(bad)


def test_production_mode_uses_only_the_operating_paths_and_the_absolute_tools(mod):
    context = mod.build_context([])
    assert context.plist == mod.operating_plist() and context.backup_dir == mod.operating_backup_dir()
    assert context.launchctl == "/bin/launchctl" and context.plutil == "/usr/bin/plutil" and context.selftest is False


# ===================================================================================== backup
def test_backup_is_a_real_copy_with_private_permissions(lab):
    assert lab.run().returncode == 0
    (backup,) = lab.backups()
    assert backup.read_bytes() == lab.original and not backup.name.endswith(".plist")
    assert stat.S_IMODE(backup.stat().st_mode) == 0o600 and stat.S_IMODE(lab.backup.stat().st_mode) == 0o700


def test_an_existing_loose_backup_directory_is_tightened(lab):
    lab.backup.mkdir(mode=0o755)
    lab.backup.chmod(0o755)
    assert lab.run().returncode == 0 and stat.S_IMODE(lab.backup.stat().st_mode) == 0o700


def test_a_failed_backup_copy_stops_before_any_edit(lab):
    lab.backup.write_text("a file where the directory should be", encoding="utf-8")
    done = lab.run()
    assert done.returncode == 5 and lab.untouched()


def test_a_backup_hash_mismatch_stops_before_any_edit_and_leaves_no_corrupt_copy(lab):
    done = lab.run(PLIST_EDIT_INJECT="backup_corrupt")
    assert done.returncode == 5, combined(done)
    assert lab.untouched() and lab.backups() == []


def test_the_backup_exists_before_the_candidate_is_built(lab):
    proc = start_paused(lab, "pause_candidate")
    try:
        (backup,) = lab.backups()
        assert backup.read_bytes() == lab.original
    finally:
        proc.send_signal(signal.SIGTERM)
        proc.communicate(timeout=20)


# ===================================================================================== candidate checks
def test_lint_runs_on_the_candidate_and_never_on_the_operating_file(lab):
    log = lab.root / "plutil-args.txt"
    tool = lab.fake_plutil(f'printf "%s\\n" "$@" >> "{log}"; exit 0')
    assert lab.run(plutil=tool).returncode == 0
    args = log.read_text(encoding="utf-8").split()
    assert args[0] == "-lint" and len(args) == 2
    assert Path(args[1]).parent == lab.work and not args[1].endswith(".plist") and args[1] != str(lab.plist)


def test_a_failed_lint_leaves_the_operating_file_and_no_candidate(lab):
    done = lab.run(plutil=lab.fake_plutil("exit 1"))
    assert done.returncode == 6 and lab.untouched()
    assert len(lab.backups()) == 1


def test_a_candidate_with_another_value_changed_is_not_published(lab):
    done = lab.run(PLIST_EDIT_INJECT="candidate_other")
    assert done.returncode == 6, combined(done)
    assert lab.untouched()


def test_a_candidate_with_other_permissions_is_not_published(lab):
    done = lab.run(PLIST_EDIT_INJECT="candidate_chmod")
    assert done.returncode == 6 and lab.untouched()


def test_candidate_checks_cover_keys_values_and_metadata(lab, mod):
    names = ["a", "b"]
    hashes = mod.digests({"a": 1, "b": [1, 2]})
    good = plistlib.dumps({"a": 1, "b": [1, 2]})
    assert mod.shape_ok(good, names, hashes)
    assert not mod.shape_ok(plistlib.dumps({"a": 1, "b": [1, 3]}), names, hashes)
    assert not mod.shape_ok(plistlib.dumps({"a": 1}), names, hashes)
    assert not mod.shape_ok(plistlib.dumps({"a": 1, "b": [1, 2], "ProcessType": "Background"}), names, hashes)
    assert not mod.shape_ok(plistlib.dumps({"b": [1, 2], "a": 1}, sort_keys=False), names, hashes)
    assert not mod.shape_ok(b"garbage", names, hashes)
    assert not mod.shape_ok(plistlib.dumps([1]), names, hashes)


def test_the_published_file_keeps_permissions(tmp_path):
    for mode in (0o600, 0o644, 0o664):
        (tmp_path / f"m{mode:o}").mkdir()
        lab = Lab(tmp_path / f"m{mode:o}", mode=mode)
        assert lab.run().returncode == 0
        assert stat.S_IMODE(lab.plist.stat().st_mode) == mode
        assert (lab.plist.stat().st_uid, lab.plist.stat().st_gid) == (os.getuid(), os.getgid())


def run_with_wrapped_meta(lab, mod, monkeypatch, changed_calls: set[int]):
    real, count = mod.meta, {"n": 0}

    def wrapped(info):
        count["n"] += 1
        mode, uid, gid = real(info)
        return (mode, uid + 1, gid) if count["n"] in changed_calls else (mode, uid, gid)

    monkeypatch.setattr(mod, "meta", wrapped)
    for key, value in lab.env().items():
        monkeypatch.setenv(key, value)
    handlers = {s: signal.getsignal(s) for s in (signal.SIGINT, signal.SIGTERM)}
    try:
        return mod.main(lab.argv())
    finally:
        for number, handler in handlers.items():
            signal.signal(number, handler)


def test_an_owner_mismatch_of_the_candidate_is_caught(lab, mod, monkeypatch):
    assert run_with_wrapped_meta(lab, mod, monkeypatch, {2}) == 6
    assert lab.untouched()


def test_an_owner_mismatch_after_publish_restores_the_backup(lab, mod, monkeypatch):
    assert run_with_wrapped_meta(lab, mod, monkeypatch, {3}) == 8
    assert lab.untouched()


def test_a_changed_plist_between_check_and_publish_is_not_overwritten(lab, mod, monkeypatch, capsys):
    changed = lab.original + b"<!-- someone else -->\n"

    def pause(self, name):
        if name == "pause_publish":
            self.plist.write_bytes(changed)

    monkeypatch.setattr(mod.Context, "pause", pause)
    for key, value in lab.env().items():
        monkeypatch.setenv(key, value)
    assert mod.main(lab.argv()) == 7
    assert lab.plist.read_bytes() == changed and lab.leftovers() == []


# ===================================================================================== publish / restore
def test_publish_is_one_rename_in_the_same_directory_of_a_complete_file(lab, mod, monkeypatch):
    seen = []
    real_replace = os.replace

    def spy(src, dst, *args, **kwargs):
        seen.append((Path(src), Path(dst), lab.plist.read_bytes(), Path(src).read_bytes()))
        return real_replace(src, dst, *args, **kwargs)

    monkeypatch.setattr(mod.os, "replace", spy)
    for key, value in lab.env().items():
        monkeypatch.setenv(key, value)
    assert mod.main(lab.argv()) == 0
    src, dst, before, candidate = seen[0]
    assert dst == lab.plist and src.parent == lab.plist.parent and not src.name.endswith(".plist")
    assert before == lab.original and candidate == plist_text(pt="").encode("utf-8")
    assert len(seen) == 1


def test_a_failed_publish_leaves_the_operating_file_complete(lab):
    done = lab.run(PLIST_EDIT_INJECT="publish_fail")
    assert done.returncode == 7 and lab.untouched()
    assert len(lab.backups()) == 1


def test_a_failed_post_check_restores_the_backup_and_compares_hashes(lab):
    done = lab.run(PLIST_EDIT_INJECT="post_corrupt")
    assert done.returncode == 8, combined(done)
    assert lab.untouched() and "복원: PASS" in done.stdout
    assert stat.S_IMODE(lab.plist.stat().st_mode) == 0o640


def test_changed_permissions_after_publish_are_caught_and_restored(lab):
    done = lab.run(PLIST_EDIT_INJECT="post_chmod")
    assert done.returncode == 8 and lab.untouched() and stat.S_IMODE(lab.plist.stat().st_mode) == 0o640


def test_a_failed_restore_says_so_and_names_the_backup(lab):
    done = lab.run(PLIST_EDIT_INJECT="post_corrupt,restore_fail")
    assert done.returncode == 9, combined(done)
    (backup,) = lab.backups()
    assert "복원: FAIL" in done.stdout and str(backup) in done.stdout
    assert backup.read_bytes() == lab.original
    assert lab.leftovers() == []


def test_restore_refuses_a_backup_that_no_longer_matches(lab, mod):
    backup = lab.root / "b.bak"
    backup.write_bytes(lab.original + b"x")
    context = mod.Context(lab.plist, lab.backup, str(lab.launchctl), mod.PLUTIL, True)
    assert mod.restore(context, backup, sha(lab.original), mod.meta(os.stat(lab.plist))) is False
    assert lab.plist.read_bytes() == lab.original


# ===================================================================================== signals
@pytest.mark.parametrize("sig,code", [(signal.SIGINT, 130), (signal.SIGTERM, 143)], ids=["int", "term"])
@pytest.mark.parametrize("hook", ["pause_candidate", "pause_publish", "pause_after_publish"])
def test_a_signal_at_any_stage_leaves_the_original_and_no_temporary_file(lab, sig, code, hook):
    proc = start_paused(lab, hook)
    if hook == "pause_publish":
        names = lab.leftovers()
        assert len(names) == 1 and names[0].endswith(".tmp") and lab.plist.read_bytes() == lab.original
    if hook == "pause_after_publish":
        assert lab.plist.read_bytes() == plist_text(pt="").encode("utf-8")
    proc.send_signal(sig)
    out, err = proc.communicate(timeout=30)
    assert proc.returncode == code, out + err
    assert lab.untouched()
    assert len(lab.backups()) == 1 and lab.backups()[0].read_bytes() == lab.original
    no_sentinel(out + err)


def test_a_signal_during_the_failed_restore_is_not_hidden(lab):
    proc = start_paused(lab, "pause_after_publish,restore_fail")
    proc.send_signal(signal.SIGTERM)
    out, err = proc.communicate(timeout=30)
    assert proc.returncode == 9 and "복원: FAIL" in out


def test_the_wrapper_forwards_a_signal_to_its_direct_child_only(lab):
    proc = start_paused(lab, "pause_candidate", via="sh")
    child = int(lab.pause_file.read_text().split()[0])
    assert child != proc.pid and alive(child)
    proc.send_signal(signal.SIGTERM)
    out, err = proc.communicate(timeout=30)
    assert proc.returncode == 143, out + err
    assert not alive(child) and lab.untouched()


# ===================================================================================== wrapper
def test_the_wrapper_passes_the_exit_code_through(lab):
    assert lab.run(via="sh").returncode == 0
    assert lab.plist.read_bytes() == plist_text(pt="").encode("utf-8")
    (lab.root / "second").mkdir()
    lab2 = Lab(lab.root / "second")
    lab2.plist.write_text(REJECTED["other-value"], encoding="utf-8")
    assert lab2.run(via="sh").returncode == 3


def test_the_wrapper_refuses_a_missing_or_relative_python(lab):
    for args in ([], ["--python", "python3"], ["--python", "/nonexistent/python"]):
        done = subprocess.run(["bash", str(SCRIPT_SH), *args, *lab.argv()], env=lab.env(), stdin=subprocess.DEVNULL,
                              capture_output=True, text=True)
        assert done.returncode == 2 and lab.untouched()


def test_the_wrapper_never_reads_from_the_terminal(lab):
    proc = subprocess.Popen(["bash", str(SCRIPT_SH), "--python", PY, *lab.argv()], env=lab.env(), stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:  # stdin stays open and silent: a script that waited for input would hang here
        assert proc.wait(timeout=30) == 0
    finally:
        proc.stdin.close()
        proc.stdout.close()
        proc.stderr.close()


def test_the_wrapper_is_syntactically_valid_and_documents_the_exit_codes():
    assert subprocess.run(["bash", "-n", str(SCRIPT_SH)]).returncode == 0
    for path in (SCRIPT_SH, SCRIPT_PY):
        text = path.read_text(encoding="utf-8")
        assert "Exit codes" in text
        for code in ("0", "2", "3", "4", "5", "6", "7", "8", "9", "130", "143"):
            assert re.search(rf"(?<![\d])\b{code}\b", text.split("Exit codes", 1)[1][:900]), (path.name, code)


# ===================================================================================== value hygiene
@pytest.mark.parametrize("scenario", ["ok", "absent", "rejected", "loaded", "lint", "candidate", "publish", "post", "restore"])
def test_no_value_ever_reaches_the_screen(tmp_path, scenario):
    content = {"absent": plist_text(pt=""), "rejected": REJECTED["other-value"]}.get(scenario)
    lab = Lab(tmp_path, content)
    env = {"loaded": {"FAKE_LC_LOADED": "1"}, "candidate": {"PLIST_EDIT_INJECT": "candidate_other"},
           "publish": {"PLIST_EDIT_INJECT": "publish_fail"}, "post": {"PLIST_EDIT_INJECT": "post_corrupt"},
           "restore": {"PLIST_EDIT_INJECT": "post_corrupt,restore_fail"}}.get(scenario, {})
    plutil = lab.fake_plutil("echo SENTINEL_ENV_a91c; echo /sentinel/out-b27d >&2; exit 1") if scenario == "lint" else None
    assert SENTINELS[0] in lab.original.decode("utf-8", "replace") or scenario == "rejected"
    done = lab.run(plutil=plutil, **env)
    no_sentinel(combined(done))
    for backup in lab.backups():
        no_sentinel(str(backup.name))


def test_the_sentinels_really_are_in_the_fixture(lab):
    text = lab.original.decode("utf-8")
    for sentinel in SENTINELS[:3]:
        assert sentinel in text


def test_the_printed_key_list_is_names_only(lab):
    done = lab.run()
    assert "완료" in done.stdout
    line = next(l for l in done.stdout.splitlines() if l.startswith("완료"))
    assert all(name in line for name in TOP_KEYS) and "ProcessType" in line


# ===================================================================================== second round (mutation gaps)
def test_a_plist_changed_while_the_backup_is_made_is_not_edited(lab):
    done = lab.run(PLIST_EDIT_INJECT="plist_changes")
    assert done.returncode == 5, combined(done)
    assert lab.backups() == [] and lab.leftovers() == []


def test_a_published_file_that_differs_from_the_candidate_is_rolled_back_even_if_it_still_parses(lab):
    done = lab.run(PLIST_EDIT_INJECT="post_comment")
    assert done.returncode == 8, combined(done)
    assert lab.untouched()


def test_a_restore_whose_result_does_not_match_the_backup_is_reported_as_failed(lab):
    done = lab.run(PLIST_EDIT_INJECT="post_corrupt,restore_corrupt")
    assert done.returncode == 9, combined(done)
    assert "복원: FAIL" in done.stdout and str(lab.backups()[0]) in done.stdout


def test_metadata_compares_mode_owner_and_group():
    import types
    from importlib import util
    spec = util.spec_from_file_location("plist_edit_meta", SCRIPT_PY)
    module = util.module_from_spec(spec)
    spec.loader.exec_module(module)
    base = types.SimpleNamespace(st_mode=0o100640, st_uid=501, st_gid=20)
    assert module.meta(base) == (0o640, 501, 20)
    assert module.meta(types.SimpleNamespace(st_mode=0o100640, st_uid=0, st_gid=20)) != module.meta(base)
    assert module.meta(types.SimpleNamespace(st_mode=0o100640, st_uid=501, st_gid=0)) != module.meta(base)
    assert module.meta(types.SimpleNamespace(st_mode=0o100644, st_uid=501, st_gid=20)) != module.meta(base)


def test_signals_inside_the_publish_step_are_held_until_it_ends(mod, tmp_path):
    context = mod.Context(tmp_path / "p", tmp_path / "b", "/x", "/y", True)
    with pytest.raises(mod.Interrupted) as caught:
        with context.deferred():
            assert context.defer is True
            context.pending = signal.SIGTERM
    assert caught.value.signum == signal.SIGTERM and context.defer is False
    context.pending = None
    with context.deferred():
        pass
    assert context.defer is False


def test_a_signal_during_the_rename_lets_the_rename_finish_and_then_rolls_back(lab, mod, monkeypatch):
    real_replace, seen = os.replace, []

    def replace(src, dst, *args, **kwargs):
        seen.append(Path(dst))
        if len(seen) == 1:
            os.kill(os.getpid(), signal.SIGTERM)  # arrives while the publish step is running
        return real_replace(src, dst, *args, **kwargs)

    monkeypatch.setattr(mod.os, "replace", replace)
    for key, value in lab.env().items():
        monkeypatch.setenv(key, value)
    handlers = {s: signal.getsignal(s) for s in (signal.SIGINT, signal.SIGTERM)}
    try:
        code = mod.main(lab.argv())
    finally:
        for number, handler in handlers.items():
            signal.signal(number, handler)
    assert code == 143 and len(seen) == 2  # the publish rename completed, then the restore rename
    assert lab.untouched()


def test_the_wrapper_returns_the_childs_own_exit_code_after_a_signal(lab):
    proc = start_paused(lab, "pause_after_publish,restore_fail", via="sh")
    proc.send_signal(signal.SIGTERM)
    out, err = proc.communicate(timeout=30)
    assert proc.returncode == 9, out + err
    assert "복원: FAIL" in out


def test_the_wrapper_waits_for_the_childs_cleanup_before_it_exits(lab):
    proc = start_paused(lab, "pause_after_publish", via="sh")
    proc.send_signal(signal.SIGTERM)
    out, err = proc.communicate(timeout=30)
    assert proc.returncode == 143 and lab.untouched()


def test_a_launchctl_answer_is_never_echoed(lab):
    done = lab.run(FAKE_LC_LOADED="1")
    assert done.returncode == 4
    assert "sentinel" not in combined(done).lower() and "com.example.other" not in combined(done)


# ===================================================================================== third round (mutation gaps)
def test_a_hanging_launchctl_is_asked_once_and_not_retried(lab):
    done = lab.run(FAKE_LC_SLEEP="3", PLIST_EDIT_CALL_S="0.4")
    assert done.returncode == 4 and lab.calls() == ["list"]


def test_an_error_while_re_checking_the_published_file_is_a_failure_and_rolls_back(lab):
    done = lab.run(PLIST_EDIT_INJECT="post_error")
    assert done.returncode == 8, combined(done)
    assert lab.untouched() and "복원: PASS" in done.stdout and "사후 재검증 오류" in done.stdout


def test_a_restore_that_leaves_other_owner_or_permissions_is_reported_as_failed(lab, mod, monkeypatch):
    assert run_with_wrapped_meta(lab, mod, monkeypatch, {3, 4}) == 9


def test_the_account_database_home_is_always_among_the_protected_homes(mod, lab, monkeypatch):
    import pwd
    monkeypatch.setenv("HOME", str(lab.home))
    homes = mod.home_directories()
    assert Path(pwd.getpwuid(os.getuid()).pw_dir) in homes and lab.home in homes


def test_the_python_child_is_isolated_from_the_environment(lab):
    poison = lab.root / "poison"
    poison.mkdir()
    marker = lab.root / "poisoned.txt"
    (poison / "plistlib.py").write_text(f"open({str(marker)!r}, 'w').write('x')\nraise ImportError\n", encoding="utf-8")
    lab.run(via="sh", PYTHONPATH=str(poison))
    assert not marker.exists() and lab.plist.read_bytes() == plist_text(pt="").encode("utf-8")
    lab.run(via="py", PYTHONPATH=str(poison))
    assert not marker.exists()


def test_temporary_files_are_removed_even_when_the_run_ends_by_refusal_after_the_candidate_exists(lab):
    done = lab.run(plutil=lab.fake_plutil("exit 1"))
    assert done.returncode == 6 and lab.leftovers() == []


# ===================================================================================== DA round 1 (M1 · M2 · m1 · m2 · m3)
def inproc(lab, mod, monkeypatch, **env):
    """Run ``main`` in this process (real signal handlers installed by it) with the fixture environment."""
    for key, value in lab.env(**env).items():
        monkeypatch.setenv(key, value)
    handlers = {s: signal.getsignal(s) for s in (signal.SIGINT, signal.SIGTERM)}
    try:
        return mod.main(lab.argv())
    finally:
        for number, handler in handlers.items():
            signal.signal(number, handler)


def signal_on_say(mod, monkeypatch, marker, sig):
    """The process signals itself at the very moment the line holding ``marker`` is being printed."""
    real = mod.say

    def say(text):
        if marker in text:
            os.kill(os.getpid(), sig)
        real(text)

    monkeypatch.setattr(mod, "say", say)


def signal_on_call(owner, name, nth, sig, monkeypatch):
    """The process signals itself as the ``nth`` call of ``owner.name`` starts."""
    real, count = getattr(owner, name), {"n": 0}

    def wrapper(*args, **kwargs):
        count["n"] += 1
        if count["n"] == nth:
            os.kill(os.getpid(), sig)
        return real(*args, **kwargs)

    monkeypatch.setattr(owner, name, wrapper)


SIGS = [pytest.param(signal.SIGINT, 130, id="int"), pytest.param(signal.SIGTERM, 143, id="term")]
# (where the signal lands after the publish, extra injections)
LIFECYCLE = {
    "rename": (lambda mod, mp, sig: signal_on_call(mod.os, "replace", 1, sig, mp), ""),
    "before-post-check": (lambda mod, mp, sig: signal_on_call(mod, "fsync_directory", 1, sig, mp), ""),
    "post-check-line": (lambda mod, mp, sig: signal_on_say(mod, mp, "사후 재검증: PASS", sig), ""),
    "done-line": (lambda mod, mp, sig: signal_on_say(mod, mp, "완료:", sig), ""),
    "restore-rename": (lambda mod, mp, sig: signal_on_call(mod.os, "replace", 2, sig, mp), "post_corrupt"),
    "restore-fsync": (lambda mod, mp, sig: signal_on_call(mod, "fsync_directory", 2, sig, mp), "post_corrupt"),
    "restore-line": (lambda mod, mp, sig: signal_on_say(mod, mp, "복원: PASS", sig), "post_corrupt"),
}


@pytest.mark.parametrize("sig,code", SIGS)
@pytest.mark.parametrize("where", sorted(LIFECYCLE))
def test_a_signal_anywhere_after_the_publish_restores_the_original_and_ends_with_the_signal_code(lab, mod, monkeypatch, capsys, where, sig, code):
    arm, inject = LIFECYCLE[where]
    arm(mod, monkeypatch, sig)
    assert inproc(lab, mod, monkeypatch, PLIST_EDIT_INJECT=inject) == code
    out = capsys.readouterr().out
    assert lab.untouched(), where
    assert "복원: PASS" in out and "운영 파일 불변" not in out
    no_sentinel(out)


@pytest.mark.parametrize("sig,code", SIGS)
def test_no_completion_line_follows_a_signal_that_was_recorded_before_it(lab, mod, monkeypatch, capsys, sig, code):
    signal_on_say(mod, monkeypatch, "사후 재검증: PASS", sig)
    assert inproc(lab, mod, monkeypatch) == code
    assert "완료:" not in capsys.readouterr().out and lab.untouched()


def test_a_broken_output_while_reporting_the_restore_does_not_change_the_outcome(lab, mod, monkeypatch):
    real = mod.say

    def say(text):
        if text.startswith("복원"):
            raise BrokenPipeError
        real(text)

    monkeypatch.setattr(mod, "say", say)
    assert inproc(lab, mod, monkeypatch, PLIST_EDIT_INJECT="post_corrupt") == 8
    assert lab.untouched()
    monkeypatch.undo()
    (lab.root / "second").mkdir()
    again = Lab(lab.root / "second")
    monkeypatch.setattr(mod, "say", say)
    assert inproc(again, mod, monkeypatch, PLIST_EDIT_INJECT="post_corrupt,restore_fail") == 9


@pytest.mark.parametrize("sig,code", SIGS)
def test_a_signal_while_the_final_success_line_is_printed_with_a_failing_restore_is_exit_nine(lab, mod, monkeypatch, capsys, sig, code):
    signal_on_say(mod, monkeypatch, "완료:", sig)
    assert inproc(lab, mod, monkeypatch, PLIST_EDIT_INJECT="restore_fail") == 9
    out = capsys.readouterr().out
    assert "복원: FAIL" in out and len(lab.backups()) == 1


def test_a_failure_to_print_the_final_line_after_the_publish_is_rolled_back(lab, mod, monkeypatch, capsys):
    real = mod.say

    def say(text):
        if "완료:" in text:
            raise BrokenPipeError
        real(text)

    monkeypatch.setattr(mod, "say", say)
    assert inproc(lab, mod, monkeypatch) == 8
    assert lab.untouched() and "복원: PASS" in capsys.readouterr().out


@pytest.mark.parametrize("sig,code", SIGS)
def test_a_signal_before_the_publish_still_says_the_operating_file_is_unchanged(lab, mod, monkeypatch, capsys, sig, code):
    signal_on_say(mod, monkeypatch, "후보 검증: PASS", sig)
    assert inproc(lab, mod, monkeypatch) == code
    assert lab.untouched() and "운영 파일 불변" in capsys.readouterr().out


# ---- M2: both path arguments are checked against both protected spaces (LaunchAgents and the operating backup space)
def protected_space(lab) -> tuple[Path, Path, Path]:
    agents = lab.home / "Library" / "LaunchAgents"
    agents.mkdir(parents=True)
    agents.chmod(0o755)
    store = lab.home / ".local" / "share" / "airag-plist-backup"
    store.mkdir(parents=True)
    old = store / "old-copy.bak"
    old.write_bytes(lab.original)
    return agents, store, old


def selftest_with(lab, plist: Path, backup_dir: Path) -> subprocess.CompletedProcess:
    args = ["--selftest", "--plist", str(plist), "--backup-dir", str(backup_dir), "--launchctl", str(lab.launchctl)]
    return subprocess.run([PY, "-I", str(SCRIPT_PY), *args], env=lab.env(), stdin=subprocess.DEVNULL, capture_output=True, text=True)


def space_untouched(lab, agents: Path, store: Path, old: Path) -> bool:
    return (stat.S_IMODE(agents.stat().st_mode) == 0o755 and sorted(p.name for p in agents.iterdir()) == []
            and old.read_bytes() == lab.original and sorted(p.name for p in store.iterdir()) == ["old-copy.bak"])


def test_the_launch_agents_directory_given_as_the_backup_directory_is_refused_before_anything_is_written(lab):
    agents, store, old = protected_space(lab)
    done = selftest_with(lab, lab.plist, agents)
    assert done.returncode == 2, combined(done)
    assert space_untouched(lab, agents, store, old) and lab.untouched() and lab.calls() == []


def test_a_file_in_the_operating_backup_space_given_as_the_plist_is_refused_before_anything_is_written(lab):
    agents, store, old = protected_space(lab)
    done = selftest_with(lab, old, lab.backup)
    assert done.returncode == 2, combined(done)
    assert space_untouched(lab, agents, store, old) and not lab.backup.exists() and lab.calls() == []


def test_symlinks_into_the_protected_spaces_are_refused_in_either_role(lab):
    agents, store, old = protected_space(lab)
    link_dir = lab.root / "backup-link"
    link_dir.symlink_to(agents)
    link_file = lab.root / "plist-link"
    link_file.symlink_to(old)
    for plist, backup_dir in ((lab.plist, link_dir), (link_file, lab.backup), (lab.plist, link_dir / "sub"), (link_file, link_dir)):
        done = selftest_with(lab, plist, backup_dir)
        assert done.returncode == 2, (plist, backup_dir, combined(done))
        assert space_untouched(lab, agents, store, old) and lab.untouched() and not lab.backup.exists() and lab.calls() == []


def test_the_operating_backup_space_and_launch_agents_are_refused_in_both_roles_for_the_account_database_home(mod, lab, monkeypatch):
    for key, value in lab.env().items():
        monkeypatch.setenv(key, value)
    import pwd
    account_home = Path(pwd.getpwuid(os.getuid()).pw_dir)  # not via mod.operating_*: those are the very thing being checked
    agents = account_home / "Library" / "LaunchAgents"
    store = account_home / ".local" / "share" / "airag-plist-backup"
    base = ["--selftest", "--launchctl", str(lab.launchctl)]
    crossed = [(store / "never-created.bak", lab.backup), (lab.plist, agents), (lab.plist, agents / "sub"),
               (agents / "never-created.plist", store), (store, agents)]
    for plist, backup_dir in crossed:
        with pytest.raises(mod.Refuse) as caught:
            mod.build_context([*base, "--plist", str(plist), "--backup-dir", str(backup_dir)])
        assert caught.value.code == 2, (plist, backup_dir)


# ---- m1: a comment between the key and the value is not silently dropped
def test_a_comment_between_the_key_and_its_value_is_refused_not_deleted(tmp_path):
    between = "  <key>ProcessType</key><!-- KEEP_BETWEEN_KEY_AND_VALUE --><string>Background</string>\n"
    lab = Lab(tmp_path, plist_text(pt=between))
    done = lab.run()
    assert done.returncode == 3, combined(done)
    assert lab.untouched() and not lab.backup.exists() and lab.calls() == []
    no_sentinel(combined(done))


def test_comments_around_the_two_elements_survive_the_edit(tmp_path):
    around = "  <!-- before -->\n  <key>ProcessType</key>\n  <string>Background</string> <!-- trailing -->\n  <!-- after -->\n"
    lab = Lab(tmp_path, plist_text(pt=around))
    assert lab.run().returncode == 0
    data = lab.plist.read_bytes()
    for comment in (b"<!-- before -->", b"<!-- trailing -->", b"<!-- after -->", b"<!-- sentinel comment: keep me -->"):
        assert comment in data
    assert b"ProcessType" not in data and top_keys(lab.plist) == TOP_KEYS


def test_whitespace_alone_between_the_key_and_its_value_is_accepted(tmp_path):
    spaced = "  <key>ProcessType</key>\n\n\t  <string>Background</string>\n"
    lab = Lab(tmp_path, plist_text(pt=spaced))
    assert lab.run().returncode == 0
    assert lab.plist.read_bytes() == plist_text(pt="").encode("utf-8")


# ---- m2: a normal run prints no backup path
def test_a_normal_run_never_prints_the_backup_location(tmp_path):
    lab = Lab(tmp_path)
    lab.backup = tmp_path / "SENTINEL_BACKUP_DIR_e4f1"
    done = lab.run()
    assert done.returncode == 0, combined(done)
    assert "SENTINEL_BACKUP_DIR_e4f1" not in combined(done) and str(tmp_path) not in combined(done)
    assert "백업: PASS" in done.stdout and len(lab.backups()) == 1


def test_a_failed_restore_still_names_the_backup_location(tmp_path):
    lab = Lab(tmp_path)
    lab.backup = tmp_path / "SENTINEL_BACKUP_DIR_e4f1"
    done = lab.run(PLIST_EDIT_INJECT="post_corrupt,restore_fail")
    assert done.returncode == 9 and str(lab.backups()[0]) in done.stdout


# ---- m3: valid property lists whose root is not a dictionary are refused with exit 3
@pytest.mark.parametrize("name,document", [("empty-array", []), ("array-of-strings", ["Label", "ProcessType"]),
                                           ("string", "Background"), ("integer", 1), ("true", True), ("data", b"x")])
def test_a_valid_non_dictionary_root_is_refused_with_exit_three(tmp_path, name, document):
    lab = Lab(tmp_path, plistlib.dumps(document, fmt=plistlib.FMT_XML))
    done = lab.run()
    assert done.returncode == 3, combined(done)
    assert lab.untouched() and not lab.backup.exists() and lab.calls() == []
