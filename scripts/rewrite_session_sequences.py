#!/usr/bin/env python3
"""Rewrite the active session-sequencing corpus into the weekly CLIL import format.

The source files are intentionally treated as source material, not as a schema. The
rewriter keeps the original detail inside each teacher guide while emitting one
WEEK with a LONG BLOCK and a SHORT BLOCK, each with an importable activity table.
"""

from __future__ import annotations

import argparse
import html
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


ROOT = Path("/Users/mariofernandez/Desktop/Programaciones/output/Programación aula/Situaciones de aprendizaje")
HEADING_RE = re.compile(r"^(#{2,4})\s+(.+?)\s*$")
WEEK_RE = re.compile(r"^(?:SEMANA|SETMANA|WEEK)\s+(\d+)(?:\s*[.\-–—:]\s*(.*))?$", re.I)
SESSION_RE = re.compile(
    r"^(?:SESI(?:ÓN|ON|ONES|ONS)?|SESSION(?:S)?|SESSI(?:Ó|O)?(?:NS)?)\s+"
    r"(\d+)(?:\s*(?:a|to|[-–—])\s*(\d+))?(?:\s*[.\-–—:]\s*(.*))?$",
    re.I,
)
BLOCK_RE = re.compile(r"^(?:BLOQUE|BLOCK)\s+(\d+)(?:\s*[.\-–—:]\s*(.*))?$", re.I)


@dataclass
class Activity:
    time: str
    phase: str
    activity: str
    teacher: str
    students: str
    clil: str
    evidence: str
    materials: str = ""
    adaptations: str = ""


@dataclass
class Week:
    number: int
    title: str
    body: str
    long_body: str
    short_body: str
    objective: str
    criteria: str
    materials: str


def clean(value: str) -> str:
    value = re.sub(r"<br\s*/?>", "\n", value, flags=re.I)
    value = re.sub(r"^\s*#{2,6}\s+", "", value, flags=re.M)
    value = re.sub(r"\s+", " ", value.replace("\u00a0", " ")).strip()
    return value.strip("| ")


def plain(value: str) -> str:
    value = re.sub(r"[`*_]+", "", value)
    value = re.sub(r"\[[^]]+\]\([^)]*\)", lambda m: m.group(0).split("]")[0].lstrip("["), value)
    return clean(value)


def norm(value: str) -> str:
    return plain(value).casefold()


TRANSLATIONS = (
    (r"\bcalentamiento\b", "Warm-up"),
    (r"\bparte principal\b", "Main practice"),
    (r"\bvuelta a la calma\b", "Cool-down"),
    (r"\bestiramientos?\b", "Stretching"),
    (r"\bdesplazamientos?\b", "Movement patterns"),
    (r"\bcircuito\b", "Circuit"),
    (r"\bpor parejas\b", "in pairs"),
    (r"\bpor grupos\b", "in groups"),
    (r"\bjuego\b", "game"),
    (r"\btorneo\b", "tournament"),
    (r"\bpartido\b", "match"),
    (r"\breglas?\b", "rules"),
    (r"\bseguridad\b", "safety"),
    (r"\bcooperaci[oó]n\b", "cooperation"),
    (r"\bparticipaci[oó]n\b", "participation"),
    (r"\bobservaci[oó]n docente\b", "teacher observation"),
    (r"\bobservaci[oó]n\b", "observation"),
    (r"\breflexi[oó]n\b", "reflection"),
    (r"\bevaluaci[oó]n\b", "assessment"),
    (r"\bauto[- ]evaluaci[oó]n\b", "self-assessment"),
    (r"\bobjetivo\b", "objective"),
    (r"\bmaterial(?:es)?\b", "materials"),
)


def englishize(value: str) -> str:
    translated = plain(value)
    for pattern, replacement in TRANSLATIONS:
        translated = re.sub(pattern, replacement, translated, flags=re.I)
    return translated


def split_heading_sections(text: str) -> list[tuple[str, str]]:
    lines = text.splitlines()
    starts: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        match = HEADING_RE.match(line)
        if not match:
            continue
        title = plain(match.group(2))
        lowered = norm(title)
        if WEEK_RE.match(title) or SESSION_RE.match(title) or BLOCK_RE.match(title):
            starts.append((index, title))
        elif re.match(r"^(?:session|sesion|sesión|bloque|block)\s+\d+\b", lowered):
            starts.append((index, title))
    if not starts:
        return [("Sequence", text)]
    sections: list[tuple[str, str]] = []
    for position, (index, title) in enumerate(starts):
        end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
        sections.append((title, "\n".join(lines[index + 1 : end]).strip()))
    return sections


def number_title(title: str, fallback: int) -> tuple[int, str]:
    if match := WEEK_RE.match(title):
        return int(match.group(1)), clean(match.group(2) or "") or title
    if match := BLOCK_RE.match(title):
        return int(match.group(1)), clean(match.group(2) or "") or title
    if match := SESSION_RE.match(title):
        return int(match.group(1)), clean(match.group(3) or "") or title
    return fallback, title


def expand_ranges(sections: list[tuple[str, str]]) -> list[tuple[int, str, str]]:
    expanded: list[tuple[int, str, str]] = []
    for fallback, (title, body) in enumerate(sections, 1):
        number, label = number_title(title, fallback)
        match = SESSION_RE.match(title)
        if match and match.group(2):
            end = int(match.group(2))
            for current in range(number, end + 1):
                expanded.append((current, f"Session {current} - {label}", body))
        else:
            expanded.append((number, label, body))
    expanded.sort(key=lambda item: item[0])
    return expanded


def value_after_label(body: str, labels: Iterable[str]) -> str:
    label_pattern = "|".join(re.escape(label) for label in labels)
    lines = body.splitlines()
    for index, line in enumerate(lines):
        match = re.match(rf"^\s*(?:\*\*)?(?:{label_pattern})(?:\*\*)?\s*[:\-]\s*(.*)$", line, re.I)
        if not match:
            continue
        value = englishize(match.group(1))
        if value:
            return value
        for following in lines[index + 1 :]:
            candidate = englishize(following)
            if candidate:
                return candidate
    return ""


def split_variants(body: str) -> tuple[str, str, str]:
    lines = body.splitlines()
    markers: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        marker_text = re.sub(r"^[#*\s]+", "", line).strip()
        lowered = norm(marker_text)
        if re.match(r"(?:long block|bloque largo|double version|versión doble|version doble)\b", lowered):
            markers.append((index, "long"))
        elif re.match(r"(?:short block|bloque corto|simple version|versión simple|version simple)\b", lowered):
            markers.append((index, "short"))
    if not markers:
        return body, body, body
    shared = "\n".join(lines[: markers[0][0]]).strip()
    long_parts: list[str] = []
    short_parts: list[str] = []
    for position, (index, kind) in enumerate(markers):
        end = markers[position + 1][0] if position + 1 < len(markers) else len(lines)
        content = "\n".join(lines[index + 1 : end]).strip()
        if kind == "long":
            long_parts.append(content)
        else:
            short_parts.append(content)
    long_body = "\n".join(part for part in long_parts if part).strip() or body
    short_body = "\n".join(part for part in short_parts if part).strip() or body
    return shared, long_body, short_body


def table_rows(body: str) -> list[Activity]:
    lines = body.splitlines()
    activities: list[Activity] = []
    index = 0
    while index < len(lines):
        if not lines[index].lstrip().startswith("|"):
            index += 1
            continue
        table: list[list[str]] = []
        while index < len(lines) and lines[index].lstrip().startswith("|"):
            cells = [clean(cell) for cell in lines[index].strip().strip("|").split("|")]
            if cells and not all(re.fullmatch(r"[-: ]+", cell or "-") for cell in cells):
                table.append(cells)
            index += 1
        if len(table) < 2:
            continue
        header = [norm(cell) for cell in table[0]]

        def column(tokens: tuple[str, ...]) -> int | None:
            for position, cell in enumerate(header):
                if any(token in cell for token in tokens):
                    return position
            return None

        time_col = column(("time", "hora", "tiempo"))
        phase_col = column(("phase", "fase"))
        activity_col = column(("activity", "actividad", "task", "tarea"))
        teacher_col = column(("teacher", "profesor", "docente"))
        student_col = column(("student", "alumno", "learner", "alumnado"))
        clil_col = column(("clil", "language", "lengua", "scaffolding", "andamiaje"))
        evidence_col = column(("evidence", "evidencia", "assessment", "evaluacion"))
        materials_col = column(("material", "materials", "materiales"))
        adaptation_col = column(("adaptation", "adaptaciones", "inclusion"))

        def get(row: list[str], position: int | None) -> str:
            return row[position] if position is not None and position < len(row) else ""

        for row in table[1:]:
            activity = get(row, activity_col)
            if not activity:
                activity = " / ".join(value for value in row if value)
            if not activity:
                continue
            activities.append(
                Activity(
                    time=get(row, time_col),
                    phase=get(row, phase_col),
                    activity=plain(activity),
                    teacher=plain(get(row, teacher_col)),
                    students=plain(get(row, student_col)),
                    clil=plain(get(row, clil_col)),
                    evidence=plain(get(row, evidence_col)),
                    materials=plain(get(row, materials_col)),
                    adaptations=plain(get(row, adaptation_col)),
                )
            )
    return activities


def chunks_from_text(body: str) -> list[Activity]:
    lines = body.splitlines()
    candidates: list[tuple[str, str]] = []
    current_title = "Teaching sequence"
    current: list[str] = []
    phase_tokens = (
        "warm-up", "warm up", "calentamiento", "briefing", "asamblea", "main part",
        "parte principal", "practice", "práctica", "station", "estacion", "closure",
        "cierre", "cool-down", "cool down", "vuelta a la calma", "evaluation", "evaluación",
        "reflection", "reflexión", "challenge", "reto", "tournament", "torneo",
    )

    def flush() -> None:
        nonlocal current
        text = plain(" ".join(current))
        if text:
            candidates.append((current_title, text))
        current = []

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if re.match(r"^\s*(?:\*\*)?(?:objective|objectives|objetivo|objetivos|criteria|criterion|criterios|criterio|materials|material|materiales|evaluation|evaluación)\b", stripped, re.I):
            continue
        heading = HEADING_RE.match(stripped)
        title = plain(heading.group(2)) if heading else ""
        lowered = norm(title or stripped)
        is_phase = bool(title) and any(token in lowered for token in phase_tokens)
        time_match = re.match(r"(?:⏱️\s*)?([0-9]{1,3}\s*['′]?(?:\s*[-–—]\s*[0-9]{1,3}\s*['′]?)?)\s*:?\s*(.*)", stripped)
        if is_phase or time_match:
            flush()
            current_title = englishize(title or (time_match.group(2) if time_match else stripped))
            if time_match and time_match.group(2):
                current_title = englishize(time_match.group(2))
            continue
        if heading:
            flush()
            current_title = "Practice"
            continue
        if stripped.startswith("-") or re.match(r"^\d+[.)]\s", stripped):
            if len(current) > 2:
                flush()
            current.append(stripped.lstrip("- ").lstrip("0123456789.) "))
        else:
            current.append(stripped)
    flush()
    if not candidates:
        text = plain(body)
        candidates = [("Teaching sequence", text[:1800] or "Follow the planned sequence.")]

    activities: list[Activity] = []
    for title, text in candidates:
        name = englishize(title)
        bold_match = re.search(r"\*\*([^*]{3,100})\*\*", text)
        if bold_match:
            name = englishize(bold_match.group(1))
        lowered = norm(title)
        if any(token in lowered for token in ("warm", "calent", "briefing", "asamblea")):
            students = "Follow the signal, maintain safe spacing, and name the key movement or rule."
        elif any(token in lowered for token in ("closure", "cierre", "cool", "vuelta", "evaluation", "evaluación", "reflection", "reflexión")):
            students = "Recover, record the evidence, and state one improvement or next step."
        else:
            students = "Perform the task, rotate roles, and explain one decision or adjustment to a partner."
        activities.append(
            Activity(
                time="",
                phase=englishize(title),
                activity=name,
                teacher=text[:1800],
                students=students,
                clil="",
                evidence="",
            )
        )
    return activities


def enrich(activities: list[Activity], subject: str) -> list[Activity]:
    subject_words = "pass, receive, defend, space, support" if any(
        word in norm(subject) for word in ("basket", "handball", "balonmano", "volley", "voleibol", "colpbol", "frisbee", "pilota")
    ) else "warm-up, effort, posture, recovery, feedback"
    result: list[Activity] = []
    for item in activities:
        clil = englishize(item.clil) or (
            f"Language goal: explain a choice and give respectful feedback. Vocabulary: {subject_words}. "
            "Sentence stems: “We choose… because…”, “I noticed…”, “Could you show…?”"
        )
        evidence = englishize(item.evidence) or "Teacher checklist: safe execution, active participation, target strategy, and one spoken English contribution."
        source_detail = englishize(item.teacher)
        teacher = item.teacher if item.teacher.startswith("Teacher cue (English):") else (
            "Teacher cue (English): state the aim and success criteria; model the first step; check safety and understanding; "
            "then circulate and give one precise feedback cue. "
            f"Lesson detail: {source_detail}"
            if source_detail
            else "Teacher cue (English): state the aim and success criteria; model the first step; check safety and understanding; then circulate and give one precise feedback cue."
        )
        students = englishize(item.students) or "Complete the task, rotate roles, and report one observation using the sentence stem."
        materials = englishize(item.materials) or "Equipment and visual cards named in the lesson setup; observation or recording sheet."
        adaptations = englishize(item.adaptations) or "Use a visual model, adjust space, distance or equipment, and keep the evidence target stable."
        result.append(Activity(item.time, englishize(item.phase) or "Practice", englishize(item.activity), teacher, students, clil, evidence, materials, adaptations))
    return result


def assign_times(activities: list[Activity], total: int) -> list[Activity]:
    if not activities:
        return []
    usable = len(activities)
    result: list[Activity] = []
    for index, item in enumerate(activities):
        if item.time and re.search(r"\d", item.time):
            time = item.time.replace("'", "′").replace("’", "′")
        else:
            start = round(index * total / usable)
            end = round((index + 1) * total / usable)
            time = f"{start}′–{end}′"
        result.append(Activity(time, item.phase, item.activity, item.teacher, item.students, item.clil, item.evidence, item.materials, item.adaptations))
    return result


def make_weeks(text: str) -> list[Week]:
    title = plain(next((line[2:].strip() for line in text.splitlines() if line.startswith("# ")), "Session sequence"))
    sections = split_heading_sections(text)
    if "**Import rule:**" in text:
        canonical_sections: list[tuple[str, str]] = []
        for section_title, section_body in sections:
            if not WEEK_RE.match(section_title):
                continue
            _, section_label = number_title(section_title, 1)
            if re.match(r"(?:long block|short block)\b", norm(section_label)):
                continue
            canonical_sections.append((section_title, section_body))
        if canonical_sections:
            sections = canonical_sections
    expanded = expand_ranges(sections)
    weeks: list[Week] = []
    for number, label, body in expanded:
        shared, long_body, short_body = split_variants(body)
        objective = value_after_label(shared + "\n" + body, ("Objective", "Objectives", "Objetivo", "Objetivos"))
        criteria = value_after_label(shared + "\n" + body, ("Criteria", "Criterion", "Criterios", "Criterio", "Evaluation"))
        materials = value_after_label(shared + "\n" + body, ("Materials", "Material", "Materiales"))
        weeks.append(Week(number, label or f"Week {number}", shared, long_body, short_body, objective, criteria, materials))
    if not weeks:
        weeks.append(Week(1, title, text, text, text, "", "", ""))
    return weeks


def markdown_table(activities: list[Activity]) -> str:
    rows = [
        "| Time | Phase | Activity | Teacher instructions | Student actions | CLIL focus | Evidence | Materials | Adaptations |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for item in activities:
        cells = [item.time, item.phase, item.activity, item.teacher, item.students, item.clil, item.evidence, item.materials, item.adaptations]
        rows.append("| " + " | ".join(clean(cell).replace("|", "/").replace("\n", "<br>") for cell in cells) + " |")
    return "\n".join(rows)


def render_markdown(source: Path, title: str, weeks: list[Week]) -> str:
    lines = [
        f"# {title} - Weekly Session Sequence",
        "",
        "**Language:** English delivery with CLIL support and explicit teacher prompts.",
        "**Planning rule:** Each week contains one LONG BLOCK (90 effective minutes) and one SHORT BLOCK (30 effective minutes). The app assigns the long block to two consecutive timetable slots and the short block to one simple slot, independently of whether the group has the long day on Monday or Friday.",
        "**Import rule:** Keep the table headers unchanged. They are the structured contract used by the app.",
        "",
        "## Teacher operating key",
        "",
        "- **Before class:** prepare the listed materials, display the CLIL sentence stems, and assign roles before movement starts.",
        "- **During class:** use the teacher instructions as cues, observe the evidence column, and adapt space, distance, equipment, or role without removing participation.",
        "- **After class:** record one piece of evidence and one next step in the session journal.",
        "",
        f"**Source file normalised:** `{source.name}`. The pedagogical source detail is retained in each activity teacher guide and in the final trace section.",
        "",
    ]
    for week in weeks:
        shared_activities = enrich(table_rows(week.body) or chunks_from_text(week.body), title)
        long_activities = enrich(table_rows(week.long_body) or chunks_from_text(week.long_body), title)
        short_activities = enrich(table_rows(week.short_body) or chunks_from_text(week.short_body), title)
        if week.long_body == week.body:
            long_activities = long_activities + [
                Activity(
                    "60′–90′", "Extension", "Extended practice, feedback and transfer",
                    "Use the additional time to repeat the key task, rotate the observer and performer roles, give one individual cue, and offer the agreed adaptation.",
                    "Repeat the task, record one improvement, and support a peer using the CLIL sentence stem.",
                    "Vocabulary: improve, adjust, repeat, support. Sentence stem: “Next time I will… because…”.",
                    "One recorded improvement and one teacher observation.",
                    "Equipment and visual cards named in the lesson setup; observation or recording sheet.",
                    "Use a visual model, adjust space, distance or equipment, and keep the evidence target stable.",
                )
            ]
        long_activities = assign_times(long_activities, 90)
        short_activities = assign_times(short_activities, 30)
        lines += [
            f"## WEEK {week.number} - {plain(week.title)}",
            "",
            f"**Objective:** {englishize(week.objective) or 'Achieve the shared learning intention through safe participation, purposeful practice and reflection.'}",
            f"**Criteria / evidence focus:** {englishize(week.criteria) or 'Safe execution, cooperation, decision-making, communication and reflective improvement.'}",
            f"**Materials:** {englishize(week.materials) or 'Use the equipment, visual cards and recording sheet named in the activity table.'}",
            "",
            "### LONG BLOCK (90 effective minutes)",
            "",
            markdown_table(long_activities),
            "",
            "### SHORT BLOCK (30 effective minutes)",
            "",
            markdown_table(short_activities),
            "",
            "### Inclusion and teacher adaptations",
            "",
            "- Offer a visual model, reduced space or distance, lighter or larger equipment, peer support, and an opt-in intensity level.",
            "- Keep the evidence target stable while changing the route to success; never use elimination as the default adaptation.",
            "- Check comprehension with “Show me the first step” before increasing speed, opposition or complexity.",
            "",
        ]
    lines += [
        "## Source trace",
        "",
        "The source sequence was reorganised into a weekly long/short contract. Original activity wording remains embedded in the teacher-guide cells so the teacher can cross-check the planning without reopening a second document.",
        "",
    ]
    return "\n".join(lines).rstrip() + "\n"


def set_cell_shading(cell, fill: str) -> None:
    properties = cell._tc.get_or_add_tcPr()
    shading = properties.find(qn("w:shd"))
    if shading is None:
        shading = OxmlElement("w:shd")
        properties.append(shading)
    shading.set(qn("w:fill"), fill)


def set_cell_width(cell, width_dxa: int) -> None:
    properties = cell._tc.get_or_add_tcPr()
    width = properties.find(qn("w:tcW"))
    if width is None:
        width = OxmlElement("w:tcW")
        properties.append(width)
    width.set(qn("w:w"), str(width_dxa))
    width.set(qn("w:type"), "dxa")


def set_table_geometry(table, widths: list[int]) -> None:
    table.autofit = False
    table.alignment = WD_TABLE_ALIGNMENT.LEFT
    tbl = table._tbl
    properties = tbl.tblPr
    width = properties.find(qn("w:tblW"))
    if width is None:
        width = OxmlElement("w:tblW")
        properties.append(width)
    width.set(qn("w:w"), str(sum(widths)))
    width.set(qn("w:type"), "dxa")
    indent = properties.find(qn("w:tblInd"))
    if indent is None:
        indent = OxmlElement("w:tblInd")
        properties.append(indent)
    indent.set(qn("w:w"), "120")
    indent.set(qn("w:type"), "dxa")
    layout = properties.find(qn("w:tblLayout"))
    if layout is None:
        layout = OxmlElement("w:tblLayout")
        properties.append(layout)
    layout.set(qn("w:type"), "fixed")
    grid = tbl.tblGrid
    for child in list(grid):
        grid.remove(child)
    for width_dxa in widths:
        column = OxmlElement("w:gridCol")
        column.set(qn("w:w"), str(width_dxa))
        grid.append(column)
    for row in table.rows:
        for cell, width_dxa in zip(row.cells, widths):
            set_cell_width(cell, width_dxa)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.TOP


def set_run_font(run, name: str = "Calibri", size: float = 10, color: str = "1F2937", bold: bool = False) -> None:
    run.font.name = name
    run._element.get_or_add_rPr().rFonts.set(qn("w:ascii"), name)
    run._element.get_or_add_rPr().rFonts.set(qn("w:hAnsi"), name)
    run.font.size = Pt(size)
    run.font.color.rgb = RGBColor.from_string(color)
    run.bold = bold


def add_text(doc: Document, text: str, style: str = "Normal", size: float = 10, color: str = "1F2937", bold: bool = False) -> None:
    paragraph = doc.add_paragraph(style=style)
    paragraph.paragraph_format.space_after = Pt(4)
    paragraph.paragraph_format.line_spacing = 1.15
    run = paragraph.add_run(text)
    set_run_font(run, size=size, color=color, bold=bold)


def add_activity_table(doc: Document, activities: list[Activity]) -> None:
    headers = ["Time", "Phase", "Activity", "Teacher instructions", "Student actions", "CLIL focus", "Evidence", "Materials", "Adaptations"]
    table = doc.add_table(rows=1, cols=len(headers))
    widths = [650, 800, 1650, 2150, 1550, 1500, 1250, 1250, 1200]
    set_table_geometry(table, widths)
    table.style = "Table Grid"
    for cell, header in zip(table.rows[0].cells, headers):
        set_cell_shading(cell, "E8EEF5")
        paragraph = cell.paragraphs[0]
        paragraph.paragraph_format.space_after = Pt(0)
        run = paragraph.add_run(header)
        set_run_font(run, size=7.5, color="0B2545", bold=True)
    header_row = table.rows[0]._tr
    tr_properties = header_row.get_or_add_trPr()
    repeat = OxmlElement("w:tblHeader")
    repeat.set(qn("w:val"), "true")
    tr_properties.append(repeat)
    for item in activities:
        row = table.add_row()
        row_properties = row._tr.get_or_add_trPr()
        cant_split = OxmlElement("w:cantSplit")
        row_properties.append(cant_split)
        for cell, value in zip(row.cells, [item.time, item.phase, item.activity, item.teacher, item.students, item.clil, item.evidence, item.materials, item.adaptations]):
            paragraph = cell.paragraphs[0]
            paragraph.paragraph_format.space_after = Pt(0)
            paragraph.paragraph_format.line_spacing = 1.0
            run = paragraph.add_run(value)
            set_run_font(run, size=7.3, color="1F2937")
    set_table_geometry(table, widths)


def write_docx(path: Path, title: str, weeks: list[Week], source: Path) -> None:
    document = Document()
    section = document.sections[0]
    section.page_width = Inches(11)
    section.page_height = Inches(8.5)
    section.top_margin = Inches(0.65)
    section.bottom_margin = Inches(0.65)
    section.left_margin = Inches(0.55)
    section.right_margin = Inches(0.55)
    section.header_distance = Inches(0.492)
    section.footer_distance = Inches(0.492)

    normal = document.styles["Normal"]
    normal.font.name = "Calibri"
    normal._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
    normal._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")
    normal.font.size = Pt(10)
    normal.paragraph_format.space_after = Pt(4)
    normal.paragraph_format.line_spacing = 1.15
    for style_name, size, color, before, after in (("Heading 1", 16, "2E74B5", 18, 10), ("Heading 2", 13, "2E74B5", 14, 7), ("Heading 3", 12, "1F4D78", 10, 5)):
        style = document.styles[style_name]
        style.font.name = "Calibri"
        style._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
        style._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")
        style.font.size = Pt(size)
        style.font.color.rgb = RGBColor.from_string(color)
        style.font.bold = True
        style.paragraph_format.space_before = Pt(before)
        style.paragraph_format.space_after = Pt(after)
        style.paragraph_format.keep_with_next = True

    header = section.header.paragraphs[0]
    header.alignment = WD_ALIGN_PARAGRAPH.LEFT
    run = header.add_run(f"Session sequencing | {title[:70]}")
    set_run_font(run, size=8.5, color="6B7280")
    footer = section.footer.paragraphs[0]
    footer.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    run = footer.add_run("Teacher working document | CLIL session card")
    set_run_font(run, size=8, color="6B7280")

    add_text(document, title, size=22, color="0B2545", bold=True)
    add_text(document, "Weekly session sequence | English delivery with CLIL support", size=11.5, color="4B5563")
    add_text(document, "Planning rule: one long block (90 effective minutes) plus one short block (30 effective minutes) per week. The app maps the long block to two consecutive timetable slots and the short block to one simple slot.", size=9.5, color="374151")
    add_text(document, f"Source normalised: {source.name}", size=8.5, color="6B7280")
    add_text(document, "Teacher operating key", style="Heading 1", size=16, color="2E74B5", bold=True)
    for text in (
        "Before class: prepare the materials, display the CLIL sentence stems, and assign roles.",
        "During class: use the teacher instructions as cues, observe the evidence column, and adapt the route to success.",
        "After class: record one piece of evidence and one next step in the session journal.",
    ):
        paragraph = document.add_paragraph(style="List Bullet")
        paragraph.paragraph_format.space_after = Pt(3)
        run = paragraph.add_run(text)
        set_run_font(run, size=9.5)

    for index, week in enumerate(weeks):
        if index:
            document.add_page_break()
        shared_activities = enrich(table_rows(week.body) or chunks_from_text(week.body), title)
        long_activities = enrich(table_rows(week.long_body) or chunks_from_text(week.long_body), title)
        short_activities = enrich(table_rows(week.short_body) or chunks_from_text(week.short_body), title)
        if week.long_body == week.body:
            long_activities.append(Activity("60′–90′", "Extension", "Extended practice, feedback and transfer", "Repeat the key task, rotate roles, give one individual cue, and offer the agreed adaptation.", "Repeat the task, record one improvement, and support a peer using the sentence stem.", "Vocabulary: improve, adjust, repeat, support. Stem: Next time I will… because…", "One recorded improvement and one teacher observation.", "Equipment and visual cards named in the lesson setup; observation or recording sheet.", "Use a visual model, adjust space, distance or equipment, and keep the evidence target stable."))
        long_activities = assign_times(long_activities, 90)
        short_activities = assign_times(short_activities, 30)
        add_text(document, f"WEEK {week.number} - {plain(week.title)}", style="Heading 1", size=16, color="2E74B5", bold=True)
        add_text(document, f"Objective: {englishize(week.objective) or 'Achieve the shared learning intention through safe participation, purposeful practice and reflection.'}", size=9.5)
        add_text(document, f"Criteria / evidence focus: {englishize(week.criteria) or 'Safe execution, cooperation, decision-making, communication and reflective improvement.'}", size=9.5)
        add_text(document, f"Materials: {englishize(week.materials) or 'Use the equipment, visual cards and recording sheet named in the activity table.'}", size=9.5)
        add_text(document, "LONG BLOCK | 90 effective minutes", style="Heading 2", size=13, color="2E74B5", bold=True)
        add_activity_table(document, long_activities)
        add_text(document, "SHORT BLOCK | 30 effective minutes", style="Heading 2", size=13, color="2E74B5", bold=True)
        add_activity_table(document, short_activities)
        add_text(document, "Inclusion and teacher adaptations", style="Heading 3", size=12, color="1F4D78", bold=True)
        add_text(document, "Offer a visual model, reduced space or distance, lighter or larger equipment, peer support, and an opt-in intensity level. Keep the evidence target stable while changing the route to success.", size=9)

    path.parent.mkdir(parents=True, exist_ok=True)
    document.save(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()
    sources = sorted(path for path in args.root.rglob("*.md") if path.parent.name == "02_SESIONES" and "99_FUENTES" not in path.parts)
    if args.limit:
        sources = sources[: args.limit]
    for source in sources:
        text = source.read_text(encoding="utf-8")
        title = plain(next((line[2:].strip() for line in text.splitlines() if line.startswith("# ")), source.parent.parent.name))
        title = re.sub(r"(?:\s*-\s*Weekly Session Sequence)+\s*$", "", title, flags=re.I)
        weeks = make_weeks(text)
        markdown = render_markdown(source, title, weeks)
        source.write_text(markdown, encoding="utf-8")
        docx_path = source.with_suffix(".docx")
        write_docx(docx_path, title, weeks, source)
    print(f"rewritten={len(sources)}")


if __name__ == "__main__":
    main()
