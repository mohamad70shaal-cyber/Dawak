// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'dart:typed_data';

import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/sale.dart';
import 'package:dawak/features/pharmacist/controllers/sales_controllers.dart';
import 'package:dawak/features/pharmacist/services/receipt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import '../support/fixtures.dart';
import '../support/harness.dart';
import 'pharmacist_fixtures.dart';

void main() {
  late AppHarness h;

  setUp(() async {
    h = await AppHarness.create();
    await signInMember(h);
  });
  tearDown(() => h.dispose());

  Map<String, dynamic> saleRow(String id, String invoice, String createdAt) => <String, dynamic>{
        'id': id,
        'pharmacy_id': 'ph-1',
        'invoice_no': invoice,
        'currency': 'SYP',
        'total': 10000,
        'discount_amount': 0,
        'created_at': createdAt,
      };

  group('SalesHistoryController', () {
    setUp(() {
      h.api.tables['sales'] = <Map<String, dynamic>>[
        saleRow('s1', 'INV-000006', '2026-10-19T09:00:00Z'), // Monday (today)
        saleRow('s2', 'INV-000005', '2026-10-18T09:00:00Z'), // Sunday
        saleRow('s3', 'INV-000004', '2026-10-17T08:00:00Z'), // Saturday: first day of this week
        saleRow('s4', 'INV-000003', '2026-10-12T09:00:00Z'),
        saleRow('s5', 'INV-000002', '2026-10-05T09:00:00Z'),
        saleRow('s6', 'INV-000001', '2026-09-20T09:00:00Z'),
        <String, dynamic>{...saleRow('other', 'INV-999999', '2026-10-19T09:00:00Z'), 'pharmacy_id': 'ph-other'},
      ];
    });

    SalesHistoryController make() => SalesHistoryController(clock: () => DateTime(2026, 10, 19, 12))..onInit();

    Future<List<String>> ids(SalesHistoryController c) async {
      await c.paged.reload();
      return c.paged.items.map((SaleSummary s) => s.id).toList();
    }

    test('without a filter every sale of the pharmacy is listed, newest first', () async {
      expect(await ids(make()), <String>['s1', 's2', 's3', 's4', 's5', 's6']);
    });

    test('the date chips narrow the list; the week starts on Saturday', () async {
      final SalesHistoryController c = make();
      c.range.value = SalesRange.today;
      expect(await ids(c), <String>['s1']);
      c.range.value = SalesRange.week;
      expect(await ids(c), <String>['s1', 's2', 's3']);
      c.range.value = SalesRange.month;
      expect(await ids(c), <String>['s1', 's2', 's3', 's4', 's5']);
    });

    test('a custom range includes both end days', () async {
      final SalesHistoryController c = make();
      expect(c.setCustom(DateTime(2026, 10, 5), DateTime(2026, 10, 12)), isTrue);
      expect(await ids(c), <String>['s4', 's5']);
      expect(c.range.value, SalesRange.custom);
    });

    test('reversed dates are refused', () {
      final SalesHistoryController c = make();
      expect(c.setCustom(DateTime(2026, 10, 12), DateTime(2026, 10, 5)), isFalse);
      expect(c.range.value, SalesRange.all);
    });

    test('searching by invoice number finds the sale', () async {
      final SalesHistoryController c = make();
      c.search('000003');
      expect(await ids(c), <String>['s4']);
    });

    test('characters that would break the filter are ignored in the search', () async {
      final SalesHistoryController c = make();
      c.search('INV-0000(03)%');
      expect(await ids(c), <String>['s4']);
    });

    test('cashiers are told they only see their own sales', () async {
      expect(make().isCashier, isFalse);
    });

    test('opening a sale goes to its receipt', () async {
      final List<String> routes = <String>[];
      final SalesHistoryController c = SalesHistoryController(open: (String r) async {
        routes.add(r);
        return null;
      });
      await c.openSale(SaleSummary.fromJson(saleRow('s1', 'INV-000006', '2026-10-19T09:00:00Z')));
      expect(routes, <String>[AppRoutes.sale('s1')]);
    });
  });

  group('SalesHistoryController as a cashier', () {
    test('is recognised as a cashier', () async {
      h.dispose();
      h = await AppHarness.create();
      await signInMember(h, memberRole: 'cashier');
      expect(SalesHistoryController().isCashier, isTrue);
    });
  });

  group('SaleDetailsController', () {
    late List<String> shared;
    late List<String> printed;

    ReceiptService receipts({bool failShare = false}) => ReceiptService(
          fontLoader: (String asset) async => pw.Font.helvetica(),
          shareFn: (Uint8List bytes, String name) async {
            if (failShare) throw StateError('no share sheet');
            shared.add(name);
          },
          printFn: (Uint8List bytes, String name) async => printed.add(name),
        );

    setUp(() {
      shared = <String>[];
      printed = <String>[];
      h.api.rpcs['get_sale'] = (Map<String, dynamic> p) => Fx.saleJson(p['p_sale_id'] as String, invoice: 'INV-000042');
    });

    test('loads the sale from the server', () async {
      final SaleDetailsController c = SaleDetailsController(saleId: 'sale-1', receipts: receipts());
      await c.refresh();
      expect(c.sale.value!.invoiceNo, 'INV-000042');
      expect(c.sale.value!.items.single.quantity, 2);
      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_sale_id': 'sale-1'});
    });

    test('sharing and printing hand the PDF named after the invoice to the system', () async {
      final SaleDetailsController c = SaleDetailsController(saleId: 'sale-1', receipts: receipts());
      await c.refresh();
      expect(await c.sharePdf(), isTrue);
      expect(await c.printReceipt(), isTrue);
      expect(shared, <String>['INV-000042.pdf']);
      expect(printed, <String>['INV-000042.pdf']);
      expect(c.working.value, isFalse);
    });

    test('a failing share sheet gives false and leaves the screen usable', () async {
      final SaleDetailsController c = SaleDetailsController(saleId: 'sale-1', receipts: receipts(failShare: true));
      await c.refresh();
      expect(await c.sharePdf(), isFalse);
      expect(c.working.value, isFalse);
    });

    test('nothing happens before the sale has loaded', () async {
      final SaleDetailsController c = SaleDetailsController(saleId: 'sale-1', receipts: receipts());
      expect(await c.sharePdf(), isFalse);
      expect(shared, isEmpty);
    });

    test('a sale that came from an order links back to it', () async {
      h.api.rpcs['get_sale'] = (Map<String, dynamic> p) => <String, dynamic>{...Fx.saleJson('sale-1'), 'order_id': 'o5'};
      final List<String> routes = <String>[];
      final SaleDetailsController c = SaleDetailsController(saleId: 'sale-1', receipts: receipts(), open: routes.add);
      await c.refresh();
      c.openOrder();
      expect(routes, <String>[AppRoutes.pharmacistOrder('o5')]);
    });

    test('a counter sale has no order to open', () async {
      final List<String> routes = <String>[];
      final SaleDetailsController c = SaleDetailsController(saleId: 'sale-1', receipts: receipts(), open: routes.add);
      await c.refresh();
      c.openOrder();
      expect(routes, isEmpty);
    });

    test('a missing sale is a failure the screen can show', () async {
      h.api.rpcs['get_sale'] = (Map<String, dynamic> p) => throw const AppFailure('not_found');
      final SaleDetailsController c = SaleDetailsController(saleId: 'nope', receipts: receipts());
      await c.refresh();
      expect(c.failure.value?.code, 'not_found');
    });
  });

  group('PosCompletedController', () {
    setUp(() {
      h.api.rpcs['get_sale'] = (Map<String, dynamic> p) => Fx.saleJson('sale-9');
    });

    test('loads the sale by id, opens its receipt and starts a new sale', () async {
      int started = 0;
      final List<String> routes = <String>[];
      final PosCompletedController c = PosCompletedController(saleId: 'sale-9', startNew: () => started++, open: routes.add);
      await c.refresh();
      expect(c.sale.value!.id, 'sale-9');
      c.openReceipt();
      c.newSale();
      expect(routes, <String>[AppRoutes.sale('sale-9')]);
      expect(started, 1);
    });
  });

  group('ReceiptService', () {
    late List<String> fontsAsked;

    ReceiptService service() {
      fontsAsked = <String>[];
      return ReceiptService(
        fontLoader: (String asset) async {
          fontsAsked.add(asset);
          return pw.Font.helvetica();
        },
        shareFn: (Uint8List bytes, String name) async {},
        printFn: (Uint8List bytes, String name) async {},
      );
    }

    test('builds a PDF document from the sale row and loads the regular and the bold font', () async {
      final Uint8List bytes = await service().buildPdf(Sale.fromJson(Fx.saleJson('s1')));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(fontsAsked, <String>[ReceiptService.regularAsset, ReceiptService.boldAsset]);
    });

    test('a discounted sale builds too', () async {
      final Map<String, dynamic> json = <String, dynamic>{...Fx.saleJson('s1', total: 9000), 'subtotal': 10000, 'discount_amount': 1000};
      final Sale sale = Sale.fromJson(json);
      expect(sale.hasDiscount, isTrue);
      final Uint8List bytes = await service().buildPdf(sale);
      expect(bytes.length, greaterThan(500));
    });

    test('the file is named after the invoice number', () {
      expect(ReceiptService.fileName(Sale.fromJson(Fx.saleJson('s1', invoice: 'INV-000007'))), 'INV-000007.pdf');
    });
  });
}
