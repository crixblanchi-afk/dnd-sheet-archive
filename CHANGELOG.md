# Changelog

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
