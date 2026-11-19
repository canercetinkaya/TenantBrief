---
trigger: model_decision
description: "Türkçe rapor metni, çeviri önbelleği, terim sözlüğü veya TR/EN yerelleştirme ile ilgili her işte uygula."
---
# Türkçe yerelleştirme kuralları

- Terim sözlüğü `data/i18n/glossary-tr.json` tek doğruluk kaynağıdır. Önerilen temel eşlemeler:
  Conditional Access → Koşullu Erişim · phishing-resistant → oltalamaya dayanıklı · legacy authentication → eski kimlik doğrulama · device code flow → cihaz kodu akışı · attestation → kanıtlama · break-glass → acil durum hesabı · sensitivity label → hassasiyet etiketi · tenant → kiracı · least privilege → en az ayrıcalık.
- Ürün ve özellik adları çevrilmez: Microsoft Entra ID, Intune, Purview, Defender for Office 365, Global Secure Access, SharePoint Online, Copilot.
- SCuBA'daki "SHALL / SHOULD" ifadeleri "…zorunludur / …önerilir" olarak çevrilir. Orijinal kontrol kimliği her zaman korunur.
- Çeviri önbelleği anahtarı `"<Source>|<TestId>"` biçimindedir. Değer şeması: `{ Title, Desc, Remediation, Reviewed: bool, Source: "machine|human" }`.
- Makine çevirisi `Reviewed=false` olarak işaretlenir. Raporda insan onaylı olmayan çeviri için iç sayaç tutulur.
- Yasak kelime listesi `tests/i18n-denylist.txt` dosyasında tutulur ve CI'da taranır. Örnekler: "tasdiqi", "öğrenin" (düzeltme alanında), "SHALL", "SHOULD".
- Kesme: düzeltme metni cümle sınırında kesilir. Kelime ortasından kesip "..." eklemek yasak.
