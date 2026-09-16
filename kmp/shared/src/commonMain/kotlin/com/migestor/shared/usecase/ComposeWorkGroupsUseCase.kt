package com.migestor.shared.usecase

import com.migestor.shared.domain.StudentSex
import kotlin.math.ceil
import kotlin.random.Random

enum class WorkGroupComposeStrategy {
    HETEROGENEOUS_GRADE,
    HOMOGENEOUS_GRADE,
    RANDOM_BALANCED,
}

data class WorkGroupStudentInput(
    val studentId: Long,
    val average: Double? = null,
    val sex: StudentSex = StudentSex.UNSPECIFIED,
    val isInjured: Boolean = false,
)

data class WorkGroupComposeOptions(
    val groupCount: Int,
    val strategy: WorkGroupComposeStrategy = WorkGroupComposeStrategy.HETEROGENEOUS_GRADE,
    val mixSex: Boolean = false,
    val spreadInjured: Boolean = true,
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

        return buckets.mapIndexed { index, members ->
            ComposedWorkGroup(
                name = "Grupo ${index + 1}",
                studentIds = members.map { it.studentId },
            )
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
            WorkGroupComposeStrategy.RANDOM_BALANCED -> {
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
