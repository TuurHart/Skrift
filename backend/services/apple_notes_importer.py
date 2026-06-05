"""
Apple Notes Markdown importer service.

Apple Notes exports notes as a folder containing:
  <Title>.md          — the note content in Markdown
  Attachments/        — any attached images or files

Attachments are renamed to "<Note Title> - <index>.<ext>" so they get clean,
collision-resistant names in the Obsidian vault.
"""

import re
import subprocess
from pathlib import Path
from urllib.parse import quote, unquote

_HEIC_EXTS = {".heic", ".heif"}


def parse_markdown_note(md_path: Path) -> dict:
    """
    Parse an Apple Notes-exported .md file.

    Renames attachments to "<Note Title> - <index>.<ext>", updates the
    markdown content to reference the new names, and re-saves the file.

    Returns:
        {
            'title': str,
            'text': str,          # markdown with updated attachment refs
            'attachments': [
                {'filename': str, 'path': str, 'mime': str}
            ]
        }
    """
    content = md_path.read_text(encoding="utf-8", errors="replace")

    # Extract title from first # heading, fall back to filename stem
    title = md_path.stem.rstrip(".")
    for line in content.splitlines():
        stripped = line.strip()
        if stripped.startswith("# "):
            title = stripped[2:].strip().rstrip(".")
            break

    # Make a filename-safe version of the title
    safe_title = re.sub(r'[\\/:*?"<>|]', "-", title).strip()
    safe_title = re.sub(r"\s+", " ", safe_title).strip("-").strip()
    if not safe_title:
        safe_title = "note"

    # Discover, rename, and update refs for each attachment
    attachments: list[dict] = []
    attachments_dir = md_path.parent / "Attachments"
    if attachments_dir.is_dir():
        files = sorted(f for f in attachments_dir.iterdir() if f.is_file() and not f.name.startswith("."))
        for index, f in enumerate(files, start=1):
            ext = f.suffix.lower()
            # HEIC/HEIF won't render in the app's Chromium webview (nor reliably
            # in Obsidian, which is also Chromium-based). Convert to JPG via macOS
            # `sips` so the image shows inline everywhere and stays portable.
            convert = ext in _HEIC_EXTS
            out_ext = ".jpg" if convert else ext
            new_name = f"{safe_title} - {index}{out_ext}"
            new_path = f.parent / new_name

            placed = False
            if convert:
                try:
                    subprocess.run(
                        ["sips", "-s", "format", "jpeg", str(f), "--out", str(new_path)],
                        check=True, capture_output=True,
                    )
                    f.unlink()  # drop the original HEIC, now replaced by the JPG
                    placed = True
                except Exception:
                    # sips unavailable/failed — keep the original file + extension
                    out_ext = ext
                    new_name = f"{safe_title} - {index}{ext}"
                    new_path = f.parent / new_name

            if not placed:
                try:
                    f.rename(new_path)
                except Exception:
                    new_path = f  # fallback: keep original
                    new_name = f.name

            # Update both URL-encoded and plain refs in the markdown (the old ref
            # still uses the original extension; the new one may be .jpg).
            for old_ref in (f"Attachments/{f.name}", f"Attachments/{quote(f.name)}"):
                content = content.replace(f"({old_ref})", f"(Attachments/{new_name})")

            attachments.append({"filename": new_name, "path": str(new_path), "mime": _guess_mime(out_ext)})

    # Re-save the .md with updated attachment references
    md_path.write_text(content, encoding="utf-8")

    return {
        "title": title,
        "text": content,
        "attachments": attachments,
    }


def _guess_mime(ext: str) -> str:
    return {
        ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
        ".png": "image/png", ".gif": "image/gif",
        ".webp": "image/webp", ".pdf": "application/pdf",
        ".mp3": "audio/mpeg", ".m4a": "audio/mp4",
        ".wav": "audio/wav",
    }.get(ext, "application/octet-stream")
