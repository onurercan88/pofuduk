# Pofuduk — App Store Metadata (draft, Turkish)

| Field | Value |
|---|---|
| Name (30) | Pofuduk: Konuşan Hava Durumu |
| Subtitle (30) | Sevimli hava durumu arkadaşın |
| Category | Weather (secondary: Lifestyle) |
| Age rating | 4+ |
| Price | Free (no ads, no account) |
| Availability | Turkey only |
| Version | 1.0.0 |
| Languages | Turkish |
| Support URL | https://onurercan88.github.io/pofuduk/destek.html |
| Privacy policy URL | https://onurercan88.github.io/pofuduk/gizlilik.html |
| Marketing URL | https://onurercan88.github.io/pofuduk/ |

## Promotional text (170)
Pofuduk havayı senin için anlatıyor: yağmur ne zaman başlıyor, ne giymeli, yolculukta hava nasıl? Sesli, altyazılı ve çok sevimli!

## Description
Pofuduk, hava durumunu sana Türkçe anlatan sevimli bir bulut arkadaş.

• Günün havasını doğal Türkçe konuşmayla ve birebir altyazıyla anlatır
• Yağmurun ne zaman başlayacağını, ne kadar süreceğini ve ne kadar kuvvetli olacağını söyler
• "Bugün Ne Giysem?" ile hava durumuna göre kıyafet önerir ve nedenini açıklar
• "Seyahat Hava Durumu" ile gideceğin yerin havasını bulunduğun yerle karşılaştırır
• "Yağmur Başlamadan Haber Ver" bildirimleriyle şemsiyeni unutmazsın
• "Pofuduk Günaydın" ile güne hava özetiyle başlarsın
• Sorularını yazarak ya da sesli sorabilirsin: "Yarın hava nasıl?", "Akşam yağmur var mı?"
• Sesi kapalıyken de her şey yazılı olarak görünür; VoiceOver ve büyük yazı desteklenir
• Hesap yok, reklam yok; tercihlerin yalnızca cihazında saklanır

Pofuduk yalnızca gerçek tahmin verilerine dayanır ve resmi meteorolojik uyarıları kendi tahmininden asla üretmez.

## Keywords (100)
hava durumu,yağmur,şemsiye,günaydın,kıyafet,seyahat,sesli,altyazı,bulut,tahmin,rüzgar,UV

## App Privacy (nutrition label) — to confirm at submission
- Data collected by the developer: **none**. Rounded coordinates are sent to Apple Weather (WeatherKit) or the Open-Meteo fallback only to answer the request in real time; there is no account, no server and no analytics.
- Tracking: **no**.
- ⚠ Re-check if a backend is introduced (coarse location + push token would then be "collected").

## Screenshot plan (6.7" + 6.1", light; one dark)
1. Home with a sunny Pofuduk and the subtitle bubble: "Pofuduk havayı senin için anlatıyor"
2. Rainy afternoon briefing with the umbrella: "Yağmur ne zaman başlıyor, söylüyor"
3. "Bugün Ne Giysem?" screen: "Ne giyeceğini nedenleriyle öneriyor"
4. Typed or voice question with the answer: "Sor, cevaplasın"
5. Travel comparison (Bursa vs İstanbul): "Yolculukta hava nasıl?"
6. Notification settings + morning briefing: "Yağmur başlamadan haber verir"
7. Stormy dark mode with a serious Pofuduk: "Ciddi havada ciddi uyarır"

Capture these on the CI simulator (the screenshot step already produces the demo variants). Final marketing shots must come from live data, with no "Örnek veri" badge, once licensing is settled.
