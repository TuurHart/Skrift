import * as Haptics from 'expo-haptics';

/** Light tap — card presses, play/pause, settings toggles */
export function tap() {
  Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
}

/** Medium impact — entering select mode, important actions */
export function medium() {
  Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
}

/** Heavy impact — start/stop recording */
export function heavy() {
  Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
}

/** Success notification — sync complete, QR paired, saved */
export function success() {
  Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
}

/** Warning notification — discard, destructive preview */
export function warning() {
  Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
}

/** Error notification — delete confirmation */
export function error() {
  Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
}
