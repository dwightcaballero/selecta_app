import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/badorder_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

class BadOrderBatchCreatePage extends StatefulWidget {
  const BadOrderBatchCreatePage({
    super.key,
    required this.pendingOrders,
    required this.existingBatchCount,
  });

  final List<QueryDocumentSnapshot<BadOrder>> pendingOrders;
  final int existingBatchCount;

  @override
  State<BadOrderBatchCreatePage> createState() => _BadOrderBatchCreatePageState();
}

class _BadOrderBatchCreatePageState extends State<BadOrderBatchCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final BadOrderController _controller = BadOrderController();

  late final TextEditingController _batchNumberController;
  final TextEditingController _supplierRefController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  DateTime _pulloutDate = DateTime.now();

  final Set<String> _selectedIds = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final defaultBatchNo = _controller.generateDefaultBatchNumber(widget.existingBatchCount);
    _batchNumberController = TextEditingController(text: defaultBatchNo);

    // Default select all pending orders
    for (final doc in widget.pendingOrders) {
      _selectedIds.add(doc.id);
    }
  }

  @override
  void dispose() {
    _batchNumberController.dispose();
    _supplierRefController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == widget.pendingOrders.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.clear();
        for (final doc in widget.pendingOrders) {
          _selectedIds.add(doc.id);
        }
      }
    });
  }

  double get _selectedStoreRefundTotal {
    double total = 0.0;
    for (final doc in widget.pendingOrders) {
      if (_selectedIds.contains(doc.id)) {
        total += doc.data().totalAmount;
      }
    }
    return total;
  }

  double get _selectedSupplierCreditTotal {
    double total = 0.0;
    for (final doc in widget.pendingOrders) {
      if (_selectedIds.contains(doc.id)) {
        final bo = doc.data();
        total += bo.hasDualPricing ? bo.supplierAmount : bo.totalAmount;
      }
    }
    return total;
  }

  Future<void> _onSubmit() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    if (_selectedIds.isEmpty) {
      ShowMessage.error(context, 'Please select at least one store bad order for this batch.');
      return;
    }

    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Create Warehouse Batch',
      message:
          'Create batch [${_batchNumberController.text.trim()}] containing ${_selectedIds.length} store pullouts?\n\n'
          'Expected Supplier Credit: ${Helperfunctions.formatDoubleAmountForDisplay(_selectedSupplierCreditTotal)}\n'
          'Stores Refunded: ${Helperfunctions.formatDoubleAmountForDisplay(_selectedStoreRefundTotal)}',
      icon: Icons.warehouse_outlined,
      confirmText: 'Confirm Batch',
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final selectedDocs = widget.pendingOrders.where((doc) => _selectedIds.contains(doc.id)).toList();

      final batchId = await _controller.createWarehouseBatch(
        batchNumber: _batchNumberController.text.trim(),
        supplierRefNo: _supplierRefController.text.trim(),
        pulloutDate: _pulloutDate,
        selectedBadOrders: selectedDocs,
        notes: _notesController.text.trim(),
      );

      if (mounted) {
        ShowMessage.success(context, 'Warehouse pullout batch created successfully!');
        Navigator.pop(context, batchId);
      }
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'BadOrderBatchCreatePage',
        action: 'Create Batch',
        error: e,
        stackTrace: s,
        extraData: {
          'batchNumber': _batchNumberController.text,
          'count': _selectedIds.length,
        },
      );
      if (mounted) ShowMessage.error(context, 'Failed to create batch: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final allSelected = widget.pendingOrders.isNotEmpty && _selectedIds.length == widget.pendingOrders.length;

    return Scaffold(
      appBar: const CustomAppbar(
        title: 'New Warehouse Batch',
        subtitle: 'Batch Supplier Pullout',
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1.0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                offset: const Offset(0, -2),
                blurRadius: 6,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_selectedIds.length} store pullout${_selectedIds.length == 1 ? '' : 's'} selected',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                    Text(
                      'Expected: ${Helperfunctions.formatDoubleAmountForDisplay(_selectedSupplierCreditTotal)}',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.primary),
                    ),
                    Text(
                      'Stores: ${Helperfunctions.formatDoubleAmountForDisplay(_selectedStoreRefundTotal)} • Diff: ${Helperfunctions.formatDoubleAmountForDisplay(_selectedStoreRefundTotal - _selectedSupplierCreditTotal)}',
                      style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AsyncFilledButton.icon(
                onPressed: _selectedIds.isEmpty ? null : _onSubmit,
                loadingLabel: 'Creating Batch...',
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  backgroundColor: Colors.blue.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text('Create Batch', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Card(
              elevation: 0,
              color: colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.inventory_2_outlined, color: Colors.blue.shade700, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Batch & Supplier Pullout Info',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    TextFormField(
                      controller: _batchNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Batch Number / ID *',
                        hintText: 'e.g. BO-202610-001',
                        prefixIcon: Icon(Icons.tag, size: 20),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Batch number is required.' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _supplierRefController,
                      decoration: const InputDecoration(
                        labelText: 'Supplier Pullout Slip / DR # *',
                        hintText: 'e.g. DR-98124 or SLIP-4321',
                        prefixIcon: Icon(Icons.receipt_outlined, size: 20),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Supplier reference number is required.' : null,
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _pulloutDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 30)),
                        );
                        if (picked != null) {
                          setState(() => _pulloutDate = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Warehouse Pullout Date *',
                          prefixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        child: Text(
                          Helperfunctions.formatDateForDisplay(_pulloutDate),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Remarks / Notes (Optional)',
                        hintText: 'e.g. Unilever driver: Juan / 10 cases picked up',
                        prefixIcon: Icon(Icons.notes_outlined, size: 20),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AVAILABLE STORE ORDERS (${widget.pendingOrders.length})',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select bad orders to include in this supplier pullout',
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: widget.pendingOrders.isEmpty ? null : _toggleSelectAll,
                  icon: Icon(allSelected ? Icons.deselect : Icons.select_all, size: 18),
                  label: Text(allSelected ? 'Deselect All' : 'Select All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.pendingOrders.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: const Center(
                  child: Text(
                    'No pending store bad orders found in warehouse.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.pendingOrders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final doc = widget.pendingOrders[index];
                  final bo = doc.data();
                  final isSelected = _selectedIds.contains(doc.id);

                  return Card(
                    elevation: 0,
                    margin: EdgeInsets.zero,
                    color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.15) : colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      value: isSelected,
                      activeColor: colorScheme.primary,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedIds.add(doc.id);
                          } else {
                            _selectedIds.remove(doc.id);
                          }
                        });
                      },
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              bo.hapistore,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                Helperfunctions.formatDoubleAmountForDisplay(
                                  bo.hasDualPricing ? bo.supplierAmount : bo.totalAmount,
                                ),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                  color: colorScheme.primary,
                                ),
                              ),
                              if (bo.hasDualPricing)
                                Text(
                                  'Store: ${Helperfunctions.formatDoubleAmountForDisplay(bo.totalAmount)}',
                                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${Helperfunctions.formatDateForDisplay(bo.badorderDate.toDate())} • ${bo.items.length} items',
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: bo.isStoreRefunded ? Colors.green.shade50 : Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                bo.isStoreRefunded ? 'Refunded' : 'Unrefunded',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: bo.isStoreRefunded ? Colors.green.shade800 : Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
