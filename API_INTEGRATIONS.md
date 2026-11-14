# Pofuduk — API Integrations

Terms were checked on 2026-11-14 against the official pages. Check them again before release.

## WeatherAPI.com — primary (when a key is configured)
- Free plan: 100,000 calls/month, **3-day forecast**, hourly data included, alerts "Limited". **Commercial use is allowed** on Free ("free for commercial use").
- Attribution: Free users must credit WeatherAPI.com by name or logo. The app shows a "Powered by WeatherAPI.com" link in the footer.
- ⚠ Terms require showing end users a specific weather disclaimer. The app shows a generic Turkish disclaimer. **The exact required wording must be checked before release.**
- Adapter: `PofudukCore/Providers/WeatherAPIProvider.swift`. Uses `forecast.json?q=lat,lon&days=3&aqi=no&alerts=no`, maps condition codes to `WeatherCondition`, and uses max(chance_of_rain, chance_of_snow) as the precipitation probability.
- Key handling: never in source or binary. Read from the Keychain (`KeychainSecretStore`). In DEBUG builds the scheme environment variable `WEATHERAPI_KEY` is copied into the Keychain once. Production should route through the backend proxy (Phase "Further releases"), because a key inside a shipped app can be extracted.

## Open-Meteo — fallback / development
- The free API is **non-commercial only**. Apps "that have subscriptions or display advertisements" count as commercial. Limits: 600/min, 5,000/hour, 10,000/day, 300,000/month. Attribution: CC BY 4.0. The footer links to open-meteo.com.
- ⚠ Before any monetized release: buy the "API Standard" plan, self-host, or remove this provider.
- Observed 2026-11-14: requests from GitHub's shared macOS runners timed out (−1001), while the same request from a home connection worked. Don't depend on Open-Meteo from shared or cloud IPs.
- `current=` has no `uv_index` → the current UV is taken from the current hour's hourly value.
- Times are local ISO strings in the requested `timezone`. They are parsed with `LocalTimeParser` in the place's time zone, which handles DST correctly.

## Fallback & cache
- `WeatherProviderFallbackEngine`: providers are tried in order (WeatherAPI → Open-Meteo). If all fail it reports the most informative error (rate limit or bad response before a network or missing-key error).
- `CachedWeatherRepository`: a cache entry younger than 30 minutes is returned without a network call. When every provider fails, a cached forecast up to 6 hours old is returned, still marked stale (the UI badge and the briefing say "güncel olmayabilir"). Older than that, the error is shown.
- Storage: JSON files in Caches/Weather (forecast + selected place only). SwiftData is reserved for user preferences and saved places, because a cache this simple doesn't need it.

## MGM (mgm.gov.tr)
- Status: no documented, authorized machine-readable API has been verified. The app shows "unavailable" plus the official site link (`UnavailableMGMAlertRepository`). Phase 10 will investigate authorized access.

## Geocoding
- Apple `CLGeocoder` / MapKit search (no key) for manual city and destination selection (Phase 4/9).
