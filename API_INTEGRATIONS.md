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
- A free, ad-free release without in-app purchases very likely counts as non-commercial; confirm with info@open-meteo.com before submission. Once ads, subscriptions or a paid version are added: buy the "API Standard" plan (separate endpoint plus key) or self-host.
- Observed 2026-11-14: requests from GitHub's shared macOS runners timed out (−1001), while the same request from a home connection worked. Don't depend on Open-Meteo from shared or cloud IPs.
- `current=` has no `uv_index` → the current UV is taken from the current hour's hourly value.
- Times are local ISO strings in the requested `timezone`. They are parsed with `LocalTimeParser` in the place's time zone, which handles DST correctly.

## Fallback & cache
- `WeatherProviderFallbackEngine`: providers are tried in order (WeatherAPI → Open-Meteo). If all fail it reports the most informative error (rate limit or bad response before a network or missing-key error).
- `CachedWeatherRepository`: a cache entry younger than 30 minutes is returned without a network call. When every provider fails, a cached forecast up to 6 hours old is returned, still marked stale (the UI badge and the briefing say "güncel olmayabilir"). Older than that, the error is shown.
- Storage: JSON files in Caches/Weather (forecast + selected place only). SwiftData is reserved for user preferences and saved places, because a cache this simple doesn't need it.

## MGM (mgm.gov.tr) — official warnings
**Findings (2026-11-14):**
- Official warning page: https://www.mgm.gov.tr/meteouyari/turkiye.aspx (an HTML map; this is the app's fallback link).
- No documented public API, RSS or CAP feed for warnings. MEVBİS and "Ücretli Ürünler" are MGM's data sales channels.
- The legal notice (https://www.mgm.gov.tr/site/yasal-uyari.aspx) forbids copying or redistributing content "önceden izin alınmadan ve kaynak gösterilmeden" (without prior permission and without citing the source). So scraping is not an option.
- MeteoAlarm (EUMETNET, CC BY 4.0) does **not** include Turkey; the Turkey feed URLs return 404.

**Implementation:**
- `ConfiguredMGMWarningProvider` reads `MGMWarningFeedURL` from Info.plist (empty by default). When empty it returns `.unavailable` with the official page. A failed feed is also `.unavailable`, never "no warnings".
- `CAPWarningParser`: CAP 1.2 (the WMO standard). Turkish `<info>` is preferred; the MeteoAlarm-style `awareness_level` is used, else CAP severity (Moderate → yellow, Severe → orange, Extreme → red).
- `WeatherAlertMatcher`: active, yellow or higher, province matched ignoring Turkish letters, district-specific warnings only if the district matches.
- Forecasts are never turned into official warnings (no code path does this).

**To enable:** write to MGM (or buy through MEVBİS) asking for written permission to show official warnings in a mobile app, plus a machine-readable (ideally CAP) feed. Once permission is granted, set `MGMWarningFeedURL` in `project.yml`.

Draft request (Turkish):
> Konu: Pofuduk mobil uygulamasında MGM meteorolojik uyarılarının gösterilmesi için izin talebi
> Sayın Yetkili, geliştirdiğimiz "Pofuduk" iOS hava durumu uygulamasında, kullanıcının bulunduğu il/ilçe için yayımlanan MGM meteorolojik uyarılarını (seviye, bölge, geçerlilik süresi, açıklama) kaynak göstererek ve resmi sayfanıza bağlantı vererek göstermek istiyoruz. Bu amaçla kullanılabilecek resmi, makine tarafından okunabilir bir veri kaynağı (tercihen CAP formatında) olup olmadığını ve kullanım koşullarını bildirmenizi rica ederiz. Saygılarımızla.

## Geocoding
- Apple `CLGeocoder` / MapKit search (no key) for manual city and destination selection (Phase 4/9).
