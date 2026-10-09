# Palette Clevane (clair et sombre)

Source de vérité : `Clevane/Sources/ClevaneUI/Theme.swift`, enum `Palette` (8 octobre 2026).
Monochrome gris neutre, proche des couleurs système d'Apple ; un seul accent : le rouge, réservé aux actions destructives.

## Jetons par rôle

| Jeton | Rôle | Clair | Sombre |
|---|---|---|---|
| `window` | Fond de fenêtre / page | `#F9F9F8` | `#1C1C1E` |
| `panel` | Barre latérale, panneaux, fonds de groupes | `#ECECEE` | `#2C2C2F` |
| `sheet` | Modales, panneau de détail, cartes surélevées | `#FFFFFF` | `#2A2A2D` |
| `field` | Fond des champs de saisie | `#FFFFFF` | `#1C1C1E` |
| `text` | Texte principal, titres | `#1D1D1F` | `#F5F5F7` |
| `text-2` | Texte secondaire, icônes | `#3A3A3C` | `#D1D1D6` |
| `muted` | Texte d'aide, libellés en petites capitales | `#636366` | `#A1A1A6` |
| `quiet` | Texte très discret (raccourcis, mentions) | `#6E6E73` | `#98989D` |
| `control-line` | Bordure des champs et contrôles (contraste 3:1) | `#8E8E93` | `#8E8E93` |
| `ink` | Fond du bouton principal (inversé selon le mode) | `#1D1D1F` | `#F5F5F7` |
| `on-ink` | Texte sur le bouton principal | `#FFFFFF` | `#1D1D1F` |
| `danger` | Suppression, erreurs | `#C41A1A` | `#FF6961` |
| `line` | Séparateurs fins | noir 8 % | blanc 8 % |
| `line-2` | Séparateurs marqués, bordures de cartes | noir 13 % | blanc 13 % |
| `select` | Ligne sélectionnée, survol | noir 6,5 % | blanc 6,5 % |
| `tile` | Tuile d'icône (dégradé haut → bas) | `#48484A` → `#2C2C2E` | `#6E6E73` → `#3A3A3C` |
| `soft-tile` | Tuile d'icône douce (dégradé haut → bas) | `#F4F4F6` → `#E3E3E7` | `#3A3A3C` → `#2C2C2E` |

Contrastes vérifiés en clair : texte discret 4,8:1, bordures de contrôle 3:1 (WCAG AA).

## Règles d'usage qui font le rendu

- Bouton principal **inversé** : `ink` / `on-ink` (noir en clair, blanc en sombre). Boutons secondaires : fond `sheet`, bordure `line-2`, forme pilule.
- Aucune couleur vive hors `danger` : la hiérarchie vient des gris, pas de la couleur.
- Champs : fond `field`, bordure 1 px `control-line`, bordure `text` au focus, rayon 10 px (pilule pour la recherche).
- Cartes : fond `sheet`, bordure 0,5 px `line-2`, ombres très légères (1 à 2 px).
- Typographie : serif pour les titres (New York sur Apple, sinon un serif éditorial), sans-serif système pour l'interface ; libellés en petites capitales 10 px, graisse 600, interlettrage 1,4 px, couleur `muted`.

## CSS prêt à coller

Mode clair par défaut, sombre automatique selon le système, et choix manuel par `data-theme="light"` ou `data-theme="dark"` sur `<html>`.

```css
:root {
  --window: #F9F9F8;
  --panel: #ECECEE;
  --sheet: #FFFFFF;
  --field: #FFFFFF;
  --text: #1D1D1F;
  --text-2: #3A3A3C;
  --muted: #636366;
  --quiet: #6E6E73;
  --control-line: #8E8E93;
  --ink: #1D1D1F;
  --on-ink: #FFFFFF;
  --danger: #C41A1A;
  --line: rgb(0 0 0 / 0.08);
  --line-2: rgb(0 0 0 / 0.13);
  --select: rgb(0 0 0 / 0.065);
  --tile: linear-gradient(to bottom, #48484A, #2C2C2E);
  --soft-tile: linear-gradient(to bottom, #F4F4F6, #E3E3E7);
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --window: #1C1C1E;
    --panel: #2C2C2F;
    --sheet: #2A2A2D;
    --field: #1C1C1E;
    --text: #F5F5F7;
    --text-2: #D1D1D6;
    --muted: #A1A1A6;
    --quiet: #98989D;
    --ink: #F5F5F7;
    --on-ink: #1D1D1F;
    --danger: #FF6961;
    --line: rgb(255 255 255 / 0.08);
    --line-2: rgb(255 255 255 / 0.13);
    --select: rgb(255 255 255 / 0.065);
    --tile: linear-gradient(to bottom, #6E6E73, #3A3A3C);
    --soft-tile: linear-gradient(to bottom, #3A3A3C, #2C2C2E);
  }
}

:root[data-theme="dark"] {
  --window: #1C1C1E;
  --panel: #2C2C2F;
  --sheet: #2A2A2D;
  --field: #1C1C1E;
  --text: #F5F5F7;
  --text-2: #D1D1D6;
  --muted: #A1A1A6;
  --quiet: #98989D;
  --ink: #F5F5F7;
  --on-ink: #1D1D1F;
  --danger: #FF6961;
  --line: rgb(255 255 255 / 0.08);
  --line-2: rgb(255 255 255 / 0.13);
  --select: rgb(255 255 255 / 0.065);
  --tile: linear-gradient(to bottom, #6E6E73, #3A3A3C);
  --soft-tile: linear-gradient(to bottom, #3A3A3C, #2C2C2E);
}
```
