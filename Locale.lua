-- Interface language and quest text.
-- English is the default. Turkish is offered while WoWTR (the Turkish translation addon) is
-- loaded: then the interface strings below, the quest titles and objectives come from WoWTR's
-- QTR_QuestData, and text is drawn in WoWTR's font so the Turkish letters show.
-- QL.L(text) returns the translation of an English string, or the string itself.

local _, QL = ...

local TR = {
	["Chain"] = "Zincir",
	["Quest chain"] = "Görev zinciri",
	["Quest Lineage"] = "Görev Soyağacı",
	["Search: quest name or id"] = "Ara: görev adı veya id",
	["No quest found for: "] = "Görev bulunamadı: ",
	["Building the chain index..."] = "Zincir dizini hazırlanıyor...",
	["QuestieDB is missing: QuestLineage reads its quest data from it."] = "QuestieDB yok: QuestLineage görev verisini ondan okur.",
	["This quest has no chain."] = "Bu görevin zinciri yok.",
	["Showing the nearest %d quests of a larger web."] = "Daha büyük bir ağın en yakın %d görevi gösteriliyor.",
	["%d/%d done"] = "%d/%d tamam",
	["Level %d"] = "Seviye %d",
	["Lv %d"] = "Sv %d",
	["Done"] = "Tamamlandı",
	["In your log"] = "Günlüğünde",
	["Ready to turn in"] = "Teslime hazır",
	["Available"] = "Alınabilir",
	["Locked"] = "Kilitli",
	["Level too low"] = "Seviye yetersiz",
	["Closed"] = "Kapandı",
	["Not for your character"] = "Karakterin için değil",
	["Starts: "] = "Veren: ",
	["Ends: "] = "Teslim: ",
	["Requires all of: "] = "Hepsi gerekli: ",
	["Requires one of: "] = "Biri gerekli: ",
	["Must be on: "] = "Alınmış olmalı: ",
	["Breadcrumb to: "] = "Şuna yönlendirir: ",
	["Taking it closes: "] = "Alırsan kapanır: ",
	["Taking this quest closes for good: "] = "Bu görevi alırsan kalıcı olarak kapanır: ",
	["This is a breadcrumb to: "] = "Bu görev şuna yönlendiren ön görevdir: ",
	["Click: center on it · Shift-click: link in chat"] = "Tık: ona odaklan · Shift+tık: sohbete link",
	["Chain %d/%d"] = "Zincir %d/%d",
	["next: "] = "sonraki: ",
	["last step"] = "son halka",
	["Show this quest's chain"] = "Bu görevin zincirini göster",
	["Legend: "] = "Açıklama: ",
	["requires"] = "gerekli",
	["one of"] = "biri yeter",
	["breadcrumb"] = "yönlendirme",
	["must be on"] = "alınmış olmalı",
	-- settings
	["Settings"] = "Ayarlar",
	["Use Turkish (needs WoWTR)"] = "Türkçe kullan (WoWTR gerekir)",
	["Quest titles, objectives and the interface in Turkish, from WoWTR."] = "Görev adları, hedefler ve arayüz Türkçe (WoWTR'den).",
	["Chain line on NPC tooltips"] = "NPC ipucunda zincir satırı",
	["Chain button in the quest log"] = "Görev günlüğünde Zincir butonu",
	["Chain button and warnings on the quest offer window"] = "Görev kabul penceresinde Zincir butonu ve uyarılar",
	["Hide quests your race or class can never take"] = "Irkının veya sınıfının alamayacağı görevleri gizle",
	-- slash
	["Usage: /ql lang en|tr"] = "Kullanım: /ql lang en|tr",
	["Turkish needs WoWTR; showing English until it is loaded."] = "Türkçe için WoWTR gerekir; yüklenene kadar İngilizce gösterilir.",
	["No errors."] = "Hata yok.",
	["open or close the chain window"] = "zincir penceresini aç/kapat",
	["show the chain of a quest"] = "bir görevin zincirini göster",
	["database and language status"] = "veritabanı ve dil durumu",
	["interface language"] = "arayüz dili",
	["settings"] = "ayarlar",
	["QuestieDB: "] = "QuestieDB: ",
	["Chain index: "] = "Zincir dizini: ",
	["ready"] = "hazır",
	["building"] = "hazırlanıyor",
	["WoWTR: "] = "WoWTR: ",
	["loaded"] = "yüklü",
	["not loaded"] = "yüklü değil",
	["language: "] = "dil: ",
	["Version: "] = "Sürüm: ",
	[" errors (/ql errors)"] = " hata (/ql errors)",
	["Quest #%d"] = "Görev #%d",
	-- window
	["This zone"] = "Bu bölge",
	["Search"] = "Ara",
	["Quest chains"] = "Görev zincirleri",
	["Unknown zone"] = "Bilinmeyen bölge",
	["QuestieDB is missing."] = "QuestieDB yok.",
	["QuestieDB is missing"] = "QuestieDB yok",
	["QuestLineage reads its quest data from the QuestieDB addon."] = "QuestLineage görev verisini QuestieDB eklentisinden okur.",
	["No quest data for this zone."] = "Bu bölge için görev verisi yok.",
	["No quest chains in this zone."] = "Bu bölgede görev zinciri yok.",
	["%d chains · %d open · %d quests"] = "%d zincir · %d açık · %d görev",
	["Lv %d–%d"] = "Sv %d–%d",
	["%d quests"] = "%d görev",
	["In progress"] = "Devam ediyor",
	["Completed"] = "Tamamlandı",
	["Quest name or id"] = "Görev adı veya id",
	["Type at least two letters."] = "En az iki harf yaz.",
	["No quest found."] = "Görev bulunamadı.",
	["%d quests found"] = "%d görev bulundu",
	["This takes a few seconds once per session."] = "Oturum başına bir kez, birkaç saniye sürer.",
	["Pick a quest chain"] = "Bir görev zinciri seç",
	["Choose one from this zone on the left, or search for any quest."] = "Soldan bu bölgedeki bir zinciri seç ya da herhangi bir görevi ara.",
	["%d quests · %d generations"] = "%d görev · %d nesil",
	["Wheel: scroll · Shift+wheel: sideways · drag: pan"] = "Tekerlek: kaydır · Shift+tekerlek: yana · sürükle: gezin",
	["Something went wrong: /ql errors"] = "Bir şeyler ters gitti: /ql errors",
	-- detail panel
	["No quest selected"] = "Görev seçilmedi",
	["Its details show here."] = "Ayrıntıları burada görünür.",
	["Objective"] = "Hedef",
	["Story"] = "Hikâye",
	["Tasks"] = "Yapılacaklar",
	["Start"] = "Başlangıç",
	["Turn in"] = "Teslim",
	["Rewards"] = "Ödüller",
	["Comes after"] = "Öncesi",
	["Leads to"] = "Sonrası",
	["Closes for good"] = "Kalıcı olarak kapatır",
	["Link in chat"] = "Sohbete link",
	["Open in quest log"] = "Görev günlüğünde aç",
	["Slay"] = "Öldür",
	["Collect"] = "Topla",
	["Use"] = "Kullan",
	["Reputation"] = "İtibar",
	["%d XP"] = "%d TP",
	["Faction #%d"] = "Fraksiyon #%d",
	["Starts from an item"] = "Bir eşyayla başlar",
	["needs %d"] = "en az %d",
	-- minimap button
	["Button on the minimap"] = "Mini haritada buton",
	["Click: open or close"] = "Tık: aç / kapat",
	["Right-click: settings"] = "Sağ tık: ayarlar",
	["Drag: move round the minimap"] = "Sürükle: mini harita çevresinde taşı",
}
QL.TR = TR

function QL.HasWoWTR()
	return type(QTR_QuestData) == "table"
end

function QL.UseTurkish()
	return QL.DB().lang == "tr" and QL.HasWoWTR()
end

function QL.L(text)
	if QL.UseTurkish() then
		local t = TR[text]
		if t then return t end
	end
	return text
end

local function wowtr(questId)
	if not QL.UseTurkish() then return nil end
	local row = QTR_QuestData[tostring(questId)]
	return type(row) == "table" and row or nil
end

-- A quest's title in the chosen language.
function QL.QuestTitle(questId)
	local row = wowtr(questId)
	if row and type(row.Title) == "string" and row.Title ~= "" then return row.Title end
	local name = QL.Q and QL.Q(questId, "name")
	if type(name) == "string" and name ~= "" then return name end
	return QL.L("Quest #%d"):format(questId)
end

-- A quest's objective text (one string) in the chosen language, or nil.
function QL.QuestObjectives(questId)
	local row = wowtr(questId)
	if row and type(row.Objectives) == "string" and row.Objectives ~= "" then return row.Objectives end
	local text = QL.Q and QL.Q(questId, "objectivesText")
	if type(text) == "table" then text = table.concat(text, " ") end
	if type(text) == "string" and text ~= "" then return text end
	return nil
end

-- One font everywhere: the game's Arial Narrow reads cleanly and has the Turkish letters
-- (ş ğ ı İ), so English and Turkish look the same.
local DEFAULT_FONT = "Fonts\\ARIALN.TTF"

function QL.FontPath()
	return DEFAULT_FONT
end

function QL.SetFont(fontString, size, flags)
	if not fontString or not fontString.SetFont then return end
	local ok = pcall(fontString.SetFont, fontString, QL.FontPath(), size or 12, flags or "")
	if not ok then pcall(fontString.SetFont, fontString, DEFAULT_FONT, size or 12, flags or "") end
end
