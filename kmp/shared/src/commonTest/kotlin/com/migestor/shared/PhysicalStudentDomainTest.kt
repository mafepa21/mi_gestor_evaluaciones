package com.migestor.shared

import com.migestor.shared.domain.Student
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PhysicalStudentDomainTest {
    @Test
    fun `ageOn handles birthday before and after test date`() {
        val student = Student(
            id = 1,
            firstName = "Ana",
            lastName = "Lopez",
            birthDate = LocalDate(2010, 5, 10),
        )

        assertEquals(13, student.ageOn(LocalDate(2024, 5, 9)))
        assertEquals(14, student.ageOn(LocalDate(2024, 5, 10)))
        assertEquals(14, student.ageOn(LocalDate(2024, 12, 1)))
    }

    @Test
    fun `ageOn returns null without birth date`() {
        assertNull(Student(id = 1, firstName = "Ana", lastName = "Lopez").ageOn(LocalDate(2024, 5, 10)))
    }
}
