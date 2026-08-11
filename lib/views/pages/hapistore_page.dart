import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';

class HapiStorePage extends StatefulWidget {
  const HapiStorePage({super.key, required this.hapiStoreID, required this.hapistore});
  final String hapiStoreID;
  final Hapistore hapistore;

  @override
  State<HapiStorePage> createState() => _HapiStorePageState();
}

class _HapiStorePageState extends State<HapiStorePage> {
  final HapiStoreService db = HapiStoreService();
  TextEditingController txtName = TextEditingController();
  TextEditingController txtAddress = TextEditingController();
  TextEditingController txtContact = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();

    if (widget.hapiStoreID.isNotEmpty){
      txtName = TextEditingController(text: widget.hapistore.storeName);
      txtAddress = TextEditingController(text: widget.hapistore.storeAddress);
      txtContact = TextEditingController(text: widget.hapistore.storeContact);
    }
  }

  @override
  void dispose() {
    super.dispose();

    txtName.dispose();
    txtContact.dispose();
    txtAddress.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Hapi Store'),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 15,
              children: [
            
                KForms.txtFormString('Store Name', txtName),
                KForms.txtFormContact('Contact Number', txtContact),
                KForms.txtFormString('Address', txtAddress),
            
                // If user opens an existing store, show update and delete button
                if (widget.hapiStoreID.isNotEmpty)...[
                  //KForms.lastUpdatedByDetails(widget.hapistore.createdBy, widget.hapistore.createdDate,widget.hapistore.lastUpdatedBy, widget.hapistore.lastupdatedDate),

                  Column(
                    spacing: 5,
                    children: [
                      KForms.regularButton('Delete', KButtonStyle.delete, () => KForms.alertDialogConfirm(ConfirmTitle.delete, ConfirmMessage.delete, context, onDelete)),
                      KForms.regularButton('Update', KButtonStyle.save, () => KForms.alertDialogConfirm(ConfirmTitle.update, ConfirmMessage.update, context, onUpdate))
                    ],
                  )
                ],
            
                // If user creates a new store, show save button
                if (widget.hapiStoreID.isEmpty)...[
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
      Hapistore newHs = Hapistore(storeName: txtName.text.toUpperCase(), storeAddress: txtAddress.text, storeContact: txtContact.text);
      db.addHapiStore(newHs);
      ShowMessage.success(context, 'Successfully created a new hapi store!\n[${newHs.storeName}]');
      Navigator.pop(context); // go back to previous page
    }
    else{
      ShowMessage.error(context, 'Please fill up the required fields');
    }
  }

  void onUpdate(){
    if (_formKey.currentState!.validate()){
      Hapistore updatedHS = widget.hapistore.copyWith(storeName: txtName.text.toUpperCase(), storeAddress: txtAddress.text, storeContact: txtContact.text);
      db.updateHapiStore(widget.hapiStoreID, updatedHS);
      ShowMessage.success(context, 'Successfully updated the hapi store!\n[${updatedHS.storeName}]');
      Navigator.pop(context); // go back to previous page
    }
    else{
      ShowMessage.error(context, 'Please fill up the required fields');
    }
  }

  void onDelete(){
    db.deleteHapiStore(widget.hapiStoreID);
    ShowMessage.success(context, 'Successfully deleted hapi store!\n[${widget.hapistore.storeName}]');
    Navigator.pop(context); // go back to previous page
  }
}