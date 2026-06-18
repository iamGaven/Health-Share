// Small data class to hold nutrient display info
import 'package:flutter/material.dart';

 class NutrientDef {
  final String label;
  final dynamic value;
  final String unit;
  final IconData icon;
  const NutrientDef(this.label, this.value, this.unit, this.icon);
}