# UI Skill: Gradients

## Standard gradients

### Photo text scrim
```swift
LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .bottom, endPoint: .center)
```

### Cover page fallback (no photo)
```swift
LinearGradient(colors: [Color(hex: "1a1a2e"), Color(hex: "2d3561")], startPoint: .top, endPoint: .bottom)
```

---

## Regional trip themes (TripsView)
Applied to trip card background based on detected location. Add new themes to the existing array in `TripsView.swift` — don't inline them in new views.

| Theme | Start RGB | End RGB |
|-------|-----------|---------|
| Iceland | `(0.1, 0.15, 0.35)` | `(0.08, 0.2, 0.3)` |
| Morocco | `(0.4, 0.2, 0.15)` | `(0.35, 0.18, 0.12)` |
| Tokyo | `(0.4, 0.15, 0.25)` | `(0.25, 0.1, 0.2)` |
| Paris | `(0.25, 0.22, 0.35)` | `(0.2, 0.18, 0.28)` |
| California | `(0.95, 0.7, 0.4)` | `(0.4, 0.5, 0.7)` |
| Alps | `(0.6, 0.75, 0.9)` | `(0.25, 0.4, 0.5)` |
| Barcelona | `(0.9, 0.4, 0.2)` | `(0.3, 0.2, 0.35)` |
| London | `(0.2, 0.22, 0.3)` | `(0.15, 0.15, 0.22)` |

---

## Mock photo placeholders (MockPhotoView — 10 variants)
Pick by `index % 10` when no real photo is available.

| # | Name | Start RGB | End RGB | Direction |
|---|------|-----------|---------|-----------|
| 0 | Sunset | `(0.95, 0.6, 0.4)` | `(0.6, 0.35, 0.6)` | top→bottom |
| 1 | Ocean | `(0.2, 0.5, 0.75)` | `(0.1, 0.3, 0.5)` | topLeading→bottomTrailing |
| 2 | Forest | `(0.2, 0.55, 0.35)` | `(0.1, 0.35, 0.2)` | top→bottom |
| 3 | Mountain | `(0.4, 0.5, 0.65)` | `(0.25, 0.35, 0.5)` | topLeading→bottom |
| 4 | Golden Hour | `(0.9, 0.7, 0.4)` | `(0.7, 0.45, 0.35)` | top→bottomTrailing |
| 5 | Aurora | `(0.1, 0.4, 0.35)` | `(0.15, 0.25, 0.4)` | topLeading→bottomTrailing |
| 6 | Beach | `(0.85, 0.75, 0.6)` | `(0.6, 0.5, 0.45)` | top→bottom |
| 7 | City/Dusk | `(0.35, 0.3, 0.45)` | `(0.2, 0.18, 0.28)` | top→bottom |
| 8 | Meadow | `(0.45, 0.65, 0.4)` | `(0.3, 0.5, 0.35)` | topLeading→bottom |
| 9 | Lake | `(0.35, 0.55, 0.7)` | `(0.2, 0.4, 0.55)` | top→bottom |

---

## Nearby Share neon glow (TripNearbyShareViews)
6 rotating colors for card glow animation:

| # | RGB |
|---|-----|
| 0 | `(0.49, 0.23, 0.99)` purple |
| 1 | `(0.22, 0.56, 1.0)` bright blue |
| 2 | `(0.28, 0.93, 0.85)` cyan |
| 3 | `(1.0, 0.36, 0.58)` pink |
| 4 | `(0.62, 0.38, 1.0)` violet |
| 5 | `(0.35, 0.82, 1.0)` light blue |
