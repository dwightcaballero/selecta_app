import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';

class ReturnPage extends StatefulWidget {
  const ReturnPage({super.key, required this.recID, required this.delivery});

  final String recID;
  final Delivery delivery;

  @override
  State<ReturnPage> createState() => _ReturnPageState();
}

class _ReturnPageState extends State<ReturnPage> {
  DeliveryService db = DeliveryService();
  TextEditingController dropdownController = TextEditingController();
  List<DropdownMenuEntry<String>> listStatus = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Return'),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 20,
          children: [
            Row(
              children: [
                KForms.textTitle('Hapi Store'),
                Spacer(),
                KForms.textDescriptionString(widget.delivery.storeName),
              ],
            ),

            Row(
              children: [
                KForms.textTitle('Return Amount'),
                Spacer(),
                KForms.textDescriptionAmount(widget.delivery.returnAmount),
              ],
            ),

            Row(
              children: [
                KForms.textTitle('Return Date'),
                Spacer(),
                KForms.textDescriptionTimestampDateOnly(
                  widget.delivery.lastupdatedDate,
                ),
              ],
            ),

            KForms.lastUpdatedByDetails(
              widget.delivery.createdBy,
              widget.delivery.createdDate,
              widget.delivery.lastUpdatedBy,
              widget.delivery.lastupdatedDate,
            ),

            Column(
              spacing: 5,
              children: [
                KForms.regularButton(
                  'Redeliver',
                  KButtonStyle.save,
                  () => KForms.alertDialogConfirm(
                    'Redeliver',
                    'Are you sure you want to redeliver this order?',
                    context,
                    onUpdate,
                  ),
                ),

                KForms.regularButton(
                  'Delete',
                  KButtonStyle.delete,
                  () => KForms.alertDialogConfirm(
                    'Delete',
                    'Are you sure you want to delete this order?',
                    context,
                    onDelete,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void onUpdate() async {
    Delivery updatedDelivery = widget.delivery.copyWith(
      storeName: widget.delivery.storeName,
      remarks: '',
      transactionStatus: DeliveryStatus.pending,
      orderAmount: widget.delivery.orderAmount,
      returnAmount: 0,
      creditAmount: widget.delivery.creditAmount,
      cashAmount: widget.delivery.cashAmount,
      onlineAmount: widget.delivery.onlineAmount,
      deliveryDate: Timestamp.now(),
      creditStatus: '',
      createdBy: widget.delivery.createdBy,
      lastUpdatedBy: authService.value.currentUser!.displayName!,
      createdDate: widget.delivery.createdDate,
      lastupdatedDate: Timestamp.now(),
    );
    db.updateDelivery(widget.recID, updatedDelivery);
    ShowMessage.success(
      context,
      'Successfully updated the delivery record!\n[${updatedDelivery.storeName}]',
    );

    Navigator.pop(context); // go back to previous page

    // log transaction
    await Helperfunctions.logTransaction(
      '[UPDATE] ${widget.delivery.storeName}',
      'Status: ${updatedDelivery.transactionStatus}\nOrder Amount: ${Helperfunctions.formatDoubleAmountForDisplay(updatedDelivery.orderAmount)}',
      LogAction.update,
    );
  }

  void onDelete() async {
    db.deleteDelivery(widget.recID);
    ShowMessage.success(
      context,
      'Successfully deleted delivery record!\n[${widget.delivery.storeName}]',
    );

    Navigator.pop(context); // go back to previous page

    // log transaction
    await Helperfunctions.logTransaction(
      '[DELETE] ${widget.delivery.storeName}',
      'Order Amount: ${Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.orderAmount)}',
      LogAction.delete,
    );
  }
}
