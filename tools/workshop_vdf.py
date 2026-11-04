"""Prepare a SteamCMD workshop_build_item for BreachPilot, without uploading anything.

Usage: python tools/workshop_vdf.py --version 0.6.0 --sha256 <published SHA-256> [--published-id <id>] [--visibility 2]
                                    [--change-note "..."] [--out C:/BreachPilotWorkshop]

- The content is the zip of the GitHub Release, downloaded again and checked against the published SHA-256:
  the Workshop and GitHub ship the same bytes.
- The description is the English text, then the French one, from docs/workshop/.
- SteamCMD's VDF reader does not handle escapes: a straight double quote, even written \\", ends a value and
  cut the description of Research Freedom. Any straight quote is refused, and the file is read back.
- Research Freedom's item id is refused: BreachPilot must have its own.
Writes <out>/content/<zip>, <out>/preview.png and <out>/BreachPilot.vdf, <out> being build/workshop unless
--out names another folder: a path without accents is the safest for SteamCMD. Then, by hand and with the author's go:
steamcmd +login <account> +workshop_build_item <absolute path of the vdf> +quit
"""
import argparse
import hashlib
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOD_ID = "Daneisra-BreachPilot"
APP_ID = "3606890"
REPO = "Daneisra/UploadLabs-BreachPilot"
TITLE = "BreachPilot – Hacking Automation & Advisor"
FORBIDDEN_IDS = {"3833196182"}  # Research Freedom
DESCRIPTION_LIMIT = 8000
PREVIEW_LIMIT = 1024 * 1024


def fail(message: str) -> None:
    print("FAIL " + message)
    sys.exit(1)


def checked_value(name: str, value: str) -> str:
    if '"' in value:
        fail(f"{name} holds a straight double quote, which would cut the VDF value")
    return value


def read_back(path: pathlib.Path) -> dict:
    """The same reading as SteamCMD: a value runs from a quote to the next one, with no escapes."""
    text = path.read_text(encoding="utf-8")
    return dict(re.findall(r'"([^"]+)"\s*"([^"]*)"', text))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--published-id", default="0")
    parser.add_argument("--visibility", default="2", choices=["0", "1", "2", "3"])
    parser.add_argument("--change-note", default="")
    parser.add_argument("--out", default=str(ROOT / "build" / "workshop"))
    args = parser.parse_args()
    if args.published_id in FORBIDDEN_IDS:
        fail(f"{args.published_id} is Research Freedom's item id")
    if not re.fullmatch(r"\d+", args.published_id):
        fail("the published id must be a number, 0 for a new item")

    name = f"{MOD_ID}-v{args.version}.zip"
    url = f"https://github.com/{REPO}/releases/download/v{args.version}/{name}"
    data = urllib.request.urlopen(url, timeout=60).read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != args.sha256.lower():
        fail(f"the Release zip is {digest}, not {args.sha256}")
    source_preview = ROOT / "docs" / "workshop" / "preview.png"
    if not source_preview.is_file() or source_preview.stat().st_size >= PREVIEW_LIMIT:
        fail("docs/workshop/preview.png is missing or not under 1 MB")
    english = (ROOT / "docs" / "workshop" / "description_en.txt").read_text(encoding="utf-8").strip()
    french = (ROOT / "docs" / "workshop" / "description_fr.txt").read_text(encoding="utf-8").strip()
    description = checked_value("description", english + "\n\n[hr][/hr]\n\n" + french)
    if len(description) > DESCRIPTION_LIMIT:
        fail(f"description is {len(description)} characters, Steam takes {DESCRIPTION_LIMIT}")
    change_note = checked_value("change note", args.change_note or f"v{args.version}, the zip of the GitHub Release, SHA-256 {digest}")

    # Everything is checked: only now is anything written. The content folder holds the zip alone.
    out = pathlib.Path(args.out)
    content = out / "content"
    content.mkdir(parents=True, exist_ok=True)
    for old in content.iterdir():
        old.unlink()
    (content / name).write_bytes(data)
    preview = out / "preview.png"
    preview.write_bytes(source_preview.read_bytes())

    values = {
        "appid": APP_ID,
        "publishedfileid": args.published_id,
        "contentfolder": str(content.resolve()),
        "previewfile": str(preview.resolve()),
        "visibility": args.visibility,
        "title": checked_value("title", TITLE),
        "description": description,
        "changenote": change_note,
    }
    lines = ['"workshopitem"', "{"] + [f'\t"{key}"\t"{value}"' for key, value in values.items()] + ["}"]
    vdf = out / "BreachPilot.vdf"
    vdf.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

    back = read_back(vdf)
    if back != values:
        fail("the VDF does not read back as written: " + ", ".join(k for k in values if back.get(k) != values[k]))
    print(f"OK {vdf.resolve()}")
    if not str(out.resolve()).isascii():
        print("  note: this path has accents; --out with a plain path is the safest for SteamCMD")
    print(f"  content: {name}, SHA-256 {digest}, same bytes as the GitHub Release")
    print(f"  preview: {preview.stat().st_size} bytes")
    print(f"  description: {len(description)} characters, read back whole")
    print(f"  item: {'new' if args.published_id == '0' else args.published_id}, visibility {args.visibility} (2 = private)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
