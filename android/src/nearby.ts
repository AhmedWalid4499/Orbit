// Places and weather for the assistant on Android, standing in for the Mac/iPhone's Apple Maps lookups
// (NearbyFinder, PlaceLookup, WeatherStore.forecastText): OpenStreetMap (Overpass for what's around, Photon for
// finding a named place) and Open-Meteo. All free, no keys. Where you are comes from the phone's location when
// Joshu may use it, otherwise from your weather city in Settings.
import { store } from '@/lib/store'
import { describe as describeWeather } from '@/lib/weather'

export interface Spot { lat: number; lon: number }
export interface Located extends Spot { label: string; exact: boolean }
export interface Found extends Spot { name: string; address: string; category: string; url: string; osmKey: string; osmValue: string }

const tz = () => Intl.DateTimeFormat().resolvedOptions().timeZone
export const homeCity = (): string => (store.setting<string>('weatherCity') ?? '').trim() || (tz().split('/').pop() ?? '').replace(/_/g, ' ')

async function json(url: string, init?: RequestInit): Promise<any> {
  const r = await fetch(url, init)
  if (!r.ok) throw new Error(`HTTP ${r.status}`)
  return r.json()
}

/** The phone's location when it's allowed (a few seconds at most), else null. */
function gps(): Promise<Spot | null> {
  if (!('geolocation' in navigator)) return Promise.resolve(null)
  return new Promise((resolve) => {
    const t = setTimeout(() => resolve(null), 7000)
    navigator.geolocation.getCurrentPosition(
      (p) => { clearTimeout(t); resolve({ lat: p.coords.latitude, lon: p.coords.longitude }) },
      () => { clearTimeout(t); resolve(null) },
      { enableHighAccuracy: false, maximumAge: 10 * 60_000, timeout: 6500 },
    )
  })
}

/** A city's centre (Open-Meteo geocoding). */
export async function geocodeCity(name: string): Promise<(Spot & { name: string }) | null> {
  try {
    const p = (await json(`https://geocoding-api.open-meteo.com/v1/search?count=1&name=${encodeURIComponent(name)}`))?.results?.[0]
    return p ? { lat: p.latitude, lon: p.longitude, name: [p.name, p.country].filter(Boolean).join(', ') } : null
  } catch { return null }
}

/** Where the user is: the phone's location, or their weather city. */
export async function locate(): Promise<Located | null> {
  const here = await gps()
  if (here) return { ...here, label: 'where they are now', exact: true }
  const city = homeCity()
  const c = city ? await geocodeCity(city) : null
  return c ? { lat: c.lat, lon: c.lon, label: c.name, exact: false } : null
}

// MARK: Places

const URL_RE = /https?:\/\/\S+/i
export const firstURL = (s: string): string | null => s.match(URL_RE)?.[0] ?? null

/** Coordinates (and a name, when there is one) written in a Google/Apple Maps or OpenStreetMap link. */
function fromLink(link: string): (Spot & { name: string }) | null {
  let u: URL
  try { u = new URL(link) } catch { return null }
  const s = decodeURIComponent(u.href)
  const name = (s.match(/\/place\/([^/@]+)/)?.[1] ?? u.searchParams.get('q') ?? '').replace(/\+/g, ' ')
  const pairs = [/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/, /@(-?\d+\.\d+),(-?\d+\.\d+)/, /[?&](?:q|ll|query|destination|mlat)=(-?\d+\.\d+),\s*(-?\d+\.\d+)/]
  for (const re of pairs) { const m = s.match(re); if (m) return { lat: +m[1], lon: +m[2], name: /^-?\d/.test(name) ? '' : name } }
  const mlat = u.searchParams.get('mlat'), mlon = u.searchParams.get('mlon')
  if (mlat && mlon) return { lat: +mlat, lon: +mlon, name: '' }
  return name && !/^-?\d/.test(name) ? { lat: NaN, lon: NaN, name } : null
}

const CATEGORY_WORDS: [string, string[]][] = [
  ['cafe', ['cafe', 'café', 'coffee', 'roaster', 'tea house', 'كافيه', 'قهوة']],
  ['bar', [' bar', 'pub', 'lounge', 'rooftop']],
  ['food', ['restaurant', 'kitchen', 'grill', 'pizza', 'burger', 'sushi', 'bistro', 'diner', 'koshary', 'شاورما', 'مطعم']],
  ['museum', ['museum', 'gallery', 'متحف']],
  ['shop', ['mall', 'store', 'shop', 'market', 'boutique', 'outlet']],
  ['park', ['park', 'garden', 'beach', 'حديقة']],
  ['hotel', ['hotel', 'resort', 'inn', 'hostel', 'فندق']],
  ['attraction', ['temple', 'pyramid', 'castle', 'citadel', 'tower', 'palace', 'cinema', 'theatre', 'theater', 'zoo']],
]

/** Same buckets as the Mac's PlaceCategory (food, cafe, bar, shop, museum, park, attraction, hotel, other). */
export function placeCategory(osmKey: string, osmValue: string, name: string): string {
  const v = osmValue
  if (['restaurant', 'fast_food', 'food_court', 'bakery', 'ice_cream'].includes(v)) return 'food'
  if (v === 'cafe') return 'cafe'
  if (['bar', 'pub', 'nightclub', 'biergarten'].includes(v)) return 'bar'
  if (osmKey === 'shop') return 'shop'
  if (['museum', 'gallery', 'arts_centre'].includes(v)) return 'museum'
  if (['park', 'garden', 'beach', 'nature_reserve'].includes(v)) return 'park'
  if (['hotel', 'guest_house', 'hostel', 'motel', 'resort'].includes(v)) return 'hotel'
  if (['attraction', 'theme_park', 'zoo', 'aquarium', 'cinema', 'theatre', 'stadium', 'viewpoint', 'castle', 'monument'].includes(v) || osmKey === 'historic') return 'attraction'
  const n = ` ${name.toLowerCase()}`
  return CATEGORY_WORDS.find(([, words]) => words.some((w) => n.includes(w)))?.[0] ?? 'other'
}

export const mapsLink = (p: Spot, name = ''): string =>
  `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(name ? `${name} ${p.lat},${p.lon}` : `${p.lat},${p.lon}`)}`

function photonAddress(pr: any): string {
  const street = [pr.housenumber, pr.street].filter(Boolean).join(' ')
  return [street, pr.district ?? pr.locality, pr.city ?? pr.town ?? pr.village, pr.city ? '' : pr.state].filter(Boolean).join(', ')
}

/** Finds a place by name, address or maps link, nearest to `near` when given (PlaceLookup.resolve). */
export async function findPlace(text: string, near?: Spot | null): Promise<Found | null> {
  const t = text.trim()
  if (!t) return null
  const link = firstURL(t)
  if (link) {
    const l = fromLink(link)
    if (l && !isNaN(l.lat)) {
      // Name the pin from the map when the link doesn't say.
      let name = l.name, address = '', key = '', value = ''
      try {
        const r = await json(`https://photon.komoot.io/reverse?lat=${l.lat}&lon=${l.lon}&limit=1`)
        const pr = r?.features?.[0]?.properties ?? {}
        name ||= pr.name ?? ''; address = photonAddress(pr); key = pr.osm_key ?? ''; value = pr.osm_value ?? ''
      } catch { /* the pin is enough */ }
      return { lat: l.lat, lon: l.lon, name: name || 'Pinned place', address, category: placeCategory(key, value, name), url: link, osmKey: key, osmValue: value }
    }
    if (l?.name) return findPlace(l.name, near)
    return null
  }
  try {
    const bias = near ? `&lat=${near.lat}&lon=${near.lon}` : ''
    const r = await json(`https://photon.komoot.io/api/?q=${encodeURIComponent(t)}&limit=5${bias}`)
    const f = (r?.features ?? [])[0]
    if (!f) return null
    const pr = f.properties ?? {}
    const [lon, lat] = f.geometry?.coordinates ?? [NaN, NaN]
    const name = pr.name ?? t
    return { lat, lon, name, address: photonAddress(pr), category: placeCategory(pr.osm_key ?? '', pr.osm_value ?? '', name),
      url: mapsLink({ lat, lon }, name), osmKey: pr.osm_key ?? '', osmValue: pr.osm_value ?? '' }
  } catch { return null }
}

// MARK: What's around

/** Everyday searches as OpenStreetMap tags. */
const TAGS: [RegExp, string[]][] = [
  [/hungry|food|eat|restaurant|lunch|dinner|breakfast|meal|koshary|pizza|burger|sushi|shawarma|مطعم|اكل/i, ['amenity~"^(restaurant|fast_food|food_court)$"']],
  [/coffee|cafe|café|tea|كافيه|قهوة/i, ['amenity="cafe"']],
  [/\bbar\b|pub|drink|beer|cocktail|nightlife/i, ['amenity~"^(bar|pub|nightclub)$"']],
  [/gym|fitness|workout/i, ['leisure="fitness_centre"', 'leisure="sports_centre"']],
  [/pharmac|drugstore|صيدلي/i, ['amenity="pharmacy"']],
  [/\batm\b|cash machine/i, ['amenity="atm"']],
  [/\bbank\b/i, ['amenity="bank"']],
  [/barber|hair|salon/i, ['shop~"^(hairdresser|barber|beauty)$"']],
  [/supermarket|grocer|groceries|convenience|سوبر/i, ['shop~"^(supermarket|convenience|greengrocer)$"']],
  [/\bmall\b|shopping cent/i, ['shop="mall"']],
  [/book ?shop|bookstore|books/i, ['shop="books"']],
  [/\bpark\b|garden|walk/i, ['leisure~"^(park|garden)$"']],
  [/hotel|stay|hostel/i, ['tourism~"^(hotel|guest_house|hostel)$"']],
  [/museum|gallery/i, ['tourism~"^(museum|gallery)$"']],
  [/hospital|clinic|doctor|emergency/i, ['amenity~"^(hospital|clinic|doctors)$"']],
  [/dentist/i, ['amenity="dentist"']],
  [/petrol|fuel|gas station/i, ['amenity="fuel"']],
  [/bakery|bread|pastry|dessert|cake/i, ['shop~"^(bakery|pastry|confectionery)$"']],
  [/ice cream|gelato/i, ['amenity="ice_cream"']],
  [/phone|charger|electronic|repair/i, ['shop~"^(mobile_phone|electronics|computer)$"']],
  [/cinema|movie/i, ['amenity="cinema"']],
  [/mosque|church|pray/i, ['amenity="place_of_worship"']],
  [/laundr|dry clean/i, ['shop~"^(laundry|dry_cleaning)$"']],
  [/clothes|clothing|fashion|shoes/i, ['shop~"^(clothes|shoes|boutique)$"']],
  [/things to do|fun|attraction|sight/i, ['tourism~"^(attraction|museum|viewpoint|zoo|theme_park)$"', 'leisure="park"']],
]

const distance = (a: Spot, b: Spot): number => {
  const r = 6_371_000, rad = Math.PI / 180
  const dLat = (b.lat - a.lat) * rad, dLon = (b.lon - a.lon) * rad
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2
  return 2 * r * Math.asin(Math.sqrt(h))
}
const fmtDistance = (m: number): string => (m < 950 ? `${Math.round(m / 10) * 10} m` : `${(m / 1000).toFixed(1)} km`)

async function overpass(filters: string[], c: Spot, radius: number): Promise<any[]> {
  const body = `[out:json][timeout:20];(${filters.map((f) => `nwr[${f}][name](around:${radius},${c.lat},${c.lon});`).join('')});out center tags 60;`
  // The main server is often busy: try its mirrors before giving up.
  let last: unknown = null
  for (const host of ['https://overpass-api.de/api/interpreter', 'https://overpass.private.coffee/api/interpreter', 'https://overpass.kumi.systems/api/interpreter']) {
    try {
      const r = await json(host, { method: 'POST', body: `data=${encodeURIComponent(body)}`, headers: { 'Content-Type': 'application/x-www-form-urlencoded' } })
      return r?.elements ?? []
    } catch (e) { last = e }
  }
  throw last ?? new Error('Overpass unavailable')
}

/** Photon's search near a point, shaped like Overpass results (when Overpass is down). */
async function photonNearby(query: string, c: Spot): Promise<any[]> {
  const r = await json(`https://photon.komoot.io/api/?q=${encodeURIComponent(query)}&lat=${c.lat}&lon=${c.lon}&limit=20`)
  return (r?.features ?? []).map((f: any) => {
    const pr = f.properties ?? {}
    return { lat: f.geometry?.coordinates?.[1], lon: f.geometry?.coordinates?.[0],
      tags: { name: pr.name, [pr.osm_key ?? 'place']: pr.osm_value, 'addr:street': pr.street, 'addr:housenumber': pr.housenumber, 'addr:suburb': pr.district ?? pr.city } }
  })
}

/** What's near the user (or near a place they name), as text for the assistant. */
export async function lookupNearby(query: string, nearText: string, radius: number): Promise<{ text: string; isError?: boolean }> {
  let center: Spot | null = null, where = ''
  const me = await locate()
  if (nearText.trim()) {
    const p = await findPlace(nearText, me)
    if (!p) return { text: `Couldn't find “${nearText}” on the map. Ask for an area or address.`, isError: true }
    center = p; where = `around ${p.name}${p.address ? ` (${p.address})` : ''}`
  } else if (me) {
    center = me; where = me.exact ? 'around the user (phone location)' : `in ${me.label} (their city from Settings, not their exact location: say so, and ask for the area if it matters)`
  } else return { text: "Couldn't tell where the user is. Ask which area they're in, then search near it.", isError: true }

  const r = Math.max(300, Math.min(8000, radius || 1500))
  const tags = TAGS.find(([re]) => re.test(query))?.[1]
  const word = query.trim().replace(/["\\]/g, '')
  let found: any[] = []
  try {
    for (const radiusTry of [r, Math.min(8000, r * 3)]) {
      found = await overpass(tags ?? [`"name"~"${word}",i`, `"shop"="${word.toLowerCase()}"`, `"amenity"="${word.toLowerCase()}"`, `"cuisine"~"${word}",i`], center, radiusTry)
      if (found.length >= 3 || radiusTry === 8000) break
    }
  } catch {
    try {
      found = (await photonNearby(query, center)).filter((e) => !isNaN(e.lat) && distance(center!, e) <= Math.max(r * 3, 5000))
    } catch {
      return { text: 'The map service didn’t answer. Try web_search for the area instead.', isError: true }
    }
  }
  const rows = found.map((e) => {
    const lat = e.lat ?? e.center?.lat, lon = e.lon ?? e.center?.lon
    const t = e.tags ?? {}
    return { name: t.name as string, t, p: { lat, lon }, d: distance(center!, { lat, lon }) }
  }).filter((x) => x.name && !isNaN(x.p.lat)).sort((a, b) => a.d - b.d)
  const seen = new Set<string>()
  const top = rows.filter((x) => !seen.has(x.name.toLowerCase()) && seen.add(x.name.toLowerCase())).slice(0, 12)
  if (!top.length) return { text: `Nothing called or tagged “${query}” within ${fmtDistance(r * 3)} ${where} on OpenStreetMap. Try web_search for it instead.` }
  const lines = top.map(({ name, t, p, d }) => {
    const kind = [t.cuisine?.replace(/;/g, ', '), t.amenity ?? t.shop ?? t.leisure ?? t.tourism].filter(Boolean).join(' · ')
    const addr = [[t['addr:housenumber'], t['addr:street']].filter(Boolean).join(' '), t['addr:suburb'] ?? t['addr:city']].filter(Boolean).join(', ')
    const extra = [addr, t.opening_hours ? `hours: ${t.opening_hours}` : '', t.website ?? t['contact:website'] ?? '', t.phone ?? t['contact:phone'] ?? ''].filter(Boolean).join(' | ')
    return `- ${name}${kind ? ` (${kind})` : ''}: ${fmtDistance(d)} away${extra ? ` | ${extra}` : ''} | map: ${mapsLink(p, name)}`
  })
  return { text: `Places for “${query}” ${where}, nearest first (OpenStreetMap; opening hours as listed there, may be out of date). Now: ${new Date().toLocaleString('en', { weekday: 'short', hour: 'numeric', minute: '2-digit' })}.\n${lines.join('\n')}` }
}

// MARK: Weather

const unit = (): 'fahrenheit' | 'celsius' => (navigator.language === 'en-US' && (tz().startsWith('America/') || tz() === 'Pacific/Honolulu') ? 'fahrenheit' : 'celsius')

/** Hour-by-hour weather for today and tomorrow (WeatherStore.forecastText on the Mac). */
export async function forecastText(cityText: string): Promise<{ text: string; isError?: boolean }> {
  let spot: Spot, place: string
  if (cityText.trim()) {
    const c = await geocodeCity(cityText.trim())
    if (!c) return { text: `Couldn't find ${cityText}.`, isError: true }
    spot = c; place = c.name
  } else {
    const me = await locate()
    if (!me) return { text: "Couldn't tell where they are. Ask which city they're in.", isError: true }
    spot = me; place = me.exact ? `the user's current location` : me.label
  }
  const q = new URLSearchParams({
    latitude: String(spot.lat), longitude: String(spot.lon),
    current: 'temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m',
    hourly: 'temperature_2m,apparent_temperature,precipitation_probability,weather_code,wind_speed_10m,uv_index',
    daily: 'temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max,sunrise,sunset',
    timezone: 'auto', forecast_days: '2', temperature_unit: unit(),
  })
  let w: any
  try { w = await json(`https://api.open-meteo.com/v1/forecast?${q}`) } catch { return { text: "The weather service didn't answer. Try again in a moment.", isError: true } }
  const u = unit() === 'fahrenheit' ? '°F' : '°C'
  const r = Math.round
  const label = (code: number) => describeWeather(code ?? 0, true).label.toLowerCase()
  const lines = [`Weather for ${place}:`]
  const c = w.current
  if (c) lines.push(`Now: ${r(c.temperature_2m)}${u}, feels like ${r(c.apparent_temperature)}${u}, ${label(c.weather_code)}, wind ${r(c.wind_speed_10m)} km/h, humidity ${r(c.relative_humidity_2m)}%`)
  const d = w.daily ?? {}
  ;(d.time ?? []).forEach((day: string, i: number) => {
    lines.push(`${i === 0 ? 'Today' : 'Tomorrow'} (${day}): ${r(d.temperature_2m_min?.[i] ?? 0)}-${r(d.temperature_2m_max?.[i] ?? 0)}${u}, rain chance up to ${r(d.precipitation_probability_max?.[i] ?? 0)}%, UV max ${r(d.uv_index_max?.[i] ?? 0)}${d.sunset?.[i] ? `, sunset ${String(d.sunset[i]).slice(-5)}` : ''}`)
  })
  const h = w.hourly ?? {}
  const now = new Date()
  const nowHour = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}T${String(now.getHours()).padStart(2, '0')}:00`
  lines.push('Every 3 hours from now:')
  ;(h.time ?? []).forEach((time: string, i: number) => {
    if (time < nowHour || i % 3 !== 0) return
    lines.push(`- ${time.replace('T', ' ')}: ${r(h.temperature_2m[i])}${u} (feels ${r(h.apparent_temperature[i])}), ${label(h.weather_code[i])}, rain ${r(h.precipitation_probability[i] ?? 0)}%, wind ${r(h.wind_speed_10m[i])} km/h, UV ${r(h.uv_index[i] ?? 0)}`)
  })
  return { text: lines.join('\n') }
}
