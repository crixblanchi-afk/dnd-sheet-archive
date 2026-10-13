/// Canale di avanzamento verso l'isolate che genera il PDF.
///
/// Sulle piattaforme senza isolate `compute` esegue la funzione sul thread
/// della UI, che quindi non può ridisegnare nulla fino alla fine: un
/// avanzamento non sarebbe comunque visibile, e il canale resta inerte.
///
/// L'interfaccia deve restare identica a quella della variante con gli
/// isolate: `flutter analyze` risolve soltanto questa, mentre a compilare la
/// prima è il compilatore, quindi una divergenza si scopre a build fatta.
class ExportProgressChannel {
  const ExportProgressChannel._();

  /// Gettone da spedire all'isolate, `null` quando nessuno ascolta.
  Object? get token => null;

  void close() {}
}

ExportProgressChannel openExportProgress(void Function(int done)? onProgress) =>
    const ExportProgressChannel._();

void reportExportProgress(Object? token, int done) {}
