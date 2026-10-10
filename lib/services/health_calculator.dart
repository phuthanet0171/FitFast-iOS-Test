import 'dart:math';

import '../models/health_result.dart';

class HealthCalculator {
  static HealthResult calculate({
    required int age,
    required String gender,
    required double height,
    required double weight,
    double? targetWeight,
    required String activity,
    required String experience,
    required bool pregnantOrBreastfeeding,
    required bool hasDiabetesOrMedication,
    required bool hasEatingDisorderHistory,
    String weightGoal = 'maintain',
    DateTime? targetDate,
    DateTime? planStart,
    double? latestWeight,
  }) {
    // [weight] is the weight the goal plan started from; [latestWeight] is
    // the most recent logged weight. Energy needs follow the latest weight,
    // because TDEE falls as weight is lost (Hall et al., 2011), while the
    // chosen pace and goal date stay those of the plan.
    final nowWeight = latestWeight ?? weight;
    final bmi = nowWeight / pow(height / 100, 2);
    final genderValue = gender == 'male' ? 5 : -161;
    double bmrFor(double kg) =>
        (10 * kg) + (6.25 * height) - (5 * age) + genderValue;
    final bmr = bmrFor(nowWeight);
    final activityFactor = switch (activity) {
      'sedentary' => 1.2,
      'light' => 1.375,
      'moderate' => 1.55,
      'high' => 1.725,
      _ => 1.2,
    };
    final tdee = bmr * activityFactor;
    final planTdee = bmrFor(weight) * activityFactor;
    final usesTeenSafetyMode = age < 18;
    final effectiveGoal = usesTeenSafetyMode ? 'maintain' : weightGoal;
    final goalWeight = targetWeight ?? weight;
    final goalPlan = planGoal(
      goal: effectiveGoal,
      gender: gender,
      tdee: planTdee,
      weight: weight,
      targetWeight: goalWeight,
      planStart: planStart ?? DateTime.now(),
      targetDate: targetDate,
    );
    // Once the latest weight reaches the goal, eat to maintain it.
    final reached = switch (effectiveGoal) {
      'lose' => nowWeight <= goalWeight,
      'gain' => nowWeight >= goalWeight,
      _ => false,
    };
    final dailyAdjustment = reached ? 0.0 : goalPlan.dailyAdjustment;
    final calories = tdee + dailyAdjustment;
    final hasSafetyRisk = age < 18 ||
        bmi < 18.5 ||
        pregnantOrBreastfeeding ||
        hasDiabetesOrMedication ||
        hasEatingDisorderHistory;

    late final String plan;
    late final String reason;
    if (hasSafetyRisk) {
      plan = 'ยังไม่แนะนำให้เริ่ม IF';
      reason = 'พบปัจจัยที่ควรปรึกษาแพทย์หรือนักกำหนดอาหารก่อนเริ่ม IF';
    } else if (experience == 'beginner') {
      plan = '16/8';
      reason =
          'เหมาะสำหรับผู้เริ่มต้น เพราะมีช่วงรับประทาน 8 ชั่วโมงและปรับตัวง่ายกว่า';
    } else if (experience == 'intermediate') {
      plan = '18/6';
      reason =
          'เหมาะกับผู้ที่ทำ 16/8 ได้สม่ำเสมอและต้องการเพิ่มช่วงอดอย่างค่อยเป็นค่อยไป';
    } else {
      plan = '20/4';
      reason = 'เป็นแผนเข้มข้นสำหรับผู้มีประสบการณ์ ควรหยุดเมื่อมีอาการผิดปกติ';
    }

    return HealthResult(
      bmi: bmi,
      bmr: bmr,
      tdee: tdee,
      calories: calories,
      protein: (calories * .25) / 4,
      carbs: (calories * .45) / 4,
      fat: (calories * .30) / 9,
      sugar: ((calories * .10) / 4).clamp(0, 24).toDouble(),
      sodium: 2000,
      recommendedPlan: plan,
      recommendationReason: reason,
      isFastingSuitable: !hasSafetyRisk,
      weightGoal: effectiveGoal,
      usesTeenSafetyMode: usesTeenSafetyMode,
      dailyAdjustment: dailyAdjustment,
      targetDate: goalPlan.targetDate,
      planDays: goalPlan.days,
      weeklyChangeKg: goalPlan.weeklyChangeKg,
      recommendedTargetDate: goalPlan.recommendedDate,
      earliestTargetDate: goalPlan.earliestDate,
      targetDateLimited: goalPlan.limited,
      calorieFloor: effectiveGoal == 'lose' ? goalPlan.floor : null,
    );
  }

  /// Energy in 1 kg of body weight change. The common 7,700 kcal/kg
  /// (3,500 kcal/lb, Wishnofsky 1958) is a static approximation: Hall (2008)
  /// shows it fits people with more body fat, and Hall et al. (2011) show
  /// that metabolic adaptation slows real weight loss over time.
  static const kcalPerKg = 7700.0;

  /// Recommended loss: 0.5 kg a week, the lower end of the 0.5–1 kg a week
  /// that NICE CG189 sets as a target and of the 1–2 lb (0.45–0.9 kg) a week
  /// in NHLBI (1998). At 7,700 kcal/kg this is a 550 kcal/day deficit,
  /// within the 500–750 kcal/day of Jensen et al. (2014).
  static const recommendedLossPerWeek = .5;

  /// Fastest loss the user can choose: 1 kg a week (NICE CG189), a
  /// 1,100 kcal/day deficit. A pace that takes intake below [calorieFloor]
  /// may still be chosen, with a warning.
  static const maxLossPerWeek = 1.0;

  /// Fastest gain the user can choose. A surplus above [maxSurplusShare]
  /// of TDEE may still be chosen, with a warning.
  static const maxGainPerWeek = .5;

  static double get recommendedDeficit =>
      dailyForWeekly(recommendedLossPerWeek);
  static double get maxDeficit => dailyForWeekly(maxLossPerWeek);

  /// Lowest daily intake while losing weight: Jensen et al. (2014) prescribe
  /// 1,200–1,500 kcal/day for women and 1,500–1,800 kcal/day for men.
  static double calorieFloor(String gender) => gender == 'male' ? 1500 : 1200;

  /// Surplus as a share of TDEE when gaining: Iraki et al. (2019) recommend
  /// about 10–20% above maintenance.
  static const recommendedSurplusShare = .10;
  static const maxSurplusShare = .20;

  static const maxPlanDays = 730;

  /// Lowest BMI of the healthy range (WHO); a loss target may not go below
  /// it, and people already below it are not offered weight loss.
  static const minHealthyBmi = 18.5;

  /// Recommended and largest daily change in kcal (both positive) for
  /// losing or gaining weight. The recommended loss keeps intake at or
  /// above [calorieFloor] where possible; the largest is the fastest pace
  /// the user may choose.
  static (double, double) adjustmentLimits({
    required String goal,
    required String gender,
    required double tdee,
  }) {
    final slowest = dailyForWeekly(.1);
    if (goal == 'gain') {
      return (tdee * recommendedSurplusShare, dailyForWeekly(maxGainPerWeek));
    }
    final recommended = min(recommendedDeficit, tdee - calorieFloor(gender));
    return (max(recommended, slowest), maxDeficit);
  }

  /// Whether a daily change goes beyond the guidelines: intake below
  /// [calorieFloor] when losing, or a surplus above [maxSurplusShare] of
  /// TDEE when gaining.
  static bool beyondGuideline({
    required String goal,
    required String gender,
    required double tdee,
    required double perDay,
  }) =>
      goal == 'gain'
          ? perDay > tdee * maxSurplusShare + 1e-6
          : tdee - perDay < calorieFloor(gender) - 1e-6;

  /// kcal per day for a change of [kgPerWeek].
  static double dailyForWeekly(double kgPerWeek) => kgPerWeek * kcalPerKg / 7;

  /// kg per week for a daily change of [kcalPerDay].
  static double weeklyForDaily(double kcalPerDay) => kcalPerDay * 7 / kcalPerKg;

  /// Daily calorie change and timeline for reaching [targetWeight].
  ///
  /// Days to the goal = weight change (kg) × 7,700 ÷ daily adjustment, and,
  /// when a [targetDate] is chosen, daily adjustment = weight change × 7,700
  /// ÷ days, limited to the safe range above.
  static GoalPlan planGoal({
    required String goal,
    required String gender,
    required double tdee,
    required double weight,
    required double targetWeight,
    required DateTime planStart,
    DateTime? targetDate,
  }) {
    final start = DateTime(planStart.year, planStart.month, planStart.day);
    final kg = (targetWeight - weight).abs();
    final floor = calorieFloor(gender);
    if (goal != 'lose' && goal != 'gain' || kg <= 0) {
      return GoalPlan(dailyAdjustment: 0, floor: floor);
    }

    final (recommended, largest) =
        adjustmentLimits(goal: goal, gender: gender, tdee: tdee);

    int daysAt(double perDay) =>
        min(maxPlanDays, (kg * kcalPerKg / perDay).ceil());
    final earliestDays = daysAt(largest);
    final recommendedDays = daysAt(recommended);

    var days = recommendedDays;
    var limited = false;
    if (targetDate != null) {
      final chosen = DateTime(targetDate.year, targetDate.month, targetDate.day)
          .difference(start)
          .inDays;
      if (chosen < earliestDays) {
        days = earliestDays;
        limited = true;
      } else {
        days = min(chosen, maxPlanDays);
      }
    }
    // The recommended and the fastest paces use their exact rate; only a
    // date the user picks sets the rate from the number of days.
    final perDay = targetDate == null || days == recommendedDays
        ? recommended
        : limited || days == earliestDays
            ? largest
            : min(largest, kg * kcalPerKg / days);
    final sign = goal == 'lose' ? -1 : 1;
    return GoalPlan(
      dailyAdjustment: sign * perDay,
      floor: floor,
      days: days,
      targetDate: start.add(Duration(days: days)),
      recommendedDate: start.add(Duration(days: recommendedDays)),
      earliestDate: start.add(Duration(days: earliestDays)),
      weeklyChangeKg: sign * perDay * 7 / kcalPerKg,
      limited: limited,
    );
  }
}

class GoalPlan {
  const GoalPlan({
    required this.dailyAdjustment,
    required this.floor,
    this.days,
    this.targetDate,
    this.recommendedDate,
    this.earliestDate,
    this.weeklyChangeKg,
    this.limited = false,
  });

  final double dailyAdjustment;
  final double floor;
  final int? days;
  final DateTime? targetDate;
  final DateTime? recommendedDate;
  final DateTime? earliestDate;
  final double? weeklyChangeKg;
  final bool limited;
}
