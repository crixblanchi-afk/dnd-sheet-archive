import 'dart:async';
import 'dart:isolate';

/// Canale di avanzamento verso l'isolate che genera il PDF.
///
/// L'export di molte schede dura secondi: senza un segnale di ritorno la UI
/// potrebbe soltanto mostrare uno spinner indeterminato per tutto il tempo.
class ExportProgressChannel {
  ExportProgressChannel._(this._port, this._subscription);

  final ReceivePort? _port;
  final StreamSubscription<dynamic>? _subscription;

  /// Gettone da spedire all'isolate, `null` quando nessuno ascolta.
  Object? get token => _port?.sendPort;

  void close() {
    unawaited(_subscription?.cancel());
    _port?.close();
  }
}

ExportProgressChannel openExportProgress(void Function(int done)? onProgress) {
  if (onProgress == null) return ExportProgressChannel._(null, null);
  final port = ReceivePort();
  return ExportProgressChannel._(
    port,
    port.listen((message) {
      if (message is int) onProgress(message);
    }),
  );
}

void reportExportProgress(Object? token, int done) {
  if (token is SendPort) token.send(done);
}
