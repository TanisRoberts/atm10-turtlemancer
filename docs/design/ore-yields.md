# Ore and ancient debris yields (spike #72)

Part of project #93. Research only, no code. Numbers come from mod recipe JSON and source, not from memory.

**Sources read** (all `datagen/generated` or `generated` recipe JSON, plus config classes):

| Mod | Branch / version read | Pack has |
| --- | --- | --- |
| Mekanism | `1.21.x`, mod_version 10.7.19, commit `bcd7a8b` | 10.7.19.85 |
| Create | `mc1.21.1/dev`, 6.0.11 | 6.0.10 |
| Immersive Engineering | `1.21.1` | 12.4.2-194 |
| Occultism | `version/1.21.1`, 1.205.0 | 1.224.4 (newer, recipes may differ) |
| Ender IO | `1.21.1` | 8.2.12-beta |

**Not checked:** Industrial Foregoing, Modern Industrialization, PneumaticCraft, Actually Additions (no ancient debris or raw ore recipe found worth chasing; AE2 has none). **Not visible from source:** KubeJS or datapack-style overrides ATM10 may ship. That is why there is one JEI question at the end.

Baseline: a furnace turns 1 raw ore into 1 ingot and 1 ancient debris into 1 netherite scrap. "x" below means ingots (or scrap) per raw ore (or per debris).

## 1. Ancient debris

| Route | Scrap per debris | Source recipe | Power per debris (J, Mekanism units) |
| --- | --- | --- | --- |
| Furnace / blast furnace | 1 | vanilla | fuel |
| **Mekanism enrich** | **2** | `enriching`, tag `c:ores/netherite_scrap` -> 2 `netherite_scrap` | 10,000 |
| **Mekanism crush, then enrich each** | **3** | `crushing` debris -> 3 `dirty_netherite_scrap`; `enriching` 1 dirty scrap -> 1 scrap | 10,000 + 3 x 10,000 = 40,000 |
| Occultism crusher | 2 | `occultism:crushing` debris -> 2 scrap dust, dust smelts 1:1 | spirit-driven, not measured |
| Immersive Engineering arc furnace | 2 (+ slag) | `arc_furnace` 512,000 FE total, 100 ticks | 512,000 FE |
| Create | no recipe | nothing found for debris or scrap | n/a |
| Ender IO SAG mill | no recipe | nothing found | n/a |

Answers to the open question: **the Mekanism crusher gives 3 dirty scrap in the 10.7.19 source** (not 2). The "2" in the old bug report matches the *enrich* recipe, which really is 2. Crush-then-enrich is 3 scrap, a 50% gain over enrich alone and 3x the furnace, for 4x the power of enrich alone (still small: 40,000 J = 16,000 FE at the default 2.5 J per FE, a few seconds of one Furnator).

Scrap to ingot (unchanged by any of this): 4 scrap + 4 gold ingots (crafting), or Mekanism `metallurgic_infusing` 4 scrap + 40 mB gold infusion (4 gold dust) -> netherite dust, smelted to an ingot. Same gold either way.

Other facts: the combiner turns 2 netherite dust + basalt into 1 ancient debris, so there is no loop worth building. Immersive Engineering mineral veins can yield debris (20% of a Nether vein sample), a way to get more debris, not more per debris.

## 2. Ordinary raw ore

Per raw ore, iron/copper/gold/lead/tin/osmium/uranium all use the same Mekanism numbers (checked every metal folder).

| Chain | x per raw | Needs | Power per raw (J) |
| --- | --- | --- | --- |
| Furnace | 1.0 | fuel | fuel |
| Create crush + wash/smelt | 1.0 | crushing wheels; gives XP nuggets (75%), washing gives 9 nuggets + 75% redstone | kinetic only |
| Immersive Engineering crusher | 1.33 | 3 raw -> 4 dust (1 dust + 33% a second) | 6,000 FE per op |
| Mekanism enrich | 1.33 | enrichment chamber/factory (3 raw -> 4 dust) | ~3,300 |
| **Ender IO SAG mill** | **1.8** | 1 dust + 80% a second + 5% tin dust | 2,400 per op |
| Occultism crusher | 2.0 per the recipe | crusher + spirit | not measured |
| **Mekanism purify** | **2.0** | oxygen. 1 raw -> 2 clump -> crush -> 2 dirty dust -> enrich -> 2 dust | 40,000 + 2 x 10,000 + 2 x 10,000 = 80,000 |
| Mekanism inject | 2.67 | hydrogen chloride (hydrogen + chlorine from brine). 3 raw -> 8 shards -> purify -> crush -> enrich | ~187,000 |
| Mekanism dissolve | 3.33 | sulfuric acid (sulfur dioxide + oxygen + water), washer, crystallizer. 3 raw -> 2000 mB slurry -> 10 crystals -> shards -> as inject | heaviest build and power, not totalled |

Power basis: Mekanism machine usage x 200 ticks per op (enrich, crush 50 J/t = 10,000 J; purify 200 J/t = 40,000 J; inject 400 J/t = 80,000 J). 1 FE = 2.5 J at the default config. The cost per extra ingot gets steep: purify buys +0.67x over enrich for ~80,000 J per raw, inject buys only +0.67x more for another ~107,000 J.

Mekanism has factories (3/5/7/9 processes at basic/advanced/elite/ultimate) for enriching, crushing, purifying, injecting and smelting. The dissolution chamber, washer and crystallizer are single machines with no factory form.

## 3. What Fortune and friends do

- **Fortune on raw ore drops**: ore blocks that drop raw ore (iron, gold, copper) use the vanilla ore formula. Average raw per ore block: Fortune I 1.33, II 1.75, III 2.2 (times the base drop, which copper already multiplies). This is a straight multiplier on everything in section 2, and costs no power.
- **Ancient debris**: drops itself, no Fortune bonus (vanilla loot table). Silk touch changes nothing for it. The only way to get more is the machines in section 1.
- **Raw ore blocks and storage blocks** are not affected by Fortune once placed. Fortune only matters at the moment the ore block is broken.
- **Create, Ender IO and the Mekanism chains ignore Fortune.** Their bonus is in the recipe.
- **Miners**: Canary and Firecrest use a pickaxe in the tool slot. Whether a Fortune-enchanted pickaxe on a turtle applies Fortune (CC: Tweaked passes the tool stack to the block drop) was not verified from CC source in this spike; test it with one enchanted pick on one miner before putting it in the plan.
- A Fortune III pick (x2.2) plus purification (x2.0) is about 4.4 ingots per iron/gold ore block mined, versus 1.0 now.

## 4. Recommendation

Build in this order:

1. **Ancient debris: crushing factory feeding an enriching factory (3 scrap per debris).** Cheapest and most useful, because debris is what is piling up. Build list: 1 crushing factory + 1 enriching factory (basic tier is enough, debris trickles in), a barrel for the feed, the crusher's eject into the enriching factory's input (hopper upgrade or a pipe), an out barrel on the enricher, wired modems on both for the smelter. If a stack of debris is on hand today and the build is far off, the existing enriching factory already gives 2 scrap per debris.
2. **Raw ore: oxygen, a purifying factory, then reuse the crusher and enrich factories (2.0x).** Build list: an electric pump or water source, an electrolytic separator for oxygen (and the hydrogen it makes can go to a heat or fuel use later), a purifying factory, plus the crusher and enricher from step 1 in a chain: purify -> crush -> enrich -> smelter. Skip injection and dissolution until power is plentiful: HCl needs a brine and chlorine chain, sulfuric acid needs a sulfur chain, and each gives only +0.67x over the previous step.
3. **Cheapest of all, no power:** a Fortune pick on the miners, after the single-miner test above.

**Can the smelter's factory route drive these?** Partly. `FX.factoryLike` in `computer/smelter/smelter.lua` accepts any machine with `getInput`, `getOutput` and `getRecipeProgress`, which all Mekanism factories have, and it reads only (no side config except auto-eject). So crushing, enriching and purifying factories can be registered. Gaps for the follow-up issues:

- The trial expects the output to be a *dust* that then smelts back to the same ore's ingot. Debris -> scrap has no smelting step (scrap is the end product), and crush gives *dirty scrap*, which is another stage.
- Chained factories (crusher -> enricher -> out) put a stage between the smelter's feed barrel and out barrel that the smelter cannot see, so the smelter would treat the *last* factory as the one it reads, and the first one would only show up as "something not moving".
- The oxygen and separator side is not item-based, so the smelter cannot see or control it; it needs to be self-running (pump + separator + power).
- The smelter has `netherite_scrap = { inputs = { "minecraft:ancient_debris" } }` in `smelt.txt`, so debris is already known as a smeltable input.

## Question for Tanis

In JEI, open Mekanism's **Crusher** and look up *Ancient Debris*: is the result **3 Dirty Netherite Scrap**? And does the **Enriching Chamber** show **2 Netherite Scrap** for debris? (Source says 3 and 2; this only checks that ATM10 hasn't changed them.)
