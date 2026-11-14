# Pofuduk — API Integrations

> Terms below are **unverified** until Phase 3/10 validation. Everything marked ⚠ must be checked against the provider's current official terms before release.

## WeatherAPI.com
- Use: primary candidate (current, hourly, daily, astro, alerts; IP lookup only on explicit user choice).
- ⚠ Verify: free-plan call limits, forecast-day limit on free tier, commercial/App Store use, attribution requirement.
- Key handling: requires API key → must not ship in the binary. Options: backend proxy (preferred for release) or user-supplied key in Keychain for development.

## Open-Meteo
- Use: development provider and alternative (no key).
- ⚠ Free API is documented for **non-commercial** use; commercial App Store distribution likely requires a paid plan or self-hosting. Attribution (CC BY 4.0) required.

## MGM (mgm.gov.tr)
- Need: official warnings (level, area, description, validity, source link).
- Status: no documented, authorized machine-readable API verified yet. Undocumented internal endpoints and scraping are **not** used.
- Fallback: `MGMWarningProvider` returns `.unavailable`; the UI shows the official MGM warning page link (exact URL to be verified in Phase 10).
- Path forward: request authorized access from MGM, or use a licensed redistributor.

## Geocoding
- Apple `CLGeocoder` / MapKit search (no key) for destinations and manual city selection.
