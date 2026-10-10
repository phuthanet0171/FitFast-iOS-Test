class DailyNutritionRecord {
  const DailyNutritionRecord({
    required this.dateKey,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.sugar,
    required this.sodium,
    required this.calorieTarget,
    required this.proteinTarget,
    required this.carbTarget,
    required this.fatTarget,
    required this.sugarLimit,
    required this.sodiumLimit,
    this.sugarDataComplete = true,
    this.sodiumDataComplete = true,
  });

  final String dateKey;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double sugar;
  final double sodium;
  final double calorieTarget;
  final double proteinTarget;
  final double carbTarget;
  final double fatTarget;
  final double sugarLimit;
  final double sodiumLimit;
  final bool sugarDataComplete;
  final bool sodiumDataComplete;

  bool get hasIntake =>
      calories > 0 ||
      protein > 0 ||
      carbs > 0 ||
      fat > 0 ||
      sugar > 0 ||
      sodium > 0;

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'sugar': sugar,
        'sodium': sodium,
        'calorieTarget': calorieTarget,
        'proteinTarget': proteinTarget,
        'carbTarget': carbTarget,
        'fatTarget': fatTarget,
        'sugarLimit': sugarLimit,
        'sodiumLimit': sodiumLimit,
        'sugarDataComplete': sugarDataComplete,
        'sodiumDataComplete': sodiumDataComplete,
      };

  factory DailyNutritionRecord.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return DailyNutritionRecord(
      dateKey: json['dateKey'] as String? ?? '',
      calories: number('calories'),
      protein: number('protein'),
      carbs: number('carbs'),
      fat: number('fat'),
      sugar: number('sugar'),
      sodium: number('sodium'),
      calorieTarget: number('calorieTarget'),
      proteinTarget: number('proteinTarget'),
      carbTarget: number('carbTarget'),
      fatTarget: number('fatTarget'),
      sugarLimit: number('sugarLimit').clamp(0, 24).toDouble(),
      sodiumLimit: number('sodiumLimit'),
      sugarDataComplete: json['sugarDataComplete'] as bool? ?? true,
      sodiumDataComplete: json['sodiumDataComplete'] as bool? ?? true,
    );
  }

  DailyNutritionRecord copyWith({
    double? calories,
    double? protein,
    double? carbs,
    double? fat,
    double? sugar,
    double? sodium,
    bool? sugarDataComplete,
    bool? sodiumDataComplete,
    double? calorieTarget,
    double? proteinTarget,
    double? carbTarget,
    double? fatTarget,
    double? sugarLimit,
    double? sodiumLimit,
  }) {
    return DailyNutritionRecord(
      dateKey: dateKey,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      sugar: sugar ?? this.sugar,
      sodium: sodium ?? this.sodium,
      calorieTarget: calorieTarget ?? this.calorieTarget,
      proteinTarget: proteinTarget ?? this.proteinTarget,
      carbTarget: carbTarget ?? this.carbTarget,
      fatTarget: fatTarget ?? this.fatTarget,
      sugarLimit: sugarLimit ?? this.sugarLimit,
      sodiumLimit: sodiumLimit ?? this.sodiumLimit,
      sugarDataComplete: sugarDataComplete ?? this.sugarDataComplete,
      sodiumDataComplete: sodiumDataComplete ?? this.sodiumDataComplete,
    );
  }
}
