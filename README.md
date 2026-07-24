# D&D Sheet Archive

Archivio Flutter per schede personaggio D&D 5e, disponibile su Android, Linux,
Windows e Web.
I dati vengono salvati localmente e possono essere sincronizzati manualmente
con Google Drive dal menu cloud nella schermata principale.

Dopo il primo accesso Google, le modifiche in sospeso vengono sincronizzate
automaticamente ogni cinque minuti, quando l'app passa in background e quando
si chiude una scheda. Sui target che supportano l'accesso silenzioso, la
sessione viene ripristinata agli avvii successivi e il sync riparte anche per le
modifiche rimaste in sospeso.

La cronologia conserva al massimo 10 versioni per personaggio. Le chiusure e i
blocchi avvenuti nella stessa finestra di 24 ore aggiornano un unico snapshot
automatico invece di crearne uno nuovo.

## Sincronizzazione Google Drive

Il sync usa un file JSON nello spazio privato `appDataFolder` e richiede
soltanto lo scope OAuth `drive.appdata`. Le schede e le versioni vengono unite
per UUID; per i conflitti sui personaggi prevale `updatedAt` più recente. Le
cancellazioni vengono sincronizzate e non fanno ricomparire dati provenienti da
un dispositivo non aggiornato.

Configurazione Google Cloud:

1. Crea un progetto nella [Google Cloud Console](https://console.cloud.google.com/).
2. Abilita la **Google Drive API** e configura la schermata consenso OAuth.
3. Per il Web crea un client OAuth “Applicazione web” e registra le origini
   JavaScript usate, ad esempio `http://localhost:7357`.
4. Per Android registra anche un client OAuth Android per il package
   `com.example.dnd_sheet_archive` e gli SHA-1 delle chiavi debug/release. Crea
   inoltre un client OAuth Web da usare come server client ID.
5. Per Linux crea un client OAuth di tipo “App desktop”. Il flusso apre il
   browser predefinito e riceve l'autorizzazione su una porta locale temporanea.

Avvio Web:

```sh
flutter run -d chrome --web-hostname localhost --web-port 7357 \
  --dart-define=GOOGLE_WEB_CLIENT_ID=CLIENT_ID_WEB.apps.googleusercontent.com
```

Avvio Android:

```sh
flutter run -d DEVICE_ID \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=CLIENT_ID_WEB.apps.googleusercontent.com
```

Avvio Linux:

```sh
mkdir -p ~/.config/dnd_sheet_archive
printf '%s\n' \
  'GOOGLE_WEB_CLIENT_ID=CLIENT_ID_WEB.apps.googleusercontent.com' \
  'GOOGLE_DESKTOP_CLIENT_ID=CLIENT_ID_DESKTOP.apps.googleusercontent.com' \
  'GOOGLE_DESKTOP_CLIENT_SECRET=CLIENT_SECRET_DESKTOP' \
  > ~/.config/dnd_sheet_archive/google_oauth.env
chmod 600 ~/.config/dnd_sheet_archive/google_oauth.env
./scripts/run_linux.sh
```

Lo script seleziona il target desktop Linux e legge la configurazione OAuth da
`~/.config/dnd_sheet_archive/google_oauth.env`, che non viene salvato nel
repository. Eventuali opzioni aggiuntive di `flutter run` possono essere
passate in coda al comando.

Build AppImage:

```sh
./scripts/build_appimage.sh
```

Build AppImage ARM64 da una macchina x86_64 con Docker:

```sh
./scripts/build_appimage_arm64.sh
```

Avvio Windows da PowerShell:

```powershell
flutter run -d windows `
  --dart-define="GOOGLE_DESKTOP_CLIENT_ID=CLIENT_ID_DESKTOP.apps.googleusercontent.com" `
  --dart-define="GOOGLE_DESKTOP_CLIENT_SECRET=CLIENT_SECRET_DESKTOP"
```

Lo script crea una build release, prepara l'AppDir, include le dipendenze
native rilevate e salva il risultato eseguibile in `dist/`. Se `linuxdeploy` e
`appimagetool` non sono installati, scarica le AppImage ufficiali nella cache
utente. È possibile passare opzioni aggiuntive di `flutter build linux` in coda
al comando. Durante la build legge il client secret Desktop dal file locale
indicato sopra e lo incorpora nell'applicazione: agli utenti finali va
distribuito soltanto il file `.AppImage`. La variante ARM64 usa Docker e QEMU
per eseguire l'intera build in un ambiente Linux `aarch64`; al primo avvio deve
scaricare l'immagine Flutter e preparare il relativo toolchain.

Per le build di distribuzione va passato il `--dart-define` appropriato a
`flutter build web`, `flutter build apk/appbundle` o `flutter build linux`.
Client ID e client secret devono restare nella configurazione locale e non
vanno inseriti nel repository.

## Release automatiche

Quando viene pubblicata una GitHub Release con destinazione `main`, GitHub
Actions esegue analisi e test, crea un APK Android firmato e una AppImage Linux
x86_64, una AppImage Linux ARM64, un archivio Windows x64 e un bundle Web,
quindi allega i file alla release. Credenziali OAuth e chiave di firma Android
vengono lette esclusivamente dai GitHub Actions Secrets. La AppImage ARM64
viene compilata direttamente su un runner GitHub ARM64 nativo.

## Sviluppo

```sh
flutter pub get
flutter test
flutter analyze
```
