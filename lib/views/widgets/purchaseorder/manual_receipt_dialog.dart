import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/purchaseorder.dart';

class ManualReceiptResult {
  const ManualReceiptResult(this.lines, this.date, this.reference);
  final List<ManualReceiptLine> lines;
  final DateTime date;
  final String reference;
}

class ManualReceiptDialog extends StatefulWidget {
  const ManualReceiptDialog({super.key, required this.items, required this.orderAmount});
  final List<OrderItem> items;
  final double orderAmount;

  @override
  State<ManualReceiptDialog> createState() => _ManualReceiptDialogState();
}

class _ManualReceiptDialogState extends State<ManualReceiptDialog> {
  final _formKey = GlobalKey<FormState>();
  late final List<TextEditingController> _quantities;
  late final List<String?> _reasons;
  final _reference = TextEditingController();
  DateTime _date = DateTime.now();
  final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _quantities = widget.items.map((item) => TextEditingController(text: '${item.effectiveQuantity}')).toList();
    _reasons = List.filled(widget.items.length, null);
  }

  @override
  void dispose() {
    for (final controller in _quantities) {
      controller.dispose();
    }
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = List.generate(widget.items.length, (i) {
      final qty = int.tryParse(_quantities[i].text) ?? 0;
      return qty * widget.items[i].buyingPrice;
    }).fold<double>(0, (a, b) => a + b);
    final credit = (widget.orderAmount - total).clamp(0.0, double.infinity);
    return AlertDialog(
      title: const Text('Receive with exceptions'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enter the quantity physically received. Set it to 0 for an item that did not arrive. Short quantities will be closed, not kept as incoming stock.'),
                const SizedBox(height: 12),
                for (var i = 0; i < widget.items.length; i++) ...[
                  Text(widget.items[i].productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Row(children: [
                    Expanded(child: TextFormField(
                      controller: _quantities[i],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(labelText: 'Received (ordered ${widget.items[i].effectiveQuantity})'),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final qty = int.tryParse(value ?? '');
                        if (qty == null || qty < 0 || qty > widget.items[i].effectiveQuantity) {
                          return 'Enter 0 to ${widget.items[i].effectiveQuantity}';
                        }
                        return null;
                      },
                    )),
                    TextButton(
                      onPressed: () => setState(() {
                        _quantities[i].text = '0';
                        _reasons[i] = 'Not delivered';
                      }),
                      child: const Text('Not received'),
                    ),
                  ]),
                  if ((int.tryParse(_quantities[i].text) ?? widget.items[i].effectiveQuantity) < widget.items[i].effectiveQuantity)
                    DropdownButtonFormField<String>(
                      initialValue: _reasons[i],
                      decoration: const InputDecoration(labelText: 'Shortage reason'),
                      items: const [
                        DropdownMenuItem(value: 'Not delivered', child: Text('Not delivered')),
                        DropdownMenuItem(value: 'Damaged / rejected', child: Text('Damaged / rejected')),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (value) => setState(() => _reasons[i] = value),
                      validator: (value) => value == null ? 'Select a reason' : null,
                    ),
                  const SizedBox(height: 12),
                ],
                TextField(controller: _reference, decoration: const InputDecoration(labelText: 'Invoice / DR number (optional)')),
                TextButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2035));
                    if (date != null) setState(() => _date = date);
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text('Received: ${DateFormat('MMM dd, yyyy').format(_date)}'),
                ),
                Text('Restock value: ${_currency.format(total)}'),
                Text('Automatic overpayment credit: ${_currency.format(credit)}'),
                const SizedBox(height: 8),
                const Text('Inventory will be updated immediately. Invoice details remain unverified.'),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final lines = List.generate(widget.items.length, (i) => ManualReceiptLine(
              item: widget.items[i],
              receivedQuantity: int.parse(_quantities[i].text),
              shortageReason: int.parse(_quantities[i].text) < widget.items[i].effectiveQuantity ? _reasons[i] ?? '' : '',
            ));
            if (lines.every((line) => line.receivedQuantity == 0)) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receive at least one unit.')));
              return;
            }
            Navigator.pop(context, ManualReceiptResult(lines, _date, _reference.text.trim()));
          },
          child: const Text('Confirm & restock'),
        ),
      ],
    );
  }
}
