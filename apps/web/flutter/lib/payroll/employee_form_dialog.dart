import 'package:flutter/material.dart';

final _ciPhoneRegex = RegExp(r'^0\d{9}$');

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

/// Formulaire de création d'un employé — champs alignés sur
/// apps/api/nestjs/src/payroll/dto/employee.dto.ts. Retourne un `Map` prêt à
/// passer à `EmployeesRepository.createEmployee`, ou `null` si annulé.
Future<Map<String, dynamic>?> showEmployeeFormDialog(BuildContext context) {
  final lastNameController = TextEditingController();
  final firstNameController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final positionController = TextEditingController();
  final weeklySalaryController = TextEditingController();
  final teamController = TextEditingController();
  final registrationNumberController = TextEditingController();
  final notesController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String? gender;
  DateTime? birthDate;
  var hireDate = DateTime.now();
  String? contractType;

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Ajouter un employé'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: lastNameController,
                    decoration: const InputDecoration(labelText: 'Nom *'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Nom requis';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: firstNameController,
                    decoration: const InputDecoration(labelText: 'Prénoms *'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Prénoms requis';
                      }
                      return null;
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: gender,
                    decoration: const InputDecoration(labelText: 'Sexe'),
                    items: const [
                      DropdownMenuItem(value: 'F', child: Text('Féminin')),
                      DropdownMenuItem(value: 'M', child: Text('Masculin')),
                    ],
                    onChanged: (v) {
                      setDialogState(() => gender = v);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              birthDate ?? DateTime(DateTime.now().year - 25),
                          firstDate: DateTime(1940),
                          lastDate: DateTime.now(),
                          helpText: 'Date de naissance',
                        );
                        if (picked != null) {
                          setDialogState(() => birthDate = picked);
                        }
                      },
                      icon: const Icon(Icons.cake_outlined),
                      label: Text(
                        birthDate == null
                            ? 'Date de naissance (optionnel)'
                            : 'Né(e) le ${_formatDate(birthDate!)}',
                      ),
                    ),
                  ),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone *',
                      hintText: '07 08 09 10 11',
                    ),
                    validator: (v) {
                      final digits = (v ?? '').replaceAll(
                        RegExp(r'[\s.-]'),
                        '',
                      );
                      if (!_ciPhoneRegex.hasMatch(digits)) {
                        return 'Numéro de téléphone invalide (10 chiffres, ex. 0708091011)';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: 'Adresse'),
                  ),
                  TextFormField(
                    controller: positionController,
                    decoration: const InputDecoration(labelText: 'Poste *'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Poste requis';
                      }
                      return null;
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: hireDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          helpText: "Date d'embauche",
                        );
                        if (picked != null) {
                          setDialogState(() => hireDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text("Embauché le ${_formatDate(hireDate)}"),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: contractType,
                    decoration: const InputDecoration(
                      labelText: 'Type de contrat',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cdi', child: Text('CDI')),
                      DropdownMenuItem(value: 'cdd', child: Text('CDD')),
                      DropdownMenuItem(
                        value: 'journalier',
                        child: Text('Journalier'),
                      ),
                    ],
                    onChanged: (v) {
                      setDialogState(() => contractType = v);
                    },
                  ),
                  TextFormField(
                    controller: weeklySalaryController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Salaire hebdomadaire *',
                    ),
                    validator: (v) {
                      final value = double.tryParse(
                        (v ?? '').trim().replaceAll(',', '.'),
                      );
                      if (value == null || value <= 0) {
                        return 'Salaire invalide';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: teamController,
                    decoration: const InputDecoration(
                      labelText: 'Service / Équipe',
                    ),
                  ),
                  TextFormField(
                    controller: registrationNumberController,
                    decoration: const InputDecoration(labelText: 'Matricule'),
                  ),
                  TextFormField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) {
                return;
              }
              Navigator.of(context).pop({
                'lastName': lastNameController.text.trim(),
                'firstName': firstNameController.text.trim(),
                'gender': gender,
                'birthDate': birthDate,
                'phone': phoneController.text.replaceAll(RegExp(r'[\s.-]'), ''),
                'address': addressController.text.trim(),
                'position': positionController.text.trim(),
                'hireDate': hireDate,
                'contractType': contractType,
                'weeklySalary': double.parse(
                  weeklySalaryController.text.trim().replaceAll(',', '.'),
                ),
                'team': teamController.text.trim(),
                'registrationNumber': registrationNumberController.text.trim(),
                'notes': notesController.text.trim(),
              });
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}
