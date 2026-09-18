import { getYoutubeVideoId } from '../lib/minihome.ts';

const cases = new Map([
  ['https://youtu.be/dQw4w9WgXcQ', 'dQw4w9WgXcQ'],
  ['https://www.youtube.com/watch?v=dQw4w9WgXcQ', 'dQw4w9WgXcQ'],
  ['https://youtube.com/shorts/dQw4w9WgXcQ', 'dQw4w9WgXcQ'],
  ['not-a-url', ''],
]);

for (const [input, expected] of cases) {
  const actual = getYoutubeVideoId(input);
  if (actual !== expected) throw new Error(`${input}: expected ${expected}, received ${actual}`);
}

console.log(`refactor self-check passed (${cases.size} cases)`);
