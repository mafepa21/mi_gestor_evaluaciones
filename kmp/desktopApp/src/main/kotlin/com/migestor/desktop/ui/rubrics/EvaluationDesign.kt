package com.migestor.desktop.ui.rubrics

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

object EvaluationDesign {
    // Colors
    val accent = Color(0xFF6366F1) // Indigo 500
    val success = Color(0xFF10B981) // Emerald 500
    val danger = Color(0xFFEF4444) // Red 500
    val warning = Color(0xFFF59E0B) // Amber 500
    val primary = Color(0xFF1F2937) // Gray 800
    val secondary = Color(0xFF6B7280) // Gray 500
    val border = Color(0xFFE5E7EB) // Gray 200
    val shadow = Color(0x0F000000)
    
    // Spacing (8pt grid)
    val screenPadding = 24.dp
    val sectionSpacing = 24.dp
    val itemSpacing = 16.dp
    val subItemSpacing = 8.dp
    
    // Radii
    val cardRadius = 32.dp
    val innerRadius = 20.dp
    val chipRadius = 12.dp
    
    // Widths
    val studentColumnWidth = 240.dp
    val criterionColumnWidth = 200.dp
    val scoreColumnWidth = 88.dp
    val actionsColumnWidth = 92.dp
}
