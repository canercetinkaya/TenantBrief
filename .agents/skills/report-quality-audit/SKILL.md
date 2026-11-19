---
name: report-quality-audit
description: Bir TenantBrief JSON/HTML raporunun veri kalitesini ölçer (korelasyon, sütun, çeviri, risk tutarlılığı, boş alanlar, skor mantığı) ve README iddialarını çıktıyla karşılaştırır. "raporu denetle", "metrikleri ölç", "iddia denetimi" isteklerinde kullan.
---

# Rapor kalite denetimi

Araç: `tools/Measure-TenantBriefQuality.ps1 -Path <report.json> [-HtmlPath <report.html>] [-AsJson]`

Ölçülecek metrikler. Tanımlar sabittir, değiştirilecekse ROADMAP'e not düşülür:

| Kod | Metrik | Tanım | Hedef (v1.1) |
|---|---|---|---|
| Q01 | MultiSourceFindings | `Sources.Count -gt 1` olan bulgu sayısı | > 0 ve crosswalk'taki çok kaynaklı kontrol sayısına eşit |
| Q02 | PillarOutsideSix | `Pillar` ∉ {Identity, Devices, Network, Data, AI, SecOps} | 0 |
| Q03 | CommaJoinedPillar | `DomainPillar` virgül içeren | 0 (dizi kullanılmalı) |
| Q04a | RiskHighImpactLow | `Risk=High` & `Impact=Düşük/Low` | gerekçeli olanlar hariç 0 |
| Q04b | RiskLowImpactHigh | `Risk=Low` & `Impact=Yüksek/High` | 0 |
| Q04 | RiskImpactConflict | `Q04a + Q04b` toplamı | gerekçeli olanlar hariç 0 |
| Q05 | StatusConflictUnflagged | aynı kanonik kontrolde farklı durum ama `StatusConflict` yok | 0 |
| Q06 | CostUnknown | `ImplementationCost = Unknown` | < %5 |
| Q07 | FailedWithoutLicense | Failed ve `MinimumLicense` boş | < %10 |
| Q08a | EnglishTitlesInTR_Narrow | TR raporda başlığı case-sensitive `\b(SHALL|SHOULD|MUST|is|are|the|enabled|configured)\b` içeren | < 5 |
| Q08b | EnglishTitlesInTR | TR raporda başlığı case-insensitive `(?i)\b(SHALL|SHOULD|MUST|is|are|the|enabled|configured)\b` içeren | < 5 |
| Q09 | DenylistHits | `tests/i18n-denylist.txt` eşleşmesi | 0 |
| Q10a | TruncatedWithEllipsis | düzeltme metni `"..."` ile kesilmiş | 0 |
| Q10b | RemediationLearnArtifact | düzeltme metni `öğrenin\|Learn\|Related links` artığı içeriyor | 0 |
| Q10 | TruncatedRemediation | `Q10a ∪ Q10b` benzersiz bulgu birleşimi | 0 |
| Q11 | PlannedInScore | Planned durumundaki bulgunun framework skoruna veya toplamına girmesi | 0 |
| Q12 | ScubaProductsCovered | SCuBA kategorilerinin farklı ürün sayısı | ≥ 5 (canlı kiracıda) |
| Q13 | CopilotGateViolation | lisans veya kritik kontrol Fail iken olgunluk > L1 | 0 |
| Q14 | UnescapedHtml | HTML'de kaçışlanmamış `<script` / `onerror=` içeren kiracı verisi (fixture ile) | 0 |
| Q15 | ClaimMismatch | README'deki iddia edilen kaynaklardan JSON `Frameworks` içinde olmayan | 0 veya README düzeltilmiş |

Çıktı: insan okunur tablo ve `-AsJson` ile makine okunur nesne. Her metrik için örnek 3 bulgu ID'si de döner (kanıt için).

Denetim raporu sonunda "iddia ↔ kanıt" tablosu bulunur: README/About'taki her iddia satırı, kodda karşılık gelen fonksiyon ve demo çıktıdaki kanıt alanı. Karşılığı yoksa `UNSUPPORTED CLAIM` olarak işaretlenir.
