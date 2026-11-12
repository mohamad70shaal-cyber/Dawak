// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/features/admin/controllers/admin_medicine_import_controller.dart';
import 'package:dawak/features/pharmacist/services/import_file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import 'admin_fixtures.dart';

PickedImportFile csvFile(String text, {String name = 'medicines.csv'}) =>
    PickedImportFile(name: name, bytes: Uint8List.fromList(utf8.encode(text)));

void main() {
  late AppHarness h;

  setUp(() async {
    h = await AppHarness.create();
    await signInAdmin(h);
  });
  tearDown(() => h.dispose());

  AdminMedicineImportController make({PickedImportFile? file}) =>
      AdminMedicineImportController(picker: () async => file)..onInit();

  const String basicCsv = 'الاسم,التركيز\nبنادول,500mg\nأموكسيل,250mg\nبروفين,400mg';

  Future<AdminMedicineImportController> onColumns({String text = basicCsv}) async {
    final AdminMedicineImportController c = make(file: csvFile(text));
    await c.pickFile();
    expect(c.step.value, AdminImportStep.columns);
    return c;
  }

  Future<AdminMedicineImportController> onPreview({String text = basicCsv}) async {
    final AdminMedicineImportController c = await onColumns(text: text);
    await c.startPreview();
    expect(c.step.value, AdminImportStep.preview);
    return c;
  }

  group('the file step', () {
    test('a readable CSV opens the columns step with rows and no error', () async {
      final AdminMedicineImportController c = await onColumns();
      expect(c.fileName.value, 'medicines.csv');
      expect(c.importError.value, isNull);
      expect(c.rows.map((AdminImportRow r) => r.line.name), <String>['بنادول', 'أموكسيل', 'بروفين']);
    });

    test('closing the chooser without picking keeps the pick step', () async {
      final AdminMedicineImportController c = make();
      await c.pickFile();
      expect(c.step.value, AdminImportStep.pick);
      expect(c.importError.value, isNull);
    });

    test('a picker that throws gives the unreadable_file error', () async {
      final AdminMedicineImportController c =
          AdminMedicineImportController(picker: () async => throw StateError('plugin'))..onInit();
      await c.pickFile();
      expect(c.importError.value, 'a_import_err_unreadable_file');
    });

    test('a file over the limit is refused before parsing', () async {
      final AdminMedicineImportController c =
          make(file: PickedImportFile(name: 'big.csv', bytes: Uint8List(ImportFiles.maxBytes + 1)));
      await c.pickFile();
      expect(c.importError.value, 'a_import_err_too_large');
      expect(c.step.value, AdminImportStep.pick);
    });

    test('an unsupported file type is refused', () async {
      final AdminMedicineImportController c = make(file: csvFile('x', name: 'list.pdf'));
      await c.pickFile();
      expect(c.importError.value, 'a_import_err_unsupported_file');
    });

    test('an empty file is refused', () async {
      final AdminMedicineImportController c = make(file: csvFile('', name: 'empty.csv'));
      await c.pickFile();
      expect(c.importError.value, 'a_import_err_empty_file');
    });
  });

  group('the columns step', () {
    test('all rows are included by default', () async {
      final AdminMedicineImportController c = await onColumns();
      expect(c.rows.every((AdminImportRow r) => r.include.value), isTrue);
      expect(c.includedCount, 3);
    });

    test('setAll(false) unticks everything; setAll(true) reticks', () async {
      final AdminMedicineImportController c = await onColumns();
      c.setAll(false);
      expect(c.includedCount, 0);
      c.setAll(true);
      expect(c.includedCount, 3);
    });

    test('toggling a single row changes only that row', () async {
      final AdminMedicineImportController c = await onColumns();
      c.toggleRow(c.rows[1], false);
      expect(c.rows[0].include.value, isTrue);
      expect(c.rows[1].include.value, isFalse);
      expect(c.rows[2].include.value, isTrue);
      expect(c.includedCount, 2);
    });

    test('changing the name column rebuilds the row list', () async {
      final AdminMedicineImportController c =
          await onColumns(text: 'التركيز,الاسم\n500mg,بنادول\n250mg,أموكسيل');
      c.setNameColumn(0);
      expect(c.rows.map((AdminImportRow r) => r.line.name), <String>['500mg', '250mg']);
    });

    test('going back to file clears everything', () async {
      final AdminMedicineImportController c = await onColumns();
      c.backToFile();
      expect(c.step.value, AdminImportStep.pick);
      expect(c.table.value, isNull);
      expect(c.rows, isEmpty);
    });

    test('a file with no rows in the name column is refused at preview', () async {
      final AdminMedicineImportController c = await onColumns(text: 'الاسم,السعر\n ,\n ,');
      expect(c.rows, isEmpty);
      await c.startPreview();
      expect(c.importError.value, 'a_import_err_no_rows');
      expect(c.step.value, AdminImportStep.columns);
    });
  });

  group('the preview step', () {
    test('preview shows all rows; can deselect and confirm subset', () async {
      final AdminMedicineImportController c = await onPreview();
      c.toggleRow(c.rows[2], false);
      expect(c.includedCount, 2);
      await c.save();
      expect(c.step.value, AdminImportStep.done);
      expect(c.result.value?.created, 2);
      expect(c.result.value?.skipped, 0);
      expect(h.api.calls.where((String s) => s == 'insert:medicines').length, 2);
    });

    test('with nothing selected the save is a no-op and step stays at preview', () async {
      final AdminMedicineImportController c = await onPreview();
      c.setAll(false);
      await c.save();
      expect(c.step.value, AdminImportStep.preview);
      expect(h.api.calls.where((String s) => s == 'insert:medicines').length, 0);
    });
  });

  group('saving', () {
    test('all included rows are sent and the done step is shown', () async {
      final AdminMedicineImportController c = await onPreview();
      await c.save();
      expect(c.step.value, AdminImportStep.done);
      expect(c.result.value?.created, 3);
      expect(c.result.value?.skipped, 0);
      expect(h.api.calls.where((String s) => s == 'insert:medicines').length, 3);
    });

    test('rows that fail to insert are counted as skipped, not a hard failure', () async {
      h.api.failNext('insert:medicines', const AppFailure('duplicate_request'));
      final AdminMedicineImportController c = await onPreview();
      await c.save();
      expect(c.step.value, AdminImportStep.done);
      expect(c.result.value?.created, 2);
      expect(c.result.value?.skipped, 1);
    });

    test('importAnother resets to the pick step', () async {
      final AdminMedicineImportController c = await onPreview();
      await c.save();
      expect(c.step.value, AdminImportStep.done);
      c.importAnother();
      expect(c.step.value, AdminImportStep.pick);
      expect(c.result.value, isNull);
      expect(c.rows, isEmpty);
    });

    test('optional columns populate the medicine draft', () async {
      final AdminMedicineImportController c = await onColumns(
        text: 'الاسم العربي,English Name,التركيز,الشكل الدوائي\nبنادول,Panadol,500mg,أقراص',
      );
      c.setNameColumn(0);
      c.setNameEnColumn(1);
      c.setStrengthColumn(2);
      c.setDosageFormColumn(3);
      await c.startPreview();
      await c.save();

      expect(c.step.value, AdminImportStep.done);
      final List<Map<String, dynamic>> meds = h.api.tables['medicines'] ?? <Map<String, dynamic>>[];
      expect(meds, isNotEmpty);
      final Map<String, dynamic> row = meds.first;
      expect(row['name_ar'], 'بنادول');
      expect(row['name_en'], 'Panadol');
      expect(row['strength'], '500mg');
      expect(row['dosage_form'], 'أقراص');
    });
  });
}
