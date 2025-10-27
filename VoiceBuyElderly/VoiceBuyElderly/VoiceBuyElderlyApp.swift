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

struct Product: Codable, Identifiable {
    let id: Int
    let name: String
    let price: Double
}

struct OrderItem: Identifiable {
    let id = UUID()
    let product: Product
    var quantity: Int
}


// MARK: - ViewModel
class VoiceViewModel: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
//    var objectWillChange: ObservableObjectPublisher
    
    @Published var recognizedText = ""
    @Published var orderInfo: OrderInfo? = nil
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    @Published var orderItems: [OrderItem] = []
    @Published var products: [Product] = []
    @Published var isRecording = false
    
    override init() {
        super.init()
        speechRecognizer?.delegate = self
        loadProducts()
    }

    
    private func loadProducts() {
        if let url = Bundle.main.url(forResource: "products", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Product].self, from: data) {
            products = decoded
        }
    }
    
    func startListening() {
        recognizedText = ""  // reset before each new recognition
        orderItems = []
        isRecording = true

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session error: \(error.localizedDescription)")
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        let inputNode = audioEngine.inputNode
        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                DispatchQueue.main.async {
                    self.recognizedText = result.bestTranscription.formattedString
                }
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.isRecording = false
                        self.finishRecognition()
                    }
                }
            }

            if let error = error {
                print("Recognition error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.finishRecognition()
                }
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("Audio engine start error: \(error.localizedDescription)")
        }
    }

    func stopListening() {
        print("Stopping recording…")
        audioEngine.stop()
        recognitionRequest?.endAudio()
        // Delay parsing to let recognizer flush results
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.finishRecognition()
        }
    }

    private func finishRecognition() {
        guard !recognizedText.isEmpty else {
            print("⚠️ No text recognized — skipping parse.")
            return
        }
        parseOrder(from: recognizedText)
    }
    
    func parseOrder(from text: String) {
        let lowerText = text.lowercased()
        var items: [OrderItem] = []

        for product in products {
            if lowerText.contains(product.name.lowercased()) {
                let quantity = extractQuantity(from: lowerText, for: product.name)
                items.append(OrderItem(product: product, quantity: quantity))
            }
        }

        orderItems = items
    }

    private func extractQuantity(from text: String, for productName: String) -> Int {
        let tokens = text.split(separator: " ")
        for (i, token) in tokens.enumerated() {
            if token.lowercased() == productName.lowercased() {
                if i > 0, let q = Int(tokens[i - 1]) { return q }
                if i < tokens.count - 1, let q = Int(tokens[i + 1]) { return q }
            }
        }
        return 1
    }

    func totalAmount() -> Double {
        orderItems.reduce(0) { $0 + Double($1.quantity) * $1.product.price }
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
