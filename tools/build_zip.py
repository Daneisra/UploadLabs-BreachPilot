"""Build the mod zip into build/. Godot needs forward slashes in entry names, so zipfile is used directly.

--trial builds the archive of an authorized active trial: it is the only way ACTIONS_ENABLED becomes
true, in the archive alone. The repository's sources are not changed.
"""
import json
import pathlib
import re
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOD_DIR = ROOT / "mods-unpacked" / "Daneisra-SmartAutomation"
POLICY = "features/threat_manager/action_policy.gd"
LOCK_CLOSED = "const ACTIONS_ENABLED := false"
LOCK_OPEN = "const ACTIONS_ENABLED := true"
TEST_ONLY = re.compile(r"ArmedActuator|ArmedObserver|TrialActuator|TrialObserver|_accepts_active_without_trial\(\) -> bool:\s+return true")

trial = "--trial" in sys.argv[1:]
manifest = json.loads((MOD_DIR / "manifest.json").read_text(encoding="utf-8"))
main_text = (MOD_DIR / "mod_main.gd").read_text(encoding="utf-8")
build = re.search(r'const BUILD := "([^"]+)"', main_text).group(1)
if not build.startswith(manifest["version_number"]):
    raise SystemExit(f"BUILD {build} does not match manifest {manifest['version_number']}")
archive_build = re.sub(r"-dev\.\d+$", "-trial.1", build) if trial else build
out = ROOT / "build" / f"Daneisra-SmartAutomation-{archive_build}.zip"
out.parent.mkdir(exist_ok=True)


def content_of(path: pathlib.Path) -> bytes:
    relative = path.relative_to(MOD_DIR).as_posix()
    data = path.read_bytes()
    if relative == POLICY:
        text = data.decode("utf-8")
        if text.count(LOCK_CLOSED) != 1 or LOCK_OPEN in text:
            raise SystemExit("the repository's policy must hold exactly one closed lock")
        if trial:
            data = text.replace(LOCK_CLOSED, LOCK_OPEN).encode("utf-8")
    elif trial and relative == "mod_main.gd":
        data = data.decode("utf-8").replace(f'"{build}"', f'"{archive_build}"').encode("utf-8")
    if path.suffix == ".gd" and TEST_ONLY.search(data.decode("utf-8")):
        raise SystemExit(f"test-only code found in {relative}")
    return data


with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(MOD_DIR.rglob("*")):
        if path.is_file():
            archive.writestr(path.relative_to(ROOT).as_posix(), content_of(path))

with zipfile.ZipFile(out) as archive:
    names = archive.namelist()
    outside = [name for name in names if not name.startswith("mods-unpacked/Daneisra-SmartAutomation/")]
    if outside:
        raise SystemExit(f"unexpected entries: {outside}")
    policy = archive.read(f"mods-unpacked/Daneisra-SmartAutomation/{POLICY}").decode("utf-8")
    if (LOCK_OPEN in policy) != trial or (LOCK_CLOSED in policy) == trial:
        raise SystemExit("the archive's lock is not what was asked")
    print(out)
    print("actions enabled:", trial)
    print("\n".join(names))
