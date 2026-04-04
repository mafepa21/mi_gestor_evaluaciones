package com.migestor.desktop.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.migestor.desktop.ui.rubrics.EvaluationDesign

@Composable
fun EvaluationChip(
    label: String,
    icon: ImageVector? = null,
    tint: Color = EvaluationDesign.accent,
    isDestructive: Boolean = false
) {
    val backgroundColor = if (isDestructive) EvaluationDesign.danger.copy(alpha = 0.1f) else tint.copy(alpha = 0.1f)
    val contentColor = if (isDestructive) EvaluationDesign.danger else tint

    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(EvaluationDesign.chipRadius))
            .background(backgroundColor)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (icon != null) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(14.dp),
                tint = contentColor
            )
        }
        Text(
            text = label,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = contentColor
        )
    }
}
