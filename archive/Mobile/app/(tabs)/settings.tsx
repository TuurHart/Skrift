import { useState, useCallback, useMemo } from 'react';
import { View, Text, StyleSheet, ScrollView, TextInput, Pressable, Alert, Platform, ActivityIndicator, Switch } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useFocusEffect, useRouter } from 'expo-router';
import { getWeatherApiKey, setWeatherApiKey } from '../../lib/metadata';
import { loadMemos, type Memo } from '../../lib/storage';
import { getPrompts, setPrompts, DEFAULT_PROMPTS } from '../../lib/prompts';
import {
  getMacConnection,
  setMacConnection,
  checkMacHealth,
  getLastSyncTime,
  type MacConnection,
} from '../../lib/sync';
import { useTheme } from '../../contexts/ThemeContext';
import * as haptics from '../../lib/haptics';
import { NamesList } from '../../components/NamesList';

function SettingsSection({ title, children, styles }: { title: string; children: React.ReactNode; styles: ReturnType<typeof StyleSheet.create> }) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      <View style={styles.sectionContent}>{children}</View>
    </View>
  );
}

function SettingsRow({ label, value, styles }: { label: string; value: string; styles: ReturnType<typeof StyleSheet.create> }) {
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={styles.rowValue}>{value}</Text>
    </View>
  );
}

export default function SettingsScreen() {
  const { theme, isDark, toggleTheme } = useTheme();
  const router = useRouter();
  const [apiKey, setApiKey] = useState('');
  const [savedKey, setSavedKey] = useState<string | null>(null);
  const [memoCount, setMemoCount] = useState(0);
  const [syncedCount, setSyncedCount] = useState(0);

  // Mac connection state
  const [connection, setConnection] = useState<MacConnection | null>(null);
  const [macReachable, setMacReachable] = useState<boolean | null>(null);
  const [testing, setTesting] = useState(false);
  const [lastSync, setLastSync] = useState<string | null>(null);

  // Prompts state
  const [customPrompts, setCustomPrompts] = useState<string[]>(DEFAULT_PROMPTS);
  const [editingPrompts, setEditingPrompts] = useState(false);
  const [editPromptIndex, setEditPromptIndex] = useState<number | null>(null);
  const [editPromptText, setEditPromptText] = useState('');

  // Manual IP entry
  const [manualHost, setManualHost] = useState('');
  const [manualPort, setManualPort] = useState('8000');

  const styles = useMemo(() => StyleSheet.create({
    container: {
      flex: 1,
      backgroundColor: theme.bg,
    },
    scroll: {
      paddingHorizontal: 20,
      paddingBottom: 40,
    },
    title: {
      fontSize: 32,
      fontWeight: '700',
      color: theme.textPrimary,
      paddingTop: 12,
      marginBottom: 24,
      lineHeight: 38,
    },
    section: {
      marginBottom: 24,
    },
    sectionTitle: {
      fontSize: 13,
      fontWeight: '600',
      color: theme.textSecondary,
      textTransform: 'uppercase',
      letterSpacing: 0.8,
      marginBottom: 8,
    },
    sectionContent: {
      backgroundColor: theme.surface,
      borderRadius: 16,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
      overflow: 'hidden',
    },
    row: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      paddingHorizontal: 16,
      paddingVertical: 14,
      borderBottomWidth: StyleSheet.hairlineWidth,
      borderBottomColor: theme.border,
    },
    rowLabel: {
      fontSize: 15,
      color: theme.textPrimary,
    },
    rowValue: {
      fontSize: 15,
      color: theme.textSecondary,
    },
    // Mac Connection
    connectionHeader: {
      paddingHorizontal: 16,
      paddingVertical: 14,
      borderBottomWidth: StyleSheet.hairlineWidth,
      borderBottomColor: theme.border,
    },
    connectionStatus: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
    },
    statusDot: {
      width: 8,
      height: 8,
      borderRadius: 4,
    },
    statusDotGreen: {
      backgroundColor: theme.checkGreen,
    },
    statusDotRed: {
      backgroundColor: theme.destructive,
    },
    connectionStatusText: {
      fontSize: 15,
      fontWeight: '500',
      color: theme.textPrimary,
    },
    connectionInfo: {
      fontSize: 13,
      color: theme.textSecondary,
      marginTop: 4,
    },
    inputSection: {
      paddingHorizontal: 16,
      paddingVertical: 14,
      borderBottomWidth: StyleSheet.hairlineWidth,
      borderBottomColor: theme.border,
    },
    inputLabel: {
      fontSize: 13,
      color: theme.textSecondary,
      marginBottom: 8,
    },
    hostPortRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 4,
    },
    input: {
      backgroundColor: theme.bg,
      borderRadius: 8,
      paddingHorizontal: 12,
      paddingVertical: 10,
      fontSize: 14,
      color: theme.textPrimary,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
    },
    hostInput: {
      flex: 1,
      fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
    },
    portInput: {
      width: 70,
      textAlign: 'center',
      fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
    },
    colonText: {
      fontSize: 16,
      color: theme.textMuted,
      fontWeight: '600',
    },
    connectionButtons: {
      flexDirection: 'row',
      gap: 8,
      marginTop: 12,
    },
    connectionButton: {
      flex: 1,
      borderRadius: 8,
      paddingVertical: 10,
      alignItems: 'center',
    },
    testButton: {
      backgroundColor: theme.accent,
    },
    scanButton: {
      backgroundColor: theme.surfaceHover,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
    },
    connectionButtonText: {
      fontSize: 14,
      fontWeight: '600',
      color: '#ffffff',
    },
    // API key
    apiKeyRow: {
      paddingHorizontal: 16,
      paddingVertical: 14,
    },
    apiKeyInputRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
      marginTop: 8,
    },
    apiKeyInput: {
      flex: 1,
      backgroundColor: theme.bg,
      borderRadius: 8,
      paddingHorizontal: 12,
      paddingVertical: 10,
      fontSize: 14,
      color: theme.textPrimary,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
      fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
    },
    saveKeyButton: {
      backgroundColor: theme.accent,
      borderRadius: 8,
      paddingHorizontal: 14,
      paddingVertical: 10,
    },
    saveKeyText: {
      fontSize: 14,
      fontWeight: '600',
      color: '#ffffff',
    },
    apiKeyHint: {
      fontSize: 12,
      color: theme.textMuted,
      marginTop: 8,
    },
    apiKeyStatus: {
      fontSize: 12,
      color: theme.checkGreen,
      marginTop: 4,
    },
  }), [theme]);

  useFocusEffect(
    useCallback(() => {
      getWeatherApiKey().then((key) => {
        setSavedKey(key);
        setApiKey(key ?? '');
      });
      loadMemos().then((memos) => {
        setMemoCount(memos.length);
        setSyncedCount(memos.filter((m) => m.syncStatus === 'synced').length);
      });
      getMacConnection().then((conn) => {
        setConnection(conn);
        if (conn) {
          setManualHost(conn.host);
          setManualPort(String(conn.port));
          // Auto-test on load
          checkMacHealth(conn.host, conn.port).then(setMacReachable);
        }
      });
      getLastSyncTime().then(setLastSync);
      getPrompts().then(setCustomPrompts);
    }, [])
  );

  const handleSaveKey = async () => {
    haptics.tap();
    await setWeatherApiKey(apiKey);
    setSavedKey(apiKey.trim() || null);
    Alert.alert('Saved', apiKey.trim() ? 'Weather API key saved.' : 'Weather API key removed.');
  };

  const handleTestConnection = async () => {
    haptics.tap();
    const host = manualHost.trim();
    const port = parseInt(manualPort.trim() || '8000', 10);
    if (!host) {
      Alert.alert('Enter IP', 'Please enter your Mac\'s IP address.');
      return;
    }

    setTesting(true);
    const reachable = await checkMacHealth(host, port);
    setMacReachable(reachable);
    setTesting(false);

    if (reachable) {
      const conn: MacConnection = { host, port, deviceName: 'Mac' };
      await setMacConnection(conn);
      setConnection(conn);
      Alert.alert('Connected', `Successfully connected to ${host}:${port}`);
    } else {
      Alert.alert('Unreachable', `Could not reach ${host}:${port}. Is Skrift running on your Mac?`);
    }
  };

  const handleSaveConnection = async () => {
    const host = manualHost.trim();
    const port = parseInt(manualPort.trim() || '8000', 10);
    if (!host) return;
    const conn: MacConnection = { host, port, deviceName: connection?.deviceName ?? 'Mac' };
    await setMacConnection(conn);
    setConnection(conn);
  };

  const keyChanged = apiKey.trim() !== (savedKey ?? '');

  // Prompt editing handlers
  const handleEditPrompt = (index: number) => {
    setEditPromptIndex(index);
    setEditPromptText(customPrompts[index]);
  };

  const handleSavePrompt = async () => {
    if (editPromptIndex === null) return;
    const text = editPromptText.trim();
    if (!text) return;
    const updated = [...customPrompts];
    updated[editPromptIndex] = text;
    setCustomPrompts(updated);
    await setPrompts(updated);
    setEditPromptIndex(null);
    setEditPromptText('');
  };

  const handleAddPrompt = async () => {
    Alert.prompt?.('New prompt', 'Enter a memory aid prompt', async (text: string) => {
      if (!text?.trim()) return;
      const updated = [...customPrompts, text.trim()];
      setCustomPrompts(updated);
      await setPrompts(updated);
    });
    // Fallback for simulators without Alert.prompt
    if (!Alert.prompt) {
      const updated = [...customPrompts, 'New prompt'];
      setCustomPrompts(updated);
      await setPrompts(updated);
      handleEditPrompt(updated.length - 1);
    }
  };

  const handleDeletePrompt = async (index: number) => {
    if (customPrompts.length <= 1) {
      Alert.alert('Cannot delete', 'You need at least one prompt.');
      return;
    }
    const updated = customPrompts.filter((_, i) => i !== index);
    setCustomPrompts(updated);
    await setPrompts(updated);
  };

  const handleResetPrompts = async () => {
    Alert.alert('Reset prompts?', 'This will restore the default prompts.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Reset',
        onPress: async () => {
          setCustomPrompts(DEFAULT_PROMPTS);
          await setPrompts(DEFAULT_PROMPTS);
        },
      },
    ]);
  };

  const formatLastSync = (iso: string | null) => {
    if (!iso) return 'Never';
    const d = new Date(iso);
    const now = new Date();
    const diffMin = Math.floor((now.getTime() - d.getTime()) / 60000);
    if (diffMin < 1) return 'Just now';
    if (diffMin < 60) return `${diffMin}m ago`;
    if (diffMin < 1440) return `${Math.floor(diffMin / 60)}h ago`;
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  };

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView contentContainerStyle={styles.scroll}>
        <Text style={styles.title}>Settings</Text>

        <SettingsSection title="Mac Connection" styles={styles}>
          <View style={styles.connectionHeader}>
            <View style={styles.connectionStatus}>
              <View style={[styles.statusDot, macReachable ? styles.statusDotGreen : styles.statusDotRed]} />
              <Text style={styles.connectionStatusText}>
                {macReachable === null ? 'Not checked' : macReachable ? 'Connected' : 'Not connected'}
              </Text>
            </View>
            {connection && (
              <Text style={styles.connectionInfo}>
                {connection.deviceName} — {connection.host}:{connection.port}
              </Text>
            )}
          </View>

          <View style={styles.inputSection}>
            <Text style={styles.inputLabel}>Mac IP address</Text>
            <View style={styles.hostPortRow}>
              <TextInput
                style={[styles.input, styles.hostInput]}
                value={manualHost}
                onChangeText={setManualHost}
                placeholder="e.g. 192.168.1.42"
                placeholderTextColor={theme.textMuted}
                keyboardType="decimal-pad"
                autoCapitalize="none"
                autoCorrect={false}
                selectionColor={theme.accent}
                cursorColor={theme.accent}
              />
              <Text style={styles.colonText}>:</Text>
              <TextInput
                style={[styles.input, styles.portInput]}
                value={manualPort}
                onChangeText={setManualPort}
                placeholder="8000"
                placeholderTextColor={theme.textMuted}
                keyboardType="number-pad"
                selectionColor={theme.accent}
                cursorColor={theme.accent}
              />
            </View>

            <View style={styles.connectionButtons}>
              <Pressable
                style={({ pressed }) => [styles.connectionButton, styles.testButton, pressed && { opacity: 0.7 }]}
                onPress={handleTestConnection}
                disabled={testing}
              >
                {testing ? (
                  <ActivityIndicator size="small" color="#fff" />
                ) : (
                  <Text style={styles.connectionButtonText}>Test Connection</Text>
                )}
              </Pressable>

              <Pressable
                style={({ pressed }) => [styles.connectionButton, styles.scanButton, pressed && { opacity: 0.7 }]}
                onPress={() => router.push('/scan-qr')}
              >
                <Text style={styles.connectionButtonText}>Scan QR Code</Text>
              </Pressable>
            </View>
          </View>

          <SettingsRow label="Last sync" value={formatLastSync(lastSync)} styles={styles} />
        </SettingsSection>

        <SettingsSection title="Names" styles={styles}>
          <NamesList />
        </SettingsSection>

        <SettingsSection title="Weather API" styles={styles}>
          <View style={styles.apiKeyRow}>
            <Text style={styles.rowLabel}>OpenWeatherMap key</Text>
            <View style={styles.apiKeyInputRow}>
              <TextInput
                style={styles.apiKeyInput}
                value={apiKey}
                onChangeText={setApiKey}
                placeholder="Paste API key here"
                placeholderTextColor={theme.textMuted}
                autoCapitalize="none"
                autoCorrect={false}
                secureTextEntry={!apiKey}
                selectionColor={theme.accent}
                cursorColor={theme.accent}
              />
              {keyChanged && (
                <Pressable style={({ pressed }) => [styles.saveKeyButton, pressed && { opacity: 0.7 }]} onPress={handleSaveKey}>
                  <Text style={styles.saveKeyText}>Save</Text>
                </Pressable>
              )}
            </View>
            <Text style={styles.apiKeyHint}>
              Free at openweathermap.org/api — enables weather + pressure capture
            </Text>
            {savedKey && (
              <Text style={styles.apiKeyStatus}>Key configured</Text>
            )}
          </View>
        </SettingsSection>

        <SettingsSection title="Metadata Capture" styles={styles}>
          <SettingsRow label="Location" value="On" styles={styles} />
          <SettingsRow label="Weather" value={savedKey ? 'On' : 'No API key'} styles={styles} />
          <SettingsRow label="Daylight" value="On" styles={styles} />
          <SettingsRow label="Step count" value="On" styles={styles} />
          <SettingsRow label="HealthKit" value="Off" styles={styles} />
        </SettingsSection>

        <SettingsSection title="Memory Aid Prompts" styles={styles}>
          {customPrompts.map((prompt, i) => (
            <View key={i} style={styles.row}>
              {editPromptIndex === i ? (
                <View style={{ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                  <TextInput
                    style={[styles.input, { flex: 1 }]}
                    value={editPromptText}
                    onChangeText={setEditPromptText}
                    autoFocus
                    onSubmitEditing={handleSavePrompt}
                    returnKeyType="done"
                    selectionColor={theme.accent}
                    cursorColor={theme.accent}
                  />
                  <Pressable onPress={handleSavePrompt}>
                    <Text style={{ color: theme.accent, fontWeight: '600', fontSize: 15 }}>Save</Text>
                  </Pressable>
                </View>
              ) : (
                <>
                  <Pressable onPress={() => handleEditPrompt(i)} style={{ flex: 1 }}>
                    <Text style={styles.rowLabel}>{prompt}</Text>
                  </Pressable>
                  <Pressable onPress={() => handleDeletePrompt(i)} hitSlop={12}>
                    <Text style={{ color: theme.destructive, fontSize: 18 }}>-</Text>
                  </Pressable>
                </>
              )}
            </View>
          ))}
          <View style={[styles.row, { justifyContent: 'center', gap: 16 }]}>
            <Pressable onPress={handleAddPrompt}>
              <Text style={{ color: theme.accent, fontSize: 15, fontWeight: '500' }}>Add Prompt</Text>
            </Pressable>
            <Text style={{ color: theme.border }}>|</Text>
            <Pressable onPress={handleResetPrompts}>
              <Text style={{ color: theme.textMuted, fontSize: 15 }}>Reset</Text>
            </Pressable>
          </View>
        </SettingsSection>

        <SettingsSection title="Appearance" styles={styles}>
          <View style={styles.row}>
            <Text style={styles.rowLabel}>Dark mode</Text>
            <Switch
              value={isDark}
              onValueChange={() => { haptics.tap(); toggleTheme(); }}
              trackColor={{ true: theme.accent, false: '#c7c7cc' }}
              thumbColor="#fff"
            />
          </View>
        </SettingsSection>

        <SettingsSection title="Quick Record Shortcut" styles={styles}>
          <View style={{ paddingHorizontal: 16, paddingVertical: 14 }}>
            <Text style={{ fontSize: 14, color: theme.textSecondary, lineHeight: 20, marginBottom: 12 }}>
              Start recording from your Lock Screen, Home Screen, or Action Button with an iOS Shortcut.
            </Text>
            <View style={{ backgroundColor: theme.bg, borderRadius: 10, padding: 14, gap: 10 }}>
              <Text style={{ fontSize: 13, fontWeight: '600', color: theme.textPrimary }}>Setup instructions:</Text>
              <View style={{ gap: 6 }}>
                {[
                  '1. Open the Shortcuts app',
                  '2. Tap + to create a new shortcut',
                  '3. Add action → "Open URLs"',
                  '4. Set the URL to: skrift://record',
                  '5. Name it "Record Memo"',
                ].map((step, i) => (
                  <Text key={i} style={{ fontSize: 13, color: theme.textSecondary, lineHeight: 18 }}>{step}</Text>
                ))}
              </View>
              <View style={{ height: StyleSheet.hairlineWidth, backgroundColor: theme.border, marginVertical: 4 }} />
              <Text style={{ fontSize: 12, color: theme.textMuted, lineHeight: 16 }}>
                Then add it to your Lock Screen, Home Screen, or assign it to the Action Button (iPhone 15 Pro+) in Settings → Action Button.
              </Text>
            </View>
            <View style={{ marginTop: 12, backgroundColor: theme.bg, borderRadius: 10, paddingHorizontal: 14, paddingVertical: 10, flexDirection: 'row', alignItems: 'center', gap: 8 }}>
              <Text style={{ fontSize: 13, color: theme.textMuted }}>Deep link:</Text>
              <Text style={{ fontSize: 13, color: theme.accent, fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace' }}>skrift://record</Text>
            </View>
          </View>
        </SettingsSection>

        <SettingsSection title="Storage" styles={styles}>
          <SettingsRow label="Local memos" value={String(memoCount)} styles={styles} />
          <SettingsRow label="Synced" value={String(syncedCount)} styles={styles} />
          <SettingsRow label="Waiting" value={String(memoCount - syncedCount)} styles={styles} />
          {syncedCount > 0 && (
            <Pressable
              style={({ pressed }) => [styles.row, { justifyContent: 'center' }, pressed && { opacity: 0.7 }]}
              onPress={() => {
                Alert.alert(
                  `Clear ${syncedCount} synced memo${syncedCount !== 1 ? 's' : ''}?`,
                  'Audio files will be deleted from this phone. They are already on your Mac.',
                  [
                    { text: 'Cancel', style: 'cancel' },
                    {
                      text: 'Clear',
                      style: 'destructive',
                      onPress: async () => {
                        const { deleteMemos } = await import('../../lib/storage');
                        const memos = await loadMemos();
                        const syncedIds = memos.filter((m) => m.syncStatus === 'synced').map((m) => m.id);
                        await deleteMemos(syncedIds);
                        const remaining = await loadMemos();
                        setMemoCount(remaining.length);
                        setSyncedCount(remaining.filter((m) => m.syncStatus === 'synced').length);
                      },
                    },
                  ],
                );
              }}
            >
              <Text style={{ color: theme.destructive, fontSize: 15, fontWeight: '500' }}>
                Clear synced memos
              </Text>
            </Pressable>
          )}
        </SettingsSection>
      </ScrollView>
    </SafeAreaView>
  );
}
