---
name: tenantbrief-sprint
description: TenantBrief yol haritasındaki bir sprinti (ör. "Sprint 1'i uygula") planlar, uygular, test eder ve kanıtlı walkthrough üretir. Kullanıcı bir sprint numarası veya ROADMAP maddesi verdiğinde kullan.
---

# TenantBrief sprint yürütme prosedürü

## 1. Hazırlık (kod değiştirmeden)
1. `docs/improvement/ROADMAP.md` içinden ilgili sprintin hedef, görev, kabul kriteri ve kapsam dışı bölümlerini oku.
2. `git status` temiz olmalı. Değilse dur ve kullanıcıya bildir.
3. Yeni bir dal aç: `git switch -c sprint-<N>-<kısa-ad>`.
4. Başlangıç ölçümü al:
   - `Invoke-Pester -Path ./tests -CI` → toplam/geçen/kalan sayıları.
   - `./tools/Measure-TenantBriefQuality.ps1 -Path ./demo/TenantBriefReport-TR.json -AsJson > ./artifacts/metrics-before.json` (Sprint 0 sonrasında mevcuttur).
5. Etkilenecek fonksiyonları `Select-String -Path TenantBrief.psm1 -Pattern '^function '` ile listele ve gerçekten oku. Fonksiyon gövdesini okumadan değişiklik planlama.

## 2. Implementation Plan artefaktı
Şu başlıkları içersin, sonra kullanıcı onayı iste:
- Değişecek dosya ve fonksiyonlar (gerçek adlarla)
- Her görev için tasarım kararı, alternatifler ve neden bu seçildi
- Eklenecek testler (dosya adı, test adı, hangi fixture)
- Riskler, geriye dönük uyumluluk ve JSON alan değişiklikleri
- Upstream araç varsayımları ve kaynakları (`ASSUMPTION:` olanlar ayrı listelenir)
- `NEEDS-LIVE-TENANT` doğrulama listesi

## 3. Uygulama döngüsü (görev başına)
1. Önce testi yaz, kırmızı olduğunu göster.
2. En küçük değişiklikle kodu düzelt.
3. Testi yeşile çevir ve tüm Pester setini tekrar çalıştır.
4. PSScriptAnalyzer çalıştır.
5. Commit at.
Bir görev 3 denemede yeşile dönmüyorsa dur. Durumu `BLOCKED` yap, hatayı ve denenenleri yaz. Etrafından dolaşma.

## 4. Doğrulama
- Mümkünse rapor çevrimdışı yeniden üretilsin (`Invoke-TenantBriefAssessment` için `-InputReportJson` veya eşdeğeri; önce parametrenin gerçekten var olduğunu doğrula) ve `artifacts/metrics-after.json` alınsın.
- Yeniden üretim mümkün değilse metrikleri yalnızca yeni birim testleri üzerinden kanıtla. Bunu açıkça yaz.
- Üretilen HTML'i tarayıcıda aç, ekran görüntüsünü walkthrough'a ekle. Görsel iddialar yalnızca ekran görüntüsüyle kanıtlanır.

## 5. Walkthrough artefaktı (zorunlu format)
```
## Sprint <N> – Özet
| Görev | Durum | Kanıt |
|---|---|---|
| S<N>.1 … | DONE-VERIFIED | tests/X.Tests.ps1 "…" geçti; metrik A: 0 → 12 |
## Metrikler (önce → sonra)  ← metrics-before/after.json'dan, elle yazma
## Test çıktısı  ← Invoke-Pester özetinin aynısı
## Bilinen sınırlamalar / ASSUMPTION listesi
## NEEDS-LIVE-TENANT: kullanıcının çalıştıracağı komutlar ve beklenen gözlem
## CHANGELOG girdisi
```
Kanıtı olmayan satırın durumu DONE-VERIFIED olamaz.
