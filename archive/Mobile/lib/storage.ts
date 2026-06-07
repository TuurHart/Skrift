import { File, Directory, Paths } from 'expo-file-system';
import { randomUUID } from 'expo-crypto';
import type { MemoMetadata } from './metadata';
import type { CapturedPhoto } from '../hooks/useRecording';

export type ShareContentType = 'url' | 'image' | 'text' | 'file';

export type SharedContent = {
  type: ShareContentType;
  url?: string;
  urlTitle?: string;
  urlDescription?: string;
  urlThumbnailUrl?: string;
  text?: string;
  filePath?: string;
  fileName?: string;
  mimeType?: string;
};

export type TranscriptStatus = 'pending' | 'transcribing' | 'done' | 'failed';

export type WordTiming = { word: string; start: number; end: number };

export type Memo = {
  id: string;
  filename: string;
  duration: number;
  recordedAt: string;
  tags: string[];
  syncStatus: 'waiting' | 'synced';
  audioUri: string;
  metadata: MemoMetadata | null;
  sharedContent?: SharedContent | null;
  annotationText?: string | null;
  transcript?: string;
  transcriptStatus?: TranscriptStatus;
  transcriptConfidence?: number;
  transcriptUserEdited?: boolean;
  /** True when the transcript already contains `[[img_NNN]]` markers (from the native module). */
  transcriptMarkersInjected?: boolean;
};

const memosFile = new File(Paths.document, 'memos.json');
const recordingsDir = new Directory(Paths.document, 'recordings');

function ensureRecordingsDir() {
  if (!recordingsDir.exists) {
    recordingsDir.create();
  }
}

// In-memory cache to avoid re-reading and re-parsing the full JSON on every call.
// Invalidated on every write. Multiple loadMemos() calls in the same sync cycle
// hit the cache instead of disk.
let _memosCache: Memo[] | null = null;

export async function loadMemos(): Promise<Memo[]> {
  // Return a shallow copy so callers can't mutate the cache in place. Combined
  // with the immutable updaters below, the cache, disk, and React state never
  // share a mutable object graph — a failed write can't leave the cache and
  // disk diverged.
  if (_memosCache) return [..._memosCache];
  try {
    if (!memosFile.exists) return [];
    const data = await memosFile.text();
    _memosCache = JSON.parse(data) as Memo[];
    return [..._memosCache];
  } catch {
    return [];
  }
}

function writeMemos(memos: Memo[]) {
  memosFile.write(JSON.stringify(memos));
  _memosCache = memos; // update cache so next loadMemos() doesn't re-read disk
}

// ── Word-timings sidecar ──────────────────────────────────────────────
// wordTimings are large per-word arrays only needed for (future) karaoke.
// Keep them in a per-memo file so memos.json stays small + cheap to parse/hold.
function wordTimingsFile(id: string): File {
  return new File(recordingsDir, `wt_${id}.json`);
}

function writeWordTimings(id: string, wt: WordTiming[]): void {
  try {
    ensureRecordingsDir();
    wordTimingsFile(id).write(JSON.stringify(wt));
  } catch {
    // non-fatal — karaoke timings are best-effort
  }
}

export async function loadWordTimings(id: string): Promise<WordTiming[] | null> {
  try {
    const f = wordTimingsFile(id);
    if (!f.exists) return null;
    return JSON.parse(await f.text()) as WordTiming[];
  } catch {
    return null;
  }
}

/** Delete all on-disk files for a memo (audio, photos, timings sidecar). */
function deleteMemoFiles(memo: Memo): void {
  try { const f = new File(memo.audioUri); if (f.exists) f.delete(); } catch { /* gone */ }
  if (memo.metadata?.photoFilename) {
    try { const p = new File(recordingsDir, memo.metadata.photoFilename); if (p.exists) p.delete(); } catch { /* gone */ }
  }
  if (memo.metadata?.imageManifest) {
    for (const e of memo.metadata.imageManifest) {
      try { const img = new File(recordingsDir, e.filename); if (img.exists) img.delete(); } catch { /* gone */ }
    }
  }
  try { const wt = wordTimingsFile(memo.id); if (wt.exists) wt.delete(); } catch { /* gone */ }
}

/**
 * Update a memo's syncStatus in the local index. Builds a new memo object
 * (never mutates the cached one) and writes a fresh array.
 */
export async function updateMemoSyncStatus(memoId: string, status: 'waiting' | 'synced'): Promise<void> {
  const memos = await loadMemos();
  const idx = memos.findIndex((m) => m.id === memoId);
  if (idx >= 0) {
    memos[idx] = { ...memos[idx], syncStatus: status };
    writeMemos(memos);
  }
}

/**
 * Patch transcript-related fields on a memo. Used by the background transcription
 * queue and the Review screen's inline editor.
 */
export async function updateMemoTranscript(
  memoId: string,
  patch: Partial<Pick<Memo, 'transcript' | 'transcriptStatus' | 'transcriptConfidence' | 'transcriptUserEdited' | 'transcriptMarkersInjected'>> & { wordTimings?: WordTiming[] },
): Promise<void> {
  const { wordTimings, ...rest } = patch;
  // wordTimings go to a per-memo sidecar, not the memo index.
  if (wordTimings) writeWordTimings(memoId, wordTimings);
  const memos = await loadMemos();
  const idx = memos.findIndex((m) => m.id === memoId);
  if (idx >= 0) {
    memos[idx] = { ...memos[idx], ...rest };
    writeMemos(memos);
  }
}

/**
 * Copy a photo to the recordings directory and return the new filename.
 * Returns null if the source doesn't exist.
 */
export function copyPhotoToRecordings(sourceUri: string, memoId: string): string | null {
  ensureRecordingsDir();
  try {
    const ext = sourceUri.split('.').pop() || 'jpg';
    const photoFilename = `photo_${memoId}.${ext}`;
    const dest = new File(recordingsDir, photoFilename);
    const source = new File(sourceUri);
    if (source.exists) {
      source.move(dest);
      return photoFilename;
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Copy multiple timestamped photos to the recordings directory.
 * Returns image manifest entries with local filenames.
 */
function copyPhotosToRecordings(
  photos: CapturedPhoto[],
  memoId: string,
): { filename: string; offsetSeconds: number }[] {
  ensureRecordingsDir();
  const manifest: { filename: string; offsetSeconds: number }[] = [];

  photos.forEach((photo, i) => {
    try {
      const ext = photo.uri.split('.').pop() || 'jpg';
      const filename = `photo_${memoId}_${String(i + 1).padStart(3, '0')}.${ext}`;
      const dest = new File(recordingsDir, filename);
      const source = new File(photo.uri);
      if (source.exists) {
        source.move(dest);
        manifest.push({ filename, offsetSeconds: photo.offsetSeconds });
      }
    } catch {
      // skip failed copies
    }
  });

  return manifest;
}

export type TranscriptInput = {
  text: string;
  confidence?: number;
  userEdited?: boolean;
  status: TranscriptStatus;
  wordTimings?: WordTiming[];
  markersInjected?: boolean;
};

export async function saveMemo(
  tempUri: string,
  duration: number,
  tags: string[],
  metadata?: MemoMetadata | null,
  photoUri?: string | null,
  photos?: CapturedPhoto[],
  transcriptInput?: TranscriptInput | null,
): Promise<Memo> {
  ensureRecordingsDir();

  const id = randomUUID();
  const filename = `memo_${id}.m4a`;
  const destFile = new File(recordingsDir, filename);

  const sourceFile = new File(tempUri);
  sourceFile.move(destFile);

  let finalMetadata = metadata ?? null;

  // Save photos even if metadata capture failed (metadata === null) — otherwise
  // the captured photos and their temp files are silently dropped.
  if (photos && photos.length > 0) {
    const imageManifest = copyPhotosToRecordings(photos, id);
    finalMetadata = { ...(finalMetadata ?? ({} as MemoMetadata)), imageManifest };
  }
  // Handle single cover photo from review screen (legacy flow)
  else if (photoUri) {
    const photoFilename = copyPhotoToRecordings(photoUri, id);
    finalMetadata = { ...(finalMetadata ?? ({} as MemoMetadata)), photoFilename };
  }

  const memo: Memo = {
    id,
    filename,
    duration,
    recordedAt: new Date().toISOString(),
    tags,
    syncStatus: 'waiting',
    audioUri: destFile.uri,
    metadata: finalMetadata,
    transcriptStatus: transcriptInput?.status ?? 'pending',
    transcript: transcriptInput?.text,
    transcriptConfidence: transcriptInput?.confidence,
    transcriptUserEdited: transcriptInput?.userEdited,
    transcriptMarkersInjected: transcriptInput?.markersInjected,
  };

  if (transcriptInput?.wordTimings?.length) {
    writeWordTimings(id, transcriptInput.wordTimings);
  }

  const memos = await loadMemos();
  memos.unshift(memo);
  writeMemos(memos);

  return memo;
}

export async function getMemo(id: string): Promise<Memo | null> {
  const memos = await loadMemos();
  return memos.find((m) => m.id === id) ?? null;
}

/**
 * Save a captured item (URL, image, text) with optional voice/text annotation.
 */
export async function saveCaptureItem(opts: {
  audioUri?: string;
  duration?: number;
  sharedContent: SharedContent;
  annotationText?: string;
  metadata?: MemoMetadata | null;
}): Promise<Memo> {
  ensureRecordingsDir();

  const id = randomUUID();
  let filename = '';
  let audioUri = '';

  // Copy audio annotation if provided
  if (opts.audioUri) {
    filename = `capture_${id}.m4a`;
    const destFile = new File(recordingsDir, filename);
    const sourceFile = new File(opts.audioUri);
    sourceFile.move(destFile);
    audioUri = destFile.uri;
  }

  // Copy shared image file if it's a local file
  let sharedContent = { ...opts.sharedContent };
  if (sharedContent.filePath && (sharedContent.type === 'image' || sharedContent.type === 'file')) {
    try {
      const ext = sharedContent.filePath.split('.').pop() || 'jpg';
      const sharedFilename = `shared_${id}.${ext}`;
      const dest = new File(recordingsDir, sharedFilename);
      const source = new File(sharedContent.filePath);
      if (source.exists) {
        source.move(dest);
        sharedContent = { ...sharedContent, filePath: dest.uri, fileName: sharedFilename };
      }
    } catch {
      // keep original path if copy fails
    }
  }

  const memo: Memo = {
    id,
    filename,
    duration: opts.duration || 0,
    recordedAt: new Date().toISOString(),
    tags: [],
    syncStatus: 'waiting',
    audioUri,
    metadata: opts.metadata ?? null,
    sharedContent,
    annotationText: opts.annotationText || null,
  };

  const memos = await loadMemos();
  memos.unshift(memo);
  writeMemos(memos);

  return memo;
}

export async function deleteMemo(id: string): Promise<void> {
  const memos = await loadMemos();
  const memo = memos.find((m) => m.id === id);

  if (memo) {
    deleteMemoFiles(memo);
  }

  const updated = memos.filter((m) => m.id !== id);
  writeMemos(updated);
}

/** Delete several memos in one pass + a single index rewrite (avoids the
 *  O(n^2) loop of calling deleteMemo per id, e.g. "Clear synced"). */
export async function deleteMemos(ids: string[]): Promise<void> {
  if (ids.length === 0) return;
  const idSet = new Set(ids);
  const memos = await loadMemos();
  for (const memo of memos) {
    if (idSet.has(memo.id)) deleteMemoFiles(memo);
  }
  writeMemos(memos.filter((m) => !idSet.has(m.id)));
}
