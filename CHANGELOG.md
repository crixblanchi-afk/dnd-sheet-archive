# Changelog

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
