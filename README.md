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
blocchi avvenuti entro 24 ore dal primo snapshot automatico aggiornano quello
stesso snapshot invece di crearne uno nuovo; passata la finestra si riparte con
una versione nuova.

Il pulsante **Visualizzazione scheda**, in alto, permette di scegliere **A pagine**
o **A scorrimento**. La vista a pagine usa tutto lo spazio disponibile, senza
zoom né barra inferiore: uno swipe orizzontale gira il foglio. La vista a
scorrimento mostra i tre fogli in una colonna continua e offre zoom, adattamento
alla larghezza e barre di scorrimento. Cambiare modalità conserva le modifiche
ai campi, che vengono salvate automaticamente.

La seconda pagina ospita due riquadri per immagini: il ritratto del personaggio
e il simbolo in “Allies & Organizations”. Si riempiono con un tocco e si
svuotano con una pressione prolungata.

Le immagini non vengono salvate dentro la scheda: l'archivio le tiene a parte,
indirizzate per contenuto, e la scheda ne conserva soltanto il riferimento. Una
stessa immagine occupa quindi un posto solo, per quante versioni della scheda la
mostrino. Ognuna viene ridotta al proprio riquadro al doppio della risoluzione —
quanto basta a disegnarla nitida — e ricodificata in JPEG, tranne quando ha
trasparenze da conservare, come il fondo ritagliato di un simbolo: in quel caso
resta PNG. Viene rifiutato soltanto un file sorgente oltre i 32 MB. Un'immagine
che nessuna scheda e nessuna versione cita più lascia l'archivio da sola.

Il backup completo su Drive ha un limite di 20 MB, uguale per caricamento e
download. Se l'archivio lo supera, il caricamento viene interrotto con un
messaggio: le schede locali e il backup già presente su Drive restano
conservati. Riduci le immagini o il numero di schede prima di riprovare.

Il nome nell'elenco e i campi nome nelle due pagine della scheda restano
sincronizzati, anche quando si usa il comando **Rinomina**.

Nell'elenco, il pulsante **Esporta schede in PDF** permette di selezionare una
o più schede, oppure tutte. Il PDF contiene tre pagine per personaggio e
mantiene i campi di testo e le caselle compilabili, con valori indipendenti
fra le schede. Include anche ritratto, simbolo, competenze e note dei campi;
anche le schede bloccate nell'app vengono esportate come moduli editabili.
Il menu della singola scheda offre **Esporta PDF** per esportarla direttamente.
Su desktop e Android si sceglie dove salvare; sul Web parte il download.

Il menu **Aspetto**, disponibile nell'elenco e nella scheda, permette di scegliere
**Chiaro**, **Scuro** o **Sistema**. La scelta viene ricordata sul dispositivo.
Il tema scuro adatta anche la carta, le cornici, le etichette, i campi e gli
indicatori della scheda: ritratto e simbolo mantengono i colori originali. La
versione scura dell'artwork è un asset a parte, generato in anticipo da
`scripts/generate_dark_artwork.py` (serve Pillow, NumPy e PyMuPDF): filtrarla a
ogni fotogramma costava due passaggi fuori schermo per pagina. Se cambiano la
palette scura o le pagine di partenza, i PNG vanno rigenerati con quello
script.

## Sincronizzazione Google Drive

Il sync usa un file JSON nello spazio privato `appDataFolder` e richiede
soltanto lo scope OAuth `drive.appdata`. Il backup è nel formato 2, che porta le
immagini in un elenco a parte invece di ripeterle dentro ogni scheda e ogni
versione; i backup nel formato 1 vengono letti e convertiti al primo sync. Una
versione dell'app che non conosce il formato 2 si fermerà con un messaggio senza
toccare i dati, quindi i dispositivi vanno aggiornati tutti. Le schede e le
versioni vengono unite per UUID. Le cancellazioni vengono sincronizzate e non
fanno ricomparire dati provenienti da un dispositivo non aggiornato; la traccia
di una cancellazione resta nel backup per 90 giorni, così l'elenco non cresce
all'infinito.

Le copie della stessa scheda si uniscono campo per campo: ogni campo, commento,
nome e blocco ricorda quando è cambiato l'ultima volta, e prevale la modifica
più recente di ciascuno. Due dispositivi che modificano campi diversi della
stessa scheda, anche offline, ritrovano entrambe le modifiche; sullo stesso
campo vince l'ultima. Una modifica fatta dopo aver ricevuto quella di un altro
dispositivo resta la più recente anche se l'orologio locale è indietro. Le
schede salvate da versioni precedenti, senza orologi per campo, si uniscono
come prima, sull'intera scheda, finché non vengono modificate.

Drive non permette scritture condizionate, quindi il sync non sovrascrive mai
un backup: scarica e unisce tutti quelli presenti, carica il risultato come
file nuovo e poi cancella quelli che ha unito. Due dispositivi che
sincronizzano nello stesso momento lasciano due file, che il sync successivo
riunisce senza perdere niente. Un backup aggiornato sul posto da una versione
precedente dell'app dopo il download non viene cancellato. Un backup che
contiene già tutto non viene ricaricato.

Il sync automatico riceve anche le modifiche fatte altrove, non solo invia le
proprie: gira ogni cinque minuti, quando l'app torna in primo piano e quando si
apre una scheda. Se la versione del backup non è cambiata dall'ultimo sync si
ferma dopo una sola richiesta leggera. Su desktop, chiudere la finestra salva
la scheda aperta e spedisce le modifiche in sospeso prima di uscire.

Una scheda aperta riceve gli aggiornamenti da Drive conservando le modifiche
locali ancora da salvare. Il salvataggio applica solo i campi modificati nella
sessione: se lo stesso campo viene cambiato anche da remoto, prevale la
modifica locale esplicita. Un personaggio eliminato da remoto non viene
ricreato da un editor rimasto aperto.

Su Linux e Windows l'archivio locale vive nella cartella dei dati dell'app
(`~/.local/share/…` su Linux, `%APPDATA%\…` su Windows), non più in Documenti,
dove OneDrive o altri client di sync potevano toccarlo durante la scrittura:
al primo avvio viene spostato. Una seconda finestra dell'app sullo stesso
archivio viene rifiutata, perché le due si sovrascriverebbero le modifiche.

Su desktop il token di refresh viene affidato al portachiavi del sistema —
libsecret su Linux, Credential Manager su Windows. Dove non c'è un servizio di
portachiavi raggiungibile resta la riserva su file, nella cartella di supporto
dell'app, leggibile soltanto dal proprietario; un token lasciato lì da una
versione precedente viene spostato nel portachiavi al primo avvio utile.

Su Linux e Windows il consenso Google scade dopo due minuti se non viene
completato nel browser. Il tentativo viene chiuso e si può riprovare dal menu
cloud senza riavviare l'applicazione.

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

Le build Linux richiedono anche le intestazioni del portachiavi:
`libsecret-1-dev` e `libjson-glib-dev` (oltre a `libgtk-3-dev`, `clang`,
`cmake`, `ninja-build`, `pkg-config`, `liblzma-dev`).

Il client secret dei client OAuth "Desktop" non è un segreto: il flusso usa
PKCE e Google lo tratta come pubblico, ma chi lo estrae dalla AppImage può
costruire un'applicazione che, ottenuto il consenso dell'utente, legge lo
stesso `appDataFolder` — che è isolato per client ID, non per applicazione. Il
consenso resta un passaggio esplicito con il nome dell'app in chiaro, quindi
non è una porta aperta, ma vale ricordarlo prima di riusare quelle credenziali
per qualcosa di diverso da questo archivio.

Su Android l'archivio è escluso dal backup automatico di sistema
(`android/app/src/main/res/xml/`): le schede lasciano il dispositivo soltanto
dal menu Drive. Il trasferimento diretto verso un nuovo telefono, che l'utente
avvia di persona, le porta invece con sé.

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

## Licenza

Il codice originale del progetto è distribuito sotto [licenza MIT](LICENSE).
Copyright (c) 2026 Cristiano Blanchi.

Le dipendenze e i materiali di terzi mantengono le rispettive licenze e i
relativi diritti. Il font Roboto Slab è distribuito sotto
[licenza Apache 2.0](assets/fonts/licenses/RobotoSlab-LICENSE.txt).
La licenza MIT del progetto non si estende a PDF, immagini, marchi o contenuti
D&D di terzi.
