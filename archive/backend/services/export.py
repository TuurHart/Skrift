"""
Export service
Handles markdown compilation and export operations
"""

import logging
import re
import shutil
from pathlib import Path
from models import ProcessingStatus
from utils.status_tracker import status_tracker
from config.settings import settings

logger = logging.getLogger(__name__)


def _resolve_attachment_markers(markdown: str, file_folder: Path, vault_folder: Path | None) -> str:
    """Rewrite Apple Notes image refs to Obsidian embed syntax and copy files to vault.

    Converts:  ![...](Attachments/photo.jpg)  →  ![[photo.jpg]]
    Attachments are copied to export.attachments_folder if configured, otherwise
    they fall back to vault_folder (same folder as the note).
    """
    from urllib.parse import unquote
    attachments_dir = file_folder / "Attachments"

    # Resolve where to put attachments in the vault
    attachments_dest: Path | None = None
    if vault_folder is not None:
        att_cfg = (settings.get('export.attachments_folder') or '').strip()
        if att_cfg:
            attachments_dest = Path(att_cfg).expanduser()
            attachments_dest.mkdir(parents=True, exist_ok=True)
        else:
            attachments_dest = vault_folder

    def replace_ref(m: re.Match) -> str:
        raw_path = m.group(1)
        filename = Path(unquote(raw_path)).name
        src = attachments_dir / filename
        if attachments_dest is not None and src.exists():
            try:
                shutil.copyfile(src, attachments_dest / filename)
            except Exception as e:
                print(f"Warning: Could not copy attachment {filename} to vault: {e}")
        return f"![[{filename}]]"

    # Match ![any alt text](Attachments/...) — case-insensitive folder name
    return re.sub(r"!\[[^\]]*\]\(Attachments/([^)]+)\)", replace_ref, markdown, flags=re.IGNORECASE)


def get_compiled_markdown(file_id: str) -> dict:
    """
    Get current compiled markdown content for a file.
    Resolution order for the active markdown file in the file's output folder:
    1) compiled.md if present
    2) If exactly one *.md exists, use that
    3) Otherwise, use the most recently modified *.md
    
    Returns:
        dict with:
        - status: 'done' or 'error'
        - path: path to markdown file (if done)
        - title: extracted YAML title (if done)
        - content: markdown content (if done)
        - error: error message (if error)
    """
    try:
        pf = status_tracker.get_file(file_id)
        if not pf:
            return {
                'status': 'error',
                'error': 'File not found'
            }
        
        folder = Path(pf.path).parent
        md_path = folder / 'compiled.md'
        
        if not md_path.exists():
            md_files = list(folder.glob('*.md'))
            # Exclude hidden files
            md_files = [p for p in md_files if not p.name.startswith('.')]
            if not md_files:
                return {
                    'status': 'error',
                    'error': 'No markdown file present for this item'
                }
            if len(md_files) == 1:
                md_path = md_files[0]
            else:
                md_path = max(md_files, key=lambda p: p.stat().st_mtime)
        
        try:
            content = md_path.read_text(encoding='utf-8')
        except Exception as e:
            return {
                'status': 'error',
                'error': f'Failed to read compiled markdown: {e}'
            }
        
        # Extract title from YAML frontmatter
        title = None
        m = re.search(r"^---\n([\s\S]*?)\n---", content, flags=re.MULTILINE)
        if m:
            block = m.group(1)
            mtitle = re.search(r"^title:\s*(.+)$", block, flags=re.MULTILINE)
            if mtitle:
                title = mtitle.group(1).strip()
        
        return {
            'status': 'done',
            'path': str(md_path),
            'title': title,
            'content': content
        }
    
    except Exception as e:
        return {
            'status': 'error',
            'error': str(e)
        }



def _inject_photo_embed(markdown: str, photo_filename: str) -> str:
    """Insert an Obsidian photo embed after the audio embed (or after YAML frontmatter).

    Ensures we do not duplicate the same embed.
    """
    embed_line = f"![[{photo_filename}]]"
    head = markdown[:800]
    if embed_line in head:
        return markdown
    # If any photo embed already exists near the top, skip
    if re.search(r"^!\[\[[^\n\]]+\.(jpg|jpeg|png|heic)\]\]$", head, flags=re.MULTILINE | re.IGNORECASE):
        return markdown

    # Try to insert after an audio embed line
    audio_match = re.search(r"^(!\[\[[^\n\]]+\.(m4a|mp3|wav)\]\])$", markdown, flags=re.MULTILINE)
    if audio_match:
        insert_pos = audio_match.end()
        return markdown[:insert_pos] + f"\n{embed_line}" + markdown[insert_pos:]

    # Fallback: insert after YAML frontmatter
    m = re.search(r"^---\n([\s\S]*?)\n---", markdown, flags=re.MULTILINE)
    if m:
        end = m.end()
        after = markdown[end:]
        after_body = after.lstrip("\n")
        return f"{markdown[:end]}\n\n\n{embed_line}\n\n{after_body}"

    # No YAML either; prepend
    return f"{embed_line}\n\n{markdown}"


def _inject_audio_embed(markdown: str, audio_filename: str) -> str:
    """Insert an Obsidian audio embed immediately after YAML frontmatter.

    Ensures we do not duplicate the same embed at the top of the document.
    Layout:

    ---
    yaml...
    ---


    ![[file.m4a]]

    <rest of content>
    """
    embed_line = f"![[{audio_filename}]]"
    head = markdown[:500]
    # If the exact embed is already near the top, assume it's in place
    if embed_line in head:
        return markdown
    # If *any* audio embed is already near the top, don't add another
    if re.search(r"^!\[\[[^\n\]]+\.(m4a|mp3|wav)\]\]$", head, flags=re.MULTILINE):
        return markdown

    m = re.search(r"^---\n([\s\S]*?)\n---", markdown, flags=re.MULTILINE)
    if not m:
        # No YAML block; prepend embed at very top with two blank lines before first text
        body = markdown.lstrip("\n")
        return f"{embed_line}\n\n\n{body}"

    start, end = m.span()
    before = markdown[:end]  # includes closing ---
    after = markdown[end:]
    after_body = after.lstrip("\n")
    # Ensure exactly two blank lines between YAML and the embed, and two between embed and body
    return f"{before}\n\n\n{embed_line}\n\n{after_body}"


def _normalize_frontmatter_spacing(markdown: str) -> str:
    """Ensure there are always two blank lines between YAML frontmatter and first body text."""
    m = re.search(r"^---\n([\s\S]*?)\n---", markdown, flags=re.MULTILINE)
    if not m:
        return markdown
    start, end = m.span()
    before = markdown[:end]
    after = markdown[end:]
    after_body = after.lstrip("\n")
    return f"{before}\n\n\n{after_body}"


def save_compiled_markdown(file_id: str, content: str, export_to_vault: bool = False, vault_path: str | None = None, include_audio: bool = False) -> dict:
    """Save compiled markdown edits and optionally export (rename) based on YAML title.

    Logic:
    - Determine the active markdown filename using the same resolver as GET.
    - A plain Save writes to the active file (overwriting it). It will not create a second .md.
    - Save & Export renames the active file to <YAML title>.md, then deletes any other .md siblings.
    - If a vault_path or configured export.note_folder is valid, copy the renamed file there.
    - If include_audio is True, also copy the original audio into export.audio_folder and
      inject an Obsidian embed for it at the top of the markdown body.

    Args:
        file_id: file identifier
        content: markdown content to save
        export_to_vault: whether to export/rename based on YAML title
        vault_path: optional override for note export path (legacy behaviour)
        include_audio: whether to export audio + embed link

    Returns:
        dict with:
        - status: 'done' or 'error'
        - success: True (if done)
        - path: path to saved file (if done, plain save)
        - exported_path: path to renamed file (if done, export)
        - vault_exported_path: path in vault (if done, vault export)
        - audio_exported_path: path to exported audio (if include_audio)
        - audio_filename: basename used for Obsidian embed
        - error: error message (if error)
    """
    try:
        pf = status_tracker.get_file(file_id)
        if not pf:
            return {
                'status': 'error',
                'error': 'File not found'
            }

        if not content:
            return {
                'status': 'error',
                'error': 'Missing markdown content'
            }

        folder = Path(pf.path).parent
        folder.mkdir(parents=True, exist_ok=True)

        # Resolve current active markdown path
        active = folder / 'compiled.md'
        if not active.exists():
            md_files = [p for p in folder.glob('*.md') if not p.name.startswith('.')]
            if md_files:
                if len(md_files) == 1:
                    active = md_files[0]
                else:
                    active = max(md_files, key=lambda p: p.stat().st_mtime)

        # If we are exporting, extract YAML title first so we can derive filenames
        title = None
        safe_title = None
        if export_to_vault:
            m = re.search(r"^---\n([\s\S]*?)\n---", content, flags=re.MULTILINE)
            if m:
                block = m.group(1)
                mtitle = re.search(r"^title:\s*(.+)$", block, flags=re.MULTILINE)
                if mtitle:
                    title = mtitle.group(1).strip()
            if not title:
                return {
                    'status': 'error',
                    'error': 'YAML frontmatter must include a title before export'
                }
            safe = title.strip()
            # Remove surrounding quotes if present
            safe = re.sub(r'^["\']+|["\']+$', '', safe).strip()
            # Replace forbidden filename characters with dashes
            safe = re.sub(r"[\\/:*?\"<>|]", "-", safe)
            # Normalise whitespace
            safe = re.sub(r"\s+", " ", safe).strip()
            # Trim leading/trailing dashes that may come from stripped quotes
            safe = re.sub(r"^-+|-+$", "", safe).strip()
            if not safe:
                safe = "Untitled"
            safe_title = safe

        # Inject audio + photo embeds into content if requested and we know the title
        audio_filename = None
        audio_exported_path = None
        photo_filename = None
        photo_exported_path = None
        content_to_write = content

        # Check for phone photo in the file folder
        phone_photo_path = None
        if pf.audioMetadata and hasattr(pf.audioMetadata, '__contains__'):
            pp = pf.audioMetadata.get('phone_photo') if isinstance(pf.audioMetadata, dict) else None
            if pp:
                phone_photo_path = Path(pp)
        if phone_photo_path is None:
            # Also check for photo.jpg/png directly in folder
            for ext_check in ('.jpg', '.jpeg', '.png', '.heic'):
                candidate = folder / f"photo{ext_check}"
                if candidate.exists():
                    phone_photo_path = candidate
                    break

        if export_to_vault and include_audio and safe_title:
            # Determine original audio path and extension
            original_audio = Path(pf.path)
            if not original_audio.exists():
                return {
                    'status': 'error',
                    'error': f'Original audio file not found: {original_audio}'
                }
            ext = original_audio.suffix or ''
            audio_filename = f"{safe_title}{ext}"
            content_to_write = _inject_audio_embed(content_to_write, audio_filename)

            # Inject photo embed if a phone photo exists
            if phone_photo_path and phone_photo_path.exists():
                photo_ext = phone_photo_path.suffix or '.jpg'
                photo_filename = f"{safe_title}_photo{photo_ext}"
                content_to_write = _inject_photo_embed(content_to_write, photo_filename)

        elif export_to_vault and not include_audio:
            # Even without audio, normalise spacing between YAML and first body text
            content_to_write = _normalize_frontmatter_spacing(content_to_write)
            # Still embed photo if present
            if safe_title and phone_photo_path and phone_photo_path.exists():
                photo_ext = phone_photo_path.suffix or '.jpg'
                photo_filename = f"{safe_title}_photo{photo_ext}"
                content_to_write = _inject_photo_embed(content_to_write, photo_filename)

        # Write content (possibly with embed) to the active file
        try:
            active.write_text(content_to_write, encoding='utf-8')
        except Exception as e:
            return {
                'status': 'error',
                'error': f'Failed to write markdown: {e}'
            }

        # Handle export/rename
        if export_to_vault:
            assert safe_title is not None
            new_path = folder / f"{safe_title}.md"

            try:
                if new_path.exists():
                    new_path.unlink()

                # If active is different, rename it
                if str(active) != str(new_path):
                    active.rename(new_path)
                    active = new_path

                # Clean up any other .md files in the folder to avoid duplicates
                for other in folder.glob('*.md'):
                    if other.resolve() != active.resolve():
                        try:
                            other.unlink()
                        except Exception:
                            pass

                # Update export status result path
                status_tracker.update_file_status(
                    file_id,
                    'export',
                    ProcessingStatus.DONE,
                    result_content=str(active)
                )

                # Persist include_audio preference on the PipelineFile
                try:
                    pf.include_audio_in_export = bool(include_audio)
                    status_tracker.save_file_status(file_id)
                except Exception:
                    # Non-fatal if this field is missing on older status files
                    pass

                # Resolve note export folder: prefer explicit vault_path, else export.note_folder
                configured_note_folder = settings.get('export.note_folder', '') or None
                note_folder_str = vault_path or configured_note_folder
                vault_exported = None
                resolved_vault_folder: Path | None = None
                if note_folder_str:
                    vp = Path(note_folder_str)
                    if not vp.exists() or not vp.is_dir():
                        return {
                            'status': 'error',
                            'error': f'Export note path is not a folder: {note_folder_str}'
                        }
                    vault_exported = str(vp / active.name)
                    resolved_vault_folder = vp

                # Replace [ATTACHMENT:filename] markers with Obsidian embed syntax
                # and copy attachment files to the vault folder
                content_to_write = _resolve_attachment_markers(content_to_write, folder, resolved_vault_folder)

                # If requested, export audio to configured audio folder
                if include_audio and audio_filename is not None:
                    audio_folder_str = settings.get('export.audio_folder', '') or None
                    if not audio_folder_str:
                        return {
                            'status': 'error',
                            'error': 'Audio export folder is not configured'
                        }
                    audio_folder = Path(audio_folder_str)
                    if not audio_folder.exists() or not audio_folder.is_dir():
                        return {
                            'status': 'error',
                            'error': f'Audio export folder is not a directory: {audio_folder_str}'
                        }
                    original_audio = Path(pf.path)
                    if not original_audio.exists():
                        return {
                            'status': 'error',
                            'error': f'Original audio file not found: {original_audio}'
                        }
                    target_audio = audio_folder / audio_filename
                    try:
                        shutil.copyfile(original_audio, target_audio)
                        audio_exported_path = str(target_audio)
                    except Exception as e:
                        return {
                            'status': 'error',
                            'error': f'Failed to export audio file: {e}'
                        }

                # If timestamped photos exist, convert markers and copy images
                image_manifest_path = folder / "image_manifest.json"
                if image_manifest_path.exists() and safe_title:
                    try:
                        import json as _json_img
                        manifest = _json_img.loads(image_manifest_path.read_text(encoding='utf-8'))
                        att_cfg = (settings.get('export.attachments_folder') or '').strip()

                        # Slugify title for image filenames
                        slug = safe_title.lower()
                        slug = re.sub(r'[^\w\s-]', '', slug)
                        slug = re.sub(r'[\s]+', '-', slug).strip('-')

                        # Resolve attachments folder (fall back to vault folder)
                        att_folder = None
                        if att_cfg:
                            att_folder = Path(att_cfg).expanduser()
                        elif resolved_vault_folder:
                            att_folder = resolved_vault_folder

                        for i, entry in enumerate(manifest):
                            img_num = i + 1
                            src_filename = entry.get("filename", "")
                            src_path = folder / "images" / src_filename
                            ext = Path(src_filename).suffix or '.jpg'
                            export_filename = f"{slug}_{img_num:03d}{ext}"

                            # Replace marker in content
                            content_to_write = content_to_write.replace(
                                f"[[img_{img_num:03d}]]",
                                f"![[{export_filename}]]"
                            )

                            # Copy image to attachments folder (skip if no folder configured)
                            if att_folder and src_path.exists():
                                try:
                                    att_folder.mkdir(parents=True, exist_ok=True)
                                    shutil.copyfile(src_path, att_folder / export_filename)
                                except Exception as e:
                                    logger.warning(f"Failed to export image {src_filename}: {e}")

                        if not att_folder:
                            logger.warning("No attachments folder configured — image markers converted but files not copied")

                    except Exception as e:
                        logger.warning(f"Failed to process timestamped photos: {e}")

                # If photo exists, copy to attachments folder with note-title name
                if phone_photo_path and phone_photo_path.exists() and photo_filename:
                    att_cfg = (settings.get('export.attachments_folder') or '').strip()
                    if att_cfg:
                        att_folder = Path(att_cfg).expanduser()
                        att_folder.mkdir(parents=True, exist_ok=True)
                    elif resolved_vault_folder:
                        att_folder = resolved_vault_folder
                    else:
                        att_folder = None
                    if att_folder:
                        target_photo = att_folder / photo_filename
                        try:
                            shutil.copyfile(phone_photo_path, target_photo)
                            photo_exported_path = str(target_photo)
                        except Exception as e:
                            print(f"Warning: Failed to export photo: {e}")

                # Write final content (with all markers resolved) to local file + vault
                try:
                    active.write_text(content_to_write, encoding='utf-8')
                    if vault_exported and resolved_vault_folder:
                        shutil.copyfile(active, resolved_vault_folder / active.name)
                except Exception as e:
                    logger.warning(f"Failed to write final export: {e}")

                result: dict = {
                    'status': 'done',
                    'success': True,
                    'exported_path': str(active),
                    'vault_exported_path': vault_exported,
                }
                if audio_exported_path and audio_filename:
                    result['audio_exported_path'] = audio_exported_path
                    result['audio_filename'] = audio_filename
                if photo_exported_path and photo_filename:
                    result['photo_exported_path'] = photo_exported_path
                    result['photo_filename'] = photo_filename
                return result

            except Exception as e:
                return {
                    'status': 'error',
                    'error': f'Failed to export/rename: {e}'
                }

        # Plain save path (no export)
        return {
            'status': 'done',
            'success': True,
            'path': str(active)
        }

    except Exception as e:
        return {
            'status': 'error',
            'error': str(e)
        }
