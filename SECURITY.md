# Security Policy

## Supported Versions

| Version | Supported |
| --- | --- |
| `1.x` (latest) | Yes |
| `< 1.0.1` | No (upgrade to `>= 1.0.1` for HTML/XSS hardening) |

## Reporting a Vulnerability

Please report security issues responsibly without opening a public issue:

- **GitHub Security Advisories:** Use the **Report a vulnerability** button under the repository's **Security** tab.
- **Response Target:** Initial acknowledgement within 5 business days; remediation timeline depends on severity and upstream dependencies.

Please include:
1. Affected file, cmdlet, or HTML/JS template section.
2. Minimal offline reproduction steps (avoid sharing real tenant IDs, domains, or UPNs).
3. Impact assessment (e.g., stored XSS in generated HTML, credential exposure, unintended write operation).

## Security & Privacy Architecture

1. **Strict Read-Only Tenant Posture:**
   - TenantBrief executes only read-only Microsoft Graph `GET` endpoints and read-only assessment cmdlets (`ZeroTrustAssessment`, `ScubaGear`, `ORCA`, `Maester`).
   - It never modifies Entra ID, Exchange Online, SharePoint Online, Teams, Purview, or Azure tenant settings.
2. **Local Machine Changes Opt-In (`-AutoFixDependencies`):**
   - By default, `Connect-TenantBrief` and `Invoke-TenantBriefAssessment` never install modules, download OPA, or remove conflicting local module copies.
   - Local changes occur only when the operator explicitly passes `-AutoFixDependencies`.
3. **Offline HTML Report Hardening (XSS & CSP):**
   - Embedded JSON uses `ConvertTo-Json -Depth 12 -Compress -EscapeHandling EscapeHtml` plus `U+2028`/`U+2029` escaping.
   - Both the main HTML report (`assets/report-template.html`) and `Export-TenantBriefExecutiveSummary` enforce an offline `Content-Security-Policy` (`default-src 'none'; connect-src 'none'; object-src 'none'; frame-ancestors 'none'`).
   - CI validates generated HTML reports against adversarial payloads in headless Chromium (`.github/workflows/ci-xss.yml`).
4. **Deep Anonymization (`-Anonymize`):**
   - Masks tenant domains, GUIDs/TenantIds, and UPN/email addresses across findings (`Title`, `Result`, `Description`, `SkippedReason`, `Remediation`, `ErrorRemedy`), `PlannedFindings`, and MFA summary text.
5. **Optional Azure AI Translator Data-Flow:**
   - No data leaves the machine unless `-TranslatorKey` (or `$env:AZURE_TRANSLATOR_KEY`) is explicitly supplied with `-Language tr`.
   - `-TranslatorKey` accepts `[SecureString]` (recommended) or `[string]` and is never logged or written to report/manifest files.
   - Control titles and descriptions are sanitized through `Protect-TenantBriefSensitiveText` (stripping UPNs/emails, GUIDs, and tenant domains) before any outbound request to `api.cognitive.microsofttranslator.com`.

## Release & PSGallery Signing Readiness

- Releases are tagged from `master` only after Pester, PSScriptAnalyzer, and Playwright XSS CI gates pass.
- Before publishing to PowerShell Gallery, maintainers verify module manifest metadata (`TenantBrief.psd1`), file hashes, and Authenticode code-signing readiness (`Set-AuthenticodeSignature` on `.psm1`/`.psd1` when a code-signing certificate is configured in CI).
