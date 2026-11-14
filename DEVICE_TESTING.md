# Pofuduk — iPhone'da Test Rehberi

Uygulamayı gerçek bir iPhone'a kurmanın iki yolu var. Mac'in yoksa **Yol B**'yi kullan.

---

## Yol A — Bir Mac ile (ücretsiz, en hızlı)
Ödünç bir Mac de olur. Ücretsiz Apple hesabıyla kurulan uygulama **7 gün** çalışır, sonra yeniden kurman gerekir.

1. **Mac'te hazırlık**
   1. App Store'dan **Xcode**'u kur ve bir kez aç (ek bileşenleri yüklemesine izin ver).
   2. Terminal'de: `brew install xcodegen` (Homebrew yoksa önce https://brew.sh).
   3. Projeyi indir: `git clone https://github.com/onurercan88/pofuduk.git && cd pofuduk`
   4. Xcode projesini oluştur: `xcodegen generate`, ardından `open Pofuduk.xcodeproj`
2. **İmzalama**
   1. Xcode › Settings › Accounts › "+" ile Apple ID'nle giriş yap.
   2. Sol panelde **Pofuduk** projesi › **Pofuduk** hedefi › *Signing & Capabilities*:
      - "Automatically manage signing" açık olsun, Team olarak kendi adını seç.
      - Bundle Identifier'ı benzersiz yap (ör. `com.pofuduk.app.<adın>`). Ücretsiz hesap aynı kimliği başkasıyla paylaşamaz.
3. **iPhone'u hazırla**
   1. iPhone'u kabloyla Mac'e bağla, "Bu bilgisayara güven" de.
   2. iPhone › Ayarlar › Gizlilik ve Güvenlik › **Geliştirici Modu**'nu aç (telefon yeniden başlar).
4. **Kur ve çalıştır**
   1. Xcode'un üst çubuğunda hedef cihaz olarak iPhone'unu seç, ▶︎ (Run) bas.
   2. İlk açılışta "Güvenilmeyen geliştirici" uyarısı çıkarsa: iPhone › Ayarlar › Genel › VPN ve Cihaz Yönetimi › kendi Apple ID'n › **Güven**.

> Yalnızca Yol A'da: Xcode › Debug › **Simulate Background Fetch** ile arka plan yenilemesini anında tetikleyebilirsin (bildirim testi için).

---

## Yol B — Mac olmadan, TestFlight ile
Uygulama GitHub Actions'taki macOS makinesinde derlenir ve TestFlight'a yüklenir. Sen iPhone'a TestFlight uygulamasından kurarsın.

1. **Apple Developer Program**'a katıl (https://developer.apple.com/programs/ — yıllık 99 USD). App Store yayını için zaten gerekli.
2. **App Store Connect**'te (https://appstoreconnect.apple.com):
   1. Apps › "+" › New App: platform iOS, ad "Pofuduk", Bundle ID `com.pofuduk.app` (önce developer.apple.com › Identifiers bölümünde oluştur).
   2. Users and Access › Integrations › **App Store Connect API** › yeni anahtar oluştur (rol: App Manager). **Issuer ID**, **Key ID** ve indirilen **.p8** dosyasını sakla. .p8 dosyası yalnızca bir kez indirilebilir.
3. **GitHub'a gizli değer olarak ekle** (repo › Settings › Secrets and variables › Actions):
   - `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_PRIVATE_KEY` (.p8 dosyasının içeriği), `APPLE_TEAM_ID`.
   - Bu değerleri sohbete yazma; doğrudan GitHub ekranına gir.
4. **Bana haber ver:** TestFlight'a yükleyen CI adımını (arşivleme ve yükleme) ben eklerim. Bu adım henüz projede yok.
5. iPhone'a **TestFlight** uygulamasını kur. App Store Connect › TestFlight › Internal Testing'e kendini ekle. Gelen davetle Pofuduk'u kur.

---

## Testten önce (her iki yol için)
- **Türkçe ses:** iPhone › Ayarlar › Erişilebilirlik › Seslendirilen İçerik › Sesler › **Türkçe** › kaliteli bir sesi ("Gelişmiş" veya "Premium") indir. İndirilmezse uygulama sadece altyazı gösterir.
- Telefonun sesini aç, sessiz modu kapat.
- Konum, mikrofon ve bildirim izinlerini **ilk kez** test etmek için uygulamayı silip yeniden kur.

---

## Test listesi
Her adımda ✅ veya ❌ işaretle. ❌ olanlar için aşağıdaki "Hata bildirirken" bölümüne bak.

### 1. İlk açılış ve konum
| # | Adım | Beklenen |
|---|---|---|
| 1.1 | Uygulamayı ilk kez aç | Önce Pofuduk'un "Neredesin?" açıklaması çıkar, iOS izin penceresi **henüz çıkmaz** |
| 1.2 | "Konumumu kullan" | iOS'un "Uygulamayı Kullanırken" izni sorulur. "Her zaman" seçeneği **yoktur** |
| 1.3 | İzin ver | Başlıkta ilçen ve ilin görünür (ör. "Kadıköy, İstanbul"), gerçek hava gelir, "Örnek veri" etiketi **yoktur** |
| 1.4 | Uygulamayı sil, kur, bu sefer izni **reddet** | "Konumunu bulamadım" ekranı: "Ayarlardan izin ver" ve "Şehir veya ilçe seç" çıkar |
| 1.5 | "Şehir veya ilçe seç" › bir il seç | O ilin havası gelir |
| 1.6 | Arama kutusuna bir ilçe yaz (ör. "Bodrum") | İlçe sonuçları listelenir, seçince o ilçenin havası gelir |
| 1.7 | Başlıktaki konum adına dokun | Konum seçme ekranı açılır |

### 2. Konuşma ve altyazı
| # | Adım | Beklenen |
|---|---|---|
| 2.1 | Açılışta | Pofuduk Türkçe konuşur, ağzı hareket eder, altyazı konuşmayla **aynı** cümleyi gösterir, söylenen kelime vurgulanır |
| 2.2 | Duraklat › Devam et › Durdur | Konuşma ve altyazı birlikte durur ve devam eder. Durunca son cümle ekranda kalır |
| 2.3 | Konuşurken biri seni arasın (ya da Siri'yi aç) | Konuşma duraklar, kendiliğinden devam etmez |
| 2.4 | Hoparlör düğmesiyle sesi kapat | Konuşma durur, metnin tamamı yazılı görünür |
| 2.5 | Ayarlar › Ses › Türkçe ses, Konuşma hızı › "Sesi dene" | Seçilen ses ve hız duyulur |
| 2.6 | "Tüm metin" | Konuşmanın tamamı okunabilir |

### 3. Soru sorma
| # | Adım | Beklenen |
|---|---|---|
| 3.1 | Yazarak sor: "Yarın hava nasıl?" | "Yarın …'da hava …" diye cevap verir, konuşur ve altyazı gösterir |
| 3.2 | Ardından: "Peki yağmur var mı?" | Cevap hâlâ **yarın** için olur |
| 3.3 | Mikrofon düğmesine ilk kez dokun | Mikrofon ve konuşma tanıma izni **o anda** sorulur |
| 3.4 | Sesli sor: "Bugün ne giysem?" | Pofuduk dinleme yüzüne geçer, sorun metin kutusunda görünür, cevap gelir |
| 3.5 | "Yarın Bursa'ya gideceğim" | Bursa'nın havası bulunduğun yerle karşılaştırılır |

### 4. Kıyafet ve seyahat
| # | Adım | Beklenen |
|---|---|---|
| 4.1 | "Bugün Ne Giysem?" kartı | Öneriler, "Neden bu öneri?" bölümü ve Bugün/Yarın seçimi |
| 4.2 | "Seyahat Hava Durumu" › bir yer ara › tarih seç | Günlük satırlar, "Yanına al" listesi, yol durumu bilgisi verilmediğine dair not |

### 5. Bildirimler ve Günaydın
| # | Adım | Beklenen |
|---|---|---|
| 5.1 | Ayarlar › Bildirimler › "Hava bildirimleri" aç | iOS bildirim izni **o anda** sorulur |
| 5.2 | Yağmur beklenen bir günde "Planlanan bildirimler" listesine bak | Yağmurdan seçtiğin süre kadar önce bir bildirim görünür |
| 5.3 | Planlanan saati bekle (uygulama kapalı olabilir) | Bildirim gelir; metinde "Kaynak: … tahmini" yazar |
| 5.4 | Sessiz saatleri şu anki saati kapsayacak şekilde ayarla | Yeni yağmur bildirimleri planlanmaz |
| 5.5 | Pofuduk Günaydın › Özel saat › 2 dakika sonrası, "Bildirim olarak da gönder" açık | O saatte "Günaydın! ☀️" bildirimi gelir |
| 5.6 | O saatten sonra (öğlene kadar) uygulamayı aç | "Günaydın!" ile başlayan özet bir kez anlatılır, tekrar açınca anlatılmaz |

> Not: iOS arka plan yenilemesini ne zaman çalıştıracağına kendisi karar verir. Bildirimlerin birkaç dakika gecikmesi ya da hiç yenileme olmaması **hata değildir** (bkz. NOTIFICATIONS.md).

### 6. Erişilebilirlik
| # | Adım | Beklenen |
|---|---|---|
| 6.1 | VoiceOver'ı aç ve ekranı baştan sona gez | Her düğme Türkçe adlandırılmış, karakter "Güneş gözlüklü, mutlu Pofuduk" gibi tarif ediliyor |
| 6.2 | Ayarlar › Ekran ve Parlaklık › Metin Boyutu en büyük (Erişilebilirlik › Daha Büyük Metin) | Yazılar büyür, kesilen metin olmaz |
| 6.3 | Hareketi Azalt'ı aç | Animasyonlar durur, karakterin gözleri açık kalır |
| 6.4 | Karanlık mod | Tüm yazılar okunur |

### 7. Hata durumları ve gizlilik
| # | Adım | Beklenen |
|---|---|---|
| 7.1 | Uçak modunda uygulamayı aç (daha önce veri yüklenmişti) | Eski veri gösterilir, "güncel olmayabilir" yazar |
| 7.2 | Uçak modunda, hiç veri yokken | "Hava durumu alınamadı" ve "Tekrar dene" |
| 7.3 | Ayarlar › Gizlilik › "Verilerimi sil" | Onay sorulur; sonra konum yeniden sorulur, ayarlar varsayılana döner |

---

## Hata bildirirken
Bana şunları yaz:
- iPhone modeli ve iOS sürümü
- Test numarası (ör. 3.2)
- Ne yaptın, ne bekledin, ne oldu
- Ekran görüntüsü veya ekran kaydı (Denetim Merkezi › Ekran Kaydı)
