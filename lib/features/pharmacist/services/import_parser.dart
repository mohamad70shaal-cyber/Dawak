import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../core/utils/search_normalizer.dart';

/// A file that cannot be imported. [code] is one of `unsupported_file`, `unreadable_file`, `empty_file`,
/// `too_many_rows` (the screen turns it into a translated message).
class ImportFormatException implements Exception {
  const ImportFormatException(this.code);

  final String code;

  @override
  String toString() => 'ImportFormatException($code)';
}

/// The raw cells of a sheet, everything as trimmed text.
class SheetTable {
  const SheetTable(this.rows);

  final List<List<String>> rows;

  int get columnCount {
    int n = 0;
    for (final List<String> r in rows) {
      if (r.length > n) n = r.length;
    }
    return n;
  }

  String cell(int row, int col) => (row < rows.length && col < rows[row].length) ? rows[row][col] : '';
}

/// Which columns hold the medicine name and the selling price, and where the data starts.
class ImportColumns {
  const ImportColumns({required this.nameColumn, required this.priceColumn, required this.firstDataRow});

  final int nameColumn;
  final int priceColumn;

  /// 0-based index of the first data row (1 when the sheet has a header row).
  final int firstDataRow;

  bool get hasHeader => firstDataRow > 0;

  ImportColumns copyWith({int? nameColumn, int? priceColumn, int? firstDataRow}) => ImportColumns(
        nameColumn: nameColumn ?? this.nameColumn,
        priceColumn: priceColumn ?? this.priceColumn,
        firstDataRow: firstDataRow ?? this.firstDataRow,
      );
}

/// One data row of the sheet.
class ImportLine {
  const ImportLine({required this.line, required this.name, required this.rawPrice, required this.price});

  /// 1-based row number in the file (what the pharmacist sees in Excel).
  final int line;
  final String name;
  final String rawPrice;

  /// Null when the price cell is empty or not a usable amount.
  final double? price;

  bool get hasPrice => price != null;
}

/// Reads the price list a pharmacy exports from its program: CSV/TSV/TXT (UTF-8 or Windows-1256, the encoding Excel uses for
/// Arabic CSV files) and .xlsx. Everything here is pure (bytes in, tables out) so it can be tested without a device.
class ImportParser {
  const ImportParser._();

  static const int maxRows = 20000;

  /// Dispatches on the file extension. The first non-empty sheet of a workbook is used.
  static SheetTable read(String fileName, Uint8List bytes) {
    final String lower = fileName.toLowerCase();
    if (lower.endsWith('.xlsx') || lower.endsWith('.xlsm')) return _readWorkbook(bytes);
    if (lower.endsWith('.csv') || lower.endsWith('.tsv') || lower.endsWith('.txt')) {
      return _limit(parseCsv(decodeText(bytes)));
    }
    throw const ImportFormatException('unsupported_file');
  }

  static SheetTable _limit(SheetTable t) {
    if (t.rows.isEmpty) throw const ImportFormatException('empty_file');
    if (t.rows.length > maxRows) throw const ImportFormatException('too_many_rows');
    return t;
  }

  static SheetTable _readWorkbook(Uint8List bytes) {
    final Excel book;
    try {
      book = Excel.decodeBytes(bytes);
    } catch (_) {
      throw const ImportFormatException('unreadable_file');
    }
    for (final String name in book.tables.keys) {
      final Sheet? sheet = book.tables[name];
      if (sheet == null) continue;
      final List<List<String>> rows = <List<String>>[];
      for (final List<Data?> r in sheet.rows) {
        final List<String> cells = r.map((Data? c) => _cellText(c?.value)).toList();
        if (cells.any((String c) => c.isNotEmpty)) rows.add(cells);
        if (rows.length > maxRows) throw const ImportFormatException('too_many_rows');
      }
      if (rows.isNotEmpty) return SheetTable(rows);
    }
    throw const ImportFormatException('empty_file');
  }

  static String _cellText(Object? v) => v == null ? '' : v.toString().trim();

  // ---- text files ------------------------------------------------------------------------------------------

  /// UTF-8 (with or without BOM); when the bytes are not valid UTF-8 they are read as Windows-1256.
  static String decodeText(Uint8List bytes) {
    int start = 0;
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) start = 3;
    final Uint8List body = start == 0 ? bytes : Uint8List.sublistView(bytes, start);
    try {
      return utf8.decode(body);
    } on FormatException {
      return String.fromCharCodes(body.map((int b) => b < 0x80 ? b : _cp1256[b - 0x80]));
    }
  }

  /// RFC-4180 style: quoted fields may contain the delimiter, quotes (`""`) and line breaks. The delimiter
  /// (`,` `;` tab or `|`) is detected on the first non-empty line.
  static SheetTable parseCsv(String text) {
    final String src = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final String delimiter = _detectDelimiter(src);
    final List<List<String>> rows = <List<String>>[];
    List<String> row = <String>[];
    final StringBuffer field = StringBuffer();
    bool quoted = false;
    bool fieldWasQuoted = false;

    void endField() {
      final String value = field.toString();
      row.add(value.trim());
      field.clear();
      fieldWasQuoted = false;
    }

    void endRow() {
      endField();
      if (row.any((String c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
    }

    for (int i = 0; i < src.length; i++) {
      final String ch = src[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < src.length && src[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"' && field.isEmpty) {
        quoted = true;
        fieldWasQuoted = true;
      } else if (ch == delimiter) {
        endField();
      } else if (ch == '\n') {
        endRow();
      } else {
        field.write(ch);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty || fieldWasQuoted) endRow();
    return SheetTable(rows);
  }

  static String _detectDelimiter(String src) {
    final int nl = src.indexOf('\n');
    final String first = nl < 0 ? src : src.substring(0, nl);
    String best = ',';
    int bestCount = -1;
    for (final String d in const <String>[',', ';', '\t', '|']) {
      bool inQuotes = false;
      int count = 0;
      for (int i = 0; i < first.length; i++) {
        final String c = first[i];
        if (c == '"') {
          inQuotes = !inQuotes;
        } else if (!inQuotes && c == d) {
          count++;
        }
      }
      if (count > bestCount) {
        best = d;
        bestCount = count;
      }
    }
    return best;
  }

  // ---- columns -----------------------------------------------------------------------------------------------

  static const List<String> _nameWords = <String>[
    'اسم', 'الاسم', 'الدواء', 'دواء', 'المادة', 'مادة', 'الصنف', 'صنف', 'البيان', 'الوصف', 'التجاري',
    'name', 'item', 'product', 'medicine', 'drug', 'description', 'brand', 'article',
  ];

  static const List<String> _priceWords = <String>[
    'سعر', 'السعر', 'المبيع', 'البيع', 'مبيع', 'الجمهور', 'price', 'sell', 'sale', 'retail', 'public', 'mrp',
  ];

  static const List<String> _costWords = <String>['شراء', 'الشراء', 'تكلفة', 'التكلفة', 'جملة', 'cost', 'purchase', 'wholesale', 'buy'];

  static bool _hasAny(String normalized, List<String> words) => words.any(normalized.contains);

  /// Finds the header row (within the first ten rows) by Arabic/English keywords; otherwise looks at the cells themselves:
  /// the column with the most amounts is the price, the column with the most letters is the name.
  /// A row that names both columns wins over one that names only one, so a title row such as "قائمة الأسعار" above the
  /// real header is not mistaken for it.
  static ImportColumns guessColumns(SheetTable table) {
    final int cols = table.columnCount;
    final int scan = table.rows.length < 10 ? table.rows.length : 10;
    ({int row, int? name, int? price})? partial;
    for (int r = 0; r < scan; r++) {
      int? nameCol;
      int? priceCol;
      for (int c = 0; c < table.rows[r].length; c++) {
        final String t = normalizeSearch(table.rows[r][c]);
        if (t.isEmpty) continue;
        if (priceCol == null && _hasAny(t, _priceWords) && !_hasAny(t, _costWords)) {
          priceCol = c;
        } else if (nameCol == null && _hasAny(t, _nameWords)) {
          nameCol = c;
        }
      }
      if (nameCol != null && priceCol != null) return ImportColumns(nameColumn: nameCol, priceColumn: priceCol, firstDataRow: r + 1);
      if (partial == null && (nameCol != null || priceCol != null)) partial = (row: r, name: nameCol, price: priceCol);
    }
    final ({int row, int? name, int? price})? p = partial;
    if (p != null) {
      final ImportColumns content = _guessByContent(table, p.row + 1, cols);
      return ImportColumns(
        nameColumn: p.name ?? (content.nameColumn != p.price ? content.nameColumn : 0),
        priceColumn: p.price ?? (content.priceColumn != p.name ? content.priceColumn : (cols > 1 ? 1 : 0)),
        firstDataRow: p.row + 1,
      );
    }
    return _guessByContent(table, 0, cols);
  }

  static ImportColumns _guessByContent(SheetTable table, int from, int cols) {
    final int to = (from + 50) < table.rows.length ? from + 50 : table.rows.length;
    int bestPrice = cols > 1 ? 1 : 0;
    double bestPriceShare = -1;
    int bestName = 0;
    double bestNameShare = -1;
    for (int c = 0; c < cols; c++) {
      int numbers = 0;
      int texts = 0;
      int seen = 0;
      for (int r = from; r < to; r++) {
        final String v = table.cell(r, c);
        if (v.isEmpty) continue;
        seen++;
        if (parsePrice(v) != null) {
          numbers++;
        } else if (RegExp(r'[A-Za-z؀-ۿ]').hasMatch(v)) {
          texts++;
        }
      }
      if (seen == 0) continue;
      final double numberShare = numbers / seen;
      final double textShare = texts / seen;
      if (numberShare >= bestPriceShare) {
        bestPriceShare = numberShare;
        bestPrice = c;
      }
      if (textShare > bestNameShare) {
        bestNameShare = textShare;
        bestName = c;
      }
    }
    if (bestName == bestPrice) bestPrice = bestName == 0 ? (cols > 1 ? 1 : 0) : 0;
    return ImportColumns(nameColumn: bestName, priceColumn: bestPrice, firstDataRow: from);
  }

  /// The data rows with a non-empty name. Rows whose price cannot be read are kept with `price == null` so the screen
  /// can list them as "skipped".
  static List<ImportLine> lines(SheetTable table, ImportColumns cols) {
    final List<ImportLine> out = <ImportLine>[];
    for (int r = cols.firstDataRow; r < table.rows.length; r++) {
      final String name = table.cell(r, cols.nameColumn).trim();
      if (name.isEmpty) continue;
      final String raw = table.cell(r, cols.priceColumn);
      out.add(ImportLine(line: r + 1, name: name, rawPrice: raw, price: parsePrice(raw)));
    }
    return out;
  }

  // ---- prices ------------------------------------------------------------------------------------------------

  /// A selling price with at most two decimals, or null. Accepts Arabic digits, currency words (`ل.س`, `SYP`, `$`), and
  /// both separator conventions (`1,500` `1.500` `1 500,50` `1500.5`).
  static double? parsePrice(String? raw) {
    if (raw == null) return null;
    final StringBuffer b = StringBuffer();
    for (final int r in raw.runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        b.writeCharCode(0x30 + (r - 0x0660));
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        b.writeCharCode(0x30 + (r - 0x06F0));
      } else if (r == 0x066B) {
        b.write('.');
      } else if (r == 0x066C || r == 0x060C) {
        b.write(',');
      } else if ((r >= 0x30 && r <= 0x39) || r == 0x2C || r == 0x2E) {
        b.writeCharCode(r);
      }
      // Everything else (spaces, currency text and symbols) is ignored.
    }
    String s = b.toString();
    if (s.isEmpty || !RegExp(r'[0-9]').hasMatch(s)) return null;
    // A cell like "ل.س 1500" leaves a leading '.'; "1500 SYP." leaves a trailing one.
    s = s.replaceAll(RegExp(r'^[.,]+|[.,]+$'), '');
    if (s.isEmpty) return null;

    final int lastDot = s.lastIndexOf('.');
    final int lastComma = s.lastIndexOf(',');
    String normalized;
    if (lastDot >= 0 && lastComma >= 0) {
      final String decimalSep = lastDot > lastComma ? '.' : ',';
      final String groupSep = decimalSep == '.' ? ',' : '.';
      normalized = s.replaceAll(groupSep, '').replaceAll(decimalSep, '.');
    } else if (lastComma >= 0) {
      normalized = _singleSeparator(s, ',');
    } else if (lastDot >= 0) {
      normalized = _singleSeparator(s, '.');
    } else {
      normalized = s;
    }
    final double? v = double.tryParse(normalized);
    if (v == null || v.isNaN || v.isInfinite || v <= 0 || v > 999999999999) return null;
    final double rounded = (v * 100).round() / 100;
    return rounded <= 0 ? null : rounded;
  }

  /// Only one kind of separator: several of them, or exactly three digits after a single one, mean thousands
  /// (`1,500`, `1.500.000`); otherwise it is the decimal point (`1,5`, `1500.25`).
  static String _singleSeparator(String s, String sep) {
    final List<String> parts = s.split(sep);
    if (parts.length > 2) return parts.join();
    final String tail = parts.last;
    if (tail.length == 3 && parts.first.isNotEmpty) return parts.join();
    return '${parts.first}.$tail';
  }
}

/// Windows-1256 bytes 0x80..0xFF → Unicode (Excel's default encoding for Arabic CSV files).
const List<int> _cp1256 = <int>[
  0x20AC, 0x067E, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
  0x02C6, 0x2030, 0x0679, 0x2039, 0x0152, 0x0686, 0x0698, 0x0688,
  0x06AF, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x06A9, 0x2122, 0x0691, 0x203A, 0x0153, 0x200C, 0x200D, 0x06BA,
  0x00A0, 0x060C, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7,
  0x00A8, 0x00A9, 0x06BE, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF,
  0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7,
  0x00B8, 0x00B9, 0x061B, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x061F,
  0x06C1, 0x0621, 0x0622, 0x0623, 0x0624, 0x0625, 0x0626, 0x0627,
  0x0628, 0x0629, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x062F,
  0x0630, 0x0631, 0x0632, 0x0633, 0x0634, 0x0635, 0x0636, 0x00D7,
  0x0637, 0x0638, 0x0639, 0x063A, 0x0640, 0x0641, 0x0642, 0x0643,
  0x00E0, 0x0644, 0x00E2, 0x0645, 0x0646, 0x0647, 0x0648, 0x00E7,
  0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x0649, 0x064A, 0x00EE, 0x00EF,
  0x064B, 0x064C, 0x064D, 0x064E, 0x00F4, 0x064F, 0x0650, 0x00F7,
  0x0651, 0x00F9, 0x0652, 0x00FB, 0x00FC, 0x200E, 0x200F, 0x06D2,
];
