import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/map_links.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/geo.dart';

/// Opens [uri] in another app; tells the user when nothing can handle it.
Future<void> launchExternal(Uri uri) async {
  try {
    final bool ok = await launchUrl(uri);
    if (!ok) AppToast.error('c_cannot_open'.tr);
  } catch (_) {
    AppToast.error('c_cannot_open'.tr);
  }
}

/// Opens the phone's map app with directions to [to].
Future<void> openDirections(GeoPoint to) => launchExternal(MapLinks.directions(to));

Future<void> callPhone(String phone) => launchExternal(Uri(scheme: 'tel', path: phone));

Future<void> writeEmail(String address) => launchExternal(Uri(scheme: 'mailto', path: address));

/// Copies [text] and confirms with a toast.
Future<void> copyText(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  AppToast.success('copied'.tr);
}
