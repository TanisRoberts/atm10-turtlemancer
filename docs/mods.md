# Mod manifest

Taken from the jar file names in Tanis's client `mods` folder (CurseForge instance "All the Mods 10 - ATM10") on 15 Oct 2026. ATM10 8.2, NeoForge 21.1.251, Minecraft 1.21.1. 491 jars. Versions come from file names, so a few odd ones (Structory, Byzantine) are the author's own numbering.

To refresh it, list that folder again and regenerate this file. The server should match the client, but if something behaves differently in game, ask Tanis to check the server's mods.

## The ones the scripts talk to

| Mod | Version | Used for |
| --- | --- | --- |
| CC: Tweaked | 1.120.2 (see warning) | every computer and turtle |
| Advanced Peripherals | 0.8.1a | chat box, player detector, environment detector, inventory manager, ME bridge, chunky turtle, smart glasses |
| Functional Storage | 1.5.8 | drawers and the storage controller |
| Mekanism (+ Generators, Tools) | 10.7.19.85 | enrichment chamber and factories, steel |
| Iron Furnaces | 4.3.2 | the smelter's furnace array |
| Hostile Neural Networks | 6.5.1 | the neural lab |
| Industrial Foregoing | 3.6.39 | plastic line, latex, enchantment extractor |
| Powah | 6.2.10 | Furnators, energy cells |
| Extreme Reactors 2 (+ ZeroCore 2) | 2.4.28 (ZeroCore 2.4.21) | planned reactor |
| Applied Energistics 2 | 19.2.17 | planned storage backend |
| Ender Storage | 2.13.0.191 | Firecrest's ender chest home link |
| FTB Chunks | 2101.1.22 | chunk loading (25 force-loaded) |
| Mystical Agriculture (+ Agradditions) | 8.0.28 (8.0.14) | essence farming |
| Immersive Engineering | 12.4.2-194 | hemp on Partridge's farm |
| Pipez / LaserIO / XNet | 1.2.31 / 1.9.11 / 7.0.7 | cables miners must never dig |
| Refined Storage | 2.0.9 | cables miners must never dig |
| Create | 6.0.10 | washing for clay, general |

**Warning: two CC: Tweaked jars are installed** (`cc-tweaked-1.21.1-forge-1.113.1.jar` and `cc-tweaked-1.21.1-forge-1.120.2.jar`). Normally only one loads, and the server's copy is what turtles actually run. Check the API docs for 1.120.x, and ask Tanis to delete the older jar (it may be a leftover from a manual update).

**Extreme Reactors 2: use active power taps.** A passive FE power tap never pushes energy out (it only gives when something pulls), so the buffer fills and nothing flows. Build every reactor and turbine with an *Active* Forge Energy Power Tap. See `docs/systems/operator.md`.

## Everything

| Mod | Version | Jar |
| --- | --- | --- |
| accelerated-decay | 21.0.0 | `accelerated-decay-neoforge-21.0.0.jar` |
| actuallyadditions | 1.3.26 | `actuallyadditions-1.3.26+mc1.21.1.jar` |
| Ad-Astra-Giselle-Addon | 8.4 | `Ad-Astra-Giselle-Addon-neoforge-1.21.1-8.4.jar` |
| adastra | 1.16.26 | `adastra-1.21.1-1.16.26-neoforge.jar` |
| additional lights | 2.1.10 | `additional_lights-neoforge-1.21-2.1.10.jar` |
| AdditionalEnchantedMiner | 21.1.164 | `AdditionalEnchantedMiner-1.21.1-neoforge-21.1.164.jar` |
| AdvancedAE | 1.6.12 | `AdvancedAE-1.6.12-1.21.1.jar` |
| AdvancedPeripherals | 0.8.1a | `AdvancedPeripherals-1.21.1-0.8.1a.jar` |
| ae2ct | 1.1.1 | `ae2ct-1.21.1-1.1.1.jar` |
| ae2importexportcard | 1.9.0 | `ae2importexportcard-1.21.1-1.9.0.jar` |
| ae2jeiintegration | 1.2.1 | `ae2jeiintegration-1.2.1.jar` |
| AE2NetworkAnalyzer | 2.1.5 | `AE2NetworkAnalyzer-1.21-2.1.5-neoforge.jar` |
| ae2wtlib | 19.5.1 | `ae2wtlib-19.5.1.jar` |
| aeinfinitybooster | 1.0.0.58 | `aeinfinitybooster-neoforge-1.21.1-1.0.0.58.jar` |
| aether | 1.5.10 | `aether-1.21.1-1.5.10-neoforge.jar` |
| AI-Improvements | 0.5.3 | `AI-Improvements-1.21-0.5.3.jar` |
| AkashicTome | 1.8-30 | `AkashicTome-1.8-30.jar` |
| allthearcanistgear | 21.3.2 | `allthearcanistgear-1.21.1-21.3.2.jar` |
| allthecompressed | 4.4.0 | `allthecompressed-1.21.1-4.4.0.jar` |
| alltheleaks | 1.1.13 | `alltheleaks-1.1.13+1.21.1-neoforge.jar` |
| allthemodium | 3.0.1 | `allthemodium-3.0.1_mc_1.21.1.jar` |
| alltheores | 3.2.0 | `alltheores-3.2.0_neoforge_1.21.1.jar` |
| allthetweaks | 2.10.0 | `allthetweaks-1.21.1-2.10.0.jar` |
| allthewizardgear | 1.2.0 | `allthewizardgear-1.21.1-1.2.0.jar` |
| almostunified | 1.4.2 | `almostunified-neoforge-1.21.1-1.4.2.jar` |
| amendments | 2.1.10 | `amendments-1.21-2.1.10-neoforge.jar` |
| Apotheosis | 8.8.0 | `Apotheosis-1.21.1-8.8.0.jar` |
| ApothicAttributes | 2.10.1 | `ApothicAttributes-1.21.1-2.10.1.jar` |
| ApothicEnchanting | 1.6.2 | `ApothicEnchanting-1.21.1-1.6.2.jar` |
| ApothicSpawners | 1.4.0 | `ApothicSpawners-1.21.1-1.4.0.jar` |
| appleskin | 3.0.9 | `appleskin-neoforge-mc1.21-3.0.9.jar` |
| Applied-Mekanistics | 1.6.3 | `Applied-Mekanistics-1.6.3.jar` |
| appliedenergistics2 | 19.2.17 | `appliedenergistics2-19.2.17.jar` |
| AppliedFlux | 2.1.5 | `AppliedFlux-1.21-2.1.5-neoforge.jar` |
| Aquaculture | 2.7.21 | `Aquaculture-1.21.1-2.7.21.jar` |
| architectury | 13.0.11 | `architectury-13.0.11-neoforge.jar` |
| ars additions | 21.3.0 | `ars_additions-1.21.1-21.3.0.jar` |
| ars controle | 1.6.16 | `ars_controle-1.21.1-1.6.16.jar` |
| ars creo | 5.4.0 | `ars_creo-1.21.1-5.4.0.jar` |
| ars elemancy | 1.18.3 | `ars_elemancy-1.21.1-1.18.3.jar` |
| ars elemental | 0.7.10.1 | `ars_elemental-1.21.1-0.7.10.1.jar` |
| ars nouveau | 5.13.1 | `ars_nouveau-1.21.1-5.13.1.jar` |
| ars ocultas | 2.6.1 | `ars_ocultas-1.21.1-2.6.1.jar` |
| ars polymorphia | 1.0.3 | `ars_polymorphia-1.0.3.jar` |
| ars technica | 2.7.6 | `ars_technica-1.21.1-2.7.6.jar` |
| ars unification | 1.2.21 | `ars_unification-1.2.21.jar` |
| arseng | 2.1.1-beta | `arseng-2.1.1-beta.jar` |
| artifacts | 13.2.3 | `artifacts-neoforge-13.2.3.jar` |
| athena | 4.0.6 | `athena-neoforge-1.21.1-4.0.6.jar` |
| atlas api | 1.2.0 | `atlas_api-1.21.1-1.2.0.jar` |
| attributefix | 21.1.3 | `attributefix-neoforge-1.21.1-21.1.3.jar` |
| auroral | 1.1.2 | `auroral-1.21.1-1.1.2.jar` |
| Auroras | 1.6.2 | `Auroras-1.21-1.6.2.jar` |
| balm | 21.0.65 | `balm-neoforge-1.21.1-21.0.65.jar` |
| baubley-heart-canisters | 1.4.2 | `baubley-heart-canisters-1.21.1-1.4.2.jar` |
| bellsandwhistles | 0.4.7 | `bellsandwhistles-0.4.7-1.21.1.jar` |
| better-advanced-tooltips | 2101.1.0-build.5 | `better-advanced-tooltips-2101.1.0-build.5.jar` |
| better-compatability-checker | 21.1.8 | `better-compatability-checker-neoforge-21.1.8.jar` |
| BetterAdvancements | 0.4.3.21 | `BetterAdvancements-NeoForge-1.21.1-0.4.3.21.jar` |
| bibliobiomes | 1.6.1 | `bibliobiomes-1.21.1-1.6.1.jar` |
| bibliocraft | 1.6.5 | `bibliocraft-1.21.1-1.6.5.jar` |
| bibliowoods | 1.6.2 | `bibliowoods-1.21.1-1.6.2.jar` |
| blockui | 1.0.212 | `blockui-1.0.212-1.21.1-snapshot.jar` |
| blueflame | 1.1.1 | `blueflame-1.21.1-1.1.1.jar` |
| bookshelf | 21.1.81 | `bookshelf-neoforge-1.21.1-21.1.81.jar` |
| borderless | 1.7.5_1 | `borderless-neoforge-1.21.1-1.7.5_1-all.jar` |
| botanypots | 21.1.44 | `botanypots-neoforge-1.21.1-21.1.44.jar` |
| botanypotsmystical | 21.1.12 | `botanypotsmystical-neoforge-1.21.1-21.1.12.jar` |
| botanytrees | 21.1.7 | `botanytrees-neoforge-1.21.1-21.1.7.jar` |
| BrandonsCore | 3.2.1.309 | `BrandonsCore-1.21.1-3.2.1.309.jar` |
| BridgingMod | 2.6.2+1.21.1. | `BridgingMod-2.6.2+1.21.1.neoforge-release.jar` |
| buildinggadgets2 | 1.3.9 | `buildinggadgets2-1.3.9.jar` |
| bwncr | 3.20.4 | `bwncr-neoforge-1.21.1-3.20.4.jar` |
| Byzantine | 51 | `Byzantine-1.21.1-51.jar` |
| cabletiers | 0.6.14 | `cabletiers-neoforge-1.21.1-0.6.14.jar` |
| caelus | 7.0.1 | `caelus-neoforge-7.0.1+1.21.1.jar` |
| camol | 0.3.1 | `camol-1.21.1-0.3.1.jar` |
| catjammies | 1.7.1 | `catjammies-1.21-1.7.1.jar` |
| cc-tweaked | 1.113.1 | `cc-tweaked-1.21.1-forge-1.113.1.jar` |
| cc-tweaked | 1.120.2 | `cc-tweaked-1.21.1-forge-1.120.2.jar` |
| charginggadgets | 1.14.1 | `charginggadgets-1.14.1.jar` |
| chipped | 4.0.2 | `chipped-neoforge-1.21.1-4.0.2.jar` |
| chisel | 2.0.1 | `chisel-neoforge-2.0.1+mc1.21.1.jar` |
| chromacarvings | 0.2.0 | `chromacarvings-1.21.1-0.2.0.jar` |
| cleanswing | 1.10 | `cleanswing-1.10-1.21.jar` |
| cloth-config | 15.0.140 | `cloth-config-15.0.140-neoforge.jar` |
| CloudGlass | 1.0.2 | `CloudGlass-1.21.1-1.0.2.jar` |
| Clumps | 19.0.0.1 | `Clumps-neoforge-1.21.1-19.0.0.1.jar` |
| cobblegengalore | 0.2.9 | `cobblegengalore-1.21.1-0.2.9.jar` |
| cobweb | 1.4.0 | `cobweb-neoforge-1.21-1.4.0.jar` |
| CodeChickenLib | 4.6.1.529 | `CodeChickenLib-1.21.1-4.6.1.529.jar` |
| colorfulhearts | 10.5.9 | `colorfulhearts-neoforge-1.21.1-10.5.9.jar` |
| colorwheel | 1.3.0-beta3 | `colorwheel-neoforge-1.3.0-beta3+mc1.21.1.jar` |
| colorwheel patcher | 1.0.5 | `colorwheel_patcher-neoforge-1.0.5+mc1.21.1.jar` |
| comforts | 9.0.5 | `comforts-neoforge-9.0.5+1.21.1.jar` |
| common-storage-lib | 0.0.10 | `common-storage-lib-neoforge-1.21.1-0.0.10.jar` |
| commoncapabilities | 2.11.6 | `commoncapabilities-1.21.1-neoforge-2.11.6.jar` |
| compactmachines | 7.0.81 | `compactmachines-neoforge-7.0.81.jar` |
| connectedglass | 1.1.14 | `connectedglass-1.1.14-neoforge-mc1.21.jar` |
| connectivity | 7.6 | `connectivity-1.21.1-7.6.jar` |
| ConstructionSticks | 1.5.0 | `ConstructionSticks-1.21.1-1.5.0.jar` |
| Controlling | 19.0.5 | `Controlling-neoforge-1.21.1-19.0.5.jar` |
| cookingforblockheads | 21.1.24 | `cookingforblockheads-neoforge-1.21.1-21.1.24.jar` |
| copycats | 3.0.9+mc. | `copycats-3.0.9+mc.1.21.1-neoforge.jar` |
| Corgilib | 5.0.0.9 | `Corgilib-NeoForge-1.21.1-5.0.0.9.jar` |
| cosmeticarmorreworked | 1 | `cosmeticarmorreworked-1.21.1-v1-neoforge.jar` |
| crafting on a stick | 1.21.0.6 | `crafting_on_a_stick-1.21.0.6.jar` |
| craftingtweaks | 21.1.11 | `craftingtweaks-neoforge-1.21.1-21.1.11.jar` |
| CrashAssistant | 1.20.6-1.11.12 | `CrashAssistant-neoforge-1.20.6-1.21.4-1.11.12.jar` |
| crashutilities | 9.0.4 | `crashutilities-9.0.4.jar` |
| create | 6.0.10 | `create-1.21.1-6.0.10.jar` |
| create aquatic ambitions | 2.0.4 | `create_aquatic_ambitions-1.21.1-2.0.4.jar` |
| create hypertube | 0.6.0 | `create_hypertube-0.6.0-NEOFORGE.jar` |
| create-enchantment-industry | 2.5.4 | `create-enchantment-industry-2.5.4.jar` |
| createaddition | 1.7.1 | `createaddition-1.7.1.jar` |
| CreateDragonsPlus | 1.11.9 | `CreateDragonsPlus-1.11.9.jar` |
| CreeperOverhaul | 4.0.6 | `CreeperOverhaul-neoforge-1.21.1-4.0.6.jar` |
| cristellib | 3.1.7 | `cristellib-neoforge-1.21.1-3.1.7.jar` |
| cryonicconfig | 1.0.0 | `cryonicconfig-neoforge-1.0.0+mc1.21.11.jar` |
| crystalix | 3.0.1 | `crystalix-3.0.1.jar` |
| CTM | 1.2.1+3 | `CTM-1.21-1.2.1+3.jar` |
| ctov | 3.6.3 | `[Neoforge]ctov-3.6.3.jar` |
| Cucumber | 8.0.16 | `Cucumber-1.21.1-8.0.16.jar` |
| cupboard | 4.2 | `cupboard-1.21.1-4.2.jar` |
| curios | 9.5.1 | `curios-neoforge-9.5.1+1.21.1.jar` |
| cyclopscore | 1.30.0 | `cyclopscore-1.21.1-neoforge-1.30.0.jar` |
| darkmodeeverywhere | 1.4.0 | `darkmodeeverywhere-neoforge-1.21.1-1.4.0.jar` |
| deeperdarker | 1.4.1 | `deeperdarker-neoforge-1.21.1-1.4.1.jar` |
| deimos | 2.7 | `deimos-1.21.1-neoforge-2.7.jar` |
| DimStorage | 9.1.1 | `DimStorage-1.21.1-9.1.1.jar` |
| disenchanting table-merged | 5.0.2 | `disenchanting_table-merged-1.21.1-5.0.2.jar` |
| domum-ornamentum | 1.0.236 | `domum-ornamentum-1.0.236-snapshot-main.jar` |
| Draconic-Evolution | 3.1.4.633 | `Draconic-Evolution-1.21.1-3.1.4.633.jar` |
| drippyloadingscreen | 3.1.5 | `drippyloadingscreen_neoforge_3.1.5_MC_1.21.1.jar` |
| dummmmmmy | 2.1.2 | `dummmmmmy-1.21-2.1.2-neoforge.jar` |
| DungeonCrawl | 2.3.17 | `DungeonCrawl-NeoForge-1.21-2.3.17.jar` |
| DungeonsArise | 2.1.68 | `DungeonsArise-1.21.1-2.1.68-release.jar` |
| dyenamics | 3.4.2 | `dyenamics-1.21.1-3.4.2.jar` |
| dyenamicsandfriends | 2.2.2 | `dyenamicsandfriends-1.21.1-2.2.2.jar` |
| dysoncubeproject | 1.0.5 | `dysoncubeproject-1.0.5.jar` |
| easy-villagers | 1.1.42 | `easy-villagers-neoforge-1.21.1-1.1.42.jar` |
| EdivadLib | 3.0.0 | `EdivadLib-1.21-3.0.0.jar` |
| elevatorid | 1.11.4 | `elevatorid-neoforge-1.21.1-1.11.4.jar` |
| enchdesc | 21.1.11 | `enchdesc-neoforge-1.21.1-21.1.11.jar` |
| enderdrives | 1.5.23 | `enderdrives-neoforge-1.21.1-1.5.23.jar` |
| enderio | 8.2.12-beta | `enderio-8.2.12-beta.jar` |
| endermanoverhaul | 2.0.3 | `endermanoverhaul-neoforge-1.21.1-2.0.3.jar` |
| EnderStorage | 2.13.0.191 | `EnderStorage-1.21.1-2.13.0.191.jar` |
| energymeter | 0.5.2 | `energymeter-neoforge-1.21.1-0.5.2.jar` |
| entangled | 1.3.21 | `entangled-1.3.21-neoforge-mc1.21.jar` |
| eternalstarlight | 0.9.1 | `eternalstarlight-0.9.1+1.21.1+neoforge.jar` |
| EuphoriaPatcher | 1.10.5-r5.9.3 | `EuphoriaPatcher-1.10.5-r5.9.3-neoforge.jar` |
| everythingcopper | 2.4.5 | `everythingcopper-1.21.1-2.4.5.jar` |
| evilcraft | 1.2.96-1106 | `evilcraft-1.21.1-neoforge-1.2.96-1106.jar` |
| expandedae | 2.1.3 | `expandedae-2.1.3.jar` |
| experiencelib | 1.2.1 | `experiencelib-1.21.1-1.2.1.jar` |
| ExplorersCompass | 3.4.0 | `ExplorersCompass-1.21.1-3.4.0-neoforge.jar` |
| Explorify | 1.6.5.mod | `Explorify v1.6.5.mod.jar` |
| extended-industrialization | 1.16.2 | `extended-industrialization-1.16.2-1.21.1.jar` |
| ExtendedAE | 2.2.38 | `ExtendedAE-1.21-2.2.38-neoforge.jar` |
| ExtraDisks | 4.0.15 | `ExtraDisks-1.21.1-4.0.15.jar` |
| ExtraStorage | 5.0.10 | `ExtraStorage-1.21.1-5.0.10.jar` |
| ExtremeReactors2 | 2.4.28 | `ExtremeReactors2-1.21.1-2.4.28.jar` |
| ExtremeSoundMuffler | 3.56 | `ExtremeSoundMuffler-3.56_NeoForge-1.21.jar` |
| factory blocks | 1.4.0 | `factory_blocks-neoforge-1.4.0+mc1.21.1.jar` |
| fancymenu | 3.9.12 | `fancymenu_neoforge_3.9.12_MC_1.21.1.jar` |
| FarmersDelight | 1.3.4 | `FarmersDelight-1.21.1-1.3.4.jar` |
| farmingforblockheads | 21.1.13 | `farmingforblockheads-neoforge-1.21.1-21.1.13.jar` |
| FastFurnace | 9.0.1 | `FastFurnace-1.21.1-9.0.1.jar` |
| FastSuite | 6.0.7 | `FastSuite-1.21.1-6.0.7.jar` |
| FastWorkbench | 9.1.3 | `FastWorkbench-1.21.1-9.1.3.jar` |
| ferritecore | 7.0.3 | `ferritecore-7.0.3-neoforge.jar` |
| fireproofboats | 1.0.4 | `fireproofboats-1.21.1-1.0.4.jar` |
| flickerfix | 6.1.0 | `flickerfix-1.21.1-6.1.0.jar` |
| FluxNetworks | 8.0.0 | `FluxNetworks-1.21.1-8.0.0.jar` |
| forbidden arcanus | 2.6.1 | `forbidden_arcanus-2.6.1.jar` |
| formations | 1.0.4 | `formations-1.0.4-neoforge-mc1.21.jar` |
| formationsnether | 1.0.5b | `formationsnether-1.0.5b-mc1.21+.jar` |
| formationsoverworld | 1.0.5c | `formationsoverworld-1.0.5c-mc1.21+.jar` |
| FramedBlocks | 10.6.2 | `FramedBlocks-10.6.2.jar` |
| framework | 0.13.11 | `framework-neoforge-1.21.1-0.13.11.jar` |
| ftb-chunks | 2101.1.22 | `ftb-chunks-neoforge-2101.1.22.jar` |
| ftb-essentials | 2101.1.10 | `ftb-essentials-neoforge-2101.1.10.jar` |
| ftb-filter-system | 21.1.4 | `ftb-filter-system-neoforge-21.1.4.jar` |
| ftb-jei-extras | 21.1.7 | `ftb-jei-extras-21.1.7.jar` |
| ftb-library | 2101.1.36 | `ftb-library-neoforge-2101.1.36.jar` |
| ftb-quests | 2101.1.36 | `ftb-quests-neoforge-2101.1.36.jar` |
| ftb-ranks | 2101.1.5 | `ftb-ranks-neoforge-2101.1.5.jar` |
| ftb-teams | 2101.1.11 | `ftb-teams-neoforge-2101.1.11.jar` |
| ftb-ultimine | 2101.1.15 | `ftb-ultimine-neoforge-2101.1.15.jar` |
| ftb-xmod-compat | 21.1.12 | `ftb-xmod-compat-neoforge-21.1.12.jar` |
| ftbquestslangsplitter | 1.0.7 | `ftbquestslangsplitter-1.0.7.jar` |
| fuelgoeshere | 1.2.0 | `fuelgoeshere-1.21.1-1.2.0.jar` |
| functionalstorage | 1.5.8 | `functionalstorage-1.21.1-1.5.8.jar` |
| fusion | 1.3.15b | `fusion-1.3.15b-neoforge-mc1.21.1.jar` |
| fzzy config | 0.7.7 | `fzzy_config-0.7.7+1.21+neoforge.jar` |
| GatewaysToEternity | 5.1.0 | `GatewaysToEternity-1.21.1-5.1.0.jar` |
| geckolib | 4.9.3 | `geckolib-neoforge-1.21.1-4.9.3.jar` |
| generatorgalore | 1.7.0 | `generatorgalore-1.21.1-1.7.0.jar` |
| getittogetherdrops | 1.4 | `getittogetherdrops-neoforge-1.21.5-1.4.jar` |
| Glassential-renewed | 3.4.7 | `Glassential-renewed-1.21.1-3.4.7.jar` |
| Glodium | 2.2 | `Glodium-1.21-2.2-neoforge.jar` |
| GravitationalModulatingAdditionalUnit | 6.4 | `GravitationalModulatingAdditionalUnit-1.21.1-6.4.jar` |
| guideme | 21.1.19 | `guideme-21.1.19.jar` |
| handcrafted | 4.0.3 | `handcrafted-neoforge-1.21.1-4.0.3.jar` |
| hardenedarmadillos | 0.2.0 | `hardenedarmadillos-1.21.1-0.2.0.jar` |
| HellishTrials | 1.0.5 | `HellishTrials-neoforge-1.0.5.jar` |
| herbsandharvest | 21 | `herbsandharvest-1.21.1-21.jar` |
| heyberryshutup | 2.0.4 | `heyberryshutup-1.21.0-2.0.4.jar` |
| HostileNeuralNetworks | 6.5.1 | `HostileNeuralNetworks-1.21.1-6.5.1.jar` |
| iceandfire | 2.0-beta.17 | `iceandfire-2.0-beta.17.jar` |
| Iceberg | 1.3.2 | `Iceberg-1.21.1-neoforge-1.3.2.jar` |
| illagerwarship | 1.0.1 | `illagerwarship-1.0.1-neoforge-1.21.1.jar` |
| imfast | 1.0.3 | `imfast-NEOFORGE-1.21.1-1.0.3.jar` |
| ImmediatelyFast | 1.6.14 | `ImmediatelyFast-NeoForge-1.6.14+1.21.1.jar` |
| Immersive-Energistics | 1.1.0-beta | `Immersive-Energistics-1.1.0-beta.jar` |
| ImmersiveEngineering | 12.4.2-194 | `ImmersiveEngineering-1.21.1-12.4.2-194.jar` |
| incontrol | 10.3.0 | `incontrol-1.21-10.3.0.jar` |
| industrial-foregoing-souls | 1.10.7 | `industrial-foregoing-souls-1.21.1-1.10.7.jar` |
| industrialforegoing | 3.6.39 | `industrialforegoing-1.21-3.6.39.jar` |
| industrialization overdrive | 1.14.0 | `industrialization_overdrive-1.14.0+1.21.1.jar` |
| integratedcrafting | 1.7.2 | `integratedcrafting-1.21.1-neoforge-1.7.2.jar` |
| integrateddynamics | 1.37.1-2160 | `integrateddynamics-1.21.1-neoforge-1.37.1-2160.jar` |
| integratedscripting | 1.0.27 | `integratedscripting-1.21.1-neoforge-1.0.27.jar` |
| integratedterminals | 1.10.0 | `integratedterminals-1.21.1-neoforge-1.10.0.jar` |
| integratedtunnels | 1.12.0-792 | `integratedtunnels-1.21.1-neoforge-1.12.0-792.jar` |
| interdimensionalwirelesstransmitter | 0.1.5 | `interdimensionalwirelesstransmitter-neoforge-1.21.1-0.1.5.jar` |
| invasiveopts | 1.0.24 | `invasiveopts-1.0.24.jar` |
| invtweaks | 1.3.2 | `invtweaks-1.21.1-1.3.2.jar` |
| iris | 1.8.14-beta.1 | `iris-neoforge-1.8.14-beta.1+mc1.21.1.jar` |
| IrisSearch | 1.8.1 | `IrisSearch-1.8.1-neoforge.jar` |
| ironfurnaces | 4.3.2 | `ironfurnaces-neoforge-1.21.1-4.3.2.jar` |
| IronJetpacks | 8.0.11 | `IronJetpacks-1.21.1-8.0.11.jar` |
| irons jewelry | 2.0.2 | `irons_jewelry-1.21.1-2.0.2.jar` |
| irons lib | 2.1.1 | `irons_lib-1.21.1-2.1.1.jar` |
| irons spellbooks | 3.16.3 | `irons_spellbooks-1.21.1-3.16.3.jar` |
| itemcollectors | 1.1.10 | `itemcollectors-1.1.10-neoforge-mc1.21.jar` |
| Jade | 15.10.6 | `Jade-1.21.1-NeoForge-15.10.6.jar` |
| jearchaeology | 1.2.0 | `jearchaeology-1.21.1-1.2.0.jar` |
| jei | 19.57.0.446 | `jei-1.21.1-neoforge-19.57.0.446.jar` |
| jeistuff | 1.2.1 | `jeistuff-1.21.1-1.2.1.jar` |
| journeymap | 6.0.9 | `journeymap-neoforge-1.21.1-6.0.9.jar` |
| jumpboat | 1.0.5 | `jumpboat-1.21.0-1.0.5.jar` |
| jupiter | 2.3.7 | `jupiter-2.3.7-1.21.1-neoforge.jar` |
| justdirethings | 1.5.7 | `justdirethings-1.5.7.jar` |
| justenoughbreeding | 3.2.1 | `justenoughbreeding-neoforge-1.21.1-3.2.1.jar` |
| JustEnoughMekanismMultiblocks | 7.21 | `JustEnoughMekanismMultiblocks-1.21.1-7.21.jar` |
| JustEnoughProfessions | 4.0.5 | `JustEnoughProfessions-neoforge-1.21.1-4.0.5.jar` |
| justzoom | 2.1.0 | `justzoom_neoforge_2.1.0_MC_1.21.1.jar` |
| keybindbundles | 1.4.0 | `keybindbundles-1.4.0.jar` |
| KeybindsPurger | 1.4.0 | `KeybindsPurger-1.4.0-neoforge-1.21.1.jar` |
| konkrete | 1.9.9 | `konkrete_neoforge_1.9.9_MC_1.21.jar` |
| kotlinfor | 5.12.0 | `kotlinforforge-5.12.0-all.jar` |
| kubejs | 2101.7.2-build.374 | `kubejs-neoforge-2101.7.2-build.374.jar` |
| kubejstweaks | 1.0.6 | `kubejstweaks-1.0.6.jar` |
| L Ender's Cataclysm | 3.33 | `L_Ender's Cataclysm 1.21.1-3.33.jar` |
| laserbridges | 6 | `laserbridges-1.21.1-neoforge-6.jar` |
| laserio | 1.9.11 | `laserio-1.9.11.jar` |
| lionfishapi | 3.1 | `lionfishapi-3.1.jar` |
| lithostitched | 1.8.0-21.1 | `lithostitched-1.8.0-neoforge-21.1.jar` |
| little-big-redstone | 1.9.11 | `little-big-redstone-1.9.11-1.21.1.jar` |
| livingthings | 2.3.2 | `livingthings-neoforge-1.21.1-2.3.2.jar` |
| lmft | 1.1.1 | `lmft-1.1.1+1.21.9-neoforge.jar` |
| logisticsnetworks | 1.16.3 | `logisticsnetworks-1.21.1-1.16.3.jar` |
| lootr | 1.11.38.126 | `lootr-neoforge-1.21.1-1.11.38.126.jar` |
| luminax | 1.3.1 | `luminax-1.3.1_neoforge_1.21.1.jar` |
| mahoutsukai | 1.36.28 | `mahoutsukai-1.21.1-v1.36.28.jar` |
| mcjtylib | 9.0.21 | `mcjtylib-1.21-9.0.21.jar` |
| mcw-bridges | 3.1.2 | `mcw-bridges-3.1.2-mc1.21.1neoforge.jar` |
| mcw-doors | 1.1.5 | `mcw-doors-1.1.5-mc1.21.1neoforge.jar` |
| mcw-furniture | 3.4.1 | `mcw-furniture-3.4.1-mc1.21.1neoforge.jar` |
| mcw-holidays | 1.1.2 | `mcw-holidays-1.1.2-mc1.21.1neoforge.jar` |
| mcw-lights | 1.1.5 | `mcw-lights-1.1.5-mc1.21.1neoforge.jar` |
| mcw-mcwfences | 1.2.1 | `mcw-mcwfences-1.2.1-mc1.21.1neoforge.jar` |
| mcw-mcwpaths | 1.1.1 | `mcw-mcwpaths-1.1.1-mc1.21.1neoforge.jar` |
| mcw-mcwstairs | 1.0.2 | `mcw-mcwstairs-1.0.2-mc1.21.1neoforge.jar` |
| mcw-mcwwindows | 2.4.2 | `mcw-mcwwindows-2.4.2-mc1.21.1neoforge.jar` |
| mcw-roofs | 2.3.2 | `mcw-roofs-2.3.2-mc1.21.1neoforge.jar` |
| mcw-trapdoors | 1.1.5 | `mcw-trapdoors-1.1.5-mc1.21.1neoforge.jar` |
| Measurements | 3.0.3 | `Measurements-neoforge-1.21.1-3.0.3.jar` |
| megacells | 4.11.0 | `megacells-4.11.0.jar` |
| Mekanism | 10.7.19.85 | `Mekanism-1.21.1-10.7.19.85.jar` |
| mekanismcovers | 1.3-BETA | `mekanismcovers-1.3-BETA+1.21.jar` |
| MekanismGenerators | 10.7.19.85 | `MekanismGenerators-1.21.1-10.7.19.85.jar` |
| MekanismTools | 10.7.19.85 | `MekanismTools-1.21.1-10.7.19.85.jar` |
| mekanisticrouters | 1.2.0 | `mekanisticrouters-1.2.0.jar` |
| mekmm | 1.4.1 | `mekmm-1.21.1-1.4.1.jar` |
| melody | 1.0.10 | `melody_neoforge_1.0.10_MC_1.21.jar` |
| memorysettings | 6.0 | `memorysettings-1.21-6.0.jar` |
| merequester | 1.5.0 | `merequester-neoforge-1.21.1-1.5.0.jar` |
| merrymaking | 16 | `merrymaking-1.21.1-16.jar` |
| mezz config | 0.6.3 | `mezz_config-1.21.1-neoforge-0.6.3.jar` |
| mffs | 5.4.44 | `mffs-5.4.44.jar` |
| mifa | 2.1.0 | `mifa-neoforge-1.21.x-2.1.0.jar` |
| minecolonies | 1.1.1396 | `minecolonies-1.1.1396-1.21.1-snapshot.jar` |
| mininggadgets | 1.18.8 | `mininggadgets-1.18.8.jar` |
| mob grinding utils | 1.1.10 | `mob_grinding_utils-1.1.10+mc1.21.1.jar` |
| modelfix | 1.10 | `modelfix-1.21-1.10.jar` |
| Modern-Dynamics | 0.9.6 | `Modern-Dynamics-0.9.6.jar` |
| Modern-Industrialization | 2.5.8 | `Modern-Industrialization-2.5.8.jar` |
| modernfix | 5.27.24 | `modernfix-neoforge-5.27.24+mc1.21.1.jar` |
| modonomicon | 1.120.4 | `modonomicon-1.21.1-neoforge-1.120.4.jar` |
| modular-routers | 13.2.7 | `modular-routers-13.2.7+mc1.21.1.jar` |
| ModularBees | 3.4 | `ModularBees-1.21.1-3.4-neoforge.jar` |
| monolib | 4.1.0 | `monolib-neoforge-1.21.1-4.1.0.jar` |
| MoogsEndStructures | 2.1.1 | `MoogsEndStructures-universal-1.21-2.1.1.jar` |
| MoogsNetherStructures | 3.1.1 | `MoogsNetherStructures-universal-1.21-3.1.1.jar` |
| MoogsSoaringStructures | 2.2.0 | `MoogsSoaringStructures-universal-1.21-2.2.0.jar` |
| MoogsStructureLib | 3.3.1 | `MoogsStructureLib-neoforge-1.21.1-3.3.1.jar` |
| MoogsVoyagerStructures | 5.1.2 | `MoogsVoyagerStructures-universal-1.21-5.1.2.jar` |
| moonlight | 3.6.8 | `moonlight-1.21.1-3.6.8-neoforge.jar` |
| moredragoneggs | 5.0 | `moredragoneggs-5.0.jar` |
| moreoverlays | 1.24.2 | `moreoverlays-1.24.2-mc1.21.1-neoforge.jar` |
| morered | 6.0.0.3 | `morered-1.21.1-6.0.0.3.jar` |
| MoreRed-CCT-Compat | 1.3.0 | `MoreRed-CCT-Compat-1.21.1-1.3.0.jar` |
| mostructures | 1.6.0 | `mostructures-neoforge-1.6.0+1.21.1.jar` |
| MouseTweaks | 2.26.1 | `MouseTweaks-neoforge-mc1.21-2.26.1.jar` |
| multipiston | 1.2.58 | `multipiston-1.2.58-1.21.1.jar` |
| MysticalAgradditions | 8.0.14 | `MysticalAgradditions-1.21.1-8.0.14.jar` |
| MysticalAgriculture | 8.0.28 | `MysticalAgriculture-1.21.1-8.0.28.jar` |
| MysticalCustomization | 6.0.2 | `MysticalCustomization-1.21.1-6.0.2.jar` |
| NaturesAura | 41.10 | `NaturesAura-41.10.jar` |
| NaturesCompass | 3.4.0 | `NaturesCompass-1.21.1-3.4.0-neoforge.jar` |
| NeoAuth | 1.0.1 | `NeoAuth-1.21.1-1.0.1.jar` |
| neovitae | 1.1.26 | `neovitae-1.21.1-1.1.26.jar` |
| netherportalfix | 21.1.1 | `netherportalfix-neoforge-1.21.1-21.1.1.jar` |
| NoChatReports | 2.9.1 | `NoChatReports-NEOFORGE-1.21.1-v2.9.1.jar` |
| not enough glyphs | 4.6.2 | `not_enough_glyphs-1.21.1-4.6.2.jar` |
| notenoughanimations | 1.12.6 | `notenoughanimations-neoforge-1.12.6-mc1.21.1.jar` |
| novillagerdm | 6.0.0 | `novillagerdm-1.21.1-6.0.0.jar` |
| Nullscape | 1.2.14 | `Nullscape_1.21.x_v1.2.14.jar` |
| observable | 5.4.4 | `observable-5.4.4.jar` |
| occultism | 1.224.4 | `occultism-1.21.1-neoforge-1.224.4.jar` |
| occultism kubejs | 1.11.0 | `occultism_kubejs-1.21.1-neoforge-1.11.0.jar` |
| OctoLib | 0.6.2 | `OctoLib-NEOFORGE-0.6.2+1.21.jar` |
| Oh-The-Biomes-Weve-Gone | 2.6.0 | `Oh-The-Biomes-Weve-Gone-NeoForge-2.6.0.jar` |
| Oh-The-Trees-Youll-Grow | 5.3.2 | `Oh-The-Trees-Youll-Grow-neoforge-1.21.1-5.3.2.jar` |
| omegaconfig | 1.5.1 | `omegaconfig-neoforge-1.5.1.jar` |
| OpenLoader | 21.1.5 | `OpenLoader-neoforge-1.21.1-21.1.5.jar` |
| oracle index | 1.4.0 | `oracle_index-neoforge-1.4.0.jar` |
| oritech | 1.2.12 | `oritech-neoforge-1.21.1-1.2.12.jar` |
| overlapless | 1.2.0 | `overlapless-1.21.1-1.2.0.jar` |
| overloadedarmorbar | 2 | `overloadedarmorbar-neoforge-1.21-2.jar` |
| owo-lib | 0.12.15.5-beta.1 | `owo-lib-neoforge-0.12.15.5-beta.1+1.21.jar` |
| pamhc2crops | 1.0.9 | `pamhc2crops-NEOFORGE-1.21.1-1.0.9.jar` |
| pamhc2foodcore | 1.0.4 | `pamhc2foodcore-NEOFORGE-1.21.1-1.0.4.jar` |
| pamhc2foodextended | 1.0.0 | `pamhc2foodextended-NEOFORGE-1.21.1-1.0.0.jar` |
| pamhc2trees | 1.0.9 | `pamhc2trees-NEOFORGE-1.21.1-1.0.9.jar` |
| Patchouli | 93 | `Patchouli-1.21.1-93-NEOFORGE.jar` |
| pipez | 1.2.31 | `pipez-neoforge-1.21.1-1.2.31.jar` |
| Placebo | 9.9.2 | `Placebo-1.21.1-9.9.2.jar` |
| player-animation-lib | 2.0.4 | `player-animation-lib-forge-2.0.4+1.21.1.jar` |
| pneumaticcraft-repressurized | 8.2.23 | `pneumaticcraft-repressurized-8.2.23+mc1.21.1.jar` |
| pocketstorage | 1.2.5-b3 | `pocketstorage-1.2.5+1.21.1-b3.jar` |
| polyeng | 0.4.1 | `polyeng-0.4.1.jar` |
| polylib | 2100.1.0-build.183 | `polylib-2100.1.0-build.183-neoforge.jar` |
| polymorph | 1.2.0 | `polymorph-neoforge-1.2.0+1.21.1.jar` |
| ponderjs | 2.4.0 | `ponderjs-neoforge-1.21.1-2.4.0.jar` |
| potionsmaster | 21.1.113-1.0.1 | `potionsmaster-21.1.113-1.0.1.jar` |
| Powah | 6.2.10 | `Powah-6.2.10.jar` |
| prickle | 21.1.11 | `prickle-neoforge-1.21.1-21.1.11.jar` |
| Prism | 1.0.11 | `Prism-1.21.1-neoforge-1.0.11.jar` |
| productivebees | 13.13.5 | `productivebees-1.21.1-13.13.5.jar` |
| productivemetalworks | 1.15.1 | `productivemetalworks-1.21.1-1.15.1.jar` |
| productivetrees | 1.1.1 | `productivetrees-1.21.1-1.1.1.jar` |
| pylons | 5.4.2 | `pylons-1.21.1-5.4.2.jar` |
| railcraft-reborn | 1.2.10 | `railcraft-reborn-1.21.1-1.2.10.jar` |
| Rainbows | 1.5 | `Rainbows-1.21-1.5.jar` |
| rangedpumps | 1.3.0 | `rangedpumps-1.3.0.jar` |
| rebind narrator | 2026.08.31 | `rebind_narrator-1.21.1-neoforge-2026.08.31.jar` |
| rechiseled | 1.2.6 | `rechiseled-1.2.6-neoforge-mc1.21.jar` |
| rechiseled chipped | 2.0 | `rechiseled_chipped-2.0-1.21.1.jar` |
| rechiseledcreate | 1.1.1 | `rechiseledcreate-1.1.1-neoforge-mc1.21.jar` |
| redstonepen | 1.11.42 | `redstonepen-1.21-neoforge-1.11.42.jar` |
| refined-types | 0.3.2 | `refined-types-1.21.1-0.3.2.jar` |
| refinedstorage | 2.0.9 | `refinedstorage-neoforge-2.0.9.jar` |
| refinedstorage-curios-integration | 1.0.0 | `refinedstorage-curios-integration-1.0.0.jar` |
| refinedstorage-jei-integration | 1.0.0 | `refinedstorage-jei-integration-neoforge-1.0.0.jar` |
| refinedstorage-mekanism-integration | 1.1.1 | `refinedstorage-mekanism-integration-1.1.1.jar` |
| refinedstorage-quartz-arsenal | 1.0.8 | `refinedstorage-quartz-arsenal-neoforge-1.0.8.jar` |
| refurbished furniture | 1.0.22 | `refurbished_furniture-neoforge-1.21.1-1.0.22.jar` |
| regions unexplored | 0.5.9 | `regions_unexplored-neoforge-1.21.1-0.5.9.jar` |
| relics | 0.12.8 | `relics-1.21.1-0.12.8.jar` |
| reliquary | 2.0.80.1570 | `reliquary-1.21.1-2.0.80.1570.jar` |
| reliquified artifacts | 1.0.8 | `reliquified_artifacts-1.21.1-1.0.8.jar` |
| repeatable trial vaults | 1.0.3 | `repeatable_trial_vaults-neoforge-1.21-1.0.3.jar` |
| repurposed structures | 7.5.22 | `repurposed_structures-7.5.22+1.21.1-neoforge.jar` |
| resourcefulconfig | 3.0.11 | `resourcefulconfig-neoforge-1.21-3.0.11.jar` |
| resourcefullib | 3.0.12 | `resourcefullib-neoforge-1.21-3.0.12.jar` |
| restrictions | 7.0.3 | `restrictions-1.21-7.0.3.jar` |
| rftoolsbase | 6.0.11 | `rftoolsbase-1.21-6.0.11.jar` |
| rftoolsbuilder | 7.0.6 | `rftoolsbuilder-1.21-7.0.6.jar` |
| rftoolspower | 7.0.6 | `rftoolspower-1.21-7.0.6.jar` |
| rftoolsstorage | 6.0.5 | `rftoolsstorage-1.21-6.0.5.jar` |
| rftoolsutility | 7.0.12 | `rftoolsutility-1.21-7.0.12.jar` |
| rhino | 2101.2.8-build.91 | `rhino-2101.2.8-build.91.jar` |
| RootsClassic | 1.5.10 | `RootsClassic-1.21.1-1.5.10.jar` |
| sawmill | 1.8.1 | `sawmill-1.21-1.8.1-neoforge.jar` |
| ScalableCatsForce | 3.7.1-build-11-with-library | `ScalableCatsForce-NeoForge-3.7.1-build-11-with-library.jar` |
| Searchables | 1.0.2 | `Searchables-neoforge-1.21.1-1.0.2.jar` |
| SecurityCraft | 1.10.2.1 | `[1.21.1] SecurityCraft v1.10.2.1.jar` |
| sgearmetalworks | 1.5.0 | `sgearmetalworks-1.21.1-1.5.0.jar` |
| shiny | 1.3.0 | `shiny-1.21.1-1.3.0.jar` |
| shrink | 2.0.1.47 | `shrink-2.0.1.47-neoforge.jar` |
| silent-gear | 4.2.1.1 | `silent-gear-1.21.1-neoforge-4.2.1.1.jar` |
| silent-lib | 10.6.0 | `silent-lib-1.21.1-neoforge-10.6.0.jar` |
| silentgems | 5.1.3 | `silentgems-1.21.1-neoforge-5.1.3.jar` |
| simple weather | 1.0.13-hotfix | `simple_weather-1.0.13-hotfix.jar` |
| SimpleBackups | 4.0.30 | `SimpleBackups-1.21-4.0.30.jar` |
| simplemagnets | 1.1.12c | `simplemagnets-1.1.12c-neoforge-mc1.21.jar` |
| simplylight | 1.5.3-b4 | `simplylight-1.5.3+1.21.1-b4.jar` |
| SmartBrainLib | 1.16.11 | `SmartBrainLib-neoforge-1.21.1-1.16.11.jar` |
| smithingtemplateviewer | 1.0.4 | `smithingtemplateviewer-1.0.4.jar` |
| sodium | 0.8.13 | `sodium-neoforge-0.8.13+mc1.21.1.jar` |
| sodium-extra | 0.9.4 | `sodium-extra-neoforge-0.9.4+mc1.21.1.jar` |
| solcarrot | 1.16.6 | `solcarrot-1.21.1-1.16.6.jar` |
| sophisticatedbackpacks | 3.26.3.2158 | `sophisticatedbackpacks-1.21.1-3.26.3.2158.jar` |
| sophisticatedbackpackscreateintegration | 0.2.0.168 | `sophisticatedbackpackscreateintegration-1.21.1-0.2.0.168.jar` |
| sophisticatedcore | 1.5.1.2341 | `sophisticatedcore-1.21.1-1.5.1.2341.jar` |
| sophisticatedstorage | 1.5.91.2127 | `sophisticatedstorage-1.21.1-1.5.91.2127.jar` |
| sophisticatedstoragecreateintegration | 0. | `sophisticatedstoragecreateintegration-1.21.1-0.1.21.209.jar` |
| sophisticatedstorageinmotion | 0.10.34.358 | `sophisticatedstorageinmotion-1.21.1-0.10.34.358.jar` |
| soulplied energistics | 1.0.3 | `soulplied_energistics-1.0.3.jar` |
| spark | 1.10.124 | `spark-1.10.124-neoforge.jar` |
| starbunclemania | 1.5.8 | `starbunclemania-1.21.1-1.5.8.jar` |
| stepcrafter | 0.1.9 | `stepcrafter-neoforge-1.21.1-0.1.9.jar` |
| stevescarts | 1.2.18 | `stevescarts-1.21-1.2.18-neoforge.jar` |
| storagedelight | 26.09.17 | `storagedelight-26.09.17-1.21-neoforge.jar` |
| Structory | 26.2_v1.3.7 | `Structory_26.2_v1.3.7.jar` |
| Structory Towers | 26.1_v1.0.16 | `Structory_Towers_26.1_v1.0.16.jar` |
| structurize | 1.0.833 | `structurize-1.0.833-1.21.1-snapshot.jar` |
| stylecolonies | 1.15.59 | `stylecolonies-1.15.59-1.21.1.jar` |
| Super Factory Manager (SFM) | 4.34.0 | `Super Factory Manager (SFM)-MC1.21.1-4.34.0.jar` |
| supermartijn642configlib | 1.1.8 | `supermartijn642configlib-1.1.8-neoforge-mc1.21.jar` |
| supermartijn642corelib | 1.1.24a | `supermartijn642corelib-1.1.24a-neoforge-mc1.21.jar` |
| supplementaries | 3.9.9 | `supplementaries-1.21.1-3.9.9-neoforge.jar` |
| sushigocrafting | 0.6.6 | `sushigocrafting-1.21-0.6.6.jar` |
| sussysniffers | 0.1.3 | `sussysniffers-1.21.1-0.1.3.jar` |
| t and t-fabric | 1.13.11 | `t_and_t-fabric-neoforge-1.13.11.jar` |
| tempad | 3.0.4 | `tempad-1.21.1-3.0.4-all.jar` |
| TerraBlender | 4.1.0.8 | `TerraBlender-neoforge-1.21.1-4.1.0.8.jar` |
| tesseract-api | 1.12.16 | `tesseract-api-neoforge-1.12.16-1.21.1.jar` |
| the bumblezone | 7.16.1 | `the_bumblezone-7.16.1+1.21.1-neoforge.jar` |
| The Undergarden | 0.9.6 | `The_Undergarden-1.21.1-0.9.6.jar` |
| theurgy | 1.76.1 | `theurgy-1.21.1-neoforge-1.76.1.jar` |
| theurgy kubejs | 1.6.0 | `theurgy_kubejs-1.21.1-neoforge-1.6.0.jar` |
| tiab | 6.5.4 | `tiab-neoforge-6.5.4.jar` |
| titanium | 4.0.50 | `titanium-1.21-4.0.50.jar` |
| ToastControl | 9.0.1 | `ToastControl-1.21.1-9.0.1.jar` |
| tombstone | 9.5.6 | `tombstone-neoforge-1.21.1-9.5.6.jar` |
| ToolBelt | 2.2.10 | `ToolBelt-1.21.1-2.2.10.jar` |
| torchmaster | 21.1.12 | `torchmaster-neoforge-1.21.1-21.1.12.jar` |
| towntalk | 1.2.0 | `towntalk-1.2.0.jar` |
| transfer labels | 0.1.9 | `transfer_labels-0.1.9.jar` |
| trashcans | 1.1.0 | `trashcans-1.1.0-neoforge-mc1.21.jar` |
| trashslot | 21.1.11 | `trashslot-neoforge-1.21.1-21.1.11.jar` |
| treetap | 0.4.6 | `treetap-1.21.1-0.4.6.jar` |
| trophymanager | 3.0.0 | `trophymanager-1.21.1-3.0.0.jar` |
| twilightforest | 4.8.3345 | `twilightforest-1.21.1-4.8.3345-universal.jar` |
| UndergroundVillages | 4.0.3 | `UndergroundVillages-neoforge-1.21.1-4.0.3.jar` |
| universalgrid | 0.3.2 | `universalgrid-neoforge-1.21.1-0.3.2.jar` |
| uranus | 2.4.1-bugfix | `uranus-2.4.1-bugfix-1.21.1-neoforge.jar` |
| utilitarian | 0.19.2 | `utilitarian-1.21.1-0.19.2.jar` |
| utilityvest | 1.3.0 | `utilityvest-1.3.0.jar` |
| valhelsia core | 1.1.5 | `valhelsia_core-neoforge-1.21.1-1.1.5.jar` |
| variantsandventures | 1.0.26 | `variantsandventures-neoforge-1.0.26+mc1.21.1.jar` |
| villagesandpillages | 1.0.3 | `villagesandpillages-neoforge-mc1.21.1-1.0.3.jar` |
| waystones | 21.1.45 | `waystones-neoforge-1.21.1-21.1.45.jar` |
| wirelesschargers | 1.0.9a | `wirelesschargers-1.0.9a-neoforge-mc1.21.jar` |
| WitherSkeletonTweaks | 10.1.1 | `WitherSkeletonTweaks-1.21.1-10.1.1.jar` |
| wits | 1.3.1 | `wits-neoforge-1.3.1.jar` |
| xnet | 7.0.7 | `xnet-1.21-7.0.7.jar` |
| xtonesreworked | 1.1.1 | `xtonesreworked-1.1.1-1.21.1.jar` |
| xycraft core | 0.7.53 | `xycraft_core-0.7.53-all.jar` |
| xycraft machines | 0.7.53 | `xycraft_machines-0.7.53.jar` |
| xycraft override | 0.7.53 | `xycraft_override-0.7.53.jar` |
| xycraft world | 0.7.53 | `xycraft_world-0.7.53.jar` |
| yeetusexperimentus | 87.0.0 | `yeetusexperimentus-neoforge-87.0.0.jar` |
| yet another config lib | 3-3.8.2 | `yet_another_config_lib_v3-3.8.2+1.21.1-neoforge.jar` |
| YungsApi | 5.1.9 | `YungsApi-1.21.1-NeoForge-5.1.9.jar` |
| YungsBetterDesertTemples | 4.1.5 | `YungsBetterDesertTemples-1.21.1-NeoForge-4.1.5.jar` |
| YungsBetterDungeons | 5.1.4 | `YungsBetterDungeons-1.21.1-NeoForge-5.1.4.jar` |
| YungsBetterEndIsland | 3.1.2 | `YungsBetterEndIsland-1.21.1-NeoForge-3.1.2.jar` |
| YungsBetterJungleTemples | 3.1.2 | `YungsBetterJungleTemples-1.21.1-NeoForge-3.1.2.jar` |
| YungsBetterMineshafts | 5.1.1 | `YungsBetterMineshafts-1.21.1-NeoForge-5.1.1.jar` |
| YungsBetterNetherFortresses | 3.1.5 | `YungsBetterNetherFortresses-1.21.1-NeoForge-3.1.5.jar` |
| YungsBetterOceanMonuments | 4.1.2 | `YungsBetterOceanMonuments-1.21.1-NeoForge-4.1.2.jar` |
| YungsBetterStrongholds | 5.1.3 | `YungsBetterStrongholds-1.21.1-NeoForge-5.1.3.jar` |
| YungsBetterWitchHuts | 4.1.1 | `YungsBetterWitchHuts-1.21.1-NeoForge-4.1.1.jar` |
| YungsExtras | 5.1.1 | `YungsExtras-1.21.1-NeoForge-5.1.1.jar` |
| ZeroCore2 | 2.4.21 | `ZeroCore2-1.21.1-2.4.21.jar` |
