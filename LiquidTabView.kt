// Android 12+ / Compose UI 1.7+. Change the package to match your project.
package studio.greenglass.demo

import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import kotlin.math.*

/** IDs must be unique and saveable (String, Int or enum); icons may use any Compose content. */
data class LiquidTab<T : Any>(val id: T, val title: String, val icon: @Composable () -> Unit)
data class LiquidTabAction(val title: String, val onClick: () -> Unit, val icon: @Composable () -> Unit)

/** Owns the backdrop and per-tab saveable state; navigation selection stays with the caller. */
@Composable
fun <T : Any> LiquidTabView(
    selectedTab: T,
    onTabSelected: (T) -> Unit,
    tabs: List<LiquidTab<T>>,
    modifier: Modifier = Modifier,
    tint: Color = Color(0xFFFF8A70),
    iconTint: Color = lerp(tint, Color.Black, .72f),
    action: LiquidTabAction? = null,
    dark: Boolean = isSystemInDarkTheme(),
    reduceMotion: Boolean = false,
    content: @Composable (T, PaddingValues) -> Unit
) {
    val backdrop = rememberGraphicsLayer()
    val holder = rememberSaveableStateHolder()
    var origin by remember { mutableStateOf(Offset.Zero) }
    CompositionLocalProvider(LocalLiquidOrigin provides origin) {
        Box(modifier.fillMaxSize().onGloballyPositioned { origin = it.positionInRoot() }) {
            Box(Modifier.fillMaxSize().drawWithContent {
                backdrop.record { this@drawWithContent.drawContent() }
                drawLayer(backdrop)
            }) {
                holder.SaveableStateProvider(selectedTab) {
                    content(selectedTab, PaddingValues(bottom = 88.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()))
                }
            }
            LiquidTabBar(selectedTab, onTabSelected, tabs, backdrop,
                Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(horizontal = 16.dp, vertical = 12.dp),
                tint, iconTint, action, dark, reduceMotion)
        }
    }
}

private val LocalLiquidOrigin = staticCompositionLocalOf { Offset.Zero }

private data class LiquidColors(val dark: Boolean, val tint: Color, val activeIcon: Color) {
    val inactiveIcon = if (dark) Color(0xFFA9ADB4) else Color(0xFF969B9C)
    val lensColors = listOf(lerp(tint, Color.White, .33f), tint, lerp(tint, Color.White, .20f))
    val heldIcon = if (dark) lerp(tint, Color.White, max(0f, .7f - maxOf(tint.red, tint.green, tint.blue)) / .7f)
        else lerp(tint, Color.Black, .45f)
}

/** Low-level bar. backdrop must record only the page, in the same root coordinate space. */
@Composable
fun <T : Any> LiquidTabBar(
    selectedTab: T,
    onTabSelected: (T) -> Unit,
    tabs: List<LiquidTab<T>>,
    backdrop: GraphicsLayer,
    modifier: Modifier = Modifier,
    tint: Color = Color(0xFFFF8A70),
    iconTint: Color = lerp(tint, Color.Black, .72f),
    action: LiquidTabAction? = null,
    dark: Boolean = isSystemInDarkTheme(),
    reduceMotion: Boolean = false
) {
    require(tabs.size in 2..5 && tabs.map { it.id }.distinct().size == tabs.size)
    require(tabs.any { it.id == selectedTab }) { "selection must belong to tabs" }
    val ids = tabs.map { it.id }
    val motionScale = rememberCoroutineScope().coroutineContext[MotionDurationScale]
    val reduced = reduceMotion || motionScale?.scaleFactor == 0f
    val selectedIndex = tabs.indexOfFirst { it.id == selectedTab }.coerceAtLeast(0)
    val palette = remember(tint, iconTint, dark) { LiquidColors(dark, tint, iconTint) }
    var touching by remember(ids) { mutableStateOf(false) }
    var releaseGeneration by remember(ids) { mutableIntStateOf(0) }
    var scrubRelease by remember(ids) { mutableStateOf(false) }
    val selectTab by rememberUpdatedState(onTabSelected)
    val motion = remember(ids) { mutableStateOf(LiquidMotionSample(selectedIndex.toFloat(), 0f)) }
    val tracking = remember(ids) { mutableStateOf<LiquidMotionSegment?>(null) }
    val pressure = animateFloatAsState(
        if (touching && !reduced) 1f else 0f,
        if (reduced) snap() else spring(dampingRatio = 1f, stiffness = if (touching) 1200f else 540f), label = "lens pressure"
    )
    LaunchedEffect(ids, selectedTab, reduced, touching, releaseGeneration) {
        if (touching) {
            while (true) {
                val frame = withFrameNanos { it }
                if (!reduced) tracking.value?.let { motion.value = it.sample(frame) }
            }
        }
        val current = motion.value
        val target = selectedIndex.toFloat()
        val durationScale = coroutineContext[MotionDurationScale]
        if (reduced || durationScale?.scaleFactor == 0f || (current.position == target && current.velocity == 0f)) {
            motion.value = LiquidMotionSample(target, 0f)
        } else {
            val trajectory = LiquidMotionSegment(current, target, 0, (tabs.size - 1).toFloat(), if (scrubRelease) .26 else null)
            var previousFrame = System.nanoTime()
            var playhead = 0L
            while (true) {
                val frame = withFrameNanos { it }
                val scale = durationScale?.scaleFactor ?: 1f
                if (scale == 0f) break
                playhead += ((frame - previousFrame).coerceAtLeast(0) / scale).toLong()
                previousFrame = frame
                motion.value = trajectory.sample(playhead)
                if (playhead / 1_000_000_000.0 >= trajectory.settlingDuration) break
            }
            motion.value = LiquidMotionSample(target, 0f)
        }
    }
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        BoxWithConstraints(modifier.height(64.dp), contentAlignment = Alignment.Center) {
            val width = minOf(maxWidth, (tabs.size * 80 + 16 + if (action == null) 0 else 84).dp)
            Row(Modifier.width(width).fillMaxHeight(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                LiquidGlassSurface(backdrop, dark, Modifier.weight(1f).fillMaxHeight()) {
                    Box(Modifier.fillMaxSize().padding(8.dp).pointerInput(ids, reduced, selectedTab) {
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                            down.consume()
                            val session = LiquidDragState(down.position.x, size.width.toFloat() / tabs.size,
                                tabs.size, motion.value.position, down.uptimeMillis, 6.dp.toPx())
                            touching = true
                            tracking.value = LiquidMotionSegment(motion.value, motion.value.position, System.nanoTime(),
                                (tabs.size - 1).toFloat(), .105)
                            try {
                                while (true) {
                                    val event = awaitPointerEvent(PointerEventPass.Initial)
                                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                    // A second pointer cancels; never hand the capsule to another finger.
                                    if (event.changes.count { it.pressed } > 1) {
                                        event.changes.forEach { it.consume() }
                                        break
                                    }
                                    if (change.isConsumed) break
                                    change.consume()
                                    session.update(change.position.x, change.uptimeMillis)
                                    if (session.moved) {
                                        val now = System.nanoTime()
                                        val current = tracking.value?.sample(now) ?: motion.value
                                        if (reduced) motion.value = session.sample.copy(velocity = 0f)
                                        else tracking.value = LiquidMotionSegment(current, session.sample.position, now,
                                            (tabs.size - 1).toFloat(), .105)
                                    }
                                    if (!change.pressed) {
                                        val inside = change.position.x in -32.dp.toPx()..(size.width + 32.dp.toPx()) &&
                                            change.position.y in -56.dp.toPx()..(size.height + 56.dp.toPx())
                                        if (inside) selectTab(tabs[if (session.moved) session.destination else session.tappedIndex].id)
                                        break
                                    }
                                }
                            } finally {
                                // Also runs on pointer cancellation, disposal or layout replacement.
                                if (!reduced) tracking.value?.let { motion.value = it.sample(System.nanoTime()) }
                                tracking.value = null
                                scrubRelease = session.moved
                                touching = false
                                releaseGeneration++
                            }
                        }
                    }) {
                        Row(Modifier.fillMaxSize().selectableGroup().drawWithContent {
                            val bounds = liquidBounds(size, motion.value, pressure.value, tabs.size)
                            val cutout = Path().apply { addRoundRect(RoundRect(bounds, CornerRadius(bounds.height / 2))) }
                            clipPath(cutout, clipOp = ClipOp.Difference) { this@drawWithContent.drawContent() }
                        }) {
                            tabs.forEach { tab ->
                                key(tab.id) {
                                    val interaction = remember { MutableInteractionSource() }
                                    Box(Modifier.weight(1f).fillMaxHeight().selectable(
                                        selected = tab.id == selectedTab, interactionSource = interaction, indication = null,
                                        role = Role.Tab, onClick = { scrubRelease = false; onTabSelected(tab.id) }
                                    ).semantics { contentDescription = tab.title }, contentAlignment = Alignment.Center) {
                                        CompositionLocalProvider(LocalContentColor provides palette.inactiveIcon) {
                                            Box(Modifier.size(22.dp).clearAndSetSemantics { }) { tab.icon() }
                                        }
                                    }
                                }
                            }
                        }
                        LiquidSelectionLens(tabs, motion, pressure, palette, Modifier.matchParentSize())
                    }
                }
                if (action != null) {
                    LiquidGlassSurface(backdrop, dark, Modifier.width(76.dp).fillMaxHeight()) {
                        IconButton(onClick = action.onClick,
                            modifier = Modifier.fillMaxSize().semantics { contentDescription = action.title }) { action.icon() }
                    }
                }
            }
        }
    }
}

/** All frame reads happen in draw/graphics. Refraction is isolated to this small icon layer. */
@Composable
private fun <T : Any> LiquidSelectionLens(
    tabs: List<LiquidTab<T>>,
    motion: State<LiquidMotionSample>,
    pressure: State<Float>,
    palette: LiquidColors,
    modifier: Modifier = Modifier
) {
    val refraction = remember { if (Build.VERSION.SDK_INT >= 33) LiquidRefraction() else null }
    val heldIcon = palette.heldIcon
    Box(modifier.clearAndSetSemantics { }) {
        Canvas(Modifier.matchParentSize()) {
            val sample = motion.value
            val press = pressure.value
            val glass = if (refraction != null) liquidGlass(press) else 0f
            val bounds = liquidBounds(size, sample, press, tabs.size)
            val radius = CornerRadius(bounds.height / 2f)
            // A small displaced shadow supports elevation without a neon halo.
            for (spread in 3 downTo 1) {
                val shadow = Rect(bounds.topLeft + Offset(-spread.dp.toPx(), 3.dp.toPx()),
                    Size(bounds.width + 2 * spread.dp.toPx(), bounds.height + spread.dp.toPx()))
                drawRoundRect(Color.Black.copy(alpha = if (palette.dark) .025f else .018f), shadow.topLeft, shadow.size, CornerRadius(shadow.height / 2f))
            }
            drawRoundRect(if (palette.dark) Color.White.copy(alpha = .08f * glass) else Color.White.copy(alpha = .35f * glass),
                bounds.topLeft, bounds.size, radius)
            drawRoundRect(Brush.linearGradient(palette.lensColors, bounds.topLeft, bounds.bottomRight), bounds.topLeft, bounds.size, radius,
                alpha = (if (palette.dark) .96f else 1f) * (1f - glass) + .035f * glass)
            drawRoundRect(Brush.radialGradient(
                listOf(Color.White.copy(alpha = .025f + .14f * glass), Color.Transparent),
                Offset(bounds.left + bounds.width * (.5f + .25f * sample.direction * sample.energy), bounds.top), bounds.width * .8f),
                bounds.topLeft, bounds.size, radius)
        }
        Row(Modifier.matchParentSize()
            .drawWithContent {
                val bounds = liquidBounds(size, motion.value, pressure.value, tabs.size)
                val path = Path().apply { addRoundRect(RoundRect(bounds, CornerRadius(bounds.height / 2f))) }
                clipPath(path) { this@drawWithContent.drawContent() }
            }
            .graphicsLayer {
                val sample = motion.value
                val press = pressure.value
                val glass = if (refraction != null) liquidGlass(press) else 0f
                if (Build.VERSION.SDK_INT >= 33 && refraction != null) {
                    renderEffect = refraction.effect(liquidBounds(size, sample, press, tabs.size),
                        glass * (.85f + .15f * sample.energy), glass, palette.activeIcon, heldIcon)
                } else {
                    transformOrigin = TransformOrigin((sample.position + .5f) / tabs.size, .5f)
                    scaleX = 1f + .12f * press
                    scaleY = scaleX
                }
            }) {
            tabs.forEach { tab ->
                Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.Center) {
                    CompositionLocalProvider(LocalContentColor provides palette.activeIcon) {
                        Box(Modifier.size(22.dp)) { tab.icon() }
                    }
                }
            }
        }
        Canvas(Modifier.matchParentSize()) {
            val sample = motion.value
            val lift = liquidGlass(pressure.value)
            val bounds = liquidBounds(size, sample, pressure.value, tabs.size)
            val rim = if (palette.dark) listOf(Color.White.copy(alpha = .12f + .65f * lift), Color.White.copy(alpha = .04f + .02f * lift), Color.Black.copy(alpha = .24f))
                else listOf(Color.White.copy(alpha = .12f + .65f * lift), Color.Black.copy(alpha = .08f + .17f * lift), Color.White.copy(alpha = .28f * lift))
            drawRoundRect(Brush.linearGradient(rim, bounds.topLeft, bounds.bottomRight), bounds.topLeft, bounds.size,
                CornerRadius(bounds.height / 2f), style = Stroke((.8f + .5f * lift).dp.toPx()))
        }
    }
}
/** Samples only the content layer. Never record this surface into its own backdrop. */
@Composable
private fun LiquidGlassSurface(
    backdrop: GraphicsLayer,
    dark: Boolean,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit
) {
    val backdropOrigin = LocalLiquidOrigin.current
    var origin by remember { mutableStateOf(Offset.Zero) }
    val shape = RoundedCornerShape(percent = 50)
    Box(
        modifier
            .onGloballyPositioned { origin = it.positionInRoot() }
            .shadow(14.dp, shape, clip = false, ambientColor = Color(0x18353F40), spotColor = Color(0x24353F40))
    ) {
        // Actual backdrop blur: replay the content layer in the surface coordinate space.
        // Modifier.blur on the surface itself would also blur the icons, which is incorrect.
        Canvas(Modifier.matchParentSize().clip(shape).blur(12.dp, BlurredEdgeTreatment.Unbounded)) {
            translate(backdropOrigin.x - origin.x, backdropOrigin.y - origin.y) { drawLayer(backdrop) }
        }
        Box(Modifier.matchParentSize().background(if (dark) Color(0xD91C1E21) else Color.White.copy(alpha = .61f), shape))
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(
            if (dark) listOf(Color(0x08FFFFFF), Color(0x0D000000))
            else listOf(Color.White.copy(alpha = .25f), Color(0x0CF0F3F3))), shape))
        content()
        Box(Modifier.matchParentSize().border(if (dark) .5.dp else 1.dp, Brush.linearGradient(
            if (dark) listOf(Color(0x14FFFFFF), Color(0x1AFFFFFF), Color(0x14000000), Color(0x08FFFFFF))
            else listOf(Color(0x5A737D7D), Color.White.copy(alpha = .94f), Color.White.copy(alpha = .42f), Color(0x74828B8B))), shape))
    }
}
@RequiresApi(33)
private class LiquidRefraction {
    private val shader = RuntimeShader("""
        uniform shader contents;
        uniform float4 lens;
        uniform float strength;
        uniform float glass;
        layout(color) uniform half4 restColor;
        layout(color) uniform half4 heldColor;
        half4 main(float2 p) {
            float2 d = p - lens.xy;
            float r = length(d / max(lens.zw, float2(1)));
            float rim = smoothstep(0.45, 0.94, r);
            float envelope = 1.0 - smoothstep(0.98, 1.16, r);
            float2 shift = -d * (0.12 + 0.18 * rim) * strength * envelope;
            float2 dispersion = normalize(d + float2(0.001)) * strength * rim * envelope;
            half4 c = contents.eval(p + shift);
            half4 red = contents.eval(p + shift + dispersion);
            half4 blue = contents.eval(p + shift - dispersion);
            half4 tint = mix(restColor, heldColor, glass);
            return half4(red.a * tint.r, c.a * tint.g, blue.a * tint.b, max(c.a, max(red.a, blue.a)));
        }
    """)
    fun effect(bounds: Rect, strength: Float, glass: Float, rest: Color, held: Color): androidx.compose.ui.graphics.RenderEffect {
        shader.setFloatUniform("lens", bounds.center.x, bounds.center.y, bounds.width / 2, bounds.height / 2)
        shader.setFloatUniform("strength", strength)
        shader.setFloatUniform("glass", glass)
        shader.setColorUniform("restColor", rest.toArgb())
        shader.setColorUniform("heldColor", held.toArgb())
        return RenderEffect.createRuntimeShaderEffect(shader, "contents").asComposeRenderEffect()
    }
}
internal fun liquidGlass(press: Float) = press * press * (3f - 2f * press)
internal fun liquidBounds(size: Size, sample: LiquidMotionSample, press: Float, tabCount: Int): Rect {
    val cell = size.width / tabCount
    val width = cell * (1f + .22f * press + .10f * sample.energy * (1f - .5f * press))
    val height = size.height * (1f + .38f * press + .025f * sample.energy)
    return Rect(Offset(cell * (sample.position + .5f) - width / 2f, (size.height - height) / 2f), Size(width, height))
}
internal data class LiquidMotionSample(val position: Float, val velocity: Float) {
    val energy: Float get() = (abs(velocity) / 8f).coerceIn(0f, 1f)
    val direction: Float get() = velocity / max(abs(velocity), .001f)
}

/** Analytic trajectory: retarget from presentation position AND velocity. */
internal class LiquidMotionSegment(
    val start: LiquidMotionSample,
    val target: Float,
    val startedAtNanos: Long,
    val maxPosition: Float = 3f,
    responseOverride: Double? = null
) {
    val response = responseOverride ?: (.32 + .13 * max(abs(target - start.position).toDouble() - 1, 0.0))
    val settlingDuration = response * 1.7

    fun sample(atNanos: Long): LiquidMotionSample {
        val time = max((atNanos - startedAtNanos) / 1_000_000_000.0, 0.0)
        val omega = 2 * PI / response
        val displacement = start.position - target
        val coefficient = start.velocity + omega * displacement
        val decay = exp(-omega * time)
        val position = target + (displacement + coefficient * time) * decay
        val velocity = (start.velocity - omega * coefficient * time) * decay
        return LiquidMotionSample(position.coerceIn(0.0, maxPosition.toDouble()).toFloat(), if (position < 0 || position > maxPosition) 0f else velocity.toFloat())
    }
}
/** Coordinates in pixels, local to the row of slots; threshold supplied in pixels. */
internal class LiquidDragState(
    private val startX: Float,
    private val cellWidth: Float,
    private val tabCount: Int,
    presentation: Float,
    time: Long,
    private val threshold: Float
) {
    private val finger = startX / cellWidth - .5f
    private val origin = if (abs(finger - presentation) <= .65f) presentation
        else finger.roundToInt().coerceIn(0, tabCount - 1).toFloat()
    var sample = LiquidMotionSample(presentation, 0f)
        private set
    var moved = false
        private set
    private var lastTime = time

    fun update(x: Float, time: Long) {
        val delta = x - startX
        moved = moved || abs(delta) >= threshold
        if (!moved) return
        val position = (origin + delta / cellWidth).coerceIn(0f, (tabCount - 1).toFloat())
        val dt = ((time - lastTime) / 1000f).coerceAtLeast(1f / 240)
        val velocity = ((position - sample.position) / dt).coerceIn(-8f, 8f)
        sample = LiquidMotionSample(position, sample.velocity * kotlin.math.exp(-dt * 18) * .65f + velocity * .35f)
        lastTime = time
    }

    val destination get() = sample.position.roundToInt().coerceIn(0, tabCount - 1)
    val tappedIndex get() = floor(startX / cellWidth).toInt().coerceIn(0, tabCount - 1)
}
