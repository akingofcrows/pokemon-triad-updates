// One-time conversion of TTMMO's card data + art into TTAndroid's asset format.
// Run with: node scripts/convert_ttmmo_data.mjs
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(__dirname, '..');
const TTMMO = path.join(ROOT, '..', 'TTMMO');

const NON_CARD_ART = new Set(['mom_npc.png', 'oak_npc.png']);

// A handful of pokemon_cards.json `artwork` filenames don't match what's
// actually on disk in Triple Triad/ (pre-existing TTMMO data-quality gaps).
// Fix the ones with a same-folder equivalent; fall back to the 192x192
// Front/ sprite (same fallback TTMMO's own artwork.ts uses) for the rest.
const ARTWORK_FIXES = {
  'HOOH.png': 'HO-OH.png',
  'MRMIME.png': 'MR. MIME.png',
};
const ARTWORK_FRONT_FALLBACK = new Set(['MAROWAK.png']);

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

// Resolves a pokemon_cards.json `artwork` filename to the source file that
// actually exists on disk, and the destination filename to copy it as (kept
// identical to the original `artwork` value so cards.json's `image` path
// always matches what's on disk in assets/pokemon/).
function resolveArtworkSource(artworkFilename) {
  if (ARTWORK_FRONT_FALLBACK.has(artworkFilename)) {
    return { srcDir: path.join(TTMMO, 'assets', 'Graphics', 'Front'), srcName: artworkFilename };
  }
  const fixedName = ARTWORK_FIXES[artworkFilename] ?? artworkFilename;
  return { srcDir: path.join(TTMMO, 'assets', 'Graphics', 'Triple Triad'), srcName: fixedName };
}

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function convertCards() {
  ensureDir(path.join(ROOT, 'assets', 'data'));
  const raw = readJson(path.join(TTMMO, 'data', 'pokemon_cards.json'));
  const cards = raw.cards.map((c) => {
    const speciesId = c.id
      .replace(/^card_/, '')
      .replace(/^trainer_/, '')
      .replace(/_\d+(_v\d+)?$/, (m) => (m.includes('_v') ? m.replace(/^_\d+/, '') : ''));
    return {
      id: c.id,
      speciesId: speciesId || c.id,
      name: c.name,
      cardType: c.card_type === 'trainer' ? 'trainer' : 'pokemon',
      rarity: c.rarity,
      affinity: c.affinity,
      values: {
        north: c.north,
        south: c.south,
        east: c.east,
        west: c.west,
      },
      worth: c.worth ?? 0,
      cardNumber: c.card_number ?? '',
      image: `assets/pokemon/${c.artwork}`,
      isStarter: c.is_starter ?? false,
      holo: c.holo ?? false,
      evolvesTo: c.evolves_to || null,
      baseLevel: c.base_level ?? null,
    };
  });
  fs.writeFileSync(
    path.join(ROOT, 'assets', 'data', 'cards.json'),
    JSON.stringify({ cards }, null, 2),
  );
  console.log(`Wrote ${cards.length} cards -> assets/data/cards.json`);
  return cards;
}

function convertSets(allCardIds) {
  const raw = readJson(path.join(TTMMO, 'data', 'sets.json'));
  const sets = raw.sets.map((s) => ({
    id: s.id,
    name: s.name,
    description: s.description ?? '',
    cardIds: s.id === 'all' ? allCardIds : (s.cards ?? []),
  }));
  fs.writeFileSync(
    path.join(ROOT, 'assets', 'data', 'sets.json'),
    JSON.stringify({ sets }, null, 2),
  );
  console.log(`Wrote ${sets.length} sets -> assets/data/sets.json`);
}

function convertStarterDecks() {
  const raw = readJson(path.join(TTMMO, 'data', 'starter_decks.json'));
  const decks = raw.starter_decks;
  fs.writeFileSync(
    path.join(ROOT, 'assets', 'data', 'starter_decks.json'),
    JSON.stringify({ decks }, null, 2),
  );
  console.log(`Wrote ${decks.length} starter decks -> assets/data/starter_decks.json`);
}

function copyArt(cards) {
  const dstDir = path.join(ROOT, 'assets', 'pokemon');
  ensureDir(dstDir);
  let count = 0;
  const missing = [];
  for (const c of cards) {
    const artworkFilename = path.basename(c.image);
    const { srcDir, srcName } = resolveArtworkSource(artworkFilename);
    const srcPath = path.join(srcDir, srcName);
    if (!fs.existsSync(srcPath)) {
      missing.push(c.id);
      continue;
    }
    fs.copyFileSync(srcPath, path.join(dstDir, artworkFilename));
    count++;
  }
  console.log(`Copied ${count} card art files -> assets/pokemon/`);
  if (missing.length) console.log('Still missing artwork for:', missing.join(', '));
}

function copyUiArt() {
  const srcDir = path.join(TTMMO, 'assets', 'Graphics', 'UI', 'Triple Triad');
  const dstDir = path.join(ROOT, 'assets', 'ui');
  ensureDir(dstDir);
  const files = ['card_bg.png', 'numbers.png', 'frame.png', 'frameU.png', 'frameR.png', 'frameE.png', 'frameL.png'];
  for (const f of files) {
    fs.copyFileSync(path.join(srcDir, f), path.join(dstDir, f));
  }
  console.log(`Copied ${files.length} UI art files -> assets/ui/`);

  const typesSrc = path.join(TTMMO, 'assets', 'Graphics', 'UI', 'Types');
  const typesDst = path.join(ROOT, 'assets', 'ui', 'types');
  ensureDir(typesDst);
  let typeCount = 0;
  for (const file of fs.readdirSync(typesSrc)) {
    if (!file.toLowerCase().endsWith('.png')) continue;
    fs.copyFileSync(path.join(typesSrc, file), path.join(typesDst, file));
    typeCount++;
  }
  console.log(`Copied ${typeCount} type icon files -> assets/ui/types/`);
}

function copyFonts() {
  const dstDir = path.join(ROOT, 'assets', 'fonts');
  ensureDir(dstDir);
  const fontFiles = [
    [path.join(TTMMO, 'assets', 'fonts', 'power green.ttf'), 'PowerGreen.ttf'],
    [path.join(TTMMO, 'assets', 'fonts', 'power green narrow.ttf'), 'PowerGreenNarrow.ttf'],
    [path.join(TTMMO, 'assets', 'fonts', 'Tiny5-Regular.ttf'), 'Tiny5-Regular.ttf'],
  ];
  for (const [src, dstName] of fontFiles) {
    fs.copyFileSync(src, path.join(dstDir, dstName));
  }
  console.log(`Copied ${fontFiles.length} font files -> assets/fonts/`);
}

const cards = convertCards();
convertSets(cards.map((c) => c.id));
convertStarterDecks();
copyArt(cards);
copyUiArt();
copyFonts();
console.log('Done.');
