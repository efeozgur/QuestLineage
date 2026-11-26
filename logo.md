# QuestLineage logo promptu

Kullanılan logo: `logo.png` (kaynak, 1254x1254). Oyun için `Media/icon.tga` (128x128, dairesel alfa) ondan üretildi: toc'taki `IconTexture` ve minimap düğmesi onu kullanıyor.

Addon: World of Warcraft için görev zinciri ağaçları, yön oku, harita rotaları. Arayüzün dili: koyu lacivert zemin, turkuaz -> mor geçiş, ince çizgiler, düz ve modern (oyunun kendi altın/parşömen stilinden bilerek farklı).

## Ana prompt (İngilizce, görsel üretici için)

```
A modern, minimalist app-style logo icon for a World of Warcraft addon called "QuestLineage".
Concept: a quest chain family tree. A small glowing node at the top connected by thin
lines to two nodes below it, which branch again into a third row, forming a clean
tree/lineage diagram. One of the nodes, the "current quest", is larger and carries a
small rounded direction arrow pointing up and to the right.
Style: flat vector, crisp geometry, soft rounded corners, subtle inner glow on the nodes,
thin 2px-style connecting lines, a faint soft shadow. No fantasy ornaments, no scrolls,
no swords, no text.
Colors: deep navy background (#0E1015), nodes and lines in a gradient from teal (#3DD6C6)
to violet (#8B7CF6), the current-quest node brighter with a soft teal glow, tiny warm
amber accent (#FBBF24) on a single node.
Shape: square canvas with a large rounded-corner tile (app icon look), centered composition,
generous padding, readable even at 32x32 pixels.
High resolution, 1024x1024, clean edges, transparent or flat dark background, no watermark.
```

## Negatif prompt (destekleyen araçlar için)

```
text, letters, words, watermark, signature, realistic photo, 3d render, heavy gradients,
clutter, fantasy frame, gold border, parchment, sword, shield, dragon, blurry, noisy,
low contrast, extra limbs, cropped
```

## Varyasyonlar

- **Yalnızca simge, yuvarlak (minimap düğmesi):** aynı prompt, "circular badge instead of rounded square, centered tree of nodes inside a thin teal ring".
- **Yatay logo (GitHub/CurseForge başlığı):** "horizontal lockup: the icon on the left, the word 'QuestLineage' on the right in a clean geometric sans-serif (Inter style), 'Quest' in white and 'Lineage' in a teal-to-violet gradient, dark navy background, 1600x400".
- **Sade tek renk:** "monochrome white version of the same logo on transparent background, solid shapes, no gradients".

## Notlar

- Küçük boyutta okunması önemli: 16-32 piksel olduğunda ağaç üç düğüm + bir ok kalacak kadar sade kalmalı.
- Oyun içinde kullanım için: 64x64 ve 128x128 `.tga` (alfa kanallı, 32 bit) olarak dışa aktar; addon klasörüne `Media\logo.tga` olarak koyarsan toc'taki `## IconTexture` ve minimap düğmesinde kullanılabilir.
- Renkler addon'un temasıyla aynı: koyu zemin `#0E1015`, turkuaz `#3DD6C6`, mor `#8B7CF6`, amber `#FBBF24`.
