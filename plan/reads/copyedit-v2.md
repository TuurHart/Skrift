# Copy-edit v2 beside v1 (Q424)

Copy-edit v2 over the 109-note synthetic corpus, replaying the model outputs v1 recorded
(Q423) plus 22 new ones (titles and summaries that now read without picture markers or links).
**68 notes are identical to v1; 41 changed**, every one registered to a clause.

The big change: v2 checks the model's output before shipping it. If the edit drops a word that
is not um/uh/eh, translates, or invents a name, the note ships with your words unedited
(fillers included), still split into paragraphs if it was a spoken wall. That is why the
pricing ramble keeps "Okay so, um" and the code-switch note keeps its English. Judge whether
that trade is right: on this corpus it fires on 20 notes.

Pictures now return after the same-numbered paragraph of the edit (C30). When the phone wrote
a note as one paragraph with the pictures inside it, all its pictures land after that
paragraph (pic-three-spread, pic-wall): the paragraph, not the sentence, is the unit.

Shown: only the parts that changed. Long bodies are cut at about 400 characters;
`layout` shows paragraphs (¶) and pictures in order.

## Words kept: v1's edit lost a word, v2 ships the words unedited (C35, C177) (20)

### edge-tag-case-dupes
Why: C35

**body v1**
> Glaze and glaze and GLAZE.

**body v2**
> Tag case: Glaze and glaze and GLAZE typed three times.

### quote-missing-book-metadata
Why: C35

**body v1**
> > Fire it slower than you think you need to.
> 
> The June bug reached the Mac with an empty metadata blob and rendered as a raw wall.

**body v2**
> > Fire it slower than you think you need to.
> 
> The June bug: this reached the Mac with an EMPTY metadata blob and rendered as a raw > wall.

### typed-blockquote-ordinary
Why: C35

**body v1**
> > The pot you want is the pot you can't make yet.
> 
> Someone said that at the fair, and I wrote it on my hand. It is exactly the blue-glaze problem.
> 
> Also: stop apologizing to customers for the price. Just say the number.

**body v2**
> > The pot you want is the pot you can't make yet.
> 
> Someone said that at the fair and I wrote it on my hand. It is exactly the blue-glaze problem.
> 
> > Also: stop apologising to customers for the price. Just say the number.

### typed-crlf-tabs-nbsp
Why: C177

**body v1**
> De belangrijkste reden waarom ik dit doe, is omdat ik denk dat het een manier is om de communicatie te verbeteren. Ik wil dat mensen het makkelijker kunnen begrijpen wat ik zeg.
> 
> 	Het is niet zo dat ik probeer om het te compliceren, maar ik wil gewoon dat het helder is.
> 
> 	Ik heb het gevoel dat als je de taal een beetje stroomlijnt, dan de boodschap beter overkomt.

**body v2**
> Line one with a trailing space 
> Line two after CRLF
> 
> 	Indented with a tab
> 
> Non breaking spaces here and three blank lines follow
> 
> 
> 
> End.

### typed-dutch-boodschappen
Why: C35

**body v1**
> Boodschappen voor zaterdag:
> 
> Kaas (jong belegen, niet die oude), brood van de Turkse bakker, 3 kg klei-gips, iets voor tante Ria's verjaardag, bier voor Jack.
> 
> Niet vergeten: de fietstassen van [[Nadia Elharrak]] liggen nog achter.

**body v2**
> Boodschappen voor zaterdag
> 
> - kaas (jong belegen, niet die oude)
> - brood van de Turkse bakker
> - 3 kg klei-gips
> - iets voor tante Ria haar verjaardag
> - bier voor Jack
> 
> Niet vergeten: de fietstassen van [[Nadia Elharrak]] liggen nog achter.

### typed-headings-and-tags
Why: C34

**body v1**
> October workshop. Six people, hand-building, two hours. [[Mariam Haddad]] is bringing two friends from her office.
> 
> Before: Clean the bike side on Friday night. Cover the stands. #studio #workshop.
> 
> Materials: Two bags of the grey body, slip, the small wooden ribs. Check we have enough boards—last time we ran out.
> 
> After: Dry a week, bisque, then invite everyone back to glaze. That second evening is the part people r … (503 chars)

**body v2**
> # October workshop
> 
> Six people, hand-building, two hours. [[Mariam Haddad]] is bringing two friends from her office.
> 
> ## Before
> 
> Clean the bike side on Friday night. Cover the stands. #studio #workshop
> 
> ## Materials
> 
> Two bags of the grey body, slip, the small wooden ribs. Check we have enough boards — last time we ran out.
> 
> ## After
> 
> Dry a week, bisque, then invite everyone back to glaze. That second evening is the p … (519 chars)

### typed-tags-with-spaces
Why: C177

**body v1**
> Does the export keep them as one tag each?

**body v2**
> Tags with spaces and hashes: does the export keep them as one tag each?

### typed-tasks
Why: C35

**body v1**
> Deze week:
> 
> - Marco bellen over de bedrading (echt).
> - Order the grey clay body.
> - Rose the website feedback.
> - [[Mariam Haddad]]: yes to the Saturday, propose 18 Oct.
> - Chain for the Gazelle, black.
> - Blue glaze test at cone 6 with the new body.

**body v2**
> Deze week
> 
> - [ ] Marco bellen over de bedrading (echt)
> - [x] Order the grey clay body
> - [ ] Rose the website feedback
> - [ ] [[Mariam Haddad]]: yes to the Saturday, propose 18 Oct
> - [x] Chain for the Gazelle, black
> - [ ] Blue glaze test at cone 6 with the new body

### typed-title-derived
Why: C177

**body v1**
> The Dutch Language
> 
> Ik denk dat het belangrijk is om te weten dat de Nederlandse taal een rijke geschiedenis heeft. Het is een taal die veel invloeden heeft gehad, zowel van andere Europese talen als van lokale dialecten.
> 
> De Nederlandse taal is een West-Germaanse taal. Het is nauw verwant aan het Engels en het Duits. Door deze verwantschappen zie je veel overeenkomsten in woordenschat en grammatica. Maar er zijn ook … (476 chars)

**body v2**
> First line becomes the title if nothing else does.
> 
> Second paragraph is just here so the first line is clearly a line.

### typed-wall-7k
Why: C35

**body v1**
> The thing I keep circling back to with the workshop is that we are trying to run two businesses out of one room and pretending it is one business. The bikes pay the rent, and the ceramics pay for nothing yet, but the ceramics are the reason I get up in the morning. [[Lotte Vos]] says that is fine as long as I admit it out loud, which I am now doing, into a note, so it counts.
> 
> The numbers from August are not terrible … (3622 chars)

**body v2**
> Okay so the thing I keep circling back to with the workshop is that we are trying to run two businesses out of one room and pretending it is one business. The bikes pay the rent and the ceramics pay for nothing yet, but the ceramics are the reason I get up in the morning, and [[Lotte Vos]] says that is fine as long as I admit it out loud, which I am now doing, into a note, so it counts.
> 
> The numbers from August are n … (3628 chars)

### typed-wall-one-paragraph
Why: C35

**body v1**
> The thing I keep circling back to with the workshop is that we are trying to run two businesses out of one room and pretending it is one business. The bikes pay the rent, and the ceramics pay for nothing yet, but the ceramics are the reason I get up in the morning. [[Lotte Vos]] says that is fine as long as I admit it out loud, which I am now doing, into a note, so it counts.
> 
> The numbers from August are not terrible … (3621 chars)

**body v2**
> Okay so the thing I keep circling back to with the workshop is that we are trying to run two businesses out of one room and pretending it is one business. The bikes pay the rent and the ceramics pay for nothing yet, but the ceramics are the reason I get up in the morning, and [[Lotte Vos]] says that is fine as long as I admit it out loud, which I am now doing, into a note, so it counts. The numbers from August are no … (3619 chars)

### typed-whitespace-only
Why: C177

**title v1**
> The Secret Life of Trees: A Look at Forest Communication

**title v2**
> (nil)

**body v1**
> Het is een beetje een complex verhaal. We hebben een situatie waar we in zitten, en die situatie is dat we een project hebben dat we moeten afronden. En dat project, dat is een heel belangrijk project voor ons. Het is een project dat we al een tijdje aan het doen zijn, en we zijn nu op een punt waar we moeten beslissen hoe we verder gaan.
> 
> Er zijn verschillende opties, en elke optie heeft zijn voor- en nadelen. We ku … (1325 chars)

**body v2**
> (empty)

### voice-en-asr-wall
Why: C35, C34

**body v1**
> The thing I keep circling back to with the workshop is that we are trying to run two businesses out of one room and pretending it is one business. The bikes pay the rent, and the ceramics pay for nothing yet, but the ceramics are the reason I get up in the morning. [[Lotte Vos]] says that is fine as long as I admit it out loud, which I am now doing, into a note, so it counts.
> 
> The numbers from August are not terrible … (3621 chars)

**body v2**
> Okay so the thing I keep circling back to with the workshop is that we are trying to run two businesses out of one room and pretending it is one business. The bikes pay the rent and the ceramics pay for nothing yet, but the ceramics are the reason I get up in the morning, and [[Lotte Vos]] says that is fine as long as I admit it out loud, which I am now doing, into a note, so it counts. The numbers from August are no … (3627 chars)

### voice-en-eight-minutes
Why: C35

**body v1**
> The thing I keep circling back to with the workshop is that we are trying to run two businesses out of one room and pretending it is one business. The bikes pay the rent, and the ceramics pay for nothing yet, but the ceramics are the reason I get up in the morning. [[Lotte Vos]] says that is fine as long as I admit it out loud, which I am now doing, into a note, so it counts.
> 
> The numbers from August are not terrible … (3622 chars)

**body v2**
> Okay so the thing I keep circling back to with the workshop is that we are trying to run two businesses out of one room and pretending it is one business. The bikes pay the rent and the ceramics pay for nothing yet, but the ceramics are the reason I get up in the morning, and [[Lotte Vos]] says that is fine as long as I admit it out loud, which I am now doing, into a note, so it counts.
> 
> The numbers from August are n … (3628 chars)

### voice-en-names-all-tiers
Why: C35

**body v1**
> Long day. [[Lotte Vos]] opened up, [[Hendrik Vos]] brought the trailer, and Jack, the Morrow one, dropped off his bike again. Then Rose came by with the website, and I said rose gold is not a color for a bike shop. Will was supposed to come, but he will not be here until Thursday. Sam texted—no idea which Sam, I need to check. Kai from next door wants to borrow the stand.

**body v2**
> Long day. [[Lotte Vos]] opened up, [[Hendrik Vos]] brought the trailer, and Jack, the Morrow one, dropped off his bike again. Then Rose came by with the website and I said rose gold is not a colour for a bike shop. Will was supposed to come but he will not be here until Thursday. Sam texted, no idea which Sam, I need to check. Kai from next door wants to borrow the stand.

### voice-en-paragraphed-by-pauses
Why: C35

**body v1**
> The blue is closer at cone five than at six.
> 
> [[Bruno Castel]]'s frame builder in Porto does lugged steel, and I want one.
> 
> [[Lotte Vos]]'s birthday is in three weeks, and I have nothing.

**body v2**
> First thought. The blue is closer at cone five than at six.
> 
> Second thought, unrelated. [[Bruno Castel]]'s frame builder in Porto does lugged steel and I want one.
> 
> Third. [[Lotte Vos]]'s birthday is in three weeks and I have nothing.

### voice-en-pricing-ramble
Why: C35

**body v1**
> Walking back from the shop, I think I've decided on the prices. Overhauls go to one sixty; tune-ups stay where they are. Jack said fifteen percent across the board, but I don't want to lose the regulars over a tune-up. [[Lotte Vos]] agrees, I think. The other thing is I should write the promised date on the tag and also in the calendar, both, because the tag gets lost. That's it.

**body v2**
> Okay so, um, walking back from the shop and I think I've decided on the prices. Overhauls go to one sixty, um, tune-ups stay where they are. Jack said fifteen percent across the board but I don't want to, I don't want to lose the regulars over a tune-up. [[Lotte Vos]] agrees, I think. Uh, the other thing is I should write the promised date on the, on the tag and also in the calendar, both, because the tag gets lost. … (436 chars)

### voice-en-raw-title
Why: C35

**body v1**
> The list must not show memo garbage; a generated or first-line title wins over a raw one.

**body v2**
> A voice note whose stored title looks like a raw filename. The list must not show memo_ garbage; a generated or first-line title wins over a raw one.

### voice-en-with-mac-polish
Why: C35

**body v1**
> The Saturday went well actually. Six people, nobody leaned on a chain. [[Mariam Haddad]]'s colleagues want to come back for the glazing evening. I think we charge forty-five.

**body v2**
> Um so the, the Saturday went well actually, six people, um, nobody leaned on a chain. [[Mariam Haddad]]'s, uh, Mariam's colleagues want to come back for the glazing evening. I think we charge forty five and, and see.

### voice-mix-code-switch
Why: C35, C177

**body v1**
> Dus ik zat te denken, de Saturday workshop. Als we dat doen, dan moet de fietskant echt schoon zijn, properly clean, niet gewoon een doek erover. [[Mariam Haddad]] brengt twee collega's mee, dat zijn zes mensen, en ik heb maar vier planken. [[Bruno Castel]] heeft er misschien nog, ik vraag het hem morgen.

**body v2**
> Dus ik zat te denken, the Saturday workshop, als we dat doen dan moet de fietskant echt schoon zijn, like properly clean, niet gewoon een doek erover. [[Mariam Haddad]] brengt twee collega's mee, so that's six people, zes mensen, en ik heb maar vier planken. [[Bruno Castel]] heeft er misschien nog, ik vraag het hem morgen.


## Pictures back by paragraph (C30) and titles read without markers (C178) (21)

### applenote-with-attachment
Why: C30

**body layout** v1: `¶ img_001 ¶` · v2: `¶ img_001 ¶`

**body v1**
> How the shelves go back in after cleaning. Photo from the manual.
> 
> [[img_001]]
> 
> 
> 
> Bottom shelf gets the posts at 15 cm, not 10.

**body v2**
> How the shelves go back in after cleaning. Photo from the manual.
> 
> [[img_001]]
> 
> Bottom shelf gets the posts at 15 cm, not 10.

### dest-project
Why: C30

**body layout** v1: `¶ img_001 ¶` · v2: `¶ img_001`

**body v1**
> Finished the wide blue bowl, the first one that came out right.
> 
> [[img_001]]
> 
>  Cone five, grey body, blue number three.

**body v2**
> Finished the wide blue bowl, the first one that came out right. Cone five, grey body, blue number three.
> 
> [[img_001]]

### edge-literal-marker-typed
Why: C30, C178

**title v1**
> Typing by hand to see what happens with the image.

**title v2**
> Typing by hand to see what happens.

**body layout** v1: `¶ img_001 ¶` · v2: `¶ img_001`

**body v1**
> I typed by hand to see what happens. 
> 
> [[img_001]]
> 
> There is no photo.

**body v2**
> I typed by hand to see what happens. There is no photo.
> 
> [[img_001]]

### pic-at-end
Why: C30

Only blank lines differ: v1 left empty lines after the last picture.

### pic-at-start
Why: C30, C178

**title v1**
> Blue glaze at cone five, straight out of the kiln.

**title v2**
> Blue glaze appearance at cone five, straight from the kiln.

**body layout** v1: `img_001 ¶` · v2: `¶ img_001`

**body v1**
> [[img_001]]
> 
> This is what the blue looks like at cone five, straight out of the kiln, before I touched it.

**body v2**
> This is what the blue looks like at cone five, straight out of the kiln, before I touched it.
> 
> [[img_001]]

### pic-in-blockquote
Why: C178

**title v1**
> The Pot You Want Is the Pot You Can't Make Yet

**title v2**
> The Pot You Can't Make Yet: A Fair Observation

### pic-in-task-list
Why: C30

**body layout** v1: `¶ ¶ img_001 ¶` · v2: `¶ ¶ img_001`

**body v1**
> Parts to order for the cargo bike:
> 
> - [ ] chain, 1/8
> - [ ] the rear hub, this one
> 
> [[img_001]]
> 
> 
> - [ ] brake pads, four
> - [x] new bell

**body v2**
> Parts to order for the cargo bike:
> 
> - [ ] chain, 1/8
> - [ ] the rear hub, this one
> - [ ] brake pads, four
> - [x] new bell
> 
> [[img_001]]

### pic-mid-sentence
Why: C30, C178

**title v1**
> Crack runs from rim to foot; body, not glaze, is the issue.

**title v2**
> Crack in the pottery: Addressing the body, not the glaze.

**body layout** v1: `¶ img_001 ¶` · v2: `¶ img_001`

**body v1**
> The crack runs from the rim all the way down to the foot, so it is the body, not the glaze. 
> 
> [[img_001]]
> 
> I will fire the next one slower.

**body v2**
> The crack runs from the rim all the way down to the foot, so it is the body, not the glaze. I will fire the next one slower.
> 
> [[img_001]]

### pic-missing-file
Why: C30, C178

**title v1**
> Placeholder Image Handling: Preventing Crashes and Marker Drops

**title v2**
> Placeholder Image Requirement: No Crash, No Drop Marker

**body layout** v1: `¶ img_001 ¶` · v2: `¶ img_001`

**body v1**
> The photo for this one never made it across.
> 
> [[img_001]]
> 
>  Should show a placeholder, not crash, not drop the marker.

**body v2**
> The photo for this one never made it across. Should show a placeholder, not crash, not drop the marker.
> 
> [[img_001]]

### pic-nl
Why: C30, C178

**title v1**
> De scheur in de klei van het aardewerk.

**title v2**
> De scheur in de klei: een les in het bakproces.

**body layout** v1: `¶ img_001 ¶` · v2: `¶ img_001`

**body v1**
> Dit is de scheur waar [[Hendrik Vos]] het over had, van de rand tot aan de voet. 
> 
> [[img_001]]
> 
> Ik denk de klei, niet de glazuur. Volgende keer langzamer stoken.

**body v2**
> Dit is de scheur waar [[Hendrik Vos]] het over had, van de rand tot aan de voet. Ik denk de klei, niet de glazuur. Volgende keer langzamer stoken.
> 
> [[img_001]]

### pic-ocr-text
Why: C30, C178

**title v1**
> Supplier's Price Board Snapped to Stop Guessing

**title v2**
> Supplier Price Board Snapped: Grey Body Price Increase

**body layout** v1: `¶ img_001 ¶` · v2: `¶ img_001`

**body v1**
> Snapped the supplier's price board so I stop guessing.
> 
> [[img_001]]
> 
>  Grey body went up again.

**body v2**
> Snapped the supplier's price board so I stop guessing. Grey body went up again.
> 
> [[img_001]]

### pic-shared-no-timestamp
Why: C30

**body layout** v1: `¶ img_001 ¶` · v2: `¶ img_001`

**body v1**
> Talking
> 
> [[img_001]]
> 
>  about the lamp base I saw at the market, the seller fires electric at cone five, so the matte blue is possible without gas.

**body v2**
> Talking about the lamp base I saw at the market, the seller fires electric at cone five, so the matte blue is possible without gas.
> 
> [[img_001]]

### pic-three-spread
Why: R3, C30

**title v1**
> Workshop preparation before Saturday: Bike, wheel, and shelf organization.

**title v2**
> Workshop walk-through before Saturday: Bike, wheel, and cluttered shelf.

**body layout** v1: `¶ img_001 ¶ img_002 img_003 ¶` · v2: `¶ img_001 img_002 img_003`

**body v1**
> Walking the workshop before Saturday. Bike side first, this all has to be covered. 
> 
> [[img_001]]
> 
> Then the wheel, which is fine. Then the shelf where the glazed pieces go, which is not fine; it is full of [[Hendrik Vos]]'s tools. 
> 
> [[img_002]]
> 
> 
> 
> [[img_003]]
> 
> Friday night job.

**body v2**
> Walking the workshop before Saturday. Bike side first, this all has to be covered. Then the wheel, which is fine. Then the shelf where the glazed pieces go, which is not fine; it is full of [[Hendrik Vos]]'s tools. Friday night job.
> 
> [[img_001]]
> 
> [[img_002]]
> 
> [[img_003]]

### pic-two-same-second
Why: C30, C178

**title v1**
> Green Edge on Bowl: Observing Heat Exposure

**title v2**
> Green Edge on Bowl Only Facing the Element

**body layout** v1: `¶ img_001 img_002 ¶` · v2: `¶ img_001 img_002`

**body v1**
> Front and back of the same bowl,
> 
> [[img_001]]
> 
> 
> 
> [[img_002]]
> 
> the green edge is only on the side that faced the element.

**body v2**
> Front and back of the same bowl, the green edge is only on the side that faced the element.
> 
> [[img_001]]
> 
> [[img_002]]

### pic-user-snapped-markers
Why: C30

**body layout** v1: `¶ ¶ img_001 img_002 ¶` · v2: `¶ img_001 ¶ img_002 ¶`

**body v1**
> Moved the markers myself in the editor so they sit on sentence ends.
> 
> This paragraph is after the first picture.
> 
> 
> [[img_001]]
> 
> 
> 
> 
> [[img_002]]
> 
> And this one after the second.

**body v2**
> Moved the markers myself in the editor so they sit on sentence ends.
> 
> [[img_001]]
> 
> This paragraph is after the first picture.
> 
> [[img_002]]
> 
> And this one after the second.

### pic-wall
Why: R3, C30

**title v1**
> Running Two Businesses in One Room: Bikes and Ceramics Challenges

**title v2**
> Running Two Businesses in One Room: Bikes and Ceramics

**summary v1**
> Reflecting on juggling two businesses, prioritizing fixing kiln wiring with Marco and raising overhaul prices. Also, planning Saturday workshop with Mariam, while trying to nail down blue glaze color by testing new clay body.

**summary v2**
> Reflecting on juggling two businesses, prioritizing fixing kiln wiring with Marco this week. Planning to raise overhaul prices and asking Rose for website revision. Also committing to Saturday workshop prep and testing new clay body for blue glaze.

**body layout** v1: `¶ ¶ ¶ ¶ ¶ ¶ img_001 ¶ ¶ ¶ img_002 ¶ ¶` · v2: `¶ img_001 img_002 ¶ ¶ ¶ ¶ ¶ ¶ ¶ ¶`

**body v1**
> The thing I keep circling back to with the workshop is that we are trying to run two businesses out of one room and pretending it is one business. The bikes pay the rent, and the ceramics pay for nothing yet, but the ceramics are the reason I get up in the morning. [[Lotte Vos]] says that is fine as long as I admit it out loud, which I am now doing, into a note, so it counts.
> 
> The numbers from August are not terrible … (3651 chars)

**body v2**
> Okay so the thing I keep circling back to with the workshop is that we are trying to run two businesses out of one room and pretending it is one business. The bikes pay the rent and the ceramics pay for nothing yet, but the ceramics are the reason I get up in the morning, and [[Lotte Vos]] says that is fine as long as I admit it out loud, which I am now doing, into a note, so it counts. The numbers from August are no … (3653 chars)

### share-whatsapp-thread
Why: C30, C178

**title v1**
> Problemen met de ovenbedrading en meterkastaansluiting

**title v2**
> Problemen met de ovenbedrading en meterkast aansluiting.

**body layout** v1: `¶ ¶ ¶ ¶ img_001 ¶ ¶` · v2: `¶ ¶ ¶ img_001 ¶ ¶`

**body v1**
> Hé Fenna, ik heb de oven bekeken. Die bedrading achter is echt niet oké.
> 
> En de aansluiting in de meterkast is ook te licht voor wat jij erop wilt zetten.
> 
> Kijk, dit is wat ik bedoel. Zie je die verkleuring bij de klemmen?
> 
> Okay, so if you want, I can come by Thursday with Marco. 
> 
> [[img_001]]
> 
> He said he has an hour.
> 
> Let me know, and don't fire it before then, please.

**body v2**
> Hé Fenna, ik heb de oven bekeken. Die bedrading achter is echt niet oké.
> 
> En de aansluiting in de meterkast is ook te licht voor wat jij erop wilt zetten.
> 
> Kijk, dit is wat ik bedoel. Zie je die verkleuring bij de klemmen?
> 
> [[img_001]]
> 
> Okay, so if you want, I can come by Thursday with Marco. He said he has an hour.
> 
> Let me know, and don't fire it before then, please.

### typed-user-wikilink
Why: C178

**title v1**
> Update on Saturday plans with Lotte Vos and potential attendees

**title v2**
> Lotte Vos Confirms Attendance for Saturday Event

**body v1**
> Talked to [[Lotte Vos]] Vos about the Saturday, and she is in. Jack might come too, the Ferreira one, not Morrow.

**body v2**
> Talked to [[Lotte Vos]] about the Saturday, and she is in. Jack might come too, the Ferreira one, not Morrow.

### video-landscape
Why: C30

**body layout** v1: `img_001 ¶` · v2: `img_001 ¶`

**body v1**
> [[img_001]]
> 
> Korte video van het draaien van de brede schaal, voor [[Ines Månsson]], zodat ze ziet wat er misgaat bij de rand.

**body v2**
> [[img_001]]
> 
> Korte video van het draaien van de brede schaal, voor [[Ines Månsson]], zodat ze ziet wat er misgaat bij de rand.

### video-no-speech
Why: C30, C177

**title v1**
> (No text provided to generate a title for.)

**title v2**
> (nil)

**body layout** v1: `¶ ¶ ¶ img_001 ¶ ¶ ¶` · v2: `img_001`

**body v1**
> Het is een beetje een complex verhaal. We hebben een situatie waar we in zitten, en die situatie is dat we een project hebben dat we moeten afronden. En dat project, dat is een heel belangrijk project voor ons. Het is een project dat we al een tijdje aan het doen zijn, en we zijn nu op een punt waar we moeten beslissen hoe we verder gaan.
> 
> Er zijn verschillende opties, en elke optie heeft zijn voor- en nadelen. We ku … (1340 chars)

**body v2**
> [[img_001]]

### video-portrait
Why: C30

**body layout** v1: `img_001 ¶` · v2: `img_001 ¶`

**body v1**
> [[img_001]]
> 
> Advice to future me, recorded on the balcony: do not say yes to a workshop before checking the calendar.

**body v2**
> [[img_001]]
> 
> Advice to future me, recorded on the balcony: do not say yes to a workshop before checking the calendar.

