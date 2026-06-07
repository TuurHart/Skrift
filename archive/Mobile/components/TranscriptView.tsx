import { useMemo, useState } from 'react';
import { View, Text, TextInput, Image, Pressable, StyleSheet } from 'react-native';
import { useTheme } from '../contexts/ThemeContext';

type Props = {
  /** Full transcript text, possibly containing `[[img_NNN]]` tokens. */
  text: string;
  /** Called when user edits the text (in edit mode). */
  onChangeText: (next: string) => void;
  /**
   * Resolved image URIs, ordered by ascending offsetSeconds — so
   * `[[img_001]]` ↔ imageUris[0], `[[img_002]]` ↔ imageUris[1], etc.
   * Matches the marker numbering produced by ParakeetModule.
   */
  imageUris?: string[];
  /** Optional placeholder when text is empty. */
  placeholder?: string;
};

const MARKER_RE = /\[\[img_(\d{3})\]\]/g;

/**
 * Renders a transcript with `[[img_NNN]]` markers expanded into inline image
 * thumbnails. Tap the pencil to swap into a plain TextInput for editing
 * (markers stay as literal tokens — deleting one removes the photo from the
 * transcript). Tap Done to flip back to the rich view.
 *
 * v1 deliberately keeps view + edit modes separate; doing inline-images +
 * editable text in a single field requires a real RichText component, and
 * the desktop's contenteditable equivalent is similarly two-mode in spirit.
 */
export function TranscriptView({ text, onChangeText, imageUris, placeholder }: Props) {
  const { theme } = useTheme();
  const [editing, setEditing] = useState(false);

  const segments = useMemo(() => splitByMarkers(text), [text]);

  const styles = StyleSheet.create({
    container: {
      backgroundColor: theme.surface,
      borderRadius: 10,
      padding: 14,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
    },
    flowText: {
      color: theme.textPrimary,
      fontSize: 15,
      lineHeight: 22,
    },
    image: {
      width: '100%',
      height: 200,
      borderRadius: 8,
      marginVertical: 8,
      backgroundColor: theme.surfaceHover,
    },
    missingImage: {
      paddingVertical: 10,
      paddingHorizontal: 12,
      borderRadius: 8,
      backgroundColor: theme.surfaceHover,
      marginVertical: 8,
    },
    missingImageText: {
      color: theme.textMuted,
      fontSize: 13,
      fontStyle: 'italic',
    },
    editInput: {
      color: theme.textPrimary,
      fontSize: 15,
      lineHeight: 22,
      minHeight: 96,
      textAlignVertical: 'top',
    },
    toolbar: {
      flexDirection: 'row',
      justifyContent: 'flex-end',
      marginTop: 8,
    },
    toolbarBtn: {
      paddingHorizontal: 12,
      paddingVertical: 6,
      borderRadius: 6,
      backgroundColor: theme.accent + '20',
    },
    toolbarBtnText: {
      color: theme.accent,
      fontSize: 13,
      fontWeight: '600',
    },
  });

  if (editing) {
    return (
      <View style={styles.container}>
        <TextInput
          style={styles.editInput}
          value={text}
          onChangeText={onChangeText}
          placeholder={placeholder}
          placeholderTextColor={theme.textMuted}
          multiline
          autoFocus
          selectionColor={theme.accent}
          cursorColor={theme.accent}
        />
        <View style={styles.toolbar}>
          <Pressable
            onPress={() => setEditing(false)}
            style={({ pressed }) => [styles.toolbarBtn, pressed && { opacity: 0.7 }]}
          >
            <Text style={styles.toolbarBtnText}>Done</Text>
          </Pressable>
        </View>
      </View>
    );
  }

  return (
    <Pressable onPress={() => setEditing(true)}>
      <View style={styles.container}>
        {segments.length === 0 ? (
          <Text style={[styles.flowText, { color: theme.textMuted, fontStyle: 'italic' }]}>
            {placeholder || 'No transcript'}
          </Text>
        ) : (
          segments.map((seg, i) => {
            if (seg.kind === 'text') {
              return (
                <Text key={i} style={styles.flowText}>
                  {seg.text}
                </Text>
              );
            }
            // image segment
            const idx = seg.imageNumber - 1;
            const uri = imageUris && imageUris[idx];
            if (uri) {
              return <Image key={i} source={{ uri }} style={styles.image} resizeMode="cover" />;
            }
            return (
              <View key={i} style={styles.missingImage}>
                <Text style={styles.missingImageText}>[[img_{String(seg.imageNumber).padStart(3, '0')}]]</Text>
              </View>
            );
          })
        )}
        <View style={styles.toolbar}>
          <View style={styles.toolbarBtn}>
            <Text style={styles.toolbarBtnText}>Edit</Text>
          </View>
        </View>
      </View>
    </Pressable>
  );
}

type Segment = { kind: 'text'; text: string } | { kind: 'image'; imageNumber: number };

function splitByMarkers(text: string): Segment[] {
  if (!text) return [];
  const out: Segment[] = [];
  let lastIndex = 0;
  // Reset stateful regex
  MARKER_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = MARKER_RE.exec(text)) !== null) {
    if (m.index > lastIndex) {
      const t = text.slice(lastIndex, m.index).trim();
      if (t) out.push({ kind: 'text', text: t });
    }
    out.push({ kind: 'image', imageNumber: parseInt(m[1], 10) });
    lastIndex = m.index + m[0].length;
  }
  if (lastIndex < text.length) {
    const t = text.slice(lastIndex).trim();
    if (t) out.push({ kind: 'text', text: t });
  }
  return out;
}
