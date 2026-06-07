import { useState, useCallback, useRef, useMemo } from 'react';
import { View, Text, StyleSheet, Pressable, Alert, Image, ScrollView, Linking, Modal } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams, useFocusEffect } from 'expo-router';
import { Paths } from 'expo-file-system';
import { getMemo, deleteMemo, type Memo } from '../../lib/storage';
import { usePlayback } from '../../hooks/usePlayback';
import { useTheme } from '../../contexts/ThemeContext';
import * as haptics from '../../lib/haptics';

function formatDuration(seconds: number) {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('en-GB', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export default function MemoDetailScreen() {
  const { theme } = useTheme();
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id: string }>();
  const [memo, setMemo] = useState<Memo | null>(null);
  const [selectedPhoto, setSelectedPhoto] = useState<string | null>(null);
  const progressBarWidth = useRef(0);

  const styles = useMemo(() => StyleSheet.create({
    container: {
      flex: 1,
      backgroundColor: theme.bg,
    },
    loading: {
      color: theme.textSecondary,
      textAlign: 'center',
      marginTop: 40,
    },
    header: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      paddingHorizontal: 20,
      paddingVertical: 12,
    },
    backButton: {
      fontSize: 15,
      color: theme.accent,
      fontWeight: '500',
    },
    deleteButton: {
      fontSize: 15,
      color: theme.destructive,
      fontWeight: '500',
    },
    content: {
      paddingHorizontal: 20,
    },
    title: {
      fontSize: 24,
      fontWeight: '700',
      color: theme.textPrimary,
      marginTop: 8,
    },
    date: {
      fontSize: 14,
      color: theme.textSecondary,
      marginTop: 6,
      lineHeight: 20,
    },
    playerCard: {
      flexDirection: 'row',
      alignItems: 'center',
      backgroundColor: theme.surface,
      borderRadius: 12,
      padding: 16,
      marginTop: 24,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
      gap: 14,
    },
    playButton: {
      width: 48,
      height: 48,
      borderRadius: 24,
      backgroundColor: theme.accent + '20',
      alignItems: 'center',
      justifyContent: 'center',
    },
    playButtonText: {
      fontSize: 20,
    },
    playerInfo: {
      flex: 1,
    },
    progressBar: {
      height: 4,
      backgroundColor: theme.surfaceHover,
      borderRadius: 2,
      overflow: 'hidden',
    },
    progressFill: {
      height: '100%',
      backgroundColor: theme.accent,
      borderRadius: 2,
    },
    timeRow: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      marginTop: 6,
    },
    timeText: {
      fontSize: 11,
      color: theme.textMuted,
      fontVariant: ['tabular-nums'],
    },
    section: {
      marginTop: 28,
    },
    sectionTitle: {
      fontSize: 13,
      fontWeight: '600',
      color: theme.textSecondary,
      textTransform: 'uppercase',
      letterSpacing: 0.8,
      marginBottom: 10,
    },
    tagsRow: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: 8,
    },
    tag: {
      backgroundColor: theme.accent + '18',
      paddingHorizontal: 10,
      paddingVertical: 5,
      borderRadius: 8,
    },
    tagText: {
      fontSize: 14,
      color: theme.accent,
      fontWeight: '500',
    },
    syncRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
    },
    syncDot: {
      width: 8,
      height: 8,
      borderRadius: 4,
    },
    syncDotWaiting: {
      backgroundColor: theme.stepEnhance,
    },
    syncDotSynced: {
      backgroundColor: theme.checkGreen,
    },
    syncText: {
      fontSize: 14,
      color: theme.textSecondary,
    },
    photo: {
      width: '100%',
      height: 240,
      borderRadius: 12,
      marginTop: 24,
    },
    metaCard: {
      backgroundColor: theme.surface,
      borderRadius: 10,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
      overflow: 'hidden',
    },
    metaRow: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      paddingHorizontal: 14,
      paddingVertical: 10,
      borderBottomWidth: StyleSheet.hairlineWidth,
      borderBottomColor: theme.border,
    },
    metaLabel: {
      fontSize: 14,
      color: theme.textSecondary,
    },
    metaValue: {
      fontSize: 14,
      color: theme.textPrimary,
      fontWeight: '500',
      flexShrink: 1,
      textAlign: 'right',
      marginLeft: 12,
    },
  }), [theme]);

  useFocusEffect(
    useCallback(() => {
      if (id) {
        getMemo(id).then(setMemo);
      }
    }, [id]),
  );

  const playback = usePlayback(memo?.audioUri);

  const handleDelete = () => {
    if (!memo) return;
    Alert.alert('Delete memo?', 'This cannot be undone.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          haptics.error();
          await playback.stop();
          await deleteMemo(memo.id);
          router.back();
        },
      },
    ]);
  };

  if (!memo) {
    return (
      <SafeAreaView style={styles.container}>
        <Text style={styles.loading}>Loading...</Text>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} style={({ pressed }) => [pressed && { opacity: 0.6 }]}>
          <Text style={styles.backButton}>{'\u2190'} Back</Text>
        </Pressable>
        <Pressable onPress={handleDelete} style={({ pressed }) => [pressed && { opacity: 0.6 }]}>
          <Text style={styles.deleteButton}>Delete</Text>
        </Pressable>
      </View>

      <ScrollView style={styles.content} contentContainerStyle={{ paddingBottom: 40 }}>
        <Text style={styles.title}>
          {memo.sharedContent
            ? memo.sharedContent.type === 'url'
              ? (memo.sharedContent.urlTitle || 'Link')
              : memo.sharedContent.type === 'image'
              ? (memo.annotationText?.slice(0, 50) || `Image · ${new Date(memo.recordedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false })}`)
              : memo.sharedContent.type === 'text'
              ? ((memo.sharedContent.text || '').slice(0, 50).replace(/\n/g, ' ') || 'Text')
              : memo.sharedContent.type === 'file'
              ? (memo.sharedContent.fileName?.replace(/\.[^.]+$/, '') || 'File')
              : 'Capture'
            : `Voice memo · ${formatDuration(memo.duration)}`}
        </Text>
        <Text style={styles.date}>{formatDate(memo.recordedAt)}</Text>

        {/* Shared content preview */}
        {memo.sharedContent?.type === 'url' && memo.sharedContent.url && (
          <Pressable
            onPress={() => Linking.openURL(memo.sharedContent!.url!)}
            style={({ pressed }) => [
              { backgroundColor: theme.surface, borderRadius: 10, padding: 14, marginTop: 12, borderWidth: StyleSheet.hairlineWidth, borderColor: theme.border },
              pressed && { opacity: 0.7 },
            ]}
          >
            <Text style={{ fontSize: 13, color: theme.accent, marginBottom: 4 }}>{memo.sharedContent.url}</Text>
            {memo.sharedContent.urlDescription && (
              <Text style={{ fontSize: 12, color: theme.textSecondary, lineHeight: 17 }} numberOfLines={3}>{memo.sharedContent.urlDescription}</Text>
            )}
            <Text style={{ fontSize: 11, color: theme.textMuted, marginTop: 8 }}>Tap to open in browser</Text>
          </Pressable>
        )}

        {memo.sharedContent?.type === 'image' && memo.sharedContent.filePath && (
          <Image
            source={{ uri: memo.sharedContent.filePath }}
            style={{ width: '100%', height: 240, borderRadius: 10, marginTop: 12 }}
            resizeMode="contain"
          />
        )}

        {memo.sharedContent?.type === 'text' && memo.sharedContent.text && (
          <View style={{ backgroundColor: theme.surface, borderRadius: 10, padding: 14, marginTop: 12, borderWidth: StyleSheet.hairlineWidth, borderColor: theme.border }}>
            <Text style={{ fontSize: 13, color: theme.textPrimary, lineHeight: 18 }}>{memo.sharedContent.text}</Text>
          </View>
        )}

        {memo.sharedContent?.type === 'file' && memo.sharedContent.filePath && (
          <Pressable
            onPress={() => Linking.openURL(memo.sharedContent!.filePath!)}
            style={({ pressed }) => [
              { backgroundColor: theme.surface, borderRadius: 10, padding: 14, marginTop: 12, borderWidth: StyleSheet.hairlineWidth, borderColor: theme.border },
              pressed && { opacity: 0.7 },
            ]}
          >
            <Text style={{ fontSize: 14, color: theme.textPrimary }}>{memo.sharedContent.fileName || 'File'}</Text>
            <Text style={{ fontSize: 11, color: theme.textMuted, marginTop: 4 }}>Tap to open</Text>
          </Pressable>
        )}

        {/* Typed annotation */}
        {memo.annotationText && (
          <View style={{ marginTop: 12 }}>
            <Text style={{ fontSize: 11, fontWeight: '600', color: theme.textMuted, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 6 }}>Annotation</Text>
            <Text style={{ fontSize: 14, color: theme.textPrimary, lineHeight: 20 }}>{memo.annotationText}</Text>
          </View>
        )}

        {/* Cover photo (single, legacy) */}
        {memo.metadata?.photoFilename && (
          <Image
            source={{ uri: memo.audioUri.replace(memo.filename, memo.metadata.photoFilename) }}
            style={styles.photo}
            resizeMode="cover"
          />
        )}

        {/* Timestamped photos from recording */}
        {memo.metadata?.imageManifest && memo.metadata.imageManifest.length > 0 && (
          <View style={{ marginTop: 20 }}>
            <Text style={styles.sectionTitle}>Photos ({memo.metadata.imageManifest.length})</Text>
            <ScrollView horizontal showsHorizontalScrollIndicator={false}>
              {memo.metadata.imageManifest.map((entry, i) => {
                const photoUri = `${Paths.document.uri}recordings/${entry.filename}`;
                return (
                  <Pressable
                    key={`${entry.filename}-${i}`}
                    onPress={() => {
                      setSelectedPhoto(photoUri);
                    }}
                    style={{ marginRight: 8 }}
                  >
                    <Image
                      source={{ uri: photoUri }}
                      style={{ width: 80, height: 80, borderRadius: 8, backgroundColor: theme.surface }}
                    />
                    <Text style={{ fontSize: 11, color: theme.textMuted, marginTop: 4, textAlign: 'center' }}>
                      {formatDuration(entry.offsetSeconds)}
                    </Text>
                  </Pressable>
                );
              })}
            </ScrollView>
          </View>
        )}

        {/* Playback card — only show if there's audio */}
        {memo.audioUri ? <View style={styles.playerCard}>
          <Pressable
            onPress={() => {
              haptics.tap();
              playback.isPlaying ? playback.pause() : playback.play();
            }}
            style={({ pressed }) => [styles.playButton, pressed && { opacity: 0.6 }]}
          >
            {playback.isPlaying ? (
              <View style={{ flexDirection: 'row', gap: 3 }}>
                <View style={{ width: 3, height: 16, backgroundColor: theme.accent, borderRadius: 1 }} />
                <View style={{ width: 3, height: 16, backgroundColor: theme.accent, borderRadius: 1 }} />
              </View>
            ) : (
              <View style={{ width: 0, height: 0, borderLeftWidth: 12, borderLeftColor: theme.accent, borderTopWidth: 8, borderTopColor: 'transparent', borderBottomWidth: 8, borderBottomColor: 'transparent', marginLeft: 3 }} />
            )}
          </Pressable>
          <View style={styles.playerInfo}>
            <Pressable
              style={styles.progressBar}
              onLayout={(e) => { progressBarWidth.current = e.nativeEvent.layout.width; }}
              onPress={(e) => {
                if (progressBarWidth.current > 0 && playback.duration) {
                  const pos = (e.nativeEvent.locationX / progressBarWidth.current) * playback.duration;
                  playback.seekTo(pos);
                }
              }}
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
            <View style={styles.timeRow}>
              <Text style={styles.timeText}>
                {formatDuration(Math.floor(playback.position))}
              </Text>
              <Text style={styles.timeText}>
                {formatDuration(Math.floor(playback.duration))}
              </Text>
            </View>
          </View>
        </View> : null}

        {/* Transcript */}
        {memo.transcript && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Transcript</Text>
            <Text style={[styles.metaValue, { marginTop: 8, lineHeight: 22 }]} numberOfLines={20}>
              {memo.transcript}
            </Text>
          </View>
        )}

        {/* Tags */}
        {memo.tags.length > 0 && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Tags</Text>
            <View style={styles.tagsRow}>
              {memo.tags.map((tag, i) => (
                <View key={i} style={styles.tag}>
                  <Text style={styles.tagText}>#{tag}</Text>
                </View>
              ))}
            </View>
          </View>
        )}

        {/* Capture context */}
        {memo.metadata && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Capture context</Text>
            <View style={styles.metaCard}>
              {memo.metadata.location?.placeName && (
                <View style={styles.metaRow}>
                  <Text style={styles.metaLabel}>Location</Text>
                  <Text style={styles.metaValue}>{memo.metadata.location.placeName}</Text>
                </View>
              )}
              <View style={styles.metaRow}>
                <Text style={styles.metaLabel}>Day period</Text>
                <Text style={styles.metaValue}>{memo.metadata.dayPeriod}</Text>
              </View>
              {memo.metadata.daylight && (
                <View style={styles.metaRow}>
                  <Text style={styles.metaLabel}>Daylight</Text>
                  <Text style={styles.metaValue}>
                    {memo.metadata.daylight.sunrise} – {memo.metadata.daylight.sunset} ({memo.metadata.daylight.hoursOfLight}h)
                  </Text>
                </View>
              )}
              {memo.metadata.steps !== null && (
                <View style={styles.metaRow}>
                  <Text style={styles.metaLabel}>Steps today</Text>
                  <Text style={styles.metaValue}>{memo.metadata.steps.toLocaleString()}</Text>
                </View>
              )}
              {memo.metadata.weather && (
                <View style={styles.metaRow}>
                  <Text style={styles.metaLabel}>Weather</Text>
                  <Text style={styles.metaValue}>
                    {memo.metadata.weather.conditions}, {memo.metadata.weather.temperature}°{memo.metadata.weather.temperatureUnit}
                  </Text>
                </View>
              )}
              {memo.metadata.pressure && (
                <View style={styles.metaRow}>
                  <Text style={styles.metaLabel}>Pressure</Text>
                  <Text style={styles.metaValue}>
                    {memo.metadata.pressure.hPa} hPa · {memo.metadata.pressure.trend}
                  </Text>
                </View>
              )}
            </View>
          </View>
        )}

        {/* Sync status */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Sync</Text>
          <View style={styles.syncRow}>
            <View
              style={[
                styles.syncDot,
                memo.syncStatus === 'synced'
                  ? styles.syncDotSynced
                  : styles.syncDotWaiting,
              ]}
            />
            <Text style={styles.syncText}>
              {memo.syncStatus === 'synced'
                ? 'Synced to Mac'
                : 'Waiting \u2014 will sync when connected to Mac'}
            </Text>
          </View>
        </View>
      </ScrollView>

      {/* Full-size photo modal */}
      <Modal visible={!!selectedPhoto} transparent animationType="fade" onRequestClose={() => setSelectedPhoto(null)}>
        <Pressable
          style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.9)', justifyContent: 'center', alignItems: 'center' }}
          onPress={() => setSelectedPhoto(null)}
        >
          {selectedPhoto && (
            <Image
              source={{ uri: selectedPhoto }}
              style={{ width: '90%', height: '70%' }}
              resizeMode="contain"
            />
          )}
          <Text style={{ color: '#fff', fontSize: 14, marginTop: 20, opacity: 0.6 }}>Tap to close</Text>
        </Pressable>
      </Modal>
    </SafeAreaView>
  );
}
