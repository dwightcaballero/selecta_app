class EndOfDayDTO {
  int totaldelivery = 0;
  int pendingstatus = 0;
  int deliveredstatus = 0;
  int returnedstatus = 0;

  double totalorderamount = 0;
  double totaldeliveredamount = 0;
  double cashamount = 0;
  double onlineamount = 0;
  double creditamount = 0;
  double returnedAmount = 0;
  double badorderAmount = 0;
  double expenseAmount = 0;

  double expectedcashonhand = 0;
  double actualcashonhand = 0;
  double discrepancy = 0;
  double bankdeposit = 0;

  EndOfDayDTO({
    required this.totaldelivery,
    required this.pendingstatus,
    required this.deliveredstatus,
    required this.returnedstatus,
    required this.totalorderamount,
    required this.totaldeliveredamount,
    required this.cashamount,
    required this.onlineamount,
    required this.creditamount,
    required this.returnedAmount,
    required this.badorderAmount,
    required this.expenseAmount,
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
    totalorderamount: 0,
    totaldeliveredamount: 0,
    cashamount: 0,
    onlineamount: 0,
    creditamount: 0,
    returnedAmount: 0,
    badorderAmount: 0,
    expenseAmount: 0,
    expectedcashonhand: 0,
    actualcashonhand: 0,
    discrepancy: 0,
    bankdeposit: 0,
  );
}
