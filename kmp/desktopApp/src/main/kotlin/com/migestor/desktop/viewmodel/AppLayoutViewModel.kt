package com.migestor.desktop.viewmodel

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

class AppLayoutViewModel(initialExpanded: Boolean = true) {
    // true = expandido (240dp), false = colapsado (56dp)
    val isSidebarExpanded = MutableStateFlow(initialExpanded)

    fun toggleSidebar() = isSidebarExpanded.update { !it }

    fun setSidebarExpanded(expanded: Boolean) {
        isSidebarExpanded.value = expanded
    }
}
