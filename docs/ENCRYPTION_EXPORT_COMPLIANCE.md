# Encryption export compliance (Bloggo / App Store)

This note summarizes [Apple’s guidance on complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations) and when **extra documentation** is required in App Store Connect. It is for internal reference only—not legal advice.

## Is the “yes, but exempt” story true?

**Mostly yes, with one nuance.**

- If you distribute outside the U.S. or Canada, U.S. export rules can apply when you upload builds. Apple asks about encryption so submissions stay compliant.
- **Using encryption** (for example HTTPS, Sign in with Apple, Keychain, or **CryptoKit**) is normal and does **not** by itself mean you must upload CCATS or other heavy paperwork.
- What matters is whether your encryption is **exempt** under Apple’s flow. For a typical app that only uses **encryption provided through Apple’s OS and standard APIs** (including `URLSession` TLS and **CryptoKit**), Apple’s own help describes **no App Store Connect encryption documentation** for that category.

You can streamline submissions by declaring this in **Info.plist** with `ITSAppUsesNonExemptEncryption`. In this project it is set to **`NO` (`false`)**, meaning: the app does not use **non-exempt** encryption (or does not use encryption at all). That matches the usual interpretation for HTTPS + Apple-stack crypto only.

**Caveat:** Apple also notes that **exempt** encryption can still trigger a **U.S. annual self-classification report** in some cases. See Apple’s “Important” note on their compliance page and [BIS guidance](https://www.bis.doc.gov/index.php/policy-guidance/encryption/4-reports-and-reviews/a-annual-self-classification) if you need to verify reporting obligations.

## When is documentation required? (Apple’s categories)

Apple’s reference table groups apps by **how** encryption is implemented. The following is aligned with [Export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption) (App Store Connect Help).

| Encryption in use | Documentation in App Store Connect |
| --- | --- |
| **Limited to encryption within the Apple operating system** (e.g. system TLS via `URLSession`, Keychain, **CryptoKit**) | **No** documentation required in App Store Connect. |
| **Industry-standard** algorithms **not** provided within the Apple OS (your own or third-party crypto **outside** Apple’s APIs for that use) | Upload **French encryption declaration** if you distribute in **France** (per Apple’s footnote on that page). |
| **Proprietary** algorithms **not** accepted as standard by bodies such as **IEEE, IETF, or ITU** | Upload **CCATS** (U.S.) and, if applicable, **French encryption declaration** for France. |

**Before you submit a build:** If documentation *is* required, Apple says to complete **App Encryption Documentation** in App Store Connect (under **App Information**) and, for a smooth review, have app description and availability set. After approval, Apple may give a compliance code to put in Info.plist as `ITSEncryptionExportComplianceCode`. Details: [Determine and upload app encryption documentation](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation).

### How this maps to informal wording

- **“Standard encryption instead of or in addition to Apple’s OS encryption”** → Think: crypto **not** going through Apple’s provided APIs for that functionality (custom TLS stack, bundled OpenSSL for your own protocol, etc.). That is when Apple’s table moves you toward **French declaration** (and possibly more), not the “no documentation” row.
- **“Proprietary or non–standard-body algorithms”** → Strongest case for **CCATS** and related paperwork.

## Bloggo codebase (quick check)

The app uses **CryptoKit** (e.g. AES-GCM) in services such as share/backup flows. CryptoKit is **Apple’s** framework and uses **standard** algorithms; that falls under **encryption within the Apple operating system** for export **documentation** purposes in Apple’s table, alongside normal HTTPS usage.

**Re-verify** before each major dependency change: any new SDK that ships **its own** encryption implementation (custom protocols, non-Apple TLS stacks, proprietary ciphers) can change your answers.

## Official links

- [Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations) (developer documentation; `ITSAppUsesNonExemptEncryption`, `ITSEncryptionExportComplianceCode`)
- [Export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption) (when uploads are required)
- [Determine and upload app encryption documentation](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation) (workflow; **before** submit)
- [Overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance) (broader context)
