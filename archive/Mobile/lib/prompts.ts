import AsyncStorage from '@react-native-async-storage/async-storage';

const STORAGE_KEY = 'memory_aid_prompts';

export const DEFAULT_PROMPTS = [
  "What's on your mind?",
  'Why does it matter?',
  'What triggered this thought?',
  'Any people involved?',
  'Tags \u2014 say them out loud',
];

export async function getPrompts(): Promise<string[]> {
  try {
    const json = await AsyncStorage.getItem(STORAGE_KEY);
    if (json) {
      const parsed = JSON.parse(json);
      if (Array.isArray(parsed) && parsed.length > 0) return parsed;
    }
  } catch {}
  return DEFAULT_PROMPTS;
}

export async function setPrompts(prompts: string[]): Promise<void> {
  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(prompts));
}

export async function resetPrompts(): Promise<void> {
  await AsyncStorage.removeItem(STORAGE_KEY);
}
