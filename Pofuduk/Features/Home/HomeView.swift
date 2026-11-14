import SwiftUI
import PofudukCore

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PofudukGradient.background(for: viewModel.appearance.theme, scheme: colorScheme)
                .ignoresSafeArea()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: viewModel.appearance.theme)

            ScrollView {
                VStack(spacing: 20) {
                    HomeHeader(viewModel: viewModel)

                    if let warning = viewModel.activeWarnings.first {
                        OfficialWarningBanner(warning: warning)
                    }

                    hero

                    SubtitleBubble(track: viewModel.track) { viewModel.showTranscript = true }
                        .padding(.top, 4)

                    PlaybackControls(viewModel: viewModel)

                    if !viewModel.upcomingHours.isEmpty, let place = viewModel.snapshot?.place {
                        HourlyTimeline(hours: viewModel.upcomingHours, timeZone: place.timeZone)
                    }
                    if let tomorrow = viewModel.tomorrow {
                        TomorrowCard(day: tomorrow)
                    }
                    if let advice = viewModel.briefing?.advice, !advice.isEmpty {
                        AdviceSection(items: advice)
                    }
                    MGMStatusCard(availability: viewModel.warningAvailability)

                    if viewModel.isDemo {
                        DemoScenarioPicker(selected: viewModel.demoScenario) { scenario in
                            Task { await viewModel.selectScenario(scenario) }
                        }
                    }
                    SourceFooter(snapshot: viewModel.snapshot, isStale: viewModel.isStale)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.refresh() }
        }
        .task { await viewModel.onAppear() }
        .sheet(isPresented: $viewModel.showTranscript) {
            TranscriptSheet(sentences: viewModel.track.sentences)
        }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            if let current = viewModel.snapshot?.current {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(TurkishFormatting.shortTemperature(current.temperature))
                        .font(PofudukFont.heroTemperature)
                        .foregroundStyle(PofudukColor.ink)
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 2) {
                        Label(TurkishFormatting.conditionName(current.condition, isDay: current.isDay).sentenceCased,
                              systemImage: current.condition.symbolName(isDay: current.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(PofudukFont.headline)
                        Text("Hissedilen \(TurkishFormatting.shortTemperature(current.feelsLike))")
                            .font(PofudukFont.caption)
                            .foregroundStyle(PofudukColor.inkSecondary)
                    }
                    .foregroundStyle(PofudukColor.ink)
                }
                .accessibilityElement(children: .combine)
            }
            CharacterView(appearance: viewModel.appearance, size: 230)
                .padding(.top, 8)
                .onTapGesture { viewModel.togglePause() }
                .accessibilityAction(named: "Konuşmayı başlat veya duraklat") { viewModel.togglePause() }
        }
    }
}

#Preview("Demo") {
    HomeView(viewModel: DependencyContainer(speech: PreviewSpeechService()).makeHomeViewModel())
}

#Preview("Dark") {
    HomeView(viewModel: DependencyContainer(speech: PreviewSpeechService()).makeHomeViewModel())
        .preferredColorScheme(.dark)
}
