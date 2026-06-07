import { useState, useRef, useMemo } from 'react';
import { View, Text, StyleSheet, Pressable, Alert } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { parseQRCode, setMacConnection, checkMacHealth } from '../lib/sync';
import { useTheme } from '../contexts/ThemeContext';
import * as haptics from '../lib/haptics';

export default function ScanQRScreen() {
  const { theme } = useTheme();
  const router = useRouter();
  const [permission, requestPermission] = useCameraPermissions();
  const [scanned, setScanned] = useState(false);
  const processingRef = useRef(false);

  const styles = useMemo(() => StyleSheet.create({
    container: {
      flex: 1,
      backgroundColor: theme.bg,
    },
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      paddingHorizontal: 20,
      paddingVertical: 12,
    },
    headerTitle: {
      fontSize: 17,
      fontWeight: '600',
      color: theme.textPrimary,
    },
    cancelButton: {
      fontSize: 15,
      color: theme.accent,
      fontWeight: '500',
    },
    cameraContainer: {
      flex: 1,
      margin: 20,
      borderRadius: 16,
      overflow: 'hidden',
      position: 'relative',
    },
    camera: {
      flex: 1,
    },
    overlay: {
      ...StyleSheet.absoluteFillObject,
      alignItems: 'center',
      justifyContent: 'center',
    },
    scanFrame: {
      width: 220,
      height: 220,
      borderWidth: 2,
      borderColor: theme.accent,
      borderRadius: 16,
      backgroundColor: 'transparent',
    },
    hint: {
      fontSize: 14,
      color: theme.textSecondary,
      textAlign: 'center',
      paddingHorizontal: 40,
      paddingBottom: 30,
    },
    message: {
      fontSize: 15,
      color: theme.textSecondary,
      textAlign: 'center',
      marginTop: 100,
    },
    permissionBox: {
      flex: 1,
      alignItems: 'center',
      justifyContent: 'center',
      paddingHorizontal: 40,
      gap: 12,
    },
    permissionTitle: {
      fontSize: 18,
      fontWeight: '600',
      color: theme.textPrimary,
    },
    permissionText: {
      fontSize: 14,
      color: theme.textSecondary,
      textAlign: 'center',
    },
    grantButton: {
      backgroundColor: theme.accent,
      borderRadius: 10,
      paddingHorizontal: 24,
      paddingVertical: 12,
      marginTop: 8,
    },
    grantButtonText: {
      fontSize: 15,
      fontWeight: '600',
      color: '#ffffff',
    },
    cancelText: {
      fontSize: 14,
      color: theme.textMuted,
      marginTop: 8,
    },
  }), [theme]);

  const handleBarCodeScanned = async ({ data }: { data: string }) => {
    if (processingRef.current) return;
    processingRef.current = true;
    setScanned(true);

    const conn = parseQRCode(data);
    if (!conn) {
      Alert.alert('Invalid QR', 'This QR code is not a Skrift pairing code.', [
        { text: 'Try again', onPress: () => { setScanned(false); processingRef.current = false; } },
        { text: 'Cancel', onPress: () => router.back() },
      ]);
      return;
    }

    // Test connection
    const reachable = await checkMacHealth(conn.host, conn.port);
    if (reachable) {
      haptics.success();
      await setMacConnection(conn);
      Alert.alert(
        'Paired!',
        `Connected to ${conn.deviceName} at ${conn.host}:${conn.port}`,
        [{ text: 'OK', onPress: () => router.back() }],
      );
    } else {
      Alert.alert(
        'Found but unreachable',
        `QR points to ${conn.host}:${conn.port} but the Mac is not responding. Make sure Skrift is running.`,
        [
          { text: 'Save anyway', onPress: async () => { await setMacConnection(conn); router.back(); } },
          { text: 'Try again', onPress: () => { setScanned(false); processingRef.current = false; } },
        ],
      );
    }
  };

  if (!permission) {
    return (
      <SafeAreaView style={styles.container}>
        <Text style={styles.message}>Requesting camera permission...</Text>
      </SafeAreaView>
    );
  }

  if (!permission.granted) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.permissionBox}>
          <Text style={styles.permissionTitle}>Camera access needed</Text>
          <Text style={styles.permissionText}>
            We need the camera to scan the QR code shown in Skrift on your Mac.
          </Text>
          <Pressable style={({ pressed }) => [styles.grantButton, pressed && { opacity: 0.7 }]} onPress={requestPermission}>
            <Text style={styles.grantButtonText}>Grant Permission</Text>
          </Pressable>
          <Pressable onPress={() => router.back()} style={({ pressed }) => [pressed && { opacity: 0.7 }]}>
            <Text style={styles.cancelText}>Cancel</Text>
          </Pressable>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} style={({ pressed }) => [pressed && { opacity: 0.7 }]}>
          <Text style={styles.cancelButton}>Cancel</Text>
        </Pressable>
        <Text style={styles.headerTitle}>Scan QR Code</Text>
        <View style={{ width: 60 }} />
      </View>

      <View style={styles.cameraContainer}>
        <CameraView
          style={styles.camera}
          facing="back"
          barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
          onBarcodeScanned={scanned ? undefined : handleBarCodeScanned}
        />
        <View style={styles.overlay}>
          <View style={styles.scanFrame} />
        </View>
      </View>

      <Text style={styles.hint}>
        Open Skrift on your Mac, go to Settings → Mobile, and scan the QR code shown there.
      </Text>
    </SafeAreaView>
  );
}
