import AsyncStorage from '@react-native-async-storage/async-storage';
import { File, Paths } from 'expo-file-system';
import { loadMemos, getMemo, type Memo } from './storage';
import { awaitTranscript } from './transcribe';
import { syncNames } from './names';

const STORAGE_KEY = 'mac_connection';
const LAST_SYNC_KEY = 'last_sync_time';

export type MacConnection = {
  host: string;
  port: number;
  deviceName: string;
};

export async function getMacConnection(): Promise<MacConnection | null> {
  try {
    const json = await AsyncStorage.getItem(STORAGE_KEY);
    return json ? (JSON.parse(json) as MacConnection) : null;
  } catch {
    return null;
  }
}

export async function setMacConnection(conn: MacConnection): Promise<void> {
  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(conn));
}

export async function clearMacConnection(): Promise<void> {
  await AsyncStorage.removeItem(STORAGE_KEY);
}

export async function getLastSyncTime(): Promise<string | null> {
  return AsyncStorage.getItem(LAST_SYNC_KEY);
}

async function setLastSyncTime(): Promise<void> {
  await AsyncStorage.setItem(LAST_SYNC_KEY, new Date().toISOString());
}

/**
 * Ping the Mac's health endpoint. Returns true if reachable.
 */
export async function checkMacHealth(host: string, port: number): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 3000);
    const res = await fetch(`http://${host}:${port}/api/system/health`, {
      signal: controller.signal,
    });
    clearTimeout(timeout);
    return res.ok;
  } catch {
    return false;
  }
}

/**
 * Upload a single memo to the Mac backend.
 * Returns true on success.
 */
export async function syncMemo(memo: Memo, host: string, port: number): Promise<boolean> {
  try {
    // Wait for on-device transcription to finish before uploading, so the
    // Mac can skip its own Parakeet step. If transcription failed, we proceed
    // without a transcript and the Mac handles it.
    if (memo.transcriptStatus === 'pending' || memo.transcriptStatus === 'transcribing') {
      await awaitTranscript(memo.id);
      const refreshed = await getMemo(memo.id);
      if (refreshed) memo = refreshed;
    }

    const formData = new FormData();

    // Add audio file (optional for capture items without voice annotation)
    if (memo.audioUri) {
      const audioFile = new File(memo.audioUri);
      if (audioFile.exists) {
        formData.append('files', {
          uri: memo.audioUri,
          name: memo.filename || `capture_${memo.id}.m4a`,
          type: 'audio/mp4',
        } as unknown as Blob);
      } else if (!memo.sharedContent) {
        // Only fail if this is a regular voice memo (not a capture item)
        console.warn(`[sync] Audio file not found: ${memo.audioUri}`);
        return false;
      }
    }

    // Add shared content attachment (image, file)
    if (memo.sharedContent?.filePath && (memo.sharedContent.type === 'image' || memo.sharedContent.type === 'file')) {
      const sharedFile = new File(memo.sharedContent.filePath);
      if (sharedFile.exists) {
        const ext = (memo.sharedContent.fileName || 'file').split('.').pop() || 'bin';
        formData.append('attachments', {
          uri: memo.sharedContent.filePath,
          name: memo.sharedContent.fileName || `shared_${memo.id}.${ext}`,
          type: memo.sharedContent.mimeType || 'application/octet-stream',
        } as unknown as Blob);
      }
    }

    // Add metadata as JSON string
    formData.append('metadata', JSON.stringify({
      ...(memo.metadata || {}),
      tags: memo.tags,
      source: 'mobile',
      recordedAt: memo.recordedAt,
      duration: memo.duration,
      // Shared content context for the backend pipeline
      sharedContent: memo.sharedContent || null,
      annotationText: memo.annotationText || null,
      // On-device transcription metadata (backend decides whether to trust)
      transcriptConfidence: memo.transcriptConfidence ?? null,
      transcriptUserEdited: memo.transcriptUserEdited ?? false,
      transcriptMarkersInjected: memo.transcriptMarkersInjected ?? false,
    }));

    // Pre-made transcript from on-device Parakeet. Only send if we actually
    // have one; the backend treats missing transcript as "do it yourself".
    // Name-linking is NOT done on-device — the Mac links names from the trusted
    // transcript and resolves ambiguities at its review step.
    if (memo.transcriptStatus === 'done' && memo.transcript) {
      formData.append('transcript', memo.transcript);
    }

    // Add timestamped photos from recording (multi-image manifest)
    if (memo.metadata?.imageManifest && memo.metadata.imageManifest.length > 0) {
      const recordingsDir = `${Paths.document.uri}recordings/`;
      for (const entry of memo.metadata.imageManifest) {
        const photoPath = `${recordingsDir}${entry.filename}`;
        const photoFile = new File(photoPath);
        if (photoFile.exists) {
          const ext = entry.filename.split('.').pop() || 'jpg';
          formData.append('images', {
            uri: photoPath,
            name: entry.filename,
            type: `image/${ext === 'jpg' ? 'jpeg' : ext}`,
          } as unknown as Blob);
        }
      }
    }
    // Add single cover photo if present (legacy flow)
    else if (memo.metadata?.photoFilename) {
      const recordingsDir = `${Paths.document.uri}recordings/`;
      const photoPath = `${recordingsDir}${memo.metadata.photoFilename}`;
      const ext = memo.metadata.photoFilename.split('.').pop() || 'jpg';
      formData.append('photo', {
        uri: photoPath,
        name: memo.metadata.photoFilename,
        type: `image/${ext === 'jpg' ? 'jpeg' : ext}`,
      } as unknown as Blob);
    }

    const res = await fetch(`http://${host}:${port}/api/files/upload`, {
      method: 'POST',
      body: formData,
      headers: {
        // Let RN set Content-Type with boundary automatically
      },
    });

    return res.ok;
  } catch (err) {
    console.warn('[sync] syncMemo failed:', err);
    return false;
  }
}

// Re-export from storage to use the same file reference (avoids race conditions)
async function updateMemoSyncStatusLocal(memoId: string, status: 'waiting' | 'synced'): Promise<void> {
  const { updateMemoSyncStatus } = await import('./storage');
  await updateMemoSyncStatus(memoId, status);
}

export type SyncResult = {
  synced: number;
  failed: number;
  total: number;
};

/**
 * Check the backend for files that are already uploaded but locally still
 * marked as "waiting". This handles the case where a sync succeeded but
 * the local status update was lost (e.g. app crash, IP change).
 */
async function reconcileSyncStatus(host: string, port: number): Promise<number> {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    const res = await fetch(`http://${host}:${port}/api/files/`, {
      signal: controller.signal,
      redirect: 'follow',
    });
    clearTimeout(timeout);
    if (!res.ok) return 0;
    const backendFiles: { filename: string }[] = await res.json();
    const backendNames = new Set(backendFiles.map((f) => f.filename));

    const memos = await loadMemos();
    let reconciled = 0;
    for (const memo of memos) {
      if (memo.syncStatus === 'waiting' && backendNames.has(memo.filename)) {
        await updateMemoSyncStatusLocal(memo.id, 'synced');
        reconciled++;
      }
    }
    if (reconciled > 0) {
      console.log(`[sync] Reconciled ${reconciled} memos (already on backend)`);
    }
    return reconciled;
  } catch (err) {
    console.warn('[sync] reconcileSyncStatus failed:', err);
    return 0;
  }
}

/**
 * Sync all pending memos to the Mac.
 * Returns count of synced/failed memos.
 */
export async function syncAllPending(): Promise<SyncResult> {
  const conn = await getMacConnection();
  if (!conn) return { synced: 0, failed: 0, total: 0 };

  const reachable = await checkMacHealth(conn.host, conn.port);
  if (!reachable) return { synced: 0, failed: 0, total: 0 };

  // Sync names FIRST — bidirectional last-write-wins merge. The Mac links
  // names from the trusted transcript, so getting the latest list before
  // memos upload means anything just-added on either side is in scope.
  try {
    const namesResult = await syncNames(conn.host, conn.port);
    if (namesResult.status === 'merged') {
      console.log(`[sync] names merged: local=${namesResult.localCount} remote=${namesResult.remoteCount} → ${namesResult.mergedCount}`);
    } else if (namesResult.status === 'failed') {
      console.warn('[sync] names sync failed:', namesResult.error);
    }
  } catch (err) {
    console.warn('[sync] names sync threw:', err);
  }

  // Reconcile any memos that are already on the backend but locally
  // still "waiting" (e.g. status was lost after a previous successful sync)
  const reconciled = await reconcileSyncStatus(conn.host, conn.port);

  const memos = await loadMemos();
  const pending = memos.filter((m) => m.syncStatus === 'waiting');

  if (pending.length === 0) {
    return { synced: reconciled, failed: 0, total: reconciled };
  }

  let synced = reconciled;
  let failed = 0;

  for (const memo of pending) {
    const ok = await syncMemo(memo, conn.host, conn.port);
    if (ok) {
      await updateMemoSyncStatusLocal(memo.id, 'synced');
      synced++;
    } else {
      failed++;
    }
  }

  if (synced > 0) {
    await setLastSyncTime();
  }

  return { synced, failed, total: pending.length + reconciled };
}

/**
 * Parse a skrift:// QR code URL into a MacConnection.
 * Format: skrift://{ip}:{port}/{deviceName}
 */
export function parseQRCode(data: string): MacConnection | null {
  try {
    const match = data.match(/^skrift:\/\/([^:]+):(\d+)\/(.+)$/);
    if (!match) return null;
    return {
      host: match[1],
      port: parseInt(match[2], 10),
      deviceName: decodeURIComponent(match[3]),
    };
  } catch {
    return null;
  }
}
