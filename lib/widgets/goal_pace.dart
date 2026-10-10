import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// How demanding a weekly pace is. The bands are a display aid chosen by
/// the developers inside the guideline range (losing 0.5–1 kg a week,
/// NHLBI 1998 and NICE CG189; gaining with a 10–20% surplus, Iraki et al.
/// 2019) so that the recommended pace falls in [balanced]; the limits
/// themselves are applied by HealthCalculator.
enum PaceLevel {
  easy('ง่าย', Icons.spa_outlined, Color(0xFF5DB866)),
  balanced('สมดุล', Icons.verified_outlined, AppColors.teal),
  moderate('ปานกลาง', Icons.trending_up_rounded, Color(0xFFE2A21B)),
  hard('ยาก', Icons.local_fire_department_outlined, AppColors.orange);

  const PaceLevel(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  /// Weekly change (kg) where each level ends, for losing or gaining.
  static List<double> bounds(String goal) =>
      goal == 'gain' ? const [.1, .25, .35, .5] : const [.2, .5, .7, 1.0];

  static PaceLevel of(String goal, double kgPerWeek) {
    final limits = bounds(goal);
    for (final (index, limit) in limits.indexed) {
      if (kgPerWeek <= limit + 1e-9) return values[index];
    }
    return hard;
  }

  String hint(String goal) => switch (this) {
        easy => 'ทำได้สบาย แทบไม่รู้สึกหิว แต่ใช้เวลานาน',
        balanced => goal == 'gain'
            ? 'ความเร็วที่แนะนำ เพิ่มกล้ามเนื้อได้ดี ไขมันเพิ่มไม่มาก'
            : 'ความเร็วที่แนะนำตามแนวทางสากล เห็นผลชัดและทำได้ต่อเนื่อง',
        moderate => goal == 'gain'
            ? 'เพิ่มเร็วขึ้น อาจมีไขมันสะสมเพิ่มขึ้นบ้าง'
            : 'เร็วขึ้น ต้องคุมอาหารมากขึ้น ควรกินโปรตีนให้พอ',
        hard => goal == 'gain'
            ? 'เพิ่มเร็ว อาจได้ไขมันมากกว่ากล้ามเนื้อ'
            : 'ต้องคุมอาหารเข้มงวด อาจหิวบ่อย ควรกินโปรตีนให้พอ',
      };
}

/// "0.5", "0.25", "1" — no trailing zeros.
String formatKgPerWeek(double value) {
  final text = value.toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// A small coloured label for a pace level.
class PaceLevelChip extends StatelessWidget {
  const PaceLevelChip(
      {super.key, required this.level, this.recommended = false});

  final PaceLevel level;
  final bool recommended;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: level.color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(level.icon, size: 14, color: level.color),
          const SizedBox(width: 4),
          Text(recommended ? '${level.label} · แนะนำ' : level.label,
              style: TextStyle(
                  color: level.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ]),
      );
}
