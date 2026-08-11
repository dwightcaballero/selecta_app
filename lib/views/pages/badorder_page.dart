import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/badorder.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/badorder_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';

class BadOrderPage extends StatefulWidget {
  const BadOrderPage({super.key, required this.recID, required this.badorder});

  final String recID;
  final BadOrder badorder;

  @override
  State<BadOrderPage> createState() => _BadOrderPageState();
}

class _BadOrderPageState extends State<BadOrderPage> {
  final BadOrderService db = BadOrderService();
  final HapiStoreService dbHS = HapiStoreService();
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  TextEditingController txtDescription = TextEditingController();
  TextEditingController txtAmount = TextEditingController();
  final TextEditingController dropDownController = TextEditingController();

  @override @override
  void initState() {
    super.initState();
    
    if (widget.recID.isNotEmpty){
      txtDescription.text = widget.badorder.description;
      txtAmount.text = Helperfunctions.formatDoubleAmountForDisplay(widget.badorder.badorderAmount);
      _selectedDate = widget.badorder.badorderDate.toDate();
      dropDownController.text = widget.badorder.hapistore;
    }
  }

  @override
  void dispose() {
    super.dispose();

    txtDescription.dispose();
    txtAmount.dispose();
    dropDownController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Bad Order'),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 20,
              children: [
          
                hapistoreDropdown(),
                KForms.txtFormMoney('Bad Order Amount', txtAmount, (bool hasFocus, TextEditingController controller) => onFocusChange(hasFocus, controller)),
                KForms.datePicker('Bad Order Date', _selectedDate, onChangeDate),
                KForms.txtAreaFormString('Description', txtDescription),

                // If user opens an existing record, 
                if (widget.recID.isNotEmpty)...[
                  KForms.lastUpdatedByDetails(widget.badorder.createdBy, widget.badorder.createdDate,widget.badorder.lastUpdatedBy, widget.badorder.lastupdatedDate),
                  Column(
                    spacing: 5,
                    children: [
                      KForms.regularButton('Delete', KButtonStyle.delete, () => KForms.alertDialogConfirm(ConfirmTitle.delete, ConfirmMessage.delete, context, onDelete)),
                      KForms.regularButton('Update', KButtonStyle.save, () => KForms.alertDialogConfirm(ConfirmTitle.update, ConfirmMessage.update, context, onUpdate))
                    ],
                  )
                ]
            
                // If user creates a new record, show save button
                else...[
                  KForms.regularButton('Save', KButtonStyle.save, () => KForms.alertDialogConfirm(ConfirmTitle.save, ConfirmMessage.save, context, onSave))
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void onSave(){
    if (_formKey.currentState!.validate()){
      BadOrder newRecord = BadOrder(
        description: txtDescription.text, 
        hapistore: dropDownController.text, 
        badorderAmount: Helperfunctions.formatStringAmountToDouble(txtAmount.text), 
        badorderDate: Timestamp.fromDate(_selectedDate),
        createdBy: authService.value.currentUser!.displayName!,
        lastUpdatedBy: authService.value.currentUser!.displayName!,
        createdDate: Timestamp.now(), 
        lastupdatedDate: Timestamp.now()
      );
      db.addBadOrder(newRecord);
      ShowMessage.success(context, 'Successfully created a new bad order record!\n[${dropDownController.text}]');
      Navigator.pop(context); // go back to previous page
    }
    else{
      ShowMessage.error(context, 'Please fill up the required fields');
    }
  }

  void onDelete(){
    db.deleteBadOrder(widget.recID);
    ShowMessage.success(context, 'Successfully deleted bad order record!\n[${widget.badorder.hapistore}]');
    Navigator.pop(context); // go back to previous page
  }

  void onUpdate(){
    if (_formKey.currentState!.validate()){
      BadOrder newRecord = widget.badorder.copyWith(
        description: txtDescription.text, 
        hapistore: dropDownController.text, 
        badorderAmount: Helperfunctions.formatStringAmountToDouble(txtAmount.text), 
        badorderDate: Timestamp.fromDate(_selectedDate),
        createdBy: widget.badorder.createdBy,
        lastUpdatedBy: authService.value.currentUser!.displayName!,
        createdDate: widget.badorder.createdDate,
        lastupdatedDate: Timestamp.now());
      db.updateBadOrder(widget.recID, newRecord);
      ShowMessage.success(context, 'Successfully updated the bad order record!\n[${dropDownController.text }]');
      Navigator.pop(context); // go back to previous page
    }
    else{
      ShowMessage.error(context, 'Please fill up the required fields');
    }
  }

  void onChangeDate() async {
    final DateTime? dateTime = await showDatePicker(
      context: context, 
      initialDate: _selectedDate,
      firstDate: DateTime(2000), 
      lastDate: DateTime(3000));
      
    if (dateTime != null){
      setState(() {
        _selectedDate = dateTime;
      });
    }
  }

  void onFocusChange(bool hasFocus, TextEditingController controller) {
    if (controller.text.isNotEmpty){
      if (!hasFocus){
        setState(() => controller.text = Helperfunctions.formatStringAmountForDisplay(controller.text) );
      }
      else{
       setState(() => controller.text = Helperfunctions.formatStringAmountForEditing(controller.text));
      }
    }
  }

  Widget hapistoreDropdown(){
    return StreamBuilder(
      stream: dbHS.getListHapiStores(), 
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        final listHapiStore = snapshot.data?.docs ?? [];
        List<DropdownMenuEntry<String>> listDropdownItems = [];
        for (int i = 0; i < listHapiStore.length; i++){
          Hapistore hapistore = listHapiStore[i].data();
          listDropdownItems.add(DropdownMenuEntry(value: hapistore.storeName, label: hapistore.storeName));
        }

        return KForms.dropdown('Hapi Store', listDropdownItems, dropDownController);
      },
    );
  }

}