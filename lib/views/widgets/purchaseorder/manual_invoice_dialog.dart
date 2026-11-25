import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/purchaseorder.dart';

class ManualInvoiceResult {
  const ManualInvoiceResult(this.number, this.amount, this.date, this.image);
  final String number;
  final double amount;
  final DateTime date;
  final File? image;
}

class ManualInvoiceDialog extends StatefulWidget {
  const ManualInvoiceDialog({super.key, required this.order});
  final Purchaseorder order;

  @override
  State<ManualInvoiceDialog> createState() => _ManualInvoiceDialogState();
}

class _ManualInvoiceDialogState extends State<ManualInvoiceDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _number;
  late final TextEditingController _amount;
  late DateTime _date;
  File? _image;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController(text: widget.order.invoiceNumber);
    _amount = TextEditingController(text: widget.order.manualReceiptValue.toStringAsFixed(2));
    _date = widget.order.invoiceDate.toDate();
  }

  @override
  void dispose() {
    _number.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Verify invoice'),
    content: Form(
      key: _form,
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Check the supplier invoice against the manually recorded receipt. This does not change stock.'),
          TextFormField(
            controller: _number,
            decoration: const InputDecoration(labelText: 'Invoice number'),
            validator: (value) => (value ?? '').trim().isEmpty ? 'Enter the invoice number' : null,
          ),
          TextFormField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'Official invoice amount'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              final amount = double.tryParse((value ?? '').trim());
              return amount == null || !amount.isFinite || amount <= 0 ? 'Enter an amount greater than zero' : null;
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text('Invoice date: ${DateFormat('MMM dd, yyyy').format(_date)}'),
            onPressed: () async {
              final date = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2035));
              if (date != null) setState(() => _date = date);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.attach_file),
            label: Text(_image == null ? 'Attach invoice image (optional)' : 'Change invoice image'),
            onPressed: () async {
              final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
              if (picked != null) setState(() => _image = File(picked.path));
            },
          ),
          if (_image != null) Text(_image!.path.split('/').last),
          const Text('The overpayment credit will be recalculated from the invoice amount.'),
        ],
      )),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, ManualInvoiceResult(_number.text.trim(), double.parse(_amount.text.trim()), _date, _image));
          }
        },
        child: const Text('Confirm invoice'),
      ),
    ],
  );
}
