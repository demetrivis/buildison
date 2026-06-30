#!/usr/bin/env node
// Wrapper npx do buildison — delega para os scripts bash.
// Subcomandos:
//   install [opts]   → install.sh   (instala a toolbox; default se nenhum subcomando)
//   switch  [opts]   → switch.sh    (troca .mcp.json do projeto atual entre local/vps)
//   --help / -h      → ajuda do install.sh
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { existsSync } from 'node:fs';

const pkgRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const scripts = {
  install: join(pkgRoot, 'install.sh'),
  switch:  join(pkgRoot, 'switch.sh'),
};

const args = process.argv.slice(2);
const first = args[0];
let sub = 'install';
if (first && Object.prototype.hasOwnProperty.call(scripts, first)) { sub = first; args.shift(); }

const script = scripts[sub];
if (!existsSync(script)) {
  console.error(`${sub}: script não encontrado no pacote buildison (esperado em ${script}).`);
  process.exit(1);
}

const res = spawnSync('bash', [script, ...args], { stdio: 'inherit' });
if (res.error && res.error.code === 'ENOENT') {
  console.error('bash não encontrado.');
  console.error('No Windows, use o instalador nativo do PowerShell:');
  console.error('  irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1 | iex');
  console.error('(ou rode este npx dentro do Git Bash / WSL)');
  process.exit(1);
}
process.exit(res.status ?? 1);
