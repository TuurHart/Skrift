/**
 * Utilities for handling shared content in the capture flow.
 */

export type UrlMetadata = {
  title: string | null;
  description: string | null;
  thumbnailUrl: string | null;
};

/**
 * Fetch page title and Open Graph metadata from a URL.
 * Returns nulls on any failure — never throws.
 */
export async function fetchUrlMetadata(url: string): Promise<UrlMetadata> {
  const empty: UrlMetadata = { title: null, description: null, thumbnailUrl: null };
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    const res = await fetch(url, {
      signal: controller.signal,
      headers: { 'User-Agent': 'Skrift/1.0' },
    });
    clearTimeout(timeout);

    if (!res.ok) return empty;

    // Only read first 50KB to avoid downloading huge pages
    const text = await res.text();
    const head = text.slice(0, 50000);

    // Extract OG tags and <title>
    const ogTitle = head.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']/i)?.[1]
      ?? head.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']/i)?.[1];
    const htmlTitle = head.match(/<title[^>]*>([^<]+)<\/title>/i)?.[1];
    const ogDesc = head.match(/<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']/i)?.[1]
      ?? head.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:description["']/i)?.[1];
    const ogImage = head.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i)?.[1]
      ?? head.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i)?.[1];

    return {
      title: ogTitle ?? htmlTitle?.trim() ?? null,
      description: ogDesc ?? null,
      thumbnailUrl: ogImage ?? null,
    };
  } catch {
    return empty;
  }
}

/**
 * Extract domain from a URL for display.
 */
export function extractDomain(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return url;
  }
}
