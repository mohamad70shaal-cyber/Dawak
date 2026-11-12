import 'package:file_picker/file_picker.dart';

/// A licence document the user chose (kept in memory until the wizard is submitted).
class PickedLicense {
  const PickedLicense({required this.name, required this.bytes, required this.contentType});

  final String name;
  final List<int> bytes;
  final String contentType;

  int get size => bytes.length;
}

/// Opens the system file chooser. Injected into the registration controller so tests never touch a plugin.
typedef LicensePicker = Future<PickedLicense?> Function();

/// What the private `pharmacy-documents` bucket accepts: PDF, JPEG and PNG up to 5 MB.
class LicenseFiles {
  const LicenseFiles._();

  static const int maxBytes = 5 * 1024 * 1024;

  static const Map<String, String> contentTypes = <String, String>{
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
  };

  /// MIME type for [fileName] from its extension, or null when the type is not accepted.
  static String? contentTypeFor(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return null;
    return contentTypes[fileName.substring(dot + 1).toLowerCase()];
  }

  static Future<PickedLicense?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: contentTypes.keys.toList(),
      withData: true,
    );
    if (r == null || r.files.isEmpty) return null;
    final PlatformFile f = r.files.first;
    final List<int>? bytes = f.bytes;
    if (bytes == null) return null;
    return PickedLicense(name: f.name, bytes: bytes, contentType: contentTypeFor(f.name) ?? 'application/octet-stream');
  }
}
