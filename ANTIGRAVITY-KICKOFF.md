# Antigravity başlangıç görevi (Agent Manager'a yapıştır)

> **Kurulum:** Bu paketteki `AGENTS.md`, `.agents/` ve `docs/improvement/` klasörlerini TenantBrief deposunun köküne kopyala ve commit et (`chore(agent): Antigravity çalışma sözleşmesi ve yol haritası`). Sonra Antigravity'de depoyu workspace olarak aç ve aşağıdaki metni yeni bir konuşmaya yapıştır. Mod: **Planning**. Terminal komutlarında "Request review" ayarını açık tut.

---

Sen TenantBrief projesinde kıdemli bir PowerShell ve M365 güvenlik mühendisisin. Kurallarına `AGENTS.md` dosyasından uy, özellikle **DÜRÜSTLÜK PROTOKOLÜ** bölümüne.

**Görev:** `docs/improvement/ROADMAP.md` içindeki yol haritasını değerlendir, doğrula ve **Sprint 0**'ı uygula.

1. **Bağımsız değerlendirme (önce bunu yap, kod değiştirme):**
   - `docs/improvement/BASELINE.md` içindeki her "kök neden" iddiasını `TenantBrief.psm1` kaynağını okuyarak doğrula. Her biri için DOĞRULANDI / YANLIŞ / KISMEN etiketi ve fonksiyon adı + satır aralığı ver.
   - ROADMAP'i 8 bakış açısıyla eleştir (CISO, güvenlik mimarı, veri mühendisi, yerelleştirme, QA, AppSec, UX, operasyon). Eksik, gereksiz veya yanlış sıralanmış maddeleri öner. Önerini bir upstream kaynakla veya kod kanıtıyla destekle.
   - Upstream araçların güncel davranışını araştır (ScubaGear `Invoke-SCuBA` parametreleri ve ürün adları, Maester test ID/etiket yapısı, ORCA JSON alanları, ZeroTrustAssessment rapor şeması). Kaynakları listele. Doğrulayamadıklarını `ASSUMPTION:` olarak işaretle.
   - Çıktı: **"Assessment"** artefaktı. Yol haritasında değişiklik önerirsen ROADMAP'i doğrudan değiştirme; diff önerisi olarak sun ve onayımı bekle.

2. **Sprint 0'ı uygula:** `tenantbrief-sprint` skill'ini kullan. Önce Implementation Plan artefaktı, sonra onayım, sonra uygulama.

3. **Bitiş:** `tenantbrief-sprint` skill'indeki formatta walkthrough. Her satırda durum etiketi ve kanıt olsun. Canlı kiracı gerektirenleri `NEEDS-LIVE-TENANT` listesine, çalıştırmam gereken komutla birlikte yaz.

**Kesin sınırlar:**
- Kiracıya bağlanmaya veya bağlanmış gibi sonuç üretmeye çalışma.
- `demo/` dosyalarını elle düzenleme.
- Test beklentisini benim onayım olmadan değiştirme.
- "Tamamlandı" demeden önce komutu çalıştır ve çıktısını göster.
- Emin olmadığın bir şeyi olmuş gibi yazma; "doğrulayamadım" demek başarısızlık değildir.

---

## Sonraki sprintler için kısa komut
```
Sprint <N>'i tenantbrief-sprint skill'i ile uygula. Önce Implementation Plan artefaktını ver ve onayımı bekle. Başlangıç metrikleri artifacts/metrics-before.json olarak, bitiş metrikleri artifacts/metrics-after.json olarak kaydedilsin. Walkthrough'da önce/sonra metrik tablosu tool çıktısından gelsin.
```

## Ara denetim komutu (her sprint sonunda ayrı bir konuşmada, "reviewer" olarak)
```
report-quality-audit skill'ini kullanarak mevcut dalı denetle. Önceki sprintin walkthrough'undaki her DONE-VERIFIED satırı için kanıtı yeniden üret (testi tekrar çalıştır, metriği tekrar ölç). Tekrar üretilemeyen her satırı "KANIT TUTMUYOR" olarak listele. Kod değiştirme.
```
