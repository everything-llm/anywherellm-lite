# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Runs AnywhereLLM Lite against a real AnythingLLM and the suite's bridge, from the suite's head.

It fetches anythingllm-suite's `main` from GitHub into `build/e2e/suite`, with no pin, so a suite
change that breaks the app fails here, and runs the suite's `tools/e2e` with this script's
`inside` as its command. `tools/e2e` starts a throwaway AnythingLLM in a container, installs the
bridge beside it, and removes both afterwards; `inside` starts the model stub in that container,
points AnythingLLM at it, runs `contract.dart` against the server and walks `steps.toml` on the
emulator with the real app, paired by its link. A failed phone step leaves its screenshot, the
screen's dump and the log in `build/e2e/`.

    uv run tool/e2e/e2e.py                    # the contract, then the phone
    uv run tool/e2e/e2e.py --only contract    # the adapters alone, no emulator
    uv run tool/e2e/e2e.py --suite ~/suite    # a local checkout in place of GitHub's head

The phone half runs on an emulator of its own, `lite_e2e` on port 5580, made the first time
and wiped at each boot, so it never touches an emulator in other use. It needs podman or docker,
curl, Node 22.18 or later, git, Flutter, and the Android SDK's android-36 google_apis image.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import tomllib
import urllib.request
from datetime import datetime
from pathlib import Path
from urllib.parse import quote, urlsplit

HERE = Path(__file__).parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT / "tool"))
from device import (
    Driver,
    StepError,
    close_device,
    install,
    own_device,
    restore,
    steady,
    tool,
)

SUITE = "https://github.com/BinaryBand/anythingllm-suite.git"
OUT = ROOT / "build/e2e"
APK = ROOT / "build/app/outputs/flutter-apk/app-debug.apk"
STUB_PORT = 8901
MODEL = "e2e-model"
# The emulator's address for the machine it runs on.
HOST = "10.0.2.2"
# The e2e's own emulator, wiped at each boot, on a port of its own beside any other running.
AVD = "lite_e2e"
PORT = 5580
IMAGE = "system-images;android-36;google_apis;x86_64"


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, check=True, **kwargs)


# --- Outside: the suite, then its tools/e2e with `inside` as the command ---------------------


def fetch_suite() -> Path:
    """GitHub's head of the suite in build/e2e/suite, cloned or brought up to it."""
    suite = OUT / "suite"
    if (suite / ".git").exists():
        run(["git", "-C", str(suite), "fetch", "-q", "origin", "main"])
        run(["git", "-C", str(suite), "reset", "-q", "--hard", "origin/main"])
        run(["git", "-C", str(suite), "clean", "-q", "-fd"])
    else:
        OUT.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "-q", SUITE, str(suite)])
    return suite


def npm_ready(suite: Path) -> None:
    """`npm ci` in the suite's packages when its lock changed since the last run."""
    lock = suite / "packages/package-lock.json"
    stamp = suite / "packages/node_modules/.e2e-lock.sha256"
    digest = hashlib.sha256(lock.read_bytes()).hexdigest()
    if stamp.exists() and stamp.read_text() == digest:
        return
    print("[e2e] npm ci in the suite's packages")
    run(["npm", "ci", "--silent"], cwd=suite / "packages")
    stamp.write_text(digest)


def outside(args: argparse.Namespace) -> int:
    suite = Path(args.suite).expanduser().resolve() if args.suite else fetch_suite()
    commit = subprocess.run(["git", "-C", str(suite), "log", "-1", "--format=%h %s"],
                            capture_output=True, text=True).stdout.strip()
    print(f"[e2e] the suite at {commit or suite}")
    npm_ready(suite)
    inner = ["uv", "run", "--quiet", str(Path(__file__).resolve()), "inside", "--only", args.only]
    inner += ["--headless"] * args.headless + ["--keep-emulator"] * args.keep_emulator
    return subprocess.run([str(suite / "tools/e2e"), *inner], cwd=ROOT).returncode


# --- Inside: the stub, the server's settings, the contract and the phone ---------------------


def env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        sys.exit(f"{name} is not set: run `uv run tool/e2e/e2e.py`, which runs this inside the suite's tools/e2e")
    return value


def api(path: str, body: dict, base: str = "") -> dict:
    """POSTs [body] to AnythingLLM's developer API, or to [base] when it is given, with the e2e's
    key, and its JSON."""
    request = urllib.request.Request(
        (base or env("E2E_ALLM_URL") + "/api/v1") + path, data=json.dumps(body).encode(), method="POST",
        headers={"Authorization": "Bearer " + env("E2E_KEY"), "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read() or b"{}")


def start_stub() -> None:
    """The model stub in AnythingLLM's container, and AnythingLLM answering and embedding with it."""
    engine, container = env("E2E_ENGINE"), env("E2E_CONTAINER")
    run([engine, "cp", str(HERE / "stub.mjs"), f"{container}:/tmp/stub.mjs"], stdout=subprocess.DEVNULL)
    run([engine, "exec", "-d", container, "node", "/tmp/stub.mjs", str(STUB_PORT)], stdout=subprocess.DEVNULL)
    probe = f"fetch('http://127.0.0.1:{STUB_PORT}/v1/models').then(r => process.exit(r.ok ? 0 : 1), () => process.exit(1))"
    for _ in range(30):
        if subprocess.run([engine, "exec", container, "node", "-e", probe]).returncode == 0:
            break
        time.sleep(1)
    else:
        sys.exit("the model stub did not start")
    base = f"http://127.0.0.1:{STUB_PORT}/v1"
    changes = {
        "LLMProvider": "generic-openai", "GenericOpenAiBasePath": base, "GenericOpenAiModelPref": MODEL,
        "GenericOpenAiTokenLimit": "8192", "GenericOpenAiMaxTokens": "1024", "GenericOpenAiKey": "e2e",
        "EmbeddingEngine": "generic-openai", "EmbeddingBasePath": base, "EmbeddingModelPref": MODEL,
        "EmbeddingModelMaxChunkLength": "1000", "GenericOpenAiEmbeddingApiKey": "e2e",
    }
    answer = api("/system/update-env", changes)
    if answer.get("error") or set(changes) - set(answer.get("newValues") or {}):
        sys.exit(f"AnythingLLM refused the stub's settings: {answer.get('error') or answer}")
    api(f"/workspace/{env('E2E_WORKSPACE')}/update", {"chatMode": "chat"})
    print(f"[e2e] AnythingLLM answers with the stub, {MODEL}")


def contract() -> bool:
    print("[e2e] flutter test tool/e2e/contract.dart")
    extra = {"E2E_PAGE": f"http://127.0.0.1:{STUB_PORT}/page.html"}
    return subprocess.run(["flutter", "test", "tool/e2e/contract.dart"], cwd=ROOT,
                          env={**os.environ, **extra}).returncode == 0


def on_phone(address: str) -> str:
    """[address] on this machine as the emulator reaches it."""
    port = urlsplit(address).port
    return f"http://{HOST}:{port}"


def make_avd() -> None:
    """The e2e's own AVD, a Pixel 6 on [IMAGE], made the first time."""
    emulator = tool("emulator", "emulator")
    if AVD in subprocess.run([emulator, "-list-avds"], capture_output=True, text=True).stdout.split():
        return
    print(f"[e2e] making the AVD {AVD}")
    avdmanager = tool("avdmanager", "cmdline-tools/latest/bin")
    subprocess.run([avdmanager, "create", "avd", "-n", AVD, "-k", IMAGE, "-d", "pixel_6"],
                   input="no\n", text=True, check=True, stdout=subprocess.DEVNULL)


def phone(args: argparse.Namespace) -> bool:
    print("[e2e] building the app")
    built = subprocess.run(["flutter", "build", "apk", "--debug", "--target-platform", "android-x64"],
                           cwd=ROOT, capture_output=True, text=True)
    if built.returncode != 0:
        print(built.stdout[-3000:] + built.stderr[-3000:])
        return False
    # A task for Upcoming to list, through the bridge as the app reaches it.
    api("/scheduled-jobs/new", {"name": "Morning check", "prompt": "Say good morning.", "tools": None,
                                "schedule": "0 6 * * *"}, base=env("E2E_BRIDGE_URL"))
    folder = OUT / datetime.now().strftime("phone-%Y%m%d-%H%M%S")
    folder.mkdir(parents=True)
    apk = shutil.copy(APK, folder / "app.apk")

    link = (f"anywherellm://connect?url={quote(on_phone(env('E2E_ALLM_URL')), safe='')}"
            f"&key={quote(env('E2E_KEY'), safe='')}&toolkit={quote(on_phone(env('E2E_BRIDGE_URL')), safe='')}")
    make_avd()
    device, booted = own_device(AVD, PORT, args.headless, "the e2e replaces the installed app")
    before = steady(device)
    walk = Driver(device, folder, {"pairing": link})
    plan = tomllib.loads((HERE / "steps.toml").read_text())
    ok = True
    try:
        install(device, Path(apk))
        device.shell("logcat -c", check=False)
        walk.launch()
        for step in plan["step"]:
            print(f"[e2e] phone: {step['name']}", end=" ", flush=True)
            try:
                for action in step["do"]:
                    walk.do(action)
            except (StepError, subprocess.TimeoutExpired) as error:
                print(f"failed: {error}")
                try:
                    walk.shoot(f"{step['name']}-FAILED")
                except StepError:
                    pass
                (folder / "logcat.txt").write_text(device.shell("logcat -d -v time", check=False))
                ok = False
                break
            print("ok")
    finally:
        restore(device, before)
        close_device(device, booted, args.keep_emulator)
    if not ok:
        print(f"[e2e] what the phone showed: {folder}")
    return ok


def inside(args: argparse.Namespace) -> int:
    start_stub()
    passed = True
    if args.only in ("all", "contract"):
        passed = contract()
    if passed and args.only in ("all", "phone"):
        passed = phone(args)
    return 0 if passed else 1


def main() -> int:
    sys.stdout.reconfigure(line_buffering=True)
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("stage", nargs="?", choices=["inside"], help=argparse.SUPPRESS)
    p.add_argument("--only", choices=["all", "contract", "phone"], default="all", help="run one half")
    p.add_argument("--suite", help="a local checkout of anythingllm-suite in place of GitHub's head")
    p.add_argument("--headless", action="store_true", help="boot without a window")
    p.add_argument("--keep-emulator", action="store_true",
                   help=f"leave {AVD} running, for the next run to use as it is")
    args = p.parse_args()
    return inside(args) if args.stage == "inside" else outside(args)


if __name__ == "__main__":
    sys.exit(main())
