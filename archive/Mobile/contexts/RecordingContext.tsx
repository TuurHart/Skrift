import { createContext, useContext, useRef, type ReactNode } from 'react';
import { useRecording, type CapturedPhoto } from '../hooks/useRecording';

type RecordingContextValue = {
  isRecording: boolean;
  isPaused: boolean;
  duration: number;
  metering: number;
  capturedPhotos: CapturedPhoto[];
  startRecording: () => Promise<void>;
  stopRecording: () => Promise<{ uri: string; duration: number; photos: CapturedPhoto[] } | null>;
  pauseRecording: () => void;
  resumeRecording: () => void;
  resetState: () => void;
  capturePhoto: (uri: string) => void;
  removePhoto: (index: number) => void;
  /** Shared ref to pass photos to review screen without URL serialization */
  pendingPhotosRef: React.MutableRefObject<CapturedPhoto[]>;
};

const _defaultRef = { current: [] as CapturedPhoto[] };

const RecordingContext = createContext<RecordingContextValue>({
  isRecording: false,
  isPaused: false,
  duration: 0,
  metering: -160,
  capturedPhotos: [],
  startRecording: async () => {},
  stopRecording: async () => null,
  pauseRecording: () => {},
  resumeRecording: () => {},
  resetState: () => {},
  capturePhoto: () => {},
  removePhoto: () => {},
  pendingPhotosRef: _defaultRef,
});

export function RecordingProvider({ children }: { children: ReactNode }) {
  const recording = useRecording();
  const pendingPhotosRef = useRef<CapturedPhoto[]>([]);

  const value: RecordingContextValue = {
    isRecording: recording.isRecording,
    isPaused: recording.isPaused,
    duration: recording.duration,
    metering: recording.metering,
    capturedPhotos: recording.capturedPhotos,
    startRecording: recording.startRecording,
    stopRecording: recording.stopRecording,
    pauseRecording: recording.pauseRecording,
    resumeRecording: recording.resumeRecording,
    resetState: recording.resetState,
    capturePhoto: recording.capturePhoto,
    removePhoto: recording.removePhoto,
    pendingPhotosRef,
  };

  return (
    <RecordingContext.Provider value={value}>
      {children}
    </RecordingContext.Provider>
  );
}

export function useRecordingContext() {
  return useContext(RecordingContext);
}
