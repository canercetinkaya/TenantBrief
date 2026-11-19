# Başlangıç ölçümleri (baseline)

**Kaynak:** Lab kiracısı (`UserCount = 1`), rapor tarihi `2026-11-19` `TenantBriefReport-TR.json` çıktısı (modül `1.0.0`, PowerShell `7.7.0`, commit `d41e7ff` dönemi). İlk başlangıç değerleri Python ile hesaplanmış; Sprint 0'da `tools/Measure-TenantBriefQuality.ps1` ile alt metriklere ayrılarak yeniden doğrulanmıştır.

> Not: Bu bir lab kiracısıdır (`UserCount = 1`). Kiracıya özgü yüzdeler genellenemez. Burada yalnızca **aracın veri kalitesi** ölçülür.

| Kod | Metrik | Değer | Not / Durum |
|---|---|---|---|
| — | Toplam bulgu | 700 (Passed 162, Failed 272, Investigate 36, Skipped 194, Planned 35, Error 1) | Birebir doğrulandı |
| Q01 | Birden fazla kaynağı olan bulgu | **0** | Crosswalk yok (Sprint 1) |
| Q02 | `Pillar` 6 sütun dışında (araç adı veya birleşik değer) | **374** | Sprint 1 `S1.4` |
| Q03 | `DomainPillar` virgülle birleşik | 33 | Sprint 1 `S1.4` |
| Q04a | `Risk=High` ve `Impact=Düşük/Low` | **142** | ZTA `UserImpact` semantik farkı (`S1.6`) |
| Q04b | `Risk=Low` ve `Impact=Yüksek/High` | **2** | `35009, 35010` |
| Q04 | Risk–Etki çelişkisi toplam (`Q04a + Q04b`) | **144** | — |
| Q05 | Çatışan durum işaretsiz (`StatusConflictUnflagged`) | **0** | `NOT STARTED` (`SourceStatuses`/`StatusConflict` Sprint 1 `S1.2`'de eklenir) |
| Q06 | `ImplementationCost = Unknown` | 100 (ORCA 66 + SCuBA 34) | — |
| Q07 | Failed ve `MinimumLicense` boş | 130 | — |
| Q08a | TR başlıkta İngilizce kalıp (case-sensitive `-cmatch`) | **148** (`Maester 73, CIS 37, SCuBA 34, EIDSCA 3, ZT 1`) | `Measure-TenantBriefQuality.ps1` `Q08a` çıktısı (ilk Python özetindeki `164`, farklı kelime kümesiyle hesaplandığı için `148` olarak kanıtla sabitlendi) |
| Q08b | TR başlıkta İngilizce kalıp (`SKILL.md` regex `(?i)`) | **202** (`+47 should, +5 Enabled, +2 must`) | Ek 54 kaydın tamamı gerçek İngilizce başlık (0 Türkçe yanlış pozitif) |
| Q09 | Yasak kelime ("tasdiqi") | 1 | `Id: 21840` |
| Q10a | `"..."` ile kesilmiş düzeltme | **77** | 160 karakter kesmesi |
| Q10b | `"öğrenin/Learn/Related links"` artığı | **10** (case-sensitive) / **11** (`(?i)` `MT.1100` `learn` dahil) | — |
| Q10 | Kesilmiş / artıklı düzeltme birleşimi (`Q10a ∪ Q10b`) | **80** | Benzersiz bulgu sayısı |
| Q11 | Planned bulgular | 35 ("Planned for future release" ZT testleri) | — |
| Q12 | SCuBA kategori dağılımı | yalnızca `AAD` (34/34) | `ScubaProductsCovered = 1` |
| Q13 | Copilot hazırlık | Skor 50 / "L2 – Tekrarlanabilir"; `COP-LIC-01 = Fail`, `COP-ENTRA-01 = Fail` | `CopilotGateViolation = 1` |
| Q14 | Kaçışlanmamış HTML / XSS (`UnescapedHtml`) | **0** (demo HTML) | `NOT STARTED` (zararlı `<script>` / `onerror=` fixture testi Sprint 1 `S1.0`'da) |
| Q15 | README/About'ta "EntraFalcon" iddiası var, `Frameworks` içinde EntraFalcon yok | 1 (`EntraFalcon`) | Uyumsuz |

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

## PSScriptAnalyzer tabanı (S0.2)

- **Araç & Sürüm (Yerel ve CI sabit):** `PSScriptAnalyzer v1.25.0`, ayar: `PSScriptAnalyzerSettings.psd1` (`Error` + `Warning`), kapsam: `-Path . -Recurse`
- **Tüm depo toplamı:** **84** bulgu (`Error: 0`, `Warning: 84`) — yerel ve CI ortamı birebir eşleşir.

### Dosya Bazında Kırılım

| Dosya | Error | Warning | Kural Dağılımı |
|---|---:|---:|---|
| `TenantBrief.psm1` | 0 | **70** | `PSAvoidUsingEmptyCatchBlock: 31`, `PSAvoidUsingWriteHost: 18`, `PSUseSingularNouns: 11`, `PSReviewUnusedParameter: 5`, `PSUseShouldProcessForStateChangingFunctions: 4`, `PSUseDeclaredVarsMoreThanAssignments: 1` |
| `tests/TenantBrief.Tests.ps1` | 0 | **14** | `PSReviewUnusedParameter: 14` (mock fonksiyon imzaları) |
| `tools/Measure-TenantBriefQuality.ps1` | 0 | **0** | Temiz |
| `TenantBrief.psd1` / diğer `tests/*.ps1` | 0 | **0** | Temiz |
| **Toplam** | **0** | **84** | — |
