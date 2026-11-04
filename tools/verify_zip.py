"""Check a built mod archive before it is published, and write its SHA-256 next to it.

Usage: python tools/verify_zip.py [build/Daneisra-SmartAutomation-<version>.zip]
Without an argument, the archive matching the current BUILD is checked. Exit code 0 when every check passes.
"""
import hashlib
import json
import pathlib
import re
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOD_ID = "Daneisra-SmartAutomation"
PREFIX = f"mods-unpacked/{MOD_ID}/"
ALLOWED = {".gd", ".uid", ".json"}
REQUIRED = ["manifest.json", "mod_main.gd"]
# Anything that must never ship: saves, secrets, game data, logs, tests, editor or build leftovers.
FORBIDDEN = re.compile(r"(?i)(savegame|token|\.dat$|\.bak$|\.pck$|\.gdc$|\.log$|\.env$|tests?/|\.godot/|\.import$|__pycache__|\.zip$)")
PRIVATE = re.compile(r"(?i)(C:\\\\Users|C:/Users|AppData|steamapps|@gmail|password|ghp_|github_pat)")


def fail(errors: list, message: str) -> None:
    errors.append(message)


def main() -> int:
    mod_dir = ROOT / "mods-unpacked" / MOD_ID
    build = re.search(r'const BUILD := "([^"]+)"', (mod_dir / "mod_main.gd").read_text(encoding="utf-8")).group(1)
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / f"{MOD_ID}-{build}.zip"
    errors: list = []
    if not path.is_file():
        print(f"FAIL archive not found: {path}")
        return 1

    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            fail(errors, "corrupted entry: %s" % archive.testzip())
        names = archive.namelist()
        files = [n for n in names if not n.endswith("/")]
        for name in names:
            if "\\" in name or name.startswith("/") or ".." in name.split("/"):
                fail(errors, f"bad path: {name}")
            if not name.startswith(PREFIX):
                fail(errors, f"outside {PREFIX}: {name}")
            if FORBIDDEN.search(name):
                fail(errors, f"forbidden file: {name}")
        for name in files:
            if pathlib.PurePosixPath(name).suffix not in ALLOWED:
                fail(errors, f"unexpected file type: {name}")
            text = archive.read(name).decode("utf-8", errors="replace")
            if PRIVATE.search(text):
                fail(errors, f"private data in {name}: {PRIVATE.search(text).group(0)}")
        for required in REQUIRED:
            if PREFIX + required not in names:
                fail(errors, f"missing {required}")

        # Every file of the mod folder ships, and only those.
        on_disk = {p.relative_to(ROOT).as_posix() for p in mod_dir.rglob("*") if p.is_file()}
        if set(files) != on_disk:
            fail(errors, "archive differs from the mod folder: missing %s, extra %s" % (sorted(on_disk - set(files)), sorted(set(files) - on_disk)))

        manifest = json.loads(archive.read(PREFIX + "manifest.json").decode("utf-8"))
        main_gd = archive.read(PREFIX + "mod_main.gd").decode("utf-8")
        shipped_build = re.search(r'const BUILD := "([^"]+)"', main_gd).group(1)
        if f"{manifest.get('namespace')}-{manifest.get('name')}" != MOD_ID:
            fail(errors, "manifest namespace-name is not %s" % MOD_ID)
        if not re.fullmatch(r"\d+\.\d+\.\d+", manifest.get("version_number", "")):
            fail(errors, "version_number is not major.minor.patch: %s" % manifest.get("version_number"))
        if shipped_build != manifest.get("version_number"):
            fail(errors, f"BUILD {shipped_build} is not the release version {manifest.get('version_number')} (a dev build?)")
        if not path.name == f"{MOD_ID}-{shipped_build}.zip":
            fail(errors, f"archive name {path.name} does not match BUILD {shipped_build}")
        schema = manifest.get("extra", {}).get("godot", {}).get("config_schema", {}).get("properties", {})
        if schema.get("regulation_mode", {}).get("default") != "off":
            fail(errors, "regulation must be off by default")
        for key in ["compatible_game_version", "compatible_mod_loader_version", "authors"]:
            if not manifest.get("extra", {}).get("godot", {}).get(key):
                fail(errors, f"manifest misses {key}")
        for name in files:
            if name.endswith(".gd") and "res://tests" in archive.read(name).decode("utf-8"):
                fail(errors, f"{name} refers to the tests")

    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if errors:
        print("FAIL %s" % path.name)
        for error in errors:
            print("  - " + error)
        return 1
    sha_file = path.with_name(path.name + ".sha256")
    sha_file.write_text(f"{digest}  {path.name}\n", encoding="utf-8", newline="\n")
    print(f"OK {path.name}: {len(files)} files, version {shipped_build}")
    print(f"SHA-256 {digest}")
    print(f"written to {sha_file.relative_to(ROOT).as_posix() if sha_file.is_relative_to(ROOT) else sha_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
