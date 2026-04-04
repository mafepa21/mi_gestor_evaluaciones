package com.migestor.shared.domain

sealed class SpeedEntryContract {
    /** confirm advance on Enter/Tab. Backspace on empty advances back. */
    object TextInput : SpeedEntryContract()
    
    /** Instant toggle and advance on Space/Enter. */
    object InstantToggle : SpeedEntryContract()
    
    /** 
     * Cycle options with arrows. Advance on Enter. 
     * Specific keys (P,A,R,T) can trigger instant selection and advance in Attendance.
     */
    data class CycleOptions(
        val options: List<String>,
        val isAttendance: Boolean = false
    ) : SpeedEntryContract()
    
    /** Opens a modal dialog. Advance managed by the dialog confirmation. */
    object ModalAction : SpeedEntryContract()
    
    /** Reading only. Selection/Arrows just navigate. */
    object ReadOnly : SpeedEntryContract()
}

fun NotebookColumnDefinition.toSpeedContract(): SpeedEntryContract {
    return when (type) {
        NotebookColumnType.NUMERIC, 
        NotebookColumnType.TEXT -> SpeedEntryContract.TextInput
        
        NotebookColumnType.CHECK -> SpeedEntryContract.InstantToggle
        
        NotebookColumnType.ORDINAL -> SpeedEntryContract.CycleOptions(
            options = ordinalLevels.ifEmpty { listOf("A", "B", "C", "D", "F") }
        )
        
        NotebookColumnType.ICON -> SpeedEntryContract.CycleOptions(
            options = availableIcons.ifEmpty { listOf("🟢", "🟡", "🔴", "⭐", "✅", "❓") }
        )
        
        NotebookColumnType.ATTENDANCE -> SpeedEntryContract.CycleOptions(
            options = listOf("P", "A", "R", "J"),
            isAttendance = true
        )
        
        NotebookColumnType.RUBRIC -> SpeedEntryContract.ModalAction
        
        NotebookColumnType.CALCULATED -> SpeedEntryContract.ReadOnly
    }
}
