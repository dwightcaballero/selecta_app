import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/payslip_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/payslip.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/views/pages/sidebar/payslip_detail_page.dart';
import 'package:selecta_ops/views/pages/sidebar/payslip_generator_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

class PayslipListPage extends StatefulWidget {
  const PayslipListPage({super.key});

  @override
  State<PayslipListPage> createState() => _PayslipListPageState();
}

class _PayslipListPageState extends State<PayslipListPage> {
  final PayslipController _controller = PayslipController();
  final NumberFormat _currencyFormat =
      NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  bool _isLoading = true;
  bool _isDealer = false;
  Users? _currentUser;
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadUserContext();
  }

  Future<void> _loadUserContext() async {
    final isDealer = await _controller.checkIsDealer();
    final user = await _controller.getCurrentUser();
    if (mounted) {
      setState(() {
        _isDealer = isDealer;
        _currentUser = user;
        _isLoading = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: CustomAppbar(
        title: _isDealer ? 'Weekly Payroll & Payslips' : 'My Digital Payslips',
        actions: [
          if (_isDealer && _currentUser != null)
            IconButton(
              tooltip: 'New Payslip',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _openGenerator(),
            ),
        ],
      ),
      floatingActionButton: _isDealer && _currentUser != null
          ? FloatingActionButton.extended(
              onPressed: _openGenerator,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Payslip'),
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentUser == null
              ? const Center(child: Text('User session not found.'))
              : _isDealer
                  ? _buildDealerView(colorScheme)
                  : _buildSalesmanView(colorScheme),
    );
  }

  void _openGenerator() {
    if (_currentUser == null) return;
    Helperfunctions.navigateThenWait(
      context,
      PayslipGeneratorPage(dealerName: _currentUser!.dealerName),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SALESMAN VIEW (Current Week Hero + Previous Weeks List)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSalesmanView(ColorScheme colorScheme) {
    return StreamBuilder<List<Payslip>>(
      stream: _controller.getSalesmanPayslipsStream(_currentUser!.username),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final payslips = snapshot.data ?? [];
        if (payslips.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined, size: 64, color: colorScheme.outlineVariant),
                const SizedBox(height: 16),
                const Text('No Payslips Yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Your weekly payslips will appear here once issued by your dealer.',
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final grouped = PayslipController.groupPayslips(payslips);
        final current = grouped.currentPayslip;
        final previous = grouped.previousPayslips;

        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              // 1. Current Week Payslip Hero Card
              if (current != null) ...[
                const Text(
                  'CURRENT PAYROLL',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                _buildCurrentPayslipHero(current, colorScheme),
                const SizedBox(height: 24),
              ],

              // 2. Previous Payslips Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'PREVIOUS PAYSLIPS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '${previous.length} record(s)',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (previous.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      'No previous payslips archived yet.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: previous.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = previous[index];
                    return _buildPayslipTile(item, colorScheme);
                  },
                ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCurrentPayslipHero(Payslip payslip, ColorScheme colorScheme) {
    final statusColor = _getStatusColor(payslip.status);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.teal.shade800,
            const Color(0xFF042F2E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withValues(alpha: 0.25),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openDetail(payslip),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        payslip.cutoffWeekLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: statusColor, width: 1),
                      ),
                      child: Text(
                        payslip.status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'NET TAKE-HOME PAY',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currencyFormat.format(payslip.netPay),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${payslip.daysWorked} days @ ${_currencyFormat.format(payslip.dailyRate)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      if (payslip.totalDeductions > 0)
                        Text(
                          'Deductions: -${_currencyFormat.format(payslip.totalDeductions)}',
                          style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.teal.shade900,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text('View Digital Slip', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _openDetail(payslip),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPayslipTile(Payslip payslip, ColorScheme colorScheme) {
    final statusColor = _getStatusColor(payslip.status);

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDetail(payslip),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.receipt_outlined, color: colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payslip.cutoffWeekLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${payslip.daysWorked} days worked • ${_currencyFormat.format(payslip.dailyRate)}/day',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _currencyFormat.format(payslip.netPay),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      payslip.status.toUpperCase(),
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DEALER VIEW (List with salesman badges and status filter tabs)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDealerView(ColorScheme colorScheme) {
    return StreamBuilder<List<Payslip>>(
      stream: _controller.getDealerPayslipsStream(_currentUser!.dealerName),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allPayslips = snapshot.data ?? [];
        final filtered = _selectedFilter == 'All'
            ? allPayslips
            : allPayslips.where((p) => p.status == _selectedFilter).toList();

        return Column(
          children: [
            // Filter Chips Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: ['All', PayslipStatus.issued, PayslipStatus.draft, PayslipStatus.paid]
                    .map((status) {
                  final isSelected = _selectedFilter == status;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(status),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedFilter = status),
                    ),
                  );
                }).toList(),
              ),
            ),

            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.payments_outlined, size: 64, color: colorScheme.outlineVariant),
                          const SizedBox(height: 16),
                          const Text('No Payslips Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(
                            'Tap "+ New Payslip" to calculate and issue payroll for your salesmen.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        return _buildDealerPayslipCard(item, colorScheme);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDealerPayslipCard(Payslip payslip, ColorScheme colorScheme) {
    final statusColor = _getStatusColor(payslip.status);

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDetail(payslip),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                        child: Icon(Icons.person, size: 18, color: colorScheme.primary),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        payslip.salesmanUsername,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor, width: 1),
                    ),
                    child: Text(
                      payslip.status.toUpperCase(),
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    payslip.cutoffWeekLabel,
                    style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    _currencyFormat.format(payslip.netPay),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${payslip.daysWorked} days • Gross: ${_currencyFormat.format(payslip.grossPay)}',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  if (payslip.totalDeductions > 0)
                    Text(
                      'Deductions: -${_currencyFormat.format(payslip.totalDeductions)}',
                      style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(Payslip payslip) {
    Helperfunctions.navigateThenWait(
      context,
      PayslipDetailPage(payslip: payslip, isDealer: _isDealer),
    );
  }
}
