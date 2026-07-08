#!/usr/bin/env node
// gen-antigravity — gera a camada .agents/ (glue do Google Antigravity) a partir da
// fonte única do buildison em .claude/. O Antigravity lê AGENTS.md nativamente (regras);
// este gerador espelha o ROSTER de agentes e as SKILLS para o formato .agents/ que ele conhece.
//
// Uso:  node scripts/gen-antigravity.mjs        (roda a partir da raiz do repo)
//
// Saída (sobrescrita — NÃO edite à mão, rode de novo pra ressincronizar):
//   .agents/agents.md          — roster dos agentes (name + description do frontmatter)
//   .agents/skills/<nome>.md   — uma skill por arquivo (frontmatter + corpo do SKILL.md)
//
// Fonte de verdade continua em .claude/. Este é um espelho de descoberta/leitura.
import { readdirSync, readFileSync, writeFileSync, mkdirSync, rmSync, existsSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const claudeAgents = join(repoRoot, '.claude', 'agents');
const claudeSkills = join(repoRoot, '.claude', 'skills');
const outDir = join(repoRoot, '.agents');
const outSkills = join(outDir, 'skills');

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

function warn(msg) { process.stderr.write(`! ${msg}\n`); }

// ---------- agents -> .agents/agents.md ----------
function buildAgents() {
  const files = readdirSync(claudeAgents).filter((f) => f.endsWith('.md')).sort();
  const rows = [];
  for (const f of files) {
    const { fm } = parse(readFileSync(join(claudeAgents, f), 'utf8'));
    const name = fm.name || f.replace(/\.md$/, '');
    const desc = fm.description || '(sem description no frontmatter)';
    if (!fm.name) warn(`agente ${f} sem 'name:' no frontmatter — usando o nome do arquivo`);
    rows.push({ name, desc, file: f });
  }
  const lines = [];
  lines.push('# buildison — roster de agentes (espelho de .claude/agents)');
  lines.push('');
  lines.push('> Gerado por `scripts/gen-antigravity.mjs` a partir de `.claude/agents/*.md`.');
  lines.push('> **Não edite à mão** — rode o gerador pra ressincronizar. Fonte de verdade: `.claude/agents/`.');
  lines.push('');
  lines.push('O Antigravity lê o `AGENTS.md` da raiz nativamente (regras permanentes + toolbox).');
  lines.push('Este arquivo espelha os **papéis especialistas** do buildison para o Antigravity adotar a mesma');
  lines.push('divisão de trabalho. As convenções por camada estão em `.agents/skills/`.');
  lines.push('');
  for (const r of rows) {
    lines.push(`## ${r.name}`);
    lines.push('');
    lines.push(r.desc);
    lines.push('');
    lines.push(`_Instruções completas do papel: \`.claude/agents/${r.file}\` (markdown legível)._`);
    lines.push('');
  }
  writeFileSync(join(outDir, 'agents.md'), lines.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n');
  return rows.length;
}

// ---------- skills -> .agents/skills/<nome>.md ----------
function buildSkills() {
  const entries = readdirSync(claudeSkills).filter((d) => {
    const p = join(claudeSkills, d);
    return statSync(p).isDirectory() && existsSync(join(p, 'SKILL.md'));
  }).sort();
  let n = 0;
  for (const d of entries) {
    const { fm, body } = parse(readFileSync(join(claudeSkills, d, 'SKILL.md'), 'utf8'));
    const name = fm.name || d;
    const desc = fm.description || '';
    const hasRefs = existsSync(join(claudeSkills, d, 'references'));
    const out = [];
    out.push('---');
    out.push(`name: ${name}`);
    if (desc) out.push(`description: ${JSON.stringify(desc)}`);
    out.push('---');
    out.push('');
    out.push(`<!-- Gerado de .claude/skills/${d}/SKILL.md por scripts/gen-antigravity.mjs — não edite à mão. -->`);
    out.push('');
    out.push(body);
    if (hasRefs) {
      out.push('');
      out.push(`> Referências detalhadas desta skill vivem em \`.claude/skills/${d}/references/\` (repo buildison).`);
    }
    writeFileSync(join(outSkills, `${name}.md`), out.join('\n').trimEnd() + '\n');
    n++;
  }
  return n;
}

// ---------- run ----------
if (!existsSync(claudeAgents) || !existsSync(claudeSkills)) {
  process.stderr.write('x .claude/agents ou .claude/skills não encontrado — rode a partir da raiz do repo buildison.\n');
  process.exit(1);
}
rmSync(outDir, { recursive: true, force: true });
mkdirSync(outSkills, { recursive: true });
const na = buildAgents();
const ns = buildSkills();
process.stdout.write(`OK .agents/ gerado: ${na} agentes em agents.md, ${ns} skills em skills/\n`);
