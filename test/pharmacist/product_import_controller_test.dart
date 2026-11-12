// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/medicine.dart';
import 'package:dawak/features/pharmacist/controllers/product_import_controller.dart';
import 'package:dawak/features/pharmacist/services/import_file_picker.dart';
import 'package:dawak/features/pharmacist/services/import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import 'pharmacist_fixtures.dart';

/// One suggestion the fake server returns for a name.
class Sug {
  const Sug(this.id, this.score);

  final String id;
  final double score;
}

PickedImportFile csvFile(String text, {String name = 'prices.csv'}) =>
    PickedImportFile(name: name, bytes: Uint8List.fromList(utf8.encode(text)));

void main() {
  late AppHarness h;

  setUp(() async {
    h = await AppHarness.create();
    await signInMember(h);
  });
  tearDown(() => h.dispose());

  ProductImportController make({PickedImportFile? file}) => ProductImportController(picker: () async => file)..onInit();

  /// `match_medicine_names` answers from [byName]; names that are not in the map get no suggestions.
  void serveMatches(Map<String, List<Sug>> byName) {
    h.api.rpcs['match_medicine_names'] = (Map<String, dynamic> p) {
      final List<dynamic> names = p['p_names'] as List<dynamic>;
      return <Map<String, dynamic>>[
        for (int i = 0; i < names.length; i++)
          for (final Sug s in byName[names[i]] ?? const <Sug>[])
            <String, dynamic>{'idx': i + 1, 'medicine_id': s.id, 'name_ar': 'دواء ${s.id}', 'name_en': 'Med ${s.id}', 'score': s.score},
      ];
    };
  }

  void serveBulk() {
    h.api.rpcs['bulk_upsert_pharmacy_products'] = (Map<String, dynamic> p) {
      final int n = (p['p_items'] as List<dynamic>).length;
      return <String, dynamic>{'inserted': n, 'updated': 0, 'skipped': 0};
    };
  }

  const String basicCsv = 'الاسم,السعر\nبنادول,5000\nأموكسيل,3000\nبروفين,1200\nزنك,0\nفيتامين,';

  /// A controller that already read [basicCsv] and sits on the columns step.
  Future<ProductImportController> onColumns({String text = basicCsv}) async {
    final ProductImportController c = make(file: csvFile(text));
    await c.pickFile();
    expect(c.step.value, ImportStep.columns);
    return c;
  }

  group('the file step', () {
    test('a readable file opens the columns step with the columns guessed and the rows listed', () async {
      final ProductImportController c = await onColumns();
      expect(c.fileName.value, 'prices.csv');
      expect(c.importError.value, isNull);
      expect(c.columns.value.nameColumn, 0);
      expect(c.columns.value.priceColumn, 1);
      expect(c.columns.value.hasHeader, isTrue);
      expect(c.lines.map((ImportLine l) => l.name), <String>['بنادول', 'أموكسيل', 'بروفين', 'زنك', 'فيتامين']);
    });

    test('closing the chooser without a file changes nothing', () async {
      final ProductImportController c = make();
      await c.pickFile();
      expect(c.step.value, ImportStep.pick);
      expect(c.importError.value, isNull);
    });

    test('a chooser that throws gives the "could not read the file" message', () async {
      final ProductImportController c = ProductImportController(picker: () async => throw StateError('plugin'))..onInit();
      await c.pickFile();
      expect(c.step.value, ImportStep.pick);
      expect(c.importError.value, 'p_import_err_unreadable_file');
    });

    test('a file over the size limit is refused before parsing', () async {
      final ProductImportController c = make(
        file: PickedImportFile(name: 'big.csv', bytes: Uint8List(ImportFiles.maxBytes + 1)),
      );
      await c.pickFile();
      expect(c.step.value, ImportStep.pick);
      expect(c.importError.value, 'p_import_err_too_large');
    });

    test('an unsupported or empty file is refused with its own message', () async {
      final ProductImportController pdf = make(file: csvFile('x', name: 'list.pdf'));
      await pdf.pickFile();
      expect(pdf.importError.value, 'p_import_err_unsupported_file');

      final ProductImportController empty = make(file: csvFile('', name: 'list.csv'));
      await empty.pickFile();
      expect(empty.importError.value, 'p_import_err_empty_file');
      expect(empty.step.value, ImportStep.pick);
    });

    test('choosing a good file after a bad one clears the message', () async {
      final ProductImportController c = make(file: csvFile('x', name: 'list.pdf'));
      await c.pickFile();
      expect(c.importError.value, isNotNull);
      final ProductImportController d = ProductImportController(picker: () async => csvFile(basicCsv))..onInit();
      d.importError.value = 'p_import_err_empty_file';
      await d.pickFile();
      expect(d.importError.value, isNull);
    });
  });

  group('the columns step', () {
    test('rows without a price (empty or zero) are counted as skipped and are not matched', () async {
      final ProductImportController c = await onColumns();
      expect(c.usableLines.map((ImportLine l) => l.name), <String>['بنادول', 'أموكسيل', 'بروفين']);
      expect(c.skippedNoPrice, 2);
      expect(c.canMatch, isTrue);
    });

    test('changing a column or the header switch re-reads the rows', () async {
      final ProductImportController c = await onColumns(text: 'السعر,الاسم\n5000,بنادول\n3000,أموكسيل');
      expect(c.columns.value.nameColumn, 1);
      expect(c.columns.value.priceColumn, 0);
      expect(c.usableLines.length, 2);

      c.setNameColumn(0); // now both point at the price column
      expect(c.sameColumn, isTrue);
      expect(c.canMatch, isFalse);

      c.setNameColumn(1);
      c.setHasHeader(false); // the header row becomes a data row without a usable price
      expect(c.lines.length, 3);
      expect(c.usableLines.length, 2);
      expect(c.skippedNoPrice, 1);
    });

    test('the same column for name and price is refused without calling the server', () async {
      final ProductImportController c = await onColumns();
      c.setPriceColumn(0);
      await c.startMatching();
      expect(c.importError.value, 'p_import_err_same_column');
      expect(c.step.value, ImportStep.columns);
      expect(h.api.rpcCount('match_medicine_names'), 0);
    });

    test('a file with no usable prices is refused without calling the server', () async {
      final ProductImportController c = await onColumns(text: 'الاسم,السعر\nبنادول,\nأموكسيل,0');
      await c.startMatching();
      expect(c.importError.value, 'p_import_err_no_rows');
      expect(h.api.rpcCount('match_medicine_names'), 0);
    });

    test('going back to the file step forgets the file and the rows', () async {
      final ProductImportController c = await onColumns();
      c.backToFile();
      expect(c.step.value, ImportStep.pick);
      expect(c.table.value, isNull);
      expect(c.lines, isEmpty);
    });
  });

  group('matching', () {
    test('sends the names of the usable rows only and lands on the review step', () async {
      serveMatches(<String, List<Sug>>{});
      final ProductImportController c = await onColumns();
      await c.startMatching();
      expect(h.api.rpcLog.single.params['p_names'], <String>['بنادول', 'أموكسيل', 'بروفين']);
      expect(c.step.value, ImportStep.review);
      expect(c.rows.length, 3);
      expect(c.progress.value, 1.0);
    });

    test('a clear, strong match is accepted automatically', () async {
      serveMatches(<String, List<Sug>>{
        'بنادول': <Sug>[const Sug('m1', 0.95), const Sug('m2', 0.6)],
      });
      final ProductImportController c = await onColumns();
      await c.startMatching();
      final ImportRow r = c.rows.first;
      expect(r.kind, ImportRowKind.auto);
      expect(r.chosen.value?.medicine.id, 'm1');
      expect(r.included.value, isTrue);
      expect(r.willSave, isTrue);
    });

    test('exactly the threshold with a single suggestion is still automatic', () async {
      serveMatches(<String, List<Sug>>{
        'بنادول': <Sug>[const Sug('m1', ProductImportController.autoScore)],
      });
      final ProductImportController c = await onColumns();
      await c.startMatching();
      expect(c.rows.first.kind, ImportRowKind.auto);
    });

    test('a strong match with a close runner-up is left for the pharmacist to choose', () async {
      serveMatches(<String, List<Sug>>{
        'بنادول': <Sug>[const Sug('m1', 0.92), const Sug('m2', 0.88)],
      });
      final ProductImportController c = await onColumns();
      await c.startMatching();
      final ImportRow r = c.rows.first;
      expect(r.kind, ImportRowKind.review);
      expect(r.chosen.value, isNull);
      expect(r.included.value, isFalse);
      expect(r.matches.map((NameMatch m) => m.medicine.id), <String>['m1', 'm2']);
    });

    test('a weak match needs a review even when it is the only suggestion', () async {
      serveMatches(<String, List<Sug>>{
        'أموكسيل': <Sug>[const Sug('m3', 0.6)],
      });
      final ProductImportController c = await onColumns();
      await c.startMatching();
      expect(c.rows[1].kind, ImportRowKind.review);
    });

    test('a name nothing matched is "unmatched" and cannot be ticked', () async {
      serveMatches(<String, List<Sug>>{});
      final ProductImportController c = await onColumns();
      await c.startMatching();
      final ImportRow r = c.rows.first;
      expect(r.kind, ImportRowKind.unmatched);
      expect(r.matches, isEmpty);
      c.toggle(r, true);
      expect(r.included.value, isFalse);
    });

    test('the counts by kind and the ready / undecided numbers add up', () async {
      serveMatches(<String, List<Sug>>{
        'بنادول': <Sug>[const Sug('m1', 0.95)],
        'أموكسيل': <Sug>[const Sug('m2', 0.6)],
      });
      final ProductImportController c = await onColumns();
      await c.startMatching();
      expect(c.count(ImportRowKind.auto), 1);
      expect(c.count(ImportRowKind.review), 1);
      expect(c.count(ImportRowKind.unmatched), 1);
      expect(c.readyCount, 1);
      expect(c.undecidedCount, 1);
    });

    test('suggestions come back best first even when the server lists them in another order', () async {
      serveMatches(<String, List<Sug>>{
        'بنادول': <Sug>[const Sug('low', 0.5), const Sug('high', 0.97)],
      });
      final ProductImportController c = await onColumns();
      await c.startMatching();
      expect(c.rows.first.matches.first.medicine.id, 'high');
      expect(c.rows.first.kind, ImportRowKind.auto);
    });

    test('more than 100 names are matched in several calls and the rows stay in file order', () async {
      serveMatches(<String, List<Sug>>{});
      final String body = List<String>.generate(130, (int i) => 'دواء$i,${1000 + i}').join('\n');
      final ProductImportController c = await onColumns(text: 'الاسم,السعر\n$body');
      await c.startMatching();
      expect(h.api.rpcCount('match_medicine_names'), 2);
      expect(c.rows.length, 130);
      expect(c.rows.first.line.name, 'دواء0');
      expect(c.rows.last.line.name, 'دواء129');
    });

    test('a failed match goes back to the columns step with the failure, and can be repeated', () async {
      h.api.rpcs['match_medicine_names'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      final ProductImportController c = await onColumns();
      await c.startMatching();
      expect(c.step.value, ImportStep.columns);
      expect(c.failure.value?.code, 'network');
      expect(c.rows, isEmpty);

      serveMatches(<String, List<Sug>>{'بنادول': <Sug>[const Sug('m1', 0.95)]});
      await c.startMatching();
      expect(c.step.value, ImportStep.review);
    });

    test('"stop waiting" returns to the columns step and the late answer is ignored', () async {
      serveMatches(<String, List<Sug>>{'بنادول': <Sug>[const Sug('m1', 0.95)]});
      h.api.delay = const Duration(milliseconds: 30);
      final ProductImportController c = await onColumns();
      final Future<void> running = c.startMatching();
      expect(c.step.value, ImportStep.matching);
      c.cancelMatching();
      expect(c.step.value, ImportStep.columns);
      await running;
      expect(c.step.value, ImportStep.columns);
      expect(c.rows, isEmpty);
    });

    test('going back to the file while matching also drops the late answer', () async {
      serveMatches(<String, List<Sug>>{});
      h.api.delay = const Duration(milliseconds: 30);
      final ProductImportController c = await onColumns();
      final Future<void> running = c.startMatching();
      c.backToFile();
      await running;
      expect(c.step.value, ImportStep.pick);
      expect(c.rows, isEmpty);
    });
  });

  group('the review step', () {
    Future<ProductImportController> reviewing() async {
      serveMatches(<String, List<Sug>>{
        'بنادول': <Sug>[const Sug('m1', 0.95)],
        'أموكسيل': <Sug>[const Sug('m2', 0.7), const Sug('m3', 0.65)],
        'بروفين': <Sug>[const Sug('m4', 0.5)],
      });
      final ProductImportController c = await onColumns();
      await c.startMatching();
      return c;
    }

    test('choosing a suggestion ticks the row; choosing nothing unticks it', () async {
      final ProductImportController c = await reviewing();
      final ImportRow r = c.rows[1];
      c.choose(r, r.matches[1]);
      expect(r.chosen.value?.medicine.id, 'm3');
      expect(r.included.value, isTrue);
      expect(c.undecidedCount, 1);

      c.choose(r, null);
      expect(r.chosen.value, isNull);
      expect(r.included.value, isFalse);
    });

    test('a chosen row can be unticked and ticked again; a row without a choice cannot be ticked', () async {
      final ProductImportController c = await reviewing();
      final ImportRow auto = c.rows[0];
      c.toggle(auto, false);
      expect(auto.willSave, isFalse);
      c.toggle(auto, true);
      expect(auto.willSave, isTrue);

      final ImportRow open = c.rows[1];
      c.toggle(open, true);
      expect(open.included.value, isFalse);
    });

    test('"tick all" / "untick all" only touch rows that have a medicine chosen', () async {
      final ProductImportController c = await reviewing();
      c.choose(c.rows[1], c.rows[1].matches.first);
      c.setAll(false);
      expect(c.readyCount, 0);
      expect(c.rows[2].included.value, isFalse);
      c.setAll(true);
      expect(c.readyCount, 2, reason: 'the row without a choice stays out');
    });
  });

  group('saving', () {
    Future<ProductImportController> reviewing(Map<String, List<Sug>> matches, {String? text}) async {
      serveMatches(matches);
      final ProductImportController c = await onColumns(text: text ?? basicCsv);
      await c.startMatching();
      return c;
    }

    test('sends the ticked rows with their file prices and shows the result', () async {
      serveBulk();
      final ProductImportController c = await reviewing(<String, List<Sug>>{
        'بنادول': <Sug>[const Sug('m1', 0.95)],
        'أموكسيل': <Sug>[const Sug('m2', 0.97)],
        'بروفين': <Sug>[const Sug('m3', 0.97)],
      });
      c.toggle(c.rows[2], false); // leave Brufen out

      await c.save();

      expect(c.step.value, ImportStep.done);
      expect(c.result.value?.saved, 2);
      expect(h.api.rpcLog.last.fn, 'bulk_upsert_pharmacy_products');
      expect(h.api.rpcLog.last.params['p_pharmacy_id'], 'ph-1');
      expect(h.api.rpcLog.last.params['p_items'], <Map<String, dynamic>>[
        <String, dynamic>{'medicine_id': 'm1', 'price': 5000.0},
        <String, dynamic>{'medicine_id': 'm2', 'price': 3000.0},
      ]);
      expect(c.duplicates.value, 0);
    });

    test('two rows for the same medicine are saved once, the later price wins, and the repeat is counted', () async {
      serveBulk();
      final ProductImportController c = await reviewing(
        <String, List<Sug>>{
          'بنادول': <Sug>[const Sug('m1', 0.95)],
          'بنادول 500': <Sug>[const Sug('m1', 0.96)],
        },
        text: 'الاسم,السعر\nبنادول,5000\nبنادول 500,5500',
      );

      await c.save();

      expect(h.api.rpcLog.last.params['p_items'], <Map<String, dynamic>>[
        <String, dynamic>{'medicine_id': 'm1', 'price': 5500.0},
      ]);
      expect(c.duplicates.value, 1);
      expect(c.result.value?.saved, 1);
    });

    test('with nothing ticked nothing is sent and the step does not change', () async {
      serveBulk();
      final ProductImportController c = await reviewing(<String, List<Sug>>{});
      await c.save();
      expect(h.api.rpcCount('bulk_upsert_pharmacy_products'), 0);
      expect(c.step.value, ImportStep.review);
    });

    test('a failed save returns to the review with everything kept, and saving again works', () async {
      h.api.rpcs['bulk_upsert_pharmacy_products'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      final ProductImportController c = await reviewing(<String, List<Sug>>{
        'بنادول': <Sug>[const Sug('m1', 0.95)],
      });

      await c.save();

      expect(c.step.value, ImportStep.review);
      expect(c.failure.value?.code, 'network');
      expect(c.readyCount, 1);
      expect(c.result.value, isNull);

      serveBulk();
      await c.save();
      expect(c.step.value, ImportStep.done);
      expect(c.result.value?.inserted, 1);
    });

    test('a server refusal (for example forbidden) is kept as the failure', () async {
      h.api.rpcs['bulk_upsert_pharmacy_products'] = (Map<String, dynamic> p) => throw const AppFailure('forbidden');
      final ProductImportController c = await reviewing(<String, List<Sug>>{
        'بنادول': <Sug>[const Sug('m1', 0.95)],
      });
      await c.save();
      expect(c.failure.value?.code, 'forbidden');
      expect(c.step.value, ImportStep.review);
    });

    test('importing another file starts over', () async {
      serveBulk();
      final ProductImportController c = await reviewing(<String, List<Sug>>{
        'بنادول': <Sug>[const Sug('m1', 0.95)],
      });
      await c.save();
      c.importAnother();
      expect(c.step.value, ImportStep.pick);
      expect(c.result.value, isNull);
      expect(c.rows, isEmpty);
      expect(c.lines, isEmpty);
    });
  });
}
