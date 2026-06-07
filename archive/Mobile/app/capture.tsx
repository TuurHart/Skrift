import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Pressable,
  TextInput,
  Alert,
  Image,
  ScrollView,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useRecording } from '../hooks/useRecording';
import { saveCaptureItem, type SharedContent } from '../lib/storage';
import { captureMetadata } from '../lib/metadata';
import { fetchUrlMetadata, extractDomain, type UrlMetadata } from '../lib/share-utils';
import { useTheme } from '../contexts/ThemeContext';
import * as haptics from '../lib/haptics';

function formatTime(seconds: number) {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export default function CaptureScreen() {
  const { theme } = useTheme();
  const router = useRouter();
  const params = useLocalSearchParams<{
    type: string;
    url?: string;
    text?: string;
    filePath?: string;
    fileName?: string;
    mimeType?: string;
  }>();

  const shareType = (params.type || 'text') as SharedContent['type'];

  // URL metadata fetching
  const [urlMeta, setUrlMeta] = useState<UrlMetadata | null>(null);
  const [fetchingUrl, setFetchingUrl] = useState(false);

  useEffect(() => {
    if (shareType === 'url' && params.url) {
      setFetchingUrl(true);
      fetchUrlMetadata(params.url)
        .then(setUrlMeta)
        .finally(() => setFetchingUrl(false));
    }
  }, [shareType, params.url]);

  // Recording state
  const recording = useRecording();
  const [recordingUri, setRecordingUri] = useState<string | null>(null);
  const [recordingDuration, setRecordingDuration] = useState(0);

  // Text annotation alternative
  const [showTextInput, setShowTextInput] = useState(false);
  const [annotationText, setAnnotationText] = useState('');
  const annotationTextRef = useRef('');

  // Keep ref in sync with state
  const updateAnnotationText = useCallback((text: string) => {
    setAnnotationText(text);
    annotationTextRef.current = text;
  }, []);

  // Saving
  const [saving, setSaving] = useState(false);

  const hasAnnotation = !!recordingUri || !!annotationText.trim();

  const handleStartRecording = useCallback(async () => {
    haptics.heavy();
    await recording.startRecording();
  }, [recording]);

  const handleStopRecording = useCallback(async () => {
    haptics.medium();
    const result = await recording.stopRecording();
    if (result) {
      setRecordingUri(result.uri);
      setRecordingDuration(result.duration);
    }
  }, [recording]);

  const handleSave = useCallback(async () => {
    if (!hasAnnotation) {
      Alert.alert(
        'No context added',
        'Voice context helps Skrift understand why you saved this. Save without annotation?',
        [
          { text: 'Add context', style: 'cancel' },
          { text: 'Save anyway', onPress: () => doSave() },
        ],
      );
      return;
    }
    doSave();
  }, [hasAnnotation]); // eslint-disable-line react-hooks/exhaustive-deps

  async function doSave() {
    setSaving(true);
    haptics.success();
    try {
      const metadata = await captureMetadata();
      const sharedContent: SharedContent = {
        type: shareType,
        url: params.url,
        urlTitle: urlMeta?.title ?? undefined,
        urlDescription: urlMeta?.description ?? undefined,
        urlThumbnailUrl: urlMeta?.thumbnailUrl ?? undefined,
        text: params.text,
        filePath: params.filePath,
        fileName: params.fileName,
        mimeType: params.mimeType,
      };

      await saveCaptureItem({
        audioUri: recordingUri || undefined,
        duration: recordingDuration,
        sharedContent,
        annotationText: annotationTextRef.current.trim() || undefined,
        metadata,
      });

      router.replace('/(tabs)');
    } catch (err) {
      console.error('Save capture failed:', err);
      Alert.alert('Error', 'Failed to save. Please try again.');
    } finally {
      setSaving(false);
    }
  }

  const styles = useMemo(() => StyleSheet.create({
    container: { flex: 1, backgroundColor: theme.bg },
    content: { flex: 1, paddingHorizontal: 20 },
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      paddingVertical: 12,
    },
    headerTitle: { fontSize: 17, fontWeight: '600', color: theme.textPrimary },
    cancelButton: { fontSize: 15, color: theme.destructive, fontWeight: '500' },
    // Preview card
    previewCard: {
      backgroundColor: theme.surface,
      borderRadius: 12,
      padding: 16,
      marginTop: 8,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
    },
    previewLabel: {
      fontSize: 11,
      fontWeight: '600',
      color: theme.textMuted,
      textTransform: 'uppercase',
      letterSpacing: 0.5,
      marginBottom: 8,
    },
    urlTitle: { fontSize: 16, fontWeight: '600', color: theme.textPrimary, marginBottom: 4 },
    urlDomain: { fontSize: 13, color: theme.accent },
    urlDescription: { fontSize: 13, color: theme.textSecondary, marginTop: 6, lineHeight: 18 },
    thumbnail: { width: '100%', height: 160, borderRadius: 8, marginTop: 10 },
    sharedText: { fontSize: 14, color: theme.textPrimary, lineHeight: 20 },
    sharedFile: { fontSize: 14, color: theme.textSecondary },
    // Annotation section
    annotationSection: { marginTop: 20 },
    sectionLabel: {
      fontSize: 11,
      fontWeight: '600',
      color: theme.textMuted,
      textTransform: 'uppercase',
      letterSpacing: 0.5,
      marginBottom: 12,
    },
    recordButton: {
      width: 72,
      height: 72,
      borderRadius: 36,
      backgroundColor: 'rgba(239, 68, 68, 0.15)',
      alignItems: 'center',
      justifyContent: 'center',
      alignSelf: 'center',
      borderWidth: 3,
      borderColor: theme.destructive,
    },
    recordButtonRecording: {
      backgroundColor: 'rgba(239, 68, 68, 0.15)',
      borderColor: theme.destructive,
    },
    recordButtonDone: {
      backgroundColor: theme.accent + '15',
      borderColor: theme.accent,
    },
    recordCircle: {
      width: 32,
      height: 32,
      borderRadius: 16,
      backgroundColor: theme.destructive,
    },
    stopSquare: {
      width: 26,
      height: 26,
      borderRadius: 4,
      backgroundColor: theme.destructive,
    },
    checkMark: {
      fontSize: 24,
      color: theme.accent,
    },
    recordingTimer: {
      fontSize: 20,
      fontWeight: '300',
      color: theme.textPrimary,
      textAlign: 'center',
      marginTop: 10,
      fontVariant: ['tabular-nums'],
    },
    recordedBadge: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      marginTop: 10,
      gap: 6,
    },
    recordedText: { fontSize: 13, color: theme.accent },
    typeInsteadButton: {
      alignSelf: 'center',
      marginTop: 14,
    },
    typeInsteadText: { fontSize: 13, color: theme.textMuted, textDecorationLine: 'underline' },
    textInputField: {
      backgroundColor: theme.surface,
      borderRadius: 10,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
      padding: 12,
      fontSize: 14,
      color: theme.textPrimary,
      minHeight: 80,
      textAlignVertical: 'top',
    },
    // Save button
    saveBar: {
      paddingHorizontal: 20,
      paddingVertical: 12,
      borderTopWidth: StyleSheet.hairlineWidth,
      borderTopColor: theme.border,
    },
    saveButton: {
      backgroundColor: theme.accent,
      borderRadius: 12,
      paddingVertical: 14,
      alignItems: 'center',
    },
    saveButtonDisabled: { opacity: 0.5 },
    saveButtonText: { fontSize: 16, fontWeight: '600', color: '#fff' },
  }), [theme]);

  return (
    <SafeAreaView style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} style={({ pressed }) => [pressed && { opacity: 0.6 }]}>
          <Text style={styles.cancelButton}>Cancel</Text>
        </Pressable>
        <Text style={styles.headerTitle}>Capture</Text>
        <View style={{ width: 50 }} />
      </View>

      <ScrollView style={styles.content} keyboardShouldPersistTaps="handled">
        {/* Content Preview */}
        <View style={styles.previewCard}>
          <Text style={styles.previewLabel}>
            {shareType === 'url' ? 'Link' : shareType === 'image' ? 'Image' : shareType === 'text' ? 'Text' : 'File'}
          </Text>

          {/* URL preview */}
          {shareType === 'url' && (
            <>
              {fetchingUrl && <ActivityIndicator size="small" color={theme.accent} />}
              {urlMeta?.title && <Text style={styles.urlTitle}>{urlMeta.title}</Text>}
              <Text style={styles.urlDomain}>{extractDomain(params.url || '')}</Text>
              {urlMeta?.description && (
                <Text style={styles.urlDescription} numberOfLines={3}>{urlMeta.description}</Text>
              )}
              {urlMeta?.thumbnailUrl && (
                <Image source={{ uri: urlMeta.thumbnailUrl }} style={styles.thumbnail} resizeMode="cover" />
              )}
              {!urlMeta?.title && !fetchingUrl && (
                <Text style={styles.sharedText} numberOfLines={2}>{params.url}</Text>
              )}
            </>
          )}

          {/* Image preview */}
          {shareType === 'image' && params.filePath && (
            <Image source={{ uri: params.filePath }} style={styles.thumbnail} resizeMode="contain" />
          )}

          {/* Text preview */}
          {shareType === 'text' && (
            <Text style={styles.sharedText} numberOfLines={10}>{params.text}</Text>
          )}

          {/* File preview */}
          {shareType === 'file' && (
            <Text style={styles.sharedFile}>{params.fileName || 'File'}</Text>
          )}
        </View>

        {/* Annotation Section */}
        <View style={styles.annotationSection}>
          <Text style={styles.sectionLabel}>Add context</Text>

          {!showTextInput ? (
            <>
              {/* Record button */}
              <Pressable
                onPress={recording.isRecording ? handleStopRecording : (recordingUri ? handleStartRecording : handleStartRecording)}
                style={[
                  styles.recordButton,
                  recording.isRecording && styles.recordButtonRecording,
                  recordingUri && !recording.isRecording && styles.recordButtonDone,
                ]}
              >
                {recording.isRecording
                  ? <View style={styles.stopSquare} />
                  : recordingUri
                  ? <Text style={styles.checkMark}>{'\u2713'}</Text>
                  : <View style={styles.recordCircle} />
                }
              </Pressable>

              {/* Recording timer / done badge */}
              {recording.isRecording && (
                <Text style={styles.recordingTimer}>{formatTime(recording.duration)}</Text>
              )}
              {recordingUri && !recording.isRecording && (
                <View style={styles.recordedBadge}>
                  <Text style={styles.recordedText}>{formatTime(recordingDuration)} recorded</Text>
                </View>
              )}

              {/* Type instead */}
              {!recording.isRecording && !recordingUri && (
                <Pressable onPress={() => setShowTextInput(true)} style={styles.typeInsteadButton}>
                  <Text style={styles.typeInsteadText}>Type instead</Text>
                </Pressable>
              )}
            </>
          ) : (
            /* Text annotation input */
            <TextInput
              style={styles.textInputField}
              placeholder="What's interesting about this?"
              placeholderTextColor={theme.textMuted}
              value={annotationText}
              onChangeText={updateAnnotationText}
              multiline
              autoFocus
            />
          )}
        </View>
      </ScrollView>

      {/* Save bar */}
      {!recording.isRecording && (
        <View style={styles.saveBar}>
          <Pressable
            onPress={handleSave}
            disabled={saving}
            style={[styles.saveButton, saving && styles.saveButtonDisabled]}
          >
            {saving ? (
              <ActivityIndicator size="small" color="#fff" />
            ) : (
              <Text style={styles.saveButtonText}>Save</Text>
            )}
          </Pressable>
        </View>
      )}
    </SafeAreaView>
  );
}
