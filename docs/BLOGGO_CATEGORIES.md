# Bloggo Universal Category System

Bloggo uses 26 universal category groups to classify places. These replace provider-specific strings (e.g. Apple's `MKPointOfInterestCategory` raw values) so that categories are consistent across iOS, the web, and the backend.

---

## All Categories

| Raw Value | Display Name | SF Symbol | How It's Assigned |
|---|---|---|---|
| `food_and_drink` | Food & Drink | `fork.knife` | Apple: Restaurant, Brewery, Distillery / Name: pub, tavern, bistro, taproom, cidery |
| `coffee_and_casual` | Coffee & Casual | `cup.and.saucer.fill` | Apple: Cafe / Name: coffee, café, espresso, roaster, teahouse, boba, matcha |
| `desserts_and_sweets` | Desserts & Sweets | `birthday.cake.fill` | Apple: Bakery / Name: bakery, dessert, gelato, patisserie, donut, macaron, creamery |
| `winery` | Wineries | `wineglass.fill` | Apple: Winery / Name: winery, vineyard, wine, chateau, cellar, domaine, estate |
| `nightlife` | Nightlife | `moon.stars.fill` | Apple: Nightlife / Name: bar, nightclub, club, lounge, disco, speakeasy, cocktail |
| `lodging` | Lodging | `bed.double.fill` | Apple: Hotel / Name: hostel, inn, resort, villa, chalet, ryokan, motel, guesthouse |
| `camping_rv` | Camping & RV | `tent.fill` | Apple: Campground / Name: campground, campsite, rv, caravan, glamping |
| `transportation` | Transportation | `car.fill` | Apple: Airport, Public Transport, Rest Stop |
| `parking` | Parking | `parkingsign` | Apple: Parking / Name: parking, garage, carpark |
| `automotive` | Automotive | `fuelpump.fill` | _(legacy — superseded by Vehicle Services)_ |
| `vehicle_services` | Vehicle Services | `car.2.fill` | Apple: Gas Station, Car Wash, EV Charger, Car Rental / Name: petrol, fuel, carwash |
| `shopping` | Shopping | `bag.fill` | Apple: Food Market, Store / Name: market, bazaar, souk, mall, outlet, flea |
| `retail_specialty` | Retail & Specialty | `tag.fill` | _(reserved)_ |
| `entertainment` | Entertainment | `theatermasks.fill` | Apple: Movie Theater, Theater, Casino, Fairground, Convention Center / Name: amphitheater, concert, carnival |
| `sports_and_fitness` | Sports & Fitness | `dumbbell.fill` | Apple: Fitness Center, Stadium |
| `golf` | Golf | `figure.golf` | Apple: Golf / Name: golf, links, clubhouse |
| `beach` | Beaches | `beach.umbrella.fill` | Apple: Beach / Name: beach, seaside, beachfront, strand, sandbar |
| `nature` | Nature | `leaf.fill` | Apple: Park, National Park / Name: lake, river, waterfall, mountain, forest, canyon, glacier, cave, island, desert, and many more landforms & ecosystems |
| `outdoor_activities` | Outdoor Activities | `figure.hiking` | Apple: Marina / Name: trail, summit, ski, surf, kayak, rafting, climbing, fishing, horseback, cycling, camping |
| `viewpoints` | Viewpoints | `binoculars.fill` | _(name only)_ Name: overlook, viewpoint, vista, lookout, panorama, belvedere |
| `hot_springs` | Hot Springs | `flame.fill` | _(name only)_ Name: onsen, hotspring, geothermal pool, mineral spring, thermal bath |
| `arts_and_culture` | Arts & Culture | `building.columns.fill` | Apple: Museum, Religious Site / Name: ruins, historic, heritage, memorial, temple, cathedral, mosque, abbey, cemetery, medieval, mural |
| `attractions` | Attractions | `star.fill` | Apple: Amusement Park, Zoo, Aquarium / Name: castle, lighthouse, bridge, fort, plaza, harbor, statue, landmark |
| `health` | Health | `cross.fill` | Apple: Hospital, Pharmacy |
| `personal_care` | Personal Care | `scissors` | Apple: Spa, Laundry / Name: hammam, sauna, bathhouse |
| `education` | Education | `graduationcap.fill` | Apple: Library, School, University |
| `government` | Government | `building.2.fill` | Apple: Police, Post Office, Fire Station |
| `financial` | Financial | `banknote.fill` | Apple: Bank, ATM |
| `other` | Other | `mappin` | Fallback — never shown in UI |

---

## How It Works

### 1. Apple POI Category → Bloggo (primary, reliable)

When a user taps a recognized POI on the map in `EditPlaceStopNameSheet`, Apple returns an `MKPointOfInterestCategory`. This is immediately converted to a Bloggo universal value before saving — the raw Apple string never reaches the backend.

```
Apple: "MKPOICategoryRestaurant"  →  Bloggo: "food_and_drink"
Apple: "MKPOICategoryBeach"       →  Bloggo: "beach"
Apple: "MKPOICategoryWinery"      →  Bloggo: "winery"
```

### 2. Name Inference (fallback for unrecognized places)

When Apple returns no category (e.g. lakes, trails, viewpoints, hot springs), Bloggo infers a group from the place name using whole-word keyword matching. The name is tokenized on non-alphanumeric characters and naive plural stemming is applied (`"Falls"` → also checks `"Fall"`).

**Priority order** (most specific first — a match stops further checks):

1. Viewpoints (`overlook`, `vista`, `lookout`…)
2. Beaches (`beach`, `seaside`, `strand`…)
3. Hot Springs (`onsen`, `hotspring`, `thermal bath`…)
4. Wineries (`vineyard`, `wine`, `chateau`…)
5. Nightlife (`bar`, `club`, `lounge`…)
6. Outdoor Activities (`trail`, `ski`, `kayak`, `summit`…)
7. Nature (`lake`, `river`, `mountain`, `forest`, `canyon`…)
8. Arts & Culture (`ruins`, `cathedral`, `historic`, `memorial`…)
9. Attractions (`castle`, `lighthouse`, `bridge`, `harbor`…)
10. Coffee & Casual (`coffee`, `café`, `espresso`…)
11. Desserts & Sweets (`bakery`, `gelato`, `patisserie`, `donut`…)
12. Golf (`golf`, `links`, `clubhouse`)
13. Food & Drink (`pub`, `tavern`, `distillery`…)
14. Shopping (`market`, `bazaar`, `mall`…)
15. Personal Care (`spa`, `hammam`, `sauna`…)
16. Camping & RV (`campground`, `campsite`, `rv`, `caravan`…)
17. Lodging (`hostel`, `inn`, `resort`…)
18. Parking (`parking`, `garage`, `carpark`)
19. Vehicle Services (`petrol`, `fuel`, `carwash`…)
20. Entertainment (`amphitheater`, `concert`, `carnival`…)

Examples:
- `"Lake Tahoe"` → **Nature** (word `"lake"`)
- `"Angel Falls Trail"` → **Outdoor Activities** (word `"trail"` checked before nature)
- `"Grand Canyon Overlook"` → **Viewpoints** (word `"overlook"` checked first)
- `"Glenfiddich Distillery"` → **Food & Drink** (word `"distillery"`)
- `"Blue Lagoon Geothermal Pool"` → **Hot Springs**
- `"Bondi Beach"` → **Beaches**
- `"Château Margaux"` → **Wineries**

### 3. Unknown / Unmapped → `other` → No badge shown

Any stored value that doesn't match a known group resolves to `.other`. The UI suppresses `.other` — no badge in `PlaceStopRowView`, excluded from filter chips in `PlacesVisitedView` and `MapDayView`. Old data (saved before this system) silently shows no category.

---

## Legacy Data Handling

`BloggoCategoryMapper.displayGroup(forStoredValue:)` handles both:
- **New values** — Bloggo raw strings like `"food_and_drink"` (direct enum lookup)
- **Old values** — Raw Apple strings like `"MKPOICategoryRestaurant"` still in the DB (fallback lookup in `appleToGroup`)

This means no migration is needed — old data degrades gracefully to no badge.

---

## Files

| File | Role |
|---|---|
| `fastblog/Models/PlaceCategoryMapper.swift` | Source of truth — `BloggoCategoryGroup` enum + `BloggoCategoryMapper` |
| `fastblog/Views/EditPlaceStopNameSheet.swift` | Single conversion point: Apple → Bloggo before save, with name inference fallback |
| `fastblog/Views/PlaceStopRowView.swift` | Displays group name + icon badge on each place row |
| `fastblog/Views/PlacesVisitedView.swift` | Filter chips by group in the Places Visited list + map |
| `fastblog/Views/MapDayView.swift` | Filter chips by group in the day map view |

---

## Adding a New Category

**New Bloggo group:**
1. Add a case to `BloggoCategoryGroup` with a unique `rawValue`
2. Add its `displayName` and `icon` (SF Symbol name)
3. Map any Apple categories to it in `appleToGroup`
4. Add a token set and check it in `inferGroup` at the right priority position

**New Apple mapping only:**
Add an entry to `appleToGroup` in `BloggoCategoryMapper`. No other changes needed.

**New name inference keywords only:**
Add tokens to the relevant existing token set in `BloggoCategoryMapper`.
