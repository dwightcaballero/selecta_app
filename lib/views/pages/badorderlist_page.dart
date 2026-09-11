import 'package:flutter/material.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/badorder.dart';
import 'package:flutter_app/services/badorder_service.dart';
import 'package:flutter_app/views/pages/badorder_page.dart';
import 'package:flutter_app/views/widgets/container_widget.dart';

class BadOrderlistPage extends StatelessWidget {
  BadOrderlistPage({super.key});

  final BadOrderService db = BadOrderService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('List of Bad Order'),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [_badorderListView(context)]),
          ),
        ),
      ),
      floatingActionButton: floatingActionAddButton(context),
    );
  }

  Widget floatingActionAddButton(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => Helperfunctions.navigateTo(context, BadOrderPage(recID: '', badorder: BadOrder.empty())),
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Icon(Icons.add, color: Colors.white),
    );
  }

  Widget _badorderListView(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.80,
      width: MediaQuery.sizeOf(context).width,

      child: StreamBuilder(
        stream: db.getListBadOrder(),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Something went wrong'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Text("Loading..."));
          if (snapshot.data!.docs.isEmpty) return const Center(child: Text("No results found"));

          List listBadOrder = snapshot.data?.docs;

          return ListView.builder(
            padding: EdgeInsets.only(bottom: 80),
            itemCount: listBadOrder.length,
            itemBuilder: (context, index) {
              BadOrder badorder = listBadOrder[index].data();
              String badorderID = listBadOrder[index].id;

              return InkWell(
                onTap: () => Helperfunctions.navigateTo(context, BadOrderPage(recID: badorderID, badorder: badorder)),
                child: ContainerWidget(
                  title: badorder.hapistore,
                  description1: Helperfunctions.formatTimestampForDisplay(badorder.badorderDate),
                  description2: Helperfunctions.formatDoubleAmountForDisplay(badorder.badorderAmount),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
