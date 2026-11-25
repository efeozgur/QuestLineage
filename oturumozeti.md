# QuestLineage — oturum özeti (26 Kasım 2026)

Kaldığımız yerden devam etmek için kısa özet. Modüllerin teknik ayrıntıları `CLAUDE.md`'de.

## Durum

- Depo: `C:\Users\ahmet\Desktop\QuestLineage`, dal `main`, GitHub: https://github.com/efeozgur/QuestLineage
- Oyuna bağlantı: `_forever_\Interface\AddOns\QuestLineage` bu klasöre junction ile bağlı; Lua değişiklikleri `/reload` ile gelir, **yeni dosya eklenince oyun tamamen yeniden başlatılmalı**.
- Testler: `C:\Users\ahmet\AppData\Local\Programs\Python\Python311\python.exe tests/run.py` (8 dosya, hepsi geçiyor).
- Oyunda hata ayıklama: `/ql hedef [id]` (hedeflerin kaynağı), `/ql kart` (görev kartı), `/ql arrow`, `/ql errors`.

## Başka bilgisayarda devam etmek

1. Depoyu indir:
   `git clone https://github.com/efeozgur/QuestLineage.git`
2. Oyuna bağla. Klasörü kopyalamak yerine bağlantı kur ki değişiklikler doğrudan oyuna yansısın. Yolları o bilgisayara göre düzelt; komut istemi yönetici olarak açılmalı:
   `mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\QuestLineage" "C:\...\QuestLineage"`
3. Oyunda gerekenler:
   - **QuestieDB** eklentisi gerekli; QuestLineage görev verisini onun `LibQuestieDB` arayüzünden okur.
   - **WoWTR** isteğe bağlı (Türkçe).
   - **WoWTR_Voices** isteğe bağlı (görev kartındaki hoparlör).
4. Testler için Python 3 ve `pip install lupa`. Sonra depo klasöründe:
   `python tests/run.py`
5. Claude Code'u depo klasöründe aç ve ilk mesajda "oturumozeti.md'yi oku, kaldığımız yerden devam edelim" de. Diğer bilgisayardaki hafıza notları oraya taşınmaz; bu dosya ve `CLAUDE.md` yeterli.

## Bu oturumda eklenenler

- **İsim plakaları:** rozet ayarları (aç/kapa, konum, renk, boyut, yatay kaydırma, sayaç, düşürenler).
- **Güncel görev penceresi:**
  - hedefler ve tamamlanma oranı ("2/3 hedef · %70" + çubuk);
  - daraltılınca "N hedef gizli · sağ tık: göster";
  - altında GÖREVLER listesi: Tümü/Bölge/Sınıf/Zincir filtreleri, listelenecek görev sayısı, her satırda bütün hedefler, satır başına ve tümüne simge durumuna küçültme, satır başında görevi bırakma (×).
- **Oyunun kendi görev takipçisi** ayardan gizlenebiliyor.
- **Görevi bırakma:** onay penceresiyle; güncel görevde, listede ve ana pencerede.
- **Haritalar:**
  - güncel görevin alanları (yumuşak dolgu + ince çember, yavaş nefes alma);
  - diğer görevlerin alanları (soluk noktalı çember, her görev kendi renginde);
  - üzerine gelince hedefi ve görevi söyleyen ipucu;
  - oyunun mavi alanını gizleme.
- **Ceset yolu:** ölünce mini haritada ve dünya haritasında cesede giden yol; ok da cesede döner.
- **Görev kartı** (oyunun NPC pencereleri yerine):
  - NPC'nin görev listesi, görev alma, devam eden görev, ödül seçimi ve teslim;
  - zincir kutusu;
  - "Görevi Görev Listesinde Göster";
  - WoWTR Voices hoparlörü (kendiliğinden okuma ayarı, varsayılan kapalı);
  - oyunun penceresini gizleme ayarı.
- **Kabul edilen görev** güncel görev oluyor.
- **Yakındaki diğer görevler kartı:** hedef, isim plakası ya da alan; bekleme süresi ayarlanabilir.
- **Ana pencere:** Görevler sekmesinde zincir görevleri yok (Zincirler sekmesinde).
- **Ayarlar sayfası:** solda menü (Genel, Görev takibi, Haritalar, Ok, İsim plakaları), gruplar ve her ayarda açıklama.

## Oyunda henüz denenmedi

- Haritadaki halkaların yeni görünümü.
- Görev kartının görev listesi ve teslim ekranları; gizleme ayarı açıkken NPC seçenekleri.
- Yakındaki görev kartları.
- Görev bırakma.

## Bekleyen fikirler

- İsim plakası rozeti için dikey kaydırma sürgüsü.
- Güncel görev başlığındaki × düğmesini de başa almak.
- Oyunda gördükten sonra halkaların opaklığını ince ayarlamak.
- Depo herkese açıksa `CLAUDE.md`'nin depoda kalıp kalmayacağı.
