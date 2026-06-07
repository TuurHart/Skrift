import { useCallback, useState, useRef, useEffect } from 'react';
import {
  useAudioRecorder,
  useAudioRecorderState,
  RecordingPresets,
  requestRecordingPermissionsAsync,
  setAudioModeAsync,
} from 'expo-audio';
import { Platform } from 'react-native';

export type CapturedPhoto = {
  uri: string;
  offsetSeconds: number;
};

type RecordingResult = {
  uri: string;
  duration: number;
  photos: CapturedPhoto[];
};

// ── Live Activity helpers (fire-and-forget, never block recording) ──

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

let _liveActivityModule: typeof import('expo-live-activity') | null = null;

async function getLiveActivity() {
  if (Platform.OS !== 'ios') return null;
  if (_liveActivityModule) return _liveActivityModule;
  try {
    _liveActivityModule = await import('expo-live-activity');
    return _liveActivityModule;
  } catch {
    return null;
  }
}

async function startLiveActivity(): Promise<string | null> {
  try {
    const LA = await getLiveActivity();
    if (!LA) return null;
    const id = LA.startActivity(
      { title: 'Recording', subtitle: '0:00' },
      {
        backgroundColor: '0f1117',
        titleColor: 'E4E4E7',
        subtitleColor: '7c6bf5',
        deepLinkUrl: 'skrift://record',
      },
    );
    return id ?? null;
  } catch {
    return null;
  }
}

async function updateLiveActivity(id: string, secs: number) {
  try {
    const LA = await getLiveActivity();
    LA?.updateActivity(id, { title: 'Recording', subtitle: formatDuration(secs) });
  } catch { /* ignore */ }
}

async function stopLiveActivity(id: string, secs: number) {
  try {
    const LA = await getLiveActivity();
    LA?.stopActivity(id, { title: 'Recording saved', subtitle: formatDuration(secs) });
  } catch { /* ignore */ }
}

// ── Hook ──

export function useRecording() {
  const [duration, setDuration] = useState(0);
  const [manualIsRecording, setManualIsRecording] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const [capturedPhotos, setCapturedPhotos] = useState<CapturedPhoto[]>([]);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const startTimeRef = useRef(0);
  // Track total paused time so duration and photo offsets reflect recording time, not wall time
  const totalPausedMsRef = useRef(0);
  const pauseStartRef = useRef(0);
  const liveActivityIdRef = useRef<string | null>(null);

  const recorder = useAudioRecorder({ ...RecordingPresets.HIGH_QUALITY, isMeteringEnabled: true });
  const recorderState = useAudioRecorderState(recorder, 150);

  const metering = isPaused ? -160 : (recorderState.metering ?? -160);

  /** Compute recording-time seconds (excludes paused intervals). */
  function getRecordingSeconds(): number {
    if (!startTimeRef.current) return 0;
    const elapsed = Date.now() - startTimeRef.current;
    const paused = totalPausedMsRef.current + (pauseStartRef.current ? Date.now() - pauseStartRef.current : 0);
    return Math.floor(Math.max(0, elapsed - paused) / 1000);
  }

  useEffect(() => {
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, []);

  const startRecording = useCallback(async (): Promise<void> => {
    try {
      const permission = await requestRecordingPermissionsAsync();
      if (!permission.granted) {
        console.warn('[useRecording] Permission not granted');
        return;
      }

      await setAudioModeAsync({
        allowsRecording: true,
        playsInSilentMode: true,
      });

      await recorder.prepareToRecordAsync();
      recorder.record();

      // Clear any lingering timer from a previous session
      if (timerRef.current) clearInterval(timerRef.current);

      setDuration(0);
      setManualIsRecording(true);
      setIsPaused(false);
      startTimeRef.current = Date.now();
      totalPausedMsRef.current = 0;
      pauseStartRef.current = 0;

      timerRef.current = setInterval(() => {
        const secs = getRecordingSeconds();
        setDuration(secs);
        // Fire-and-forget Live Activity update
        if (liveActivityIdRef.current) {
          updateLiveActivity(liveActivityIdRef.current, secs);
        }
      }, 1000);

      // Fire-and-forget: start Live Activity after recording is already running
      startLiveActivity().then(id => { liveActivityIdRef.current = id; });
    } catch (err) {
      console.warn('[useRecording] startRecording failed:', err);
      setManualIsRecording(false);
    }
  }, [recorder]);

  const pauseRecording = useCallback(() => {
    if (!manualIsRecording || isPaused) return;
    try {
      recorder.pause();
      pauseStartRef.current = Date.now();
      setIsPaused(true);
    } catch (err) {
      console.warn('[useRecording] pause failed:', err);
    }
  }, [recorder, manualIsRecording, isPaused]);

  const resumeRecording = useCallback(() => {
    if (!manualIsRecording || !isPaused) return;
    try {
      // Accumulate paused duration
      if (pauseStartRef.current) {
        totalPausedMsRef.current += Date.now() - pauseStartRef.current;
        pauseStartRef.current = 0;
      }
      recorder.record();
      setIsPaused(false);
    } catch (err) {
      console.warn('[useRecording] resume failed:', err);
    }
  }, [recorder, manualIsRecording, isPaused]);

  const capturePhoto = useCallback((photoUri: string) => {
    if (!manualIsRecording || !startTimeRef.current) return;
    // Use recording time (not wall time) for photo offset
    const offsetSeconds = getRecordingSeconds();
    setCapturedPhotos(prev => [...prev, { uri: photoUri, offsetSeconds }]);
  }, [manualIsRecording]);

  const removePhoto = useCallback((index: number) => {
    setCapturedPhotos(prev => prev.filter((_, i) => i !== index));
  }, []);

  const stopRecording = useCallback(async (): Promise<RecordingResult | null> => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }

    // Finalize any active pause
    if (pauseStartRef.current) {
      totalPausedMsRef.current += Date.now() - pauseStartRef.current;
      pauseStartRef.current = 0;
    }

    setManualIsRecording(false);
    setIsPaused(false);

    // Fire-and-forget: stop Live Activity
    const laId = liveActivityIdRef.current;
    liveActivityIdRef.current = null;
    if (laId) {
      stopLiveActivity(laId, getRecordingSeconds());
    }

    try {
      await recorder.stop();
    } catch (err) {
      console.warn('[useRecording] stop failed:', err);
    }

    await setAudioModeAsync({ allowsRecording: false });

    const uri = recorder.uri;
    const finalDuration = getRecordingSeconds();

    if (!uri) return null;
    return { uri, duration: finalDuration, photos: capturedPhotos };
  }, [recorder, capturedPhotos]);

  const resetState = useCallback(() => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
    setDuration(0);
    setManualIsRecording(false);
    setIsPaused(false);
    setCapturedPhotos([]);
    totalPausedMsRef.current = 0;
    pauseStartRef.current = 0;
  }, []);

  return {
    startRecording,
    stopRecording,
    pauseRecording,
    resumeRecording,
    resetState,
    capturePhoto,
    removePhoto,
    isRecording: manualIsRecording,
    isPaused,
    duration,
    metering,
    capturedPhotos,
  };
}
