"""Build the mod zip into build/. Godot needs forward slashes in entry names, so zipfile is used directly."""
import json
import pathlib
import re
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOD_ID = "Daneisra-BreachPilot"
MOD_DIR = ROOT / "mods-unpacked" / MOD_ID
# Shipped next to the mod's code, as in the archives of the author's other mods.
EXTRA = {ROOT / "LICENSE": f"mods-unpacked/{MOD_ID}/LICENSE"}

manifest = json.loads((MOD_DIR / "manifest.json").read_text(encoding="utf-8"))
build = re.search(r'const BUILD := "([^"]+)"', (MOD_DIR / "mod_main.gd").read_text(encoding="utf-8")).group(1)
if not build.startswith(manifest["version_number"]):
    raise SystemExit(f"BUILD {build} does not match manifest {manifest['version_number']}")
out = ROOT / "build" / f"{MOD_ID}-v{build}.zip"
out.parent.mkdir(exist_ok=True)

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(MOD_DIR.rglob("*")):
        if path.is_file():
            archive.write(path, path.relative_to(ROOT).as_posix())
    for source, name in EXTRA.items():
        archive.write(source, name)

with zipfile.ZipFile(out) as archive:
    print(out)
    print("\n".join(archive.namelist()))
