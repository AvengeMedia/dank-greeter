pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Greetd

Singleton {
    id: root

    property int refCount: 0

    property var weather: ({
            "available": false,
            "temp": 0,
            "tempF": 0,
            "wCode": 0,
            "isDay": true
        })

    property var location: null
    property int retryAttempts: 0
    property int maxRetryAttempts: 3
    property int retryDelay: 30000
    property int lastFetchTime: 0
    property int minFetchInterval: 30000
    property int persistentRetryCount: 0

    readonly property var lowPriorityCmd: ["nice", "-n", "19", "ionice", "-c3"]
    readonly property var curlBaseCmd: ["curl", "-sS", "--fail", "--connect-timeout", "3", "--max-time", "6", "--limit-rate", "100k", "--compressed"]

    property var weatherIcons: ({
            "0": "clear_day",
            "1": "clear_day",
            "2": "partly_cloudy_day",
            "3": "cloud",
            "45": "foggy",
            "48": "foggy",
            "51": "rainy",
            "53": "rainy",
            "55": "rainy",
            "56": "rainy",
            "57": "rainy",
            "61": "rainy",
            "63": "rainy",
            "65": "rainy",
            "66": "rainy",
            "67": "rainy",
            "71": "cloudy_snowing",
            "73": "cloudy_snowing",
            "75": "snowing_heavy",
            "77": "cloudy_snowing",
            "80": "rainy",
            "81": "rainy",
            "82": "rainy",
            "85": "cloudy_snowing",
            "86": "snowing_heavy",
            "95": "thunderstorm",
            "96": "thunderstorm",
            "99": "thunderstorm"
        })

    property var nightWeatherIcons: ({
            "0": "clear_night",
            "1": "clear_night",
            "2": "partly_cloudy_night",
            "3": "cloud",
            "45": "foggy",
            "48": "foggy",
            "51": "rainy",
            "53": "rainy",
            "55": "rainy",
            "56": "rainy",
            "57": "rainy",
            "61": "rainy",
            "63": "rainy",
            "65": "rainy",
            "66": "rainy",
            "67": "rainy",
            "71": "cloudy_snowing",
            "73": "cloudy_snowing",
            "75": "snowing_heavy",
            "77": "cloudy_snowing",
            "80": "rainy",
            "81": "rainy",
            "82": "rainy",
            "85": "cloudy_snowing",
            "86": "snowing_heavy",
            "95": "thunderstorm",
            "96": "thunderstorm",
            "99": "thunderstorm"
        })

    function getWeatherIcon(code, isDay) {
        if (typeof isDay === "undefined") {
            isDay = weather.isDay;
        }
        const iconMap = isDay ? weatherIcons : nightWeatherIcons;
        return iconMap[String(code)] || "cloud";
    }

    function setLocation(lat, lon) {
        root.location = {
            latitude: lat,
            longitude: lon
        };
    }

    function getWeatherApiUrlForCoords(lat, lon) {
        if (lat == null || lon == null)
            return null;

        const params = ["latitude=" + lat, "longitude=" + lon, "current=temperature_2m,is_day,weather_code", "timezone=auto"];
        return "https://api.open-meteo.com/v1/forecast?" + params.join('&');
    }

    function addRef() {
        refCount++;

        if (refCount === 1 && !weather.available && GreetdSettings.greeterShowWeather) {
            fetchWeather();
        }
    }

    function removeRef() {
        refCount = Math.max(0, refCount - 1);
    }

    function updateLocation() {
        if (GreetdSettings.useAutoLocation) {
            ipLocationFetcher.running = true;
            return;
        }

        const coords = SessionData.weatherCoordinates;
        const cityName = SessionData.weatherLocation;

        if (coords) {
            const parts = coords.split(",");
            if (parts.length === 2) {
                const lat = parseFloat(parts[0]);
                const lon = parseFloat(parts[1]);
                if (!isNaN(lat) && !isNaN(lon)) {
                    setLocation(lat, lon);
                    fetchWeather(lat, lon);
                    return;
                }
            }
        }

        if (!cityName) {
            root.handleWeatherFailure();
            return;
        }

        const geocodeUrl = "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(cityName) + "&count=1&language=en&format=json";
        cityGeocodeFetcher.command = lowPriorityCmd.concat(curlBaseCmd).concat([geocodeUrl]);
        cityGeocodeFetcher.running = true;
    }

    function fetchWeather(lat, lon) {
        if (root.refCount === 0 || !GreetdSettings.greeterShowWeather) {
            return;
        }

        if (lat == null || lon == null) {
            if (!location) {
                updateLocation();
                return;
            }
            lat = location.latitude;
            lon = location.longitude;
        }

        if (weatherFetcher.running) {
            return;
        }

        const now = Date.now();
        if (now - root.lastFetchTime < root.minFetchInterval) {
            return;
        }

        const apiUrl = getWeatherApiUrlForCoords(lat, lon);
        if (!apiUrl) {
            return;
        }

        root.lastFetchTime = now;
        weatherFetcher.command = lowPriorityCmd.concat(curlBaseCmd).concat([apiUrl]);
        weatherFetcher.running = true;
    }

    function forceRefresh() {
        root.lastFetchTime = 0;
        fetchWeather();
    }

    function handleWeatherSuccess() {
        root.retryAttempts = 0;
        root.persistentRetryCount = 0;
        if (persistentRetryTimer.running) {
            persistentRetryTimer.stop();
        }
    }

    function handleWeatherFailure() {
        root.retryAttempts++;
        if (root.retryAttempts < root.maxRetryAttempts) {
            retryTimer.start();
            return;
        }

        root.retryAttempts = 0;
        const backoffDelay = Math.min(60000 * Math.pow(2, persistentRetryCount), 300000);
        persistentRetryCount++;
        persistentRetryTimer.interval = backoffDelay;
        persistentRetryTimer.start();
    }

    Process {
        id: ipLocationFetcher
        running: false
        command: lowPriorityCmd.concat(curlBaseCmd).concat(["http://ip-api.com/json/"])

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (!raw || raw[0] !== "{") {
                    root.handleWeatherFailure();
                    return;
                }

                try {
                    const data = JSON.parse(raw);

                    if (data.status === "fail") {
                        throw new Error("IP location lookup failed");
                    }

                    const lat = parseFloat(data.lat);
                    const lon = parseFloat(data.lon);

                    if (isNaN(lat) || isNaN(lon)) {
                        throw new Error("Missing or invalid location data");
                    }

                    root.setLocation(lat, lon);
                    root.fetchWeather(lat, lon);
                } catch (e) {
                    root.handleWeatherFailure();
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.handleWeatherFailure();
            }
        }
    }

    Process {
        id: cityGeocodeFetcher
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (!raw || raw[0] !== "{") {
                    root.handleWeatherFailure();
                    return;
                }

                try {
                    const data = JSON.parse(raw);
                    const results = data.results;

                    if (!results || results.length === 0) {
                        throw new Error("No results found");
                    }

                    root.setLocation(results[0].latitude, results[0].longitude);
                    root.fetchWeather();
                } catch (e) {
                    root.handleWeatherFailure();
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.handleWeatherFailure();
            }
        }
    }

    Process {
        id: weatherFetcher
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (!raw || raw[0] !== "{") {
                    root.handleWeatherFailure();
                    return;
                }

                try {
                    const data = JSON.parse(raw);

                    if (!data.current) {
                        throw new Error("Required weather data fields missing");
                    }

                    const current = data.current;
                    const tempC = current.temperature_2m || 0;

                    root.weather = {
                        "available": true,
                        "temp": Math.round(tempC),
                        "tempF": Math.round(tempC * 9 / 5 + 32),
                        "wCode": current.weather_code || 0,
                        "isDay": Boolean(current.is_day)
                    };
                    root.handleWeatherSuccess();
                } catch (e) {
                    root.handleWeatherFailure();
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.handleWeatherFailure();
            }
        }
    }

    Timer {
        id: retryTimer
        interval: root.retryDelay
        running: false
        repeat: false
        onTriggered: {
            root.fetchWeather();
        }
    }

    Timer {
        id: persistentRetryTimer
        interval: 60000
        running: false
        repeat: false
        onTriggered: {
            root.fetchWeather();
        }
    }
}
