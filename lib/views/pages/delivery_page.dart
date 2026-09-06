import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:another_telephony/telephony.dart';

class DeliveryUpdatePage extends StatefulWidget {
  const DeliveryUpdatePage({
    super.key,
    required this.deliveryID,
    required this.delivery,
  });

  final String deliveryID;
  final Delivery delivery;

  @override
  State<DeliveryUpdatePage> createState() => _DeliveryPageState();
}

class _DeliveryPageState extends State<DeliveryUpdatePage> {
  final DeliveryService db = DeliveryService();
  TextEditingController txtOrderAmount = TextEditingController();
  TextEditingController txtCashAmount = TextEditingController();
  TextEditingController txtOnlineAmount = TextEditingController();
  TextEditingController txtCreditAmount = TextEditingController();
  TextEditingController txtReturnAmount = TextEditingController();
  TextEditingController txtRemarks = TextEditingController();
  TextEditingController txtSMS = TextEditingController();
  TextEditingController dropdownStatus = TextEditingController();
  TextEditingController dropdownHapiStore = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  List<DropdownMenuEntry<String>> listDropdownStatus = [];
  List<DropdownMenuEntry<String>> listDropdownStore = [];
  double discrepancy = 0;
  bool isDealer = true;
  final _formkey = KVariables.formkey;
  File? image;
  final picker = ImagePicker();
  bool isLoading = false;
  String networkImagePath = '';
  bool sendText = false;
  String simDetails = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Delivery'),
      body: isLoading
          ? KForms.loadingScreen
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: SingleChildScrollView(
                child: Form(
                  key: _formkey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 20,
                    children: [
                      hapistoreDropdown(),
                      KForms.txtFormMoney(
                        'Order Amount',
                        txtOrderAmount,
                        (bool hasFocus, TextEditingController controller) =>
                            onFocusChange(hasFocus, controller),
                        isEnabled: isDealer,
                      ),
                      KForms.documentScanner(
                        'Receipt',
                        context,
                        image,
                        networkImagePath,
                        scanDocs,
                        isEnabled: isDealer,
                      ),

                      // If creating a new delivery record
                      if (widget.deliveryID.isEmpty) ...[
                        KForms.datePicker(
                          'Delivery Date',
                          _selectedDate,
                          onChangeDate,
                        ),
                        KForms.switchYesNo(
                          'Send Text Message?',
                          sendText,
                          () => setState(() => sendText = !sendText),
                        ),
                        if (sendText)
                          KForms.txtAreaFormSMS('Text Message', txtSMS),
                        KForms.regularButton(
                          'Save',
                          KButtonStyle.save,
                          () => KForms.alertDialogConfirm(
                            ConfirmTitle.save,
                            ConfirmMessage.save,
                            context,
                            onSave,
                          ),
                        ),
                      ]
                      // if updating an existing delivery record
                      else ...[
                        KForms.dropdown(
                          'Delivery Status',
                          listDropdownStatus,
                          dropdownStatus,
                          onSelected: () => setState(() {}),
                        ),

                        if (dropdownStatus.text ==
                            DeliveryStatus.delivered) ...[
                          KForms.txtFormMoney(
                            'Cash Amount',
                            txtCashAmount,
                            (bool hasFocus, TextEditingController controller) =>
                                onFocusChange(hasFocus, controller),
                            isRequired: false,
                          ),
                          KForms.txtFormMoney(
                            'Online Amount',
                            txtOnlineAmount,
                            (bool hasFocus, TextEditingController controller) =>
                                onFocusChange(hasFocus, controller),
                            isRequired: false,
                          ),
                          KForms.txtFormMoney(
                            'Credit Amount',
                            txtCreditAmount,
                            (bool hasFocus, TextEditingController controller) =>
                                onFocusChange(hasFocus, controller),
                            isRequired: false,
                          ),
                          KForms.txtFormMoney(
                            'Return Amount',
                            txtReturnAmount,
                            (bool hasFocus, TextEditingController controller) =>
                                onFocusChange(hasFocus, controller),
                            isRequired: false,
                          ),

                          KForms.lefRightLabel(
                            'Discrepancy',
                            Helperfunctions.formatDoubleAmountForDisplay(
                              discrepancy,
                            ),
                            rightLabelColor: Colors.red,
                          ),
                        ],

                        if (dropdownStatus.text == DeliveryStatus.delivered ||
                            dropdownStatus.text == DeliveryStatus.returned) ...[
                          KForms.txtAreaFormString(
                            'Remarks',
                            txtRemarks,
                            isRequired:
                                (dropdownStatus.text ==
                                    DeliveryStatus.returned ||
                                (dropdownStatus.text ==
                                        DeliveryStatus.delivered &&
                                    txtReturnAmount.text.isNotEmpty)),
                          ),
                        ],

                        KForms.lastUpdatedByDetails(
                          widget.delivery.createdBy,
                          widget.delivery.createdDate,
                          widget.delivery.lastUpdatedBy,
                          widget.delivery.lastupdatedDate,
                        ),

                        Column(
                          spacing: 5,
                          children: [
                            if (isDealer)
                              KForms.regularButton(
                                'Delete',
                                KButtonStyle.delete,
                                () => KForms.alertDialogConfirm(
                                  ConfirmTitle.delete,
                                  ConfirmMessage.delete,
                                  context,
                                  onDelete,
                                ),
                              ),
                            KForms.regularButton(
                              'Update',
                              KButtonStyle.save,
                              () => KForms.alertDialogConfirm(
                                ConfirmTitle.update,
                                ConfirmMessage.update,
                                context,
                                onUpdate,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  void onSave() async {
    if (_formkey.currentState!.validate()) {
      showLoading(true);

      // save image
      String imageFilePath = '';
      if (image != null) {
        imageFilePath = await Helperfunctions.saveImage(context, image!);
      }

      Delivery newRecord = Delivery(
        storeName: dropdownHapiStore.text,
        remarks: '',
        transactionStatus: DeliveryStatus.pending,
        imagePath: imageFilePath,
        orderAmount: Helperfunctions.formatStringAmountToDouble(
          txtOrderAmount.text,
        ),
        returnAmount: 0,
        creditAmount: 0,
        cashAmount: 0,
        onlineAmount: 0,
        deliveryDate: Timestamp.fromDate(_selectedDate),
        creditStatus: CreditStatus.unpaid,
        createdBy: authService.value.currentUser!.displayName!,
        lastUpdatedBy: authService.value.currentUser!.displayName!,
        createdDate: Timestamp.now(),
        lastupdatedDate: Timestamp.now(),
      );
      db.addDelivery(newRecord);

      // log transaction
      await Helperfunctions.logTransaction(
        '[CREATE] ${dropdownHapiStore.text}',
        'Order Amount: ${Helperfunctions.formatDoubleAmountForDisplay(newRecord.orderAmount)}',
        LogAction.create,
      );

      // send text message to the store if user opted to send a text message
      if (sendText) {
        final dbHs = HapiStoreService();
        String storeContact = await dbHs.getContactByStoreName(
          dropdownHapiStore.text,
        );
        storeContact = storeContact.replaceFirst('09', '+639');

        final Telephony telephony = Telephony.instance;
        bool? permissionsGranted =
            await telephony.requestPhoneAndSmsPermissions;

        if (permissionsGranted ?? false) {
          telephony.sendSms(
            to: storeContact,
            message: txtSMS.text,
            isMultipart: true,
          );
        }
      }

      if (mounted) {
        ShowMessage.success(
          context,
          'Successfully created a new delivery record!\n[${dropdownHapiStore.text}]',
        );
        Navigator.pop(context); // go back to previous page
      }

      showLoading(false);
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
    }
  }

  void prefetchData() async {
    if (widget.deliveryID.isNotEmpty) {
      setState(() => isLoading = true);

      isDealer = await KVariables.getIsDealer();
      networkImagePath = widget.delivery.imagePath;

      listDropdownStatus = [
        DropdownMenuEntry(
          label: DeliveryStatus.pending,
          value: DeliveryStatus.pending,
        ),
        DropdownMenuEntry(
          label: DeliveryStatus.delivered,
          value: DeliveryStatus.delivered,
        ),
        DropdownMenuEntry(
          label: DeliveryStatus.returned,
          value: DeliveryStatus.returned,
        ),
      ];

      dropdownHapiStore.text = widget.delivery.storeName;
      dropdownStatus.text = widget.delivery.transactionStatus;
      txtRemarks.text = widget.delivery.remarks;
      txtOrderAmount.text = widget.delivery.orderAmount == 0
          ? ''
          : Helperfunctions.formatDoubleAmountForDisplay(
              widget.delivery.orderAmount,
            );
      txtCashAmount.text = widget.delivery.cashAmount == 0
          ? ''
          : Helperfunctions.formatDoubleAmountForDisplay(
              widget.delivery.cashAmount,
            );
      txtOnlineAmount.text = widget.delivery.onlineAmount == 0
          ? ''
          : Helperfunctions.formatDoubleAmountForDisplay(
              widget.delivery.onlineAmount,
            );
      txtCreditAmount.text = widget.delivery.creditAmount == 0
          ? ''
          : Helperfunctions.formatDoubleAmountForDisplay(
              widget.delivery.creditAmount,
            );
      txtReturnAmount.text = widget.delivery.returnAmount == 0
          ? ''
          : Helperfunctions.formatDoubleAmountForDisplay(
              widget.delivery.returnAmount,
            );

      computeDiscrepancy();

      setState(() => isLoading = false);
    } else {
      composeSMS();
    }
  }

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

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

  List<String> validate() {
    List<String> listError = [];
    Decimal cashAmount = Helperfunctions.formatStringAmountToDecimal(
      txtCashAmount.text,
    );
    Decimal onlineAmount = Helperfunctions.formatStringAmountToDecimal(
      txtOnlineAmount.text,
    );
    Decimal creditAmount = Helperfunctions.formatStringAmountToDecimal(
      txtCreditAmount.text,
    );
    Decimal returnAmount = Helperfunctions.formatStringAmountToDecimal(
      txtReturnAmount.text,
    );

    Decimal totalAmount =
        cashAmount + onlineAmount + creditAmount + returnAmount;
    Decimal orderAmount = Decimal.parse(widget.delivery.orderAmount.toString());

    if (dropdownStatus.text == DeliveryStatus.delivered &&
        totalAmount != orderAmount) {
      listError.add('Total amount does not match the order amount!');
    }
    if ((returnAmount != Decimal.zero ||
            dropdownStatus.text == DeliveryStatus.returned) &&
        txtRemarks.text.isEmpty) {
      listError.add('Please enter a remark for return details!');
    }

    return listError;
  }

  void onUpdate() async {
    var listError = validate();
    if (listError.isEmpty) {
      showLoading(true);

      double returnAmount = 0;
      double creditAmount = 0;
      double onlineAmount = 0;
      double cashAmount = 0;
      String remark = txtRemarks.text;

      switch (dropdownStatus.text) {
        case DeliveryStatus.pending:
          widget.delivery.orderAmount =
              Helperfunctions.formatStringAmountToDouble(txtOrderAmount.text);
          remark = '';
          break;

        case DeliveryStatus.delivered:
          returnAmount = Helperfunctions.formatStringAmountToDouble(
            txtReturnAmount.text,
          );
          creditAmount = Helperfunctions.formatStringAmountToDouble(
            txtCreditAmount.text,
          );
          onlineAmount = Helperfunctions.formatStringAmountToDouble(
            txtOnlineAmount.text,
          );
          cashAmount = Helperfunctions.formatStringAmountToDouble(
            txtCashAmount.text,
          );
          break;

        case DeliveryStatus.returned:
          returnAmount = widget.delivery.orderAmount;
          break;
        default:
      }

      // update image data
      String imageFilePath = await Helperfunctions.updateImage(
        context,
        image,
        networkImagePath,
        widget.delivery.imagePath,
      );

      Delivery updatedDelivery = widget.delivery.copyWith(
        storeName: dropdownHapiStore.text,
        remarks: remark,
        transactionStatus: dropdownStatus.text,
        imagePath: imageFilePath,
        orderAmount: widget.delivery.orderAmount,
        returnAmount: returnAmount,
        creditAmount: creditAmount,
        cashAmount: cashAmount,
        onlineAmount: onlineAmount,
        deliveryDate: widget.delivery.deliveryDate,
        createdBy: widget.delivery.createdBy,
        lastUpdatedBy: authService.value.currentUser!.displayName!,
        createdDate: widget.delivery.createdDate,
        lastupdatedDate: Timestamp.now(),
      );
      db.updateDelivery(widget.deliveryID, updatedDelivery);

      // log transaction
      await Helperfunctions.logTransaction(
        '[UPDATE] ${dropdownHapiStore.text}',
        'Status: ${updatedDelivery.transactionStatus}\nOrder Amount: ${Helperfunctions.formatDoubleAmountForDisplay(updatedDelivery.orderAmount)}',
        LogAction.update,
      );

      if (mounted) {
        ShowMessage.success(
          context,
          'Successfully updated delivery record!\n[${widget.delivery.storeName}]',
        );
        Navigator.pop(context); // go back to previous page
      }

      showLoading(false);
    } else {
      ShowMessage.listError(context, listError);
    }
  }

  void onDelete() async {
    showLoading(true);
    if (widget.delivery.imagePath.isNotEmpty) {
      await Helperfunctions.deleteImage(context, widget.delivery.imagePath);
    }
    db.deleteDelivery(widget.deliveryID);

    // log transaction
    await Helperfunctions.logTransaction(
      '[DELETE] ${dropdownHapiStore.text}',
      'Order Amount: ${Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.orderAmount)}',
      LogAction.delete,
    );

    if (mounted) {
      ShowMessage.success(
        context,
        'Successfully deleted a delivery record!\n[${widget.delivery.storeName}]',
      );
      Navigator.pop(context); // go back to previous page
    }

    showLoading(false);
  }

  void onFocusChange(bool hasFocus, TextEditingController controller) {
    if (controller.text.isNotEmpty) {
      if (!hasFocus) {
        computeDiscrepancy();
        setState(
          () => controller.text = Helperfunctions.formatStringAmountForDisplay(
            controller.text,
          ),
        );
        composeSMS();
      } else {
        setState(
          () => controller.text = Helperfunctions.formatStringAmountForEditing(
            controller.text,
          ),
        );
      }
    } else {
      if (!hasFocus) {
        setState(() => computeDiscrepancy());
      }
    }
  }

  void computeDiscrepancy() {
    Decimal cashAmount = Helperfunctions.formatStringAmountToDecimal(
      txtCashAmount.text,
    );
    Decimal onlineAmount = Helperfunctions.formatStringAmountToDecimal(
      txtOnlineAmount.text,
    );
    Decimal creditAmount = Helperfunctions.formatStringAmountToDecimal(
      txtCreditAmount.text,
    );
    Decimal returnAmount = Helperfunctions.formatStringAmountToDecimal(
      txtReturnAmount.text,
    );

    Decimal totalAmount =
        cashAmount + onlineAmount + creditAmount + returnAmount;
    Decimal orderAmount = Decimal.parse(widget.delivery.orderAmount.toString());

    discrepancy = (totalAmount - orderAmount).toDouble();

    setState(() {});
  }

  Widget hapistoreDropdown() {
    final HapiStoreService dbHS = HapiStoreService();
    return StreamBuilder(
      stream: dbHS.getListHapiStores(),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        final listHapiStore = snapshot.data?.docs ?? [];
        List<DropdownMenuEntry<String>> listDropdownItems = [];
        for (int i = 0; i < listHapiStore.length; i++) {
          Hapistore hapistore = listHapiStore[i].data();
          listDropdownItems.add(
            DropdownMenuEntry(
              value: hapistore.storeName,
              label: hapistore.storeName,
            ),
          );
        }

        return KForms.dropdown(
          'Hapi Store',
          listDropdownItems,
          dropdownHapiStore,
          isenabled: isDealer,
          onSelected: () => composeSMS(),
        );
      },
    );
  }

  void showLoading(bool showLoading) {
    setState(() {
      isLoading = showLoading;
    });
  }

  void scanDocs(File? scannedImage) {
    setState(() {
      networkImagePath = '';
      scannedImage == null ? image = null : image = scannedImage;
    });
  }

  void composeSMS() async {
    txtSMS.text =
        '[SELECTA DELIVERY]\n\nGood day ${dropdownHapiStore.text}! This is to confirm that your order worth (${txtOrderAmount.text}) is now pending for delivery.\n\nPlease expect your stocks to arrive in a few hours. Thank you for choosing Selecta Ice Cream. Have a sweet day!';
  }
}
