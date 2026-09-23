[English](README.md) | **[Türkçe](README.tr.md)**

# RDP Signer

**Windows `.rdp` dosyalarını sürükle bırak yöntemiyle imzalayan tek dosyalık BAT/PowerShell aracı.** Sertifikayı hazırlar, yerel bilgisayarda yayımlayıcı güvenini ayarlar ve `rdpsign.exe` ile dosyayı imzalar.

![Platform](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows&logoColor=white) ![Arayüz](https://img.shields.io/badge/kullanım-sürükle%20bırak-2ea44f) ![Bağımlılık](https://img.shields.io/badge/araçlar-PowerShell%20%7C%20LGPO%20%7C%20rdpsign.exe-blueviolet)

> [!IMPORTANT]
> Betik yönetici yetkisi ister; geçerli kullanıcının sertifika depolarını ve bilgisayarın yerel Computer Grup İlkesi’ni değiştirir. İşlemi yalnızca güvendiğiniz bir makinede ve içeriğini kontrol ettiğiniz `.rdp` dosyalarında çalıştırın.

## Hızlı başlangıç

1. Depodaki `.bat` dosyasını indirin. İsterseniz adını `RDP-Signer.bat` olarak değiştirin; içerikte değişiklik gerekmez.
2. İmzalamak istediğiniz `.rdp` dosyasını BAT dosyasının üzerine sürükleyip bırakın.
3. Windows yönetici izni istediğinde onaylayın.
4. Açılan konsolda **İŞLEM BAŞARILI** çıktısını kontrol edin. İmzalanan dosya, sürüklediğiniz aynı `.rdp` dosyasıdır; ayrı bir çıktı dosyası oluşturulmaz.

```text
Baglanti.rdp  ── sürükle/bırak ──▶  RDP-Signer.bat
                                  │
                                  └─▶ aynı Baglanti.rdp dosyasına imza
```

> [!TIP]
> `.rdp` dosyanızın bir kopyasını önceden saklayın. `rdpsign.exe` dosyayı yerinde günceller.

### Gereksinimler

- Windows; Windows PowerShell, `New-SelfSignedCertificate`, `gpupdate.exe` ve `%SystemRoot%\System32\rdpsign.exe` kullanılabilir olmalı.
- Yönetici yetkisi ve yerel Computer Grup İlkesi’ni değiştirme izni.
- İmzalanacak mevcut bir `.rdp` dosyası.

> Kurumsal cihazlarda merkezi Grup İlkesi, betiğin yazdığı yerel değerin üzerine yazabilir. Böyle bir ortamda yayımlayıcı güveni kurum politikasıyla yönetilmelidir.

## Nasıl çalışır?

```mermaid
flowchart TD
    A[".rdp dosyasını sürükle bırak"] --> B["Yönetici yetkisiyle yeniden başlat"]
    B --> L["Gömülü LGPO.exe dosyasını çıkar ve doğrula"]
    L --> C{"Kullanılabilir sertifika var mı?"}
    C -- Evet --> D["Mevcut sertifikayı seç"]
    C -- Hayır --> E["Kendinden imzalı sertifika oluştur"]
    D --> F["Sertifikayı güven depolarına ekle"]
    E --> F
    F --> G["İlkeyi LGPO ile uygula ve gpupdate çalıştır"]
    G --> H["rdpsign.exe ile dosyayı imzala"]
    H --> I["İmza alanlarının varlığını kontrol et"]
```

| Aşama | Betiğin yaptığı işlem |
| --- | --- |
| Dosya kontrolü | Argümanın `.rdp` uzantılı ve mevcut bir dosya olduğunu doğrular. |
| Yetki yükseltme | BAT dosyasını `RunAs` ile yeniden başlatır; sürüklenen dosyanın yolunu geçici bir dosya üzerinden aktarır. |
| Gömülü LGPO | Base64 olarak gömülü `LGPO.exe` dosyasını geçici dizine çıkarır; çalıştırmadan önce SHA-256 değerini BAT içindeki sabit değerle karşılaştırır. |
| Sertifika | `Cert:\CurrentUser\My` içinde `CN=<kullanıcı adı> RDP` konulu, özel anahtarlı ve süresi dolmamış sertifikayı arar; bulamazsa SHA-256 kullanan, dışa aktarılabilir anahtarlı bir kod imzalama sertifikası oluşturur. |
| Yerel güven | Sertifikayı geçerli kullanıcının `TrustedPublisher` ve `Root` depolarına ekler. |
| Yayımlayıcı ilkesi | Sertifikanın DER verisinden SHA-256 özeti hesaplar ve `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` altındaki `TrustedCertThumbprints` (`REG_SZ`) değerine `sha256:<64 hex karakter>` biçiminde hazırlar. Computer ilkesi için metin dosyası oluşturup `LGPO.exe /t` ile yerel GPO’ya uygular, oluşan kayıt değerini doğrular ve `gpupdate /force` çalıştırır. |
| İmzalama | `%SystemRoot%\System32\rdpsign.exe /sha256 <sertifika thumbprint> /v <dosya>` komutunu çalıştırır. |
| Son kontrol | `.rdp` içeriğinde `signature:s:` ve `signscope:s:` satırlarının bulunduğunu kontrol eder. |

BAT dosyası açık başlangıç ve bitiş işaretleri arasındaki PowerShell bölümünü geçici bir `.ps1` dosyasına çıkarır. Gömülü `LGPO.exe` ve ilke metni geçici dizinde tutulur; PowerShell `finally` bloğunda dizin silinir. BAT, PowerShell işlemi bittiğinde `.ps1` dosyasını da siler. Ayrı bir LGPO veya PowerShell dosyası indirmeniz gerekmez. BAT işlemi kesilirse geçici `.ps1` dosyası kalabilir.

## Yeniden çalıştırma ve kapsam

- Aynı kullanıcıda uygun sertifika varsa yeniden kullanılır; geçerli değilse yenisi oluşturulur.
- Aynı SHA-256 değeri ilkede varsa ikinci kez eklenmez.
- Betik ilkedeki mevcut metinden yalnızca `sha256:` ile başlayan 64 haneli hex değerleri toplar ve virgülle birleştirerek değeri **yeniden yazar**. Başka biçimdeki kayıtlar korunmaz. Kayıt değerinde elle yönetilen öğeler varsa önce yedekleyin.
- Sertifika depoları **geçerli kullanıcıya**, Computer ilkesi ise **yerel bilgisayara** aittir. Başka bir bilgisayar veya kullanıcı, bu betiğin oluşturduğu sertifikaya otomatik olarak güvenmez.
- Bu araç kendinden imzalı sertifika kullanır. İmza dosyanın yayımlayıcı bilgisini ilişkilendirir; dışarıdan doğrulanmış bir kimlik veya uzak RDP sunucusunun kimlik doğrulaması anlamına gelmez.

## Hata durumları

| Mesaj / belirti | Kontrol edin |
| --- | --- |
| `.rdp dosyasi degil` veya `Dosya bulunamadi` | Gerçek bir `.rdp` dosyasını BAT üzerine bırakın; dosyanın taşınmadığından emin olun. |
| `Yonetici yetkisi alinamadi` | UAC istemini ve hesabın yönetici yetkisini kontrol edin. |
| `rdpsign.exe bulunamadi` | Windows kurulumunda `%SystemRoot%\System32\rdpsign.exe` dosyasının varlığını kontrol edin. |
| `LGPO.exe SHA256 dogrulamasi basarisiz` | Gömülü dosya BAT içinde tanımlı hash ile eşleşmiyor; çalıştırmayın. Güvenilir kaynaktan yeni kopya edinin. |
| `LGPO.exe policy'yi uygulayamadi` veya `... kaydi dogrulanamadi` | LGPO çıktısını, yönetici yetkisini ve ilke kısıtlarını kontrol edin. Sertifika depoları bu aşamadan önce değişmiş olabilir. |
| `gpupdate /force hata verdi` | Konsoldaki `gpupdate` çıktısını inceleyin; bu aşamada sertifika depoları ve yerel ilke daha önce değiştirilmiş olabilir. |
| `signature/signscope alanlari bulunamadi` | `rdpsign.exe` çıktısını inceleyin; son kontrol yalnızca bu alanların varlığını sınar, kriptografik imza doğrulaması yapmaz. |
