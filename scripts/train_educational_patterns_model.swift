#!/usr/bin/env swift
//
// scripts/train_educational_patterns_model.swift
// Mi Gestor Evaluaciones - Fase 2: Motor de Detección de Patrones No Obvios con Core ML
//
// Entrena un clasificador tabular supervisado usando CreateML con datos sintéticos calibrados.
// Cero fuga de datos de menores (Zero-Data Leakage), 100% privacidad y ejecución on-device.
//

import Foundation
import TabularData
import CreateML

print("======================================================================")
print("  Entrenador de Modelo Tabular Core ML para Patrones Educativos")
print("  Mi Gestor Evaluaciones - Capa 2 (Inferencia Matemática On-Device)")
print("======================================================================")

let currentDir = FileManager.default.currentDirectoryPath
let projectRoot: URL
if FileManager.default.fileExists(atPath: "\(currentDir)/kmp/iosApp/AppleShared") {
    projectRoot = URL(fileURLWithPath: currentDir)
} else {
    // Si se ejecuta desde scripts/
    projectRoot = URL(fileURLWithPath: currentDir).deletingLastPathComponent()
}

let targetMLDir = projectRoot.appendingPathComponent("kmp/iosApp/AppleShared/ML")
try? FileManager.default.createDirectory(at: targetMLDir, withIntermediateDirectories: true)

print("\n[1/5] Generando dataset sintético calibrado con arquetipos pedagógicos...")

var df = DataFrame()
var avgGrades: [Double] = []
var deltas: [Double] = []
var attendances: [Double] = []
var evalAbsences: [Double] = []
var pendingRatios: [Double] = []
var rubricVars: [Double] = []
var incidents: [Double] = []
var labels: [String] = []

func clamp(_ value: Double, min: Double, max: Double) -> Double {
    Swift.max(min, Swift.min(max, value))
}

// 1. Silent Disengagement (Desenganche Silencioso)
// Alumnos formalmente aprobados (5.0 a 6.8) que sufren una desaceleración no lineal:
// - Faltas que coinciden con sesiones evaluables/rúbricas (evaluableDayAbsenceRatio > 0.25)
// - Acumulación de tareas o entregas pendientes (pendingTaskRatio > 0.18)
// - Tendencia a la baja (gradeDelta < -0.5)
for _ in 0..<350 {
    let avg = clamp(Double.random(in: 5.0...6.8) + Double.random(in: -0.2...0.2), min: 4.8, max: 7.2)
    let delta = clamp(Double.random(in: -2.4...(-0.6)) + Double.random(in: -0.2...0.2), min: -4.0, max: -0.4)
    let att = clamp(Double.random(in: 80.0...94.0) + Double.random(in: -3.0...3.0), min: 75.0, max: 96.0)
    let evalAbs = clamp(Double.random(in: 0.25...0.70) + Double.random(in: -0.05...0.05), min: 0.20, max: 0.85)
    let pending = clamp(Double.random(in: 0.20...0.55) + Double.random(in: -0.05...0.05), min: 0.15, max: 0.70)
    let rVar = clamp(Double.random(in: 1.2...2.6) + Double.random(in: -0.2...0.2), min: 0.8, max: 3.2)
    let inc = Double(Int.random(in: 0...2))
    
    avgGrades.append(avg)
    deltas.append(delta)
    attendances.append(att)
    evalAbsences.append(evalAbs)
    pendingRatios.append(pending)
    rubricVars.append(rVar)
    incidents.append(inc)
    labels.append("silent_disengagement")
}

// 2. Bottleneck Risk (Criterios Cuello de Botella)
// Alumnos con rendimiento frágil (4.5 a 6.0) donde un criterio o competencia base ha caído
// fuertemente, provocando alta dispersión en rúbricas a pesar de tener asistencia normal:
for _ in 0..<350 {
    let avg = clamp(Double.random(in: 4.5...6.0) + Double.random(in: -0.3...0.3), min: 4.0, max: 6.5)
    let delta = clamp(Double.random(in: -0.5...0.4) + Double.random(in: -0.2...0.2), min: -1.0, max: 0.8)
    let att = clamp(Double.random(in: 86.0...98.0) + Double.random(in: -2.0...2.0), min: 82.0, max: 100.0)
    let evalAbs = clamp(Double.random(in: 0.0...0.15) + Double.random(in: 0.0...0.05), min: 0.0, max: 0.22)
    let pending = clamp(Double.random(in: 0.08...0.30) + Double.random(in: -0.03...0.03), min: 0.05, max: 0.38)
    let rVar = clamp(Double.random(in: 2.0...3.8) + Double.random(in: -0.2...0.2), min: 1.6, max: 4.2)
    let inc = Double(Int.random(in: 0...1))
    
    avgGrades.append(avg)
    deltas.append(delta)
    attendances.append(att)
    evalAbsences.append(evalAbs)
    pendingRatios.append(pending)
    rubricVars.append(rVar)
    incidents.append(inc)
    labels.append("bottleneck_risk")
}

// 3. Evaluation Anomaly (Anomalía en la Evaluación)
// Desviación atípica en las notas o rúbricas: caída o salto drástico inexplicable sin
// relación con la asistencia (asistencia 92-100%, entregas al día), sugiriendo rúbrica mal
// calibrada o error de registro:
for _ in 0..<350 {
    let avg = clamp(Double.random(in: 5.5...8.5) + Double.random(in: -0.4...0.4), min: 5.0, max: 9.0)
    let delta = clamp(Double.random(in: -3.2...(-1.8)) + Double.random(in: -0.2...0.2), min: -4.5, max: -1.5)
    let att = clamp(Double.random(in: 92.0...100.0) + Double.random(in: -1.0...0.0), min: 88.0, max: 100.0)
    let evalAbs = clamp(Double.random(in: 0.0...0.08), min: 0.0, max: 0.12)
    let pending = clamp(Double.random(in: 0.0...0.10), min: 0.0, max: 0.15)
    let rVar = clamp(Double.random(in: 2.8...4.6) + Double.random(in: -0.2...0.2), min: 2.4, max: 5.0)
    let inc = 0.0
    
    avgGrades.append(avg)
    deltas.append(delta)
    attendances.append(att)
    evalAbsences.append(evalAbs)
    pendingRatios.append(pending)
    rubricVars.append(rVar)
    incidents.append(inc)
    labels.append("evaluation_anomaly")
}

// 4. Steady (Evolución Estable / Favorable)
// Alumnos en progresión regular sin señales de riesgo:
for _ in 0..<350 {
    let avg = clamp(Double.random(in: 6.0...9.6) + Double.random(in: -0.3...0.3), min: 5.5, max: 10.0)
    let delta = clamp(Double.random(in: -0.3...1.6) + Double.random(in: -0.1...0.1), min: -0.5, max: 2.5)
    let att = clamp(Double.random(in: 90.0...100.0) + Double.random(in: -2.0...0.0), min: 86.0, max: 100.0)
    let evalAbs = clamp(Double.random(in: 0.0...0.10), min: 0.0, max: 0.15)
    let pending = clamp(Double.random(in: 0.0...0.10), min: 0.0, max: 0.15)
    let rVar = clamp(Double.random(in: 0.1...1.1), min: 0.05, max: 1.4)
    let inc = Double(Int.random(in: 0...1))
    
    avgGrades.append(avg)
    deltas.append(delta)
    attendances.append(att)
    evalAbsences.append(evalAbs)
    pendingRatios.append(pending)
    rubricVars.append(rVar)
    incidents.append(inc)
    labels.append("steady")
}

df.append(column: Column(name: "averageGrade", contents: avgGrades))
df.append(column: Column(name: "gradeDelta", contents: deltas))
df.append(column: Column(name: "attendanceRate", contents: attendances))
df.append(column: Column(name: "evaluableDayAbsenceRatio", contents: evalAbsences))
df.append(column: Column(name: "pendingTaskRatio", contents: pendingRatios))
df.append(column: Column(name: "rubricVariance", contents: rubricVars))
df.append(column: Column(name: "incidentCount", contents: incidents))
df.append(column: Column(name: "patternType", contents: labels))

print("✓ Dataset creado con \(df.shape.rows) ejemplos y 7 variables normalizadas.")

print("\n[2/5] Dividiendo en Train (80%) y Test (20%)...")
let totalRows = df.shape.rows
let testCount = Int(Double(totalRows) * 0.2)
let trainRows = df.prefix(totalRows - testCount)
let testRows = df.suffix(testCount)

print("\n[3/5] Entrenando MLClassifier con CreateML...")
let classifier = try MLClassifier(trainingData: DataFrame(trainRows), targetColumn: "patternType")

let evaluation = classifier.evaluation(on: DataFrame(testRows))
let accuracy = (1.0 - evaluation.classificationError) * 100.0
print("✓ Modelo entrenado exitosamente.")
print(String(format: "  - Exactitud en test: %.2f%%", accuracy))
print(String(format: "  - Error de clasificación: %.4f", evaluation.classificationError))

print("\n[4/5] Guardando EducationalPatternsClassifier.mlmodel...")
let modelURL = targetMLDir.appendingPathComponent("EducationalPatternsClassifier.mlmodel")
let metadata = MLModelMetadata(
    author: "Mi Gestor Evaluaciones - Antigravity",
    shortDescription: "Clasificador tabular para detección temprana de patrones de desenganche, cuellos de botella y anomalías evaluativas.",
    version: "1.0.0"
)
try classifier.write(to: modelURL, metadata: metadata)
print("✓ Archivo .mlmodel guardado en: \(modelURL.path)")

print("\n[5/5] Compilando con coremlcompiler a .mlmodelc...")
let compiledDestDir = targetMLDir.appendingPathComponent("EducationalPatternsClassifier.mlmodelc")
// Eliminar versión previa si existe
try? FileManager.default.removeItem(at: compiledDestDir)

let compileProcess = Process()
compileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
compileProcess.arguments = ["coremlcompiler", "compile", modelURL.path, targetMLDir.path]
try compileProcess.run()
compileProcess.waitUntilExit()

if compileProcess.terminationStatus == 0 {
    print("✓ Modelo compilado a \(compiledDestDir.path)")
} else {
    print("⚠ coremlcompiler terminó con status \(compileProcess.terminationStatus)")
}

print("\n======================================================================")
print("  Proceso completado con éxito. Modelo listo para inferencia en ANE/CPU.")
print("======================================================================")
