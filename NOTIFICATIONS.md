# Pofuduk — Notifications

## What the app does today (local, on device)
1. Each time a **fresh** forecast is loaded (foreground, or a background refresh), `RainNotificationEngine` plans notifications:
   - rain/snow soon (lead time and minimum probability set by the user), heavy rain (from amounts only), thunderstorms, strong wind, a big day-to-day temperature change, and verified MGM warnings
   - only within **6 h of when the forecast was retrieved**, and never from a stale forecast
   - quiet hours are respected; only orange/red official MGM warnings break through
   - a delivery log stops anything already delivered from being sent again (a pending notification may be replaced by a newer forecast)
   - every message states its source ("Kaynak: Open-Meteo.com tahmini, saat 13.00 itibarıyla" / "Kaynak: MGM (resmi uyarı)")
2. `UNUserNotificationCenter` schedules them as local notifications. Each new plan replaces all pending Pofuduk notifications.
3. `BGAppRefreshTask` (`com.pofuduk.app.refresh`, earliest 1 h after backgrounding) fetches a new forecast for the **last used place** (stored coarsened to ~1 km; location is never requested in the background) and replans.

## Limits of local scheduling (by design, not a bug)
- iOS decides **if and when** a background refresh runs (usage patterns, battery, Low Power Mode). It can be hours late or not run at all.
- A notification scheduled at 13:00 for rain at 14:00 is based on the 13:00 forecast. If the forecast changes and no refresh runs, the notification can be wrong. The 6-hour horizon and the source/time in the message limit this.
- Turning notifications off, or a stale forecast, cancels everything pending.

## Reliable delivery: optional backend + APNs (future)
| | Local (now) | Backend + APNs (later) |
|---|---|---|
| Forecast freshness | When the app or iOS runs a refresh | Server checks every N minutes |
| Timing | Best effort | Server-controlled, near real time |
| Works if the app isn't opened for days | Rarely | Yes |
| Needs | Nothing | ASP.NET Core service, APNs key, device token, a server-side place per subscription |
| Privacy | Everything on device | Coarse location + token on the server (needs consent and a privacy update) |

The backend would reuse the same rules (thresholds, quiet hours, dedup keys), so both paths produce the same messages.
