# Matteparken

GitHub Pages-version av Matteparken.

- `index.html` är startsidan.
- `assets/` innehåller bilderna som tidigare låg inbäddade i HTML-filen.
- `.nojekyll` gör att GitHub Pages serverar filerna direkt utan Jekyll-bearbetning.

## Publicera med GitHub Pages
1. Lägg innehållet i ett GitHub-repository.
2. Öppna **Settings → Pages**.
3. Under **Build and deployment**, välj **Deploy from a branch**.
4. Välj branch **main** och mappen **/(root)**.
5. Spara. GitHub visar sedan adressen till sidan.

## Uppdatera
Byt ut `index.html` och de filer i `assets/` som hör till den nya versionen, och gör en ny commit. GitHub Pages uppdaterar webbplatsen automatiskt.


## Supabase: klasshantering
Efter uppdateringen av läraradmin ska `supabase_class_management.sql` köras en gång i Supabase **SQL Editor**. Den lägger till stöd för att byta namn på, arkivera, återställa och säkert försöka ta bort klasser permanent.

Lärarinbjudningar från Supabase routas automatiskt till `admin.html`, där den inbjudna läraren kan välja sitt eget lösenord och därefter skapa sin första klass.
