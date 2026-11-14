# Pofuduk — Product Requirements

## Vision
Pofuduk is a talking weather companion for iOS. A cute cloud character explains the day's weather in natural Turkish speech, with subtitles that match the speech word for word, expressions that follow the weather, and practical advice. It is not a grid of numbers.

## Target
- Turkish-speaking iPhone users, iOS 17+.
- Release 1 is Turkish only. The architecture is ready for more languages.
- Celsius is the default unit.

## Core experience
1. App opens → Pofuduk greets the user.
2. Location resolved (GPS → optional IP (approximate) → manual city/district).
3. Forecast fetched; hourly changes analysed.
4. MGM official warnings checked (only through an authorized source).
5. A Turkish briefing is generated from the retrieved data only.
6. Pofuduk speaks it; subtitles show exactly the spoken text.
7. The character's mood and accessories reflect the weather.

## Principles (non-negotiable)
- Never invent temperatures, dates, events or official warnings.
- "Heavy rain" requires precipitation amount/condition data, not probability alone.
- Personality never overrides facts; serious warnings are delivered calmly and clearly.
- Fully usable without sound (subtitles + transcript); accessible (VoiceOver, Dynamic Type, Reduce Motion, warning severity never by colour alone).
- Privacy first: When-In-Use location only, no continuous tracking, no audio without explicit action.
- Cached data is never presented as live; demo data is always labelled.

## Feature set
| Feature | Turkish name | Release |
|---|---|---|
| Animated character + states | Pofuduk | MVP |
| Current / hourly / daily weather | — | MVP |
| Weather briefing engine | Günlük özet | MVP |
| GPS / IP (opt-in) / manual location | Konum | MVP |
| Turkish TTS + synced subtitles | — | MVP |
| Text weather questions | Pofuduk'a sor | MVP |
| Basic clothing advice | Bugün Ne Giysem? | MVP |
| MGM link + verified warnings where authorized | MGM Uyarıları | MVP |
| Rain/weather-change notifications | Yağmur Başlamadan Haber Ver | Follow-up |
| Morning briefing | Pofuduk Günaydın | Follow-up |
| Personality styles & personalization | — | Follow-up |
| Voice questions (Speech framework) | — | Follow-up |
| Travel weather | Seyahat Hava Durumu | Follow-up |
| Multiple saved cities | — | Follow-up |
| Backend (ASP.NET Core) + APNs, air quality, widgets, more languages, optional LLM | — | Later |

Detailed behaviour for each feature follows the original project specification (sections 9–21). This file records only scope and principles; implementation details live in ARCHITECTURE.md.

## Character
A small, fluffy, pastel cloud with big expressive eyes and a soft smile. It is original and not based on any existing character.
- Moods: idle, speaking, listening, thinking, happy, surprised, warning, sad, sleeping, celebrating, error.
- Weather looks: sunny (sunglasses, sun rays), rainy (umbrella, drops, slight concern), stormy (serious, lightning), snowy (scarf, flakes), cloudy (calm), windy (sways, fluttering scarf), morning (sleepy → awake).

## Success criteria (MVP)
- The briefing for a location is accurate against provider data, and the spoken text matches the subtitles.
- The app works with sound off, in VoiceOver and at the largest Dynamic Type sizes.
- No secrets in the binary, no unauthorized MGM access, and provider terms are validated before release.
