# Nicer Tooltip

Gives World of Warcraft tooltips a nicer look:

- an ornate gold frame instead of the default border,
- a themed, textured background,
- a gold separator under the name line,
- the Alliance or Horde emblem in front of a player's faction, and in front of "PvP" on faction NPCs,
- the health bar set in a matching slot under the tooltip.

## Options

In the game's options (Options > AddOns > Nicer Tooltip), or with `/nicertooltip` (`/ntt`):

- Background: opacity, brightness, show/hide the corner art, art size
- Show the unit's level after its name, e.g. Name (60) (off by default)
- Minimum tooltip width
- Follow the cursor (off by default)
- In combat: hide the tooltip, show it at its original position, or keep it on the cursor

## Themes

| Tooltip | Background |
|---|---|
| Alliance player | `alliance` |
| Horde player | `horde` |
| Unaligned player and everything else | `neutral` |
| Friendly NPC | `creature_ally` |
| Neutral NPC | `creature_neutral` |
| Hostile NPC | `creature_enemy` |
| Buffs / debuffs | `buff` / `debuff` |
| Spells and abilities | `spell` |
| Items | `item` |
| Herbs you can gather | `herb` |
| Mineral veins you can mine | `mineral` |
| Dead NPC or player (ghosts too) | `dead` |

## Development

The source artwork lives in `src/` (not packaged). The in-game textures in
`media/` and `Media.lua` are generated from it:

```sh
cd tools
npm install
npm run build
```
