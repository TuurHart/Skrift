import { useCallback, useEffect, useRef } from 'react';
import {
  useAudioPlayer,
  useAudioPlayerStatus,
  setAudioModeAsync,
} from 'expo-audio';

export function usePlayback(uri?: string) {
  const source = uri ? { uri } : undefined;
  const player = useAudioPlayer(source);
  const status = useAudioPlayerStatus(player);
  const hasSetMode = useRef(false);

  useEffect(() => {
    if (uri && !hasSetMode.current) {
      hasSetMode.current = true;
      setAudioModeAsync({
        allowsRecording: false,
        playsInSilentMode: true,
      });
    }
  }, [uri]);

  const play = useCallback(async () => {
    // Ensure audio session is in playback mode — recording may have just stopped
    await setAudioModeAsync({
      allowsRecording: false,
      playsInSilentMode: true,
    });
    player.play();
  }, [player]);

  const pause = useCallback(() => {
    player.pause();
  }, [player]);

  const stop = useCallback(async () => {
    player.pause();
    await player.seekTo(0);
  }, [player]);

  const seekTo = useCallback(
    async (seconds: number) => {
      await player.seekTo(seconds);
    },
    [player],
  );

  return {
    play,
    pause,
    stop,
    seekTo,
    isPlaying: status.playing,
    position: status.currentTime,
    duration: status.duration,
    isLoaded: status.isLoaded,
  };
}
