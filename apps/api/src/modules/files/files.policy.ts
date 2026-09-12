/**
 * Serving policy for user-uploaded content.
 *
 * The stored MIME type is client-supplied, so it must never be echoed
 * verbatim for inline rendering — `text/html` (or SVG) served inline would
 * execute scripts on the API origin. Only a small allowlist of raster image
 * types renders inline; everything else downloads as an opaque attachment.
 */
export const INLINE_IMAGE_TYPES = new Set([
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
  'image/bmp',
]);

export interface ServingPlan {
  contentType: string;
  disposition: 'inline' | 'attachment';
}

export function normalizeMime(mimeType: string | null | undefined): string {
  return (mimeType ?? '').split(';')[0].trim().toLowerCase();
}

export function planServing(mimeType: string): ServingPlan {
  const normalized = normalizeMime(mimeType);
  if (INLINE_IMAGE_TYPES.has(normalized)) {
    return { contentType: normalized, disposition: 'inline' };
  }
  return { contentType: 'application/octet-stream', disposition: 'attachment' };
}
