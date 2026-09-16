import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class HapiStorePage extends StatefulWidget {
  const HapiStorePage({super.key, required this.hapiStoreID, required this.hapistore});

  final String hapiStoreID;
  final Hapistore hapistore;

  @override
  State<HapiStorePage> createState() => _HapiStorePageState();
}

class _HapiStorePageState extends State<HapiStorePage> {
  final HapiStoreService db = HapiStoreService();
  late TextEditingController txtAddress;
  late TextEditingController txtContact;
  late TextEditingController txtName;
  DateTime? _selectedOpeningDate;

  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    txtName.dispose();
    txtContact.dispose();
    txtAddress.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    txtName = TextEditingController(text: widget.hapistore.storeName);
    txtAddress = TextEditingController(text: widget.hapistore.storeAddress);
    txtContact = TextEditingController(text: widget.hapistore.storeContact);
    _selectedOpeningDate = widget.hapistore.openingDate?.toDate();
  }

  void onChangeDate() async {
    final DateTime? dateTime = await showDatePicker(
      context: context,
      initialDate: _selectedOpeningDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
    );

    if (dateTime != null) {
      setState(() {
        _selectedOpeningDate = dateTime;
      });
    }
  }

  void onClearDate() {
    setState(() {
      _selectedOpeningDate = null;
    });
  }

  void onSave() {
    if (_formKey.currentState!.validate()) {
      Hapistore newHs = Hapistore(
        storeName: txtName.text.trim().toUpperCase(),
        storeAddress: txtAddress.text.trim(),
        storeContact: txtContact.text.trim(),
        openingDate: _selectedOpeningDate != null ? Timestamp.fromDate(_selectedOpeningDate!) : null,
      );
      db.addHapiStore(newHs);
      ShowMessage.success(context, 'Successfully created Hapi Store [${newHs.storeName}]!');
      Navigator.pop(context);
    } else {
      ShowMessage.error(context, 'Please fill up all required fields');
    }
  }

  void onUpdate() {
    if (_formKey.currentState!.validate()) {
      Hapistore updatedHS = widget.hapistore.copyWith(
        storeName: txtName.text.trim().toUpperCase(),
        storeAddress: txtAddress.text.trim(),
        storeContact: txtContact.text.trim(),
        openingDate: _selectedOpeningDate != null ? Timestamp.fromDate(_selectedOpeningDate!) : null,
        clearOpeningDate: _selectedOpeningDate == null,
      );
      db.updateHapiStore(widget.hapiStoreID, updatedHS);
      ShowMessage.success(context, 'Successfully updated Hapi Store [${updatedHS.storeName}]!');
      Navigator.pop(context);
    } else {
      ShowMessage.error(context, 'Please fill up all required fields');
    }
  }

  void onDelete() {
    db.deleteHapiStore(widget.hapiStoreID);
    ShowMessage.success(context, 'Successfully deleted Hapi Store [${widget.hapistore.storeName}]!');
    Navigator.pop(context);
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
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
                  decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildStoreDetailsCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildSectionCard(
      title: 'Store Information',
      icon: Icons.storefront_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          // Store Name
          TextFormField(
            controller: txtName,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Store Name',
              hintText: 'e.g. DWIGHT MINI STORE',
              prefixIcon: Icon(Icons.store_outlined, size: 20, color: colorScheme.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Store Name should not be blank';
              return null;
            },
          ),

          // Contact Number
          TextFormField(
            controller: txtContact,
            maxLength: 11,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Contact Number',
              hintText: '09XXXXXXXXX',
              counterText: '',
              prefixIcon: Icon(Icons.phone_outlined, size: 20, color: colorScheme.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Contact Number should not be blank';
              if (value.trim().length != 11) return 'Contact Number should consist of 11 digits';
              return null;
            },
          ),

          // Store Address
          TextFormField(
            controller: txtAddress,
            keyboardType: TextInputType.streetAddress,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Store Address',
              hintText: 'e.g. Purok 14, Saavedra Village, Bago Aplaya...',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.location_on_outlined, size: 20, color: colorScheme.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Address should not be blank';
              return null;
            },
          ),

          // Opening Date
          _buildDatePickerField(label: 'Opening Date', selectedDate: _selectedOpeningDate, onTap: onChangeDate, onClear: onClearDate),
        ],
      ),
    );
  }

  Widget _buildDatePickerField({required String label, required DateTime? selectedDate, required VoidCallback onTap, VoidCallback? onClear}) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black54),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined, size: 20, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  Text(
                    selectedDate != null ? Helperfunctions.formatDateForDisplay(selectedDate) : 'Select Date',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selectedDate != null ? FontWeight.w600 : FontWeight.normal,
                      color: selectedDate != null ? null : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selectedDate != null && onClear != null)
              IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: onClear, padding: EdgeInsets.zero, constraints: const BoxConstraints())
            else
              Icon(Icons.edit_calendar_outlined, size: 18, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildStickyBottomBar() {
    final colorScheme = Theme.of(context).colorScheme;
    bool isUpdating = widget.hapiStoreID.isNotEmpty;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1.0)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: isUpdating
            ? Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await ShowMessage.confirm(
                          context,
                          title: ConfirmTitle.delete,
                          message: 'Are you sure you want to delete [${widget.hapistore.storeName}]?',
                          isDestructive: true,
                          icon: Icons.delete_outline,
                          confirmText: 'Delete',
                        );
                        if (confirmed) onDelete();
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50.0),
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300, width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final confirmed = await ShowMessage.confirm(
                          context,
                          title: ConfirmTitle.update,
                          message: 'Save changes to store [${txtName.text.trim().toUpperCase()}]?',
                          icon: Icons.check_circle_outline,
                          confirmText: 'Update',
                        );
                        if (confirmed) onUpdate();
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 50.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text('Update Store', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            : FilledButton.icon(
                onPressed: () async {
                  final confirmed = await ShowMessage.confirm(
                    context,
                    title: ConfirmTitle.save,
                    message: 'Save new store [${txtName.text.trim().toUpperCase()}]?',
                    icon: Icons.save_outlined,
                    confirmText: 'Save',
                  );
                  if (confirmed) onSave();
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Store', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Hapi Store', subtitle: widget.hapiStoreID.isEmpty ? 'New Store Record' : widget.hapistore.storeName),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              // 1. Store Details Card
              _buildStoreDetailsCard(),
            ],
          ),
        ),
      ),
    );
  }
}
