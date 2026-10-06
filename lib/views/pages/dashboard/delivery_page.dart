import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/delivery_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/data.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/views/pages/dashboard/picklist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/return_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/digital_receipt_dialog.dart';
import 'package:selecta_ops/views/widgets/hapistore_dropdown.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';

class DeliveryPage extends StatefulWidget {
  const DeliveryPage({super.key, required this.deliveryID, required this.delivery});

  final Delivery delivery;
  final String deliveryID;

  @override
  State<DeliveryPage> createState() => _DeliveryPageState();
}

class _DeliveryPageState extends State<DeliveryPage> {
  final DeliveryController _controller = DeliveryController();
  bool hasBreakdownForDay = false;
  bool isDayVerified = false;
  bool get isPermanentlySettled =>
      widget.delivery.isReturnApprovedByDealer || widget.delivery.isInventorySettled;

  bool get isLocked {
    if (isPermanentlySettled) return true;
    if (!isDealer) {
      return isDayVerified || hasBreakdownForDay;
    }
    return false;
  }

  bool get isSalesmanLocked => isLocked;

  bool get isDealerLateReconciliation =>
      isDealer && isDayVerified && !widget.delivery.isInventorySettled && widget.deliveryID.isNotEmpty;

  bool _withReturns = false;
  final Map<String, int> _returnQuantities = {};
  final Set<String> _selectedReturnProductIds = {};

  double get originalOrderTotal {
    final orig = widget.delivery.originalOrderAmount;
    if (orig != null && orig > 0) {
      return orig;
    }
    if (widget.delivery.items.isNotEmpty) {
      return widget.delivery.items.fold<double>(0.0, (acc, i) => acc + (i.pickedQuantity * i.sellingPrice));
    }
    return widget.delivery.orderAmount;
  }

  double get calculatedItemsReturnAmount {
    if (!_withReturns || widget.delivery.items.isEmpty) return 0.0;
    double sum = 0.0;
    for (final item in widget.delivery.items) {
      if (_selectedReturnProductIds.contains(item.productId)) {
        final qty = _returnQuantities[item.productId] ?? 1;
        sum += (item.sellingPrice * qty);
      }
    }
    return sum;
  }

  double discrepancy = 0;
  double get effectiveOrderAmount =>
      txtOrderAmount.text.isNotEmpty ? Helperfunctions.formatStringAmountToDouble(txtOrderAmount.text) : widget.delivery.orderAmount;
  TextEditingController dropdownHapiStore = TextEditingController();
  TextEditingController dropdownStatus = TextEditingController();
  bool isDealer = true;
  List<DropdownMenuEntry<String>> listDropdownStatus = [];
  List<DropdownMenuEntry<String>> listDropdownStore = [];
  String networkImagePath = '';
  bool sendText = false;
  String simDetails = '';
  TextEditingController txtCashAmount = TextEditingController();
  TextEditingController txtCreditAmount = TextEditingController();
  TextEditingController txtOnlineAmount = TextEditingController();
  TextEditingController txtOrderAmount = TextEditingController();
  TextEditingController txtRemarks = TextEditingController();
  TextEditingController txtReturnAmount = TextEditingController();
  TextEditingController txtSMS = TextEditingController();
  List<KPlacement> listPlacement = [];
  String placementID = '';

  final _formkey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    super.dispose();
    txtOrderAmount.dispose();
    txtCashAmount.dispose();
    txtOnlineAmount.dispose();
    txtCreditAmount.dispose();
    txtReturnAmount.dispose();
    txtRemarks.dispose();
    txtSMS.dispose();
    dropdownStatus.dispose();
    dropdownHapiStore.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.deliveryID.isNotEmpty) {
      _selectedDate = widget.delivery.deliveryDate?.toDate() ?? DateTime.now();
      networkImagePath = widget.delivery.imagePath;
      dropdownHapiStore.text = widget.delivery.storeName;
      dropdownStatus.text = widget.delivery.transactionStatus;
      txtRemarks.text = widget.delivery.remarks;
      txtOrderAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.orderAmount);
      txtCashAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.cashAmount);
      txtOnlineAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.onlineAmount);
      txtCreditAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.creditAmount);
      txtReturnAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.returnAmount);

      if (widget.delivery.items.isNotEmpty) {
        if (widget.delivery.hasReturnedItems) {
          _withReturns = true;
          for (final item in widget.delivery.items) {
            if (item.returnedQuantity > 0) {
              _selectedReturnProductIds.add(item.productId);
              _returnQuantities[item.productId] = item.returnedQuantity;
            } else {
              _returnQuantities[item.productId] = 1;
            }
          }
        } else {
          for (final item in widget.delivery.items) {
            _returnQuantities[item.productId] = 1;
          }
        }
      }

      computeDiscrepancy();
    }
    prefetchData();
  }

  void onSave() async {
    if (isSalesmanLocked) {
      ShowMessage.error(context, 'Editing is disabled. A cash breakdown is already recorded for this day.');
      return;
    }
    if (_formkey.currentState!.validate()) {
      try {
        final newRecord = await _controller.createDelivery(
          context: context,
          storeName: dropdownHapiStore.text,
          orderAmountText: txtOrderAmount.text,
          selectedDate: _selectedDate,
          imageFile: null,
          placements: listPlacement,
          placementId: placementID,
          sendText: sendText,
          smsMessage: txtSMS.text,
        );

        if (mounted) {
          ShowMessage.success(context, 'Successfully created a new delivery record!\n[${newRecord.storeName}]');
          Navigator.pop(context); // go back to previous page
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Error creating delivery record: $e');
        }
      }
    } else {
      ShowMessage.error(context, 'Please fill up the required fields');
    }
  }

  void onChangeDate() async {
    final DateTime? dateTime = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
    );

    if (dateTime != null) {
      setState(() {
        _selectedDate = dateTime;
      });
      await _checkBreakdownStatus();
    }
  }

  Future<void> _checkBreakdownStatus() async {
    final status = await _controller.checkBreakdownAndVerificationStatus(_selectedDate);
    if (mounted) {
      setState(() {
        hasBreakdownForDay = status.hasBreakdown;
        isDayVerified = status.isVerified;
      });
    }
  }

  void prefetchData() async {
    final dealer = await _controller.checkIsDealer();

    if (widget.deliveryID.isNotEmpty) {
      String imgPath = widget.delivery.imagePath;

      final latest = await _controller.getDeliveryById(widget.deliveryID);
      if (latest != null) {
        if (latest.imagePath.isNotEmpty) {
          imgPath = latest.imagePath;
        }
        if (latest.deliveryDate != null && mounted) {
          _selectedDate = latest.deliveryDate!.toDate();
        }
      }

      await _checkBreakdownStatus();

      final entries = [
        DropdownMenuEntry(label: DeliveryStatus.pending, value: DeliveryStatus.pending),
        DropdownMenuEntry(label: DeliveryStatus.delivered, value: DeliveryStatus.delivered),
        DropdownMenuEntry(label: DeliveryStatus.returned, value: DeliveryStatus.returned),
      ];

      dropdownHapiStore.text = widget.delivery.storeName;
      dropdownStatus.text = widget.delivery.transactionStatus;
      txtRemarks.text = widget.delivery.remarks;
      txtOrderAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.orderAmount);
      txtCashAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.cashAmount);
      txtOnlineAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.onlineAmount);
      txtCreditAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.creditAmount);
      txtReturnAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.returnAmount);

      computeDiscrepancy();

      if (mounted) {
        setState(() {
          isDealer = dealer;
          networkImagePath = imgPath;
          listDropdownStatus = entries;
        });
      }
    } else {
      await _checkBreakdownStatus();
      if (mounted) {
        setState(() {
          isDealer = dealer;
        });
      }
      onStoreSelected();
    }
  }

  void onUpdate() async {
    if (isLocked) {
      final msg = widget.delivery.isReturnApprovedByDealer
          ? 'Editing is locked. This returned order has already been approved by the dealer and cannot be modified.'
          : (widget.delivery.isInventorySettled
              ? 'Editing is locked. This delivery order has already been settled into inventory.'
              : (isDayVerified
                  ? 'Editing is locked. This day\'s cash breakdown has been verified.'
                  : 'Editing is disabled. A cash breakdown is already recorded for this day.'));
      ShowMessage.error(context, msg);
      return;
    }

    if (isDealerLateReconciliation) {
      final confirmReconcile = await ShowMessage.confirm(
        context,
        title: 'Reconcile Late Delivery',
        message:
            'This date\'s cash breakdown has already been verified and closed.\n\n'
            'Updating this order will automatically reconcile and settle inventory movements for these items.\n\n'
            'Do you want to proceed?',
        confirmText: 'Update & Reconcile',
        icon: Icons.sync_problem_outlined,
      );
      if (confirmReconcile != true || !mounted) return;
    }

    final bool hasItemReturns = _withReturns && widget.delivery.items.isNotEmpty && _selectedReturnProductIds.isNotEmpty;
    final double targetOrderAmount = hasItemReturns
        ? (originalOrderTotal - calculatedItemsReturnAmount).clamp(0.0, double.infinity)
        : effectiveOrderAmount;

    final listError = _controller.validateDeliveryForm(
      status: dropdownStatus.text,
      orderAmount: targetOrderAmount,
      cash: txtCashAmount.text,
      online: txtOnlineAmount.text,
      credit: txtCreditAmount.text,
      returnAmount: hasItemReturns
          ? Helperfunctions.formatDoubleAmountForField(calculatedItemsReturnAmount)
          : txtReturnAmount.text,
      remarks: txtRemarks.text,
      withItemReturns: hasItemReturns,
      hasReturnsRecorded: hasItemReturns,
    );

    if (listError.isEmpty) {
      try {
        List<OrderItem>? itemsWithReturns;
        if (widget.delivery.items.isNotEmpty) {
          itemsWithReturns = widget.delivery.items.map((item) {
            final isReturned = hasItemReturns && _selectedReturnProductIds.contains(item.productId);
            final retQty = isReturned ? (_returnQuantities[item.productId] ?? 1) : 0;
            return item.copyWith(returnedQuantity: retQty);
          }).toList();
        }

        final updatedDelivery = await _controller.updateDelivery(
          context: context,
          deliveryId: widget.deliveryID,
          currentDelivery: widget.delivery,
          storeName: dropdownHapiStore.text,
          status: dropdownStatus.text,
          remarks: txtRemarks.text,
          orderAmountText: hasItemReturns
              ? Helperfunctions.formatDoubleAmountForField(targetOrderAmount)
              : txtOrderAmount.text,
          cashAmountText: txtCashAmount.text,
          onlineAmountText: txtOnlineAmount.text,
          creditAmountText: txtCreditAmount.text,
          returnAmountText: hasItemReturns
              ? Helperfunctions.formatDoubleAmountForField(calculatedItemsReturnAmount)
              : txtReturnAmount.text,
          imageFile: null,
          networkImagePath: networkImagePath,
          selectedDate: _selectedDate,
          itemsWithReturns: itemsWithReturns,
        );

        // If this was a late delivery reconciled on a verified date, settle inventory immediately
        if (isDealerLateReconciliation &&
            (dropdownStatus.text == DeliveryStatus.delivered || dropdownStatus.text == DeliveryStatus.returned)) {
          await _controller.settleSingleDelivery(widget.deliveryID);
        }

        if (mounted) {
          final successMsg = isDealerLateReconciliation &&
                  (dropdownStatus.text == DeliveryStatus.delivered || dropdownStatus.text == DeliveryStatus.returned)
              ? 'Successfully updated [${updatedDelivery.storeName}] and reconciled inventory!'
              : 'Successfully updated delivery record!\n[${updatedDelivery.storeName}]';
          ShowMessage.success(context, successMsg);
          Navigator.pop(context); // go back to previous page
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Error updating delivery record: $e');
        }
      }
    } else {
      if (mounted) ShowMessage.listError(context, listError);
    }
  }

  void onDelete() async {
    if (widget.delivery.isReturnApprovedByDealer) {
      ShowMessage.error(context, 'This returned order has already been approved by the dealer and cannot be deleted.');
      return;
    }
    if (widget.delivery.isInventorySettled) {
      ShowMessage.error(context, 'This delivery has been settled into inventory, and cannot be deleted.');
      return;
    }
    if (!isDealer && isDayVerified) {
      ShowMessage.error(context, 'This delivery date has been verified and settled. Only dealers can manage records for this day.');
      return;
    }
    try {
      await _controller.deleteDelivery(context: context, deliveryId: widget.deliveryID, delivery: widget.delivery);

      if (mounted) {
        ShowMessage.success(context, 'Successfully deleted a delivery record!\n[${widget.delivery.storeName}]');
        Navigator.pop(context); // go back to previous page
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Error deleting delivery record: $e');
      }
    }
  }

  void onFocusChange(bool hasFocus, TextEditingController controller) {
    if (controller.text.isNotEmpty) {
      if (!hasFocus) {
        computeDiscrepancy();
        setState(() => controller.text = Helperfunctions.formatStringAmountForDisplay(controller.text));
        onStoreSelected();
      } else {
        setState(() => controller.text = Helperfunctions.formatStringAmountForEditing(controller.text));
      }
    } else {
      if (!hasFocus) {
        computeDiscrepancy();
      }
    }
  }

  void computeDiscrepancy() {
    final bool hasItemReturns = _withReturns && widget.delivery.items.isNotEmpty && _selectedReturnProductIds.isNotEmpty;
    final double targetOrderAmount = hasItemReturns
        ? (originalOrderTotal - calculatedItemsReturnAmount).clamp(0.0, double.infinity)
        : effectiveOrderAmount;

    final result = _controller.computeDiscrepancy(
      orderAmount: targetOrderAmount,
      cash: txtCashAmount.text,
      online: txtOnlineAmount.text,
      credit: txtCreditAmount.text,
      returnAmount: hasItemReturns ? '0' : txtReturnAmount.text,
      withItemReturns: hasItemReturns,
    );
    if (mounted) {
      setState(() {
        discrepancy = result;
      });
    }
  }

  Widget hapistoreDropdown() {
    return HapistorePickerField(
      controller: dropdownHapiStore,
      enabled: isDealer && !isSalesmanLocked,
      label: 'Hapi Store',
      validator: (value) => value == null || value.isEmpty ? 'Please select a Hapi Store' : null,
      onChanged: () {
        onStoreSelected();
      },
    );
  }

  void onStoreSelected() async {
    txtSMS.text = _controller.generateSmsMessage(storeName: dropdownHapiStore.text, formattedOrderAmount: txtOrderAmount.text);

    if (dropdownHapiStore.text.isNotEmpty) {
      final result = await _controller.loadPlacementsForStore(dropdownHapiStore.text);
      if (mounted) {
        setState(() {
          placementID = result.placementId;
          listPlacement = result.placements;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          placementID = '';
          listPlacement = [];
        });
      }
    }
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child, Widget? trailing}) {
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
                  child: Icon(icon, size: 20, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildProofOfDeliveryCard() {
    final imagePath = networkImagePath.trim();
    final colorScheme = Theme.of(context).colorScheme;

    if (imagePath.isEmpty) {
      return _buildSectionCard(
        title: 'Proof of Delivery',
        icon: Icons.image_outlined,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.no_photography_outlined, size: 22, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No Proof of Delivery photo attached.',
                  style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _buildSectionCard(
      title: 'Proof of Delivery',
      icon: Icons.image_outlined,
      trailing: OutlinedButton.icon(
        onPressed: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: null, networkImagePath: imagePath)),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.fullscreen, size: 16),
        label: const Text('View Full Screen'),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: null, networkImagePath: imagePath)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Image.network(
                imagePath,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 200,
                    width: double.infinity,
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 200,
                  width: double.infinity,
                  color: colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined, size: 36, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 6),
                      Text('Unable to load Proof of Delivery image', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.zoom_in, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Tap image to zoom / inspect proof',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderAndStoreCard() {
    return _buildSectionCard(
      title: 'Order & Store Info',
      icon: Icons.storefront_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          hapistoreDropdown(),
          _buildMoneyField(
            label: 'Order Amount',
            controller: txtOrderAmount,
            prefixIcon: Icons.attach_money,
            iconColor: Colors.blue,
            isEnabled: isDealer && !isSalesmanLocked,
          ),
          _buildDatePickerField(
            label: 'Delivery Date',
            selectedDate: _selectedDate,
            isEnabled: isDealer && !isSalesmanLocked,
            onTap: isDealer && !isSalesmanLocked ? onChangeDate : null,
          ),
          if (widget.deliveryID.isNotEmpty) _buildDeliveryStatusSelector(),
        ],
      ),
    );
  }

  Widget _buildDeliveryStatusSelector() {
    String rawStatus = dropdownStatus.text.isNotEmpty ? dropdownStatus.text : DeliveryStatus.pending;
    String currentStatus = rawStatus == DeliveryStatus.pendingPicklist ? DeliveryStatus.pending : rawStatus;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delivery Status',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            segments: [
              ButtonSegment<String>(
                value: DeliveryStatus.pending,
                label: const Text('For Delivery', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                icon: Icon(
                  Icons.local_shipping_outlined,
                  size: 18,
                  color: currentStatus == DeliveryStatus.pending ? Colors.orange.shade800 : colorScheme.onSurfaceVariant,
                ),
              ),
              ButtonSegment<String>(
                value: DeliveryStatus.delivered,
                label: const Text(
                  DeliveryStatus.delivered,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                icon: Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: currentStatus == DeliveryStatus.delivered ? Colors.green.shade800 : colorScheme.onSurfaceVariant,
                ),
              ),
              ButtonSegment<String>(
                value: DeliveryStatus.returned,
                label: const Text(DeliveryStatus.returned, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                icon: Icon(
                  Icons.assignment_return_outlined,
                  size: 18,
                  color: currentStatus == DeliveryStatus.returned ? Colors.red.shade800 : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            selected: {currentStatus},
            onSelectionChanged: isSalesmanLocked
                ? null
                : (Set<String> newSelection) {
                    setState(() {
                      dropdownStatus.text = newSelection.first;
                    });
                  },
          ),
        ),
      ],
    );
  }

  Widget _buildWithReturnsSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildSectionCard(
      title: 'Itemized Returns',
      icon: Icons.assignment_return_outlined,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Text(
          'Total Return: ₱ ${Helperfunctions.formatDoubleAmountForDisplay(calculatedItemsReturnAmount)}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.red.shade800,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            value: _withReturns,
            onChanged: isLocked
                ? null
                : (val) {
                    setState(() {
                      _withReturns = val ?? false;
                      if (!_withReturns) {
                        _selectedReturnProductIds.clear();
                      }
                      computeDiscrepancy();
                    });
                  },
            title: const Text(
              'With Returns',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: const Text(
              'Mark specific products or quantities being returned for this delivery.',
              style: TextStyle(fontSize: 12.5),
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_withReturns) ...[
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Original Order Total:', style: TextStyle(fontSize: 13)),
                      Text(
                        '₱ ${Helperfunctions.formatDoubleAmountForDisplay(originalOrderTotal)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Return Deduction:', style: TextStyle(fontSize: 13, color: Colors.red.shade800)),
                      Text(
                        '- ₱ ${Helperfunctions.formatDoubleAmountForDisplay(calculatedItemsReturnAmount)}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Adjusted Delivered Total:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      Text(
                        '₱ ${Helperfunctions.formatDoubleAmountForDisplay((originalOrderTotal - calculatedItemsReturnAmount).clamp(0.0, double.infinity))}',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Select returned products & quantities:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.delivery.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = widget.delivery.items[index];
                final isSelected = _selectedReturnProductIds.contains(item.productId);
                final currentReturnQty = _returnQuantities[item.productId] ?? 1;
                final maxQty = item.pickedQuantity > 0 ? item.pickedQuantity : item.orderedQuantity;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.red.shade50.withValues(alpha: 0.5) : colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? Colors.red.shade300 : colorScheme.outlineVariant,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        onChanged: isLocked
                            ? null
                            : (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedReturnProductIds.add(item.productId);
                                    if (!_returnQuantities.containsKey(item.productId) || _returnQuantities[item.productId]! <= 0) {
                                      _returnQuantities[item.productId] = 1;
                                    }
                                  } else {
                                    _selectedReturnProductIds.remove(item.productId);
                                  }
                                  computeDiscrepancy();
                                });
                              },
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Picked: $maxQty  ·  ₱${Helperfunctions.formatDoubleAmountForDisplay(item.sellingPrice)} each',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                            if (isSelected)
                              Text(
                                'Delivered: ${maxQty - currentReturnQty}  ·  Return: ₱${Helperfunctions.formatDoubleAmountForDisplay(item.sellingPrice * currentReturnQty)}',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade800),
                              ),
                          ],
                        ),
                      ),
                      if (isSelected) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 20),
                              onPressed: isLocked || currentReturnQty <= 1
                                  ? null
                                  : () {
                                      setState(() {
                                        _returnQuantities[item.productId] = currentReturnQty - 1;
                                        computeDiscrepancy();
                                      });
                                    },
                            ),
                            Text(
                              '$currentReturnQty',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, size: 20),
                              onPressed: isLocked || currentReturnQty >= maxQty
                                  ? null
                                  : () {
                                      setState(() {
                                        _returnQuantities[item.productId] = currentReturnQty + 1;
                                        computeDiscrepancy();
                                      });
                                    },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentBreakdownCard() {
    return _buildSectionCard(
      title: 'Payment Breakdown',
      icon: Icons.payments_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          _buildPaymentSummary(),
          _buildQuickFillChips(),
          _buildMoneyField(
            label: 'Cash Amount',
            controller: txtCashAmount,
            prefixIcon: Icons.payments_outlined,
            iconColor: Colors.green,
            isRequired: false,
            isEnabled: !isSalesmanLocked,
          ),
          _buildMoneyField(
            label: 'Online Amount',
            controller: txtOnlineAmount,
            prefixIcon: Icons.account_balance_outlined,
            iconColor: Colors.blue,
            isRequired: false,
            isEnabled: !isSalesmanLocked,
          ),
          _buildMoneyField(
            label: 'Credit Amount',
            controller: txtCreditAmount,
            prefixIcon: Icons.credit_card_outlined,
            iconColor: Colors.purple,
            isRequired: false,
            isEnabled: !isSalesmanLocked,
          ),
          if (_withReturns && widget.delivery.items.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.assignment_return_outlined, color: Colors.red.shade700, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Calculated Return Amount',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  Text(
                    '₱ ${Helperfunctions.formatDoubleAmountForDisplay(calculatedItemsReturnAmount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.5,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            )
          else
            _buildMoneyField(
              label: 'Return Amount',
              controller: txtReturnAmount,
              prefixIcon: Icons.assignment_return_outlined,
              iconColor: Colors.red,
              isRequired: false,
              isEnabled: !isSalesmanLocked,
            ),
        ],
      ),
    );
  }

  Widget _buildMoneyField({
    required String label,
    required TextEditingController controller,
    required IconData prefixIcon,
    Color? iconColor,
    bool isRequired = true,
    bool isEnabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      onFocusChange: (hasFocus) => onFocusChange(hasFocus, controller),
      child: TextFormField(
        enabled: isEnabled,
        controller: controller,
        textAlign: TextAlign.end,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
        autovalidateMode: AutovalidateMode.onUnfocus,
        onChanged: (_) => computeDiscrepancy(),
        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(prefixIcon, size: 22, color: iconColor ?? colorScheme.primary),
          prefixText: '₱ ',
          prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        validator: (value) {
          if (isRequired) {
            double amount = Helperfunctions.formatStringAmountToDouble(controller.text);
            if (amount <= 0) return '$label should be greater than 0';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildDatePickerField({required String label, required DateTime selectedDate, required VoidCallback? onTap, bool isEnabled = true}) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool canTap = isEnabled && onTap != null;
    return InkWell(
      onTap: canTap ? onTap : (isEnabled ? null : () => ShowMessage.info(context, 'Only dealers can change the delivery date.')),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: canTap ? 1.0 : 0.5)),
          color: canTap ? null : colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined, size: 22, color: canTap ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
                Text(
                  Helperfunctions.formatDateForDisplay(selectedDate),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: canTap ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (canTap)
              Icon(Icons.edit_calendar_outlined, size: 20, color: colorScheme.primary)
            else
              Icon(Icons.lock_outline, size: 18, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFillChips() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt, size: 18, color: Colors.amber[800]),
            const SizedBox(width: 4),
            Text(
              'Quick-Fill Total Order:',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
            children: [
              ActionChip(
                avatar: Icon(Icons.payments_outlined, size: 18, color: colorScheme.primary),
                label: Text(
                  'Full Cash',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                ),
                onPressed: isSalesmanLocked ? null : () => _quickFillPayment(target: 'cash'),
              ),
              ActionChip(
                avatar: Icon(Icons.account_balance_outlined, size: 18, color: colorScheme.primary),
                label: Text(
                  'Full Online',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                ),
                onPressed: isSalesmanLocked ? null : () => _quickFillPayment(target: 'online'),
              ),
              ActionChip(
                avatar: Icon(Icons.credit_card_outlined, size: 18, color: colorScheme.primary),
                label: Text(
                  'Full Credit',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                ),
                onPressed: isSalesmanLocked ? null : () => _quickFillPayment(target: 'credit'),
              ),
              ActionChip(
                avatar: Icon(Icons.restart_alt, size: 18, color: colorScheme.error),
                label: Text(
                  'Clear All',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.error),
                ),
                onPressed: isSalesmanLocked ? null : () => _quickFillPayment(target: 'clear'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _quickFillPayment({required String target}) {
    final bool hasItemReturns = _withReturns && widget.delivery.items.isNotEmpty && _selectedReturnProductIds.isNotEmpty;
    final double targetAmount = hasItemReturns
        ? (originalOrderTotal - calculatedItemsReturnAmount).clamp(0.0, double.infinity)
        : effectiveOrderAmount;
    String formattedOrder = Helperfunctions.formatDoubleAmountForField(targetAmount);

    setState(() {
      txtCashAmount.text = target == 'cash' ? formattedOrder : '';
      txtOnlineAmount.text = target == 'online' ? formattedOrder : '';
      txtCreditAmount.text = target == 'credit' ? formattedOrder : '';
      if (!hasItemReturns) {
        txtReturnAmount.text = '';
      }
      computeDiscrepancy();
    });
  }

  Widget _buildPaymentSummary() {
    final colorScheme = Theme.of(context).colorScheme;
    final bool hasItemReturns = _withReturns && widget.delivery.items.isNotEmpty && _selectedReturnProductIds.isNotEmpty;
    final double targetOrderAmt = hasItemReturns
        ? (originalOrderTotal - calculatedItemsReturnAmount).clamp(0.0, double.infinity)
        : effectiveOrderAmount;
    final double totalCollected = _controller.computeTotalCollected(
      cash: txtCashAmount.text,
      online: txtOnlineAmount.text,
      credit: txtCreditAmount.text,
      returnAmount: hasItemReturns ? '0' : txtReturnAmount.text,
      withItemReturns: hasItemReturns,
    );
    double orderAmt = targetOrderAmt;
    bool isBalanced = discrepancy.abs() < 0.005;
    bool isOver = discrepancy >= 0.005;

    Color badgeColor = isBalanced ? Colors.green : (isOver ? Colors.orange.shade800 : Colors.red.shade700);
    Color bgColor = isBalanced
        ? Colors.green.withValues(alpha: 0.08)
        : (isOver ? Colors.orange.withValues(alpha: 0.08) : Colors.red.withValues(alpha: 0.08));
    Color borderColor = isBalanced ? Colors.green.shade300 : (isOver ? Colors.orange.shade300 : Colors.red.shade300);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        children: [
          // Live Calculation Grid
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Accounted', style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      Helperfunctions.formatDoubleAmountForDisplay(totalCollected),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17.5),
                    ),
                  ],
                ),
              ),
              Container(height: 34, width: 1, color: colorScheme.outlineVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasItemReturns ? 'Target (Delivered)' : 'Target Order Amount',
                      style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(Helperfunctions.formatDoubleAmountForDisplay(orderAmt), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17.5)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          // Status Badge with explanation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(isBalanced ? Icons.check_circle : (isOver ? Icons.error_outline : Icons.warning_amber_rounded), size: 22, color: badgeColor),
                  const SizedBox(width: 6),
                  Text(
                    isBalanced
                        ? 'Balanced'
                        : (isOver
                              ? 'Over by ${Helperfunctions.formatDoubleAmountForDisplay(discrepancy.abs())}'
                              : 'Short by ${Helperfunctions.formatDoubleAmountForDisplay(discrepancy.abs())}'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: badgeColor),
                  ),
                ],
              ),
              if (!isBalanced)
                Text(
                  isOver ? 'Overpaid' : 'Unsettled',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: badgeColor),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRemarksCard() {
    return _buildSectionCard(
      title: 'Remarks & Return Details',
      icon: Icons.note_alt_outlined,
      child: _buildTextAreaField(
        label: 'Remarks',
        controller: txtRemarks,
        prefixIcon: Icons.notes_outlined,
        minLines: 3,
        isEnabled: !isSalesmanLocked,
        isRequired:
            (dropdownStatus.text == DeliveryStatus.returned || (dropdownStatus.text == DeliveryStatus.delivered && txtReturnAmount.text.isNotEmpty)),
      ),
    );
  }

  Widget _buildTextAreaField({
    required String label,
    required TextEditingController controller,
    required IconData prefixIcon,
    int minLines = 3,
    bool isRequired = true,
    bool isEnabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      enabled: isEnabled,
      controller: controller,
      keyboardType: TextInputType.multiline,
      minLines: minLines,
      maxLines: null,
      style: const TextStyle(fontSize: 15.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
        alignLabelWithHint: true,
        prefixIcon: Icon(prefixIcon, size: 22, color: colorScheme.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      autovalidateMode: AutovalidateMode.onUnfocus,
      validator: (value) {
        if (isRequired && (value == null || value.trim().isEmpty)) return '$label should not be blank';
        return null;
      },
    );
  }

  Widget _buildSmsCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildSectionCard(
      title: 'SMS Notification',
      icon: Icons.sms_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Send Text Message?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
              subtitle: const Text('Notify store contact about the pending order', style: TextStyle(fontSize: 13.5)),
              value: sendText,
              onChanged: isSalesmanLocked ? null : (val) => setState(() => sendText = val),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: sendText
                ? Padding(
                    padding: const EdgeInsets.only(top: 14.0),
                    child: _buildTextAreaField(
                      label: 'Text Message',
                      controller: txtSMS,
                      prefixIcon: Icons.message_outlined,
                      minLines: 4,
                      isEnabled: !isSalesmanLocked,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyBottomBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1.0)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: widget.deliveryID.isEmpty
            ? FilledButton.icon(
                onPressed: isSalesmanLocked
                    ? null
                    : () async {
                        final confirmed = await ShowMessage.confirm(
                          context,
                          title: ConfirmTitle.save,
                          message: ConfirmMessage.save,
                          icon: Icons.save_outlined,
                          confirmText: 'Save',
                        );
                        if (confirmed) onSave();
                      },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(isSalesmanLocked ? Icons.lock_outline : Icons.save_outlined),
                label: Text(
                  isSalesmanLocked ? 'Locked (Breakdown Recorded)' : 'Save Delivery Record',
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                ),
              )
            : Row(
                children: [
                  if (isDealer) ...[
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: (isDayVerified || widget.delivery.isInventorySettled || widget.delivery.isReturnApprovedByDealer)
                            ? null
                            : () async {
                                final confirmed = await ShowMessage.confirm(
                                  context,
                                  title: ConfirmTitle.delete,
                                  message: ConfirmMessage.delete,
                                  isDestructive: true,
                                  icon: Icons.delete_outline,
                                  confirmText: 'Delete',
                                );
                                if (confirmed) onDelete();
                              },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 50.0),
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(
                            color: (isDayVerified || widget.delivery.isInventorySettled || widget.delivery.isReturnApprovedByDealer)
                                ? Colors.grey.shade300
                                : Colors.red.shade300,
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 20),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.delivery.isReturnApprovedByDealer
                                ? 'Approved'
                                : ((isDayVerified || widget.delivery.isInventorySettled) ? 'Settled' : 'Delete'),
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: isDealer ? 3 : 1,
                    child: FilledButton.icon(
                      onPressed: isLocked
                          ? null
                          : () async {
                              final confirmed = await ShowMessage.confirm(
                                context,
                                title: ConfirmTitle.update,
                                message: ConfirmMessage.update,
                                icon: Icons.check_circle_outline,
                                confirmText: 'Update',
                              );
                              if (confirmed) onUpdate();
                            },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 50.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(isLocked ? Icons.lock_outline : Icons.check_circle_outline, size: 22),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          widget.delivery.isReturnApprovedByDealer
                              ? 'Locked (Return Approved)'
                              : (widget.delivery.isInventorySettled
                                  ? 'Locked (Inventory Settled)'
                                  : (isLocked
                                      ? 'Locked (Breakdown Verified)'
                                      : (isDealerLateReconciliation
                                          ? 'Reconcile & Update'
                                          : 'Update Delivery'))),
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPlacementCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final placedCount = listPlacement.where((placement) => placement.isPlaced).length;
    final unplacedCount = listPlacement.where((placement) => !placement.isPlaced).length;

    return _buildSectionCard(
      title: 'Placement Checklist',
      icon: Icons.inventory_2_outlined,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (placedCount == 12 ? colorScheme.primary : colorScheme.onSurfaceVariant).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$placedCount/12 placed',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: placedCount == 12 ? colorScheme.primary : colorScheme.onSurfaceVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: listPlacement.isEmpty ? 0 : placedCount / listPlacement.length,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      color: placedCount == 12 ? Colors.green : colorScheme.primary,
                    ),
                  ),
                ),
                if (unplacedCount > 0) ...[
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: isSalesmanLocked
                        ? null
                        : () {
                            setState(() {
                              for (var placement in listPlacement) {
                                placement.isPlaced = true;
                              }
                            });
                          },
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                    icon: const Icon(Icons.done_all_rounded, size: 16),
                    label: const Text('Place All', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: listPlacement.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            itemBuilder: (context, index) {
              final item = listPlacement[index];
              final isPlaced = item.isPlaced;
              final isLocked = item.isPlacedFromDB;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: isLocked
                      ? colorScheme.primary.withValues(alpha: 0.08)
                      : (isPlaced ? colorScheme.primary.withValues(alpha: 0.04) : Colors.transparent),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isLocked
                        ? colorScheme.primary.withValues(alpha: 0.35)
                        : (isPlaced ? colorScheme.primary.withValues(alpha: 0.2) : Colors.transparent),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  onTap: isSalesmanLocked
                      ? null
                      : (isLocked
                            ? () => ShowMessage.error(context, '${item.itemName} is already placed for this month.')
                            : () => setState(() => item.isPlaced = !item.isPlaced)),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      item.itemImagePath,
                      width: 60,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 60,
                        height: 50,
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.image_outlined, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  title: Text(item.itemName, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    isLocked ? 'Locked (saved in DB)' : (isPlaced ? 'Placed and ready' : 'Pending placement'),
                    style: TextStyle(fontSize: 13, color: isPlaced ? colorScheme.primary : colorScheme.onSurfaceVariant),
                  ),
                  trailing: isLocked
                      ? Icon(Icons.lock_outline, size: 20, color: colorScheme.primary)
                      : Checkbox(
                          value: isPlaced,
                          activeColor: colorScheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: isSalesmanLocked
                              ? null
                              : (value) {
                                  setState(() {
                                    item.isPlaced = value ?? false;
                                  });
                                },
                        ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDelivered = dropdownStatus.text == DeliveryStatus.delivered;
    bool isReturned = dropdownStatus.text == DeliveryStatus.returned;
    bool showRemarks = isReturned || (isDelivered && (txtReturnAmount.text.isNotEmpty || (_withReturns && _selectedReturnProductIds.isNotEmpty)));

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Delivery',
        subtitle: widget.deliveryID.isEmpty ? 'New Record' : widget.delivery.storeName,
        actions: [
          if (widget.delivery.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.receipt_long_rounded, color: Colors.white),
              tooltip: 'Digital Receipt & Thermal Print',
              onPressed: () => DigitalReceiptDialog.show(context, delivery: widget.delivery, deliveryId: widget.deliveryID, proceedLabel: 'Close'),
            ),
        ],
      ),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _formkey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                if (isLocked)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: widget.delivery.isReturnApprovedByDealer
                          ? Colors.green.shade50
                          : (widget.delivery.isInventorySettled || isDayVerified ? Colors.red.shade50 : Colors.amber.shade50),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.delivery.isReturnApprovedByDealer
                            ? Colors.green.shade300
                            : (widget.delivery.isInventorySettled || isDayVerified ? Colors.red.shade300 : Colors.amber.shade300),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.delivery.isReturnApprovedByDealer ? Icons.check_circle_outline : Icons.lock_outline,
                          color: widget.delivery.isReturnApprovedByDealer
                              ? Colors.green.shade900
                              : (widget.delivery.isInventorySettled || isDayVerified ? Colors.red.shade900 : Colors.amber.shade900),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.delivery.isReturnApprovedByDealer
                                ? 'Locked: This return order has been approved by the dealer. Returned items have been moved into Current Stock and this record cannot be modified or deleted.'
                                : (widget.delivery.isInventorySettled
                                    ? 'Locked: This delivery order has already been verified and settled into inventory.'
                                    : (isDayVerified
                                        ? 'Locked: The dealer has verified the daily cash breakdown and delivery records for this day are locked for salesmen.'
                                        : 'View-Only: A cash breakdown for this date has already been recorded. Salesmen cannot edit delivery records for this day.')),
                            style: TextStyle(
                              fontSize: 14,
                              color: widget.delivery.isReturnApprovedByDealer
                                  ? Colors.green.shade900
                                  : (widget.delivery.isInventorySettled || isDayVerified ? Colors.red.shade900 : Colors.amber.shade900),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isDealerLateReconciliation)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.amber.shade400,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.amber.shade900,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Late Delivery: This date\'s cash breakdown has already been verified. As a dealer, you can update or reschedule this transaction; saving as Delivered or Returned will automatically reconcile inventory.',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (widget.delivery.isReturnIncoming || widget.delivery.hasReturnedItems || widget.delivery.returnAmount > 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.assignment_return_outlined,
                          color: Color(0xFF0284C7),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pending Dealer Return Approval',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0284C7),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Returned items (₱${Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.returnAmount > 0 ? widget.delivery.returnAmount : widget.delivery.orderAmount)}) are tracked as Incoming Stock until approved into Current Stock by the dealer.',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF0C4A6E)),
                              ),
                            ],
                          ),
                        ),
                        if (isDealer) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => Helperfunctions.navigateTo(
                              context,
                              ReturnPage(recID: widget.deliveryID, delivery: widget.delivery),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF0284C7),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            child: const Text('Review', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                  ),

                if (widget.delivery.transactionStatus == DeliveryStatus.pendingPicklist && widget.deliveryID.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.fact_check_outlined, color: Color(0xFF7C3AED), size: 24),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('This order is Booked (Awaiting Picklist).', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        FilledButton.tonal(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PicklistPage(deliveryID: widget.deliveryID, delivery: widget.delivery),
                              ),
                            );
                          },
                          child: const Text('Open Picklist', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),

                // 1. Order & Store Info Card
                _buildOrderAndStoreCard(),

                // 2. Proof of Delivery Card for reviewing uploaded photo (accessible to all users)
                if (widget.deliveryID.isNotEmpty) _buildProofOfDeliveryCard(),

                // 3. Itemized Returns Section (when Delivered and delivery has items)
                if (widget.deliveryID.isNotEmpty && isDelivered && widget.delivery.items.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _buildWithReturnsSection(),
                  ),

                // 4. Payment Breakdown Card (Animated for Delivered status)
                if (widget.deliveryID.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: isDelivered ? _buildPaymentBreakdownCard() : const SizedBox.shrink(),
                  ),

                // 5. Remarks Card (Animated for Returned or Delivered with return amount)
                if (widget.deliveryID.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: showRemarks ? _buildRemarksCard() : const SizedBox.shrink(),
                  ),

                // 6. Placement Card
                if (widget.deliveryID.isEmpty && dropdownHapiStore.text.isNotEmpty) _buildPlacementCard(),

                // 7. SMS Notification Card (when creating new delivery)
                if (widget.deliveryID.isEmpty) _buildSmsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
