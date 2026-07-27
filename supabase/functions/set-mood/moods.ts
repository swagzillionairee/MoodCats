/**
 * The 8 moods. Mood id is the array index and is stable FOREVER.
 * Adding a mood means appending to the end. Never reorder, never remove.
 *
 * >>> This table exists in two places and they must stay in sync: <<<
 *   - Swift: Shared/Mood.swift
 *   - TypeScript: this file
 *
 * The TypeScript copy is used only to build the notification body string; the mood id
 * itself is what travels in the payload, so a drift here is cosmetic rather than
 * corrupting. Fix it anyway.
 */
export interface Mood {
  readonly key: string;
  readonly label: string;
  readonly emoji: string;
}

export const MOODS: readonly Mood[] = [
  { key: "happy", label: "Happy", emoji: "😊" },
  { key: "sad", label: "Sad", emoji: "😢" },
  { key: "sleepy", label: "Sleepy", emoji: "😴" },
  { key: "angry", label: "Angry", emoji: "😠" },
  { key: "anxious", label: "Anxious", emoji: "😰" },
  { key: "chill", label: "Chill", emoji: "😎" },
  { key: "excited", label: "Excited", emoji: "🤩" },
  { key: "hungry", label: "Hungry", emoji: "🍜" },
] as const;

export const MOOD_COUNT = MOODS.length;

/** "is feeling sleepy 😴" -- the notification body. Title is the mover's name. */
export function notificationBody(moodId: number): string {
  const mood = MOODS[moodId];
  if (!mood) return "changed their mood";
  return `is feeling ${mood.key} ${mood.emoji}`;
}
