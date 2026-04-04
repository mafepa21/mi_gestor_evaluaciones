package com.migestor.desktop.ui.system

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions

data class ToolbarSearchResult(
    val id: String,
    val label: String,
    val subtitle: String,
)

@Composable
fun AppToolbar(
    title: String,
    subtitle: String,
    searchQuery: String,
    onSearchQueryChange: (String) -> Unit,
    searchResults: List<ToolbarSearchResult>,
    onSearchResultSelected: (ToolbarSearchResult) -> Unit,
    onSearchSubmit: (String) -> Unit,
    actions: List<AppActionModel>,
    onToggleInspector: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val toolbarActions = actions.filter { it.placement == AppActionPlacement.Toolbar }
    val overflowActions = actions.filter { it.placement == AppActionPlacement.Overflow }
    val primaryAction = toolbarActions.firstOrNull { it.emphasis == AppActionEmphasis.Primary }
    val secondaryActions = toolbarActions.filter { it.emphasis != AppActionEmphasis.Primary }
    var overflowExpanded by remember { mutableStateOf(false) }

    val searchFieldColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.9f)

    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.78f),
        tonalElevation = 1.dp,
        shadowElevation = 0.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(84.dp)
                .padding(horizontal = 24.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    text = subtitle.uppercase(),
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontWeight = FontWeight.Medium,
                        letterSpacing = 0.8.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    ),
                )
                Text(
                    text = title,
                    style = MaterialTheme.typography.headlineSmall.copy(
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    ),
                )
            }

            Box {
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = onSearchQueryChange,
                    placeholder = { Text("Buscar módulo o acción") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = "Buscar") },
                    singleLine = true,
                    shape = CircleShape,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { onSearchSubmit(searchQuery) }),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedContainerColor = searchFieldColor,
                        unfocusedContainerColor = searchFieldColor,
                        focusedBorderColor = Color.Transparent,
                        unfocusedBorderColor = Color.Transparent,
                    ),
                    modifier = Modifier.width(320.dp),
                )

                DropdownMenu(
                    expanded = searchQuery.isNotBlank() && searchResults.isNotEmpty(),
                    onDismissRequest = { onSearchQueryChange("") },
                    modifier = Modifier.width(360.dp),
                ) {
                    searchResults.forEach { result ->
                        DropdownMenuItem(
                            text = {
                                Column {
                                    Text(result.label, style = MaterialTheme.typography.bodyMedium)
                                    Text(
                                        result.subtitle,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            },
                            onClick = { onSearchResultSelected(result) }
                        )
                    }
                }
            }

            secondaryActions.take(2).forEach { action ->
                IconButton(
                    onClick = action.onClick,
                    enabled = action.enabled,
                    modifier = Modifier.size(44.dp),
                ) {
                    Icon(
                        imageVector = action.icon,
                        contentDescription = action.label,
                        tint = if (action.emphasis == AppActionEmphasis.Destructive) {
                            MaterialTheme.colorScheme.error
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                    )
                }
            }

            primaryAction?.let { action ->
                Button(onClick = action.onClick, enabled = action.enabled) {
                    Icon(action.icon, contentDescription = null)
                    Text(" ${action.label}")
                }
            }

            Box {
                IconButton(
                    onClick = { overflowExpanded = true },
                    modifier = Modifier.size(44.dp),
                ) {
                    Icon(Icons.Default.MoreVert, contentDescription = "Más acciones")
                }
                DropdownMenu(
                    expanded = overflowExpanded,
                    onDismissRequest = { overflowExpanded = false },
                ) {
                    overflowActions.forEach { action ->
                        DropdownMenuItem(
                            text = { Text(action.label) },
                            leadingIcon = { Icon(action.icon, contentDescription = null) },
                            onClick = {
                                overflowExpanded = false
                                action.onClick()
                            },
                            enabled = action.enabled,
                        )
                    }
                }
            }

            IconButton(onClick = onToggleInspector, modifier = Modifier.size(44.dp)) {
                Icon(Icons.Outlined.Tune, contentDescription = "Mostrar inspector")
            }
        }
    }
}

@Composable
fun AppShellScaffold(
    sidebar: @Composable () -> Unit,
    toolbar: @Composable () -> Unit,
    content: @Composable () -> Unit,
    inspectorVisible: Boolean,
    inspector: @Composable () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier = modifier.fillMaxSize()) {
        sidebar()
        Column(modifier = Modifier.weight(1f)) {
            toolbar()
            Row(modifier = Modifier.weight(1f)) {
                Box(modifier = Modifier.weight(1f)) { content() }
                if (inspectorVisible) {
                    Surface(
                        modifier = Modifier
                            .fillMaxHeight()
                            .width(320.dp),
                        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.42f),
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.72f))
                                .padding(16.dp),
                        ) {
                            inspector()
                        }
                    }
                }
            }
        }
    }
}
