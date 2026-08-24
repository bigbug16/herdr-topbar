# herdr-topbar

[English](README.md) · **Türkçe**

[herdr](https://herdr.dev) için macOS menü çubuğu eklentisi.

herdr terminalin içinde yaşar. Bu eklenti menü çubuğuna küçük bir ikon koyar;
böylece herdr'a her yerden dönebilir, istediğin klasörde başlatabilir ve bir
ajanın seni beklediğini tek bakışta görebilirsin.

```
┌─ menü çubuğu ──────────────────────────────────────────── ▣ ─┐
                                                            ▲
                                       sol tık  →  herdr'ı öne getir
                                       sağ tık  →  menü
```

## Ne yapar

**Sol tık** herdr'ın çalıştığı terminali öne getirir. herdr açık değilse menüyü
açar, böylece tıklama yine bir işe yarar.

**Sağ tık** menüyü açar:

- **Start herdr** / **Bring herdr to Front**
- **Waiting for Input** — hangi ajan, hangi projede bekliyor. Satıra tıklayınca
  doğrudan o çalışma alanına atlar.
- **Open Folder…** — bir klasör seç; herdr çalışma alanı olarak açılır.
- **Recent Projects** — son 10 proje. herdr'ın içinden açtıkların da listeye
  düşer.
- **Settings** — yanıp sönme süresi, girişte başlat, Finder entegrasyonu.

**Durgun haldeki ikon her zaman koyu koçtur**, sistem teması ne olursa olsun.
Bilerek AppKit template görseli değil: template kontrast için yeniden boyanır ve
koyu menü çubuğunda beyaza dönerdi. Buradaki amaç durgun görünümün hiç
değişmemesi — hareket eden tek şey yanıp sönme olsun.

**Bir ajan girdi beklediğinde** ikon açık tonlu koça geçip geri döner, saniyede
üç kez. herdr öne geldiği anda durur — bu ikonla, Cmd-Tab ile ya da pencereye
tıklayarak — ve ajan hâlâ beklerken küçük bir nokta bırakır. Sonradan **başka**
bir ajan bloke olursa yanıp sönme yeniden başlar.

**Settings → Blink Duration** ile kendi kendine de durur; böylece gece boyu
bekleyen bir ajan sabaha kadar yanıp sönmez:

| Seçenek | Davranış |
|---|---|
| 1 minute | Bir dakika yanıp söner, sonra sabit nokta |
| **3 minutes** | Varsayılan |
| 10 minutes | Uzun süre başında olmayacaksan |
| Until clicked | Kendi kendine hiç durmaz |

Nokta her durumda kalır — duran yalnızca harekettir.

**Finder** iki giriş kazanır; ikisi de herdr'ı seçili klasörde açar (dosya
seçtiysen üst klasöründe):

- sağ tık → **Hizmetler → Open with herdr** (menünün alt tarafında)
- sağ tık → **Birlikte Aç → HerdrBar**

### Bildirimler hakkında

herdr'ın kendi bildirimleri zaten var (`config.toml` içindeki `[ui.toast]`,
`[ui.sound]`). **Bu eklenti hiç bildirim göndermez ve bu ayarların hiçbirini
değiştirmez.** Yalnızca hâlihazırda var olan "ajan bekliyor" durumunu ekranın
öbür ucundan fark edilir hale getirir. herdr bildirim ayarların aynen kalır.

## Kurulum

```bash
git clone https://github.com/bigbug16/herdr-topbar.git
cd herdr-topbar

herdr plugin link "$PWD"
bash scripts/build.sh
bash scripts/install-finder.sh
bash scripts/install-login-item.sh
```

Ya da doğrudan GitHub'dan kur — bu yol derleme adımını da çalıştırır:

```bash
herdr plugin install bigbug16/herdr-topbar
```

`herdr plugin install` senin yerine `scripts/build.sh` çalıştırır, ama
**`herdr plugin link` derleme adımlarını çalıştırmaz** — yani link ile bağlı bir
kopya üzerinde çalışırken, herhangi bir Swift dosyasını değiştirdikten sonra
`build.sh`'i kendin çalıştır, ardından `scripts/restart-bar.sh`.

`install-login-item.sh`, herdr kapalıyken bile ikonun menü çubuğunda kalmasını
sağlayan şeydir. Eklentinin `[[startup]]` kancası yalnızca bir herdr sunucusu
başlarken tetiklenir; bu da "herdr kapalı, ikona tıklayıp başlatayım" durumunu
karşılayamaz.

**Hizmetler → Open with herdr** görünmüyorsa **Sistem Ayarları → Klavye → Klavye
Kısayolları… → Hizmetler** altından etkinleştir, sonra Finder'ı yeniden başlat
(`killall Finder`).

Şunu bil: `~/Library/Services` içindeki bir `.workflow`, Finder'ın **Hizmetler**
alt menüsüne düşer, **Hızlı İşlemler** altına *değil* — macOS o menüyü uygulama
uzantıları ve Kısayollar için ayırmıştır. İkisi de aynı komutu çalıştırır, tek
fark alt menü. Özellikle Hızlı İşlemler altında istiyorsan, Kısayollar
uygulamasında "Receive files and folders from Quick Actions" ile başlayan ve
`~/Applications/HerdrBar.app/Contents/MacOS/herdrbar-open "$@"` çalıştıran bir
kısayol oluştur.

## Eklenti eylemleri

| Eylem | Ne yapar |
|---|---|
| `open-picker` | Klasör seçiciyi gösterir |
| `install-finder-integration` | Hizmetler girdisini ve Birlikte Aç kaydını kurar |
| `install-login-item` | Girişte başlatan LaunchAgent'ı kurar |
| `restart-bar` | Yeni derlemeyi alması için menü çubuğu uygulamasını yeniden başlatır |

Klasör seçiciyi `~/.config/herdr/config.toml` içinde bir tuşa bağla:

```toml
[[keys.command]]
key = "prefix+o"
type = "plugin_action"
command = "herdr-topbar.open-picker"
description = "open a folder in herdr"
```

## İkon

Menü çubuğundaki simge herdr'ın kendi koçu;
[`herdr.dev/assets/ram.svg`](https://herdr.dev/assets/ram.svg) adresinden alındı.
Kaynak SVG `Resources/ram.svg` içinde duruyor; `scripts/make-icon.sh` onu koçun
kafasına kırpıp uygulamanın gerçekte paketlediği vektörel PDF'i üretiyor.

Kırpma önemli: tam markada koçun gövdesi çerçeveden taşan dolu bir kütle ve menü
çubuğu boyutunda okunmaz bir bloğa dönüşüyor. Kafaya kırpmak kıvrık boynuzu ve
`>-` istem yüzünü koruyor — 17pt'de onu tanıtan parçalar bunlar. Görsel ya da
kırpma değişirse yeniden üret:

```bash
bash scripts/make-icon.sh && bash scripts/build.sh
```

## Yapılandırma

`~/Library/Application Support/dev.herdr.topbar/config.json`:

```json
{
  "herdrBinary": "/opt/homebrew/bin/herdr",
  "terminalBundleId": "com.apple.Terminal",
  "blinkTimeoutSeconds": 180
}
```

`blinkTimeoutSeconds`, Blink Duration menüsünün aynısıdır; `0` "tıklanana kadar"
demektir. Buradan elle de düzenleyebilirsin ama uygulama bunu açılışta okur, o
yüzden elle değişiklikten sonra `scripts/restart-bar.sh` ile yeniden başlat.

`terminalBundleId` yalnızca *yeni* bir herdr başlatırken kullanılır. Açık olanı
öne getirmek, herdr sürecini gerçekte hangi terminal barındırıyorsa onu bularak
çalışır; yani terminal değiştirmen için ayar gerekmez.

## Nasıl çalışır

```
sen       ──sol tık────▶  HerdrBar ──süreç ağacı──▶ Terminal.activate()
sen       ──sağ tık────▶  HerdrBar ──JSON/unix────▶ herdr.sock
Finder    ──sağ tık────▶  herdrbar-open ──────────▶ HerdrBar
herdr     ──[[events]]─▶  forward-event.sh ───────▶ HerdrBar  (ikon yanıp söner)
```

Bilinmeye değer iki tasarım notu:

**Terminali öne getirmek hiçbir izin gerektirmez.** Terminal'i AppleScript ile
sürmek, sonradan geri alınabilen ve ikonun asıl işini sessizce bozan bir TCC
otomasyon izni sorar. Bunun yerine HerdrBar `herdr` istemci sürecini bulur, üst
süreç zincirini yürüyerek onu barındıran GUI uygulamasına ulaşır ve
`NSRunningApplication.activate()` çağırır. İzin sorulmaz ve her terminalle
çalışır.

**Bekleyen ajanlar bir eklenti kancasından gelir, socket aboneliğinden değil.**
`pane.agent_status_changed`, `events.subscribe` altında somut bir `pane_id`
ister; yani global bir biçimi yok — ama herdr'ın eklenti kancası izin listesi bu
olayı kabul ediyor, dolayısıyla her pane'i aynı anda izlemenin yolu `[[events]]`.
Menü her açıldığında tüm durum `session.snapshot`'tan yeniden türetilir; böylece
bir olay tetiklendiğinde uygulama kapalıysa bile hiçbir şey bayatlamaz.

## Sorun giderme

```bash
# Uygulama neyi görüyor?
~/Applications/HerdrBar.app/Contents/MacOS/HerdrBar --diagnose

# Anlık durum, JSON olarak
~/Applications/HerdrBar.app/Contents/MacOS/herdrbar-open --status

# Kancalar tetiklendi mi?
herdr plugin log list
```

Gerçek bir ajanı beklemeden yanıp sönmeyi denemek için, herhangi bir pane
üzerinde herdr'a gerçek bir durum olayı yaydır:

```bash
herdr pane report-agent <PANE_ID> --source selftest --agent claude --state blocked
herdr pane report-agent <PANE_ID> --source selftest --agent claude --state idle
herdr pane release-agent <PANE_ID> --source selftest --agent claude
```

Bunu `scripts/forward-event.sh`'i elle yazılmış bir yükle çağırmaya tercih et:
herdr olay verisini `{"event":…,"data":{…}}` zarfına sarar, yani düz elle
hazırlanmış bir yük herdr'ın hiç göndermediği bir biçimi test eder. Ayrıca
`herdr plugin log list` çıktısında `exit 0` görmek iletildiğini kanıtlamaz —
`forward-event.sh` bir kanca herdr'ı asla kilitlemesin diye her zaman 0 döner —
bunun yerine `--status`'a bak.

`--diagnose`; çözümlenen herdr ikilisini, sunucunun ayakta olup olmadığını, onu
hangi terminalin barındırdığını, açık çalışma alanlarını ve bekleyen ajanları
yazdırır. herdr açıkça çalışırken "host terminal: none" görünüyorsa, herdr
bağlı bir istemci olmadan çalışıyordur — bir tane başlat, düzelir.

## Gereksinimler

macOS 13 veya üzeri, herdr 0.8.0 veya üzeri ve Xcode ya da Command Line Tools
ile gelen Swift derleyicisi (`scripts/build.sh` için).

## Lisans

MIT — bkz. [LICENSE](LICENSE).

Lisans kaynak kodu kapsar. herdr'ın adını ve koç logosunu kapsamaz:
`Resources/ram.svg` herdr'a aittir ve yalnızca bu eklentinin genişlettiği aracı
tanıtmak için bulunmaktadır.
