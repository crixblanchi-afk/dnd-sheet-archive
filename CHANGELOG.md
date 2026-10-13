# Changelog

## 1.4.0 — 2026-10-14

- Modifica contemporanea più resiliente: le copie di una scheda si uniscono
  campo per campo, con un orologio per ogni campo, commento, nome e blocco.
  Due dispositivi che modificano campi diversi conservano entrambe le
  modifiche invece di perdere quelle di chi ha salvato per primo. Gli orologi
  non tornano mai indietro rispetto all'ultima modifica ricevuta, così un
  dispositivo con l'orologio indietro non perde le proprie.
- Il sync non sovrascrive più il backup su Drive: carica un file nuovo e
  cancella soltanto quelli che ha già unito. Due dispositivi che sincronizzano
  insieme lasciano due file, riuniti al giro successivo, invece di cancellare
  l'uno le modifiche dell'altro.
- Il sync automatico riceve le modifiche fatte altrove anche senza modifiche
  locali: ogni cinque minuti, al ritorno in primo piano e all'apertura di una
  scheda, con una sola richiesta leggera quando non è cambiato niente. Un
  backup che contiene già tutto non viene ricaricato.
- Corretta la perdita di un'immagine appena scelta: se un sync cadeva prima
  dell'autosalvataggio della scheda, la raccolta delle immagini orfane la
  cancellava. Le immagini nuove ora hanno un giorno di tregua.
- Su desktop, chiudere la finestra salva la scheda aperta e spedisce le
  modifiche in sospeso prima di uscire.
- Su Linux e Windows l'archivio passa dalla cartella Documenti a quella dei
  dati dell'app, con spostamento automatico al primo avvio; una seconda
  istanza dell'app viene rifiutata invece di corrompere l'archivio.
- Un record danneggiato non blocca più l'elenco e il sync delle altre schede.
- Avvio: errore dettagliato e pulsante «Riprova» se l'archivio non si apre.
- Export PDF: un'immagine condivisa da più schede viene incorporata una volta.
- CI: una build Android di release senza chiave di firma fallisce invece di
  produrre un APK firmato con la chiave di debug.
- Scheda più fluida durante l'animazione della tastiera e il
  ridimensionamento della finestra: le pagine non vengono più ricostruite a
  ogni fotogramma — prima erano più di cento campi per fotogramma nella vista
  a pagine e più di trecento in quella a scorrimento, ora nessuno.
- Vista a pagine: le pagine già viste restano vive e quella accanto viene
  preparata a gesto fermo, quindi lo swipe non costruisce più duecento campi
  nel fotogramma in cui parte. L'artwork delle tre pagine viene precaricato.
- Digitazione più leggera nei campi lunghi: l'adattamento del carattere parte
  dalla dimensione trovata per il testo precedente e di solito si chiude con un
  solo layout invece di dodici.

Build: **9**. Verifiche: **169 test** e analisi statica. I pacchetti Android,
Linux x86_64 e ARM64, Windows e Web vengono creati da GitHub Actions.
Restano da verificare su dispositivi reali il sync contemporaneo, la chiusura
della finestra desktop e la fluidità durante l'apertura della tastiera Android.

## 1.3.1 — 2026-10-13

- Tema scuro con l'artwork della scheda precalcolato invece di filtrato a
  ogni fotogramma: via i due `ColorFiltered` annidati che imponevano due
  `saveLayer` a piena pagina — sei, con le tre pagine della vista a
  scorrimento. Ritratto e simbolo conservano i colori originali.
- Carta scura più calda e grassetto distinguibile dal testo normale, in linea
  con l'artwork precalcolato.
- Zoom sotto il 100% letto correttamente: la scala viene applicata anche
  all'asse Z, che `InteractiveViewer`, le scrollbar e il vincolo orizzontale
  leggono come massimo dei tre. Prima, rimpicciolendo, la scheda si appoggiava
  al bordo sinistro e il trascinamento le si opponeva.
- Scrollbar della scheda ridisegnate invece che ricostruite, e comandi di zoom
  che non si ricostruiscono più a ogni fotogramma di trascinamento.
- Adattamento alla larghezza che non ricostruisce le tre pagine con tutti i
  loro campi solo per cambiare l'icona di un pulsante.
- Misure del testo condivise fra le caselle: tornare su una pagina già vista o
  cambiare modalità non rimisura di nuovo tutti i campi.
- Ritratto e simbolo non vengono più ridecodificati a ogni ritorno sulla
  pagina.

Build: **8**. Verifiche: **145 test**, analisi statica e build Web e Windows
sulla pull request; anteprime delle tre pagine scure controllate prima del
rilascio. I pacchetti di release vengono creati da GitHub Actions.

## 1.3.0 — 2026-10-13

- Immagini conservate una sola volta per contenuto, fuori dalla scheda, e
  condivise fra le sue versioni e il backup: una scheda illustrata non pesa più
  dieci volte la propria immagine. Ricodifica in JPEG quando non ci sono
  trasparenze da preservare.
- Backup Drive nel formato 2, con le immagini in un elenco a parte; i backup
  nel formato 1 vengono convertiti al primo sync e le schede già salvate
  migrano al primo avvio.
- Serializzazione e lettura del backup spostate in un isolate: il sync non
  blocca più l'interfaccia mentre prepara fino a 20 MB di archivio.
- Il sync aggiorna soltanto i record cambiati invece di riscrivere l'intero
  archivio locale, riducendo la finestra in cui un'interruzione poteva lasciarlo
  incompleto.
- Token di refresh Google su desktop nel portachiavi del sistema, con riserva
  su file ristretta al proprietario e migrazione automatica.
- Archivio escluso dal backup automatico di Android, conservato nel
  trasferimento diretto verso un nuovo dispositivo.
- Avanzamento per scheda durante l'esportazione PDF di più personaggi.
- Digitare il nome non ricostruisce più tutti i campi della pagina, e
  l'artwork della scheda viene decodificato alla densità dello schermo.
- Workflow di release con action fissate al commit; rimosso il workflow di
  diagnostica che firmava con la chiave di release.

Attenzione: il formato 2 del backup non è leggibile dalle versioni precedenti,
che si fermano con un messaggio senza toccare i dati. Vanno aggiornati tutti i
dispositivi che condividono lo stesso archivio Drive.

Build: **7**. Verifiche: **141 test**, analisi statica e build Linux, Web e
Android verificate in locale; i pacchetti di release vengono creati da GitHub
Actions.

## 1.2.1 — 2026-10-11

- Ripristinata la scelta fra vista a pagine e vista a scorrimento dal menu
  Visualizzazione scheda.
- Pagine sfogliabili con swipe orizzontale, senza barra inferiore né zoom,
  adattate all'intera area disponibile mantenendo le proporzioni del foglio.
- Vista continua con pan, zoom, adattamento alla larghezza e scrollbar.
- Modifiche, blocco e ultima pagina sfogliata conservati al cambio modalità.
- Spostamento del campo sopra la tastiera corretto anche con zoom al 50% e al
  200%; eliminati i salti verso campi precedenti dopo la perdita del focus.

Build: **6**. Verifiche: **118 test**, analisi statica e build Web e Windows
sulla pull request.

## 1.2.0 — 2026-10-11

- Visualizzazione della scheda una pagina alla volta, con frecce precedente e
  successiva e indicatore del numero di pagina.
- Fogli adattati automaticamente allo spazio disponibile, senza zoom né
  scorrimento; modifiche e stato di blocco conservati al cambio pagina.
- Comandi di navigazione disponibili anche sopra la tastiera aperta.
- Margini proporzionali quando resta poca altezza, così la pagina e il campo
  attivo rimangono visibili anche in una finestra bassa con la tastiera aperta.
- Lanciadadi nascosto temporaneamente nelle viste compatte, conservando il suo
  stato e ripristinandolo quando torna disponibile lo spazio necessario.

Build: **5**. Verifiche: **114 test**, analisi statica e build Web e Windows
sulla pull request.

## 1.1.0 — 2026-10-01

- Esportazione dalla lista di una, più o tutte le schede in un PDF compilabile,
  con tre pagine per personaggio, valori indipendenti, immagini, note e competenze.
- Esportazione diretta dal menu della singola scheda, salvataggio su desktop e
  Android e download sul Web.
- Tema chiaro, scuro o di sistema, con scelta persistente e colori adattati anche
  alla scheda.
- Il comando Indietro chiude prima la tastiera, senza uscire subito dalla scheda.
- Aggiornamenti da Drive nelle schede aperte senza perdere le modifiche locali;
  le schede eliminate da remoto non vengono ricreate dall'editor.
- Nome del personaggio coerente fra elenco e campi della scheda, anche dopo una
  rinomina o un ripristino dalla cronologia.
- Consenso Google su desktop limitato a due minuti e cancellazione dei tentativi
  abbandonati, con possibilità di riprovare senza riavviare l'app.
- Backup Drive limitato a 20 MB in upload e download, con controlli sulla sessione
  di accesso prima di modificare l'archivio o pubblicare il backup.

Build: **4**. Verifiche: **112 test**, analisi statica e build Web; controllo dei
campi e dell'aspetto dei PDF esportati anche dopo una modifica.
