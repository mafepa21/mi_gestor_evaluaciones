package com.migestor.desktop.ui.attendance

import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.migestor.shared.domain.Student
import com.migestor.desktop.ui.components.OrganicGlassCard

@Composable
fun StudentAttendanceRow(
    student: Student,
    currentStatus: AttendanceStatus?,
    onStatusSelected: (AttendanceStatus) -> Unit
) {
    OrganicGlassCard(
        cornerRadius = 12.dp,
        elevation = 0.dp,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 4.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "${student.lastName}, ${student.firstName}",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }

            CompactStatusSelector(
                selectedStatus = currentStatus,
                onStatusSelected = onStatusSelected
            )
        }
    }
}
