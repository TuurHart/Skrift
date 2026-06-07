import { useRef, useCallback } from 'react';
import { Tabs, useRouter } from 'expo-router';
import { View, StyleSheet } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../contexts/ThemeContext';
import { useRecordingContext } from '../../contexts/RecordingContext';
import * as haptics from '../../lib/haptics';

function MemosIcon({ focused, color }: { focused: boolean; color: string }) {
  return (
    <View style={{ width: 24, height: 24, justifyContent: 'center' }}>
      <View style={{ width: 18, height: 2, backgroundColor: color, borderRadius: 1, marginBottom: 4 }} />
      <View style={{ width: 14, height: 2, backgroundColor: color, borderRadius: 1, marginBottom: 4 }} />
      <View style={{ width: 16, height: 2, backgroundColor: color, borderRadius: 1 }} />
    </View>
  );
}

function SettingsIcon({ focused, color }: { focused: boolean; color: string }) {
  return (
    <View style={{ width: 24, height: 24, alignItems: 'center', justifyContent: 'center' }}>
      <View style={{
        width: 18,
        height: 18,
        borderRadius: 9,
        borderWidth: 2,
        borderColor: color,
        alignItems: 'center',
        justifyContent: 'center',
      }}>
        <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: color }} />
      </View>
    </View>
  );
}

export default function TabLayout() {
  const { theme } = useTheme();
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const { isRecording, startRecording, stopRecording, resetState, pendingPhotosRef } = useRecordingContext();
  const navigatingRef = useRef(false);

  const handleRecordTabPress = useCallback(async (e: { preventDefault: () => void }) => {
    e.preventDefault();

    if (isRecording) {
      // Stop recording → navigate to review
      if (navigatingRef.current) return;
      navigatingRef.current = true;
      haptics.heavy();

      const result = await stopRecording();
      if (!result) {
        navigatingRef.current = false;
        return;
      }

      // Store photos in shared ref (avoids URL length limits with many photos)
      pendingPhotosRef.current = result.photos;

      router.push({
        pathname: '/review',
        params: {
          uri: result.uri,
          duration: result.duration.toString(),
        },
      });
      navigatingRef.current = false;
    } else {
      // Navigate to record tab and start recording
      haptics.heavy();
      resetState();
      router.navigate('/(tabs)/record');
      setTimeout(() => { startRecording().catch(() => {}); }, 100);
    }
  }, [isRecording, startRecording, stopRecording, resetState, router]);

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarStyle: {
          backgroundColor: theme.surface,
          borderTopColor: theme.border,
          borderTopWidth: StyleSheet.hairlineWidth,
          height: 58 + insets.bottom,
          paddingBottom: insets.bottom,
        },
        tabBarActiveTintColor: theme.accent,
        tabBarInactiveTintColor: theme.textMuted,
        tabBarLabelStyle: {
          fontSize: 11,
          fontWeight: '500',
        },
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: 'Memos',
          tabBarIcon: ({ focused, color }) => <MemosIcon focused={focused} color={color} />,
        }}
      />
      <Tabs.Screen
        name="record"
        listeners={{
          tabPress: handleRecordTabPress,
        }}
        options={{
          title: '',
          tabBarIcon: ({ focused }) => (
            <View style={styles.recordButtonOuter}>
              {isRecording ? (
                <View style={styles.stopSquare} />
              ) : (
                <View
                  style={[
                    styles.recordButtonInner,
                    focused && styles.recordButtonInnerActive,
                  ]}
                />
              )}
            </View>
          ),
        }}
      />
      <Tabs.Screen
        name="settings"
        options={{
          title: 'Settings',
          tabBarIcon: ({ focused, color }) => <SettingsIcon focused={focused} color={color} />,
        }}
      />
    </Tabs>
  );
}

const styles = StyleSheet.create({
  recordButtonOuter: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 6,
  },
  recordButtonInner: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: '#ef4444',
  },
  recordButtonInnerActive: {
    backgroundColor: '#ff5555',
  },
  stopSquare: {
    width: 22,
    height: 22,
    borderRadius: 4,
    backgroundColor: '#ef4444',
  },
});
