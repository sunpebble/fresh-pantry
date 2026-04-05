# Fresh Pantry: Stitch Design Migration Spec

## Overview

Incremental refactor of the existing Flutter "食材管家" app to align with the Stitch "Verdant Kitchen" design system, introduce Riverpod state management, extract reusable components, and add missing search functionality. No data persistence in this iteration.

## Tech Stack

- Flutter 3.x + Dart
- Riverpod 2.x (`flutter_riverpod` + `riverpod_annotation` + `riverpod_generator`)
- Material 3
- No persistence layer (mock data via providers)

## Target Directory Structure

```
lib/
├── main.dart                       # App entry + ProviderScope
├── app.dart                        # MaterialApp config
├── theme/
│   ├── app_theme.dart              # ThemeData builder
│   ├── app_colors.dart             # Color tokens (aligned to Stitch)
│   └── app_typography.dart         # Font styles
├── models/
│   ├── ingredient.dart             # Ingredient model + FreshnessState enum
│   ├── shopping_item.dart          # ShoppingItem model
│   └── storage_area.dart           # StorageArea model + IconType enum
├── providers/
│   ├── inventory_provider.dart     # Inventory state (CRUD)
│   ├── shopping_provider.dart      # Shopping list state
│   ├── search_provider.dart        # Global search state
│   └── navigation_provider.dart    # Tab navigation state
├── screens/
│   ├── dashboard_screen.dart       # Home/Dashboard
│   ├── inventory_screen.dart       # Inventory list
│   ├── add_ingredient_screen.dart  # Add ingredient form
│   └── shopping_list_screen.dart   # Shopping list
├── widgets/
│   ├── common/
│   │   ├── top_app_bar.dart        # Shared top bar (avatar + title + search)
│   │   ├── bottom_nav_bar.dart     # Frosted glass bottom nav
│   │   ├── search_overlay.dart     # Search overlay with blur
│   │   ├── category_chips.dart     # Horizontal filter chips
│   │   └── status_badge.dart       # Freshness status pill
│   ├── dashboard/
│   │   ├── stat_card.dart          # Stat number card
│   │   ├── alert_card.dart         # Expiration alert item
│   │   ├── quick_action_card.dart  # Bento quick action
│   │   ├── storage_summary_card.dart # Storage area card
│   │   ├── recent_addition_item.dart # Recent addition list item
│   │   └── curators_tip_card.dart  # Curator's Tip quote card
│   ├── inventory/
│   │   └── ingredient_card.dart    # Ingredient list card
│   ├── shopping/
│   │   ├── shopping_item_tile.dart # Shopping item with checkbox
│   │   ├── quick_add_field.dart    # Quick add input + suggestions
│   │   └── smart_planner_card.dart # Smart Planner promo card
│   └── shared/
│       └── freshness_meter.dart    # Freshness progress bar
└── data/
    └── mock_data.dart              # Static mock data
```

## Design System: "Verdant Kitchen"

### Color Tokens

| Token | Value | Usage |
|---|---|---|
| primary | `#0F5238` | Main actions, selected states |
| onPrimary | `#FFFFFF` | Text on primary |
| primaryContainer | `#C2F0D8` | Light green containers |
| secondary | `#9B4500` | Secondary actions (warm orange) |
| onSecondary | `#FFFFFF` | Text on secondary |
| secondaryContainer | `#FFDBC8` | Light orange containers |
| tertiary | `#5B4400` | Accent (amber) |
| tertiaryContainer | `#FFE08C` | Light amber containers |
| error | `#BA1A1A` | Expired/error states |
| errorContainer | `#FFDAD6` | Error backgrounds |
| surface | `#FFF9F5` | Main background (warm white) |
| onSurface | `#1C1C1A` | Primary text (NO pure black) |
| surfaceContainer | `#F4F1EE` | Card backgrounds |
| surfaceContainerHigh | `#EBE8E5` | Secondary containers |
| surfaceContainerLow | `#F9F6F3` | Floating layers |
| outline | `#7D7974` | Helper lines/icons |
| outlineVariant | `#CEC9C3` | Subtle borders |

### Typography

| Token | Font | Size | Weight | Usage |
|---|---|---|---|---|
| displayLarge | Plus Jakarta Sans | 32 | 800 | Page titles |
| headlineMedium | Plus Jakarta Sans | 24 | 700 | Section headers |
| titleLarge | Plus Jakarta Sans | 20 | 600 | Card titles |
| titleMedium | Manrope | 16 | 600 | Subtitles/labels |
| bodyLarge | Manrope | 16 | 400 | Body text |
| bodyMedium | Manrope | 14 | 400 | Secondary body |
| labelLarge | Manrope | 14 | 700 | Buttons/labels (uppercase) |
| labelSmall | Manrope | 11 | 600 | Badges/captions |

### Shape System ("No-Line" Rule)

- Cards: `BorderRadius.circular(24)` (Stitch `rounded-3xl`)
- Sub-cards/inputs: `BorderRadius.circular(16)` (Stitch `rounded-2xl`)
- Pills/chips/badges: `StadiumBorder` (Stitch `rounded-full`)
- Images/thumbnails: `BorderRadius.circular(12)` (Stitch `rounded-xl`)
- Minimum corner radius: 8px — NO 90-degree corners
- NO 1px solid borders — use background color hierarchy to define boundaries
- List items separated by 0.75rem vertical whitespace, NOT dividers

### Frosted Glass Bottom Navigation

- Background: `surface.withOpacity(0.8)`
- Blur: `BackdropFilter` + `ImageFilter.blur(sigmaX: 20, sigmaY: 20)`
- No border, no top divider line

## Page Specifications

### Dashboard (首页/仪表盘)

Reference: `12-home-dashboard-optimized.png`

Sections (top to bottom):
1. **Greeting** — "Morning, Chef." + subtitle with inventory stats
2. **Stat Cards** — 2-column row: total items (24) + expiring soon (3), large number + uppercase label, `surfaceContainer` background
3. **Urgent Attention** — Expiring items list (thumbnail + name + expiry badge + action button), "Recipe recommendations" button at bottom
4. **Quick Actions** — 2-column grid: "Add New" (`primaryContainer`) + "Groceries" (`secondaryContainer`)
5. **Storage Summary** — 3 storage area cards (Fridge/Pantry/Freezer) with icon + name + count + capacity progress bar
6. **Recent Additions** — Ingredient list items (thumbnail + name + source/time + freshness bar)
7. **Curator's Tip** — Quote-style card with green left border

### Inventory (库存列表)

Reference: `11-inventory-list.png`

- **Search bar** (NEW) — inline search field at top, `rounded-xl`
- **Category Chips** — horizontal scroll pills (All Items / Vegetables / Proteins / ...), selected state uses primary fill
- **Ingredient Cards** — each: left thumbnail (`rounded-xl`), name, quantity/spec, expiry badge (`status_badge`), freshness bar
- **Expired item degradation** — image grayscale + reduced overall opacity

### Shopping List (购物清单)

Reference: `04-shopping-list.png`

- **Quick Add Bar** — top input field "Add an ingredient to your list..."
- **Quick Suggestion Chips** — horizontal pills (+ Milk / + Eggs / + Sourdough), tap to quick-add
- **Grouped List** — items grouped by category (Fresh Produce / Dairy & Pantry), each group shows header + count
- **Shopping Items** — circular checkbox + name + detail + right-side thumbnail; checked state: text line-through + image grayscale + reduced opacity
- **Smart Planner Card** (bottom) — `primaryContainer` background, recipe completion prompt

### Add Ingredient (添加食材)

Reference: `05-add-ingredient.png`

- **Header** — "Curate Your Pantry" + subtitle
- **Barcode Button** — full-width button, QR icon + "Quick Scan Barcode"
- **Form Fields** — underline-style input (bottom border only, NOT boxed), focus state changes border to primary
- Fields: Ingredient Name, Category (dropdown), Quantity + Units
- **Expiration Date** — date picker + gradient freshness meter preview
- **Save Button** — gradient green (primary), `rounded-full`, full-width
- **Discard Button** — text button, centered

### Search Overlay (搜索覆盖层 — NEW)

Reference: `08-home-search-active.png`

- Triggered by tapping search icon in TopAppBar
- Background content: `blur(2px) + opacity(0.6)`
- Inline search field replaces TopAppBar
- Shows recent search history
- Real-time filtering of results

## State Management (Riverpod)

### Providers

```
inventoryProvider (NotifierProvider<InventoryNotifier, List<Ingredient>>)
├── Initial data: MockData.inventoryItems
├── Methods: add / remove / update / getByCategory
└── Derived: expiringItemsProvider / recentAdditionsProvider / statCountsProvider

shoppingProvider (NotifierProvider<ShoppingNotifier, List<ShoppingItem>>)
├── Initial data: MockData.shoppingItems
├── Methods: add / remove / toggleCheck / addFromSuggestion
└── Derived: groupedByCategory / checkedCount / uncheckedCount

searchProvider (StateProvider<String>)
├── Current search keyword
└── Linked: filteredInventoryProvider / filteredShoppingProvider

navigationProvider (StateProvider<int>)
└── Currently selected tab index (0-3)

searchActiveProvider (StateProvider<bool>)
└── Whether search overlay is active
```

### Data Flow

```
MockData (data/mock_data.dart)
    ↓ injected at init
Notifier (providers/)
    ↓ state change notifications
ConsumerWidget / ConsumerStatefulWidget (screens/ & widgets/)
    ↓ ref.watch / ref.read
UI render
```

### New Dependencies

| Package | Purpose |
|---|---|
| `flutter_riverpod` | State management core |
| `riverpod_annotation` | `@riverpod` annotation support |
| `riverpod_generator` | Code generation |
| `build_runner` | Code gen driver |
| `intl` | Date formatting |

## Out of Scope

- Data persistence (SQLite/Hive/SharedPreferences)
- Router library (go_router) — keep IndexedStack navigation
- Internationalization — keep Chinese hardcoded strings
- Unit/widget tests — add in future iteration
- Backend/API integration
- Push notifications

## Implementation Strategy

Incremental refactor (Approach A): modify files one at a time, keeping the app runnable at every step.

Order:
1. Add dependencies (pubspec.yaml)
2. Refactor theme (split + align to Stitch tokens)
3. Split models into separate files
4. Create providers (Riverpod)
5. Extract common widgets (TopAppBar, BottomNav, SearchOverlay, etc.)
6. Refactor Dashboard screen
7. Refactor Inventory screen (+ add search)
8. Refactor Shopping List screen
9. Refactor Add Ingredient screen
10. Implement Search Overlay
11. Final polish and verify
