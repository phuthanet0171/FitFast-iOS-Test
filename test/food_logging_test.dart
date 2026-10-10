import 'package:fitfast/models/food_item.dart';
import 'package:fitfast/models/health_result.dart';
import 'package:fitfast/models/meal_entry.dart';
import 'package:fitfast/screens/food_screen.dart';
import 'package:fitfast/services/meal_history_service.dart';
import 'package:fitfast/services/nutrition_history_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _food = FoodItem(
  id: 7,
  foodCode: 'T7',
  nameTh: 'ข้าวผัดทดสอบ',
  nameEn: null,
  energyKcalPer100g: 200,
  proteinGPer100g: 8,
  carbsGPer100g: 30,
  fatGPer100g: 6,
  sugarGPer100g: 2,
  sodiumMgPer100g: 400,
);

String _key(DateTime date) => NutritionHistoryService.dateKey(date);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    // No user signs in, so every service works on local storage only.
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() async {
    await MealHistoryService.instance.clear();
    await NutritionHistoryService.instance.clear();
  });

  group('MealEntry', () {
    test('ids stay unique when many entries are created at once', () {
      final ids = {for (var i = 0; i < 500; i++) newMealEntryId(1)};
      expect(ids, hasLength(500));
    });

    test('relog copies the portion to a new id, date and meal', () {
      final original = MealEntry.fromFood(
        food: _food,
        mealType: MealType.lunch,
        grams: 250,
        dateKey: '2026-09-30',
      );
      final copy =
          original.relogAs(dateKey: '2026-10-01', mealType: MealType.dinner);
      expect(copy.id, isNot(original.id));
      expect(copy.dateKey, '2026-10-01');
      expect(copy.mealType, MealType.dinner);
      expect(copy.grams, 250);
      expect(copy.calories, original.calories);
    });
  });

  test('editing the health profile updates the targets of today only',
      () async {
    HealthResult result(double calories) => HealthResult(
          bmi: 24,
          bmr: 1600,
          tdee: 2200,
          calories: calories,
          protein: calories * .25 / 4,
          carbs: calories * .45 / 4,
          fat: calories * .30 / 9,
          sugar: 24,
          sodium: 2000,
          recommendedPlan: '16/8',
          recommendationReason: '',
          isFastingSuitable: true,
          weightGoal: 'lose',
          usesTeenSafetyMode: false,
        );
    final history = NutritionHistoryService.instance;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await history.replaceIntake(
      date: yesterday,
      healthResult: result(1900),
      calories: 1500,
      protein: 80,
      carbs: 200,
      fat: 50,
      sugar: 20,
      sodium: 1500,
      sugarDataComplete: true,
      sodiumDataComplete: true,
    );
    final before = await history.loadOrCreateToday(result(1900));
    expect(before.calorieTarget, 1900);

    // The user lowers the target weight: today follows the new plan.
    final after = await history.loadOrCreateToday(result(1700));
    expect(after.calorieTarget, 1700);
    expect(after.proteinTarget, closeTo(106.25, .001));
    expect((await history.loadOrCreateToday(null)).calorieTarget, 1700);
    // Yesterday keeps the target it was logged against.
    expect((await history.load(yesterday))!.calorieTarget, 1900);
  });

  test('frequent foods rank foods eaten at the same meal first', () async {
    final today = _key(DateTime.now());
    MealEntry log(FoodItem food, MealType meal) => MealEntry.fromFood(
        food: food, mealType: meal, grams: 100, dateKey: today);
    const other = FoodItem(
      id: 8,
      foodCode: 'T8',
      nameTh: 'โจ๊กทดสอบ',
      nameEn: null,
      energyKcalPer100g: 60,
      proteinGPer100g: 2,
      carbsGPer100g: 10,
      fatGPer100g: 1,
      sugarGPer100g: null,
      sodiumMgPer100g: null,
    );
    await MealHistoryService.instance.addAll([
      log(_food, MealType.lunch),
      log(_food, MealType.lunch),
      log(other, MealType.breakfast),
    ]);

    final breakfast = await MealHistoryService.instance
        .loadFrequentFoods(mealType: MealType.breakfast);
    expect(breakfast.map((f) => f.template.foodId), [8, 7]);
    final lunch = await MealHistoryService.instance
        .loadFrequentFoods(mealType: MealType.lunch);
    expect(lunch.first.template.foodId, 7);
    expect(lunch.first.count, 2);
  });

  testWidgets('food tab copies, quick-logs and deletes entries',
      (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await tester.runAsync(() => MealHistoryService.instance.add(
          MealEntry.fromFood(
            food: _food,
            mealType: MealType.lunch,
            grams: 250,
            dateKey: _key(yesterday),
          ),
        ));

    var changes = 0;
    await tester.pumpWidget(MaterialApp(
      home: FoodScreen(onNutritionChanged: () => changes++),
    ));
    await tester.pumpAndSettle();

    // Copy yesterday's lunch into today.
    final copyButton = find.textContaining('คัดลอกจากเมื่อวาน');
    expect(copyButton, findsOneWidget);
    expect(find.textContaining('1 รายการ · 500 kcal'), findsOneWidget);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    expect(find.text('250 ก. · 500 kcal'), findsOneWidget);
    expect(find.text('คัดลอก 1 รายการแล้ว'), findsOneWidget);
    expect(copyButton, findsNothing);
    var today =
        await MealHistoryService.instance.loadDate(_key(DateTime.now()));
    expect(today.single.mealType, MealType.lunch);

    // The undo message closes by itself.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('คัดลอก 1 รายการแล้ว'), findsNothing);

    // The same food is offered as a one-tap chip on the other meals.
    final chips = find.widgetWithText(ActionChip, 'ข้าวผัดทดสอบ · 500');
    expect(chips, findsNWidgets(3));
    await tester.tap(chips.first);
    await tester.pumpAndSettle();
    today = await MealHistoryService.instance.loadDate(_key(DateTime.now()));
    expect(today.map((e) => e.mealType),
        containsAll([MealType.lunch, MealType.breakfast]));

    // Each row has visible edit and delete buttons; delete asks first.
    expect(find.byTooltip('แก้ไขรายการ'), findsNWidgets(2));
    await tester.tap(find.byTooltip('ลบรายการ').first);
    await tester.pumpAndSettle();
    expect(find.text('ลบรายการอาหาร?'), findsOneWidget);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('ลบรายการ'), findsNWidgets(2));

    await tester.tap(find.byTooltip('ลบรายการ').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ลบ'));
    await tester.pumpAndSettle();
    expect(find.text('ลบ ข้าวผัดทดสอบ แล้ว'), findsOneWidget);
    expect(find.byTooltip('ลบรายการ'), findsOneWidget);
    today = await MealHistoryService.instance.loadDate(_key(DateTime.now()));
    expect(today, hasLength(1));

    // Daily totals are saved for the changed date.
    await tester.pumpAndSettle();
    final record = await NutritionHistoryService.instance.load(DateTime.now());
    expect(record?.calories, 500);
    expect(changes, greaterThan(0));

    // Browse back to yesterday.
    await tester.tap(find.byTooltip('วันก่อนหน้า'));
    await tester.pumpAndSettle();
    expect(find.text('เมื่อวาน'), findsOneWidget);
    expect(find.byTooltip('วันถัดไป'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
