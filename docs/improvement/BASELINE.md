# Başlangıç ölçümleri (baseline)

**Kaynak:** `cnrctnky.onmicrosoft.com_20261119_1035` çalışmasının `TenantBriefReport-TR.json` çıktısı (modül 1.0.0, PowerShell 7.7.0, commit `d41e7ff` dönemi). Değerler Python ile hesaplandı. Sprint 0'da `tools/Measure-TenantBriefQuality.ps1` aynı değerleri **yeniden üretmeli**. Üretemiyorsa fark araştırılır.

> Not: Bu bir lab kiracısıdır (`UserCount = 1`). Kiracıya özgü yüzdeler genellenemez. Burada yalnızca **aracın veri kalitesi** ölçülür.

| Kod | Metrik | Değer |
|---|---|---|
| — | Toplam bulgu | 700 (Passed 162, Failed 272, Investigate 36, Skipped 194, Planned 35, Error 1) |
| Q01 | Birden fazla kaynağı olan bulgu | **0** |
| Q02 | `Pillar` 6 sütun dışında (araç adı veya birleşik değer) | **374** |
| Q03 | `DomainPillar` virgülle birleşik | 33 |
| Q04 | Risk=High ve Impact=Düşük | **142** |
| Q06 | `ImplementationCost = Unknown` | 100 (ORCA 66 + SCuBA 34) |
| Q07 | Failed ve `MinimumLicense` boş | 130 |
| Q08 | TR başlıkta İngilizce kalıp | 164 (Maester 85, CIS 38, SCuBA 34, EIDSCA 4, ORCA 2, ZT 1) |
| Q09 | Yasak kelime ("tasdiqi") | 1 |
| Q10 | "..." ile kesilmiş düzeltme | 77; "öğrenin/Learn/Related links" artığı 10 |
| Q11 | Planned bulgular | 35 ("Planned for future release" ZT testleri) |
| Q12 | SCuBA kategori dağılımı | yalnızca `AAD` (34/34) |
| Q13 | Copilot hazırlık | Skor 50 / "L2 – Tekrarlanabilir"; COP-LIC-01 = Fail, COP-ENTRA-01 = Fail |
| Q15 | README/About'ta "EntraFalcon" iddiası var, `Frameworks` içinde EntraFalcon yok | uyumsuz |

## Koddan tespit edilen kök nedenler (doğrulanmalı)
- `New-TenantBriefCorrelatedTests`: eşleşme anahtarı İngilizce başlığın normalize hali (`$normTitle`). Farklı motorlar aynı kontrolü farklı ifade ettiği için eşleşme olmuyor.
- `New-TenantBriefCorrelatedTests`: `$statusRank` içinde `'Error'` yok. Değeri 0 sayılıyor, yani Passed ile aynı ağırlıkta.
- `New-TenantBriefFindings`: `Pillar/PrimaryPillar`, `TestPillar` (araç etiketi) alanından; 6 sütun ise `DomainPillar` alanında. Portal ve rol seçimi kısmen `$primaryPillar` alanına bakıyor.
- `Import-TenantBriefOrcaResults`: `TestRisk` ve `TestImpact` sabit `'Medium'`.
- `Import-TenantBriefScubaResults`: Risk ve Impact Shall/Should'tan geliyor, ancak ZT Impact değerleri farklı bir ölçekle geliyor.
- Çeviri: `tr-translation-cache.json` yalnızca `-TranslatorKey` ile ve `TestId` anahtarıyla doluyor. `ConvertTo-TenantBriefTurkish` tanımlı ama çağrılmıyor (doğrula).
- Düzeltme metni `New-TenantBriefFindings` içinde 160 karakterde kesiliyor. Portal adları dilden bağımsız olarak Türkçe sabit.
- `Get-TenantBriefCopilotReadiness`: skor = Pass/Toplam; kapı (gate) yok.
- `Export-TenantBriefExecutiveSummary`: İlk 15 sıralaması maliyet ve ID'ye göre. `Title`, `Category` ve düzeltme metni HTML'e kaçışlanmadan gömülüyor. EN sürümde düzeltme yerine `Description` kullanılıyor.
- Yol haritası "Focus" metinleri sabit yazılmış.
- `Connect-TenantBrief`: kullanıcı profilindeki Graph ve SPO modül sürümlerini `Remove-Item` ile siliyor, modülleri `-Force -AllowClobber` ile kuruyor. Bunlar "salt okunur" algısıyla çelişen yerel yan etkiler.
- CI (`.github/workflows/ci.yml`) yalnızca Pester çalıştırıyor. Lint, şema ve kalite metriği adımı yok.
