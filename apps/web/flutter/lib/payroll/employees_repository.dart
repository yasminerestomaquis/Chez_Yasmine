import '../api/api_client.dart';
import 'employee_models.dart';

/// Correspond à apps/api/nestjs/src/payroll/employees.controller.ts.
class EmployeesRepository {
  EmployeesRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId/employees';

  Future<List<Employee>> listEmployees() async {
    final json = await _api.get(_base) as List<dynamic>;
    return json
        .map((e) => Employee.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<Employee> createEmployee({
    required String lastName,
    required String firstName,
    String? gender,
    DateTime? birthDate,
    required String phone,
    String? address,
    required String position,
    required DateTime hireDate,
    String? contractType,
    required double weeklySalary,
    String? team,
    String? registrationNumber,
    String? notes,
  }) async {
    final json = await _api.post(
      _base,
      body: {
        'lastName': lastName,
        'firstName': firstName,
        'gender': ?gender,
        'birthDate': ?(birthDate != null ? _dateOnly(birthDate) : null),
        'phone': phone,
        'address': ?address,
        'position': position,
        'hireDate': _dateOnly(hireDate),
        'contractType': ?contractType,
        'weeklySalary': weeklySalary,
        'team': ?team,
        'registrationNumber': ?registrationNumber,
        'notes': ?notes,
      },
    ) as Map<String, dynamic>;
    return Employee.fromJson(json);
  }

  Future<Employee> updateEmployee(
    String employeeId,
    Map<String, dynamic> data,
  ) async {
    final json = await _api.patch(
      '$_base/$employeeId',
      body: data,
    ) as Map<String, dynamic>;
    return Employee.fromJson(json);
  }

  Future<Employee> setStatus(String employeeId, String status) =>
      updateEmployee(employeeId, {'status': status});
}
