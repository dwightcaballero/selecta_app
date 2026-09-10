import 'package:flutter/material.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/dto/dashboard_dto.dart';

class ThruputPage extends StatelessWidget {
  const ThruputPage({super.key, required this.dashboardDTO});
  final DashboardDTO dashboardDTO;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('KPI - Thruput'),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          spacing: 20,
          children: [
            KForms.lefRightLabel('Total No. of Stores : ', '${dashboardDTO.buyingCount + dashboardDTO.nonBuyingCount}'),
            KForms.lefRightLabel('Buying Stores : ', '${dashboardDTO.buyingCount}', withLeftIndent: true, rightLabelColor: Colors.green),
            KForms.lefRightLabel('Non Buying Stores : ', '${dashboardDTO.nonBuyingCount}', withLeftIndent: true, rightLabelColor: Colors.red),
            Divider(),
            KForms.lefRightLabel('Sales of Buying Stores: ', Helperfunctions.formatDoubleAmountForDisplay(dashboardDTO.totalBuyingSales)),
            KForms.lefRightLabel('Transaction Count: ', '${dashboardDTO.totaltransactionCount}'),
            KForms.lefRightLabel(
              'AVG Sale per Transaction:',
              Helperfunctions.formatDoubleAmountForDisplay(dashboardDTO.totalBuyingSales / dashboardDTO.totaltransactionCount),
            ),
            KForms.lefRightLabel('AVG Transaction per Store:', (dashboardDTO.totaltransactionCount / dashboardDTO.buyingCount).toStringAsFixed(2)),
            Divider(),
            KForms.lefRightLabel('Target Thruput: ', Helperfunctions.formatDoubleAmountForDisplay(8000)),
            KForms.lefRightLabel(
              'Actual Thruput: ',
              Helperfunctions.formatDoubleAmountForDisplay(dashboardDTO.buyingThruput),
              withLeftIndent: true,
              rightLabelColor: Colors.green,
            ),
            KForms.lefRightLabel(
              'Missing Thruput: ',
              Helperfunctions.formatDoubleAmountForDisplay(8000 - dashboardDTO.buyingThruput),
              withLeftIndent: true,
              rightLabelColor: Colors.red,
            ),
          ],
        ),
      ),
    );
  }
}
