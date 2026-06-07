import { useEffect } from 'react';
import { useRouter } from 'expo-router';

/**
 * Catch-all for unmatched routes.
 * expo-share-intent passes data via skrift://dataUrl=skriftShareKey which
 * expo-router can't match. Instead of showing an error, redirect home
 * and let the useShareIntent hook handle the data.
 */
export default function NotFound() {
  const router = useRouter();

  useEffect(() => {
    router.replace('/(tabs)');
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  return null;
}
