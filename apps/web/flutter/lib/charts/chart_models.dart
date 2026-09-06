class WeeklyPoint {
  WeeklyPoint({required this.day, required this.value});

  final String day;
  final double value;

  factory WeeklyPoint.fromJson(Map<String, dynamic> json) =>
      WeeklyPoint(day: json['day'] as String, value: (json['value'] as num).toDouble());
}

class WeeklySeries {
  WeeklySeries({required this.id, required this.name, required this.points});

  final String? id;
  final String name;
  final List<WeeklyPoint> points;

  factory WeeklySeries.fromJson(Map<String, dynamic> json) => WeeklySeries(
        id: json['id'] as String?,
        name: json['name'] as String,
        points: (json['points'] as List<dynamic>).map((e) => WeeklyPoint.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class WeeklyChart {
  WeeklyChart({required this.weekStart, required this.weekEnd, required this.series});

  final String weekStart;
  final String weekEnd;
  final List<WeeklySeries> series;

  factory WeeklyChart.fromJson(Map<String, dynamic> json) => WeeklyChart(
        weekStart: json['weekStart'] as String,
        weekEnd: json['weekEnd'] as String,
        series: (json['series'] as List<dynamic>).map((e) => WeeklySeries.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class MonthlyPoint {
  MonthlyPoint({required this.month, required this.value});

  final String month;
  final double value;

  factory MonthlyPoint.fromJson(Map<String, dynamic> json) =>
      MonthlyPoint(month: json['month'] as String, value: (json['value'] as num).toDouble());
}

class MonthlyChart {
  MonthlyChart({required this.year, required this.months});

  final int year;
  final List<MonthlyPoint> months;

  factory MonthlyChart.fromJson(Map<String, dynamic> json) => MonthlyChart(
        year: json['year'] as int,
        months: (json['months'] as List<dynamic>).map((e) => MonthlyPoint.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class RankingItem {
  RankingItem({required this.id, required this.name, required this.value});

  final String? id;
  final String name;
  final double value;

  factory RankingItem.fromJson(Map<String, dynamic> json) => RankingItem(
        id: json['id'] as String?,
        name: json['name'] as String,
        value: (json['value'] as num).toDouble(),
      );
}

class RankingChart {
  RankingChart({required this.from, required this.to, required this.groupBy, required this.items});

  final String from;
  final String to;
  final String groupBy;
  final List<RankingItem> items;

  factory RankingChart.fromJson(Map<String, dynamic> json) => RankingChart(
        from: json['from'] as String,
        to: json['to'] as String,
        groupBy: json['groupBy'] as String,
        items: (json['items'] as List<dynamic>).map((e) => RankingItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
