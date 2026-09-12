---
title: Unicode, emoji and caret-positioning QA
purpose: manual QA for text measurement, caret placement and preview rendering
---

# Unicode and emoji torture test

Open this file in the editor and read it in the preview side by side. The editor
measures one monospace cell and places the caret by column, so anything that is
not exactly one cell wide is a candidate for drift.

What to look for:

- **Caret drift** — click at the end of a line, then walk left with the arrow
  keys. The caret should land between glyphs, never inside one, and should reach
  column 0 in exactly as many presses as there are characters you can see.
- **Selection boxes** — drag-select a line containing emoji or CJK. The
  highlight should cover the glyphs, not stop short or overhang.
- **Glyph splitting** — a family emoji that renders as four separate people, or
  a flag that renders as two letters in boxes, means the font or the shaper lost
  the sequence.
- **Combining marks** — an accent that sits over the wrong letter, or drifts
  into the next column, is a measurement bug.
- **Alignment** — section 7 is the most useful signal in this file. Those grids
  are supposed to line up perfectly in a monospace context. If the `|` columns
  wander, the editor's cell model disagrees with the font.

Check every section in both the editor pane and the preview pane; they use
different fonts and can fail independently.

---

## 1. Basic emoji

Faces in prose: the build went green 🎉 and nobody had to be paged 😴, though
the reviewer was skeptical 🤨 and the intern was terrified 😱. By Friday we were
all 🥲.

Animals in prose: a 🐈 sat on the 🐕 bed while a 🦊 watched from the hedge and a
🐙 did something unspeakable in the aquarium.

Food in prose: 🍕 for the release, 🍣 for the retro, ☕ for everything else, and
🍰 because it was somebody's birthday.

Lists, one category per block:

Faces and people:

- 😀 grinning face
- 🙃 upside-down face
- 🤔 thinking face
- 😭 loudly crying face
- 🫠 melting face
- 🧑‍🦰 person, red hair

Animals and nature:

- 🐢 turtle
- 🦋 butterfly
- 🐝 honeybee
- 🌻 sunflower
- 🌋 volcano
- 🦑 squid

Food and drink:

- 🥐 croissant
- 🌮 taco
- 🍜 steaming bowl
- 🧀 cheese wedge
- 🍺 beer mug
- 🫖 teapot

Objects:

- 💻 laptop
- 🔧 wrench
- 📎 paperclip
- 🧲 magnet
- 🕰️ mantelpiece clock
- 🔋 battery

Symbols:

- ✅ check mark button
- ❌ cross mark
- ⚠️ warning
- ♻️ recycling symbol
- ⏳ hourglass not done
- ⚙️ gear

Flags:

- 🇳🇴 Norway
- 🇯🇵 Japan
- 🇺🇸 United States
- 🇩🇪 Germany
- 🇧🇷 Brazil
- 🏴󠁧󠁢󠁳󠁣󠁴󠁿 Scotland (tag sequence)

Mixed into a numbered list, which is where list markers and wide glyphs argue:

1. 🍳 Start the coffee ☕
2. 🚇 Get on the train 🚉
3. 💻 Open the editor 📝
4. 🐛 Find the bug 🔍
5. 🚀 Ship it ✨

---

## 2. Multi-codepoint emoji

Every line here is a single grapheme cluster that *should* render as one glyph.
If you see the components separately, that is the bug.

Skin-tone modifiers (base + U+1F3FB..U+1F3FF) — should be one hand, five shades,
never a hand followed by a colour swatch:

- 👋 waving hand, no modifier
- 👋🏻 waving hand, light skin tone
- 👋🏼 waving hand, medium-light skin tone
- 👋🏽 waving hand, medium skin tone
- 👋🏾 waving hand, medium-dark skin tone
- 👋🏿 waving hand, dark skin tone
- 🧑🏽‍🚀 astronaut with medium skin tone (modifier *and* ZWJ in one cluster)

ZWJ sequences — families. Should be one group portrait, not two to four
separate people with no visible joiner:

- 👨‍👩‍👧 family: man, woman, girl (3 people, 2 ZWJ)
- 👨‍👩‍👧‍👦 family: man, woman, girl, boy (4 people, 3 ZWJ)
- 👩‍👩‍👦 family: woman, woman, boy
- 👨‍👨‍👧‍👧 family: man, man, girl, girl
- 🧑‍🧑‍🧒 family: adult, adult, child (gender-neutral)

ZWJ sequences — professions. Should be one person holding/wearing the object,
not a person followed by a laptop, book, or microscope:

- 👩‍💻 woman technologist (woman + ZWJ + laptop)
- 👨‍🍳 man cook (man + ZWJ + cooking)
- 🧑‍🔬 scientist (person + ZWJ + microscope)
- 👩🏿‍🏫 woman teacher, dark skin tone (base + modifier + ZWJ + book)
- 🧑‍🚒 firefighter
- 👨‍⚕️ man health worker (note the variation selector on the staff of Aesculapius)

ZWJ sequences — couples. Should be one couple, not two people with a floating
heart between them:

- 💑 couple with heart (single codepoint, for comparison)
- 👩‍❤️‍👨 couple with heart: woman, man (person + ZWJ + heart + VS16 + ZWJ + person)
- 👨‍❤️‍👨 couple with heart: man, man
- 👩‍❤️‍💋‍👨 kiss: woman, man (four components, three ZWJ)
- 🧑‍🤝‍🧑 people holding hands (gender-neutral)
- 👩🏽‍❤️‍👨🏿 couple with heart, two different skin tones

Other ZWJ constructions — should be one glyph each:

- 🏳️‍🌈 rainbow flag (white flag + VS16 + ZWJ + rainbow)
- 🏳️‍⚧️ transgender flag
- 🏴‍☠️ pirate flag (black flag + ZWJ + skull and crossbones)
- 😶‍🌫️ face in clouds
- ❤️‍🔥 heart on fire
- 🐻‍❄️ polar bear (bear + ZWJ + snowflake)
- 👁️‍🗨️ eye in speech bubble

Keycap sequences (digit/`#`/`*` + U+FE0F + U+20E3) — should be a key, not a
bare digit followed by an empty box:

- 0️⃣ keycap digit zero
- 1️⃣ keycap digit one
- 5️⃣ keycap digit five
- 9️⃣ keycap digit nine
- 🔟 keycap ten (single codepoint, for comparison)
- #️⃣ keycap number sign
- *️⃣ keycap asterisk

Variation selectors — the *same* base character in text (VS15, U+FE0E) and emoji
(VS16, U+FE0F) presentation. The left one should be a flat monochrome glyph, the
right one a colour emoji, and both should sit in the same run of text:

- Heart: ❤︎ text presentation vs ❤️ emoji presentation (U+2764)
- Sun: ☀︎ text vs ☀️ emoji (U+2600)
- Snowman: ☃︎ text vs ☃️ emoji (U+2603)
- Umbrella: ☂︎ text vs ☂️ emoji (U+2602)
- Airplane: ✈︎ text vs ✈️ emoji (U+2708)
- Warning: ⚠︎ text vs ⚠️ emoji (U+26A0)
- Pencil: ✏︎ text vs ✏️ emoji (U+270F)
- Watch: ⌚ default emoji presentation, no selector needed (U+231A)
- Bare, no selector at all: ❤ ☀ ☃ ☂ ✈ ⚠ ✏ — the font decides, and the editor
  and preview may decide differently, which is itself worth noting.

Regional-indicator flags (two U+1F1E6..U+1F1FF letters, one flag). Should be a
flag, never two boxed letters. Note the adjacency test at the end — consecutive
flags must not re-pair across the boundary:

- 🇳🇴 NO — Norway
- 🇸🇪 SE — Sweden
- 🇩🇰 DK — Denmark
- 🇫🇮 FI — Finland
- 🇮🇸 IS — Iceland
- 🇪🇺 EU — European Union
- 🇺🇳 UN — United Nations
- Adjacency: 🇳🇴🇸🇪🇩🇰🇫🇮🇮🇸 should read Norway, Sweden, Denmark, Finland, Iceland
  — exactly five flags, no mystery sixth flag formed from the seam.
- Lone regional indicator: 🇳 on its own should be a boxed letter N, not half a
  flag stolen from the next line.

Tag sequences (black flag + tag characters + cancel tag) — the subdivision flags:

- 🏴󠁧󠁢󠁥󠁮󠁧󠁿 England
- 🏴󠁧󠁢󠁳󠁣󠁴󠁿 Scotland
- 🏴󠁧󠁢󠁷󠁬󠁳󠁿 Wales

Newer multi-person and multi-component sequences (Emoji 14+, where older fonts
fall back to the components):

- 🧑‍🤝‍🧑 people holding hands
- 👩🏻‍🤝‍👨🏿 woman and man holding hands, different skin tones
- 🧑‍🍼 person feeding baby
- 🫱🏼‍🫲🏾 handshake with two skin tones (a two-component handshake — the most
  fragile sequence in this file)
- 🧑‍🦯 person with white cane
- 🧑‍🦼 person in motorized wheelchair
- 🧑‍⚖️ judge
- 🧑‍🎄 mx claus
- 🫂 people hugging (single codepoint)
- 🩷 🩵 🩶 newer hearts, single codepoints, common fallback boxes

Counting test — this line is exactly ten grapheme clusters, and the caret should
take ten left-arrow presses to cross it:

👨‍👩‍👧‍👦👋🏽🏳️‍🌈1️⃣🇳🇴🧑‍💻❤️‍🔥🫱🏼‍🫲🏾😀🐻‍❄️

---

## 3. Diacritics and combining marks

Precomposed (NFC) versus decomposed (NFD). Each pair should look identical but
has a different character count — the second of each pair is base letter plus a
combining mark, so the caret needs one extra press to cross it:

- é U+00E9 vs é U+0065 U+0301
- ü U+00FC vs ü U+0075 U+0308
- ñ U+00F1 vs ñ U+006E U+0303
- å U+00E5 vs å U+0061 U+030A
- ç U+00E7 vs ç U+0063 U+0327
- ø U+00F8 — no decomposition exists; the stroke is part of the letter
- Ǻ U+01FA vs Ǻ U+0041 U+030A U+0301 (two stacked marks)

Whole-word NFC vs NFD comparison — same word, same appearance, different byte
length. Selecting either should select the whole word:

- NFC: `résumé naïve Ångström Öresund façade`
- NFD: `résumé naïve Ångström Öresund façade`
- NFC: `København` — NFD: `København`

Nordic:

- æ ø å Æ Ø Å
- Blåbærsyltetøy på rundstykker med smør.
- Ærlig talt, øvelse gjør mester — så ål i ålegress.
- Icelandic: þ ð Þ Ð — Þorsteinn frá Hafnarfirði, hérað, Eyjafjallajökull.
- Faroese: Tórshavn, oyggj, ærligur.

German:

- ä ö ü Ä Ö Ü ß ẞ
- Größenwahn, Straßenbahn, Füße, Äpfel, Öl, Übermut.
- Capital sharp s: STRASSE vs STRAẞE (U+1E9E, often missing from fonts).

Polish:

- ą ć ę ł ń ó ś ź ż Ą Ć Ę Ł Ń Ó Ś Ź Ż
- Zażółć gęślą jaźń — the Polish pangram, every diacritic in one line.
- Łódź, Częstochowa, Świętokrzyskie, Gdańsk.

Czech and Slovak (carons and the ring):

- č ď ě ň ř š ť ů ž Č Ď Ě Ň Ř Š Ť Ů Ž
- Příliš žluťoučký kůň úpěl ďábelské ódy.
- ĺ ľ ŕ ŧ — Slovak additions; dĺžeň on ĺ and ŕ.

Turkish (the dotted/dotless i, the classic case-folding trap):

- ı I (dotless i, capital I) vs i İ (dotted i, capital İ)
- ğ ş ç ö ü Ğ Ş Ç Ö Ü
- Iğdır, Diyarbakır, İstanbul, Şanlıurfa, Çanakkale.
- Case test: `istanbul` uppercases to `İSTANBUL` in Turkish, `ISTANBUL`
  elsewhere; `ILIK` lowercases to `ılık`.

Vietnamese — the stacked-mark stress test. Every syllable carries a vowel
modifier, a tone mark, or both, and many need two marks on one base:

- Tiếng Việt rất đẹp và khó đánh máy.
- Phở bò, bánh mì, cà phê sữa đá, chả giò.
- ế ề ể ễ ệ — e-circumflex under all five tones
- ố ồ ổ ỗ ộ — o-circumflex under all five tones
- ớ ờ ở ỡ ợ — o-horn under all five tones
- ứ ừ ử ữ ự — u-horn under all five tones
- Nguyễn Thị Thanh Hương, Đà Nẵng, Quảng Ngãi, Vũng Tàu.
- NFC vs NFD of the same phrase: `Tiếng Việt` vs `Tiếng Việt`

Pathological stacking — many combining marks on one base, which should stay in
one column and not overlap the neighbours:

- a + U+0308 U+030A U+0301 rendered: ä̊́
- Zalgo-lite: ḥ̈e̛̋l̤̓l̨͂o̗̔
- A long mark run on one base: ȩ̨́̂̃̄̆̇̈̊̋̌

---

## 4. Scripts

Greek:

- Αα Ββ Γγ Δδ Εε Ζζ Ηη Θθ Ιι Κκ Λλ Μμ Νν Ξξ Οο Ππ Ρρ Σσς Ττ Υυ Φφ Χχ Ψψ Ωω
- Ἐν ἀρχῇ ἦν ὁ λόγος — polytonic, with breathings and iota subscript.
- Τάχιστη αλεπού βαφής ψημένη γη, δρασκελίζει υπέρ νωθρού κυνός.
- Final sigma test: ΟΔΟΣ lowercases to οδός, and `ΣΟΦΟΣ` to `σοφός`.

Cyrillic:

- Аа Бб Вв Гг Дд Ее Ёё Жж Зз Ии Йй Кк Лл Мм Нн Оо Пп Рр Сс Тт Уу Фф Хх Цц Чч Шш Щщ Ъъ Ыы Ьь Ээ Юю Яя
- Съешь же ещё этих мягких французских булок, да выпей чаю.
- Ukrainian: ґ є і ї — Ґлей, Київ, Україна.
- Serbian: љ њ џ ћ ђ — Београд, Ниш, Ђорђе.
- Homoglyph trap: Latin `ADEKMHOPCTXBa` vs Cyrillic `АDЕКМНОРСТХВа` — these look
  alike and must still be selectable and searchable as distinct characters.

Hebrew (RTL):

- א ב ג ד ה ו ז ח ט י כ ל מ נ ס ע פ צ ק ר ש ת
- שלום עולם — hello world.
- With niqqud (combining vowel points under consonants): בְּרֵאשִׁית בָּרָא אֱלֹהִים
- Final forms: ך ם ן ף ץ — these appear only at word end: מים, ארץ, שלום.

Arabic (RTL, with contextual shaping — letters change form by position):

- ا ب ت ث ج ح خ د ذ ر ز س ش ص ض ط ظ ع غ ف ق ك ل م ن ه و ي
- مرحبا بالعالم — hello world.
- العربية لغة جميلة ومعقدة في الطباعة.
- Ligature test: لا (lam-alef) must render as one glyph.
- With harakat (combining diacritics): بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
- Persian and Urdu extensions: پ چ ژ گ — پارسی, اردو, ٹھیک.

Devanagari (complex conjuncts and reordering vowel signs):

- अ आ इ ई उ ऊ ए ऐ ओ औ क ख ग घ च छ ज झ ट ठ ड ढ त थ द ध न प फ ब भ म य र ल व श ष स ह
- नमस्ते दुनिया — hello world.
- हिन्दी भारत की राजभाषा है।
- Conjuncts: क्ष त्र ज्ञ श्र द्ध ट्ट — each is multiple consonants in one cluster.
- Reordering: कि places the i-vowel *before* the consonant it follows logically.
- Bengali for contrast: আমি বাংলায় গান গাই। — Tamil: வணக்கம் உலகம்

Thai — no spaces between words, and vowels/tones stack above and below:

- สวัสดีชาวโลก
- ภาษาไทยเขียนติดกันโดยไม่มีการเว้นวรรคระหว่างคำ
- Stacked marks: ที่ ไม่ ให้ เป็น น้ำ — note the tone mark above the vowel above
  the consonant.
- Line breaking here is dictionary-based; watch where the preview chooses to
  wrap a long run: ประเทศไทยมีประชากรประมาณเจ็ดสิบล้านคนและมีภาษาราชการคือภาษาไทย

CJK — Chinese:

- Simplified: 你好世界，这是一个测试文件。
- Traditional: 你好世界，這是一個測試檔案。
- Full sentence: 中文字符在等宽字体中通常占两个字符宽度。
- Punctuation is also full width: 。、，！？：；「」『』（）

CJK — Japanese, all three scripts in one line:

- Hiragana: あいうえお かきくけこ さしすせそ たちつてと なにぬねの
- Katakana: アイウエオ カキクケコ サシスセソ タチツテト ナニヌネノ
- Kanji: 日本語 漢字 東京 大阪 京都 新幹線 図書館
- Mixed: 私はエディタでマークダウンを書きます。Fence は Elm と Electron で作られています。
- Small kana and long vowel marks: きゃ きゅ きょ ファイル コーヒー ヴァイオリン
- Half-width katakana (should be *one* cell, unlike the full-width above):
  ﾊﾝｶｸ ｶﾀｶﾅ ﾃｽﾄ

CJK — Korean:

- Hangul syllables: 안녕하세요 세계
- Jamo composition: ㅎ + ㅏ + ㄴ = 한, ㄱ + ㅡ + ㄹ = 글 → 한글
- Sentence: 한국어는 한글로 씁니다. 마크다운 편집기 테스트입니다.
- Decomposed jamo (should compose visually into the same syllables): 한글

Mixed LTR/RTL paragraph — the cursor should move visually-sensibly and the
selection should not jump wildly across the direction boundary:

The config key is مفتاح التكوين and the default value is صحيح, unless the
environment variable `FENCE_LOCALE` is set to `he-IL`, in which case שלום takes
precedence over the fallback مرحبا defined in `defaults.json`.

Bidirectional text with embedded numbers — numbers run LTR inside an RTL run,
so the digits should read left to right even though the words read right to left:

- Arabic with Western digits: لدينا 42 ملفًا و 1024 سطرًا في 7 مجلدات.
- Arabic with Arabic-Indic digits: لدينا ٤٢ ملفًا و ١٠٢٤ سطرًا.
- Hebrew with numbers and a date: יש לנו 3 קבצים מתאריך 12/09/2026 בגודל 1.5 MB.
- Nested: The price is ١٢٣٤ ريال (about 330 USD) as of 2026.
- Mirrored brackets: (مرحبا) [שלום] {نص} — the brackets should visually mirror.

---

## 5. Width edge cases

Full-width versus half-width forms of the same characters. The first row should
be twice as wide as the second in any correct monospace rendering:

- Full-width latin: ＡＢＣＤＥＦＧ　１２３４５６７　！＠＃＄％
- Half-width latin: ABCDEFG 1234567 !@#$%
- Full-width katakana: アイウエオカキクケコ
- Half-width katakana: ｱｲｳｴｵｶｷｸｹｺ
- Full-width punctuation: （）［］｛｝：；，．
- Half-width punctuation: ()[]{}:;,.

CJK inside a table — the cells should keep their column edges in the preview
even though the source columns cannot line up in the editor:

| Key | English | 日本語 | 中文 | 한국어 | Emoji |
| --- | --- | --- | --- | --- | --- |
| `open` | Open file | ファイルを開く | 打开文件 | 파일 열기 | 📂 |
| `save` | Save | 保存 | 保存 | 저장 | 💾 |
| `find` | Find and replace | 検索と置換 | 查找和替换 | 찾기 및 바꾸기 | 🔍 |
| `theme` | Theme | テーマ | 主题 | 테마 | 🎨 |
| `quit` | Quit | 終了 | 退出 | 종료 | 👋🏽 |

CJK inside a fenced code block, where column alignment matters most. The `|`
characters below should form straight vertical lines if CJK is measured as two
cells:

```text
+--------+--------+--------+
| abcdef | ghijkl | mnopqr |
+--------+--------+--------+
| 日本語者 | 中文字符 | 한국어글 |
+--------+--------+--------+
| ｱｲｳｴｵｶ | ＡＢＣ | abcdef |
+--------+--------+--------+
```

Combining marks inside inline code: `café` (NFC) and `café` (NFD) and
`Việt` and `ǻ` and `n͡g` — these should stay inside the code span's
background and not spill over its edge.

Combining marks inside a fenced block, where the accent must not shift the
column of what follows:

```text
abcde|fghij
ábćdé|fǵhíj
àbčdè|fĝhîj
a◌́b◌̈c◌̊d◌̃e|fghij
```

An emoji inside a heading, a table cell, a link, a code span and a fence:

### 🚀 Heading with an emoji and 日本語 and a flag 🇳🇴

| Where | Sample |
| --- | --- |
| Table cell | 🎉 party popper in a cell |
| Wide cell | 🧑🏽‍🚀 astronaut with a modifier in a cell |
| Flag cell | 🇯🇵 regional indicator pair in a cell |

- Link text with emoji: [📖 Read the docs 日本語 🇳🇴](https://example.com/docs)
- Link with emoji in the URL text: [https://example.com/🚀](https://example.com/)
- Code span with emoji: `console.log("🚀 launch 日本語")`
- Bold with emoji: **🔥 hot path 🔥** and italic *✨ sparkle ✨*
- Blockquote with emoji:

> 🗣️ "Ship it," they said. 日本語でも大丈夫。🇳🇴

Fenced block with emoji, where the caret has to survive wide glyphs in a
monospace context:

```javascript
const status = {
  ok: "✅",       // check mark
  fail: "❌",     // cross mark
  warn: "⚠️",     // warning, with VS16
  busy: "⏳",     // hourglass
  user: "🧑‍💻",    // ZWJ sequence
  flag: "🇳🇴",     // regional indicators
};
console.log(`${status.ok} 完了 / 완료 / done`);
```

Very long line with mixed widths, for horizontal-scroll and caret testing — put
the caret at the far right and hold the left arrow:

日本語 abc 🚀 한국어 def 🇳🇴 中文 ghi 👨‍👩‍👧‍👦 عربى jkl ไทย mno é́ pqr ＡＢＣ stu ｱｲｳ vwx 🫱🏼‍🫲🏾 yz END

---

## 6. Whitespace and invisible characters

Everything in this section is *supposed* to look wrong or look like nothing.
These characters are invisible by design, so judge them by behaviour: the caret
should still need one press per character to cross them, selection should reveal
them as highlighted gaps, and the word "GAP" markers below bracket each sample so
you can see where the character lives.

To confirm one is really there: select the whole line and watch the highlight, or
put the caret just before the closing bracket and press left once — it should
land inside the brackets, not jump past them.

- Non-breaking space U+00A0 — a space that never breaks a line:
  `[GAP GAP]` and in prose: 10 kg, 5 °C, Mr. Smith, 100 %.
  A long run that must not wrap between the words: this phrase stays together no matter how narrow the pane becomes.
- Zero-width space U+200B — a break opportunity with no width:
  `[GAP​GAP]` and inside a word: super​cali​fragilistic​expiali​docious.
  Selecting the word should show one extra caret stop per invisible break.
- Zero-width non-joiner U+200C — prevents ligature/joining:
  `[GAP‌GAP]` and in Persian, where it separates word parts: می‌روم vs میروم.
- Zero-width joiner U+200D — the emoji glue, on its own here with no emoji around
  it: `[GAP‍GAP]`. Two unrelated characters joined: a‍b should stay "ab".
- Soft hyphen U+00AD — invisible until the line breaks there:
  `[GAP­GAP]` and in a long word: Donau­dampf­schiff­fahrts­gesell­schafts­kapitän.
  Narrow the preview pane until it wraps; a hyphen should appear at the break.
- Thin space U+2009 — narrower than a normal space:
  `[GAP GAP]` and between digits: 1 000 000 and before punctuation
  French-style: Bonjour ! Ça va ?
- Hair space U+200A, even narrower: `[GAP GAP]`
- Ideographic space U+3000 — full width, two cells:
  `[GAP　GAP]` and in Japanese: 日本語　の　文章　です。
  Compare against a normal ASCII space: 日本語 の 文章 です。
- Figure space U+2007 (digit width): `[GAP GAP]` and 1 234
- Narrow no-break space U+202F: `[GAP GAP]`
- Word joiner U+2060 (zero width, prevents breaks): `[GAP⁠GAP]`
- Byte order mark / zero-width no-break space U+FEFF: `[GAP﻿GAP]`
- Combining grapheme joiner U+034F: `[GAP͏GAP]`

Mixed line — six different invisible characters between the letters, so the caret
needs far more presses than there are visible glyphs:

`a b​c‌d­e f　g`

Tabs versus spaces, which are visible only by their width:

```text
a	b	c	(tab separated)
a   b   c   (space separated)
	indented with one tab
    indented with four spaces
日本語	x	(tab after wide characters)
```

Trailing whitespace on the next line (three spaces after "end"):

this line has trailing spaces after end   

---

## 7. Alignment grids

This is the most useful section in the file. Every line inside each block below
is supposed to have the **same visual width**, with the `|` characters forming
perfectly straight vertical columns. Drift means the editor's cell model
disagrees with what the font actually draws.

Read each block twice: once in the editor pane, once in the preview's code
block. They can fail independently.

### 7.1 ASCII baseline — must be perfect

```text
|--------|--------|--------|--------|
|aaaaaaaa|bbbbbbbb|cccccccc|dddddddd|
|12345678|87654321|abcdefgh|hgfedcba|
|........|........|........|........|
|--------|--------|--------|--------|
```

### 7.2 ASCII versus CJK — CJK cells hold four wide characters against eight narrow ones

```text
|--------|--------|--------|--------|
|abcdefgh|ijklmnop|qrstuvwx|yz012345|
|日本語者|中文字符|한국어글|漢字仮名|
|ＡＢＣＤ|ＥＦＧＨ|１２３４|５６７８|
|abcdefgh|日本語者|qrstuvwx|한국어글|
|--------|--------|--------|--------|
```

### 7.3 Emoji grid — each emoji cell holds four emoji against eight ASCII columns

```text
|--------|--------|--------|--------|
|abcdefgh|ijklmnop|qrstuvwx|yz012345|
|🚀🎉🔥✨|🐢🦋🐝🌻|🍕🍣🍰☕|💻🔧📎🧲|
|✅❌⚠️♻️|⏳⚙️🔋🕰️|😀🙃🤔😭|🥐🌮🍜🧀|
|abcdefgh|🚀🎉🔥✨|qrstuvwx|🐢🦋🐝🌻|
|--------|--------|--------|--------|
```

### 7.4 Multi-codepoint emoji grid — the hardest case, four clusters per cell

```text
|--------|--------|--------|--------|
|abcdefgh|ijklmnop|qrstuvwx|yz012345|
|👋🏻👋🏼👋🏽👋🏾|🇳🇴🇸🇪🇩🇰🇫🇮|1️⃣2️⃣3️⃣4️⃣|🧑‍💻👩‍🍳🧑‍🔬👨‍⚕️|
|👨‍👩‍👧‍👦👩‍❤️‍👨🏳️‍🌈🐻‍❄️|🫱🏼‍🫲🏾🧑‍🤝‍🧑👩🏽‍🏫🧑‍🚒|❤️‍🔥😶‍🌫️🏴‍☠️👁️‍🗨️|🩷🩵🩶🫂|
|--------|--------|--------|--------|
```

### 7.5 Combining marks — accented cells must occupy the same columns as plain ones

```text
|--------|--------|--------|--------|
|abcdefgh|ijklmnop|qrstuvwx|yz012345|
|ábćdéfǵh|íjḱlḿnóp|q́rśtúvẃx|ýź012345|
|àbčdêfĝh|ïjǩlm̃nõp|q̌rštûvŵx|ÿz̃012345|
|a◌́b◌̈c◌̊d|e◌̃f◌̄g◌̆h|i◌̇j◌̉k◌̌l|m◌̋n◌̏o◌̑p|
|--------|--------|--------|--------|
```

### 7.6 Mixed everything — the integration test

```text
+--------+--------+--------+--------+
| ascii  | 日本語 | emoji  | accent |
+--------+--------+--------+--------+
| abcdef | 日本語者 | 🚀🎉🔥 | ábćdéf |
| 123456 | 中文字符 | 🇳🇴🇸🇪🇩🇰 | íjḱlḿn |
| !@#$%^ | 한국어글 | 👨‍👩‍👧‍👦👋🏽🏳️‍🌈 | q̌rštûv |
| ｱｲｳｴｵｶ | ＡＢＣ | ⏳⚙️🔋 | ÿz̃0123 |
+--------+--------+--------+--------+
```

### 7.7 Ruler — count columns against the scale

```text
         1         2         3         4         5
1234567890123456789012345678901234567890123456789012345
abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabc
日本語日本語日本語日本語日本語日本語日本語日本語日本語
🚀🎉🔥✨🚀🎉🔥✨🚀🎉🔥✨🚀🎉🔥✨🚀🎉🔥✨🚀🎉🔥✨🚀🎉🔥✨
ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ
áéíóúáéíóúáéíóúáéíóúáéíóúáéíóúáéíóúáéíóúáéíóúáéíóúáéíóú
```

Each line above is meant to span the same 55-column ruler width: the ASCII rows
at one cell per character, the CJK and full-width rows at two cells per
character, the emoji row at two cells per emoji, and the accented row at one
cell per base letter regardless of the mark. Any row that ends short or long is
the finding worth reporting.
