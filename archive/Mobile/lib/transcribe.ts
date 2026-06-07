/**
 * On-device transcription queue.
 *
 * Runs Parakeet TDT v3 via the native FluidAudio module. Serial (one memo at a
 * time) — Parakeet pins the Neural Engine so there's no benefit to parallelism.
 *
 * Triggered from RecordingContext when recording stops. The Review screen
 * observes memo.transcriptStatus via storage polling.
 */

import Parakeet from '../modules/parakeet';
import { getMemo, updateMemoTranscript } from './storage';

type QueueEntry = { memoId: string };

const _queue: QueueEntry[] = [];
let _running = false;
const _listeners = new Set<(memoId: string) => void>();

/** Subscribe to transcription-complete events. Returns an unsubscribe fn. */
export function onTranscriptDone(listener: (memoId: string) => void): () => void {
  _listeners.add(listener);
  return () => _listeners.delete(listener);
}

function emit(memoId: string) {
  for (const l of _listeners) {
    try {
      l(memoId);
    } catch {
      // ignore listener errors
    }
  }
}

/** Enqueue a memo for on-device transcription. No-op if already queued/running. */
export async function startTranscription(memoId: string): Promise<void> {
  if (_queue.some((q) => q.memoId === memoId)) return;
  _queue.push({ memoId });
  if (!_running) {
    void _drain();
  }
}

async function _drain() {
  _running = true;
  try {
    while (_queue.length > 0) {
      const { memoId } = _queue.shift()!;
      await _process(memoId);
    }
  } finally {
    _running = false;
  }
}

async function _process(memoId: string) {
  const memo = await getMemo(memoId);
  if (!memo || !memo.audioUri) {
    await updateMemoTranscript(memoId, { transcriptStatus: 'failed' });
    emit(memoId);
    return;
  }

  if (!Parakeet.isAvailable()) {
    // Native module not linked (e.g. running without prebuild). Fail soft —
    // Mac will transcribe on sync.
    await updateMemoTranscript(memoId, { transcriptStatus: 'failed' });
    emit(memoId);
    return;
  }

  await updateMemoTranscript(memoId, { transcriptStatus: 'transcribing' });

  try {
    const manifest = memo.metadata?.imageManifest;
    const result = await Parakeet.transcribe(memo.audioUri, manifest ?? null);
    await updateMemoTranscript(memoId, {
      transcript: result.text,
      transcriptConfidence: result.confidence,
      transcriptStatus: 'done',
      transcriptMarkersInjected: result.markersInjected,
      wordTimings: result.wordTimings,
    });
  } catch {
    await updateMemoTranscript(memoId, { transcriptStatus: 'failed' });
  } finally {
    emit(memoId);
  }
}

/**
 * Wait until a memo's transcript is no longer pending/transcribing.
 * Used by sync to block per-memo until on-device transcription finishes.
 */
export async function awaitTranscript(memoId: string, timeoutMs = 10 * 60_000): Promise<void> {
  const memo = await getMemo(memoId);
  if (!memo) return;
  const status = memo.transcriptStatus;
  if (status === 'done' || status === 'failed' || status === undefined) return;

  await new Promise<void>((resolve) => {
    const unsub = onTranscriptDone((id) => {
      if (id === memoId) {
        unsub();
        clearTimeout(timer);
        resolve();
      }
    });
    const timer = setTimeout(() => {
      unsub();
      resolve();
    }, timeoutMs);
  });
}

/** Kick off model download in the background. Safe to call repeatedly. */
export async function ensureModelDownloaded(): Promise<boolean> {
  if (!Parakeet.isAvailable()) return false;
  try {
    if (await Parakeet.isModelReady()) return true;
    await Parakeet.downloadModel();
    return true;
  } catch {
    return false;
  }
}
