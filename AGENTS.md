# TenantBrief – Ajan Çalışma Sözleşmesi (always-on)

## Proje
TenantBrief, M365 ve Azure kiracıları için salt okunur CISO değerlendirme raporu üreten bir PowerShell 7 modülüdür.
- Kod: `TenantBrief.psm1` (tek dosya), `TenantBrief.psd1`
- Veri: `data/framework-mappings.json`, `data/sku-catalog.json`, `data/tr-translation-cache.json`
- Şablon: `assets/report-template.html`, `assets/progress-template.html`
- Testler: `tests/*.Tests.ps1` (Pester 5), `tests/fixtures/`
- Örnek çıktı: `demo/TenantBriefReport-{TR,EN}.{json,html}`, `demo/TenantBrief-ExecutiveSummary-*.html`
- Yol haritası: `docs/improvement/ROADMAP.md`. Başlangıç ölçümleri: `docs/improvement/BASELINE.md`

## DÜRÜSTLÜK PROTOKOLÜ (ihlal edilemez)
1. **Kanıtsız "tamamlandı" yok.** Bir maddeyi tamamlandı saymak için çalıştırdığın komutu ve gerçek çıktısını (Pester özeti, metrik değeri, diff) walkthrough artefaktına koy. Komutu çalıştıramadıysan durum `NOT VERIFIED` olur.
2. **Durum etiketleri:** her madde `DONE-VERIFIED` (test/metrik ile kanıtlı), `DONE-UNVERIFIED` (kod yazıldı, doğrulanamadı; nedenini yaz), `PARTIAL`, `BLOCKED` (engeli yaz), `NOT STARTED` olarak işaretlenir. "Muhtemelen çalışır" bir durum değildir.
3. **Canlı kiracı gerektiren doğrulamalar** (Graph, EXO, SPO, Teams, ScubaGear, ORCA, Maester bağlantıları) senin ortamında yapılamaz. Bunları `NEEDS-LIVE-TENANT` olarak işaretle ve kullanıcının çalıştıracağı tam komutu yaz. Asla sonuç uydurma.
4. **Testi geçmek için testi bozma.** Mevcut bir testin beklentisini değiştirmen gerekiyorsa gerekçesini ayrı başlıkta yaz ve kullanıcı onayı iste. Kodu mock'la "yeşil" yapıp gerçek davranışı test etmemek yasak.
5. **Demo/çıktı dosyalarını elle düzenleme.** `demo/*.json|html` yalnızca modülün kendisi tarafından yeniden üretilebilir. Üretemiyorsan dokunma ve bunu raporla.
6. **README ve kod iddiaları eşleşmeli.** Kodda olmayan bir özelliği README'ye, rapora veya commit mesajına yazma. Mevcut bir iddia doğrulanamıyorsa README'yi düzelt ya da `Bilinen Sınırlamalar` bölümüne taşı.
7. **Sayıları hesapla, tahmin etme.** Metrikler `tools/Measure-TenantBriefQuality.ps1` (Sprint 0'da yazılır) ile üretilir. Elle sayım yapıp rapora yazma.
8. **Bilmiyorsan araştır, bulamazsan söyle.** Upstream araç davranışı (ScubaGear parametreleri, Maester etiketleri, ORCA çıktı alanları, Graph uç noktaları) için resmi dokümana veya modülün kendi kaynağına bak (`Get-Command -Syntax`, modül klasörü). Kaynağı walkthrough'da belirt. Bulamazsan `ASSUMPTION:` önekiyle yaz.

## Salt okunur garanti
- Kiracıda hiçbir yazma işlemi yapılmaz: `New-*`, `Set-*`, `Update-*`, `Remove-*` Graph/EXO/SPO/Teams cmdlet'leri ve POST/PATCH/DELETE çağrıları yasak. İstisna yalnızca Microsoft Translator gibi rapor dışı servisler. Bunları da `Diagnostics` kaydına yaz.
- Kullanıcı makinesinde modül silme veya kurma (`Remove-Item` modül klasörü, `Install-Module -Force -AllowClobber`) yalnızca açık bir anahtarla (`-AutoFixDependencies`) yapılabilir. Varsayılan davranış uyar ve dur olmalıdır.

## Tamamlanma tanımı (her PR / sprint)
- `Invoke-Pester -Path ./tests -CI` yeşil. Yeni davranış için en az bir yeni test var.
- `Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1` yeni Error/Warning üretmiyor.
- `tools/Measure-TenantBriefQuality.ps1 -Path demo/TenantBriefReport-TR.json` çıktısı sprint hedeflerini karşılıyor ve önce/sonra tablosu walkthrough'da var.
- JSON çıktısı `schemas/tenantbrief-report.schema.json` ile doğrulanıyor (Sprint 1'den itibaren).
- Geriye dönük uyumluluk: dışa açık fonksiyon adları korunuyor (`*-ZtLens*` alias'ları v1.0.x'te kaldırıldı — `9a37886`). JSON alan adı değişiyorsa eski alan bir sürüm boyunca `Deprecated` olarak tutuluyor ve `CHANGELOG.md`'ye yazılıyor.
- Walkthrough artefaktında şunlar var: yapılanlar, durum etiketleri, kanıt (komut ve çıktı), bilinen sınırlamalar, kullanıcının canlı kiracıda çalıştırması gereken komutlar.

## Çalışma biçimi
- Her sprinte önce **Implementation Plan** artefaktı ile başla ve kullanıcı onayı al. Sonra uygula.
- Küçük, geri alınabilir commit'ler kullan. Mesaj formatı: `type(scope): özet`, ör. `fix(correlation): crosswalk ile kaynaklar arası eşleme`.
- Bir sprintte kapsam dışı bir sorun bulursan düzeltme. `docs/improvement/BACKLOG.md`'ye ekle.
- Sprint sırası ve kabul kriterleri için: @docs/improvement/ROADMAP.md

## Özerk çalışma yetkisi

### İZİNLİ (sormadan yap)
- Branch açma, commit, kendi dallarına push (`--force-with-lease` dahil), PR açma.
- `gh pr checks` tamamen pass ise kendi açtığın PR'ı `gh pr merge --squash --delete-branch` ile merge etme.
- Bir sprint bittiğinde sonraki sprintin planını yazıp uygulamaya geçme.

### DUR VE BANA SOR (yalnızca bunlarda)
- Bir check fail oldu ve 3 denemede düzelmedi (`BLOCKED`).
- Mevcut bir testin beklentisini değiştirmek gerekiyor.
- Dışa açık fonksiyon adı/parametre ya da JSON alanı kaldırılacak (breaking change).
- Tag, release veya PSGallery yayını (sürüm sonu: `v1.1`, `v1.2`, `v2.0`).
- `NEEDS-LIVE-TENANT` adımı.
- `ROADMAP.md`'de kapsam değişikliği.

### Raporlama formatı
- Ara rapor verme. Her sprint sonunda yalnızca en fazla 15 satırla özetle:
  `Sprint N | PR linki | Pester x/y | Q metrikleri önce→sonra (araç çıktısından) | BLOCKED/PARTIAL maddeler | NEEDS-LIVE-TENANT komutları.`
- Ayrıntılar walkthrough artefaktında kalır.
- Kurallar değişmedi: DÜRÜSTLÜK PROTOKOLÜ, kırmızı→yeşil test, kanıtsız `DONE-VERIFIED` yok. Framework skorları ve önceki tüm testler gerilemeyecek; gerilerse merge etme.
