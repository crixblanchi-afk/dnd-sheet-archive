import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Nota di copyright della scheda ufficiale, la stessa stampata in fondo a
/// ogni pagina dell'artwork.
const sheetCopyrightNotice =
    'TM & © 2014 Wizards of the Coast LLC. Permission is granted to '
    'photocopy this document for personal use.';

const _sheetAttribution =
    'La scheda del personaggio riprodotta nell’app e nei PDF esportati è '
    'quella ufficiale di Dungeons & Dragons 5ª edizione.\n\n'
    '$sheetCopyrightNotice\n\n'
    'Dungeons & Dragons e D&D sono marchi di Wizards of the Coast LLC. '
    'Questa app non è affiliata a Wizards of the Coast, né approvata o '
    'sponsorizzata da essa.';

/// Aggiunge alla pagina delle licenze i materiali che non arrivano da un
/// pacchetto Dart: la scheda e il font delle esportazioni PDF.
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks([
      'Scheda del personaggio D&D 5e',
    ], _sheetAttribution);
    yield LicenseEntryWithLineBreaks(
      ['Roboto Slab'],
      await rootBundle.loadString(
        'assets/fonts/licenses/RobotoSlab-LICENSE.txt',
      ),
    );
  });
}

class AboutButton extends StatelessWidget {
  const AboutButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Informazioni',
    icon: const Icon(Icons.info_outline),
    onPressed: () => showAboutDialog(
      context: context,
      applicationName: 'Sheet Archive 5e',
      applicationLegalese: '© 2026 Cristiano Blanchi — licenza MIT',
      children: const [SizedBox(height: 16), Text(_sheetAttribution)],
    ),
  );
}
