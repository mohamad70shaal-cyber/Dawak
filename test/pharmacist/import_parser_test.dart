// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dawak/features/pharmacist/services/import_parser.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

SheetTable csv(String s) => ImportParser.parseCsv(s);

void main() {
  group('parsePrice', () {
    test('plain numbers and the two decimal conventions', () {
      expect(ImportParser.parsePrice('5000'), 5000);
      expect(ImportParser.parsePrice('2500.5'), 2500.5);
      expect(ImportParser.parsePrice('2500,5'), 2500.5);
      expect(ImportParser.parsePrice('1,500'), 1500, reason: 'exactly three digits after one separator mean thousands');
      expect(ImportParser.parsePrice('1.500'), 1500);
      expect(ImportParser.parsePrice('1,500,000'), 1500000);
      expect(ImportParser.parsePrice('1.500.000'), 1500000);
      expect(ImportParser.parsePrice('1,500.75'), 1500.75);
      expect(ImportParser.parsePrice('1.500,75'), 1500.75);
      expect(ImportParser.parsePrice('1 500,50'), 1500.5);
    });

    test('Arabic digits and separators', () {
      expect(ImportParser.parsePrice('٥٠٠٠'), 5000);
      expect(ImportParser.parsePrice('٢٥٠٠٫٥'), 2500.5);
      expect(ImportParser.parsePrice('١٬٥٠٠'), 1500);
    });

    test('currency words and symbols are ignored', () {
      expect(ImportParser.parsePrice('ل.س 1500'), 1500);
      expect(ImportParser.parsePrice('1500 ل.س'), 1500);
      expect(ImportParser.parsePrice('1500 SYP.'), 1500);
      expect(ImportParser.parsePrice('\$12.5'), 12.5);
    });

    test('more than two decimals are rounded to two', () {
      expect(ImportParser.parsePrice('12.3456'), 12.35);
    });

    test('empty, zero, negative-looking and non-numeric cells are not prices', () {
      expect(ImportParser.parsePrice(null), isNull);
      expect(ImportParser.parsePrice(''), isNull);
      expect(ImportParser.parsePrice('   '), isNull);
      expect(ImportParser.parsePrice('abc'), isNull);
      expect(ImportParser.parsePrice('0'), isNull);
      expect(ImportParser.parsePrice('0.00'), isNull);
      expect(ImportParser.parsePrice('.'), isNull);
      expect(ImportParser.parsePrice('9999999999999'), isNull, reason: 'above the largest price the server accepts');
    });
  });

  group('text files', () {
    test('commas, semicolons, tabs and pipes are detected on the first line', () {
      expect(csv('a,b\n1,2').rows, <List<String>>[<String>['a', 'b'], <String>['1', '2']]);
      expect(csv('a;b\n1;2').rows, <List<String>>[<String>['a', 'b'], <String>['1', '2']]);
      expect(csv('a\tb\n1\t2').rows, <List<String>>[<String>['a', 'b'], <String>['1', '2']]);
      expect(csv('a|b\n1|2').rows, <List<String>>[<String>['a', 'b'], <String>['1', '2']]);
    });

    test('quoted fields may hold the delimiter, doubled quotes and line breaks', () {
      final SheetTable t = csv('name,price\n"Panadol, 500mg",5000\n"He said ""hi""",1\n"two\nlines",2');
      expect(t.rows[1], <String>['Panadol, 500mg', '5000']);
      expect(t.rows[2], <String>['He said "hi"', '1']);
      expect(t.rows[3], <String>['two\nlines', '2']);
    });

    test('Windows line endings, trailing newlines and blank lines are harmless', () {
      final SheetTable t = csv('a,b\r\n1,2\r\n\r\n3,4\r\n');
      expect(t.rows, <List<String>>[<String>['a', 'b'], <String>['1', '2'], <String>['3', '4']]);
    });

    test('cells are trimmed and short rows stay short', () {
      final SheetTable t = csv(' a , b \n x \n');
      expect(t.rows, <List<String>>[<String>['a', 'b'], <String>['x']]);
      expect(t.cell(1, 1), '', reason: 'a missing cell reads as empty');
      expect(t.columnCount, 2);
    });

    test('UTF-8 with a byte-order mark is read as UTF-8', () {
      final Uint8List bytes = Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode('بنادول,5000')]);
      expect(ImportParser.decodeText(bytes), 'بنادول,5000');
    });

    test('bytes that are not UTF-8 are read as Windows-1256 (what Excel writes for Arabic CSV files)', () {
      // "بنادول" in Windows-1256: ب=C8 ن=E4 ا=C7 د=CF و=E6 ل=E1
      final Uint8List bytes = Uint8List.fromList(<int>[0xC8, 0xE4, 0xC7, 0xCF, 0xE6, 0xE1, 0x2C, 0x35]);
      expect(ImportParser.decodeText(bytes), 'بنادول,5');
    });

    test('read() dispatches on the extension, whatever its letter case', () {
      expect(ImportParser.read('LIST.CSV', utf8Bytes('a,b\n1,2')).rows.length, 2);
      expect(ImportParser.read('list.txt', utf8Bytes('a,b\n1,2')).rows.length, 2);
      expect(ImportParser.read('list.tsv', utf8Bytes('a\tb\n1\t2')).rows.length, 2);
    });

    test('an unknown extension, an empty file and too many rows are refused with a code', () {
      void expectCode(void Function() f, String code) {
        try {
          f();
          fail('expected $code');
        } on ImportFormatException catch (e) {
          expect(e.code, code);
        }
      }

      expectCode(() => ImportParser.read('list.pdf', utf8Bytes('x')), 'unsupported_file');
      expectCode(() => ImportParser.read('list.csv', utf8Bytes('')), 'empty_file');
      expectCode(() => ImportParser.read('list.csv', utf8Bytes('  \n\n ')), 'empty_file');
      final String many = List<String>.generate(ImportParser.maxRows + 1, (int i) => 'n$i,1').join('\n');
      expectCode(() => ImportParser.read('list.csv', utf8Bytes(many)), 'too_many_rows');
    });
  });

  group('workbooks', () {
    test('an .xlsx file is read: first non-empty sheet, numbers as text', () {
      final Excel book = Excel.createExcel();
      final Sheet sheet = book[book.getDefaultSheet()!];
      sheet.appendRow(<CellValue?>[TextCellValue('الاسم'), TextCellValue('السعر')]);
      sheet.appendRow(<CellValue?>[TextCellValue('بنادول'), IntCellValue(5000)]);
      sheet.appendRow(<CellValue?>[TextCellValue('أموكسيل'), DoubleCellValue(2500.5)]);
      final List<int>? encoded = book.encode();
      expect(encoded, isNotNull);

      final SheetTable t = ImportParser.read('list.xlsx', Uint8List.fromList(encoded!));

      expect(t.rows.length, 3);
      expect(t.cell(1, 0), 'بنادول');
      expect(ImportParser.parsePrice(t.cell(1, 1)), 5000);
      expect(ImportParser.parsePrice(t.cell(2, 1)), 2500.5);
    });

    test('bytes that are not a workbook are "unreadable"', () {
      try {
        ImportParser.read('list.xlsx', utf8Bytes('this is not a zip file'));
        fail('expected unreadable_file');
      } on ImportFormatException catch (e) {
        expect(e.code, 'unreadable_file');
      }
    });
  });

  group('guessing the columns', () {
    test('an Arabic header row names the columns; data starts below it', () {
      final ImportColumns c = ImportParser.guessColumns(csv('الكود,اسم الدواء,السعر\n1,بنادول,5000\n2,أموكسيل,3000'));
      expect(c.nameColumn, 1);
      expect(c.priceColumn, 2);
      expect(c.firstDataRow, 1);
      expect(c.hasHeader, isTrue);
    });

    test('an English header row works too, and a purchase-price column is not taken for the selling price', () {
      final ImportColumns c = ImportParser.guessColumns(csv('Item,Cost,Sale Price\nPanadol,4000,5000\nAmoxil,2000,3000'));
      expect(c.nameColumn, 0);
      expect(c.priceColumn, 2);
      expect(c.firstDataRow, 1);
    });

    test('a header that is not on the first row is found (within the first ten rows)', () {
      final ImportColumns c = ImportParser.guessColumns(csv('صيدلية الأمل\nقائمة الأسعار\nالاسم,السعر\nبنادول,5000'));
      expect(c.nameColumn, 0);
      expect(c.priceColumn, 1);
      expect(c.firstDataRow, 3);
    });

    test('without a header the column with the amounts is the price and the one with letters the name', () {
      final ImportColumns c = ImportParser.guessColumns(csv('5000,بنادول\n3000,أموكسيل\n1200,بروفين'));
      expect(c.nameColumn, 1);
      expect(c.priceColumn, 0);
      expect(c.firstDataRow, 0);
      expect(c.hasHeader, isFalse);
    });
  });

  group('the data rows', () {
    test('rows without a name are dropped; rows without a usable price are kept with a null price', () {
      final SheetTable t = csv('name,price\nPanadol,5000\n,7000\nAmoxil,\nBrufen,abc\nZinc,1.500');
      final List<ImportLine> lines = ImportParser.lines(t, const ImportColumns(nameColumn: 0, priceColumn: 1, firstDataRow: 1));
      expect(lines.map((ImportLine l) => l.name), <String>['Panadol', 'Amoxil', 'Brufen', 'Zinc']);
      expect(lines.map((ImportLine l) => l.price), <double?>[5000, null, null, 1500]);
      expect(lines.map((ImportLine l) => l.hasPrice), <bool>[true, false, false, true]);
    });

    test('the line number is the 1-based row of the file, header included', () {
      final SheetTable t = csv('name,price\nPanadol,5000\nAmoxil,3000');
      final List<ImportLine> lines = ImportParser.lines(t, const ImportColumns(nameColumn: 0, priceColumn: 1, firstDataRow: 1));
      expect(lines.map((ImportLine l) => l.line), <int>[2, 3]);
    });

    test('a file without a header starts at the first row', () {
      final SheetTable t = csv('Panadol,5000\nAmoxil,3000');
      final List<ImportLine> lines = ImportParser.lines(t, const ImportColumns(nameColumn: 0, priceColumn: 1, firstDataRow: 0));
      expect(lines.length, 2);
      expect(lines.first.line, 1);
    });
  });
}
