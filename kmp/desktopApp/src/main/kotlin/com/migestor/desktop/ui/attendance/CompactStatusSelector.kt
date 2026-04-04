package com.migestor.desktop.ui.attendance

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun CompactStatusSelector(
    selectedStatus: AttendanceStatus?,
    onStatusSelected: (AttendanceStatus) -> Unit
) {
    Row(
        modifier = Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        AttendanceStatus.values().forEach { status ->
            val isSelected = selectedStatus == status
            val backgroundColor by animateColorAsState(
                if (isSelected) status.color.copy(alpha = 0.2f) else Color.White.copy(alpha = 0.4f),
                animationSpec = tween(200)
            )
            val contentColor by animateColorAsState(
                if (isSelected) status.color else Color.Gray,
                animationSpec = tween(200)
            )

            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(backgroundColor)
                    .clickable { onStatusSelected(status) }
                    .heightIn(min = 44.dp)
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                contentAlignment = Alignment.Center
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center
                ) {
                    Icon(
                        imageVector = status.icon,
                        contentDescription = status.label,
                        modifier = Modifier.size(16.dp),
                        tint = contentColor
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = status.label,
                        fontSize = 12.sp,
                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                        color = contentColor
                    )
                }
            }
        }
    }
}
