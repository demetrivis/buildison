#!/usr/bin/env node
// gen-antigravity — gera a camada .agents/ (glue do Google Antigravity 2.0 / CLI / IDE) a partir
// da fonte única em .claude/. O Antigravity lê AGENTS.md da raiz nativamente (regras); o .agents/
// dá a ele skills e agentes. Formato conferido na doc oficial em 2026-09-21
// (https://antigravity.google/llms.txt — cada página tem versão .md):
//
//   .agents/skills/<nome>/SKILL.md   skills no padrão Agent Skills (PASTA, não arquivo solto). No
//                                    CLI cada skill vira /<nome> sozinha; no 2.0 também dá /<nome>.
//   .agents/agents/<nome>.md         custom subagents (frontmatter name + description obrigatórios).
//
// Workflows (.agents/workflows/) estão DEPRECADOS e saem em 2026-11-01 — por isso os commands
// viram skills. O formato antigo deste gerador (skill como .agents/skills/<nome>.md solto, commands
// e agentes de missão como workflows) não é mais gerado; o instalador remove os que ele mesmo gerou.
//
// Uso:
//   node scripts/gen-antigravity.mjs                  (gera no próprio repo buildison)
//   node scripts/gen-antigravity.mjs /caminho/projeto (gera a partir do .claude/ daquele projeto)
//
// Saída sobrescrita a cada execução — NÃO edite à mão. Fonte de verdade continua em .claude/.
import { readdirSync, readFileSync, writeFileSync, mkdirSync, rmSync, existsSync, statSync, cpSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = process.argv[2] || join(dirname(fileURLToPath(import.meta.url)), '..');
const claudeAgents = join(root, '.claude', 'agents');
const claudeSkills = join(root, '.claude', 'skills');
const claudeCommands = join(root, '.claude', 'commands');
const outDir = join(root, '.agents');
const outSkills = join(outDir, 'skills');
const outAgents = join(outDir, 'agents');
const MARK = 'por gen-antigravity.mjs — não edite à mão.';

// Frontmatter YAML (--- ... ---) + corpo. Parser tolerante: só lê chaves de uma linha, que é o
// formato de todos os agents e commands da fonte.
function parse(md) {
  if (!md.startsWith('---')) return { fm: {}, body: md.trim() };
  const end = md.indexOf('\n---', 3);
  if (end === -1) return { fm: {}, body: md.trim() };
  const fm = {};
  for (const line of md.slice(3, end).trim().split('\n')) {
    const m = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!m) continue;
    let v = m[2].trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    fm[m[1]] = v;
  }
  return { fm, body: md.slice(end + 4).replace(/^\s*\n/, '').trimEnd() };
}

// Descrição de uma linha. Corta os blocos de exemplo (o security-auditor traz ~2 mil caracteres de
// "Examples:" com \n literais): o planner do Antigravity decide a delegação por ela, e ruído atrapalha.
function oneLine(s) {
  let d = (s || '').replace(/\\n/g, ' ');
  const ex = d.search(/\bExamples?:/);
  if (ex > 0) d = d.slice(0, ex);
  return d.replace(/\s+/g, ' ').trim();
}

// Os agents apontam pras skills em .claude/skills/ (projeto) e ~/.claude/skills/ (global). No
// Antigravity elas moram em .agents/skills/ e ~/.gemini/config/skills/.
function toAntigravityPaths(s) {
  return s.replaceAll('~/.claude/skills/', '~/.gemini/config/skills/').replaceAll('.claude/skills/', '.agents/skills/');
}

// ---------- skills: cópia integral da pasta (SKILL.md + references/ + scripts/) ----------
function buildSkills() {
  if (!existsSync(claudeSkills)) return [];
  const names = readdirSync(claudeSkills)
    .filter((d) => statSync(join(claudeSkills, d)).isDirectory() && existsSync(join(claudeSkills, d, 'SKILL.md')))
    .sort();
  for (const d of names) cpSync(join(claudeSkills, d), join(outSkills, d), { recursive: true });
  return names;
}

// ---------- commands -> skills (workflows saem em 2026-11-01; skill vira /<nome> sozinha) ----------
function buildCommandSkills(taken) {
  if (!existsSync(claudeCommands)) return [];
  const out = [];
  for (const f of readdirSync(claudeCommands).filter((x) => x.endsWith('.md')).sort()) {
    const name = f.replace(/\.md$/, '');
    if (taken.has(name)) {
      process.stderr.write(`x command '${name}' tem o mesmo nome de uma skill — no Antigravity os dois viram /${name}. Renomeie um.\n`);
      process.exit(1);
    }
    const { fm, body: rawBody } = parse(readFileSync(join(claudeCommands, f), 'utf8'));
    let desc = fm.description || '';
    let body = rawBody;
    const head = body.split('\n').find((l) => l.trim().startsWith('#'));
    if (!desc && head) {
      let t = head.replace(/^#+\s*/, '').trim();
      const dash = t.indexOf('—');
      desc = dash !== -1 ? t.slice(dash + 1).trim() : t.replace(/^\/\S+\s*/, '').trim();
    }
    desc = (oneLine(desc) || name).replace(/[.;:,]*$/, '');
    desc = `${desc}. Command /${name} do buildison — use quando o usuário pedir /${name} ou essa tarefa.`;
    mkdirSync(join(outSkills, name), { recursive: true });
    writeFileSync(join(outSkills, name, 'SKILL.md'), [
      '---', `name: ${name}`, `description: ${JSON.stringify(desc)}`, '---', '',
      `<!-- Gerado de .claude/commands/${f} ${MARK} -->`, '', body.trimEnd(), '',
    ].join('\n'));
    out.push(name);
  }
  return out;
}

// ---------- agents -> .agents/agents/<nome>.md ----------
// Só name + description no frontmatter. `tools` fica de fora de propósito: os nomes do Claude
// (Read, Bash…) não existem no Antigravity, e a doc avisa que nome de tool inválido TRAVA o
// subagente. `model` também (lá os valores são inherit|flash|pro).
function buildAgents() {
  if (!existsSync(claudeAgents)) return [];
  const out = [];
  for (const f of readdirSync(claudeAgents).filter((x) => x.endsWith('.md')).sort()) {
    const { fm, body } = parse(readFileSync(join(claudeAgents, f), 'utf8'));
    const name = fm.name || f.replace(/\.md$/, '');
    writeFileSync(join(outAgents, `${name}.md`), [
      '---', `name: ${name}`, `description: ${JSON.stringify(oneLine(fm.description) || name)}`, '---', '',
      `<!-- Gerado de .claude/agents/${f} ${MARK} -->`, '', toAntigravityPaths(body).trimEnd(), '',
    ].join('\n'));
    out.push(name);
  }
  return out;
}

// ---------- run ----------
if (!existsSync(claudeSkills) && !existsSync(claudeCommands) && !existsSync(claudeAgents)) {
  process.stderr.write(`x nenhum .claude/{skills,commands,agents} em ${root} — alvo inválido?\n`);
  process.exit(1);
}
rmSync(outDir, { recursive: true, force: true });
mkdirSync(outSkills, { recursive: true });
mkdirSync(outAgents, { recursive: true });
const skills = buildSkills();
const cmds = buildCommandSkills(new Set(skills));
const agents = buildAgents();
process.stdout.write(`OK ${outDir}: ${skills.length + cmds.length} skills (${skills.length} skills + ${cmds.length} commands), ${agents.length} agents.\n`);
