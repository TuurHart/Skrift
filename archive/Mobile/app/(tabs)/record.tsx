import { View, Text, StyleSheet, Pressable, Animated } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useFocusEffect } from 'expo-router';
import { useRef, useEffect, useState, useCallback, useMemo } from 'react';
import { CameraView, useCameraPermissions } from 'expo-camera';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useRecordingContext } from '../../contexts/RecordingContext';
import { useTheme } from '../../contexts/ThemeContext';
import { getPrompts, DEFAULT_PROMPTS } from '../../lib/prompts';
import * as haptics from '../../lib/haptics';

const WAVEFORM_BARS = 80;
const TOOLTIP_SHOWN_KEY = 'photo_capture_tooltip_shown';

function formatTime(seconds: number) {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

function Waveform({ metering, isActive, theme }: { metering: number; isActive: boolean; theme: ReturnType<typeof useTheme>['theme'] }) {
  // Use a ref for the bars array to avoid creating a new array every 50ms tick.
  // Only use state for the render trigger (a counter).
  const barsRef = useRef<number[]>(new Array(WAVEFORM_BARS).fill(0));
  const [, setTick] = useState(0);
  const meteringRef = useRef(metering);
  meteringRef.current = metering;

  useEffect(() => {
    if (!isActive) {
      barsRef.current = new Array(WAVEFORM_BARS).fill(0);
      setTick(t => t + 1);
      return;
    }
    const interval = setInterval(() => {
      const m = meteringRef.current;
      const normalized = Math.max(0, Math.min(1, (m + 55) / 50));
      const level = Math.pow(normalized, 0.65);
      // Shift in-place instead of allocating a new array
      const b = barsRef.current;
      for (let i = 0; i < b.length - 1; i++) b[i] = b[i + 1];
      b[b.length - 1] = level;
      setTick(t => t + 1);
    }, 50);
    return () => clearInterval(interval);
  }, [isActive]);

  const bars = barsRef.current;

  const maxHeight = 48;

  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', height: maxHeight, gap: 1.5, paddingHorizontal: 24 }}>
      {bars.map((level, i) => {
        const height = Math.max(1.5, level * maxHeight);
        return (
          <View key={i} style={{ flex: 1, height, backgroundColor: theme.accent, borderRadius: 1.5, opacity: 0.85 }} />
        );
      })}
    </View>
  );
}

export default function RecordScreen() {
  const { theme } = useTheme();
  const { isRecording, isPaused, duration, metering, capturedPhotos, capturePhoto, pauseRecording, resumeRecording } = useRecordingContext();
  const dotOpacity = useRef(new Animated.Value(1)).current;
  const [prompts, setPromptsState] = useState<string[]>(DEFAULT_PROMPTS);
  const cameraRef = useRef<CameraView>(null);
  const [cameraPermission, requestCameraPermission] = useCameraPermissions();
  const [showCamera, setShowCamera] = useState(false);
  const [showTooltip, setShowTooltip] = useState(false);
  const tooltipOpacity = useRef(new Animated.Value(0)).current;
  const flashOpacity = useRef(new Animated.Value(0)).current;

  const styles = useMemo(() => StyleSheet.create({
    container: { flex: 1, backgroundColor: theme.bg },
    content: { flex: 1 },

    // Top section: waveform + timer
    topSection: {
      paddingHorizontal: 20,
      paddingTop: 8,
      paddingBottom: 12,
      alignItems: 'center',
      gap: 4,
    },
    timer: {
      fontSize: 48,
      fontWeight: '200',
      color: theme.textPrimary,
      fontVariant: ['tabular-nums'],
    },
    recordingIndicator: { flexDirection: 'row', alignItems: 'center', gap: 6 },
    redDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: theme.destructive },
    timerLabel: { fontSize: 13, color: theme.textSecondary },

    // Pause/resume button
    pauseButton: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 8,
      marginTop: 12,
      paddingVertical: 10,
      paddingHorizontal: 24,
      borderRadius: 24,
      backgroundColor: 'rgba(255,255,255,0.06)',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.1)',
      alignSelf: 'center',
    },
    pauseBars: { flexDirection: 'row', gap: 3 },
    pauseBar: { width: 3, height: 14, borderRadius: 1.5, backgroundColor: theme.textPrimary },
    resumeTriangle: {
      width: 0, height: 0,
      borderLeftWidth: 10, borderLeftColor: theme.textPrimary,
      borderTopWidth: 7, borderTopColor: 'transparent',
      borderBottomWidth: 7, borderBottomColor: 'transparent',
    },
    pauseLabel: { fontSize: 13, fontWeight: '500' as const, color: theme.textPrimary },

    // Middle section: camera OR prompts
    middleSection: { flex: 1 },

    // Camera (always mounted, visibility via height)
    cameraWrapper: {
      flex: 1,
      marginHorizontal: 16,
      marginBottom: 12,
      borderRadius: 16,
      overflow: 'hidden',
      backgroundColor: '#000',
    },
    cameraHidden: { height: 0, overflow: 'hidden', flex: 0, margin: 0 },
    camera: { flex: 1 },
    cameraOverlay: {
      ...StyleSheet.absoluteFillObject,
      justifyContent: 'flex-end',
      alignItems: 'center',
      paddingBottom: 24,
    },
    shutterButton: {
      width: 68, height: 68, borderRadius: 34,
      borderWidth: 4, borderColor: 'rgba(255, 255, 255, 0.9)',
      alignItems: 'center', justifyContent: 'center',
    },
    shutterInner: {
      width: 56, height: 56, borderRadius: 28,
      backgroundColor: 'rgba(255, 255, 255, 0.85)',
    },
    photoBadge: {
      position: 'absolute', top: 12, right: 12,
      backgroundColor: theme.accent, borderRadius: 12,
      paddingHorizontal: 10, paddingVertical: 4,
      flexDirection: 'row', alignItems: 'center', gap: 4,
    },
    photoBadgeText: { color: '#fff', fontSize: 13, fontWeight: '600' },
    tooltip: {
      position: 'absolute', bottom: 100, alignSelf: 'center',
      backgroundColor: 'rgba(0, 0, 0, 0.75)',
      paddingHorizontal: 16, paddingVertical: 8, borderRadius: 20,
    },
    tooltipText: { color: '#fff', fontSize: 13 },
    flashOverlay: { ...StyleSheet.absoluteFillObject, backgroundColor: '#fff' },

    // Prompts card (visible when not recording)
    promptsContainer: {
      marginTop: 24, marginHorizontal: 20, padding: 16,
      backgroundColor: theme.surface, borderRadius: 12,
      borderWidth: StyleSheet.hairlineWidth, borderColor: theme.border,
    },
    promptsTitle: {
      fontSize: 13, fontWeight: '600', color: theme.textSecondary,
      textTransform: 'uppercase', letterSpacing: 0.8, marginBottom: 12,
    },
    promptRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 8 },
    promptDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: theme.accent, marginRight: 12 },
    promptText: { fontSize: 15, color: theme.textPrimary },
    noCameraText: { color: theme.textMuted, fontSize: 14 },
    cameraToggle: {
      alignItems: 'center' as const,
      paddingVertical: 20,
    },
    cameraToggleText: {
      fontSize: 17,
      fontWeight: '600' as const,
      color: theme.accent,
      marginBottom: 4,
    },
    cameraToggleHint: {
      fontSize: 13,
      color: theme.textMuted,
    },
    cameraToggleDisabled: {
      opacity: 0.4,
    },
  }), [theme]);

  // Request camera permission when user opens camera (not on recording start)
  const handleOpenCamera = useCallback(async () => {
    if (!cameraPermission?.granted) {
      const result = await requestCameraPermission();
      if (!result.granted) return;
    }
    setShowCamera(true);
  }, [cameraPermission, requestCameraPermission]);

  // Hide camera when recording stops
  useEffect(() => {
    if (!isRecording) setShowCamera(false);
  }, [isRecording]);

  // Load prompts on focus
  useFocusEffect(
    useCallback(() => {
      getPrompts().then(setPromptsState);
    }, [])
  );

  // Tooltip: show once
  useEffect(() => {
    AsyncStorage.getItem(TOOLTIP_SHOWN_KEY).then(val => {
      if (!val) setShowTooltip(true);
    });
  }, []);

  useEffect(() => {
    if (isRecording && showTooltip) {
      Animated.timing(tooltipOpacity, { toValue: 1, duration: 300, useNativeDriver: true }).start();
      const timer = setTimeout(() => {
        Animated.timing(tooltipOpacity, { toValue: 0, duration: 500, useNativeDriver: true }).start();
        setShowTooltip(false);
        AsyncStorage.setItem(TOOLTIP_SHOWN_KEY, '1');
      }, 3000);
      return () => clearTimeout(timer);
    }
  }, [isRecording, showTooltip, tooltipOpacity]);

  // Blinking red dot animation
  useEffect(() => {
    if (isRecording) {
      const dot = Animated.loop(
        Animated.sequence([
          Animated.timing(dotOpacity, { toValue: 0.3, duration: 600, useNativeDriver: true }),
          Animated.timing(dotOpacity, { toValue: 1, duration: 600, useNativeDriver: true }),
        ]),
      );
      dot.start();
      return () => dot.stop();
    } else { dotOpacity.setValue(1); }
  }, [isRecording, dotOpacity]);

  const isCapturingRef = useRef(false);

  const handleShutter = useCallback(async () => {
    if (!cameraRef.current || isCapturingRef.current) return;
    isCapturingRef.current = true;
    haptics.heavy();

    Animated.sequence([
      Animated.timing(flashOpacity, { toValue: 0.6, duration: 50, useNativeDriver: true }),
      Animated.timing(flashOpacity, { toValue: 0, duration: 200, useNativeDriver: true }),
    ]).start();

    try {
      const photo = await cameraRef.current.takePictureAsync({ quality: 0.7, skipProcessing: true });
      if (photo?.uri) {
        capturePhoto(photo.uri);
      }
    } catch (err) {
      console.warn('[RecordScreen] takePicture failed:', err);
    } finally {
      isCapturingRef.current = false;
    }
  }, [capturePhoto, flashOpacity]);

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.content}>
        {/* Top: waveform + timer */}
        <View style={styles.topSection}>
          <Waveform metering={metering} isActive={isRecording} theme={theme} />
          <Text style={styles.timer}>
            {formatTime(duration)}
          </Text>
          <View style={styles.recordingIndicator}>
            {isRecording && !isPaused && <Animated.View style={[styles.redDot, { opacity: dotOpacity }]} />}
            {isRecording && isPaused && <View style={[styles.redDot, { opacity: 0.4 }]} />}
            <Text style={styles.timerLabel}>
              {isPaused ? 'Paused' : isRecording ? 'Recording' : 'Tap to record'}
            </Text>
          </View>
          {isRecording && (
            <Pressable
              onPress={() => {
                haptics.medium();
                isPaused ? resumeRecording() : pauseRecording();
              }}
              style={({ pressed }) => [styles.pauseButton, pressed && { opacity: 0.7 }]}
            >
              {isPaused ? (
                // Resume: filled triangle
                <View style={styles.resumeTriangle} />
              ) : (
                // Pause: two vertical bars
                <View style={styles.pauseBars}>
                  <View style={styles.pauseBar} />
                  <View style={styles.pauseBar} />
                </View>
              )}
              <Text style={styles.pauseLabel}>{isPaused ? 'Resume' : 'Pause'}</Text>
            </Pressable>
          )}
        </View>

        {/* Middle: camera (always mounted) + prompts (shown when not recording) */}
        <View style={styles.middleSection}>
          {/* Prompts + camera toggle — hidden only when camera is open */}
          {!showCamera && (
            <View style={styles.promptsContainer}>
              <Text style={styles.promptsTitle}>Memory aids</Text>
              {prompts.map((prompt, i) => (
                <View key={i} style={styles.promptRow}>
                  <View style={styles.promptDot} />
                  <Text style={styles.promptText}>{prompt}</Text>
                </View>
              ))}
              <Pressable
                onPress={isRecording ? handleOpenCamera : undefined}
                style={({ pressed }) => [styles.cameraToggle, !isRecording && styles.cameraToggleDisabled, pressed && isRecording && { opacity: 0.7 }]}
              >
                <Text style={[styles.cameraToggleText, !isRecording && { color: theme.textMuted }]}>Open Camera</Text>
                <Text style={styles.cameraToggleHint}>{isRecording ? 'Take photos while recording' : 'Available during recording'}</Text>
              </Pressable>
            </View>
          )}

          {/* Camera — hidden until user taps "Open Camera".
              IMPORTANT: CameraView must have ZERO React children. Fabric crashes
              when conditional children are mounted/unmounted inside a native
              CameraView because the native view's child indices diverge from
              Fabric's shadow tree. All overlays go in a sibling View. */}
          <View style={[styles.cameraWrapper, !(isRecording && showCamera) && styles.cameraHidden]}>
            {cameraPermission?.granted ? (
              <>
                <CameraView
                  ref={cameraRef}
                  style={styles.camera}
                  facing="back"
                  active={isRecording && showCamera}
                />
                {/* Overlays rendered as sibling, not child of CameraView */}
                {isRecording && (
                  <>
                    <View style={styles.cameraOverlay}>
                      <Pressable
                        onPress={handleShutter}
                        hitSlop={12}
                        style={({ pressed }) => [pressed && { opacity: 0.7 }]}
                      >
                        <View style={styles.shutterButton}>
                          <View style={styles.shutterInner} />
                        </View>
                      </Pressable>
                    </View>

                    {capturedPhotos.length > 0 && (
                      <View style={styles.photoBadge}>
                        <Text style={styles.photoBadgeText}>
                          {capturedPhotos.length} {capturedPhotos.length === 1 ? 'photo' : 'photos'}
                        </Text>
                      </View>
                    )}

                    {showTooltip && (
                      <Animated.View style={[styles.tooltip, { opacity: tooltipOpacity }]}>
                        <Text style={styles.tooltipText}>Tap to capture what you see</Text>
                      </Animated.View>
                    )}

                    <Animated.View style={[styles.flashOverlay, { opacity: flashOpacity }]} pointerEvents="none" />
                  </>
                )}
              </>
            ) : isRecording ? (
              <View style={[styles.camera, { alignItems: 'center', justifyContent: 'center' }]}>
                <Text style={styles.noCameraText}>Camera permission needed</Text>
              </View>
            ) : null}
          </View>
        </View>
      </View>
    </SafeAreaView>
  );
}
