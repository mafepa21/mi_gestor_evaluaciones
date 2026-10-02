import Foundation
import SwiftUI
import MiGestorKit

/// Categorías temáticas de las plantillas oficiales de rúbricas.
enum RubricTemplateCategory: String, CaseIterable, Identifiable {
    case all = "Todas"
    case physicalCondition = "Condición Física"
    case sportsAndGames = "Deportes y Juegos"
    case bodyExpression = "Expresión Corporal"
    case outdoorNature = "Medio Natural"
    case transversal = "Transversales y Coevaluación"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .physicalCondition:
            return "heart.fill"
        case .sportsAndGames:
            return "figure.run"
        case .bodyExpression:
            return "figure.dance"
        case .outdoorNature:
            return "leaf.fill"
        case .transversal:
            return "person.2.fill"
        }
    }
}

/// Nivel LOMLOE de una rúbrica oficial (1 a 4).
struct RubricTemplateLevel: Identifiable, Hashable {
    let id: String
    let order: Int
    let name: String
    let points: Int
    let description: String
}

/// Criterio ponderado de una plantilla de rúbrica.
struct RubricTemplateCriterion: Identifiable, Hashable {
    let id: String
    let name: String
    let weight: Double
    let levels: [RubricTemplateLevel]
}

/// Plantilla oficial de rúbrica lista para importación.
struct RubricTemplateItem: Identifiable, Hashable {
    let id: String
    let title: String
    let category: RubricTemplateCategory
    let subject: String
    let stage: String
    let description: String
    let criteria: [RubricTemplateCriterion]
}

/// Catálogo oficial de plantillas pedagógicas LOMLOE para Educación Física y materias competenciales.
enum RubricTemplateCatalog {
    /// Banco curado de plantillas oficiales LOMLOE.
    static let templates: [RubricTemplateItem] = [
        // 1. Calentamiento Autónomo
        RubricTemplateItem(
            id: "ef-calentamiento-autonomo",
            title: "Calentamiento General y Específico Autónomo",
            category: .physicalCondition,
            subject: "Educación Física",
            stage: "ESO y Bachillerato",
            description: "Evalúa la capacidad del alumnado para diseñar, dirigir y ejecutar una rutina de calentamiento completa respetando las fases fisiológicas y la prevención de lesiones.",
            criteria: [
                RubricTemplateCriterion(
                    id: "c1",
                    name: "Fase de activación y movilidad articular",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c1_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Omite articulaciones principales o realiza movimientos bruscos y desordenados sin seguir una progresión anatómica lógica."),
                        RubricTemplateLevel(id: "c1_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Recuerda la mayoría de articulaciones pero requiere indicaciones externas para mantener el orden céfalo-caudal."),
                        RubricTemplateLevel(id: "c1_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Ejecuta de manera ordenada y fluida la movilidad de todas las articulaciones con control postural adecuado."),
                        RubricTemplateLevel(id: "c1_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Dirige con soltura una rutina de movilidad dinámica adaptada a la actividad posterior, explicando la función de cada ejercicio.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c2",
                    name: "Activación vegetativa y pulsaciones progresivas",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c2_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Inicia con esfuerzos explosivos sin progresión cardiovascular o permanece pasivo."),
                        RubricTemplateLevel(id: "c2_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Realiza desplazamientos continuos aunque no gradúa la intensidad de forma equilibrada."),
                        RubricTemplateLevel(id: "c2_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Incrementa progresivamente la intensidad de la carrera y ejercicios de coordinación hasta alcanzar pulsaciones óptimas."),
                        RubricTemplateLevel(id: "c2_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Monitorea su propia frecuencia cardiaca y ajusta los desplazamientos para situar al grupo en la zona aeróbica idónea.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c3",
                    name: "Estiramientos dinámicos y tonificación previa",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c3_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Aplica rebotes lesivos o posturas incorrectas que comprometen la salud de la espalda."),
                        RubricTemplateLevel(id: "c3_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Realiza estiramientos estáticos pasivos pero olvida los grupos musculares solicitados en la sesión."),
                        RubricTemplateLevel(id: "c3_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Integra estiramientos dinámicos activos y ejercicios de fuerza isométrica o funcional de forma segura."),
                        RubricTemplateLevel(id: "c3_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Selecciona estiramientos dinámicos específicos que preparan con precisión el rango de movimiento de la tarea principal.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c4",
                    name: "Autonomía y actitud preventiva",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c4_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Muestra desinterés y solo calienta bajo supervisión constante y obligada del docente."),
                        RubricTemplateLevel(id: "c4_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Sigue la rutina con actitud pasiva y sin prestar atención a posibles riesgos del entorno."),
                        RubricTemplateLevel(id: "c4_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Actúa de forma autónoma con material adecuado y respetando el espacio del resto de compañeros."),
                        RubricTemplateLevel(id: "c4_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Muestra liderazgo positivo, corrige posturas de sus iguales con empatía y previene riesgos en el espacio de trabajo.")
                    ]
                )
            ]
        ),

        // 2. Resistencia Aeróbica
        RubricTemplateItem(
            id: "ef-resistencia-aerobica",
            title: "Resistencia Aeróbica y Dosificación del Esfuerzo",
            category: .physicalCondition,
            subject: "Educación Física",
            stage: "Secundaria y Bachillerato",
            description: "Valora la capacidad del alumno/a para regular el ritmo de carrera o esfuerzo continuo, controlar la respiración y aplicar la escala subjetiva de fatiga.",
            criteria: [
                RubricTemplateCriterion(
                    id: "c1",
                    name: "Mantenimiento del ritmo de carrera continuo",
                    weight: 1.2,
                    levels: [
                        RubricTemplateLevel(id: "c1_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Alterna sprints con paradas constantes por fatiga prematura y falta total de regulación."),
                        RubricTemplateLevel(id: "c1_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Consigue mantener el trote durante la mitad del tiempo establecido, debiendo caminar ocasionalmente."),
                        RubricTemplateLevel(id: "c1_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Sostiene un ritmo uniforme y continuo durante todo el test o prueba sin interrupciones."),
                        RubricTemplateLevel(id: "c1_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Demuestra un dominio milimétrico del ritmo, con zancada eficiente, economizando energía y acelerando en el tramo final.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c2",
                    name: "Control respiratorio y recuperación activa",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c2_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Hiperventila con sensación de ahogo y se sienta bruscamente en el suelo al terminar."),
                        RubricTemplateLevel(id: "c2_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Mantiene la respiración bucal forzada y tarda más de 5 minutos en estabilizarse tras la prueba."),
                        RubricTemplateLevel(id: "c2_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Sincroniza la respiración con la cadencia de pasos y realiza recuperación activa caminando."),
                        RubricTemplateLevel(id: "c2_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Aplica técnicas respiratorias profundas conscientes y muestra una recuperación cardiaca rápida y registrada.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c3",
                    name: "Conciencia fisiológica y escala de Borg",
                    weight: 0.8,
                    levels: [
                        RubricTemplateLevel(id: "c3_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Desconoce su nivel de esfuerzo subjetivo y no sabe localizar el pulso radial o carotídeo."),
                        RubricTemplateLevel(id: "c3_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Localiza las pulsaciones con ayuda pero confunde los rangos saludables de entrenamiento."),
                        RubricTemplateLevel(id: "c3_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Calcula con precisión su FC en 15 segundos y evalúa su esfuerzo de 1 a 10 con la escala RPE/Borg."),
                        RubricTemplateLevel(id: "c3_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Relaciona con soltura su FC de reposo, esfuerzo y recuperación con las zonas de salud cardiovascular.")
                    ]
                )
            ]
        ),

        // 3. Deportes de Invasión
        RubricTemplateItem(
            id: "ef-deportes-invasion",
            title: "Toma de Decisiones y Táctica en Deportes de Invasión",
            category: .sportsAndGames,
            subject: "Educación Física",
            stage: "Primaria, ESO y Bachillerato",
            description: "Analiza la comprensión táctica en deportes colectivos (baloncesto, fútbol sala, balonmano, ultimate): desmarques, conservación de balón, repliegue y Fair Play.",
            criteria: [
                RubricTemplateCriterion(
                    id: "c1",
                    name: "Ocupación inteligente de espacios libres y desmarque",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c1_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Se aglomera alrededor del balón impidiendo la circulación de sus compañeros de equipo."),
                        RubricTemplateLevel(id: "c1_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Se desmarca en estático cuando se le pide, pero vuelve a perder la posición útil de juego."),
                        RubricTemplateLevel(id: "c1_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Crea líneas de pase continuas con cambios de dirección y ritmo en función del poseedor del balón."),
                        RubricTemplateLevel(id: "c1_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Lee las trayectorias defensivas, arrastra marcas para liberar a un compañero y genera superioridades numéricas.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c2",
                    name: "Toma de decisiones con balón (Pase, Bote o Lanzamiento)",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c2_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Retiene el balón de forma individualista hasta perderlo o lo lanza sin mirar hacia dónde va."),
                        RubricTemplateLevel(id: "c2_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Ejecuta pases seguros únicamente al compañero más próximo, sin explorar opciones de progresión."),
                        RubricTemplateLevel(id: "c2_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Discrimina acertadamente entre pasar al compañero libre, avanzar mediante bote o finalizar con tiro."),
                        RubricTemplateLevel(id: "c2_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Anticipa la acción, toma decisiones en milisegundos bajo presión y elige siempre la opción más eficaz para el equipo.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c3",
                    name: "Transición y actitud defensiva",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c3_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Se desconecta tras perder el balón y camina en la pista sin intentar recuperar o defender."),
                        RubricTemplateLevel(id: "c3_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Defiende solo cuando el rival con balón está cerca, perdiendo de vista a su atacante asignado."),
                        RubricTemplateLevel(id: "c3_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Realiza el balance defensivo rápido situándose entre su adversario directo y la propia meta."),
                        RubricTemplateLevel(id: "c3_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Comunica ayudas defensivas, intercepta líneas de pase y protege el centro de la pista con solidez.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c4",
                    name: "Respeto al reglamento y Juego Limpio (Fair Play)",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c4_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Protesta decisiones arbitrales, comete faltas intencionadas o menosprecia a los rivales."),
                        RubricTemplateLevel(id: "c4_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Acepta las reglas con resignación pero muestra gestos de frustración cuando el resultado es adverso."),
                        RubricTemplateLevel(id: "c4_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Asume las decisiones arbitrales, felicita a los rivales y colabora en el montaje y recogida de material."),
                        RubricTemplateLevel(id: "c4_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Es un modelo de deportividad: arbitra con imparcialidad, ayuda al compañero rival caído y prima los valores sobre la victoria.")
                    ]
                )
            ]
        ),

        // 4. Deportes de Red y Raqueta
        RubricTemplateItem(
            id: "ef-deportes-raqueta",
            title: "Técnica y Táctica en Deportes de Red / Raqueta",
            category: .sportsAndGames,
            subject: "Educación Física",
            stage: "ESO y Bachillerato",
            description: "Evalúa los gestos técnicos básicos (derecha, revés, saque), colocación en pista y lectura de trayectorias en bádminton, pádel o tenis de mesa.",
            criteria: [
                RubricTemplateCriterion(
                    id: "c1",
                    name: "Posición básica de espera y juego de pies",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c1_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Permanece con las piernas rígidas y la raqueta caída, llegando siempre tarde al golpeo."),
                        RubricTemplateLevel(id: "c1_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Adopta la postura flexionada solo en el saque, olvidando recuperar el centro de la pista."),
                        RubricTemplateLevel(id: "c1_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Se desplaza con pasos de ajuste fluidos y recupera sistemáticamente la zona de equilibrio tras cada golpe."),
                        RubricTemplateLevel(id: "c1_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Anticipa la trayectoria del móvil con movimientos explosivos y economía de esfuerzo.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c2",
                    name: "Dominio de los golpeos fundamentales y control del móvil",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c2_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Falla el impacto frecuentemente o envía la pelota/volante sistemáticamente fuera de los límites."),
                        RubricTemplateLevel(id: "c2_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Impacta con control en la derecha pero muestra graves dificultades de agarre o golpeo en el revés."),
                        RubricTemplateLevel(id: "c2_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Ejecuta derecha, revés y saque con empuñadura correcta, manteniendo el volante en juego durante varios intercambios."),
                        RubricTemplateLevel(id: "c2_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Modula la altura, profundidad y potencia del impacto, alternando dejadas, globos y remates con gran precisión.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c3",
                    name: "Estrategia de juego y búsqueda de espacios libres",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c3_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Golpea sin intención táctica, enviando el móvil directamente al cuerpo del adversario."),
                        RubricTemplateLevel(id: "c3_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Intenta variar direcciones pero comete numerosos errores no forzados por precipitación."),
                        RubricTemplateLevel(id: "c3_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Dirige el volante al espacio libre más alejado del rival, provocando su desplazamiento."),
                        RubricTemplateLevel(id: "c3_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Construye el punto con paciencia, detecta los puntos débiles del contrincante y define con criterio táctico.")
                    ]
                )
            ]
        ),

        // 5. Expresión Corporal y Danza
        RubricTemplateItem(
            id: "ef-expresion-corporal",
            title: "Composición Coreográfica y Expresión Corporal Colectiva",
            category: .bodyExpression,
            subject: "Educación Física",
            stage: "Primaria, ESO y Bachillerato",
            description: "Valora la creatividad expresiva, el sentido del ritmo, el trabajo coreográfico grupal y la superación de la vergüenza en representaciones motrices.",
            criteria: [
                RubricTemplateCriterion(
                    id: "c1",
                    name: "Sincronización rítmica y tempo musical",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c1_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Se muestra desacompasado con la base musical y requiere mirar continuamente a sus compañeros."),
                        RubricTemplateLevel(id: "c1_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Sigue el pulso en movimientos sencillos pero se desincroniza al introducir cambios de compás o transiciones."),
                        RubricTemplateLevel(id: "c1_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Ajusta con precisión los pasos y figuras al tempo musical de forma autónoma."),
                        RubricTemplateLevel(id: "c1_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Interioriza el ritmo musical interpretando matices sonoros, silencios y acentos rítmicos con gran plasticidad.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c2",
                    name: "Riqueza motriz y ocupación del espacio escénico",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c2_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Permanece en un único punto del escenario repitiendo el mismo gesto monótono."),
                        RubricTemplateLevel(id: "c2_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Utiliza un único nivel espacial (medio) con desplazamientos lineales poco variados."),
                        RubricTemplateLevel(id: "c2_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Combina niveles bajo (suelo), medio y alto (saltos/elevaciones) con formaciones grupales diversas."),
                        RubricTemplateLevel(id: "c2_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Diseña figuras coreográficas complejas, canones, diagonales y contrastes de velocidad que llenan armónicamente el espacio.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c3",
                    name: "Comunicación no verbal, desinhibición y emoción",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c3_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Risas nerviosas continuas, rigidez facial y evidente falta de implicación por timidez."),
                        RubricTemplateLevel(id: "c3_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Cumple con la coreografía de forma mecánica, transmitiendo escasa emoción o expresividad."),
                        RubricTemplateLevel(id: "c3_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Muestra seguridad en sí mismo, expresión facial coherente con la temática y contacto visual con el público."),
                        RubricTemplateLevel(id: "c3_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Conecta emocionalmente con los espectadores a través del gesto, mirada y energía corporal con auténtico carisma.")
                    ]
                )
            ]
        ),

        // 6. Actividades en el Medio Natural
        RubricTemplateItem(
            id: "ef-medio-natural",
            title: "Carrera de Orientación y Respeto al Medio Natural",
            category: .outdoorNature,
            subject: "Educación Física",
            stage: "Secundaria y Bachillerato",
            description: "Analiza la competencia para interpretar planos y mapas topográficos, trazar itinerarios en el entorno natural o escolar y aplicar normas de no dejar rastro.",
            criteria: [
                RubricTemplateCriterion(
                    id: "c1",
                    name: "Lectura de mapas y orientación con brújula",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c1_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "No sabe colocar el mapa con respecto al norte ni reconoce la leyenda básica de colores y símbolos."),
                        RubricTemplateLevel(id: "c1_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Identifica elementos evidentes (caminos, edificios) pero se desorienta en áreas abiertas o vegetación."),
                        RubricTemplateLevel(id: "c1_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Orienta el mapa con brújula, estima distancias mediante talonamiento y sigue rumbos con precisión."),
                        RubricTemplateLevel(id: "c1_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Interpreta con solvencia curvas de nivel y elementos sutiles del relieve, eligiendo la ruta más eficiente.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c2",
                    name: "Toma de decisiones en carrera y localización de balizas",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c2_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Sigue a otros grupos a ciegas sin verificar la numeración de la baliza encontrada."),
                        RubricTemplateLevel(id: "c2_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Encuentra las balizas pero comete errores de pinzado por falta de comprobación del código de control."),
                        RubricTemplateLevel(id: "c2_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Planifica la ruta antes de salir de cada control y localiza los puntos objetivo en el tiempo fijado."),
                        RubricTemplateLevel(id: "c2_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Adapta la velocidad de carrera a la dificultad técnica del terreno y rectifica rumbos sin vacilar.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c3",
                    name: "Conducta ecológica y seguridad en el entorno",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c3_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Arroja envoltorios o daña la flora del entorno, desoyendo las normas del parque/entorno natural."),
                        RubricTemplateLevel(id: "c3_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Guarda sus residuos pero necesita recordatorios para no salirse de los senderos protegidos."),
                        RubricTemplateLevel(id: "c3_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Aplica estrictamente el principio de 'no dejar rastro' y cuida la indumentaria adecuada."),
                        RubricTemplateLevel(id: "c3_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Sensibiliza al grupo sobre la sostenibilidad, recoge residuos ajenos y vela por la seguridad colectiva.")
                    ]
                )
            ]
        ),

        // 7. Coevaluación Trabajo en Equipo
        RubricTemplateItem(
            id: "transversal-coevaluacion",
            title: "Rúbrica de Coevaluación del Trabajo en Equipo",
            category: .transversal,
            subject: "Educación Física y Materias LOMLOE",
            stage: "Todos los niveles",
            description: "Instrumento diseñado para que los alumnos evalúen constructivamente la aportación de sus pares en proyectos, retos cooperativos o coreografías grupales.",
            criteria: [
                RubricTemplateCriterion(
                    id: "c1",
                    name: "Compromiso y aportación activa a las tareas del equipo",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c1_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Raras veces participa, delega sus responsabilidades en el resto y se distrae con facilidad."),
                        RubricTemplateLevel(id: "c1_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Colabora únicamente cuando se le pide de forma explícita, mostrando iniciativa limitada."),
                        RubricTemplateLevel(id: "c1_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Cumple con dedicación el rol asignado y aporta ideas constructivas al proyecto común."),
                        RubricTemplateLevel(id: "c1_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Lidera con entusiasmo, dinamiza al equipo y se anticipa a las dificultades con soluciones eficaces.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c2",
                    name: "Escucha activa y resolución pacífica de diferencias",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c2_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Impone su criterio sin escuchar a los demás o genera discusiones estériles."),
                        RubricTemplateLevel(id: "c2_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Tolera las opiniones distintas pero defiende su postura con cierta rigidez."),
                        RubricTemplateLevel(id: "c2_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Respeta el turno de palabra, valora las propuestas del grupo y busca el consenso."),
                        RubricTemplateLevel(id: "c2_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Es un mediador natural que fomenta un clima de confianza, empatía y valoración positiva de cada voz.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c3",
                    name: "Apoyo y refuerzo motivacional hacia los compañeros",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c3_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Critica los fallos de sus iguales o muestra indiferencia ante sus esfuerzos."),
                        RubricTemplateLevel(id: "c3_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Se centra en su propia tarea sin fijarse en si algún compañero necesita ayuda adicional."),
                        RubricTemplateLevel(id: "c3_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Anima y felicita los progresos de sus iguales ofreciendo ayuda cuando detecta dificultades."),
                        RubricTemplateLevel(id: "c3_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Genera una atmósfera de superación compartida donde el error se celebra como oportunidad de aprendizaje.")
                    ]
                )
            ]
        ),

        // 8. Autoevaluación Hábitos Saludables
        RubricTemplateItem(
            id: "transversal-autoevaluacion-habitos",
            title: "Rúbrica de Autoevaluación de Hábitos Saludables",
            category: .transversal,
            subject: "Educación Física",
            stage: "Primaria y Secundaria",
            description: "Permite al alumno/a tomar conciencia de su higiene personal, calzado deportivo adecuado, hidratación y perseverancia en la práctica de actividad física.",
            criteria: [
                RubricTemplateCriterion(
                    id: "c1",
                    name: "Equipación deportiva adecuada e higiene personal",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c1_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Acude sin calzado adecuado o indumentaria deportiva, poniendo en riesgo su seguridad articular."),
                        RubricTemplateLevel(id: "c1_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Lleva ropa deportiva pero olvida el aseo posterior o el cambio de camiseta de recambio."),
                        RubricTemplateLevel(id: "c1_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Viste indumentaria técnica adecuada y realiza el lavado de manos y aseo al concluir la sesión."),
                        RubricTemplateLevel(id: "c1_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Es plenamente autónomo y ejemplar en su higiene: neceser completo, hidratación propia y vestimenta impecable.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c2",
                    name: "Superación personal y esfuerzo sostenido",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c2_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "Abandona ante la primera dificultad o sensación de fatiga leve."),
                        RubricTemplateLevel(id: "c2_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Se esfuerza solo en los juegos que le gustan especialmente, desentendiéndose en el resto."),
                        RubricTemplateLevel(id: "c2_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Mantiene la constancia en todas las actividades buscando mejorar sus marcas personales."),
                        RubricTemplateLevel(id: "c2_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Muestra resiliencia ejemplar, disfruta del proceso de esfuerzo y se fija metas de superación realistas.")
                    ]
                ),
                RubricTemplateCriterion(
                    id: "c3",
                    name: "Reflexión crítica y autorregulación del aprendizaje",
                    weight: 1.0,
                    levels: [
                        RubricTemplateLevel(id: "c3_l1", order: 1, name: "Nivel 1 (Inicial)", points: 1, description: "No sabe identificar en qué aspectos ha mejorado ni qué dificultades tiene pendientes."),
                        RubricTemplateLevel(id: "c3_l2", order: 2, name: "Nivel 2 (Básico)", points: 2, description: "Reconoce sus puntos fuertes pero le cuesta aceptar áreas de mejora con objetividad."),
                        RubricTemplateLevel(id: "c3_l3", order: 3, name: "Nivel 3 (Avanzado)", points: 3, description: "Analiza con honestidad sus logros y establece pautas concretas para continuar progresando."),
                        RubricTemplateLevel(id: "c3_l4", order: 4, name: "Nivel 4 (Excelente)", points: 4, description: "Conecta los aprendizajes de clase con sus hábitos de vida activa fuera del centro escolar de forma madura.")
                    ]
                )
            ]
        )
    ]

    /// Genera la representación TSV que entiende `KmpBridge.importRubricDraft(tsv:)`.
    static func generateTsv(for template: RubricTemplateItem) -> String {
        var lines: [String] = []
        let levels = template.criteria.first?.levels ?? []
        let headerCols = ["Criterio"] + levels.map { "\($0.name) (\($0.points))" }
        lines.append(headerCols.joined(separator: "\t"))

        for criterion in template.criteria {
            let cleanDescriptions = criterion.levels.map {
                $0.description
                    .replacingOccurrences(of: "\t", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
            }
            let rowCols = [criterion.name] + cleanDescriptions
            lines.append(rowCols.joined(separator: "\t"))
        }

        return lines.joined(separator: "\n")
    }

    /// Importa una plantilla oficial del catálogo en la base de datos local usando `KmpBridge`.
    @MainActor
    static func importTemplate(
        _ template: RubricTemplateItem,
        into bridge: KmpBridge,
        targetClassId: Int64? = nil
    ) async throws -> Int64 {
        let tsv = generateTsv(for: template)
        try await bridge.importRubricDraft(tsv: tsv)
        bridge.updateRubricName(template.title)
        bridge.updateRubricInstructions(template.description)
        if let targetClassId {
            bridge.selectRubricClass(targetClassId)
        }
        for (idx, criterion) in template.criteria.enumerated() {
            bridge.updateRubricCriterionWeight(at: idx, weight: criterion.weight)
        }
        return try await bridge.saveRubricFromBuilderReturningId()
    }
}
