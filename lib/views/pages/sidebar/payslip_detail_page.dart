import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/payslip_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/payslip.dart';
import 'package:selecta_ops/services/payslip_pdf_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

class PayslipDetailPage extends StatefulWidget {
  final Payslip payslip;
  final bool isDealer;

  const PayslipDetailPage({
    super.key,
    required this.payslip,
    required this.isDealer,
  });

  @override
  State<PayslipDetailPage> createState() => _PayslipDetailPageState();
}

class _PayslipDetailPageState extends State<PayslipDetailPage> {
  final PayslipController _controller = PayslipController();
  final NumberFormat _currencyFormat =
      NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');

  late Payslip _currentPayslip;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _currentPayslip = widget.payslip;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case PayslipStatus.draft:
        return Colors.orange;
      case PayslipStatus.issued:
        return Colors.blue;
      case PayslipStatus.acknowledged:
        return Colors.teal;
      case PayslipStatus.paid:
        return const Color(0xFF10B981);
      default:
        return Colors.grey;
    }
  }


  Future<void> _handleExportPdf() async {
    setState(() => _isProcessing = true);
    try {
      final file = await PayslipPdfService.saveAndOpenPdf(_currentPayslip);
      if (mounted) {
        ShowMessage.success(
          context,
          'Payslip PDF saved: ${file.path.split('/').last}',
        );
      }
    } catch (e, s) {
      debugPrint('Error exporting PDF: $e\n$s');
      if (mounted) {
        ShowMessage.error(context, 'Failed to generate PDF: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleAcknowledge() async {
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Acknowledge Payslip',
      message: 'Confirm that you have reviewed and received your payslip for ${_currentPayslip.cutoffWeekLabel}?',
      confirmText: 'Acknowledge',
      icon: Icons.check_circle_outline_rounded,
    );

    if (confirmed && mounted) {
      setState(() => _isProcessing = true);
      try {
        await _controller.acknowledgePayslip(_currentPayslip.id);
        setState(() {
          _currentPayslip = _currentPayslip.copyWith(
            status: PayslipStatus.acknowledged,
          );
        });
        if (mounted) {
          ShowMessage.success(context, 'Payslip acknowledged successfully!');
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Failed to update: $e');
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleMarkPaid() async {
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Mark as Paid',
      message: 'Are you sure you want to mark this payslip as Paid for ${_currentPayslip.salesmanUsername}?',
      confirmText: 'Mark Paid',
      icon: Icons.payments_rounded,
    );

    if (confirmed && mounted) {
      setState(() => _isProcessing = true);
      try {
        await _controller.markPaid(_currentPayslip.id);
        setState(() {
          _currentPayslip = _currentPayslip.copyWith(
            status: PayslipStatus.paid,
          );
        });
        if (mounted) {
          ShowMessage.success(context, 'Payslip marked as Paid!');
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Failed to update: $e');
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleIssue() async {
    setState(() => _isProcessing = true);
    try {
      await _controller.issuePayslip(_currentPayslip.id);
      setState(() {
        _currentPayslip = _currentPayslip.copyWith(
          status: PayslipStatus.issued,
        );
      });
      if (mounted) {
        ShowMessage.success(context, 'Payslip issued to ${_currentPayslip.salesmanUsername}!');
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to issue payslip: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleDelete() async {
    if (!widget.isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to delete payslips.');
      return;
    }

    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Delete Payslip',
      message:
          'Are you sure you want to delete payslip #${_currentPayslip.payslipNumber} for ${_currentPayslip.salesmanUsername}? This action cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
      icon: Icons.delete_forever_rounded,
    );

    if (confirmed && mounted) {
      setState(() => _isProcessing = true);
      try {
        await _controller.deletePayslip(_currentPayslip.id, _currentPayslip);
        if (mounted) {
          ShowMessage.success(context, 'Payslip deleted successfully.');
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Failed to delete payslip: $e');
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _getStatusColor(_currentPayslip.status);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: CustomAppbar(
          title: 'Digital Payslip',
        actions: [
          if (widget.isDealer)
            AsyncIconButton(
              tooltip: 'Delete Payslip',
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
              onPressed: _handleDelete,
            ),
        ],
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Digital Slip Card (Branded)
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Card Header
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _currentPayslip.dealerName.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: colorScheme.primary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Payslip #${_currentPayslip.payslipNumber.isNotEmpty ? _currentPayslip.payslipNumber : "N/A"}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: statusColor, width: 1),
                                ),
                                child: Text(
                                  _currentPayslip.status.toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Employee & Rate Information
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                                    child: Icon(Icons.person_rounded,
                                        color: colorScheme.primary, size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _currentPayslip.salesmanUsername,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Cutoff: ${_currentPayslip.cutoffWeekLabel}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 14),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildMetaColumn(
                                      'Daily Rate',
                                      _currencyFormat.format(_currentPayslip.dailyRate),
                                      colorScheme,
                                    ),
                                    Container(
                                      width: 1,
                                      height: 30,
                                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                    ),
                                    _buildMetaColumn(
                                      'Days Worked',
                                      '${_currentPayslip.daysWorked} days',
                                      colorScheme,
                                    ),
                                    Container(
                                      width: 1,
                                      height: 30,
                                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                    ),
                                    _buildMetaColumn(
                                      'Base Salary',
                                      _currencyFormat.format(_currentPayslip.basePay),
                                      colorScheme,
                                      isBold: true,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Divider(height: 1),

                        // Net Pay Callout
                        Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.teal.shade700,
                                Colors.teal.shade900,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.teal.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'NET TAKE-HOME PAY',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Total Payout for Week',
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                _currencyFormat.format(_currentPayslip.netPay),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 2. Earnings Section
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.add_circle_outline_rounded,
                                      color: Colors.teal, size: 18),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Gross Earnings',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _currencyFormat.format(_currentPayslip.grossPay),
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _buildRow(
                                'Basic Pay (${_currentPayslip.daysWorked} days @ ${_currencyFormat.format(_currentPayslip.dailyRate)})',
                                _currencyFormat.format(_currentPayslip.basePay),
                              ),
                              if (_currentPayslip.incentiveAmount > 0)
                                _buildRow(
                                  _currentPayslip.incentiveRemarks.isNotEmpty
                                      ? 'Incentive: ${_currentPayslip.incentiveRemarks}'
                                      : 'Sales Performance Incentive',
                                  _currencyFormat.format(_currentPayslip.incentiveAmount),
                                ),
                            ],
                          ),
                        ),

                        const Divider(height: 1),

                        // 3. Deductions Section
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.remove_circle_outline_rounded,
                                      color: Colors.redAccent, size: 18),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Deductions',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '-${_currencyFormat.format(_currentPayslip.totalDeductions)}',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.redAccent),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (_currentPayslip.deductions.isEmpty &&
                                  _currentPayslip.otherDeductions == 0)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Text(
                                    'No deductions for this cutoff.',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ..._currentPayslip.deductions.map((item) {
                                final dStr = _dateFormat.format(item.date.toDate());
                                return _buildRow(
                                  '${item.title} ($dStr)',
                                  '-${_currencyFormat.format(item.amount)}',
                                  isDeduction: true,
                                );
                              }),
                              if (_currentPayslip.otherDeductions > 0)
                                _buildRow(
                                  _currentPayslip.otherDeductionsRemarks.isNotEmpty
                                      ? 'Other: ${_currentPayslip.otherDeductionsRemarks}'
                                      : 'Other Deductions',
                                  '-${_currencyFormat.format(_currentPayslip.otherDeductions)}',
                                  isDeduction: true,
                                ),
                            ],
                          ),
                        ),

                        if (_currentPayslip.remarks.isNotEmpty) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'Remarks: ${_currentPayslip.remarks}',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 4. Export PDF Action
                  SizedBox(
                    width: double.infinity,
                    child: AsyncOutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text(
                        'Export PDF',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _handleExportPdf,
                    ),
                  ),

                  // 5. Contextual Action Buttons
                  if (!widget.isDealer &&
                      _currentPayslip.status == PayslipStatus.issued) ...[
                    const SizedBox(height: 16),
                    AsyncFilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Acknowledge Payslip Receipt',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _handleAcknowledge,
                    ),
                  ],

                  if (widget.isDealer) ...[
                    const SizedBox(height: 16),
                    if (_currentPayslip.status == PayslipStatus.draft)
                      AsyncFilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('Issue Payslip to Salesman',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _handleIssue,
                      )
                    else if (_currentPayslip.status != PayslipStatus.paid)
                      AsyncFilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.payments_rounded),
                        label: const Text('Mark as Paid',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _handleMarkPaid,
                      ),
                  ],
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildMetaColumn(String label, String value, ColorScheme colorScheme,
      {bool isBold = false}) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value, {bool isDeduction = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDeduction ? Colors.redAccent : null,
            ),
          ),
        ],
      ),
    );
  }
}
