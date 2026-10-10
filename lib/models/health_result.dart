class HealthResult {
  const HealthResult({
    required this.bmi,
    required this.bmr,
    required this.tdee,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.sugar,
    required this.sodium,
    required this.recommendedPlan,
    required this.recommendationReason,
    required this.isFastingSuitable,
    required this.weightGoal,
    required this.usesTeenSafetyMode,
    this.dailyAdjustment = 0,
    this.targetDate,
    this.planDays,
    this.weeklyChangeKg,
    this.recommendedTargetDate,
    this.earliestTargetDate,
    this.targetDateLimited = false,
    this.calorieFloor,
  });

  final double bmi;
  final double bmr;
  final double tdee;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double sugar;
  final double sodium;
  final String recommendedPlan;
  final String recommendationReason;
  final bool isFastingSuitable;
  final String weightGoal;
  final bool usesTeenSafetyMode;

  /// kcal per day below (negative) or above (positive) TDEE.
  final double dailyAdjustment;

  /// The day the goal weight is planned for; null when maintaining or when
  /// no safe plan exists (TDEE already at the calorie floor).
  final DateTime? targetDate;

  /// Days from the start of the plan to [targetDate].
  final int? planDays;

  /// Expected change in kg per week (negative when losing).
  final double? weeklyChangeKg;

  /// The date at the recommended pace (500 kcal/day deficit, or a 10%
  /// surplus when gaining).
  final DateTime? recommendedTargetDate;

  /// The earliest date that keeps the plan within the safe limits.
  final DateTime? earliestTargetDate;

  /// True when the chosen date was too soon and the plan uses the earliest
  /// safe date instead.
  final bool targetDateLimited;

  /// Lowest daily calories the plan allows when losing weight.
  final double? calorieFloor;
}
