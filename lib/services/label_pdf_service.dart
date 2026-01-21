import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

import '../models/inventory_item.dart';
import '../utils/date_utils.dart';

class LabelPdfService {
  /// 生成单张价签 PDF，返回保存路径
  ///
  /// V0：先做 PDF 输出，后续再做“直接打印”
  static Future<String> generatePriceLabelPdf({
    required InventoryItem item,
    required DateTime now,
    required double currentPrice,
    required double discountPercent, // 0~1
  }) async {
    final doc = pw.Document();

    final discountText =
        discountPercent > 0 ? '${(discountPercent * 100).round()}% OFF' : 'NO DISCOUNT';

    // 简单标签版式：适配小票/标签打印
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(70 * PdfPageFormat.mm, 40 * PdfPageFormat.mm),
        margin: const pw.EdgeInsets.all(6),
        build: (context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 1, color: PdfColors.grey700),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            padding: const pw.EdgeInsets.all(8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  item.name,
                  maxLines: 2,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text('Category: ${item.category}', style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 2),
                pw.Text('Expires: ${DateUtilsX.yyyyMmDd(item.expiryDate)}',
                    style: const pw.TextStyle(fontSize: 8)),
                pw.Spacer(),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '\$${currentPrice.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Text(
                      '\$${item.originalPrice.toStringAsFixed(2)}',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                        decoration: pw.TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Text(discountText, style: const pw.TextStyle(fontSize: 9, color: PdfColors.black)),
                pw.SizedBox(height: 2),
                pw.Text('Generated: ${DateUtilsX.yyyyMmDd(now)}',
                    style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
              ],
            ),
          );
        },
      ),
    );

    // 保存路径：Documents/ExpiryManagerV0/labels/
    final dir = await _ensureLabelsDir();
    final fileName = 'label_${item.id}_${now.millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  static Future<Directory> _ensureLabelsDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final base = Directory('${docDir.path}${Platform.pathSeparator}ExpiryManagerV0');
    final labels = Directory('${base.path}${Platform.pathSeparator}labels');

    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    if (!await labels.exists()) {
      await labels.create(recursive: true);
    }
    return labels;
  }
}
