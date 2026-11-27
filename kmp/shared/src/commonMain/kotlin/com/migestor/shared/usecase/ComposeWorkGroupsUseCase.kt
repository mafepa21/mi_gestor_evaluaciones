package com.migestor.shared.usecase

import com.migestor.shared.domain.StudentSex
import com.migestor.shared.workgroup.WorkGroupMark
import kotlin.math.ceil
import kotlin.random.Random

enum class WorkGroupComposeStrategy {
    HETEROGENEOUS_GRADE,
    HOMOGENEOUS_GRADE,
    RANDOM_BALANCED,

    /**
     * Por nivel técnico: un líder por grupo, comportamiento bajo repartido y el resto
     * equilibrado por la nota de técnica (o la media si no la hay). Las marcas
     * «Fuerte» / «Necesita apoyo» del docente cuentan como nivel alto / bajo.
     */
    SKILL_LEVEL,
}

data class WorkGroupStudentInput(
    val studentId: Long,
    val average: Double? = null,
    val sex: StudentSex = StudentSex.UNSPECIFIED,
    val isInjured: Boolean = false,
    /** Nota de 0 a 10 de los instrumentos de técnica elegidos. `null` si no tiene. */
    val technique: Double? = null,
    /** Nota de 0 a 10 de los instrumentos de comportamiento elegidos. */
    val behaviour: Double? = null,
    /** Nota de 0 a 10 de los instrumentos de liderazgo elegidos. */
    val leadership: Double? = null,
    val mark: WorkGroupMark = WorkGroupMark.NONE,
) {
    /**
     * Nivel con el que se reparte en [WorkGroupComposeStrategy.SKILL_LEVEL]: técnica,
     * si no la media, si no un nivel neutro. La marca del docente manda sobre la nota:
     * «Fuerte» sube al menos a [STRONG_FLOOR] y «Necesita apoyo» baja como mucho a
     * [SUPPORT_CEILING].
     */
    val skillLevel: Double
        get() {
            val base = technique ?: average ?: NEUTRAL_LEVEL
            return when (mark) {
                WorkGroupMark.STRONG -> maxOf(base, STRONG_FLOOR)
                WorkGroupMark.SUPPORT -> minOf(base, SUPPORT_CEILING)
                WorkGroupMark.NONE -> base
            }
        }

    companion object {
        const val NEUTRAL_LEVEL = 5.0
        const val STRONG_FLOOR = 8.5
        const val SUPPORT_CEILING = 3.5
    }
}

data class WorkGroupComposeOptions(
    val groupCount: Int,
    val strategy: WorkGroupComposeStrategy = WorkGroupComposeStrategy.HETEROGENEOUS_GRADE,
    val mixSex: Boolean = false,
    val spreadInjured: Boolean = true,
    /** Solo [WorkGroupComposeStrategy.SKILL_LEVEL]: un líder (mejor nota de liderazgo) en cada grupo. */
    val oneLeaderPerGroup: Boolean = true,
    /** Solo [WorkGroupComposeStrategy.SKILL_LEVEL]: reparte a quien tiene comportamiento bajo. */
    val spreadLowBehaviour: Boolean = true,
    /** Por debajo de esta nota de comportamiento se considera «bajo». */
    val lowBehaviourThreshold: Double = 5.0,
    val random: Random = Random.Default,
)

data class ComposedWorkGroup(
    val name: String,
    val studentIds: List<Long>,
)

class ComposeWorkGroupsUseCase {
    fun compose(
        students: List<WorkGroupStudentInput>,
        options: WorkGroupComposeOptions,
    ): List<ComposedWorkGroup> {
        if (students.isEmpty()) return emptyList()
        val groupCount = options.groupCount.coerceIn(1, students.size)
        val buckets = List(groupCount) { mutableListOf<WorkGroupStudentInput>() }
        if (options.strategy == WorkGroupComposeStrategy.SKILL_LEVEL) {
            composeBySkill(students, buckets, options)
            return buckets.toComposed()
        }
        val remaining = students.toMutableList()

        if (options.spreadInjured) {
            val injured = remaining.filter { it.isInjured }.shuffled(options.random)
            remaining.removeAll { it.isInjured }
            injured.forEachIndexed { index, student ->
                buckets[index % groupCount].add(student)
            }
        }

        val ordered = orderStudents(remaining, options)
        distribute(ordered, buckets, options.strategy)

        if (options.mixSex) {
            rebalanceSex(buckets)
        }
        equalizeSizes(buckets)

        return buckets.toComposed()
    }

    private fun List<List<WorkGroupStudentInput>>.toComposed(): List<ComposedWorkGroup> =
        mapIndexed { index, members ->
            ComposedWorkGroup(
                name = "Grupo ${index + 1}",
                studentIds = members.map { it.studentId },
            )
        }

    /**
     * Reparto por nivel técnico, en este orden:
     * 1. lesionados repartidos (si se pide);
     * 2. un líder por grupo: los de mejor nota de liderazgo;
     * 3. comportamiento bajo repartido: cada uno al grupo que menos tenga;
     * 4. el resto, de más a menos nivel, al grupo más pequeño y, a igualdad, al de menos
     *    nivel acumulado. Así los tamaños quedan iguales y los niveles parecidos;
     * 5. chicos y chicas mezclados (si se pide) e igualación final de tamaños.
     * Determinista: los empates se resuelven por id de alumno y por orden de grupo.
     */
    private fun composeBySkill(
        students: List<WorkGroupStudentInput>,
        buckets: List<MutableList<WorkGroupStudentInput>>,
        options: WorkGroupComposeOptions,
    ) {
        val remaining = students.sortedBy { it.studentId }.toMutableList()
        val hasLeader = BooleanArray(buckets.size)
        val leaderIds = mutableSetOf<Long>()
        val lowBehaviourCount = IntArray(buckets.size)

        fun level(bucket: List<WorkGroupStudentInput>) = bucket.sumOf { it.skillLevel }
        fun isLowBehaviour(student: WorkGroupStudentInput) =
            student.behaviour?.let { it < options.lowBehaviourThreshold } == true

        fun place(student: WorkGroupStudentInput, index: Int) {
            buckets[index].add(student)
            if (isLowBehaviour(student)) lowBehaviourCount[index]++
            remaining.remove(student)
        }

        /** Grupo con menos [priority] (si se da), luego el más pequeño y luego el de menos nivel. */
        fun bestBucket(candidates: List<Int>, priority: (Int) -> Int = { 0 }): Int =
            candidates.minWith(
                compareBy<Int> { priority(it) }
                    .thenBy { buckets[it].size }
                    .thenBy { level(buckets[it]) }
                    .thenBy { it },
            )

        if (options.spreadInjured) {
            remaining.filter { it.isInjured }.forEachIndexed { index, student ->
                place(student, index % buckets.size)
            }
        }

        if (options.oneLeaderPerGroup) {
            remaining.filter { it.leadership != null }
                .sortedWith(compareByDescending<WorkGroupStudentInput> { it.leadership }.thenBy { it.studentId })
                .take(buckets.size)
                .forEach { leader ->
                    val index = bestBucket(buckets.indices.filter { !hasLeader[it] })
                    place(leader, index)
                    hasLeader[index] = true
                    leaderIds += leader.studentId
                }
        }

        if (options.spreadLowBehaviour) {
            remaining.filter(::isLowBehaviour)
                .sortedWith(compareBy<WorkGroupStudentInput> { it.behaviour }.thenBy { it.studentId })
                .forEach { student ->
                    place(student, bestBucket(buckets.indices.toList()) { lowBehaviourCount[it] })
                }
        }

        remaining.sortedWith(compareByDescending<WorkGroupStudentInput> { it.skillLevel }.thenBy { it.studentId })
            .forEach { student -> place(student, bestBucket(buckets.indices.toList())) }

        if (options.mixSex) {
            rebalanceSexByLevel(buckets, locked = leaderIds)
        }
        equalizeSizes(buckets)
    }

    /**
     * Como [rebalanceSex], pero sin mover a los líderes ni a los lesionados y cambiando
     * cada vez el chico y la chica de nivel más parecido, para no desequilibrar la técnica.
     */
    private fun rebalanceSexByLevel(
        buckets: List<MutableList<WorkGroupStudentInput>>,
        locked: Set<Long>,
    ) {
        fun movable(student: WorkGroupStudentInput, sex: StudentSex) =
            student.sex == sex && student.studentId !in locked && !student.isInjured
        repeat(buckets.size * 4) {
            val maleBalance = buckets.map { bucket ->
                bucket.count { it.sex == StudentSex.MALE } - bucket.count { it.sex == StudentSex.FEMALE }
            }
            val richest = maleBalance.indices.maxByOrNull { maleBalance[it] } ?: return
            val poorest = maleBalance.indices.minByOrNull { maleBalance[it] } ?: return
            if (richest == poorest || maleBalance[richest] - maleBalance[poorest] <= 1) return
            val pair = buckets[richest].filter { movable(it, StudentSex.MALE) }
                .flatMap { male -> buckets[poorest].filter { movable(it, StudentSex.FEMALE) }.map { male to it } }
                .minWithOrNull(
                    compareBy<Pair<WorkGroupStudentInput, WorkGroupStudentInput>> {
                        kotlin.math.abs(it.first.skillLevel - it.second.skillLevel)
                    }.thenBy { it.first.studentId }.thenBy { it.second.studentId },
                ) ?: return
            val (male, female) = pair
            buckets[richest][buckets[richest].indexOf(male)] = female
            buckets[poorest][buckets[poorest].indexOf(female)] = male
        }
    }

    private fun orderStudents(
        students: List<WorkGroupStudentInput>,
        options: WorkGroupComposeOptions,
    ): List<WorkGroupStudentInput> {
        val byGrade = compareByDescending<WorkGroupStudentInput> { it.average ?: Double.NEGATIVE_INFINITY }
            .thenBy { it.studentId }
        val sorted = when (options.strategy) {
            WorkGroupComposeStrategy.RANDOM_BALANCED -> students.shuffled(options.random)
            else -> students.sortedWith(byGrade)
        }
        if (!options.mixSex) return sorted

        val males = sorted.filter { it.sex == StudentSex.MALE }
        val females = sorted.filter { it.sex == StudentSex.FEMALE }
        val rest = sorted.filter { it.sex == StudentSex.UNSPECIFIED }
        val interleaved = mutableListOf<WorkGroupStudentInput>()
        val max = maxOf(males.size, females.size)
        for (index in 0 until max) {
            if (index < males.size) interleaved += males[index]
            if (index < females.size) interleaved += females[index]
        }
        interleaved += rest
        return interleaved
    }

    private fun distribute(
        students: List<WorkGroupStudentInput>,
        buckets: List<MutableList<WorkGroupStudentInput>>,
        strategy: WorkGroupComposeStrategy,
    ) {
        if (students.isEmpty() || buckets.isEmpty()) return
        when (strategy) {
            WorkGroupComposeStrategy.HOMOGENEOUS_GRADE -> {
                val chunk = ceil(students.size / buckets.size.toDouble()).toInt().coerceAtLeast(1)
                students.chunked(chunk).forEachIndexed { index, slice ->
                    buckets[index.coerceAtMost(buckets.lastIndex)].addAll(slice)
                }
            }
            WorkGroupComposeStrategy.HETEROGENEOUS_GRADE,
            WorkGroupComposeStrategy.RANDOM_BALANCED,
            // No llega aquí: compose() lo resuelve antes con composeBySkill.
            WorkGroupComposeStrategy.SKILL_LEVEL -> {
                snakeInto(students, buckets)
            }
        }
    }

    private fun snakeInto(
        students: List<WorkGroupStudentInput>,
        buckets: List<MutableList<WorkGroupStudentInput>>,
    ) {
        val count = buckets.size
        students.forEachIndexed { index, student ->
            val cycle = index / count
            val offset = index % count
            val bucketIndex = if (cycle % 2 == 0) offset else count - 1 - offset
            buckets[bucketIndex].add(student)
        }
    }

    private fun rebalanceSex(buckets: List<MutableList<WorkGroupStudentInput>>) {
        repeat(buckets.size * 4) {
            val maleBalance = buckets.map { bucket ->
                bucket.count { it.sex == StudentSex.MALE } - bucket.count { it.sex == StudentSex.FEMALE }
            }
            val richest = maleBalance.indices.maxByOrNull { maleBalance[it] } ?: return
            val poorest = maleBalance.indices.minByOrNull { maleBalance[it] } ?: return
            if (richest == poorest) return
            if (maleBalance[richest] - maleBalance[poorest] <= 1) return
            val maleIndex = buckets[richest].indexOfFirst { it.sex == StudentSex.MALE }
            val femaleIndex = buckets[poorest].indexOfFirst { it.sex == StudentSex.FEMALE }
            if (maleIndex < 0 || femaleIndex < 0) return
            val male = buckets[richest][maleIndex]
            buckets[richest][maleIndex] = buckets[poorest][femaleIndex]
            buckets[poorest][femaleIndex] = male
        }
    }

    private fun equalizeSizes(buckets: List<MutableList<WorkGroupStudentInput>>) {
        if (buckets.isEmpty()) return
        val total = buckets.sumOf { it.size }
        repeat(total) {
            val largest = buckets.indices.maxBy { buckets[it].size }
            val smallest = buckets.indices.minBy { buckets[it].size }
            if (buckets[largest].size - buckets[smallest].size <= 1) return
            buckets[smallest].add(buckets[largest].removeAt(buckets[largest].lastIndex))
        }
    }
}
