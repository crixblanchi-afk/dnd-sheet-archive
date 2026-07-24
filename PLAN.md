# App archivio schede D&D 5e (Flutter — Android + Web)

## Context

L'utente vuole un'app minimale (Android + Web) che funga da archivio di schede personaggio D&D 5e basate sul PDF compilabile già presente in `/home/crixis/Progetti/D&D pdf character sheet/dnd_5e_charactersheet_formfillable.pdf` (scheda ufficiale WotC, 3 pagine letter 612×792pt, AcroForm con 332 campi utili: 210 testo, 122 checkbox; 4 pushbutton immagine da escludere). La gestione nativa dei form PDF è scadente, quindi i campi vanno resi custom in-app. Progetto greenfield: la cartella contiene solo il PDF.

**Requisiti confermati con l'utente:**
- Stack: **Flutter** (Android APK + web).
- Due schermate: selezione personaggi (lista + crea nuovo) e schermata scheda (solo 2 bottoni: lock read-only e indietro).
- Ogni campo compilabile e commentabile; commento via long-press (mobile) / tasto destro (web); pallino indicatore sui campi commentati.
- **Lock blocca tutto**: da loccata la scheda è interamente read-only, commenti inclusi (restano visibili ma non modificabili).
- Autosave con conservazione versioni precedenti; cronologia accessibile dalla lista personaggi in modo **non prominente** (menu contestuale), con ripristino.
- Storage solo locale; **sync cloud è funzione futura** → data model e repository progettati per essere sync-ready (UUID, timestamp, versioni append-only, interfaccia repository pulita).

## Approccio

### Pipeline di estrazione build-time (`tools/`) — zero dipendenze PDF a runtime
Il PDF è fisso, quindi si pre-processa una volta sola e si committano gli output come asset:
- `tools/extract_fields.py` (Python, venv con `pypdf`): itera le annotation `/Widget` di ogni pagina, esclude i 4 pushbutton (`Ff & (1<<16)`), emette `assets/sheet/fields.json` con per ogni campo: `name` (byte-exact, MAI trimmare — alcuni nomi hanno spazi finali tipo `"Race "`), `page`, `type` (text/checkbox), rect in punti PDF **già convertito a origine top-left** (`x=x1, y=792−y2, w, h`), `multiline` (flag bit 13), `align` (da `/Q`). Assert: nomi unici, count 332, rect dentro i bounds.
- `pdftoppm -png -r 200` → `assets/sheet/page-1..3.png` (1700×2200px, nitide fino a ~3× DPR; se sfocate in zoom, rilanciare a 300 DPI senza toccare l'app).

### Mapping coordinate — il trucco centrale
Ogni pagina è renderizzata a **esattamente 612×792 logical pixel** (Column di 3 SizedBox dentro un unico `InteractiveViewer`). Così punti PDF == logical pixel: ogni overlay è un semplice `Positioned(left: f.x, top: f.y, width: f.w, height: f.h)`, nessuna matematica di scala. `InteractiveViewer` (constrained: false, minScale 0.3, maxScale 6) gestisce fit-to-width iniziale, pan e zoom. Font size: single-line `clamp(h*0.62, 7, 14)`, multiline fissa ~9.5.

### Pacchetti
- `sembast` + `sembast_web`: document store JSON, stessa API su file (Android via `path_provider`) e IndexedDB (web). Documenti già a forma di payload sync futuro. No codegen.
- `path_provider`, `uuid` (v4), `intl`.
- State management: **nessun package** — `ChangeNotifier`/`ValueNotifier`. Un `SheetController` possiede il personaggio aperto; ogni campo ha il suo `TextEditingController` locale (i tasti non ricostruiscono la scheda).
- Scartati: drift/hive/isar (overhead o web incerto), qualsiasi package PDF runtime (non serve).

### Data model (sembast)
Store `characters` (chiave = id):
```json
{ "id": "uuid", "name": "...", "createdAt": "...", "updatedAt": "...", "locked": false,
  "fields": { "CharacterName": "Ser Bolg", "Check Box 11": true },
  "comments": { "AC": "include +2 scudo" } }
```
Mappe sparse (assente = vuoto/unchecked/nessun commento). `name` è proprietà dell'app: alla creazione prefilla il campo `CharacterName`, poi vive indipendente.

Store `versions` (append-only, chiave = version id): snapshot completi `{id, characterId, createdAt, reason: "session|lock|pre-restore", name, fields, comments}`. Pochi KB l'uno — niente diff.

### Repository (seam per la sync futura)
```dart
abstract class CharacterRepository {
  Stream<List<CharacterSummary>> watchCharacters();      // updatedAt desc
  Future<Character?> getCharacter(String id);
  Future<Character> createCharacter(String name);
  Future<void> saveCharacter(Character c);               // upsert autosave
  Future<void> renameCharacter(String id, String newName);
  Future<void> deleteCharacter(String id);               // + relative versioni
  Future<List<VersionMeta>> listVersions(String characterId);
  Future<CharacterVersion?> getVersion(String versionId);
  Future<void> createSnapshot(Character c, String reason);
  Future<void> restoreVersion(String characterId, String versionId);
}
```
`restoreVersion` = prima snapshot dello stato corrente (reason `pre-restore`), poi copia della versione nel documento live → il ripristino non può mai perdere dati.

### Autosave + policy versioni ("una versione per sessione di editing")
- Ogni modifica → mutazione in-memory → `dirty=true` → Timer riavviabile **800ms** → `saveCharacter`. Flush immediato su: dispose schermata, toggle lock, lifecycle paused/hidden, prima di ogni snapshot (controller registrato come `WidgetsBindingObserver`).
- Snapshot SOLO quando una sessione sporca termina: (a) uscita dalla schermata scheda, (b) lock ON, (c) app in background, (d) cap di sicurezza 10 min di editing continuo. Ogni trigger scatta solo se `dirtySinceSnapshot`, poi azzera il flag. → una manciata di versioni per sessione di gioco, non una per tasto. Nessun pruning (fuori scope).

## Struttura progetto

Creare in-place (il nome cartella non è un package name valido):
`flutter create --project-name dnd_sheet_archive --platforms android,web .`

```
tools/extract_fields.py + README.md
assets/sheet/page-1..3.png, fields.json
lib/
  main.dart                        # MaterialApp, bootstrap repo, disableContextMenu su web
  models/character.dart, character_version.dart, sheet_field.dart
  data/app_database.dart           # sembast, conditional import io/web
  data/character_repository.dart + sembast_character_repository.dart
  controllers/sheet_controller.dart
  screens/character_list_screen.dart, sheet_screen.dart
  widgets/sheet_page.dart, text_field_overlay.dart, checkbox_overlay.dart,
          comment_dialog.dart, version_history_sheet.dart
```

## Schermate

**Selezione personaggi**: `StreamBuilder` su `watchCharacters()` → ListView di ListTile (nome + "modificato il …"); tap → scheda; FAB "+" → dialog nome → crea e apre. Per riga un `PopupMenuButton` discreto: **Rinomina / Cronologia versioni / Elimina** (con conferma). Cronologia = bottom sheet con lista `VersionMeta` (timestamp + chip reason) e bottone Ripristina con conferma.

**Scheda**: unico `InteractiveViewer` con Column di 3 pagine (Stack: `Image.asset` 612×792 + overlay Positioned). Chrome: solo 2 bottoni circolari flottanti negli angoli alti (SafeArea) — indietro a sinistra, lock a destra.
- Text overlay: `TextField` con `InputDecoration.collapsed`, sfondo trasparente, `textAlign` da def; multiline → `maxLines:null, expands:true`, top-aligned; `readOnly` quando loccata.
- Checkbox overlay: `GestureDetector` sul rect, se true dipinge pallino/check dimensionato al rect (l'arte del cerchio vuoto è già stampata sulla pagina); tap disabilitato da loccata.
- Commenti: gesture layer su ogni overlay con `onLongPress` + `onSecondaryTapUp` → dialog (titolo = nome campo, TextField multiline, Salva/Rimuovi). **Da loccata il dialog è read-only** (solo visualizzazione, niente Salva/Rimuovi). Su web `BrowserContextMenu.disableContextMenu()` in `main()` (guardato da `kIsWeb`).
- Pallino indicatore: cerchio ~7px in alto a destra del rect, via `ValueListenableBuilder` su `ValueNotifier<Set<String>> commentedFields` (repaint puntuale).
- Tastiera mobile: al focus, calcola il rect on-screen via `TransformationController`; se coperto dalla tastiera, anima una traslazione (~20 righe).
- Performance: ~332 TextField vivi dovrebbero reggere; fallback contenuto SE il profiling mostra jank: Text statico + swap in TextField al tap (tocca solo `text_field_overlay.dart`). Non costruirlo preventivamente.

## Passi di implementazione (ordinati)

1. `flutter create` in-place, deps, `git init` + commit baseline.
2. `tools/extract_fields.py`, eseguirlo + `pdftoppm`; committare asset; registrare `assets/sheet/` in pubspec.
3. `models/` + loader di fields.json (lista `SheetFieldDef` raggruppata per pagina).
4. `data/`: sembast con conditional import, repository (versioni + restore inclusi). Unit test con `databaseFactoryMemory` (create/save/snapshot/restore/delete).
5. Rendering statico: sheet screen con InteractiveViewer + 3 pagine + **painter di debug dei rect** per verificare visivamente l'allineamento prima di qualsiasi editing.
6. `SheetController` + overlay testo/checkbox; autosave debounce + flush lifecycle.
7. Lista personaggi (crea/rinomina/elimina) + navigazione.
8. Lock + bottoni chrome; trigger snapshot (uscita/lock/lifecycle/cap 10 min).
9. Commenti: gesture, dialog (read-only da loccata), pallini, soppressione context menu web.
10. Bottom sheet cronologia + ripristino.
11. Rifinitura pan-tastiera; pass di verifica completo.

## Verifica

1. Estrazione: `fields.json` con 332 campi; spot-check `CharacterName` → `x≈47.6, y≈61.3`; PNG visivamente corretti.
2. `flutter run -d chrome` e `flutter run -d <android>`:
   - Crea "Test" → scheda si apre con CharacterName prefillato.
   - **Allineamento** (valida tutta la pipeline): testo in STR/DEX/skill e toggle dei cerchi proficiency a zoom massimo devono cadere dentro i box stampati su tutte e 3 le pagine.
   - Multiline (Features and Traits) → wrap top-aligned.
   - Kill + rilancio dopo ~1s di pausa dalla digitazione → valore persistito (autosave).
   - Long-press (Android) / tasto destro (Chrome) → dialog commento; salva → pallino; rilancio → pallino persiste; il context menu del browser NON deve apparire.
   - Lock → digitazione, checkbox E commenti bloccati (commenti solo visibili); unlock ripristina.
   - Edita→esci, edita→esci → cronologia mostra 2 versioni (non una per tasto). Ripristina la vecchia → valori vecchi + entry `pre-restore` in cronologia; ripristina quella → stato più recente.
   - Rinomina/Elimina dalla lista; elimina rimuove anche le versioni.
   - Tastiera mobile: focus su campo in basso → la scheda trasla sopra la tastiera.
