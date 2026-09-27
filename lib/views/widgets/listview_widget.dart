import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/purchaseorder_controller.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/purchaseorder.dart';
import 'package:flutter_app/views/pages/sidebar/purchaseorder_page.dart';

/// Demo listview widget demonstrating Purchase Order streaming via PurchaseOrderController.
class ListviewWidget extends StatelessWidget {
  const ListviewWidget({super.key});

  static final PurchaseOrderController _controller = PurchaseOrderController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Purchase Order List")),
      body: StreamBuilder<QuerySnapshot>(
        stream: _controller.getPurchaseOrdersStream(),
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No items found."));
          }
          final itemList = snapshot.data?.docs ?? [];

          return ListView.builder(
            itemCount: itemList.length,
            itemBuilder: (context, index) {
              final purchaseorder = itemList[index].data() as Purchaseorder;

              return InkWell(
                onTap: () {
                  Helperfunctions.navigateTo(
                    context,
                    PurchaseorderPage(
                      purchaseorderID: itemList[index].id,
                      purchaseorder: purchaseorder,
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 5.0),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(purchaseorder.orderDate.toString()),
                              Text(purchaseorder.orderAmount.toString()),
                              Text(purchaseorder.overpayment.toString()),
                            ],
                          ),
                          const Spacer(),
                          const Icon(Icons.info, color: Colors.blue),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Helperfunctions.navigateTo(
            context,
            PurchaseorderPage(
              purchaseorderID: "",
              purchaseorder: Purchaseorder.empty(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
