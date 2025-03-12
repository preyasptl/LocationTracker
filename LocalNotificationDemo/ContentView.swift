//
//  ContentView.swift
//  LocalNotificationDemo
//
//  Created by mymac on 30/01/25.
//

import SwiftUI
import AVFoundation
import MediaPlayer
import UserNotifications
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    @Published var isLocationUpdated :Bool = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestAlwaysAuthorization()
    }
    
    func startUpdatingLocation(completion: @escaping(CLLocation?) -> Void) {
        locationManager.requestLocation()
        if isLocationUpdated {
            completion(currentLocation)
            isLocationUpdated = false
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
        isLocationUpdated = true
//        print("LATITUDE------>", currentLocation?.coordinate.latitude ?? "Unknown Latitude")
//        print("LONGITUDE------>", currentLocation?.coordinate.longitude ?? "Unknown Longitude")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        print("Location fail",error.localizedDescription)
        isLocationUpdated = false
    }
}

class BackgroundAudioPlayer: NSObject, ObservableObject {
    static let shared = BackgroundAudioPlayer()
    private var audioPlayer: AVAudioPlayer?
    @Published var isPlaying = false
    private var shouldAutoRestart = true
    private let locationManager = LocationManager()
    @Published var logArray : [String] = [""]
    
    override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommandCenter()
//        requestNotificationPermission()
//        locationManager.startUpdatingLocation()
        registerForNotifications()
        
    }
    
    func registerForNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleInterruption),
                                               name: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance())
    }

    @objc func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
        }
        if type == .began {
            print("----Interruption began")
        }
        else if type == .ended {
            guard let optionsValue =
                    info[AVAudioSessionInterruptionOptionKey] as? UInt else {
                    return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // Interruption Ended - playback should resume
                print("----Interuption ended")
                self.resumePlayback()
            }
        }
    }

    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Error requesting notification permission: \(error)")
            }
        }
    }
    
    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Audio Playback"
        content.body = "Hello I am playing"
        content.sound = .none
        
        // Create trigger for immediate delivery
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.01, repeats: false)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }
    
    private func callAPI() {
        print("********************-------------------------------************************")
        print("REQUEST LOCATION TIME:---->",self.getCurrentTime())
        logArray.append("Request location time: "+self.getCurrentTime()+"\n")
        locationManager.startUpdatingLocation { currentLocation in
            self.logArray.append("Location completion time: "+self.getCurrentTime()+"\n")
            self.logArray.append("Current Lat: \(String(currentLocation?.coordinate.latitude ?? Double()))\n")
            self.logArray.append("Current Long: \(String(currentLocation?.coordinate.longitude ?? Double()))\n")
            
            print("LOCATION COMPLETION TIME: ",self.getCurrentTime())
            print("CURRENT LAT: ", currentLocation?.coordinate.latitude ?? "Unknown loaction")
            print("CURRENT LONG: ", currentLocation?.coordinate.longitude ?? "Unknown loaction")
            
            let latitude = String(currentLocation?.coordinate.latitude ?? Double())
            let longitude = String(currentLocation?.coordinate.longitude ?? Double())
            
            if let url = URL(string: "https://www.id-hr.it/koala/inserisci_coordinate.php/?ID_Dispositivo=732&Latitudine=" + latitude + "&Longitudine=" + longitude + "&Giorno=Now&Ora=Now") {
                print("Server URL: ",url.absoluteString)
                self.logArray.append("SERVER URL: "+url.absoluteString+"\n")
                var request = URLRequest(url: url,timeoutInterval: Double.infinity)
                    request.httpMethod = "GET"
                print("API call started at: ",self.getCurrentTime())
                    let task = URLSession.shared.dataTask(with: request) { data, response, error in
                      guard let data = data else {
                        print("API RESPONSE: ERROR ",String(describing: error))
                          DispatchQueue.main.async{
                              self.logArray.append("API response: ERROR "+String(describing: error)+"\n")
                              self.logArray.append("-----------------------------")
                          }
                          print("********************-------------------------------************************")
                        return
                      }
                      print("API RESPONSE",String(data: data, encoding: .utf8)!)
                        DispatchQueue.main.async{
                            self.logArray.append("API response"+String(data: data, encoding: .utf8)!+"\n")
                            self.logArray.append("-----------------------------")
                        }
                        print("********************-------------------------------************************")
                    }

                    task.resume()
            }
        }
    }
    
    func getCurrentTime() -> String {
        let time = Date()
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let stringDate = timeFormatter.string(from: time)
        return stringDate
    }
    
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resumePlayback()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pausePlayback()
            return .success
        }
        
        updateNowPlayingInfo()
    }
    
    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = "Your Audio Title"
        nowPlayingInfo[MPMediaItemPropertyArtist] = "Artist Name"
        
        if let image = UIImage(named: "YourArtwork") {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    func startLoop(soundName: String, type: String = "mp3") {
        guard let path = Bundle.main.path(forResource: soundName, ofType: type) else {
            print("Sound file not found")
            return
        }
        
        let url = URL(fileURLWithPath: path)
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.numberOfLoops = 0  // Changed to 0 to allow track completion
            audioPlayer?.play()
            isPlaying = true
            shouldAutoRestart = true
            
            updateNowPlayingInfo()
        } catch {
            print("Error playing sound: \(error.localizedDescription)")
        }
    }
    
    func stopLoop() {
        shouldAutoRestart = false
        audioPlayer?.stop()
        isPlaying = false
    }
    
    private func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
    }
    
    private func resumePlayback() {
        audioPlayer?.play()
        isPlaying = true
    }
}

extension BackgroundAudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            print("Hello I am playing")
            //            sendNotification()
            callAPI()
            if shouldAutoRestart {
                // Restart the playback
                player.currentTime = 0
                player.play()
                isPlaying = true
            } else {
                isPlaying = false
            }
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlaying = false
        print("Audio decode error: \(error?.localizedDescription ?? "unknown error")")
    }
}

struct BackgroundAudioButton: View {
    @StateObject private var audioPlayer = BackgroundAudioPlayer.shared
    let soundName: String
    let soundType: String
    @StateObject private var logs = BackgroundAudioPlayer.shared
    
    var body: some View {
        
        VStack(){
            Button(action: {
                if audioPlayer.isPlaying {
                    audioPlayer.stopLoop()
                } else {
                    audioPlayer.startLoop(soundName: soundName, type: soundType)
                }
            }) {
                HStack {
                    Image(systemName: audioPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                    Text(audioPlayer.isPlaying ? "Stop Tracking" : "Start Tracking")
                }
                .padding()
                .background(audioPlayer.isPlaying ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                .cornerRadius(10)
            }
            
            Spacer()
            
            VStack(alignment: .leading) {
                ScrollViewReader { scrollView in
                    ScrollView(showsIndicators: false) {
                        ForEach(logs.logArray.indices, id: \.self) { index in
                            Text(logs.logArray[index])
                                .font(.system(size: 12))
                                .padding(.horizontal,8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                        //                    ForEach(logs.logArray, id: \.self) { log in
                        //                        Text(log)
                        //                            .font(.system(size: 12))
                        //                            .padding(.horizontal,8)
                        //                            .frame(maxWidth: .infinity, alignment: .leading)
                        //                    }
                    }
                    .onChange(of: logs.logArray.count) { _ in
                        if let lastIndex = logs.logArray.indices.last {
                            withAnimation {
                                scrollView.scrollTo(lastIndex, anchor: .bottom)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity) // Adjust height as needed
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.green)
                    .cornerRadius(10)
                    .padding()
                    Spacer()

                }
                
            }
            Spacer()
            
            
            //            Button(action: {
            //                if audioPlayer.isPlaying {
            //                    audioPlayer.stopLoop()
            //                } else {
            //                    audioPlayer.startLoop(soundName: soundName, type: soundType)
            //                }
            //            }) {
            //                HStack {
            //                    Image(systemName: audioPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
            //                        .font(.system(size: 24))
            //                    Text(audioPlayer.isPlaying ? "Stop Audio" : "Play Audio")
            //                }
            //                .padding()
            //                .background(audioPlayer.isPlaying ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
            //                .cornerRadius(10)
            //            }
        }
    }
}

struct ContentView: View {
    var body: some View {
        BackgroundAudioButton(soundName: "silenceMusic", soundType: "mp3")  /// 10 sec audio
//        BackgroundAudioButton(soundName: "silenceMusic15", soundType: "mp3")   ///15 sec audio
        // BackgroundAudioButton(soundName: "feedback", soundType: "m4a")
    }
}

#Preview {
    ContentView()
}
