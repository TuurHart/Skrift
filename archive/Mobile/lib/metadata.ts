import * as Location from 'expo-location';
import { Pedometer } from 'expo-sensors';
import SunCalc from 'suncalc';
import AsyncStorage from '@react-native-async-storage/async-storage';

const WEATHER_API_KEY_STORAGE = 'openweathermap_api_key';

export type MemoMetadata = {
  capturedAt: string;
  location: {
    latitude: number;
    longitude: number;
    placeName: string | null;
  } | null;
  weather: {
    conditions: string;
    temperature: number;
    temperatureUnit: string;
  } | null;
  pressure: {
    hPa: number;
    trend: 'rising' | 'steady' | 'falling';
  } | null;
  dayPeriod: 'morning' | 'afternoon' | 'evening' | 'night';
  daylight: {
    sunrise: string;
    sunset: string;
    hoursOfLight: number;
  } | null;
  steps: number | null;
  tags: string[];
  photoFilename: string | null;
  imageManifest: { filename: string; offsetSeconds: number }[] | null;
};

function getDayPeriod(hour: number): MemoMetadata['dayPeriod'] {
  if (hour >= 6 && hour < 12) return 'morning';
  if (hour >= 12 && hour < 17) return 'afternoon';
  if (hour >= 17 && hour < 21) return 'evening';
  return 'night';
}

function formatTime(date: Date): string {
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false });
}

async function captureLocation(): Promise<MemoMetadata['location']> {
  try {
    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status !== 'granted') return null;

    const loc = await Location.getCurrentPositionAsync({
      accuracy: Location.Accuracy.Balanced,
    });

    let placeName: string | null = null;
    try {
      const [geo] = await Location.reverseGeocodeAsync({
        latitude: loc.coords.latitude,
        longitude: loc.coords.longitude,
      });
      if (geo) {
        // Prefer neighborhood/street over district (which in Portugal is the full freguesia name)
        const area = geo.name || geo.street || geo.city || geo.subregion || geo.district;
        const city = geo.city && area !== geo.city ? geo.city : null;
        const parts = [area, city].filter(Boolean);
        placeName = parts.join(', ') || null;
      }
    } catch {
      // reverse geocoding can fail silently
    }

    return {
      latitude: loc.coords.latitude,
      longitude: loc.coords.longitude,
      placeName,
    };
  } catch {
    return null;
  }
}

function captureDaylight(
  latitude: number,
  longitude: number,
  date: Date,
): MemoMetadata['daylight'] {
  try {
    const times = SunCalc.getTimes(date, latitude, longitude);
    const sunrise = times.sunrise;
    const sunset = times.sunset;
    const hoursOfLight =
      (sunset.getTime() - sunrise.getTime()) / (1000 * 60 * 60);

    return {
      sunrise: formatTime(sunrise),
      sunset: formatTime(sunset),
      hoursOfLight: Math.round(hoursOfLight * 100) / 100,
    };
  } catch {
    return null;
  }
}

async function captureSteps(): Promise<number | null> {
  try {
    const available = await Pedometer.isAvailableAsync();
    if (!available) return null;

    const now = new Date();
    const startOfDay = new Date(now);
    startOfDay.setHours(0, 0, 0, 0);

    const result = await Pedometer.getStepCountAsync(startOfDay, now);
    return result.steps;
  } catch {
    return null;
  }
}

/**
 * Fetch current weather from OpenWeatherMap.
 * Returns null for both weather and pressure if no API key is configured.
 */
async function captureWeather(
  latitude: number,
  longitude: number,
): Promise<{ weather: MemoMetadata['weather']; pressure: MemoMetadata['pressure'] }> {
  try {
    const apiKey = await AsyncStorage.getItem(WEATHER_API_KEY_STORAGE);
    if (!apiKey) return { weather: null, pressure: null };

    const url = `https://api.openweathermap.org/data/2.5/weather?lat=${latitude}&lon=${longitude}&units=metric&appid=${apiKey}`;
    const res = await fetch(url);
    if (!res.ok) return { weather: null, pressure: null };

    const data = await res.json();

    const weather: MemoMetadata['weather'] = {
      conditions: data.weather?.[0]?.main ?? 'Unknown',
      temperature: Math.round(data.main?.temp ?? 0),
      temperatureUnit: 'C',
    };

    const pressure: MemoMetadata['pressure'] = data.main?.pressure
      ? { hPa: data.main.pressure, trend: 'steady' as const }
      : null;

    return { weather, pressure };
  } catch {
    return { weather: null, pressure: null };
  }
}

/**
 * Capture all available metadata in a single burst.
 * Called when the user stops recording.
 */
export async function captureMetadata(): Promise<MemoMetadata> {
  const now = new Date();

  // Run location and steps in parallel
  const [location, steps] = await Promise.all([
    captureLocation(),
    captureSteps(),
  ]);

  // Daylight and weather need coordinates
  let daylight: MemoMetadata['daylight'] = null;
  let weather: MemoMetadata['weather'] = null;
  let pressure: MemoMetadata['pressure'] = null;

  if (location) {
    daylight = captureDaylight(location.latitude, location.longitude, now);
    const weatherData = await captureWeather(location.latitude, location.longitude);
    weather = weatherData.weather;
    pressure = weatherData.pressure;
  }

  return {
    capturedAt: now.toISOString(),
    location,
    weather,
    pressure,
    dayPeriod: getDayPeriod(now.getHours()),
    daylight,
    steps,
    tags: [],
    photoFilename: null,
    imageManifest: null,
  };
}

/** Helper to get/set the weather API key */
export async function getWeatherApiKey(): Promise<string | null> {
  return AsyncStorage.getItem(WEATHER_API_KEY_STORAGE);
}

export async function setWeatherApiKey(key: string): Promise<void> {
  if (key.trim()) {
    await AsyncStorage.setItem(WEATHER_API_KEY_STORAGE, key.trim());
  } else {
    await AsyncStorage.removeItem(WEATHER_API_KEY_STORAGE);
  }
}
