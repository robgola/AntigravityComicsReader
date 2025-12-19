import SwiftUI

struct DownloadStatusOverlay: View {
    @StateObject private var manager = DownloadManager.shared
    
    var body: some View {
        if manager.isDownloading || !manager.queue.isEmpty {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    // Icon/Progress Ring
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 3)
                            .opacity(0.3)
                            .foregroundColor(.white)
                        
                        Circle()
                            .trim(from: 0.0, to: CGFloat(min(manager.progress, 1.0)))
                            .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .foregroundColor(.yellow)
                            .rotationEffect(Angle(degrees: 270.0))
                            .animation(.linear, value: manager.progress)
                        
                        Image(systemName: "arrow.down")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                    .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if let current = manager.currentDownload {
                            Text("Downloading: \(current.name)")
                                .font(.body) // Increased Size (was caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        } else {
                             Text(manager.queue.isEmpty ? "Done" : "Preparing...")
                                .font(.body) // Increased Size
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        
                        if !manager.queue.isEmpty {
                            Text(manager.isPaused ? "Paused • \(manager.queue.count) remaining" : "\(manager.queue.count) remaining")
                                .font(.subheadline) // Increased Size
                                .foregroundColor(.gray)
                        } else {
                            Text("\(Int(manager.progress * 100))%")
                                .font(.subheadline) // Increased Size
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    // Controls
                    HStack(spacing: 16) {
                        // Pause / Resume
                        Button(action: {
                            if manager.isPaused {
                                manager.resumeDownloads()
                            } else {
                                manager.pauseDownloads()
                            }
                        }) {
                            Image(systemName: manager.isPaused ? "play.fill" : "pause.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                        }
                        
                        // Stop (Finish current, clear queue)
                        Button(action: {
                            manager.stopQueue()
                        }) {
                            Image(systemName: "stop.fill")
                                .font(.title3)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14) // Increased padding
                .background(Color(uiColor: .systemGray6).opacity(0.95))
                .cornerRadius(30)
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                .padding(.horizontal, 20)
                .padding(.bottom, 70) // Increased safe area offset for visibility
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut, value: manager.isDownloading)
        }
    }
}

struct DownloadStatusOverlay_Previews: PreviewProvider {
    static var previews: some View {
        DownloadStatusOverlay()
    }
}
