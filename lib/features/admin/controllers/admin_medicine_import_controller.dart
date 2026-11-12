import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/medicine_repository.dart';
import '../../pharmacist/services/import_file_picker.dart';
import '../../pharmacist/services/import_parser.dart';

/// Steps of the admin medicine import wizard.
enum AdminImportStep { pick, columns, preview, saving, done }

/// One data row ready for the admin to include or skip.
class AdminImportRow {
  AdminImportRow({required this.line, required bool include}) : include = include.obs;

  final ImportLine line;

  /// Whether the admin wants to import this row.
  final RxBool include;
}

/// Admin-side result after bulk creation of medicines.
class AdminImportResult {
  const AdminImportResult({required this.created, required this.skipped});

  final int created;
  final int skipped;
}

/// Import medicines from Excel / CSV into the global catalogue (A-16).
/// Reads the file locally, lets the admin map columns, previews rows, and
/// bulk-creates approved catalogue entries via [MedicineRepository.adminCreate].
class AdminMedicineImportController extends BaseController {
  AdminMedicineImportController({
    MedicineRepository? medicines,
    ImportFilePicker? picker,
  })  : _medicines = medicines ?? Get.find<MedicineRepository>(),
        _picker = picker ?? ImportFiles.pick;

  final MedicineRepository _medicines;
  final ImportFilePicker _picker;

  final Rx<AdminImportStep> step = AdminImportStep.pick.obs;

  /// Translation key of the last file/parse problem (`a_import_err_*`), shown on the first two steps.
  final RxnString importError = RxnString();

  final RxString fileName = ''.obs;
  final Rxn<SheetTable> table = Rxn<SheetTable>();

  /// Current column mapping. nameColumn is the only required column; the rest are optional.
  final Rx<ImportColumns> columns =
      const ImportColumns(nameColumn: 0, priceColumn: 1, firstDataRow: 1).obs;

  /// Optional extra columns (0-based, or -1 meaning "not mapped").
  final RxInt nameEnColumn = (-1).obs;
  final RxInt strengthColumn = (-1).obs;
  final RxInt dosageFormColumn = (-1).obs;

  /// Every row that has a non-empty name in the name column.
  final RxList<AdminImportRow> rows = <AdminImportRow>[].obs;

  /// 0..1 progress while saving.
  final RxDouble progress = 0.0.obs;

  final Rxn<AdminImportResult> result = Rxn<AdminImportResult>();

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  // ---- step 1: pick -----------------------------------------------------------------------

  Future<void> pickFile() async {
    if (submitting.value) return;
    importError.value = null;
    final PickedImportFile? f;
    try {
      f = await _picker();
    } catch (_) {
      importError.value = 'a_import_err_unreadable_file';
      return;
    }
    if (f == null) return;
    if (f.bytes.length > ImportFiles.maxBytes) {
      importError.value = 'a_import_err_too_large';
      return;
    }
    final SheetTable t;
    try {
      t = ImportParser.read(f.name, f.bytes);
    } on ImportFormatException catch (e) {
      importError.value = 'a_import_err_${e.code}';
      return;
    }
    fileName.value = f.name;
    table.value = t;
    // Try to auto-detect columns from header keywords.
    final ImportColumns guessed = ImportParser.guessColumns(t);
    columns.value = guessed;
    nameEnColumn.value = -1;
    strengthColumn.value = -1;
    dosageFormColumn.value = -1;
    _rebuildRows();
    step.value = AdminImportStep.columns;
  }

  // ---- step 2: columns --------------------------------------------------------------------

  void setNameColumn(int i) {
    columns.value = columns.value.copyWith(nameColumn: i);
    _rebuildRows();
  }

  void setHasHeader(bool hasHeader) {
    columns.value = columns.value.copyWith(firstDataRow: hasHeader ? 1 : 0);
    _rebuildRows();
  }

  void setNameEnColumn(int i) {
    nameEnColumn.value = i;
    _rebuildRows();
  }

  void setStrengthColumn(int i) {
    strengthColumn.value = i;
    _rebuildRows();
  }

  void setDosageFormColumn(int i) {
    dosageFormColumn.value = i;
    _rebuildRows();
  }

  void _rebuildRows() {
    final SheetTable? t = table.value;
    if (t == null) {
      rows.clear();
      return;
    }
    final int first = columns.value.firstDataRow;
    final int nameCol = columns.value.nameColumn;
    final List<AdminImportRow> built = <AdminImportRow>[];
    for (int r = first; r < t.rows.length; r++) {
      final String name = t.cell(r, nameCol).trim();
      if (name.isEmpty) continue;
      built.add(AdminImportRow(line: ImportLine(line: r + 1, name: name, rawPrice: '', price: null), include: true));
    }
    rows.assignAll(built);
  }

  void backToFile() {
    table.value = null;
    rows.clear();
    importError.value = null;
    step.value = AdminImportStep.pick;
  }

  bool get hasRows => rows.isNotEmpty;

  int get includedCount => rows.where((AdminImportRow r) => r.include.value).length;

  void toggleRow(AdminImportRow row, bool value) => row.include.value = value;

  void setAll(bool value) {
    for (final AdminImportRow r in rows) {
      r.include.value = value;
    }
  }

  // ---- step 3: preview -> save ------------------------------------------------------------

  Future<void> startPreview() async {
    if (rows.isEmpty) {
      importError.value = 'a_import_err_no_rows';
      return;
    }
    importError.value = null;
    step.value = AdminImportStep.preview;
  }

  Future<void> save() async {
    if (submitting.value) return;
    final List<AdminImportRow> included = rows.where((AdminImportRow r) => r.include.value).toList();
    if (included.isEmpty) return;
    progress.value = 0;
    step.value = AdminImportStep.saving;

    final int total = included.length;
    int created = 0;
    int skipped = 0;

    final AdminImportResult? r = await submit<AdminImportResult>(() async {
      for (int i = 0; i < total; i++) {
        final AdminImportRow row = included[i];
        final int nameCol = columns.value.nameColumn;
        final SheetTable t = table.value!;
        final int fileRow = row.line.line - 1; // convert back to 0-based

        String cell(int col) => col < 0 ? '' : t.cell(fileRow, col).trim();

        final String nameAr = cell(nameCol);
        final String nameEn = cell(nameEnColumn.value);
        final String strength = cell(strengthColumn.value);
        final String dosageForm = cell(dosageFormColumn.value);

        try {
          await _medicines.adminCreate(MedicineDraft(
            nameAr: nameAr,
            nameEn: nameEn.isEmpty ? null : nameEn,
            brandName: null,
            activeIngredient: null,
            strength: strength.isEmpty ? null : strength,
            dosageForm: dosageForm.isEmpty ? null : dosageForm,
            packageDescription: null,
            categoryId: null,
          ));
          created++;
        } catch (_) {
          skipped++;
        }
        progress.value = (i + 1) / total;
      }
      return AdminImportResult(created: created, skipped: skipped);
    });

    if (r == null) {
      step.value = AdminImportStep.preview;
      return;
    }
    result.value = r;
    if (r.created > 0) AppToast.success('a_import_done_title'.trParams(<String, String>{'n': '${r.created}'}));
    step.value = AdminImportStep.done;
  }

  void importAnother() {
    result.value = null;
    backToFile();
  }
}
