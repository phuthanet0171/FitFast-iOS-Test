import 'package:fitfast/models/health_result.dart';
import 'package:fitfast/services/health_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HealthCalculator weight goals', () {
    dynamic calculate({
      required int age,
      required String goal,
      double? targetWeight,
    }) {
      return HealthCalculator.calculate(
        age: age,
        gender: 'male',
        height: 170,
        weight: 70,
        targetWeight: targetWeight ??
            (goal == 'lose'
                ? 60
                : goal == 'gain'
                    ? 80
                    : 70),
        activity: 'light',
        experience: 'beginner',
        pregnantOrBreastfeeding: false,
        hasDiabetesOrMedication: false,
        hasEatingDisorderHistory: false,
        weightGoal: goal,
      );
    }

    test('adult calorie targets follow lose maintain gain order', () {
      final lose = calculate(age: 25, goal: 'lose');
      final maintain = calculate(age: 25, goal: 'maintain');
      final gain = calculate(age: 25, goal: 'gain');

      expect(lose.calories, lessThan(maintain.calories));
      expect(maintain.calories, closeTo(maintain.tdee, .001));
      expect(gain.calories, greaterThan(maintain.calories));
    });

    test('teen uses maintenance calories and cannot receive IF plan', () {
      final result = calculate(age: 16, goal: 'lose');

      expect(result.weightGoal, 'maintain');
      expect(result.calories, closeTo(result.tdee, .001));
      expect(result.usesTeenSafetyMode, isTrue);
      expect(result.isFastingSuitable, isFalse);
    });

    test('daily sugar limit never exceeds 24 grams', () {
      final result = calculate(age: 25, goal: 'gain');
      expect(result.sugar, lessThanOrEqualTo(24));
    });

    test('the recommended pace is 0.5 kg a week or a 10% surplus', () {
      final lose = calculate(age: 25, goal: 'lose', targetWeight: 65);
      expect(lose.tdee, closeTo(2258.4, .1));
      expect(lose.dailyAdjustment, closeTo(-550, .001));
      expect(lose.calories, closeTo(1708.4, .1));
      // 5 kg x 7,700 kcal / 550 kcal per day = 70 days.
      expect(lose.planDays, 70);
      expect(lose.weeklyChangeKg, closeTo(-.5, .001));

      final gain = calculate(age: 25, goal: 'gain', targetWeight: 75);
      expect(gain.dailyAdjustment, closeTo(225.84, .01));
      expect(gain.planDays, 171);
    });
  });

  group('goal date', () {
    final start = DateTime(2026, 1, 1);

    HealthResult plan({
      required String goal,
      required double target,
      DateTime? date,
      String gender = 'male',
      String activity = 'light',
      double? latest,
    }) =>
        HealthCalculator.calculate(
          age: 25,
          gender: gender,
          height: 170,
          weight: 70,
          targetWeight: target,
          activity: activity,
          experience: 'beginner',
          pregnantOrBreastfeeding: false,
          hasDiabetesOrMedication: false,
          hasEatingDisorderHistory: false,
          weightGoal: goal,
          targetDate: date,
          planStart: start,
          latestWeight: latest,
        );

    test('a chosen date sets the daily deficit', () {
      // 5 kg in 110 days: 5 x 7,700 / 110 = 350 kcal per day.
      final result = plan(
          goal: 'lose', target: 65, date: start.add(const Duration(days: 110)));
      expect(result.dailyAdjustment, closeTo(-350, .001));
      expect(result.targetDate, start.add(const Duration(days: 110)));
      expect(result.targetDateLimited, isFalse);
    });

    test('a date that is too soon uses the fastest pace, 1 kg a week', () {
      final result = plan(
          goal: 'lose', target: 65, date: start.add(const Duration(days: 20)));
      expect(result.targetDateLimited, isTrue);
      expect(result.dailyAdjustment, closeTo(-1100, .001));
      expect(result.planDays, 35);
      expect(result.earliestTargetDate, result.targetDate);
    });

    test('a pace below the calorie floor is allowed but flagged', () {
      final result = plan(
          goal: 'lose', target: 65, date: start.add(const Duration(days: 35)));
      expect(result.calories, closeTo(2258.4375 - 1100, .001));
      expect(
          HealthCalculator.beyondGuideline(
              goal: 'lose', gender: 'male', tdee: result.tdee, perDay: 1100),
          isTrue);
      expect(
          HealthCalculator.beyondGuideline(
              goal: 'lose', gender: 'male', tdee: result.tdee, perDay: 550),
          isFalse);
    });

    test('the recommended loss still keeps intake above the floor', () {
      final woman = plan(goal: 'lose', target: 60, gender: 'female');
      expect(woman.calorieFloor, 1200);
      expect(woman.calories, greaterThanOrEqualTo(1200));
    });

    test('gaining is capped at 0.5 kg a week and flagged above 20%', () {
      final result = plan(
          goal: 'gain', target: 80, date: start.add(const Duration(days: 10)));
      expect(result.dailyAdjustment, closeTo(550, .001));
      expect(result.targetDateLimited, isTrue);
      expect(
          HealthCalculator.beyondGuideline(
              goal: 'gain',
              gender: 'male',
              tdee: result.tdee,
              perDay: result.tdee * .25),
          isTrue);
    });

    test('maintaining has no date', () {
      final result = plan(goal: 'maintain', target: 70);
      expect(result.targetDate, isNull);
      expect(result.calories, closeTo(result.tdee, .001));
    });
    test('energy needs follow the latest weight, the pace stays', () {
      final first = plan(goal: 'lose', target: 65);
      final later = plan(goal: 'lose', target: 65, latest: 68);
      // Mifflin-St Jeor: 2 kg less is 20 kcal less BMR, x 1.375 activity.
      expect(later.tdee, closeTo(first.tdee - 27.5, .001));
      expect(later.dailyAdjustment, closeTo(first.dailyAdjustment, .001));
      expect(later.planDays, first.planDays);
      expect(later.calories, closeTo(first.calories - 27.5, .001));
    });

    test('reaching the goal switches to maintenance', () {
      final result = plan(goal: 'lose', target: 65, latest: 64.8);
      expect(result.dailyAdjustment, 0);
      expect(result.calories, closeTo(result.tdee, .001));
    });
  });
}
