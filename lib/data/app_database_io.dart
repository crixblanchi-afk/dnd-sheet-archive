import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openAppDatabase() async {
  final directory = await getApplicationDocumentsDirectory();
  await directory.create(recursive: true);
  return databaseFactoryIo.openDatabase(
    p.join(directory.path, 'dnd_sheet_archive.db'),
  );
}
