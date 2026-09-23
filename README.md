[**English**](README.md) | [Türkçe](README.tr.md)

# RDP Signer

**Sign Windows `.rdp` files by dragging them onto a single BAT/PowerShell script.** The script prepares a certificate, configures publisher trust on the local machine, and signs the file with `rdpsign.exe`.

![Platform](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows&logoColor=white) ![Usage](https://img.shields.io/badge/usage-drag%20and%20drop-2ea44f) ![Tools](https://img.shields.io/badge/tools-PowerShell%20%7C%20LGPO%20%7C%20rdpsign.exe-blueviolet)

> [!IMPORTANT]
> This script requests administrator privileges. It changes certificate stores for the current user and the local Computer Group Policy for the machine. Run it only on a computer you trust and with `.rdp` files whose contents you have reviewed.

## Quick start

1. Download the `.bat` file from this repository. You can rename it to `RDP-Signer.bat` without changing its contents.
2. Drag the `.rdp` file you want to sign onto the BAT file.
3. Approve the Windows administrator prompt.
4. Check the console for **İŞLEM BAŞARILI** (operation successful). The script updates the original `.rdp` file; it does not create a separate output file.

```text
Connection.rdp ── drag and drop ──▶ RDP-Signer.bat
                                     │
                                     └─▶ signs Connection.rdp in place
```

> [!TIP]
> Keep a backup of the `.rdp` file before signing. `rdpsign.exe` modifies it in place.

### Requirements

- Windows with Windows PowerShell, `New-SelfSignedCertificate`, `gpupdate.exe`, and `%SystemRoot%\System32\rdpsign.exe` available.
- Administrator privileges and permission to change local Computer Group Policy.
- An existing `.rdp` file.

> On managed computers, a centrally applied Group Policy can overwrite the local value set by the script. In that environment, configure publisher trust through your organization's policy.

## How it works

```mermaid
flowchart TD
    A["Drop an .rdp file"] --> B["Relaunch as administrator"]
    B --> L["Extract and verify bundled LGPO.exe"]
    L --> C{"Suitable certificate exists?"}
    C -- Yes --> D["Reuse certificate"]
    C -- No --> E["Create self-signed certificate"]
    D --> F["Add certificate to trust stores"]
    E --> F
    F --> G["Apply policy through LGPO and run gpupdate"]
    G --> H["Sign with rdpsign.exe"]
    H --> I["Check for signature fields"]
```

| Step | What the script does |
| --- | --- |
| Input | Checks that the input exists and has an `.rdp` extension. |
| Elevation | Relaunches the BAT file using `RunAs`, passing the file path through a temporary file. |
| Bundled LGPO | Decodes the Base64-embedded `LGPO.exe` to a temporary folder and checks its SHA-256 hash against a value embedded in the BAT file before execution. |
| Certificate | Searches `Cert:\CurrentUser\My` for a certificate with subject `CN=<username> RDP`, a private key, and an unexpired validity period. Otherwise creates a SHA-256 code-signing certificate with an exportable private key. |
| Local trust | Adds the certificate to the current user's `TrustedPublisher` and `Root` stores. |
| Publisher policy | Computes SHA-256 over the certificate's DER data. Adds `sha256:<64 hexadecimal characters>` to `TrustedCertThumbprints` (`REG_SZ`) under `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services`. It writes a Computer policy text file and applies it with `LGPO.exe /t`; then verifies the resulting registry value and runs `gpupdate /force`. |
| Signing | Runs `%SystemRoot%\System32\rdpsign.exe /sha256 <certificate thumbprint> /v <file>`. |
| Final check | Checks the `.rdp` file for `signature:s:` and `signscope:s:` fields. |

The BAT file extracts the PowerShell code between explicit markers into a temporary `.ps1` file. The embedded `LGPO.exe` and its policy input file are placed in a temporary directory and removed in a `finally` block. The BAT wrapper also removes the `.ps1` file after the PowerShell process exits. You do not need to download LGPO or a separate PowerShell file. An interrupted BAT process may leave a temporary `.ps1` file.

## Repeated runs and scope

- The script reuses a suitable certificate for the same user; otherwise it creates a new one.
- It does not add the same SHA-256 policy entry twice.
- It extracts only `sha256:` entries followed by 64 hexadecimal characters from the existing policy text, joins them with commas, and **rewrites** the value. Entries in other formats are not preserved. Back up the value first if it contains manually managed entries.
- The certificate stores belong to the **current user**, while the Computer policy belongs to the **local machine**. Other computers or users do not automatically trust the generated certificate.
- The certificate is self-signed. This associates publisher information with the file; it does not establish an externally verified identity or authenticate the remote RDP server.

## Troubleshooting

| Message or symptom | What to check |
| --- | --- |
| `.rdp dosyasi degil` or `Dosya bulunamadi` | Drop an existing `.rdp` file onto the BAT file and check its path. |
| `Yonetici yetkisi alinamadi` | Check the UAC prompt and administrator privileges. |
| `rdpsign.exe bulunamadi` | Check whether `%SystemRoot%\System32\rdpsign.exe` exists. |
| `LGPO.exe SHA256 dogrulamasi basarisiz` | The embedded binary did not match the hash hardcoded in the BAT file; do not run it. Download a fresh copy from a trusted source. |
| `LGPO.exe policy'yi uygulayamadi` or `... kaydi dogrulanamadi` | Check the LGPO output, administrator privileges, and policy restrictions. The certificate stores may already have changed. |
| `gpupdate /force hata verdi` | Inspect the `gpupdate` console output. The certificate stores and local policy may already have changed before this error. |
| `signature/signscope alanlari bulunamadi` | Inspect the `rdpsign.exe` output. The final check only tests for these fields; it does not cryptographically verify the signature. |
