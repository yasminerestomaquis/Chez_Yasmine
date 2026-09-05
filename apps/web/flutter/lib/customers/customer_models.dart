class Customer {
  Customer({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    required this.creditBalance,
    required this.creditLimit,
  });

  final String id;
  final String name;
  final String? phone;
  final String? address;
  final double creditBalance;
  final double creditLimit;

  double get availableCredit => creditLimit - creditBalance;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
        creditBalance: (json['creditBalance'] as num).toDouble(),
        creditLimit: (json['creditLimit'] as num).toDouble(),
      );
}

class CreditHistoryEntry {
  CreditHistoryEntry({required this.type, required this.amount, required this.createdAt, this.saleId});

  final String type; // 'credit' | 'repayment'
  final double amount;
  final DateTime createdAt;
  final String? saleId;

  factory CreditHistoryEntry.fromJson(Map<String, dynamic> json) => CreditHistoryEntry(
        type: json['type'] as String,
        amount: (json['amount'] as num).toDouble(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        saleId: json['saleId'] as String?,
      );
}
