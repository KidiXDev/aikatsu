# Aikatsu Design System

## Visual Identity: Warm Sakura & Soft Pastel Japanese Anime
Aikatsu embraces a warm, cozy Japanese anime aesthetic inspired by cherry blossoms (sakura) and Japanese craft. It eschews generic flat Material 3 templates and avoids excessive translucent glassmorphism in favor of **solid, tactile, beautifully rounded surfaces** with organic warmth, cozy cherry blossom accents, and smooth micro-animations.

## Color Tokens

### Dark Mode (Warm Obsidian & Sakura)
- **Background / Surface:** `#171113` (warm dark plum obsidian, not sterile gray)
- **Surface Low:** `#1f1619`
- **Surface Card / Container:** `#261c20`
- **Surface High / Elevated:** `#312429`
- **Surface Highest:** `#3d2d34`
- **Primary (Sakura Glow):** `#ff8db5` (warm cherry petal)
- **Primary Container:** `#4a182d`
- **On Primary Container:** `#ffd9e5`
- **Secondary (Blush Lilac):** `#f3a6cf`
- **Secondary Container:** `#531f3d`
- **Tertiary (Warm Lavender):** `#aba4ff`
- **Tertiary Container:** `#2e256b`
- **Outline / Border:** `#4c3b42` (subtle warm border)
- **On Surface:** `#fceef1` (soft cream white)
- **On Surface Variant:** `#c7b2b8` (warm muted rose)

### Light Mode (Warm Cream & Sakura Rose)
- **Background / Surface:** `#fff6f7` (warm cherry blossom cream)
- **Surface Card / Container:** `#faebed`
- **Surface High / Elevated:** `#f3dfe3`
- **Primary:** `#af2462`
- **Primary Container:** `#ffdbe6`
- **On Primary Container:** `#3e001d`
- **Secondary:** `#9a3c77`
- **Tertiary:** `#554eb7`
- **Outline / Border:** `#e3ccd2`
- **On Surface:** `#382b30`
- **On Surface Variant:** `#6b585f`

## Elevation & Depth
- Solid card containers with refined warm border outlines (1px `#4c3b42` in dark, `#e3ccd2` in light) and soft diffuse shadows.
- No heavy frosted glass or illegible translucent layers. Content is crisp, tactile, and easily readable.

## Typography
- **Font Family:** `GoogleSansFlex` (rounded axes, soft friendly letters, clear numerals).
- Title and display headings use generous line height and warm weights.
- Labels use medium weights with comfortable letter spacing.

## Geometry & Radii
- **Pill / Squircle:** 20px–24px for major cards, 16px for tiles, 999px for badges, chips, and navigation capsules.
- Consistent smooth continuous curves.

## Motion & Interaction
- **Duration:** 250ms–350ms with `Curves.easeOutCubic`.
- Bouncy scale feedback on card taps (0.98 scale press response).
- Smooth animated pill tab transitions in the custom navigation bar.
- Animated switcher for content state changes.
