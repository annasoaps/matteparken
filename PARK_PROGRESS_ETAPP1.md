# Matteparken, Etapp 1 (testgren)

## Genomfört
- `park_progression_etapp1.js` laddas direkt efter den befintliga `MZ.habitats`-modulen.
- Nio nya parkmärken och regler för Skogsdungen, Sjön och Berget.
- Skogsdungen → Sjön: 3 träd, 5 olika skogsföremål (utan träd), 3 skogsarter och 35 **nya** matteomgångar.
- Sjön → Berget: brygga, 5 olika sjöföremål (utan brygga), 5 unika fiskarter, 2 andra sjöarter och 50 **nya** matteomgångar.
- Berget: ljung, 5 olika bergsföremål (utan ljung), 3 bergsarter.
- För gamla upplåsningar utan sparad omgångsbaslinje startar räknaren på nuvarande total, utan retroaktiv uppräkning.
- Parkmärken sparas permanent i `state.habitats.badges`. Föremål och arter räknas från redan sparad data.
- Startgläntans upplåsning och 15 matteomgångar är oförändrade.
- Test: `node tests/park_progression_etapp1.test.cjs`.

## Medvetet kvar före publicering
1. **Elevlagring i Supabase.** Parkens föremål, upptäckter, fiske och parkmärken finns fortfarande i den befintliga browser-localStorage. **Ingen elevdata eller produktionsdatabas har ändrats.** Nuvarande lagring behöver kopplas till rätt elev med säker migrering; annars kan delade datorer ge fel framsteg.
2. **Etapp 2, elevgränssnitt.** Sjön och Berget får riktiga `snapshot()` och `unlock()`-villkor i motorn, men nya låsskärmar, upplåsningsknappar och elevtexter är ännu inte byggda. Den publicerade `main` är orörd.
3. **Webbläsartest.** Testfilen täcker logiken med mockade spelhändelser. Funktioner behöver även testas i en riktig elevsession innan lansering.
4. **Innehåll/balans.** Kontrollera att spelaren kan samla fem olika föremål i varje zon utan oskälig slump från påsar/lådor. Nya bergsgrafiken och mineraljakten ligger i senare etapper.

## Nästa säkra steg
Skapa en separat, elevbunden datamodell för parkens tillstånd, med RLS så att en elevsession bara får läsa och skriva sin egen park. Utforma en uttrycklig migrering från nuvarande localStorage **utan att automatiskt tillskriva en elev tidigare data från en delad webbläsare**. Testa först med testelever. Fortsätt därefter med Etapp 2 i samma gren.
