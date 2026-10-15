import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:selecta_ops/models/payslip.dart';

class PayslipPdfService {
  static final NumberFormat _currencyFormat =
      NumberFormat.currency(symbol: 'PHP ', decimalDigits: 2);
  static final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');

  /// Helper to sanitize any Unicode characters (e.g. ₱, em-dashes) for standard PDF fonts
  static String _clean(String input) {
    return input
        .replaceAll('₱', 'PHP ')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('’', "'")
        .replaceAll('‘', "'");
  }

  /// Generates the raw PDF bytes for a given payslip
  static Future<Uint8List> generatePayslipPdf(Payslip payslip) async {
    final pdf = pw.Document();

    final startDate = payslip.periodStart.toDate();
    final endDate = payslip.periodEnd.toDate();
    final periodStr = _clean(
        '${_dateFormat.format(startDate)} - ${_dateFormat.format(endDate)}');
    final issueDateStr = payslip.issuedDate != null
        ? _dateFormat.format(payslip.issuedDate!.toDate())
        : _dateFormat.format(payslip.createdDate.toDate());

    final cleanDealer = payslip.dealerName.isNotEmpty
        ? _clean(payslip.dealerName.toUpperCase())
        : 'SELECTA DISTRIBUTION DEALER';
    final cleanPayslipNum = payslip.payslipNumber.isNotEmpty
        ? _clean(payslip.payslipNumber)
        : 'N/A';
    final cleanUsername = _clean(payslip.salesmanUsername);
    final cleanWeekLabel = _clean(payslip.cutoffWeekLabel);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 14),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.red800, width: 2),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          cleanDealer,
                          style: pw.TextStyle(
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.red800,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'OFFICIAL EMPLOYEE PAYSLIP',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey800,
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'Payslip #: $cleanPayslipNum',
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'Issued: $issueDateStr',
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.Text(
                          'Status: ${payslip.status.toUpperCase()}',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: payslip.status.toLowerCase() == 'draft'
                                ? PdfColors.orange700
                                : PdfColors.green700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 14),

              // Employee & Period Info Box
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildPdfInfoRow('Employee Name:', cleanUsername),
                        pw.SizedBox(height: 4),
                        _buildPdfInfoRow('Role:', 'Salesman'),
                        pw.SizedBox(height: 4),
                        _buildPdfInfoRow('Cutoff Period:', periodStr),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildPdfInfoRow(
                          'Daily Rate:',
                          _currencyFormat.format(payslip.dailyRate),
                        ),
                        pw.SizedBox(height: 4),
                        _buildPdfInfoRow(
                          'Days Worked:',
                          '${payslip.daysWorked} days',
                        ),
                        pw.SizedBox(height: 4),
                        _buildPdfInfoRow('Cutoff Week:', cleanWeekLabel),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 18),

              // Earnings & Deductions Tables (Side by Side)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // EARNINGS TABLE
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.symmetric(
                              vertical: 6, horizontal: 8),
                          color: PdfColors.teal700,
                          child: pw.Text(
                            'GROSS EARNINGS',
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                        _buildPdfTableRow(
                          'Base Salary (${payslip.daysWorked}d @ ${_currencyFormat.format(payslip.dailyRate)})',
                          _currencyFormat.format(payslip.basePay),
                        ),
                        if (payslip.incentiveAmount > 0)
                          _buildPdfTableRow(
                            payslip.incentiveRemarks.isNotEmpty
                                ? _clean('Incentive (${payslip.incentiveRemarks})')
                                : 'Performance Incentive',
                            _currencyFormat.format(payslip.incentiveAmount),
                          ),
                        pw.Divider(color: PdfColors.grey400),
                        _buildPdfTableRow(
                          'TOTAL GROSS PAY',
                          _currencyFormat.format(payslip.grossPay),
                          isBold: true,
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(width: 14),

                  // DEDUCTIONS TABLE
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.symmetric(
                              vertical: 6, horizontal: 8),
                          color: PdfColors.red700,
                          child: pw.Text(
                            'DEDUCTIONS',
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                        if (payslip.deductions.isEmpty &&
                            payslip.otherDeductions == 0)
                          _buildPdfTableRow('No deductions', 'PHP 0.00'),
                        ...payslip.deductions.map((item) {
                          final dateStr =
                              _dateFormat.format(item.date.toDate());
                          return _buildPdfTableRow(
                            _clean('${item.title} ($dateStr)'),
                            _currencyFormat.format(item.amount),
                          );
                        }),
                        if (payslip.otherDeductions > 0)
                          _buildPdfTableRow(
                            payslip.otherDeductionsRemarks.isNotEmpty
                                ? _clean('Other: ${payslip.otherDeductionsRemarks}')
                                : 'Other Deductions',
                            _currencyFormat.format(payslip.otherDeductions),
                          ),
                        pw.Divider(color: PdfColors.grey400),
                        _buildPdfTableRow(
                          'TOTAL DEDUCTIONS',
                          _currencyFormat.format(payslip.totalDeductions),
                          isBold: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 20),

              // NET PAY CALLOUT BOX
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: PdfColors.teal50,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.teal700, width: 1.5),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'NET TAKE-HOME PAY',
                          style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.teal900,
                          ),
                        ),
                        pw.Text(
                          'Gross Pay minus Total Deductions for this period',
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                    pw.Text(
                      _currencyFormat.format(payslip.netPay),
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.teal900,
                      ),
                    ),
                  ],
                ),
              ),

              if (payslip.remarks.isNotEmpty) ...[
                pw.SizedBox(height: 12),
                pw.Text(
                  _clean('Remarks: ${payslip.remarks}'),
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ],

              pw.SizedBox(height: 28),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 180,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            bottom: pw.BorderSide(color: PdfColors.grey600, width: 1),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Salesman Signature / Date',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 180,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            bottom: pw.BorderSide(color: PdfColors.grey600, width: 1),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Dealer / Authorized Signature',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text(
                  'Generated via Selecta Operations App',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildPdfInfoRow(String label, String value) {
    return pw.Row(
      children: [
        pw.Text(
          '$label ',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
        ),
        pw.Text(
          value,
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.black),
        ),
      ],
    );
  }

  static pw.Widget _buildPdfTableRow(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  /// Generates the PDF, saves it directly to the device Documents directory,
  /// and opens it in the default system PDF viewer (Drive, Samsung Notes, Acrobat, etc.).
  static Future<File> saveAndOpenPdf(Payslip payslip) async {
    final pdfBytes = await generatePayslipPdf(payslip);

    final directory = await getApplicationDocumentsDirectory();
    final sanitizedNumber = payslip.payslipNumber.isNotEmpty
        ? payslip.payslipNumber.replaceAll(RegExp(r'[^\w\-]'), '_')
        : 'payslip_${DateTime.now().millisecondsSinceEpoch}';
    final sanitizedSalesman =
        payslip.salesmanUsername.replaceAll(RegExp(r'[^\w\-]'), '_');
    final fileName = '${sanitizedNumber}_$sanitizedSalesman.pdf';

    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(pdfBytes, flush: true);

    // Open file using OpenFilex
    await OpenFilex.open(file.path);
    return file;
  }

  /// Fallback: Opens the system print/share sheet with the generated PDF
  static Future<void> printOrSharePdf(BuildContext context, Payslip payslip) async {
    try {
      final pdfBytes = await generatePayslipPdf(payslip);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name:
            '${payslip.payslipNumber.isNotEmpty ? payslip.payslipNumber : "payslip"}_${payslip.salesmanUsername}.pdf',
      );
    } catch (_) {
      // If native printing platform channel fails, gracefully fall back to save & open
      await saveAndOpenPdf(payslip);
    }
  }

  /// Directly shares the PDF file
  static Future<void> sharePdf(Payslip payslip) async {
    try {
      final pdfBytes = await generatePayslipPdf(payslip);
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename:
            '${payslip.payslipNumber.isNotEmpty ? payslip.payslipNumber : "payslip"}_${payslip.salesmanUsername}.pdf',
      );
    } catch (_) {
      await saveAndOpenPdf(payslip);
    }
  }
}
