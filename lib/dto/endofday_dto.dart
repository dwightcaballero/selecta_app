import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/return_proof.dart';
import 'package:selecta_ops/models/van_load.dart';

class EndOfDayDTO {
  int totaldelivery = 0;
  int pendingstatus = 0;
  int deliveredstatus = 0;
  int returnedstatus = 0;
  int pendingPicklistStatus = 0;
  int vanSellCount = 0;
  int preSellCount = 0;

  double totalorderamount = 0;
  double totaldeliveredamount = 0;
  double preSellAmount = 0;
  double vanSellAmount = 0;
  double cashamount = 0;
  double onlineamount = 0;
  double creditamount = 0;
  double returnedAmount = 0;
  double expenseAmount = 0; // Total cash expenses deducted from expected cash
  double salesmanExpenseAmount = 0; // Salesman expenses (always cash)
  double dealerExpenseAmount = 0; // Total dealer expenses (cash + online)
  double dealerExpenseCashAmount = 0; // Dealer expenses paid in cash (deducted)
  double dealerExpenseOnlineAmount = 0; // Dealer expenses paid online (not deducted)

  double preSellCashAmount = 0;
  double preSellOnlineAmount = 0;
  double preSellCreditAmount = 0;

  double vanSellCashAmount = 0;
  double vanSellOnlineAmount = 0;
  double vanSellCreditAmount = 0;

  VanLoad? vanLoad;

  double expectedcashonhand = 0;
  double actualcashonhand = 0;
  double discrepancy = 0;
  double bankdeposit = 0;

  List<StoreReturnProofSummary> returnStores = [];
  bool hasUnconfirmedReturnProof = false;

  EndOfDayDTO({
    required this.totaldelivery,
    required this.pendingstatus,
    required this.deliveredstatus,
    required this.returnedstatus,
    this.pendingPicklistStatus = 0,
    required this.totalorderamount,
    required this.totaldeliveredamount,
    this.preSellCount = 0,
    this.preSellAmount = 0,
    this.preSellCashAmount = 0,
    this.preSellOnlineAmount = 0,
    this.preSellCreditAmount = 0,
    this.vanSellCount = 0,
    this.vanSellAmount = 0,
    this.vanSellCashAmount = 0,
    this.vanSellOnlineAmount = 0,
    this.vanSellCreditAmount = 0,
    this.vanLoad,
    required this.cashamount,
    required this.onlineamount,
    required this.creditamount,
    required this.returnedAmount,
    required this.expenseAmount,
    this.salesmanExpenseAmount = 0,
    this.dealerExpenseAmount = 0,
    this.dealerExpenseCashAmount = 0,
    this.dealerExpenseOnlineAmount = 0,
    required this.expectedcashonhand,
    required this.actualcashonhand,
    required this.discrepancy,
    required this.bankdeposit,
    this.returnStores = const [],
    this.hasUnconfirmedReturnProof = false,
  });

  static EndOfDayDTO empty() => EndOfDayDTO(
    totaldelivery: 0,
    pendingstatus: 0,
    deliveredstatus: 0,
    returnedstatus: 0,
    pendingPicklistStatus: 0,
    totalorderamount: 0,
    totaldeliveredamount: 0,
    preSellCount: 0,
    preSellAmount: 0,
    preSellCashAmount: 0,
    preSellOnlineAmount: 0,
    preSellCreditAmount: 0,
    vanSellCount: 0,
    vanSellAmount: 0,
    vanSellCashAmount: 0,
    vanSellOnlineAmount: 0,
    vanSellCreditAmount: 0,
    cashamount: 0,
    onlineamount: 0,
    creditamount: 0,
    returnedAmount: 0,
    expenseAmount: 0,
    salesmanExpenseAmount: 0,
    dealerExpenseAmount: 0,
    dealerExpenseCashAmount: 0,
    dealerExpenseOnlineAmount: 0,
    expectedcashonhand: 0,
    actualcashonhand: 0,
    discrepancy: 0,
    bankdeposit: 0,
    returnStores: const [],
    hasUnconfirmedReturnProof: false,
  );
}

/// Summary of returned goods and proof-of-return status for a store on a given day.
class StoreReturnProofSummary {
  final String storeName;
  final String status; // 'none' | 'submitted' | 'confirmed' | 'rejected' | 'overridden'
  final List<MapEntry<String, Delivery>> deliveriesWithIds;
  final int totalReturnedQty;
  final double totalReturnedAmount;
  final ReturnProof? proof;
  final String? rejectReason;

  const StoreReturnProofSummary({
    required this.storeName,
    required this.status,
    required this.deliveriesWithIds,
    required this.totalReturnedQty,
    required this.totalReturnedAmount,
    this.proof,
    this.rejectReason,
  });

  bool get isSatisfied => ReturnProofStatus.isSatisfied(status);
  bool get isSubmitted => status == ReturnProofStatus.submitted;
  bool get isRejected => status == ReturnProofStatus.rejected;
  bool get isRequired => status == ReturnProofStatus.none || status == ReturnProofStatus.rejected;
}
