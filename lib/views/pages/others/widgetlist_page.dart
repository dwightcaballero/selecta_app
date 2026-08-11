import 'package:flutter/material.dart';

class WidgetListPage extends StatefulWidget {
  const WidgetListPage({
    super.key,
    required this.title});

  final String title;

  @override
  State<WidgetListPage> createState() => _WidgetListPageState();
}

class _WidgetListPageState extends State<WidgetListPage> {
  TextEditingController textEditingController = TextEditingController();
  bool? isChecked = false;
  bool isSwitched = false;
  double sliderValue = 0.0;
  String? dropDownSelected = "1";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Settings"),
        // automaticallyImplyLeading: false, //! to disable the back button
        // leading: BackButton(onPressed: () => Navigator.pop(context),), //! to personalize the back button
      ),
      body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: InputDecoration(border: OutlineInputBorder()),
              controller: textEditingController,
              onEditingComplete: () => setState(() {}),
            ),
            Text(textEditingController.text),
            Checkbox(
              value: isChecked, 
              onChanged: (bool? value) {
                setState(() {
                  isChecked = value;
                });
              },
            ),
            CheckboxListTile(
              title: Text("Click Me!"),
              value: isChecked, 
              onChanged: (bool? value) {
                setState(() {
                  isChecked = value;
                });
              },
            ),
            Switch(
              value: isSwitched, 
              onChanged: (bool value) {
                setState(() {
                  isSwitched = value;
                });
              },
            ),
            SwitchListTile(
              title: Text("Click My Switch!"),
              value: isSwitched, 
              onChanged: (bool value) {
                setState(() {
                  isSwitched = value;
                });
              },
            ),
            Slider(
              value: sliderValue,
              // max: 10,
              // divisions: 10,
              onChanged: (double value) {
                setState(() {
                  sliderValue = value;
                });
              },
            ),
            Text("${((sliderValue*100).toStringAsFixed(0))}%"),
            InkWell(
              splashColor: Colors.red,
              onTap: () {
                // print("color clicked");
              },
              child: Container(
                width: double.infinity,
                height: 200,
                color: Colors.white12
              ),
            ),  
            GestureDetector( 
              child: Image.asset('assets/images/logo.png'),
              onTap: () {
                // print("image clicked");
              },
            ),
            ElevatedButton(onPressed: () => {}, child: Text("Click Me")),
            FilledButton(onPressed: () => {}, child: Text("Click Me")),
            OutlinedButton(onPressed: () => {}, child: Text("Click Me")),
            TextButton(onPressed: () => {}, child: Text("Click Me")),
            BackButton(onPressed: () => {}),
            CloseButton(onPressed: () => {}),
            DropdownButton(
              value: dropDownSelected,
              items: [
                DropdownMenuItem(
                  value: "1",
                  child: Text("Option 1"),
                ),
                DropdownMenuItem(
                  value: "2",
                  child: Text("Option 2"),
                ),
                DropdownMenuItem(
                  value: "3",
                  child: Text("Option 3"),
                ),
              ],
              onChanged: (String? value) {
                setState(() {
                  dropDownSelected = value;
                });
              },
            ),
            // Snack Bar
            ElevatedButton(
              onPressed: () => {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text("This is the snack bar!"),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 3),
                ))
              }, 
              child: Text("Show Snack Bar")
            ),
            Divider(
              color: Colors.red,
              thickness: 5.0,
            ),
            // Alert Dialog
            ElevatedButton(
              onPressed: () => {
                showDialog(context: context, builder: (context) {
                  return AlertDialog(
                    title: Text("Title"),
                    content: Text("Details"),
                    actions: [
                      FilledButton(onPressed: () => Navigator.pop(context), child: Text("Close"))
                    ],
                  );
                },)
              }, 
              child: Text("Show Alert")
            ),
          ],
        ),
      ),
    ),
    );
  }
}