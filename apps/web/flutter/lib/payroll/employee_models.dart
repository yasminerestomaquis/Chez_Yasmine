class Employee {
  Employee({
    required this.id,
    required this.lastName,
    required this.firstName,
    this.gender,
    this.birthDate,
    required this.phone,
    this.address,
    this.photoUrl,
    required this.position,
    required this.hireDate,
    this.contractType,
    required this.weeklySalary,
    this.salaryType = 'weekly',
    this.team,
    this.registrationNumber,
    this.notes,
    this.status = 'active',
  });

  final String id;
  final String lastName;
  final String firstName;
  final String? gender;
  final DateTime? birthDate;
  final String phone;
  final String? address;
  final String? photoUrl;
  final String position;
  final DateTime hireDate;
  final String? contractType;

  /// Montant du salaire PAR PÉRIODE : par semaine ou par mois selon
  /// [salaryType] (le nom `weeklySalary` est historique, voir l'API).
  final double weeklySalary;

  /// 'weekly' | 'monthly'.
  final String salaryType;
  final String? team;
  final String? registrationNumber;
  final String? notes;
  final String status;

  String get fullName => '$lastName $firstName';
  bool get isActive => status == 'active';
  bool get isMonthly => salaryType == 'monthly';

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
    id: json['id'] as String,
    lastName: json['lastName'] as String,
    firstName: json['firstName'] as String,
    gender: json['gender'] as String?,
    birthDate: json['birthDate'] != null
        ? DateTime.parse(json['birthDate'] as String)
        : null,
    phone: json['phone'] as String,
    address: json['address'] as String?,
    photoUrl: json['photoUrl'] as String?,
    position: json['position'] as String,
    hireDate: DateTime.parse(json['hireDate'] as String),
    contractType: json['contractType'] as String?,
    weeklySalary: (json['weeklySalary'] as num).toDouble(),
    salaryType: json['salaryType'] as String? ?? 'weekly',
    team: json['team'] as String?,
    registrationNumber: json['registrationNumber'] as String?,
    notes: json['notes'] as String?,
    status: json['status'] as String? ?? 'active',
  );
}
