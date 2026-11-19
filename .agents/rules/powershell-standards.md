---
trigger: glob
globs: "*.ps1, *.psm1, *.psd1"
description: "TenantBrief PowerShell kod standartları"
---
# PowerShell standartları (TenantBrief)

- Hedef: PowerShell 7.4+. `Set-StrictMode -Version Latest` korunur. Geçici `-Off` blokları `try/finally` ile geri açılır (mevcut desen).
- Dışa açık fonksiyonlar `[CmdletBinding()]`, `[OutputType()]` ve comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`) içerir.
- `Write-Host` yalnızca ilerleme bildirimi için kullanılır. Veri `return` ya da pipeline ile döner. Tanılama bilgisi `Add-TenantBriefDiagnostic` ile yazılır.
- Boş `catch {}` yasak. En azından `Write-Verbose` veya diagnostic kaydı bırakılır.
- Dizi biriktirmede `+=` yerine `[System.Collections.Generic.List[object]]` kullanılır (performans).
- Kiracıdan gelen her metin HTML'e yazılmadan önce `[System.Net.WebUtility]::HtmlEncode()` ile kaçışlanır.
- Gizli bilgi (`-TranslatorKey` vb.) loglanmaz, JSON'a yazılmaz. Mümkünse `SecureString` veya ortam değişkeni ile alınır.
- Dil metinleri koda gömülmez. `data/i18n/{tr,en}.json` üzerinden okunur (Sprint 3'ten itibaren).
- Her yeni import/eşleme fonksiyonu için `tests/fixtures/` altında küçük bir örnek girdi ve ona karşı Pester testi eklenir.
- Upstream araç çıktı formatı varsayımları (ScubaGear `ScubaResults*.json`, ORCA, Maester `Tests[]`) fonksiyon başındaki yorumda kaynak sürümle belgelenir.
