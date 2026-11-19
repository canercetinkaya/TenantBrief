# TenantBrief v1.1 → v2.0 İyileştirme Yol Haritası

**Amaç:** TenantBrief'i, iddia ettiği her özelliği kanıtlanabilir biçimde yerine getiren, Türkçe ve İngilizce raporu kurumsal CISO sunumuna hazır, test edilebilir ve güvenli bir araca dönüştürmek.

**Bakış açıları (her sprintte ilgili rol perspektifinden değerlendir):**
- **CISO / Yönetici:** Rapor doğru önceliği veriyor mu, karar aldırıyor mu?
- **Güvenlik mimarı:** Kontroller doğru eşleniyor mu, kapsam boşluğu görünür mü?
- **Veri mühendisi:** Veri modeli tutarlı mı, korelasyon deterministik mi?
- **Yerelleştirme uzmanı:** Türkçe doğal, tutarlı ve teknik olarak doğru mu?
- **PowerShell mühendisi / QA:** Test kapsamı, regresyon güvencesi ve lint durumu yeterli mi?
- **AppSec / tedarik zinciri:** Rapor ve araç güvenli mi; yerel yan etkiler kontrol altında mı?
- **UX / erişilebilirlik:** Rapor okunur, filtrelenebilir, yazdırılabilir ve erişilebilir mi?
- **Operasyon:** Kurulum, bağlantı, hata ve yeniden deneme davranışı öngörülebilir mi?

Her sprint şu şablonla yürütülür: `.agents/skills/tenantbrief-sprint/SKILL.md`. Metrikler: `.agents/skills/report-quality-audit/SKILL.md`. Başlangıç değerleri: `BASELINE.md`.

---

## Sprint 0 – Temel ölçüm ve iddia denetimi (kod davranışı değişmez)
**Perspektif:** QA, veri mühendisi, CISO (dürüstlük)

| ID | Görev | Kabul kriteri |
|---|---|---|
| S0.1 | Mevcut Pester setini çalıştır, sonucu kaydet. | `artifacts/pester-baseline.txt` var. Kırmızı testler varsa listelenmiş, düzeltilmemiş. |
| S0.2 | `PSScriptAnalyzerSettings.psd1` ekle ve analizi çalıştır. | Bulgu sayısı kural bazında `artifacts/pssa-baseline.txt` dosyasında. |
| S0.3 | `tools/Measure-TenantBriefQuality.ps1` yaz (Q01–Q15, `report-quality-audit` skill'indeki tanımlar). | `demo/TenantBriefReport-TR.json` üzerinde çalışıyor. Q01–Q11 değerleri `BASELINE.md` ile tutarlı ya da fark açıklanmış (demo dosyası farklı kiracıdan olabilir, bunu belirt). Kendi Pester testi var. |
| S0.4 | İddia denetimi: README, About metni, NOTICE.md, fonksiyon help'leri ↔ kod ↔ demo çıktı tablosu. | `docs/improvement/CLAIMS.md`. Örnek kontrol: "EntraFalcon", "multi-source tags", "6 unified pillars", "verified benchmark scores", "read-only". Her biri SUPPORTED / PARTIAL / UNSUPPORTED olarak etiketli ve kanıt satırı olan. |
| S0.5 | `schemas/tenantbrief-report.schema.json` taslağı (mevcut yapıyı tarif eder, henüz sıkılaştırmaz). | Demo JSON şemaya karşı doğrulanıyor. |
| S0.6 | CI'a PSScriptAnalyzer ve kalite metriği adımı ekle (şimdilik yalnızca rapor üretir, kırmızıya düşürmez). | `ci.yml` güncellendi, iş akışı yerelde `act` ile ya da push sonrası doğrulandı. Doğrulanamadıysa `DONE-UNVERIFIED`. |

**Kapsam dışı:** davranış değişikliği.

---

## Sprint 1 – Veri modeli ve gerçek korelasyon
**Perspektif:** Veri mühendisi, güvenlik mimarı

| ID | Görev | Kabul kriteri |
|---|---|---|
| S1.0 | *(v1.0.1 `hotfix/xss-htmlencode` ile tamamlandı — PR #2)* Tüm HTML çıktılarında kaçışlama: `ConvertTo-Json -Depth 12 -Compress -EscapeHandling EscapeHtml` + `U+2028`/`U+2029`, `Export-TenantBriefExecutiveSummary` `HtmlEncode`, `report-template.html` `esc()` + `data-*` `onclick` ve Playwright headless Chromium CI kapısı. | Q14 = 0, Playwright XSS = PASS (`v1.0.1`). |
| S1.1 | `data/control-crosswalk.json`: kanonik kontrol kimliği (`TB-<SÜTUN>-<AD>`) → kaynak ID listesi (ZT test ID, `SCUBA-MS.AAD.x.y`, `SCUBA-MS.SECURITYSUITE.x.y`, `MT.xxxx`, `EIDSCA.xxx`, `CIS.M365.x.y.z`, `ORCA-xxx`). Önce yüksek etkili ≥40 kontrol: legacy auth, device code, phishing-resistant MFA (tüm kullanıcılar + ayrıcalıklı roller), riskli kullanıcı/oturum engelleme, break-glass, guest davet, user consent, SSPR (yöneticiler), token protection, DKIM/DMARC/SPF, Safe Links/Attachments, audit log, external sharing… ScubaGear eski/yeni ID eşlemesi için ScubaGear `mappings/scuba-baseline-policy-migrations.csv` (71 satır olduğu testle kanıtlanır) kaynak alınır. | Her eşleme upstream kaynakla kanıtlanmış ve `source` alanında URL/dosya yolu var. Katalog doğrulama Pester testi her upstream ID'nin gerçek katalogda bulunduğunu doğrular; bulunmayan ID testi kırar. |
| S1.2 | `New-TenantBriefCorrelatedTests`: İngilizce başlık eşlemesi kaldırılır; eşleme yalnızca `data/control-crosswalk.json` üzerinden yapılır. `CanonicalId`, `Sources[]`, `CorrelatedIds[]`, `SourceStatuses{}` ve `StatusConflict` alanları eklenir. Rapor `Summary` içinde "benzersiz kontrol" (`UniqueControls`) ve "kaynak kontrol" (`SourceControls`) sayıları ayrı gösterilir. | Fixture testi: legacy auth için ZT + SCuBA + 2 Maester = 1 bulgu, 4 ID, 3 kaynak. `Q01` hedefi crosswalk'ta ilgili run'da ≥2 kaynağı bulunan kontrol sayısına eşit (bağımsız hesaplanır). Framework skorları değişmez (regresyon testi). |
| S1.3 | `$statusRank` sırası: `Failed 4 > Error 3 > Investigate 2 > Skipped/Planned 1 > Passed 0`. `Failed + Error` sonucu `Failed` ve `StatusConflict = $true`. `Planned` kayıtları skordan ve ana toplamdan dışlanıp ayrı listede tutulur. | `Error + Passed → Error`; `Failed + Error → Failed` + `StatusConflict = $true`; `Q11 = 0`. Testler yeşil. |
| S1.4 | `Pillar`/`PrimaryPillar` = `DomainPillars[0]`, `DomainPillars` dizi. Araç adı yalnızca `Sources` alanında. `EngineLabel` yeni alanına eski değer taşınır. `Resolve-TenantBriefDomainPillars` regex'ine ScubaGear 2.0 `SECURITYSUITE` (`MS.SECURITYSUITE.*`) eklenir. | Q02 = 0, Q03 = 0. `MS.SECURITYSUITE.*` doğru sütuna düşer. HTML şablonu kırılmadı. |
| S1.5 | Portal ve rol seçimi kaynak etiketine ve sütuna bağlanır (`$primaryPillar -eq 'CISA SCuBA'` vb. dallar kaldırılır). | Fixture: SCuBA EXO kontrolü → Exchange/Defender portalı. |
| S1.6 | Risk/Etki normalizasyonu: tek ölçek (`Critical/High/Medium/Low`), son kullanıcı kesinti etkisi için yeni `UserImpact` alanı eklenir (`Impact` bir sürüm boyunca `deprecated` kalır ve `CHANGELOG.md`'ye yazılır). ORCA risk seviyesi upstream `ChiValue` (`ORCA.psm1:187-195` `enum ORCACHI`: `NotRated=0, Low=5, Medium=10, High=15, VeryHigh=20, Critical=100`) üzerinden türetilir; `Critical` şemadaki `Risk` enum'una ve şablon filtre/renklerine yansıtılır. *(`PriorityScore` ve `data/scoring.json` Sprint 2 `S2.7`'ye taşındı.)* | Q04 ve gerekçesiz çelişki = 0. ORCA'da `Critical`/`High`/`Medium`/`Low` dağılımı var. |
| S1.7 | Şema sıkılaştırılır (enum'lar, zorunlu alanlar, `Risk` içinde `Critical`). Eski alanlar `deprecated` olarak işaretlenir. `Compare-TenantBriefReports` eski (`1035`) rapor ile yeni rapor arasında geriye dönük uyumlu kalır (test). | Demo JSON yeniden üretildiyse şemadan geçiyor. Eski+yeni rapor `Compare-TenantBriefReports` testi yeşil. CHANGELOG girdisi var. |

**NEEDS-LIVE-TENANT:** tam bir çalıştırma ile Q01 değerinin gerçek veride ölçülmesi.

---

## Sprint 2 – Kapsam, toplama ve operasyonel güvenilirlik
**Perspektif:** Operasyon, güvenlik mimarı

| ID | Görev | Kabul kriteri |
|---|---|---|
| S2.1 | ScubaGear 2.0.0 çağrısında tüm doğrulanmış ürünler (`aad, securitysuite, exo, powerplatform, sharepoint, teams, powerbi` — `ScubaConfigDefaults.json` `AllProductNames`). Çalışan ve atlanan ürünler manifest'e yazılır. | Birim testinde çağrı parametreleri doğrulanıyor (mock yalnızca çağrı imzası için). Q12 için `NEEDS-LIVE-TENANT`. |
| S2.2 | `Test-TenantBriefPrerequisites` (yeni, salt okunur preflight): modüller, sürümler, Graph scope'ları, EXO/SPO/Teams bağlantısı, lisans sinyalleri. Çıktı tablo halinde ve rapora "Kapsam ve kör noktalar" kartı olarak eklenir. | Bağlantı yokken bile çalışıyor ve eksikleri listeliyor. Test var. |
| S2.3 | `Connect-TenantBrief` ve `Invoke-TenantBriefBaselineCollections`: modül silme ve zorla kurma yalnızca `-AutoFixDependencies` ile. Varsayılan davranış: uyar, yapılacak komutu göster, devam et veya dur. | Varsayılan yolda `Remove-Item` ve `Install-Module` çağrılmadığını doğrulayan test (mock). README "Yerel değişiklikler" bölümü. |
| S2.4 | EntraFalcon: ya gerçekten entegre edilir (`Import-TenantBriefEntraFalconFindings` uçtan uca, framework kartı, fixture), ya da README ve About'tan "opsiyonel / deneysel" olarak düzeltilir. | Q15 = 0. Seçilen yol CLAIMS.md'de. |
| S2.5 | Planned ZT testleri skordan ve toplamdan çıkarılır, raporda "Yakında (upstream)" listesinde gösterilir. Error bulguları "Eksik izin/hata" eylem kartına dönüşür (ör. 403 → gereken Graph izni). | Q11 = 0. Fixture testi. |
| S2.6 | Diagnostics: her atlanan aşama veya ürün için yapılandırılmış kayıt (Stage, Component, Severity, Remedy). | Yönetici Özeti'nde kısmi veri uyarısı doğru tetikleniyor (test). |
| S2.7 | `PriorityScore` ağırlıklı önceliklendirme formülü ve `data/scoring.json` yapılandırma dosyası (Sprint 1 `S1.6`'dan taşındı). | Formül README'de belgelenmiş, deterministik sıralama Pester testi yeşil. |

---

## Sprint 3 – Türkçe yerelleştirme kalitesi
**Perspektif:** Yerelleştirme uzmanı, CISO

| ID | Görev | Kabul kriteri |
|---|---|---|
| S3.1 | `data/i18n/{tr,en}.json` dosyaları: tüm UI ve rapor sabit metinleri (portal adları, roller, yol haritası, etiketler) koddan sözlüğe taşınır. | EN raporda Türkçe portal adı kalmıyor (test). |
| S3.2 | `data/i18n/glossary-tr.json` ve `tests/i18n-denylist.txt`. | CI taraması var. Q09 = 0. |
| S3.3 | Çeviri önbelleği yeniden yapılandırılır: anahtar `Source|TestId`, değer `{Title, Desc, Remediation, Reviewed, Source}`. Eski önbellekten göç betiği yazılır. | Göç sonrası kayıp yok (sayım testi). |
| S3.4 | Tüm kaynaklar için TR önbelleği doldurulur (önce SCuBA 34, CIS, Maester, EIDSCA). Makine çevirisi + glossary + insan gözden geçirme listesi (`Reviewed = false`). | Q08 < 5. İnceleme bekleyen sayısı raporda ve walkthrough'da. Ajan kendi çevirisini "Reviewed = true" yapamaz. |
| S3.5 | Düzeltme metni üretimi: cümle sınırında kesme, "Learn / Related links / öğrenin" satırlarının atılması, alan adının `Remediation` olması (dile duyarlı) ve `RemediationTr` alias'ının korunması. | Q10 = 0. Fixture testleri. |
| S3.6 | `ConvertTo-TenantBriefTurkish`: ya glossary tabanlı post-processor olarak bağlanır ya da silinir. | Ölü kod kalmıyor. |

---

## Sprint 4 – Skorlama, önceliklendirme ve yönetici anlatısı
**Perspektif:** CISO, güvenlik mimarı

| ID | Görev | Kabul kriteri |
|---|---|---|
| S4.1 | Copilot Hazırlık kapı kuralları: COP-LIC-01 veya kritik Fail varken olgunluk en fazla L1, Warning yarım puan. Ağırlıklar `data/scoring.json` dosyasında. | Q13 = 0. Demo senaryosunda L1 çıkıyor (test). |
| S4.2 | Yol haritası: fazlar `PriorityScore` ile doldurulur, "Focus" metni fazdaki ilk kategorilerden üretilir, her fazda bulgu ID listesi bulunur. | Sabit Focus metni kalmıyor. Test var. |
| S4.3 | Yönetici Özeti: İlk 15 `PriorityScore` sırasına göre; Secure Score, aktif yüksek önemde olaylar, MFA kaydı ve CA kapsamı karşılaştırması, Copilot durumu, kapsam ve kör nokta kartı; SKU yoksa ROI "Uygulanamaz"; `UserCount < 25` ise "test kiracısı" bandı. | Demo üzerinde ekran görüntüsü. Her rakam JSON'daki alanla eşleşiyor (test, HTML parse). |
| S4.4 | Framework skorları korelasyon sonrası değil, kaynak bazında hesaplanmaya devam eder (ölçülen kontrol başına). Bu kural README'de açıklanır. | Skorlar S1 öncesiyle aynı kaynak sayımına dayanıyor. Fark varsa açıklanmış. |
| S4.5 | (Opsiyonel) Uyum eşlemesi: kanonik kontrolden CIS v8 / NIST CSF 2.0 / ISO 27001:2022 Ek A eşlemesi (`data/compliance-map.json`), yalnızca kaynağı gösterilebilen eşlemelerle. | Kaynaksız eşleme yok. |

---

## Sprint 5 – Uygulama güvenliği ve gizlilik
**Perspektif:** AppSec, tedarik zinciri, gizlilik

| ID | Görev | Kabul kriteri |
|---|---|---|
| S5.1 | *(Sprint 1 `S1.0`'a öne çekildi — burada regresyon ve ek XSS sertleştirme denetimi doğrulanır.)* | Q14 = 0 korunuyor. |
| S5.2 | HTML'e Content-Security-Policy meta etiketi (inline script için hash veya nonce yaklaşımı değerlendirilir), harici kaynak yok. | Rapor çevrimdışı açılıyor, CSP ihlali yok (tarayıcı konsolu ekran görüntüsü). |
| S5.3 | `-Anonymize`: yalnızca kiracı adı değil, `Result`/`Description` içindeki UPN, e-posta, GUID, domain ve görünen adlar da maskelenir. | Fixture'da bilinen 5 hassas değer çıktıda bulunmuyor (test). |
| S5.4 | `-TranslatorKey`: SecureString veya ortam değişkeni desteği. Anahtar log, manifest ve JSON'a yazılmaz. Translator'a giden veri yalnızca genel kontrol metni (kiracı verisi içermediği test edilir). | Test var. README'de veri akışı notu. |
| S5.5 | Bağımlılık sabitleme: `RequiredModules` ve minimum/maksimum sürümler, SECURITY.md, imzalama hazırlığı. | PSGallery yayın kontrol listesi. |

---

## Sprint 6 – Mimari ve test altyapısı
**Perspektif:** PowerShell mühendisi, QA

| ID | Görev | Kabul kriteri |
|---|---|---|
| S6.1 | Golden-file testleri: `tests/fixtures/raw/*` girdisinden üretilen JSON'un normalize hali `tests/golden/*.json` ile karşılaştırılır. | Refaktör öncesinde yeşil. |
| S6.2 | `TenantBrief.psm1` dosyası `Public/`, `Private/Import`, `Private/Correlation`, `Private/Scoring`, `Private/Render` klasörlerine bölünür. Davranış değişmez. | Golden testler değişmeden yeşil. Export listesi aynı. |
| S6.3 | CI: Windows ve Ubuntu matrisi (Ubuntu'da yalnızca saf fonksiyon testleri), Pester kod kapsamı raporu, PSSA ve kalite metrikleri artık **bloklayıcı**, şema doğrulaması. | CI çalıştırmasının bağlantısı walkthrough'da. Ajan push edemiyorsa `DONE-UNVERIFIED`. |
| S6.4 | Performans: 700+ bulguda Stage 4 süresi ölçülür; `+=` dizi birikimleri `List[T]` ile değiştirilir. | Önce/sonra süre ölçümü (`Measure-Command`) aynı makinede. |

---

## Sprint 7 – Rapor UX, erişilebilirlik ve trend
**Perspektif:** UX, CISO

| ID | Görev | Kabul kriteri |
|---|---|---|
| S7.1 | Erişilebilirlik: tablo başlıkları, `aria-*`, klavye gezinmesi, kontrast. | Lighthouse veya axe raporu (araç yoksa manuel kontrol listesi + ekran görüntüsü). |
| S7.2 | Sütun bazında grafikler (geçti/kaldı/atlandı) ve risk × efor ısı haritası (bağımlılıksız SVG). | Ekran görüntüsü. Rakamlar JSON ile tutarlı. |
| S7.3 | Trend: `Compare-TenantBriefReports` çıktısı HTML'de "Önceki rapora göre" sekmesi olarak gösterilir (yeni / kapanan / geriye giden kontroller, skor değişimi). | İki fixture rapor ile test. |
| S7.4 | Boyut: gömülü veri sıkıştırılır veya tekrar eden metinler sözlükleştirilir. Hedef boyut, demo için mevcut ~1,7 MB'tan anlamlı düşüş. | Önce/sonra boyut ölçümü. |
| S7.5 | Yazdırma/PDF düzeni: Yönetici Özeti A4'e sığar. | Tarayıcı yazdırma önizlemesi ekran görüntüsü. |

---

## Sürüm planı
- **v1.1:** Sprint 0–3 (doğruluk ve Türkçe)
- **v1.2:** Sprint 4–5 (anlatı ve güvenlik)
- **v2.0:** Sprint 6–7 (mimari ve UX; JSON şeması v2, deprecated alanlar kaldırılır)
