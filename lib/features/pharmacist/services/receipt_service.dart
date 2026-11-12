import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/sale.dart';

/// Builds the cash receipt of a sale as a PDF (P-44) and hands it to the system share sheet (P-45) or the printer
/// (P-52). The receipt is rendered from the server's sale row only, never from the basket, so a reprint always shows what
/// was really charged. Fonts and the share/print plug-ins are injectable so tests do not need a device.
class ReceiptService {
  ReceiptService({
    Future<pw.Font> Function(String asset)? fontLoader,
    Future<void> Function(Uint8List bytes, String name)? shareFn,
    Future<void> Function(Uint8List bytes, String name)? printFn,
  })  : _fontLoader = fontLoader ?? _bundleFont,
        _share = shareFn ?? _defaultShare,
        _print = printFn ?? _defaultPrint;

  final Future<pw.Font> Function(String asset) _fontLoader;
  final Future<void> Function(Uint8List bytes, String name) _share;
  final Future<void> Function(Uint8List bytes, String name) _print;

  static const String regularAsset = 'assets/fonts/Cairo_400Regular.ttf';
  static const String boldAsset = 'assets/fonts/Cairo_700Bold.ttf';

  static Future<pw.Font> _bundleFont(String asset) async => pw.Font.ttf(await rootBundle.load(asset));

  static Future<void> _defaultShare(Uint8List bytes, String name) async {
    await Printing.sharePdf(bytes: bytes, filename: name);
  }

  static Future<void> _defaultPrint(Uint8List bytes, String name) async {
    await Printing.layoutPdf(name: name, onLayout: (PdfPageFormat format) async => bytes);
  }

  static String fileName(Sale sale) => '${sale.invoiceNo}.pdf';

  Future<Uint8List> buildPdf(Sale sale) async {
    final pw.Font regular = await _fontLoader(regularAsset);
    final pw.Font bold = await _fontLoader(boldAsset);
    final bool arabic = Get.locale?.languageCode != 'en';
    final pw.TextDirection dir = arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    pw.Widget ltr(String text, {pw.TextStyle? style}) =>
        pw.Directionality(textDirection: pw.TextDirection.ltr, child: pw.Text(text, style: style));

    pw.Widget kv(String label, pw.Widget value, {bool strong = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(label, style: strong ? pw.TextStyle(font: bold, fontSize: 12) : const pw.TextStyle(fontSize: 10)),
              value,
            ],
          ),
        );

    final pw.Document doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        textDirection: dir,
        build: (pw.Context context) => <pw.Widget>[
          pw.Center(child: pw.Text(sale.pharmacyName, style: pw.TextStyle(font: bold, fontSize: 16))),
          if (sale.pharmacyAddress.isNotEmpty) pw.Center(child: pw.Text(sale.pharmacyAddress, style: const pw.TextStyle(fontSize: 9))),
          if ((sale.pharmacyPhone ?? '').isNotEmpty) pw.Center(child: ltr(sale.pharmacyPhone!, style: const pw.TextStyle(fontSize: 9))),
          pw.SizedBox(height: 10),
          pw.Center(child: pw.Text('p_receipt_title'.tr, style: pw.TextStyle(font: bold, fontSize: 13))),
          pw.Divider(),
          kv('p_receipt_invoice'.tr, ltr(sale.invoiceNo, style: pw.TextStyle(font: bold, fontSize: 10))),
          kv('p_receipt_date'.tr, ltr(Fmt.dateTime(sale.createdAt), style: const pw.TextStyle(fontSize: 10))),
          if (sale.cashierName.isNotEmpty) kv('p_receipt_cashier'.tr, pw.Text(sale.cashierName, style: const pw.TextStyle(fontSize: 10))),
          pw.Divider(),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(flex: 5, child: pw.Text('p_receipt_item'.tr, style: pw.TextStyle(font: bold, fontSize: 10))),
              pw.Expanded(flex: 1, child: pw.Center(child: pw.Text('p_receipt_qty'.tr, style: pw.TextStyle(font: bold, fontSize: 10)))),
              pw.Expanded(flex: 2, child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('p_receipt_total'.tr, style: pw.TextStyle(font: bold, fontSize: 10)))),
            ],
          ),
          pw.Divider(thickness: 0.5),
          for (final SaleItem i in sale.items)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: <pw.Widget>[
                        pw.Text(i.name, style: const pw.TextStyle(fontSize: 10)),
                        if ((i.strength ?? '').isNotEmpty) pw.Text(i.strength!, style: const pw.TextStyle(fontSize: 8)),
                        ltr('${Fmt.money(i.unitPrice, sale.currency)} × ${i.quantity}', style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ),
                  pw.Expanded(flex: 1, child: pw.Center(child: ltr('${i.quantity}', style: const pw.TextStyle(fontSize: 10)))),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Align(alignment: pw.Alignment.centerRight, child: ltr(Fmt.money(i.lineTotal, sale.currency), style: const pw.TextStyle(fontSize: 10))),
                  ),
                ],
              ),
            ),
          pw.Divider(),
          kv('p_receipt_subtotal'.tr, ltr(Fmt.money(sale.subtotal, sale.currency), style: const pw.TextStyle(fontSize: 10))),
          if (sale.hasDiscount) kv('p_receipt_discount'.tr, ltr('-${Fmt.money(sale.discountAmount, sale.currency)}', style: const pw.TextStyle(fontSize: 10))),
          kv('p_receipt_grand_total'.tr, ltr(Fmt.money(sale.total, sale.currency), style: pw.TextStyle(font: bold, fontSize: 13)), strong: true),
          pw.SizedBox(height: 8),
          pw.Center(child: pw.Text('p_receipt_cash'.tr, style: const pw.TextStyle(fontSize: 9))),
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text('p_receipt_thanks'.tr, style: const pw.TextStyle(fontSize: 9))),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> share(Sale sale) async => _share(await buildPdf(sale), fileName(sale));

  Future<void> printReceipt(Sale sale) async => _print(await buildPdf(sale), fileName(sale));
}
