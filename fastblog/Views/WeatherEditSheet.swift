//
//  WeatherEditSheet.swift
//  fastblog
//
//  Lets the user manually override the weather condition and temperatures for a blog day.
//

import SwiftUI

struct WeatherEditSheet: View {
    @Binding var day: RecapBlogDay
    var onDismiss: () -> Void

    @AppStorage(WeatherTemperatureUnit.storageKey) private var weatherUnitRaw: String = WeatherTemperatureUnit.fahrenheit.rawValue

    private var unit: WeatherTemperatureUnit { WeatherTemperatureUnit(rawValue: weatherUnitRaw) ?? .fahrenheit }

    private let conditions: [(code: Int, emoji: String, label: String)] = [
        (0,  "☀️", "Clear sky"),
        (1,  "🌤️", "Mainly clear"),
        (2,  "⛅️", "Partly cloudy"),
        (3,  "☁️", "Overcast"),
        (45, "🌫️", "Foggy"),
        (51, "🌦️", "Drizzle"),
        (61, "🌧️", "Rain"),
        (71, "🌨️", "Light snow"),
        (73, "❄️", "Moderate snow"),
        (75, "🌨️", "Heavy snow"),
        (80, "🌧️", "Rain showers"),
        (85, "🌨️", "Snow showers"),
        (95, "⛈️", "Thunderstorm"),
    ]

    @State private var selectedCode: Int = 1
    @State private var highDisplay: Double = 70
    @State private var lowDisplay: Double = 55

    private var unitSuffix: String { unit == .fahrenheit ? "°F" : "°C" }

    private func fromCelsius(_ c: Double) -> Double {
        unit == .fahrenheit ? (c * 9 / 5 + 32).rounded() : c.rounded()
    }

    private func toCelsius(_ value: Double) -> Double {
        unit == .fahrenheit ? (value - 32) * 5 / 9 : value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Condition") {
                    ForEach(conditions, id: \.code) { condition in
                        Button {
                            selectedCode = condition.code
                        } label: {
                            HStack {
                                Text(condition.emoji)
                                    .font(.title3)
                                Text(condition.label)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedCode == condition.code {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Temperature (\(unitSuffix))") {
                    Stepper("High: \(Int(highDisplay))\(unitSuffix)", value: $highDisplay, in: -60...130, step: 1)
                    Stepper("Low:  \(Int(lowDisplay))\(unitSuffix)", value: $lowDisplay, in: -60...130, step: 1)
                }

                Section {
                    Button("Reset to Auto", role: .destructive) {
                        day.weather = nil
                        day.weatherIsManual = false
                        onDismiss()
                    }
                }
            }
            .navigationTitle(day.shortDateText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        day.weather = DayWeather(
                            weatherCode: selectedCode,
                            tempMaxC: toCelsius(highDisplay),
                            tempMinC: toCelsius(lowDisplay),
                            precipitationMm: day.weather?.precipitationMm ?? 0
                        )
                        day.weatherIsManual = true
                        onDismiss()
                    }
                }
            }
            .onAppear { loadInitialValues() }
        }
    }

    private func loadInitialValues() {
        if let w = day.weather {
            selectedCode = w.weatherCode
            highDisplay = fromCelsius(w.tempMaxC)
            lowDisplay = fromCelsius(w.tempMinC)
        } else {
            selectedCode = 1
            highDisplay = unit == .fahrenheit ? 70 : 21
            lowDisplay  = unit == .fahrenheit ? 55 : 13
        }
    }
}
