// Drug Wars: Re-Up — character component generator (Imagen 4)
// Adapted from LobsterPot's avatar.ts pattern.
//
// Generates 10 variants × 5 categories (head, hair, torso, arms, legs) × 4 character
// types (male, female, android, alien) = 200 component images. ~$8 at $0.04/image,
// or whatever the free-tier allowance is.
//
// Usage:
//   export GEMINI_API_KEY=...
//   deno run --allow-env --allow-read --allow-write --allow-net \
//     tools/generate-character-components.ts [--dry-run] [--types M,F] [--cats head,hair] [--limit N]
//
// Outputs to assets/sprites/components/<type>/<category>/<variant>.png and writes
// a manifest.json describing each piece. Skips files that already exist (resumable).

import { ensureDir } from "https://deno.land/std/fs/ensure_dir.ts";
import { existsSync } from "https://deno.land/std/fs/exists.ts";

const API_KEY = Deno.env.get("GEMINI_API_KEY");
const OUT_DIR = "assets/sprites/components";
const ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/imagen-4.0-generate-001:predict?key=${API_KEY}`;
const COOLDOWN_MS = 4500;             // be polite — public Imagen has tight rate caps
const TIMEOUT_MS = 120_000;

const TYPES = ["male", "female", "android", "alien"] as const;
type CharType = typeof TYPES[number];

const CATEGORIES = ["head", "hair", "torso", "arms", "legs"] as const;
type Category = typeof CATEGORIES[number];

// 10 visual archetype modifiers, applied per (type, category, idx).
// They lean into criminal-underworld variety while staying mode-neutral
// (the same modifier reads differently in head vs torso vs legs).
const VARIANT_TAGS = [
  "weathered", "youthful", "tactical", "blue-collar", "academic",
  "rockabilly", "biker", "preppy", "sportswear", "1970s",
] as const;

// Per-character-type stylistic backbone (kept short — Imagen prompts cap usefully near 80-120 tokens).
const TYPE_STYLE: Record<CharType, string> = {
  male:    "a humanoid adult man, late 20s to mid 50s",
  female:  "a humanoid adult woman, late 20s to mid 50s",
  android: "a HUMAN-looking adult of indeterminate gender; subtle uncanny tells (slightly too-symmetric face, eyes a touch too clear, motionless poise)",
  alien:   "a HUMAN-looking adult passing as ordinary; one or two subtle off cues (faint shimmer in skin, irises slightly off-color, fingers a hair too long)",
};

// Per-category prompt fragment.
const CATEGORY_PROMPT: Record<Category, string> = {
  head:  "from the neck up — head and face only, neutral expression, ears visible, no shoulders",
  hair:  "hairstyle isolated, roughly head-shaped, no face beneath, top-down to 3/4 angle",
  torso: "torso clothing only, from collarbone to waistline, no head, no arms past the shoulders",
  arms:  "both arms and hands, separated from the body, palms visible",
  legs:  "lower body — pants/skirt and shoes only, from waistline to feet, no torso, no head",
};

// Output style — consistent so pieces composite later.
const STYLE_SUFFIX = "Render as a 2D character sprite component, front-facing, "
  + "flat lighting, slight cel-shaded outlines, high contrast, "
  + "isolated on a solid neon-magenta (#ff00bf) background for chroma-key alpha extraction, "
  + "no text, no watermarks, no shadow, no other characters or objects.";

interface GenSpec {
  type: CharType;
  category: Category;
  variant: number;
  tag: string;
  prompt: string;
  outPath: string;
}

function buildSpecs(filter?: { types?: CharType[]; cats?: Category[]; limit?: number }): GenSpec[] {
  const specs: GenSpec[] = [];
  const useTypes = filter?.types ?? Array.from(TYPES);
  const useCats = filter?.cats ?? Array.from(CATEGORIES);
  for (const type of useTypes) {
    for (const category of useCats) {
      for (let i = 0; i < VARIANT_TAGS.length; i++) {
        const tag = VARIANT_TAGS[i];
        const prompt =
          `${TYPE_STYLE[type]}, ${CATEGORY_PROMPT[category]}, ${tag} style. ${STYLE_SUFFIX}`;
        specs.push({
          type,
          category,
          variant: i,
          tag,
          prompt,
          outPath: `${OUT_DIR}/${type}/${category}/${i.toString().padStart(2, "0")}_${tag}.png`,
        });
        if (filter?.limit && specs.length >= filter.limit) return specs;
      }
    }
  }
  return specs;
}

async function generateOne(spec: GenSpec, dryRun: boolean): Promise<{ ok: boolean; bytes?: number; err?: string }> {
  if (dryRun) {
    return { ok: true };
  }
  if (!API_KEY) return { ok: false, err: "no GEMINI_API_KEY in env" };

  try {
    const resp = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        instances: [{ prompt: spec.prompt }],
        parameters: {
          sampleCount: 1,
          aspectRatio: "1:1",
          personGeneration: "allow_all",
        },
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!resp.ok) {
      return { ok: false, err: `HTTP ${resp.status}: ${(await resp.text()).slice(0, 180)}` };
    }
    const data = await resp.json() as { predictions?: Array<{ bytesBase64Encoded?: string }> };
    const b64 = data.predictions?.[0]?.bytesBase64Encoded;
    if (!b64) return { ok: false, err: "no image data in response" };
    const buf = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    await ensureDir(spec.outPath.substring(0, spec.outPath.lastIndexOf("/")));
    await Deno.writeFile(spec.outPath, buf);
    return { ok: true, bytes: buf.length };
  } catch (e) {
    return { ok: false, err: e instanceof Error ? e.message.slice(0, 180) : String(e).slice(0, 180) };
  }
}

function parseArgs(): { dryRun: boolean; types?: CharType[]; cats?: Category[]; limit?: number } {
  const args = Deno.args;
  const out: { dryRun: boolean; types?: CharType[]; cats?: Category[]; limit?: number } = {
    dryRun: args.includes("--dry-run"),
  };
  const t = args.indexOf("--types");
  if (t >= 0) {
    out.types = args[t + 1].split(",").map((s) => {
      const k = s.trim().toLowerCase();
      if (k === "m") return "male";
      if (k === "f") return "female";
      if (k === "a") return "android";
      if (k === "x") return "alien";
      return k as CharType;
    });
  }
  const c = args.indexOf("--cats");
  if (c >= 0) out.cats = args[c + 1].split(",").map((s) => s.trim() as Category);
  const l = args.indexOf("--limit");
  if (l >= 0) out.limit = parseInt(args[l + 1], 10);
  return out;
}

async function main() {
  const args = parseArgs();
  const specs = buildSpecs(args);
  console.log(`[gen] planning ${specs.length} components${args.dryRun ? " (dry run)" : ""}`);

  const manifest: Array<{ type: CharType; category: Category; variant: number; tag: string; path: string; bytes?: number }> = [];
  let done = 0, skipped = 0, failed = 0;
  for (const spec of specs) {
    if (existsSync(spec.outPath)) {
      skipped++;
      manifest.push({ type: spec.type, category: spec.category, variant: spec.variant, tag: spec.tag, path: spec.outPath });
      continue;
    }
    process.stdout?.write?.(`[gen] ${spec.type}/${spec.category}/${spec.variant.toString().padStart(2, "0")}_${spec.tag}: `);
    const r = await generateOne(spec, args.dryRun);
    if (r.ok) {
      done++;
      console.log(args.dryRun ? "(dry)" : `${((r.bytes ?? 0) / 1024).toFixed(0)}KB`);
      manifest.push({ type: spec.type, category: spec.category, variant: spec.variant, tag: spec.tag, path: spec.outPath, bytes: r.bytes });
    } else {
      failed++;
      console.log(`FAIL: ${r.err}`);
    }
    if (!args.dryRun && done < specs.length - skipped) {
      await new Promise((res) => setTimeout(res, COOLDOWN_MS));
    }
  }

  await ensureDir(OUT_DIR);
  await Deno.writeTextFile(`${OUT_DIR}/manifest.json`, JSON.stringify({
    generated_at: new Date().toISOString(),
    total: specs.length,
    components: manifest,
  }, null, 2));

  console.log(`[gen] done. generated=${done} skipped=${skipped} failed=${failed}  (manifest at ${OUT_DIR}/manifest.json)`);
}

if (import.meta.main) main();
