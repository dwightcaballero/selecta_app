import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/views/widgets/imageviewer_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:toggle_switch/toggle_switch.dart';

class KForms {
  static Text textTitle(String title) {
    return Text(title, style: KTextStyle.titleTextStyle);
  }

  static Text textDescriptionString(String title, {Color color = Colors.black}) {
    return Text(title, style: TextStyle(fontSize: 18, color: color));
  }

  static Text textDescriptionAmount(double amount) {
    return Text(Helperfunctions.formatDoubleAmountForDisplay(amount), style: KTextStyle.descriptionTextStyle);
  }

  static Text textDescriptionTimestamp(Timestamp date) {
    return Text(DateFormat('E, d MMM yyyy, hh:mm a').format(date.toDate()), style: KTextStyle.descriptionTextStyle);
  }

  static Text textDescriptionTimestampDateOnly(Timestamp date) {
    return Text(DateFormat('E, d MMM yyyy').format(date.toDate()), style: KTextStyle.descriptionTextStyle);
  }

  static Text textDescriptionDateTime(DateTime date) {
    return Text(DateFormat('E, d MMM yyyy, hh:mm a').format(date), style: KTextStyle.descriptionTextStyle);
  }

  static TextFormField txtFormString(String label, TextEditingController controller, {bool isRequired = true, bool isenabled = true}) {
    return TextFormField(
      controller: controller,
      enabled: isenabled,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
        labelText: label,
      ),
      autovalidateMode: AutovalidateMode.onUnfocus,
      validator: (value) {
        if (isRequired && (value == null || value.isEmpty)) return '$label should not be blank!';
        return null;
      },
    );
  }

  static InputDecorator txtFieldTitleLabel(String label, String text) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, enabled: false, contentPadding: EdgeInsets.all(15), border: OutlineInputBorder()),
      child: Text(text, style: KTextStyle.descriptionTextStyle),
    );
  }

  static TextFormField txtFormContact(String label, TextEditingController controller, {bool isRequired = true}) {
    return TextFormField(
      controller: controller,
      maxLength: 11,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly, // Limits input strictly to 0-9
      ],
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
        labelText: label,
      ),
      autovalidateMode: AutovalidateMode.onUnfocus,
      validator: (value) {
        if (isRequired && (value == null || value.isEmpty)) return '$label should not be blank';
        if (value!.length != 11) return '$label should consist of 11 digits';

        return null;
      },
    );
  }

  static TextFormField txtFormNumber(String label, TextEditingController controller, {bool isRequired = true, VoidCallback? onEditingComplete}) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly, // Limits input strictly to 0-9
      ],
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
        labelText: label,
      ),
      onTap: onEditingComplete,
      onChanged: (value) => controller.text = value,
      autovalidateMode: AutovalidateMode.onUnfocus,
      validator: (value) {
        if (isRequired && (value == null || value.isEmpty)) return '$label should not be blank';

        return null;
      },
    );
  }

  static Focus txtFormMoney(
    String label,
    TextEditingController controller,
    Function(bool hasFocus, TextEditingController controller) onFocusChange, {
    bool isRequired = true,
    isEnabled = true,
  }) {
    return Focus(
      onFocusChange: (hasFocus) => onFocusChange(hasFocus, controller),
      child: TextFormField(
        enabled: isEnabled,
        controller: controller,
        textAlign: TextAlign.end,
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
          labelText: label,
        ),
        autovalidateMode: AutovalidateMode.onUnfocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),

        inputFormatters: [
          // Allows only numbers and a single dot/comma
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
        ],

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

  static TextFormField txtAreaFormString(String label, TextEditingController controller, {bool isRequired = true}) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.multiline,
      minLines: 3,
      maxLines: null,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
        alignLabelWithHint: true,
        labelText: label,
      ),
      autovalidateMode: AutovalidateMode.onUnfocus,
      validator: (value) {
        if (isRequired && (value == null || value.isEmpty)) return '$label should not be blank';
        return null;
      },
    );
  }

  static TextFormField txtAreaFormSMS(String label, TextEditingController controller, {bool isRequired = true}) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.multiline,
      minLines: 5,
      maxLines: null,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
        alignLabelWithHint: true,
        labelText: label,
      ),
      autovalidateMode: AutovalidateMode.onUnfocus,
      validator: (value) {
        if (isRequired && (value == null || value.isEmpty)) return '$label should not be blank';
        return null;
      },
    );
  }

  static TextFormField txtFormEmail(String label, TextEditingController controller, {bool isRequired = true}) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
        labelText: label,
      ),
      autovalidateMode: AutovalidateMode.onUnfocus,
      validator: (value) {
        if (isRequired && (value == null || value.trim().isEmpty)) '$label should not be blank';

        // Regular expression for email validation
        final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
        if (!emailRegex.hasMatch(value ?? '')) {
          return 'Please enter a valid $label';
        }

        return null; // Return null if the input is valid
      },
    );
  }

  static TextFormField txtFormPassword(String label, TextEditingController controller, bool isObscured, VoidCallback? onEyePressed) {
    return TextFormField(
      controller: controller,
      obscureText: isObscured,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
        labelText: label,
        suffixIcon: IconButton(icon: Icon(isObscured ? Icons.visibility_off : Icons.visibility), onPressed: onEyePressed),
      ),
      autovalidateMode: AutovalidateMode.onUnfocus,
      validator: (value) {
        if (value == null || value.trim().isEmpty) return '$label should not be blank';
        return null; // Return null if the input is valid
      },
    );
  }

  static AppBar appbar(String title) {
    return AppBar(
      backgroundColor: Colors.transparent,
      // 2. Remove default shadows if you want a flat premium look
      elevation: 0,
      // 3. Use flexibleSpace to build the gradient layer
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[Colors.blue, Colors.purple[200]!]),
        ),
      ),
      title: Text(title),
    );
  }

  static Center loadingScreen = Center(child: CircularProgressIndicator());

  static FilledButton regularButton(String title, ButtonStyle style, VoidCallback onPressed) {
    return FilledButton(onPressed: onPressed, style: style, child: Text(title));
  }

  static InputDecorator datePicker(String label, DateTime selectedDate, VoidCallback onChangeDate, {bool isEnabled = true}) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
      ),
      child: Row(
        children: [
          Text(Helperfunctions.formatDateForDisplay(selectedDate), style: KTextStyle.descriptionTextStyle),
          Spacer(),
          FilledButton(onPressed: isEnabled ? onChangeDate : null, child: Text("Choose")),
        ],
      ),
    );
  }

  static DropdownMenuFormField<String> dropdown(
    String label,
    List<DropdownMenuEntry<String>> dropdownItems,
    TextEditingController dropDownController, {
    VoidCallback? onSelected,
    isenabled = true,
  }) {
    return DropdownMenuFormField<String>(
      controller: dropDownController,
      enabled: isenabled,
      initialSelection: dropDownController.text,
      label: Text(label),
      validator: (value) => value == null || value.isEmpty ? 'Please select a $label' : null,
      autovalidateMode: AutovalidateMode.onUnfocus,
      dropdownMenuEntries: dropdownItems,
      enableSearch: true,
      enableFilter: true,
      requestFocusOnTap: true,
      expandedInsets: EdgeInsets.zero,
      menuHeight: 300,
      onSelected: (String? newValue) {
        if (onSelected != null) onSelected();
      },
    );
  }

  static void alertDialogConfirm(String title, String description, BuildContext context, VoidCallback functionIfYes) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            KForms.regularButton('No', KButtonStyle.alertNo, () => Navigator.pop(dialogContext)),
            KForms.regularButton('Yes', KButtonStyle.alertYes, () {
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              functionIfYes();
            }),
          ],
        );
      },
    );
  }

  static Row switchYesNo(String title, bool isToggled, VoidCallback onToggle) {
    return Row(
      children: [
        KForms.textTitle(title),
        Spacer(),
        ToggleSwitch(
          initialLabelIndex: isToggled ? 1 : 0, // Map boolean to index
          totalSwitches: 2,
          labels: ['No', 'Yes'],
          activeBgColors: [
            [Colors.red[300]!],
            [Colors.green[300]!],
          ],
          onToggle: (index) {
            onToggle();
          },
        ),
      ],
    );
  }

  static Row lefRightLabel(String leftLabel, String rightLabel, {Color rightLabelColor = Colors.black, bool withLeftIndent = false}) {
    return Row(
      children: [
        if (withLeftIndent) SizedBox(width: 50.0),
        KForms.textTitle(leftLabel),
        Spacer(),
        KForms.textDescriptionString(rightLabel, color: rightLabelColor),
      ],
    );
  }

  static Column lastUpdatedByDetails(String createdBy, Timestamp createdDate, String lastUpdatedBy, Timestamp lastUpdatedDate) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(),
        Text(
          'Created By: $createdBy\nCreated Date: ${DateFormat('E, d MMM yyyy, hh:mm a').format(createdDate.toDate())}\n\nUpdated By: $lastUpdatedBy\nUpdated Date: ${DateFormat('E, d MMM yyyy, hh:mm a').format(lastUpdatedDate.toDate())}',
          style: KTextStyle.descriptionTextStyle,
        ),
        Divider(),
      ],
    );
  }

  static Row imagePicker(BuildContext context, File? image, String networkImagePath, Function(ImageSource? source) pickImage) {
    bool hasImageData = (image != null || networkImagePath.isNotEmpty);

    return Row(
      spacing: 20,
      children: [
        Container(
          width: 170,
          height: 170,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: hasImageData
              ? InkWell(
                  onTap: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: image, networkImagePath: networkImagePath)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: image != null
                        ? Image.file(image, fit: BoxFit.cover)
                        : Image.network(
                            networkImagePath,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(child: CircularProgressIndicator());
                            },
                          ),
                  ),
                )
              : const Icon(Icons.image, size: 50, color: Colors.grey),
        ),

        Expanded(
          child: Column(
            spacing: 5,
            mainAxisSize: MainAxisSize.min, // Shrinks column vertical height to fit buttons
            crossAxisAlignment: CrossAxisAlignment.stretch, // Makes buttons fill column width
            children: [
              FilledButton.icon(onPressed: () => pickImage(ImageSource.camera), icon: Icon(Icons.camera_alt), label: const Text('Open camera')),
              FilledButton.icon(onPressed: () => pickImage(ImageSource.gallery), icon: Icon(Icons.image_search), label: const Text('Open Gallery')),
              FilledButton.icon(
                onPressed: image == null && networkImagePath.isEmpty ? null : () => pickImage(null),
                style: FilledButton.styleFrom(backgroundColor: Colors.red[300]),
                icon: Icon(Icons.close),
                label: const Text('Remove Photo'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Row documentScanner(
    String title,
    BuildContext context,
    File? image,
    String networkImagePath,
    Function(File? scannedImage) scanDocs, {
    bool isEnabled = true,
  }) {
    bool hasImageData = (image != null || networkImagePath.isNotEmpty);

    return Row(
      spacing: 20,
      children: [
        Container(
          width: 170,
          height: 170,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: hasImageData
              ? InkWell(
                  onTap: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: image, networkImagePath: networkImagePath)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: image != null
                        ? Image.file(image, fit: BoxFit.cover)
                        : Image.network(
                            networkImagePath,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(child: CircularProgressIndicator());
                            },
                          ),
                  ),
                )
              : const Icon(Icons.image, size: 50, color: Colors.grey),
        ),

        Expanded(
          child: Column(
            spacing: 5,
            mainAxisSize: MainAxisSize.min, // Shrinks column vertical height to fit buttons
            crossAxisAlignment: CrossAxisAlignment.stretch, // Makes buttons fill column width
            children: [
              KForms.textTitle(title),
              Divider(),
              FilledButton.icon(
                onPressed: !isEnabled
                    ? null
                    : () async {
                        ImageScanResult? scannedData;
                        try {
                          scannedData = await FlutterDocScanner().getScannedDocumentAsImages(page: 1);
                        } on PlatformException catch (e) {
                          scannedData = null;
                          if (context.mounted) {
                            ShowMessage.error(context, e.message ?? 'There was an error upon scanning a document');
                          }
                        }

                        if (scannedData != null) {
                          String filepath = scannedData.images.first.replaceFirst('file://', '');
                          scanDocs(File(filepath.toString()));
                        } else {
                          scanDocs(null);
                        }
                      },
                style: FilledButton.styleFrom(minimumSize: Size(double.infinity, 50)),
                icon: Icon(Icons.document_scanner),
                label: const Text('Scan Document', textAlign: TextAlign.center),
              ),
              FilledButton.icon(
                onPressed: image == null && networkImagePath.isEmpty && isEnabled
                    ? null
                    : () {
                        image = null;
                        networkImagePath = '';
                        scanDocs(null);
                      },
                style: FilledButton.styleFrom(backgroundColor: Colors.red[300], minimumSize: Size(double.infinity, 50)),
                icon: Icon(Icons.close),
                label: const Text('Remove Document', textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget pieChart({required List<PieChartSectionData> listData, String title = ''}) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: PieChart(
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOutQuint,
            PieChartData(sections: listData),
          ),
        ),
        Text(title),
      ],
    );
  }
}
