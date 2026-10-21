// Current weather from Open-Meteo (free, no key), same as the Mac app.
export interface Weather { place: string; temp: number; feels: number; high: number; low: number; code: number; isDay: boolean }

const tzCity = (): string => (Intl.DateTimeFormat().resolvedOptions().timeZone.split('/').pop() ?? 'London').replace(/_/g, ' ')

export async function fetchWeather(city?: string): Promise<Weather> {
  const name = city?.trim() || tzCity()
  const geo = await fetch(`https://geocoding-api.open-meteo.com/v1/search?count=1&name=${encodeURIComponent(name)}`).then((r) => r.json())
  const place = geo?.results?.[0]
  if (!place) throw new Error(`Couldn't find “${name}”. Set your city in Settings.`)
  // Fahrenheit only for US English *and* a US time zone (many people elsewhere run Windows in US English).
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone
  const unit = navigator.language === 'en-US' && (tz.startsWith('America/') || tz === 'Pacific/Honolulu') ? 'fahrenheit' : 'celsius'
  const q = new URLSearchParams({
    latitude: String(place.latitude), longitude: String(place.longitude),
    current: 'temperature_2m,apparent_temperature,weather_code,is_day',
    daily: 'temperature_2m_max,temperature_2m_min', timezone: 'auto', forecast_days: '1', temperature_unit: unit,
  })
  const w = await fetch(`https://api.open-meteo.com/v1/forecast?${q}`).then((r) => r.json())
  return {
    place: place.name, temp: w.current.temperature_2m, feels: w.current.apparent_temperature,
    high: w.daily.temperature_2m_max[0], low: w.daily.temperature_2m_min[0], code: w.current.weather_code, isDay: w.current.is_day === 1,
  }
}

export function describe(code: number, isDay: boolean): { emoji: string; label: string } {
  if (code === 0) return { emoji: isDay ? '☀️' : '🌙', label: 'Clear' }
  if (code <= 2) return { emoji: isDay ? '🌤️' : '☁️', label: 'Partly cloudy' }
  if (code === 3) return { emoji: '☁️', label: 'Cloudy' }
  if (code === 45 || code === 48) return { emoji: '🌫️', label: 'Foggy' }
  if (code >= 51 && code <= 57) return { emoji: '🌦️', label: 'Drizzle' }
  if (code >= 61 && code <= 67) return { emoji: '🌧️', label: 'Rain' }
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return { emoji: '❄️', label: 'Snow' }
  if (code >= 80 && code <= 82) return { emoji: '🌧️', label: 'Showers' }
  if (code >= 95) return { emoji: '⛈️', label: 'Thunderstorm' }
  return { emoji: '☁️', label: '' }
}
