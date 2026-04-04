package com.migestor.desktop.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

@Composable
fun MeshBackground(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color(0xFFF8FAFC)) // Light base
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            // Radial Gradient 1: Top Center (Blue-ish)
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(Color(0xFF3B82F6).copy(alpha = 0.08f), Color.Transparent),
                    center = Offset(size.width * 0.5f, 0f),
                    radius = size.width * 0.6f
                ),
                center = Offset(size.width * 0.5f, 0f),
                radius = size.width * 0.6f
            )

            // Radial Gradient 2: Bottom Right (Pink-ish)
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(Color(0xFFEC4899).copy(alpha = 0.08f), Color.Transparent),
                    center = Offset(size.width, size.height),
                    radius = size.width * 0.6f
                ),
                center = Offset(size.width, size.height),
                radius = size.width * 0.6f
            )

            // Optional: Subtle center mesh effect
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(Color(0xFF818CF8).copy(alpha = 0.05f), Color.Transparent),
                    center = Offset(size.width * 0.2f, size.height * 0.8f),
                    radius = size.width * 0.4f
                ),
                center = Offset(size.width * 0.2f, size.height * 0.8f),
                radius = size.width * 0.4f
            )
        }
        content()
    }
}
