import { requireNativeModule } from 'expo-modules-core';

export type WordTiming = {
  word: string;
  start: number;
  end: number;
};

export type TranscribeResult = {
  text: string;
  confidence: number;
  durationMs: number;
  wordTimings: WordTiming[];
  /** True when the native module injected `[[img_NNN]]` markers into `text`. */
  markersInjected: boolean;
};

/** Manifest passed to native to drive marker insertion. Mirrors the desktop schema. */
export type ImageManifestEntry = {
  filename: string;
  offsetSeconds: number;
};

/** Phase reported by FluidAudio while pulling/compiling the model. */
export type DownloadPhase = 'listing' | 'downloading' | 'compiling' | 'ready';

export type DownloadProgress = {
  fractionCompleted: number;
  phase: DownloadPhase;
  completedFiles: number;
  totalFiles: number;
};

type ParakeetNativeModule = {
  transcribe(audioUri: string, imageManifestJson: string | null): Promise<TranscribeResult>;
  isModelReady(): Promise<boolean>;
  downloadModel(): Promise<void>;
  unloadModel(): Promise<void>;
  addListener(eventName: string): void;
  removeListeners(count: number): void;
};

let _native: ParakeetNativeModule | null = null;

function getNative(): ParakeetNativeModule | null {
  if (_native) return _native;
  try {
    _native = requireNativeModule<ParakeetNativeModule>('ParakeetModule');
    return _native;
  } catch {
    return null;
  }
}

export const Parakeet = {
  /** True when the Swift binding is linked. False on simulator without FluidAudio, or before prebuild. */
  isAvailable(): boolean {
    return getNative() !== null;
  },

  async isModelReady(): Promise<boolean> {
    const n = getNative();
    if (!n) return false;
    return n.isModelReady();
  },

  async downloadModel(): Promise<void> {
    const n = getNative();
    if (!n) throw new Error('Parakeet native module not available');
    await n.downloadModel();
  },

  /** Release the in-memory ASR model (~600 MB) to relieve memory pressure. The
   *  model reloads from the on-disk cache on the next transcribe. No-op while a
   *  transcription is in flight. Safe to call anytime. */
  async unloadModel(): Promise<void> {
    const n = getNative();
    if (!n) return;
    await n.unloadModel();
  },

  /**
   * Transcribe an audio file. If `imageManifest` is non-empty, the native side
   * will inject `[[img_NNN]]` markers into the returned text at the word
   * boundary closest to each photo's offsetSeconds. Numbering ascends by offset.
   */
  async transcribe(audioUri: string, imageManifest?: ImageManifestEntry[] | null): Promise<TranscribeResult> {
    const n = getNative();
    if (!n) throw new Error('Parakeet native module not available');
    const manifestJson = imageManifest && imageManifest.length > 0 ? JSON.stringify(imageManifest) : null;
    return n.transcribe(audioUri, manifestJson);
  },

  /**
   * Subscribe to model download/compile progress. The callback fires at most a
   * few times per second while FluidAudio pulls the ~600 MB Parakeet weights
   * from HuggingFace and compiles them. Returns an unsubscribe function.
   */
  onDownloadProgress(cb: (p: DownloadProgress) => void): () => void {
    const n = getNative();
    if (!n) return () => {};
    const sub = (n as unknown as { addListener(name: string, fn: (e: DownloadProgress) => void): { remove(): void } })
      .addListener('downloadProgress', cb);
    return () => sub.remove();
  },
};

export default Parakeet;
