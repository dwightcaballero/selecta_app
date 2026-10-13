class EndOfDayDTO {
  int totaldelivery = 0;
  int pendingstatus = 0;
  int deliveredstatus = 0;
  int returnedstatus = 0;
  int pendingPicklistStatus = 0;

  double totalorderamount = 0;
  double totaldeliveredamount = 0;
  double cashamount = 0;
  double onlineamount = 0;
  double creditamount = 0;
  double returnedAmount = 0;
  double expenseAmount = 0; // Total cash expenses deducted from expected cash
  double salesmanExpenseAmount = 0; // Salesman expenses (always cash)
  double dealerExpenseAmount = 0; // Total dealer expenses (cash + online)
  double dealerExpenseCashAmount = 0; // Dealer expenses paid in cash (deducted)
  double dealerExpenseOnlineAmount = 0; // Dealer expenses paid online (not deducted)

  double expectedcashonhand = 0;
  double actualcashonhand = 0;
  double discrepancy = 0;
  double bankdeposit = 0;

  EndOfDayDTO({
    required this.totaldelivery,
    required this.pendingstatus,
    required this.deliveredstatus,
    required this.returnedstatus,
    this.pendingPicklistStatus = 0,
    required this.totalorderamount,
    required this.totaldeliveredamount,
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
  });

  static EndOfDayDTO empty() => EndOfDayDTO(
    totaldelivery: 0,
    pendingstatus: 0,
    deliveredstatus: 0,
    returnedstatus: 0,
    pendingPicklistStatus: 0,
    totalorderamount: 0,
    totaldeliveredamount: 0,
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
  );
}
