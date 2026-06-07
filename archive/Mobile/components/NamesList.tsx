import { useEffect, useMemo, useState } from 'react';
import { View, Text, TextInput, Pressable, StyleSheet, Alert } from 'react-native';
import { useTheme } from '../contexts/ThemeContext';
import { loadNames, upsertPerson, deletePerson, searchPeople, type Person } from '../lib/names';
import * as haptics from '../lib/haptics';

/**
 * Mobile equivalent of frontend-new/src/features/settings/NamesTab.tsx.
 *
 * - Search box appears once you have more than ~5 people.
 * - Each person is an expandable row with canonical, short, and editable
 *   alias chips.
 * - Add / delete bumps the local `lastModifiedAt` so the next memo-sync
 *   propagates it to the Mac.
 */
export function NamesList() {
  const { theme } = useTheme();
  const [people, setPeople] = useState<Person[]>([]);
  const [query, setQuery] = useState('');
  const [refreshTick, setRefreshTick] = useState(0);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const data = await loadNames();
      if (cancelled) return;
      setPeople(data.people.filter((p) => !p.deleted));
    })();
    return () => {
      cancelled = true;
    };
  }, [refreshTick]);

  const filtered = useMemo(() => searchPeople(people, query), [people, query]);

  async function handleSave(person: Person, original?: Person) {
    await upsertPerson({
      canonical: person.canonical,
      aliases: person.aliases,
      short: person.short,
    });
    setRefreshTick((t) => t + 1);
    void original;
  }

  async function handleDelete(canonical: string) {
    Alert.alert('Delete person?', 'This removes the entry from sync — it will tombstone for 90 days.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          haptics.warning();
          await deletePerson(canonical);
          setRefreshTick((t) => t + 1);
        },
      },
    ]);
  }

  function handleAdd() {
    haptics.tap();
    setPeople((prev) => [
      ...prev,
      {
        canonical: '',
        aliases: [],
        short: null,
        lastModifiedAt: new Date().toISOString(),
      } as Person,
    ]);
  }

  const styles = StyleSheet.create({
    container: { gap: 10 },
    headerRow: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    headerText: {
      fontSize: 12,
      color: theme.textMuted,
      fontWeight: '600',
      textTransform: 'uppercase',
      letterSpacing: 0.6,
    },
    addBtn: {
      paddingHorizontal: 10,
      paddingVertical: 6,
      borderRadius: 8,
      backgroundColor: theme.accent + '20',
    },
    addBtnText: {
      color: theme.accent,
      fontSize: 12,
      fontWeight: '600',
    },
    search: {
      backgroundColor: theme.surface,
      borderRadius: 10,
      paddingHorizontal: 12,
      paddingVertical: 10,
      fontSize: 14,
      color: theme.textPrimary,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
    },
    empty: {
      paddingVertical: 24,
      alignItems: 'center',
    },
    emptyText: {
      fontSize: 13,
      color: theme.textMuted,
    },
  });

  return (
    <View style={styles.container}>
      <View style={styles.headerRow}>
        <Text style={styles.headerText}>People ({people.length})</Text>
        <Pressable onPress={handleAdd} style={({ pressed }) => [styles.addBtn, pressed && { opacity: 0.7 }]}>
          <Text style={styles.addBtnText}>+ Add</Text>
        </Pressable>
      </View>

      {people.length > 5 && (
        <TextInput
          style={styles.search}
          value={query}
          onChangeText={setQuery}
          placeholder="Search names or aliases…"
          placeholderTextColor={theme.textMuted}
          autoCapitalize="none"
          autoCorrect={false}
          selectionColor={theme.accent}
        />
      )}

      {people.length === 0 && (
        <View style={styles.empty}>
          <Text style={styles.emptyText}>No people yet. Tap "Add" to create one.</Text>
        </View>
      )}

      {filtered.length === 0 && people.length > 0 && query.trim() !== '' && (
        <View style={styles.empty}>
          <Text style={styles.emptyText}>No matches for "{query.trim()}".</Text>
        </View>
      )}

      {filtered.map((p, i) => (
        <PersonRow
          key={p.canonical || `new-${i}`}
          person={p}
          onSave={(updated) => handleSave(updated, p)}
          onDelete={() => p.canonical && handleDelete(p.canonical)}
        />
      ))}
    </View>
  );
}

// ─────────────────────────────────────────────────────────────────────

function PersonRow({
  person,
  onSave,
  onDelete,
}: {
  person: Person;
  onSave: (next: Person) => void;
  onDelete: () => void;
}) {
  const { theme } = useTheme();
  const [expanded, setExpanded] = useState(!person.canonical);
  const [canonical, setCanonical] = useState(stripBrackets(person.canonical));
  const [short, setShort] = useState(person.short ?? '');
  const [aliases, setAliases] = useState(person.aliases);
  const [aliasInput, setAliasInput] = useState('');

  const dirty =
    stripBrackets(person.canonical) !== canonical.trim() ||
    (person.short ?? '') !== short.trim() ||
    !arraysEqual(person.aliases, aliases);

  function addAlias() {
    const v = aliasInput.trim();
    if (!v) return;
    if (aliases.includes(v)) {
      setAliasInput('');
      return;
    }
    setAliases([...aliases, v]);
    setAliasInput('');
  }

  function removeAlias(a: string) {
    setAliases(aliases.filter((x) => x !== a));
  }

  function commit() {
    const trimmed = canonical.trim();
    if (!trimmed) return;
    onSave({
      ...person,
      canonical: `[[${trimmed}]]`,
      aliases,
      short: short.trim() || null,
    });
  }

  const styles = StyleSheet.create({
    row: {
      backgroundColor: theme.surface,
      borderRadius: 10,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
      overflow: 'hidden',
    },
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingHorizontal: 14,
      paddingVertical: 12,
      gap: 10,
    },
    chevron: {
      fontSize: 12,
      color: theme.textMuted,
      width: 12,
    },
    title: {
      flex: 1,
      fontSize: 14,
      color: theme.textPrimary,
      fontWeight: '500',
    },
    aliasCount: {
      fontSize: 11,
      color: theme.textMuted,
    },
    body: {
      paddingHorizontal: 14,
      paddingBottom: 12,
      gap: 10,
      borderTopWidth: StyleSheet.hairlineWidth,
      borderTopColor: theme.border,
      paddingTop: 12,
    },
    label: {
      fontSize: 11,
      color: theme.textMuted,
      textTransform: 'uppercase',
      letterSpacing: 0.4,
    },
    input: {
      backgroundColor: theme.bg,
      borderRadius: 8,
      paddingHorizontal: 10,
      paddingVertical: 8,
      fontSize: 13,
      color: theme.textPrimary,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
    },
    aliasChipsRow: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: 6,
    },
    aliasChip: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 6,
      paddingHorizontal: 10,
      paddingVertical: 4,
      borderRadius: 14,
      backgroundColor: theme.surfaceHover,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: theme.border,
    },
    aliasChipText: {
      fontSize: 12,
      color: theme.textPrimary,
    },
    aliasChipX: {
      fontSize: 14,
      color: theme.textMuted,
      lineHeight: 14,
    },
    aliasInputRow: {
      flexDirection: 'row',
      gap: 8,
    },
    actionRow: {
      flexDirection: 'row',
      gap: 10,
      marginTop: 6,
    },
    saveBtn: {
      flex: 1,
      paddingVertical: 10,
      borderRadius: 8,
      backgroundColor: theme.accent,
      alignItems: 'center',
    },
    saveBtnDisabled: {
      opacity: 0.4,
    },
    saveBtnText: {
      color: '#fff',
      fontSize: 13,
      fontWeight: '600',
    },
    deleteBtn: {
      paddingHorizontal: 14,
      paddingVertical: 10,
      borderRadius: 8,
      backgroundColor: theme.destructive + '20',
      alignItems: 'center',
    },
    deleteBtnText: {
      color: theme.destructive,
      fontSize: 13,
      fontWeight: '600',
    },
  });

  return (
    <View style={styles.row}>
      <Pressable
        onPress={() => setExpanded((e) => !e)}
        style={({ pressed }) => [styles.header, pressed && { opacity: 0.7 }]}
      >
        <Text style={styles.chevron}>{expanded ? '▾' : '▸'}</Text>
        <Text style={styles.title}>{stripBrackets(person.canonical) || 'New person'}</Text>
        <Text style={styles.aliasCount}>{aliases.length} alias{aliases.length === 1 ? '' : 'es'}</Text>
      </Pressable>

      {expanded && (
        <View style={styles.body}>
          <Text style={styles.label}>Canonical name</Text>
          <TextInput
            style={styles.input}
            value={canonical}
            onChangeText={setCanonical}
            placeholder="Full Name"
            placeholderTextColor={theme.textMuted}
            autoCapitalize="words"
            autoCorrect={false}
            selectionColor={theme.accent}
          />

          <Text style={styles.label}>Short (used for repeat mentions)</Text>
          <TextInput
            style={styles.input}
            value={short}
            onChangeText={setShort}
            placeholder={canonical.split(' ')[0] || 'First name'}
            placeholderTextColor={theme.textMuted}
            autoCapitalize="words"
            autoCorrect={false}
            selectionColor={theme.accent}
          />

          <Text style={styles.label}>Aliases</Text>
          <View style={styles.aliasChipsRow}>
            {aliases.map((a) => (
              <Pressable key={a} onPress={() => removeAlias(a)} style={styles.aliasChip}>
                <Text style={styles.aliasChipText}>{a}</Text>
                <Text style={styles.aliasChipX}>×</Text>
              </Pressable>
            ))}
          </View>
          <View style={styles.aliasInputRow}>
            <TextInput
              style={[styles.input, { flex: 1 }]}
              value={aliasInput}
              onChangeText={setAliasInput}
              onSubmitEditing={addAlias}
              placeholder="Add alias and press return"
              placeholderTextColor={theme.textMuted}
              autoCapitalize="none"
              autoCorrect={false}
              selectionColor={theme.accent}
            />
          </View>

          <View style={styles.actionRow}>
            <Pressable
              disabled={!dirty || !canonical.trim()}
              onPress={commit}
              style={({ pressed }) => [
                styles.saveBtn,
                (!dirty || !canonical.trim()) && styles.saveBtnDisabled,
                pressed && { opacity: 0.7 },
              ]}
            >
              <Text style={styles.saveBtnText}>{dirty ? 'Save' : 'Saved'}</Text>
            </Pressable>
            {person.canonical && (
              <Pressable onPress={onDelete} style={({ pressed }) => [styles.deleteBtn, pressed && { opacity: 0.7 }]}>
                <Text style={styles.deleteBtnText}>Delete</Text>
              </Pressable>
            )}
          </View>
        </View>
      )}
    </View>
  );
}

function stripBrackets(s: string): string {
  if (!s) return '';
  if (s.startsWith('[[') && s.endsWith(']]')) return s.slice(2, -2);
  return s;
}

function arraysEqual(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}
