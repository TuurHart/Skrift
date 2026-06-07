import { useState, useEffect, useRef, useMemo } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Pressable,
  TextInput,
  Alert,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
  Image,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { File } from 'expo-file-system';
import * as ImagePicker from 'expo-image-picker';
import { usePlayback } from '../hooks/usePlayback';
import { saveMemo, type TranscriptStatus } from '../lib/storage';
import { useRecordingContext } from '../contexts/RecordingContext';
import { captureMetadata } from '../lib/metadata';
import type { MemoMetadata } from '../lib/metadata';
import { useTheme } from '../contexts/ThemeContext';
import * as haptics from '../lib/haptics';
import Parakeet from '../modules/parakeet';
import { startTranscription } from '../lib/transcribe';
import { TranscriptView } from '../components/TranscriptView';

function formatTime(seconds: number) {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

function MetadataRow({ label, value, theme }: { label: string; value: string | null; theme: ReturnType<typeof useTheme>['theme'] }) {
  if (!value) return null;
  return (
    <View style={{
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      paddingHorizontal: 14,
      paddingVertical: 10,
      borderBottomWidth: StyleSheet.hairlineWidth,
      borderBottomColor: theme.border,
    }}>
      <Text style={{ fontSize: 14, color: theme.textSecondary }}>{label}</Text>
      <Text style={{ fontSize: 14, color: theme.textPrimary, fontWeight: '500', flexShrink: 1, textAlign: 'right', marginLeft: 12 }}>{value}</Text>
    </View>
  );
}

type CapturedPhoto = { uri: string; offsetSeconds: number };

function formatOffset(seconds: number) {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export default function ReviewScreen() {
  const { theme } = useTheme();
  const router = useRouter();
  const { uri, duration: durationParam } = useLocalSearchParams<{
    uri: string;
    duration: string;
  }>();
  const { pendingPhotosRef, resetState } = useRecordingContext();
  const recordedDuration = parseInt(durationParam || '0', 10);
  const [tagInput, setTagInput] = useState('');
  const [saving, setSaving] = useState(false);
  const [metadata, setMetadata] = useState<MemoMetadata | null>(null);
  const [capturingMeta, setCapturingMeta] = useState(true);
  const [photoUri, setPhotoUri] = useState<string | null>(null);
  const [capturedPhotos, setCapturedPhotos] = useState<CapturedPhoto[]>([]);
  const progressBarWidth = useRef(0);
  const playback = usePlayback(uri);

  const [transcriptStatus, setTranscriptStatus] = useState<TranscriptStatus>('pending');
  const [transcriptText, setTranscriptText] = useState('');
  const [transcriptConfidence, setTranscriptConfidence] = useState<number | undefined>(undefined);
  const [transcriptWordTimings, setTranscriptWordTimings] = useState<{ word: string; start: number; end: number }[] | undefined>(undefined);
  const [transcriptMarkersInjected, setTranscriptMarkersInjected] = useState(false);
  const transcriptEditedRef = useRef(false);

  // First-launch model download progress (only visible while phase != 'ready').
  const [modelProgress, setModelProgress] = useState<{ fractionCompleted: number; phase: string } | null>(null);
  useEffect(() => {
    const unsub = Parakeet.onDownloadProgress((p) => {
      if (p.phase === 'ready' || p.fractionCompleted >= 1) {
        setModelProgress(null);
      } else {
        setModelProgress({ fractionCompleted: p.fractionCompleted, phase: p.phase });
      }
    });
    return unsub;
  }, []);

  // Read timestamped photos from shared ref (set by _layout.tsx on stop) — must
  // happen BEFORE transcription so the manifest is available when we transcribe.
  useEffect(() => {
    if (pendingPhotosRef.current.length > 0) {
      setCapturedPhotos(pendingPhotosRef.current);
      pendingPhotosRef.current = [];  // consume once
    }
  }, [pendingPhotosRef]);

  // Capture photos length once at transcribe time so it doesn't re-trigger on later state.
  const photosForTranscribe = useRef<CapturedPhoto[]>([]);
  useEffect(() => { photosForTranscribe.current = capturedPhotos; }, [capturedPhotos]);

  useEffect(() => {
    if (!uri) return;
    if (!Parakeet.isAvailable()) {
      setTranscriptStatus('failed');
      return;
    }
    let cancelled = false;
    setTranscriptStatus('transcribing');
    (async () => {
      try {
        const ready = await Parakeet.isModelReady();
        if (!ready) {
          await Parakeet.downloadModel();
        }
        // Build a transcription-time manifest from captured photos. The
        // `filename` field is not used by the marker injector (it just numbers
        // by ascending offset), so a placeholder is fine here. The real
        // imageManifest with actual filenames is built later in saveMemo().
        const photosNow = photosForTranscribe.current;
        const manifest = photosNow.length > 0
          ? photosNow.map((p, i) => ({ filename: `tmp_${i}`, offsetSeconds: p.offsetSeconds }))
          : null;

        const result = await Parakeet.transcribe(uri, manifest);
        if (cancelled) return;
        setTranscriptText(result.text);
        setTranscriptConfidence(result.confidence);
        setTranscriptWordTimings(result.wordTimings);
        setTranscriptMarkersInjected(result.markersInjected);
        setTranscriptStatus('done');
      } catch {
        if (cancelled) return;
        setTranscriptStatus('failed');
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [uri]);

  const hasTimestampedPhotos = capturedPhotos.length > 0;

  const handleRemoveTimestampedPhoto = (index: number) => {
    haptics.tap();
    setCapturedPhotos(prev => prev.filter((_, i) => i !== index));
  };

  const styles = useMemo(() => StyleSheet.create({
    container: {
      flex: 1,
      backgroundColor: theme.bg,
    },
    flex: {
      flex: 1,
      paddingHorizontal: 20,
    },
    scrollContent: {
      flex: 1,
    },
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      paddingVertical: 12,
    },
    headerTitle: {
      fontSize: 17,
      fontWeight: '600',
      color: theme.textPrimary,
    },
    discardButton: {
      fontSize: 15,
      color: theme.destructive,
      fontWeight: '500',
    },
    card: {
      backgroundColor: theme.surface,
      borderRadius: 12,
      padding: 16,
      marginTop: 8,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
    },
    cardRow: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
    },
    cardDuration: {
      fontSize: 28,
      fontWeight: '300',
      color: theme.textPrimary,
      fontVariant: ['tabular-nums'],
    },
    playButton: {
      width: 44,
      height: 44,
      borderRadius: 22,
      backgroundColor: theme.accent + '20',
      alignItems: 'center',
      justifyContent: 'center',
    },
    playButtonText: {
      fontSize: 18,
    },
    cardDate: {
      fontSize: 13,
      color: theme.textSecondary,
      marginTop: 8,
    },
    progressBar: {
      height: 3,
      backgroundColor: theme.surfaceHover,
      borderRadius: 1.5,
      marginTop: 12,
      overflow: 'hidden',
    },
    progressFill: {
      height: '100%',
      backgroundColor: theme.accent,
      borderRadius: 1.5,
    },
    section: {
      marginTop: 20,
    },
    sectionTitle: {
      fontSize: 13,
      fontWeight: '600',
      color: theme.textSecondary,
      textTransform: 'uppercase',
      letterSpacing: 0.8,
      marginBottom: 8,
    },
    metaCard: {
      backgroundColor: theme.surface,
      borderRadius: 10,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
      overflow: 'hidden',
    },
    metaLoading: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
      paddingVertical: 8,
    },
    metaLoadingText: {
      fontSize: 13,
      color: theme.textMuted,
    },
    metaEmpty: {
      fontSize: 13,
      color: theme.textMuted,
      fontStyle: 'italic',
    },
    photoButtons: {
      flexDirection: 'row',
      gap: 12,
    },
    photoButton: {
      flex: 1,
      backgroundColor: theme.surface,
      borderRadius: 10,
      paddingVertical: 16,
      alignItems: 'center',
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
      gap: 4,
    },
    photoButtonIcon: {
      fontSize: 24,
    },
    photoButtonText: {
      fontSize: 13,
      color: theme.textSecondary,
    },
    photoPreview: {
      width: '100%',
      height: 180,
      borderRadius: 10,
      backgroundColor: theme.surface,
    },
    photoHint: {
      fontSize: 12,
      color: theme.textMuted,
      textAlign: 'center',
      marginTop: 6,
    },
    tagInput: {
      backgroundColor: theme.surface,
      borderRadius: 10,
      paddingHorizontal: 14,
      paddingVertical: 12,
      fontSize: 15,
      color: theme.textPrimary,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
    },
    tagHint: {
      fontSize: 12,
      color: theme.textMuted,
      marginTop: 6,
    },
    saveButton: {
      backgroundColor: theme.accent,
      borderRadius: 12,
      paddingVertical: 16,
      alignItems: 'center',
      marginBottom: 20,
    },
    saveButtonDisabled: {
      opacity: 0.5,
    },
    saveButtonText: {
      fontSize: 17,
      fontWeight: '600',
      color: '#ffffff',
    },
  }), [theme]);

  useEffect(() => {
    captureMetadata()
      .then(setMetadata)
      .catch(() => setMetadata(null))
      .finally(() => setCapturingMeta(false));
  }, []);

  const handlePickPhoto = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      quality: 0.8,
      allowsEditing: true,
    });

    if (!result.canceled && result.assets[0]) {
      setPhotoUri(result.assets[0].uri);
    }
  };

  const handleTakePhoto = async () => {
    const permission = await ImagePicker.requestCameraPermissionsAsync();
    if (!permission.granted) {
      Alert.alert('Permission needed', 'Camera access is required to take a photo.');
      return;
    }

    const result = await ImagePicker.launchCameraAsync({
      quality: 0.8,
      allowsEditing: true,
    });

    if (!result.canceled && result.assets[0]) {
      setPhotoUri(result.assets[0].uri);
    }
  };

  const handleSave = async () => {
    if (!uri || saving) return;
    setSaving(true);

    const tags = tagInput
      .split(',')
      .map((t) => t.trim().replace(/^#/, ''))
      .filter(Boolean);

    // Merge tags into metadata
    const finalMetadata = metadata
      ? { ...metadata, tags }
      : null;

    const transcriptInput =
      transcriptStatus === 'done'
        ? {
            text: transcriptText,
            confidence: transcriptConfidence,
            userEdited: transcriptEditedRef.current,
            status: 'done' as const,
            wordTimings: transcriptWordTimings,
            markersInjected: transcriptMarkersInjected,
          }
        : transcriptStatus === 'failed'
        ? { text: '', status: 'failed' as const }
        : { text: '', status: transcriptStatus };

    try {
      const saved = await saveMemo(
        uri,
        recordedDuration,
        tags,
        finalMetadata,
        photoUri,
        capturedPhotos,
        transcriptInput,
      );
      // If transcription hasn't finished yet, hand it off to the background queue
      // so it completes after the user leaves the Review screen.
      if (transcriptInput.status !== 'done' && transcriptInput.status !== 'failed') {
        void startTranscription(saved.id);
      }
      router.replace('/(tabs)');
    } catch {
      Alert.alert('Error', 'Failed to save memo');
      setSaving(false);
    }
  };

  const handleDiscard = () => {
    haptics.warning();
    Alert.alert('Discard recording?', 'This cannot be undone.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Discard',
        style: 'destructive',
        onPress: async () => {
          if (uri) {
            try {
              const f = new File(uri);
              if (f.exists) f.delete();
            } catch { /* already gone */ }
          }
          resetState();
          router.navigate('/(tabs)');
        },
      },
    ]);
  };

  const now = new Date();
  const dateStr = now.toLocaleDateString('en-GB', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        style={styles.flex}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <View style={styles.header}>
          <Pressable onPress={handleDiscard} style={({ pressed }) => [pressed && { opacity: 0.7 }]}>
            <Text style={styles.discardButton}>Discard</Text>
          </Pressable>
          <Text style={styles.headerTitle}>Review</Text>
          <View style={{ width: 60 }} />
        </View>

        <ScrollView style={styles.scrollContent} showsVerticalScrollIndicator={false}>
          <View style={styles.card}>
            <View style={styles.cardRow}>
              <Text style={styles.cardDuration}>{formatTime(recordedDuration)}</Text>
              <Pressable
                onPress={() => { haptics.tap(); playback.isPlaying ? playback.pause() : playback.play(); }}
                style={({ pressed }) => [styles.playButton, pressed && { opacity: 0.7 }]}
              >
                {playback.isPlaying ? (
                  <View style={{ flexDirection: 'row', gap: 3 }}>
                    <View style={{ width: 3, height: 14, backgroundColor: theme.accent, borderRadius: 1 }} />
                    <View style={{ width: 3, height: 14, backgroundColor: theme.accent, borderRadius: 1 }} />
                  </View>
                ) : (
                  <View style={{ width: 0, height: 0, borderLeftWidth: 10, borderLeftColor: theme.accent, borderTopWidth: 7, borderTopColor: 'transparent', borderBottomWidth: 7, borderBottomColor: 'transparent', marginLeft: 3 }} />
                )}
              </Pressable>
            </View>
            <Text style={styles.cardDate}>{dateStr}</Text>
            {playback.isPlaying && (
              <Pressable
                onLayout={(e) => { progressBarWidth.current = e.nativeEvent.layout.width; }}
                onPress={(e) => {
                  if (progressBarWidth.current > 0 && playback.duration) {
                    const pos = (e.nativeEvent.locationX / progressBarWidth.current) * playback.duration;
                    playback.seekTo(pos);
                  }
                }}
                style={styles.progressBar}
              >
                <View
                  style={[
                    styles.progressFill,
                    {
                      width: playback.duration
                        ? `${(playback.position / playback.duration) * 100}%`
                        : '0%',
                    },
                  ]}
                />
              </Pressable>
            )}
          </View>

          {/* Captured metadata */}
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Context</Text>
            {capturingMeta ? (
              <View style={styles.metaLoading}>
                <ActivityIndicator color={theme.accent} size="small" />
                <Text style={styles.metaLoadingText}>Capturing location, daylight, steps...</Text>
              </View>
            ) : metadata ? (
              <View style={styles.metaCard}>
                <MetadataRow
                  label="Location"
                  value={metadata.location?.placeName ?? null}
                  theme={theme}
                />
                <MetadataRow label="Day period" value={metadata.dayPeriod} theme={theme} />
                {metadata.daylight && (
                  <MetadataRow
                    label="Daylight"
                    value={`${metadata.daylight.sunrise} – ${metadata.daylight.sunset} (${metadata.daylight.hoursOfLight}h)`}
                    theme={theme}
                  />
                )}
                {metadata.steps !== null && (
                  <MetadataRow
                    label="Steps today"
                    value={metadata.steps.toLocaleString()}
                    theme={theme}
                  />
                )}
                {metadata.weather && (
                  <MetadataRow
                    label="Weather"
                    value={`${metadata.weather.conditions}, ${metadata.weather.temperature}°${metadata.weather.temperatureUnit}`}
                    theme={theme}
                  />
                )}
                {metadata.pressure && (
                  <MetadataRow
                    label="Pressure"
                    value={`${metadata.pressure.hPa} hPa · ${metadata.pressure.trend}`}
                    theme={theme}
                  />
                )}
              </View>
            ) : (
              <Text style={styles.metaEmpty}>No metadata captured</Text>
            )}
          </View>

          {/* Photos — filmstrip if captured during recording, single picker otherwise */}
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>
              {hasTimestampedPhotos ? `Photos (${capturedPhotos.length})` : 'Photo'}
            </Text>
            {hasTimestampedPhotos ? (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginHorizontal: -4 }}>
                {capturedPhotos.map((photo, i) => (
                  <View key={`${photo.offsetSeconds}-${i}`} style={{ marginHorizontal: 4, alignItems: 'center' }}>
                    <View style={{ position: 'relative' }}>
                      <Image source={{ uri: photo.uri }} style={{ width: 80, height: 80, borderRadius: 8, backgroundColor: theme.surface }} />
                      <Pressable
                        onPress={() => handleRemoveTimestampedPhoto(i)}
                        style={{
                          position: 'absolute', top: -6, right: -6,
                          width: 22, height: 22, borderRadius: 11,
                          backgroundColor: theme.destructive,
                          alignItems: 'center', justifyContent: 'center',
                        }}
                      >
                        <Text style={{ color: '#fff', fontSize: 12, fontWeight: '700', lineHeight: 14 }}>X</Text>
                      </Pressable>
                    </View>
                    <Text style={{ fontSize: 11, color: theme.textMuted, marginTop: 4 }}>
                      {formatOffset(photo.offsetSeconds)}
                    </Text>
                  </View>
                ))}
              </ScrollView>
            ) : photoUri ? (
              <Pressable onPress={() => setPhotoUri(null)}>
                <Image source={{ uri: photoUri }} style={styles.photoPreview} />
                <Text style={styles.photoHint}>Tap to remove</Text>
              </Pressable>
            ) : (
              <View style={styles.photoButtons}>
                <Pressable style={({ pressed }) => [styles.photoButton, pressed && { opacity: 0.7 }]} onPress={handleTakePhoto}>
                  <View style={{ width: 24, height: 20, borderRadius: 4, borderWidth: 2, borderColor: theme.textSecondary, alignItems: 'center', justifyContent: 'center' }}>
                    <View style={{ width: 8, height: 8, borderRadius: 4, borderWidth: 1.5, borderColor: theme.textSecondary }} />
                  </View>
                  <Text style={styles.photoButtonText}>Camera</Text>
                </Pressable>
                <Pressable style={({ pressed }) => [styles.photoButton, pressed && { opacity: 0.7 }]} onPress={handlePickPhoto}>
                  <View style={{ width: 24, height: 20, borderRadius: 3, borderWidth: 2, borderColor: theme.textSecondary, alignItems: 'center', justifyContent: 'center' }}>
                    <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: theme.textSecondary, marginTop: 2 }} />
                  </View>
                  <Text style={styles.photoButtonText}>Library</Text>
                </Pressable>
              </View>
            )}
          </View>

          {/* Transcript */}
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>
              Transcript
            </Text>
            {transcriptStatus === 'transcribing' || transcriptStatus === 'pending' ? (
              <View style={styles.metaLoading}>
                <ActivityIndicator color={theme.accent} size="small" />
                <Text style={styles.metaLoadingText}>
                  {modelProgress
                    ? modelProgress.phase === 'listing'
                      ? 'Preparing transcription model…'
                      : modelProgress.phase === 'compiling'
                        ? 'Compiling model…'
                        : `Downloading model… ${Math.round(modelProgress.fractionCompleted * 100)}%`
                    : 'Transcribing…'}
                </Text>
              </View>
            ) : transcriptStatus === 'failed' ? (
              <Text style={styles.metaEmpty}>Transcription failed — Mac will transcribe on sync</Text>
            ) : (
              <TranscriptView
                text={transcriptText}
                onChangeText={(t) => {
                  transcriptEditedRef.current = true;
                  setTranscriptText(t);
                }}
                imageUris={
                  capturedPhotos.length > 0
                    ? [...capturedPhotos]
                        .sort((a, b) => a.offsetSeconds - b.offsetSeconds)
                        .map((p) => p.uri)
                    : undefined
                }
                placeholder="Transcript"
              />
            )}
          </View>

          {/* Tags */}
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Tags</Text>
            <TextInput
              style={styles.tagInput}
              placeholder="e.g. inzicht, filosofatie, realisatie"
              placeholderTextColor={theme.textMuted}
              value={tagInput}
              onChangeText={setTagInput}
              autoCapitalize="none"
              autoCorrect={false}
              selectionColor={theme.accent}
              cursorColor={theme.accent}
            />
            <Text style={styles.tagHint}>Separate with commas</Text>
          </View>

          <View style={{ height: 20 }} />
        </ScrollView>

        <Pressable
          style={({ pressed }) => [styles.saveButton, saving && styles.saveButtonDisabled, pressed && { opacity: 0.7 }]}
          onPress={handleSave}
          disabled={saving}
        >
          <Text style={styles.saveButtonText}>
            {saving ? 'Saving...' : 'Save memo'}
          </Text>
        </Pressable>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
