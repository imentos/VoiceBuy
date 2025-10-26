import SwiftUI
import AVFoundation
import Speech
internal import Combine

// MARK: - VoiceBuy Elderly App MVP
@main
struct VoiceBuyElderlyApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .listening:
                            ListeningView()
                        case .confirm(let text):
                            ConfirmView(item: text)
                        case .complete:
                            CompleteView()
                        }
                    }
            }
        }
    }
}


// MARK: - Model
struct OrderInfo: Codable {
    var user: String
    var address: String
    var payment: String
    var familyContact: String
}

enum AppRoute: Hashable {
    case listening
    case confirm(String)
    case complete
}

// MARK: - ViewModel
class VoiceViewModel: ObservableObject {
//    var objectWillChange: ObservableObjectPublisher
    
    @Published var recognizedText = ""
    @Published var orderInfo: OrderInfo? = nil
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    
    func startListening() {
        recognizedText = ""
        
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.removeTap(onBus: 0) // avoid duplicate taps
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        
        recognitionTask?.cancel()
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                DispatchQueue.main.async {
                    self.recognizedText = result.bestTranscription.formattedString
                }
            }
            if error != nil {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
    }
    
    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        AVSpeechSynthesizer().speak(utterance)
    }
    
    func loadOrderInfo() {
        // Load from local mock file
        if let url = Bundle.main.url(forResource: "mock_user", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let info = try? JSONDecoder().decode(OrderInfo.self, from: data) {
            orderInfo = info
        }
    }
}

// MARK: - Views
struct HomeView: View {
    var body: some View {
        VStack(spacing: 40) {
            Text("VoiceBuy")
                .font(.largeTitle)
                .bold()
            Text("Your voice shopping assistant")
                .font(.headline)
            
            NavigationLink(value: AppRoute.listening) {
                VStack {
                    Image(systemName: "mic.circle.fill")
                        .resizable()
                        .frame(width: 150, height: 150)
                        .foregroundColor(.blue)
                    Text("Tap to Speak")
                        .font(.title2)
                }
            }
        }
        .padding()
    }
}

struct ListeningView: View {
    @StateObject private var viewModel = VoiceViewModel()
    @State private var navigate = false
    var body: some View {
        VStack(spacing: 30) {
            Text("Listening...")
                .font(.largeTitle)
            Text(viewModel.recognizedText)
                .font(.title2)
                .frame(maxWidth: .infinity, minHeight: 100)
                .border(Color.gray)
                .padding()
            
            NavigationLink(value: AppRoute.confirm(viewModel.recognizedText)) {
                Text("Stop and Confirm")
                    .font(.title2)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
        .onAppear {
            SFSpeechRecognizer.requestAuthorization { status in
                if status == .authorized {
                    viewModel.startListening()
                    viewModel.speak("Please say what you would like to buy.")
                } else {
                    viewModel.speak("Speech recognition not authorized.")
                }
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }
}

struct ConfirmView: View {
    var item: String
    @StateObject private var viewModel = VoiceViewModel()
    
    var body: some View {
        VStack(spacing: 40) {
            Text("You said:")
                .font(.headline)
            Text(item)
                .font(.title)
                .padding()
            
            NavigationLink(value: AppRoute.complete) {
                Text("Yes, order it")
                    .font(.title2)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            
            NavigationLink(value: AppRoute.listening) {
                Text("No, try again")
                    .font(.title2)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
        .onAppear {
            viewModel.loadOrderInfo()
            if let info = viewModel.orderInfo {
                viewModel.speak("You said \(item). Shall I order it to \(info.address)?")
            } else {
                viewModel.speak("You said \(item). Do you want to order it?")
            }
        }
    }
}

struct CompleteView: View {
    @StateObject private var viewModel = VoiceViewModel()
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 120, height: 120)
                .foregroundColor(.green)
            Text("Order placed successfully!")
                .font(.largeTitle)
            NavigationLink(value: AppRoute.listening) {
                Text("Back to Home")
                    .font(.title2)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
        .onAppear {
            viewModel.speak("Your order has been placed successfully.")
        }
    }
}
