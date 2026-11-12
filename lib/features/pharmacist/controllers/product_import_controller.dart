import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/services/session_service.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/listing_repository.dart';
import '../services/import_file_picker.dart';
import '../services/import_parser.dart';

enum ImportStep { pick, columns, matching, review, saving, done }

/// How sure the server's name matching was for one row of the file.
enum ImportRowKind { auto, review, unmatched }

/// One row of the file with the catalogue suggestions the server found for its name.
class ImportRow {
  ImportRow({required this.line, required this.matches, required this.kind, NameMatch? chosen})
      : chosen = Rxn<NameMatch>(chosen),
        included = (chosen != null).obs;

  final ImportLine line;

  /// Up to three suggestions, best first.
  final List<NameMatch> matches;
  final ImportRowKind kind;

  /// The catalogue medicine this row will be saved as (null until the pharmacist picks one for a `review` row).
  final Rxn<NameMatch> chosen;

  /// Unticked rows are left out of the import.
  final RxBool included;

  bool get willSave => included.value && chosen.value != null;
}

/// Import a price list (Excel / CSV) into the pharmacy's list (P-29): read the file, pick the name and price columns,
/// let the server suggest catalogue medicines for every name, review the doubtful ones, then save. Importing is
/// idempotent (same medicine twice = price updated), so a failed save can simply be tried again.
class ProductImportController extends BaseController {
  ProductImportController({ListingRepository? listing, SessionService? session, ImportFilePicker? picker})
      : _listing = listing ?? Get.find<ListingRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _picker = picker ?? ImportFiles.pick;

  /// A name matches automatically when its best suggestion is at least this similar and clearly ahead of the next one.
  static const double autoScore = 0.85;
  static const double autoLead = 0.1;

  final ListingRepository _listing;
  final SessionService _session;
  final ImportFilePicker _picker;

  final Rx<ImportStep> step = ImportStep.pick.obs;

  /// Translation key of the last file problem (`p_import_err_*`), shown on the first two steps.
  final RxnString importError = RxnString();

  final RxString fileName = ''.obs;
  final Rxn<SheetTable> table = Rxn<SheetTable>();
  final Rx<ImportColumns> columns = const ImportColumns(nameColumn: 0, priceColumn: 1, firstDataRow: 1).obs;

  /// Every data row with a name (rows without a usable price are kept so the screen can say they are skipped).
  final RxList<ImportLine> lines = <ImportLine>[].obs;

  final RxList<ImportRow> rows = <ImportRow>[].obs;

  /// 0..1 while matching / saving.
  final RxDouble progress = 0.0.obs;

  final Rxn<ImportResult> result = Rxn<ImportResult>();

  /// Rows that were ticked but repeat a medicine already imported from an earlier row (the later row wins).
  final RxInt duplicates = 0.obs;

  int _generation = 0;

  String get pharmacyId => _session.pharmacy?.id ?? '';

  String get currency => _session.pharmacy?.currency ?? 'SYP';

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  // ---- step 1: the file ----------------------------------------------------------------------------------

  Future<void> pickFile() async {
    if (submitting.value) return;
    importError.value = null;
    final PickedImportFile? f;
    try {
      f = await _picker();
    } catch (_) {
      importError.value = 'p_import_err_unreadable_file';
      return;
    }
    if (f == null) return;
    if (f.bytes.length > ImportFiles.maxBytes) {
      importError.value = 'p_import_err_too_large';
      return;
    }
    final SheetTable t;
    try {
      t = ImportParser.read(f.name, f.bytes);
    } on ImportFormatException catch (e) {
      importError.value = 'p_import_err_${e.code}';
      return;
    }
    fileName.value = f.name;
    table.value = t;
    columns.value = ImportParser.guessColumns(t);
    _rebuildLines();
    step.value = ImportStep.columns;
  }

  // ---- step 2: columns -----------------------------------------------------------------------------------

  void setNameColumn(int i) {
    columns.value = columns.value.copyWith(nameColumn: i);
    _rebuildLines();
  }

  void setPriceColumn(int i) {
    columns.value = columns.value.copyWith(priceColumn: i);
    _rebuildLines();
  }

  void setHasHeader(bool hasHeader) {
    columns.value = columns.value.copyWith(firstDataRow: hasHeader ? 1 : 0);
    _rebuildLines();
  }

  void _rebuildLines() {
    final SheetTable? t = table.value;
    lines.assignAll(t == null ? <ImportLine>[] : ImportParser.lines(t, columns.value));
  }

  bool get sameColumn => columns.value.nameColumn == columns.value.priceColumn;

  /// Rows that can be matched: a name and a price above zero.
  List<ImportLine> get usableLines => lines.where((ImportLine l) => (l.price ?? 0) > 0).toList();

  int get skippedNoPrice => lines.length - usableLines.length;

  bool get canMatch => !sameColumn && usableLines.isNotEmpty;

  void backToFile() {
    _generation++;
    table.value = null;
    lines.clear();
    rows.clear();
    importError.value = null;
    step.value = ImportStep.pick;
  }

  // ---- step 3: matching ----------------------------------------------------------------------------------

  Future<void> startMatching() async {
    if (submitting.value) return;
    if (sameColumn) {
      importError.value = 'p_import_err_same_column';
      return;
    }
    final List<ImportLine> usable = usableLines;
    if (usable.isEmpty) {
      importError.value = 'p_import_err_no_rows';
      return;
    }
    importError.value = null;
    final int gen = ++_generation;
    progress.value = 0;
    step.value = ImportStep.matching;
    final List<List<NameMatch>>? found = await submit<List<List<NameMatch>>>(() => _listing.matchNames(
          usable.map((ImportLine l) => l.name).toList(),
          onProgress: (int done, int total) {
            if (gen == _generation) progress.value = total == 0 ? 0 : done / total;
          },
        ));
    if (gen != _generation) return; // the pharmacist went back while the server was working
    if (found == null) {
      step.value = ImportStep.columns;
      return;
    }
    rows.assignAll(<ImportRow>[for (int i = 0; i < usable.length; i++) _classify(usable[i], found[i])]);
    step.value = ImportStep.review;
  }

  /// "Stop waiting": goes back to the columns step; whatever the server answers afterwards is ignored.
  void cancelMatching() {
    _generation++;
    step.value = ImportStep.columns;
  }

  static ImportRow _classify(ImportLine line, List<NameMatch> matches) {
    if (matches.isEmpty) return ImportRow(line: line, matches: matches, kind: ImportRowKind.unmatched);
    final NameMatch top = matches.first;
    final bool clear = matches.length == 1 || top.score - matches[1].score >= autoLead;
    if (top.score >= autoScore && clear) return ImportRow(line: line, matches: matches, kind: ImportRowKind.auto, chosen: top);
    return ImportRow(line: line, matches: matches, kind: ImportRowKind.review);
  }

  // ---- step 4: review ------------------------------------------------------------------------------------

  int count(ImportRowKind k) => rows.where((ImportRow r) => r.kind == k).length;

  /// Rows that will be saved if the pharmacist confirms now.
  int get readyCount => rows.where((ImportRow r) => r.willSave).length;

  /// Rows that still wait for a choice (a `review` row that is neither chosen nor skipped on purpose).
  int get undecidedCount => rows.where((ImportRow r) => r.kind == ImportRowKind.review && r.chosen.value == null).length;

  /// Picking a suggestion also ticks the row.
  void choose(ImportRow row, NameMatch? match) {
    row.chosen.value = match;
    row.included.value = match != null;
  }

  void toggle(ImportRow row, bool value) {
    if (row.chosen.value == null) return;
    row.included.value = value;
  }

  /// Ticks or unticks every row that has a medicine chosen.
  void setAll(bool value) {
    for (final ImportRow r in rows) {
      if (r.chosen.value != null) r.included.value = value;
    }
  }

  // ---- step 5: save --------------------------------------------------------------------------------------

  Future<void> save() async {
    if (submitting.value) return;
    final Map<String, ListingEntry> byMedicine = <String, ListingEntry>{};
    int ticked = 0;
    for (final ImportRow r in rows) {
      if (!r.willSave) continue;
      ticked++;
      final NameMatch m = r.chosen.value!;
      byMedicine[m.medicine.id] = ListingEntry(medicineId: m.medicine.id, price: r.line.price!);
    }
    if (byMedicine.isEmpty) return;
    duplicates.value = ticked - byMedicine.length;
    progress.value = 0;
    step.value = ImportStep.saving;
    final ImportResult? r = await submit<ImportResult>(() => _listing.bulkUpsert(
          pharmacyId,
          byMedicine.values.toList(),
          onProgress: (int done, int total) => progress.value = total == 0 ? 0 : done / total,
        ));
    if (r == null) {
      step.value = ImportStep.review; // nothing is lost: saving again repeats the same idempotent call
      return;
    }
    result.value = r;
    step.value = ImportStep.done;
  }

  /// Start over with another file.
  void importAnother() {
    result.value = null;
    backToFile();
  }
}
