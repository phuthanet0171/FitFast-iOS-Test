import 'dart:async';

import 'package:flutter/material.dart';

import '../models/health_result.dart';
import '../models/meal_entry.dart';
import '../services/food_catalog_service.dart';
import '../services/food_preference_service.dart';
import '../services/household_units.dart';
import '../services/meal_history_service.dart';
import '../services/nutrition_history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/meal_type_style.dart';
import 'food_amount_screen.dart';
import 'food_search_screen.dart';
import '../widgets/app_snackbar.dart';

class FoodScreen extends StatefulWidget {
  const FoodScreen(
      {super.key, this.healthResult, required this.onNutritionChanged});

  final HealthResult? healthResult;
  final VoidCallback onNutritionChanged;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> with WidgetsBindingObserver {
  static const _thaiMonths = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];

  DateTime _selectedDate = _dateOnly(DateTime.now());
  DateTime _today = _dateOnly(DateTime.now());
  List<MealEntry> _entries = [];
  List<MealEntry> _previousDay = [];
  Map<MealType, List<FrequentFood>> _frequent = {};
  bool _loading = true;
  Timer? _midnightTimer;
  Future<void> _totalsQueue = Future.value();

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String get _dateKey => NutritionHistoryService.dateKey(_selectedDate);
  bool get _isToday => _selectedDate == _dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _scheduleMidnightRefresh();
    // Portions are shown in household units, which come from the catalogue.
    FoodCatalogService.instance.warmUp().then((loaded) {
      if (loaded && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _rollOverIfNewDay();
    _scheduleMidnightRefresh();
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(nextMidnight.difference(now), () {
      _rollOverIfNewDay();
      _scheduleMidnightRefresh();
    });
  }

  /// Keeps "today" pointing at the real date when the app stays open
  /// overnight, without moving a user who is browsing an older date.
  void _rollOverIfNewDay() {
    final today = _dateOnly(DateTime.now());
    if (!mounted || today == _today) return;
    final wasOnToday = _selectedDate == _today;
    _today = today;
    if (wasOnToday) _selectDate(today);
  }

  Future<void> _load({bool refresh = false}) async {
    final dateKey = _dateKey;
    final previousKey = NutritionHistoryService.dateKey(
        _selectedDate.subtract(const Duration(days: 1)));
    final history = MealHistoryService.instance;
    final entries = await history.loadDate(dateKey, refresh: refresh);
    final previous = await history.loadDate(previousKey);
    final frequent = {
      for (final meal in MealType.values)
        meal: await history.loadFrequentFoods(mealType: meal, limit: 8),
    };
    if (!mounted || dateKey != _dateKey) return;
    setState(() {
      _entries = entries;
      _previousDay = previous;
      _frequent = frequent;
      _loading = false;
    });
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = _dateOnly(date);
      _loading = true;
    });
    _load();
  }

  Future<void> _chooseDate() async {
    final today = _dateOnly(DateTime.now());
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(today) ? today : _selectedDate,
      firstDate: DateTime(today.year - 2),
      lastDate: today,
      helpText: 'เลือกวันที่ต้องการบันทึก',
      cancelText: 'ยกเลิก',
      confirmText: 'เลือก',
    );
    if (selected != null) _selectDate(selected);
  }

  String _dateLabel(DateTime date) {
    final today = _dateOnly(DateTime.now());
    if (date == today) return 'วันนี้';
    if (date == today.subtract(const Duration(days: 1))) return 'เมื่อวาน';
    return '${date.day} ${_thaiMonths[date.month - 1]} ${date.year + 543}';
  }

  Future<void> _add(MealType mealType) async {
    final entry = await Navigator.of(context).push<MealEntry>(
      MaterialPageRoute(
        builder: (_) => FoodSearchScreen(
          mealType: mealType,
          dateKey: _dateKey,
          healthResult: widget.healthResult,
        ),
      ),
    );
    if (entry == null) return;
    await MealHistoryService.instance.add(entry);
    await _afterChange(entry.dateKey);
    _showUndo('บันทึก ${entry.foodName} แล้ว', () async {
      await MealHistoryService.instance.delete(entry);
      await _afterChange(entry.dateKey);
    });
  }

  Future<void> _quickAdd(FrequentFood food, MealType mealType) async {
    final entry = food.template.relogAs(dateKey: _dateKey, mealType: mealType);
    await MealHistoryService.instance.add(entry);
    unawaited(FoodPreferenceService.instance
        .addRecent(food.template.toFoodItem())
        .then<void>((_) {}, onError: (Object _) {}));
    await _afterChange(entry.dateKey);
    _showUndo(
      'บันทึก ${entry.foodName} ${entry.calories.round()} kcal แล้ว',
      () async {
        await MealHistoryService.instance.delete(entry);
        await _afterChange(entry.dateKey);
      },
    );
  }

  Future<void> _copyPrevious(MealType mealType) async {
    final dateKey = _dateKey;
    final copies = [
      for (final entry in _previousDay.where((e) => e.mealType == mealType))
        entry.relogAs(dateKey: dateKey, mealType: mealType),
    ];
    if (copies.isEmpty) return;
    await MealHistoryService.instance.addAll(copies);
    await _afterChange(dateKey);
    _showUndo('คัดลอก ${copies.length} รายการแล้ว', () async {
      for (final entry in copies) {
        await MealHistoryService.instance.delete(entry);
      }
      await _afterChange(dateKey);
    });
  }

  Future<void> _edit(MealEntry entry) async {
    final result = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => FoodAmountScreen(
          food: entry.toFoodItem(),
          initialMealType: entry.mealType,
          dateKey: entry.dateKey,
          existingEntry: entry,
          healthResult: widget.healthResult,
        ),
      ),
    );
    if (result == FoodAmountScreen.deleteResult) {
      await _delete(entry);
    } else if (result is MealEntry) {
      await MealHistoryService.instance.update(result);
      await _afterChange(result.dateKey);
      _showMessage('แก้ไข ${result.foodName} แล้ว');
    }
  }

  Future<void> _confirmDelete(MealEntry entry) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('ลบรายการอาหาร?'),
            content:
                Text('ลบ “${entry.foodName}” (${entry.calories.round()} kcal) '
                    'ออกจาก${entry.mealType.label}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  minimumSize: const Size(88, 44),
                ),
                child: const Text('ลบ'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed && mounted) await _delete(entry);
  }

  Future<void> _delete(MealEntry entry) async {
    await MealHistoryService.instance.delete(entry);
    await _afterChange(entry.dateKey);
    _showMessage('ลบ ${entry.foodName} แล้ว');
  }

  /// Refreshes the list, then recalculates the saved daily totals of the
  /// changed date (not necessarily today).
  Future<void> _afterChange(String dateKey) async {
    await _load();
    // Totals are saved in the background, one date at a time, so the list and
    // the undo message appear without waiting for the network.
    _totalsQueue = _totalsQueue
        .then((_) => _syncTotals(dateKey))
        .then<void>((_) {}, onError: (Object _) {});
  }

  Future<void> _syncTotals(String dateKey) async {
    final entries = await MealHistoryService.instance.loadDate(dateKey);
    double sum(double Function(MealEntry) value) =>
        entries.fold<double>(0, (total, item) => total + value(item));
    await NutritionHistoryService.instance.replaceIntake(
      date: DateTime.parse(dateKey),
      healthResult: widget.healthResult,
      calories: sum((item) => item.calories),
      protein: sum((item) => item.protein),
      carbs: sum((item) => item.carbs),
      fat: sum((item) => item.fat),
      sugar: sum((item) => item.sugar),
      sodium: sum((item) => item.sodium),
      sugarDataComplete: entries.every((item) => item.hasSugarData),
      sodiumDataComplete: entries.every((item) => item.hasSodiumData),
    );
    widget.onNutritionChanged();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showAppSnackBar(context, message,
        type: AppMessageType.success, duration: const Duration(seconds: 2));
  }

  void _showUndo(String message, Future<void> Function() undo) {
    if (!mounted) return;
    showAppSnackBar(
      context,
      message,
      type: AppMessageType.success,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(label: 'เลิกทำ', onPressed: () => undo()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final previousLabel = _isToday ? 'เมื่อวาน' : 'วันก่อนหน้า';
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(refresh: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
            children: [
              Text('บันทึกอาหาร',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              _DateSwitcher(
                label: _dateLabel(_selectedDate),
                onPrevious: () => _selectDate(
                    _selectedDate.subtract(const Duration(days: 1))),
                onNext: _selectedDate.isBefore(today)
                    ? () =>
                        _selectDate(_selectedDate.add(const Duration(days: 1)))
                    : null,
                onPick: _chooseDate,
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                for (final meal in MealType.values) ...[
                  _MealCard(
                    type: meal,
                    entries: _entries.where((e) => e.mealType == meal).toList(),
                    frequent: (_frequent[meal] ?? const [])
                        .where((food) => !_entries.any((e) =>
                            e.mealType == meal &&
                            e.foodId == food.template.foodId))
                        .take(5)
                        .toList(),
                    previousDayEntries:
                        _previousDay.where((e) => e.mealType == meal).toList(),
                    previousDayLabel: previousLabel,
                    onAdd: () => _add(meal),
                    onQuickAdd: (food) => _quickAdd(food, meal),
                    onCopyPrevious: () => _copyPrevious(meal),
                    onEdit: _edit,
                    onDelete: _confirmDelete,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DateSwitcher extends StatelessWidget {
  const _DateSwitcher({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Row(children: [
        IconButton.outlined(
          tooltip: 'วันก่อนหน้า',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.calendar_month_rounded, size: 20),
            label: Text(label),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          tooltip: 'วันถัดไป',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ]);
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.type,
    required this.entries,
    required this.frequent,
    required this.previousDayEntries,
    required this.previousDayLabel,
    required this.onAdd,
    required this.onQuickAdd,
    required this.onCopyPrevious,
    required this.onEdit,
    required this.onDelete,
  });

  final MealType type;
  final List<MealEntry> entries;
  final List<FrequentFood> frequent;
  final List<MealEntry> previousDayEntries;
  final String previousDayLabel;
  final VoidCallback onAdd;
  final ValueChanged<FrequentFood> onQuickAdd;
  final VoidCallback onCopyPrevious;
  final ValueChanged<MealEntry> onEdit;
  final ValueChanged<MealEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    final calories =
        entries.fold<double>(0, (sum, item) => sum + item.calories);
    final previousCalories =
        previousDayEntries.fold<double>(0, (sum, item) => sum + item.calories);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: type.color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(15)),
              child: Icon(type.icon, color: type.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.label,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    entries.isEmpty
                        ? 'ยังไม่ได้บันทึก'
                        : '${entries.length} รายการ · ${calories.round()} kcal',
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              onPressed: onAdd,
              tooltip: 'เพิ่ม${type.label}',
              icon: const Icon(Icons.add_rounded),
            ),
          ]),
        ),
        for (final entry in entries)
          InkWell(
            key: ValueKey(entry.id),
            onTap: () => onEdit(entry),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.foodName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '${portionText(entry)} · '
                        '${entry.calories.round()} kcal',
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'แก้ไขรายการ',
                  onPressed: () => onEdit(entry),
                  icon: const Icon(Icons.edit_outlined,
                      color: AppColors.tealDark),
                ),
                IconButton(
                  tooltip: 'ลบรายการ',
                  onPressed: () => onDelete(entry),
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.orange),
                ),
              ]),
            ),
          ),
        if (entries.isEmpty && previousDayEntries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onCopyPrevious,
                icon: const Icon(Icons.content_copy_rounded, size: 18),
                label: Text(
                  'คัดลอกจาก$previousDayLabel · '
                  '${previousDayEntries.length} รายการ · '
                  '${previousCalories.round()} kcal',
                ),
              ),
            ),
          ),
        if (frequent.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('กินบ่อย แตะเพื่อบันทึกทันที',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(children: [
              for (final food in frequent)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      '${_shortName(food.template.foodName)} · '
                      '${food.template.calories.round()}',
                    ),
                    tooltip: '${food.template.foodName} '
                        '${portionText(food.template)} '
                        '${food.template.calories.round()} kcal',
                    onPressed: () => onQuickAdd(food),
                  ),
                ),
            ]),
          ),
        ] else
          const SizedBox(height: 8),
      ]),
    );
  }

  static String _shortName(String name) =>
      name.length <= 18 ? name : '${name.substring(0, 17)}…';
}

/// How much was eaten, in the words used when logging it: "2 ฟอง",
/// "1 จาน · ข้าวน้อย · ไข่ดาว 2 ฟอง" or "3 ส่วนประกอบ".
String portionText(MealEntry entry) {
  if (entry.plateOrder != null) {
    return [
      for (final (index, component) in entry.components.indexed)
        index == 0
            ? component.portion ?? ''
            : '${component.foodName} ${component.portion ?? ''}'.trim(),
    ].join(' · ');
  }
  if (entry.isDetailed) return '${entry.components.length} ส่วนประกอบ';
  final food = FoodCatalogService.instance.cachedFood(entry.foodId);
  return HouseholdUnits.describe(
      food != null && food.foodCode == entry.foodCode
          ? food
          : entry.toFoodItem(),
      entry.grams);
}
