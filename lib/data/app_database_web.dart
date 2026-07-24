import 'package:sembast_web/sembast_web.dart';

Future<Database> openAppDatabase() =>
    databaseFactoryWeb.openDatabase('dnd_sheet_archive');
