import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/models/transactionlog.dart';
import 'package:flutter_app/services/transactionlog_service.dart';
import 'package:intl/intl.dart';

class TransactionLogPage extends StatefulWidget {
  const TransactionLogPage({super.key});

  @override
  State<TransactionLogPage> createState() => _TransactionLogPageState();
}

class _TransactionLogPageState extends State<TransactionLogPage> {
  final TransactionLogService db = TransactionLogService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Logs'),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [_transactionLogListView()],
          ),
        ),
      ),
    );
  }

  Widget _transactionLogListView() {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.80,
      width: MediaQuery.sizeOf(context).width,

      child: StreamBuilder(
        stream: db.getListLogs(),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: Text("Loading..."));
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No results found"));
          }

          List listTransactions = snapshot.data?.docs;

          return ListView.builder(
            padding: EdgeInsets.only(bottom: 80),
            itemCount: listTransactions.length,
            itemBuilder: (context, index) {
              TransactionLog log = listTransactions[index].data();

              return Container(
                width: double.infinity,
                padding: EdgeInsets.only(top: 5.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(log.message, style: KTextStyle.titleTextStyle),
                            Text(
                              log.details,
                              style: KTextStyle.descriptionTextStyle,
                            ),
                            Text(
                              '[${log.loggedRole} ${log.loggedBy}] ${DateFormat('hh:mm a').format(log.loggedDate.toDate())}',
                              style: KTextStyle.descriptionTextStyle,
                            ),
                          ],
                        ),
                        Spacer(),
                        if (log.logAction == LogAction.create) ...[
                          Icon(Icons.add_circle, color: Colors.green, size: 40),
                        ] else if (log.logAction == LogAction.update) ...[
                          Icon(Icons.edit, color: Colors.orange, size: 40),
                        ] else ...[
                          Icon(Icons.delete, color: Colors.red, size: 40),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
