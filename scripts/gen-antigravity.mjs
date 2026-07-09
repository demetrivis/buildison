#!/usr/bin/env node
// gen-antigravity — gera a camada .agents/ (glue do Google Antigravity) a partir da fonte
// única em .claude/. O Antigravity lê AGENTS.md nativamente (regras) e reconhece o .agents/
// para SKILLS e WORKFLOWS. Ele NÃO registra "agentes custom" via arquivo — os subagentes
// (Browser/Terminal) são orquestrados internamente pela IDE. Por isso este gerador NÃO
// produz um roster de agentes; os agentes "de missão" viram WORKFLOWS (slash-commands).
//
// Uso:
//   node scripts/gen-antigravity.mjs                 (gera no próprio repo buildison)
//   node scripts/gen-antigravity.mjs /caminho/projeto (gera no .claude/ daquele projeto)
//
// Saída (sobrescrita — NÃO edite à mão, rode de novo pra ressincronizar):
//   .agents/skills/<nome>.md     — uma skill por arquivo (de .claude/skills/<nome>/SKILL.md)
//   .agents/workflows/<nome>.md  — um slash-command por arquivo:
//       - de .claude/commands/*.md  (comandos)
//       - dos agentes de missão em .claude/agents/ (arq-info, arq-info-web, design-system-extractor)
//
// Fonte de verdade continua em .claude/. Este é um espelho de descoberta/execução.
import { readdirSync, readFileSync, writeFileSync, mkdirSync, rmSync, existsSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = process.argv[2] || join(dirname(fileURLToPath(import.meta.url)), '..');
const claudeAgents = join(root, '.claude', 'agents');
const claudeSkills = join(root, '.claude', 'skills');
const claudeCommands = join(root, '.claude', 'commands');
const outDir = join(root, '.agents');
const outSkills = join(outDir, 'skills');
const outWorkflows = join(outDir, 'workflows');

// Agentes "de missão" (você descreve → roda uma vez) que fazem sentido como slash-command.
// Os agentes de camada (api, db, logic, ...) NÃO entram: suas convenções já vivem nas skills.
const MISSION_AGENTS = ['arq-info', 'arq-info-web', 'design-system-extractor'];

// Extrai o bloco de frontmatter YAML (--- ... ---) e o corpo. Parser tolerante:
// só precisamos de name/description (linhas simples, valor com ou sem aspas).
function parse(md) {
  if (!md.startsWith('---')) return { fm: {}, body: md.trim() };
  const end = md.indexOf('\n---', 3);
  if (end === -1) return { fm: {}, body: md.trim() };
  const fmRaw = md.slice(3, end).trim();
  const body = md.slice(end + 4).replace(/^\s*\n/, '').trimEnd();
  const fm = {};
  for (const line of fmRaw.split('\n')) {
    const m = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!m) continue;
    let v = m[2].trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1);
    }
    fm[m[1]] = v;
  }
  return { fm, body };
}

// description do frontmatter do Antigravity: 1 linha, ≤250 chars.
function shortDesc(s, fallback) {
  const d = (s || fallback || '').replace(/\s+/g, ' ').trim();
  return d.length > 240 ? d.slice(0, 239).trimEnd() + '…' : d;
}

// ---------- skills -> .agents/skills/<nome>.md ----------
function buildSkills() {
  if (!existsSync(claudeSkills)) return 0;
  const entries = readdirSync(claudeSkills).filter((d) => {
    const p = join(claudeSkills, d);
    return statSync(p).isDirectory() && existsSync(join(p, 'SKILL.md'));
  }).sort();
  let n = 0;
  for (const d of entries) {
    const { fm, body } = parse(readFileSync(join(claudeSkills, d, 'SKILL.md'), 'utf8'));
    const name = fm.name || d;
    const out = ['---', `name: ${name}`];
    if (fm.description) out.push(`description: ${JSON.stringify(fm.description)}`);
    out.push('---', '', `<!-- Gerado de .claude/skills/${d}/SKILL.md por gen-antigravity.mjs — não edite à mão. -->`, '', body);
    if (existsSync(join(claudeSkills, d, 'references'))) {
      out.push('', `> Referências detalhadas: \`.claude/skills/${d}/references/\`.`);
    }
    writeFileSync(join(outSkills, `${name}.md`), out.join('\n').trimEnd() + '\n');
    n++;
  }
  return n;
}

// escreve um arquivo de workflow (frontmatter description + corpo)
function writeWorkflow(name, description, body, sourceNote) {
  const out = [
    '---',
    `description: ${JSON.stringify(description)}`,
    '---',
    '',
    `<!-- ${sourceNote} — não edite à mão. -->`,
    '',
    body.trimEnd(),
  ];
  writeFileSync(join(outWorkflows, `${name}.md`), out.join('\n').trimEnd() + '\n');
}

// ---------- comandos -> .agents/workflows/<nome>.md ----------
function buildCommandWorkflows() {
  if (!existsSync(claudeCommands)) return 0;
  const files = readdirSync(claudeCommands).filter((f) => f.endsWith('.md')).sort();
  let n = 0;
  for (const f of files) {
    const raw = readFileSync(join(claudeCommands, f), 'utf8');
    const head = raw.split('\n').find((l) => l.trim().startsWith('#'));
    let desc = f.replace(/\.md$/, '');
    if (head) {
      let t = head.replace(/^#+\s*/, '').trim();
      const dash = t.indexOf('—');
      t = dash !== -1 ? t.slice(dash + 1).trim() : t.replace(/^\/\S+\s*/, '').trim();
      if (t) desc = t;
    }
    let body = raw;
    if (head) { const i = raw.indexOf(head); body = raw.slice(i + head.length).replace(/^\s*\n/, ''); }
    writeWorkflow(f.replace(/\.md$/, ''), shortDesc(desc), body, `Gerado de .claude/commands/${f} por gen-antigravity.mjs`);
    n++;
  }
  return n;
}

// ---------- agentes de missão -> .agents/workflows/<nome>.md ----------
// No Antigravity não há "agente custom" invocável; então a persona vira um workflow disparável por /.
function buildAgentWorkflows() {
  if (!existsSync(claudeAgents)) return 0;
  let n = 0;
  for (const name of MISSION_AGENTS) {
    const file = join(claudeAgents, `${name}.md`);
    if (!existsSync(file)) continue;
    const { fm, body } = parse(readFileSync(file, 'utf8'));
    writeWorkflow(name, shortDesc(fm.description, name), body, `Gerado do agente .claude/agents/${name}.md por gen-antigravity.mjs`);
    n++;
  }
  return n;
}

// ---------- run ----------
if (!existsSync(claudeSkills) && !existsSync(claudeCommands) && !existsSync(claudeAgents)) {
  process.stderr.write(`x nenhum .claude/{skills,commands,agents} em ${root} — alvo inválido?\n`);
  process.exit(1);
}
rmSync(outDir, { recursive: true, force: true });
mkdirSync(outSkills, { recursive: true });
mkdirSync(outWorkflows, { recursive: true });
const ns = buildSkills();
const nc = buildCommandWorkflows();
const nawf = buildAgentWorkflows();
process.stdout.write(`OK ${outDir}: ${ns} skills, ${nc + nawf} workflows (${nc} comandos + ${nawf} agentes de missão). Sem roster de agentes (Antigravity não registra agente via arquivo).\n`);
