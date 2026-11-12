import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A spreadsheet or text file the pharmacist chose (kept in memory while the import wizard runs).
class PickedImportFile {
  const PickedImportFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Opens the system file chooser. Injected into the import controller so tests never touch a plugin.
typedef ImportFilePicker = Future<PickedImportFile?> Function();

class ImportFiles {
  const ImportFiles._();

  /// Larger files are refused before parsing (a price list of 20 000 rows is well below this).
  static const int maxBytes = 10 * 1024 * 1024;

  static const List<String> extensions = <String>['xlsx', 'xlsm', 'csv', 'tsv', 'txt'];

  static Future<PickedImportFile?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    if (r == null || r.files.isEmpty) return null;
    final PlatformFile f = r.files.first;
    final Uint8List? bytes = f.bytes;
    if (bytes == null) return null;
    return PickedImportFile(name: f.name, bytes: bytes);
  }
}
