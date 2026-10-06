const pptxgen = require("pptxgenjs");
const { applyTheme } = require("/mnt/skills/public/pptx/scripts/apply_theme.js");

const THEME = {
  name: "Ndume Ranch", headFontFace: "Cambria", bodyFontFace: "Calibri",
  colors: { dk1: "1B2A21", lt1: "FFFFFF", dk2: "2F4F3A", lt2: "EEF2EC",
    accent1: "2F4F3A", accent2: "C8553D", accent3: "7A9A6B", accent4: "D9A441", accent5: "5B6F63", accent6: "A33B2A",
    hlink: "2F4F3A", folHlink: "5B6F63" }
};

const pres = new pptxgen();
pres.layout = "LAYOUT_16x9";           // 10 x 5.625 in
pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
pres.title = "Ndume Ranch Capstone"; pres.author = "Elim Benjamin";
const C = pres.SchemeColor;

pres.defineSlideMaster({ title: "DARK", background: { color: C.accent1 }, slideNumber: undefined,
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.6, y: 1.5, w: 8.8, h: 1.3, fontSize: 40, bold: true, color: C.background1, fontFace: "Cambria", valign: "top", align: "left", margin: 0 }, text: "" } },
    { placeholder: { options: { name: "body", type: "body", x: 0.6, y: 3.0, w: 8.8, h: 1.2, fontSize: 18, color: C.background2, valign: "top", margin: 0 }, text: "" } } ] });
pres.defineSlideMaster({ title: "CONTENT", background: { color: C.background1 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.6, y: 0.35, w: 8.8, h: 0.8, fontSize: 32, bold: true, color: C.text2, fontFace: "Cambria", valign: "middle", align: "left", margin: 0 }, text: "" } },
    { text: { text: "Ndume Ranch capstone", options: { x: 0.6, y: 5.2, w: 4, h: 0.3, fontSize: 10, color: C.accent5, margin: 0 } } } ],
  slideNumber: { x: 9.0, y: 5.2, w: 0.5, h: 0.3, fontSize: 10, color: C.accent5 } });

const card = (s, x, y, w, h, name) => s.addShape(pres.ShapeType.roundRect, { x, y, w, h, rectRadius: 0.08, fill: { color: C.background2 }, line: { color: C.background2, width: 0 }, objectName: name });

// 1 Title
pres.addSection({ title: "Intro" });
let s = pres.addSlide({ masterName: "DARK", sectionTitle: "Intro" });
s.addText("Ndume Ranch: a multi-tenant cattle ranch database", { placeholder: "title" });
s.addText("PostgreSQL + Redis, built in layers: design, migrations, performance proof, security, recovery", { placeholder: "body" });
s.addNotes("Capstone walkthrough. Domain: cattle ranch management for many ranches in one system. Story: design first, build in layers, measure before claiming speed, test the security, prove the backup restores.");

// 2 Requirements
s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Intro" });
s.addText("Many ranches, one database, no leaks", { placeholder: "title" });
const stats = [["3", "ranches (tenants)"], ["6,000", "animals"], ["569,696", "weigh-ins"], ["7", "migrations"]];
stats.forEach((t, i) => { const x = 0.6 + i * 2.25; card(s, x, 1.45, 2.05, 1.5, "stat" + i);
  s.addText(t[0], { x, y: 1.6, w: 2.05, h: 0.8, fontSize: 36, bold: true, color: C.accent2, align: "center", fontFace: "Cambria", isTextBox: true, margin: 0 });
  s.addText(t[1], { x, y: 2.4, w: 2.05, h: 0.4, fontSize: 14, color: C.text1, align: "center", isTextBox: true, margin: 0 }); });
s.addText([
  { text: "Owners, managers, vets and workers see different things.", options: { bullet: true, breakLine: true } },
  { text: "Isolation is enforced by the database, not only by the app.", options: { bullet: true, breakLine: true } },
  { text: "Dashboards must be fast at half a million weigh-ins.", options: { bullet: true } } ],
  { x: 0.6, y: 3.3, w: 8.8, h: 1.5, fontSize: 18, color: C.text1, paraSpaceAfter: 8, isTextBox: true, margin: 0, valign: "top" });
s.addNotes("Requirements: F1-F9 functional, N1-N6 non-functional in docs/01_requirements.md. ER diagram is docs/er_diagram.png.");

// 3 Architecture
pres.addSection({ title: "Build" });
s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Build" });
s.addText("PostgreSQL leads; other stores add speed", { placeholder: "title" });
const box = (x, y, w, h, fill, txtColor, head, sub, name) => { s.addShape(pres.ShapeType.roundRect, { x, y, w, h, rectRadius: 0.1, fill: { color: fill }, line: { color: fill, width: 0 }, objectName: name });
  s.addText([{ text: head, options: { bold: true, fontSize: 18, breakLine: true } }, { text: sub, options: { fontSize: 14 } }], { x: x + 0.15, y, w: w - 0.3, h, color: txtColor, valign: "middle", isTextBox: true, margin: 0 }); };
box(0.6, 1.6, 2.4, 1.3, C.accent5, C.background1, "Application", "sets tenant per transaction", "app");
box(3.8, 1.3, 2.6, 1.9, C.accent1, C.background1, "PostgreSQL 16", "RLS, audit, 7 migrations", "pg");
box(7.2, 1.3, 2.2, 0.85, C.accent3, C.text1, "Redis", "cache, sessions: built", "redis");
box(7.2, 2.35, 2.2, 0.85, C.background2, C.text1, "MongoDB", "sensor data: design only", "mongo");
s.addShape(pres.ShapeType.line, { x: 3.0, y: 2.25, w: 0.8, h: 0, line: { color: C.accent5, width: 2, endArrowType: "triangle" }, objectName: "arrow1" });
s.addShape(pres.ShapeType.line, { x: 6.4, y: 1.72, w: 0.8, h: 0, line: { color: C.accent5, width: 2, endArrowType: "triangle" }, objectName: "arrow2" });
s.addText([
  { text: "Redis fits repeated reads that expire (dashboard cache, sessions, rate limits).", options: { bullet: true, breakLine: true } },
  { text: "MongoDB fits high-volume, append-only collar readings. It was not run here: no server was available.", options: { bullet: true } } ],
  { x: 0.6, y: 3.7, w: 8.8, h: 1.2, fontSize: 16, color: C.text1, paraSpaceAfter: 6, isTextBox: true, margin: 0, valign: "top" });
s.addNotes("Be upfront: Redis was built and tested; MongoDB is a documented design and script that was not executed.");

// 4 Migrations timeline
s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Build" });
s.addText("Seven migrations rebuild it from empty", { placeholder: "title" });
const mig = [["V1", "Core tables"], ["V2", "Base indexes"], ["V3", "Audit + triggers"], ["V4", "Roles + RLS"], ["V5", "Seed data"], ["V6", "Perf indexes"], ["V7", "Tenant-safe FKs"]];
mig.forEach((m, i) => { const x = 0.6 + i * 1.28; const late = i >= 5;
  s.addShape(pres.ShapeType.ellipse, { x: x + 0.25, y: 1.5, w: 0.7, h: 0.7, fill: { color: late ? C.accent2 : C.accent1 }, line: { color: late ? C.accent2 : C.accent1, width: 0 }, objectName: "node" + i });
  s.addText(m[0], { x: x + 0.25, y: 1.5, w: 0.7, h: 0.7, fontSize: 16, bold: true, color: C.background1, align: "center", valign: "middle", isTextBox: true, margin: 0 });
  s.addText(m[1], { x: x - 0.05, y: 2.3, w: 1.3, h: 0.6, fontSize: 14, color: C.text1, align: "center", valign: "top", isTextBox: true, margin: 0 }); });
card(s, 0.6, 3.3, 8.8, 1.5, "callout");
s.addText([
  { text: "V6 and V7 came from testing, not planning. ", options: { bold: true, color: C.accent2 } },
  { text: "Measuring showed a 32-second query (V6). A security test showed one ranch could link its data to another ranch's animal (V7). Fixes are new migrations, never edits to old ones." } ],
  { x: 0.85, y: 3.4, w: 8.3, h: 1.3, fontSize: 16, color: C.text1, valign: "middle", isTextBox: true, margin: 0 });
s.addNotes("The real Flyway CLI could not be downloaded in the build sandbox. The files use Flyway naming; a stand-in runner applied them from an empty database. Run real Flyway before submitting.");

// 5 Optimization
pres.addSection({ title: "Prove" });
s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Prove" });
s.addText("Measured: 32 seconds down to 11 ms", { placeholder: "title" });
const opt = [["Q1 herd by breed", "32.3 s", "10.9 ms"], ["Q2 daily gain", "35.4 s", "18.0 ms"], ["Q3 overdue shots", "10.5 ms", "0.8 ms"]];
opt.forEach((o, i) => { const x = 0.6 + i * 3.0; card(s, x, 1.4, 2.8, 2.1, "opt" + i);
  s.addText(o[0], { x, y: 1.5, w: 2.8, h: 0.4, fontSize: 16, bold: true, color: C.text2, align: "center", isTextBox: true, margin: 0 });
  s.addText("before " + o[1], { x, y: 1.95, w: 2.8, h: 0.4, fontSize: 16, color: C.accent5, align: "center", isTextBox: true, margin: 0 });
  s.addText(o[2], { x, y: 2.4, w: 2.8, h: 0.8, fontSize: 36, bold: true, color: C.accent2, align: "center", fontFace: "Cambria", isTextBox: true, margin: 0 }); });
s.addText([
  { text: "Cause: a full table scan per animal. Fix: one composite index (animal, date).", options: { bullet: true, breakLine: true } },
  { text: "Evidence: EXPLAIN ANALYZE before and after, saved in the evidence folder.", options: { bullet: true, breakLine: true } },
  { text: "Redis would have hidden the slow query; the index fixed it.", options: { bullet: true } } ],
  { x: 0.6, y: 3.7, w: 8.8, h: 1.3, fontSize: 16, color: C.text1, paraSpaceAfter: 6, isTextBox: true, margin: 0, valign: "top" });
s.addNotes("Single runs on one machine, so trust the ratio and the plan change (Seq Scan to Index Scan), not the exact milliseconds. Q4 and Q5 were already fast and left alone on purpose.");

// 6 Security
pres.addSection({ title: "Protect" });
s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Protect" });
s.addText("Security checklist: four pass, two partial", { placeholder: "title" });
const sec = [["Least-privilege roles", "PASS"], ["RLS on all tenant tables", "PASS"], ["Audit log on critical tables", "PASS"], ["Backup + test restore", "PASS"], ["Sensitive fields protected", "PARTIAL"], ["Parameterized queries", "PARTIAL"]];
sec.forEach((r, i) => { const col = i % 2, row = Math.floor(i / 2); const x = 0.6 + col * 4.5, y = 1.4 + row * 0.95; const ok = r[1] === "PASS";
  card(s, x, y, 4.3, 0.8, "sec" + i);
  s.addShape(pres.ShapeType.ellipse, { x: x + 0.2, y: y + 0.18, w: 0.44, h: 0.44, fill: { color: ok ? C.accent3 : C.accent4 }, line: { color: ok ? C.accent3 : C.accent4, width: 0 }, objectName: "dot" + i });
  s.addText(ok ? "P" : "!", { x: x + 0.2, y: y + 0.18, w: 0.44, h: 0.44, fontSize: 14, bold: true, color: C.text1, align: "center", valign: "middle", isTextBox: true, margin: 0 });
  s.addText([{ text: r[0], options: { bold: true, breakLine: true } }, { text: r[1], options: { fontSize: 12, color: ok ? C.text2 : C.accent6 } }], { x: x + 0.8, y, w: 3.4, h: 0.8, fontSize: 16, color: C.text1, valign: "middle", isTextBox: true, margin: 0 }); });
s.addText("Partial: the encryption key in the seed file is a demo key; no application code was written to prove parameterized queries.", { x: 0.6, y: 4.35, w: 8.8, h: 0.6, fontSize: 14, color: C.accent5, isTextBox: true, margin: 0, valign: "top" });
s.addNotes("Each item has an evidence file in docs/05_security_checklist.md. Known gaps listed there: sandbox trust authentication, placeholder passwords, RLS depends on the app setting the tenant honestly, no point-in-time recovery.");

// 7 Closing
s = pres.addSlide({ masterName: "DARK", sectionTitle: "Protect" });
s.addText("What I would do next", { placeholder: "title" });
s.addText([
  { text: "Run real Flyway and the MongoDB script, then record the results", options: { bullet: true, breakLine: true } },
  { text: "Move secrets out of the migrations; add TLS and a non-superuser owner role", options: { bullet: true, breakLine: true } },
  { text: "Add WAL archiving for point-in-time recovery and an offsite encrypted backup", options: { bullet: true } } ],
  { placeholder: "body", paraSpaceAfter: 8 });
s.addNotes("Close with the honest status: what was run, what was designed only, and the concrete next steps.");

(async () => { await pres.writeFile({ fileName: "presentation/Ndume_Ranch_Capstone.pptx" });
  await applyTheme("presentation/Ndume_Ranch_Capstone.pptx", THEME); console.log("deck written"); })();
